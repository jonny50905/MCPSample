# ps-bizspec.ps1 — /ps-spec 的業務需求文件流程（BIZ1）。寫手 session 照 <框架>/peoplesoft/bizspec/standard.md 寫業務需求文件；
# 外環逐字比對證據、退回修正、補查（只查「該問誰＝Spec 產製端」的開放假設）、回填、套用業務窗口回覆。PowerShell 5.1；公司機資料只留本機。
# 輸入 .ps-private/bizspec/<job>/（status.md、project.md、answers.md）＋知識層 docs/ps-research/；執行狀態 .ps-runtime/bizspec/<job>/；
# 產出 docs/ps-spec/<job>/（寫手寫）與 docs/ps-spec/<job>/evidence/（只有補查 session 寫）。OpenCode 版（-Cli opencode，或資料夾只有 .opencode/peoplesoft）
# 上面各目錄與 log 目錄加 -opencode；模型讀 .opencode/peoplesoft/sdoc/model.yaml（-Model 可臨時覆寫）。最後一行一律是結論碼（BIZ1-…）。
# 每次執行依產出現況決定下一步（寫作 → 檢查 → 修正 → 套回覆 → 補查 → 回填 → 檢查），中斷後同命令續跑。
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Components,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$MoreComponents = @(),
    [string]$Root = '',
    [switch]$Status,
    [ValidateRange(1, 100)][int]$MaxSessions = 6,
    [ValidateRange(1, 180)][int]$TimeoutMin = 60,
    [string]$Model = '',
    [string]$Cli = '',
    [switch]$NoQuery,
    [switch]$Retry,
    [string]$FakeWriter = '',
    [string]$FakeQuery = '',
    [switch]$Diag
)
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'ps-knowledge-lib.ps1')
    . (Join-Path $PSScriptRoot 'ps-session-lib.ps1')
    . (Join-Path $PSScriptRoot 'ps-bizspec-lib.ps1')
}
catch { Write-Host ('共用腳本載入失敗，請核對搬運清單與 UTF-8 BOM：' + $_.Exception.Message); Write-Host 'BIZ1-9-02'; exit 2 }

$script:BzSkeletonMark = '<!-- BIZSPEC:SKELETON -->'
$script:BzMaxFix = 3
$script:BzMaxStepTries = 3
$script:BzWriteLines = 30
$script:BzFixBatch = 20
$script:BzAnswerBatch = 5
# 寫作步驟：照規範「寫作順序」，一個 session 只做一項；progress.md 的勾選項就是這張清單
$script:BzSteps = @('02-spec-overview.md', '03-reading-guide.md', '05-3-data.md', '05-4-rules.md', '05-5-states.md', '05-7-interfaces.md', '05-6-permissions.md',
    '05-1-flows.md', '05-2-screens.md', '09-acceptance.md', '05-8-coverage.md', '04-requirement-index.md', '06-tracking.md', '07-assumptions.md', '10-evidence.md',
    '01-goals.md', '08-spec-change.md', 'appendix.md', 'README.md', '完成前自我檢查')
# 每一步要讀的規範段落（Get-PsBzStandardRanges 的鍵）
$script:BzStepSections = @{
    '02-spec-overview.md' = @('general', 'ch2', 'ch10'); '03-reading-guide.md' = @('general', 'ch3', 'ch7a', 'ch10')
    '05-3-data.md' = @('general', 'ch5common', 'ch5.3', 'ch7a', 'ch10'); '05-4-rules.md' = @('general', 'ch5common', 'ch5.4', 'ch7a', 'ch10')
    '05-5-states.md' = @('general', 'ch5common', 'ch5.5', 'ch7a', 'ch10'); '05-7-interfaces.md' = @('general', 'ch5common', 'ch5.7', 'ch7a', 'ch10')
    '05-6-permissions.md' = @('general', 'ch5common', 'ch5.6', 'ch7a', 'ch10'); '05-1-flows.md' = @('general', 'ch5common', 'ch5.1', 'ch7a', 'ch10')
    '05-2-screens.md' = @('general', 'ch5common', 'ch5.2', 'ch7a', 'ch10'); '09-acceptance.md' = @('general', 'ch9', 'ch7a', 'ch10')
    '05-8-coverage.md' = @('general', 'ch5common', 'ch5.8', 'ch7a'); '04-requirement-index.md' = @('general', 'ch4', 'ch10')
    '06-tracking.md' = @('general', 'ch6'); '07-assumptions.md' = @('general', 'ch7', 'ch10'); '10-evidence.md' = @('general', 'ch10')
    '01-goals.md' = @('general', 'ch1'); '08-spec-change.md' = @('general', 'ch8'); 'appendix.md' = @('general', 'appendix'); 'README.md' = @('general', 'ch0')
    '完成前自我檢查' = @('general', 'selfcheck'); 'FIX' = @('general', 'ch7a', 'ch10'); 'ANSWER' = @('general', 'ch7'); 'BACKFILL' = @('general', 'ch7', 'ch10')
}
$script:BzSectionNames = @{ general = '通用規則'; ch0 = '第 0 章'; ch1 = '第 1 章'; ch2 = '第 2 章'; ch3 = '第 3 章'; ch4 = '第 4 章'; ch5common = '第 5 章共通規則'
    'ch5.1' = '5.1'; 'ch5.2' = '5.2'; 'ch5.3' = '5.3'; 'ch5.4' = '5.4'; 'ch5.5' = '5.5'; 'ch5.6' = '5.6'; 'ch5.7' = '5.7'; 'ch5.8' = '5.8'
    ch6 = '第 6 章'; ch7 = '第 7 章'; ch7a = '7.1～7.2（缺口與假設登記、暫定做法表）'; ch8 = '第 8 章'; ch9 = '第 9 章'; ch10 = '第 10 章（證據）'; appendix = '附錄'; selfcheck = '完成前自我檢查' }
$script:BzMaxQueryTries = 2
$script:BzMaxKnowledgeList = 40

# ---------------- 檔案 ----------------
function Get-BzRel([string]$Path) { return ($Path.Substring($J.Root.Length).TrimStart('\', '/') -replace '\\', '/') }
function Get-BzText([string]$Path) { return (Read-PsKnText -LiteralPath $Path) }
function Write-BzText([string]$Path, [string]$Text) { if (-not (Write-PsKnAtomicText -LiteralPath $Path -Text $Text)) { throw 'BZ_WRITE_DEFERRED' } }
function Get-BzFiles([string]$Dir) {
    $out = @()
    if ([System.IO.Directory]::Exists($Dir)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $Dir -File -Recurse -Force)) {
            if (($f.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw '不支援 reparse point 的工作目錄。' }
            $out += $f.FullName
        }
    }
    return , $out
}
function Get-BzNumber([string]$Dir, [string]$Pattern) {
    $n = 0
    if ([System.IO.Directory]::Exists($Dir)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Force)) { $m = [regex]::Match($f.Name, $Pattern); if ($m.Success) { $n = [Math]::Max($n, [int]$m.Groups[1].Value) } }
    }
    return $n
}
function Test-BzSamePath([string]$A, [string]$B) {
    if ($A -eq '' -or $B -eq '') { return $false }
    $fa = [System.IO.Path]::GetFullPath($A); $fb = [System.IO.Path]::GetFullPath($B)
    if ([System.IO.Path]::DirectorySeparatorChar -eq [char]92) { return [string]::Equals($fa, $fb, [System.StringComparison]::OrdinalIgnoreCase) }
    return [string]::Equals($fa, $fb, [System.StringComparison]::Ordinal)
}

# ---------------- 工作狀態（job.json）與補查帳本（queries.json） ----------------
function Read-BzJson([string]$Path) {
    $t = Get-BzText $Path
    if ($null -eq $t -or $t.Trim() -eq '') { return $null }
    try { return ($t | ConvertFrom-Json) } catch { throw ('JSON 損壞，保留現場：' + (Get-BzRel $Path)) }
}
function Read-BzJob {
    $o = Read-BzJson $J.JobPath
    $job = @{ fix = 0; lastFindings = -1; stepTries = @{}; answerTries = @{}; backfillTries = 0; phase = '' }
    if ($null -ne $o) {
        if ($null -ne $o.fix) { $job.fix = [int]$o.fix }
        if ($null -ne $o.lastFindings) { $job.lastFindings = [int]$o.lastFindings }
        if ($null -ne $o.backfillTries) { $job.backfillTries = [int]$o.backfillTries }
        if ($null -ne $o.stepTries) { foreach ($p in $o.stepTries.PSObject.Properties) { $job.stepTries[$p.Name] = [int]$p.Value } }
        if ($null -ne $o.answerTries) { foreach ($p in $o.answerTries.PSObject.Properties) { $job.answerTries[$p.Name] = [int]$p.Value } }
        if ($null -ne $o.phase) { $job.phase = [string]$o.phase }
    }
    return $job
}
function ConvertTo-BzSortedCounts($Map) { $o = [ordered]@{}; foreach ($k in (Sort-PsKnOrdinal -Items @($Map.Keys))) { if ($null -ne $k) { $o[$k] = [int]$Map[$k] } }; return $o }
function Write-BzJob($Job) {
    $o = [ordered]@{ schemaVersion = 1; jobId = $J.JobId; components = @($J.Names); phase = [string]$Job.phase; fix = [int]$Job.fix; lastFindings = [int]$Job.lastFindings
        backfillTries = [int]$Job.backfillTries; stepTries = (ConvertTo-BzSortedCounts $Job.stepTries); answerTries = (ConvertTo-BzSortedCounts $Job.answerTries); updatedAt = (Get-PsKnUtcStamp) }
    Write-BzText $J.JobPath ((ConvertTo-PsKnJson -Value $o) + "`n")
}
function Read-BzLedger {
    $o = Read-BzJson $J.LedgerPath
    $led = @{ entries = @(); failed = @{} }
    if ($null -ne $o) {
        foreach ($e in @($o.entries)) { if ($null -ne $e) { $led.entries += @{ assumption = [string]$e.assumption; file = [string]$e.file; sha = [string]$e.sha; conclusion = [string]$e.conclusion; at = [string]$e.at } } }
        if ($null -ne $o.failed) { foreach ($p in $o.failed.PSObject.Properties) { $led.failed[$p.Name] = [int]$p.Value } }
    }
    return $led
}
function Write-BzLedger($Led) {
    $entries = @(); foreach ($e in $Led.entries) { $entries += [ordered]@{ assumption = $e.assumption; file = $e.file; sha = $e.sha; conclusion = $e.conclusion; at = $e.at } }
    $failed = [ordered]@{}; foreach ($k in (Sort-PsKnOrdinal -Items @($Led.failed.Keys))) { if ($null -ne $k) { $failed[$k] = [int]$Led.failed[$k] } }
    Write-BzText $J.LedgerPath ((ConvertTo-PsKnJson -Value ([ordered]@{ schemaVersion = 1; entries = $entries; failed = $failed })) + "`n")
}
function Get-BzLedgerMap($Led) { $m = @{}; foreach ($e in $Led.entries) { $m[$e.file] = $e.sha }; return $m }

# ---------------- 輸入 ----------------
function Initialize-BzInputs {
    # 缺檔就建骨架（不覆寫既有檔）；同一組 Component 的 Spec 文件流程（DOC1）已有狀態圖就複製一份。
    [void][System.IO.Directory]::CreateDirectory($J.InputRoot)
    $st = Join-Path $J.InputRoot 'status.md'
    if (-not [System.IO.File]::Exists($st)) {
        $old = Get-BzText (Join-Path (Join-Path (Join-Path $J.Root ('.ps-private/sdoc' + $J.Sfx)) ('clone-' + $J.Hash)) 'status.md')
        if ($null -ne $old -and -not $old.Contains('<!-- SDOC:SKELETON -->')) {
            if (Write-PsKnCreateOnlyText -LiteralPath $st -Text $old) { Write-Host ('已從 Spec 文件流程同一組 Component 的輸入複製 status.md 到 ' + (Get-BzRel $J.InputRoot) + '/。') }
        }
    }
    $files = [ordered]@{
        'status.md' = @($script:BzSkeletonMark, '# 狀態圖（選填）', '',
            '把這組 Component 的狀態圖貼在這裡（Mermaid 或文字都可以），圖下方可寫各階段誰做什麼。', '',
            '貼好後刪掉第一行的 BIZSPEC:SKELETON 標記。沒有狀態圖就保留標記，外環只用知識層與其他輸入。') -join "`n"
        'project.md' = @($script:BzSkeletonMark, '# 專案輸入（選填）', '', '## 業務名稱', '', '## 本期目標', '',
            '## 補充說明（業務規則、範圍、例外，寫業務語言；不寫人名）', '', '填好後刪掉第一行的 BIZSPEC:SKELETON 標記。') -join "`n"
        'answers.md' = @('# 業務窗口回覆', '', '假設編號以業務需求文件 07-assumptions.md 為準；回覆人只寫代稱；日期寫 YYYY-MM-DD。填好後用相同命令續跑，外環會請寫手照第 7 章 7.4 關閉。', '',
            ('| ' + ($script:PsBzAnswerHeader -join ' | ') + ' |'), '|---|---|---|---|') -join "`n"
    }
    foreach ($name in $files.Keys) {
        $p = Join-Path $J.InputRoot $name
        if (-not [System.IO.File]::Exists($p)) { [void](Write-PsKnCreateOnlyText -LiteralPath $p -Text ($files[$name] + "`n")) }
    }
}
function Get-BzHumanSources {
    $out = @()
    foreach ($n in @('status.md', 'project.md')) {
        $t = Get-BzText (Join-Path $J.InputRoot $n)
        if ($null -ne $t -and -not $t.Contains($script:BzSkeletonMark) -and $t.Trim() -ne '') { $out += ((Get-BzRel $J.InputRoot) + '/' + $n) }
    }
    return , $out
}
function Find-BzKnowledge {
    # docs/ps-research 底下提到這組 Component 任一名稱的 .md（不分大小寫；knowledge/ 索引快取除外）
    $dir = Join-Path $J.Root 'docs/ps-research'
    $out = @()
    if (-not [System.IO.Directory]::Exists($dir)) { return , $out }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Recurse -Filter '*.md')) {
        $rel = Get-BzRel $f.FullName
        if ($rel -like 'docs/ps-research/knowledge/*') { continue }
        $t = Get-BzText $f.FullName
        if ($null -eq $t) { continue }
        foreach ($n in $J.Names) { if ($t.IndexOf($n, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $out += $rel; break } }
    }
    return , (Sort-PsKnOrdinal -Items $out)
}

# ---------------- 工單 ----------------
function New-BzOrder([string]$Kind, [string[]]$Body) {
    $n = (Get-BzNumber $J.OrderDir '^o([0-9]{4,8})\.md$') + 1
    $id = 'o' + $n.ToString('0000')
    $kn = @($J.Knowledge)
    $knLines = @()
    foreach ($k in ($kn | Select-Object -First $script:BzMaxKnowledgeList)) { $knLines += ('  - ' + $k) }
    if ($kn.Count -gt $script:BzMaxKnowledgeList) { $knLines += ('  - 其餘 ' + ($kn.Count - $script:BzMaxKnowledgeList) + ' 個檔：以知識層索引定位') }
    if ($kn.Count -eq 0) { $knLines += '  - （知識層沒有提到這組 Component 的檔）' }
    $hs = Get-BzHumanSources
    $hsText = '（人工輸入都還是骨架）'; if ($hs.Count -gt 0) { $hsText = ($hs -join '、') }
    $q = '不可用'; if (-not $NoQuery) { $q = '可用' }
    $lines = @(('# 工單 ' + $id + '（' + $Kind + '）'), '',
        ('- 規範：' + $J.StandardRel),
        ('- 來源資料夾：' + (Get-BzRel $J.InputRoot) + '（人工輸入，唯讀；已填的檔：' + $hsText + '）'),
        '- 其他可引用位置：docs/ps-research（知識層，唯讀；先讀 docs/ps-research/knowledge/index.md 定位）。提到這組 Component 的檔：') + $knLines + @(
        ('- 輸出資料夾：' + (Get-BzRel $J.OutputRoot)),
        ('- 補查：' + $q),
        ('- Component：' + ($J.Names -join '、')),
        ('- 證據的位置一律寫從專案根目錄起算的路徑，例：' + (Get-BzRel $J.InputRoot) + '/status.md §…、docs/ps-research/<領域>/<檔名>.md §…。'),
        '', '## 這次要做', '') + $Body
    Write-BzText (Join-Path $J.OrderDir ($id + '.md')) ((($lines | ForEach-Object { [string]$_ }) -join "`n") + "`n")
    return $id
}

# ---------------- session 與圍欄 ----------------
function Get-BzFence([string[]]$Dirs) {
    $map = @{}
    foreach ($d in $Dirs) { foreach ($p in (Get-BzFiles $d)) { $map[$p] = [System.IO.File]::ReadAllBytes($p) } }
    return , $map
}
function Restore-BzFence($Snapshot, [string[]]$Dirs, [string[]]$Allowed) {
    # 快照裡的檔被改或刪 → 原樣還原；快照外新出現的檔（不在 Allowed）→ 移到 quarantine。回傳違規的相對路徑。
    $violations = @()
    foreach ($p in @($Snapshot.Keys)) {
        $now = $null; if ([System.IO.File]::Exists($p)) { $now = [System.IO.File]::ReadAllBytes($p) }
        if ($null -ne $now -and [Convert]::ToBase64String($now) -ceq [Convert]::ToBase64String($Snapshot[$p])) { continue }
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($p))
        [System.IO.File]::WriteAllBytes($p, $Snapshot[$p])
        $violations += (Get-BzRel $p)
    }
    foreach ($d in $Dirs) {
        foreach ($p in (Get-BzFiles $d)) {
            if ($Snapshot.ContainsKey($p)) { continue }
            $ok = $false; foreach ($a in @($Allowed)) { if (Test-BzSamePath $p $a) { $ok = $true; break } }
            if ($ok) { continue }
            $qd = Join-Path $J.RuntimeRoot 'quarantine'
            [void][System.IO.Directory]::CreateDirectory($qd)
            [System.IO.File]::Move($p, (Join-Path $qd ([guid]::NewGuid().ToString('N') + '-' + [System.IO.Path]::GetFileName($p))))
            $violations += (Get-BzRel $p)
        }
    }
    return , $violations
}
function Invoke-BzSession([string]$Agent, [string]$OrderId, [string]$Kind, [string]$Fake) {
    Write-Host ('派工 ' + $OrderId + '：' + $Kind)
    $orderPath = Join-Path $J.OrderDir ($OrderId + '.md')
    try {
        if ($Fake -ne '') {
            $global:LASTEXITCODE = 0
            $null = (& $Fake -OrderPath $orderPath -Kind $Kind -Root $J.Root -OutputRoot $J.OutputRoot *>&1 | ForEach-Object { [string]$_ })
            return @{ ExitCode = [int]$LASTEXITCODE; TimedOut = $false; SlotBusy = $false; FailureKind = 'NONE'; ApiKind = 'NONE' }
        }
        return (Invoke-PsOcSession -OcPath $J.OcPath -Root $J.Root -LogRoot $J.LogRoot -Model $J.Model -ExtraArgs ('--agent ' + $Agent) -PromptText ($J.JobId + '/' + $OrderId) -TimeoutMin $TimeoutMin -Tag ($J.JobId + '-' + $OrderId) -Log { param($msg) Write-Host $msg } -SlotWaitMin 0 -TimeoutParamName 'TimeoutMin' -EnvDefaults (Get-PsOcClaudeEnvDefaults -Agent $Agent))
    }
    catch { Write-Host ('session 未完成：' + $_.Exception.Message); return @{ ExitCode = -1; TimedOut = $false; SlotBusy = $false; FailureKind = 'DISPATCH_ERROR'; ApiKind = 'NONE' } }
}
function Test-BzSessionFailed($Sr) { return ([bool]$Sr.TimedOut -or [int]$Sr.ExitCode -ne 0 -or (@('', 'NONE') -notcontains [string]$Sr.FailureKind)) }

# ---------------- 檢查 ----------------
function Get-BzCheckContext {
    $led = Read-BzLedger
    return @{ Root = $J.Root; FileRoots = @(((Get-BzRel $J.InputRoot) + '/'), 'docs/ps-research/'); EvidenceRel = ((Get-BzRel $J.EvidenceDir) + '/'); Ledger = (Get-BzLedgerMap $led) }
}
function Invoke-BzCheckNow {
    $r = Invoke-PsBzCheck -OutDir $J.OutputRoot -Ctx (Get-BzCheckContext)
    $J.LastStats = $r.Stats
    return $r
}

# ---------------- 輸出骨架與規範段落 ----------------
function Initialize-BzOutput {
    # 第一次寫之前由外環建 progress.md（勾選清單＝寫作步驟）與 10-evidence.md 的表頭；已有就不動
    [void][System.IO.Directory]::CreateDirectory($J.OutputRoot)
    $pp = Join-Path $J.OutputRoot 'progress.md'
    if (-not [System.IO.File]::Exists($pp)) {
        $items = @(); foreach ($st in $script:BzSteps) { $items += ('- [ ] ' + $st) }
        $lines = @('# 進度', ('來源：' + (Get-BzRel $J.InputRoot)), ('輸出：' + (Get-BzRel $J.OutputRoot)), '', '## 勾選') + $items + @('',
            '## 預留需求鍵', '| 需求鍵 | 摘要 | 來源 | 被誰引用 |', '|---|---|---|---|', '', '## 待歸類', '', '## 自我檢查', '')
        [void](Write-PsKnCreateOnlyText -LiteralPath $pp -Text (($lines -join "`n") + "`n"))
    }
    $ep = Join-Path $J.OutputRoot '10-evidence.md'
    if (-not [System.IO.File]::Exists($ep)) {
        $lines = @('# 10 證據', '', '## 10.1 證據清單', '', ('| ' + ($script:PsBzEvidenceHeader -join ' | ') + ' |'), '|---|---|---|---|')
        [void](Write-PsKnCreateOnlyText -LiteralPath $ep -Text (($lines -join "`n") + "`n"))
    }
}
function Get-BzReadLines([string]$Key) {
    # 工單的「規範要讀的段落」：段落名稱與行號（1 起算）
    if ($null -eq $J.Ranges) { $J.Ranges = Get-PsBzStandardRanges (Get-BzText (Join-Path $J.Root $J.StandardRel)) }
    $out = @()
    foreach ($sec in @($script:BzStepSections[$Key])) {
        if (-not $J.Ranges.ContainsKey($sec)) { continue }
        $r = $J.Ranges[$sec]
        $out += ('  - ' + $script:BzSectionNames[$sec] + '：第 ' + $r[0] + '～' + $r[1] + ' 行')
    }
    return , $out
}
function Get-BzReadHeader([string]$Key) {
    return , (@(('- 先讀規範 ' + $J.StandardRel + ' 的這幾段（用行號分段讀，不要整份讀；其他章不用讀）：')) + (Get-BzReadLines $Key))
}

# ---------------- 下一步 ----------------
function Test-BzStepDone([string]$Step) {
    # 打勾才算完成；完成前自我檢查另要有「自我檢查：通過」那一行
    $done = Test-PsBzItemChecked (Get-PsBzCheckedItems $J.OutputRoot) $Step
    if ($done -and $Step -eq '完成前自我檢查') { $done = (Get-PsBzProgress $J.OutputRoot).SelfCheck }
    return $done
}
function Get-BzNext($Job) {
    foreach ($st in $script:BzSteps) {
        if (Test-BzStepDone $st) { continue }
        $t = 0; if ($Job.stepTries.ContainsKey($st)) { $t = [int]$Job.stepTries[$st] }
        if ($t -ge $script:BzMaxStepTries) { return @{ Kind = 'BLOCKED'; Reason = ('「' + $st + '」連續 ' + $t + ' 個 session 沒有完成（progress.md 沒打勾）') } }
        return @{ Kind = 'WRITE'; Step = $st }
    }
    $chk = Invoke-BzCheckNow
    $nf = @($chk.Findings).Count
    if ($nf -gt 0) {
        if ($Job.lastFindings -lt 0 -or $nf -lt [int]$Job.lastFindings) { $Job.fix = 0 }
        $Job.lastFindings = $nf
        if ($Job.fix -ge $script:BzMaxFix) { return @{ Kind = 'BLOCKED'; Reason = ('外環檢查連續 ' + $script:BzMaxFix + ' 輪修正後問題數沒有減少'); Findings = $chk.Findings } }
        return @{ Kind = 'FIX'; Findings = $chk.Findings }
    }
    $Job.fix = 0; $Job.lastFindings = -1
    $assump = Get-PsBzAssumptions $J.OutputRoot
    $open = @{}; foreach ($a in $assump) { if ($a.State -ceq '開放') { $open[$a.Id] = $a } }
    $ans = @()
    foreach ($x in (Get-PsBzAnswers (Get-BzText (Join-Path $J.InputRoot 'answers.md')))) {
        if ($open.ContainsKey($x.Id) -and $ans -cnotcontains $x.Id -and $ans.Count -lt $script:BzAnswerBatch) {
            $tries = 0; if ($Job.answerTries.ContainsKey($x.Id)) { $tries = [int]$Job.answerTries[$x.Id] }
            if ($tries -lt 2) { $ans += $x.Id }
        }
    }
    if ($ans.Count -gt 0) { return @{ Kind = 'ANSWER'; Ids = $ans } }
    $led = Read-BzLedger
    $queried = @{}; foreach ($e in $led.entries) { $queried[$e.assumption] = $true }
    if (-not $NoQuery) {
        foreach ($id in (Sort-PsKnOrdinal -Items @($open.Keys))) {
            if ($null -eq $id) { continue }
            $a = $open[$id]
            if ($a.Owner -cne 'Spec 產製端' -or $queried.ContainsKey($id)) { continue }
            $f = 0; if ($led.failed.ContainsKey($id)) { $f = [int]$led.failed[$id] }
            if ($f -ge $script:BzMaxQueryTries) { continue }
            return @{ Kind = 'QUERY'; Assumption = $a }
        }
    }
    $listed = Get-PsBzQueryRows $J.OutputRoot
    $pending = @(); foreach ($e in $led.entries) { if (-not $listed.ContainsKey([System.IO.Path]::GetFileName($e.file).ToLowerInvariant())) { $pending += $e } }
    if ($pending.Count -eq 0) { $Job.backfillTries = 0 }
    if ($pending.Count -gt 0) {
        if ($Job.backfillTries -ge 2) { return @{ Kind = 'BLOCKED'; Reason = '同一個補查檔回填兩次後 10.2 仍沒有列出' } }
        return @{ Kind = 'BACKFILL'; Entries = @($pending[0]) }
    }
    if ($open.Count -gt 0) { return @{ Kind = 'DONE'; Phase = 'NEEDS_ANSWERS'; Open = $open.Count } }
    return @{ Kind = 'DONE'; Phase = 'REVIEW_READY'; Open = 0 }
}

# ---------------- 各步驟 ----------------
function Invoke-BzWriterStep($Next, $Job) {
    $kind = $Next.Kind
    $body = @()
    $limit = ('- 每次寫入不超過 ' + $script:BzWriteLines + ' 行：新檔先寫檔頭與第一段，之後在檔尾追加下一段；在 10-evidence.md 登證據也一樣在表末追加。寫完不要再讀回整份檔。')
    if ($kind -eq 'WRITE') {
        $st = $Next.Step
        $tag = $st
        if ($st -eq '完成前自我檢查') {
            $body = @('- 這次只做：完成前自我檢查（progress.md 的最後一項）。') + (Get-BzReadHeader $st) + @(
                '- 一次查一項：查完就在 progress.md「## 自我檢查」節追加一行「第 N 項：通過」或「第 N 項：已修〈改了什麼〉」，再查下一項；不要先把全部檔讀完再寫。',
                '- 這一節已經有結果的項目不重查，從下一項接著做。',
                '- 全部查完後在同一節寫「自我檢查：通過；修正項：〈項號，無則寫無〉」，並把「完成前自我檢查」打勾。',
                $limit)
        }
        else {
            $body = @(('- 這次只做：' + $st + '（progress.md 的這一項）。做完把這一項打勾就結束，不接著做下一項。')) + (Get-BzReadHeader $st) + @(
                ('- ' + $st + ' 已經存在（上一個 session 沒寫完）→ 只讀它的最後一段，從沒寫完的地方接著寫，不重寫已寫的部分。'),
                '- 這一項要用到前面自己寫過的檔時，只讀需要的那幾列（例：需求鍵、證據編號），不整份重讀。',
                '- 來源只讀這一項需要的段落：先看檔名與標題定位，再讀對應的節。',
                $limit,
                '- 只談業務需求，不寫系統設計；每條需求先在 10-evidence.md 登證據再寫。')
        }
        $t = 0; if ($Job.stepTries.ContainsKey($st)) { $t = [int]$Job.stepTries[$st] }
        $Job.stepTries[$st] = $t + 1
    }
    elseif ($kind -eq 'FIX') {
        $n = (Get-BzNumber $J.CheckDir '^c([0-9]{4,8})\.md$') + 1
        $cp = Join-Path $J.CheckDir ('c' + $n.ToString('0000') + '.md')
        Write-BzText $cp (ConvertTo-PsBzFindingsMd -Findings $Next.Findings -Title ('外環檢查 c' + $n.ToString('0000')) -Max $script:BzFixBatch)
        $body = @(('- 外環檢查沒過：讀 ' + (Get-BzRel $cp) + '，只修表列的項目（一次最多 ' + $script:BzFixBatch + ' 項，其餘下一輪再給）。')) + (Get-BzReadHeader 'FIX') + @(
            '- BZ_EV_EXCERPT／BZ_EV_LENGTH：回到位置所指的檔，從同一行逐字照抄；檔裡真的沒有 → 刪掉這筆證據與只靠它的需求，改登記假設（第 7 章）。',
            '- BZ_REF_*、BZ_REQ_NO_EVIDENCE、BZ_ASSUMP_NO_EVIDENCE：補登證據或補上引用；沒人引用的證據刪掉。',
            '- BZ_FILE_MISSING、BZ_HEADER_MISSING：照規範補檔、補表頭。',
            '- 一項一項修，每修一項就存檔；只改有問題的列，不重寫其他內容。',
            $limit)
        $Job.fix = [int]$Job.fix + 1
    }
    elseif ($kind -eq 'ANSWER') {
        $body = @(('- 業務窗口在 ' + (Get-BzRel (Join-Path $J.InputRoot 'answers.md')) + ' 回覆了下列假設：' + ($Next.Ids -join '、') + '。')) + (Get-BzReadHeader 'ANSWER') + @(
            '- 照規範第 7 章 7.4 逐筆關閉：關閉依據寫「〈日期〉〈回覆人代稱〉：〈結論一句〉」；把結論寫進受影響需求；確認狀態與追蹤表照 7.4 同步。',
            '- 業務窗口的回覆不登證據；回覆與來源衝突時照 7.4 第 5 步處理。一筆一筆做，只改受影響的列。',
            $limit)
        foreach ($id in $Next.Ids) { $t = 0; if ($Job.answerTries.ContainsKey($id)) { $t = [int]$Job.answerTries[$id] }; $Job.answerTries[$id] = $t + 1 }
    }
    elseif ($kind -eq 'BACKFILL') {
        $e = $Next.Entries[0]
        $body = @(('- 外環補查完成：照規範第 10 章 10.3 回填補查檔 ' + $e.file + '（' + $e.assumption + '，結論：' + $e.conclusion + '；只讀，不改）。')) + (Get-BzReadHeader 'BACKFILL') + @(
            '- 這個補查檔在 10.2 寫一列。只改受影響的列。', $limit)
        $Job.backfillTries = [int]$Job.backfillTries + 1
    }
    Write-BzJob $Job
    $id = New-BzOrder $kind $body
    $dirs = @($J.InputRoot, $J.EvidenceDir, $J.JobRoot)
    $fence = Get-BzFence $dirs
    $sr = Invoke-BzSession 'ps-bizspec-writer' $id $kind $FakeWriter
    $viol = Restore-BzFence $fence $dirs @()
    if (@($viol).Count -gt 0) { $J.Gaps += ('寫手改了不准改的檔，已還原／隔離：' + (@($viol | Select-Object -First 5) -join '、')) }
    if ($kind -eq 'WRITE') {
        $st = $Next.Step
        if (Test-BzStepDone $st) { $Job.stepTries[$st] = 0 }
        elseif (Test-BzSessionFailed $sr) { $Job.stepTries[$st] = [Math]::Max(0, [int]$Job.stepTries[$st] - 1) }
    }
    Write-BzJob $Job
    return $sr
}
function Invoke-BzQueryStep($Next, $Job) {
    $a = $Next.Assumption
    $rel = (Get-BzRel $J.EvidenceDir) + '/Q-' + $a.Id + '.md'
    $target = Join-Path $J.Root $rel
    $ev = Read-PsBzEvidence $J.OutputRoot
    $ctx = @()
    foreach ($m in $script:PsBzEvidenceIdRx.Matches([string]$a.Missing)) {
        if ($ev.ById.ContainsKey($m.Value)) { $it = $ev.ById[$m.Value]; $ctx += ('  - ' + $it.Id + '：' + $it.Location + '：' + $it.Excerpt) }
    }
    if ($ctx.Count -eq 0) { $ctx += '  - （沒有相關證據）' }
    $body = @(('- 契約：' + $J.QueryContractRel),
        ('- 假設：' + $a.Id + '（' + $a.Kind + '）'),
        ('- 缺什麼：' + $a.Missing),
        ('- 暫定做法：' + $a.Provisional),
        ('- 影響的需求鍵：' + $a.Keys),
        '- 相關證據：') + $ctx + @(('- 輸出檔：' + $rel + '（只寫這一個檔）'), '',
        '向舊系統補查這一件事，照契約寫補查結果檔。查不到就照實寫「查無」；查詢工具故障就寫「查詢失敗」。')
    $id = New-BzOrder 'QUERY' $body
    $dirs = @($J.InputRoot, $J.OutputRoot, $J.JobRoot)
    $fence = Get-BzFence $dirs
    $sr = Invoke-BzSession 'ps-bizspec-query' $id 'QUERY' $FakeQuery
    $viol = Restore-BzFence $fence $dirs @($target)
    if (@($viol).Count -gt 0) { $J.Gaps += ('補查 session 改了不准改的檔，已還原／隔離：' + (@($viol | Select-Object -First 5) -join '、')) }
    $led = Read-BzLedger
    $text = Get-BzText $target
    $chk = Test-PsBzQueryFile $text
    if ($null -ne $text -and $chk.Ok) {
        $led.entries += @{ assumption = $a.Id; file = $rel; sha = (Get-PsKnTextHash -Text $text); conclusion = $chk.Conclusion; at = (Get-PsKnUtcStamp) }
        Write-BzText (Join-Path $J.QueryCopyDir ('Q-' + $a.Id + '.md')) $text
        Write-Host ('補查 ' + $a.Id + '：' + $chk.Conclusion)
    }
    else {
        $f = 0; if ($led.failed.ContainsKey($a.Id)) { $f = [int]$led.failed[$a.Id] }
        $led.failed[$a.Id] = $f + 1
        if ($null -ne $text) {
            $qd = Join-Path $J.RuntimeRoot 'quarantine'; [void][System.IO.Directory]::CreateDirectory($qd)
            [System.IO.File]::Move($target, (Join-Path $qd ([guid]::NewGuid().ToString('N') + '-Q-' + $a.Id + '.md')))
        }
        $why = '沒有寫補查結果檔'; if ($null -ne $text) { $why = ($chk.Errors -join '；') }
        $J.Gaps += ('補查 ' + $a.Id + ' 不合格（' + $why + '）；第 ' + $led.failed[$a.Id] + ' 次')
    }
    Write-BzLedger $led
    return $sr
}
function Repair-BzLedgerFiles {
    # 補查檔被改或刪：從 .ps-runtime 的副本還原（寫手只准讀）
    $led = Read-BzLedger
    foreach ($e in $led.entries) {
        $p = Join-Path $J.Root $e.file
        $t = Get-BzText $p
        if ($null -ne $t -and (Get-PsKnTextHash -Text $t) -ceq $e.sha) { continue }
        $copy = Get-BzText (Join-Path $J.QueryCopyDir ([System.IO.Path]::GetFileName($e.file)))
        if ($null -ne $copy -and (Get-PsKnTextHash -Text $copy) -ceq $e.sha) { Write-BzText $p $copy; $J.Gaps += ('補查檔被改動，已從副本還原：' + $e.file) }
    }
}

# ---------------- 診斷（-Diag：只印代號與數字，可以唸給維護端） ----------------
# 每個工單一行：oNNNN K=種類（W 寫作 F 修正 A 套回覆 B 回填 Q 補查）ST=步驟（02、03、05-4…、SC=自我檢查、RD=README、AP=附錄）
#   X=結束碼 RT=模型端重試的狀態碼分布（504x6、NRx2＝無回應）P=成功的回應數 Q=請求數 M=主代理最大輸入（k token）O=單次最多輸出
#   ERR=err 檔分類（E0 空、E504、ECONN 連線中斷、E400、EOTH 其他）DUR=分鐘；最後一行 SUM 為各種類數與最近一個失敗工單的 RT。
function Get-BzStepCode([string]$Step) {
    if ($Step -eq '') { return '-' }
    if ($Step -eq '完成前自我檢查') { return 'SC' }
    if ($Step -eq 'README.md') { return 'RD' }
    if ($Step -eq 'appendix.md') { return 'AP' }
    $m = [regex]::Match($Step, '^([0-9]{2}(-[0-9])?)')
    if ($m.Success) { return $m.Groups[1].Value }
    return '?'
}
function Show-BzDiag {
    $kinds = @{ WRITE = 'W'; FIX = 'F'; ANSWER = 'A'; BACKFILL = 'B'; QUERY = 'Q' }
    $orders = @()
    if ([System.IO.Directory]::Exists($J.OrderDir)) { foreach ($f in @(Get-ChildItem -LiteralPath $J.OrderDir -File -Filter 'o*.md')) { $orders += $f.Name } }
    $orders = @(Sort-PsKnOrdinal -Items $orders | Select-Object -Last 12)
    $logs = @(); if ([System.IO.Directory]::Exists($J.LogRoot)) { $logs = @(Get-ChildItem -LiteralPath $J.LogRoot -File) }
    $count = @{}; $lastFail = '-'
    foreach ($name in $orders) {
        if ($null -eq $name) { continue }
        $oid = [System.IO.Path]::GetFileNameWithoutExtension($name)
        $t = Get-BzText (Join-Path $J.OrderDir $name)
        $k = '?'; $mk = [regex]::Match([string]$t, '（(WRITE|FIX|ANSWER|BACKFILL|QUERY)）'); if ($mk.Success) { $k = $kinds[$mk.Groups[1].Value] }
        $step = ''; $ms = [regex]::Match([string]$t, '這次只做：([^（\r\n]+)'); if ($ms.Success) { $step = $ms.Groups[1].Value.Trim() }
        if ($k -eq 'W' -and $step -eq '') { $step = '完成前自我檢查' }
        $count[$k] = 1 + [int]$count[$k]
        $tag = '-' + $J.JobId + '-' + $oid + '.'
        $mine = @($logs | Where-Object { $_.Name.Contains($tag) } | Sort-Object Name)
        $x = '-'; $rt = '-'; $p = '-'; $q = '-'; $mx = '-'; $mo = '-'; $err = 'E0'; $dur = '-'
        $rc = $mine | Where-Object { $_.Name.EndsWith('.rc.txt') } | Select-Object -Last 1
        if ($null -ne $rc) { $x = ([string](Get-BzText $rc.FullName)).Trim(); if ($x -eq '') { $x = '-' } }
        $ef = $mine | Where-Object { $_.Name.EndsWith('.err.txt') } | Select-Object -Last 1
        if ($null -ne $ef) {
            $et = [string](Get-BzText $ef.FullName)
            if ($et.Trim() -eq '') { $err = 'E0' } elseif ($et -match '504') { $err = 'E504' } elseif ($et -match '(?i)ECONNRESET|socket hang up|connection reset|terminated') { $err = 'ECONN' } elseif ($et -match '\b400\b') { $err = 'E400' } else { $err = 'EOTH' }
        }
        $sf = $mine | Where-Object { $_.Name.EndsWith('.stream.jsonl') } | Select-Object -Last 1
        $last = $ef; if ($null -ne $sf) { $last = $sf }
        if ($null -ne $sf) {
            $a = Get-PsOcClaudeApiRetry -StreamFile $sf.FullName
            $rt = [string]$a.Statuses; if ($rt -eq '') { $rt = '-' }
            $p = [string]$a.Progress; $q = [string]$a.Requests; $mx = [string][Math]::Round([double]$a.MaxContextMain / 1000); $mo = [string]$a.MaxOutput
        }
        if ($null -ne $last) {
            $ms2 = [regex]::Match($last.Name, '^([0-9]{8}-[0-9]{6})')
            if ($ms2.Success) {
                try { $st0 = [datetime]::ParseExact($ms2.Groups[1].Value, 'yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture); $dur = [string][Math]::Round(($last.LastWriteTime - $st0).TotalMinutes) } catch { $dur = '-' }
            }
        }
        if ($x -ne '0' -and $x -ne '-') { $lastFail = $rt }
        Write-Host ($oid + ' K=' + $k + ' ST=' + (Get-BzStepCode $step) + ' X=' + $x + ' RT=' + $rt + ' P=' + $p + ' Q=' + $q + ' M=' + $mx + ' O=' + $mo + ' ERR=' + $err + ' DUR=' + $dur)
    }
    $parts = @(); foreach ($k in (Sort-PsKnOrdinal -Items @($count.Keys))) { if ($null -ne $k) { $parts += ($k + $count[$k]) } }
    Write-Host ('SUM ' + $J.Cli + ' ' + ($parts -join ' ') + ' LASTFAIL-RT=' + $lastFail)
}

# ---------------- OpenCode 版的模型（與 Spec 文件流程共用 sdoc/model.yaml） ----------------
function Get-BzOpencodeModel {
    $t = Get-BzText (Join-Path $J.Root ($J.PsDir + '/sdoc/model.yaml'))
    if ($null -eq $t) { return '' }
    foreach ($ln in ($t -split "`n")) {
        $m = [regex]::Match($ln, '^\s*model\s*:(.*)$')
        if (-not $m.Success) { continue }
        $v = ($m.Groups[1].Value -replace '\s+#.*$', '').Trim()
        if ($v.Length -ge 2 -and (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'")))) { $v = $v.Substring(1, $v.Length - 2).Trim() }
        return $v
    }
    return ''
}
function Test-BzOpencodeModelName([string]$Name) {
    if ($null -eq $Name -or -not (Test-PsOcPromptSafe -PromptText $Name)) { return $false }
    if ($Name -match '(?i)FILL_ME') { return $false }
    return ($Name -cmatch '^[A-Za-z0-9_][A-Za-z0-9_.@-]*/[A-Za-z0-9_][A-Za-z0-9_.:/@-]*$')
}

# ---------------- 主程式 ----------------
$exitCode = 0; $code = 'BIZ1-9-02'; $mutex = $null; $held = $false
$J = @{ Gaps = @(); EnvChanged = $false; LastStats = $null; EnvSaved = @{ Cli = $env:PS_CLI; NoClaude = $env:OPENCODE_DISABLE_CLAUDE_CODE } }
try {
    if ($Root -eq '') { $Root = Split-Path $PSScriptRoot -Parent }
    $Root = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if (-not [System.IO.Directory]::Exists($Root) -or -not (Test-PsOcPromptSafe -PromptText $Root) -or ($Model -ne '' -and (-not (Test-PsOcPromptSafe -PromptText $Model) -or $Model -cnotmatch '^[A-Za-z0-9_][A-Za-z0-9_.:/-]*$'))) { throw 'BZ_ARGUMENT_INVALID' }
    if ($Status -and $Retry) { throw 'BZ_ARGUMENT_INVALID' }
    $cliArg = ([string]$Cli).Trim().ToLowerInvariant()
    if (@('', 'claude', 'opencode') -notcontains $cliArg) { throw 'BZ_ARGUMENT_INVALID' }
    $set = @{}
    $componentText = ((@($Components) + @($MoreComponents) | Where-Object { $null -ne $_ }) -join ' ').Replace("'", ' ').Trim()
    foreach ($name in @($componentText -split '[,\s]+' | Where-Object { $_ -ne '' })) {
        if ($name -match '[^\x00-\x7F]') { throw 'BZ_ARGUMENT_INVALID' }
        $upper = $name.ToUpperInvariant()
        if ($upper -cnotmatch '^[A-Z0-9_][A-Z0-9_.$#-]{0,59}$') { throw 'BZ_ARGUMENT_INVALID' }
        $set[$upper] = $true
    }
    if ($set.Count -eq 0) { throw 'BZ_ARGUMENT_INVALID' }
    if ($cliArg -ne '') { $J.EnvChanged = $true; $env:PS_CLI = $cliArg }
    $fe = Get-PsCliVariant -Root $Root
    $J.Cli = $fe.Name; $J.PsDir = $fe.PsDir; $J.Root = $Root
    $J.StandardRel = $fe.PsDir + '/bizspec/standard.md'
    $J.QueryContractRel = $fe.PsDir + '/bizspec/query-contract.md'
    if (-not [System.IO.File]::Exists((Join-Path $Root $J.StandardRel))) { throw 'BZ_VARIANT' }
    $J.Names = Sort-PsKnOrdinal -Items @($set.Keys)
    $J.Hash = (Get-PsKnTextHash -Text ($J.Names -join "`n")).Substring(0, 16).ToLowerInvariant()
    $J.JobId = 'biz-' + $J.Hash
    $J.Sfx = ''; if ($fe.Name -eq 'opencode') { $J.Sfx = '-opencode' }
    $J.InputRoot = Join-Path (Join-Path $Root ('.ps-private/bizspec' + $J.Sfx)) $J.JobId
    $J.RuntimeRoot = Join-Path $Root ('.ps-runtime/bizspec' + $J.Sfx)
    $J.LogRoot = Join-Path $Root ('.ps-runtime/bizspec' + $J.Sfx + '-logs')
    $J.JobRoot = Join-Path $J.RuntimeRoot $J.JobId
    $J.OrderDir = Join-Path $J.JobRoot 'orders'
    $J.CheckDir = Join-Path $J.JobRoot 'check'
    $J.QueryCopyDir = Join-Path $J.JobRoot 'queries'
    $J.JobPath = Join-Path $J.JobRoot 'job.json'
    $J.LedgerPath = Join-Path $J.JobRoot 'queries.json'
    $J.OutputRoot = Join-Path (Join-Path $Root ('docs/ps-spec' + $J.Sfx)) $J.JobId
    $J.EvidenceDir = Join-Path $J.OutputRoot 'evidence'
    $J.NextCommand = "powershell -NoProfile -File '" + $PSCommandPath.Replace("'", "''") + "' -Root '" + $Root.Replace("'", "''") + "' -Components '" + ($J.Names -join ',') + "'"
    if ($fe.Name -eq 'opencode') { $J.NextCommand += ' -Cli opencode' }
    if ($Model -ne '') { $J.NextCommand += " -Model '" + $Model + "'" }
    if ($NoQuery) { $J.NextCommand += ' -NoQuery' }
    if ($PSBoundParameters.ContainsKey('TimeoutMin')) { $J.NextCommand += ' -TimeoutMin ' + $TimeoutMin }
    $J.Model = $Model; $J.ModelFrom = '-Model'
    if ($fe.Name -eq 'opencode') {
        $J.EnvChanged = $true; $env:OPENCODE_DISABLE_CLAUDE_CODE = '1'
        if ($J.Model -eq '') { $J.Model = Get-BzOpencodeModel; $J.ModelFrom = $fe.PsDir + '/sdoc/model.yaml' }
        if (-not (Test-BzOpencodeModelName $J.Model)) { throw 'BZ_MODEL_INVALID' }
        Write-Host ('OpenCode 模型：' + $J.Model + '（' + $J.ModelFrom + '）')
    }
    if ($Diag) { Show-BzDiag; throw 'BZ_DIAG_DONE' }
    $rootLockId = (Get-PsKnTextHash -Text $Root.ToUpperInvariant()).Substring(0, 16)
    $mutex = New-Object System.Threading.Mutex($false, ('Global\MCPSample-BizSpec-' + $rootLockId + '-' + $J.JobId + $J.Sfx))
    try { $held = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $held = $true }
    if (-not $held) { Write-Host '同一組 Component 的業務需求文件工作正在執行；稍後用相同命令繼續。'; $code = 'BIZ1-0-03'; $exitCode = 3 }
    else {
        if (-not $Status) { Initialize-BzInputs }
        $J.Knowledge = Find-BzKnowledge
        $human = Get-BzHumanSources
        $started = [System.IO.File]::Exists((Join-Path $J.OutputRoot 'progress.md'))
        if (-not $started -and $human.Count -eq 0 -and $J.Knowledge.Count -eq 0) {
            Write-Host ('等待來源：知識層（docs/ps-research）沒有提到 ' + ($J.Names -join '、') + ' 的文件，人工輸入也還是骨架。')
            Write-Host ('先用 /ps-research 研究這組 Component 所屬領域，或把狀態圖、業務說明寫進 ' + (Get-BzRel $J.InputRoot) + '/ 的 status.md、project.md（刪掉第一行的 BIZSPEC:SKELETON 標記）。放好後用相同命令繼續：')
            Write-Host $J.NextCommand
            $code = 'BIZ1-0-01'
        }
        elseif ($Status -and -not $started) { Write-Host '尚未開始。下一步：'; Write-Host $J.NextCommand; $code = 'BIZ1-0-02' }
        else {
            [void][System.IO.Directory]::CreateDirectory($J.OrderDir)
            $job = Read-BzJob
            if ($Retry) { $job.fix = 0; $job.lastFindings = -1; $job.stepTries = @{}; $job.backfillTries = 0; $job.answerTries = @{}; $led0 = Read-BzLedger; $led0.failed = @{}; Write-BzLedger $led0; Write-BzJob $job }
            if (-not $Status) {
                if ($FakeWriter -eq '' -or (-not $NoQuery -and $FakeQuery -eq '')) {
                    $oc = Get-PsOcPath -Root $Root; $J.OcPath = [string]$oc.Path
                    if ($J.OcPath -eq '') { throw ('無法啟動 ' + $oc.Exe + '：' + $oc.Error) }
                }
                foreach ($fk in @($FakeWriter, $FakeQuery)) { if ($fk -ne '' -and -not [System.IO.File]::Exists($fk)) { throw 'Fake 腳本不存在。' } }
                if ($fe.Name -eq 'opencode' -and $FakeWriter -eq '') {
                    $mc = Test-PsOcOpencodeModel -OcPath $J.OcPath -Model $J.Model -Root $J.Root -LogRoot $J.LogRoot
                    if ($mc.Result -eq 'UNKNOWN') { Write-Host ('提醒：無法先確認模型（' + $mc.Message + '）；照常開 session。') }
                    elseif ($mc.Result -ne 'OK') { Write-Host ('模型不能用：' + $mc.Message + '。改 ' + $J.ModelFrom + ' 的 model 那一行，再跑同一個命令：'); Write-Host $J.NextCommand; throw 'BZ_MODEL_UNAVAILABLE' }
                }
                Repair-BzLedgerFiles
                Initialize-BzOutput
            }
            $sessions = 0; $stop = ''; $failedApi = @(); $next = $null
            while ($true) {
                $next = Get-BzNext $job
                if (@('DONE', 'BLOCKED') -contains $next.Kind -or $Status) { break }
                if ($sessions -ge $MaxSessions) { break }
                $sr = $null
                if ($next.Kind -eq 'QUERY') { $sr = Invoke-BzQueryStep $next $job } else { $sr = Invoke-BzWriterStep $next $job }
                if ([bool]$sr.SlotBusy) { $stop = 'SLOT_BUSY'; break }
                $sessions++
                if (Test-BzSessionFailed $sr) { $stop = 'SESSION_FAILED'; $failedApi += [string]$sr.ApiKind; break }
            }
            if ($next.Kind -eq 'DONE') { $job.fix = 0 }
            $job.phase = $next.Kind; if ($next.Kind -eq 'DONE') { $job.phase = $next.Phase }
            if (-not $Status) { Write-BzJob $job }
            if ($null -eq $J.LastStats -and [System.IO.File]::Exists((Join-Path $J.OutputRoot 'progress.md'))) { [void](Invoke-BzCheckNow) }
            $s = $J.LastStats
            $statLine = '欄位統計：需求=0；證據=0；補查證據=0；開放假設=0'
            if ($null -ne $s) { $statLine = '欄位統計：需求=' + $s.Requirements + '；證據=' + $s.Evidence + '；補查證據=' + $s.QueryEvidence + '；開放假設=' + $s.OpenAssumptions }
            Write-Host ('狀態：' + $job.phase + '；本輪 session=' + $sessions + '；修正輪次=' + $job.fix)
            Write-Host $statLine
            Write-Host ('入口：' + (Join-Path $J.OutputRoot 'README.md'))
            foreach ($g in $J.Gaps) { Write-Host ('缺口：' + $g) }
            if ($next.Kind -eq 'DONE' -and $next.Phase -eq 'REVIEW_READY') { Write-Host '外環檢查全過、補查已回填、沒有開放假設，可人工審閱。這不是業務驗收。'; $code = 'BIZ1-7-01' }
            elseif ($next.Kind -eq 'DONE') {
                Write-Host ('外環檢查全過、補查已回填；還有 ' + $next.Open + ' 筆開放假設要業務窗口回覆：看 07-assumptions.md，回覆寫進 ' + (Get-BzRel (Join-Path $J.InputRoot 'answers.md')) + ' 後用相同命令續跑。')
                $code = 'BIZ1-5-01'
            }
            elseif ($next.Kind -eq 'BLOCKED') {
                Write-Host ('卡住：' + $next.Reason + '。')
                if ($null -ne $next.Findings) { foreach ($f in @($next.Findings | Select-Object -First 10)) { Write-Host ('檢查：' + $f.Code + ' ' + $f.File + '：' + $f.Detail) } }
                Write-Host '處理原因後同命令加 -Retry：'; Write-Host ($J.NextCommand + ' -Retry'); $code = 'BIZ1-4-03'; $exitCode = 1
            }
            else { Write-Host ('下一步：' + $next.Kind + '；用相同命令繼續：'); Write-Host $J.NextCommand; $code = 'BIZ1-3-02-1' }
            if ($stop -eq 'SLOT_BUSY') { Write-Host '模型服務被其他 session 使用；稍後重跑。'; $code = 'BIZ1-3-03'; $exitCode = 1 }
            if ($stop -eq 'SESSION_FAILED') {
                $hint = Get-PsOcApiHint -Kinds $failedApi -TimeoutMin $TimeoutMin
                if ($hint -ne '') { Write-Host ('session 失敗。' + $hint + '。已寫的檔保留，同命令續跑。') }
                elseif ($fe.Name -eq 'opencode') { Write-Host ('session 失敗；檢查 OpenCode 的模型與 provider（' + $J.Model + '，設定在 ' + $J.ModelFrom + '）與 MCP 後重跑；錯誤訊息在 ' + (Get-BzRel $J.LogRoot) + ' 最新的 .err.txt。') }
                else { Write-Host 'session 失敗；檢查 Claude Code／MCP 後重跑。已寫的檔保留，同命令續跑。' }
                $code = 'BIZ1-3-04'; $exitCode = 1
            }
        }
    }
}
catch {
    $exitCode = 1
    $msg = $_.Exception.Message
    if ($msg -eq 'BZ_DIAG_DONE') { $code = 'BIZ1-0-04'; $exitCode = 0 }
    elseif ($msg -eq 'BZ_WRITE_DEFERRED') { Write-Host '寫入暫時失敗，未假裝完成；解除檔案占用後用相同命令繼續。'; $code = 'BIZ1-3-07' }
    elseif ($msg -eq 'BZ_ARGUMENT_INVALID') { Write-Host '參數錯誤：Components 只收 exact ASCII 物件名（逗號或空白分隔）；Status 與 Retry 不可混用；Model／Root 不可含命令列控制字元；Cli 只收 claude 或 opencode。'; $code = 'BIZ1-9-01'; $exitCode = 2 }
    elseif ($msg -eq 'BZ_VARIANT') { Write-Host ('這個資料夾沒有 ' + $J.StandardRel + '（業務需求文件的規範）：請解開含 peoplesoft/bizspec/ 的搬運包。'); $code = 'BIZ1-9-01'; $exitCode = 2 }
    elseif ($msg -eq 'BZ_MODEL_INVALID') { Write-Host ('OpenCode 版的模型設定不對（' + $J.ModelFrom + '，目前讀到「' + $J.Model + '」）：要寫成 <provider>/<model>，照「opencode models」列出的原樣。'); $code = 'BIZ1-9-01'; $exitCode = 2 }
    elseif ($msg -eq 'BZ_MODEL_UNAVAILABLE') { $code = 'BIZ1-9-01'; $exitCode = 2 }
    else { Write-Host ('無法繼續：' + $msg); if ($env:PS_BIZSPEC_TRACE) { Write-Host $_.ScriptStackTrace }; $code = 'BIZ1-9-02'; $exitCode = 2 }
}
finally {
    if ($held -and $null -ne $mutex) { $mutex.ReleaseMutex() }; if ($null -ne $mutex) { $mutex.Dispose() }
    if ($J.EnvChanged) { $env:PS_CLI = $J.EnvSaved.Cli; $env:OPENCODE_DISABLE_CLAUDE_CODE = $J.EnvSaved.NoClaude }
}
Write-Host $code
exit $exitCode
