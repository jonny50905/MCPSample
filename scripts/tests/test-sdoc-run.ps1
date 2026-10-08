# test-sdoc-run.ps1 — Spec 文件流程外環（ps-sdoc.ps1）端到端：合成 worker 依工單回狀態圖解讀、研究包、覆核；不查 MCP、不呼叫模型。
# 以設計範例（walkthrough、gate）為來源：從空目錄跑到發布，比對發布的 canonical 與範例，並驗結論碼、中斷、重試、重跑、裁決與核准。
# 用法：pwsh -NoProfile -File scripts/tests/test-sdoc-run.ps1   （公司機：powershell -NoProfile -ExecutionPolicy Bypass -File …）
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
foreach ($f in @('ps-knowledge-lib', 'ps-sdoc-schema-lib', 'ps-sdoc-status-lib', 'ps-sdoc-lib')) { . (Join-Path $repo ('scripts/' + $f + '.ps1')) }
. (Join-Path $PSScriptRoot 'sdoc-test-fixtures.ps1')
$script:failed = 0; $script:passed = 0
function Assert-Sd([bool]$Condition, [string]$Name, [string]$Detail = '') {
    if ($Condition) { $script:passed++; Write-Host ('PASS ' + $Name) }
    else { $script:failed++; Write-Host ('FAIL ' + $Name); if ($Detail) { Write-Host ('     ' + $Detail) } }
}
$design = Join-Path $repo 'docs/design/spec-schema-framework'
$base = Join-Path ([System.IO.Path]::GetTempPath()) ('ps-sdoc-run-' + [guid]::NewGuid().ToString('N'))
# 凍結這次待測的腳本，避免並行維護同一 checkout 時被誤判成來源改變
$tools = Join-Path $base 'framework'
[void][System.IO.Directory]::CreateDirectory($tools)
foreach ($n in @('ps-sdoc.ps1', 'ps-sdoc-schema-lib.ps1', 'ps-sdoc-status-lib.ps1', 'ps-sdoc-lib.ps1', 'ps-sdoc-check-lib.ps1', 'ps-sdoc-render-lib.ps1', 'ps-knowledge-lib.ps1', 'ps-session-lib.ps1', 'ps-cli-lib.ps1')) {
    Copy-Item -LiteralPath (Join-Path $repo ('scripts/' + $n)) -Destination (Join-Path $tools $n)
}
$cli = Join-Path $tools 'ps-sdoc.ps1'
$priorEnv = @{ Cli = $env:PS_CLI; Lib = $env:PS_SDOC_TEST_LIB; Fx = $env:PS_SDOC_TEST_FIXTURES; Mode = $env:PS_SDOC_TEST_MODE }
$env:PS_CLI = ''
$env:PS_SDOC_TEST_LIB = $tools

function Write-SdFx([string]$Path, [string]$Text, [bool]$Bom = $false) {
    if (-not (Write-PsKnAtomicText -LiteralPath $Path -Text $Text -Bom $Bom)) { throw 'TEST_WRITE_FAILED' }
}
function Read-SdFxJson([string]$Path) { return , (ConvertTo-PsSdNode (Read-PsSdJsonFile $Path)) }

# ---------------- 合成 worker（外環以 -FakeWorker 在同一行程呼叫） ----------------
$script:fakeWorker = Join-Path $base 'fake-worker.ps1'
$fakeText = @'
param([string]$AttemptDir, [string]$InputPath, [string]$OutputPath, [string]$Kind, [string]$Root)
$ErrorActionPreference = 'Stop'
$lib = $env:PS_SDOC_TEST_LIB; $fx = $env:PS_SDOC_TEST_FIXTURES
$mode = @(([string]$env:PS_SDOC_TEST_MODE) -split ',' | Where-Object { $_ -ne '' })
. (Join-Path $lib 'ps-knowledge-lib.ps1'); . (Join-Path $lib 'ps-sdoc-schema-lib.ps1')
function Read-FwJson([string]$Path) { return , (ConvertTo-PsSdNode (Read-PsSdJsonFile $Path)) }
function Write-FwOut($Value) { [System.IO.File]::WriteAllText($OutputPath, ((ConvertTo-PsKnJson -Value $Value) + "`n"), (New-Object System.Text.UTF8Encoding($false))) }
function Test-FwOnce([string]$Flag) {
    # 只觸發一次的模式：第一次回 $true 並留下記號
    if ($mode -notcontains $Flag) { return $false }
    $mark = Join-Path $fx ('marks/' + $Flag)
    if ([System.IO.File]::Exists($mark)) { return $false }
    [void][System.IO.Directory]::CreateDirectory((Join-Path $fx 'marks'))
    [System.IO.File]::WriteAllText($mark, 'x')
    return $true
}
$inp = Read-FwJson $InputPath
$unit = [string]$inp['unit']; $subj = [string]$inp['subject']; $page = [int]$inp['page']
[System.IO.File]::AppendAllText((Join-Path $fx 'calls.log'), ($Kind + ' ' + $unit + ' ' + $subj + ' ' + $page + "`n"))
if (Test-FwOnce 'session-fail-once') { exit 1 }
if (Test-FwOnce 'stray-once') { [System.IO.File]::WriteAllText((Join-Path $AttemptDir 'stray.txt'), 'x') }
if (Test-FwOnce 'touch-status-once') { [System.IO.File]::AppendAllText((Join-Path $Root ([string]$inp['statusPath'])), "`n") }
if ($Kind -eq 'STATUS_READ') {
    $r = Read-FwJson (Join-Path $fx ('readings/' + [string]$inp['reader'] + '.json'))
    $r['jobId'] = [string]$inp['jobId']; $r['source']['ref'] = 'status.md'; $r['source']['fingerprint'] = [string]$inp['statusFingerprint']
    if ($mode -contains ('bad-read-' + [string]$inp['reader'])) { $r['source']['fingerprint'] = ('0' * 64) }
    Write-FwOut $r; exit 0
}
if ($Kind -eq 'STATUS_ROUND2') {
    $truth = Read-FwJson (Join-Path $fx 'round2.json')
    $o = New-PsSdObject; $o['schemaVersion'] = '1.0'; $o['jobId'] = [string]$inp['jobId']; $o['reader'] = [string]$inp['reader']; $o['round'] = 2
    $src = New-PsSdObject; $src['ref'] = 'status.md'; $src['fingerprint'] = [string]$inp['statusFingerprint']; $o['source'] = $src
    $ans = @()
    foreach ($q in @($inp['questions'])) {
        $a = New-PsSdObject; $a['id'] = [string]$q['id']; $v = 'UNSURE'
        if ($mode -notcontains 'round2-unsure' -and $truth.Contains([string]$q['id'])) { $v = [string]$truth[[string]$q['id']] }
        $a['answer'] = $v; $ans += , $a
    }
    $o['answers'] = $ans
    Write-FwOut $o; exit 0
}
if ($Kind -eq 'RESEARCH') {
    $src = Join-Path $fx ('research/' + $unit + '/' + $subj + '.json')
    if ([System.IO.File]::Exists($src)) { $pk = Read-FwJson $src }
    else {
        $pk = New-PsSdObject
        foreach ($kv in @(@('schemaVersion', '1.0'), @('jobId', ''), @('attemptId', ''), @('unit', $unit), @('subject', $subj), @('page', 1), @('inputHash', ''), @('coverage', 'COMPLETE'), @('summary', '合成：範例在這個主題沒有內容。'))) { $pk[$kv[0]] = $kv[1] }
        $pk['items'] = @(); $pk['evidence'] = @(); $pk['questions'] = @(); $pk['requests'] = @(); $pk['nextCursor'] = ''
    }
    $pk['jobId'] = [string]$inp['jobId']; $pk['attemptId'] = [string]$inp['attemptId']; $pk['unit'] = $unit; $pk['subject'] = $subj; $pk['page'] = $page
    $pk['inputHash'] = [string]$inp['inputHash']; $pk['coverage'] = 'COMPLETE'; $pk['nextCursor'] = ''
    $all = @($pk['items'])
    if ($mode -contains ('partial-' + $unit + '-' + $subj) -and $all.Count -ge 2) {
        $half = [int][Math]::Floor($all.Count / 2)
        if ($page -eq 1) {
            $pk['items'] = @($all[0..($half - 1)]); $pk['coverage'] = 'PARTIAL'; $pk['nextCursor'] = 'P2'; $pk['questions'] = @()
            foreach ($x in @('statusTexts', 'programDispositions', 'definitionOnlyCodes')) { if ($pk.Contains($x)) { $pk.Remove($x) } }
        }
        else { $pk['items'] = @($all[$half..($all.Count - 1)]); if ($pk.Contains('denominators')) { $pk.Remove('denominators') } }
    }
    if ($mode -contains ('bad-packet-' + $unit) -and $all.Count -gt 0) { $pk['items'] = @($all) + @($all[0]) }
    if (Test-FwOnce ('dup-' + $unit + '-' + $subj)) {
        # 重寫別的主題已驗收的項目（全 job 同一個自然鍵只寫一次）
        foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $fx ('research/' + $unit)) -Filter '*.json')) {
            if ($f.BaseName -cne $subj) { $other = Read-FwJson $f.FullName; if (@($other['items']).Count -gt 0) { $pk['items'] = @($pk['items']) + @(@($other['items'])[0]); break } }
        }
    }
    Write-FwOut $pk; exit 0
}
if ($Kind -eq 'REVIEW') {
    $pk = $inp['packet']
    $keys = @(); foreach ($it in @($pk['items'])) { $keys += ([string]$it['type'] + '/' + [string]$it['key']) }
    $o = New-PsSdObject
    foreach ($kv in @(@('schemaVersion', '1.0'), @('jobId', [string]$inp['jobId']), @('attemptId', [string]$inp['attemptId']), @('unit', $unit), @('subject', $subj), @('page', $page), @('inputHash', [string]$inp['inputHash']))) { $o[$kv[0]] = $kv[1] }
    if (Test-FwOnce ('review-fail-once-' + $unit)) {
        $f = New-PsSdObject; $f['key'] = 'TOPIC'; if ($keys.Count -gt 0) { $f['key'] = $keys[0] }; $f['code'] = 'MISSING_DETAIL'; $f['detail'] = '合成：第一次覆核刻意不通過。'
        $o['verdict'] = 'FAIL'; $o['checkedKeys'] = @($keys); $o['findings'] = @($f); $o['summary'] = '合成：覆核不通過。'
    }
    else { $o['verdict'] = 'PASS'; $o['checkedKeys'] = @($keys); $o['findings'] = @(); $o['summary'] = '合成：逐項核對通過。' }
    Write-FwOut $o; exit 0
}
throw ('未知工單種類：' + $Kind)
'@
Write-SdFx $script:fakeWorker $fakeText $true

# ---------------- 範例 → 合成 worker 的素材 ----------------
function New-SdRunFixtures([string]$Example, [string]$StatusFile, $Pages, $Records, [bool]$Round2, [string]$Name) {
    $ex = Join-Path $design ('examples/' + $Example)
    $fx = Join-Path $base ('fx-' + $Name)
    $text = [System.IO.File]::ReadAllText((Join-Path $ex ('input/' + $StatusFile)), [System.Text.Encoding]::UTF8)
    $readings = @()
    foreach ($n in 1..3) {
        $r = Read-SdFxJson (Join-Path $ex ('readings/R' + $n + '.json'))
        $readings += , $r
        Write-SdFx (Join-Path $fx ('readings/R' + $n + '.json')) (ConvertTo-PsSdJsonText $r)
    }
    $res = Compare-PsSdReadings $text $readings $null
    $ans = New-PsSdObject
    if ($Round2) {
        $qs = Get-PsSdRound2Questions $text $res
        $maps = Get-PsSdAlignment $readings
        $truth = Get-PsSdReadingFacts $readings[0] $maps[0]
        foreach ($q in $qs) { $a = 'NO'; if ($truth.Facts.ContainsKey($q.factKey)) { $a = 'YES' }; $ans[[string]$q.id] = $a }
    }
    Write-SdFx (Join-Path $fx 'round2.json') (ConvertTo-PsSdJsonText $ans)
    $r = Get-SdExampleReceipts $ex 'clone-0000000000000000' 'status.md' $Pages $Records -UiPerComponent
    foreach ($rc in $r.Receipts) {
        $u = [string]$rc.Packet['unit']; $s = [string]$rc.Packet['subject']; if ($u -eq 'texts') { $s = 'JOB' }
        $json = (ConvertTo-PsSdJsonText $rc.Packet).Replace(('"' + $StatusFile + '#L'), '"status.md#L')
        Write-SdFx (Join-Path $fx ('research/' + $u + '/' + $s + '.json')) $json
    }
    return @{ Dir = $fx; Text = $text; Fixture = $r; Example = $ex }
}
function New-SdRunRoot([string]$Name) {
    $dir = Join-Path $base $Name
    $src = Join-Path $repo 'claude-code/.claude/peoplesoft/sdoc'
    foreach ($f in @(Get-ChildItem -LiteralPath $src -File -Recurse)) {
        $rel = $f.FullName.Substring($src.Length).TrimStart('\', '/')
        $dst = Join-Path (Join-Path $dir '.claude/peoplesoft/sdoc') $rel
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($dst))
        Copy-Item -LiteralPath $f.FullName -Destination $dst
    }
    return $dir
}
function Get-SdRunJobId([string[]]$Names) {
    $sorted = Sort-PsKnOrdinal -Items $Names
    return ('clone-' + (Get-PsKnTextHash -Text ($sorted -join "`n")).Substring(0, 16).ToLowerInvariant())
}
function Invoke-SdRun([string]$Root, [string]$Components, $Fx, [string]$Mode = '', [hashtable]$Extra = @{}) {
    $prior = @{ Mode = $env:PS_SDOC_TEST_MODE; Fx = $env:PS_SDOC_TEST_FIXTURES }
    try {
        $env:PS_SDOC_TEST_MODE = $Mode; $env:PS_SDOC_TEST_FIXTURES = $Fx.Dir
        $h = @{ Root = $Root; Components = $Components; FakeWorker = $script:fakeWorker; MaxSessions = 100 }
        foreach ($k in $Extra.Keys) { $h[$k] = $Extra[$k] }
        $out = ((& $cli @h *>&1 | ForEach-Object { [string]$_ }) -join "`n")
        $lines = @($out -split "`n" | Where-Object { $_.Trim() -ne '' })
        return @{ Output = $out; Exit = $LASTEXITCODE; Code = $lines[-1].Trim() }
    }
    finally { $env:PS_SDOC_TEST_MODE = $prior.Mode; $env:PS_SDOC_TEST_FIXTURES = $prior.Fx }
}
function Invoke-SdRunUntilDone([string]$Root, [string]$Components, $Fx, [string]$Mode = '', [int]$MaxRuns = 6) {
    $r = $null
    for ($i = 0; $i -lt $MaxRuns; $i++) {
        $r = Invoke-SdRun $Root $Components $Fx $Mode
        if ($r.Code -notlike 'DOC1-3-02-*') { break }
    }
    return $r
}
function Get-SdCalls($Fx) {
    $p = Join-Path $Fx.Dir 'calls.log'
    if (-not [System.IO.File]::Exists($p)) { return , @() }
    return , @([System.IO.File]::ReadAllLines($p) | Where-Object { $_ -ne '' })
}
function Get-SdOutcomes([string]$JobRoot) {
    $out = @()
    $dir = Join-Path $JobRoot 'attempts'
    if (-not [System.IO.Directory]::Exists($dir)) { return , $out }
    foreach ($d in @(Get-ChildItem -LiteralPath $dir -Directory | Sort-Object Name)) {
        $o = Join-Path $d.FullName 'outcome.json'; $i = Join-Path $d.FullName 'input.json'
        if ([System.IO.File]::Exists($o)) { $out += , @{ Id = $d.Name; Outcome = (Read-SdFxJson $o); Input = (Read-SdFxJson $i) } }
    }
    return , $out
}
function Get-SdPublished([string]$Root, [string]$JobId) {
    $cur = Read-SdFxJson (Join-Path $Root ('docs/ps-spec/' + $JobId + '/current.json'))
    $dir = Join-Path $Root ('docs/ps-spec/' + $JobId + '/generated/' + [string]$cur['generation'])
    $docs = @{}
    foreach ($d in $script:PsSdDocOrder) { $docs[$d] = Read-SdFxJson (Join-Path $dir ('canonical/' + $d + '.json')) }
    return @{ Current = $cur; Dir = $dir; Docs = $docs; Gate = (Read-SdFxJson (Join-Path $dir 'gate.json')) }
}
function Get-SdKeySet($Items) {
    $l = [System.Collections.Generic.List[string]]::new()
    foreach ($it in @($Items)) { if ($null -ne $it) { $l.Add([string]$it['key']) } }
    $l.Sort([System.StringComparer]::Ordinal)
    return ($l.ToArray() -join '|')
}

try {
    # ================= 貫穿範例：從空目錄到發布 =================
    $wkPages = @(
        @{ Component = 'TW_DEMO_APV'; Page = 'TW_DEMO_APVPG'; Fields = @('TW_DEMO_REQHDR.AMOUNT', 'TW_DEMO_REQHDR.REASON', 'TW_DEMO_REQHDR.COMMENTS', 'TW_DEMO_REQWRK.APPROVE_PB', 'TW_DEMO_REQWRK.RETURN_PB') }
        @{ Component = 'TW_DEMO_REQ'; Page = 'TW_DEMO_REQPG'; Fields = @('TW_DEMO_REQHDR.AMOUNT', 'TW_DEMO_REQHDR.REASON', 'TW_DEMO_REQHDR.REQ_TYPE', 'TW_DEMO_REQHDR.REQ_STATUS', 'TW_DEMO_REQWRK.SUBMIT_PB', 'TW_DEMO_REQWRK.WITHDRAW_PB') }
    )
    $wkRecords = @(@{ Record = 'TW_DEMO_REQHDR'; Fields = @('REQ_ID', 'REQUESTER_EMPLID', 'REQ_STATUS', 'REQ_TYPE', 'AMOUNT', 'REASON', 'COMMENTS', 'SUBMIT_DT', 'APPROVER_EMPLID', 'APPROVE_DT', 'OLD_REF_NO', 'PRIORITY_CD', 'BUDGET_CODE') })
    $fxW = New-SdRunFixtures 'walkthrough' 'status-REQ_STATUS.md' $wkPages $wkRecords $false 'walk'
    $comps = 'tw_demo_req, TW_DEMO_APV'
    $jobW = Get-SdRunJobId @('TW_DEMO_APV', 'TW_DEMO_REQ')
    $rootW = New-SdRunRoot 'walk'
    $inW = Join-Path $rootW ('.ps-private/sdoc/' + $jobW)
    $jobRootW = Join-Path $rootW ('.ps-runtime/sdoc/' + $jobW)

    $r = Invoke-SdRun $rootW $comps $fxW
    Assert-Sd ($r.Code -eq 'DOC1-0-01' -and $r.Exit -eq 0) '首跑沒有 STATUS 檔：DOC1-0-01' $r.Output
    $sk = [System.IO.File]::ReadAllText((Join-Path $inW 'status.md'))
    Assert-Sd ($sk.Contains('<!-- SDOC:SKELETON -->') -and [System.IO.File]::Exists((Join-Path $inW 'project.md')) -and [System.IO.File]::Exists((Join-Path $inW 'decisions.md')) -and [System.IO.File]::Exists((Join-Path $inW 'approvals.md'))) '首跑建好四個人工輸入檔骨架'
    $r = Invoke-SdRun $rootW $comps $fxW '' @{ Status = $true }
    Assert-Sd ($r.Code -eq 'DOC1-0-01') '-Status：STATUS 檔還是骨架 → DOC1-0-01'
    Write-SdFx (Join-Path $inW 'status.md') $fxW.Text
    Write-SdFx (Join-Path $inW 'project.md') ([System.IO.File]::ReadAllText((Join-Path $fxW.Example 'input/project.md'), [System.Text.Encoding]::UTF8))
    $r = Invoke-SdRun $rootW $comps $fxW '' @{ Status = $true }
    Assert-Sd ($r.Code -eq 'DOC1-0-02' -and -not [System.IO.Directory]::Exists((Join-Path $jobRootW 'attempts'))) '-Status：STATUS 檔已放、尚未開始 → DOC1-0-02，不派工' $r.Output
    $r = Invoke-SdRun $rootW $comps $fxW '' @{ MaxSessions = 2 }
    Assert-Sd ($r.Code -eq 'DOC1-3-02-1') '第 0 階段：兩個 session 後還差一位讀者 → DOC1-3-02-1' $r.Code
    $r = Invoke-SdRunUntilDone $rootW $comps $fxW
    Assert-Sd ($r.Code -eq 'DOC1-5-01') '貫穿範例跑完研究：L5 尚未執行 → DOC1-5-01（DRAFT）' ($r.Output -split "`n" | Select-Object -Last 15 | Out-String)
    $calls = Get-SdCalls $fxW
    $nRead = @($calls | Where-Object { $_ -like 'STATUS_READ *' }).Count
    $nRes = @($calls | Where-Object { $_ -like 'RESEARCH *' }).Count
    $nRev = @($calls | Where-Object { $_ -like 'REVIEW *' }).Count
    Assert-Sd ($nRead -eq 3 -and $nRes -eq $nRev -and $nRes -eq 20 -and -not (@($calls) -like 'STATUS_ROUND2 *')) ('派工：3 份解讀、20 頁研究（9 個 Component 單元 ×2＋說明區域＋1 個狀態實體）各配一次獨立覆核、沒有第 2 輪（實際 ' + $nRead + '／' + $nRes + '／' + $nRev + '）')
    $order = @(); foreach ($c in $calls) { if ($c -like 'RESEARCH *') { $u = ($c -split ' ')[1]; if ($order -notcontains $u) { $order += $u } } }
    Assert-Sd (($order -join ',') -ceq 'scope,data,security,texts,workflow,interfaces,functions,ui,rules,operations,testing') '研究單元依序（前一單元全部完成才開下一單元）' ($order -join ',')
    $dataAtt = $null
    foreach ($d in @(Get-ChildItem -LiteralPath (Join-Path $jobRootW 'attempts') -Directory | Sort-Object Name)) {
        $i = Read-SdFxJson (Join-Path $d.FullName 'input.json')
        if ($null -eq $dataAtt -and [string]$i['unit'] -ceq 'data' -and [string]$i['kind'] -ceq 'RESEARCH') { $dataAtt = $d.FullName }
    }
    $fg = [System.IO.File]::ReadAllText((Join-Path $dataAtt 'fields.md')); $mf = [System.IO.File]::ReadAllText((Join-Path $dataAtt 'manifest.md'))
    Assert-Sd ($fg.Contains('| `keys` |') -and $fg.Contains('## FLD ') -and $mf.Contains('.claude/peoplesoft/sdoc/examples/data.json') -and $mf.Contains('research-contract.md')) '工單：欄位說明列出每個欄位（含名為 keys 的欄位），並指向契約與本單元範例'
    $pub = Get-SdPublished $rootW $jobW
    $files = @('00-index.md', '90-questions.md', 'gate.json', 'canonical/evidence.json')
    foreach ($d in $script:PsSdDocOrder) { $files += ($d + '.md'); $files += ('canonical/' + $d + '.json') }
    $missing = @(); foreach ($f in $files) { if (-not [System.IO.File]::Exists((Join-Path $pub.Dir $f))) { $missing += $f } }
    Assert-Sd ($missing.Count -eq 0) '發布：00-index、15 份 Markdown、15 份 canonical、evidence、gate 都在' ($missing -join '、')
    Assert-Sd ([string]$pub.Current['phase'] -eq 'DRAFT' -and [string]$pub.Gate['phase'] -eq 'DRAFT') 'current.json／gate.json 的整體狀態是 DRAFT'
    $diff = @()
    foreach ($d in @('01-overview', '02-functional-requirements', '03-roles-permissions', '04-workflow', '05-ui', '06-architecture', '07-database', '08-api', '09-business-logic', '14-testing', '16-ai-instructions')) {
        $a = Get-SdKeySet $pub.Docs[$d]['items']; $b = Get-SdKeySet $fxW.Fixture.Docs[$d]['items']
        if ($a -cne $b) { $diff += $d }
    }
    Assert-Sd ($diff.Count -eq 0) '發布的 01～14、16 項目自然鍵與範例相同' ($diff -join '、')
    $l1 = @(); foreach ($d in $script:PsSdDocOrder) { if ([string]$pub.Gate['docs'][$d]['gate']['L1'] -cne 'PASS') { $l1 += $d } }
    Assert-Sd ($l1.Count -eq 0) '15 份文件 L1（schema）都 PASS' ($l1 -join '、')
    $l4 = @(); foreach ($d in $script:PsSdDocOrder) { $g = [string]$pub.Gate['docs'][$d]['gate']['L4']; if (@('PASS', 'NOT_APPLICABLE') -cnotcontains $g) { $l4 += ($d + '=' + $g) } }
    Assert-Sd ($l4.Count -eq 0) '研究全部完成：L4 都 PASS（或不適用）' ($l4 -join '、')
    $qKeys = @(); foreach ($q in @($pub.Docs['90-questions']['items'])) { $qKeys += [string]$q['key'] }
    $exQ = @(); foreach ($q in @($fxW.Fixture.Docs['90-questions']['items'])) { if (-not ([string]$q['category']).StartsWith('READER_')) { $exQ += [string]$q['key'] } }
    $lostQ = @(); foreach ($k in $exQ) { if ($qKeys -cnotcontains $k) { $lostQ += $k } }
    Assert-Sd ($lostQ.Count -eq 0) '90：範例的非讀者問題都在' ($lostQ -join '、')
    $readme = [System.IO.File]::ReadAllText((Join-Path $rootW ('docs/ps-spec/' + $jobW + '/README.md')))
    Assert-Sd ($readme.Contains('generated/' + [string]$pub.Current['generation'] + '/00-index.md') -and $readme.Contains('-Components ''TW_DEMO_APV,TW_DEMO_REQ''')) 'README 指向本次發布並附續跑命令（元件名已正規化排序）'

    # 重跑：不派工、同一份發布
    $gen0 = [string]$pub.Current['generation']
    $before = (Get-SdCalls $fxW).Count
    $r = Invoke-SdRun $rootW $comps $fxW
    $pub2 = Get-SdPublished $rootW $jobW
    Assert-Sd ($r.Code -eq 'DOC1-5-01' -and (Get-SdCalls $fxW).Count -eq $before -and [string]$pub2.Current['generation'] -ceq $gen0) '重跑同命令：不派工、發布內容不變（同 generation）'

    # 裁決：DROP 圖外轉移問題 → 不換研究版本、不派工，重新組裝出 19 的決策
    $qd = $null; foreach ($q in @($pub2.Docs['90-questions']['items'])) { if ([string]$q['category'] -ceq 'OFF_DIAGRAM_TRANSITION') { $qd = [string]$q['id'] } }
    Assert-Sd ($null -ne $qd) '90 有圖外轉移問題可供裁決'
    $decHead = "# 人工裁決`n`n| 問題 ID | 決定 | 理由 | 效果 | 決定者類別 | 日期 |`n|---|---|---|---|---|---|`n"
    $decText = $decHead + '| ' + $qd + " | 不重建 | 合成：管理者維護用的資料修正 | DROP | 業務單位主管 | 2026-10-08 |`n"
    Write-SdFx (Join-Path $inW 'decisions.md') $decText
    $r = Invoke-SdRun $rootW $comps $fxW
    $pub3 = Get-SdPublished $rootW $jobW
    $qst = ''; foreach ($q in @($pub3.Docs['90-questions']['items'])) { if ([string]$q['id'] -ceq $qd) { $qst = [string]$q['status'] } }
    Assert-Sd ($r.Code -eq 'DOC1-5-01' -and (Get-SdCalls $fxW).Count -eq $before -and [string]$pub3.Current['revision'] -ceq 'r0001' -and [string]$pub3.Current['generation'] -cne $gen0 -and @($pub3.Docs['19-decision-log']['items']).Count -eq 1 -and $qst -cne 'OPEN') ('裁決（DROP）：不換版本、不派工，19 出現決策、問題不再 OPEN（' + $qst + '）')
    # 核准：16 的 docHash 前 12 碼寫進 approvals.md → 16 approved；hash 不符的列不成立
    $h16 = [string]$pub3.Gate['docs']['16-ai-instructions']['docHash']
    $apText = "# 人工核准`n`n| 文件 | 版本 | docHash 前 12 碼 | 核准者類別 | 日期 |`n|---|---|---|---|---|`n| 16-ai-instructions | r0001 | " + $h16.Substring(0, 12) + " | 業務單位主管 | 2026-10-08 |`n| 01 | r0001 | 000000000000 | 業務單位主管 | 2026-10-08 |`n"
    Write-SdFx (Join-Path $inW 'approvals.md') $apText
    $r = Invoke-SdRun $rootW $comps $fxW
    $pub4 = Get-SdPublished $rootW $jobW
    Assert-Sd ($r.Code -eq 'DOC1-5-01' -and [string]$pub4.Docs['16-ai-instructions']['status'] -ceq 'approved' -and [string]$pub4.Docs['16-ai-instructions']['approval']['docHash'] -ceq $h16 -and [string]$pub4.Docs['01-overview']['status'] -ceq 'in_review') '核准：docHash 相符的 16 變 approved；hash 不符的 01 維持 in_review'
    Assert-Sd ([string]$pub4.Gate['docs']['16-ai-instructions']['docHash'] -ceq $h16) '核准不改變 docHash（docHash 不含狀態與核准）'
    # 來源改變：STATUS 檔或 ADD_SCOPE 裁決改了 → -Status 報 STALE；改回原樣 → 回到原版本
    Write-SdFx (Join-Path $inW 'status.md') ($fxW.Text + "`n")
    $r = Invoke-SdRun $rootW $comps $fxW '' @{ Status = $true }
    Assert-Sd ($r.Code -eq 'DOC1-4-04' -and $r.Exit -eq 1) 'STATUS 檔改了：-Status → DOC1-4-04（STALE）'
    Write-SdFx (Join-Path $inW 'status.md') $fxW.Text
    Write-SdFx (Join-Path $inW 'decisions.md') ($decText + '| ' + $qd + " | 納入範圍 | 合成 | ADD_SCOPE | 業務單位主管 | 2026-10-08 |`n")
    $r = Invoke-SdRun $rootW $comps $fxW '' @{ Status = $true }
    Assert-Sd ($r.Code -eq 'DOC1-4-04') 'ADD_SCOPE 裁決：-Status → DOC1-4-04（要開新研究版本）'
    Write-SdFx (Join-Path $inW 'decisions.md') $decText
    $r = Invoke-SdRun $rootW $comps $fxW '' @{ Status = $true }
    Assert-Sd ($r.Code -eq 'DOC1-5-01' -and -not [System.IO.File]::Exists((Join-Path $jobRootW 'revisions/r0002.json'))) '改回原樣：-Status 回到 DOC1-5-01，沒有開新版本'
    # 鎖：另一個執行緒持有同 Root＋同 Component 的鎖 → DOC1-0-03
    $lockName = 'Global\MCPSample-SpecDocs-' + (Get-PsKnTextHash -Text ([System.IO.Path]::GetFullPath($rootW).TrimEnd('\', '/').ToUpperInvariant())).Substring(0, 16) + '-' + $jobW
    $ready = Join-Path $base 'lock.ready'; $release = Join-Path $base 'lock.release'
    $ps = [powershell]::Create()
    [void]$ps.AddScript({ param($Name, $Ready, $Release)
            $m = New-Object System.Threading.Mutex($false, $Name); $held = $false
            try { $held = $m.WaitOne(5000); [System.IO.File]::WriteAllText($Ready, [string]$held); $w = [System.Diagnostics.Stopwatch]::StartNew(); while (-not [System.IO.File]::Exists($Release) -and $w.Elapsed.TotalSeconds -lt 60) { Start-Sleep -Milliseconds 50 } }
            finally { if ($held) { $m.ReleaseMutex() }; $m.Dispose() } }).AddArgument($lockName).AddArgument($ready).AddArgument($release)
    $handle = $ps.BeginInvoke()
    try {
        for ($i = 0; $i -lt 200 -and -not [System.IO.File]::Exists($ready); $i++) { Start-Sleep -Milliseconds 50 }
        $r = Invoke-SdRun $rootW $comps $fxW '' @{ Status = $true }
        Assert-Sd ([System.IO.File]::ReadAllText($ready) -eq 'True' -and $r.Code -eq 'DOC1-0-03' -and $r.Exit -eq 3) '另一個執行緒持鎖：DOC1-0-03（不碰任何檔案）'
    }
    finally { [System.IO.File]::WriteAllText($release, 'x'); [void]$ps.EndInvoke($handle); $ps.Dispose() }
    $r = Invoke-SdRun $rootW $comps $fxW '' @{ Status = $true }
    Assert-Sd ($r.Code -eq 'DOC1-5-01') '鎖釋放後恢復'
    # 參數與版本
    $r = Invoke-SdRun $rootW 'TW_DEMO_APV,BAD!NAME' $fxW '' @{ Status = $true }
    Assert-Sd ($r.Code -eq 'DOC1-9-01' -and $r.Exit -eq 2) 'Component 名稱含不合法字元 → DOC1-9-01'
    $r = Invoke-SdRun $rootW $comps $fxW '' @{ Status = $true; Refresh = $true }
    Assert-Sd ($r.Code -eq 'DOC1-9-01') '-Status 與 -Refresh 混用 → DOC1-9-01'
    $plain = Join-Path $base 'plain'; [void][System.IO.Directory]::CreateDirectory($plain)
    $r = Invoke-SdRun $plain $comps $fxW
    Assert-Sd ($r.Code -eq 'DOC1-9-01' -and -not [System.IO.Directory]::Exists((Join-Path $plain '.ps-private'))) '不是 Claude Code 版（沒有 .claude/peoplesoft）→ DOC1-9-01，不建任何檔'

    # ================= 中斷、失敗、重試、圍欄、覆核不通過、分頁 =================
    $fxE = New-SdRunFixtures 'walkthrough' 'status-REQ_STATUS.md' $wkPages $wkRecords $false 'edge'
    $rootE = New-SdRunRoot 'edge'
    $inE = Join-Path $rootE ('.ps-private/sdoc/' + $jobW)
    $jobRootE = Join-Path $rootE ('.ps-runtime/sdoc/' + $jobW)
    [void](Invoke-SdRun $rootE $comps $fxE)
    Write-SdFx (Join-Path $inE 'status.md') $fxE.Text
    Write-SdFx (Join-Path $inE 'project.md') ([System.IO.File]::ReadAllText((Join-Path $fxE.Example 'input/project.md'), [System.Text.Encoding]::UTF8))
    $r = Invoke-SdRun $rootE $comps $fxE 'touch-status-once'
    Assert-Sd ($r.Code -eq 'DOC1-4-04' -and -not [System.IO.File]::Exists((Join-Path $rootE ('docs/ps-spec/' + $jobW + '/current.json')))) 'session 期間 STATUS 檔被改：停止、不發布 → DOC1-4-04' $r.Code
    $r = Invoke-SdRun $rootE $comps $fxE 'bad-read-R2'
    $oc = Get-SdOutcomes $jobRootE
    $r2bad = @($oc | Where-Object { [string]$_.Input['revision'] -ceq 'r0002' -and [string]$_.Input['workKey'] -ceq 'stage0/read/R2' -and [string]$_.Outcome['status'] -ceq 'INVALID' }).Count
    Assert-Sd ($r.Code -eq 'DOC1-4-03' -and [System.IO.File]::Exists((Join-Path $jobRootE 'revisions/r0002.json')) -and $r2bad -eq 2) ('新版本 r0002；讀者 R2 本預算兩次不合格 → BLOCKED（DOC1-4-03）（不合格 ' + $r2bad + ' 次）')
    $r = Invoke-SdRun $rootE $comps $fxE 'session-fail-once' @{ Retry = $true }
    $oc = Get-SdOutcomes $jobRootE
    $last = $oc[$oc.Length - 1]
    Assert-Sd ($r.Code -eq 'DOC1-3-04' -and [System.IO.File]::Exists((Join-Path $jobRootE 'budgets/r0002/b0002.json')) -and [string]$last.Outcome['status'] -ceq 'SESSION_FAILED' -and $last.Outcome['counted'] -eq $false) '-Retry 開新預算；session 失敗不計次 → DOC1-3-04'
    $r = Invoke-SdRunUntilDone $rootE $comps $fxE 'stray-once,review-fail-once-data,partial-ui-TW_DEMO_APV,dup-scope-TW_DEMO_REQ'
    $oc = Get-SdOutcomes $jobRootE
    $stray = @($oc | Where-Object { [string]$_.Outcome['status'] -ceq 'INVALID' -and (@($_.Outcome['findings']) -join ' ') -like '*stray.txt*' }).Count
    $qdir = Join-Path $rootE '.ps-runtime/sdoc/quarantine'
    $qfiles = 0; if ([System.IO.Directory]::Exists($qdir)) { $qfiles = @(Get-ChildItem -LiteralPath $qdir -File).Count }
    $rf = @($oc | Where-Object { [string]$_.Outcome['status'] -ceq 'REVIEW_FAIL' -and [string]$_.Input['unit'] -ceq 'data' }).Count
    $callsE = Get-SdCalls $fxE
    $p2 = @($callsE | Where-Object { $_ -ceq 'RESEARCH ui TW_DEMO_APV 2' }).Count
    Assert-Sd ($r.Code -eq 'DOC1-5-01') '邊界情境最後仍跑完 → DOC1-5-01' ($r.Output -split "`n" | Select-Object -Last 12 | Out-String)
    Assert-Sd ($stray -eq 1 -and $qfiles -eq 1) 'worker 多寫檔：隔離到 quarantine、本次不合格且計次'
    Assert-Sd ($rf -eq 1) '覆核不通過：計次後重新研究，第二次覆核通過'
    Assert-Sd ($p2 -eq 1) '分頁：畫面單元第 1 頁 PARTIAL（含引用第 2 頁才寫的項目），第 2 頁 COMPLETE'
    $dupBad = @($oc | Where-Object { [string]$_.Outcome['status'] -ceq 'INVALID' -and [string]$_.Input['unit'] -ceq 'scope' -and (@($_.Outcome['findings']) -join ' ') -like '*別頁已寫過*' }).Count
    Assert-Sd ($dupBad -eq 1) '另一個 Component 重寫已驗收的物件：退回（改為參照），重做後通過'
    $pubE = Get-SdPublished $rootE $jobW
    $diff = @()
    foreach ($d in @('01-overview', '02-functional-requirements', '03-roles-permissions', '04-workflow', '05-ui', '06-architecture', '07-database', '08-api', '09-business-logic', '14-testing')) {
        if ((Get-SdKeySet $pubE.Docs[$d]['items']) -cne (Get-SdKeySet $fxE.Fixture.Docs[$d]['items'])) { $diff += $d }
    }
    Assert-Sd ($diff.Count -eq 0 -and [string]$pubE.Current['revision'] -ceq 'r0002') '邊界情境的發布內容仍與範例相同（r0002）' ($diff -join '、')
    $uiIds = @(); foreach ($it in @($pubE.Docs['05-ui']['items'])) { $uiIds += [string]$it['id'] }
    $bad = @(); foreach ($it in @($pubE.Docs['05-ui']['items'])) { foreach ($ref in (Get-PsSdItemRefs $it)) { if ((Get-PsSdIdPrefix $ref) -ceq 'UI' -and $uiIds -cnotcontains $ref) { $bad += $ref } } }
    Assert-Sd ($bad.Count -eq 0) '分頁的前向引用在組裝時換成正式 ID' ($bad -join '、')

    # ================= 守門範例：三份解讀不一致 → 第 2 輪多數決 =================
    $gComps = 'TW_DEMO_CASE,TW_DEMO_DOCREV,TW_DEMO_PAYMNT'
    $jobG = Get-SdRunJobId @('TW_DEMO_CASE', 'TW_DEMO_DOCREV', 'TW_DEMO_PAYMNT')
    $fxG = New-SdRunFixtures 'gate' 'status-CASE_STATUS.md' @() @() $true 'gate'
    $rootG = New-SdRunRoot 'gate'
    [void](Invoke-SdRun $rootG $gComps $fxG)
    Write-SdFx (Join-Path $rootG ('.ps-private/sdoc/' + $jobG + '/status.md')) $fxG.Text
    $r = Invoke-SdRun $rootG $gComps $fxG '' @{ MaxSessions = 7 }
    $callsG = Get-SdCalls $fxG
    $n2 = @($callsG | Where-Object { $_ -like 'STATUS_ROUND2 *' }).Count
    Assert-Sd ($r.Code -like 'DOC1-3-02-*' -and $n2 -eq 3 -and @($callsG | Where-Object { $_ -like 'RESEARCH scope *' }).Count -eq 1) ('守門範例：3 份解讀不一致 → 3 份第 2 輪 → 進入研究（' + $r.Code + '）')
    $regG = Read-SdFxJson (Join-Path $rootG ('.ps-runtime/sdoc/' + $jobG + '/registry.json'))
    $got = @(); foreach ($k in $regG['prefixes']['STATE']['keys'].Keys) { $got += [string]$k }
    $want = @(); foreach ($it in @($fxG.Fixture.Docs['04-workflow']['items'])) { if (([string]$it['id']).StartsWith('STATE-')) { $want += [string]$it['key'] } }
    Assert-Sd (((Sort-PsKnOrdinal -Items $got) -join '|') -ceq ((Sort-PsKnOrdinal -Items $want) -join '|')) '守門範例：多數決後採用的狀態（含第 2 輪補回的子業務）與範例相同'
    $fxU = New-SdRunFixtures 'gate' 'status-CASE_STATUS.md' @() @() $true 'gate-unsure'
    $rootU = New-SdRunRoot 'gate-unsure'
    [void](Invoke-SdRun $rootU $gComps $fxU)
    Write-SdFx (Join-Path $rootU ('.ps-private/sdoc/' + $jobG + '/status.md')) $fxU.Text
    $r = Invoke-SdRun $rootU $gComps $fxU 'round2-unsure'
    $pubU = Get-SdPublished $rootU $jobG
    $conf = @($pubU.Docs['90-questions']['items'] | Where-Object { [string]$_['category'] -ceq 'STATUS_READING_CONFLICT' }).Count
    $callsU = Get-SdCalls $fxU
    Assert-Sd ($r.Code -eq 'DOC1-4-01' -and $r.Exit -eq 1 -and $conf -gt 0 -and -not (@($callsU) -like 'RESEARCH *')) ('第 2 輪仍無多數：不研究，發布 90 的 STATUS_READING_CONFLICT（' + $conf + ' 題）→ DOC1-4-01')
}
finally {
    $env:PS_CLI = $priorEnv.Cli; $env:PS_SDOC_TEST_LIB = $priorEnv.Lib; $env:PS_SDOC_TEST_FIXTURES = $priorEnv.Fx; $env:PS_SDOC_TEST_MODE = $priorEnv.Mode
    if ($env:PS_SDOC_TEST_KEEP) { Write-Host ('保留測試目錄：' + $base) } else { try { Remove-Item -LiteralPath $base -Recurse -Force } catch { Write-Host ('無法刪除測試目錄：' + $base) } }
}
Write-Host ('sdoc run tests: PASS=' + $script:passed + ' FAIL=' + $script:failed)
if ($script:failed -gt 0) { exit 1 }
exit 0
