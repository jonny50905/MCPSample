# test-sdoc.ps1 — Spec 文件流程（Claude Code 版）的單元測試；合成資料，不查 MCP、不讀企業產物、不呼叫模型。
# 用法：pwsh -NoProfile -File scripts/tests/test-sdoc.ps1   （公司機：powershell -NoProfile -ExecutionPolicy Bypass -File …）
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repo 'scripts/ps-sdoc-schema-lib.ps1')
. (Join-Path $repo 'scripts/ps-sdoc-status-lib.ps1')
$script:failed = 0; $script:passed = 0
function Assert-Sd([bool]$Condition, [string]$Name, [string]$Detail = '') {
    if ($Condition) { $script:passed++; Write-Host ('PASS ' + $Name) }
    else { $script:failed++; Write-Host ('FAIL ' + $Name); if ($Detail) { Write-Host ('     ' + $Detail) } }
}
function Test-SdHasError($Errors, [string]$Needle) {
    foreach ($e in @($Errors)) { if (([string]$e).Contains($Needle)) { return $true } }
    return $false
}
$design = Join-Path $repo 'docs/design/spec-schema-framework'
$runtimeSchemas = Join-Path $repo 'claude-code/.claude/peoplesoft/sdoc/schemas'

# ---------------- schema 驗證器 ----------------
$reg = Read-PsSdSchemaDir $runtimeSchemas
Assert-Sd ($reg.Schemas.Count -ge 18) 'schema：載入設計的 18 份'
$same = $true
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $design 'schemas') -Filter '*.json' -File)) {
    $rt = Join-Path $runtimeSchemas $f.Name
    if (-not (Test-Path -LiteralPath $rt)) { $same = $false; continue }
    if ([System.IO.File]::ReadAllText($f.FullName) -cne [System.IO.File]::ReadAllText($rt)) { $same = $false }
}
Assert-Sd $same 'schema：部署副本與設計文件的 schemas 相同'

$targets = New-Object System.Collections.ArrayList
foreach ($d in @('examples/walkthrough/canonical', 'examples/gate/canonical', 'examples/minimal')) {
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $design $d) -Filter '*.json' -File | Sort-Object Name)) {
        [void]$targets.Add(@($f.FullName, ('urn:ps-spec:schema:' + [System.IO.Path]::GetFileNameWithoutExtension($f.Name)), ($d + '/' + $f.Name)))
    }
}
foreach ($d in @('examples/walkthrough/readings', 'examples/gate/readings')) {
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $design $d) -Filter '*.json' -File | Sort-Object Name)) {
        [void]$targets.Add(@($f.FullName, 'urn:ps-spec:schema:status-reading', ($d + '/' + $f.Name)))
    }
}
$bad = @()
foreach ($t in $targets) {
    $errs = Test-PsSdSchema $reg $t[1] (Read-PsSdJsonFile $t[0])
    if (@($errs).Count -gt 0) { $bad += ($t[2] + '：' + @($errs)[0]) }
}
Assert-Sd ($targets.Count -eq 44 -and $bad.Count -eq 0) ('schema：' + $targets.Count + ' 份範例全部通過') ($bad -join '；')

# 壞範例：從守門範例的 04 改壞
$wf = ConvertTo-PsSdNode (Read-PsSdJsonFile (Join-Path $design 'examples/gate/canonical/04-workflow.json'))
function Get-SdItem($Doc, [string]$Prefix) { foreach ($it in $Doc['items']) { if (([string]$it['id']).StartsWith($Prefix + '-')) { return $it } }; return $null }
function Copy-SdNode($Node) { return (ConvertTo-PsSdNode (ConvertFrom-PsSdJson (ConvertTo-PsSdCanonical $Node))) }
function Test-SdWf($Doc) { $e = Test-PsSdSchema $reg 'urn:ps-spec:schema:04-workflow' $Doc; return , $e }

$d = Copy-SdNode $wf; (Get-SdItem $d 'TRN').Remove('guard')
$e = Test-SdWf $d
Assert-Sd (Test-SdHasError $e '缺必填欄位 guard') 'schema 擋：轉移缺 guard'
$d = Copy-SdNode $wf; (Get-SdItem $d 'TRN')['extra'] = 'x'
$e = Test-SdWf $d
Assert-Sd (Test-SdHasError $e '不允許的欄位 extra') 'schema 擋：未定義欄位'
$d = Copy-SdNode $wf; (Get-SdItem $d 'TRN')['Guard'] = (Get-SdItem $d 'TRN')['guard']
$e = Test-SdWf $d
Assert-Sd (Test-SdHasError $e '不允許的欄位 Guard') 'schema 擋：欄位名大小寫不同'
$d = Copy-SdNode $wf; (Get-SdItem $d 'TRN')['reentry'] = 'TODO'
$e = Test-SdWf $d
Assert-Sd (Test-SdHasError $e '命中禁用的寫法') 'schema 擋：敘述欄填充字'
$d = Copy-SdNode $wf; (Get-SdItem $d 'TRN')['key'] = 'CASEAPV_STATUS:*>010' + "`n"
$e = Test-SdWf $d
Assert-Sd (Test-SdHasError $e '格式不符') 'schema 擋：自然鍵結尾多一個換行'
$d = Copy-SdNode $wf; (Get-SdItem $d 'TRN')['writes'][0]['field'] = 'FLD-1'
$e = Test-SdWf $d
Assert-Sd (Test-SdHasError $e '格式不符') 'schema 擋：參照格式錯誤'
$d = Copy-SdNode $wf; (Get-SdItem $d 'STATE')['code'] = 10
$e = Test-SdWf $d
Assert-Sd (Test-SdHasError $e '型別應為 string') 'schema 擋：狀態碼寫成數字'
# 守門轉移的逐列條件缺 whenEmpty
$d = Copy-SdNode $wf
$rows = $null
foreach ($it in $d['items']) {
    if (-not ([string]$it['id']).StartsWith('TRN-')) { continue }
    $g = $it['guard']
    if ($g -is [System.Collections.IDictionary] -and $g.Contains('all')) { foreach ($c in $g['all']) { if ($c -is [System.Collections.IDictionary] -and $c.Contains('rows')) { $rows = $c; break } } }
    if ($null -ne $rows) { break }
}
Assert-Sd ($null -ne $rows) '範例有逐列條件'
if ($null -ne $rows) { $rows.Remove('whenEmpty') }
$e = Test-SdWf $d
Assert-Sd (@($e).Count -gt 0) 'schema 擋：逐列條件 ALL 沒寫 whenEmpty' (@($e) -join '；')
# 單元素陣列與空陣列保留（PowerShell 陣列展開的回歸）
$d = Copy-SdNode $wf; $d['components'] = @('TW_DEMO_CASE'); $d['openQuestions'] = @()
$e = Test-SdWf $d
Assert-Sd (@($e).Count -eq 0) 'schema：單元素與空陣列不被展開' (@($e) -join '；')
# 解讀：狀態碼不是三位數
$r1 = ConvertTo-PsSdNode (Read-PsSdJsonFile (Join-Path $design 'examples/gate/readings/R1.json'))
$r1['states'][0]['code'] = '10'
$e = Test-PsSdSchema $reg 'urn:ps-spec:schema:status-reading' $r1
Assert-Sd (Test-SdHasError $e '格式不符') 'schema 擋：解讀的狀態碼不是三位數'

# ---------------- 第 0 階段：三份狀態圖解讀 ----------------
function Read-SdText([string]$Rel) { return [System.IO.File]::ReadAllText((Join-Path $design $Rel), [System.Text.Encoding]::UTF8) }
function Read-SdReading([string]$Rel) { return (ConvertTo-PsSdNode (Read-PsSdJsonFile (Join-Path $design $Rel))) }
function Get-SdCodes($Problems) { $c = @(); foreach ($p in @($Problems)) { $c += $p.Code }; return , $c }
$gateText = Read-SdText 'examples/gate/input/status-CASE_STATUS.md'
$gateR = @((Read-SdReading 'examples/gate/readings/R1.json'), (Read-SdReading 'examples/gate/readings/R2.json'), (Read-SdReading 'examples/gate/readings/R3.json'))
$ok = $true
foreach ($r in $gateR) { $pr = Test-PsSdReading $gateText $r; if (@($pr).Count -gt 0) { $ok = $false } }
Assert-Sd $ok '第 0 階段：守門範例三份解讀都逐行交代'
Assert-Sd ((Get-PsSdStatusFingerprint $gateText) -eq $gateR[0]['source']['fingerprint']) '第 0 階段：STATUS 指紋與範例相同'
Assert-Sd ((Get-PsSdStatusFingerprint ($gateText.Replace("`n", "`r`n"))) -eq $gateR[0]['source']['fingerprint']) '第 0 階段：CRLF 檔指紋不變'
$mm = Get-PsSdMermaidLines $gateText
Assert-Sd ($mm.Count -eq 46) ('第 0 階段：Mermaid 非空行 46（實得 ' + $mm.Count + '）')
$crlf = Get-PsSdMermaidLines ($gateText.Replace("`n", "`r`n"))
Assert-Sd ($crlf.Count -eq 46 -and $crlf[45] -eq $mm[45]) '第 0 階段：CRLF 檔行號不變'
# 漏交代一行、引用圖外的行、同一行列兩次
$bad = Copy-SdNode $gateR[0]
foreach ($t in $bad['transitions']) { if ($t['entity'] -eq 'CASE_STATUS' -and $t['from'] -eq '040' -and $t['to'] -eq '090') { $t['lines'] = @(30) } }
$pr = Test-PsSdReading $gateText $bad
$codes = Get-SdCodes $pr
Assert-Sd ($codes -contains 'LINE_UNACCOUNTED' -and (@($pr | Where-Object { $_.Message -like '第 45 行*' }).Count -eq 1)) '第 0 階段擋：漏交代第 45 行'
$bad = Copy-SdNode $gateR[2]
$bad['states'][0]['lines'] = @($bad['states'][0]['lines']) + @(71)
$codes = Get-SdCodes (Test-PsSdReading $gateText $bad)
Assert-Sd ($codes -contains 'CITE_OUTSIDE') '第 0 階段擋：引用圖外的第 71 行'
$bad = Copy-SdNode $gateR[0]
$bad['otherLines'] = @($bad['otherLines']) + @(@{ lines = @(8); disposition = 'NO_SPEC_CONTENT'; note = '重複' })
$codes = Get-SdCodes (Test-PsSdReading $gateText $bad)
Assert-Sd ($codes -contains 'LINE_TWICE') '第 0 階段擋：同一行列兩次'
$bad = Copy-SdNode $gateR[0]
$bad['transitions'][0]['to'] = '777'
$codes = Get-SdCodes (Test-PsSdReading $gateText $bad)
Assert-Sd ($codes -contains 'BAD_REF') '第 0 階段擋：轉移指向不存在的狀態'
# 對齊與比對
$maps = Get-PsSdAlignment $gateR
Assert-Sd ($maps[1]['CASE_DOC_STATUS'] -eq 'CASEDOC_STATUS') '第 0 階段：代號不同的實體以引用的行對齊，取多數讀者的代號'
$res1 = Compare-PsSdReadings $gateText $gateR $null
Assert-Sd ($res1.FactCount -eq 47 -and $res1.Unanimous -eq 44 -and $res1.Contested.Length -eq 3) ('第 0 階段：47 事實、44 一致、3 項不一致（實得 ' + $res1.FactCount + '／' + $res1.Unanimous + '／' + $res1.Contested.Length + '）')
$q2 = Get-PsSdRound2Questions $gateText $res1
Assert-Sd ($q2.Length -eq 3 -and $q2[0].id -eq 'F01' -and $q2[0].lines[0].line -eq 14) '第 0 階段：第 2 輪工單逐項附引用的行'
$truth = Get-PsSdReadingFacts $gateR[0] $maps[0]
$answers = @{}
for ($i = 0; $i -lt 3; $i++) { foreach ($c in $res1.Contested) { $a = 'NO'; if ($truth.Facts.ContainsKey($c.Key)) { $a = 'YES' }; $answers[[string]$i + '|' + $c.Key] = $a } }
$res2 = Compare-PsSdReadings $gateText $gateR $answers
$sum = Get-PsSdStatusReadingSummary $res2 'status-CASE_STATUS.md' (Get-PsSdStatusFingerprint $gateText)
$gate04 = Read-PsSdJsonFile (Join-Path $design 'examples/gate/canonical/04-workflow.json')
$wantSum = ConvertTo-PsSdCanonical $gate04.statusReading
Assert-Sd ((ConvertTo-PsSdCanonical $sum) -ceq $wantSum) '第 0 階段：statusReading 與範例相同（第 2 輪 3:0 採用）' ((ConvertTo-PsSdCanonical $sum) + ' ≠ ' + $wantSum)
# 仍無多數：一位 YES、一位 NO、一位 UNSURE
$answers3 = @{}
foreach ($c in $res1.Contested) { $answers3['0|' + $c.Key] = 'YES'; $answers3['1|' + $c.Key] = 'NO'; $answers3['2|' + $c.Key] = 'UNSURE' }
$res3 = Compare-PsSdReadings $gateText $gateR $answers3
Assert-Sd ($res3.Unresolved.Length -eq 3 -and $res3.Contested[0].Round2 -eq '1:1:1') '第 0 階段：無多數時交人（UNRESOLVED）'
# 採用的事實 → 04 的分母
$built = Get-PsSdBuiltModel $gateText $res2
$caseE = $built.Entities['CASE_STATUS']
$codesCase = @($caseE.Codes) | Sort-Object
Assert-Sd ((($codesCase) -join ',') -eq '010,040,050,060,090' -and $caseE.Main) '第 0 階段：主業務狀態碼'
Assert-Sd ((@($built.Composites['CASE_STATUS|040'].Regions) -join ',') -eq 'CASEDOC_STATUS,CASEPAY_STATUS') '第 0 階段：040 裡的子業務依圖上順序'
Assert-Sd (-not $built.Entities['CASEPAY_STATUS'].Main -and $built.Entities['CASEPAY_STATUS'].Pairs.Contains('010>090')) '第 0 階段：第 2 輪補回的轉移'
Assert-Sd ((@($caseE.Labels['040>050']) -join '') -eq '文件審查與付款都完成，且已上傳結案報告') '第 0 階段：線上描述帶進轉移'
Assert-Sd ($caseE.Scenarios['撤案'].Contains('040>090')) '第 0 階段：線上寫描述的轉移由讀者歸入情境'
$tl = @(); foreach ($t in $built.Texts) { $tl += $t.Line }
$wantTexts = @(); foreach ($st in $gate04.statusTexts) { $wantTexts += [int]($st.locator -replace '^.*#L', '') }
Assert-Sd (($tl -join ',') -eq ($wantTexts -join ',')) ('第 0 階段：說明區域逐行列舉與範例相同（' + ($tl -join ',') + '）')
# 貫穿範例：三份完全一致
$wkText = Read-SdText 'examples/walkthrough/input/status-REQ_STATUS.md'
$wkR = @((Read-SdReading 'examples/walkthrough/readings/R1.json'), (Read-SdReading 'examples/walkthrough/readings/R2.json'), (Read-SdReading 'examples/walkthrough/readings/R3.json'))
$wres = Compare-PsSdReadings $wkText $wkR $null
$wk04 = Read-PsSdJsonFile (Join-Path $design 'examples/walkthrough/canonical/04-workflow.json')
$wsum = Get-PsSdStatusReadingSummary $wres 'status-REQ_STATUS.md' (Get-PsSdStatusFingerprint $wkText)
Assert-Sd ((ConvertTo-PsSdCanonical $wsum) -ceq (ConvertTo-PsSdCanonical $wk04.statusReading)) '第 0 階段：貫穿範例 statusReading 與範例相同'
$wb = Get-PsSdBuiltModel $wkText $wres
Assert-Sd (@($wb.Entities['REQ_STATUS'].Via.Keys).Count -ge 1) '第 0 階段：經過判斷節點的轉移帶 via'

# ---------------- 檔案紀律 ----------------
# PowerShell 變數不分大小寫：同一函式裡 $e 與 $E 是同一個變數（曾造成子業務被當成主業務）
$sdocFiles = @(Get-ChildItem -LiteralPath (Join-Path $repo 'scripts') -Filter 'ps-sdoc*.ps1' -File | Sort-Object Name)
$clash = @()
foreach ($f in $sdocFiles) {
    $tk = $null; $pe = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tk, [ref]$pe)
    foreach ($fd in $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        $seenV = @{}
        foreach ($v in $fd.Body.FindAll({ param($x) $x -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) {
            $nm = [string]$v.VariablePath.UserPath
            $lk = $nm.ToLowerInvariant()
            if ($seenV.ContainsKey($lk) -and $seenV[$lk] -cne $nm) { $clash += ($f.Name + ':' + $fd.Name + ' $' + $seenV[$lk] + '／$' + $nm) }
            else { $seenV[$lk] = $nm }
        }
    }
}
Assert-Sd ($clash.Count -eq 0) ('同一函式內沒有只差大小寫的變數（' + $sdocFiles.Count + ' 支）') (($clash | Select-Object -Unique) -join '；')
# PowerShell 把 U+2018／U+2019／U+201C／U+201D 等彎引號當成引號：寫進字串會把字串提早結束
$smart = @()
foreach ($f in @($sdocFiles) + @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*sdoc*.ps1' -File)) {
    $tx = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    foreach ($cp in @(0x2018, 0x2019, 0x201A, 0x201B, 0x201C, 0x201D, 0x201E)) { if ($tx.IndexOf([char]$cp) -ge 0) { $smart += $f.Name } }
}
Assert-Sd ($smart.Count -eq 0) '沒有彎引號（PowerShell 會當成引號）' (($smart | Select-Object -Unique) -join '、')
foreach ($rel in @('scripts/ps-sdoc-schema-lib.ps1', 'scripts/ps-sdoc-status-lib.ps1', 'scripts/tests/test-sdoc.ps1')) {
    $b = [System.IO.File]::ReadAllBytes((Join-Path $repo $rel))
    Assert-Sd ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) ('UTF-8 BOM：' + $rel)
}

Write-Host ('sdoc tests: PASS=' + $script:passed + ' FAIL=' + $script:failed)
if ($script:failed -gt 0) { exit 1 }
exit 0
