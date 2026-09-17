# ps-spec.ps1 — Spec 引擎 CLI：私有需求包驗證／規劃／外環派工／render／gate／doctor
# 用法（公司機）：powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ps-spec.ps1 -ValidatePack -Pack <packId>
#                powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ps-spec.ps1 -Plan -JobId <jobId> -Component TW_X -Pack <packId> [-DomainHint <領域>]
#                powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ps-spec.ps1 -Run -JobId <jobId> [-MaxSessions 4] [-Model m] [-TimeoutMin 30]
#                powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ps-spec.ps1 -Render -JobId <jobId>
#                powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ps-spec.ps1 -Gate -JobId <jobId>
#                powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ps-spec.ps1 -Doctor [-JobId <jobId>] [-Drill <stage>-<code>] [-WriteGenericManifest]
# 路徑：pack＝<PrivateRoot>/<packId>/（預設 .ps-private/spec/）；job＝<RuntimeRoot>/<jobId>/（預設 .ps-runtime/spec/）；兩者皆 gitignore。
#       -RuntimeRoot 只供測試（-FakeWorker）：worker 的 command 與 permission 把工單路徑固定在 <Root>/.ps-runtime/spec/，派真 worker 時不是預設值＝SPEC1-9-07。
# 只讀 docs/ps-research/**、docs/ps-research/knowledge/index.json（每個動詞都先 check，STALE 即重建：等級要看現況）、.ps-private；只寫 .ps-runtime/spec/<jobId>/、
# docs/ps-research/supplemental/requests/（KnowledgeNeed）、docs/ps-research/knowledge/（重建）、.opencode/peoplesoft/spec/generic.manifest.json（-WriteGenericManifest）。
# 永不寫 NN／wiki／checklist。worker session：opencode run --command ps-spec-batch "<jobId>-<attemptId>"（agent ps-spec-worker 只寫 fragment.md）。
# 最後一行永遠是唯一結論碼 SPEC1-<stage>-<code>[-<count>]（碼表 .opencode/peoplesoft/spec/support-codes.md；不含路徑／物件名／hash）；
# -Render／-Gate 只印結論碼。exit：0＝完成／1＝未達（BLOCKED、gate 未過、映射未簽核、來源已變…）／2＝環境或參數錯／3＝job 互斥鎖被占用。
# -FakeWorker <ps1>：測試專用——以該腳本取代 opencode session（收 -AttemptDir -ManifestPath -FragmentPath），公司機不用。
param(
    [switch]$ValidatePack,
    [switch]$Plan,
    [switch]$Run,
    [switch]$Render,
    [switch]$Gate,
    [switch]$Doctor,
    [string]$JobId = '',
    [string]$Pack = '',
    [string]$Component = '',
    [string]$DomainHint = '',
    [string]$Root = '',
    [string]$PrivateRoot = '',
    [string]$RuntimeRoot = '',
    [string]$LogRoot = '',
    [string]$Model = '',
    [int]$TimeoutMin = 30,
    [int]$MaxSessions = 4,
    [string]$Drill = '',
    [switch]$WriteGenericManifest,
    [string]$FakeWorker = ''
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path $PSScriptRoot -Parent }
$Root = [System.IO.Path]::GetFullPath($Root)
if ($PrivateRoot -ne '') { $PrivateRoot = [System.IO.Path]::GetFullPath($PrivateRoot) }
if ($RuntimeRoot -ne '') { $RuntimeRoot = [System.IO.Path]::GetFullPath($RuntimeRoot) }
if ($LogRoot -eq '') { $LogRoot = Join-Path $Root (Join-Path 'auto-loop-logs' 'spec') } else { $LogRoot = [System.IO.Path]::GetFullPath($LogRoot) }
. (Join-Path $PSScriptRoot 'ps-knowledge-lib.ps1')
. (Join-Path $PSScriptRoot 'ps-supplemental-lib.ps1')
. (Join-Path $PSScriptRoot 'ps-session-lib.ps1')
. (Join-Path $PSScriptRoot 'ps-spec-lib.ps1')

function Finish([string]$Code, [int]$Exit) { Write-Host $Code; exit $Exit }
function Say([string]$m) { if (-not ($Render -or $Gate)) { Write-Host $m } }

if ($PsKnowledgeLibVersion -ne 1 -or $PsSupplementalLibVersion -ne 1 -or $PsSessionLibVersion -ne 1 -or $PsSpecLibVersion -ne 1) { Say 'SYSTEM ERROR：lib 版本不符'; Finish 'SPEC1-9-06' 2 }
$modes = 0
foreach ($m in @($ValidatePack, $Plan, $Run, $Render, $Gate, $Doctor)) { if ($m) { $modes++ } }
if ($modes -ne 1) { Say '用法：-ValidatePack -Pack <packId> | -Plan -JobId <jobId> -Component <物件> -Pack <packId> [-DomainHint <領域>] | -Run -JobId <jobId> [-MaxSessions n] | -Render -JobId <jobId> | -Gate -JobId <jobId> | -Doctor [-JobId <jobId>] [-Drill <stage>-<code>] [-WriteGenericManifest]（擇一）'; Finish 'SPEC1-9-01' 2 }
if ($JobId -ne '' -and -not (Test-PsSpId -Id $JobId)) { Say ('jobId 不符文法 ' + $script:PsSpIdRx + '（小寫英數與連字號，≤32）'); Finish 'SPEC1-9-05' 2 }
if ($Pack -ne '' -and -not (Test-PsSpId -Id $Pack)) { Say ('packId 不符文法 ' + $script:PsSpIdRx); Finish 'SPEC1-9-05' 2 }
if (($Plan -or $Run -or $Render -or $Gate) -and $JobId -eq '') { Say '缺 -JobId'; Finish 'SPEC1-9-01' 2 }
if ($Plan -and ($Pack -eq '' -or $Component -eq '')) { Say '-Plan 需要 -Component 與 -Pack'; Finish 'SPEC1-9-01' 2 }
if ($ValidatePack -and $Pack -eq '') { Say '-ValidatePack 需要 -Pack'; Finish 'SPEC1-9-01' 2 }
if ($Component -ne '' -and $Component.Trim().ToUpperInvariant() -notmatch '^[A-Z0-9_][A-Z0-9_.$#-]{0,59}$') { Say 'Component 不符物件名文法'; Finish 'SPEC1-9-05' 2 }

$dirs = Get-PsSpDirs -Root $Root -PrivateRoot $PrivateRoot -RuntimeRoot $RuntimeRoot -PackId $Pack -JobId $JobId
$caps = $null
try { $caps = Get-PsSpCapabilities -Root $Root } catch { Say ('SYSTEM ERROR：' + $_.Exception.Message); Finish 'SPEC1-9-02' 2 }

# ── -Doctor：stage 0 完整性 → job 摘要 → drill tuple ──────────────
if ($Doctor) {
    if ($WriteGenericManifest) {
        $w = New-PsSpGenericManifest -Root $Root
        Say ('SPEC：generic manifest files=' + $w.Count)
        if (-not $w.Ok) { Finish 'SPEC1-0-05' 1 }
        Finish 'SPEC1-0-04' 0
    }
    $g = Test-PsSpGenericManifest -Root $Root
    if ($g.ManifestMissing) { Say 'SPEC：generic manifest 不存在（維護端跑 -Doctor -WriteGenericManifest）' }
    else { Say ('SPEC：generic missing=' + $g.Missing + ' modified=' + $g.Modified + ' extra=' + $g.Extra) }
    $drillLines = @()
    $planObj = $null; $idx = $null; $gateObj = $null
    if ($JobId -ne '') {
        $job = Read-PsSpJob -Dirs $dirs
        if ($null -eq $job) { Say 'SPEC：job 不存在'; if (-not $g.Ok) { Finish ('SPEC1-0-01-' + $g.Count) 1 }; Finish 'SPEC1-9-03' 2 }
        $idx = Read-PsKnowledgeIndex -Root $Root
        $planObj = Read-PsSpPlan -Dirs $dirs -PlanRef ([string]$job.currentPlanRef)
        $cur = Read-PsSpJsonFile -LiteralPath $dirs.CurrentFile
        if ($null -ne $cur) {
            # gate 指標（最後一次 -Gate／-Render 評估的世代）優先於 render 指標
            $gg = [string](Get-PsSpProp $cur 'gateGeneration')
            if ($gg -eq '') { $gg = [string]$cur.generation }
            if ($gg.Length -ge 16) { $gateObj = Read-PsSpJsonFile -LiteralPath (Join-Path (Join-Path $dirs.Outputs ($gg.Substring(0, 16).ToLowerInvariant())) 'gate.json') }
        }
        $units = 0; $receipts = 0; $pending = 0; $blocked = 0; $waiting = 0; $changed = 0
        if ($null -ne $planObj -and $null -ne $idx) {
            foreach ($s in (Get-PsSpUnitStatus -Root $Root -Dirs $dirs -Plan $planObj -Index $idx)) {
                $units++
                switch ([string]$s.State) { 'HAS_RECEIPT' { $receipts++ } 'PENDING' { $pending++ } 'SOURCE_CHANGED' { $changed++ } 'BLOCKED' { $blocked++ } 'BLOCKED_CAPACITY' { $blocked++ } default { $waiting++ } }
            }
        }
        $verdict = 'NONE'
        if ($null -ne $gateObj) { $verdict = [string]$gateObj.verdict }
        Say ('SPEC：phase=' + [string]$job.phase + ' units=' + $units + ' receipts=' + $receipts + ' pending=' + $pending + ' changed=' + $changed + ' blocked=' + $blocked + ' waiting=' + $waiting + ' verdict=' + $verdict)
        if ($Drill -ne '') { $drillLines = Get-PsSpDrill -Root $Root -Dirs $dirs -Plan $planObj -Index $idx -Code $Drill -Gate $gateObj }
    }
    elseif ($Drill -ne '') { $drillLines = Get-PsSpDrill -Root $Root -Dirs $dirs -Plan $null -Index $null -Code $Drill }
    foreach ($l in $drillLines) { Write-Host $l }
    if ($Drill -ne '') { Finish ('SPEC1-0-05-' + $drillLines.Count) 0 }
    if ($g.ManifestMissing) { Finish 'SPEC1-0-02' 1 }
    if (-not $g.Ok) { Finish ('SPEC1-0-01-' + $g.Count) 1 }
    Finish 'SPEC1-0-03' 0
}

# ── -ValidatePack ─────────────────────────────────────────────────
if ($ValidatePack) {
    $v = Test-PsSpPack -PackDir $dirs.PackDir -Capabilities $caps
    foreach ($e in $v.Errors) { Say ('PACK：' + $e) }
    if ($v.Errors.Count -gt 0) {
        if ($v.Errors.Count -eq 1 -and $v.Errors[0] -like 'PACK_NOT_FOUND*') { Finish 'SPEC1-1-02' 2 }
        if ($v.Errors.Count -eq 1 -and $v.Errors[0] -like 'TEMPLATE_MISSING*') { Finish 'SPEC1-1-04' 1 }
        Finish ('SPEC1-1-03-' + $v.Errors.Count) 1
    }
    Say ('SPEC：pack=' + $v.PackId + ' v' + $v.PackVersion + ' reviewed=' + $v.ReviewedVersion + ' requirements=' + $v.Requirements.Count + ' slots=' + @($v.Pack.slots).Count + ' checklist=' + @($v.Pack.checklist).Count + ' content=' + $v.ContentHash.Substring(0, 16) + ' binding=' + $v.BindingHash.Substring(0, 16))
    if (-not $v.Signed) { Say 'SPEC：reviewedVersion ≠ packVersion（內部覆核後填 reviewedVersion）'; Finish 'SPEC1-8-01' 1 }
    Finish 'SPEC1-1-01' 0
}

# 以下動詞都需要 job 互斥鎖（memo §6.5）：ctor 例外→exit 2；WaitOne(0) false→exit 3；abandoned＝取得
$mutex = $null
try { $mutex = New-Object System.Threading.Mutex($false, ('Global\MCPSample-Spec-' + $JobId)) } catch { Say ('SYSTEM ERROR：互斥鎖無法建立 ' + $_.Exception.Message); Finish 'SPEC1-9-02' 2 }
$held = $false
try { $held = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $held = $true }
if (-not $held) { try { $mutex.Dispose() } catch { }; Say 'SPEC：job 互斥鎖被占用（另一個 ps-spec 正在跑同一 job）'; Finish 'SPEC1-9-04' 3 }
$code = 'SPEC1-9-02'; $exitCode = 2
try {
    if (-not [System.IO.Directory]::Exists($dirs.Research)) { Say ('SYSTEM ERROR：找不到 ' + $dirs.Research); throw 'ENV' }
    # ── -Plan ─────────────────────────────────────────────────────
    if ($Plan) {
        $v = Test-PsSpPack -PackDir $dirs.PackDir -Capabilities $caps
        foreach ($e in $v.Errors) { Say ('PACK：' + $e) }
        if ($v.Errors.Count -gt 0) { if ($v.Errors.Count -eq 1 -and $v.Errors[0] -like 'PACK_NOT_FOUND*') { $code = 'SPEC1-1-02'; $exitCode = 2; throw 'DONE' }; $code = 'SPEC1-1-03-' + $v.Errors.Count; $exitCode = 1; throw 'DONE' }
        if (-not $v.Signed) { Say 'SPEC：reviewedVersion ≠ packVersion（可規劃，gate 將標 8-01）' }
        $chk = Test-PsKnowledgeIndex -Root $Root
        if ($chk.State -ne 'CURRENT') { $pub = Publish-PsKnowledgeIndex -Root $Root; Say ('SPEC：知識索引 ' + $chk.State + ' → 重建 published=' + $pub.published) }
        $idx = Read-PsKnowledgeIndex -Root $Root
        if ($null -eq $idx) { Say 'SYSTEM ERROR：知識索引無法讀取'; throw 'ENV' }
        $job = Read-PsSpJob -Dirs $dirs
        if ($null -eq $job) { $job = New-PsSpJob -JobId $JobId -PackV $v -Component $Component -DomainHint $DomainHint }
        else {
            if ([string]$job.packId -ne $v.PackId -or [string]$job.component -ne $Component.Trim().ToUpperInvariant()) { Say 'SPEC：job 已綁定另一個 pack／Component（換 jobId）'; $code = 'SPEC1-9-01'; $exitCode = 2; throw 'DONE' }
            $job.packVersion = $v.PackVersion; $job.contentHash = $v.ContentHash; $job.bindingHash = $v.BindingHash
            if ($DomainHint -ne '') { $job.domainHint = $DomainHint }
        }
        $hint = $DomainHint
        if ($hint -eq '') { $hint = [string]$job.domainHint }
        $np = New-PsSpPlan -Root $Root -Dirs $dirs -PackV $v -JobId $JobId -Component $Component -DomainHint $hint -Index $idx -Capabilities $caps
        $id = $np.Identity
        if ($id.State -ne 'OK') {
            Say ('SPEC：identity=' + $id.State + ' candidates=' + @($id.Candidates).Count)
            if ($id.State -eq 'AMBIGUOUS') { $code = 'SPEC1-2-04-' + @($id.Candidates).Count; $exitCode = 1; throw 'DONE' }
            if ($id.State -eq 'HINT_MISS') { $code = 'SPEC1-2-05'; $exitCode = 1; throw 'DONE' }
            if ($hint -ne '') {
                # 目標尚無 NN：以 DomainHint 提交 KnowledgeNeed（Research 相位建檔），並寫一個只含該 need 的 plan（無 facts／units）——
                # 之後 -Run 回 5-01 等待、result 到達回 5-06，重跑 -Plan 才真正抽取（planHash 隨 need 狀態變）
                $needRid = Get-PsSpNeedRequirementId -PackV $v
                $need = [ordered]@{ target = [ordered]@{ type = 'COMPONENT'; name = $Component.Trim().ToUpperInvariant() }; context = [ordered]@{}; factKind = 'UI.COMPONENT_IDENTITY'; properties = @('primaryObject', 'origin', 'status', 'functionName'); evidencePolicy = 'ANY'; freshness = 'CURRENT' }
                $rs = Resolve-PsSpNeed -Root $Root -Need $need -JobId $JobId -RequirementId $needRid -DomainHint $hint -Reason 'MISSING' -Index $idx
                Say ('SPEC：need=' + $rs.State)
                if ($rs.State -eq 'ROUTING_REQUIRED') { $code = 'SPEC1-5-07-1'; $exitCode = 1; throw 'DONE' }
                if ($rs.State -eq 'INVALID') { $code = 'SPEC1-5-08-1'; $exitCode = 1; throw 'DONE' }
                $needState = 'WAITING_KNOWLEDGE'
                if ($rs.State -eq 'BLOCKED_KNOWLEDGE') { $needState = 'BLOCKED_KNOWLEDGE' }
                $np2 = New-PsSpNeedOnlyPlan -PackV $v -JobId $JobId -Component $Component -Domain $hint -Need $need -Resolve $rs -State $needState
                $wp = Write-PsSpPlan -Dirs $dirs -Plan $np2
                if ($wp.Deferred) { $code = 'SPEC1-2-07'; $exitCode = 1; throw 'DONE' }
                Say ('SPEC：plan=' + $wp.PlanRef + ' created=' + $wp.Created + ' domain=' + $hint + ' facts=0 units=0（身分 need：' + $needState + '）')
                $job.domain = $hint; $job.currentPlanRef = $wp.PlanRef; $job.phase = Get-PsSpPhaseFromPlan -Plan $np2
                if ($needState -eq 'BLOCKED_KNOWLEDGE') { $code = 'SPEC1-5-05-1'; $exitCode = 1 } else { $code = 'SPEC1-5-01-1'; $exitCode = 0 }
                $job.lastCode = $code
                if (-not (Write-PsSpJob -Dirs $dirs -Job $job)) { $code = 'SPEC1-2-07'; $exitCode = 1 }
                throw 'DONE'
            }
            $code = 'SPEC1-2-03'; $exitCode = 1; throw 'DONE'
        }
        $wp = Write-PsSpPlan -Dirs $dirs -Plan $np.Plan
        if ($wp.Deferred) { Say 'SPEC：plan.json 寫入延遲（WRITE_DEFERRED）'; $code = 'SPEC1-2-07'; $exitCode = 1; throw 'DONE' }
        $s = $np.Summary
        Say ('SPEC：plan=' + $wp.PlanRef + ' created=' + $wp.Created + ' domain=' + [string]$np.Plan.domain + ' facts=' + $s.facts + ' units=' + $s.units + ' unknown=' + $s.unknown + ' unsupported=' + $s.unsupported)
        Say ('SPEC：knowledge submitted=' + $s.submitted + ' resubmitted=' + $s.resubmitted + ' pending=' + $s.pending + ' waitingAudit=' + $s.waitingAudit + ' blocked=' + $s.blocked + ' routing=' + $s.routing)
        $job.domain = [string]$np.Plan.domain
        $job.currentPlanRef = $wp.PlanRef
        $job.phase = Get-PsSpPhaseFromPlan -Plan $np.Plan
        if ($wp.Created) { $code = 'SPEC1-2-01-' + $s.units } else { $code = 'SPEC1-2-02-' + $s.units }
        $job.lastCode = $code
        if (-not (Write-PsSpJob -Dirs $dirs -Job $job)) { $code = 'SPEC1-2-07'; $exitCode = 1; throw 'DONE' }
        $exitCode = 0
        throw 'DONE'
    }
    # ── -Run／-Render／-Gate 共同前置：job、plan、pack、索引 ──────────
    $job = Read-PsSpJob -Dirs $dirs
    if ($null -eq $job) { Say 'SPEC：job 不存在（先 -Plan）'; $code = 'SPEC1-9-03'; $exitCode = 2; throw 'DONE' }
    $planObj = Read-PsSpPlan -Dirs $dirs -PlanRef ([string]$job.currentPlanRef)
    if ($null -eq $planObj) { Say 'SPEC：無 plan（先 -Plan）'; if ($Run) { $code = 'SPEC1-3-06' } else { $code = 'SPEC1-6-03' }; $exitCode = 2; throw 'DONE' }
    $packDirs = Get-PsSpDirs -Root $Root -PrivateRoot $PrivateRoot -RuntimeRoot $RuntimeRoot -PackId ([string]$job.packId) -JobId $JobId
    $v = Test-PsSpPack -PackDir $packDirs.PackDir -Capabilities $caps
    if (-not $v.Ok) { foreach ($e in $v.Errors) { Say ('PACK：' + $e) }; $code = 'SPEC1-1-03-' + $v.Errors.Count; $exitCode = 1; throw 'DONE' }
    if ($v.ContentHash -cne [string]$planObj.contentHash) { Say 'SPEC：pack 內容（contentHash）已變，plan 過期 → 重跑 -Plan'; $code = 'SPEC1-2-08'; $exitCode = 1; throw 'DONE' }
    # 等級是稽核／checklist／audit-done 的性質，不是 NN bytes 的性質：每個動詞都用現況索引（STALE 即重建），gate 才抓得到規劃後的等級下降
    $chk = Test-PsKnowledgeIndex -Root $Root
    if ($chk.State -ne 'CURRENT') { $pub = Publish-PsKnowledgeIndex -Root $Root; Say ('SPEC：知識索引 ' + $chk.State + ' → 重建 published=' + $pub.published) }
    $idx = Read-PsKnowledgeIndex -Root $Root
    if ($null -eq $idx) { Say 'SYSTEM ERROR：知識索引不存在（先 -Plan）'; throw 'ENV' }
    if ($Run) {
        $dispatch = $null
        if ($FakeWorker -ne '') {
            $fw = [System.IO.Path]::GetFullPath($FakeWorker)
            $dispatch = {
                param($a)
                # 假 worker 以標準輸出一行 FAILURE_KIND=<kind> 模擬 session 層事件（真 session 由 out／err 檔判 CONTEXT_OVERFLOW）
                $outLines = @(& $fw -AttemptDir $a.AttemptDir -ManifestPath $a.ManifestPath -FragmentPath $a.FragmentPath | ForEach-Object { [string]$_ })
                $ec = $LASTEXITCODE
                if ($null -eq $ec) { $ec = 0 }
                $fk = 'FAKE'
                foreach ($ol in $outLines) { $m = [regex]::Match($ol, '^FAILURE_KIND=([A-Z_]+)$'); if ($m.Success) { $fk = $m.Groups[1].Value } }
                return @{ TimedOut = $false; ExitCode = [int]$ec; FailureKind = $fk; SlotBusy = $false }
            }.GetNewClosure()
        }
        else {
            # 真 worker：command 與 permission 把工單固定在 <Root>/.ps-runtime/spec/<jobId>/attempts/<attemptId>/，RuntimeRoot 不是預設值就派不動
            $rtExpected = [System.IO.Path]::GetFullPath((Join-Path $Root (Join-Path '.ps-runtime' 'spec'))).TrimEnd('\', '/')
            $rtActual = [System.IO.Path]::GetFullPath($dirs.RuntimeRoot).TrimEnd('\', '/')
            if (-not [string]::Equals($rtActual, $rtExpected, [System.StringComparison]::OrdinalIgnoreCase)) { Say 'SPEC：-RuntimeRoot 只供測試（-FakeWorker）；派 worker session 時 job 目錄必須是 <Root>/.ps-runtime/spec/'; $code = 'SPEC1-9-07'; $exitCode = 2; throw 'DONE' }
            $oc = Get-PsOcPath
            if ($oc.Path -eq '') { Say ('SYSTEM ERROR：' + $oc.Error); $code = 'SPEC1-3-05'; $exitCode = 2; throw 'DONE' }
            $ocPath = $oc.Path
            $dispatch = {
                param($a)
                $prompt = $a.JobId + '-' + $a.AttemptId
                $tag = 'spec-' + $a.JobId + '-' + $a.AttemptId
                $sr = Invoke-PsOcSession -OcPath $ocPath -Root $Root -LogRoot (Join-Path $LogRoot $a.JobId) -Model $Model -ExtraArgs '--command ps-spec-batch' -PromptText $prompt -TimeoutMin $TimeoutMin -Tag $tag -Log { param($m) Write-Host $m } -SlotWaitMin 10 -TimeoutParamName 'TimeoutMin'
                return @{ TimedOut = [bool]$sr.TimedOut; ExitCode = [int]$sr.ExitCode; FailureKind = [string]$sr.FailureKind; SlotBusy = [bool]$sr.SlotBusy }
            }.GetNewClosure()
        }
        $prevPhase = [string]$job.phase
        $job.phase = 'RUNNING'
        [void](Write-PsSpJob -Dirs $dirs -Job $job)
        $rr = $null
        try { $rr = Invoke-PsSpRun -Root $Root -Dirs $dirs -Plan $planObj -PackV $v -Capabilities $caps -JobId $JobId -MaxSessions $MaxSessions -Dispatch $dispatch -Log { param($m) Write-Host $m } -Index $idx }
        finally {
            # 任何離開路徑（含例外）都不得把 job.json 留在 RUNNING
            if ($null -eq $rr) { $job.phase = $prevPhase; $job.lastCode = 'SPEC1-9-02'; [void](Write-PsSpJob -Dirs $dirs -Job $job) }
        }
        Say ('SPEC：sessions=' + $rr.Sessions + ' accepted=' + $rr.Accepted + ' invalid=' + $rr.Invalid + ' splits=' + $rr.Splits + ' pending=' + $rr.Pending + ' blocked=' + $rr.Blocked + ' waiting=' + $rr.Waiting + ' sourceChanged=' + $rr.SourceChanged + ' replan=' + $rr.Replan + ' writeDeferred=' + $rr.WriteDeferred)
        if ($rr.Code -match '^SPEC1-5-0[14]-(\d+)$') { Say ('SPEC：' + $rr.Phase + ' n=' + $Matches[1]) }
        $job.phase = $rr.Phase; $job.lastCode = $rr.Code
        [void](Write-PsSpJob -Dirs $dirs -Job $job)
        $code = $rr.Code; $exitCode = $rr.Exit
        throw 'DONE'
    }
    # ── -Render／-Gate（不印任何內容）──────────────────────────────
    $rd = Invoke-PsSpRender -Root $Root -Dirs $dirs -Plan $planObj -PackV $v -Capabilities $caps -Index $idx -GateOnly ([bool]$Gate)
    if ($Render -and $rd.Exit -eq 0) { $job.phase = 'PUBLISHED'; $job.lastCode = $rd.Code; [void](Write-PsSpJob -Dirs $dirs -Job $job) }
    if ($Gate -and $rd.Code -ne '') { $job.lastCode = $rd.Code; [void](Write-PsSpJob -Dirs $dirs -Job $job) }
    $code = $rd.Code; $exitCode = $rd.Exit
    throw 'DONE'
}
catch {
    if ($_.ToString() -ne 'DONE' -and $_.ToString() -ne 'ENV') { Say ('SYSTEM ERROR：' + $_.Exception.Message + ' @ ' + $_.InvocationInfo.ScriptLineNumber); $code = 'SPEC1-9-02'; $exitCode = 2 }
    if ($_.ToString() -eq 'ENV') { $code = 'SPEC1-9-02'; $exitCode = 2 }
}
finally {
    try { $mutex.ReleaseMutex() } catch { }
    try { $mutex.Dispose() } catch { }
}
Finish $code $exitCode
