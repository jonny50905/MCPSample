# test-sdoc-assemble.ps1 — Spec 文件流程：研究包驗收、派號、組裝、計算文件、L2／L3 檢核、外殼與 docHash、渲染。
# 以設計範例為預期結果：把範例 canonical 拆回研究包，再組裝回來比對；另跑 20 種刻意破壞。合成資料，不查 MCP、不呼叫模型。
# 用法：pwsh -NoProfile -File scripts/tests/test-sdoc-assemble.ps1   （公司機：powershell -NoProfile -ExecutionPolicy Bypass -File …）
#       加 -WriteExamples：重生部署給 worker 看格式的研究包範例（claude-code/.claude/peoplesoft/sdoc/examples/）。
param([switch]$WriteExamples)
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
foreach ($f in @('ps-knowledge-lib', 'ps-sdoc-schema-lib', 'ps-sdoc-status-lib', 'ps-sdoc-lib', 'ps-sdoc-check-lib', 'ps-sdoc-render-lib')) { . (Join-Path $repo ('scripts/' + $f + '.ps1')) }
. (Join-Path $PSScriptRoot 'sdoc-test-fixtures.ps1')
$script:failed = 0; $script:passed = 0
function Assert-Sd([bool]$Condition, [string]$Name, [string]$Detail = '') {
    if ($Condition) { $script:passed++; Write-Host ('PASS ' + $Name) }
    else { $script:failed++; Write-Host ('FAIL ' + $Name); if ($Detail) { Write-Host ('     ' + $Detail) } }
}
function Test-SdAny($List, [scriptblock]$Pred) { foreach ($x in @($List)) { if ($null -ne $x -and (& $Pred $x)) { return $true } }; return $false }
$sdocDir = Join-Path $repo 'claude-code/.claude/peoplesoft/sdoc'
$reg = Read-PsSdSchemaDir @((Join-Path $sdocDir 'schemas'), (Join-Path $sdocDir 'schemas-runtime'))
$design = Join-Path $repo 'docs/design/spec-schema-framework'

function Invoke-SdAssemble {
    # 範例 → 第 0 階段 → 研究包 → 派號 → 組裝 → 檢核。回傳 @{ Model; Built; Skeleton; Summary; Registry; Fixture; L2; L3; W; Meta; Text }
    param([string]$Example, [string]$StatusRef, [string]$JobId, $Pages, $Records, [bool]$Round2)
    $ex = Join-Path $design ('examples/' + $Example)
    $text = [System.IO.File]::ReadAllText((Join-Path $ex ('input/' + $StatusRef)), [System.Text.Encoding]::UTF8)
    $readings = @(); foreach ($n in 1..3) { $readings += , (ConvertTo-PsSdNode (Read-PsSdJsonFile (Join-Path $ex ('readings/R' + $n + '.json')))) }
    $res = Compare-PsSdReadings $text $readings $null
    if ($Round2) {
        $maps = Get-PsSdAlignment $readings
        $truth = Get-PsSdReadingFacts $readings[0] $maps[0]
        $answers = @{}
        for ($i = 0; $i -lt 3; $i++) { foreach ($c in $res.Contested) { $a = 'NO'; if ($truth.Facts.ContainsKey($c.Key)) { $a = 'YES' }; $answers[[string]$i + '|' + $c.Key] = $a } }
        $res = Compare-PsSdReadings $text $readings $answers
    }
    $built = Get-PsSdBuiltModel $text $res
    $sk = Get-PsSdWorkflowSkeleton $built
    $summary = Get-PsSdStatusReadingSummary $res $StatusRef (Get-PsSdStatusFingerprint $text)
    $fx = Get-SdExampleReceipts $ex $JobId $StatusRef $Pages $Records
    $ids = New-PsSdIdRegistry
    [void](Update-PsSdRegistry $reg $ids $sk $fx.Receipts @())
    $proj = $null; $projPath = Join-Path $ex 'input/project.md'; if (Test-Path -LiteralPath $projPath) { $proj = [System.IO.File]::ReadAllText($projPath, [System.Text.Encoding]::UTF8) }
    $dec = $null; $decPath = Join-Path $ex 'input/decisions.md'; if (Test-Path -LiteralPath $decPath) { $dec = [System.IO.File]::ReadAllText($decPath, [System.Text.Encoding]::UTF8) }
    $aiT = Read-PsSdJsonNode (Join-Path $sdocDir 'ai-instructions.json')
    $model = Build-PsSdModel @{ SchemaReg = $reg; Registry = $ids; Skeleton = $sk; Built = $built; StageResult = $res; StatusRef = $StatusRef; Receipts = $fx.Receipts
        ProjectText = $proj; ProjectRef = 'project.md'; DecisionsText = $dec; DecisionsRef = 'decisions.md'; AiTemplate = @($aiT['clauses']); ExtraQuestions = $fx.ExtraQuestions }
    $meta = @{ JobId = $JobId; Revision = 'r0001'; Components = $fx.Components; FrameworkFp = (Get-PsSdFrameworkFingerprint $reg); StatusRef = $StatusRef; StatusFp = (Get-PsSdStatusFingerprint $text)
        ProjectRef = 'project.md'; ProjectFp = (Get-PsSdStatusFingerprint $proj); DecisionsRef = 'decisions.md'; DecisionsFp = (Get-PsSdStatusFingerprint $dec); StatusReading = $summary }
    return @{ Model = $model; Built = $built; Skeleton = $sk; Summary = $summary; Registry = $ids; Fixture = $fx; Meta = $meta; Text = $text; StageResult = $res
        L2 = (Invoke-PsSdL2Checks $model $ids); L3 = (Invoke-PsSdL3Checks $model $built $StatusRef $summary); W = (Get-PsSdSpeculationWarnings $model) }
}

# ---------------- 貫穿範例：拆回研究包再組裝 ----------------
$wkPages = @(
    @{ Component = 'TW_DEMO_APV'; Page = 'TW_DEMO_APVPG'; Fields = @('TW_DEMO_REQHDR.AMOUNT', 'TW_DEMO_REQHDR.REASON', 'TW_DEMO_REQHDR.COMMENTS', 'TW_DEMO_REQWRK.APPROVE_PB', 'TW_DEMO_REQWRK.RETURN_PB') }
    @{ Component = 'TW_DEMO_REQ'; Page = 'TW_DEMO_REQPG'; Fields = @('TW_DEMO_REQHDR.AMOUNT', 'TW_DEMO_REQHDR.REASON', 'TW_DEMO_REQHDR.REQ_TYPE', 'TW_DEMO_REQHDR.REQ_STATUS', 'TW_DEMO_REQWRK.SUBMIT_PB', 'TW_DEMO_REQWRK.WITHDRAW_PB') }
)
$wkRecords = @(@{ Record = 'TW_DEMO_REQHDR'; Fields = @('REQ_ID', 'REQUESTER_EMPLID', 'REQ_STATUS', 'REQ_TYPE', 'AMOUNT', 'REASON', 'COMMENTS', 'SUBMIT_DT', 'APPROVER_EMPLID', 'APPROVE_DT', 'OLD_REF_NO', 'PRIORITY_CD', 'BUDGET_CODE') })
$wk = Invoke-SdAssemble 'walkthrough' 'status-REQ_STATUS.md' 'clone-0123456789abcdef' $wkPages $wkRecords $false
$m = $wk.Model
# 每一包在驗收（Check）模式下都合格
$bad = @()
foreach ($r in $wk.Fixture.Receipts) {
    $ctx = New-PsSdResolveContext $reg $wk.Registry $wk.Skeleton 'status-REQ_STATUS.md' $wk.Built 'Check'
    $rr = Resolve-PsSdPacket $ctx $r.Packet
    if ($rr.Errors.Count -gt 0) { $bad += ($r.Ref + '：' + $rr.Errors[0]) }
    $se = Test-PsSdSchema $reg 'urn:ps-sdoc:schema:research-packet' $r.Packet
    if (@($se).Count -gt 0) { $bad += ($r.Ref + ' 研究包 schema：' + @($se)[0]) }
}
Assert-Sd ($bad.Count -eq 0) ('組裝：' + $wk.Fixture.Receipts.Length + ' 包研究包都通過驗收') ($bad -join '；')
Assert-Sd ($m.Problems.Count -eq 0) '組裝：沒有輸入或收據問題' (($m.Problems | Select-Object -First 3) -join '；')
# 與範例逐項比對（證據以內容比；GOAL 的名稱與 DEC 的敘述在範例是手寫的，只比結構欄位）
$evNew = New-PsSdMap; foreach ($e in $m.Evidence) { $evNew[[string]$e['id']] = Get-PsSdEvidenceSignature $e }
$evOld = New-PsSdMap; foreach ($e in $wk.Fixture.Docs['evidence']['items']) { $evOld[[string]$e['id']] = Get-PsSdEvidenceSignature $e }
$diffs = @(); $same = 0
foreach ($d in $script:PsSdDocOrder) {
    $old = @{}; foreach ($it in $wk.Fixture.Docs[$d]['items']) { $old[[string]$it['id']] = $it }
    $newItems = Get-PsSdDocItems $m $d
    if ($newItems.Length -ne $old.Count) { $diffs += ($d + ' 項目數 ' + $newItems.Length + '≠' + $old.Count) }
    foreach ($it in $newItems) {
        $id = [string]$it['id']
        if (-not $old.ContainsKey($id)) { $diffs += ($d + ' 多 ' + $id); continue }
        $a = ConvertTo-SdComparable $it $evNew ''; $b = ConvertTo-SdComparable $old[$id] $evOld ''
        if ($id.StartsWith('GOAL-')) { foreach ($k in @('name', 'statement', 'successCriteria')) { $a.Remove($k); $b.Remove($k) } }
        if ($id.StartsWith('DEC-')) { foreach ($k in @('context', 'options', 'decision', 'rationale', 'title')) { $a.Remove($k); $b.Remove($k) } }
        if ((ConvertTo-PsSdCanonical $a) -cne (ConvertTo-PsSdCanonical $b)) { $diffs += ($d + ' ' + $id) } else { $same++ }
    }
}
Assert-Sd ($diffs.Count -eq 0 -and $same -eq 155) ('組裝：155 個項目與範例相同（ID、參照、計算的 17／18、問題狀態；實得 ' + $same + '）') (($diffs | Select-Object -First 5) -join '；')
Assert-Sd (@($wk.L2).Count -eq 0) 'L2：貫穿範例沒有違規' ((@($wk.L2) | ForEach-Object { $_.Code + ' ' + $_.Message } | Select-Object -First 3) -join '；')
$l3msgs = @(); foreach ($x in $wk.L3) { $l3msgs += ($x.Code + ' ' + $x.Message) }
Assert-Sd ($l3msgs.Count -eq 2 -and ($l3msgs -join '|') -ceq 'C07 TRN-005（015>090）沒有測試案例|C07 TRN-009（025>015）沒有測試案例') 'L3：恰好抓到範例故意留下的兩條 C07 缺口' ($l3msgs -join '；')
# 外殼與狀態：與範例的檢核報告相同
$rep = Read-PsSdJsonNode (Join-Path $design 'examples/walkthrough/gate-report.json')
$viol = @{}; foreach ($x in @($wk.L2) + @($wk.L3)) { $viol[$x.Doc + '/' + $x.Layer] = $true }
$envBad = @(); $envs = @{}
foreach ($d in $script:PsSdDocOrder) {
    $g = New-PsSdGate $d
    $e0 = New-PsSdEnvelope $m $d $g $wk.Meta $null
    $e1 = Test-PsSdSchema $reg ('urn:ps-spec:schema:' + $d) $e0
    if (@($e1).Count -gt 0) { $g['L1'] = 'FAIL' } else { $g['L1'] = 'PASS' }
    $g['L2'] = 'PASS'; if ($viol.ContainsKey($d + '/L2')) { $g['L2'] = 'FAIL' }
    if ($g['L3'] -ne 'NOT_APPLICABLE') { $g['L3'] = 'PASS'; if ($viol.ContainsKey($d + '/L3')) { $g['L3'] = 'FAIL' } }
    if ($g['L4'] -ne 'NOT_APPLICABLE') { $g['L4'] = 'PASS' }
    if ($g['L5'] -ne 'NOT_APPLICABLE') { $ok = $true; foreach ($k in @('L1', 'L2', 'L3', 'L4')) { if (@('PASS', 'NOT_APPLICABLE') -notcontains $g[$k]) { $ok = $false } }; if ($ok) { $g['L5'] = 'PASS' } else { $g['L5'] = 'NOT_RUN' } }
    $env = New-PsSdEnvelope $m $d $g $wk.Meta $null
    $envs[$d] = $env
    $want = $rep['docs'][$d]; $exDoc = $wk.Fixture.Docs[$d]
    if ($env['status'] -cne $want['status'] -or $env['summary'] -cne $want['summary'] -or -not (Test-PsSdSameNode $env['gate'] $want['gate']) -or -not (Test-PsSdSameNode $env['dependsOn'] $want['dependsOn']) -or -not (Test-PsSdSameNode $env['openQuestions'] $exDoc['openQuestions'])) { $envBad += $d }
    $ek = @(); foreach ($x in @($env.Keys)) { $ek += $x }; $xk = @(); foreach ($x in @($exDoc.Keys)) { $xk += $x }
    if (($ek -join ',') -cne ($xk -join ',')) { $envBad += ($d + ' 外殼欄位順序') }
}
Assert-Sd ($envBad.Count -eq 0) '外殼：15 份文件的狀態、檢核層、摘要、相依、未解問題與欄位順序都與範例相同' ($envBad -join '；')
Assert-Sd ((Test-PsSdSameNode $envs['04-workflow']['statusReading'] $wk.Fixture.Docs['04-workflow']['statusReading']) -and (Test-PsSdSameNode $envs['04-workflow']['statusTexts'] $wk.Fixture.Docs['04-workflow']['statusTexts'])) '外殼：04 的 statusReading 與 statusTexts 與範例相同'
Assert-Sd ((Test-PsSdSameNode $envs['90-questions']['suppressed'] $wk.Fixture.Docs['90-questions']['suppressed']) -and (Test-PsSdSameNode $envs['09-business-logic']['programDispositions'] $wk.Fixture.Docs['09-business-logic']['programDispositions'])) '外殼：90 的只計數代碼、09 的程式處置與範例相同'
$evDoc = Get-PsSdEvidenceDoc $m 'clone-0123456789abcdef' 'r0001'
$ee = Test-PsSdSchema $reg 'urn:ps-spec:schema:evidence' $evDoc
Assert-Sd (@($ee).Count -eq 0) '證據登錄：evidence.json 通過 schema'
# docHash：不含 status／gate／approval／revision
$h1 = Get-PsSdDocHash $envs['02-functional-requirements']
$c2 = Copy-PsSdNode $envs['02-functional-requirements']; $c2['status'] = 'approved'; $c2['revision'] = 'r0009'; $c2['gate']['L5'] = 'FAIL'
$c3 = Copy-PsSdNode $envs['02-functional-requirements']; $c3['items'][0]['outcome'] = '改過的內容。'
Assert-Sd ($h1 -ceq (Get-PsSdDocHash $c2) -and $h1 -cne (Get-PsSdDocHash $c3) -and $h1 -match '^[0-9a-f]{64}$') 'docHash：狀態、檢核、版本改了不變；內容改了就變'
# registry：再組裝一次 ID 不變；新鍵依字元碼排在後面
$before = ConvertTo-PsSdCanonical $wk.Registry
[void](Update-PsSdRegistry $reg $wk.Registry $wk.Skeleton $wk.Fixture.Receipts @())
Assert-Sd ($before -ceq (ConvertTo-PsSdCanonical $wk.Registry)) 'registry：同一批收據再派號，ID 不變'
$newIds = Register-PsSdKeys $wk.Registry 'FLD' @('TW_DEMO_REQHDR.ZZZ_NEW', 'TW_DEMO_REQHDR.AAA_NEW')
Assert-Sd ($newIds['TW_DEMO_REQHDR.AAA_NEW'] -eq 'FLD-020' -and $newIds['TW_DEMO_REQHDR.ZZZ_NEW'] -eq 'FLD-021') 'registry：新鍵接在既有 ID 後面、同批依字元碼排序'

# ---------------- 研究包驗收擋得住的寫法 ----------------
function Test-SdPacketErrors($Packet) {
    $ctx = New-PsSdResolveContext $reg $wk.Registry $wk.Skeleton 'status-REQ_STATUS.md' $wk.Built 'Check'
    $rr = Resolve-PsSdPacket $ctx $Packet
    $se = Test-PsSdSchema $reg 'urn:ps-sdoc:schema:research-packet' $Packet
    $all = @(); foreach ($e in $rr.Errors) { $all += $e }; foreach ($e in @($se)) { $all += $e }
    return , $all
}
function Get-SdReceipt([string]$Prefix) { foreach ($r in $wk.Fixture.Receipts) { if ($r.Ref.StartsWith($Prefix)) { return (Copy-PsSdNode $r.Packet) } }; return $null }
$p = Get-SdReceipt 'workflow/'; $p['items'][0]['code'] = '777'
$e = Test-SdPacketErrors $p
Assert-Sd (Test-SdAny $e { param($x) $x -like '*不得寫 code*' }) '研究包擋：工作流程項目改寫骨架欄位（狀態碼）'
$p = Get-SdReceipt 'workflow/'; $x0 = Copy-PsSdNode $p['items'][6]; $x0['key'] = 'REQ_STATUS:030>010'; $p['items'] = @($p['items']) + @(, $x0)
$e = Test-SdPacketErrors $p
Assert-Sd (Test-SdAny $e { param($x) $x -like '*不是狀態圖解讀採用的*' }) '研究包擋：新增狀態圖沒有的轉移'
$p = Get-SdReceipt 'rules/'; $p['items'][4]['appliesTo'] = @('@FR/TW_DEMO_REQ:NO_SUCH')
$e = Test-SdPacketErrors $p
Assert-Sd (Test-SdAny $e { param($x) $x -like '*參照不存在的 @FR/TW_DEMO_REQ:NO_SUCH*' }) '研究包擋：以自然鍵參照不存在的項目'
$p = Get-SdReceipt 'rules/'; $p['items'][4]['evidence'] = @('E99')
$e = Test-SdPacketErrors $p
Assert-Sd (Test-SdAny $e { param($x) $x -like '*E99 不在本包*' }) '研究包擋：引用不存在的證據'
$p = Get-SdReceipt 'rules/'; $p['evidence'][0]['kind'] = 'SQL'; $p['evidence'][0]['locator'] = 'UPDATE PS_TW_DEMO_REQHDR SET REQ_STATUS = ''030'''
$e = Test-SdPacketErrors $p
Assert-Sd (Test-SdAny $e { param($x) $x -like '*只准單一 SELECT*' -or $x -like '*格式不符*' }) '研究包擋：SQL 證據不是 SELECT'
$p = Get-SdReceipt 'functions/'; $p['items'][0]['id'] = 'FR-001'
$e = Test-SdPacketErrors $p
Assert-Sd (Test-SdAny $e { param($x) $x -like '*不得寫 id*' }) '研究包擋：研究包自己寫 ID'
$p = Get-SdReceipt 'functions/'; $p['items'][0]['description'] = '待確認'
$e = Test-SdPacketErrors $p
Assert-Sd (Test-SdAny $e { param($x) $x -like '*命中禁用的寫法*' }) '研究包擋：敘述欄填充字（合成後以 canonical schema 驗）'
$p = Get-SdReceipt 'functions/'; $p['items'] = @($p['items']) + @(, (Copy-PsSdNode $p['items'][0]))
$e = Test-SdPacketErrors $p
Assert-Sd (Test-SdAny $e { param($x) $x -like '*同一包重複*' }) '研究包擋：同一包重複的自然鍵'
$p = Get-SdReceipt 'functions/'; $p['coverage'] = 'PARTIAL'; $p['nextCursor'] = ''
$e = Test-SdPacketErrors $p
Assert-Sd ($e.Count -gt 0) '研究包擋：PARTIAL 沒有 nextCursor'
$p = Get-SdReceipt 'data/'; $p['items'][0]['type'] = 'BR'
$e = Test-SdPacketErrors $p
Assert-Sd (Test-SdAny $e { param($x) $x -like '*單元不能寫 BR*' }) '研究包擋：研究單元寫了別的單元的項目'
$p = Get-SdReceipt 'functions/'; $p['items'][0]['outcome'] = @{ unresolved = '完成後的狀態變化尚未查到程式' }
$ctx = New-PsSdResolveContext $reg $wk.Registry $wk.Skeleton 'status-REQ_STATUS.md' $wk.Built 'Check'
$rr = Resolve-PsSdPacket $ctx $p
Assert-Sd ($rr.Gaps.Length -eq 1 -and $rr.Gaps[0].Key -like 'EVIDENCE_GAP:*#outcome' -and $rr.Errors.Count -gt 0) '研究包：unresolved 欄位轉成 EVIDENCE_GAP 問題（outcome 不允許 UNRESOLVED 時另擋）'

# ---------------- 20 種刻意破壞（negative-report）在組裝後的模型上 ----------------
function Get-SdById([string]$Id) { return $m.ById[$Id] }
function Invoke-SdItemSchema([string]$Id) { $p0 = Get-PsSdIdPrefix $Id; $e = Test-PsSdSchema $reg (Get-PsSdItemSchemaRoot $p0) $m.ById[$Id]; return , $e }
function Invoke-SdChecks { $a = @(); foreach ($x in (Invoke-PsSdL2Checks $m $wk.Registry)) { $a += ($x.Code + ' ' + $x.Message) }; foreach ($x in (Invoke-PsSdL3Checks $m $wk.Built 'status-REQ_STATUS.md' $wk.Summary)) { $a += ($x.Code + ' ' + $x.Message) }; foreach ($x in (Get-PsSdSpeculationWarnings $m)) { $a += ($x.Code + ' ' + $x.Message) }; return , $a }
function Invoke-SdMutation([string]$Id, [string]$Field, $Value, [scriptblock]$Check) {
    $it = $m.ById[$Id]; $had = $it.Contains($Field); $old = $null; if ($had) { $old = $it[$Field] }
    if ($null -eq $Value) { $it.Remove($Field) } else { $it[$Field] = $Value }
    try { return (& $Check) } finally { if ($had) { $it[$Field] = $old } else { $it.Remove($Field) } }
}
$r = Invoke-SdMutation 'TRN-008' 'guard' $null { $e = Invoke-SdItemSchema 'TRN-008'; Test-SdAny $e { param($x) $x -like '*缺必填欄位 guard*' } }
Assert-Sd $r '破壞擋：TRN-008 刪掉 guard（L1）'
$r = Invoke-SdMutation 'BR-006' 'condition' '需要長官審核' { $e = Invoke-SdItemSchema 'BR-006'; @($e).Count -gt 0 }
Assert-Sd $r '破壞擋：BR-006 的條件寫成「需要長官審核」（L1）'
$r = Invoke-SdMutation 'FR-004' 'description' '待確認' { $e = Invoke-SdItemSchema 'FR-004'; Test-SdAny $e { param($x) $x -like '*命中禁用的寫法*' } }
Assert-Sd $r '破壞擋：FR-004 的說明寫「待確認」（L1）'
$r = Invoke-SdMutation 'DRV-002' 'certainty' 'INFERRED' { $e = Invoke-SdItemSchema 'DRV-002'; Test-SdAny $e { param($x) $x -like '*缺必填欄位 inference*' } }
Assert-Sd $r '破壞擋：DRV-002 改成 INFERRED 卻沒寫推論鏈（L1）'
$tx = Copy-PsSdNode $m.ById['OP-001']['transaction']; $tx['concurrency']['legacyBehavior'] = '應該是後存檔者覆蓋。'
$r = Invoke-SdMutation 'OP-001' 'transaction' $tx { Test-SdAny (Invoke-SdChecks) { param($x) $x -like 'S07 OP-001*應該是*' } }
Assert-Sd $r '破壞抓：OP-001 的併發行為寫「應該是…」（S07 警告）'
$r = Invoke-SdMutation 'OP-004' 'validations' @('BR-099') { Test-SdAny (Invoke-SdChecks) { param($x) $x -ceq 'R01 OP-004 參照不存在的 BR-099' } }
Assert-Sd $r '破壞擋：OP-004 的檢核清單指向不存在的 BR-099（R01）'
$r = Invoke-SdMutation 'FLD-010' 'derivedFrom' @('TC-001') { Test-SdAny (Invoke-SdChecks) { param($x) $x -ceq 'R03 FLD-010 往下游參照 TC-001' } }
Assert-Sd $r '破壞擋：FLD-010 宣稱推導自 TC-001（R03）'
$r = Invoke-SdMutation 'BR-003' 'boundaries' '0 拒絕；OLD_REF_NO 不檢查。' { Test-SdAny (Invoke-SdChecks) { param($x) $x -like 'R04 BR-003 正文寫到不建置欄位*OLD_REF_NO' } }
Assert-Sd $r '破壞擋：BR-003 的邊界提到不建置欄位 OLD_REF_NO（R04）'
$cond = New-PsSdObject; $cond['all'] = @((Copy-PsSdNode $m.ById['BR-003']['condition']), (ConvertTo-PsSdNode @{ left = @{ fld = 'FLD-018' }; op = 'NE'; right = @{ const = 'INT'; type = 'CHAR' } }))
$r = Invoke-SdMutation 'BR-003' 'condition' $cond { Test-SdAny (Invoke-SdChecks) { param($x) $x -like 'R14 BR-003 的條件比對*INT*Q-001*' } }
Assert-Sd $r '破壞擋：原生未使用分支寫回 BR-003 的條件（R14）'
$extra = Copy-PsSdNode $m.ById['TRN-008']; $extra['id'] = 'TRN-099'; $extra['key'] = 'REQ_STATUS:030>010'; $extra['from'] = 'STATE-005'; $extra['to'] = 'STATE-001'; $extra.Remove('via')
$m.Items['TRN'].Add($extra); $m.ById['TRN-099'] = $extra
try { $r = Test-SdAny (Invoke-SdChecks) { param($x) $x -like 'C01 REQ_STATUS 的 TRN 與解讀的轉移不符：多 030>010*' } } finally { [void]$m.Items['TRN'].Remove($extra); $m.ById.Remove('TRN-099') }
Assert-Sd $r '破壞擋：圖外轉移 030→010 寫進 04（C01）'
Assert-Sd ((ConvertTo-PsSdCanonical (Invoke-SdChecks)) -ceq (ConvertTo-PsSdCanonical @('C07 TRN-005（015>090）沒有測試案例', 'C07 TRN-009（025>015）沒有測試案例'))) '破壞後還原：結果回到兩條 C07'

# ---------------- 守門範例（只有 01、02、03、04、07、14） ----------------
$gt = Invoke-SdAssemble 'gate' 'status-CASE_STATUS.md' 'clone-fedcba9876543210' @() @() $true
$gm = $gt.Model
$rel = @(); foreach ($x in @($gt.L2) + @($gt.L3)) { if (@('R01', 'R13', 'C01') -ccontains $x.Code -or ($x.Code -eq 'C02' -and $x.Message -like '*守門活動*') -or ($x.Code -eq 'C07' -and $x.Message -like '*守門*')) { $rel += ($x.Code + ' ' + $x.Message) } }
Assert-Sd ($rel.Count -eq 0) '守門範例：R01、R13、C01、守門的 C02／C07 都通過' ($rel -join '；')
$gdiff = @()
$gEvNew = New-PsSdMap; foreach ($e in $gm.Evidence) { $gEvNew[[string]$e['id']] = Get-PsSdEvidenceSignature $e }
$gEvOld = New-PsSdMap; foreach ($e in $gt.Fixture.Docs['evidence']['items']) { $gEvOld[[string]$e['id']] = Get-PsSdEvidenceSignature $e }
foreach ($d in @('01-overview', '02-functional-requirements', '03-roles-permissions', '04-workflow', '07-database', '14-testing')) {
    $old = @{}; foreach ($it in $gt.Fixture.Docs[$d]['items']) { $old[[string]$it['id']] = $it }
    foreach ($it in (Get-PsSdDocItems $gm $d)) {
        $id = [string]$it['id']
        if (-not $old.ContainsKey($id)) { $gdiff += ($d + ' 多 ' + $id); continue }
        if ((ConvertTo-PsSdCanonical (ConvertTo-SdComparable $it $gEvNew '')) -cne (ConvertTo-PsSdCanonical (ConvertTo-SdComparable $old[$id] $gEvOld ''))) { $gdiff += ($d + ' ' + $id) }
    }
}
Assert-Sd ($gdiff.Count -eq 0) '守門範例：組裝結果與範例相同（含第 2 輪補回的子業務與轉移）' (($gdiff | Select-Object -First 5) -join '；')
Assert-Sd (Test-PsSdSameNode $gt.Summary $gt.Fixture.Docs['04-workflow']['statusReading']) '守門範例：statusReading 與範例相同'
function Invoke-SdGateMutation([string]$Id, [string]$Field, $Value, [scriptblock]$Pred) {
    $it = $gm.ById[$Id]; $had = $it.Contains($Field); $old = $null; if ($had) { $old = $it[$Field] }
    if ($null -eq $Value) { $it.Remove($Field) } else { $it[$Field] = $Value }
    try {
        $all = @(); foreach ($x in (Invoke-PsSdL2Checks $gm $gt.Registry)) { $all += ($x.Code + ' ' + $x.Message) }; foreach ($x in (Invoke-PsSdL3Checks $gm $gt.Built 'status-CASE_STATUS.md' $gt.Summary)) { $all += ($x.Code + ' ' + $x.Message) }
        return (Test-SdAny $all $Pred)
    } finally { if ($had) { $it[$Field] = $old } else { $it.Remove($Field) } }
}
$g10 = Copy-PsSdNode $gm.ById['TRN-010']['guard']; $g10['all'] = @($g10['all'][0], $g10['all'][2])
Assert-Sd (Invoke-SdGateMutation 'TRN-010' 'guard' $g10 { param($x) $x -ceq 'R13 TRN-010 的守衛沒有要求子業務 CASEPAY_STATUS 的資料全部到終點 090' }) '破壞擋：TRN-010 的守衛漏掉付款子業務（R13）'
$g10 = Copy-PsSdNode $gm.ById['TRN-010']['guard']; $g10['all'] = @($g10['all'][0], $g10['all'][1])
Assert-Sd (Invoke-SdGateMutation 'TRN-010' 'guard' $g10 { param($x) $x -ceq 'R13 TRN-010 的守衛沒有要求守門活動 ACT-005 完成' }) '破壞擋：TRN-010 的守衛漏掉「上傳結案報告」（R13）'
$origGuard = $gm.ById['TRN-010']['guard']
$g10 = Copy-PsSdNode $origGuard; $g10['all'][0].Remove('whenEmpty')
$gm.ById['TRN-010']['guard'] = $g10
try { $e = Test-PsSdSchema $reg (Get-PsSdItemSchemaRoot 'TRN') $gm.ById['TRN-010']; $r = @($e).Count -gt 0 } finally { $gm.ById['TRN-010']['guard'] = $origGuard }
Assert-Sd $r '破壞擋：逐列條件 ALL 沒寫 whenEmpty（L1）'
Assert-Sd (Invoke-SdGateMutation 'TRN-011' 'exitMode' 'NORMAL' { param($x) $x -ceq 'C01 TRN-011 從有子業務的 STATE-008 離開，exitMode 不得為 NORMAL' }) '破壞擋：處理中撤案（TRN-011）的 exitMode 寫成 NORMAL（C01）'
$g10 = Copy-PsSdNode $gm.ById['TRN-010']['guard']; $g10['all'][2]['left']['act'] = 'ACT-002'
Assert-Sd (Invoke-SdGateMutation 'TRN-010' 'guard' $g10 { param($x) $x -ceq 'R13 TRN-010 以 DONE 引用的 ACT-002 不是 SYSTEM_GATE 活動' }) '破壞擋：DONE 指向以轉移完成的活動 ACT-002（R13）'
Assert-Sd (Invoke-SdGateMutation 'TRN-010' 'diagramLabels' $null { param($x) $x -ceq 'C01 TRN-010 的線上文字與解讀不符（解讀：文件審查與付款都完成，且已上傳結案報告）' }) '破壞擋：TRN-010 漏帶線上文字（C01）'
$keep = $gm.StatusTexts
$gm.StatusTexts = @($keep | Where-Object { [string]$_['locator'] -cne 'status-CASE_STATUS.md#L72' })
try { $all = @(); foreach ($x in (Invoke-PsSdL3Checks $gm $gt.Built 'status-CASE_STATUS.md' $gt.Summary)) { $all += ($x.Code + ' ' + $x.Message) }; $r = Test-SdAny $all { param($x) $x -ceq 'C01 STATUS 文字 status-CASE_STATUS.md#L72「文件審查 010 待審查：審查人員逐份審查文件。」沒有處置' } } finally { $gm.StatusTexts = $keep }
Assert-Sd $r '破壞擋：說明區域「審查人員逐份審查文件」那一行沒有處置（C01）'
Assert-Sd (Invoke-SdGateMutation 'FR-002' 'performs' $null { param($x) $x -ceq 'C02 ACT-005 是守門活動，但沒有功能讓操作者完成它' }) '破壞擋：守門活動沒有功能可完成（C02）'

# ---------------- 渲染 ----------------
$md = ConvertTo-PsSdMarkdownSet $m $envs @{ JobId = 'clone-0123456789abcdef'; Revision = 'r0001'; StatusRef = 'status-REQ_STATUS.md'; Problems = @(); Warnings = @(); Phase = 'DRAFT' }
Assert-Sd ($md.Count -eq 16 -and $md.Contains('00-index.md') -and $md.Contains('90-questions.md')) '渲染：00-index＋14 份＋90'
$wf = $md['04-workflow.md']
Assert-Sd ($wf.Contains('```mermaid') -and $wf.Contains('stateDiagram-v2') -and $wf.Contains('TRN-008')) '渲染：04 重新產生狀態圖並標 TRN ID'
Assert-Sd ($md['07-database.md'].Contains('DRV-002') -and $md['07-database.md'].Contains('<a id="DRV-002"></a>')) '渲染：每個項目有錨點'
$md2 = ConvertTo-PsSdMarkdownSet $m $envs @{ JobId = 'clone-0123456789abcdef'; Revision = 'r0001'; StatusRef = 'status-REQ_STATUS.md'; Problems = @(); Warnings = @(); Phase = 'DRAFT' }
$same2 = $true; foreach ($k in $md.Keys) { if ($md[$k] -cne $md2[$k]) { $same2 = $false } }
Assert-Sd $same2 '渲染：同樣的輸入產生逐位元相同的 Markdown'
$fence = $true; foreach ($k in $md.Keys) { if ((([regex]::Matches($md[$k], '```')).Count % 2) -ne 0) { $fence = $false } }
Assert-Sd $fence '渲染：每份的程式碼區塊都有成對的 ```'

# ---------------- L5：出題、引用驗證、比對與多數決 ----------------
. (Join-Path $repo 'scripts/ps-sdoc-reader-lib.ps1')
$l5Docs = @('02-functional-requirements', '03-roles-permissions', '04-workflow', '05-ui', '06-architecture', '07-database', '08-api', '09-business-logic')
$qs = Get-PsSdL5Questions $m $l5Docs
$qmap = @{}; foreach ($q in $qs) { $qmap[[string]$q['id']] = $q }
$q1 = $qmap['TRN-008/T1']; $q4 = $qmap['TRN-008/T4']; $q2 = $qmap['TRN-008/T2']
$t1 = Sort-PsKnOrdinal -Items @($q1['ids']); $t4 = @($q4['ids'])
Assert-Sd ($qs.Length -gt 50 -and $null -ne $q1 -and (@($t1) -join ',') -ceq 'DRV-002,ROLE-001') '出題：TRN-008 的 T1 標準答案是操作者條件裡的 ROLE-001、DRV-002' (@($t1) -join ',')
Assert-Sd ($t4 -ccontains 'FLD-017' -and $t4 -ccontains 'FLD-011' -and $t4 -ccontains 'FLD-012' -and [string]$q2['kind'] -ceq 'USER_ACTION' -and @($q2['ids']) -ccontains 'OBJ-002') '出題：T4 是寫入的欄位、T2 是觸發種類與物件'
$noIds = @(); foreach ($q in $qs) { if (@('T4', 'D1', 'B2', 'F1', 'W1', 'O1', 'A1') -ccontains [string]$q['q'] -and @($q['ids']).Count -eq 0) { $noIds += [string]$q['id'] } }
Assert-Sd ($noIds.Count -eq 0) '出題：寫入、查找、條件、步驟類的題目標準答案都有 ID（不會是空集合）' (($noIds | Select-Object -First 5) -join '、')
$txt = @(); foreach ($q in $qs) { if ([string]$q['mode'] -ceq 'TEXT' -and ([string]$q['text']).Trim() -eq '') { $txt += [string]$q['id'] } }
Assert-Sd ($txt.Count -eq 0) '出題：文字題都有標準答案' ($txt -join '、')
$qs2 = Get-PsSdL5Questions $m @('04-workflow')
$other = @(); foreach ($q in $qs2) { if ([string]$q['doc'] -cne '04-workflow') { $other += [string]$q['id'] } }
Assert-Sd ($other.Count -eq 0 -and $qs2.Length -gt 0) '出題：只出可出題文件的題目'
$groups = Get-PsSdL5Groups $m $qs 20
$cnt = 0; $big = 0; foreach ($g in $groups) { $cnt += @($g).Count; if (@($g).Count -gt 20) { $big++ } }
Assert-Sd ($cnt -eq $qs.Length -and $big -eq 0) '分批：每題恰在一批、每批最多 20 題'
$sec = Get-PsSdMdSections $md
Assert-Sd ($sec.ContainsKey('04-workflow.md#TRN-008') -and $sec['04-workflow.md#TRN-008'].Contains('ROLE-001') -and -not $sec['04-workflow.md#TRN-008'].Contains('<a id="TRN-009">')) '段落：錨點到下一個錨點'
$mkAns = { param($St, $Idl, $Kd, $Cit) $o = New-PsSdObject; $o['id'] = 'TRN-008/T1'; $o['status'] = $St; $o['ids'] = @($Idl); $o['kind'] = $Kd; $o['text'] = '合成'; $o['citations'] = @($Cit); return , $o }
$a1 = Test-PsSdL5Answer (& $mkAns 'ANSWERED' @('ROLE-001', 'DRV-002', 'TRN-008') '' @('04-workflow.md#TRN-008')) $q1 $sec
$a2 = Test-PsSdL5Answer (& $mkAns 'ANSWERED' @('ROLE-001') '' @('04-workflow.md#TRN-999')) $q1 $sec
$a3 = Test-PsSdL5Answer (& $mkAns 'ANSWERED' @('FLD-001') '' @('04-workflow.md#TRN-008')) $q1 $sec
$a4 = Test-PsSdL5Answer (& $mkAns 'NOT_IN_SPEC' @() '' @()) $q1 $sec
Assert-Sd ($a1.Class -ceq 'ANS' -and (@($a1.Ids) -join ',') -ceq 'ROLE-001,DRV-002' -and $a2.Class -ceq 'INV' -and $a3.Class -ceq 'INV' -and $a4.Class -ceq 'NIS') '引用驗證：有效、段落不存在、引用段落裡沒有該 ID、文件沒寫；自己的 ID 不算'
Assert-Sd ((Get-PsSdL5Vote $q1 $a1 '') -ceq 'MATCH' -and (Get-PsSdL5Vote $q1 @{ Class = 'ANS'; Ids = @('ROLE-001'); Kind = ''; Text = '' } '') -ceq 'MISMATCH' -and (Get-PsSdL5Vote $q2 @{ Class = 'ANS'; Ids = @('OBJ-002'); Kind = 'BATCH'; Text = '' } '') -ceq 'MISMATCH') '比對：ID 集合；KIND 題代碼也要相同'
$va = @{ Class = 'ANS'; Ids = @('ROLE-001'); Kind = ''; Text = '' }
$vn = @{ Class = 'NIS'; Ids = @(); Kind = ''; Text = '' }
$vi = @{ Class = 'INV'; Ids = @('DRV-009'); Kind = ''; Text = '' }
$V = { param($A, $B, $C) return (Get-PsSdL5Verdict $q1 @(@{ Vote = $A[0]; Ans = $A[1] }, @{ Vote = $B[0]; Ans = $B[1] }, @{ Vote = $C[0]; Ans = $C[1] })) }
$ok = ((& $V @('MATCH', $a1) @('MATCH', $a1) @('MISMATCH', $va)) -ceq 'CONSISTENT') -and ((& $V @('NIS', $vn) @('NIS', $vn) @('MATCH', $a1)) -ceq 'UNDERSPECIFIED') -and
    ((& $V @('MISMATCH', $va) @('MISMATCH', $va) @('MATCH', $a1)) -ceq 'CONTRADICTS_SOURCE') -and ((& $V @('INV', $vi) @('INV', $vi) @('MATCH', $a1)) -ceq 'UNDERSPECIFIED') -and
    ((& $V @('MATCH', $a1) @('NIS', $vn) @('MISMATCH', $va)) -ceq 'DIVERGENT')
Assert-Sd $ok '多數決：CONSISTENT／UNDERSPECIFIED（2 票沒寫或 2 位腦補相同）／CONTRADICTS_SOURCE（2 票相同的錯答）／DIVERGENT'

# ---------------- 研究包範例（部署給 worker 看格式；貫穿範例裁成每型別最多 4 項） ----------------
function Get-SdEvRefs($Node, $Set) {
    if ($Node -is [string]) { if ([regex]::IsMatch($Node, '^E[1-9][0-9]*$')) { [void]$Set.Add($Node) }; return }
    if ($Node -is [System.Collections.IDictionary]) { foreach ($k in @($Node.get_Keys())) { Get-SdEvRefs $Node[$k] $Set }; return }
    if ($Node -is [System.Collections.IList]) { foreach ($x in $Node) { Get-SdEvRefs $x $Set } }
}
$exDir = Join-Path $sdocDir 'examples'
$exBad = @(); $exMade = 0
foreach ($u in $script:PsSdUnits) {
    $src = $null; foreach ($r in $wk.Fixture.Receipts) { if ($null -eq $src -and [string]$r.Packet['unit'] -ceq $u.Id) { $src = $r.Packet } }
    if ($null -eq $src) { $exBad += ($u.Id + '：貫穿範例沒有這個單元'); continue }
    $o = Copy-PsSdNode $src
    if ($u.Per -eq 'job') { $o['subject'] = 'JOB' }
    $o['summary'] = '合成範例：只示範研究包的格式；項目已裁成每種最多 4 個，參照的項目不一定在本範例裡。'
    $count = @{}; $kept = @()
    foreach ($it in @($o['items'])) { $t = [string]$it['type']; if (-not $count.ContainsKey($t)) { $count[$t] = 0 }; if ($count[$t] -lt 4) { $kept += , $it; $count[$t]++ } }
    $o['items'] = $kept
    $used = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($k in @($o.get_Keys())) { if ([string]$k -cne 'evidence') { Get-SdEvRefs $o[$k] $used } }
    $evs = @(); foreach ($e in @($o['evidence'])) { if ($used.Contains([string]$e['id'])) { $evs += , $e } }
    $o['evidence'] = $evs
    $text = (ConvertTo-PsSdJsonText $o).Replace('"status-REQ_STATUS.md#L', '"status.md#L')
    $node = ConvertTo-PsSdNode (ConvertFrom-PsSdJson $text)
    $se = Test-PsSdSchema $reg 'urn:ps-sdoc:schema:research-packet' $node
    $ctx = New-PsSdResolveContext $reg $wk.Registry $wk.Skeleton 'status.md' $wk.Built 'Check'
    $rr = Resolve-PsSdPacket $ctx $node
    if (@($se).Count -gt 0) { $exBad += ($u.Id + ' schema：' + @($se)[0]) }
    if ($rr.Errors.Count -gt 0) { $exBad += ($u.Id + ' 驗收：' + $rr.Errors[0]) }
    $path = Join-Path $exDir ($u.Id + '.json')
    if ($WriteExamples) { if (-not (Write-PsKnAtomicText -LiteralPath $path -Text $text -Bom $false)) { throw 'TEST_WRITE_FAILED' }; $exMade++ }
    elseif (-not [System.IO.File]::Exists($path) -or [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) -cne $text) { $exBad += ($u.Id + '：部署的範例與重生結果不同（加 -WriteExamples 重生）') }
}
if ($WriteExamples) { Write-Host ('已重生研究包範例 ' + $exMade + ' 份：' + $exDir) }
Assert-Sd ($exBad.Count -eq 0) '研究包範例：每個研究單元一份，通過研究包 schema 與驗收，且與重生結果相同' ($exBad -join '；')

foreach ($rel in @('scripts/ps-sdoc-lib.ps1', 'scripts/ps-sdoc-check-lib.ps1', 'scripts/ps-sdoc-render-lib.ps1', 'scripts/tests/test-sdoc-assemble.ps1', 'scripts/tests/sdoc-test-fixtures.ps1')) {
    $b = [System.IO.File]::ReadAllBytes((Join-Path $repo $rel))
    Assert-Sd ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) ('UTF-8 BOM：' + $rel)
}
Write-Host ('sdoc assemble tests: PASS=' + $script:passed + ' FAIL=' + $script:failed)
if ($script:failed -gt 0) { exit 1 }
exit 0
