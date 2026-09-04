# scripts/tests/test-contract.ps1 — Legacy Contract（issue #17 Phase 1）外環的功能測試
# 用法：pwsh -NoProfile -File scripts/tests/test-contract.ps1   （PowerShell 7 或 5.1 皆可）
# 範圍：值域／canonical JSON／NN 抽取／fragment 不變量／證據 token E<nn>.<n>／stable ID／merge 交叉引用／approvals／
#       verify 單位收據（OBJ／FLD／RQ）／currentSchema 守衛／控制項分頁與容量事件／render parity／G1～G18 聚合／CLI exit code。
# 情境 K9～K11 會在 docs/ps-research/zz-contract-fixture 建臨時領域跑真 CLI（ps-contract.ps1），結束自刪。不需模型、不需 Oracle。
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ErrorActionPreference = 'Stop'
. (Join-Path $repoRoot 'scripts/ps-contract-lib.ps1')
$vocabPath = Join-Path $repoRoot '.opencode/peoplesoft/legacy-contract-vocabulary.md'
$cliPath = Join-Path $repoRoot 'scripts/ps-contract.ps1'
$fixtureDomain = 'zz-contract-fixture'
$fixtureDir = Join-Path $repoRoot (Join-Path 'docs' (Join-Path 'ps-research' $fixtureDomain))

$failCount = 0
function Assert([bool]$Cond, [string]$Name) {
    if ($Cond) { Write-Host "  PASS：$Name" -ForegroundColor Green }
    else { Write-Host "  FAIL：$Name" -ForegroundColor Red; $script:failCount++ }
}

function Write-Fixture([string]$Rel, [string]$Text) {
    $p = Join-Path $fixtureDir $Rel
    Write-CtText -LiteralPath $p -Text ($Text -replace "`r?`n", "`r`n") -Bom
    return $p
}

$nnText = @'
# 03 兵役資料維護（[[TW_MIL001]]）

> 所屬總覽：[00-overview.md](00-overview.md)　狀態：COMPLETE
> Origin：CUSTOM_PREFIX　搜尋政策：CUSTOM_ONLY_ROOTS　Delivered fallback：未使用

## 相關物件

| 物件 | 角色 |
|---|---|
| [[TW_MIL001]] | 主 Component |

## 功能定位

### 導覽入口

人事 > 兵役 > 兵役資料維護（REGISTRY_DEFINED；PSPRSMDEFN 待人工SQL）。

### Technical Menu

RECRUITING / USE / TW_MIL001

## 畫面與欄位

| 欄位 | 顯示文字 | 類型 | 選項（label ↔ 儲存值） | 生命狀態 |
|---|---|---|---|---|
| MIL_STATUS | 兵役狀態 | Translate | 免役=E / 服役中=S | E：使用中 |
| EXEMPT_RSN | 免役原因 | Edit Box | | |

## 行為邏輯

- **CONFIRMED**：選 E 時開放免役原因並帶入日期（`peoplecode/TW_MIL001/FieldChange.pcode:12-24`）
- **CONFIRMED**：存檔時免役原因空白擋錯（`peoplecode/TW_MIL001/SaveEdit.pcode:3-9`）

## 資料流

| 表 | 操作 | 來源 | 信心 |
|---|---|---|---|
| PS_TW_MILITARY | UPDATE | 存檔 PeopleCode | CONFIRMED |

## 執行方式

線上操作。

## 權限

（無——待查）

## 未解事項（gaps）

- 權限路徑未查

## Evidence 附錄

| # | 位置 | 說明 | 機器參照 |
|---|---|---|---|
| 1 | `peoplecode/TW_MIL001/FieldChange.pcode:12-24` | E 分支條件 | ChunkId `3f2a9c1e-7b4d-4e8a-9c6f-1d2e3a4b5c6d` |
| 2 | `peoplecode/TW_MIL001/SaveEdit.pcode:3-9` | 存檔擋錯 | ChunkId `9b2f5c1e-4a3d-4f0a-8f21-7e5d0c9a1b2c` |
| 3 | SQL：`SELECT FIELDVALUE FROM PSXLATITEM WHERE FIELDNAME='MIL_STATUS' FETCH FIRST 100 ROWS ONLY` | 選項清單 | keyRows：E=免役 |
| 4 | `PS_TW_MILITARY` | 表結構 | 待人工SQL |
'@

# 第二個 NN（多來源 entity 測試用）：也寫 TW_MILITARY，附錄只有 2 列
$nn2Text = @'
# 07 兵役核定（[[TW_MIL003]]）

> 所屬總覽：[00-overview.md](00-overview.md)　狀態：COMPLETE
> Origin：CUSTOM_PREFIX　搜尋政策：CUSTOM_ONLY_ROOTS　Delivered fallback：未使用

## 相關物件

| 物件 | 角色 |
|---|---|
| [[TW_MIL003]] | 主 Component |

## 功能定位

核定。

## 畫面與欄位

| 欄位 | 顯示文字 | 類型 | 選項（label ↔ 儲存值） | 生命狀態 |
|---|---|---|---|---|
| APPR_STATUS | 核定狀態 | Edit Box | | |

## 行為邏輯

- **CONFIRMED**：核定時更新兵役資料（`peoplecode/TW_MIL003/SavePostChange.pcode:1-9`）

## 資料流

| 表 | 操作 | 來源 | 信心 |
|---|---|---|---|
| PS_TW_MILITARY | UPDATE | 核定 PeopleCode | CONFIRMED |

## 執行方式

線上操作。

## 未解事項（gaps）

- 無

## Evidence 附錄

| # | 位置 | 說明 | 機器參照 |
|---|---|---|---|
| 1 | `peoplecode/TW_MIL003/SavePostChange.pcode:1-9` | 核定更新 | ChunkId `1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d` |
| 2 | `PS_TW_MILITARY` | 表結構 | 待人工SQL |
'@

$screenText = @'
## 畫面
| 鍵 | 值 |
|---|---|
| component | TW_MIL001 |
| pages | TW_MIL001_PG1 |
| searchRecord | TW_MIL_SRCH |
| modes | ADD;UPDATE |
| technicalMenu | RECRUITING/USE/TW_MIL001 |
| origin | CUSTOM_PREFIX |
| sourceNn | 03-TW_MIL001.md |

## 控制項
| 頁 | Record.Field | 顯示文字 | 語系 | 控制型 | 選項型 | 選項 | 預設 | 可見 | 可編輯 | 必填 | 證據 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| TW_MIL001_PG1 | TW_MILITARY.MIL_STATUS | 兵役狀態 | ZHT | DROP_DOWN | TRANSLATE_VALUE | 免役=E;服役中=S | UNRESOLVED | YES | YES | YES | E03.3 |
| TW_MIL001_PG1 | TW_MILITARY.EXEMPT_RSN | 免役原因 | ZHT | EDIT_BOX | NONE | NOT_APPLICABLE | UNRESOLVED | DYNAMIC_RUNTIME | YES | DYNAMIC_RUNTIME | E03.1 |

## 狀態
| 目標 Record.Field | 屬性 | 條件 | 觸發事件 | 解析 | 證據 |
|---|---|---|---|---|---|
| TW_MILITARY.EXEMPT_RSN | VISIBLE | MIL_STATUS = 'E' | FIELD_CHANGE | RESOLVED | E03.1 |

## 互動
| 觸發事件 | 條件 | 效果型 | 目標 | 說明 | 證據 |
|---|---|---|---|---|---|
| FIELD_CHANGE | MIL_STATUS = 'E' | SET_VALUE | TW_MILITARY.EXEMPT_DT | 帶入今日 | E03.1 |

## 驗證
| 觸發事件 | 條件 | 訊息型 | 訊息 | 證據 |
|---|---|---|---|---|
| SAVE_EDIT | EXEMPT_RSN 空白 | ERROR | 20001,5 | E03.2 |

## 導覽
| 來源 | 目標 | 型 | 入口型 | 可見性 | 證據 |
|---|---|---|---|---|---|
| HC_TW_MIL_CREF | TW_MIL001 | MENU_ENTRY | PORTAL_REGISTRY | REGISTRY_DEFINED | UNRESOLVED |
| HC_TW_MIL_LINK | TW_MIL001 | MENU_ENTRY | CREF_LINK | REGISTRY_DEFINED | UNRESOLVED |

## 業務操作
| 操作鍵 | 觸發 | 模式 | 說明 | 寫入 | 證據 |
|---|---|---|---|---|---|
| SAVE | SAVE_POST_CHANGE | UPDATE | 存檔兵役資料 | TW_MILITARY:UPDATE | E03.2 |

## 權限
| Permission List | Role | 人數 | Search Record | 證據 |
|---|---|---|---|---|
| UNRESOLVED | UNRESOLVED | UNRESOLVED | UNRESOLVED | UNRESOLVED |

## 查詢證據
| 用途 | SQL | 關鍵列 |
|---|---|---|
| NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE |
'@

$entityText = @'
## 實體
| 鍵 | 值 |
|---|---|
| record | TW_MILITARY |
| businessMeaning | 員工兵役資料 |
| storageKind | SQL_TABLE |
| physicalObject | PS_TW_MILITARY |
| origin | CUSTOM_PREFIX |
| domainGate | DOMAIN_ROOT |
| sourceNn | 03-TW_MIL001.md |

## 欄位
| Field | Column | 型別 | 長度 | 鍵 | 必填 | 選項來源 | 證據 |
|---|---|---|---|---|---|---|---|
| EMPLID | EMPLID | CHAR | 11 | K | YES | PROMPT:PERSON | E03.4 |
| EFFDT | EFFDT | DATE | UNRESOLVED | K | YES | NONE | E03.4 |
| MIL_STATUS | MIL_STATUS | CHAR | 1 | N | YES | XLAT | E03.3 |

## 鍵
| 鍵 | 值 |
|---|---|
| psKeys | EMPLID;EFFDT |
| businessKey | EMPLID |
| physicalUniqueKey | UNRESOLVED |
| parentRecord | PERSON |
| rowIdentity | EMPLID+EFFDT 現行列 |

## 生效日
| 鍵 | 值 |
|---|---|
| effdtRule | EFFDT_ONLY |
| asOf | SYSDATE |
| selection | MAX_EFFDT_LE_ASOF |
| activeOnly | NO |

## 讀取語意
| 型 | 內容 | 證據 |
|---|---|---|
| SOURCE | PS_TW_MILITARY | E03.4 |
| LOOKUP | MIL_STATUS → PSXLATITEM(ZHT) | E03.3 |

## 參考查詢
| 用途 | SQL | 關鍵列 | 狀態 |
|---|---|---|---|
| 現行有效列 | SELECT EMPLID, EFFDT FROM PS_TW_MILITARY A WHERE A.EFFDT <= SYSDATE FETCH FIRST 200 ROWS ONLY | NOT_APPLICABLE | PENDING |

## 寫入
| 操作鍵 | 操作 | 列選擇 | 變更欄位 | 伴隨效果 | 證據 |
|---|---|---|---|---|---|
| SAVE | UPDATE | EMPLID+EFFDT 現行列 | MIL_STATUS;EXEMPT_RSN | NOT_APPLICABLE | E03.2 |

## 存取策略
| 鍵 | 值 |
|---|---|
| read | DIRECT_DB_READ |
| write | PS_MEDIATED_WRITE |
| approvalRef | NOT_APPLICABLE |
'@

$rqSql = 'SELECT EMPLID, EFFDT FROM PS_TW_MILITARY A WHERE A.EFFDT <= SYSDATE FETCH FIRST 200 ROWS ONLY'

function Reset-Fixture {
    if (Test-Path -LiteralPath $fixtureDir) { Remove-Item -LiteralPath $fixtureDir -Recurse -Force }
    New-Item -ItemType Directory -Path (Join-Path $fixtureDir 'contract-parts') -Force | Out-Null
    $null = Write-Fixture '03-TW_MIL001.md' $nnText
    $null = Write-Fixture '00-overview.md' "# 兵役 業務總覽`n`n## 功能地圖`n`n| # | 功能 | Component / 物件 | 類型 | Origin | 一句話說明 |`n|---|---|---|---|---|---|`n| 03 | 兵役資料維護 | [[TW_MIL001]] | 線上頁面 | CUSTOM_PREFIX | 維護 |`n"
    $null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' $screenText
    $null = Write-Fixture 'contract-parts/entity-TW_MILITARY.md' $entityText
}

function Get-Facts {
    $m = @{}
    foreach ($f in (Get-CtNnFiles -DomainDir $fixtureDir)) { $m[$f.Name] = Get-CtNnFacts -LiteralPath $f.FullName }
    return $m
}

function Read-Frag([string]$Name, [string]$Kind, $Facts, [string[]]$Expected = @()) {
    return (Read-CtFragment -LiteralPath (Join-Path $fixtureDir (Join-Path 'contract-parts' $Name)) -Kind $Kind -Vocab $vocab -NnFactsMap $Facts -ExpectedFields $Expected)
}

function Get-Merged($Facts, [bool]$SchemaKnown = $false, [string[]]$Extra = @()) {
    $frs = @()
    $frs += , (Read-Frag 'entity-TW_MILITARY.md' 'entity' $Facts)
    $frs += , (Read-Frag 'screen-TW_MIL001.md' 'screen' $Facts)
    foreach ($x in $Extra) { $k = 'entity'; if ($x -match '-p\d+\.md$') { $k = 'screenpage' } elseif ($x -like 'screen-*') { $k = 'screen' }; $frs += , (Read-Frag $x $k $Facts) }
    $approvals = @(Read-CtApprovals -LiteralPath (Join-Path $fixtureDir 'contract/approvals.md'))
    $draft = Merge-CtContract -Domain $fixtureDomain -Fragments $frs -NnFactsMap $Facts -Approvals $approvals -VerifyReceipts @{} -Vocab $vocab -SchemaKnown $false
    $verify = @{}
    if ($SchemaKnown) { $verify = Read-CtVerifyReceipts -PartsDir (Join-Path $fixtureDir 'contract-parts') -Vocab $vocab -Contract $draft -FieldPageSize 10 }
    return (Merge-CtContract -Domain $fixtureDomain -Fragments $frs -NnFactsMap $Facts -Approvals $approvals -VerifyReceipts $verify -Vocab $vocab -SchemaKnown $SchemaKnown)
}

$vocab = Get-CtVocabulary -LiteralPath $vocabPath
Reset-Fixture

Write-Host "情境 K1：值域檔解析——值域、黑名單、UNRESOLVED 出口、無 PARTIAL"
Assert ($vocab.Version -eq 2) "vocabularyVersion=2"
Assert ($vocab.Enums.Count -ge 32) "值域數 ≥32（實際 $($vocab.Enums.Count)）"
Assert ($vocab.Blacklist -contains 'probablyDirectWritable') "黑名單含 probablyDirectWritable"
Assert (Test-CtEnum -Vocab $vocab -EnumName 'storageKind' -Value 'DERIVED_WORK') "storageKind 含 DERIVED_WORK"
Assert (-not (Test-CtEnum -Vocab $vocab -EnumName 'fragmentStatus' -Value 'PARTIAL')) "fragmentStatus 無 PARTIAL（容量由外環分頁決定）"
Assert (Test-CtEnum -Vocab $vocab -EnumName 'verifyQueryState' -Value 'ORACLE_MCP_DOWN') "verifyQueryState 含 ORACLE_MCP_DOWN"

Write-Host "情境 K2：canonical JSON——鍵名 keys／count 不被 PowerShell 屬性劫持、Unicode 原樣、Ordinal 排序"
$j = ConvertTo-CtJson -Value ([ordered]@{ keys = [ordered]@{ a = 1 }; count = 2; s = '中文"q'; arr = @(); n = $null })
Assert ($j -match '"keys": \{' -and $j -match '"count": 2' -and $j -match '中文\\"q' -and $j -match '"arr": \[\]') "含 keys／count 鍵的字典、Unicode、空陣列正確序列化"
$rt = $j | ConvertFrom-Json
Assert ([int]$rt.keys.a -eq 1) "序列化結果可被 ConvertFrom-Json 回讀"
$sorted = Sort-CtOrdinal -Items @('ENT.TW_MIL_HIST', 'ENT.TW_MILITARY', 'ENT.A')
Assert (($sorted -join ',') -eq 'ENT.A,ENT.TW_MILITARY,ENT.TW_MIL_HIST') "Ordinal 排序：底線在字母後（跨機一致）"

Write-Host "情境 K3：NN 確定性抽取——Prefix／Component／欄位列／行為邏輯分類／資料流去 PS_／證據型別"
$facts = Get-Facts
$f = $facts['03-TW_MIL001.md']
Assert ($f.Prefix -eq '03' -and $f.Component -eq 'TW_MIL001') "Prefix=03、Component 由標題 [[ ]] 抽出"
Assert (@($f.FieldRows).Count -eq 2 -and $f.FieldRows[0].Field -eq 'MIL_STATUS') "畫面與欄位 2 列"
Assert ($f.UiStateLineCount -eq 1 -and $f.SaveKeywordCount -eq 1) "行為邏輯：UI 狀態類 1、存檔類 1"
Assert (@($f.DataFlowRows).Count -eq 1 -and $f.DataFlowRows[0].Record -eq 'TW_MILITARY' -and $f.DataFlowRows[0].Op -eq 'UPDATE') "資料流：PS_TW_MILITARY → Record TW_MILITARY／UPDATE"
Assert (-not $f.PermissionDeclared) "權限節「（無——…）」＝未申報內容"
Assert (@($f.EvidenceRows).Count -eq 4 -and $f.EvidenceRows[0].Kind -eq 'CHUNK' -and $f.EvidenceRows[2].Kind -eq 'SQL' -and $f.EvidenceRows[3].Kind -eq 'PENDING_MANUAL') "Evidence 附錄 4 列：CHUNK／CHUNK／SQL／PENDING_MANUAL"
Assert ((Get-CtEvidenceTokens -NnFacts $f) -like 'E03.1=CHUNK*E03.4=PENDING_MANUAL*') "manifest 證據 token 形式 E03.n=Kind"

Write-Host "情境 K4：fragment 不變量——正典通過；表頭差一字／enum 外值／空格／證據越界／舊語法 E5／洩漏／>150 行／自由 token／EXECUTED／DIRECT_DB_WRITE_APPROVED／Derived／DML／省略號"
$ok = Read-Frag 'screen-TW_MIL001.md' 'screen' $facts @('MIL_STATUS', 'EXEMPT_RSN')
Assert ($ok.Invalid.Count -eq 0) "正典 screen fragment 零 INVALID（$($ok.Invalid -join '；')）"
$ok2 = Read-Frag 'entity-TW_MILITARY.md' 'entity' $facts
Assert ($ok2.Invalid.Count -eq 0) "正典 entity fragment 零 INVALID（$($ok2.Invalid -join '；')）"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' ($screenText -replace '\| 頁 \| Record\.Field \|', '| 頁面 | Record.Field |')
Assert (@((Read-Frag 'screen-TW_MIL001.md' 'screen' $facts).Invalid | Where-Object { $_ -like '*表頭與規格不符*' }).Count -gt 0) "表頭差一字 → INVALID"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' ($screenText -replace 'DROP_DOWN \| TRANSLATE_VALUE', 'COMBO | TRANSLATE_VALUE')
Assert (@((Read-Frag 'screen-TW_MIL001.md' 'screen' $facts).Invalid | Where-Object { $_ -like '*不在值域 controlType*' }).Count -gt 0) "enum 外值 COMBO → INVALID"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' ($screenText -replace '\| ZHT \| EDIT_BOX', '|  | EDIT_BOX')
Assert (@((Read-Frag 'screen-TW_MIL001.md' 'screen' $facts).Invalid | Where-Object { $_ -like '*空值*' }).Count -gt 0) "空格 → INVALID"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' ($screenText -replace '\| E03\.2 \|', '| E03.9 |')
Assert (@((Read-Frag 'screen-TW_MIL001.md' 'screen' $facts).Invalid | Where-Object { $_ -like '*E03.9 超出*' }).Count -gt 0) "證據 E03.9 越界（附錄只有 4 列）→ INVALID"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' ($screenText -replace '\| E03\.2 \|', '| E5 |')
Assert (@((Read-Frag 'screen-TW_MIL001.md' 'screen' $facts).Invalid | Where-Object { $_ -like '*不是 E<nn>.<n>*' }).Count -gt 0) "舊語法 E5 → INVALID"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' ($screenText -replace '\| E03\.2 \|', '| E07.1 |')
Assert (@((Read-Frag 'screen-TW_MIL001.md' 'screen' $facts).Invalid | Where-Object { $_ -like '*前綴 07 不在 sourceNn*' }).Count -gt 0) "E07.1 但 sourceNn 無 07 → INVALID"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' ($screenText + "`n{ `"agent`": `"x`", `"findings`": [] }`n")
Assert (@((Read-Frag 'screen-TW_MIL001.md' 'screen' $facts).Invalid | Where-Object { $_ -like '*洩漏*' }).Count -gt 0) "契約 JSON 洩漏 → INVALID"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' ($screenText -replace '帶入今日', '可能帶入今日')
Assert (@((Read-Frag 'screen-TW_MIL001.md' 'screen' $facts).Invalid | Where-Object { $_ -like '*自由 token*' }).Count -gt 0) "自由 token「可能」→ INVALID"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' ($screenText + ("`n" * 120))
$big = Read-Frag 'screen-TW_MIL001.md' 'screen' $facts
Assert (@($big.Invalid | Where-Object { $_ -like '*150 行*' }).Count -gt 0 -and $big.CapacityEvent) ">150 行 → INVALID＋容量事件"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' $screenText
$null = Write-Fixture 'contract-parts/entity-TW_MILITARY.md' ($entityText -replace '\| PENDING \|', '| EXECUTED |')
Assert (@((Read-Frag 'entity-TW_MILITARY.md' 'entity' $facts).Invalid | Where-Object { $_ -like '*由 verify 收據決定*' }).Count -gt 0) "參考查詢寫 EXECUTED → INVALID（外環才准寫）"
$null = Write-Fixture 'contract-parts/entity-TW_MILITARY.md' ($entityText -replace '\| write \| PS_MEDIATED_WRITE \|', '| write | DIRECT_DB_WRITE_APPROVED |')
Assert (@((Read-Frag 'entity-TW_MILITARY.md' 'entity' $facts).Invalid | Where-Object { $_ -like '*DIRECT_DB_WRITE_APPROVED 不得由模型填*' }).Count -gt 0) "模型填 DIRECT_DB_WRITE_APPROVED → INVALID"
$null = Write-Fixture 'contract-parts/entity-TW_MILITARY.md' ($entityText -replace '\| storageKind \| SQL_TABLE \|', '| storageKind | DERIVED_WORK |')
$bad = Read-Frag 'entity-TW_MILITARY.md' 'entity' $facts
Assert (@($bad.Invalid | Where-Object { $_ -like '*physicalObject 必須 NOT_APPLICABLE*' }).Count -gt 0 -and @($bad.Invalid | Where-Object { $_ -like '*不得有寫入效果*' }).Count -gt 0) "DERIVED_WORK 帶實體表＋寫入 → 兩條 INVALID"
$null = Write-Fixture 'contract-parts/entity-TW_MILITARY.md' ($entityText.Replace($rqSql, 'UPDATE PS_TW_MILITARY SET X=1'))
Assert (@((Read-Frag 'entity-TW_MILITARY.md' 'entity' $facts).Invalid | Where-Object { $_ -like '*SELECT-only*' }).Count -gt 0) "參考查詢含 UPDATE → INVALID"
$null = Write-Fixture 'contract-parts/entity-TW_MILITARY.md' ($entityText.Replace($rqSql, 'SELECT … FROM PS_TW_MILITARY FETCH FIRST 10 ROWS ONLY'))
Assert (@((Read-Frag 'entity-TW_MILITARY.md' 'entity' $facts).Invalid | Where-Object { $_ -like '*SELECT-only*' }).Count -gt 0) "參考查詢含省略號 → INVALID"
$null = Write-Fixture 'contract-parts/entity-TW_MILITARY.md' $entityText
Assert ((Test-CtSelectOnly -Sql 'SELECT A FROM B WHERE ROWNUM <= 10') -and -not (Test-CtSelectOnly -Sql 'SELECT A FROM B') -and -not (Test-CtSelectOnly -Sql 'SELECT A FROM B FETCH FIRST 10 ROWS ONLY; DELETE FROM B')) "SELECT-only：ROWNUM 可、無上限不可、分號串接不可"

Write-Host "情境 K5：stable ID——自然鍵派發、列序調換／插入列不改既有 ID、同自然鍵 .2、claimDomain"
$c1 = Get-Merged $facts
$s1 = $c1.screens[0]
Assert ($s1.id -eq 'SCR.TW_MIL001' -and $s1.controls[0].id -eq 'CTL.TW_MIL001.TW_MIL001_PG1.TW_MILITARY.MIL_STATUS') "SCR／CTL ID"
Assert ($s1.states[0].id -eq 'STA.TW_MIL001.TW_MILITARY.EXEMPT_RSN.VISIBLE') "STA ID 含 RECORD.FIELD.PROPERTY"
Assert ($s1.interactions[0].id -eq 'INT.TW_MIL001.FIELD_CHANGE.SET_VALUE.TW_MILITARY.EXEMPT_DT') "INT ID＝事件.效果.目標（非列序）"
Assert ($s1.validations[0].id -eq 'VAL.TW_MIL001.SAVE_EDIT.ERROR.20001_5') "VAL ID＝事件.訊息型.訊息"
Assert ($s1.navigation[0].id -eq 'NAV.TW_MIL001.HC_TW_MIL_CREF.TW_MIL001.MENU_ENTRY.PORTAL_REGISTRY' -and $s1.navigation[1].id -eq 'NAV.TW_MIL001.HC_TW_MIL_LINK.TW_MIL001.MENU_ENTRY.CREF_LINK') "NAV ID＝來源.目標.型.入口型（TARG／LINK 不撞名，#24 Case 2）"
Assert ($s1.navigation[0].entryType -eq 'PORTAL_REGISTRY' -and $s1.navigation[0].visibility -eq 'REGISTRY_DEFINED' -and @($s1.technicalMenu).Count -eq 1 -and @($s1.technicalMenu)[0] -eq 'RECRUITING/USE/TW_MIL001' -and $null -eq $s1.menuPath) "JSON：entryType／visibility 入欄、technicalMenu 陣列、menuPath 已移除（#24）"
Assert ($s1.businessOperations[0].id -eq 'BOP.TW_MIL001.SAVE' -and $s1.persistenceEffects[0].id -eq 'EFF.TW_MIL001.SAVE.TW_MILITARY.UPDATE') "BOP／EFF ID"
$e1 = $c1.dataEntities[0]
Assert ($e1.id -eq 'ENT.TW_MILITARY' -and $e1.fields[0].id -eq 'FLD.TW_MILITARY.EMPLID' -and $e1.readSemantics[0].id -eq 'RDS.TW_MILITARY.SOURCE' -and $e1.readSemantics[1].id -eq 'RDS.TW_MILITARY.LOOKUP') "ENT／FLD／RDS ID（RDS 依型別不依列序）"
Assert ($e1.referenceQueries[0].id -eq 'RQ.TW_MILITARY.1' -and $e1.referenceQueries[0].sqlHash.Length -eq 12) "RQ ID＋12 碼 sqlHash"
Assert ($s1.controls[0].claimDomain -eq 'BEHAVIOR' -and $e1.fields[0].claimDomain -eq 'PERSISTENCE') "claimDomain 依前綴"
$inserted = $screenText -replace '(\| FIELD_CHANGE \| MIL_STATUS = ''E'' \| SET_VALUE)', "| ROW_INIT | NOT_APPLICABLE | SET_DEFAULT | TW_MILITARY.MIL_STATUS | 預設 S | E03.1 |`n`$1"
$inserted = $inserted -replace '(\| HC_TW_MIL_CREF \| TW_MIL001 \| MENU_ENTRY \| PORTAL_REGISTRY \| REGISTRY_DEFINED \| UNRESOLVED \|)', "| TW_MIL001 | TW_MIL002 | TRANSFER | NOT_APPLICABLE | NOT_APPLICABLE | UNRESOLVED |`n`$1"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' $inserted
$c2 = Get-Merged $facts
$oldInt = @($c1.screens[0].interactions | ForEach-Object { $_.id }); $newInt = @($c2.screens[0].interactions | ForEach-Object { $_.id })
$oldNav = @($c1.screens[0].navigation | ForEach-Object { $_.id }); $newNav = @($c2.screens[0].navigation | ForEach-Object { $_.id })
Assert ((@($oldInt | Where-Object { $newInt -notcontains $_ }).Count -eq 0) -and (@($oldNav | Where-Object { $newNav -notcontains $_ }).Count -eq 0) -and $newInt.Count -eq 2 -and $newNav.Count -eq 3) "互動／導覽表首列前插入一列 → 原 ID 一個不變"
$dupRow = $screenText -replace '\| TW_MIL001_PG1 \| TW_MILITARY\.EXEMPT_RSN \| 免役原因 \| ZHT \| EDIT_BOX \| NONE \| NOT_APPLICABLE \| UNRESOLVED \| DYNAMIC_RUNTIME \| YES \| DYNAMIC_RUNTIME \| E03\.1 \|', "| TW_MIL001_PG1 | TW_MILITARY.EXEMPT_RSN | 免役原因 | ZHT | EDIT_BOX | NONE | NOT_APPLICABLE | UNRESOLVED | DYNAMIC_RUNTIME | YES | DYNAMIC_RUNTIME | E03.1 |`n| TW_MIL001_PG1 | TW_MILITARY.EXEMPT_RSN | 免役原因（第二欄位） | ZHT | EDIT_BOX | NONE | NOT_APPLICABLE | UNRESOLVED | YES | YES | NO | E03.1 |"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' $dupRow
$c3 = Get-Merged $facts
Assert (@($c3.screens[0].controls | Where-Object { $_.id -eq 'CTL.TW_MIL001.TW_MIL001_PG1.TW_MILITARY.EXEMPT_RSN.2' }).Count -eq 1) "同自然鍵第二列 → .2"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' $screenText

Assert (@((Read-Frag 'screen-TW_MIL001.md' 'screen' $facts).Invalid).Count -eq 0) "導覽表兩列不同入口型 → 通過不變量（#24 Case 2 多入口）"
$navDup = $screenText -replace '\| HC_TW_MIL_LINK \| TW_MIL001 \| MENU_ENTRY \| CREF_LINK \| REGISTRY_DEFINED \| UNRESOLVED \|', '| HC_TW_MIL_CREF | TW_MIL001 | MENU_ENTRY | PORTAL_REGISTRY | REGISTRY_DEFINED | UNRESOLVED |'
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' $navDup
Assert (@((Read-Frag 'screen-TW_MIL001.md' 'screen' $facts).Invalid | Where-Object { $_ -like '*四元組*' }).Count -gt 0) "同（來源,目標,型,入口型）寫兩列 → INVALID（ID 不退回列序相依）"
$navAuth = $screenText -replace 'REGISTRY_DEFINED', 'AUTHORIZED_FOR_CONTEXT'
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' $navAuth
Assert (@((Read-Frag 'screen-TW_MIL001.md' 'screen' $facts).Invalid | Where-Object { $_ -like '*AUTHORIZED_FOR_CONTEXT*' }).Count -gt 0) "模型填 AUTHORIZED_FOR_CONTEXT → INVALID（#24 Case 3）"
# #24 審查補強：Portal 入口列可見性 NOT_APPLICABLE／來源寫中文標籤／technicalMenu 寫成路徑
$navNa = $screenText -replace '\| HC_TW_MIL_LINK \| TW_MIL001 \| MENU_ENTRY \| CREF_LINK \| REGISTRY_DEFINED \| UNRESOLVED \|', '| HC_TW_MIL_LINK | TW_MIL001 | MENU_ENTRY | CREF_LINK | NOT_APPLICABLE | UNRESOLVED |'
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' $navNa
Assert (@((Read-Frag 'screen-TW_MIL001.md' 'screen' $facts).Invalid | Where-Object { $_ -like '*可見性只能*' }).Count -gt 0) "Portal 入口列可見性 NOT_APPLICABLE → INVALID（沒有主張）"
$navZh = $screenText -replace 'HC_TW_MIL_LINK', '招募入口'
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' $navZh
Assert (@((Read-Frag 'screen-TW_MIL001.md' 'screen' $facts).Invalid | Where-Object { $_ -like '*大寫英數底線*' }).Count -gt 0) "來源欄寫中文標籤 → INVALID（ID 消毒後不撞名）"
$tmPath = $screenText -replace '\| technicalMenu \| RECRUITING/USE/TW_MIL001 \|', '| technicalMenu | 人事 > 兵役 > 兵役資料維護 |'
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' $tmPath
Assert (@((Read-Frag 'screen-TW_MIL001.md' 'screen' $facts).Invalid | Where-Object { $_ -like '*technicalMenu*路徑*' }).Count -gt 0) "technicalMenu 寫成 A > B > C → INVALID（#24 不接受的修法 3）"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' $screenText
Write-Host "情境 K6：證據解引用與交叉引用——E<nn>.<n> 多來源、screen 查詢證據 SQL:<n>、effect 連結、缺 entity、五維"
$c = Get-Merged $facts
$ef = $c.screens[0].persistenceEffects[0]
Assert ($ef.dataEntityId -eq 'ENT.TW_MILITARY' -and $ef.writeSemanticsId -eq 'WRT.TW_MILITARY.SAVE.UPDATE') "effect 連到 entity 與寫入列"
Assert ($c.unresolvedReferences.Count -eq 0) "正典無未解析引用"
$ctl = $c.screens[0].controls
Assert ($ctl[1].evidence[0].kind -eq 'CHUNK' -and $ctl[1].evidence[0].chunkId -eq '3f2a9c1e-7b4d-4e8a-9c6f-1d2e3a4b5c6d' -and $ctl[1].evidence[0].sourceNn -eq '03-TW_MIL001.md') "E03.1 → CHUNK 逐字 ChunkId＋來源檔"
Assert ($ctl[0].evidence[0].kind -eq 'SQL' -and $ctl[0].verification.staticEvidence -eq 'PASS') "E03.3（SELECT 在位置欄）→ SQL、staticEvidence PASS"
Assert ($c.dataEntities[0].fields[0].evidence[0].kind -eq 'PENDING_MANUAL' -and $c.dataEntities[0].fields[0].verification.staticEvidence -eq 'UNRESOLVED') "E03.4 待人工SQL → PENDING_MANUAL、UNRESOLVED"
Assert ($c.dataEntities[0].referenceQueries[0].state -eq 'PENDING' -and $c.dataEntities[0].referenceQueries[0].oracleReadVerification -eq 'NOT_RUN') "RQ 未驗 → PENDING／oracleRead NOT_RUN"
Assert ($c.dataEntities[0].verification.oracleSchemaVerification -eq 'NOT_RUN' -and $c.dataEntities[0].schemaNote -like '*currentSchema 未回填*') "currentSchema 未知 → oracleSchema NOT_RUN（收據不採信）"
# 多來源 entity：E07.2 解到第二檔第 2 列
$null = Write-Fixture '07-TW_MIL003.md' $nn2Text
$facts2 = Get-Facts
$null = Write-Fixture 'contract-parts/entity-TW_MILITARY.md' (($entityText -replace '\| sourceNn \| 03-TW_MIL001\.md \|', '| sourceNn | 03-TW_MIL001.md;07-TW_MIL003.md |') -replace '\| SOURCE \| PS_TW_MILITARY \| E03\.4 \|', '| SOURCE | PS_TW_MILITARY | E07.2 |')
$fr2 = Read-Frag 'entity-TW_MILITARY.md' 'entity' $facts2
Assert ($fr2.Invalid.Count -eq 0) "雙來源 entity 引用 E07.2 → 通過不變量"
$cm = Get-Merged $facts2
$src = @($cm.dataEntities[0].readSemantics | Where-Object { $_.kind -eq 'SOURCE' })[0]
Assert ($src.evidence[0].kind -eq 'PENDING_MANUAL' -and $src.evidence[0].sourceNn -eq '07-TW_MIL003.md') "E07.2 解到 07 檔第 2 列（不是 03 檔）"
$null = Write-Fixture 'contract-parts/entity-TW_MILITARY.md' (($entityText -replace '\| sourceNn \| 03-TW_MIL001\.md \|', '| sourceNn | 03-TW_MIL001.md;07-TW_MIL003.md |') -replace '\| SOURCE \| PS_TW_MILITARY \| E03\.4 \|', '| SOURCE | PS_TW_MILITARY | E07.3 |')
Assert (@((Read-Frag 'entity-TW_MILITARY.md' 'entity' $facts2).Invalid | Where-Object { $_ -like '*E07.3 超出*' }).Count -gt 0) "E07.3 超出 07 檔附錄列數（2）→ INVALID"
Remove-Item -LiteralPath (Join-Path $fixtureDir '07-TW_MIL003.md') -Force
$null = Write-Fixture 'contract-parts/entity-TW_MILITARY.md' $entityText
# screen 查詢證據
$qe = $screenText -replace '\| NOT_APPLICABLE \| NOT_APPLICABLE \| NOT_APPLICABLE \|', "| 導覽入口（cookbook §2k-2 首選三欄） | SELECT PORTAL_NAME, PORTAL_OBJNAME, PORTAL_CREF_USGT, PORTAL_PRNTOBJNAME FROM PSPRSMDEFN WHERE PORTAL_REFTYPE='C' AND UPPER(TRIM(PORTAL_URI_SEG1))='TW_MENU' AND UPPER(TRIM(PORTAL_URI_SEG2))='TW_MIL001' AND UPPER(TRIM(PORTAL_URI_SEG3))='GBL' FETCH FIRST 200 ROWS ONLY | 2 列 |"
$qe = $qe -replace '\| HC_TW_MIL_CREF \| TW_MIL001 \| MENU_ENTRY \| PORTAL_REGISTRY \| REGISTRY_DEFINED \| UNRESOLVED \|', '| HC_TW_MIL_CREF | TW_MIL001 | MENU_ENTRY | PORTAL_REGISTRY | REGISTRY_DEFINED | SQL:1 |'
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' $qe
$frq = Read-Frag 'screen-TW_MIL001.md' 'screen' $facts
Assert ($frq.Invalid.Count -eq 0) "screen 查詢證據 1 列＋導覽引用 SQL:1 → 通過"
$cq = Get-Merged $facts
Assert ($cq.screens[0].navigation[0].verification.staticEvidence -eq 'PASS' -and $cq.screens[0].navigation[0].evidence[0].kind -eq 'SQL' -and $cq.screens[0].queryEvidence.Count -eq 1) "SQL:1 → staticEvidence PASS、evidenceKind SQL（不派 RQ id）"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' ($qe -replace '\| REGISTRY_DEFINED \| SQL:1 \|', '| REGISTRY_DEFINED | SQL:2 |')
Assert (@((Read-Frag 'screen-TW_MIL001.md' 'screen' $facts).Invalid | Where-Object { $_ -like '*SQL:2 超出查詢證據*' }).Count -gt 0) "SQL:2 超出查詢證據列數 → INVALID"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' ($screenText -replace 'TW_MILITARY:UPDATE', 'TW_MILITARY:UPDATE;TW_MIL_HIST:INSERT')
$cx = Get-Merged $facts
Assert ($cx.unresolvedReferences.Count -eq 1 -and $cx.unresolvedReferences[0] -like '*無 entity-TW_MIL_HIST.md*') "寫入指向無 entity fragment 的 Record → 未解析引用"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' $screenText

Write-Host "情境 K7：approvals.md——人工核准才升格 DIRECT_DB_WRITE_APPROVED；欄位缺一不算"
$null = Write-Fixture 'contract/approvals.md' "# 人工核准`n`n| Record | 操作鍵 | 策略 | 核准者 | 日期 | 證據 |`n|---|---|---|---|---|---|`n| TW_MILITARY | SAVE | DIRECT_DB_WRITE_APPROVED | 王小明 | 2026-09-02 | 架構會議紀錄 2026-09-01 |`n"
$ca = Get-Merged $facts
Assert ($ca.dataEntities[0].accessStrategy.write -eq 'DIRECT_DB_WRITE_APPROVED' -and $ca.dataEntities[0].accessStrategy.approvalRef -eq '王小明@2026-09-02') "完整核准列 → write 升格＋approvalRef"
$null = Write-Fixture 'contract/approvals.md' "| Record | 操作鍵 | 策略 | 核准者 | 日期 | 證據 |`n|---|---|---|---|---|---|`n| TW_MILITARY | SAVE | DIRECT_DB_WRITE_APPROVED |  | 2026-09-02 | x |`n"
Assert ((Get-Merged $facts).dataEntities[0].accessStrategy.write -eq 'PS_MEDIATED_WRITE') "核准者空白 → 不升格"
Remove-Item -LiteralPath (Join-Path $fixtureDir 'contract/approvals.md') -Force

Write-Host "情境 K8：verify 單位收據——OBJ／FLD／RQ 各自判定、EXISTS／MISMATCH 由外環算、hash 比對、通道未掛、currentSchema 守衛"
$objOk = "## 查詢`n| 單位 | 樣板 | SQL | 關鍵列 | 狀態 |`n|---|---|---|---|---|`n| PS_TW_MILITARY | OBJECT_EXISTS | SELECT OBJECT_NAME, OBJECT_TYPE FROM ALL_OBJECTS WHERE OBJECT_NAME='PS_TW_MILITARY' FETCH FIRST 10 ROWS ONLY | PS_TW_MILITARY TABLE | EXECUTED |`n`n## 物件`n| 檢查 | 值 |`n|---|---|`n| OBJECT_TYPE | TABLE |`n"
$fldOk = "## 查詢`n| 單位 | 樣板 | SQL | 關鍵列 | 狀態 |`n|---|---|---|---|---|`n| PS_TW_MILITARY | COLUMN_TYPE | SELECT COLUMN_NAME, DATA_TYPE, DATA_LENGTH FROM ALL_TAB_COLUMNS WHERE TABLE_NAME='PS_TW_MILITARY' FETCH FIRST 200 ROWS ONLY | 3 列 | EXECUTED |`n`n## 欄位`n| Field | Column | DATA_TYPE | DATA_LENGTH |`n|---|---|---|---|`n| EMPLID | EMPLID | VARCHAR2 | 11 |`n| EFFDT | EFFDT | DATE | 7 |`n| MIL_STATUS | MIL_STATUS | VARCHAR2 | 1 |`n"
$rqOk = "## 查詢`n| 單位 | 樣板 | SQL | 關鍵列 | 狀態 |`n|---|---|---|---|---|`n| RQ.TW_MILITARY.1 | REFERENCE_QUERY | $rqSql | 1 列 | EXECUTED |`n"
$null = Write-Fixture 'contract-parts/verify-TW_MILITARY-OBJ.md' $objOk
$null = Write-Fixture 'contract-parts/verify-TW_MILITARY-FLD-1-3.md' $fldOk
$null = Write-Fixture 'contract-parts/verify-TW_MILITARY-RQ-1.md' $rqOk
$cv = Get-Merged $facts $true
Assert ($cv.dataEntities[0].verification.oracleSchemaVerification -eq 'PASS') "OBJ＋FLD 收據全過 → oracleSchema PASS"
Assert ($cv.dataEntities[0].referenceQueries[0].oracleReadVerification -eq 'PASS' -and $cv.dataEntities[0].referenceQueries[0].state -eq 'EXECUTED' -and $cv.dataEntities[0].referenceQueries[0].keyRows -eq '1 列') "RQ 收據 hash 相符＋EXECUTED → oracleRead PASS、state EXECUTED、關鍵列回填"
$cvNo = Get-Merged $facts $false
Assert ($cvNo.dataEntities[0].verification.oracleSchemaVerification -eq 'NOT_RUN' -and $cvNo.dataEntities[0].referenceQueries[0].oracleReadVerification -eq 'NOT_RUN') "currentSchema 未知 → 同一批收據不採信（NOT_RUN）"
$null = Write-Fixture 'contract-parts/verify-TW_MILITARY-RQ-1.md' ($rqOk.Replace($rqSql, 'SELECT EMPLID FROM PS_TW_MILITARY FETCH FIRST 200 ROWS ONLY'))
Assert ((Get-Merged $facts $true).dataEntities[0].referenceQueries[0].oracleReadVerification -eq 'NOT_RUN') "RQ 收據 SQL 與契約 hash 不符 → 不算（NOT_RUN）"
$null = Write-Fixture 'contract-parts/verify-TW_MILITARY-RQ-1.md' $rqOk
$null = Write-Fixture 'contract-parts/verify-TW_MILITARY-FLD-1-3.md' ($fldOk -replace '\| MIL_STATUS \| MIL_STATUS \| VARCHAR2 \| 1 \|', '| MIL_STATUS | NOT_FOUND | NOT_FOUND | NOT_FOUND |')
$cvF = Get-Merged $facts $true
Assert ($cvF.dataEntities[0].verification.oracleSchemaVerification -eq 'FAIL' -and $cvF.dataEntities[0].schemaNote -like '*MIL_STATUS NOT_FOUND*') "欄位 NOT_FOUND → oracleSchema FAIL（外環算，非模型判）"
$null = Write-Fixture 'contract-parts/verify-TW_MILITARY-FLD-1-3.md' ($fldOk -replace '\| EFFDT \| EFFDT \| DATE \| 7 \|', '| EFFDT | EFFDT | VARCHAR2 | 10 |')
Assert ((Get-Merged $facts $true).dataEntities[0].verification.oracleSchemaVerification -eq 'FAIL') "型別 DATE vs VARCHAR2 → oracleSchema FAIL"
$null = Write-Fixture 'contract-parts/verify-TW_MILITARY-FLD-1-3.md' $fldOk
$null = Write-Fixture 'contract-parts/verify-TW_MILITARY-OBJ.md' ($objOk -replace '\| OBJECT_TYPE \| TABLE \|', '| OBJECT_TYPE | VIEW |')
Assert ((Get-Merged $facts $true).dataEntities[0].verification.oracleSchemaVerification -eq 'FAIL') "OBJECT_TYPE=VIEW 對 SQL_TABLE → FAIL"
$null = Write-Fixture 'contract-parts/verify-TW_MILITARY-OBJ.md' "## 查詢`n| 單位 | 樣板 | SQL | 關鍵列 | 狀態 |`n|---|---|---|---|---|`n| PS_TW_MILITARY | OBJECT_EXISTS | NOT_APPLICABLE | NOT_APPLICABLE | ORACLE_MCP_DOWN |`n"
$cvD = Get-Merged $facts $true
Assert ($cvD.dataEntities[0].verification.oracleSchemaVerification -eq 'NOT_RUN' -and $cvD.dataEntities[0].schemaNote -like '*通道未掛*') "ORACLE_MCP_DOWN → NOT_RUN（未跑不是錯）"
Remove-Item -LiteralPath (Join-Path $fixtureDir 'contract-parts/verify-TW_MILITARY-FLD-1-3.md') -Force
$cvM = Get-Merged $facts $true
Assert ($cvM.dataEntities[0].verification.oracleSchemaVerification -eq 'NOT_RUN' -and $cvM.dataEntities[0].schemaNote -like '*無收據*') "缺 FLD 單位收據 → NOT_RUN"
$null = Write-Fixture 'contract-parts/verify-TW_MILITARY-OBJ.md' "## 查詢`n| 單位 | 樣板 | SQL | 關鍵列 | 狀態 |`n|---|---|---|---|---|`n| PS_TW_MILITARY | OBJECT_EXISTS | DELETE FROM PS_TW_MILITARY | 0 | EXECUTED |`n"
$vr = Read-CtVerifyReceipts -PartsDir (Join-Path $fixtureDir 'contract-parts') -Vocab $vocab -Contract $cvM -FieldPageSize 10
Assert ($vr['TW_MILITARY'].Units['verify-TW_MILITARY-OBJ.md'].Invalid.Count -gt 0 -and $vr['TW_MILITARY'].Units['verify-TW_MILITARY-OBJ.md'].State -eq 'NOT_RUN') "含 DELETE 的收據 → 無效、NOT_RUN"
Get-ChildItem -LiteralPath (Join-Path $fixtureDir 'contract-parts') -Filter 'verify-*.md' | Remove-Item -Force

Write-Host "情境 K9：CLI 端到端——Plan／Accept／Merge／Render／Gate／parity／exit code／NN 變動作廢收據／attempts→BLOCKED／VerifyPlan 守衛"
$out = & $cliPath -Domain $fixtureDomain -Plan *>&1 | Out-String
Assert ($LASTEXITCODE -eq 0 -and $out -match 'PLAN：單位 2') "-Plan：2 個單位（screen＋entity）"
$mf = Read-CtText -LiteralPath (Join-Path $fixtureDir 'contract-parts/manifest.txt')
Assert ($mf -match '## 單位 1：screen TW_MIL001' -and $mf -match 'E03\.3=SQL' -and $mf -match 'E03\.4=PENDING_MANUAL' -and $mf -match '第 1～2 個欄位，共 1 頁') "manifest 含單位、E<nn>.<n> token、控制項頁範圍"
$out = & $cliPath -Domain $fixtureDomain -All *>&1 | Out-String
Assert ($LASTEXITCODE -eq 0) "-All：tier 1 通過（exit 0）"
Assert ($out -match 'ACCEPT_SUMMARY：DONE=2 INVALID=0 BLOCKED=0') "Accept：2 DONE"
Assert ($out -match 'GATE：G1=PASS' -and $out -match 'GATE：G2=PASS' -and $out -match 'GATE：G7=PASS' -and $out -match 'GATE：G12=PASS' -and $out -match 'GATE：G17=PASS' -and $out -match 'GATE：G18=PASS') "結構類 gate 全 PASS"
Assert ($out -match 'GATE：G14=UNRESOLVED' -and $out -match 'GATE：G16=UNRESOLVED' -and $out -match 'DEBT：G16｜RQ\.TW_MILITARY\.1｜oracleRead｜NOT_RUN') "G14／G16 首版 UNRESOLVED＋RQ oracleRead debt"
Assert ($out -match 'GATE_SUMMARY：tier1=True tier2=False') "tier1 通過、tier2 因 UNRESOLVED 未過"
Assert ($out -match 'DEBT：NAV｜SCR\.TW_MIL001｜alternateSurfaces｜NOT_INSPECTED') "有 Portal 入口列 → 固定出 alternateSurfaces NOT_INSPECTED debt（#24 Case 6）"
$out = & $cliPath -Domain $fixtureDomain -Gate -Tier 2 *>&1 | Out-String
Assert ($LASTEXITCODE -eq 1) "-Gate -Tier 2：exit 1"
$out = & $cliPath -Domain $fixtureDomain -Gate *>&1 | Out-String
Assert ($LASTEXITCODE -eq 0 -and $out -match 'GATE：G18=PASS') "獨立重跑 -Gate：render parity PASS（磁碟 JSON 為單一真相）"
$specPath = Join-Path $fixtureDir 'contract/spec/TW_MIL001.spec.md'
$spec = Read-CtText -LiteralPath $specPath
Assert ($spec -match '其他導覽 surface \| NAV_COLLECTION／FLUID_TILE／NAVBAR 本版未盤查') "spec：其他導覽 surface 未盤查列（#24 Case 6）"
$missing = @()
foreach ($h in @('## 功能與入口', '## 畫面結構', '## 欄位與控制項', '## 狀態與條件', '## 欄位互動', '## 驗證與訊息', '## Navigation', '## Business Operations', '## Data Source of Truth', '## Logical / Physical Data Mapping', '## Key / Effective-Date Semantics', '## Read Semantics / Reference Query', '## Write Semantics / Persistence Effects', '## Data Access Strategy', '## 權限差異', '## Runtime / DB Verification Status', '## 未解事項', '## Traceability / Evidence')) { if ($spec -notmatch [regex]::Escape($h)) { $missing += $h } }
Assert ($missing.Count -eq 0 -and $spec -notmatch '\[\[') "spec 18 章節齊且不含 [[ ]]"
Write-CtText -LiteralPath $specPath -Text ($spec -replace '兵役狀態', '兵役狀況') -Bom
$out = & $cliPath -Domain $fixtureDomain -Gate *>&1 | Out-String
Assert ($LASTEXITCODE -eq 1 -and $out -match 'GATE：G18=FAIL') "手改 spec 一字 → G18 FAIL、exit 1"
$out = & $cliPath -Domain $fixtureDomain -Render -Gate *>&1 | Out-String
Assert ($LASTEXITCODE -eq 0) "重 render 後恢復 PASS"
$null = Write-Fixture '03-TW_MIL001.md' ($nnText -replace '免役原因', '免役事由')
$out = & $cliPath -Domain $fixtureDomain -Plan *>&1 | Out-String
Assert ($out -match 'PLAN_UNIT：screen｜TW_MIL001') "NN 內容變 → screen 單位重回待寫（收據作廢）"
$null = Write-Fixture '03-TW_MIL001.md' $nnText
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' ($screenText -replace 'DROP_DOWN \| TRANSLATE_VALUE', 'COMBO | TRANSLATE_VALUE')
$out = & $cliPath -Domain $fixtureDomain -Accept *>&1 | Out-String
Assert ($LASTEXITCODE -eq 1 -and $out -match 'INVALID（attempts=1）') "INVALID fragment → exit 1、attempts=1"
$out = & $cliPath -Domain $fixtureDomain -Accept *>&1 | Out-String
Assert ($out -match 'INVALID（attempts=1）') "同 hash 重驗不加 attempts"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' ($screenText -replace 'DROP_DOWN \| TRANSLATE_VALUE', 'COMBO2 | TRANSLATE_VALUE')
$out = & $cliPath -Domain $fixtureDomain -Accept *>&1 | Out-String
Assert ($out -match 'BLOCKED（attempts=2）') "第二次不同內容仍 INVALID → BLOCKED"
$out = & $cliPath -Domain $fixtureDomain -Plan *>&1 | Out-String
Assert ($out -match 'PLAN：screen-TW_MIL001\.md BLOCKED' -and $out -notmatch 'PLAN_UNIT：screen｜TW_MIL001') "BLOCKED 單位 -Plan 靠邊不排入"
$out = & $cliPath -Domain $fixtureDomain -Gate *>&1 | Out-String
Assert ($out -match 'GATE_WARN：legacy-contract\.json 早於 contract-parts' -and $out -match 'GATE：G17=FAIL' -and $LASTEXITCODE -eq 1) "獨立 -Gate 吃舊 JSON → 印過期警告、G17 FAIL、exit 1"
$out = & $cliPath -Domain $fixtureDomain -All *>&1 | Out-String
Assert ($out -match 'DEBT：screen-TW_MIL001\.md｜capacity｜BLOCKED' -and $out -match 'GATE：G2=FAIL' -and $out -match 'BLOCKED:screen-TW_MIL001\.md') "BLOCKED → -All 重合併後 capacity debt、G2 FAIL 理由標 BLOCKED"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' $screenText
Remove-Item -LiteralPath (Join-Path $fixtureDir 'contract/contract-ledger.json') -Force
$out = & $cliPath -Domain $fixtureDomain -All *>&1 | Out-String
Assert ($LASTEXITCODE -eq 0) "刪 ledger 重跑 → 恢復 tier 1"
$out = & $cliPath -Domain $fixtureDomain -VerifyPlan *>&1 | Out-String
Assert ($LASTEXITCODE -eq 2 -and $out -match 'currentSchema=FILL_ME') "-VerifyPlan：currentSchema 未回填 → 不產工單、exit 2"
$out = & $cliPath -Domain $fixtureDomain -VerifyPlan -CurrentSchema SYSADM *>&1 | Out-String
$vm = Read-CtText -LiteralPath (Join-Path $fixtureDir 'contract-parts/verify-manifest.txt')
Assert ($LASTEXITCODE -eq 0 -and $vm -match '## 單位 1：OBJ TW_MILITARY' -and $vm -match '## 單位 2：FLD TW_MILITARY' -and $vm -match '## 單位 3：RQ TW_MILITARY' -and $vm -match 'verify-TW_MILITARY-FLD-1-3\.md' -and $vm -match 'RQ\.TW_MILITARY\.1') "-VerifyPlan（schema 已知）：OBJ／FLD-1-3／RQ 三單位工單"

Write-Host "情境 K10：控制項分頁——NN 35 欄位 → 主檔＋分頁單位；覆蓋不變量；merge 串接後 ID 與單頁相同；容量事件頁對半"
$bigFields = @()
for ($i = 1; $i -le 35; $i++) { $bigFields += "| FLD$('{0:D2}' -f $i) | 欄位$i | Edit Box | | |" }
$nnBig = $nnText -replace '(?s)\| MIL_STATUS \| 兵役狀態 \| Translate \| 免役=E / 服役中=S \| E：使用中 \|\r?\n\| EXEMPT_RSN \| 免役原因 \| Edit Box \| \| \|', ($bigFields -join "`n")
$null = Write-Fixture '03-TW_MIL001.md' $nnBig
Remove-Item -LiteralPath (Join-Path $fixtureDir 'contract/contract-ledger.json') -Force -ErrorAction SilentlyContinue
$out = & $cliPath -Domain $fixtureDomain -Plan *>&1 | Out-String
Assert ($out -match 'PLAN：單位 3（screen 1／分頁 1／entity 1）' -and $out -match 'PLAN_UNIT：screenpage｜TW_MIL001#2｜screen-TW_MIL001-p2\.md') "35 欄位、頁大小 30 → 主檔＋p2 分頁單位"
$mf = Read-CtText -LiteralPath (Join-Path $fixtureDir 'contract-parts/manifest.txt')
Assert ($mf -match '第 1～30 個欄位，共 2 頁' -and $mf -match 'FLD31（欄位31）') "manifest：主檔第 1～30、p2 列 FLD31…"
function New-CtlRows([int]$From, [int]$To) { $r = @(); for ($i = $From; $i -le $To; $i++) { $r += "| TW_MIL001_PG1 | TW_MILITARY.FLD$('{0:D2}' -f $i) | 欄位$i | ZHT | EDIT_BOX | NONE | NOT_APPLICABLE | UNRESOLVED | YES | YES | NO | UNRESOLVED |" }; return ($r -join "`n") }
$mainBig = $screenText -replace '(?s)\| TW_MIL001_PG1 \| TW_MILITARY\.MIL_STATUS.*?\| E03\.1 \|', (New-CtlRows 1 30)
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' $mainBig
$p2 = "## 畫面`n| 鍵 | 值 |`n|---|---|`n| component | TW_MIL001 |`n| page | 2 |`n| sourceNn | 03-TW_MIL001.md |`n`n## 控制項`n| 頁 | Record.Field | 顯示文字 | 語系 | 控制型 | 選項型 | 選項 | 預設 | 可見 | 可編輯 | 必填 | 證據 |`n|---|---|---|---|---|---|---|---|---|---|---|---|`n" + (New-CtlRows 31 35) + "`n"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001-p2.md' $p2
$out = & $cliPath -Domain $fixtureDomain -All *>&1 | Out-String
Assert ($out -match 'ACCEPT：screen-TW_MIL001-p2\.md DONE' -and $out -match 'ACCEPT：screen-TW_MIL001\.md DONE' -and $out -match 'GATE：G2=PASS｜35/35') "主檔 30＋分頁 5 → 兩檔 DONE、G2 35/35"
$cj = Read-CtJsonFile -LiteralPath (Join-Path $fixtureDir 'contract/legacy-contract.json')
Assert (@($cj.screens[0].controls).Count -eq 35 -and @($cj.screens[0].controls | Where-Object { $_.fragmentPage -eq 2 }).Count -eq 5 -and $cj.screens[0].fragment.pageFiles[0] -eq 'screen-TW_MIL001-p2.md') "merge 串接 35 控制項（5 個來自 p2）"
$idsPaged = @($cj.screens[0].controls | ForEach-Object { $_.id }) | Sort-Object
$null = Write-Fixture 'contract-parts/screen-TW_MIL001-p2.md' ($p2 -replace '\| TW_MIL001_PG1 \| TW_MILITARY\.FLD35 [^\n]+\n', '')
$out = & $cliPath -Domain $fixtureDomain -Accept *>&1 | Out-String
Assert ($out -match '範圍未覆蓋欄位 FLD35') "p2 少一列 → INVALID「範圍未覆蓋」"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001-p2.md' ($p2 + "| TW_MIL001_PG1 | TW_MILITARY.FLD01 | 欄位1 | ZHT | EDIT_BOX | NONE | NOT_APPLICABLE | UNRESOLVED | YES | YES | NO | UNRESOLVED |`n")
$out = & $cliPath -Domain $fixtureDomain -Accept *>&1 | Out-String
Assert ($out -match '欄位 FLD01 不在本檔範圍') "p2 多寫主檔的欄位 → INVALID「不在本檔範圍」"
$null = Write-Fixture 'contract-parts/screen-TW_MIL001-p2.md' $p2
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' ($mainBig + ("`n" * 80))
$out = & $cliPath -Domain $fixtureDomain -Accept *>&1 | Out-String
Assert ($out -match '容量事件——TW_MIL001 控制項頁大小 30 → 15') "主檔 >150 行 → 容量事件、頁大小 30→15"
$led = Get-CtLedger -LiteralPath (Join-Path $fixtureDir 'contract/contract-ledger.json')
Assert ([int]$led.pageSizes['TW_MIL001'] -eq 15 -and $led.fragments['screen-TW_MIL001-p2.md'].status -eq 'PENDING') "ledger：pageSizes=15、該 Component 全部 screen 檔重排為 PENDING"
$out = & $cliPath -Domain $fixtureDomain -Plan *>&1 | Out-String
Assert ($out -match 'PLAN：單位 4（screen 1／分頁 2／entity 1）') "重切後 35 欄位／頁大小 15 → 主檔＋p2＋p3"
# 單頁 vs 分頁 ID 相同：把 35 欄位縮回單頁大小（-ControlPageSize 40）
Remove-Item -LiteralPath (Join-Path $fixtureDir 'contract/contract-ledger.json') -Force
Get-ChildItem -LiteralPath (Join-Path $fixtureDir 'contract-parts') -Filter 'screen-TW_MIL001-p*.md' | Remove-Item -Force
$null = Write-Fixture 'contract-parts/screen-TW_MIL001.md' ($screenText -replace '(?s)\| TW_MIL001_PG1 \| TW_MILITARY\.MIL_STATUS.*?\| E03\.1 \|', (New-CtlRows 1 35))
$out = & $cliPath -Domain $fixtureDomain -All -ControlPageSize 40 *>&1 | Out-String
$cj2 = Read-CtJsonFile -LiteralPath (Join-Path $fixtureDir 'contract/legacy-contract.json')
$idsSingle = @($cj2.screens[0].controls | ForEach-Object { $_.id }) | Sort-Object
Assert ($LASTEXITCODE -eq 0 -and (($idsPaged -join ',') -eq ($idsSingle -join ','))) "單頁 merge 與分頁 merge 的控制項 ID 集合相同"

Write-Host ""
if (Test-Path -LiteralPath $fixtureDir) { Remove-Item -LiteralPath $fixtureDir -Recurse -Force }
if ($failCount -eq 0) { Write-Host "全部情境 PASS" -ForegroundColor Green; exit 0 }
else { Write-Host "FAIL 計 $failCount" -ForegroundColor Red; exit 1 }
