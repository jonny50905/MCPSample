# test-oracle-gate-runtime.ps1 — Oracle 連線前置閘門的「執行紀錄」回歸（公司機；PowerShell 5.1 可跑）
# 目的：不是看 prompt 文字，而是看每個 session 真正發生的工具順序——
#       「已執行的 DB 委派（task）發生在 list_connections → connect 成功之前」的次數必須是 0。
# 資料來源：閘門 plugin 的交易紀錄 auto-loop-logs\ps-oracle-gate\<sessionID>.jsonl（每筆 hook 事件一行），
#           並用 opencode export <sessionID> 的正式 transcript 交叉比對 task 件數與真實題目 id（hook 覆蓋率必須 100%）。
# 用法：
#   跑 N 次新鮮 session（headless，opencode run）：
#     powershell -File scripts\tests\test-oracle-gate-runtime.ps1 -Scenario B1 -Runs 30
#     powershell -File scripts\tests\test-oracle-gate-runtime.ps1 -Scenario B3 -Runs 30 -Question "（純 PeopleCode 流程題）"
#     -QuestionFile <本機檔>：一行一題，輪流使用（真實物件名不進 repo，放本機）
#   只分析既有 session（互動 TUI 同一視窗連問 ≥ 20 題後做 P1 探測）：
#     powershell -File scripts\tests\test-oracle-gate-runtime.ps1 -AnalyzeAll [-Since "2026-09-08 09:00"]
#     powershell -File scripts\tests\test-oracle-gate-runtime.ps1 -AnalyzeSession ses_xxx
# 判定（exit 1 ＝ 有違反；全部無豁免——閘門刻意放行的 task 一樣照算，另以 standDowns 說明來源）：
#   executedTaskBeforePreflight（會查 DB 的 task 入場時狀態 ≠ READY 卻執行了）總和 ＝ 0
#   hookMismatch（閘門看到的 task 次數 ≠ transcript 的 task 件數）總和 ＝ 0（task hook 覆蓋率 100%）
#   turnMismatch（transcript 裡的真實 user 訊息——有非 synthetic 的 text／file／agent／subtask part——找不到同 id 的 chat.message）＝ 0
#     ——compaction／續行／背景回灌那種系統插入的 user 訊息不算題；/undo 刪掉的訊息不算漏（另計 orphanTurns 觀察值）
#   turnInvariantViolations（已執行的 DB task 在「同一 turn 內」找不到依序先於它的 list_connections 成功→connect 成功→READY）＝ 0
#   另：export 失敗（exportFailures）與 run 結束碼非 0／逾時（runsWithBadExit）也判 FAIL——否則覆蓋率判定是空的
# 附帶統計（不判定，供觀察）：blockedRuns＝模型先派 task 被擋的 session 數（＝錯序機率）；preflightRuns＝有依序完成 list→connect 的
#   session 數（R8：不需要 DB 的題也應為 100%）；standDowns＝閘門因 oracleMCP 未掛載而放行的次數——這些 task 仍計入
#   executedTaskBeforePreflight（不是豁免），回歸要在 oracleMCP 掛載時跑；orphanTurns＝chat.message 有、transcript 沒有的題（/undo）。
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

# 從 opencode export 的物件取：task 工具件數、真實題目（user 訊息）id 清單
# 真實題目＝role=user 且至少有一個非 synthetic 的 text／file／agent／subtask part；
# compaction（只有 compaction part）、續行／背景回灌（全部 synthetic）都是系統插的，plugin 不重置、這裡也不算題
function Get-ExportCounts($Obj, [string]$SessionId) {
    $n = 0
    $ids = @()
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
                if ($null -eq $sid -or $sid -eq $SessionId) { $n++ }
            }
        }
    }
    return @{ tasks = $n; promptIds = $ids }
}

# 一個 session 的判讀：回傳 pscustomobject（PS 5.1 的 Measure-Object／Select-Object 對 hashtable 不吃鍵）
# -ExportPath：測試用，直接讀 export JSON 檔而不呼叫 opencode
function Get-SessionVerdict([string]$SessionId, [string]$OcPath, [string]$ExportPath = '') {
    $rows = @(Read-Jsonl (Join-Path $gateDir ($SessionId + '.jsonl')))
    $before = @($rows | Where-Object { $_.hook -eq 'before' -and $_.tool -eq 'task' })
    $blocked = @($before | Where-Object { $_.decision -eq 'block' })
    $wouldBlock = @($before | Where-Object { $_.decision -eq 'observe-would-block' })
    $executed = @($rows | Where-Object { $_.hook -eq 'after' -and $_.tool -eq 'task' -and $_.executed -eq $true })
    # 閘門因 oracleMCP 未掛載而放行的 task：只做來源說明（callID 配對），不是豁免
    $standDownRows = @($before | Where-Object { $_.decision -eq 'allow' -and $_.note -match '^gate stands down' })
    $standDownIds = @{}
    foreach ($q in $standDownRows) { if ($q.callID) { $standDownIds[[string]$q.callID] = $true } }
    # 會查 DB 的 task 入場時狀態 ≠ READY 卻執行了＝違反（無豁免：observe 模式、oracleMCP 未掛載的退讓都照算）
    $early = @($executed | Where-Object { $_.basis -eq 'run_sql:enabled' -and $_.state -ne 'READY' })
    $earlyStandDown = @($early | Where-Object { $_.callID -and $standDownIds.ContainsKey([string]$_.callID) }).Count
    $afters = @($rows | Where-Object { $_.hook -eq 'after' })
    $listOk = @($afters | Where-Object { $_.tool -eq 'oracleMCP_list_connections' -and $_.ok -eq $true })
    $connOk = @($afters | Where-Object { $_.tool -eq 'oracleMCP_connect' -and $_.next -eq 'READY' })
    $preflight = ($listOk.Count -gt 0 -and $connOk.Count -gt 0)
    # per-turn 不變量：每個已執行的 DB task，同一 turn 內、在它之前必須依序有 list 成功 → connect→READY
    # turn 識別＝turnId（該則 user 訊息 id；opencode run --session 續接是新行程，數字 turn 會歸零）；task 列的 turnId 是入場快照
    $turnViol = 0
    # 真實 user 訊息才算一題：全部 part 都 synthetic 的（背景 subagent 回灌／compaction 續行）與同 id 重複到達的列 plugin 不重置、這裡也不計
    $chatRows = @($rows | Where-Object { $_.hook -eq 'chat.message' -and -not ([string]$_.note -match 'no reset') })
    function Get-TurnKey($row) { if ($row.turnId) { return [string]$row.turnId } return ([string]$row.pid + '-' + [string]$row.turn) }
    for ($k = 0; $k -lt $rows.Count; $k++) {
        $r = $rows[$k]
        if (-not ($r.hook -eq 'after' -and $r.tool -eq 'task' -and $r.executed -eq $true -and $r.basis -eq 'run_sql:enabled')) { continue }
        $t = Get-TurnKey $r
        $listIdx = -1; $connIdx = -1
        for ($j = 0; $j -lt $k; $j++) {
            $q = $rows[$j]
            if ($q.hook -ne 'after') { continue }
            if ((Get-TurnKey $q) -ne $t) { continue }
            if ($q.tool -eq 'oracleMCP_list_connections' -and $q.ok -eq $true -and $listIdx -lt 0) { $listIdx = $j }
            if ($q.tool -eq 'oracleMCP_connect' -and $q.next -eq 'READY' -and $listIdx -ge 0 -and $j -gt $listIdx) { $connIdx = $j }
        }
        if ($connIdx -lt 0) { $turnViol++ }
    }
    # transcript 交叉比對：task 工具件數；真實題目 id ↔ chat.message turnId 逐一配對
    $exportedTasks = -1
    $exportedTurns = -1
    $missingTurns = 0
    $orphanTurns = 0
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
    }
    $mismatch = 0
    if ($exportedTasks -ge 0 -and $exportedTasks -ne $before.Count) { $mismatch = 1 }
    $modeVal = ''
    $modeRow = @($rows | Where-Object { $_.mode } | Select-Object -First 1)
    if ($modeRow.Count -gt 0) { $modeVal = [string]$modeRow[0].mode }
    return [pscustomobject]@{
        sessionID = $SessionId; rows = $rows.Count; taskAttempts = $before.Count; blocked = $blocked.Count
        wouldBlock = $wouldBlock.Count; executed = $executed.Count; executedBeforePreflight = $early.Count; earlyStandDown = $earlyStandDown
        preflight = $preflight; exportedTasks = $exportedTasks; hookMismatch = $mismatch; exportError = $exportErr
        turns = $chatRows.Count; exportedTurns = $exportedTurns; turnMismatch = $missingTurns; orphanTurns = $orphanTurns
        turnInvariantViolations = $turnViol; standDowns = $standDownRows.Count
        exportFailures = $(if ($exportErr -ne '') { 1 } else { 0 }); exitCode = -1; timedOut = $false
        mode = $modeVal
    }
}

function New-EmptyVerdict([string]$Label, [string]$Err) {
    return [pscustomobject]@{
        sessionID = $Label; rows = 0; taskAttempts = 0; blocked = 0; wouldBlock = 0; executed = 0; executedBeforePreflight = 0; earlyStandDown = 0
        preflight = $false; exportedTasks = -1; hookMismatch = 0; exportError = $Err; turns = 0; exportedTurns = -1; turnMismatch = 0; orphanTurns = 0
        turnInvariantViolations = 0; standDowns = 0; exportFailures = 0; exitCode = -1; timedOut = $false; mode = ''
    }
}

function Show-Table($verdicts) {
    Write-Host ''
    Write-Host ('{0,-32} {1,5} {2,5} {3,5} {4,5} {5,7} {6,5} {7,5} {8,5} {9,6} {10,8} {11,5}' -f 'sessionID', 'try', 'blk', 'exec', 'early', 'prefl', 'xTask', 'mism', 'turns', 'xTurns', 'turnViol', 'sdown')
    foreach ($v in $verdicts) {
        Write-Host ('{0,-32} {1,5} {2,5} {3,5} {4,5} {5,7} {6,5} {7,5} {8,5} {9,6} {10,8} {11,5}' -f $v.sessionID, $v.taskAttempts, $v.blocked, $v.executed, $v.executedBeforePreflight, $v.preflight, $v.exportedTasks, $v.hookMismatch, $v.turns, $v.exportedTurns, $v.turnInvariantViolations, $v.standDowns)
    }
}

function Write-Summary($verdicts, [string]$Label) {
    $early = ($verdicts | Measure-Object -Property executedBeforePreflight -Sum).Sum
    $earlySd = ($verdicts | Measure-Object -Property earlyStandDown -Sum).Sum
    $mism = ($verdicts | Measure-Object -Property hookMismatch -Sum).Sum
    $tmism = ($verdicts | Measure-Object -Property turnMismatch -Sum).Sum
    $tviol = ($verdicts | Measure-Object -Property turnInvariantViolations -Sum).Sum
    $sd = ($verdicts | Measure-Object -Property standDowns -Sum).Sum
    $orphan = ($verdicts | Measure-Object -Property orphanTurns -Sum).Sum
    $xfail = ($verdicts | Measure-Object -Property exportFailures -Sum).Sum
    $exitBad = @($verdicts | Where-Object { $_.exitCode -gt 0 -or $_.timedOut }).Count
    $blockedRuns = @($verdicts | Where-Object { $_.blocked -gt 0 -or $_.wouldBlock -gt 0 }).Count
    $preflightRuns = @($verdicts | Where-Object { $_.preflight }).Count
    $noTask = @($verdicts | Where-Object { $_.taskAttempts -eq 0 }).Count
    $summary = [pscustomobject]@{
        label = $Label; sessions = $verdicts.Count; executedTaskBeforePreflight = [int]$early; hookMismatch = [int]$mism
        turnMismatch = [int]$tmism; turnInvariantViolations = [int]$tviol
        exportFailures = [int]$xfail; runsWithBadExit = $exitBad
        blockedRuns = $blockedRuns; preflightRuns = $preflightRuns; sessionsWithoutTask = $noTask
        standDowns = [int]$sd; earlyViaStandDown = [int]$earlySd; orphanTurns = [int]$orphan
        stamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }
    $out = Join-Path $gateDir ('summary-' + $Label + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    [System.IO.File]::WriteAllText($out, (ConvertTo-Json $summary -Depth 3), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ''
    Write-Host ('sessions=' + $verdicts.Count + '  executedTaskBeforePreflight=' + [int]$early + '  hookMismatch=' + [int]$mism +
        '  turnMismatch=' + [int]$tmism + '  turnInvariantViolations=' + [int]$tviol)
    Write-Host ('blockedRuns=' + $blockedRuns + '（模型先派 task 被擋）  preflightRuns=' + $preflightRuns + '  sessionsWithoutTask=' + $noTask +
        '  standDowns=' + [int]$sd + '（oracleMCP 未掛載時閘門放行，觀察值）  orphanTurns=' + [int]$orphan + '（/undo 或 fork，觀察值）')
    Write-Host ('摘要已寫：' + $out)
    if ([int]$earlySd -gt 0) { Write-Host ('注意：早於前置執行的 ' + [int]$early + ' 筆裡有 ' + [int]$earlySd + ' 筆發生在 oracleMCP 未掛載期間（閘門退讓）——不是豁免、照判 FAIL；回歸請在 oracleMCP 掛載時重跑') -ForegroundColor Yellow }
    if ([int]$xfail -gt 0) { Write-Host ('注意：' + [int]$xfail + ' 個 session 的 opencode export 失敗（看各列 exportError）——覆蓋率判定對這些 session 是空的') -ForegroundColor Yellow }
    if ($exitBad -gt 0) { Write-Host ('注意：' + $exitBad + ' 次 run 結束碼非 0 或逾時強殺（看 runs\*.err.txt）') -ForegroundColor Yellow }
    if ([int]$early -gt 0 -or [int]$mism -gt 0 -or [int]$tmism -gt 0 -or [int]$tviol -gt 0 -or [int]$xfail -gt 0 -or $exitBad -gt 0) {
        Write-Host '判定：FAIL（DB 委派先於前置執行／task hook 覆蓋率不足／有題沒收到重置／同題內找不到 list→connect／export 失敗／run 異常結束）' -ForegroundColor Red
        return 1
    }
    Write-Host '判定：PASS（executed task before preflight = 0；task／turn hook 覆蓋率 100%；每個已執行的 DB task 同題內都有 list→connect）' -ForegroundColor Green
    return 0
}

$ocPath = Get-OpencodeCmd

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
    exit (Write-Summary $verdicts ('analyze-' + $Scenario))
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

Write-Host ('opencode：' + $ocPath + '  agent=' + $Agent + '  scenario=' + $Scenario + '  runs=' + $Runs)
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
    Write-Host ('  ' + $sessionId + '  exit=' + $exitCode + '  task嘗試=' + $v.taskAttempts + ' 被擋=' + $v.blocked + ' 執行=' + $v.executed + ' 早於前置=' + $v.executedBeforePreflight + ' 前置完成=' + $v.preflight + ' transcript task=' + $v.exportedTasks + ' turns=' + $v.turns + '/' + $v.exportedTurns + ' turnViol=' + $v.turnInvariantViolations)
    if (($v.executedBeforePreflight -gt 0 -or $v.turnInvariantViolations -gt 0) -and -not $KeepGoing) { Write-Host '  違反：DB 委派先於前置執行——停止（加 -KeepGoing 可續跑）' -ForegroundColor Red; break }
}
Show-Table $verdicts
exit (Write-Summary $verdicts $Scenario)
