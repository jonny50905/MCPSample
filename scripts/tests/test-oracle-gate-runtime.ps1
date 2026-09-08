# test-oracle-gate-runtime.ps1 — Oracle 連線前置閘門的「執行紀錄」回歸（公司機；PowerShell 5.1 可跑）
# 目的：不是看 prompt 文字，而是看每個 session 真正發生的工具順序——
#       「已執行的 DB 委派（task）發生在 list_connections → connect 成功之前」的次數必須是 0。
# 資料來源：閘門 plugin 的交易紀錄 auto-loop-logs\ps-oracle-gate\<sessionID>.jsonl（每筆 hook 事件一行），
#           並用 opencode export <sessionID> 的正式 transcript 交叉比對 task 件數（hook 覆蓋率必須 100%）。
# 用法：
#   跑 N 次新鮮 session（headless，opencode run）：
#     powershell -File scripts\tests\test-oracle-gate-runtime.ps1 -Scenario B1 -Runs 30
#     powershell -File scripts\tests\test-oracle-gate-runtime.ps1 -Scenario B3 -Runs 30 -Question "（純 PeopleCode 流程題）"
#     -QuestionFile <本機檔>：一行一題，輪流使用（真實物件名不進 repo，放本機）
#   只分析既有 session（互動 TUI 跑過 20 題後做 P1 探測）：
#     powershell -File scripts\tests\test-oracle-gate-runtime.ps1 -AnalyzeAll [-Since "2026-09-08 09:00"]
#     powershell -File scripts\tests\test-oracle-gate-runtime.ps1 -AnalyzeSession ses_xxx
# 判定（exit 1 ＝ 有違反）：
#   executedTaskBeforePreflight（會查 DB 的 task 在狀態 READY 之前執行）總和 ＝ 0
#   hookMismatch（閘門看到的 task 次數 ≠ transcript 的 task 件數）總和 ＝ 0（task hook 覆蓋率 100%）
#   turnMismatch（閘門看到的 chat.message 次數 ≠ transcript 的 user 訊息數）總和 ＝ 0（每題都有重置）
#   turnInvariantViolations（已執行的 DB task 在「同一 turn 內」找不到先於它的 list_connections 成功＋connect 成功）＝ 0
# 附帶統計（不判定，供觀察模型行為）：blockedRuns＝模型先派 task 被擋的 session 數（＝錯序機率）、
#   preflightRuns＝有依序完成 list→connect 的 session 數（R8：不需要 DB 的題也應為 100%）。
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

# 一個 session 的判讀：回傳 hashtable
function Get-SessionVerdict([string]$SessionId, [string]$OcPath) {
    $rows = @(Read-Jsonl (Join-Path $gateDir ($SessionId + '.jsonl')))
    $before = @($rows | Where-Object { $_.hook -eq 'before' -and $_.tool -eq 'task' })
    $blocked = @($before | Where-Object { $_.decision -eq 'block' })
    $wouldBlock = @($before | Where-Object { $_.decision -eq 'observe-would-block' })
    $executed = @($rows | Where-Object { $_.hook -eq 'after' -and $_.tool -eq 'task' -and $_.executed -eq $true })
    # 會查 DB 的 task 在 READY 之前執行＝違反（observe 模式或閘門退讓時才可能發生）；祖先 READY 放行的子 session 不算
    $ancestorAllowed = (@($before | Where-Object { $_.note -match 'ancestor READY' }).Count -gt 0)
    $early = @($executed | Where-Object { $_.basis -eq 'run_sql:enabled' -and $_.state -ne 'READY' -and -not $ancestorAllowed })
    $afters = @($rows | Where-Object { $_.hook -eq 'after' })
    $listOk = @($afters | Where-Object { $_.tool -eq 'oracleMCP_list_connections' -and $_.ok -eq $true })
    $connOk = @($afters | Where-Object { $_.tool -eq 'oracleMCP_connect' -and $_.next -eq 'READY' })
    $preflight = ($listOk.Count -gt 0 -and $connOk.Count -gt 0)
    # per-turn 不變量：每個已執行的 DB task，同一 turn 內、在它之前必須有 list 成功與 connect→READY
    # turn 識別＝turnId（該則 user 訊息 id；opencode run --session 續接是新行程，數字 turn 會歸零）
    $turnViol = 0
    # 真實 user 訊息才算一題：全部 part 都 synthetic 的（背景 subagent 回灌／compaction 續行）plugin 不重置、這裡也不計
    $chatRows = @($rows | Where-Object { $_.hook -eq 'chat.message' -and $_.synthetic -ne $true })
    function Get-TurnKey($row) { if ($row.turnId) { return [string]$row.turnId } return ([string]$row.pid + '-' + [string]$row.turn) }
    for ($k = 0; $k -lt $rows.Count; $k++) {
        $r = $rows[$k]
        if (-not ($r.hook -eq 'after' -and $r.tool -eq 'task' -and $r.executed -eq $true -and $r.basis -eq 'run_sql:enabled')) { continue }
        $t = Get-TurnKey $r
        $sawList = $false; $sawConn = $false; $viaAncestor = $false
        for ($j = 0; $j -lt $k; $j++) {
            $q = $rows[$j]
            if ((Get-TurnKey $q) -ne $t) { continue }
            # 子 session 靠祖先 READY 放行（subagent_depth > 1 才會發生）：前置在祖先 session 做，本檔不會有 list／connect
            if ($q.hook -eq 'before' -and $q.tool -eq 'task' -and $q.note -match 'ancestor READY') { $viaAncestor = $true }
            if ($q.hook -ne 'after') { continue }
            if ($q.tool -eq 'oracleMCP_list_connections' -and $q.ok -eq $true) { $sawList = $true }
            if ($q.tool -eq 'oracleMCP_connect' -and $q.next -eq 'READY') { $sawConn = $true }
        }
        if (-not ($sawList -and $sawConn) -and -not $viaAncestor) { $turnViol++ }
    }
    $staleBlocks = @($rows | Where-Object { $_.hook -eq 'before' -and $_.tool -eq 'task' -and $_.note -match 'shared connection changed' }).Count
    # transcript 交叉比對：task 工具件數；user 訊息數（每題一次 chat.message）
    $exportedTasks = -1
    $exportedTurns = -1
    $exportErr = ''
    if ($OcPath -ne '') {
        try {
            $json = (& cmd.exe /d /s /c ('"' + $OcPath + '" export ' + $SessionId + ' 2>nul') | Out-String)
            $obj = ConvertFrom-Json $json
            $n = 0
            $u = 0
            $msgs = @()
            if ($null -ne $obj.messages) { $msgs = @($obj.messages) }
            foreach ($m in $msgs) {
                $info = $m.info
                if ($null -eq $info) { $info = $m }
                $msid = $info.sessionID
                $parts = @()
                if ($null -ne $m.parts) { $parts = @($m.parts) }
                if ($info.role -eq 'user' -and ($null -eq $msid -or $msid -eq $SessionId)) {
                    $allSynthetic = ($parts.Count -gt 0)
                    foreach ($pp in $parts) { if ($pp.synthetic -ne $true) { $allSynthetic = $false } }
                    if (-not $allSynthetic) { $u++ }
                }
                foreach ($p in $parts) {
                    if ($p.type -eq 'tool' -and $p.tool -eq 'task') {
                        $sid = $p.sessionID
                        if ($null -eq $sid -or $sid -eq $SessionId) { $n++ }
                    }
                }
            }
            $exportedTasks = $n
            $exportedTurns = $u
        }
        catch { $exportErr = $_.Exception.Message }
    }
    $mismatch = 0
    if ($exportedTasks -ge 0 -and $exportedTasks -ne $before.Count) { $mismatch = 1 }
    $turnMismatch = 0
    if ($exportedTurns -ge 0 -and $exportedTurns -ne $chatRows.Count) { $turnMismatch = 1 }
    return @{
        sessionID = $SessionId; rows = $rows.Count; taskAttempts = $before.Count; blocked = $blocked.Count
        wouldBlock = $wouldBlock.Count; executed = $executed.Count; executedBeforePreflight = $early.Count
        preflight = $preflight; exportedTasks = $exportedTasks; hookMismatch = $mismatch; exportError = $exportErr
        turns = $chatRows.Count; exportedTurns = $exportedTurns; turnMismatch = $turnMismatch
        turnInvariantViolations = $turnViol; staleEpochBlocks = $staleBlocks
        mode = @($rows | Where-Object { $_.mode } | Select-Object -First 1 | ForEach-Object { $_.mode })
    }
}

function Show-Table($verdicts) {
    Write-Host ''
    Write-Host ('{0,-32} {1,5} {2,5} {3,5} {4,5} {5,7} {6,5} {7,5} {8,5} {9,6} {10,8} {11,5}' -f 'sessionID', 'try', 'blk', 'exec', 'early', 'prefl', 'xTask', 'mism', 'turns', 'xTurns', 'turnViol', 'stale')
    foreach ($v in $verdicts) {
        Write-Host ('{0,-32} {1,5} {2,5} {3,5} {4,5} {5,7} {6,5} {7,5} {8,5} {9,6} {10,8} {11,5}' -f $v.sessionID, $v.taskAttempts, $v.blocked, $v.executed, $v.executedBeforePreflight, $v.preflight, $v.exportedTasks, $v.hookMismatch, $v.turns, $v.exportedTurns, $v.turnInvariantViolations, $v.staleEpochBlocks)
    }
}

function Write-Summary($verdicts, [string]$Label) {
    $early = ($verdicts | Measure-Object -Property executedBeforePreflight -Sum).Sum
    $mism = ($verdicts | Measure-Object -Property hookMismatch -Sum).Sum
    $tmism = ($verdicts | Measure-Object -Property turnMismatch -Sum).Sum
    $tviol = ($verdicts | Measure-Object -Property turnInvariantViolations -Sum).Sum
    $stale = ($verdicts | Measure-Object -Property staleEpochBlocks -Sum).Sum
    $blockedRuns = @($verdicts | Where-Object { $_.blocked -gt 0 -or $_.wouldBlock -gt 0 }).Count
    $preflightRuns = @($verdicts | Where-Object { $_.preflight }).Count
    $noTask = @($verdicts | Where-Object { $_.taskAttempts -eq 0 }).Count
    $summary = [pscustomobject]@{
        label = $Label; sessions = $verdicts.Count; executedTaskBeforePreflight = [int]$early; hookMismatch = [int]$mism
        turnMismatch = [int]$tmism; turnInvariantViolations = [int]$tviol; staleEpochBlocks = [int]$stale
        blockedRuns = $blockedRuns; preflightRuns = $preflightRuns; sessionsWithoutTask = $noTask
        stamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }
    $out = Join-Path $gateDir ('summary-' + $Label + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    [System.IO.File]::WriteAllText($out, (ConvertTo-Json $summary -Depth 3), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ''
    Write-Host ('sessions=' + $verdicts.Count + '  executedTaskBeforePreflight=' + [int]$early + '  hookMismatch=' + [int]$mism +
        '  turnMismatch=' + [int]$tmism + '  turnInvariantViolations=' + [int]$tviol + '  staleEpochBlocks=' + [int]$stale + '（共用連線被別人改動而重做前置，觀察值）')
    Write-Host ('blockedRuns=' + $blockedRuns + '（模型先派 task 被擋）  preflightRuns=' + $preflightRuns + '  sessionsWithoutTask=' + $noTask)
    Write-Host ('摘要已寫：' + $out)
    if ([int]$early -gt 0 -or [int]$mism -gt 0 -or [int]$tmism -gt 0 -or [int]$tviol -gt 0) {
        Write-Host '判定：FAIL（DB 委派先於前置執行／task hook 覆蓋率不足／有 turn 沒收到重置／同 turn 內找不到 list→connect）' -ForegroundColor Red
        return 1
    }
    Write-Host '判定：PASS（executed task before preflight = 0；task／turn hook 覆蓋率 100%；每個已執行的 DB task 同 turn 內都有 list→connect）' -ForegroundColor Green
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
    if (-not $p.WaitForExit($TimeoutMin * 60 * 1000)) {
        & taskkill.exe /PID $p.Id /T /F 2>$null | Out-Null
        Write-Host ('  逾時（' + $TimeoutMin + ' 分）強殺') -ForegroundColor Yellow
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
        $verdicts += @{ sessionID = ('(run ' + $i + ' no-session)'); rows = 0; taskAttempts = 0; blocked = 0; wouldBlock = 0; executed = 0; executedBeforePreflight = 0; preflight = $false; exportedTasks = -1; hookMismatch = 0; exportError = 'no sessionID'; turns = 0; exportedTurns = -1; turnMismatch = 0; turnInvariantViolations = 0; staleEpochBlocks = 0; mode = '' }
        if (-not $KeepGoing) { break }
        continue
    }
    $v = Get-SessionVerdict $sessionId $ocPath
    $verdicts += $v
    Write-Host ('  ' + $sessionId + '  task嘗試=' + $v.taskAttempts + ' 被擋=' + $v.blocked + ' 執行=' + $v.executed + ' 早於前置=' + $v.executedBeforePreflight + ' 前置完成=' + $v.preflight + ' transcript task=' + $v.exportedTasks + ' turns=' + $v.turns + '/' + $v.exportedTurns + ' turnViol=' + $v.turnInvariantViolations)
    if (($v.executedBeforePreflight -gt 0 -or $v.turnInvariantViolations -gt 0) -and -not $KeepGoing) { Write-Host '  違反：DB 委派先於前置執行——停止（加 -KeepGoing 可續跑）' -ForegroundColor Red; break }
}
Show-Table $verdicts
exit (Write-Summary $verdicts $Scenario)
