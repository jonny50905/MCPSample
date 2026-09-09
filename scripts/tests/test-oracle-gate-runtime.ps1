# test-oracle-gate-runtime.ps1 — Oracle 連線前置閘門的「執行紀錄」回歸（公司機；PowerShell 5.1 可跑）
# 目的：不是看 prompt 文字，而是看每個 session 真正發生的工具順序——
#       「已執行的 DB 委派（task）發生在 connect 成功之前」的次數必須是 0，且正向題目真的有查到 DB。
#       （第 0 步只有 connect 一步：connection_name＝profile 值原樣；list_connections 不是前置——清單把名稱與連線字串黏在一起，不拿來挑名字）
# 資料來源：閘門 plugin 的交易紀錄 auto-loop-logs\ps-oracle-gate\<sessionID>.jsonl（每筆 hook 事件一行），
#           並用 opencode export <sessionID> 的正式 transcript 交叉比對 task 件數、真實題目 id、每個 task 所屬的題目（hook 覆蓋率必須 100%）。
# 用法：
#   跑 N 次新鮮 session（headless，opencode run）：
#     powershell -File scripts\tests\test-oracle-gate-runtime.ps1 -Scenario B1 -Runs 30
#     powershell -File scripts\tests\test-oracle-gate-runtime.ps1 -Scenario B3 -Runs 30 -Question "（純 PeopleCode 流程題）"
#     -QuestionFile <本機檔>：一行一題，輪流使用（真實物件名不進 repo，放本機）
#   只分析既有 session（互動 TUI 同一視窗連問 ≥ 20 題後做 P1 探測）：
#     powershell -File scripts\tests\test-oracle-gate-runtime.ps1 -AnalyzeAll [-Since "2026-09-08 09:00"]
#     powershell -File scripts\tests\test-oracle-gate-runtime.ps1 -AnalyzeSession ses_xxx
# 判定（exit 1 ＝ 有違反；全部無豁免）——分「安全」與「可用」兩條：
#   安全（每個情境都判）：
#   executedTaskBeforePreflight（會查 DB 的 task 入場時狀態 ≠ READY 卻執行了）＝ 0
#     ——「會查 DB」看列上的 dbCapable 欄位（plugin 機械判定；不認識的 agent 也是 true），不看 basis 說明字串；舊紀錄沒有欄位時由 basis 推導
#   hookMismatch（閘門看到的 task 次數 ≠ transcript 的 task 件數）＝ 0（task hook 覆蓋率 100%）
#   turnMismatch（transcript 裡的真實 user 訊息——有非 synthetic 的 text／file／agent／subtask part——找不到同 id 的 chat.message）＝ 0
#     ——compaction／續行／背景回灌那種系統插入的 user 訊息不算題；/undo 刪掉的訊息不算漏（另計 orphanTurns 觀察值）
#   turnInvariantViolations（已執行的 DB task 在「同一 turn 內」找不到先於它的 connect 成功→READY；list_connections 不看）＝ 0
#   callMismatch（同一 callID 的 before／after 列 turnId 不一致，或 transcript 裡該 task 所屬的 user 訊息 id ≠ before 列的 turnId）＝ 0
#     ——證明每次呼叫的歸屬沒有被改標到別的題目，不只比件數
#   另：export 失敗（exportFailures）與 run 結束碼非 0／逾時（runsWithBadExit）也判 FAIL——否則覆蓋率判定是空的
#   可用（依情境；-ExpectDbTask 覆寫）：
#   Yes（B1 預設）＝每個 session 至少 1 個「完成」的 DB task：子 agent 報告 status=COMPLETE，且其子 session 的交易紀錄裡至少一個
#     oracleMCP_run_sql 成功（after 列 ok=true）——只有報告宣稱成功不算、「沒回 NOT_CONNECTED」不算；BLOCKED（任何 blockedReason）、
#     INVALID（非契約 JSON／task_error）都不算完成，PARTIAL 另計。零違規但零完成不算過。B1 的題目要用預期能 COMPLETE 的固定題
#   No（B3 預設）＝0 個會查 DB 的 task 執行；Any（B2／CUSTOM／-AnalyzeAll 預設）＝不判、只列數字
# 附帶統計（不判定，供觀察）：blockedRuns＝模型先派 task 被擋的 session 數（＝錯序機率）；preflightRuns＝有 connect 成功（READY）的
#   session 數（R8：不需要 DB 的題也應為 100%）；listCalls＝list_connections 呼叫數（第 0 步不 list；只在 connect 失敗後附清單原文給管理者，正常為 0）；mcpDownBlocks＝oracleMCP 未掛載時被擋的 task（閘門不放行）；staleReplies＝上一題晚到的
#   回覆（標 stale、不計入該題）；unknownResults＝list／connect 回空輸出（閘門不當成功——真 SQLcl 若如此回覆要回報維護 session）；
#   orphanTurns＝chat.message 有、transcript 沒有的題（/undo）；unmatchedCalls＝閘門有 before、transcript 找不到同 callID 的 task；
#   tasksNotReturned＝放行了但沒有 after 的 task（一直執行中／被中止）；connectBlocks＝connect 在執行前被擋（profile 未填或目標不一致）；
#   dbTasksPartial／dbTasksBlocked／dbTasksInvalid／dbTasksCompletedNoSql（報告 COMPLETE 但子 session 沒有成功的 run_sql）。
# 注意：prompt 走 cmd.exe 命令列——題目禁用半形雙引號與 > < & | % ^（中文引號「」不受限）。
param(
    [ValidateSet('B1', 'B2', 'B3', 'CUSTOM')][string]$Scenario = 'B1',
    [int]$Runs = 30,
    [string]$Agent = 'ps-orchestrator',
    [string]$Model = '',
    [string]$Question = '',
    [string]$QuestionFile = '',
    [int]$TimeoutMin = 15,
    [switch]$AnalyzeAll,
    [string]$AnalyzeSession = '',
    [string]$Since = '',
    [ValidateSet('Auto', 'Yes', 'No', 'Any')][string]$ExpectDbTask = 'Auto',
    [switch]$KeepGoing
)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$gateDir = Join-Path $root (Join-Path 'auto-loop-logs' 'ps-oracle-gate')
$runDir = Join-Path $gateDir 'runs'
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

# 預設題目：只用 README 的公開範例領域（兵役），真實客製物件名請用 -Question／-QuestionFile 從本機帶入
$defaultQuestions = @{
    'B1' = '兵役狀態欄位在畫面上有哪些選項？請列出畫面文字與儲存值'
    'B2' = '兵役資料在哪個畫面維護？（請改用一題 wiki 已驗證的問題）'
    'B3' = '兵役資料存檔時 SavePreChange 事件做了什麼檢查？只看 PeopleCode，不必查 DB'
}

function Get-OpencodeCmd {
    $all = @(Get-Command opencode -All -ErrorAction SilentlyContinue)
    if ($all.Count -eq 0) { throw 'PATH 找不到 opencode' }
    $pick = $all | Where-Object { $_.Source -match '\.(cmd|exe|bat)$' } | Select-Object -First 1
    if ($null -eq $pick) { throw ('PATH 上的 opencode 不是 .cmd/.exe/.bat 型 shim：' + $all[0].Source) }
    return $pick.Source
}

function Read-Jsonl([string]$Path) {
    $rows = @()
    if (-not (Test-Path -LiteralPath $Path)) { return $rows }
    foreach ($ln in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
        if ($ln.Trim() -eq '') { continue }
        try { $rows += (ConvertFrom-Json $ln) } catch { }
    }
    return $rows
}

# 從 opencode export 的物件取：task 工具件數、真實題目（user 訊息）id 清單、每個 task 呼叫（callID）所屬的題目 id
# 真實題目＝role=user 且至少有一個非 synthetic 的 text／file／agent／subtask part；
# compaction（只有 compaction part）、續行／背景回灌（全部 synthetic）都是系統插的，plugin 不重置、這裡也不算題
# task 所屬題目＝含該 tool part 的 assistant 訊息的 parentID（OpenCode 把觸發它的 user 訊息 id 記在 assistant 訊息上）
function Get-ExportCounts($Obj, [string]$SessionId) {
    $n = 0
    $ids = @()
    $parents = @{}
    $msgs = @()
    if ($null -ne $Obj.messages) { $msgs = @($Obj.messages) }
    foreach ($m in $msgs) {
        $info = $m.info
        if ($null -eq $info) { $info = $m }
        $msid = $info.sessionID
        $parts = @()
        if ($null -ne $m.parts) { $parts = @($m.parts) }
        if ($info.role -eq 'user' -and ($null -eq $msid -or $msid -eq $SessionId)) {
            $real = $false
            foreach ($pp in $parts) {
                if (($pp.synthetic -ne $true) -and (@('text', 'file', 'agent', 'subtask') -contains [string]$pp.type)) { $real = $true }
            }
            if ($real) { $ids += [string]$info.id }
        }
        foreach ($p in $parts) {
            if ($p.type -eq 'tool' -and $p.tool -eq 'task') {
                $sid = $p.sessionID
                if ($null -eq $sid -or $sid -eq $SessionId) {
                    $n++
                    if ($p.callID -and $info.parentID) { $parents[[string]$p.callID] = [string]$info.parentID }
                }
            }
        }
    }
    return @{ tasks = $n; promptIds = $ids; taskParents = $parents }
}

# 一個 session 的判讀：回傳 pscustomobject（PS 5.1 的 Measure-Object／Select-Object 對 hashtable 不吃鍵）
# -ExportPath：測試用，直接讀 export JSON 檔而不呼叫 opencode
function Get-SessionVerdict([string]$SessionId, [string]$OcPath, [string]$ExportPath = '') {
    $rows = @(Read-Jsonl (Join-Path $gateDir ($SessionId + '.jsonl')))
    # 會查 DB：plugin 的機械欄位 dbCapable；舊紀錄沒有欄位時由 basis 推導——只有明確的 run_sql:disabled 才算不會查（不認識的 agent＝會查）
    function Test-DbCapable($row) {
        $p = $row.PSObject.Properties['dbCapable']
        if ($null -ne $p -and $null -ne $p.Value) { return [bool]$p.Value }
        if ([string]$row.basis -eq 'run_sql:disabled') { return $false }
        return $true
    }
    function Get-TurnKey($row) { if ($row.turnId) { return [string]$row.turnId } return ([string]$row.pid + '-' + [string]$row.turn) }
    $before = @($rows | Where-Object { $_.hook -eq 'before' -and $_.tool -eq 'task' })
    $blocked = @($before | Where-Object { $_.decision -eq 'block' })
    $mcpDown = @($blocked | Where-Object { [string]$_.note -match '^oracleMCP not mounted' })
    $wouldBlock = @($before | Where-Object { $_.decision -eq 'observe-would-block' })
    $executed = @($rows | Where-Object { $_.hook -eq 'after' -and $_.tool -eq 'task' -and $_.executed -eq $true })
    $executedDb = @($executed | Where-Object { Test-DbCapable $_ })
    # 會查 DB 的 task 入場時狀態 ≠ READY 卻執行了＝違反（無豁免：observe 模式照算）
    $early = @($executedDb | Where-Object { $_.state -ne 'READY' })
    # 可用：子 agent 報告 status=COMPLETE，且其子 session 的交易紀錄裡至少一個 run_sql 成功（ok=true）——「沒回 NOT_CONNECTED」不算成功；
    # 舊紀錄沒有 reportStatus 欄位 → 不算完成（INVALID）
    function Get-ChildSqlOk([string]$Child) {
        if ($Child -eq '') { return 0 }
        $rows2 = @(Read-Jsonl (Join-Path $gateDir ($Child + '.jsonl')))
        return @($rows2 | Where-Object { $_.hook -eq 'after' -and $_.tool -eq 'oracleMCP_run_sql' -and $_.ok -eq $true }).Count
    }
    $dbOk = @(); $dbPartial = @(); $dbBlocked = @(); $dbInvalid = @(); $dbNoSql = @()
    foreach ($e in $executedDb) {
        $st = [string]$e.reportStatus
        if ($st -eq '') { $st = $(if ($e.notConnected -eq $true) { 'BLOCKED' } else { 'INVALID' }) }
        if ($st -eq 'COMPLETE') {
            if ((Get-ChildSqlOk ([string]$e.childSessionID)) -gt 0) { $dbOk += $e } else { $dbNoSql += $e }
        }
        elseif ($st -eq 'PARTIAL') { $dbPartial += $e }
        elseif ($st -eq 'BLOCKED') { $dbBlocked += $e }
        else { $dbInvalid += $e }
    }
    # 放行了卻沒有 after 的 task（一直執行中／被中止）；connect 在執行前被擋（profile 未填或目標不一致）
    $afterIds = @{}
    foreach ($e in $executed) { if ($e.callID) { $afterIds[[string]$e.callID] = $true } }
    $notReturned = @($before | Where-Object { $_.decision -ne 'block' -and $_.callID -and -not $afterIds.ContainsKey([string]$_.callID) }).Count
    $connectBlocks = @($rows | Where-Object { $_.hook -eq 'before' -and $_.tool -eq 'oracleMCP_connect' -and $_.decision -eq 'block' }).Count
    $afters = @($rows | Where-Object { $_.hook -eq 'after' })
    $listCalls = @($afters | Where-Object { $_.tool -eq 'oracleMCP_list_connections' }).Count
    $connOk = @($afters | Where-Object { $_.tool -eq 'oracleMCP_connect' -and $_.next -eq 'READY' })
    $preflight = ($connOk.Count -gt 0)
    $stale = @($rows | Where-Object { $_.stale -eq $true }).Count
    $unknownRes = @($afters | Where-Object { ($_.tool -eq 'oracleMCP_list_connections' -or $_.tool -eq 'oracleMCP_connect') -and [string]$_.ok -eq 'unknown' }).Count
    # per-turn 不變量：每個已執行的 DB task，同一 turn 內、在它之前必須有 connect→READY（list_connections 不是前置、不看）
    # turn 識別＝turnId（該則 user 訊息 id；opencode run --session 續接是新行程，數字 turn 會歸零）；task 列的 turnId 是入場快照
    $turnViol = 0
    # 真實 user 訊息才算一題：全部 part 都 synthetic 的（背景 subagent 回灌／compaction 續行）與同 id 重複到達的列 plugin 不重置、這裡也不計
    $chatRows = @($rows | Where-Object { $_.hook -eq 'chat.message' -and -not ([string]$_.note -match 'no reset') })
    for ($k = 0; $k -lt $rows.Count; $k++) {
        $r = $rows[$k]
        if (-not ($r.hook -eq 'after' -and $r.tool -eq 'task' -and $r.executed -eq $true -and (Test-DbCapable $r))) { continue }
        $t = Get-TurnKey $r
        $connIdx = -1
        for ($j = 0; $j -lt $k; $j++) {
            $q = $rows[$j]
            if ($q.hook -ne 'after') { continue }
            if ((Get-TurnKey $q) -ne $t) { continue }
            if ($q.tool -eq 'oracleMCP_connect' -and $q.next -eq 'READY') { $connIdx = $j }
        }
        if ($connIdx -lt 0) { $turnViol++ }
    }
    # 呼叫歸屬：同一 callID 的 before／after 列 turnId 必須一致（after 用入場快照，改標到新題就是 bug）
    $callMis = 0
    $beforeById = @{}
    foreach ($b in $before) { if ($b.callID) { $beforeById[[string]$b.callID] = $b } }
    foreach ($e in $executed) {
        if ($e.callID -and $beforeById.ContainsKey([string]$e.callID)) {
            if ((Get-TurnKey $beforeById[[string]$e.callID]) -ne (Get-TurnKey $e)) { $callMis++ }
        }
    }
    # transcript 交叉比對：task 工具件數；真實題目 id ↔ chat.message turnId 逐一配對；每個 task 所屬題目 ↔ before 列 turnId
    $exportedTasks = -1
    $exportedTurns = -1
    $missingTurns = 0
    $orphanTurns = 0
    $unmatched = 0
    $exportErr = ''
    $obj = $null
    try {
        if ($ExportPath -ne '') { $obj = ConvertFrom-Json ([System.IO.File]::ReadAllText($ExportPath, [System.Text.Encoding]::UTF8)) }
        elseif ($OcPath -ne '') {
            # export 先落檔再以 UTF-8 讀：PS 5.1 的主控台解碼（zh-TW 是 CP950）會把 JSON 裡的中文與跳脫弄壞
            $exportFile = Join-Path $runDir ($SessionId + '.export.json')
            $inner = '"' + $OcPath + '" export ' + $SessionId + ' 1> "' + $exportFile + '" 2>nul'
            $null = & cmd.exe /d /s /c $inner
            if (-not (Test-Path -LiteralPath $exportFile)) { throw 'export 沒有產生檔案' }
            $json = [System.IO.File]::ReadAllText($exportFile, [System.Text.Encoding]::UTF8)
            if ($json.Trim() -eq '') { throw 'export 檔為空（session 找不到或 opencode 失敗）' }
            $obj = ConvertFrom-Json $json
        }
    }
    catch { $exportErr = $_.Exception.Message }
    if ($null -ne $obj) {
        $ec = Get-ExportCounts $obj $SessionId
        $exportedTasks = [int]$ec.tasks
        $promptIds = @($ec.promptIds)
        $exportedTurns = $promptIds.Count
        $chatIds = @($chatRows | ForEach-Object { [string]$_.turnId })
        foreach ($pid0 in $promptIds) { if ($chatIds -notcontains $pid0) { $missingTurns++ } }
        foreach ($cid in $chatIds) { if ($promptIds -notcontains $cid) { $orphanTurns++ } }
        $parents = $ec.taskParents
        foreach ($cid in @($beforeById.Keys)) {
            if ($parents.ContainsKey($cid)) {
                if ([string]$parents[$cid] -ne (Get-TurnKey $beforeById[$cid])) { $callMis++ }
            }
            else { $unmatched++ }
        }
    }
    $mismatch = 0
    if ($exportedTasks -ge 0 -and $exportedTasks -ne $before.Count) { $mismatch = 1 }
    $modeVal = ''
    $modeRow = @($rows | Where-Object { $_.mode } | Select-Object -First 1)
    if ($modeRow.Count -gt 0) { $modeVal = [string]$modeRow[0].mode }
    return [pscustomobject]@{
        sessionID = $SessionId; rows = $rows.Count; taskAttempts = $before.Count; blocked = $blocked.Count; mcpDownBlocks = $mcpDown.Count
        wouldBlock = $wouldBlock.Count; executed = $executed.Count; executedDb = $executedDb.Count; dbTasksCompleted = $dbOk.Count
        dbTasksPartial = $dbPartial.Count; dbTasksBlocked = $dbBlocked.Count; dbTasksInvalid = $dbInvalid.Count; dbTasksCompletedNoSql = $dbNoSql.Count
        tasksNotReturned = $notReturned; connectBlocks = $connectBlocks; listCalls = $listCalls
        executedBeforePreflight = $early.Count
        preflight = $preflight; exportedTasks = $exportedTasks; hookMismatch = $mismatch; exportError = $exportErr
        turns = $chatRows.Count; exportedTurns = $exportedTurns; turnMismatch = $missingTurns; orphanTurns = $orphanTurns
        turnInvariantViolations = $turnViol; callMismatch = $callMis; unmatchedCalls = $unmatched
        staleReplies = $stale; unknownResults = $unknownRes
        exportFailures = $(if ($exportErr -ne '') { 1 } else { 0 }); exitCode = -1; timedOut = $false
        mode = $modeVal
    }
}

function New-EmptyVerdict([string]$Label, [string]$Err) {
    return [pscustomobject]@{
        sessionID = $Label; rows = 0; taskAttempts = 0; blocked = 0; mcpDownBlocks = 0; wouldBlock = 0; executed = 0; executedDb = 0; dbTasksCompleted = 0
        dbTasksPartial = 0; dbTasksBlocked = 0; dbTasksInvalid = 0; dbTasksCompletedNoSql = 0; tasksNotReturned = 0; connectBlocks = 0; listCalls = 0
        executedBeforePreflight = 0; preflight = $false; exportedTasks = -1; hookMismatch = 0; exportError = $Err; turns = 0; exportedTurns = -1
        turnMismatch = 0; orphanTurns = 0; turnInvariantViolations = 0; callMismatch = 0; unmatchedCalls = 0; staleReplies = 0; unknownResults = 0
        exportFailures = 0; exitCode = -1; timedOut = $false; mode = ''
    }
}

function Show-Table($verdicts) {
    Write-Host ''
    $fmt = '{0,-32} {1,4} {2,4} {3,4} {4,5} {5,6} {6,5} {7,4} {8,5} {9,6} {10,8} {11,7} {12,5}'
    Write-Host ($fmt -f 'sessionID', 'try', 'blk', 'exec', 'early', 'prefl', 'xTask', 'mism', 'turns', 'xTurns', 'turnViol', 'callMis', 'dbOk')
    foreach ($v in $verdicts) {
        Write-Host ($fmt -f $v.sessionID, $v.taskAttempts, $v.blocked, $v.executed, $v.executedBeforePreflight, $v.preflight, $v.exportedTasks, $v.hookMismatch, $v.turns, $v.exportedTurns, $v.turnInvariantViolations, $v.callMismatch, $v.dbTasksCompleted)
    }
}

# $Expect：Yes＝每 session 至少一個會查 DB 的 task 完成；No＝不得有會查 DB 的 task 執行；Any＝不判
function Write-Summary($verdicts, [string]$Label, [string]$Expect) {
    $early = ($verdicts | Measure-Object -Property executedBeforePreflight -Sum).Sum
    $mism = ($verdicts | Measure-Object -Property hookMismatch -Sum).Sum
    $tmism = ($verdicts | Measure-Object -Property turnMismatch -Sum).Sum
    $tviol = ($verdicts | Measure-Object -Property turnInvariantViolations -Sum).Sum
    $cmis = ($verdicts | Measure-Object -Property callMismatch -Sum).Sum
    $orphan = ($verdicts | Measure-Object -Property orphanTurns -Sum).Sum
    $unmatched = ($verdicts | Measure-Object -Property unmatchedCalls -Sum).Sum
    $xfail = ($verdicts | Measure-Object -Property exportFailures -Sum).Sum
    $down = ($verdicts | Measure-Object -Property mcpDownBlocks -Sum).Sum
    $stale = ($verdicts | Measure-Object -Property staleReplies -Sum).Sum
    $unknown = ($verdicts | Measure-Object -Property unknownResults -Sum).Sum
    $exitBad = @($verdicts | Where-Object { $_.exitCode -gt 0 -or $_.timedOut }).Count
    $blockedRuns = @($verdicts | Where-Object { $_.blocked -gt 0 -or $_.wouldBlock -gt 0 }).Count
    $preflightRuns = @($verdicts | Where-Object { $_.preflight }).Count
    $noTask = @($verdicts | Where-Object { $_.taskAttempts -eq 0 }).Count
    $dbOkRuns = @($verdicts | Where-Object { $_.dbTasksCompleted -gt 0 }).Count
    $dbRuns = @($verdicts | Where-Object { $_.executedDb -gt 0 }).Count
    $dbDone = ($verdicts | Measure-Object -Property dbTasksCompleted -Sum).Sum
    $dbPart = ($verdicts | Measure-Object -Property dbTasksPartial -Sum).Sum
    $dbBlk = ($verdicts | Measure-Object -Property dbTasksBlocked -Sum).Sum
    $dbInv = ($verdicts | Measure-Object -Property dbTasksInvalid -Sum).Sum
    $dbNoSql = ($verdicts | Measure-Object -Property dbTasksCompletedNoSql -Sum).Sum
    $notRet = ($verdicts | Measure-Object -Property tasksNotReturned -Sum).Sum
    $cblk = ($verdicts | Measure-Object -Property connectBlocks -Sum).Sum
    $lcalls = ($verdicts | Measure-Object -Property listCalls -Sum).Sum
    $usabilityFail = 0
    if ($Expect -eq 'Yes') { $usabilityFail = @($verdicts | Where-Object { $_.dbTasksCompleted -eq 0 }).Count }
    if ($Expect -eq 'No') { $usabilityFail = $dbRuns }
    $summary = [pscustomobject]@{
        label = $Label; sessions = $verdicts.Count; expectDbTask = $Expect
        executedTaskBeforePreflight = [int]$early; hookMismatch = [int]$mism; turnMismatch = [int]$tmism
        turnInvariantViolations = [int]$tviol; callMismatch = [int]$cmis
        exportFailures = [int]$xfail; runsWithBadExit = $exitBad; usabilityFailures = $usabilityFail
        blockedRuns = $blockedRuns; preflightRuns = $preflightRuns; sessionsWithoutTask = $noTask
        sessionsWithDbTaskOk = $dbOkRuns; sessionsWithDbTask = $dbRuns
        dbTasksCompleted = [int]$dbDone; dbTasksPartial = [int]$dbPart; dbTasksBlocked = [int]$dbBlk; dbTasksInvalid = [int]$dbInv
        dbTasksCompletedNoSql = [int]$dbNoSql; tasksNotReturned = [int]$notRet; connectBlocks = [int]$cblk; listCalls = [int]$lcalls
        mcpDownBlocks = [int]$down; staleReplies = [int]$stale; unknownResults = [int]$unknown; orphanTurns = [int]$orphan; unmatchedCalls = [int]$unmatched
        stamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }
    $out = Join-Path $gateDir ('summary-' + $Label + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    [System.IO.File]::WriteAllText($out, (ConvertTo-Json $summary -Depth 3), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ''
    Write-Host ('安全：sessions=' + $verdicts.Count + '  executedTaskBeforePreflight=' + [int]$early + '  hookMismatch=' + [int]$mism +
        '  turnMismatch=' + [int]$tmism + '  turnInvariantViolations=' + [int]$tviol + '  callMismatch=' + [int]$cmis)
    Write-Host ('可用（ExpectDbTask=' + $Expect + '）：sessionsWithDbTaskOk=' + $dbOkRuns + '/' + $verdicts.Count + '  sessionsWithDbTask=' + $dbRuns + '  usabilityFailures=' + $usabilityFail +
        '  dbTasks completed=' + [int]$dbDone + ' partial=' + [int]$dbPart + ' blocked=' + [int]$dbBlk + ' invalid=' + [int]$dbInv + ' completedNoSql=' + [int]$dbNoSql +
        '  tasksNotReturned=' + [int]$notRet + '  connectBlocks=' + [int]$cblk)
    if ([int]$dbNoSql -gt 0) { Write-Host ('注意：' + [int]$dbNoSql + ' 個 DB task 報告 COMPLETE 但子 session 沒有成功的 run_sql——只是宣稱成功，不計為完成') -ForegroundColor Yellow }
    if ([int]$cblk -gt 0) { Write-Host ('注意：' + [int]$cblk + ' 次 connect 在執行前被擋（profile oracle.connectionName 未填或與 connect 目標不一致）——看 jsonl 的 note') -ForegroundColor Yellow }
    Write-Host ('觀察：blockedRuns=' + $blockedRuns + '（模型先派 task 被擋）  preflightRuns=' + $preflightRuns + '  sessionsWithoutTask=' + $noTask +
        '  listCalls=' + [int]$lcalls + '（第 0 步不 list，正常為 0）  mcpDownBlocks=' + [int]$down + '  staleReplies=' + [int]$stale + '  unknownResults=' + [int]$unknown + '  orphanTurns=' + [int]$orphan + '  unmatchedCalls=' + [int]$unmatched)
    Write-Host ('摘要已寫：' + $out)
    if ([int]$down -gt 0) { Write-Host ('注意：有 ' + [int]$down + ' 個 task 因 oracleMCP 未掛載被擋——回歸請在 oracleMCP 掛載時跑') -ForegroundColor Yellow }
    if ([int]$unknown -gt 0) { Write-Host ('注意：有 ' + [int]$unknown + ' 次 list_connections／connect 回空輸出（閘門不當成功）——真 SQLcl 若如此回覆，把 jsonl 那列回報維護 session') -ForegroundColor Yellow }
    if ([int]$xfail -gt 0) { Write-Host ('注意：' + [int]$xfail + ' 個 session 的 opencode export 失敗（看各列 exportError）——覆蓋率判定對這些 session 是空的') -ForegroundColor Yellow }
    if ($exitBad -gt 0) { Write-Host ('注意：' + $exitBad + ' 次 run 結束碼非 0 或逾時強殺（看 runs\*.err.txt）') -ForegroundColor Yellow }
    $safeFail = ([int]$early -gt 0 -or [int]$mism -gt 0 -or [int]$tmism -gt 0 -or [int]$tviol -gt 0 -or [int]$cmis -gt 0 -or [int]$xfail -gt 0 -or $exitBad -gt 0)
    if ($safeFail) {
        Write-Host '判定：FAIL（安全：DB 委派先於前置執行／task hook 覆蓋率不足／有題沒收到重置／同題內找不到 connect→READY／呼叫歸屬被改標／export 失敗／run 異常結束）' -ForegroundColor Red
        return 1
    }
    if ($usabilityFail -gt 0) {
        if ($Expect -eq 'Yes') { Write-Host ('判定：FAIL（可用：' + $usabilityFail + ' 個 session 沒有任何「報告 COMPLETE 且子 session run_sql 成功」的 DB task——零違規不等於可用）') -ForegroundColor Red }
        else { Write-Host ('判定：FAIL（可用：' + $usabilityFail + ' 個 session 派了會查 DB 的 task，但本情境預期不查 DB）') -ForegroundColor Red }
        return 1
    }
    Write-Host '判定：PASS（安全四項＋呼叫歸屬全 0；task／turn hook 覆蓋率 100%' + $(if ($Expect -eq 'Yes') { '；每個 session 都有會查 DB 的 task 完成' } elseif ($Expect -eq 'No') { '；沒有會查 DB 的 task 執行' } else { '' }) + '）' -ForegroundColor Green
    return 0
}

$ocPath = Get-OpencodeCmd
$expect = $ExpectDbTask
if ($expect -eq 'Auto') {
    if ($AnalyzeAll -or $AnalyzeSession -ne '') { $expect = 'Any' }
    elseif ($Scenario -eq 'B1') { $expect = 'Yes' }
    elseif ($Scenario -eq 'B3') { $expect = 'No' }
    else { $expect = 'Any' }
}

# ── 模式一：只分析既有 session ─────────────────────────────
if ($AnalyzeAll -or $AnalyzeSession -ne '') {
    $ids = @()
    if ($AnalyzeSession -ne '') { $ids = @($AnalyzeSession) }
    else {
        $files = @(Get-ChildItem -LiteralPath $gateDir -Filter 'ses_*.jsonl' -File -ErrorAction SilentlyContinue)
        if ($Since -ne '') { $t = [datetime]::Parse($Since); $files = @($files | Where-Object { $_.LastWriteTime -ge $t }) }
        $ids = @($files | ForEach-Object { $_.BaseName })
    }
    if ($ids.Count -eq 0) { Write-Host '沒有可分析的 session 紀錄（閘門 plugin 有載入嗎？看 _plugin.log）'; exit 2 }
    $verdicts = @()
    foreach ($id in $ids) {
        # 先用 jsonl 判斷是不是 subagent 的子 session（agent 名＋沒有 task 事件）——跳過就不必跑 opencode export（每個都跑很慢）
        $pre = @(Read-Jsonl (Join-Path $gateDir ($id + '.jsonl')))
        $agentRow = @($pre | Where-Object { $_.hook -eq 'chat.message' } | Select-Object -First 1)
        $hasTask = (@($pre | Where-Object { $_.tool -eq 'task' }).Count -gt 0)
        if (-not $hasTask -and $agentRow.Count -gt 0 -and $agentRow[0].agent -match '^ps-(ui|metadata|ae)-flow$|^ps-auditor$|^ps-(peoplecode|sql|sqr)-flow$|^(explore|general|scout)$') { continue }
        $verdicts += (Get-SessionVerdict $id $ocPath)
    }
    Show-Table $verdicts
    exit (Write-Summary $verdicts ('analyze-' + $Scenario) $expect)
}

# ── 模式二：跑 N 次新鮮 headless session ───────────────────
$questions = @()
if ($QuestionFile -ne '') {
    $questions = @([System.IO.File]::ReadAllLines($QuestionFile, [System.Text.Encoding]::UTF8) | Where-Object { $_.Trim() -ne '' -and -not $_.Trim().StartsWith('#') })
}
elseif ($Question -ne '') { $questions = @($Question) }
elseif ($defaultQuestions.ContainsKey($Scenario)) { $questions = @($defaultQuestions[$Scenario]) }
else { throw 'CUSTOM 情境需要 -Question 或 -QuestionFile' }
foreach ($q in $questions) {
    if ($q -match '["<>&|%^]') { throw ('題目含 cmd 特殊字元（半形雙引號 < > & | % ^）：' + $q) }
}

Write-Host ('opencode：' + $ocPath + '  agent=' + $Agent + '  scenario=' + $Scenario + '  runs=' + $Runs + '  expectDbTask=' + $expect)
$verdicts = @()
for ($i = 1; $i -le $Runs; $i++) {
    $q = $questions[($i - 1) % $questions.Count]
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $tag = ('gate-' + $Scenario + '-' + $i)
    $outFile = Join-Path $runDir ($stamp + '-' + $tag + '.out.txt')
    $errFile = Join-Path $runDir ($stamp + '-' + $tag + '.err.txt')
    $rcFile = Join-Path $runDir ($stamp + '-' + $tag + '.rc.txt')
    $inner = '"' + $ocPath + '" run '
    if ($Model -ne '') { $inner += '--model "' + $Model + '" ' }
    $inner += '--agent ' + $Agent + ' --format json --title "' + $tag + '" "' + $q + '" 1> "' + $outFile + '" 2> "' + $errFile + '"'
    $inner += ' & call echo %^ERRORLEVEL% > "' + $rcFile + '"'
    Write-Host ('[' + $i + '/' + $Runs + '] ' + $q)
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList ('/d /s /c "' + $inner + '"') -WorkingDirectory $root -NoNewWindow -PassThru
    try { $null = $p.Handle } catch { }
    $timedOut = $false
    if (-not $p.WaitForExit($TimeoutMin * 60 * 1000)) {
        # 走 cmd 殺整樹：PS 5.1 在 $ErrorActionPreference=Stop 下，原生指令的 stderr 重導會變成終止錯誤
        $null = & cmd.exe /d /c ('taskkill /PID ' + $p.Id + ' /T /F >nul 2>&1')
        $timedOut = $true
        Write-Host ('  逾時（' + $TimeoutMin + ' 分）強殺') -ForegroundColor Yellow
    }
    $exitCode = -1
    if (Test-Path -LiteralPath $rcFile) {
        $rcText = ([System.IO.File]::ReadAllText($rcFile)).Trim()
        if ($rcText -match '^-?\d+$') { $exitCode = [int]$rcText }
    }
    $sessionId = ''
    if (Test-Path -LiteralPath $outFile) {
        foreach ($ln in [System.IO.File]::ReadAllLines($outFile, [System.Text.Encoding]::UTF8)) {
            if ($ln.Trim().StartsWith('{')) {
                try { $ev = ConvertFrom-Json $ln; if ($ev.sessionID) { $sessionId = [string]$ev.sessionID; break } } catch { }
            }
        }
    }
    if ($sessionId -eq '') {
        Write-Host '  找不到 sessionID（看 err 檔）' -ForegroundColor Yellow
        $v0 = New-EmptyVerdict ('(run ' + $i + ' no-session exit=' + $exitCode + ')') 'no sessionID'
        $v0.exitCode = $exitCode
        $v0.timedOut = $timedOut
        $verdicts += $v0
        if (-not $KeepGoing) { break }
        continue
    }
    $v = Get-SessionVerdict $sessionId $ocPath
    $v.exitCode = $exitCode
    $v.timedOut = $timedOut
    $verdicts += $v
    Write-Host ('  ' + $sessionId + '  exit=' + $exitCode + '  task嘗試=' + $v.taskAttempts + ' 被擋=' + $v.blocked + ' 執行=' + $v.executed + ' 早於前置=' + $v.executedBeforePreflight + ' DB完成=' + $v.dbTasksCompleted + ' 前置完成=' + $v.preflight + ' transcript task=' + $v.exportedTasks + ' turns=' + $v.turns + '/' + $v.exportedTurns + ' turnViol=' + $v.turnInvariantViolations + ' callMis=' + $v.callMismatch)
    if (($v.executedBeforePreflight -gt 0 -or $v.turnInvariantViolations -gt 0 -or $v.callMismatch -gt 0) -and -not $KeepGoing) { Write-Host '  違反：DB 委派先於前置執行或呼叫歸屬錯誤——停止（加 -KeepGoing 可續跑）' -ForegroundColor Red; break }
}
Show-Table $verdicts
exit (Write-Summary $verdicts $Scenario $expect)
