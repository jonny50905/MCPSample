# ps-spec-build.ps1 — 複製功能規格的單一入口；研究與獨立覆核分開 session。
# PowerShell 5.1；公司機資料只留本機。generated 是投影，交付修訂請另存副本。
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Components,
    [string]$Root = '',
    [switch]$Status,
    [ValidateRange(1, 100)][int]$MaxSessions = 4,
    [ValidateRange(1, 180)][int]$TimeoutMin = 30,
    [string]$Model = '',
    [switch]$Refresh,
    [switch]$Retry,
    [string]$FakeWorker = ''
)
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'ps-knowledge-lib.ps1')
    . (Join-Path $PSScriptRoot 'ps-session-lib.ps1')
    . (Join-Path $PSScriptRoot 'ps-spec-clone-lib.ps1')
}
catch { Write-Host ('共用腳本載入失敗，請核對搬運清單與 UTF-8 BOM：' + $_.Exception.Message); Write-Host 'CLONE1-9-02'; exit 2 }

function Read-CbJson([string]$Path) {
    if (-not [System.IO.File]::Exists($Path)) { return $null }
    try { return (ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($Path))) }
    catch { throw ('JSON 損壞，保留現場：' + $Path) }
}
function Write-CbJson([string]$Path, $Value, [switch]$Create) {
    $text = (ConvertTo-PsKnJson -Value $Value -SortKeys) + "`n"
    if ($Create) {
        $ok = Write-PsKnCreateOnlyText -LiteralPath $Path -Text $text
        if ($null -eq $ok) { throw 'CLONE_WRITE_DEFERRED' }
        if (-not $ok -and (Read-PsKnText -LiteralPath $Path) -cne $text) { throw ('不可覆寫既有收據：' + $Path) }
    }
    elseif (-not (Write-PsKnAtomicText -LiteralPath $Path -Text $text)) { throw 'CLONE_WRITE_DEFERRED' }
}
function Write-CbText([string]$Path, [string]$Text) {
    if (-not (Write-PsKnAtomicText -LiteralPath $Path -Text $Text)) { throw 'CLONE_WRITE_DEFERRED' }
}
function Get-CbFiles([string]$Dir) {
    $out = @()
    if ([System.IO.Directory]::Exists($Dir)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $Dir -File -Recurse -Force)) {
            if (($f.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw '不支援 reparse point 的工作目錄。' }
            $out += $f.FullName
        }
    }
    return , $out
}
function Get-CbSource {
    $paths = @()
    $rawHashPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $research = Join-Path $Root 'docs/ps-research'
    $researchFiles = Get-CbFiles $research
    foreach ($f in $researchFiles) {
        $rel = $f.Substring($research.Length).TrimStart('\', '/') -replace '\\', '/'
        if ($rel -match '^(knowledge|supplemental)/') { continue }
        if ($f.EndsWith('.md', [StringComparison]::OrdinalIgnoreCase) -or [System.IO.Path]::GetFileName($f) -eq 'audit-done.json') { $paths += $f }
    }
    foreach ($p in @('.opencode/peoplesoft/spec/clone-profile.json', '.opencode/peoplesoft/spec/clone-contract.md', '.opencode/peoplesoft/customization-profile.yaml', '.opencode/peoplesoft/business-domain-map.yaml', '.opencode/agent/ps-clone-worker.md', '.opencode/command/ps-clone-batch.md')) { $paths += (Join-Path $Root $p) }
    # 委派 flow／auditor／orchestrator 的模型契約也是來源版本；保守納入全部 ps-* agent。
    $agentFiles = Get-CbFiles (Join-Path $Root '.opencode/agent')
    foreach ($p in $agentFiles) { if ([System.IO.Path]::GetFileName($p) -match '^ps-.*\.md$') { $paths += $p } }
    foreach ($p in @('.opencode/peoplesoft/subagent-report-contract.md', '.opencode/peoplesoft/knowledge-retrieval-contract.md')) { $paths += (Join-Path $Root $p) }
    $skillFiles = Get-CbFiles (Join-Path $Root '.opencode/skills')
    foreach ($p in $skillFiles) { $paths += $p; [void]$rawHashPaths.Add($p) }
    $modelContracts = Join-Path $Root '.opencode/peoplesoft'
    if ([System.IO.Directory]::Exists($modelContracts)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $modelContracts -File -Filter '*.md')) {
            if (@('SOP.md', 'README.md', 'test-scenarios.md') -notcontains $f.Name) { $paths += $f.FullName }
        }
    }
    foreach ($p in @('ps-spec-build.ps1', 'ps-spec-clone-lib.ps1', 'ps-knowledge-lib.ps1', 'ps-session-lib.ps1')) { $paths += (Join-Path $PSScriptRoot $p) }
    $map = [ordered]@{}
    $orderedPaths = Sort-PsKnOrdinal -Items $paths
    foreach ($p in $orderedPaths) {
        if ($rawHashPaths.Contains($p)) { $map[$p] = [string](Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
        else { $map[$p] = Get-PsKnFileHash -LiteralPath $p }
    }
    return @{ Hash = (Get-PsKnTextHash -Text (ConvertTo-PsKnJson -Value $map -SortKeys)); Files = $map }
}
function Get-CbNumber([string]$Dir, [string]$Pattern) {
    $n = 0
    if ([System.IO.Directory]::Exists($Dir)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Force)) { $m = [regex]::Match($f.Name, $Pattern); if ($m.Success) { $n = [Math]::Max($n, [int]$m.Groups[1].Value) } }
    }
    return $n
}
function Get-CbLedger {
    $rows = @()
    if ([System.IO.Directory]::Exists($attemptRoot)) {
        foreach ($d in @(Get-ChildItem -LiteralPath $attemptRoot -Directory | Sort-Object Name)) {
            if ($d.Name -notmatch '^a[0-9]{4,8}$') { continue }
            $inp = Read-CbJson (Join-Path $d.FullName 'input.json')
            if ($null -eq $inp -or [string]$inp.revision -cne $revision.id) { continue }
            $rows += , @{ Id = $d.Name; Dir = $d.FullName; Input = $inp; Outcome = (Read-CbJson (Join-Path $d.FullName 'outcome.json')) }
        }
    }
    return , $rows
}
function Get-CbAccepted {
    $rows = @()
    $files = Get-CbFiles $receiptRoot
    foreach ($p in $files) {
        if (-not $p.EndsWith('.json')) { continue }
        $rc = Read-CbJson $p
        if ($null -eq $rc -or [string]$rc.revision -cne $revision.id -or [string]$rc.sourceHash -cne $revision.sourceHash) { continue }
        $packetHash = Get-PsKnTextHash -Text (ConvertTo-PsKnJson -Value $rc.packet -SortKeys)
        if ($packetHash -cne [string]$rc.packetHash -or [string]$rc.review.verdict -cne 'PASS') { throw ('驗收收據失去完整性：' + $p) }
        $rows += , @{ Path = $p; Receipt = $rc }
    }
    foreach ($a in $rows) {
        $rc = $a.Receipt
        $scope = @()
        foreach ($s in $rows) { if ($s.Receipt.component -ceq $rc.component -and $s.Receipt.topic -ceq 'scope') { $scope += @($s.Receipt.packet.items) } }
        $pv = Test-PsClonePacket -Packet $rc.packet -Component ([string]$rc.component) -Topic ([string]$rc.topic) -Profile $profile -ScopeItems $scope
        $rv = Test-PsCloneReview -Review $rc.review -Packet $rc.packet -InputHash ([string]$rc.inputHash)
        if (-not $pv.Ok -or -not $rv.Passed -or $names -cnotcontains [string]$rc.component) { throw ('驗收收據重驗未通過：' + $a.Path) }
        if ([int]$rc.page -gt 1 -and [string]$rc.packet.coverage -eq 'NOT_APPLICABLE') { throw '續頁不能改稱整個主題不適用；範圍已變請 -Refresh。' }
        if ([string]$rc.reviewAttempt -cnotmatch '^a[0-9]{4,8}$' -or [string]$rc.researchAttempt -cnotmatch '^a[0-9]{4,8}$' -or [string]$rc.reviewAttempt -ceq [string]$rc.researchAttempt) { throw '驗收收據沒有獨立研究／覆核 attempt。' }
        $reviewInput = Read-CbJson (Join-Path (Join-Path $attemptRoot ([string]$rc.reviewAttempt)) 'input.json')
        $researchOutcome = Read-CbJson (Join-Path (Join-Path $attemptRoot ([string]$rc.researchAttempt)) 'outcome.json')
        if ($null -eq $reviewInput -or $null -eq $researchOutcome) { throw '驗收收據缺少原始派工／候選紀錄。' }
        if ([string]$reviewInput.kind -cne 'AUDIT' -or [string]$reviewInput.inputHash -cne [string]$rc.inputHash -or [string]$reviewInput.candidateId -cne [string]$rc.researchAttempt -or [string]$reviewInput.candidateHash -cne [string]$rc.packetHash -or [string]$researchOutcome.status -cne 'CANDIDATE' -or [string]$researchOutcome.packetHash -cne [string]$rc.packetHash) { throw '驗收收據與獨立覆核工單／候選不一致。' }
        $savedHash = [string]$reviewInput.inputHash
        $reviewInput.inputHash = ''
        if ((Get-PsKnTextHash -Text (ConvertTo-PsKnJson -Value $reviewInput -SortKeys)) -cne $savedHash) { throw '覆核工單快照已被修改。' }
        if ((Get-PsKnTextHash -Text (ConvertTo-PsKnJson -Value $reviewInput.packet -SortKeys)) -cne [string]$rc.packetHash) { throw '覆核工單不是這份研究候選。' }
    }
    $topicOrder = @{}
    for ($i = 0; $i -lt @($profile.topics).Count; $i++) { $topicOrder[[string]$profile.topics[$i].id] = $i }
    $sorted = @($rows | Sort-Object @{ Expression = { [string]$_.Receipt.component } }, @{ Expression = { $topicOrder[[string]$_.Receipt.topic] } }, @{ Expression = { [int]$_.Receipt.page } })
    return , $sorted
}
function Get-CbPageState([string]$Component, [string]$Topic, $Accepted, $Ledger) {
    $pages = @($Accepted | Where-Object { $_.Receipt.component -ceq $Component -and $_.Receipt.topic -ceq $Topic } | Sort-Object { [int]$_.Receipt.page })
    $page = 1; $cursor = ''; $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal); $unresolved = @()
    foreach ($a in $pages) {
        $rc = $a.Receipt
        if ([int]$rc.page -ne $page -or [string]$rc.cursor -cne $cursor) { throw '驗收頁次不連續，停止而不猜測。' }
        $cv = [string]$rc.packet.coverage
        $unresolved += @($rc.packet.gaps)
        if ($cv -eq 'COMPLETE' -or $cv -eq 'NOT_APPLICABLE') {
            if ($unresolved.Count -gt 0) { return @{ State = 'BLOCKED'; Page = $page; Cursor = $cursor; Key = ''; Candidate = $null; Findings = @($unresolved + '先前頁仍有未解缺口；後頁 COMPLETE 不會自動消債。補齊證據後 -Refresh。') } }
            return @{ State = 'DONE'; Page = $page; Cursor = $cursor; Key = ''; Candidate = $null; Findings = @() }
        }
        $next = [string]$rc.packet.nextCursor
        if ($next -eq '' -or $seen.Contains($next) -or $page -ge 20) { return @{ State = 'BLOCKED'; Page = $page; Cursor = $cursor; Key = ''; Candidate = $null; Findings = @($unresolved + '仍有缺口，或續頁已達界限；請檢查證據／縮小功能範圍後 -Refresh。') } }
        [void]$seen.Add($next); $cursor = $next; $page++
    }
    $key = $Component + '/' + $Topic + '/' + $page
    $entries = @($Ledger | Where-Object { $_.Input.pageKey -ceq $key })
    $invalid = 0; $findings = @(); $candidate = $null; $rejected = @{}
    foreach ($e in $entries) {
        $o = $e.Outcome
        if ($null -eq $o) { continue }
        if ([int]$e.Input.budget -eq $budget -and [bool]$o.counted) { $invalid++ }
        if ([bool]$o.counted -and @($o.findings).Count -gt 0) { $findings = @($o.findings) }
        if (@('REVIEW_FAIL', 'REVIEW_BLOCKED') -contains [string]$o.status) { $rejected[[string]$e.Input.candidateId] = $true; $findings = @($o.findings) }
    }
    foreach ($e in $entries) {
        if ($null -ne $e.Outcome -and [string]$e.Outcome.status -eq 'CANDIDATE' -and -not $rejected.ContainsKey($e.Id)) { $candidate = $e }
    }
    if ($invalid -ge 2) { return @{ State = 'BLOCKED'; Page = $page; Cursor = $cursor; Key = $key; Candidate = $candidate; Findings = @($findings + '本頁本次預算已兩次未通過；修正原因後加 -Retry，保留既有收據。') } }
    if ($null -ne $candidate) { return @{ State = 'AUDIT'; Page = $page; Cursor = $cursor; Key = $key; Candidate = $candidate; Findings = $findings } }
    return @{ State = 'RESEARCH'; Page = $page; Cursor = $cursor; Key = $key; Candidate = $null; Findings = $findings }
}
function Get-CbState {
    $accepted = Get-CbAccepted
    $ledger = Get-CbLedger
    $work = @(); $gaps = @(); $allDone = $true
    foreach ($comp in $names) {
        $scope = Get-CbPageState $comp 'scope' $accepted $ledger
        foreach ($topic in @($profile.topics)) {
            if ([string]$topic.id -ne 'scope' -and $scope.State -ne 'DONE') { $allDone = $false; continue }
            $s = Get-CbPageState $comp ([string]$topic.id) $accepted $ledger
            if ($s.State -eq 'DONE') { continue }
            $allDone = $false
            if ($s.State -eq 'BLOCKED') { $gaps += ($comp + ' / ' + $topic.id + '：' + ($s.Findings -join '；')); continue }
            $work += , @{ Component = $comp; Topic = [string]$topic.id; Kind = $s.State; Page = $s.Page; Cursor = $s.Cursor; Key = $s.Key; Candidate = $s.Candidate; Findings = $s.Findings }
        }
    }
    $used = @($ledger | Where-Object { [int]$_.Input.budget -eq $budget -and ($null -eq $_.Outcome -or [string]$_.Outcome.status -ne 'SLOT_BUSY') }).Count
    $limit = [Math]::Min(4000, $names.Count * @($profile.topics).Count * 20 * 6)
    if ($used -ge $limit -and $work.Count -gt 0) { $gaps += '本次總派工預算已達上限；檢查缺口後加 -Retry 開新預算。'; $work = @() }
    $phase = 'RUNNABLE'
    if ($allDone) { $phase = 'REVIEW_READY' } elseif ($work.Count -eq 0) { $phase = 'BLOCKED' }
    return @{ Accepted = $accepted; Ledger = $ledger; Work = $work; Gaps = $gaps; Phase = $phase; Used = $used; Limit = $limit }
}

# 外環獨佔的檔案全部快照；worker 只准新增這次指定的 packet/review。
function Get-CbFence {
    $map = @{}
    foreach ($dir in @($jobRoot, $outputRoot)) {
        $files = Get-CbFiles $dir
        foreach ($p in $files) { $map[$p] = [System.IO.File]::ReadAllBytes($p) }
    }
    return , $map
}
function Restore-CbFence($Snapshot, [string]$Allowed) {
    $violations = @()
    foreach ($p in $Snapshot.Keys) {
        $old = [Convert]::ToBase64String($Snapshot[$p])
        $now = ''; if ([System.IO.File]::Exists($p)) { $now = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($p)) }
        if ($old -ceq $now) { continue }
        $bytes = $Snapshot[$p]
        $txt = [Text.Encoding]::UTF8.GetString($bytes)
        $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)
        if ($bom) { $txt = $txt.Substring(1) }
        if (-not (Write-PsKnAtomicText -LiteralPath $p -Text $txt -Bom $bom)) { throw 'CLONE_WRITE_DEFERRED' }
        $violations += $p
    }
    foreach ($dir in @($jobRoot, $outputRoot)) {
        $files = Get-CbFiles $dir
        foreach ($p in $files) {
            if ($Snapshot.ContainsKey($p) -or $p -ceq $Allowed) { continue }
            $q = Join-Path (Join-Path $runtimeRoot 'quarantine') ([guid]::NewGuid().ToString('N') + '-' + [System.IO.Path]::GetFileName($p))
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($q))
            [System.IO.File]::Move($p, $q)
            $violations += $p
        }
    }
    return , $violations
}
function Invoke-CbOne($Work, $State) {
    $n = 1 + (Get-CbNumber $attemptRoot '^a([0-9]{4,8})$')
    $aid = 'a' + $n.ToString('0000')
    $ad = Join-Path $attemptRoot $aid
    $kind = $Work.Kind
    $outName = 'packet.json'; if ($kind -eq 'AUDIT') { $outName = 'review.json' }
    $outPath = Join-Path $ad $outName
    $scopeItems = @(); $packetPaths = @()
    foreach ($a in $State.Accepted) {
        $packetPaths += $a.Path
        if ([string]$a.Receipt.component -ceq $Work.Component) {
            if ([string]$a.Receipt.topic -eq 'scope') { $scopeItems += @($a.Receipt.packet.items) }
        }
    }
    $packet = $null; $candidateId = ''; $candidateHash = ''
    if ($kind -eq 'AUDIT') {
        $candidateId = $Work.Candidate.Id
        $packet = Read-CbJson (Join-Path $Work.Candidate.Dir 'candidate.json')
        $candidateHash = Get-PsKnTextHash -Text (ConvertTo-PsKnJson -Value $packet -SortKeys)
        if ($candidateHash -cne [string]$Work.Candidate.Outcome.packetHash) { throw '候選快照 hash 不符，停止而不沿用。' }
    }
    $inp = [ordered]@{ schemaVersion = 1; jobId = $jobId; attemptId = $aid; revision = $revision.id; budget = $budget; components = @($names); component = $Work.Component; topic = $Work.Topic; kind = $kind; page = $Work.Page; pageKey = $Work.Key; cursor = $Work.Cursor; sourceHash = $revision.sourceHash; scopeItems = @($scopeItems); acceptedPacketPaths = @($packetPaths); previousFindings = @($Work.Findings); candidateId = $candidateId; candidateHash = $candidateHash; packet = $packet; outputPath = $outPath; inputHash = '' }
    $inp.inputHash = Get-PsKnTextHash -Text (ConvertTo-PsKnJson -Value $inp -SortKeys)
    Write-CbJson (Join-Path $ad 'input.json') $inp -Create
    $manifest = @('# 有界功能規格工單', '', ('Component: ' + $Work.Component), ('Topic: ' + $Work.Topic), ('Kind: ' + $kind), ('OutputPath: ' + $outPath), ('InputPath: ' + (Join-Path $ad 'input.json')), ('InputHash: ' + $inp.inputHash), ('ProfilePath: ' + (Join-Path $Root '.opencode/peoplesoft/spec/clone-profile.json')), ('PacketSchemaPath: ' + (Join-Path $Root '.opencode/peoplesoft/spec/clone-contract.md')), ('ReviewSchemaPath: ' + (Join-Path $Root '.opencode/peoplesoft/spec/clone-contract.md')), ('KnowledgeIndex: ' + (Join-Path $Root 'docs/ps-research/knowledge/index.md')), ('ResearchRoot: ' + (Join-Path $Root 'docs/ps-research')), '', '先讀 clone-contract.md 與 input.json。只准寫 OutputPath，不改任何 NN、收據、工單或既有文件。', 'input.components 是全工作功能清單；scopeItems 只屬於本功能；acceptedPacketPaths 包含全工作已接受內容（檔案內 packet 欄位），須檢查跨主題與跨 Component 共用欄位、狀態、交易及介面的一致性。', '先定位知識索引與相關節；沒有 NN 並非失敗，可定向委派既有 PeopleSoft subagent 查證。', '每頁至多 40 items；有明確未完成範圍才用 PARTIAL＋nextCursor；證據不足請明列 gaps，不把未知寫成不適用。', 'RESEARCH 回 packet.json；AUDIT 是獨立覆核 session，讀 input.packet 與來源後回 review.json，inputHash 原樣帶回。') -join "`n"
    Write-CbText (Join-Path $ad 'manifest.md') ($manifest + "`n")
    $fence = Get-CbFence
    Write-Host ('研究／覆核：' + $Work.Component + ' / ' + $Work.Topic + ' / 第 ' + $Work.Page + ' 頁 / ' + $kind)
    $sr = $null
    try {
        if ($FakeWorker -ne '') {
            $global:LASTEXITCODE = 0
            $raw = ((& $FakeWorker -AttemptDir $ad -ManifestPath (Join-Path $ad 'manifest.md') -OutputPath $outPath -Kind $kind *>&1 | ForEach-Object { [string]$_ }) -join "`n")
            $sr = @{ ExitCode = [int]$LASTEXITCODE; TimedOut = $false; SlotBusy = $false; FailureKind = 'NONE' }
        }
        else { $sr = Invoke-PsOcSession -OcPath $ocPath -Root $Root -LogRoot (Join-Path $Root '.ps-runtime/clone-spec-logs') -Model $Model -ExtraArgs '--command ps-clone-batch' -PromptText ($jobId + '/' + $aid) -TimeoutMin $TimeoutMin -Tag ($jobId + '-' + $aid) -Log { param($m) Write-Host $m } -SlotWaitMin 0 -TimeoutParamName 'TimeoutMin' }
    }
    catch { $sr = @{ ExitCode = -1; TimedOut = $false; SlotBusy = $false; FailureKind = 'DISPATCH_ERROR' }; Write-Host ('session 未完成：' + $_.Exception.Message) }
    $violations = Restore-CbFence $fence $outPath
    $after = Get-CbSource
    $outcome = [ordered]@{ status = ''; counted = $false; findings = @(); packetHash = ''; at = (Get-PsKnUtcStamp) }
    if ($after.Hash -cne $revision.sourceHash) { $outcome.status = 'SOURCE_CHANGED' }
    elseif ([bool]$sr.SlotBusy) { $outcome.status = 'SLOT_BUSY' }
    elseif ($violations.Count -gt 0) { $outcome.status = 'INVALID'; $outcome.counted = $true; $outcome.findings = @('worker 修改非授權檔案，已還原／隔離。') }
    elseif ([bool]$sr.TimedOut -or [int]$sr.ExitCode -ne 0 -or (@('', 'NONE') -notcontains [string]$sr.FailureKind)) { $outcome.status = 'SESSION_FAILED'; $outcome.findings = @([string]$sr.FailureKind) }
    else {
        $value = $null
        try { $value = Read-CbJson $outPath } catch { $value = $null }
        if ($kind -eq 'RESEARCH') {
            $v = Test-PsClonePacket -Packet $value -Component $Work.Component -Topic $Work.Topic -Profile $profile -ScopeItems $scopeItems
            $extra = @()
            if ($v.Ok) {
                $priorIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
                $allTopicItems = @($v.Items)
                foreach ($a in $State.Accepted) { if ($a.Receipt.component -ceq $Work.Component -and $a.Receipt.topic -ceq $Work.Topic) { foreach ($it in @($a.Receipt.packet.items)) { [void]$priorIds.Add([string]$it.id); $allTopicItems += , $it } } }
                foreach ($it in @($v.Items)) { if ($priorIds.Contains([string]$it.id)) { $extra += ('跨頁 item id 重複：' + $it.id) } }
                if ([string]$v.Packet.nextCursor -ne '' -and [string]$v.Packet.nextCursor -ceq $Work.Cursor) { $extra += 'nextCursor 沒有前進。' }
                if ([int]$Work.Page -gt 1 -and [string]$v.Packet.coverage -eq 'NOT_APPLICABLE') { $extra += '續頁不能否定前頁已研究的主題；範圍已變請 -Refresh。' }
                if ($Work.Topic -eq 'acceptance' -and [string]$v.Packet.coverage -eq 'COMPLETE') {
                    $types = @($allTopicItems | ForEach-Object { [string]$_.values.scenarioType })
                    foreach ($requiredType in @('POSITIVE', 'NEGATIVE', 'BOUNDARY')) { if ($types -cnotcontains $requiredType) { $extra += ('驗收情境缺少：' + $requiredType) } }
                }
            }
            if (-not $v.Ok -or $extra.Count -gt 0) { $outcome.status = 'INVALID'; $outcome.counted = $true; $outcome.findings = @($v.Errors) + $extra }
            else {
                Write-CbJson (Join-Path $ad 'candidate.json') $v.Packet -Create
                $candidateText = ConvertTo-PsCloneSpec -Components @($Work.Component) -Packets @($v.Packet) -Profile $profile -Status 'UNREVIEWED_CANDIDATE' -Gaps @('此為尚未驗收的研究候選，不屬於已接受正文；請以 job 的 current.json 為準。')
                Write-CbText (Join-Path $ad 'candidate.md') $candidateText
                $outcome.status = 'CANDIDATE'; $outcome.packetHash = Get-PsKnTextHash -Text (ConvertTo-PsKnJson -Value $v.Packet -SortKeys)
            }
        }
        else {
            $v = Test-PsCloneReview -Review $value -Packet $packet -InputHash $inp.inputHash
            if (-not $v.Ok) { $outcome.status = 'INVALID'; $outcome.counted = $true; $outcome.findings = @($v.Errors) }
            elseif (-not $v.Passed) { $outcome.status = 'REVIEW_FAIL'; if ([string]$value.verdict -eq 'BLOCKED') { $outcome.status = 'REVIEW_BLOCKED' }; $outcome.counted = $true; $outcome.findings = @($value.findings | ForEach-Object { [string]$_.code + '：' + [string]$_.detail }) }
            elseif ([string]$packet.coverage -eq 'PARTIAL' -and @($packet.gaps).Count -gt 0) {
                # PASS 只覆核已寫的事實，不能消除已聲明的未知。重查本頁，不迫使整份 Refresh。
                $outcome.status = 'REVIEW_BLOCKED'; $outcome.counted = $true
                $outcome.findings = @($packet.gaps) + '本頁仍缺證據，候選草稿保留；下一次研究只補查本頁缺口。'
            }
            else {
                $rc = [ordered]@{ schemaVersion = 1; revision = $revision.id; sourceHash = $revision.sourceHash; component = $Work.Component; topic = $Work.Topic; page = $Work.Page; cursor = $Work.Cursor; packet = $packet; packetHash = $candidateHash; review = $value; inputHash = $inp.inputHash; researchAttempt = $candidateId; reviewAttempt = $aid; acceptedAt = (Get-PsKnUtcStamp) }
                $rk = (Get-PsKnTextHash -Text $Work.Key).Substring(0, 24).ToLowerInvariant()
                Write-CbJson (Join-Path $receiptRoot ($rk + '.json')) $rc -Create
                $outcome.status = 'ACCEPTED'
            }
        }
    }
    Write-CbJson (Join-Path $ad 'outcome.json') $outcome -Create
    Write-Host ('本次結果：' + $outcome.status)
    foreach ($gap in @($outcome.findings)) { Write-Host ('  缺口：' + $gap) }
    return [string]$outcome.status
}
function Publish-Cb($State) {
    $packets = @($State.Accepted | ForEach-Object { $_.Receipt.packet })
    $gaps = @($State.Gaps)
    foreach ($w in $State.Work) { $gaps += ($w.Component + ' / ' + $w.Topic + ' 第 ' + $w.Page + ' 頁：待 ' + $w.Kind) }
    $candidates = @($State.Ledger | Where-Object { $null -ne $_.Outcome -and $_.Outcome.status -eq 'CANDIDATE' })
    foreach ($c in $candidates) {
        # 同頁已被後續候選取代時，舊草稿只留 audit trail，不再假列為目前缺口。
        $used = @($State.Accepted | Where-Object { $_.Receipt.component -ceq $c.Input.component -and $_.Receipt.topic -ceq $c.Input.topic -and [int]$_.Receipt.page -eq [int]$c.Input.page }).Count
        if ($used -eq 0) { $gaps += ('未驗收候選（不列入正文）：' + (Join-Path $c.Dir 'candidate.md')) }
    }
    $spec = ConvertTo-PsCloneSpec -Components $names -Packets $packets -Profile $profile -Status $State.Phase -Gaps $gaps
    $trace = ConvertTo-PsCloneTrace -Components $names -Packets $packets -Profile $profile -Status $State.Phase -Gaps $gaps
    $gate = [ordered]@{ schemaVersion = 1; jobId = $jobId; revision = $revision.id; sourceHash = $revision.sourceHash; status = $State.Phase; components = @($names); acceptedPages = $packets.Count; gaps = @($gaps); assurance = '結構驗證及不同 session 的 LLM 覆核；不是企業環境 E2E，也不是重建功能保證。'; receipts = @($State.Accepted | ForEach-Object { $_.Path }) }
    $generation = (Get-PsKnTextHash -Text ($spec + "`n" + $trace + "`n" + (ConvertTo-PsKnJson -Value $gate -SortKeys))).Substring(0, 24).ToLowerInvariant()
    $dir = Join-Path (Join-Path $outputRoot 'generated') $generation
    foreach ($item in @(@{ Name = 'spec.md'; Text = $spec }, @{ Name = 'trace.md'; Text = $trace }, @{ Name = 'gate.json'; Text = ((ConvertTo-PsKnJson -Value $gate -SortKeys) + "`n") })) {
        $path = Join-Path $dir $item.Name
        $ok = Write-PsKnCreateOnlyText -LiteralPath $path -Text $item.Text
        if ($null -eq $ok) { throw 'CLONE_WRITE_DEFERRED' }
        if (-not $ok -and (Read-PsKnText -LiteralPath $path) -cne $item.Text) { throw '既有 generated 檔案已被修改；保留人工內容，不覆寫。請先另存後排除衝突。' }
    }
    if ((Get-CbSource).Hash -cne $revision.sourceHash) { throw 'CLONE_SOURCE_CHANGED' }
    $readme = @('# 功能規格本機入口', '', ('狀態：' + $State.Phase), '', ('- [文件](generated/' + $generation + '/spec.md)'), ('- [證據追蹤](generated/' + $generation + '/trace.md)'), ('- [品質狀態](generated/' + $generation + '/gate.json)'), '', 'generated 是可重建投影，請勿在其中人工修稿。交付前請另存副本，補人工內容與實機確認。', 'REVIEW_READY 僅代表結構及獨立 LLM 覆核通過，不代表企業 E2E 或可無差異重建。', '', '在 PowerShell 繼續：', ('`' + $nextCommand + '`'), '', '重新研究：同命令加 -Refresh；修正失敗原因後重試：同命令加 -Retry。') -join "`n"
    Write-CbText (Join-Path $outputRoot 'README.md') ($readme + "`n")
    Write-CbJson (Join-Path $outputRoot 'current.json') ([ordered]@{ schemaVersion = 1; generation = $generation; revision = $revision.id; sourceHash = $revision.sourceHash; status = $State.Phase; specPath = (Join-Path $dir 'spec.md'); tracePath = (Join-Path $dir 'trace.md'); gatePath = (Join-Path $dir 'gate.json') })
    return (Join-Path $dir 'spec.md')
}

$exitCode = 0; $code = 'CLONE1-0-01'; $mutex = $null; $held = $false
try {
    if ($Root -eq '') { $Root = Split-Path $PSScriptRoot -Parent }
    $Root = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if (-not [System.IO.Directory]::Exists($Root) -or -not (Test-PsOcPromptSafe -PromptText $Root) -or ($Model -ne '' -and (-not (Test-PsOcPromptSafe -PromptText $Model) -or $Model -cnotmatch '^[A-Za-z0-9_][A-Za-z0-9_.:/-]*$'))) { throw 'CLONE_ARGUMENT_INVALID' }
    if (($Status -and ($Refresh -or $Retry)) -or ($Refresh -and $Retry)) { throw 'CLONE_ARGUMENT_INVALID' }
    $set = @{}
    $componentText = $Components.Trim()
    # cmd.exe 不剝單引號，PowerShell／Bash 會剝；只接受一對最外層引號，內部仍嚴格驗證。
    if ($componentText.Length -ge 2 -and $componentText.StartsWith("'") -and $componentText.EndsWith("'")) { $componentText = $componentText.Substring(1, $componentText.Length - 2) }
    foreach ($name in @($componentText -split '[,\s]+' | Where-Object { $_ -ne '' })) {
        if ($name -match '[^\x00-\x7F]') { throw 'CLONE_ARGUMENT_INVALID' }
        $upper = $name.ToUpperInvariant()
        if ($upper -cnotmatch '^[A-Z0-9_][A-Z0-9_.$#-]{0,59}$') { throw 'CLONE_ARGUMENT_INVALID' }
        $set[$upper] = $true
    }
    if ($set.Count -eq 0) { throw 'CLONE_ARGUMENT_INVALID' }
    $names = Sort-PsKnOrdinal -Items @($set.Keys)
    $jobId = 'clone-' + (Get-PsKnTextHash -Text ($names -join "`n")).Substring(0, 16).ToLowerInvariant()
    $runtimeRoot = Join-Path $Root '.ps-runtime/clone-spec'
    $jobRoot = Join-Path $runtimeRoot $jobId
    $attemptRoot = Join-Path $jobRoot 'attempts'
    $outputRoot = Join-Path (Join-Path $Root 'docs/ps-spec') $jobId
    $revisionRoot = Join-Path $jobRoot 'revisions'
    $nextCommand = "powershell -NoProfile -File '" + $PSCommandPath.Replace("'", "''") + "' -Root '" + $Root.Replace("'", "''") + "' -Components '" + ($names -join ',') + "'"
    if ($Model -ne '') { $nextCommand += " -Model '" + $Model + "'" }
    $profile = Get-PsCloneProfile -Root $Root
    if ($null -eq $profile -or @($profile.topics).Count -eq 0 -or [string]$profile.topics[0].id -ne 'scope') { throw 'clone profile 缺少 scope-first topics。' }
    # 不同 checkout 的同名 Component 是不同工作；模型服務仍由共用 session slot 串行。
    $rootLockId = (Get-PsKnTextHash -Text $Root.ToUpperInvariant()).Substring(0, 16)
    $mutex = New-Object System.Threading.Mutex($false, ('Global\MCPSample-CloneSpec-' + $rootLockId + '-' + $jobId))
    try { $held = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $held = $true }
    if (-not $held) { Write-Host '同一組功能的寫文件工作正在執行；稍後用相同命令繼續。'; $code = 'CLONE1-0-03'; $exitCode = 3 }
    else {
        $source = Get-CbSource
        $rn = Get-CbNumber $revisionRoot '^r([0-9]{4,8})\.json$'
        $revision = $null
        if ($rn -gt 0) { $revision = Read-CbJson (Join-Path $revisionRoot ('r' + $rn.ToString('0000') + '.json')) }
        if ($Status -and $null -eq $revision) { Write-Host '尚未開始。下一步：'; Write-Host $nextCommand; $code = 'CLONE1-0-02' }
        elseif ($Status -and $revision.sourceHash -cne $source.Hash) { Write-Host '狀態：STALE。知識或 agent／profile 契約已變，舊文件不可視為已覆核。下一步：'; Write-Host $nextCommand; $code = 'CLONE1-4-04'; $exitCode = 1 }
        else {
            if ($null -eq $revision -or $Refresh -or $revision.sourceHash -cne $source.Hash) {
                $rn++; $revision = [ordered]@{ schemaVersion = 1; id = ('r' + $rn.ToString('0000')); sourceHash = $source.Hash; sourceFiles = $source.Files; components = @($names); createdAt = (Get-PsKnUtcStamp) }
                Write-CbJson (Join-Path $revisionRoot ($revision.id + '.json')) $revision -Create
                Write-Host ('開始新研究版本 ' + $revision.id + '；舊版本與文件保留。')
            }
            $receiptRoot = Join-Path (Join-Path $jobRoot 'receipts') $revision.id
            $budgetRoot = Join-Path (Join-Path $jobRoot 'budgets') $revision.id
            $budget = Get-CbNumber $budgetRoot '^b([0-9]{4,8})\.json$'
            if ($budget -eq 0 -or $Retry) {
                $budget++
                if (-not $Status) { Write-CbJson (Join-Path $budgetRoot ('b' + $budget.ToString('0000') + '.json')) ([ordered]@{ revision = $revision.id; budget = $budget; createdAt = (Get-PsKnUtcStamp); explicitRetry = [bool]$Retry }) -Create }
            }
            $state = Get-CbState
            $stopReason = ''; $sessions = 0
            if (-not $Status) {
                if ($FakeWorker -eq '') { $oc = Get-PsOcPath; $ocPath = [string]$oc.Path; if ($ocPath -eq '' -and $state.Work.Count -gt 0) { throw ('無法啟動 OpenCode：' + $oc.Error) } }
                elseif (-not [System.IO.File]::Exists($FakeWorker)) { throw 'FakeWorker 不存在。' }
                $componentCursor = 0
                $sessionFailedComponents = @{}
                if ($state.Ledger.Count -gt 0) { $lastComp = [string]$state.Ledger[-1].Input.component; for ($i = 0; $i -lt $names.Count; $i++) { if ($names[$i] -ceq $lastComp) { $componentCursor = ($i + 1) % $names.Count } } }
                while ($sessions -lt $MaxSessions -and $state.Work.Count -gt 0) {
                    $work = $null
                    for ($offset = 0; $offset -lt $names.Count; $offset++) {
                        $ci = ($componentCursor + $offset) % $names.Count
                        $matches = @($state.Work | Where-Object { $_.Component -ceq $names[$ci] -and -not $sessionFailedComponents.ContainsKey($_.Component) })
                        if ($matches.Count -gt 0) { $work = $matches[0]; $componentCursor = ($ci + 1) % $names.Count; break }
                    }
                    if ($null -eq $work) { break }
                    if ((Get-CbSource).Hash -cne $revision.sourceHash) { $stopReason = 'SOURCE_CHANGED'; break }
                    $result = Invoke-CbOne $work $state
                    if ($result -ne 'SLOT_BUSY') { $sessions++ }
                    if (@('SOURCE_CHANGED', 'SLOT_BUSY') -contains $result) { $stopReason = $result; break }
                    if ($result -eq 'SESSION_FAILED') { $stopReason = $result; $sessionFailedComponents[$work.Component] = $true }
                    $state = Get-CbState
                }
                $state = Get-CbState
                if ($stopReason -eq 'SOURCE_CHANGED') { $state.Phase = 'STALE'; $state.Gaps += '來源在 session 期間改變；本次不發布。用相同命令重建新版本。' }
                else { $specPath = Publish-Cb $state }
                Write-CbJson (Join-Path $jobRoot 'job.json') ([ordered]@{ schemaVersion = 1; jobId = $jobId; components = @($names); revision = $revision.id; budget = $budget; status = $state.Phase; sourceHash = $revision.sourceHash; updatedAt = (Get-PsKnUtcStamp) })
            }
            Write-Host ('狀態：' + $state.Phase + '；本輪 session=' + $sessions + '；已接受頁=' + $state.Accepted.Count + '；待處理=' + $state.Work.Count)
            Write-Host ('入口：' + (Join-Path $outputRoot 'README.md'))
            $pointer = Read-CbJson (Join-Path $outputRoot 'current.json')
            if ($null -ne $pointer) { $label = '文件：'; if ([string]$pointer.revision -cne $revision.id) { $label = '前一版本文件（不是目前已覆核版本）：' }; Write-Host ($label + $pointer.specPath) }
            foreach ($gap in $state.Gaps) { Write-Host ('缺口：' + $gap) }
            if ($state.Phase -eq 'REVIEW_READY') { Write-Host '可人工審閱；這是結構與獨立 LLM 覆核，不是企業 E2E。交付修稿請另存副本。'; $code = 'CLONE1-7-01' }
            elseif ($state.Phase -eq 'BLOCKED') { Write-Host '下一步：檢查缺口／候選與證據，修正原因後同命令加 -Retry；範圍或來源重做用 -Refresh。'; Write-Host ($nextCommand + ' -Retry'); $code = 'CLONE1-4-03'; $exitCode = 1 }
            elseif ($state.Phase -eq 'STALE') { Write-Host '下一步：來源已變，用相同命令建立新版本。'; Write-Host $nextCommand; $code = 'CLONE1-4-04'; $exitCode = 1 }
            else { Write-Host '下一步：在 PowerShell 用相同命令繼續（不必找 Pack 或 Domain）：'; Write-Host $nextCommand; $code = 'CLONE1-3-02-' + $state.Work.Count }
            if ($stopReason -eq 'SLOT_BUSY') { Write-Host '模型服務被其他 session 使用，未消耗本頁無效次數；稍後重跑。'; $code = 'CLONE1-3-03'; $exitCode = 1 }
            if ($stopReason -eq 'SESSION_FAILED') { Write-Host 'session 失敗，未消耗本頁無效次數；檢查 OpenCode/MCP 後重跑。'; $code = 'CLONE1-3-04'; $exitCode = 1 }
        }
    }
}
catch {
    $exitCode = 1
    if ($_.Exception.Message -eq 'CLONE_WRITE_DEFERRED') { Write-Host '寫入暫時失敗，未假裝完成；解除檔案占用後用相同命令繼續。'; $code = 'CLONE1-3-07' }
    elseif ($_.Exception.Message -eq 'CLONE_SOURCE_CHANGED') { Write-Host '來源在發布前改變，未換 current；用相同命令重建。'; $code = 'CLONE1-4-04' }
    elseif ($_.Exception.Message -eq 'CLONE_ARGUMENT_INVALID') { Write-Host '參數錯誤：Components 只收 exact ASCII 物件名（逗號或空白分隔）；Status／Refresh／Retry 不可混用，Model／Root 不可含命令列控制字元。'; $code = 'CLONE1-9-01'; $exitCode = 2 }
    else { Write-Host ('無法繼續：' + $_.Exception.Message); $code = 'CLONE1-9-02'; $exitCode = 2 }
}
finally { if ($held -and $null -ne $mutex) { $mutex.ReleaseMutex() }; if ($null -ne $mutex) { $mutex.Dispose() } }
Write-Host $code
exit $exitCode
