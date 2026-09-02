<!-- 來源：2026-09-02 接手 session 對 issue #16／#17 的現況盤點（7 讀者＋彙整 workflow）與對抗驗證。本備忘是 Phase 1 切片 1 的設計依據；落地後以 applied.md L108 為準，本文供後續切片參考。 -->

# Legacy Contract Phase 1 決策備忘（issue #17 現況裁決與切片 1 設計）

> **採信基礎**：issue #16／#17 的需求逐條對照 repo 現況（模板、契約、cookbook、lint、auto-loop、畢業門、教訓 L92～L107）。凡「既有零件已具備」者沿用其形狀與詞彙，不另創；凡「repo 無前身」者在本文定義。所有「檔案:行號」為本次實看。

---

## 1. 現況定性（issue 文字與 repo 的差距）

1. **產物線現況**：subagent JSON 報告 → 模型手寫 NN markdown（八節門檻）→ wiki entity。Behavior 面只有「畫面與欄位」五欄表、「行為邏輯」散文條列、Evidence 附錄；Persistence 面只有「資料流」四欄表（表／操作／來源／信心）。stable ID、storageKind、keys、生效日規則、read/write 語意、存取策略、五維驗證狀態，**repo 內全無前身**。
2. **最接近的既有機制＝L107 分批稽核**：外環產 manifest（模型唯讀）→ 每 session 只寫一個固定表格 part 檔 → 外環驗不變量發檔級收據 → 收據齊備才外環合併寫報告。#17 的「fragment＋stable ID＋deterministic merge／render」與此同構。
3. **證據契約不可動**：evidence 只有 CHUNK（36 字元 ChunkId）與 SQL（實際執行的 SELECT＋keyRows）兩種；confidence 只有 CONFIRMED／INFERRED／DYNAMIC_RUNTIME；稽核 verdict 只有 PASS／FAIL(原因)／UNVERIFIABLE(原因)。#17 的五維 verification 與 NOT_RUN／NOT_APPLICABLE／UNRESOLVED **只住在 contract 產物**，不進 NN、不進 90-audit（lint 只認既有五詞）。
4. **Oracle 能力只在 agent 側**：scripts/ 零 MCP 呼叫；oracleMCP 單工、SELECT-only、30 秒逾時、`currentSchema` 仍 FILL_ME；cookbook 沒有 key／constraint／型別長度／view 區分／EFFSEQ／SETID／Message Catalog 樣板。**G16 在 Phase 1 驗的是「SQL 收據」不是 DB**。
5. **#14 未實作**：GitHub 關成 completed，但 auto-loop tier 2 仍 `Unticked -eq 0`，BlockingDebt 全 repo 零命中。**contract gate 必須獨立於 tier 門**，不得依賴 tier 2 收斂。
6. **小模型硬約束**：單次 write ≤150 行、JSON 截斷為永久條件（SOP-9／SOP-10）、write 工具參數本身是 JSON（內容含大量 `"` 時逃逸出錯機率升高）；分批稽核 part 檔（固定表格 .md）在管理者實跑中已可寫（前兩批 6/6）；contract fragment 本身尚未實測（§7）。
7. **搬運邊界**：manifest 搬運集合＝scripts＋.opencode 全樹；docs/ps-research/** 機密只進內部 git；docs/、README.md、HANDOFF.md 不佔搬運成本。

---

## 2. issue #17 逐條裁決表

| # | #17 項目 | 裁決 | 一句理由 |
|---|---|---|---|
| 1 | Behavior＋Persistence 雙軌 contract | **採納** | 兩軌各自一種 fragment（screen／entity），共用 evidence 與 ID 規則 |
| 2 | Canonical Contract 為單一真相、Markdown 為 projection | **採納** | canonical＝外環 merge 產的 JSON；spec.md 由 renderer 產；模型零寫入 spec |
| 3 | fragment 拆分（Screen／BO／Data Entity／Persistence Effect 四種） | **修正為兩種** | BO 與 Effect 是 screen／entity fragment 內的表格列，不獨立成檔——四種＝四倍 session 數與四倍 ID 交叉引用失敗面；#16 硬規則 8 只列三種，兩份 issue 本就不一致 |
| 4 | 模型輸出 JSON contract fragment | **修正為固定表格 .md** | write 工具的 JSON 逃逸與截斷是永久條件；audit part 固定表格已在分批稽核實跑中可寫；表格欄位＝封閉 enum 天然禁自由 token；JSON 由外環產 |
| 5 | stable ID 由模型給 | **修正為外環派發** | 模型只寫自然鍵（Component／Page／Record.Field／opKey）；ID 由確定性層以正規化名組成，跨 fragment 合併後不變（L104「候選→身分升格點必須有 gate」） |
| 6 | 五維 verification | **採納＋映射表** | staticEvidence 由外環依 evidence 解析結果算；oracleSchema／oracleRead 由驗證收據算；uiRuntime／writeEffect 固定 NOT_RUN（Phase 2／3） |
| 7 | Access Strategy 五值＋人工核准 | **採納** | 模型只准填 UNRESOLVED／PS_MEDIATED_*／DIRECT_DB_READ；DIRECT_DB_WRITE_APPROVED 只能來自 `contract/approvals.md`（人填），外環驗存在性 |
| 8 | Oracle read-only 驗證 | **採納為收據制** | 外環產 verify manifest → 持 oracleMCP 的 subagent 跑 §7 樣板 → 寫 verify 收據 .md → 外環驗 SELECT-only＋形狀後蓋章；§7 樣板全數標「待公司機驗證」 |
| 9 | G1～G18 | **採納，分母改 NN 抽取** | 切片 1 的 discovered 分母來自 NN 檔的確定性抽取（畫面與欄位列、行為邏輯列、資料流列、權限節、Evidence 附錄）；metadata 分母（PSPNLFIELD 盤點）留切片 2 |
| 10 | 19 節 developer-facing Markdown | **採納（落地 18 節）** | 依 #17 章節順序由 renderer 產，落 `contract/spec/`，檔名不用 `NN-` 前綴、內文不含 `[[ ]]`（避開 lint 八節門檻與 wiki 斷鏈掃描） |
| 11 | 「不再用單一 CONFIRMED」 | **修正措辭** | confidence 三值是證據強度、lint 必要標註，保留；五維另立 |
| 12 | G14 security | **首版允許 UNRESOLVED** | 存量 NN 全缺「## 權限」（L94），補齊＝獨立回灌戰役 |
| 13 | referenceQuery 帶 ID | **採納，ID 外環派發** | 既有契約 SQL 證據無 id 且禁自創；RQ id＝`RQ.<RECNAME>.<n>`＋正規化 SQL 的 hash 記在 contract |
| 14 | Deterministic Graduation Gate 併入畢業門 | **不併** | 獨立收據 `contract-receipt.json`（gitignore）；不 bump GraduationGateVersion、不動三層門 |

---

## 3. 採納的設計（切片 1，全部以現有零件形狀拼）

### D1. 產物與落點

```text
docs/ps-research/<領域>/
├─ contract-parts/                 ← 暫存（模型唯一可寫區）
│  ├─ manifest.txt                 ← 外環產、模型唯讀：本批要寫哪些 fragment、每個的 NN 來源與預抽事實
│  ├─ screen-<COMPONENT>.md        ← screen fragment（固定表格）
│  ├─ screen-<COMPONENT>-p<k>.md   ← 控制項分頁檔（外環依頁大小切；只在 manifest 列出時寫）
│  ├─ entity-<RECNAME>.md          ← entity fragment（固定表格）
│  └─ verify-<RECNAME>-<單位>.md   ← Oracle 驗證收據（OBJ／FLD-a-b／RQ-n，一單位一檔）
├─ contract/
│  ├─ legacy-contract.json         ← Canonical Legacy Contract（外環 merge 產，單一真相）
│  ├─ contract-ledger.json         ← fragment 級收據（hash／status／attempts／nnHash）＋pageSizes
│  ├─ contract-gate.json           ← G1～G18 結果＋debt 清單（供 #18～#21 繼承）
│  ├─ contract-receipt.json        ← 單機收據（gitignore）：contract／enums／腳本 hash
│  ├─ approvals.md                 ← 人工核准記錄（人填；模型零寫入）
│  └─ spec/
│     ├─ index.spec.md             ← 領域索引
│     └─ <COMPONENT>.spec.md       ← 18 節 developer-facing spec（renderer 產）
```

- 全部在 `docs/ps-research/<領域>/` 子目錄：不進 lint 八節門檻、不進 checklist 對帳、不進 graduation contentHash（非頂層）。
- fragment 驗收通過後**不刪**（與 audit-parts 不同）：fragment 是可續跑的原料，ledger 以 hash 判斷是否需重做；NN 檔內容變 → 對應 fragment 收據作廢（同 audit-ledger 語意）。

### D2. Fragment 形狀（模型寫、固定表格、每檔 ≤150 行）

> 對抗審查後的定稿以 `.opencode/peoplesoft/legacy-contract-fragments.md` 為準；本節草案與定稿的差異：
> screen 多一張「## 查詢證據」表（用途｜SQL｜關鍵列）供 `SQL:<n>` 引用；控制項多於頁大小時另有分頁檔
> （只含「## 畫面」＋「## 控制項」）；entity「參考查詢」狀態欄只准 PENDING／NOT_APPLICABLE；沒有「（續）」列。

**screen fragment** `contract-parts/screen-<COMPONENT>.md`（一個 Component 一檔；來源＝該 NN 檔＋必要委派）：

```markdown
## 畫面
| 鍵 | 值 |
|---|---|
| component | TW_MIL001 |
| pages | TW_MIL001_PG1;TW_MIL001_PG2 |
| searchRecord | TW_MIL_SRCH |
| modes | ADD;UPDATE |
| menuPath | 人事 > 兵役 > 兵役資料維護 |
| origin | CUSTOM_PREFIX |
| sourceNn | 03-TW_MIL001.md |

## 控制項
| 頁 | Record.Field | 顯示文字 | 語系 | 控制型 | 選項型 | 選項 | 預設 | 可見 | 可編輯 | 必填 | 證據 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| TW_MIL001_PG1 | TW_MILITARY.MIL_STATUS | 兵役狀態 | ZHT | DROP_DOWN | TRANSLATE_VALUE | 免役=E;服役中=S | UNRESOLVED | YES | YES | YES | E1 |

## 狀態
| 目標 Record.Field | 屬性 | 條件 | 觸發事件 | 解析 | 證據 |
|---|---|---|---|---|---|
| TW_MILITARY.EXEMPT_RSN | VISIBLE | MIL_STATUS = 'E' | FIELD_CHANGE | RESOLVED | E1 |

## 互動
| 觸發事件 | 條件 | 效果型 | 目標 | 說明 | 證據 |
|---|---|---|---|---|---|
| FIELD_CHANGE | MIL_STATUS = 'E' | SET_VALUE | TW_MILITARY.EXEMPT_DT | 帶入今日 | E1 |

## 驗證
| 觸發事件 | 條件 | 訊息型 | 訊息 | 證據 |
|---|---|---|---|---|
| SAVE_EDIT | EXEMPT_RSN 空白 | ERROR | 20001,5 | E2 |

## 導覽
| 來源 | 目標 | 型 | 證據 |
|---|---|---|---|
| MENU | TW_MIL001 | MENU_ENTRY | E3 |

## 業務操作
| 操作鍵 | 觸發 | 模式 | 說明 | 寫入 | 證據 |
|---|---|---|---|---|---|
| SAVE | SAVE_POST_CHANGE | UPDATE | 存檔兵役資料 | TW_MILITARY:UPDATE;TW_MIL_HIST:INSERT | E4 |

## 權限
| Permission List | Role | 人數 | Search Record | 證據 |
|---|---|---|---|---|
| UNRESOLVED | | | | |
```

**entity fragment** `contract-parts/entity-<RECNAME>.md`（一個 Record 一檔）：

```markdown
## 實體
| 鍵 | 值 |
|---|---|
| record | TW_MILITARY |
| businessMeaning | 員工兵役資料 |
| storageKind | SQL_TABLE |
| physicalObject | PS_TW_MILITARY |
| origin | CUSTOM_PREFIX |
| domainGate | DOMAIN_ROOT |
| sourceNn | 03-TW_MIL001.md;07-TW_MIL003.md |

## 欄位
| Field | Column | 型別 | 長度 | 鍵 | 必填 | 選項來源 | 證據 |
|---|---|---|---|---|---|---|---|
| EMPLID | EMPLID | CHAR | 11 | K | YES | PROMPT:PERSON | E5 |
| EFFDT | EFFDT | DATE | | K | YES | | E5 |

## 鍵
| 鍵 | 值 |
|---|---|
| psKeys | EMPLID;EFFDT |
| businessKey | EMPLID |
| physicalUniqueKey | UNRESOLVED |
| parentRecord | PERSON |
| rowIdentity | EMPLID+EFFDT |

## 生效日
| 鍵 | 值 |
|---|---|
| effdtRule | EFFDT_EFFSEQ_STATUS |
| asOf | SYSDATE |
| selection | MAX_EFFDT_LE_ASOF |
| activeOnly | YES |

## 讀取語意
| 型 | 內容 | 證據 |
|---|---|---|
| SOURCE | PS_TW_MILITARY | E5 |
| LOOKUP | MIL_STATUS → PSXLATITEM(ZHT) | E1 |
| ROW_SECURITY | 依 Component Search Record TW_MIL_SRCH | UNRESOLVED |

## 參考查詢
| 用途 | SQL | 關鍵列 | 狀態 |
|---|---|---|---|
| 現行有效列 | SELECT … FROM PS_TW_MILITARY A WHERE … FETCH FIRST 200 ROWS ONLY | 1 列 | EXECUTED |

## 寫入
| 操作鍵 | 操作 | 列選擇 | 變更欄位 | 伴隨效果 | 證據 |
|---|---|---|---|---|---|
| SAVE | UPDATE | EMPLID+EFFDT 現行列 | MIL_STATUS;EXEMPT_RSN;EXEMPT_DT | TW_MIL_HIST:INSERT | E4 |

## 存取策略
| 鍵 | 值 |
|---|---|
| read | DIRECT_DB_READ |
| write | PS_MEDIATED_WRITE |
| approvalRef | |
```

硬規則（寫進 fragment 指南）：
- 章節標題與表頭**逐字**照本文；欄位值只准用 `legacy-contract-vocabulary.md` 列的值；缺值只能寫 `UNRESOLVED`（未知）或 `NOT_APPLICABLE`（不適用），**不得留空、不得自創詞**。
- 「證據」欄只准三種：`E<nn>.<n>`（nn＝來源 NN 檔前兩碼、n＝該檔 Evidence 附錄第 n 列；entity 可引多個來源）、`SQL:<n>`（screen＝本檔「查詢證據」第 n 列；entity＝「參考查詢」第 n 列）、`UNRESOLVED`。ChunkId 不重抄（由外環從 NN 附錄解引用），避免縮寫與捏造。
- 多值以 `;` 分隔；選項以 `label=value` 成對；操作鍵 `^[A-Z][A-Z0-9_]{1,30}$`。
- 一檔 ≤150 行；模型不自估容量、沒有「（續）」列——控制項頁大小由外環決定（預設 30）；>150 行＝容量事件：外環把該 Component 的頁大小對半（最小 10）重切分頁並重排、不記 attempts；到最小仍超容量 → BLOCKED（出路＝拆 NN 續篇）。
- 不寫 NN 檔、不寫 checklist、不寫 90-audit、不寫 spec；最終回覆一行「已寫 <路徑>」。

### D3. Stable ID（外環派發；模型不寫 ID）

| 元素 | ID 規則 | claimDomain |
|---|---|---|
| screen | `SCR.<COMPONENT>` | BEHAVIOR |
| control | `CTL.<COMPONENT>.<PAGE>.<RECNAME>.<FIELDNAME>[.<n>]` | BEHAVIOR |
| state | `STA.<COMPONENT>.<RECNAME>.<FIELDNAME>.<PROPERTY>[.<n>]` | BEHAVIOR |
| interaction | `INT.<COMPONENT>.<EVENT>.<EFFECT>.<TARGET>[.<n>]` | BEHAVIOR |
| validation | `VAL.<COMPONENT>.<EVENT>.<KIND>.<MSG>[.<n>]` | BEHAVIOR |
| navigation | `NAV.<COMPONENT>.<FROM>.<TO>.<KIND>[.<n>]` | BEHAVIOR |
| businessOperation | `BOP.<COMPONENT>.<OPKEY>` | BEHAVIOR |
| dataEntity | `ENT.<RECNAME>` | PERSISTENCE |
| fieldMapping | `FLD.<RECNAME>.<FIELDNAME>` | PERSISTENCE |
| readSemantic | `RDS.<RECNAME>.<KIND>[.<n>]` | PERSISTENCE |
| writeSemantic | `WRT.<RECNAME>.<OPKEY>.<OPERATION>[.<n>]` | PERSISTENCE |
| persistenceEffect | `EFF.<COMPONENT>.<OPKEY>.<RECNAME>.<OPERATION>[.<n>]` | PERSISTENCE |
| referenceQuery | `RQ.<RECNAME>.<n>`（另記正規化 SQL 的 SHA256 前 12 碼，非 hex 8 連字避開 lint） | PERSISTENCE |

- 正規化：大寫、去頭尾空白、`.` 與 `;` 不得出現在自然鍵內（含則該列 FAIL）。ID 全由自然鍵組成、與列序無關（插列不改既有 ID，測試 K5 覆蓋）；同自然鍵在同表出現兩次即第二列 `.2`。
- claimId＝元素 ID；每個帶「證據」欄的列都是一個 claim。
- 跨 fragment 引用一律用自然鍵（Record.Field、操作鍵、Record:操作），merge 時解析成 ID；解析不到＝G15 違規。

### D4. 外環：`scripts/ps-contract.ps1`（CLI）＋`scripts/ps-contract-lib.ps1`（函式庫）

| 動作 | 做什麼 | 產物 |
|---|---|---|
| `-Plan` | 讀 NN 檔（`^\d\d-` 且非 00／90）抽取確定性事實：Component（標題）、畫面與欄位列、行為邏輯列（含 confidence 標籤）、資料流列、權限節是否申報、Evidence 附錄列（E<nn>.<n> → 機器參照型）；依 ledger pageSizes 切控制項分頁單位；與 ledger 比對決定本批 K 個待寫 fragment（BLOCKED 靠邊）；寫 `contract-parts/manifest.txt`（每單位：fragment 路徑、來源 NN、預抽事實、可用 E<nn>.<n> 清單、控制項頁範圍） | manifest.txt |
| `-Accept` | 解析 fragment → 驗不變量（表頭逐字、enum 值、證據 ref 可解析到 NN 附錄、無洩漏標記、無空值、行數 ≤150、分頁覆蓋）→ 寫 ledger 收據（hash＋status DONE／INVALID／BLOCKED／PENDING＋reason＋attempts）；>150 行＝容量事件→頁大小對半重排 | contract-ledger.json |
| `-Merge` | 本次驗不變量零 INVALID 的 fragment → canonical JSON（stable ID 派發、跨 fragment 引用解析、evidence 解引用成 CHUNK／SQL／PENDING_MANUAL、五維 verification 計算、approvals 套用、verify 收據蓋章——只在 currentSchema 已知時採信）；寫檔後回讀磁碟 JSON 供 Render／Gate | legacy-contract.json |
| `-Render` | canonical JSON → `spec/<COMPONENT>.spec.md`（18 節）＋`spec/index.spec.md`；BOM、CRLF 與既有產物一致 | spec/ |
| `-Gate` | G1～G18 → contract-gate.json；console 機器行 `GATE：G<n>=<state>｜<分子/分母>｜<理由>`、`DEBT：<claimId>｜<維度>｜<state>`；exit 0 全過（PASS／NOT_APPLICABLE）／1 有 FAIL 或 UNRESOLVED（依 `-Tier`）／2 環境錯誤 | contract-gate.json、contract-receipt.json |
| `-All` | Accept → Merge → Render → Gate | |
| `-VerifyPlan` | currentSchema 未知即 exit 2；否則由 canonical 列出 physicalObject≠空的實體 → OBJ／FLD-a-b／RQ-n 單位（一單位一委派一收據）→ 寫 `contract-parts/verify-manifest.txt` | verify-manifest.txt |

- 慣例：UTF-8 BOM、PS 5.1 相容（無三元、Join-Path 兩參數、-LiteralPath、ConvertTo-Json 明示 -Depth、[ordered]）、`-Domain` 消毒（複製 lint 同段）、Write-Host 機器可解析行、exit 0／1／2。
- canonical 序列化：鍵序固定（照 schema 順序）、陣列依 ID 排序、無時間戳（時間戳只進 receipt）；G18 以「重新 render 的正規化文字（剝 BOM、\r）」與磁碟檔比對。

### D5. 五維 verification 計算規則（外環算，模型不填）

| 維度 | 來源 | 值 |
|---|---|---|
| staticEvidence | 該 claim 的證據 ref 解引用結果 | 全部解析為 CHUNK（36 字元 UUID）或 SQL（含 SELECT…FROM）→ PASS；含 `待人工SQL`／`UNRESOLVED` → UNRESOLVED；ref 指向不存在的 E<nn>.<n> 在 Accept 即 INVALID（進不了 merge） |
| oracleSchemaVerification | `verify-<RECNAME>-OBJ.md`＋`-FLD-a-b.md` 單位收據（EXISTS／MISMATCH 由外環對照 entity fragment 算，模型不判） | 全部單位 PASS → PASS；任一 NOT_FOUND／型別不符／物件型別不符 → FAIL；任一單位無收據／ORACLE_MCP_DOWN／BLOCKED／收據無效／currentSchema 未知 → NOT_RUN；storageKind ∈ {DERIVED_WORK, SUBRECORD, OTHER_LOGICAL} → NOT_APPLICABLE |
| oracleReadVerification | `verify-<RECNAME>-RQ-n.md` 收據（SQL hash 須與契約相符；fragment 的狀態欄只准 PENDING） | EXECUTED 且關鍵列非空 → PASS；FAILED／NOT_FOUND → FAIL；無收據／hash 不符／PENDING → NOT_RUN；無參考查詢 → NOT_APPLICABLE |
| uiRuntimeVerification | — | 固定 NOT_RUN（Phase 2） |
| writeEffectVerification | — | 效果列固定 NOT_RUN；非寫入 claim NOT_APPLICABLE |

與既有詞彙的映射：任務 A PASS→staticEvidence PASS；FAIL(*)→FAIL；UNVERIFIABLE(*)→UNRESOLVED；FAIL(ORACLE_MCP_DOWN)／status BLOCKED→NOT_RUN（「未跑」不是「錯」）。

### D6. G1～G18（切片 1 定義；分母＝NN 確定性抽取）

共通：每個 gate 輸出 PASS／FAIL／NOT_APPLICABLE／UNRESOLVED＋分子／分母；分母不可得→UNRESOLVED；分母空且 fragment 明示 NOT_APPLICABLE→NOT_APPLICABLE；分母有、contract 無、又未申報→FAIL。

| Gate | 分母（NN 抽取） | 判準 |
|---|---|---|
| G1 identity | NN 標題的 Component；00-overview 功能地圖 | screen.component 命中 NN 標題；ID 唯一；pages／modes 值域合法 |
| G2 control inventory | 畫面與欄位表的欄位列 | 每列在 controls 有對應 Record.Field（同名或 NN 只寫 FIELDNAME 時尾綴相符）；申報（無——…）→ NOT_APPLICABLE |
| G3 label／choice | controls | 每控制項 label 非 UNRESOLVED（或 DYNAMIC_RUNTIME）；選項型控制項 choices 非空且成對 |
| G4 state／conditional UI | 行為邏輯含 UI 狀態關鍵詞（顯示／隱藏／唯讀／必填／Visible／Enabled／DisplayOnly／Required）之列數 | 分母>0 時 states 非空且每列有條件＋證據＋解析值 |
| G5 interaction／validation | 行為邏輯帶 confidence 標籤之列數 | interactions＋validations 列數 ≥ 1 且每列 trigger／效果型 ∈ enum、證據解析 |
| G6 business operation | 資料流表非空 或 行為邏輯含存檔類詞 | ≥1 操作；每操作「寫入」欄非空或 NOT_APPLICABLE |
| G7 entity mapping | 資料流表的 distinct Record（去 PS_） | 每個已合併進 canonical（entity fragment 零 INVALID）；每個 effect 的 record 有 entity |
| G8 logical↔physical | entities | storageKind ∈ enum；SQL_TABLE／SQL_VIEW／TEMP_TABLE→physicalObject 非空或 UNRESOLVED；DERIVED_WORK／SUBRECORD／OTHER_LOGICAL→physicalObject 必須 NOT_APPLICABLE 且無寫入效果指向 |
| G9 keys | entities | psKeys 非空（或 UNRESOLVED）；欄位表鍵旗標與 psKeys 一致；rowIdentity 非空 |
| G10 effective dating | 欄位表含 EFFDT／EFFSEQ／EFF_STATUS | 含→effdtRule ≠ NONE 且四鍵齊；不含→effdtRule=NONE 或 NOT_APPLICABLE |
| G11 read semantics | 控制項選項型 PROMPT_TABLE／TRANSLATE_VALUE 之欄位；entity SOURCE | 每個 prompt／translate 欄位有 LOOKUP 列；每 entity ≥1 SOURCE 列 |
| G12 write／effects | 資料流表 INSERT／UPDATE／DELETE／MERGE 列 | 每列有對應 effect（record＋operation）；每 effect operation ∈ enum、列選擇與變更欄位非空（或 DYNAMIC_RUNTIME） |
| G13 access strategy | entities | read／write ∈ enum；DIRECT_DB_WRITE_APPROVED 必有 approvals.md 記錄（approver／date／evidence） |
| G14 security | NN「## 權限」節非空心 | 分母空→UNRESOLVED（首版）；有→權限表非 UNRESOLVED |
| G15 evidence integrity | contract 全部 ref | 每 ref 解析；每 claim ≥1 ref 或 UNRESOLVED；跨 fragment 引用全部解析 |
| G16 Oracle schema | physicalObject 非空之 entities | 依 D5 聚合：全 PASS→PASS；任一 FAIL→FAIL；有 NOT_RUN→UNRESOLVED |
| G17 schema validity | fragments | Accept 零 INVALID；enum 零違規；自由 token 黑名單零命中 |
| G18 renderer parity | spec/ | 重 render 正規化後與磁碟相等；18 節齊 |

聚合：`tier 1`＝結構類 gate（G1、G2、G6、G7、G8、G12、G13、G15、G17、G18）**無 FAIL**（UNRESOLVED 允許——未知已申報，結構可交付）；`tier 2`＝全部 gate PASS／NOT_APPLICABLE 且 debt 清單中無任何 UNRESOLVED／NOT_RUN。兩級都不動 graduation.json；`-Gate -Tier 1|2` 決定 exit code。

實作落地時修正的兩點（見 L108）：canonical JSON 序列化改走 `GetEnumerator`（PowerShell 的 `$dict.Keys` 會被名為 `keys` 的鍵劫持，entity 的鍵欄位因此改名 `recordKeys`）；Render／Gate 一律回讀磁碟上的 JSON（記憶體物件與反序列化物件形狀不同，否則獨立 -Gate 的 G18 會假 FAIL）。

### D7. 指令（掛 ps-deep-research，程序全寫在指令本文；agent 定義不改）

- `/ps-contract-batch <領域>`：第一動作 read `contract-parts/manifest.txt`；對每個單位：read 指定 NN 檔 → 缺料才委派（screen：@ps-ui-flow 以 cookbook §2d／§2e 取 Page 欄位盤點與 modes；entity：@ps-metadata-flow 以 §6 取 RECTYPE／SQLTABLENAME／欄位）→ 照 `legacy-contract-fragments.md` 寫 fragment → read 回確認。不寫 NN／checklist／90-audit／spec。
- `/ps-contract-verify <領域>`：第一動作 read `contract-parts/verify-manifest.txt`；每單位（OBJ／FLD-a-b／RQ-n）一個委派 @ps-metadata-flow 跑 cookbook §7 樣板（同時 ≤3）→ 寫 `verify-<RECNAME>-<單位>.md`（「## 查詢」表：單位｜樣板｜SQL｜關鍵列｜狀態；FLD 加「## 欄位」表、OBJ 加「## 物件」表）；模型不判 PASS／FAIL。
- 切片 1 不做外環駕駛 loop（實驗先行）：管理者手動 `opencode run --command ps-contract-batch <領域>` 每批一次，之間跑 `ps-contract.ps1 -Domain <領域> -All`。實測 fragment 可寫後再上 loop（切片 2）。

### D8. Cookbook §7（Schema Verification 樣板，全數標「待公司機驗證」）

PSRECDEFN.RECTYPE（→ storageKind 對照，值域待驗）、PSRECFIELDDB 欄位清單、ALL_TAB_COLUMNS（column／data_type／data_length）、ALL_OBJECTS（TABLE／VIEW）、PSKEYDEFN（Record 鍵，待驗）、ALL_INDEXES＋ALL_IND_COLUMNS（唯一索引）、EFFSEQ 版標準樣式（as-of 參數化）、PSMSGCATDEFN（訊息文字）。規則 6／8 適用：第一次使用前先驗表名欄位名，查不到記 gaps，不硬湊。

---

## 4. 拒絕或延後的項目與理由

| 項目 | 裁決 | 理由 |
|---|---|---|
| JSON fragment | 拒絕（切片 1） | write 工具 JSON 逃逸／截斷風險；固定表格已實證 |
| 修改 ps-auto-loop 加 contract 相位 | 延後 | 管理者正在跑分批稽核；2270 行檔案再搬一次成本高；先驗證模型能寫 fragment |
| ps-contract-loop 外環駕駛 | 延後（切片 2） | 實驗先行；Invoke-Opencode 尚未抽成共用函式庫 |
| 併入 graduation 三層門／bump GateVersion | 拒絕 | #14 未落地、tier 2 不可收斂；contract 有獨立收據 |
| metadata 分母（PSPNLFIELD 全頁盤點） | 延後（切片 2） | 需新 ui-flow 任務型與公司機驗證；切片 1 以 NN 為分母 |
| 修改 ps-deep-research.md | 拒絕（切片 1） | ps-audit-batch 前例證明「程序寫進指令本文」即可；避免 475 行再搬 |
| 修改 lint | 拒絕 | 衝刺期凍結標準；contract 產物全在子目錄，lint 不掃 |
| test-scenarios K 類、.opencode/peoplesoft/README.md | 延後 | 佔搬運成本；先以 SOP-18＋root README 說明 |

---

## 5. 編輯清單（切片 1）

| 檔案 | 動作 | 內容 |
|---|---|---|
| `.opencode/peoplesoft/legacy-contract-vocabulary.md` | 新增 | 封閉值域單一真相（表格；腳本機械解析、模型照抄） |
| `.opencode/peoplesoft/legacy-contract-fragments.md` | 新增 | fragment 形狀與硬規則（D2） |
| `.opencode/command/ps-contract-batch.md` | 新增 | D7 |
| `.opencode/command/ps-contract-verify.md` | 新增 | D7 |
| `.opencode/peoplesoft/oracle-query-cookbook.md` | 只加 | §7 |
| `scripts/ps-contract-lib.ps1` | 新增 | 解析／驗證／ID／merge／render／gate 函式 |
| `scripts/ps-contract.ps1` | 新增 | CLI（D4） |
| `scripts/tests/test-contract.ps1` | 新增 | 合成 fixture（NN＋fragment）→ 全鏈斷言 |
| `.gitignore` | 只加 | `docs/ps-research/*/contract/contract-receipt.json` |
| `.opencode/peoplesoft/lessons/applied.md` | 只加 | L108 |
| `.opencode/peoplesoft/SOP.md` | 只加 | SOP-18（操作程序） |
| `README.md`、`HANDOFF.md`、`AGENTS.md` | 修改 | 指令／腳本／版線／搬運清單 |
| `scripts/ps-transfer-manifest.json` | 重生 | -WriteManifest |

---

## 6. 回歸測試情境（scripts/tests/test-contract.ps1，PS 5.1／7 皆可，不需模型）

1. NN 抽取：八節 fixture → 欄位列／行為邏輯列／資料流列／Evidence E<nn>.<n> 型別正確；申報「（無——…）」→ NOT_APPLICABLE。
2. Fragment 解析與不變量：正典 fragment 全過；表頭差一字、enum 外值、空值、證據越界、舊語法 E5、前綴不在 sourceNn、含洩漏標記、>150 行（＝容量事件）、自由 token、EXECUTED、DIRECT_DB_WRITE_APPROVED、DML／省略號 → 各自對應的 INVALID 理由。
3. ID 派發穩定：同 fragment 兩次 merge → 相同 ID；列序調換不改 ID（自然鍵決定）；同自然鍵重複 → `.2`。
4. Merge：跨 fragment 引用（screen 寫入 → entity effect）解析；解析不到 → G15 FAIL；evidence 解引用成 CHUNK／SQL／PENDING_MANUAL；五維計算。
5. approvals：模型寫 DIRECT_DB_WRITE_APPROVED → INVALID；approvals.md 有記錄 → G13 PASS。
6. Render parity：render 兩次相等；手改 spec 一字 → G18 FAIL；18 節齊。
7. Gate 聚合：乾淨 fixture → T1 PASS、T2 因 UNRESOLVED 未過；補齊後 T2 PASS；exit code 對應。
8. Verify 單位收據：SELECT-only（含 DELETE → 收據無效）；NOT_FOUND／型別不符／VIEW 對 SQL_TABLE → FAIL；ORACLE_MCP_DOWN／缺單位／SQL hash 不符／currentSchema 未知 → NOT_RUN。
9. 控制項分頁：35 欄位 → 主檔＋p2；覆蓋不變量（少列「範圍未覆蓋」／越界列「不在本檔範圍」）；>150 行 → 容量事件 30→15、重切為 3 單位；單頁與分頁 merge 的 CTL ID 集合相同。
10. CLI 收據語意：NN 內容變 → 收據作廢；INVALID 兩次 → BLOCKED、-Plan 靠邊；獨立 -Gate 吃舊 JSON → GATE_WARN＋G17 FAIL；-All 重合併後 capacity debt、G2 FAIL 標 BLOCKED。

實作結果：K1～K10 共 102 判定全 PASS（pwsh 7.4；PS 5.1 待公司機回歸）。

---

## 7. 未決問題（需管理者在公司機提供）

- §7 樣板表名／欄位名／RECTYPE 值域實測（規則 6／8）。
- Qwen 寫固定表格 fragment 的實測行數與失敗形狀（是否需再切小）。
- `currentSchema` 回填（FILL_ME 下所有 verify 收據只能是 NOT_RUN）。
- 存量 67 檔中「畫面與欄位」欄位是否一致寫 `RECNAME.FIELDNAME`（G2 配對規則需依實況調整）。
- 首批以 `-BatchSize 1` 觀察單檔可寫性與實際行數，決定 `-ControlPageSize` 預設 30 是否合適。
