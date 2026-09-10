# test-oracle-runtime.ps1 — Oracle 委派的「執行紀錄」驗收（公司機；PowerShell 5.1 可跑）
# 目的：不是看 prompt 文字，而是看每個 session 真正發生的事——DB 委派是否真的查到 DB（合法報告＋子 session 有成功的 sql_run）、
#       NOT_CONNECTED 是否只重連重派一次、工具不可用時有沒有多 connect／重派、路由錯誤有沒有被擋。沒有「READY 順序」「todo 順序」判定。
# 資料來源：ps-runtime-guard 的紀錄 auto-loop-logs\ps-runtime-guard\<sessionID>.jsonl（每筆 hook 事件一行）、
#           主機診斷 auto-loop-logs\ps-runtime-guard\_mcp-diag.jsonl（掛載事件／快照／重掛），
#           並用 opencode export <sessionID> 的正式 transcript 交叉比對 task 件數、真實題目 id、每個 task 所屬的題目（hook 覆蓋率）。
# 用法：
#   跑 N 次新鮮 session（headless，opencode run）：
#     powershell -File scripts\tests\test-oracle-runtime.ps1 -Scenario B1 -Runs 30
#     powershell -File scripts\tests\test-oracle-runtime.ps1 -Scenario B3 -Runs 30 -Question "（純 PeopleCode 流程題）"
#     -QuestionFile <本機檔>：一行一題，輪流使用（真實物件名不進 repo，放本機）
#   只分析既有 session（互動 TUI 連問 ≥ 20 題後）：
#     powershell -File scripts\tests\test-oracle-runtime.ps1 -AnalyzeAll [-Since "2026-09-10 09:00"]
#     powershell -File scripts\tests\test-oracle-runtime.ps1 -AnalyzeSession ses_xxx
# 判定（exit 1 ＝ 有違反；全部無豁免）——分「覆蓋與行為」與「可用」兩條：
#   覆蓋與行為（每個情境都判）：
#   hookMismatch（guard 看到的 task 次數 ≠ transcript 的 task 件數）＝ 0（task hook 覆蓋率 100%）
#   turnMismatch（transcript 裡的真實 user 訊息——有非 synthetic 的 text／file／agent／subtask part——找不到同 id 的 chat.message）＝ 0
#   callMismatch（同一 callID 的 before／after 列 messageID 不一致，或 transcript 裡該 task 所屬的 user 訊息 id ≠ before 列的 messageID）＝ 0
#   reconnectLoops（同一題內 subagent 回 NOT_CONNECTED 之後 connect 超過 1 次，或重連後又重派超過 1 次）＝ 0（至多重連＋重派一次）
#   downThenConnect／downThenRedispatch（同一題內 subagent 回 ORACLE_MCP_DOWN 之後主 agent 又 connect／又派會查 DB 的 task）＝ 0
#   另：export 失敗（exportFailures）與 run 結束碼非 0／逾時（runsWithBadExit）也判 FAIL——否則覆蓋率判定是空的
#   可用（依情境；-ExpectDbTask 覆寫）：
#   Yes（B1 預設）＝每個 session 至少 1 個「完成」的 DB task：子 agent 報告 status=COMPLETE，且其子 session 的紀錄裡至少一個
#     oracleMCP_sql_run 成功（after 列 ok=true）——只有報告宣稱成功不算、「沒回 NOT_CONNECTED」不算；BLOCKED（任何 blockedReason）、
#     INVALID（非契約 JSON／task_error）都不算完成，PARTIAL 另計。零違規但零完成不算過。B1 的題目要用預期能 COMPLETE 的固定題
#   No（B3 預設）＝0 個會查 DB 的 task 執行；Any（B2／CUSTOM／-AnalyzeAll 預設）＝不判、只列數字
# 觀察值（不判定）：notConnectedReports（subagent 回 NOT_CONNECTED 次數＝模型錯序機率）、reconnects、downReports、
#   routingBlocks（task 用 skill 名當 agent 被擋：PS_TASK_TARGET_INVALID）、suggestedNextInvalid（報告建議了無效目標，guard 已附註）、
#   connectBlocks（connect 在執行前被擋：profile 未填或目標不一致）、invalidOracleCalls（模型呼叫了看不到的 oracleMCP_ 工具）、
#   listCalls（list_connections 呼叫數；正常為 0）、unknownResults（connect／sql_run 回空輸出）、tasksNotReturned（沒有 after 的 task）；
#   -AnalyzeAll 另印主機診斷摘要：tools.changed 事件、快照狀態分布、重掛決定（would-remount／remount-ok／remount-failed／suppressed）
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
$gateDir = Join-Path $root (Join-Path 'auto-loop-logs' 'ps-runtime-guard')
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
# compaction（只有 compaction part）、續行／背景回灌（全部 synthetic）都是系統插的，guard 不記、這裡也不算題
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
    # 會查 DB：guard 的機械欄位 dbCapable；沒有欄位時由 basis 推導——只有明確的 sql_run:disabled 才算不會查（不認識的 agent＝會查）
    function Test-DbCapable($row) {
        $p = $row.PSObject.Properties['dbCapable']
        if ($null -ne $p -and $null -ne $p.Value) { return [bool]$p.Value }
        if ([string]$row.basis -eq 'sql_run:disabled') { return $false }
        return $true
    }
    function Get-MsgKey($row) { if ($row.messageID) { return [string]$row.messageID } return '' }
    $before = @($rows | Where-Object { $_.hook -eq 'before' -and $_.tool -eq 'task' })
    $routingBlocks = @($before | Where-Object { $_.decision -eq 'block' -and [string]$_.note -match '^PS_TASK_TARGET_INVALID' })
    $executed = @($rows | Where-Object { $_.hook -eq 'after' -and $_.tool -eq 'task' -and $_.executed -eq $true })
    $executedDb = @($executed | Where-Object { Test-DbCapable $_ })
    # 可用：子 agent 報告 status=COMPLETE，且其子 session 的紀錄裡至少一個 sql_run 成功（ok=true）——「沒回 NOT_CONNECTED」不算成功
    function Get-ChildSqlOk([string]$Child) {
        if ($Child -eq '') { return 0 }
        $rows2 = @(Read-Jsonl (Join-Path $gateDir ($Child + '.jsonl')))
        return @($rows2 | Where-Object { $_.hook -eq 'after' -and $_.tool -eq 'oracleMCP_sql_run' -and $_.ok -eq $true }).Count
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
    $afterIds = @{}
    foreach ($e in $executed) { if ($e.callID) { $afterIds[[string]$e.callID] = $true } }
    $notReturned = @($before | Where-Object { $_.decision -ne 'block' -and $_.callID -and -not $afterIds.ContainsKey([string]$_.callID) }).Count
    $connectBlocks = @($rows | Where-Object { $_.hook -eq 'before' -and $_.tool -eq 'oracleMCP_connect' -and $_.decision -eq 'block' }).Count
    $invalidOracle = @($rows | Where-Object { $_.hook -eq 'invalid' }).Count
    $suggestedBad = 0
    foreach ($e in $executed) { $sp = $e.PSObject.Properties['suggestedNextInvalid']; if ($null -ne $sp -and $null -ne $sp.Value) { $suggestedBad += @($sp.Value).Count } }
    $afters = @($rows | Where-Object { $_.hook -eq 'after' })
    $listCalls = @($afters | Where-Object { $_.tool -eq 'oracleMCP_list_connections' }).Count
    $unknownRes = @($afters | Where-Object { ($_.tool -eq 'oracleMCP_connect' -or $_.tool -eq 'oracleMCP_sql_run') -and [string]$_.ok -eq 'unknown' }).Count
    $notConnectedReports = @($executed | Where-Object { $_.notConnected -eq $true }).Count
    $downReports = @($executed | Where-Object { [string]$_.blockedReason -eq 'ORACLE_MCP_DOWN' }).Count
    # 同一題內的行為：NOT_CONNECTED 之後至多 connect 一次、重派一次；ORACLE_MCP_DOWN 之後不 connect、不重派會查 DB 的 task
    $reconnects = 0; $loops = 0; $downConn = 0; $downRedispatch = 0
    $byMsg = @{}
    foreach ($r in $rows) {
        if ($r.hook -eq 'chat.message') { continue }
        $k = Get-MsgKey $r
        if (-not $byMsg.ContainsKey($k)) { $byMsg[$k] = @() }
        $byMsg[$k] += $r
    }
    foreach ($k in @($byMsg.Keys)) {
        $seq = @($byMsg[$k])
        $ncSeen = 0; $connAfterNc = 0; $redispatchAfterNc = 0; $downSeen = $false
        foreach ($r in $seq) {
            if ($r.hook -eq 'after' -and $r.tool -eq 'task' -and $r.executed -eq $true) {
                if ($r.notConnected -eq $true) { $ncSeen++; continue }
                if ([string]$r.blockedReason -eq 'ORACLE_MCP_DOWN') { $downSeen = $true; continue }
            }
            if ($r.hook -eq 'before' -and $r.tool -eq 'oracleMCP_connect' -and $r.decision -ne 'block') {
                if ($ncSeen -gt 0) { $connAfterNc++ }
                if ($downSeen) { $downConn++ }
            }
            if ($r.hook -eq 'before' -and $r.tool -eq 'task' -and $r.decision -ne 'block' -and (Test-DbCapable $r)) {
                if ($ncSeen -gt 0 -and $connAfterNc -gt 0) { $redispatchAfterNc++ }
                if ($downSeen) { $downRedispatch++ }
            }
        }
        $reconnects += $connAfterNc
        if ($connAfterNc -gt 1 -or $redispatchAfterNc -gt 1) { $loops++ }
    }
    # 呼叫歸屬：同一 callID 的 before／after 列 messageID 必須一致
    $callMis = 0
    $beforeById = @{}
    foreach ($b in $before) { if ($b.callID) { $beforeById[[string]$b.callID] = $b } }
    foreach ($e in $executed) {
        if ($e.callID -and $beforeById.ContainsKey([string]$e.callID)) {
            if ((Get-MsgKey $beforeById[[string]$e.callID]) -ne (Get-MsgKey $e)) { $callMis++ }
        }
    }
    # transcript 交叉比對：task 工具件數；真實題目 id ↔ chat.message messageID 逐一配對；每個 task 所屬題目 ↔ before 列 messageID
    $chatRows = @($rows | Where-Object { $_.hook -eq 'chat.message' -and $_.synthetic -ne $true })
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
        $chatIds = @($chatRows | ForEach-Object { [string]$_.messageID } | Sort-Object -Unique)
        foreach ($pid0 in $promptIds) { if ($chatIds -notcontains $pid0) { $missingTurns++ } }
        foreach ($cid in $chatIds) { if ($promptIds -notcontains $cid) { $orphanTurns++ } }
        $parents = $ec.taskParents
        foreach ($cid in @($beforeById.Keys)) {
            if ($parents.ContainsKey($cid)) {
                if ([string]$parents[$cid] -ne (Get-MsgKey $beforeById[$cid])) { $callMis++ }
            }
            else { $unmatched++ }
        }
    }
    $mismatch = 0
    if ($exportedTasks -ge 0 -and $exportedTasks -ne $before.Count) { $mismatch = 1 }
    return [pscustomobject]@{
        sessionID = $SessionId; rows = $rows.Count; taskAttempts = $before.Count; routingBlocks = $routingBlocks.Count
        executed = $executed.Count; executedDb = $executedDb.Count; dbTasksCompleted = $dbOk.Count
        dbTasksPartial = $dbPartial.Count; dbTasksBlocked = $dbBlocked.Count; dbTasksInvalid = $dbInvalid.Count; dbTasksCompletedNoSql = $dbNoSql.Count
        notConnectedReports = $notConnectedReports; reconnects = $reconnects; reconnectLoops = $loops
        downReports = $downReports; downThenConnect = $downConn; downThenRedispatch = $downRedispatch
        tasksNotReturned = $notReturned; connectBlocks = $connectBlocks; invalidOracleCalls = $invalidOracle; suggestedNextInvalid = $suggestedBad
        listCalls = $listCalls; unknownResults = $unknownRes
        exportedTasks = $exportedTasks; hookMismatch = $mismatch; exportError = $exportErr
        turns = @($chatRows | ForEach-Object { [string]$_.messageID } | Sort-Object -Unique).Count; exportedTurns = $exportedTurns; turnMismatch = $missingTurns; orphanTurns = $orphanTurns
        callMismatch = $callMis; unmatchedCalls = $unmatched
        exportFailures = $(if ($exportErr -ne '') { 1 } else { 0 }); exitCode = -1; timedOut = $false
    }
}

function New-EmptyVerdict([string]$Label, [string]$Err) {
    return [pscustomobject]@{
        sessionID = $Label; rows = 0; taskAttempts = 0; routingBlocks = 0; executed = 0; executedDb = 0; dbTasksCompleted = 0
        dbTasksPartial = 0; dbTasksBlocked = 0; dbTasksInvalid = 0; dbTasksCompletedNoSql = 0
        notConnectedReports = 0; reconnects = 0; reconnectLoops = 0; downReports = 0; downThenConnect = 0; downThenRedispatch = 0
        tasksNotReturned = 0; connectBlocks = 0; invalidOracleCalls = 0; suggestedNextInvalid = 0; listCalls = 0; unknownResults = 0
        exportedTasks = -1; hookMismatch = 0; exportError = $Err; turns = 0; exportedTurns = -1; turnMismatch = 0; orphanTurns = 0
        callMismatch = 0; unmatchedCalls = 0; exportFailures = 0; exitCode = -1; timedOut = $false
    }
}

function Show-Table($verdicts) {
    Write-Host ''
    $fmt = '{0,-32} {1,4} {2,4} {3,5} {4,4} {5,5} {6,5} {7,4} {8,5} {9,6} {10,7} {11,5}'
    Write-Host ($fmt -f 'sessionID', 'try', 'exec', 'dbOk', 'nc', 'loops', 'down', 'rout', 'turns', 'xTurns', 'callMis', 'mism')
    foreach ($v in $verdicts) {
        Write-Host ($fmt -f $v.sessionID, $v.taskAttempts, $v.executed, $v.dbTasksCompleted, $v.notConnectedReports, $v.reconnectLoops, $v.downReports, $v.routingBlocks, $v.turns, $v.exportedTurns, $v.callMismatch, $v.hookMismatch)
    }
}

# 主機診斷摘要（_mcp-diag.jsonl；不判定）
function Show-Diag {
    $d = @(Read-Jsonl (Join-Path $gateDir '_mcp-diag.jsonl'))
    if ($d.Count -eq 0) { Write-Host '主機診斷：_mcp-diag.jsonl 無資料（沒有掛載事件；或 guard 沒載入——看 _plugin.log）'; return }
    $ev = @($d | Where-Object { $_.kind -eq 'event' -and $_.type -eq 'mcp.tools.changed' }).Count
    $snap = @($d | Where-Object { $_.kind -eq 'snapshot' })
    $stat = @{}
    foreach ($s in $snap) { $k = [string]$s.runtimeStatus; if (-not $stat.ContainsKey($k)) { $stat[$k] = 0 }; $stat[$k]++ }
    $rec = @($d | Where-Object { $_.kind -eq 'recovery' })
    $dec = @{}
    foreach ($r in $rec) { $k = [string]$r.decision; if (-not $dec.ContainsKey($k)) { $dec[$k] = 0 }; $dec[$k]++ }
    $inv = @($d | Where-Object { $_.kind -eq 'invalid-tool' }).Count
    $terr = @($d | Where-Object { $_.kind -eq 'tool-error' }).Count
    $statS = (@($stat.Keys | Sort-Object | ForEach-Object { $_ + '=' + $stat[$_] }) -join ' ')
    $decS = (@($dec.Keys | Sort-Object | ForEach-Object { $_ + '=' + $dec[$_] }) -join ' ')
    Write-Host ('主機診斷：tools.changed=' + $ev + '  快照狀態[' + $statS + ']  重掛決定[' + $decS + ']  invalid-tool=' + $inv + '  tool-error=' + $terr + '  instances=' + @($d | ForEach-Object { [string]$_.instance } | Sort-Object -Unique).Count)
    $bad = @($rec | Where-Object { $_.decision -eq 'remount-failed' -or $_.decision -eq 'suppressed' -or $_.decision -eq 'gave-up' })
    if ($bad.Count -gt 0) { Write-Host ('注意：有 ' + $bad.Count + ' 筆自動恢復失敗／被抑制——依 SOP-21 人工在該視窗 /mcps 重掛，看 _mcp-diag.jsonl 的 note') -ForegroundColor Yellow }
}

# $Expect：Yes＝每 session 至少一個會查 DB 的 task 完成；No＝不得有會查 DB 的 task 執行；Any＝不判
function Write-Summary($verdicts, [string]$Label, [string]$Expect) {
    $mism = ($verdicts | Measure-Object -Property hookMismatch -Sum).Sum
    $tmism = ($verdicts | Measure-Object -Property turnMismatch -Sum).Sum
    $cmis = ($verdicts | Measure-Object -Property callMismatch -Sum).Sum
    $loops = ($verdicts | Measure-Object -Property reconnectLoops -Sum).Sum
    $dconn = ($verdicts | Measure-Object -Property downThenConnect -Sum).Sum
    $dred = ($verdicts | Measure-Object -Property downThenRedispatch -Sum).Sum
    $orphan = ($verdicts | Measure-Object -Property orphanTurns -Sum).Sum
    $unmatched = ($verdicts | Measure-Object -Property unmatchedCalls -Sum).Sum
    $xfail = ($verdicts | Measure-Object -Property exportFailures -Sum).Sum
    $unknown = ($verdicts | Measure-Object -Property unknownResults -Sum).Sum
    $exitBad = @($verdicts | Where-Object { $_.exitCode -gt 0 -or $_.timedOut }).Count
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
    $nc = ($verdicts | Measure-Object -Property notConnectedReports -Sum).Sum
    $rc = ($verdicts | Measure-Object -Property reconnects -Sum).Sum
    $down = ($verdicts | Measure-Object -Property downReports -Sum).Sum
    $rout = ($verdicts | Measure-Object -Property routingBlocks -Sum).Sum
    $sug = ($verdicts | Measure-Object -Property suggestedNextInvalid -Sum).Sum
    $inv = ($verdicts | Measure-Object -Property invalidOracleCalls -Sum).Sum
    $ncRuns = @($verdicts | Where-Object { $_.notConnectedReports -gt 0 }).Count
    $usabilityFail = 0
    if ($Expect -eq 'Yes') { $usabilityFail = @($verdicts | Where-Object { $_.dbTasksCompleted -eq 0 }).Count }
    if ($Expect -eq 'No') { $usabilityFail = $dbRuns }
    $summary = [pscustomobject]@{
        label = $Label; sessions = $verdicts.Count; expectDbTask = $Expect
        hookMismatch = [int]$mism; turnMismatch = [int]$tmism; callMismatch = [int]$cmis
        reconnectLoops = [int]$loops; downThenConnect = [int]$dconn; downThenRedispatch = [int]$dred
        exportFailures = [int]$xfail; runsWithBadExit = $exitBad; usabilityFailures = $usabilityFail
        sessionsWithoutTask = $noTask; sessionsWithDbTaskOk = $dbOkRuns; sessionsWithDbTask = $dbRuns; sessionsWithNotConnected = $ncRuns
        dbTasksCompleted = [int]$dbDone; dbTasksPartial = [int]$dbPart; dbTasksBlocked = [int]$dbBlk; dbTasksInvalid = [int]$dbInv
        dbTasksCompletedNoSql = [int]$dbNoSql; tasksNotReturned = [int]$notRet
        notConnectedReports = [int]$nc; reconnects = [int]$rc; downReports = [int]$down; routingBlocks = [int]$rout; suggestedNextInvalid = [int]$sug
        connectBlocks = [int]$cblk; invalidOracleCalls = [int]$inv; listCalls = [int]$lcalls; unknownResults = [int]$unknown; orphanTurns = [int]$orphan; unmatchedCalls = [int]$unmatched
        stamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }
    $out = Join-Path $gateDir ('summary-' + $Label + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    [System.IO.File]::WriteAllText($out, (ConvertTo-Json $summary -Depth 3), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ''
    Write-Host ('覆蓋與行為：sessions=' + $verdicts.Count + '  hookMismatch=' + [int]$mism + '  turnMismatch=' + [int]$tmism + '  callMismatch=' + [int]$cmis +
        '  reconnectLoops=' + [int]$loops + '  downThenConnect=' + [int]$dconn + '  downThenRedispatch=' + [int]$dred)
    Write-Host ('可用（ExpectDbTask=' + $Expect + '）：sessionsWithDbTaskOk=' + $dbOkRuns + '/' + $verdicts.Count + '  sessionsWithDbTask=' + $dbRuns + '  usabilityFailures=' + $usabilityFail +
        '  dbTasks completed=' + [int]$dbDone + ' partial=' + [int]$dbPart + ' blocked=' + [int]$dbBlk + ' invalid=' + [int]$dbInv + ' completedNoSql=' + [int]$dbNoSql +
        '  tasksNotReturned=' + [int]$notRet)
    if ([int]$dbNoSql -gt 0) { Write-Host ('注意：' + [int]$dbNoSql + ' 個 DB task 報告 COMPLETE 但子 session 沒有成功的 sql_run——只是宣稱成功，不計為完成') -ForegroundColor Yellow }
    if ([int]$cblk -gt 0) { Write-Host ('注意：' + [int]$cblk + ' 次 connect 在執行前被擋（profile oracle.connectionName 未填或與 connect 目標不一致）——看 jsonl 的 note') -ForegroundColor Yellow }
    Write-Host ('觀察：sessionsWithNotConnected=' + $ncRuns + '（模型錯序：先派後連）  notConnectedReports=' + [int]$nc + '  reconnects=' + [int]$rc + '  downReports=' + [int]$down +
        '  routingBlocks=' + [int]$rout + '（skill 名當 agent 被擋）  suggestedNextInvalid=' + [int]$sug + '  invalidOracleCalls=' + [int]$inv + '  listCalls=' + [int]$lcalls +
        '（正常為 0）  unknownResults=' + [int]$unknown + '  sessionsWithoutTask=' + $noTask + '  orphanTurns=' + [int]$orphan + '  unmatchedCalls=' + [int]$unmatched)
    Write-Host ('摘要已寫：' + $out)
    if ([int]$unknown -gt 0) { Write-Host ('注意：有 ' + [int]$unknown + ' 次 connect／sql_run 回空輸出——真 SQLcl 若如此回覆，把 jsonl 那列回報維護 session') -ForegroundColor Yellow }
    if ([int]$xfail -gt 0) { Write-Host ('注意：' + [int]$xfail + ' 個 session 的 opencode export 失敗（看各列 exportError）——覆蓋率判定對這些 session 是空的') -ForegroundColor Yellow }
    if ($exitBad -gt 0) { Write-Host ('注意：' + $exitBad + ' 次 run 結束碼非 0 或逾時強殺（看 runs\*.err.txt）') -ForegroundColor Yellow }
    $behaviourFail = ([int]$mism -gt 0 -or [int]$tmism -gt 0 -or [int]$cmis -gt 0 -or [int]$loops -gt 0 -or [int]$dconn -gt 0 -or [int]$dred -gt 0 -or [int]$xfail -gt 0 -or $exitBad -gt 0)
    if ($behaviourFail) {
        Write-Host '判定：FAIL（覆蓋與行為：task hook 覆蓋率不足／有題沒收到 chat.message／呼叫歸屬被改標／NOT_CONNECTED 後重連重派超過一次／ORACLE_MCP_DOWN 後又 connect 或重派／export 失敗／run 異常結束）' -ForegroundColor Red
        return 1
    }
    if ($usabilityFail -gt 0) {
        if ($Expect -eq 'Yes') { Write-Host ('判定：FAIL（可用：' + $usabilityFail + ' 個 session 沒有任何「報告 COMPLETE 且子 session sql_run 成功」的 DB task——零違規不等於可用）') -ForegroundColor Red }
        else { Write-Host ('判定：FAIL（可用：' + $usabilityFail + ' 個 session 派了會查 DB 的 task，但本情境預期不查 DB）') -ForegroundColor Red }
        return 1
    }
    Write-Host ('判定：PASS（覆蓋與行為六項全 0' + $(if ($Expect -eq 'Yes') { '；每個 session 都有會查 DB 的 task 完成' } elseif ($Expect -eq 'No') { '；沒有會查 DB 的 task 執行' } else { '' }) + '）') -ForegroundColor Green
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
    if ($ids.Count -eq 0) { Write-Host '沒有可分析的 session 紀錄（guard plugin 有載入嗎？看 _plugin.log）'; exit 2 }
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
    Show-Diag
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
    $tag = ('guard-' + $Scenario + '-' + $i)
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
    Write-Host ('  ' + $sessionId + '  exit=' + $exitCode + '  task嘗試=' + $v.taskAttempts + ' 執行=' + $v.executed + ' DB完成=' + $v.dbTasksCompleted + ' NOT_CONNECTED=' + $v.notConnectedReports + ' 重連=' + $v.reconnects + ' 迴圈=' + $v.reconnectLoops + ' DOWN=' + $v.downReports + ' 路由擋=' + $v.routingBlocks + ' transcript task=' + $v.exportedTasks + ' turns=' + $v.turns + '/' + $v.exportedTurns + ' callMis=' + $v.callMismatch)
    if (($v.reconnectLoops -gt 0 -or $v.downThenConnect -gt 0 -or $v.downThenRedispatch -gt 0 -or $v.callMismatch -gt 0) -and -not $KeepGoing) { Write-Host '  違反：重連迴圈／DOWN 後又 connect 或重派／呼叫歸屬錯誤——停止（加 -KeepGoing 可續跑）' -ForegroundColor Red; break }
}
Show-Table $verdicts
Show-Diag
exit (Write-Summary $verdicts $Scenario $expect)
