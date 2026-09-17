# scripts/tests/test-knowledge.ps1 — 知識索引（ps-knowledge-lib／ps-knowledge CLI）的功能測試（issue #33）
# 用法：pwsh -NoProfile -File scripts/tests/test-knowledge.ps1   （PowerShell 7 或 5.1 皆可）
# 範圍：合成 fixtures（臨時目錄，結束自刪；無公司資料）：NN 解析（節行號／續篇／PARTIAL／BLOCKED／缺節／CRLF＋BOM／中文路徑）、
#       90-audit 記分卡與明細、checklist 待補、graduation.json／audit-r<N>.done.json 有無、wiki 有效性（verified／draft／stale／
#       reviewed／來源被判 FAIL／過期）、等級表、index.md 無 [[ ]]、原子替換與 tmp 殘留、確定性重建、-Check 三態、CLI exit code、
#       canonical JSON 逃逸、create-only 發布、片段讀回標題比對。
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ErrorActionPreference = 'Stop'
. (Join-Path $repoRoot 'scripts/ps-knowledge-lib.ps1')
. (Join-Path $repoRoot 'scripts/ps-graduation.ps1')
$cli = Join-Path $repoRoot 'scripts/ps-knowledge.ps1'

$failCount = 0
function Assert([bool]$Cond, [string]$Name) {
    if ($Cond) { Write-Host "  PASS：$Name" }
    else { Write-Host "  FAIL：$Name" -ForegroundColor Red; $script:failCount++ }
}
function Write-Utf8([string]$Path, [string[]]$Lines, [bool]$Bom, [string]$Eol = "`n") {
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, ($Lines -join $Eol), (New-Object System.Text.UTF8Encoding($Bom)))
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('kn-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$research = Join-Path $root 'docs/ps-research'
$domA = Join-Path $research '職缺測試'
$domB = Join-Path $research 'zz-b'
$wiki = Join-Path $research 'wiki'
$logs = Join-Path $root 'auto-loop-logs'
$uuid1 = '3f2a9c1e-7b4d-4e8a-9c6f-1d2e3a4b5c6d'
$uuid2 = '9b2f5c1e-4a3d-4f0a-8f21-7e5d0c9a1b2c'
$uuid3 = '11111111-2222-4333-8444-555555555555'

function New-NnLines([string]$Num, [string]$Obj, [string]$Status, [string[]]$ExtraBehavior, [bool]$DropPermission = $false) {
    $l = @(
        "# $Num 功能$Obj（[[$Obj]]）",
        '',
        "> 所屬總覽：[00-overview.md](00-overview.md)　狀態：$Status",
        '> Origin：CUSTOM_PREFIX　搜尋政策：CUSTOM_FIRST　Delivered fallback：未使用',
        '',
        '## 相關物件',
        '',
        '| 物件 | 角色 |',
        '|---|---|',
        "| [[$Obj]] | 主 Component |",
        '| [[PS_JOB]] | 讀取來源 |',
        '| `PS_SHARED_TBL` | 寫入目標 |',
        '',
        '## 功能定位',
        '',
        '誰在用、業務目的。',
        '',
        '### 導覽入口',
        '',
        'Portal Registry 導覽入口：未確認（navigation metadata 尚未查證）',
        '',
        '### Technical Menu',
        '',
        'MENU_A / USE / ITEM_A',
        '',
        '## 畫面與欄位',
        '',
        '| 欄位 | 顯示文字 | 類型 | 選項（label ↔ 儲存值） | 生命狀態 |',
        '|---|---|---|---|---|',
        '| MIL_STATUS | 兵役狀態 | Translate | 免役=E / 服役中=S | E：使用中（資料 3 筆） |',
        '| EFFDT | 生效日 | Date |  |  |',
        '',
        '## 行為邏輯',
        '',
        '- **CONFIRMED**：選 E 時開放免役原因並帶入日期（`a.pcode:12`）'
    )
    $l += $ExtraBehavior
    $l += @(
        '',
        '## 資料流',
        '',
        '| 表 | 操作 | 來源 | 信心 |',
        '|---|---|---|---|',
        '| PS_TW_A | UPDATE | 存檔 PeopleCode | CONFIRMED |',
        '| PS_JOB | READ | 查詢 | INFERRED |',
        '',
        '## 執行方式',
        '',
        '線上操作。'
    )
    if (-not $DropPermission) {
        $l += @('', '## 權限', '', '<!-- 無 -->')
    }
    $l += @(
        '',
        '## 未解事項（gaps）',
        '',
        '- 缺一',
        '- 缺二',
        '',
        '## Evidence 附錄',
        '',
        '| # | 位置 | 說明 | 機器參照 |',
        '|---|---|---|---|',
        "| 1 | ``a.pcode:12-24`` | E 分支 | ChunkId ``$uuid1`` |",
        '| 2 | SQL：`SELECT X FROM PSXLATITEM` | 選項 | keyRows：E=免役 |',
        '| 3 | `PS_PRCSRECUR` | 排程 | 待人工SQL |',
        '| 4 | `b.sqr:1` | 標籤 | ChunkId |'
    )
    return , $l
}

# ── 情境 1：NN 解析（CRLF＋BOM、續篇、PARTIAL／BLOCKED、缺節）────────
Write-Host "情境 1：NN 解析（CRLF＋BOM／續篇／狀態／缺節）"
Write-Utf8 (Join-Path $domA '01-TW_A.md') (New-NnLines '01' 'TW_A' 'COMPLETE' @('- **INFERRED**：核准後回寫', '- **DYNAMIC_RUNTIME**：目標表由設定決定')) $true "`r`n"
Write-Utf8 (Join-Path $domA '01-TW_A-2.md') (New-NnLines '01' 'TW_A' 'COMPLETE' @()) $false
Write-Utf8 (Join-Path $domA '02-TW_B.md') (New-NnLines '02' 'TW_B' 'PARTIAL' @()) $false
Write-Utf8 (Join-Path $domA '03-TW_C.md') (New-NnLines '03' 'TW_C' 'BLOCKED' @() $true) $false
Write-Utf8 (Join-Path $domA '04-TW_D.md') (New-NnLines '04' 'TW_D' 'COMPLETE' @()) $false
Write-Utf8 (Join-Path $domA '05-TW_E.md') (New-NnLines '05' 'TW_E' 'COMPLETE' @()) $false
Write-Utf8 (Join-Path $domA '00-overview.md') @('# 職缺測試 業務總覽', '', '## 功能地圖', '', '| # | 功能 | Component / 物件 | 類型 | Origin | 一句話說明 |', '|---|---|---|---|---|---|', '| 01 | 功能甲 | [[TW_A]] | 線上頁面 | CUSTOM_PREFIX | 說明 |', '| 02 | 功能乙 | [[TW_B]] | 批次 | CUSTOM_PREFIX | 說明 |') $false
Write-Utf8 (Join-Path $domA '90-audit.md') @('# 職缺測試 稽核報告（90-audit）', '', '> 稽核輪次：4　稽核日期：X', '', '## 總覽記分卡', '', '| 檔案 | 證據 PASS | FAIL | UNVERIFIABLE | Claim VERIFIED | DISPUTED | 燈號 |', '|---|---|---|---|---|---|---|', '| 01-TW_A.md | 4 | 0 | 0 | 2 | 0 | 🟢 |', '| 01-TW_A-2.md | 3 | 1 | 0 | 2 | 0 | 🔴 |', '| 02-TW_B.md | 4 | 0 | 0 | 2 | 0 | 🟢 |', '| 04-TW_D.md | 4 | 0 | 1 | 2 | 0 | 🟡 |', '| 05-TW_E.md | 未稽核 | | | | | ⛔ |', '| **合計** | **15** | **1** | **1** | **8** | **0** | 🟢2／🟡1／🔴1 |', '', '## FAIL / DISPUTED / UNVERIFIABLE 明細', '', '| 檔案 | 類型 | 內容 | 原因 | 處置 |', '|---|---|---|---|---|', "| 01-TW_A-2.md | 證據 FAIL | ChunkId $uuid2 | quote 非子字串 | 回灌補查 |", '| 04-TW_D.md | 證據 UNVERIFIABLE | SQL … | 逾時 | 回灌重驗 |', '', '## 完整性（換角度 diff）', '', '- 任務 C 覆蓋：全部完成', '', '| 候選物件 | 型別 | 經由表 | 方向 | origin | 分類 | 理由 |', '|---|---|---|---|---|---|---|', '| PS_SHARED_TBL | RECORD | PS_SHARED_TBL | 讀 | DELIVERED | DEPENDENCY | 共用表 |', '| TW_OUT | COMPONENT | PS_X | 寫 | CUSTOM_PREFIX | OUT_OF_SCOPE | 泛用框架 |', '| TW_ROOT2 | COMPONENT | PS_Y | 寫 | CUSTOM_PREFIX | DOMAIN_ROOT | 命中 alias |') $false
Write-Utf8 (Join-Path $domA 'checklist.md') @('# 職缺測試 調查進度', '', '稽核輪次：4', '', '## 調查進度', '', '- [x] 01 功能甲 `TW_A` → 01-TW_A.md', '- [ ] A4-01 補查 04-TW_D.md：UNVERIFIABLE 1（稽核）', '- [ ] D4-01 新發現 TW_NEW：任務C（稽核）', '- [ ] 06 功能己 `TW_F` → 06-TW_F.md', '', '## Gaps 彙整（隨深查更新）', '', '- x') $true
Write-Utf8 (Join-Path $domA 'log.md') @('## [日期] 動作 | 檔案') $false
$nnA = Get-PsKnNnFacts -LiteralPath (Join-Path $domA '01-TW_A.md') -Domain '職缺測試'
Assert ($nnA.primaryObject -eq 'TW_A' -and $nnA.status -eq 'COMPLETE' -and $nnA.origin -eq 'CUSTOM_PREFIX') "檔頭：主物件／狀態／Origin"
Assert ((@($nnA.sections | Where-Object { $_.level -eq 2 })).Count -eq 9 -and $nnA.missingSections.Count -eq 0 -and $nnA.duplicateSections -eq 0) "九個 ## 節全部命中（含 Evidence 附錄與（gaps）標題正規化）、無重複"
$secDf = Get-PsKnSectionRange -Sections $nnA.sections -Name '資料流'
Assert ($secDf.start -eq 39 -and $secDf.end -eq 45) "節行號＝原檔行號（CRLF＋BOM 不影響）：資料流 39-45"
Assert ((Get-PsKnSectionRange -Sections $nnA.sections -Name '導覽入口' -Level 3).start -eq 18 -and $null -ne (Get-PsKnSectionRange -Sections $nnA.sections -Name 'TechnicalMenu' -Level 3)) "### 子節（導覽入口／Technical Menu）有行號"
Assert ($nnA.relatedObjects.Count -eq 3 -and $nnA.relatedObjects[2].name -eq 'PS_SHARED_TBL' -and $nnA.relatedObjects[1].role -eq '讀取來源') "相關物件表：[[ ]] 與反引號兩種寫法都抽到、角色保留"
Assert ($nnA.fieldRows -eq 2 -and $nnA.behaviorCounts.CONFIRMED -eq 1 -and $nnA.behaviorCounts.INFERRED -eq 1 -and $nnA.behaviorCounts.DYNAMIC_RUNTIME -eq 1) "畫面欄位列數＝2；行為邏輯三種信心各 1"
Assert ($nnA.dataFlow.Count -eq 2 -and $nnA.dataFlow[0].table -eq 'PS_TW_A' -and $nnA.dataFlow[0].op -eq 'UPDATE' -and $nnA.dataFlow[1].confidence -eq 'INFERRED') "資料流列：表／操作／信心"
Assert ($nnA.permissionHollow -and -not $nnA.executionHollow -and $nnA.gaps -eq 2) "權限只有 HTML 註解＝空洞；執行方式非空洞；未解事項 2 條"
Assert ($nnA.evidence.Count -eq 4 -and $nnA.evidenceKinds.CHUNK -eq 1 -and $nnA.evidenceKinds.SQL -eq 1 -and $nnA.evidenceKinds.PENDING_MANUAL -eq 1 -and $nnA.evidenceKinds.UNRESOLVED -eq 1) "Evidence 附錄四列：CHUNK／SQL／待人工SQL／標籤充數＝UNRESOLVED"
Assert ($nnA.evidence[0].ref -eq $uuid1 -and $nnA.evidence[0].n -eq 1) "證據列記完整 36 字元 ChunkId 與 # 欄"
Assert (($nnA.links -contains 'TW_A') -and ($nnA.links -contains 'PS_JOB') -and $nnA.links.Count -eq 2) "全文 wikilink 去重"
$nnC = Get-PsKnNnFacts -LiteralPath (Join-Path $domA '03-TW_C.md') -Domain '職缺測試'
Assert ($nnC.status -eq 'BLOCKED' -and $nnC.missingSections -contains '權限' -and $nnC.permissionHollow) "缺「## 權限」節＝missingSections 記錄、視為空洞"
Assert ((Get-PsKnFileHash -LiteralPath (Join-Path $domA '01-TW_A.md')) -ceq (Get-NormalizedFileHash -LiteralPath (Join-Path $domA '01-TW_A.md'))) "正規化 hash 與 ps-graduation.ps1 的 Get-NormalizedFileHash 一致"
$ov = Get-PsKnOverviewFacts -LiteralPath (Join-Path $domA '00-overview.md')
Assert ($ov.functionMap.Count -eq 2 -and $ov.functionMap[1].object -eq 'TW_B' -and $ov.functionMap[1].type -eq '批次') "功能地圖：物件／類型"

# ── 情境 2：90-audit／checklist／收據 ─────────────────────────────
Write-Host "情境 2：90-audit 記分卡與明細、checklist 待補、收據／done.json"
$au = Get-PsKnAuditFacts -LiteralPath (Join-Path $domA '90-audit.md')
Assert ($au.round -eq 4 -and $au.scorecard.Count -eq 5 -and $au.scorecard['01-TW_A.md'].light -eq 'GREEN' -and $au.scorecard['01-TW_A-2.md'].fail -eq 1 -and $au.scorecard['01-TW_A-2.md'].light -eq 'RED') "記分卡：輪次 4、五檔、燈號與 FAIL 數（合計列略過）"
Assert ($au.scorecard['05-TW_E.md'].light -eq 'NOT_AUDITED') "記分卡「未稽核」列＝NOT_AUDITED"
Assert ($au.details.Count -eq 2 -and $au.failedRefs.Count -eq 1 -and $au.failedRefs[0] -eq $uuid2.ToLowerInvariant()) "明細：兩列；FAIL 列的 ChunkId 進 failedRefs"
Assert ($au.domainGate.Count -eq 3 -and $au.domainGate[0].object -eq 'PS_SHARED_TBL' -and $au.domainGate[0].classification -eq 'DEPENDENCY' -and $au.domainGate[1].classification -eq 'OUT_OF_SCOPE' -and $au.domainGate[2].classification -eq 'DOMAIN_ROOT') "完整性節候選表 → domainGate 三分類"
$cl = Get-PsKnChecklistFacts -LiteralPath (Join-Path $domA 'checklist.md')
Assert ($cl.pendingRepairs.Contains('04-TW_D.md') -and $cl.pendingRepairs['04-TW_D.md'] -eq 1 -and $cl.pendingD -eq 1 -and $cl.pendingPlain -eq 1) "checklist：A 列待補歸戶到檔、D 列與未建調查項各 1"
$rc = Get-PsKnReceiptFacts -DomainDir $domA
Assert (-not $rc.exists -and $rc.tier -eq 0) "無 graduation.json → tier 0"
$done = Get-PsKnAuditDoneFacts -LogDir (Join-Path $logs '職缺測試')
Assert (-not $done.exists) "無 done.json → exists=false"

# ── 情境 3：wiki 解析與有效性 ───────────────────────────────────
Write-Host "情境 3：wiki 解析與有效性（verified／draft／stale／reviewed／來源 FAIL／過期）"
Write-Utf8 (Join-Path $wiki 'TW_A.md') @('---', 'aliases: [功能甲, 甲畫面]', 'type: COMPONENT', 'origin: CUSTOM_PREFIX', 'status: verified', 'confidence: 0.9', 'last_verified: 2026-09-01', 'sources:', "  - $uuid1", 'reviewed: false', '---', '# TW_A', '', '定位。', '', '## Observations', '', '- [結構] 事實一', '- [行為] 事實二', '', '## Relations', '', '- part_of [[職缺測試]]', '- writes_to [[PS_TW_A]]', '', '## Invalidated（作廢紀錄——只追加，不刪除）', '', '- 舊事實') $false
Write-Utf8 (Join-Path $wiki 'PS_JOB.md') @('---', 'aliases:', '  - 職務主檔', 'type: RECORD', 'origin: DELIVERED', 'status: verified', 'confidence: 0.8', 'last_verified: 2026-09-10', "sources: [$uuid2]", 'reviewed: true', '---', '# PS_JOB', '', '## Observations', '', '- [結構] x', '', '## Relations', '', '- read_by [[TW_A]]') $false
Write-Utf8 (Join-Path $wiki 'TW_OLD.md') @('---', 'aliases: []', 'type: PAGE', 'status: draft', 'last_verified: 2026-01-01', 'sources: []', 'reviewed: false', '---', '# TW_OLD', '', '## Observations', '', '- x') $false
Write-Utf8 (Join-Path $wiki 'TW_STALE.md') @('---', 'aliases: []', 'type: AE', 'status: stale', 'last_verified: 2026-09-10', 'sources: []', '---', '# TW_STALE') $false
Write-Utf8 (Join-Path $wiki 'index.md') @('# Entity Wiki 索引', '', '- [[TW_A]] — COMPONENT — 說明') $false
$wA = Get-PsKnWikiFacts -LiteralPath (Join-Path $wiki 'TW_A.md')
Assert ($wA.type -eq 'COMPONENT' -and $wA.status -eq 'verified' -and $wA.aliases.Count -eq 2 -and $wA.aliases[1] -eq '甲畫面' -and $wA.sources.Count -eq 1 -and -not $wA.reviewed) "frontmatter：type／status／aliases（[a, b]）／sources（YAML 清單）／reviewed"
Assert ($wA.observations -eq 2 -and $wA.relations.Count -eq 2 -and $wA.relations[1].type -eq 'writes_to' -and $wA.relations[1].target -eq 'PS_TW_A' -and $wA.invalidated -eq 1) "Observations／typed Relations／Invalidated 計數"
$wJ = Get-PsKnWikiFacts -LiteralPath (Join-Path $wiki 'PS_JOB.md')
Assert ($wJ.aliases.Count -eq 1 -and $wJ.aliases[0] -eq '職務主檔' -and $wJ.reviewed -and $wJ.sources[0] -eq $uuid2) "frontmatter：aliases 的 - 清單形、reviewed true、sources 的 [x] 形"
$asOf = [datetime]'2026-09-16'
Assert ((Get-PsKnWikiEffective -Wiki $wA -FailedRefs @() -AsOf $asOf) -eq 'verified') "有效性：verified＋來源未被判 FAIL＋未過期 → verified"
Assert ((Get-PsKnWikiEffective -Wiki $wJ -FailedRefs @($uuid2.ToLowerInvariant()) -AsOf $asOf) -eq 'STALE_BY_SOURCE') "有效性：來源 ChunkId 在最新稽核明細被判 FAIL → STALE_BY_SOURCE（即使 reviewed）"
Assert ((Get-PsKnWikiEffective -Wiki (Get-PsKnWikiFacts -LiteralPath (Join-Path $wiki 'TW_OLD.md')) -FailedRefs @() -AsOf $asOf) -eq 'EXPIRED') "有效性：last_verified 超過 90 天 → EXPIRED"
Assert ((Get-PsKnWikiEffective -Wiki (Get-PsKnWikiFacts -LiteralPath (Join-Path $wiki 'TW_STALE.md')) -FailedRefs @() -AsOf $asOf) -eq 'stale') "有效性：frontmatter stale → stale"

# ── 情境 4：建索引：等級表、物件表、wiki 引用、index.md 形狀 ────────
Write-Host "情境 4：Build／Publish：等級、物件、wiki 引用、index.md 形狀"
Write-Utf8 (Join-Path $domB '07-TW_G.md') (New-NnLines '07' 'TW_G' 'COMPLETE' @()) $false
Write-Utf8 (Join-Path $domB '00-overview.md') @('# zz-b 業務總覽', '', '## 功能地圖', '', '| # | 功能 | Component / 物件 | 類型 | Origin | 一句話說明 |', '|---|---|---|---|---|---|') $false
New-Item -ItemType Directory -Path (Join-Path $research 'knowledge') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $research 'supplemental') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $research 'zz-l103-fixture') -Force | Out-Null
$idx = Build-PsKnowledgeIndex -Root $root -AsOf $asOf
Assert ($idx.domains.Count -eq 2 -and $idx.domains[0].domain -eq 'zz-b' -and $idx.domains[1].domain -eq '職缺測試') "領域：保留名（knowledge／supplemental／wiki）與 zz-*-fixture 不算領域；Ordinal 排序"
$byFile = @{}
foreach ($e in $idx.nn) { $byFile[$e.domain + '/' + $e.file] = $e }
Assert ($byFile['職缺測試/01-TW_A.md'].grade -eq 'AUDITED_CLEAN') "等級：COMPLETE＋🟢＋無待補＋無 done.json（unknown 不降級）→ AUDITED_CLEAN"
Assert ($byFile['職缺測試/01-TW_A-2.md'].grade -eq 'AUDITED_ISSUES' -and $byFile['職缺測試/01-TW_A-2.md'].fail -eq 1) "等級：續篇 FAIL 1 → AUDITED_ISSUES"
Assert ($byFile['職缺測試/02-TW_B.md'].grade -eq 'PARTIAL') "等級：檔頭 PARTIAL 優先於稽核燈號"
Assert ($byFile['職缺測試/03-TW_C.md'].grade -eq 'BLOCKED') "等級：檔頭 BLOCKED"
Assert ($byFile['職缺測試/04-TW_D.md'].grade -eq 'AUDITED_ISSUES' -and $byFile['職缺測試/04-TW_D.md'].pendingRepairs -eq 1) "等級：🟡 但有待補 A 列 → AUDITED_ISSUES"
Assert ($byFile['職缺測試/05-TW_E.md'].grade -eq 'UNAUDITED') "等級：記分卡「未稽核」→ UNAUDITED"
Assert ($byFile['zz-b/07-TW_G.md'].grade -eq 'UNAUDITED' -and $byFile['zz-b/07-TW_G.md'].auditRound -eq 0) "等級：領域沒有 90-audit.md → UNAUDITED、輪次 0"
$objA = @($idx.objects | Where-Object { $_.object -eq 'TW_A' })
Assert ($objA.Count -eq 2 -and $objA[0].type -eq 'COMPONENT' -and $objA[0].role -eq '主物件') "物件表：TW_A 在兩個 NN（本篇＋續篇）各一列、類型取自 wiki、角色主物件"
$objJ = @($idx.objects | Where-Object { $_.object -eq 'PS_JOB' -and $_.file -eq '01-TW_A.md' })
Assert ($objJ.Count -eq 1 -and $objJ[0].type -eq 'RECORD' -and $objJ[0].role -eq '讀取來源') "物件表：相關物件表的角色與 wiki 型別"
$objB = @($idx.objects | Where-Object { $_.object -eq 'TW_B' -and $_.role -eq '主物件' })
Assert ($objB.Count -eq 1 -and $objB[0].type -eq '批次') "物件表：無 wiki 時型別取功能地圖"
$wikiA = @($idx.wiki | Where-Object { $_.name -eq 'TW_A' })[0]
Assert ($wikiA.referencedBy.Count -eq 2 -and $wikiA.effective -eq 'verified') "wiki 列：被兩個 NN 引用；有效性 verified"
$wikiJ = @($idx.wiki | Where-Object { $_.name -eq 'PS_JOB' })[0]
Assert ($wikiJ.effective -eq 'STALE_BY_SOURCE') "wiki 列：來源在 90-audit 明細 FAIL → STALE_BY_SOURCE（跨檔）"
$pub = Publish-PsKnowledgeIndex -Root $root -AsOf $asOf
$mdPath = Join-Path $research 'knowledge/index.md'
$jsonPath = Join-Path $research 'knowledge/index.json'
$md = Read-PsKnText -LiteralPath $mdPath
Assert ((Test-Path -LiteralPath $mdPath) -and (Test-Path -LiteralPath $jsonPath) -and $pub.nn -eq 7) "Publish 寫出 index.md 與 index.json（NN 7）"
Assert ($md -notmatch '\[\[') "index.md 不含 [[（不進 lint 的 wikilink 掃描）"
Assert ($md -match '(?m)^\| 職缺測試 \| 01-TW_A\.md \| TW_A \| 否 \| AUDITED_CLEAN \| COMPLETE \| 第4輪🟢 \| 相關物件@6/8;功能定位@14/12;畫面與欄位@26/7;行為邏輯@33/6;資料流@39/7;執行方式@46/4;權限@50/4;未解事項@54/5;Evidence 附錄@59/8;導覽入口@18/4;TechnicalMenu@22/4 \| 4 \| 2 \| 0 \| [0-9A-F]{8} \|') "index.md NN 列：等級／稽核／節@offset/limit（Evidence 附錄用實際標題名）一列一筆可 grep"
Assert ($md -match '(?m)^\| 職缺測試 \| 03-TW_C\.md \| TW_C \| 否 \| BLOCKED \| BLOCKED \| 無 \| [^|]*權限@缺[^|]* \|') "index.md NN 列：缺節寫 @缺；沒有記分卡列＝稽核「無」"
Assert ($md -match '(?m)^\| 職缺測試 \| 01-TW_A-2\.md \| TW_A \| 是 \|' -and $md -notmatch 'TW_A（續篇）') "index.md NN 列：主物件欄保持純物件名（cell 錨定可命中）、續篇另欄標「是」"
$omd = Read-PsKnText -LiteralPath (Join-Path $research 'knowledge/objects.md')
Assert ($omd -match '(?m)^\| PS_JOB \| RECORD \|  \| 7 \| zz-b/07-TW_G\.md（讀取來源）、職缺測試/01-TW_A-2\.md（讀取來源）、職缺測試/01-TW_A\.md（讀取來源）') "objects.md 物件列：一物件一列彙總、引用數與角色"
Assert ($omd -match '(?m)^\| TW_A \| COMPONENT \| 職缺測試/01-TW_A-2\.md、職缺測試/01-TW_A\.md \| 0 \|' -and $omd -notmatch '\[\[') "objects.md 物件列：主物件於（本篇＋續篇）；不含 [["
$posW = $md.IndexOf('## Wiki'); $posN = $md.IndexOf('## NN')
Assert ($posW -gt 0 -and $posW -lt $posN -and $md.IndexOf('## 物件') -lt 0) "index.md 表序 Wiki → NN；物件表不在 index.md（hub 物件不會吃掉 grep 上限）"
Assert ($md -match '(?m)^\| PS_JOB \| RECORD \| verified \| STALE_BY_SOURCE \| 是 \| 2026-09-10 \| 1 \| 7 \| 職務主檔 \|') "index.md Wiki 列：有效性／人工／aliases"
Assert ($md -match '(?m)^\| 職缺測試 \| 6 \| 4 \| 1 \| 2 \| 無 \|') "index.md 領域列：NN 數／輪次／待補／未建（D＋調查項）／tier"
$bytes = [System.IO.File]::ReadAllBytes($jsonPath)
Assert (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) "index.json 無 BOM"
$parsed = Read-PsKnText -LiteralPath $jsonPath | ConvertFrom-Json
Assert ($parsed.schemaVersion -eq 1 -and $parsed.nn.Count -eq 7 -and $parsed.generation -ceq $idx.generation) "index.json 可用 ConvertFrom-Json 讀回，世代一致"

# ── 情境 5：確定性、-Check 三態、原子替換、tmp 殘留 ─────────────────
Write-Host "情境 5：確定性重建、-Check、原子替換、tmp 殘留、收據／done.json 影響"
$md1 = Read-PsKnText -LiteralPath $mdPath
[void](Publish-PsKnowledgeIndex -Root $root -AsOf $asOf)
$md2 = Read-PsKnText -LiteralPath $mdPath
Assert ($md1 -ceq $md2) "同輸入重建 index.md byte 相同（builtAt 固定時）"
$chk = Test-PsKnowledgeIndex -Root $root
Assert ($chk.State -eq 'CURRENT') "-Check：CURRENT"
[System.IO.File]::WriteAllText((Join-Path $research ('knowledge/index.md.tmp-' + ('a' * 32))), 'garbage', (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::SetLastWriteTimeUtc((Join-Path $research ('knowledge/index.md.tmp-' + ('a' * 32))), [datetime]::UtcNow.AddMinutes(-30))
[System.IO.File]::WriteAllText((Join-Path $research ('knowledge/index.md.tmp-' + ('b' * 32))), 'fresh', (New-Object System.Text.UTF8Encoding($false)))
[void](Publish-PsKnowledgeIndex -Root $root -AsOf $asOf)
$tmps = @(Get-ChildItem -LiteralPath (Join-Path $research 'knowledge') -File -Force | Where-Object { $_.Name -match '\.tmp-' })
Assert ($tmps.Count -eq 1 -and $tmps[0].Name -match 'b{32}$') "Publish 只清超過 10 分鐘的 tmp 殘留（別的行程正在寫的新 tmp 不動）"
Remove-Item -LiteralPath $tmps[0].FullName -Force
[System.IO.File]::AppendAllText((Join-Path $domA '04-TW_D.md'), "`n- 補一行`n")
$chk = Test-PsKnowledgeIndex -Root $root
Assert ($chk.State -eq 'STALE' -and $chk.Reason -match '已修改：職缺測試/04-TW_D\.md') "-Check：NN 改了 → STALE 並點名檔案"
[void](Publish-PsKnowledgeIndex -Root $root -AsOf $asOf)
# graduation.json（單機）＋ done.json：tier 與稽核後是否改過
$gradFiles = [ordered]@{}
foreach ($f in @('00-overview.md', '01-TW_A-2.md', '01-TW_A.md', '02-TW_B.md', '03-TW_C.md', '04-TW_D.md', '05-TW_E.md', '90-audit.md', 'checklist.md')) { $gradFiles[$f] = Get-PsKnFileHash -LiteralPath (Join-Path $domA $f) }
$gradFiles['01-TW_A-2.md'] = 'DEADBEEF'
$grad = [ordered]@{ schemaVersion = 2; gateVersion = 4; tier = 1; domain = '職缺測試'; contentHash = 'X'; files = $gradFiles }
[System.IO.File]::WriteAllText((Join-Path $domA 'graduation.json'), (ConvertTo-PsKnJson -Value $grad), (New-Object System.Text.UTF8Encoding($false)))
$doneFiles = [ordered]@{}
$doneFiles['01-TW_A.md'] = [ordered]@{ hash = (Get-PsKnFileHash -LiteralPath (Join-Path $domA '01-TW_A.md')); status = 'DONE' }
$doneFiles['04-TW_D.md'] = [ordered]@{ hash = 'OLDHASH'; status = 'DONE' }
$doneObj = [ordered]@{ round = 4; files = $doneFiles }
New-Item -ItemType Directory -Path (Join-Path $logs '職缺測試') -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $logs '職缺測試/audit-r3.done.json'), '{"round":3,"files":{}}', (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $logs '職缺測試/audit-r4.done.json'), (ConvertTo-PsKnJson -Value $doneObj), (New-Object System.Text.UTF8Encoding($false)))
$chk = Test-PsKnowledgeIndex -Root $root
Assert ($chk.State -eq 'STALE') "-Check：收據／done.json 出現也算輸入變動 → STALE"
$doneDom = Get-PsKnAuditDoneFacts -LogDir (Join-Path $logs '職缺測試') -DomainDir $domA
Assert ($doneDom.exists -and $doneDom.source -eq 'logs' -and $doneDom.round -eq 4) "done：領域目錄沒有 audit-done.json → 退到 auto-loop-logs 取最大輪次"
[System.IO.File]::WriteAllText((Join-Path $domA 'audit-done.json'), '{"round":5,"files":{"01-TW_A.md":{"hash":"ZZZ","status":"DONE"}}}', (New-Object System.Text.UTF8Encoding($false)))
$doneDom = Get-PsKnAuditDoneFacts -LogDir (Join-Path $logs '職缺測試') -DomainDir $domA
Assert ($doneDom.source -eq 'domain' -and $doneDom.round -eq 5 -and $doneDom.files['01-TW_A.md'] -eq 'ZZZ') "done：領域目錄的 audit-done.json（進內部 git）優先"
Remove-Item -LiteralPath (Join-Path $domA 'audit-done.json') -Force
$idx2 = Build-PsKnowledgeIndex -Root $root -AsOf $asOf
$by2 = @{}
foreach ($e in $idx2.nn) { $by2[$e.file] = $e }
Assert ($by2['01-TW_A.md'].receiptTier -eq 1 -and -not $by2['01-TW_A.md'].receiptStale -and $by2['01-TW_A.md'].hashSinceAudit -eq 'same' -and $by2['01-TW_A.md'].grade -eq 'AUDITED_CLEAN') "收據 hash 相同 → tier 1；done.json 同 hash → same → 仍 AUDITED_CLEAN"
Assert ($by2['01-TW_A-2.md'].receiptTier -eq 0 -and $by2['01-TW_A-2.md'].receiptStale) "收據 hash 不同 → tier 0、receiptStale"
Assert ($by2['04-TW_D.md'].hashSinceAudit -eq 'changed' -and $by2['04-TW_D.md'].grade -eq 'AUDITED_ISSUES') "done.json（取最大輪次）hash 不同 → 稽核後已改 → AUDITED_ISSUES"
$dObj = @($idx2.domains | Where-Object { $_.domain -eq '職缺測試' })[0]
Assert ($dObj.receiptTier -eq 1 -and $dObj.receiptExists) "領域列：tier（本機）"

# ── 情境 6：CLI（exit code、-Find、-Slice）、片段讀回標題 ─────────────
Write-Host "情境 6：CLI exit code／-Find／-Slice；片段第一行＝節標題"
$o = (& $cli -Root $root -Check *>&1 | Out-String); $ec = $LASTEXITCODE
Assert ($ec -eq 1 -and $o -match 'KNOWLEDGE_CHECK：STALE' -and $o -match '(?m)^結論代號：KNOW1-2-02-\d+\s*$' -and $o -notmatch '(?m)^結論代號：.*(\.md|/)') "CLI -Check STALE → exit 1；結論碼只帶變動檔數（檔名不出）"
$o = (& $cli -Root $root -Rebuild *>&1 | Out-String); $ec = $LASTEXITCODE
Assert ($ec -eq 0 -and $o -match 'KNOWLEDGE：generation=[0-9A-F]{16} domains=2 nn=7' -and $o -match '(?m)^結論代號：KNOW1-1-01\s*$') "CLI -Rebuild → exit 0、KNOWLEDGE 行、結論碼"
$o = (& $cli -Root $root -Check *>&1 | Out-String); $ec = $LASTEXITCODE
Assert ($ec -eq 0 -and $o -match 'CURRENT' -and $o -match '(?m)^結論代號：KNOW1-2-01\s*$') "CLI -Check CURRENT → exit 0、結論碼"
$o = (& $cli -Root $root -Find '甲畫面' *>&1 | Out-String); $ec = $LASTEXITCODE
Assert ($ec -eq 0 -and $o -match 'wiki：docs/ps-research/wiki/TW_A\.md' -and $o -match 'FIND：甲畫面｜nn=0 objects=0 wiki=1') "CLI -Find 以 alias 命中 wiki"
$o = (& $cli -Root $root -Find 'TW_A' *>&1 | Out-String); $ec = $LASTEXITCODE
Assert ($ec -eq 0 -and $o -match 'NN：docs/ps-research/職缺測試/01-TW_A\.md｜AUDITED_CLEAN' -and $o -match '資料流@39/7') "CLI -Find 命中 NN 並印節行號"
$o = (& $cli -Root $root -Slice 'docs/ps-research/職缺測試/01-TW_A.md' -Section '資料流' *>&1 | Out-String); $ec = $LASTEXITCODE
Assert ($ec -eq 0 -and $o -match 'SLICE：.*｜資料流｜39-45' -and $o -match '(?m)^## 資料流') "CLI -Slice 印出節（第一行＝## 資料流）"
$sl = Get-PsKnowledgeSlice -LiteralPath (Join-Path $domA '01-TW_A.md') -Section 'Evidence 附錄'
Assert ($null -ne $sl -and $sl.Lines[0] -match '^## Evidence 附錄' -and $sl.End -eq 66) "片段讀回：Evidence 附錄以模板標題寫法查得到、迄行＝檔尾"
$sl3 = Get-PsKnowledgeSlice -LiteralPath (Join-Path $domA '01-TW_A.md') -Section '導覽入口'
Assert ($null -ne $sl3 -and $sl3.Lines[0] -match '^### 導覽入口') "片段讀回：### 子節也查得到"
# 重複標題（大小寫變體與完全重複）：index.json 仍可 ConvertFrom-Json、兩個範圍都在、重複數列在節欄
Write-Utf8 (Join-Path $domA '08-TW_H.md') ((New-NnLines '08' 'TW_H' 'COMPLETE' @()) + @('', '## 未解事項（gaps）', '', '- 第二個未解事項節', '', '### Technical menu', '', 'X / Y / Z')) $false
$nnH = Get-PsKnNnFacts -LiteralPath (Join-Path $domA '08-TW_H.md') -Domain '職缺測試'
Assert ($nnH.duplicateSections -eq 2 -and (@($nnH.sections | Where-Object { $_.name -eq '未解事項' })).Count -eq 2) "重複標題：## 未解事項 兩次＋### Technical menu 大小寫變體 → duplicateSections=2、兩個範圍都保留"
[void](Publish-PsKnowledgeIndex -Root $root -AsOf $asOf)
$idxH = Read-PsKnowledgeIndex -Root $root
$rowH = @($idxH.nn | Where-Object { $_.file -eq '08-TW_H.md' })[0]
Assert ($null -ne $idxH -and $null -ne $rowH -and (@($rowH.sections)).Count -ge 11) "重複標題不會讓 index.json 無法 ConvertFrom-Json（sections 是陣列）"
$mdH = Read-PsKnText -LiteralPath $mdPath
Assert ($mdH -match '(?m)^\| 職缺測試 \| 08-TW_H\.md \|[^\r\n]*重複標題×2') "index.md 節欄標示 重複標題×2"
Remove-Item -LiteralPath (Join-Path $domA '08-TW_H.md') -Force
$o = (& $cli -Root $root -Slice 'docs/ps-research/職缺測試/01-TW_A.md' -Section '不存在的節' *>&1 | Out-String); $ec = $LASTEXITCODE
Assert ($ec -eq 2) "CLI -Slice 找不到節 → exit 2"
$o = (& $cli -Root $root *>&1 | Out-String); $ec = $LASTEXITCODE
Assert ($ec -eq 2 -and $o -match '用法') "CLI 無模式 → exit 2 印用法"
$emptyRoot = Join-Path $root 'empty'
New-Item -ItemType Directory -Path (Join-Path $emptyRoot 'docs/ps-research') -Force | Out-Null
$o = (& $cli -Root $emptyRoot -Check *>&1 | Out-String); $ec = $LASTEXITCODE
Assert ($ec -eq 2 -and $o -match 'MISSING' -and $o -match '(?m)^結論代號：KNOW1-2-03\s*$') "CLI -Check 無索引 → MISSING exit 2、結論碼"
$allCodes = [regex]::Matches($o, '(?m)^結論代號：(.+)$')
Assert ($allCodes.Count -eq 1 -and $allCodes[0].Groups[1].Value -match '^(KNOW|SUPP|SPEC)1-\d-\d\d(-\d+)?$') "每次 CLI 只印一行結論碼、形狀固定"

# ── 情境 7：canonical JSON、create-only 發布 ─────────────────────
Write-Host "情境 7：canonical JSON 逃逸與 create-only"
$j = ConvertTo-PsKnJson -Value ([ordered]@{ a = 'x"y\z<>''' + [char]0x2028 + "`n"; b = @(1, $true, $null, 2.5); c = [ordered]@{}; d = @() })
Assert ($j -match '"a": "x\\"y\\\\z<>' -and $j -match '\\u2028\\n"' -and $j -match '"b": \[\s+1,\s+true,\s+null,\s+2\.5\s+\]' -and $j -match '"c": \{\}' -and $j -match '"d": \[\]') "canonical JSON：引號／反斜線／U+2028／換行逃逸；< > ' 原樣；bool／null／小數；空物件與空陣列"
$k1 = ConvertTo-PsKnJson -Value (@{ zeta = 1; alpha = @(@{ b = 1; a = 2 }); mid = 'x' }) -SortKeys
$k2 = ConvertTo-PsKnJson -Value ([ordered]@{ mid = 'x'; alpha = @([ordered]@{ a = 2; b = 1 }); zeta = 1 }) -SortKeys
$k3 = ConvertTo-PsKnJson -Value ($k1 | ConvertFrom-Json) -SortKeys
Assert ($k1 -ceq $k2 -and $k2 -ceq $k3 -and $k1 -match '"alpha": \[[\s\S]*"a": 2,[\s\S]*"b": 1[\s\S]*"mid": "x",[\s\S]*"zeta": 1') "-SortKeys：@{}／[ordered]／ConvertFrom-Json 回讀 三者序列化 byte 相同、逐層排序"
$utc = New-Object System.DateTime(2026, 9, 16, 8, 0, 0, [System.DateTimeKind]::Utc)
Assert ((ConvertTo-PsKnJson -Value ([ordered]@{ d = [double]0.5 })) -match '"d": 0\.5' -and (Get-PsKnUtcStamp -At $utc) -eq '2026-09-16T08:00:00Z' -and (Get-PsKnDateKey -At $utc) -eq '20260916' -and (New-PsKnRandomHex -Chars 12) -match '^[0-9a-f]{12}$') "小數 InvariantCulture；UTC 時間戳／日期鍵格式固定；12 hex 隨機"
$back = $j | ConvertFrom-Json
Assert ($back.a -eq ('x"y\z<>''' + [char]0x2028 + "`n") -and $back.b.Count -eq 4) "canonical JSON 可被 ConvertFrom-Json 回讀"
$co = Join-Path $root 'co/req.json'
Assert ((Write-PsKnCreateOnlyText -LiteralPath $co -Text '{"a":1}') -eq $true) "create-only：第一次寫成功"
Assert ((Write-PsKnCreateOnlyText -LiteralPath $co -Text '{"a":2}') -eq $false -and (Read-PsKnText -LiteralPath $co) -eq '{"a":1}') "create-only：第二次不覆寫、回 false、內容不變"
Assert (@(Get-ChildItem -LiteralPath (Join-Path $root 'co') -File -Force | Where-Object { $_.Name -match '\.tmp-' }).Count -eq 0) "create-only：失敗時 tmp 已清"
$dtJson = ConvertTo-PsKnJson -Value ([ordered]@{ t = [datetime]::new(2026, 9, 16, 8, 0, 0, [System.DateTimeKind]::Utc) })
Assert ($dtJson -match '"t": "2026-09-16T08:00:00Z"') "canonical JSON：DateTime（PS 7 ConvertFrom-Json 會把 ISO 字串轉成 DateTime）回寫成 UTC ISO 字串"
$adjPath = Join-Path $root 'adjacent.md'
Write-Utf8 $adjPath @('# 09 x（[[TW_H]]）', '', '## 執行方式', '## 權限', '## 未解事項（gaps）', '', '- b') $false
$adj = Get-PsKnNnFacts -LiteralPath $adjPath -Domain 'x'
Assert ($adj.executionHollow -and $adj.permissionHollow -and $adj.gaps -eq 1) "標題緊接下一標題（無內文）＝空洞；不會把下一標題當內文"
$viaText = Get-PsKnNnFacts -LiteralPath $adjPath -Domain 'x' -Text (Read-PsKnText -LiteralPath $adjPath)
Assert ($viaText.hash -ceq $adj.hash -and $viaText.sections.Count -eq $adj.sections.Count) "Get-PsKnNnFacts -Text：以已讀入的內容解析，結果與讀檔相同"

Remove-Item -Recurse -Force $root
Write-Host ""
if ($failCount -gt 0) { Write-Host "共 $failCount 個 FAIL" -ForegroundColor Red; exit 1 }
Write-Host "全部情境 PASS" -ForegroundColor Green
