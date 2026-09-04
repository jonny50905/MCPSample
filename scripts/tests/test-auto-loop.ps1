# scripts/tests/test-auto-loop.ps1 — 外環函式的功能測試（AST 抽真實函式，跑 fixture 情境）
# 用法：pwsh -NoProfile -File scripts/tests/test-auto-loop.ps1   （PowerShell 7 或 5.1 皆可）
# 範圍：調帳／治理／台帳／破壞防衛／歸檔 commit／分批稽核（manifest、part 不變量、合併器）
#       ＋ lint fixture（[附錄] 守衛、ChunkId 誤判、[回灌] 陳舊、-EvidenceStats、-StrictAudit 未稽核）
#       ＋ research 範圍債（#23：checkpoint ≠ discovery complete、GateVersion 4 舊收據作廢）
#       ＋ lint 導覽主張守衛（#24：情境 28，在 docs/ps-research/zz-nav24-fixture 建臨時領域跑真 lint，結束自刪）
# 注意：情境 22 會在 docs/ps-research/zz-l103-fixture 建臨時領域跑真 lint，結束自刪。
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ErrorActionPreference = 'Stop'
$src = Get-Content (Join-Path $repoRoot "scripts/ps-auto-loop.ps1") -Raw
$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$tokens, [ref]$errs)
$wanted = @('Get-ResearchDebt', 'Test-ResearchScopeOk', 'Get-RowIdentity', 'Get-ChecklistInventory', 'Invoke-ChecklistReconcile', 'Test-RowStillRepresented', 'Get-CanonicalObject', 'Invoke-DItemGovernance', 'Get-OrderFingerprint', 'Get-SurgeryLedger', 'Save-SurgeryLedger', 'Select-SurgeryBatch', 'Get-ActionableSurgicalCount', 'Get-NnHeadKeys', 'Get-NnGuardSnapshot', 'Invoke-NnDestructionGuard', 'Invoke-ArchiveDedup', 'Invoke-ChecklistArchiveCommit', 'Get-SessionFailureKind', 'Get-AuditLedger', 'Save-AuditLedger', 'Get-ClaimSample', 'New-AuditManifest', 'Test-AuditPart', 'Read-DomainPart', 'Add-ChecklistRows', 'Set-ChecklistRoundAndFlag', 'Invoke-AuditMerge')
$funcs = $ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $a.Name }, $true)
if ($funcs.Count -ne 28) { throw "抽不到二十八個函式（抽到 $($funcs.Count)）" }
foreach ($f in $funcs) { Invoke-Expression $f.Extent.Text }
function Write-Log([string]$msg) { }

$global:dir = Join-Path ([System.IO.Path]::GetTempPath()) ("recon-test-" + [guid]::NewGuid().ToString('N'))
$global:logRoot = $dir
$global:Domain = 'zz-test'
$global:auditLedgerPath = Join-Path $dir 'audit-ledger.json'
$global:auditPartsDir = Join-Path $dir 'audit-parts'
$global:auditManifestPath = Join-Path $auditPartsDir 'manifest.txt'
$global:auditManifestCopy = Join-Path $dir 'audit-manifest.txt'
$global:uuidRx = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
$global:root = $dir
New-Item -ItemType Directory -Path $dir | Out-Null
$cl = Join-Path $dir "checklist.md"
$ar = Join-Path $dir "checklist-archive-r5.md"
$ledger = Join-Path $logRoot "reconcile-restored.txt"

function Reset-Fixture {
    $clText = @(
        '# 測試領域 調查進度',
        '',
        '稽核輪次：5',
        '查無全量抽驗：已執行（第 3 輪）',
        '',
        '## 調查進度',
        '',
        '- [ ] 16 功能甲 `TW_A` → 16-TW_A.md',
        '- [ ] A5-01 補查 03-TW_C.md：FAIL 2（稽核）',
        '- [ ] A5-02 補查 07-TW_D.md：FAIL 1（稽核）',
        '- [ ] D5-01 新發現 TW_NEWOBJ：任務C 反查 PS_X 讀寫（稽核）',
        '- [ ] 任務 C 批次 2/4 未完成',
        '',
        '## Gaps 彙整（隨深查更新）',
        '',
        '- 某 gap 描述'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText($cl, $clText, (New-Object System.Text.UTF8Encoding($true)))
    $arText = @(
        '- [x] 01 功能乙 `TW_B` → 01-TW_B.md',
        '- [x] 02 功能丙 `TW_E` → 02-TW_E.md'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText($ar, $arText, (New-Object System.Text.UTF8Encoding($true)))
    Remove-Item -LiteralPath $ledger -Force -ErrorAction SilentlyContinue
}

$failCount = 0
function Assert([bool]$Cond, [string]$Name) {
    if ($Cond) { Write-Host "  PASS：$Name" }
    else { Write-Host "  FAIL：$Name" -ForegroundColor Red; $script:failCount++ }
}

# ── 情境 1：掉一列＋加一列（總數不變）＋節標題被吃 ─────────────
Write-Host "情境 1：A5-02 消失＋新 A6-01 出現（總數不變）＋兩個節標題被吃"
Reset-Fixture
$pre = Get-ChecklistInventory
$broken = @(
    '# 測試領域 調查進度',
    '',
    '稽核輪次：6',
    '查無全量抽驗：已執行（第 3 輪）',
    '',
    '- [ ] 16 功能甲 `TW_A` → 16-TW_A.md',
    '- [ ] A5-01 補查 03-TW_C.md：FAIL 2（稽核）',
    '- [ ] A6-01 補查 09-TW_F.md：FAIL 3（稽核）',
    '- [ ] D5-01 新發現 TW_NEWOBJ：任務C 反查 PS_X 讀寫（稽核）',
    '- [ ] 任務 C 批次 2/4 未完成',
    '',
    '- 某 gap 描述'
) -join "`r`n"
[System.IO.File]::WriteAllText($cl, $broken, (New-Object System.Text.UTF8Encoding($true)))
$r = Invoke-ChecklistReconcile -PreInv $pre -PreRound 5
$after = Get-Content $cl -Raw -Encoding UTF8
Assert ($r.Restored -eq 1) "補回恰 1 列（A5-02）"
Assert ($after -match [regex]::Escape('A5-02 補查 07-TW_D.md')) "A5-02 內容回到活頁"
Assert ($after -match [regex]::Escape('A6-01 補查 09-TW_F.md')) "新 A6-01 未被刪"
Assert ($after -match '(?m)^##\s*調查進度') "調查進度節標題重建"
Assert ($after -match '(?m)^##\s*Gaps') "Gaps 節標題重建"
Assert ($after -match '稽核輪次：6') "session 寫的輪次 6 未被覆蓋"
$rows = @([regex]::Matches($after, '(?m)^\s*-\s*\[[ xX]\]'))
Assert ($rows.Count -eq 6) "活頁勾選列數正確（6）：實際 $($rows.Count)"

# ── 情境 2：合法歸檔搬移不誤報 ─────────────────────────────
Write-Host "情境 2：16 打勾搬進歸檔（合法）→ 不補回"
Reset-Fixture
$pre = Get-ChecklistInventory
$clText2 = (Get-Content $cl -Raw -Encoding UTF8) -replace [regex]::Escape('- [ ] 16 功能甲 `TW_A` → 16-TW_A.md') , ''
[System.IO.File]::WriteAllText($cl, $clText2, (New-Object System.Text.UTF8Encoding($true)))
Add-Content -Path $ar -Value "`r`n- [x] 16 功能甲 ``TW_A`` → 16-TW_A.md" -Encoding UTF8
$r = Invoke-ChecklistReconcile -PreInv $pre -PreRound 5
Assert ($r.Restored -eq 0) "歸檔搬移不算 loss（補回 0 列）"

# ── 情境 3：流程標籤列消失 → 不復活 ────────────────────────
Write-Host "情境 3：垃圾列（任務 C 批次）被刪 → 不補回"
Reset-Fixture
$pre = Get-ChecklistInventory
$clText3 = (Get-Content $cl -Raw -Encoding UTF8) -replace [regex]::Escape('- [ ] 任務 C 批次 2/4 未完成'), ''
[System.IO.File]::WriteAllText($cl, $clText3, (New-Object System.Text.UTF8Encoding($true)))
$r = Invoke-ChecklistReconcile -PreInv $pre -PreRound 5
Assert ($r.Restored -eq 0) "流程標籤不復活（補回 0 列）"

# ── 情境 4：打勾＋⚠ 註記（列文字合法變化）→ 不誤判 ───────────
Write-Host "情境 4：A5-01 打勾＋加 ⚠ 註記 → 身分不變，不補回"
Reset-Fixture
$pre = Get-ChecklistInventory
$clText4 = (Get-Content $cl -Raw -Encoding UTF8) -replace [regex]::Escape('- [ ] A5-01 補查 03-TW_C.md：FAIL 2（稽核）'), '- [x] A5-01 補查 03-TW_C.md：FAIL 2（稽核）⚠（部分修不了）'
[System.IO.File]::WriteAllText($cl, $clText4, (New-Object System.Text.UTF8Encoding($true)))
$r = Invoke-ChecklistReconcile -PreInv $pre -PreRound 5
Assert ($r.Restored -eq 0) "打勾＋⚠ 不算 loss（補回 0 列）"

# ── 情境 5：輪次行被吃 → 用圈前值重建 ─────────────────────
Write-Host "情境 5：輪次行消失 → 重建為圈前值"
Reset-Fixture
$pre = Get-ChecklistInventory
$clText5 = (Get-Content $cl -Raw -Encoding UTF8) -replace '稽核輪次：5', ''
[System.IO.File]::WriteAllText($cl, $clText5, (New-Object System.Text.UTF8Encoding($true)))
$r = Invoke-ChecklistReconcile -PreInv $pre -PreRound 5
$after5 = Get-Content $cl -Raw -Encoding UTF8
Assert ($after5 -match '稽核輪次[：:]\s*5') "輪次行重建為 5"
Assert (@($r.Rebuilt).Count -ge 1) "Rebuilt 有記錄"

# ── 情境 6：D 列被改寫成一般格式（錨點仍在）→ 不復活 ──────────
Write-Host "情境 6：D5-01 被 session 改寫成打勾一般列 → 視為改寫非遺失"
Reset-Fixture
$pre = Get-ChecklistInventory
$clText6 = (Get-Content $cl -Raw -Encoding UTF8) -replace [regex]::Escape('- [ ] D5-01 新發現 TW_NEWOBJ：任務C 反查 PS_X 讀寫（稽核）'), '- [x] 21 新發現功能 TW_NEWOBJ → 21-TW_NEWOBJ.md'
[System.IO.File]::WriteAllText($cl, $clText6, (New-Object System.Text.UTF8Encoding($true)))
$r = Invoke-ChecklistReconcile -PreInv $pre -PreRound 5
$after6 = Get-Content $cl -Raw -Encoding UTF8
Assert ($r.Restored -eq 0) "不復活（補回 0 列）"
Assert ($r.SkippedTransformed -eq 1) "計為改寫（SkippedTransformed=1）"
Assert (-not ($after6 -match [regex]::Escape('- [ ] D5-01'))) "未勾 D5-01 沒有重生"

# ── 情境 7：復活斷路器——同列第二次消失不再補回 ───────────────
Write-Host "情境 7：D5-01 真遺失 → 補回；再次遺失 → 斷路器擋下"
Reset-Fixture
$pre = Get-ChecklistInventory
$clText7 = (Get-Content $cl -Raw -Encoding UTF8) -replace [regex]::Escape('- [ ] D5-01 新發現 TW_NEWOBJ：任務C 反查 PS_X 讀寫（稽核）'), ''
[System.IO.File]::WriteAllText($cl, $clText7, (New-Object System.Text.UTF8Encoding($true)))
$r1 = Invoke-ChecklistReconcile -PreInv $pre -PreRound 5
Assert ($r1.Restored -eq 1) "第一次真遺失 → 補回（含「任務C」字樣的合法 D 工單不被垃圾過濾誤殺）"
Assert (Test-Path -LiteralPath $ledger) "台帳已寫入"
$pre2 = Get-ChecklistInventory
$clText7b = (Get-Content $cl -Raw -Encoding UTF8) -replace [regex]::Escape('- [ ] D5-01 新發現 TW_NEWOBJ：任務C 反查 PS_X 讀寫（稽核）'), ''
[System.IO.File]::WriteAllText($cl, $clText7b, (New-Object System.Text.UTF8Encoding($true)))
$r2 = Invoke-ChecklistReconcile -PreInv $pre2 -PreRound 5
Assert ($r2.Restored -eq 0) "第二次消失 → 不補回"
Assert ($r2.SkippedRepeat -eq 1) "斷路器計數（SkippedRepeat=1）"

# ── 情境 8：同文重複列收斂；一勾一未勾不動 ─────────────────
Write-Host "情境 8：完全同文的重複列收斂為一列；勾況不同的不動"
Reset-Fixture
Add-Content -Path $cl -Value '' -Encoding UTF8
Add-Content -Path $cl -Value '- [ ] D5-01 新發現 TW_NEWOBJ：任務C 反查 PS_X 讀寫（稽核）' -Encoding UTF8
Add-Content -Path $cl -Value '- [x] 16 功能甲 `TW_A` → 16-TW_A.md' -Encoding UTF8
$pre = Get-ChecklistInventory
$r = Invoke-ChecklistReconcile -PreInv $pre -PreRound 5
$after8 = Get-Content $cl -Raw -Encoding UTF8
Assert ($r.Deduped -eq 1) "同文重複收斂 1 列"
$d501 = @([regex]::Matches($after8, [regex]::Escape('- [ ] D5-01 新發現')))
Assert ($d501.Count -eq 1) "D5-01 只剩一列"
Assert (($after8 -match [regex]::Escape('- [ ] 16 功能甲')) -and ($after8 -match [regex]::Escape('- [x] 16 功能甲'))) "一勾一未勾的 16 兩列都保留（不亂刪）"

# ── 情境 9：身分工具本身——「任務C」D 列的身分是工單不是垃圾 ────
Write-Host "情境 9：Get-RowIdentity 對含「任務C」的 D 列給 wo: 身分"
$id9 = Get-RowIdentity -Row '- [ ] D63-07 新發現 TW_XYZ：任務C 反查（稽核）'
Assert ($id9 -eq 'wo:D63-07') "身分＝wo:D63-07（實際：$id9）"

# ══ D 項治理（issue #8／L99）══════════════════════════════════
function Set-GovChecklist([string[]]$Rows) {
    $head = @('# 測試領域 調查進度', '', '稽核輪次：6', '', '## 調查進度', '')
    $tail = @('', '## Gaps 彙整（隨深查更新）', '', '- （無）')
    [System.IO.File]::WriteAllText($cl, (($head + $Rows + $tail) -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
}

Write-Host "情境 10：D 提案的物件已有 NN 檔 → 刪；沒有 → 留"
Reset-Fixture
[System.IO.File]::WriteAllText((Join-Path $dir '21-TW_K1.md'), "# t`n", (New-Object System.Text.UTF8Encoding($true)))
Set-GovChecklist @(
    '- [ ] D6-01 新發現 TW_K1：任務C 反查（稽核）',
    '- [ ] D6-02 新發現 TW_K2：任務C 反查（稽核）'
)
$g = Invoke-DItemGovernance
$a10 = Get-Content $cl -Raw -Encoding UTF8
Assert ($g.Removed -eq 1) "刪 1 列（TW_K1）"
Assert (-not ($a10 -match 'TW_K1')) "TW_K1 提案已刪"
Assert ($a10 -match 'TW_K2') "TW_K2 提案保留"

Write-Host "情境 11：大小寫＋PS_ 前綴正規化 → 同物件"
Set-GovChecklist @('- [ ] D6-03 新發現 ps_tw_k1：任務C 反查（稽核）')
$g = Invoke-DItemGovernance
Assert ($g.Removed -eq 1) "ps_tw_k1 視同 TW_K1，刪除"

Write-Host "情境 12：只有續篇檔（-2）也算已知物件"
[System.IO.File]::WriteAllText((Join-Path $dir '23-TW_K4-2.md'), "# t`n", (New-Object System.Text.UTF8Encoding($true)))
Set-GovChecklist @('- [ ] D6-04 新發現 TW_K4：任務C 反查（稽核）')
$g = Invoke-DItemGovernance
Assert ($g.Removed -eq 1) "續篇檔的主物件視為已知，刪除"

Write-Host "情境 13：本頁兩列同物件（異號）→ 第二列刪"
Set-GovChecklist @(
    '- [ ] D6-05 新發現 TW_K5：任務C 反查（稽核）',
    '- [ ] D6-06 新發現 tw_k5：批次二回報（稽核）'
)
$g = Invoke-DItemGovernance
$a13 = Get-Content $cl -Raw -Encoding UTF8
Assert ($g.Removed -eq 1) "第二列刪除"
Assert ($a13 -match 'D6-05') "第一列保留"

Write-Host "情境 14：同號異物件 → 第二列重配號"
Set-GovChecklist @(
    '- [ ] D6-07 新發現 TW_K6：任務C 反查（稽核）',
    '- [ ] D6-07 新發現 TW_K7：任務C 反查（稽核）'
)
$g = Invoke-DItemGovernance
$a14 = Get-Content $cl -Raw -Encoding UTF8
Assert ($g.Renumbered -eq 1) "重配 1 列"
Assert (($a14 -match 'D6-07 新發現 TW_K6') -and ($a14 -match 'D6-08 新發現 TW_K7')) "TW_K7 改號 D6-08，兩列都在"

Write-Host "情境 15：歸檔 D 列的物件擋掉新提案；已勾列不動"
Add-Content -Path $ar -Value '' -Encoding UTF8
Add-Content -Path $ar -Value '- [x] D5-09 新發現 TW_K8：任務C 反查（稽核）（→ 24-TW_K8.md）' -Encoding UTF8
Set-GovChecklist @(
    '- [x] D6-09 新發現 TW_K9：任務C 反查（稽核）（→ 25-TW_K9.md）',
    '- [ ] D6-10 新發現 TW_K8：任務C 反查（稽核）'
)
$g = Invoke-DItemGovernance
$a15 = Get-Content $cl -Raw -Encoding UTF8
Assert ($g.Removed -eq 1) "歸檔 D 物件擋掉新提案（刪 1）"
Assert ($a15 -match [regex]::Escape('- [x] D6-09 新發現 TW_K9')) "已勾 D 列原樣不動"

# ══ 手術佇列生命週期（issue #11／L102）═══════════════════════
$global:surgeryLedgerPath = Join-Path $dir 'surgery-ledger.json'

Write-Host "情境 16：指紋去編號——編號漂移不改身分"
$f1 = Get-OrderFingerprint '3. [證據] 27-TW_A.md：縮寫 id abc12345'
$f2 = Get-OrderFingerprint '17. [證據] 27-TW_A.md：縮寫 id abc12345'
Assert ($f1 -eq $f2 -and $f1 -eq '[證據] 27-TW_A.md：縮寫 id abc12345') "同單不同編號＝同指紋"

Write-Host "情境 17：選批跳過 BLOCKED——毒丸靠邊，後方照常服務"
$surgical = @('1. [證據] A：x', '2. [證據] B：y', '3. [證據] C：z', '4. [證據] D：w')
$led = @{}
$led[(Get-OrderFingerprint '1. [證據] A：x')] = @{ attempts = 2; blocked = $true }
$b = Select-SurgeryBatch -Surgical $surgical -Ledger $led -Size 2
Assert ($b.Count -eq 2 -and $b[0] -match '\[證據\] B' -and $b[1] -match '\[證據\] C') "批＝B、C（A 被跳過）"
Assert ((Get-ActionableSurgicalCount -Surgical $surgical -Ledger $led) -eq 3) "可執行債＝3（4 總 −1 BLOCKED）"

Write-Host "情境 18：Save 剪枝——lint 已不出的工單不得被台帳復活"
$led2 = @{}
$led2['[證據] A：x'] = @{ attempts = 2; blocked = $true }
$led2['[證據] B：y'] = @{ attempts = 1; blocked = $false }
$led3 = Save-SurgeryLedger -Ledger $led2 -CurrentSurgical @('9. [證據] B：y')
Assert ((-not $led3.ContainsKey('[證據] A：x')) -and $led3.ContainsKey('[證據] B：y')) "A（已解決）剪掉、B 保留"
$led4 = Get-SurgeryLedger
Assert ($led4.ContainsKey('[證據] B：y') -and $led4['[證據] B：y'].attempts -eq 1) "落檔重讀 round-trip 一致"

Write-Host "情境 19：身分尺——count 平手但掉 A 生 D＝有進度"
$setB = @{}; foreach ($x in @('[a]','[b]','[c]')) { $setB[$x] = $true }
$setA = @{}; foreach ($x in @('[b]','[c]','[d]')) { $setA[$x] = $true }
$res = 0; foreach ($k in $setB.Keys) { if (-not $setA.ContainsKey($k)) { $res++ } }
Assert ($res -eq 1) "resolved＝1（舊 a 已解；count 3→3 不誤判零進度）"

Write-Host "情境 20：指紋正規化——行號與行清單是狀態不是身分（L103）"
$a1 = Get-OrderFingerprint '3. [洩漏] 27-TW_A.md:120：<TOOL_CALL>'
$a2 = Get-OrderFingerprint '5. [洩漏] 27-TW_A.md:145：<TOOL_CALL>'
Assert ($a1 -eq $a2 -and $a1 -eq '[洩漏] 27-TW_A.md：<TOOL_CALL>') "同檔同標記、行號漂移＝同指紋（幻影 resolved 消失）"
$b1 = Get-OrderFingerprint '4. [欄位] 27-TW_A.md：12 列欄位錯放（行 10、22、31）'
$b2 = Get-OrderFingerprint '4. [欄位] 27-TW_A.md：12 列欄位錯放（行 11、23、32）'
$b3 = Get-OrderFingerprint '4. [欄位] 27-TW_A.md：8 列欄位錯放（行 11、23）'
Assert ($b1 -eq $b2) "[欄位] 行清單漂移＝同指紋"
Assert ($b1 -ne $b3) "[欄位] 列數下降＝真進度＝不同指紋（attempts 重置合法）"
$c1 = Get-OrderFingerprint '7. [證據] 27-TW_A.md：縮寫 id abc12345'
Assert ($c1 -eq '[證據] 27-TW_A.md：縮寫 id abc12345') "[證據] 型無行號成分＝原樣保留"
$d1 = Get-OrderFingerprint '9. [附錄] 48-TW_B.md：Evidence 附錄非模板表格（裸 ChunkId 傾倒）'
$d2 = Get-OrderFingerprint '2. [附錄] 48-TW_B.md：Evidence 附錄非模板表格（裸 ChunkId 傾倒）'
Assert ($d1 -eq $d2) "[附錄] 型編號漂移＝同指紋"
$e1 = Get-OrderFingerprint '1. [證據] 27-TW_A.md:88：機器參照無效＠fld.pcode:12-24'
$e2 = Get-OrderFingerprint '6. [證據] 27-TW_A.md:99：機器參照無效＠fld.pcode:12-24'
Assert ($e1 -eq $e2 -and $e1 -match 'fld\.pcode:12-24') "只剝 .md 行號——pcode 路徑行號是內容、保留"

Write-Host "情境 21：NN 檔破壞防衛——掏空還原、合法改動不誤傷（L103）"
Reset-Fixture
$nn = Join-Path $dir "27-TW_A.md"
$full = @('# 27 功能甲（TW_A）', '', '## 相關物件', 'x', '## 功能定位', 'x', '## 畫面與欄位', 'x', '## 行為邏輯', 'x', '## 資料流', 'x', '## 執行方式', 'x', '## 未解事項（gaps）', 'x', '## Evidence 附錄', '| # | 位置 | 說明 | 機器參照 |') -join "`r`n"
[System.IO.File]::WriteAllText($nn, $full, (New-Object System.Text.UTF8Encoding($true)))
$audit90 = Join-Path $dir "90-audit.md"
[System.IO.File]::WriteAllText($audit90, "# audit`r`n## 記分卡", (New-Object System.Text.UTF8Encoding($true)))
$snap = Get-NnGuardSnapshot
Assert ($snap.ContainsKey('27-TW_A.md') -and -not $snap.ContainsKey('90-audit.md') -and -not $snap.ContainsKey('checklist.md')) "快照含 NN 檔、不含 90-audit.md 與 checklist"
$origBytes = [System.IO.File]::ReadAllBytes($nn)
[System.IO.File]::WriteAllText($nn, "## Evidence 附錄`r`nchunks 3f2a9c1e-7b4d-4e8a-9c6f-1d2e3a4b5c6d", (New-Object System.Text.UTF8Encoding($true)))
$n1 = Invoke-NnDestructionGuard -Snap $snap -Tag "test"
Assert ($n1 -eq 1 -and ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($nn)) -eq [Convert]::ToBase64String($origBytes))) "正典節消失→整檔位元組還原（實案：只剩 Evidence 節）"
$legal = ($full -replace '## 未解事項（gaps）', '## 未解事項') + "`r`n| 1 | a.pcode:1-2 | 說明 | ChunkId 3f2a9c1e-7b4d-4e8a-9c6f-1d2e3a4b5c6d |"
[System.IO.File]::WriteAllText($nn, $legal, (New-Object System.Text.UTF8Encoding($true)))
$n2 = Invoke-NnDestructionGuard -Snap $snap -Tag "test"
Assert ($n2 -eq 0 -and ((Get-Content $nn -Raw -Encoding UTF8) -match '新增|ChunkId')) "（gaps）尾註正規化＋加內容＝合法、不誤傷"
Remove-Item -LiteralPath $nn -Force
$n3 = Invoke-NnDestructionGuard -Snap $snap -Tag "test"
Assert ($n3 -eq 1 -and (Test-Path $nn)) "檔案消失→還原"
$big = (@('# t', '', '## 相關物件') + (1..50 | ForEach-Object { "line$_" }) + @('## Evidence 附錄', '| 1 | p | s | 待人工SQL |')) -join "`r`n"
[System.IO.File]::WriteAllText($nn, $big, (New-Object System.Text.UTF8Encoding($true)))
$snap3 = Get-NnGuardSnapshot
[System.IO.File]::WriteAllText($nn, (@('# t', '', '## 相關物件', '## Evidence 附錄') -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
$n4 = Invoke-NnDestructionGuard -Snap $snap3 -Tag "test"
Assert ($n4 -eq 1) "節都在但 40+ 行掏空到 30% 以下→還原"
$smallSnapFile = Join-Path $dir "28-TW_S.md"
[System.IO.File]::WriteAllText($smallSnapFile, (@('# s', '## 相關物件', 'a', 'b', 'c') -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
$snap4 = Get-NnGuardSnapshot
[System.IO.File]::WriteAllText($smallSnapFile, (@('# s', '## 相關物件') -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
$n5 = Invoke-NnDestructionGuard -Snap $snap4 -Tag "test"
Assert (@($snap4.Keys | Where-Object { $_ -eq '28-TW_S.md' }).Count -eq 1 -and $n5 -eq 0) "小檔（不足 40 行）縮短不觸發行數規則"
$snapA = Get-NnGuardSnapshot
Assert ($snapA.ContainsKey('checklist-archive-r5.md') -and $snapA['checklist-archive-r5.md'].Kind -eq 'archive') "歸檔檔進快照（Kind=archive）"
Add-Content -LiteralPath $ar -Value '- [x] 03 功能丁 `TW_F` → 03-TW_F.md' -Encoding UTF8
$nA1 = Invoke-NnDestructionGuard -Snap $snapA -Tag "test"
Assert ($nA1 -eq 0) "歸檔 append（長大）＝合法、不觸發"
$arOrig = [System.IO.File]::ReadAllBytes($ar)
$snapA2 = Get-NnGuardSnapshot
[System.IO.File]::WriteAllText($ar, "- [x] 01 功能乙 `r`n", (New-Object System.Text.UTF8Encoding($true)))
$nA2 = Invoke-NnDestructionGuard -Snap $snapA2 -Tag "test"
Assert ($nA2 -eq 1) "歸檔縮短→還原（r60 實案：整檔消失前身）"
Remove-Item -LiteralPath $ar -Force
$nA3 = Invoke-NnDestructionGuard -Snap $snapA2 -Tag "test"
Assert ($nA3 -eq 1 -and (Test-Path $ar)) "歸檔消失→還原"
Remove-Item -LiteralPath $smallSnapFile -Force
Remove-Item -LiteralPath $audit90 -Force

Write-Host "情境 23：跨檔同文去重——已勾刪活頁、未勾留人工、記帳可用（L103）"
Reset-Fixture
$clDup = @(
    '# 測試領域 調查進度', '', '稽核輪次：8', '', '## 調查進度', '',
    '- [x] 05 功能戊 `TW_G` → 05-TW_G.md',
    '- [ ] 06 功能己 `TW_H` → 06-TW_H.md',
    '- [x] 07 功能庚 `TW_I` → 07-TW_I.md',
    '', '## Gaps 彙整（隨深查更新）', '', '- 無'
) -join "`r`n"
[System.IO.File]::WriteAllText($cl, $clDup, (New-Object System.Text.UTF8Encoding($true)))
$arDup = @(
    '- [x] 05 功能戊 `TW_G` → 05-TW_G.md',
    '- [x] 06 功能己 `TW_H` → 06-TW_H.md'
) -join "`r`n"
[System.IO.File]::WriteAllText($ar, $arDup, (New-Object System.Text.UTF8Encoding($true)))
$adN = Invoke-ArchiveDedup
$clAfter = Get-Content $cl -Raw -Encoding UTF8
Assert ($adN -eq 1) "只刪 1 列（已勾且歸檔已存）"
Assert ($clAfter -notmatch '\[x\] 05 功能戊') "已勾重複列已從活頁移除"
Assert ($clAfter -match '\[ \] 06 功能己') "未勾×歸檔已存＝歧義，留人工"
Assert ($clAfter -match '\[x\] 07 功能庚') "非重複的已勾列不動"
$adN2 = Invoke-ArchiveDedup
Assert ($adN2 -eq 0) "冪等：第二次跑零刪除"

Write-Host "情境 24：歸檔 commit 外環化——先寫後驗才刪活頁、同輪合併、冪等（L105）"
Get-ChildItem $dir -Filter "checklist-archive*.md" | Remove-Item -Force
$clAc = @(
    '# 測試領域 調查進度', '', '稽核輪次：6', '', '## 調查進度', '',
    '- [x] 11 功能子 `TW_M` → 11-TW_M.md',
    '- [x] A6-01 補查 03-TW_C.md：FAIL 1（稽核）',
    '- [ ] D6-01 新發現 TW_N：任務C 反查（稽核）',
    '', '## Gaps 彙整（隨深查更新）', '', '- 無'
) -join "`r`n"
[System.IO.File]::WriteAllText($cl, $clAc, (New-Object System.Text.UTF8Encoding($true)))
$acN = Invoke-ChecklistArchiveCommit
$arNew = Join-Path $dir "checklist-archive-r6.md"
$clNow = Get-Content $cl -Raw -Encoding UTF8
$arNow = Get-Content $arNew -Raw -Encoding UTF8
Assert ($acN -eq 2 -and (Test-Path $arNew)) "2 列已勾搬進 checklist-archive-r6.md"
Assert ($arNow -match '11 功能子' -and $arNow -match 'A6-01') "archive 含兩列"
Assert ($clNow -notmatch '11 功能子' -and $clNow -notmatch 'A6-01') "活頁已刪兩列（搬移不是複製）"
Assert ($clNow -match 'D6-01' -and $clNow -match '## 調查進度' -and $clNow -match '## Gaps') "未勾列與固定結構保留"
$acN2 = Invoke-ChecklistArchiveCommit
Assert ($acN2 -eq 0) "無已勾列＝冪等零動作"
$clNow2 = ($clNow -replace '\[ \] D6-01', '[x] D6-01')
[System.IO.File]::WriteAllText($cl, $clNow2, (New-Object System.Text.UTF8Encoding($true)))
$acN3 = Invoke-ChecklistArchiveCommit
$arNow3 = Get-Content $arNew -Raw -Encoding UTF8
Assert ($acN3 -eq 1 -and $arNow3 -match 'D6-01' -and $arNow3 -match '11 功能子' -and (@([regex]::Matches($arNow3, '11 功能子')).Count -eq 1)) "同輪二次 commit＝合併寫、既有列不重複"
Get-ChildItem $dir -Filter "checklist-archive*.md" | Remove-Item -Force

Write-Host "情境 25：容量事件標籤——out/err 含 context 溢出字樣即標 CONTEXT_OVERFLOW，不看 exit（L106）"
$fkOut = Join-Path $dir "t.out.txt"; $fkErr = Join-Path $dir "t.err.txt"
[System.IO.File]::WriteAllText($fkOut, "normal output`r`ndone", (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText($fkErr, "", (New-Object System.Text.UTF8Encoding($false)))
Assert ((Get-SessionFailureKind -OutFile $fkOut -ErrFile $fkErr) -eq 'NONE') "無字樣＝NONE"
[System.IO.File]::WriteAllText($fkOut, "tool result: Error: Context length exceeded (32768)`r`n", (New-Object System.Text.UTF8Encoding($false)))
Assert ((Get-SessionFailureKind -OutFile $fkOut -ErrFile $fkErr) -eq 'CONTEXT_OVERFLOW') "out 含 Context length exceeded → CONTEXT_OVERFLOW"
[System.IO.File]::WriteAllText($fkOut, "ok", (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText($fkErr, "openai: This model's maximum context length is 32768 tokens", (New-Object System.Text.UTF8Encoding($false)))
Assert ((Get-SessionFailureKind -OutFile $fkOut -ErrFile $fkErr) -eq 'CONTEXT_OVERFLOW') "err 含 maximum context length → CONTEXT_OVERFLOW"
Assert ((Get-SessionFailureKind -OutFile (Join-Path $dir "nope.txt") -ErrFile $null) -eq 'NONE') "檔案不存在／null＝NONE 不炸"
Remove-Item -LiteralPath $fkOut, $fkErr -Force

Write-Host "情境 26：分批稽核——claim 抽樣／manifest 切段／part 不變量／合併器（L107）"
Reset-Fixture
Get-ChildItem $dir -Filter "checklist-archive*.md" | Remove-Item -Force
$U1='3f2a9c1e-7b4d-4e8a-9c6f-1d2e3a4b5c6d'; $U2='4a3b2c1d-5e6f-4a8b-9c0d-1e2f3a4b5c6d'; $U3='5b4c3d2e-6f7a-4b9c-8d1e-2f3a4b5c6d7e'; $UX='99999999-8888-4777-8666-555544443333'
$nn01 = @('# 01 甲（TW_A）','## 相關物件','x','## 功能定位','x','## 畫面與欄位','x','## 行為邏輯','- **CONFIRMED**：選 E 時開放免役原因（`a.pcode:12`）','- **INFERRED**：略','- **CONFIRMED**：核准後回寫（`a.pcode:40`）','## 資料流','| 表 | 操作 | 來源 | 信心 |','|---|---|---|---|','| PS_TW_X | UPDATE | 存檔 | CONFIRMED |','## 執行方式','x','## 未解事項（gaps）','- 無','## Evidence 附錄','| # | 位置 | 說明 | 機器參照 |','|---|---|---|---|',"| 1 | ``a.pcode:1-2`` | 測試 | ChunkId ``$U1`` |","| 2 | ``a.pcode:3-4`` | 測試 | ChunkId ``$U2`` |","| 3 | ``a.pcode:5-6`` | 測試 | ChunkId ``$U3`` |") -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $dir '01-TW_A.md'), $nn01, (New-Object System.Text.UTF8Encoding($true)))
$claims = Get-ClaimSample -Path (Join-Path $dir '01-TW_A.md') -Max 5
Assert ($claims.Count -eq 3 -and $claims[0] -match '免役原因' -and $claims[2] -match 'PS_TW_X') "claim 抽樣：粗體行 2＋資料流表 1＝3 條、順序穩定"
Assert ((Get-ClaimSample -Path (Join-Path $dir '01-TW_A.md') -Max 2).Count -eq 2) "claim 抽樣上限生效"
$mfFiles = @(@{ Name='01-TW_A.md'; Rows=3; PageSize=10; Claims=@('c1') }, @{ Name='02-TW_B.md'; Rows=25; PageSize=10; Claims=@() }, @{ Name='03-TW_C.md'; Rows=0; PageSize=10; Claims=@('z') })
$null = New-AuditManifest -TargetRound 6 -FullSweep $true -Files $mfFiles -BatchIndex 1 -BatchTotal 2 -DomainTasks $false -WikiPicks @()
$mf = Get-Content $auditManifestPath -Raw -Encoding UTF8
Assert ($mf -match '目標輪次：6' -and $mf -match '待執行' -and $mf -match '02-TW_B\.md｜Evidence 列數=25｜範圍=1-10,11-20,21-25' -and $mf -match '03-TW_C\.md｜Evidence 列數=0｜範圍=全' -and $mf -match 'part-1\.md') "manifest：輪次／旗標／範圍切段（25 列→3 段、0 列→全）／輸出路徑"
$null = New-AuditManifest -TargetRound 6 -FullSweep $false -Files @() -BatchIndex 0 -BatchTotal 0 -DomainTasks $true -WikiPicks @('docs/ps-research/wiki/TW_A.md')
$mf0 = Get-Content $auditManifestPath -Raw -Encoding UTF8
Assert ($mf0 -match '照常' -and $mf0 -match '任務 C' -and $mf0 -match 'wiki/TW_A\.md' -and $mf0 -match 'domain\.md') "manifest 批次 0：領域任務＋wiki 抽驗＋domain.md 輸出"
New-Item -ItemType Directory -Path $auditPartsDir -Force | Out-Null
$partOk = @('## 記分卡','| 檔案 | 範圍 | PASS | FAIL | UNVERIFIABLE | PENDING_MANUAL | VERIFIED | DISPUTED |','|---|---|---|---|---|---|---|---|','| 01-TW_A.md | 全 | 2 | 1 | 0 | 0 | 2 | 0 |','| 02-TW_B.md | 1-10 | 10 | 0 | 0 | 0 | 0 | 0 |','| 02-TW_B.md | 11-12 | 1 | 0 | 1 | 0 | 0 | 0 |','','## 明細','| 檔案 | 類型 | 內容 | 原因 | 處置 |','|---|---|---|---|---|',"| 01-TW_A.md | 證據 FAIL(ID_RELINK) | ChunkId $U2 | 文件說…；實際…；差異… | 換 id：$U2 → $UX |","| 02-TW_B.md | 證據 UNVERIFIABLE | SQL … | oracleMCP 逾時 | 回灌重驗 |") -join "`r`n"
$partP = Join-Path $auditPartsDir 'part-1.md'
[System.IO.File]::WriteAllText($partP, $partOk, (New-Object System.Text.UTF8Encoding($true)))
$res = Test-AuditPart -PartPath $partP -Expected @{ '01-TW_A.md' = 3; '02-TW_B.md' = 12 }
Assert ($res.Files.ContainsKey('01-TW_A.md') -and $res.Files.ContainsKey('02-TW_B.md') -and $res.Invalid.Count -eq 0) "part 不變量：合計＝列數、範圍覆蓋、明細 id 在附錄（處置欄的新 id 不算）→ 兩檔收據"
Assert ($res.Files['02-TW_B.md'].pass -eq 11 -and $res.Files['02-TW_B.md'].unver -eq 1 -and $res.Files['01-TW_A.md'].detail.Count -eq 1) "part 範圍加總正確、明細歸檔"
[System.IO.File]::WriteAllText($partP, ($partOk -replace '\| 02-TW_B\.md \| 11-12 \| 1 \| 0 \| 1 \|', '| 02-TW_B.md | 11-12 | 1 | 0 | 0 |'), (New-Object System.Text.UTF8Encoding($true)))
$res2 = Test-AuditPart -PartPath $partP -Expected @{ '01-TW_A.md' = 3; '02-TW_B.md' = 12 }
Assert ($res2.Invalid.ContainsKey('02-TW_B.md') -and $res2.Invalid['02-TW_B.md'] -match '合計 11') "合計≠列數 → 無收據（半檔漏網抓得到）"
[System.IO.File]::WriteAllText($partP, ($partOk -replace '\| 02-TW_B\.md \| 11-12 \| 1 \| 0 \| 1 \| 0 \| 0 \| 0 \|', ''), (New-Object System.Text.UTF8Encoding($true)))
$res3 = Test-AuditPart -PartPath $partP -Expected @{ '01-TW_A.md' = 3; '02-TW_B.md' = 12 }
Assert ($res3.Invalid.ContainsKey('02-TW_B.md')) "缺範圍列 → 無收據"
[System.IO.File]::WriteAllText($partP, ($partOk -replace [regex]::Escape("ChunkId $U2 |"), "ChunkId $UX |"), (New-Object System.Text.UTF8Encoding($true)))
$res4 = Test-AuditPart -PartPath $partP -Expected @{ '01-TW_A.md' = 3; '02-TW_B.md' = 12 }
Assert ($res4.Invalid.ContainsKey('01-TW_A.md') -and $res4.Invalid['01-TW_A.md'] -match '不在該檔') "明細內容欄引用附錄沒有的 id → 無收據（捏造判定）"
[System.IO.File]::WriteAllText($partP, ($partOk + "`r`n</think>"), (New-Object System.Text.UTF8Encoding($true)))
$res5 = Test-AuditPart -PartPath $partP -Expected @{ '01-TW_A.md' = 3; '02-TW_B.md' = 12 }
Assert ($res5.Invalid.Count -eq 2) "part 含洩漏標記 → 整批無收據"
$dom = @('## 完整性','- 任務 C 覆蓋：完成 2／共 2 批（未完成批次：無）','| 候選物件 | 型別 | 經由表 | 方向 | origin | 分類 | 理由 |','|---|---|---|---|---|---|---|','| TW_NEW1 | Component | PS_JOB | WRITE | CUSTOM_PREFIX | DOMAIN_ROOT | 命中 aliases |','| PS_JOB | Record | PS_JOB | READ | DELIVERED | DEPENDENCY | 共用表 |','','## wiki 記分卡','| 檔案 | 範圍 | PASS | FAIL | UNVERIFIABLE | PENDING_MANUAL | VERIFIED | DISPUTED |','|---|---|---|---|---|---|---|---|','| wiki/TW_A.md | 全 | 3 | 1 | 0 | 0 | 0 | 0 |','','## wiki 明細','| 檔案 | 類型 | 內容 | 原因 | 處置 |','|---|---|---|---|---|','| wiki/TW_A.md | 證據 FAIL | ChunkId x | 過期 | 回灌補查 |') -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $auditPartsDir 'domain.md'), $dom, (New-Object System.Text.UTF8Encoding($true)))
$clM = @('# 測試領域 調查進度','','稽核輪次：5','查無全量抽驗：待執行','','## 調查進度','','- [ ] 16 功能甲 `TW_A` → 16-TW_A.md','','## Gaps 彙整（隨深查更新）','','- 無') -join "`r`n"
[System.IO.File]::WriteAllText($cl, $clM, (New-Object System.Text.UTF8Encoding($true)))
$led = @{ round = 6; batchK = 6; domainDone = $true; domainAttempts = 0; domainReason = ''; wiki = @(); files = @{
    '01-TW_A.md' = @{ hash='h1'; rows=3; status='DONE'; attempts=0; pageSize=10; reason=''; pass=2; fail=1; unver=0; pending=0; verified=2; disputed=0; detail=@("| 01-TW_A.md | 證據 FAIL(ID_RELINK) | ChunkId $U2 | 文件說… | 換 id：$U2 → $UX |") }
    '02-TW_B.md' = @{ hash='h2'; rows=12; status='DONE'; attempts=0; pageSize=10; reason=''; pass=11; fail=0; unver=0; pending=1; verified=0; disputed=0; detail=@('| 02-TW_B.md | 證據 UNVERIFIABLE(PENDING_MANUAL) | SQL … | 待人工SQL | — |') }
    '03-TW_C.md' = @{ hash='h3'; rows=37; status='BLOCKED'; attempts=2; pageSize=3; reason='證據判定合計 30 ≠ Evidence 列數 37'; pass=0; fail=0; unver=0; pending=0; verified=0; disputed=0; detail=@() } } }
Save-AuditLedger -Ledger $led
$led2 = Get-AuditLedger
Assert ($led2.round -eq 6 -and $led2.files['03-TW_C.md'].status -eq 'BLOCKED' -and $led2.files['01-TW_A.md'].detail.Count -eq 1) "台帳 round-trip"
$mg = Invoke-AuditMerge -Ledger $led2 -TargetRound 6
$rep = Get-Content (Join-Path $dir '90-audit.md') -Raw -Encoding UTF8
$clA = Get-Content $cl -Raw -Encoding UTF8
Assert ($mg.ARows -eq 2 -and $mg.DRows -eq 1 -and $mg.Blocked.Count -eq 1) "合併器：A 列 2（01 有 FAIL、wiki 有 FAIL；02 只有 PENDING 不開單）、D 列 1（只 DOMAIN_ROOT）、BLOCKED 1"
foreach ($sec in @('## 總覽記分卡','## FAIL / DISPUTED / UNVERIFIABLE 明細','## 上輪回灌項覆核','## 完整性（換角度 diff）','## 已回灌 checklist 的行動項','## 系統性錯誤觀察')) { Assert ($rep -match [regex]::Escape($sec)) "90-audit 章節：$sec" }
Assert ($rep -match '稽核輪次：6' -and $rep -match '\| 01-TW_A\.md \| 2 \| 1 \| 0 \| 2 \| 0 \| 🔴 \|' -and $rep -match '\| 02-TW_B\.md \| 11 \| 0 \| 1 \| 0 \| 0 \| 🟡 \|' -and $rep -match '\| 03-TW_C\.md \| 未稽核（BLOCKED' -and $rep -match '\*\*合計\*\* \| \*\*13\*\*') "90-audit：輪次、逐檔列（PENDING 併入 UNVERIFIABLE 欄）、未稽核列、合計"
Assert ($rep -match '任務 C 覆蓋：完成 2／共 2 批' -and $rep -match '\| TW_NEW1 \|') "90-audit 完整性節承接 domain.md"
Assert ($clA -match '- \[ \] A6-01 補查 01-TW_A\.md：FAIL 1／DISPUTED 0／UNVERIFIABLE 0（稽核）' -and $clA -match '- \[ \] A6-02 補查 wiki/TW_A\.md：FAIL 1' -and $clA -match '- \[ \] D6-01 新發現 TW_NEW1：命中 aliases（稽核）' -and $clA -notmatch 'PS_JOB') "checklist：A 列連號一檔一行、D 列僅 DOMAIN_ROOT、DEPENDENCY 不建 D"
Assert ($clA -match '稽核輪次：6' -and $clA -match '查無全量抽驗：已執行（第 6 輪）' -and $clA -match '## Gaps 彙整' -and $clA -match '16 功能甲') "checklist：輪次遞增、旗標翻轉、骨架與原列保留"
Remove-Item -Recurse -Force $auditPartsDir; Remove-Item -LiteralPath $auditLedgerPath, $auditManifestPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $dir '01-TW_A.md'), (Join-Path $dir '90-audit.md') -Force

Write-Host "情境 27：research 範圍債——checkpoint ≠ discovery complete（issue #23）"
Reset-Fixture
$rd = Get-ResearchDebt
Assert ($rd.Plain -eq 1 -and $rd.D -eq 1 -and $rd.Total -eq 2) "fixture：原始調查項 1＋D 項 1＝債 2；A 項與流程標籤不計"
$sc = Test-ResearchScopeOk
Assert ((-not $sc.Ok) -and $sc.Debt.Total -eq 2) "縱深：有債 → RESEARCH_SCOPE FAIL（畢業門獨立判定，不依賴相位）"
$rows = @('# 測試領域 調查進度', '', '稽核輪次：0', '', '## 調查進度', '')
for ($i = 1; $i -le 15; $i++) { $box = if ($i -le 6) { '[x]' } else { '[ ]' }; $rows += ('- ' + $box + ' ' + ('{0:D2}' -f $i) + ' 功能' + $i + ' `TW_F' + $i + '` → ' + ('{0:D2}' -f $i) + '-TW_F' + $i + '.md') }
$rows += @('', '## Gaps 彙整', '', '- 無')
[System.IO.File]::WriteAllText($cl, ($rows -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
$rd = Get-ResearchDebt
Assert ($rd.Plain -eq 9 -and $rd.D -eq 0 -and $rd.Total -eq 9) "正常 checkpoint：15 項做完 6 項 → 債 9（下一圈必須 research，不得 audit）"
[System.IO.File]::WriteAllText((Join-Path $dir '07-TW_F7.md'), "# 07`n", (New-Object System.Text.UTF8Encoding($true)))
Assert ((Get-ResearchDebt).Total -eq 9) "強殺：目標檔已存在但列未勾 → 仍是債（以勾選為準，/ps-research 從該項續做）"
Remove-Item -LiteralPath (Join-Path $dir '07-TW_F7.md') -Force
$rows2 = @('# x', '', '稽核輪次：2', '', '## 調查進度', '', '- [x] 01 功能1 `TW_F1` → 01-TW_F1.md', '- [ ] A2-01 補查 01-TW_F1.md：FAIL 1（稽核）', '- [ ] U2-01 條件UI回灌 01-TW_F1.md：主角 TW_F1 UI 狀態變異偵測與解析', '- [ ] 任務 C 批次 1/2 未完成', '- [ ] task C batch 2/2', '', '## Gaps 彙整', '', '- 無')
[System.IO.File]::WriteAllText($cl, ($rows2 -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
$rd = Get-ResearchDebt
Assert ($rd.Total -eq 0 -and (Test-ResearchScopeOk).Ok) "只剩 A／U 補強項與流程標籤（中英）→ 債 0，tier 1 可進 audit／畢業（non-blocking）"
$rows3 = @('# x', '', '## 調查進度', '', '- [x] 01 功能1 `TW_F1` → 01-TW_F1.md', '- [ ] d2-01 新發現 TW_NEW：任務C 反查 PS_X（稽核）', '- [ ] 12 功能12 `TW_F12` -> 12-TW_F12.md')
[System.IO.File]::WriteAllText($cl, ($rows3 -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
$rd = Get-ResearchDebt
Assert ($rd.D -eq 1 -and $rd.Plain -eq 1 -and (-not (Test-ResearchScopeOk).Ok)) "D 項（小寫、含「任務C」字樣）仍算債擋門；ASCII 箭頭列也算原始調查項"
Remove-Item -LiteralPath $cl -Force
Assert ((Get-ResearchDebt).Total -eq 0) "無 checklist → 債 0（相位由「領域不存在一律 research」處理）"
. (Join-Path $repoRoot 'scripts/ps-graduation.ps1')
Assert ($script:GraduationGateVersion -ge 4) "GraduationGateVersion 已 bump（≥4）"
$gdir = Join-Path $dir 'grad-dom'; New-Item -ItemType Directory -Path $gdir -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $gdir '01-TW_X.md'), "# 01`n", (New-Object System.Text.UTF8Encoding($true)))
$oldRc = @{ schemaVersion = $script:GraduationSchemaVersion; gateVersion = 3; tier = 1; domain = 'grad-dom'; contentHash = 'x' } | ConvertTo-Json
[System.IO.File]::WriteAllText((Get-GraduationReceiptPath -DomainDir $gdir), $oldRc, (New-Object System.Text.UTF8Encoding($false)))
$v = Test-GraduationReceipt -DomainDir $gdir -Domain 'grad-dom' -LintScriptPath (Join-Path $repoRoot 'scripts/ps-doc-lint.ps1') -GateScriptPath (Join-Path $repoRoot 'scripts/ps-graduation.ps1') -RequiredTier 1
Assert ((-not $v.Valid) -and $v.Reason -match 'gateVersion') "GateVersion 3 的舊 tier 1 收據 → invalid（gateVersion 不符），領域重新 RUN"
Remove-Item -Recurse -Force $gdir
Reset-Fixture

Write-Host "情境 22：lint [附錄] 形狀守衛——裸 GUID 傾倒抓到、正典表格放行（L103）"
$fxDom = "zz-l103-fixture"
$fxDir = (Join-Path $repoRoot "docs/ps-research/$fxDom")
New-Item -ItemType Directory -Path $fxDir -Force | Out-Null
$secs8 = @('## 相關物件', 'x', '## 功能定位', 'x', '## 畫面與欄位', 'x', '## 行為邏輯', '- **CONFIRMED**：測試（`a.pcode:1`） **證據 ChunkIds**: `3f2a9c1e-7b4d-4e8a-9c6f-1d2e3a4b5c6d`,` 4a3b2c1d-5e6f-4a8b-9c0d-1e2f3a4b5c6d`', '- 註記緊貼：ChunkId 5b4c3d2e-6f7a-4b9c-8d1e-2f3a4b5c6d7e( auditor 覆核) 與 ChunkId: 6c5d4e3f-7a8b-4c9d-8e1f-3a4b5c6d7e8f（auditor 補）', '## 資料流', '| 表 | 操作 |', '|---|---|', '| PS_X | UPDATE |', '## 執行方式', 'x', '## 未解事項（gaps）', '- 無', '')
$goodEv = @('## Evidence 附錄', '| # | 位置 | 說明 | 機器參照 |', '|---|---|---|---|', '| 1 | `a.pcode:1-2` | 測試 | ChunkId `3f2a9c1e-7b4d-4e8a-9c6f-1d2e3a4b5c6d` |')
$badEv = @('## Evidence 附錄', 'chunks 3f2a9c1e-7b4d-4e8a-9c6f-1d2e3a4b5c6d,4a3b2c1d-5e6f-4a8b-9c0d-1e2f3a4b5c6d,5b4c3d2e-6f7a-4b9c-8d1e-2f3a4b5c6d7e')
[System.IO.File]::WriteAllText((Join-Path $fxDir "47-TW_GOOD.md"), ((@('# 47 好檔（TW_GOOD）') + $secs8 + $goodEv) -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
[System.IO.File]::WriteAllText((Join-Path $fxDir "48-TW_BAD.md"), ((@('# 48 壞檔（TW_BAD）') + $secs8 + $badEv) -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
[System.IO.File]::WriteAllText((Join-Path $fxDir "00-overview.md"), "# 總覽`r`n測試 fixture", (New-Object System.Text.UTF8Encoding($true)))
$auditFx = @(
    '# 90 稽核報告', '', '## 記分卡', '', '## 明細', '',
    '| 檔案 | 類型 | 內容 | 處置 |',
    '|---|---|---|---|',
    '| 47-TW_GOOD.md | 證據 | 舊引用 | 換 id aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee → 11111111-2222-4333-8444-555555555555 |',
    '| 48-TW_BAD.md | 證據 | 舊引用 | 換 id 3f2a9c1e-7b4d-4e8a-9c6f-1d2e3a4b5c6d → 99999999-8888-4777-8666-555544443333 |'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $fxDir "90-audit.md"), $auditFx, (New-Object System.Text.UTF8Encoding($true)))
$lintOut = (& (Join-Path $repoRoot "scripts/ps-doc-lint.ps1") -Domain $fxDom *>&1 | Out-String)
Assert ($lintOut -match '\[附錄\] 48-TW_BAD\.md') "壞檔出 [附錄] 工單"
Assert ($lintOut -notmatch '47-TW_GOOD\.md：Evidence 附錄非模板表格') "好檔（正典表格）不觸發"
Assert ($lintOut -match '【附錄】型') "修法說明段有印"
Assert ($lintOut -notmatch 's\*\*:') "行內「**證據 ChunkIds**: 清單」不再誤捕 s**: 當捏造 id（L103）"
Assert ($lintOut -notmatch '疑似捏造') "UUID 緊貼註記括號（兩種寬度）不再冤判捏造（L103）"
Assert ($lintOut -match '陳舊工單壓下：47-TW_GOOD\.md') "[回灌] 舊 id 不在檔＝陳舊，壓下並點名（L103）"
Assert ($lintOut -notmatch '\[回灌\] 47-TW_GOOD') "陳舊 [回灌] 不進工單"
Assert ($lintOut -match '\[回灌\] 48-TW_BAD\.md') "舊 id 還在檔＝正常開單（對照組）"
$lintStats = (& (Join-Path $repoRoot "scripts/ps-doc-lint.ps1") -Domain $fxDom -EvidenceStats *>&1 | Out-String)
Assert ($lintStats -match 'EVIDENCE_ROWS：47-TW_GOOD\.md=1' -and $lintStats -match 'EVIDENCE_ROWS：48-TW_BAD\.md=0') "-EvidenceStats 逐檔列數正確（表格 1 列／裸傾倒 0 列）"
Assert ($lintStats -match 'EVIDENCE_ROWS_SUMMARY：檔數=2 最大=1') "-EvidenceStats 摘要行"
$auditUa = @('# 稽核報告','','> 稽核輪次：1','','## 總覽記分卡','| 檔案 | 證據 PASS | FAIL | UNVERIFIABLE | Claim VERIFIED | DISPUTED | 燈號 |','|---|---|---|---|---|---|---|','| 47-TW_GOOD.md | 1 | 0 | 0 | 0 | 0 | 🟢 |','| 48-TW_BAD.md | 未稽核（BLOCKED：合計不符） | - | - | - | - | ⛔ |','## FAIL / DISPUTED / UNVERIFIABLE 明細','| 檔案 | 類型 | 內容 | 原因 | 處置 |','|---|---|---|---|---|','## 上輪回灌項覆核','- 無上輪','## 完整性（換角度 diff）','- 任務 C 覆蓋：完成 1／共 1 批','## 已回灌 checklist 的行動項','- 無','## 系統性錯誤觀察','- 無') -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $fxDir "90-audit.md"), $auditUa, (New-Object System.Text.UTF8Encoding($true)))
$lintUa = (& (Join-Path $repoRoot "scripts/ps-doc-lint.ps1") -Domain $fxDom -StrictAudit *>&1 | Out-String)
Assert ($lintUa -match '90-audit\.md 記分卡有 1 檔標「未稽核」' -and $lintUa -match 'FAIL：') "lint -StrictAudit：記分卡「未稽核」列＝違規（L107）"
Remove-Item -Recurse -Force $fxDir

Write-Host "情境 28：lint 導覽主張守衛——技術選單冒充路徑／可見性過度宣稱／誠實 gap 不誤報（issue #24）"
$nvDom = "zz-nav24-fixture"
$nvDir = (Join-Path $repoRoot "docs/ps-research/$nvDom")
New-Item -ItemType Directory -Path $nvDir -Force | Out-Null
$nvHead = @('## 相關物件', 'x')
$nvTail = @('## 畫面與欄位', 'x', '## 行為邏輯', '- **CONFIRMED**：測試（`a.pcode:1`）', '## 資料流', '| 表 | 操作 |', '|---|---|', '| PS_X | UPDATE |', '## 執行方式', 'x', '## 未解事項（gaps）', '- 無')
$nvEvMenu = @('## Evidence 附錄', '| # | 位置 | 說明 | 機器參照 |', '|---|---|---|---|', "| 1 | PSMENUITEM（PNLGRPNAME='TW_X'） | 技術選單 | SQL：SELECT MENUNAME, BARNAME, ITEMNAME FROM PSMENUITEM WHERE PNLGRPNAME='TW_X' FETCH FIRST 200 ROWS ONLY |")
$nvEvPortal = @('## Evidence 附錄', '| # | 位置 | 說明 | 機器參照 |', '|---|---|---|---|', "| 1 | PSPRSMDEFN（CREF） | Portal 入口 | SQL：SELECT PORTAL_OBJNAME, PORTAL_LABEL FROM PSPRSMDEFN WHERE PORTAL_REFTYPE='C' FETCH FIRST 200 ROWS ONLY |")
# Case 1：技術選單三欄被串成使用者路徑，證據只有 PSMENUITEM
$nvBad = @('# 41 壞檔（TW_NAV_BAD）') + $nvHead + @('## 功能定位', 'Recruiting > Use > Manage Applicants。人資使用。') + $nvTail + $nvEvMenu
# Case 3：Registry 有入口但無 user context，卻寫「使用者可以從…」
$nvOver = @('# 42 過度宣稱（TW_NAV_OVER）') + $nvHead + @('## 功能定位', '### 導覽入口', 'Recruiting > Applicant Management > Manage Applicants（REGISTRY_DEFINED）。', '使用者可以從此路徑進入。') + $nvTail + $nvEvPortal
# Case 5：parent 斷鏈／未查證＝誠實 gap，且技術選單用 / 分隔——兩條規則都不得誤報
$nvGood = @('# 43 好檔（TW_NAV_GOOD）') + $nvHead + @('## 功能定位', '### 導覽入口', 'Portal Registry 導覽入口：未確認（navigation metadata 尚未查證）。', '### Technical Menu', 'RECRUITING / USE / MANAGE_APPLICANTS') + $nvTail + $nvEvMenu
[System.IO.File]::WriteAllText((Join-Path $nvDir "41-TW_NAV_BAD.md"), ($nvBad -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
[System.IO.File]::WriteAllText((Join-Path $nvDir "42-TW_NAV_OVER.md"), ($nvOver -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
[System.IO.File]::WriteAllText((Join-Path $nvDir "43-TW_NAV_GOOD.md"), ($nvGood -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
# #24 審查補強：多字段英文路徑（嚴格式漏抓）／箭頭流程敘述（假陽性）／AUTHORIZED_FOR_CONTEXT 自證（消音）／
# 有入口列無 gap 行（Case 6）／反序待人工SQL（合法出口）／Technical Menu 段用 >（誠實分段不誤報）
$nvTailGap = @($nvTail | ForEach-Object { if ($_ -eq '- 無') { '- Navigation Collection／Fluid Tile／NavBar 未盤查——不宣稱唯一入口' } else { $_ } })
$nvSpace = @('# 44 多字段路徑（TW_NAV_SPACE）') + $nvHead + @('## 功能定位', 'Workforce Administration > Job Information > Job Data。人資使用。') + $nvTail + $nvEvMenu
$nvFlow = @('# 45 流程敘述（TW_NAV_FLOW）') + $nvHead + @('## 功能定位', '本功能供 HR 使用：員工申請 → 主管審核 → HR 覆核 後入帳。') + $nvTail + $nvEvMenu
$nvAuth = @('# 46 自證消音（TW_NAV_AUTH）') + $nvHead + @('## 功能定位', '### 導覽入口', 'Recruiting > Applicants > Manage（REGISTRY_DEFINED）。', '使用者可以從此路徑進入（可見性：AUTHORIZED_FOR_CONTEXT）。') + $nvTailGap + $nvEvPortal
$nvNavTbl = @('### 導覽入口', '| # | Portal | 入口型 | CREF 物件名 | 導覽入口（Portal Registry 登錄路徑） | 可見性 | 語系／來源 | 證據 |', '|---|---|---|---|---|---|---|---|', '| 1 | EMPLOYEE | PORTAL_REGISTRY | HC_TW_X_CREF | Recruiting > Applicants > Manage | REGISTRY_DEFINED | ENG／BASE | E01.1 |')
$nvOnly = @('# 47 有入口列無 gap（TW_NAV_ONLY）') + $nvHead + @('## 功能定位') + $nvNavTbl + $nvTail + $nvEvPortal
$nvGap = @('# 48 有入口列有 gap（TW_NAV_GAP）') + $nvHead + @('## 功能定位') + $nvNavTbl + $nvTailGap + $nvEvPortal
$nvEvPend = @('## Evidence 附錄', '| # | 位置 | 說明 | 機器參照 |', '|---|---|---|---|', '| 1 | Portal Registry | 導覽入口 | 待人工SQL（PSPRSMDEFN 需 DBA 權限） |')
$nvPend = @('# 49 反序待人工SQL（TW_NAV_PEND）') + $nvHead + @('## 功能定位', '### 導覽入口', '招募 > 應徵者管理 > 維護應徵者（REGISTRY_DEFINED）。') + $nvTailGap + $nvEvPend
$nvTm = @('# 50 技術選單段用 >（TW_NAV_TM）') + $nvHead + @('## 功能定位', '### 導覽入口', 'Portal Registry 導覽入口：未確認（navigation metadata 尚未查證）。', '### Technical Menu', 'Technical Menu（非導覽路徑）：RECRUITING > USE > MANAGE_APPLICANTS') + $nvTail + $nvEvMenu
foreach ($pair in @(@('44-TW_NAV_SPACE.md', $nvSpace), @('45-TW_NAV_FLOW.md', $nvFlow), @('46-TW_NAV_AUTH.md', $nvAuth), @('47-TW_NAV_ONLY.md', $nvOnly), @('48-TW_NAV_GAP.md', $nvGap), @('49-TW_NAV_PEND.md', $nvPend), @('50-TW_NAV_TM.md', $nvTm))) {
    [System.IO.File]::WriteAllText((Join-Path $nvDir $pair[0]), ($pair[1] -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
}
[System.IO.File]::WriteAllText((Join-Path $nvDir "00-overview.md"), "# 總覽`r`n測試 fixture", (New-Object System.Text.UTF8Encoding($true)))
$nvOut = (& (Join-Path $repoRoot "scripts/ps-doc-lint.ps1") -Domain $nvDom *>&1 | Out-String)
Assert ($nvOut -match '41-TW_NAV_BAD\.md：功能定位宣稱導覽路徑') "Case 1：技術選單串成路徑＋無 Portal 證據 → 違規"
Assert ($nvOut -match '\[導覽\] 41-TW_NAV_BAD\.md：TECHNICAL_MENU_AS_NAVIGATION') "Case 1：出 [導覽] 工單"
Assert ($nvOut -notmatch '42-TW_NAV_OVER\.md：功能定位宣稱導覽路徑') "Case 1 對照組：有 PSPRSMDEFN 證據的路徑主張不誤報"
Assert ($nvOut -match '42-TW_NAV_OVER\.md：功能定位宣稱使用者可見性') "Case 3：無 AUTHORIZED_FOR_CONTEXT 的使用者宣稱 → 違規"
Assert ($nvOut -notmatch '43-TW_NAV_GOOD\.md：功能定位') "Case 5：誠實寫未確認＋Technical Menu 用 / 分隔 → 零違規（不誤報）"
Assert ($nvOut -match '【導覽】型') "修法說明段有印"
Assert ($nvOut -match '44-TW_NAV_SPACE\.md：功能定位宣稱導覽路徑') "審查補強：多字段英文路徑（段內含空白）＋無 Portal 證據 → 違規（嚴格式漏抓）"
Assert ($nvOut -notmatch '45-TW_NAV_FLOW\.md：功能定位') "審查補強：箭頭型流程敘述不是導覽主張 → 不誤報"
Assert ($nvOut -match '46-TW_NAV_AUTH\.md：功能定位出現 AUTHORIZED_FOR_CONTEXT' -and $nvOut -match '\[導覽\] 46-TW_NAV_AUTH\.md：[^\r\n]*USER_VISIBILITY_OVERCLAIM') "審查補強：加註 AUTHORIZED_FOR_CONTEXT 不能消音（Case 3）"
Assert ($nvOut -match '47-TW_NAV_ONLY\.md：功能定位 ### 導覽入口 有 1 列但未解事項無' -and $nvOut -match '\[導覽\] 47-TW_NAV_ONLY\.md：SINGLE_PATH_COLLAPSE') "審查補強：有入口列但無 surface 未盤查 gap → SINGLE_PATH_COLLAPSE（Case 6）"
Assert ($nvOut -notmatch '48-TW_NAV_GAP\.md：功能定位') "審查補強：有入口列＋gap 行＋Portal 證據 → 零違規"
Assert ($nvOut -notmatch '49-TW_NAV_PEND\.md：功能定位宣稱導覽路徑') "審查補強：反序「待人工SQL（PSPRSMDEFN…）」是合法出口 → 不誤報"
Assert ($nvOut -notmatch '50-TW_NAV_TM\.md：功能定位') "審查補強：### Technical Menu 段用 > 串（誠實分段）→ 不誤報"
Assert ((Get-OrderFingerprint '3. [導覽] 41-TW_NAV_BAD.md：TECHNICAL_MENU_AS_NAVIGATION＋USER_VISIBILITY_OVERCLAIM') -eq '[導覽] 41-TW_NAV_BAD.md') "審查補強：[導覽] 工單指紋剝 Kinds（狀態不是身分）"
$nvCov = (& (Join-Path $repoRoot "scripts/ps-doc-lint.ps1") -Domain $nvDom -CoverageOnly *>&1 | Out-String)
Assert ($nvCov -match '\[美工／不擋覆蓋畢業\].*功能定位宣稱導覽路徑') "tier 1：導覽類降為警告（不重演 L94 全存量違規）"
Assert ($nvCov -notmatch '\[導覽\] 41-TW_NAV_BAD') "tier 1：導覽工單受 emitPolish 抑制"
Remove-Item -Recurse -Force $nvDir

Remove-Item -Recurse -Force $dir
Write-Host ""
if ($failCount -gt 0) { Write-Host "共 $failCount 個 FAIL" -ForegroundColor Red; exit 1 }
Write-Host "全部情境 PASS" -ForegroundColor Green
