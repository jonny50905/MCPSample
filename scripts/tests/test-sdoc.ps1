# test-sdoc.ps1 — Spec 文件流程（Claude Code 版）的單元測試；合成資料，不查 MCP、不讀企業產物、不呼叫模型。
# 用法：pwsh -NoProfile -File scripts/tests/test-sdoc.ps1   （公司機：powershell -NoProfile -ExecutionPolicy Bypass -File …）
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repo 'scripts/ps-sdoc-schema-lib.ps1')
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
Assert-Sd ($reg.Schemas.Count -eq 18) 'schema：載入 18 份'
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
    if ($g -is [hashtable] -and $g.ContainsKey('all')) { foreach ($c in $g['all']) { if ($c -is [hashtable] -and $c.ContainsKey('rows')) { $rows = $c; break } } }
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

# ---------------- 檔案紀律 ----------------
foreach ($rel in @('scripts/ps-sdoc-schema-lib.ps1', 'scripts/tests/test-sdoc.ps1')) {
    $b = [System.IO.File]::ReadAllBytes((Join-Path $repo $rel))
    Assert-Sd ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) ('UTF-8 BOM：' + $rel)
}

Write-Host ('sdoc tests: PASS=' + $script:passed + ' FAIL=' + $script:failed)
if ($script:failed -gt 0) { exit 1 }
exit 0
