# test-sdoc-run.ps1 — Spec 文件流程外環（ps-sdoc.ps1）端到端：合成 worker 依工單回狀態圖解讀、研究包、覆核；不查 MCP、不呼叫模型。
# 以設計範例（walkthrough、gate）為來源：從空目錄跑到發布，比對發布的 canonical 與範例，並驗結論碼、中斷、重試、重跑、裁決與核准。
# 用法：pwsh -NoProfile -File scripts/tests/test-sdoc-run.ps1   （公司機：powershell -NoProfile -ExecutionPolicy Bypass -File …）
#       -Only walk｜edge｜gate｜opencode：只跑一組情境（CI 拆成幾個 job 平行跑；不給＝全部）
#       opencode 組：OpenCode 版（-Cli opencode）的目錄、模型設定、與 Claude Code 版同資料夾並存、產出與 Claude Code 版相同、模型預檢、
#       session slot 兩版各一把（兩版可以同時跑，同一版一次一個）
param([ValidateSet('', 'walk', 'edge', 'gate', 'opencode')][string]$Only = '')
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
foreach ($f in @('ps-knowledge-lib', 'ps-sdoc-schema-lib', 'ps-sdoc-status-lib', 'ps-sdoc-lib')) { . (Join-Path $repo ('scripts/' + $f + '.ps1')) }
. (Join-Path $PSScriptRoot 'sdoc-test-fixtures.ps1')
$script:failed = 0; $script:passed = 0
function Assert-Sd([bool]$Condition, [string]$Name, [string]$Detail = '') {
    if ($Condition) { $script:passed++; Write-Host ('PASS ' + $Name) }
    else { $script:failed++; Write-Host ('FAIL ' + $Name); if ($Detail) { Write-Host ('     ' + $Detail) } }
}
$paths = Get-SdTestPaths $repo
if (-not $paths.HasDesign) { Write-Host 'SKIP 本測試以設計範例為預期結果（docs/design/spec-schema-framework），範例只在維護端 repo、不在搬運包'; exit 0 }
$design = $paths.Design
$base = Join-Path ([System.IO.Path]::GetTempPath()) ('ps-sdoc-run-' + [guid]::NewGuid().ToString('N'))
# 凍結這次待測的腳本，避免並行維護同一 checkout 時被誤判成來源改變
$tools = Join-Path $base 'framework'
[void][System.IO.Directory]::CreateDirectory($tools)
foreach ($n in @('ps-sdoc.ps1', 'ps-sdoc-schema-lib.ps1', 'ps-sdoc-status-lib.ps1', 'ps-sdoc-lib.ps1', 'ps-sdoc-check-lib.ps1', 'ps-sdoc-render-lib.ps1', 'ps-sdoc-reader-lib.ps1', 'ps-knowledge-lib.ps1', 'ps-session-lib.ps1', 'ps-cli-lib.ps1')) {
    Copy-Item -LiteralPath (Join-Path $repo ('scripts/' + $n)) -Destination (Join-Path $tools $n)
}
$cli = Join-Path $tools 'ps-sdoc.ps1'
$priorEnv = @{ Cli = $env:PS_CLI; Lib = $env:PS_SDOC_TEST_LIB; Fx = $env:PS_SDOC_TEST_FIXTURES; Mode = $env:PS_SDOC_TEST_MODE; Part = $env:PS_SDOC_READING_PART_LINES; PageItems = $env:PS_SDOC_RESEARCH_PAGE_ITEMS }
$env:PS_CLI = ''
$env:PS_SDOC_TEST_LIB = $tools
# 範例的狀態圖不大：每段 8 行，讓解讀一定分成好幾段（走合併）
$env:PS_SDOC_READING_PART_LINES = '8'
# 設計範例一頁本來就超過預設的每頁上限（data 19 項）：釘回 schema 上限 60，上限本身另有專門情境測
$env:PS_SDOC_RESEARCH_PAGE_ITEMS = '60'

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
    if ($mode -contains ('read-whole-' + [string]$inp['reader'])) { Write-FwOut $r; exit 0 }
    # 照工單 outputParts 分段寫：每段只放這段行號範圍內的行（同一狀態、轉移在多段都出現就各段都寫），conflicts 放最後一段
    $parts = @($inp['outputParts']); $skipLast = Test-FwOnce 'read-skip-part-once'
    for ($pi = 0; $pi -lt $parts.Count; $pi++) {
        $pt = $parts[$pi]; $from = [int]$pt['from']; $to = [int]$pt['to']
        if ($skipLast -and $pi -eq $parts.Count - 1) { continue }
        $o = New-PsSdObject; foreach ($k in @('schemaVersion', 'jobId', 'reader', 'round', 'source')) { $o[$k] = $r[$k] }
        $ss = @(); $tt = @(); $oo = @()
        foreach ($s in @($r['states'])) {
            $ls = @(@($s['lines']) | Where-Object { [int]$_ -ge $from -and [int]$_ -le $to })
            $rg = @(); foreach ($g in @($s['regions'])) { $gl = @(@($g['lines']) | Where-Object { [int]$_ -ge $from -and [int]$_ -le $to }); if ($gl.Count -gt 0) { $x = New-PsSdObject; $x['entity'] = $g['entity']; $x['lines'] = $gl; $rg += , $x } }
            if ($ls.Count -gt 0 -or $rg.Count -gt 0) { $x = New-PsSdObject; foreach ($k in @($s.Keys)) { $x[[string]$k] = $s[$k] }; $x['lines'] = $ls; $x['regions'] = $rg; $ss += , $x }
        }
        foreach ($t in @($r['transitions'])) {
            $ls = @(@($t['lines']) | Where-Object { [int]$_ -ge $from -and [int]$_ -le $to })
            if ($ls.Count -gt 0) { $x = New-PsSdObject; foreach ($k in @($t.Keys)) { $x[[string]$k] = $t[$k] }; $x['lines'] = $ls; $tt += , $x }
        }
        foreach ($q in @($r['otherLines'])) {
            $ls = @(@($q['lines']) | Where-Object { [int]$_ -ge $from -and [int]$_ -le $to })
            if ($ls.Count -gt 0) { $x = New-PsSdObject; foreach ($k in @($q.Keys)) { $x[[string]$k] = $q[$k] }; $x['lines'] = $ls; $oo += , $x }
        }
        $o['states'] = $ss; $o['transitions'] = $tt; $o['otherLines'] = $oo; $o['conflicts'] = @()
        if ($pi -eq $parts.Count - 1) { $o['conflicts'] = @($r['conflicts']) }
        [System.IO.File]::WriteAllText((Join-Path $Root ([string]$pt['path'])), ((ConvertTo-PsKnJson -Value $o) + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    }
    # 全部段都寫完才失敗（例如寫完後 Read 回確認的那個請求卡在 gateway）：外環要照收已驗收的產出
    if (Test-FwOnce 'read-fail-after-all') { exit 1 }
    exit 0
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
    if (([string]$inp['cursor']).StartsWith('L5-AMEND')) {
        # 改寫頁：只重寫工單要改寫的項目
        $want = @(); foreach ($k in @($inp['requestedKeys'])) { $want += [string]$k }
        $keep = @(); foreach ($it in $all) { if ($want -ccontains ([string]$it['type'] + '/' + [string]$it['key'])) { $keep += , $it } }
        $pk['items'] = $keep; $pk['questions'] = @(); $pk['requests'] = @()
        foreach ($x in @('statusTexts', 'programDispositions', 'definitionOnlyCodes', 'denominators')) { if ($pk.Contains($x)) { $pk.Remove($x) } }
        Write-FwOut $pk; exit 0
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
if ($Kind -eq 'READER') {
    # 合成讀者：讀外環的完整工單（含標準答案）照答；真的讀者只看得到 inbox 的工單與文件
    $full = Read-FwJson (Join-Path $AttemptDir 'input.json')
    $docOf = @{ 'GOAL' = '01-overview'; 'RESP' = '01-overview'; 'OBJ' = '01-overview'; 'ENT' = '07-database'; 'FLD' = '07-database'; 'DRV' = '07-database'; 'XF' = '07-database'
        'ROLE' = '03-roles-permissions'; 'PERM' = '03-roles-permissions'; 'STATE' = '04-workflow'; 'TRN' = '04-workflow'; 'FLOW' = '04-workflow'; 'ACT' = '04-workflow'
        'IF' = '06-architecture'; 'FR' = '02-functional-requirements'; 'UI' = '05-ui'; 'MSG' = '09-business-logic'; 'BR' = '09-business-logic'; 'OP' = '08-api'; 'TC' = '14-testing' }
    $exp = @{}; foreach ($q in @($full['questions'])) { $exp[[string]$q['id']] = $q }
    $o = New-PsSdObject
    foreach ($kv in @(@('schemaVersion', '1.0'), @('jobId', [string]$inp['jobId']), @('attemptId', [string]$inp['attemptId']), @('reader', [string]$inp['reader']), @('round', [int]$inp['round']), @('batch', [string]$inp['batch']), @('inputHash', [string]$inp['inputHash']))) { $o[$kv[0]] = $kv[1] }
    $round = [int]$inp['round']; $bad = Test-FwOnce ('l5-badcite-' + [string]$inp['reader'])
    $ans = @()
    foreach ($q in @($inp['questions'])) {
        $id = [string]$q['id']; $e = $exp[$id]
        $a = New-PsSdObject; $a['id'] = $id
        if (($mode -contains ('l5-nis-' + $id) -and $round -eq 1) -or $mode -contains ('l5-nis-always-' + $id)) {
            $a['status'] = 'NOT_IN_SPEC'; $a['ids'] = @(); $a['kind'] = ''; $a['text'] = '文件沒寫'; $a['citations'] = @()
        }
        else {
            $cites = @([string]$e['doc'] + '.md#' + [string]$e['item'])
            foreach ($x in @($e['ids'])) { $c = $docOf[([string]$x).Split('-')[0]] + '.md#' + [string]$x; if ($cites -notcontains $c) { $cites += $c } }
            if ($bad) { $cites = @('04-workflow.md#TRN-999'); $bad = $false }
            $t = [string]$e['text']; if ($t -eq '') { $t = '合成讀者的答案' }
            $a['status'] = 'ANSWERED'; $a['ids'] = @($e['ids']); $a['kind'] = [string]$e['kind']; $a['text'] = $t; $a['citations'] = $cites
        }
        $ans += , $a
    }
    $o['answers'] = $ans
    Write-FwOut $o; exit 0
}
if ($Kind -eq 'JUDGE') {
    $o = New-PsSdObject
    foreach ($kv in @(@('schemaVersion', '1.0'), @('jobId', [string]$inp['jobId']), @('attemptId', [string]$inp['attemptId']), @('round', [int]$inp['round']), @('batch', [string]$inp['batch']), @('inputHash', [string]$inp['inputHash']))) { $o[$kv[0]] = $kv[1] }
    $vs = @()
    foreach ($it in @($inp['items'])) {
        foreach ($a in @($it['answers'])) {
            $v = New-PsSdObject; $v['id'] = [string]$it['id']; $v['reader'] = [string]$a['reader']; $v['verdict'] = 'MISMATCH'
            if ([string]$a['text'] -ceq [string]$it['standard']) { $v['verdict'] = 'MATCH' }
            $vs += , $v
        }
    }
    $o['verdicts'] = $vs
    Write-FwOut $o; exit 0
}
throw ('未知工單種類：' + $Kind)
'@
Write-SdFx $script:fakeWorker $fakeText $true

# ---------------- 範例 → 合成 worker 的素材 ----------------
function Add-SdRunTests([string]$Dir) {
    # 貫穿範例的 14 刻意少兩條轉移的測試（C07）；端到端要走到 REVIEW_READY，合成兩個案例補上
    $tp = Join-Path $Dir 'research/testing/TW_DEMO_APV.json'
    $pk = Read-SdFxJson $tp
    $add = @()
    foreach ($spec in @(@('TW_DEMO_REQ:WITHDRAW:POSITIVE:WITHDRAW_DRAFT', 'TW_DEMO_REQ:WITHDRAW:POSITIVE:WITHDRAW_RETURNED', 'REQ_STATUS:015>090', 'REQ_STATUS:015', '合成：撤回退回補件中的申請'),
            @('TW_DEMO_APV:RETURN:POSITIVE:RETURN_WITH_COMMENT', 'TW_DEMO_APV:RETURN:POSITIVE:DEPT_MANAGER_RETURN', 'REQ_STATUS:025>015', 'REQ_STATUS:025', '合成：部門主管退回申請'))) {
        foreach ($it in @($pk['items'])) {
            if ([string]$it['key'] -cne $spec[0]) { continue }
            $c = Copy-PsSdNode $it
            $c['key'] = $spec[1]; $c['name'] = $spec[4]; $c['covers'] = New-PsSdObject; $c['covers']['transitions'] = @('@TRN/' + $spec[2]); $c['preconditions']['state'] = '@STATE/' + $spec[3]
            $add += , $c
        }
    }
    $pk['items'] = @($pk['items']) + $add
    Write-SdFx $tp (ConvertTo-PsSdJsonText $pk)
}
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
    if ($Example -eq 'walkthrough') { Add-SdRunTests $fx }
    return @{ Dir = $fx; Text = $text; Fixture = $r; Example = $ex }
}
function New-SdRunRoot([string]$Name) {
    $dir = Join-Path $base $Name
    $src = $paths.SdocDir
    foreach ($f in @(Get-ChildItem -LiteralPath $src -File -Recurse)) {
        $rel = $f.FullName.Substring($src.Length).TrimStart('\', '/')
        $dst = Join-Path (Join-Path $dir '.claude/peoplesoft/sdoc') $rel
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($dst))
        Copy-Item -LiteralPath $f.FullName -Destination $dst
    }
    return $dir
}
function New-SdRunRootOc([string]$Name, [switch]$WithClaude) {
    # OpenCode 版部署版面：.opencode/peoplesoft/sdoc；-WithClaude 另放 .claude/peoplesoft/sdoc（兩版同一資料夾）
    $dir = Join-Path $base $Name
    $pairs = @(, @($paths.OcSdocDir, '.opencode/peoplesoft/sdoc'))
    if ($WithClaude) { $pairs += , @($paths.SdocDir, '.claude/peoplesoft/sdoc') }
    foreach ($pr in $pairs) {
        $src = $pr[0]
        foreach ($f in @(Get-ChildItem -LiteralPath $src -File -Recurse)) {
            $rel = $f.FullName.Substring($src.Length).TrimStart('\', '/')
            $dst = Join-Path (Join-Path $dir $pr[1]) $rel
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($dst))
            Copy-Item -LiteralPath $f.FullName -Destination $dst
        }
    }
    return $dir
}
function Get-SdTreeText([string]$Dir) {
    # 目錄底下每個檔「相對路徑＋內容」（比對兩版產出用）
    $sb = New-Object System.Text.StringBuilder
    $files = @(Get-ChildItem -LiteralPath $Dir -File -Recurse | ForEach-Object { $_.FullName })
    foreach ($f in (Sort-PsKnOrdinal -Items $files)) { [void]$sb.Append(($f.Substring($Dir.Length).TrimStart('\', '/') -replace '\\', '/')).Append("`n").Append([System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)).Append("`n") }
    return $sb.ToString()
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
function Start-SdMutexHold([string]$Name, [string]$Tag) {
    # 另一個執行緒持有具名互斥鎖（同行程另一個 runspace；互斥鎖屬於執行緒，本執行緒的 WaitOne 會拿不到）。回 @{ Held; … }
    $ready = Join-Path $base ($Tag + '.ready'); $release = Join-Path $base ($Tag + '.release')
    $ps = [powershell]::Create()
    [void]$ps.AddScript({ param($N, $Ready, $Release)
            $m = New-Object System.Threading.Mutex($false, $N); $held = $false
            try {
                try { $held = $m.WaitOne(5000) } catch [System.Threading.AbandonedMutexException] { $held = $true }
                [System.IO.File]::WriteAllText($Ready, [string]$held)
                $w = [System.Diagnostics.Stopwatch]::StartNew()
                while (-not [System.IO.File]::Exists($Release) -and $w.Elapsed.TotalSeconds -lt 180) { Start-Sleep -Milliseconds 50 }
            }
            finally { if ($held) { $m.ReleaseMutex() }; $m.Dispose() } }).AddArgument($Name).AddArgument($ready).AddArgument($release)
    $handle = $ps.BeginInvoke()
    for ($i = 0; $i -lt 1200 -and -not [System.IO.File]::Exists($ready); $i++) { Start-Sleep -Milliseconds 50 }
    $ok = $false
    if ([System.IO.File]::Exists($ready)) { $ok = ([System.IO.File]::ReadAllText($ready) -eq 'True') }
    return @{ Ps = $ps; Handle = $handle; Release = $release; Held = $ok }
}
function Stop-SdMutexHold($H) {
    [System.IO.File]::WriteAllText($H.Release, 'x'); [void]$H.Ps.EndInvoke($H.Handle); $H.Ps.Dispose()
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
    # 14 的預期案例（貫穿範例＋第 2 輪補的兩題）：walk 與 edge 兩組都用
    $tcWant = @(); foreach ($it in @($fxW.Fixture.Docs['14-testing']['items'])) { $tcWant += [string]$it['key'] }
    $tcWant += @('TW_DEMO_APV:RETURN:POSITIVE:DEPT_MANAGER_RETURN', 'TW_DEMO_REQ:WITHDRAW:POSITIVE:WITHDRAW_RETURNED')
    $tcWantSorted = Sort-PsKnOrdinal -Items $tcWant

    if ($Only -eq '' -or $Only -eq 'walk') {  # 貫穿範例從空目錄到核准
        $r = Invoke-SdRun $rootW $comps $fxW
        Assert-Sd ($r.Code -eq 'DOC1-0-01' -and $r.Exit -eq 0) '首跑沒有 STATUS 檔：DOC1-0-01' $r.Output
        $sk = [System.IO.File]::ReadAllText((Join-Path $inW 'status.md'))
        Assert-Sd ($sk.Contains('<!-- SDOC:SKELETON -->') -and [System.IO.File]::Exists((Join-Path $inW 'project.md')) -and [System.IO.File]::Exists((Join-Path $inW 'decisions.md')) -and [System.IO.File]::Exists((Join-Path $inW 'approvals.md'))) '首跑建好四個人工輸入檔骨架'
        $r = Invoke-SdRun $rootW $comps $fxW '' @{ Status = $true }
        Assert-Sd ($r.Code -eq 'DOC1-0-01') '-Status：STATUS 檔還是骨架 → DOC1-0-01'
        # 公司機的叫法：另開 powershell -File；名稱用空白分開、沒包在同一個引號裡，或像 cmd.exe 一樣留著單引號
        $self = (Get-Process -Id $PID).Path
        $o1 = @(& $self -NoProfile -File $cli -Components tw_demo_req TW_DEMO_APV -Root $rootW -Status -MaxSessions 1 -TimeoutMin 5 2>&1 | ForEach-Object { [string]$_ })
        $o2 = @(& $self -NoProfile -File $cli -Components "'tw_demo_req," "TW_DEMO_APV'" -Root $rootW -Status 2>&1 | ForEach-Object { [string]$_ })
        $l1 = @($o1 | Where-Object { $_.Trim() -ne '' }); $l2 = @($o2 | Where-Object { $_.Trim() -ne '' })
        Assert-Sd ($l1.Count -gt 0 -and $l1[-1].Trim() -eq 'DOC1-0-01' -and ($o1 -join "`n").Contains($jobW) -and $l2.Count -gt 0 -and $l2[-1].Trim() -eq 'DOC1-0-01' -and ($o2 -join "`n").Contains($jobW)) '-Components 名稱用空白分開或留著單引號（cmd）：同一個工作，不把多出來的名稱塞給 -TimeoutMin' (($o1 + $o2) -join ' | ')
        Write-SdFx (Join-Path $inW 'status.md') $fxW.Text
        Write-SdFx (Join-Path $inW 'project.md') ([System.IO.File]::ReadAllText((Join-Path $fxW.Example 'input/project.md'), [System.Text.Encoding]::UTF8))
        $r = Invoke-SdRun $rootW $comps $fxW '' @{ Status = $true }
        Assert-Sd ($r.Code -eq 'DOC1-0-02' -and -not [System.IO.Directory]::Exists((Join-Path $jobRootW 'attempts'))) '-Status：STATUS 檔已放、尚未開始 → DOC1-0-02，不派工' $r.Output
        $r = Invoke-SdRun $rootW $comps $fxW '' @{ MaxSessions = 2; TimeoutMin = 45 }
        Assert-Sd ($r.Code -eq 'DOC1-3-02-1') '第 0 階段：兩個 session 後還差一位讀者 → DOC1-3-02-1' $r.Code
        Assert-Sd ($r.Output -match "-Components '[^']+' -TimeoutMin 45") '續跑命令帶上自訂的 -TimeoutMin' ($r.Output -split "`n" | Select-Object -Last 4 | Out-String)
        $r = Invoke-SdRunUntilDone $rootW $comps $fxW
        Assert-Sd ($r.Code -eq 'DOC1-7-01') '貫穿範例跑完研究與 L5：五層檢核全過 → DOC1-7-01（REVIEW_READY）' ($r.Output -split "`n" | Select-Object -Last 15 | Out-String)
        $calls = Get-SdCalls $fxW
        $nRead = @($calls | Where-Object { $_ -like 'STATUS_READ *' }).Count
        $nRes = @($calls | Where-Object { $_ -like 'RESEARCH *' }).Count
        $nRev = @($calls | Where-Object { $_ -like 'REVIEW *' }).Count
        Assert-Sd ($nRead -eq 3 -and $nRes -eq $nRev -and $nRes -eq 20 -and -not (@($calls) -like 'STATUS_ROUND2 *')) ('派工：3 份解讀、20 頁研究（9 個 Component 單元 ×2＋說明區域＋1 個狀態實體）各配一次獨立覆核、沒有第 2 輪（實際 ' + $nRead + '／' + $nRes + '／' + $nRev + '）')
        $nReader = @($calls | Where-Object { $_ -like 'READER *' }).Count
        $nJudge = @($calls | Where-Object { $_ -like 'JUDGE *' }).Count
        Assert-Sd ($nReader -gt 0 -and ($nReader % 3) -eq 0 -and $nJudge -gt 0 -and $nJudge -le ($nReader / 3)) ('L5：每批三位讀者各答一次，文字題每批一次判定（讀者 ' + $nReader + '、判定 ' + $nJudge + '）')
        $order = @(); foreach ($c in $calls) { if ($c -like 'RESEARCH *') { $u = ($c -split ' ')[1]; if ($order -notcontains $u) { $order += $u } } }
        Assert-Sd (($order -join ',') -ceq 'scope,data,security,texts,workflow,interfaces,functions,ui,rules,operations,testing') '研究單元依序（前一單元全部完成才開下一單元）' ($order -join ',')
        $dataAtt = $null
        foreach ($d in @(Get-ChildItem -LiteralPath (Join-Path $jobRootW 'attempts') -Directory | Sort-Object Name)) {
            $i = Read-SdFxJson (Join-Path $d.FullName 'input.json')
            if ($null -eq $dataAtt -and [string]$i['unit'] -ceq 'data' -and [string]$i['kind'] -ceq 'RESEARCH') { $dataAtt = $d.FullName }
        }
        $fg = [System.IO.File]::ReadAllText((Join-Path $dataAtt 'fields.md')); $mf = [System.IO.File]::ReadAllText((Join-Path $dataAtt 'manifest.md'))
        Assert-Sd ($mf.Contains('本頁上限：items 最多 60 個')) '工單：manifest 印出本頁的項目上限（測試釘 60）'
        Assert-Sd ($fg.Contains('| `keys` |') -and $fg.Contains('## FLD ') -and $mf.Contains('.claude/peoplesoft/sdoc/examples/data.json') -and $mf.Contains('research-contract.md')) '工單：欄位說明列出每個欄位（含名為 keys 的欄位），並指向契約與本單元範例'
        $pub = Get-SdPublished $rootW $jobW
        $files = @('00-index.md', '90-questions.md', 'gate.json', 'canonical/evidence.json')
        foreach ($d in $script:PsSdDocOrder) { $files += ($d + '.md'); $files += ('canonical/' + $d + '.json') }
        $missing = @(); foreach ($f in $files) { if (-not [System.IO.File]::Exists((Join-Path $pub.Dir $f))) { $missing += $f } }
        Assert-Sd ($missing.Count -eq 0) '發布：00-index、15 份 Markdown、15 份 canonical、evidence、gate 都在' ($missing -join '、')
        Assert-Sd ([string]$pub.Current['phase'] -eq 'REVIEW_READY' -and [string]$pub.Gate['phase'] -eq 'REVIEW_READY') 'current.json／gate.json 的整體狀態是 REVIEW_READY'
        $diff = @()
        foreach ($d in @('01-overview', '02-functional-requirements', '03-roles-permissions', '04-workflow', '05-ui', '06-architecture', '07-database', '08-api', '09-business-logic', '16-ai-instructions')) {
            $a = Get-SdKeySet $pub.Docs[$d]['items']; $b = Get-SdKeySet $fxW.Fixture.Docs[$d]['items']
            if ($a -cne $b) { $diff += $d }
        }
        if ((Get-SdKeySet $pub.Docs['14-testing']['items']) -cne (@($tcWantSorted) -join '|')) { $diff += '14-testing' }
        Assert-Sd ($diff.Count -eq 0) '發布的 01～14、16 項目自然鍵與範例相同（14 另有補上的兩個合成案例）' ($diff -join '、')
        $l5 = @(); foreach ($d in @('02-functional-requirements', '03-roles-permissions', '04-workflow', '05-ui', '06-architecture', '07-database', '08-api', '09-business-logic')) { if ([string]$pub.Gate['docs'][$d]['gate']['L5'] -cne 'PASS') { $l5 += ($d + '=' + $pub.Gate['docs'][$d]['gate']['L5']) } }
        Assert-Sd ($l5.Count -eq 0) '02～09 的 L5（乾淨讀者）都 PASS' ($l5 -join '、')
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
        Assert-Sd ($r.Code -eq 'DOC1-7-01' -and (Get-SdCalls $fxW).Count -eq $before -and [string]$pub2.Current['generation'] -ceq $gen0) '重跑同命令：不派工、發布內容不變（同 generation）'

        # 裁決：DROP 圖外轉移問題 → 不換研究版本、不派工，重新組裝出 19 的決策
        $qd = $null; foreach ($q in @($pub2.Docs['90-questions']['items'])) { if ([string]$q['category'] -ceq 'OFF_DIAGRAM_TRANSITION') { $qd = [string]$q['id'] } }
        Assert-Sd ($null -ne $qd) '90 有圖外轉移問題可供裁決'
        $decHead = "# 人工裁決`n`n| 問題 ID | 決定 | 理由 | 效果 | 決定者類別 | 日期 |`n|---|---|---|---|---|---|`n"
        $decText = $decHead + '| ' + $qd + " | 不重建 | 合成：管理者維護用的資料修正 | DROP | 業務單位主管 | 2026-10-08 |`n"
        Write-SdFx (Join-Path $inW 'decisions.md') $decText
        $r = Invoke-SdRun $rootW $comps $fxW
        $pub3 = Get-SdPublished $rootW $jobW
        $qst = ''; foreach ($q in @($pub3.Docs['90-questions']['items'])) { if ([string]$q['id'] -ceq $qd) { $qst = [string]$q['status'] } }
        Assert-Sd ($r.Code -eq 'DOC1-7-01' -and (Get-SdCalls $fxW).Count -eq $before -and [string]$pub3.Current['revision'] -ceq 'r0001' -and [string]$pub3.Current['generation'] -cne $gen0 -and @($pub3.Docs['19-decision-log']['items']).Count -eq 1 -and $qst -cne 'OPEN') ('裁決（DROP）：不換版本、不派工，19 出現決策、問題不再 OPEN（' + $qst + '）')
        # 核准：16 的 docHash 前 12 碼寫進 approvals.md → 16 approved；hash 不符的列不成立
        $h16 = [string]$pub3.Gate['docs']['16-ai-instructions']['docHash']
        $apText = "# 人工核准`n`n| 文件 | 版本 | docHash 前 12 碼 | 核准者類別 | 日期 |`n|---|---|---|---|---|`n| 16-ai-instructions | r0001 | " + $h16.Substring(0, 12) + " | 業務單位主管 | 2026-10-08 |`n| 01 | r0001 | 000000000000 | 業務單位主管 | 2026-10-08 |`n"
        Write-SdFx (Join-Path $inW 'approvals.md') $apText
        $r = Invoke-SdRun $rootW $comps $fxW
        $pub4 = Get-SdPublished $rootW $jobW
        Assert-Sd ($r.Code -eq 'DOC1-7-01' -and [string]$pub4.Docs['16-ai-instructions']['status'] -ceq 'approved' -and [string]$pub4.Docs['16-ai-instructions']['approval']['docHash'] -ceq $h16 -and [string]$pub4.Docs['01-overview']['status'] -ceq 'in_review') '核准：docHash 相符的 16 變 approved；hash 不符的 01 維持 in_review'
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
        Assert-Sd ($r.Code -eq 'DOC1-7-01' -and -not [System.IO.File]::Exists((Join-Path $jobRootW 'revisions/r0002.json'))) '改回原樣：-Status 回到 DOC1-7-01，沒有開新版本'
        # 鎖：另一個執行緒持有同 Root＋同 Component 的鎖 → DOC1-0-03
        $lockName = 'Global\MCPSample-SpecDocs-' + (Get-PsKnTextHash -Text ([System.IO.Path]::GetFullPath($rootW).TrimEnd('\', '/').ToUpperInvariant())).Substring(0, 16) + '-' + $jobW
        $hold = Start-SdMutexHold $lockName 'lock'
        try {
            $r = Invoke-SdRun $rootW $comps $fxW '' @{ Status = $true }
            Assert-Sd ($hold.Held -and $r.Code -eq 'DOC1-0-03' -and $r.Exit -eq 3) '另一個執行緒持鎖：DOC1-0-03（不碰任何檔案）' ('held=' + $hold.Held + ' code=' + $r.Code)
        }
        finally { Stop-SdMutexHold $hold }
        $r = Invoke-SdRun $rootW $comps $fxW '' @{ Status = $true }
        Assert-Sd ($r.Code -eq 'DOC1-7-01') '鎖釋放後恢復'
        # 全部文件都由人核准 → APPROVED
        $rows = @(); foreach ($d in $script:PsSdDocOrder) { $rows += ('| ' + $d + ' | r0001 | ' + ([string]$pub4.Gate['docs'][$d]['docHash']).Substring(0, 12) + ' | 業務單位主管 | 2026-10-08 |') }
        Write-SdFx (Join-Path $inW 'approvals.md') ("# 人工核准`n`n| 文件 | 版本 | docHash 前 12 碼 | 核准者類別 | 日期 |`n|---|---|---|---|---|`n" + ($rows -join "`n") + "`n")
        $r = Invoke-SdRun $rootW $comps $fxW
        $pub5 = Get-SdPublished $rootW $jobW
        Assert-Sd ($r.Code -eq 'DOC1-7-02' -and [string]$pub5.Current['phase'] -ceq 'APPROVED') '15 份都依 docHash 核准 → DOC1-7-02（APPROVED）' $r.Code
        # 參數與版本
        $r = Invoke-SdRun $rootW 'TW_DEMO_APV,BAD!NAME' $fxW '' @{ Status = $true }
        Assert-Sd ($r.Code -eq 'DOC1-9-01' -and $r.Exit -eq 2) 'Component 名稱含不合法字元 → DOC1-9-01'
        $r = Invoke-SdRun $rootW $comps $fxW '' @{ Status = $true; Refresh = $true }
        Assert-Sd ($r.Code -eq 'DOC1-9-01') '-Status 與 -Refresh 混用 → DOC1-9-01'
        $plain = Join-Path $base 'plain'; [void][System.IO.Directory]::CreateDirectory($plain)
        $r = Invoke-SdRun $plain $comps $fxW
        Assert-Sd ($r.Code -eq 'DOC1-9-01' -and -not [System.IO.Directory]::Exists((Join-Path $plain '.ps-private'))) '不是 Claude Code 版（沒有 .claude/peoplesoft）→ DOC1-9-01，不建任何檔'
    }

    # ================= 中斷、失敗、重試、圍欄、覆核不通過、分頁 =================
    if ($Only -eq '' -or $Only -eq 'edge') {  # 中斷、失敗、重試、圍欄、覆核不通過、分頁
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
        Assert-Sd ((@($last.Outcome['findings']) -join ',') -match '^EXIT_[1-9][0-9]*$' -and $r.Output -match 'session 失敗，未消耗失敗次數；檢查 Claude Code／MCP') 'session 失敗的 findings 記結束碼 enum（EXIT_<n>）；沒有模型端重試時沿用「檢查 Claude Code／MCP」' (@($last.Outcome['findings']) -join ',')
        # ================= 研究頁每頁上限：超量 → INVALID 計次、下一張工單帶原因；兩次 → BLOCKED =================
        $fxC = New-SdRunFixtures 'walkthrough' 'status-REQ_STATUS.md' $wkPages $wkRecords $false 'cap'
        $rootC = New-SdRunRoot 'cap'
        $inC = Join-Path $rootC ('.ps-private/sdoc/' + $jobW)
        $jobRootC = Join-Path $rootC ('.ps-runtime/sdoc/' + $jobW)
        [void](Invoke-SdRun $rootC $comps $fxC)
        Write-SdFx (Join-Path $inC 'status.md') $fxC.Text
        Write-SdFx (Join-Path $inC 'project.md') ([System.IO.File]::ReadAllText((Join-Path $fxC.Example 'input/project.md'), [System.Text.Encoding]::UTF8))
        $env:PS_SDOC_RESEARCH_PAGE_ITEMS = '2'
        try { $rC = Invoke-SdRunUntilDone $rootC $comps $fxC '' 8 } finally { $env:PS_SDOC_RESEARCH_PAGE_ITEMS = '60' }
        $ocC = Get-SdOutcomes $jobRootC
        $capInv = @($ocC | Where-Object { [string]$_.Outcome['status'] -ceq 'INVALID' -and $_.Outcome['counted'] -eq $true -and (@($_.Outcome['findings']) -join ' ') -like '*超過上限 2 筆*' })
        $capMan = $false; $capInp = $false
        foreach ($e in $ocC) {
            if ([string]$e.Input['kind'] -cne 'RESEARCH') { continue }
            $mC = [System.IO.File]::ReadAllText((Join-Path (Join-Path $jobRootC ('attempts/' + $e.Id)) 'manifest.md'), [System.Text.Encoding]::UTF8)
            if ($mC.Contains('本頁上限：items 最多 2 個')) { $capInp = $true }
            if ($mC.Contains('前次未通過的原因') -and $mC.Contains('超過上限 2 筆')) { $capMan = $true }
        }
        Assert-Sd ($capInv.Count -ge 2 -and $capMan -and $capInp -and $rC.Code -eq 'DOC1-4-03') ('每頁上限：PS_SDOC_RESEARCH_PAGE_ITEMS=2 → 超量研究包 INVALID 計次（' + $capInv.Count + ' 次）、工單印上限 2、重派的工單帶「前次未通過的原因」、兩次後 BLOCKED（DOC1-4-03）') $rC.Code
        $r = Invoke-SdRunUntilDone $rootE $comps $fxE 'stray-once,review-fail-once-data,partial-ui-TW_DEMO_APV,dup-scope-TW_DEMO_REQ,l5-nis-DRV-002/D1,l5-nis-always-DRV-001/D3,l5-badcite-R2'
        $oc = Get-SdOutcomes $jobRootE
        $stray = @($oc | Where-Object { [string]$_.Outcome['status'] -ceq 'INVALID' -and (@($_.Outcome['findings']) -join ' ') -like '*stray.txt*' }).Count
        $qdir = Join-Path $rootE '.ps-runtime/sdoc/quarantine'
        $qfiles = 0; if ([System.IO.Directory]::Exists($qdir)) { $qfiles = @(Get-ChildItem -LiteralPath $qdir -File).Count }
        $rf = @($oc | Where-Object { [string]$_.Outcome['status'] -ceq 'REVIEW_FAIL' -and [string]$_.Input['unit'] -ceq 'data' }).Count
        $callsE = Get-SdCalls $fxE
        $p2 = @($callsE | Where-Object { $_ -ceq 'RESEARCH ui TW_DEMO_APV 2' }).Count
        Assert-Sd ($r.Code -eq 'DOC1-5-01') '邊界情境最後仍跑完；一題兩輪都沒讀懂 → DOC1-5-01（DRAFT）' ($r.Output -split "`n" | Select-Object -Last 12 | Out-String)
        Assert-Sd ($stray -eq 1 -and $qfiles -eq 1) 'worker 多寫檔：隔離到 quarantine、本次不合格且計次'
        Assert-Sd ($rf -eq 1) '覆核不通過：計次後重新研究，第二次覆核通過'
        Assert-Sd ($p2 -eq 1) '分頁：畫面單元第 1 頁 PARTIAL（含引用第 2 頁才寫的項目），第 2 頁 COMPLETE'
        $dupBad = @($oc | Where-Object { [string]$_.Outcome['status'] -ceq 'INVALID' -and [string]$_.Input['unit'] -ceq 'scope' -and (@($_.Outcome['findings']) -join ' ') -like '*別頁已寫過*' }).Count
        Assert-Sd ($dupBad -eq 1) '另一個 Component 重寫已驗收的物件：退回（改為參照），重做後通過'
        $pubE = Get-SdPublished $rootE $jobW
        $diff = @()
        foreach ($d in @('01-overview', '02-functional-requirements', '03-roles-permissions', '04-workflow', '05-ui', '06-architecture', '07-database', '08-api', '09-business-logic')) {
            if ((Get-SdKeySet $pubE.Docs[$d]['items']) -cne (Get-SdKeySet $fxE.Fixture.Docs[$d]['items'])) { $diff += $d }
        }
        if ((Get-SdKeySet $pubE.Docs['14-testing']['items']) -cne (@($tcWantSorted) -join '|')) { $diff += '14-testing' }
        Assert-Sd ($diff.Count -eq 0 -and [string]$pubE.Current['revision'] -ceq 'r0002') '邊界情境的發布內容仍與範例相同（r0002）' ($diff -join '、')
        # L5：第 1 輪沒讀懂 → 原研究單元改寫 → 第 2 輪；仍沒讀懂 → READER 問題（BLOCKING）
        $amendRc = $null
        foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $jobRootE 'receipts/r0002') -Filter '*.json' -File)) { $rc = Read-SdFxJson $f.FullName; if (([string]$rc['cursor']).StartsWith('L5-AMEND')) { $amendRc = $rc } }
        $aqs = @(); if ($null -ne $amendRc) { foreach ($x in @($amendRc['amendQuestions'])) { $aqs += [string]$x } }
        Assert-Sd ($null -ne $amendRc -and [string]$amendRc['unit'] -ceq 'data' -and $aqs -ccontains 'DRV-002/D1' -and $aqs -ccontains 'DRV-001/D3') '第 1 輪沒讀懂的兩題交給資料單元改寫（L5-AMEND 頁，覆核通過才收）' ($aqs -join '、')
        $rq = @($pubE.Docs['90-questions']['items'] | Where-Object { [string]$_['key'] -ceq 'READER_UNDERSPECIFIED:DRV-001:D3' })
        $rq2 = @($pubE.Docs['90-questions']['items'] | Where-Object { [string]$_['key'] -like 'READER_*:DRV-002:D1' })
        Assert-Sd ($rq.Count -eq 1 -and [string]$rq[0]['severity'] -ceq 'BLOCKING' -and $rq2.Count -eq 0) '第 2 輪：改寫後讀懂的題目通過；仍答「文件沒寫」的開 READER_UNDERSPECIFIED（BLOCKING）'
        Assert-Sd ([string]$pubE.Gate['docs']['07-database']['gate']['L5'] -ceq 'PASS' -and [string]$pubE.Gate['docs']['07-database']['gate']['L3'] -ceq 'FAIL' -and [string]$pubE.Docs['07-database']['status'] -ceq 'draft') 'L5 做完記 PASS；未解的 READER 問題讓 07 的 L3（C09）FAIL、文件維持 draft'
        $retry = @($oc | Where-Object { [string]$_.Input['workKey'] -like 'l5/*/R2/retry' -and [string]$_.Outcome['status'] -ceq 'ACCEPTED' }).Count
        Assert-Sd ($retry -ge 1) '讀者答案沒有出處：同一輪重問該讀者一次'
        $uiIds = @(); foreach ($it in @($pubE.Docs['05-ui']['items'])) { $uiIds += [string]$it['id'] }
        $bad = @(); foreach ($it in @($pubE.Docs['05-ui']['items'])) { foreach ($ref in (Get-PsSdItemRefs $it)) { if ((Get-PsSdIdPrefix $ref) -ceq 'UI' -and $uiIds -cnotcontains $ref) { $bad += $ref } } }
        Assert-Sd ($bad.Count -eq 0) '分頁的前向引用在組裝時換成正式 ID' ($bad -join '、')
    }

    # ================= 守門範例：三份解讀不一致 → 第 2 輪多數決 =================
    if ($Only -eq '' -or $Only -eq 'gate') {  # 守門範例、第 2 輪仍無多數、分段寫
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

        # ================= 解讀分段寫：缺段退回、一次寫完的 output.json 照收 =================
        $fxP = New-SdRunFixtures 'gate' 'status-CASE_STATUS.md' @() @() $true 'parts'
        $rootP = New-SdRunRoot 'parts'
        [void](Invoke-SdRun $rootP $gComps $fxP)
        Write-SdFx (Join-Path $rootP ('.ps-private/sdoc/' + $jobG + '/status.md')) $fxP.Text
        $r = Invoke-SdRun $rootP $gComps $fxP 'read-skip-part-once,read-whole-R3' @{ MaxSessions = 4 }
        $ocP = Get-SdOutcomes (Join-Path $rootP ('.ps-runtime/sdoc/' + $jobG))
        $byReader = @{}; foreach ($e in $ocP) { $k = [string]$e.Input['workKey']; if (-not $byReader.ContainsKey($k)) { $byReader[$k] = @() }; $byReader[$k] += , $e }
        $r1 = @($byReader['stage0/read/R1']); $r2 = @($byReader['stage0/read/R2']); $r3 = @($byReader['stage0/read/R3'])
        $nParts = @($r1[0].Input['outputParts']).Count
        $r2Dir = Join-Path $rootP ('.ps-runtime/sdoc/' + $jobG + '/attempts/' + $r2[0].Id)
        $manP = [System.IO.File]::ReadAllText((Join-Path (Join-Path $rootP ('.ps-runtime/sdoc/' + $jobG + '/attempts/' + $r1[0].Id)) 'manifest.md'), [System.Text.Encoding]::UTF8)
        Assert-Sd ($nParts -ge 5 -and $manP.Contains('分 ' + $nParts + ' 段寫') -and [System.IO.File]::Exists((Join-Path $r2Dir 'output-part-01.json')) -and [System.IO.File]::Exists((Join-Path $r2Dir ('output-part-' + $nParts.ToString('00') + '.json'))) -and [System.IO.File]::Exists((Join-Path $r2Dir 'output.json')) -and [string]$r2[0].Outcome['status'] -ceq 'ACCEPTED') ('分段寫：工單與 manifest 列出 ' + $nParts + ' 段；各段原樣留在 attempt、合併成 output.json 後驗收通過')
        Assert-Sd ($r1.Count -eq 2 -and [string]$r1[0].Outcome['status'] -ceq 'INVALID' -and $r1[0].Outcome['counted'] -eq $true -and (@($r1[0].Outcome['findings']) -join ' ') -like ('*第 ' + $nParts + ' 段沒有寫*') -and [string]$r1[1].Outcome['status'] -ceq 'ACCEPTED') '分段寫：少寫一段 → INVALID（指出第幾段），重派後通過' ((@($r1[0].Outcome['findings']) -join ' ') + ' / ' + $r.Code)
        Assert-Sd ($r3.Count -eq 1 -and [string]$r3[0].Outcome['status'] -ceq 'ACCEPTED') '分段寫：讀者一次寫完 output.json 也照收'
        # ================= session 失敗但產出已驗收：照收（寫完後才失敗的那個請求） =================
        $fxF = New-SdRunFixtures 'gate' 'status-CASE_STATUS.md' @() @() $true 'partsfail'
        $rootF = New-SdRunRoot 'partsfail'
        [void](Invoke-SdRun $rootF $gComps $fxF)
        Write-SdFx (Join-Path $rootF ('.ps-private/sdoc/' + $jobG + '/status.md')) $fxF.Text
        $rF = Invoke-SdRun $rootF $gComps $fxF 'read-fail-after-all' @{ MaxSessions = 1 }
        $ocF = Get-SdOutcomes (Join-Path $rootF ('.ps-runtime/sdoc/' + $jobG)); $ocF = @($ocF)
        Assert-Sd ($ocF.Count -eq 1 -and [string]$ocF[0].Outcome['status'] -ceq 'ACCEPTED' -and (@($ocF[0].Outcome['sessionFindings']) -join ',') -match '^EXIT_[1-9][0-9]*$' -and $rF.Code -like 'DOC1-3-02-*' -and $rF.Output.Contains('但產出已驗收通過，照收')) ('session 失敗但各段都寫完且合格 → ACCEPTED、outcome 記 sessionFindings=EXIT_1、不是 DOC1-3-04（' + $rF.Code + '）') ($rF.Output)
    }

    # ================= OpenCode 版（-Cli opencode）：獨立目錄、模型設定、與 Claude Code 版並存、產出相同、模型預檢 =================
    if ($Only -eq '' -or $Only -eq 'opencode') {  # OpenCode 版
        if ($paths.OcSdocDir -eq '') { Write-Host 'SKIP OpenCode 版情境：這個版面沒有 .opencode/peoplesoft/sdoc（Claude Code 版搬運包解開的資料夾）' }
        else {
            $hasClaudeSdoc = [System.IO.Directory]::Exists($paths.SdocDir) -and $paths.SdocDir -ne $paths.OcSdocDir
            $gComps = 'TW_DEMO_CASE,TW_DEMO_DOCREV,TW_DEMO_PAYMNT'
            $jobG = Get-SdRunJobId @('TW_DEMO_CASE', 'TW_DEMO_DOCREV', 'TW_DEMO_PAYMNT')
            # 只有 .opencode 的資料夾（另開資料夾部署）：不帶 -Cli 也認成 OpenCode 版，目錄各加 -opencode
            $fxO = New-SdRunFixtures 'gate' 'status-CASE_STATUS.md' @() @() $true 'oc'
            $rootO = New-SdRunRootOc 'oc'
            $inO = Join-Path $rootO ('.ps-private/sdoc-opencode/' + $jobG)
            $r = Invoke-SdRun $rootO $gComps $fxO
            Assert-Sd ($r.Code -eq 'DOC1-0-01' -and [System.IO.File]::Exists((Join-Path $inO 'status.md')) -and -not [System.IO.Directory]::Exists((Join-Path $rootO '.ps-private/sdoc'))) 'OpenCode 版：人工輸入骨架建在 .ps-private/sdoc-opencode/<job>/，不碰 .ps-private/sdoc/' $r.Output
            Assert-Sd ($r.Output.Contains('OpenCode 模型：anthropic/claude-haiku-4-5（.opencode/peoplesoft/sdoc/model.yaml）') -and $r.Output.Contains("-Components 'TW_DEMO_CASE,TW_DEMO_DOCREV,TW_DEMO_PAYMNT' -Cli opencode")) 'OpenCode 版：印出模型與唯一設定檔；續跑命令帶 -Cli opencode' $r.Output
            Assert-Sd ($r.Output.Contains('提醒：.opencode/peoplesoft/customization-profile.yaml 的 oracle.currentSchema 還沒填') -and $r.Code -eq 'DOC1-0-01') 'OpenCode 版：profile 沒填表的擁有者 → 只提醒、不擋' $r.Output
            # 貫穿範例跑到 REVIEW_READY（含 L5 讀者與判定）：目錄、工單、與 Claude Code 版逐位元相同的產出
            $fxOW = New-SdRunFixtures 'walkthrough' 'status-REQ_STATUS.md' $wkPages $wkRecords $false 'oc-walk'
            $rootOW = New-SdRunRootOc 'oc-walk'
            [void](Invoke-SdRun $rootOW $comps $fxOW)
            $inOW = Join-Path $rootOW ('.ps-private/sdoc-opencode/' + $jobW)
            Write-SdFx (Join-Path $inOW 'status.md') $fxOW.Text
            Write-SdFx (Join-Path $inOW 'project.md') ([System.IO.File]::ReadAllText((Join-Path $fxOW.Example 'input/project.md'), [System.Text.Encoding]::UTF8))
            $r = Invoke-SdRunUntilDone $rootOW $comps $fxOW
            $jobRootO = Join-Path $rootOW ('.ps-runtime/sdoc-opencode/' + $jobW)
            $outO = Join-Path $rootOW ('docs/ps-spec-opencode/' + $jobW)
            $curO = Join-Path $outO 'current.json'
            Assert-Sd ($r.Code -eq 'DOC1-7-01' -and [System.IO.File]::Exists($curO) -and [System.IO.Directory]::Exists((Join-Path $jobRootO 'attempts')) -and -not [System.IO.Directory]::Exists((Join-Path $rootOW '.ps-runtime/sdoc')) -and -not [System.IO.Directory]::Exists((Join-Path $rootOW 'docs/ps-spec'))) ('OpenCode 版：貫穿範例跑到 REVIEW_READY；執行狀態在 .ps-runtime/sdoc-opencode/、產出在 docs/ps-spec-opencode/（' + $r.Code + '）') ($r.Output -split "`n" | Select-Object -Last 12 | Out-String)
            $ocO = Get-SdOutcomes $jobRootO
            $man = @{}
            foreach ($e in $ocO) {
                $k = [string]$e.Input['kind']
                if (-not $man.ContainsKey($k)) { $man[$k] = [System.IO.File]::ReadAllText((Join-Path (Join-Path $jobRootO ('attempts/' + $e.Id)) 'manifest.md'), [System.Text.Encoding]::UTF8) }
            }
            $allMan = ($man.Values | ForEach-Object { [string]$_ }) -join "`n"
            Assert-Sd ([string]$man['STATUS_READ'] -like '*.opencode/peoplesoft/sdoc/status-reading-contract.md*' -and [string]$man['RESEARCH'] -like '*.opencode/peoplesoft/sdoc/research-contract.md*' -and [string]$man['RESEARCH'] -like '*.opencode/peoplesoft/sdoc/examples/*' -and [string]$man['REVIEW'] -like '*.opencode/peoplesoft/sdoc/review-contract.md*' -and [string]$man['READER'] -like '*.opencode/peoplesoft/sdoc/reader-contract.md*' -and [string]$man['JUDGE'] -like '*.opencode/peoplesoft/sdoc/judge-contract.md*' -and [string]$man['READER'] -like '*.ps-runtime/sdoc-opencode/*/inbox/*' -and -not $allMan.Contains('.claude/') -and ([string]$ocO[0].Input['statusPath']).StartsWith('.ps-private/sdoc-opencode/')) ('工單（解讀、研究、覆核、L5 讀者、判定）都指向 OpenCode 版的契約與 *-opencode 目錄，不出現 .claude/（種類 ' + (@($man.Keys | Sort-Object) -join ',') + '）')
            if ($hasClaudeSdoc) {
                # 同一份合成 worker 輸出：OpenCode 版發布的文件與 Claude Code 版逐位元相同（只有前端不同）
                $fxKW = New-SdRunFixtures 'walkthrough' 'status-REQ_STATUS.md' $wkPages $wkRecords $false 'oc-walk-claude'
                $rootKW = New-SdRunRoot 'oc-walk-claude'
                [void](Invoke-SdRun $rootKW $comps $fxKW)
                $inKW = Join-Path $rootKW ('.ps-private/sdoc/' + $jobW)
                Write-SdFx (Join-Path $inKW 'status.md') $fxKW.Text
                Write-SdFx (Join-Path $inKW 'project.md') ([System.IO.File]::ReadAllText((Join-Path $fxKW.Example 'input/project.md'), [System.Text.Encoding]::UTF8))
                $rK = Invoke-SdRunUntilDone $rootKW $comps $fxKW
                $curK = Read-SdFxJson (Join-Path $rootKW ('docs/ps-spec/' + $jobW + '/current.json'))
                $curOn = Read-SdFxJson $curO
                $genK = Join-Path $rootKW ('docs/ps-spec/' + $jobW + '/generated/' + [string]$curK['generation'])
                $genO = Join-Path $outO ('generated/' + [string]$curOn['generation'])
                Assert-Sd ($rK.Code -ceq $r.Code -and [string]$curK['generation'] -ceq [string]$curOn['generation'] -and (Get-SdTreeText $genK) -ceq (Get-SdTreeText $genO) -and ((Get-SdCalls $fxKW) -join '|') -ceq ((Get-SdCalls $fxOW) -join '|')) ('同一份 worker 輸出：OpenCode 版與 Claude Code 版的派工順序、結論碼、generated 世代與全部文件逐位元相同（' + $rK.Code + '／' + $r.Code + '）')
            }
            else { Write-Host 'SKIP 兩版產出比對：這個版面只有 OpenCode 版' }

            # 同一資料夾兩版並存：Claude Code 版照舊；-Cli opencode 另一份工作，第一次從 Claude Code 版複製 status.md
            if ($hasClaudeSdoc) {
                $fxC = New-SdRunFixtures 'gate' 'status-CASE_STATUS.md' @() @() $true 'both-claude'
                $fxB = New-SdRunFixtures 'gate' 'status-CASE_STATUS.md' @() @() $true 'both-oc'
                $rootB = New-SdRunRootOc 'both' -WithClaude
                [void](Invoke-SdRun $rootB $gComps $fxC)
                Write-SdFx (Join-Path $rootB ('.ps-private/sdoc/' + $jobG + '/status.md')) $fxC.Text
                $r = Invoke-SdRun $rootB $gComps $fxC '' @{ MaxSessions = 2 }
                $jrC = Join-Path $rootB ('.ps-runtime/sdoc/' + $jobG)
                $nC = (Get-SdOutcomes $jrC).Count
                $revC = Get-SdTreeText (Join-Path $jrC 'revisions')
                Assert-Sd ($r.Code -like 'DOC1-3-02-*' -and $nC -eq 2 -and -not $r.Output.Contains('OpenCode')) '兩版並存：不帶 -Cli＝Claude Code 版，照舊用 .ps-private/sdoc 與 .ps-runtime/sdoc' $r.Output
                $cliBefore = [string]$env:PS_CLI; $noClaudeBefore = [string]$env:OPENCODE_DISABLE_CLAUDE_CODE
                # Claude Code 版的 profile 已填、OpenCode 版還是 FILL_ME：提醒裡給複製方法
                $pfSrc = Join-Path $repo '.opencode/peoplesoft/customization-profile.yaml'
                $pfText = [System.IO.File]::ReadAllText($pfSrc, [System.Text.Encoding]::UTF8)
                Write-SdFx (Join-Path $rootB '.claude/peoplesoft/customization-profile.yaml') ($pfText -replace '(?m)^  currentSchema: FILL_ME', '  currentSchema: DEMOOWN')
                Write-SdFx (Join-Path $rootB '.opencode/peoplesoft/customization-profile.yaml') $pfText
                $r = Invoke-SdRun $rootB $gComps $fxB '' @{ Cli = 'opencode'; MaxSessions = 2 }
                Assert-Sd ($r.Output.Contains('copy .claude\peoplesoft\customization-profile.yaml .opencode\peoplesoft\customization-profile.yaml')) '兩版並存：OpenCode 版 profile 沒填、Claude Code 版填好了 → 提醒裡給整份複製的命令' $r.Output
                $inB = Join-Path $rootB ('.ps-private/sdoc-opencode/' + $jobG)
                $jrB = Join-Path $rootB ('.ps-runtime/sdoc-opencode/' + $jobG)
                $stB = [System.IO.File]::ReadAllText((Join-Path $inB 'status.md'), [System.Text.Encoding]::UTF8)
                Assert-Sd ($r.Output.Contains('已從 Claude Code 版同一組 Component 的輸入') -and $stB -ceq $fxC.Text -and $r.Code -like 'DOC1-3-02-*' -and (Get-SdOutcomes $jrB).Count -eq 2) '兩版並存：-Cli opencode 第一次從 Claude Code 版複製 status.md，在 *-opencode 目錄另跑一份工作' $r.Output
                Assert-Sd ((Get-SdOutcomes $jrC).Count -eq $nC -and (Get-SdTreeText (Join-Path $jrC 'revisions')) -ceq $revC -and [string]$env:PS_CLI -ceq $cliBefore -and [string]$env:OPENCODE_DISABLE_CLAUDE_CODE -ceq $noClaudeBefore) '兩版並存：OpenCode 版沒有動到 Claude Code 版的工作；PS_CLI／OPENCODE_DISABLE_CLAUDE_CODE 跑完還原'
                $r = Invoke-SdRun $rootB $gComps $fxC '' @{ MaxSessions = 1 }
                Assert-Sd ($r.Code -like 'DOC1-3-02-*' -and -not $r.Output.Contains('開始新研究版本') -and (Get-SdOutcomes $jrC).Count -eq ($nC + 1) -and (Get-SdTreeText (Join-Path $jrC 'revisions')) -ceq $revC) '兩版並存：之後再跑 Claude Code 版，接著原本的研究版本續跑（不因 OpenCode 版開新版本）' $r.Output
            }
            else { Write-Host 'SKIP 兩版並存：這個版面只有 OpenCode 版' }

            # 模型設定：只有 model.yaml 一個地方；-Model 可臨時覆寫；寫錯就 DOC1-9-01、不建任何檔
            $mY = Join-Path $rootO '.opencode/peoplesoft/sdoc/model.yaml'
            $mOrig = [System.IO.File]::ReadAllText($mY, [System.Text.Encoding]::UTF8)
            [System.IO.File]::WriteAllText($mY, ("# 測試`r`nmodel: 'company-gw/qwen3.6-35b-a3b:latest'   # 地端`r`n"), (New-Object System.Text.UTF8Encoding($true)))
            $r = Invoke-SdRun $rootO $gComps $fxO '' @{ Status = $true }
            Assert-Sd ($r.Output.Contains('OpenCode 模型：company-gw/qwen3.6-35b-a3b:latest（.opencode/peoplesoft/sdoc/model.yaml）')) 'model.yaml：引號、行尾註解、CRLF、BOM 都讀得懂' $r.Output
            Write-SdFx (Join-Path $rootO '.opencode/peoplesoft/customization-profile.yaml') ("oracle:`n  currentSchema: DEMOOWN   # 已填`n")
            $r = Invoke-SdRun $rootO $gComps $fxO '' @{ Status = $true; Model = 'other/x-1' }
            Assert-Sd (-not $r.Output.Contains('oracle.currentSchema 還沒填')) 'profile 已填表的擁有者 → 不提醒' $r.Output
            Assert-Sd ($r.Output.Contains('OpenCode 模型：other/x-1（-Model）') -and $r.Output.Contains("-Cli opencode -Model 'other/x-1'")) '-Model 臨時覆寫 model.yaml，續跑命令帶著它' $r.Output
            $plainO = New-SdRunRootOc 'oc-badmodel'
            [System.IO.File]::WriteAllText((Join-Path $plainO '.opencode/peoplesoft/sdoc/model.yaml'), "model: FILL_ME`n", (New-Object System.Text.UTF8Encoding($false)))
            $r = Invoke-SdRun $plainO $gComps $fxO
            Assert-Sd ($r.Code -eq 'DOC1-9-01' -and $r.Exit -eq 2 -and $r.Output.Contains('model.yaml') -and -not [System.IO.Directory]::Exists((Join-Path $plainO '.ps-private'))) 'model.yaml 沒填好（FILL_ME）→ DOC1-9-01，指出要改 model.yaml，不建任何檔' $r.Output
            [System.IO.File]::Delete((Join-Path $plainO '.opencode/peoplesoft/sdoc/model.yaml'))
            $r = Invoke-SdRun $plainO $gComps $fxO
            Assert-Sd ($r.Code -eq 'DOC1-9-01' -and $r.Output.Contains('model.yaml')) '沒有 model.yaml → DOC1-9-01' $r.Output
            $r = Invoke-SdRun $rootO $gComps $fxO '' @{ Status = $true; Model = 'noslash' }
            Assert-Sd ($r.Code -eq 'DOC1-9-01') '-Model 不是 <provider>/<model> → DOC1-9-01' $r.Output
            $r = Invoke-SdRun $rootO $gComps $fxO '' @{ Status = $true; Cli = 'bogus' }
            Assert-Sd ($r.Code -eq 'DOC1-9-01') '-Cli 只收 claude／opencode → 其他 DOC1-9-01' $r.Output
            [System.IO.File]::WriteAllText($mY, $mOrig, (New-Object System.Text.UTF8Encoding($false)))
            $oldOc = Join-Path $base 'oc-old'; [void][System.IO.Directory]::CreateDirectory((Join-Path $oldOc '.opencode/peoplesoft'))
            $r = Invoke-SdRun $oldOc $gComps $fxO
            Assert-Sd ($r.Code -eq 'DOC1-9-01' -and $r.Output.Contains('.opencode/peoplesoft/sdoc') -and -not [System.IO.Directory]::Exists((Join-Path $oldOc '.ps-private'))) '舊的 OpenCode 部署（沒有 .opencode/peoplesoft/sdoc）→ DOC1-9-01，不建任何檔' $r.Output

            # 模型預檢（opencode models <provider>）：假 opencode 列出清單或回 Provider not found
            . (Join-Path $tools 'ps-session-lib.ps1')
            $fakeOc = Join-Path $base 'fake-opencode'
            [void][System.IO.Directory]::CreateDirectory($fakeOc)
            $isWin = ([System.IO.Path]::DirectorySeparatorChar -eq [char]92)
            $callLog = Join-Path $fakeOc 'calls.txt'
            if ($isWin) {
                $ocExe = Join-Path $fakeOc 'opencode.cmd'
                [System.IO.File]::WriteAllText($ocExe, ("@echo off`r`n" + 'echo %* >> "' + $callLog + '"' + "`r`n" + 'if "%1"=="run" exit /b 3' + "`r`n" + 'if "%2"=="mock" (echo mock/scripted& echo mock/other-1& exit /b 0)' + "`r`n" + 'if "%2"=="slow" (ping -n 8 127.0.0.1 > nul& exit /b 0)' + "`r`n" + 'echo Error: Provider not found: %2 1>&2' + "`r`n" + "exit /b 1`r`n"), (New-Object System.Text.ASCIIEncoding))
            }
            else {
                $ocExe = Join-Path $fakeOc 'opencode'
                [System.IO.File]::WriteAllText($ocExe, ("#!/bin/sh`n" + 'echo "$*" >> "' + $callLog + '"' + "`n" + 'if [ "$1" = "run" ]; then exit 3; fi' + "`n" + 'if [ "$2" = "mock" ]; then echo mock/scripted; echo mock/other-1; exit 0; fi' + "`n" + 'if [ "$2" = "slow" ]; then sleep 8; exit 0; fi' + "`n" + 'printf ''\033[91m\033[1mError: \033[0mProvider not found: %s\n'' "$2" >&2' + "`n" + "exit 1`n"), (New-Object System.Text.UTF8Encoding($false)))
                & chmod +x $ocExe
            }
            $pfLog = Join-Path $base 'preflight-logs'
            $m1 = Test-PsOcOpencodeModel -OcPath $ocExe -Model 'mock/scripted' -Root $rootO -LogRoot $pfLog
            $m2 = Test-PsOcOpencodeModel -OcPath $ocExe -Model 'mock/other-2' -Root $rootO -LogRoot $pfLog
            $m3 = Test-PsOcOpencodeModel -OcPath $ocExe -Model 'nosuch/x' -Root $rootO -LogRoot $pfLog
            $m4 = Test-PsOcOpencodeModel -OcPath $ocExe -Model 'slow/x' -Root $rootO -LogRoot $pfLog -TimeoutSec 2
            $m5 = Test-PsOcOpencodeModel -OcPath (Join-Path $fakeOc 'missing.cmd') -Model 'mock/scripted' -Root $rootO -LogRoot $pfLog
            Assert-Sd ($m1.Result -eq 'OK' -and $m2.Result -eq 'NOT_LISTED' -and $m2.Count -eq 2 -and $m3.Result -eq 'NO_PROVIDER' -and $m4.Result -eq 'UNKNOWN' -and $m5.Result -eq 'UNKNOWN') ('模型預檢：清單有＝OK、provider 有但沒這個模型＝NOT_LISTED、Provider not found＝NO_PROVIDER、逾時與無法執行＝UNKNOWN（不擋）：' + $m1.Result + '/' + $m2.Result + '/' + $m3.Result + '/' + $m4.Result + '/' + $m5.Result)

            # session slot 兩版各一把：另一版占著不影響，同一版占著才 SLOT_BUSY（session 不啟動，外環 DOC1-3-03）
            $slotC = Get-PsOcSessionSlotName -Cli 'claude'; $slotO = Get-PsOcSessionSlotName -Cli 'opencode'
            Assert-Sd ($slotC -ceq 'Global\MCPSample-OpencodeSession' -and $slotO -ceq 'Global\MCPSample-OpencodeSession-opencode' -and (Get-PsOcSessionSlotName) -ceq $slotC) 'session slot：Claude Code 版沿用原本的名字（還沒換新 scripts 的資料夾也用它），OpenCode 版另一把'
            $slotLog = Join-Path $base 'slot-logs'
            $rootSC = Join-Path $base 'slot-claude'; [void][System.IO.Directory]::CreateDirectory((Join-Path $rootSC '.claude/peoplesoft'))
            $rootSO = Join-Path $base 'slot-oc'; [void][System.IO.Directory]::CreateDirectory((Join-Path $rootSO '.opencode/peoplesoft'))
            $script:slotMsgs = @()
            $hold = Start-SdMutexHold $slotC 'hold-claude'
            try {
                $eo = Enter-PsOcSessionSlot -Cli 'opencode'; $okO = [bool]$eo.Held; Exit-PsOcSessionSlot -Slot $eo
                $ec = Enter-PsOcSessionSlot -Cli 'claude'
                $sc = Invoke-PsOcSession -OcPath 'unused.cmd' -Root $rootSC -LogRoot $slotLog -PromptText 'x/a0001' -TimeoutMin 1 -Tag 'slot-c' -SlotWaitMin 0 -Log { param($m) $script:slotMsgs += $m }
                Assert-Sd ($hold.Held -and $okO -and -not $ec.Held -and [string]$ec.Reason -ceq 'session slot 被占用（Claude Code 版）' -and [bool]$sc.SlotBusy -and [string]$sc.FailureKind -ceq 'SLOT_BUSY' -and (($script:slotMsgs -join ' ') -like '*同一版另一個*另一版不受影響*')) 'session slot：Claude Code 版的那把被占時，OpenCode 版照樣取得；Claude Code 版的 session 回 SLOT_BUSY、不啟動' ($script:slotMsgs -join ' ')
            }
            finally { Stop-SdMutexHold $hold }
            $hold = Start-SdMutexHold $slotO 'hold-oc'
            try {
                $ec = Enter-PsOcSessionSlot -Cli 'claude'; $okC = [bool]$ec.Held; Exit-PsOcSessionSlot -Slot $ec
                $eo = Enter-PsOcSessionSlot -Cli 'opencode'
                $so = Invoke-PsOcSession -OcPath 'unused.cmd' -Root $rootSO -LogRoot $slotLog -PromptText 'x/a0001' -TimeoutMin 1 -Tag 'slot-o' -SlotWaitMin 0 -Log { param($m) }
                $cliSaved = $env:PS_CLI
                try { $env:PS_CLI = 'opencode'; $sb = Invoke-PsOcSession -OcPath 'unused.cmd' -Root $rootSC -LogRoot $slotLog -PromptText 'x/a0001' -TimeoutMin 1 -Tag 'slot-b' -SlotWaitMin 0 -Log { param($m) } }
                finally { $env:PS_CLI = $cliSaved }
                Assert-Sd ($hold.Held -and $okC -and -not $eo.Held -and [string]$eo.Reason -ceq 'session slot 被占用（OpenCode 版）' -and [bool]$so.SlotBusy -and [bool]$sb.SlotBusy) 'session slot：OpenCode 版的那把被占時，Claude Code 版照樣取得；OpenCode 版的 session（含同資料夾 PS_CLI=opencode，也就是 ps-sdoc -Cli opencode）回 SLOT_BUSY'
            }
            finally { Stop-SdMutexHold $hold }
            $e2 = Enter-PsOcSessionSlot -Cli 'opencode'; $e3 = Enter-PsOcSessionSlot -Cli 'claude'
            Assert-Sd ([bool]$e2.Held -and [bool]$e3.Held) 'session slot：放開之後兩版都取得到（沒有殘留占用）'
            Exit-PsOcSessionSlot -Slot $e2; Exit-PsOcSessionSlot -Slot $e3
            if ($isWin) {
                # 真的走外環：假 opencode.cmd 放在 PATH 最前面（ps-sdoc 以 cmd.exe 啟動）
                $savedPath = $env:PATH
                $env:PATH = $fakeOc + [System.IO.Path]::PathSeparator + $env:PATH
                try {
                    $rootW2 = New-SdRunRootOc 'oc-win'
                    $inW2 = Join-Path $rootW2 ('.ps-private/sdoc-opencode/' + $jobG)
                    [void][System.IO.Directory]::CreateDirectory($inW2)
                    Write-SdFx (Join-Path $inW2 'status.md') $fxO.Text
                    $h = @{ Root = $rootW2; Components = $gComps; MaxSessions = 1; TimeoutMin = 2; Model = 'mock/other-2' }
                    $out1 = ((& $cli @h *>&1 | ForEach-Object { [string]$_ }) -join "`n")
                    $lines1 = @($out1 -split "`n" | Where-Object { $_.Trim() -ne '' })
                    Assert-Sd ($lines1[-1].Trim() -eq 'DOC1-9-01' -and $out1.Contains('模型不能用') -and -not [System.IO.Directory]::Exists((Join-Path $rootW2 ('.ps-runtime/sdoc-opencode/' + $jobG + '/attempts')))) '外環（Windows）：模型不在 opencode models 清單 → 開 session 前就停在 DOC1-9-01' $out1
                    [System.IO.File]::WriteAllText($callLog, '', (New-Object System.Text.ASCIIEncoding))
                    $h['Model'] = 'mock/scripted'
                    $out2 = ((& $cli @h *>&1 | ForEach-Object { [string]$_ }) -join "`n")
                    $lines2 = @($out2 -split "`n" | Where-Object { $_.Trim() -ne '' })
                    $calls = [System.IO.File]::ReadAllText($callLog)
                    Assert-Sd ($lines2[-1].Trim() -eq 'DOC1-3-04' -and $calls -match ('run --model "?mock/scripted"? --agent ps-status-reader --title "?auto-' + $jobG + '-a0001"? "?' + $jobG + '/a0001"?') -and $out2.Contains('檢查 OpenCode 的模型與 provider')) '外環（Windows）：opencode run --model <model.yaml 或 -Model> --agent ps-status-reader；session 失敗提示看模型與 provider' ($out2 + "`n" + $calls)
                    # 兩版同時跑：Claude Code 版的 session slot 被占時，OpenCode 版外環照樣開 session；OpenCode 版自己的被占才 DOC1-3-03
                    $hold = Start-SdMutexHold $slotC 'hold-claude-win'
                    try {
                        $rootW3 = New-SdRunRootOc 'oc-win-par'
                        $inW3 = Join-Path $rootW3 ('.ps-private/sdoc-opencode/' + $jobG)
                        [void][System.IO.Directory]::CreateDirectory($inW3)
                        Write-SdFx (Join-Path $inW3 'status.md') $fxO.Text
                        [System.IO.File]::WriteAllText($callLog, '', (New-Object System.Text.ASCIIEncoding))
                        $h3 = @{ Root = $rootW3; Components = $gComps; MaxSessions = 1; TimeoutMin = 2; Model = 'mock/scripted' }
                        $out3 = ((& $cli @h3 *>&1 | ForEach-Object { [string]$_ }) -join "`n")
                        $lines3 = @($out3 -split "`n" | Where-Object { $_.Trim() -ne '' })
                        $calls3 = [System.IO.File]::ReadAllText($callLog)
                        Assert-Sd ($hold.Held -and $lines3[-1].Trim() -eq 'DOC1-3-04' -and $calls3 -match '(?m)^run ') '兩版同時跑（Windows）：Claude Code 版的 session slot 被占時，OpenCode 版外環照樣開 session（假 opencode 回失敗＝DOC1-3-04，不是 DOC1-3-03）' ($out3 + "`n" + $calls3)
                    }
                    finally { Stop-SdMutexHold $hold }
                    $hold = Start-SdMutexHold $slotO 'hold-oc-win'
                    try {
                        $rootW4 = New-SdRunRootOc 'oc-win-busy'
                        $inW4 = Join-Path $rootW4 ('.ps-private/sdoc-opencode/' + $jobG)
                        [void][System.IO.Directory]::CreateDirectory($inW4)
                        Write-SdFx (Join-Path $inW4 'status.md') $fxO.Text
                        [System.IO.File]::WriteAllText($callLog, '', (New-Object System.Text.ASCIIEncoding))
                        $h4 = @{ Root = $rootW4; Components = $gComps; MaxSessions = 1; TimeoutMin = 2; Model = 'mock/scripted' }
                        $out4 = ((& $cli @h4 *>&1 | ForEach-Object { [string]$_ }) -join "`n")
                        $lines4 = @($out4 -split "`n" | Where-Object { $_.Trim() -ne '' })
                        $calls4 = [System.IO.File]::ReadAllText($callLog)
                        Assert-Sd ($hold.Held -and $lines4[-1].Trim() -eq 'DOC1-3-03' -and -not ($calls4 -match '(?m)^run ') -and $out4.Contains('另一版不受影響')) 'OpenCode 版自己的 session slot 被占（同一版另一個外環在跑）→ DOC1-3-03，不啟動 opencode run' ($out4 + "`n" + $calls4)
                        $ccExe = Join-Path $fakeOc 'claude.cmd'
                        [System.IO.File]::WriteAllText($ccExe, ("@echo off`r`n" + 'echo claude %* >> "' + $callLog + '"' + "`r`n" + "exit /b 3`r`n"), (New-Object System.Text.ASCIIEncoding))
                        $scw = Invoke-PsOcSession -OcPath $ccExe -Root $rootSC -LogRoot $slotLog -ExtraArgs '--agent ps-status-reader' -PromptText 'x/a0001' -TimeoutMin 1 -Tag 'slot-cw' -SlotWaitMin 0 -Log { param($m) }
                        $calls5 = [System.IO.File]::ReadAllText($callLog)
                        Assert-Sd (-not [bool]$scw.SlotBusy -and [int]$scw.ExitCode -eq 3 -and $calls5 -match '(?m)^claude -p --agent ps-status-reader') '兩版同時跑（Windows）：OpenCode 版的 session slot 被占時，Claude Code 版的 session 照樣啟動（假 claude 回 3）' ($calls5 + ' exit=' + $scw.ExitCode + ' kind=' + $scw.FailureKind)
                    }
                    finally { Stop-SdMutexHold $hold }
                }
                finally { $env:PATH = $savedPath }
            }
            else { Write-Host 'SKIP 外環真的啟動 opencode（需要 Windows cmd.exe）' }
        }
    }
}
finally {
    $env:PS_CLI = $priorEnv.Cli; $env:PS_SDOC_TEST_LIB = $priorEnv.Lib; $env:PS_SDOC_TEST_FIXTURES = $priorEnv.Fx; $env:PS_SDOC_TEST_MODE = $priorEnv.Mode; $env:PS_SDOC_READING_PART_LINES = $priorEnv.Part; $env:PS_SDOC_RESEARCH_PAGE_ITEMS = $priorEnv.PageItems
    if ($env:PS_SDOC_TEST_KEEP) { Write-Host ('保留測試目錄：' + $base) } else { try { Remove-Item -LiteralPath $base -Recurse -Force } catch { Write-Host ('無法刪除測試目錄：' + $base) } }
}
Write-Host ('sdoc run tests: PASS=' + $script:passed + ' FAIL=' + $script:failed)
if ($script:failed -gt 0) { exit 1 }
exit 0
