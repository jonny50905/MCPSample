# PeopleSoft 知識庫分析框架

把一套 PeopleSoft 客製系統，變成**可查詢、可驗證、可持續更新**的業務知識庫。

不是「叫模型讀原始碼然後相信它」。這個框架的核心假設是**模型會出錯、會偷懶、
會宣稱做了沒做的事**——所以每一份產出都要有機器可重跑的證據，每一輪工作
都由確定性的外環驗收，模型說自己做完了不算數。

```
確定性外環（PowerShell）          機率性內層（本機模型）
─────────────────────          ────────────────────
保證「有沒有做」          ←→     決定「怎麼做」
checklist 解析                    領域探勘、證據檢索
lint 格式稽核                     文件撰寫、稽核判定
狀態轉移比對                      委派 subagent
畢業門 / 收據                     回灌待辦項
```

## 這個系統解決什麼問題

PeopleSoft 的業務邏輯散在 Component、PeopleCode、Application Engine、SQR、
Record 定義與 Portal Registry 裡，客製（`TW_` 前綴等）又疊在原生物件之上。
要回答「兵役資料在哪維護」「這個選項選了會跑什麼」，人得跨五六個工具翻半天。

框架的做法：**先用模型把領域探勘成結構化文件，再用機械稽核逼它拿出證據**，
最後沉澱成可直接問答的 wiki。

## 證據契約（整個框架的地基）

只有兩種東西算證據：

| 型別 | 形式 | 為什麼 |
|---|---|---|
| **CHUNK** | 36 字元 UUID 的 chunk id | 可用 `PeoplecodeSource` 原文取回 |
| **SQL** | 可重跑的 `SELECT` | 任何人都能自己跑一次驗證 |

搜尋工具回傳的 snippet、metadata、模型的敘述**都不是證據**，只是定位線索。
縮寫的 id（8 碼）、自編編號、失敗的查詢，一律視為捏造，lint 直接擋。

長文本鐵律：**不可一次載入整支** PeopleCode / SQL / SQR / SQC——一律走
「搜尋候選 → 精確取段 → 定向展開 → 停止」。

## 目錄結構

```text
.opencode/
├─ peoplesoft/                     框架本體（協定、SOP、教訓、模板）
│  ├─ README.md                    架構總覽（三個核心概念、完整檔案說明）
│  ├─ SOP.md                       人工作業程序 SOP-1 ~ SOP-16
│  ├─ lessons/applied.md           教訓帳本 L0 ~ L50 ★框架唯一完整的歷史
│  ├─ oracle-query-cookbook.md     PeopleTools metadata 查詢樣板（SELECT-only）
│  ├─ progressive-source-retrieval.md  長文本檢索協定
│  ├─ subagent-report-contract.md  subagent 回報 JSON 契約
│  ├─ report-templates/            總覽／功能細查／checklist／entity 模板
│  ├─ test-scenarios.md            回歸題庫（A~F 類業務題 ＋ J 類機制檢查點）
│  └─ research-domains.txt         批次佇列（一行一領域）
├─ agent/                          subagent 定義（ps-deep-research、ps-auditor、各 flow）
├─ command/                        /ps-research /ps-audit /ps-lesson /ps-correct
└─ skills/                         ps-business-discovery 等 11 個技能

scripts/                           確定性外環（PowerShell 5.1）
docs/ps-research/<領域>/           研究產出（機密，見下方資安邊界）
docs/ps-research/wiki/             已歸戶的已驗證知識——問答一律先查這裡
```

## 三層構件：command / agent / skill

三者常被混為一談，但職責完全不同：

```text
command  決定「誰上場」   使用者打的 /指令，frontmatter 指定交給哪個 agent
agent    決定「能碰什麼」 獨立 context ＋ 工具白名單（圍堵單位）
skill    決定「怎麼做」   載入當下 context 的作業程序（查法、判準、寫法）
```

### Command（`.opencode/command/`）

使用者的入口。指令本身只是一段 prompt ＋ 指定執行的 agent。

所有指令的 frontmatter 都是 `agent: ps-deep-research`——因為只有它有寫檔權限。

| 指令 | 做什麼 |
|---|---|
| `/ps-research <領域>` | 產完整業務文件：總覽 ＋ 逐功能深查 → `docs/ps-research/<領域>/`。中斷後重跑即續跑 |
| `/ps-audit <領域>` | 稽核：逐檔委派 `ps-auditor` 做證據解引用、claim 反駁抽驗、完整性 diff → 產 `90-audit.md`，問題回灌 checklist |
| `/ps-lesson <描述>` | 模型答錯時登錄教訓：自動分類落點、套用最小修改、記進 `applied.md` |
| `/ps-correct <正確知識>` | 業務知識被指正時更新 wiki entity（作廢不刪除、來源標 human、標 verified） |
| `/ps-contract-batch <領域>` | Legacy Contract 批次（外環專用）：依 `contract-parts/manifest.txt` 只寫本批 fragment（固定表格）；SOP-18 |
| `/ps-contract-verify <領域>` | Legacy Contract 的 Oracle schema 唯讀驗證批次（外環專用）：每單位（OBJ／FLD／RQ）寫 `verify-<RECNAME>-<單位>.md` 收據 |

後兩者「本機立即生效」，團隊生效走內部 git PR 審核。

純問答不要用這些指令——問答走 `ps-orchestrator`（Tab 切換），它不產文件。

### Agent（`.opencode/agent/`）

分三類。**primary** 可以直接對話，**subagent** 只能被委派，**覆寫檔**是把
OpenCode 內建 agent 重新上鎖。

| Agent | 類型 | 職責 |
|---|---|---|
| `ps-orchestrator` | primary | 業務問答主流程：解析領域與客製政策，把重檢索委派出去，彙整 JSON 報告後產出業務說明 |
| `ps-deep-research` | primary | 文件生成：總覽 ＋ 調查 checklist ＋ 逐功能深查，可中斷續跑 |
| `ps-auditor` | subagent | 稽核：證據解引用驗證（chunk／SQL 重查比對）、claim 反駁、換角度完整性盤點 |
| `ps-ui-flow` | subagent | 畫面顯示文字、選項 label↔儲存值、Component/Page/Record.Field 對映 |
| `ps-peoplecode-flow` | subagent | 事件與分支邏輯（FieldChange／SaveEdit／SavePre/PostChange…），漸進式取段 |
| `ps-sql-flow` | subagent | SQL Definition／View SQL／AE SQL，table 讀寫分類、Meta-SQL、動態 SQL |
| `ps-sqr-flow` | subagent | SQR/SQC：先 outline 再定向取段，procedure call graph、SQC include |
| `ps-ae-flow` | subagent | Application Engine：Section/Step/Action 結構、Call Section 鏈、State Record |
| `ps-metadata-flow` | subagent | 資料血緣、Process Scheduler 執行方式、授權路徑（Menu→Component→PL→Role） |
| `explore`／`general`／`scout` | 覆寫 | OpenCode 內建 agent 的同名覆寫——**唯一目的是補鎖** |

**兩條非讀不可的設計規則：**

1. **`tools` 是覆寫表，沒列出的工具一律預設開啟。** 所以不屬於某個 subagent 的
   MCP 必須**明確寫 `false`**，不能靠「不列」。內建的 explore／general／scout
   不在本專案的封鎖體系內，因此要同名覆寫補鎖——否則委派漏到內建 agent 時，
   檢索 MCP 與 bash 全是開的。
2. **主 context 絕不取 source chunk。** `ps-orchestrator` 把三個檢索 MCP 全部
   deny，長文本與 metadata 一律委派給 subagent，subagent 回傳壓縮過的 JSON
   報告。這不是效能考量——是防止主 context 被長文本撐爆而觸發自動壓縮，
   把已經驗證過的證據悄悄丟掉。

subagent 回報一律遵守 `subagent-report-contract.md`：單一 JSON、單段引用 ≤ 5 行、
必附 evidence IDs。

### Skill（`.opencode/skills/`）

作業程序。agent 是「誰去做」，skill 是「怎麼做」——在一般 agent 底下處理
PeopleSoft 問題時，載入對應 skill 就能照同一套流程走。

| Skill | 內容 |
|---|---|
| `ps-business-discovery` | **業務問題入口**：解析 business domain 與客製政策（CUSTOM_ONLY_ROOTS／CUSTOM_FIRST），定位業務根物件 |
| `ps-business-explain` | **最終彙整**：把各 flow 的證據轉成業務說明；畫面文字與儲存值分開、標 CONFIRMED／INFERRED／DYNAMIC_RUNTIME、原生物件僅列 Dependency |
| `ps-ui-flow` | 畫面顯示文字、選項 label↔儲存值、由文字反查 Component/Page/Record.Field |
| `ps-peoplecode-flow` | PeopleCode 事件與分支邏輯，漸進式取段、不整支載入 |
| `ps-sql-flow` | SQL Definition／View／AE SQL：table 讀寫分類、Meta-SQL、動態 SQL |
| `ps-sqr-flow` | SQR/SQC：outline 優先、procedure call graph、SQC include、報表輸出 |
| `ps-ae-flow` | Application Engine 結構與 Call Section 鏈 |
| `ps-process-flow` | 批次執行方式：Process Definition／Job／Recurrence／Run Control |
| `ps-security-flow` | 授權路徑：Menu → Component → Permission List → Role 與 Row-level Security |
| `ps-data-lineage` | Record.Field 資料血緣：上下游誰讀誰寫（READ／UPDATE／…／DYNAMIC_RUNTIME） |
| `ps-impact-analysis` | （選配）物件變更影響盤點：UI/PeopleCode/SQL/SQR/AE/Process/Security 引用面與嚴重度分級 |

多數 flow 類 skill 有**同名 subagent**——那不是重複：skill 是流程規則本身，
同名 agent 是「把這套流程包進獨立 context」的委派對象。輕量查詢直接載 skill
在當下 context 做；重檢索（會拉大量原始碼）就委派給同名 agent，讓長文本
留在它自己的 context 裡。

典型串法：`ps-business-discovery`（定位）→ 各 flow（取證）→ `ps-business-explain`（彙整）。

## 日常操作

### 問答

走 `ps-orchestrator` agent。先查 `docs/ps-research/wiki/`，wiki 沒有或
標記未驗證，才現場檢索。查無證據就照實說——不編造物件名稱或執行期結果。

### 產文件

```text
/ps-research <領域>     領域探勘：總覽 ＋ 逐功能細查（中斷後重跑即續跑）
/ps-audit <領域>        稽核：證據解引用、claim 反駁抽驗、完整性 diff
                        → 產 90-audit.md，問題回灌 checklist
/ps-lesson <描述>       模型答錯 → 登錄教訓，自動套用最小修改
/ps-correct <正確知識>  業務知識被指正 → 更新 wiki entity（作廢不刪除）
```

### 機械稽核

```powershell
powershell -File .\scripts\ps-doc-lint.ps1 -Domain <領域>
```

30 秒、不經模型、可重複。任何寫入波之後都該跑一次。有違規時會在最後印出
**手術式修復指令**——整段複製貼給模型，逐筆修完再跑一次。

檢查項、三種模式、工單型別與 exit code 見下方[腳本](#腳本)章節。

### 自動迴圈

```powershell
# 先驗環境（唯讀，不啟動任何 session）
powershell -File .\scripts\ps-auto-loop.ps1 -Domain <領域> -Preflight

# 開跑
powershell -File .\scripts\ps-auto-loop.ps1 -Domain <領域>
```

外環自己決定每圈要跑 research 還是 audit、跑完驗收、有問題自動餵一個
修復 session，達標就發收據停機。log 在 `auto-loop-logs\<領域>\`——
早上看摘要即可。

### 多領域批次

```powershell
powershell -File .\scripts\ps-auto-all.ps1 -MaxCyclesPerDomain 8
```

佇列讀 `.opencode/peoplesoft/research-domains.txt`。預設**兩趟**：
所有領域先跑到 tier 1，全部跑完才開第二趟做 tier 2。

## 兩段式畢業

單一的「完美門」在這種系統裡等於沒有終點——修復寫入會以低固定率播下新
瑕疵，稽核每輪回灌新項，第一個領域會吃掉全部時間、其餘領域停在零分。
所以完工標準分兩級，排程走廣度優先。

| | 保證什麼 | 門檻 |
|---|---|---|
| **tier 1**<br>覆蓋畢業（可用） | 功能查得到、每份文件有實質內容、沒被截斷或污染 | session 正常收場 ＋ 稽核狀態轉移 ＋ `lint -CoverageOnly` 全過 ＋ 研究範圍完成（原始調查項／D 項全建檔，#23） |
| **tier 2**<br>精修畢業 | 每句話都能逐條回溯驗證 | 上述 ＋ 待辦清零 ＋ lint 全綠 ＋ `-StrictAudit` 全綠 |

tier 1 **不保證每句話能回溯驗證**——證據 id 格式、機器參照、confidence
標註屬「美工類」，留給 tier 2。這是刻意的取捨：先讓每個領域都可用。

### 畢業收據

達標時寫入 `docs/ps-research/<領域>/graduation.json`，記錄 tier、稽核輪次，
以及三個指紋：領域內容、lint 腳本、門檻腳本。**任何一個變了，收據自動失效**
——所以改 lint 就等於宣告全部領域重驗（衝刺期因此要凍結標準）。

收據是**單機事實**，不進 git：各機各自驗證、各自畢業。

## 熔絲

自動迴圈是無人看管的長時間作業，所以停機條件比執行邏輯更重要：

```text
畢業（門全過）              連續 2 圈無進度
連續 2 次 session 錯誤       連續 2 次逾時
強殺後檔案一致性 FAIL        稽核相位連續 2 圈零回灌未畢業（活鎖）
圈數上限
```

每條熔絲都是**照實測基線設的，不是照直覺**——過敏的警告會訓練人忽略警告，
比沒有警告更糟。

## 腳本

七個是框架本體，兩個是前一個專案的遺留。全部 PowerShell 5.1、**UTF-8 with
BOM**，從哪個工作目錄執行都可以（腳本自己以 `$PSScriptRoot` 反推 repo 根；
放錯資料夾會印 WARN）。

| 腳本 | 一句話 | 寫檔 |
|---|---|---|
| `ps-doc-lint.ps1` | 文件格式與證據的確定性稽核 ＋ 產手術工單 | 唯讀 |
| `ps-auto-loop.ps1` | 單領域自動迴圈駕駛 | log、收據 |
| `ps-auto-all.ps1` | 多領域批次排程 | log |
| `ps-graduation.ps1` | 收據的寫入與驗證（函式庫，不直接執行） | 收據 |
| `ps-fs-doctor.ps1` | 檔案系統健檢 | 唯讀（`-FixBom` 例外） |
| `ps-contract.ps1` | Legacy Contract 外環（issue #17）：NN 抽取→manifest→fragment 驗收→canonical JSON→spec render→G1～G18 | `contract-parts/`、`contract/` |
| `ps-contract-lib.ps1` | 上者的函式庫（值域解析／不變量／stable ID／merge／render／gate；不直接執行） | — |
| `test-mcp-tools-list.ps1`<br>`test-elasticsearch-mcp-tools-list.ps1` | **遺留**，與本框架無關 | — |

---

### `ps-doc-lint.ps1` — 第一層稽核

```powershell
powershell -File .\scripts\ps-doc-lint.ps1 -Domain <領域>
powershell -File .\scripts\ps-doc-lint.ps1 -Domain <領域> -CoverageOnly
powershell -File .\scripts\ps-doc-lint.ps1 -Domain <領域> -StrictAudit
```

**定位**：這是**確定性**那一層——不經模型、30 秒、同樣輸入永遠同樣輸出。
第二層是 `/ps-audit`（模型重新取證）。兩層職責不重疊：lint 只判**機械上可
判定**的事（欄位格式、檔案是否存在、章節是否空殼），不判內容對不對。

任何一波寫入之後都該跑一次。

#### 三種模式

| 模式 | 誰在用 | 差別 |
|---|---|---|
| 無開關 | 人工（SOP-2） | 結構性問題只警告不擋——手動檢查不該被格式問題卡住 |
| `-CoverageOnly` | **tier 1 畢業門** | 美工類違規降為警告；記分卡塌縮升為違規；工單只出 `[洩漏]` 型 |
| `-StrictAudit` | **tier 2 畢業門** | `90-audit.md` 的結構性問題由警告升為 FAIL |

`-CoverageOnly` **不是新增檢查，是把既有檢查分兩段收**。標準沒有變嚴。

分類採**白名單**：只有明確列在 `$polishPatterns` 的訊息算美工，**其餘一律算
缺料**。這是 fail-safe——分類漏掉只會讓門更嚴，不會放水。

#### exit code

```text
0  全部通過
1  有違規（違規清單與手術工單印在最後）
2  環境錯誤：領域目錄不存在，或 -Domain 參數含隱形字元
```

#### 檢查項

**缺料類**（tier 1 就擋——「有沒有東西可讀」）

| 類別 | 檢查 |
|---|---|
| 檔案存在 | 缺 `00-overview.md`（附近似檔名收據，分辨假缺／真缺／掃錯目錄）、空檔（0 byte） |
| 章節完整 | 缺必要章節、章節空殼（有標題無實質內容：僅 HTML 註解、佔位符、「同前」類省略語） |
| checklist 對帳 | 已打勾但檔案不存在、檔案未列於調查進度、歸檔檔含未打勾項、缺節標題（破壞性覆寫指紋） |
| 寫入脫軌 | 模型內部標記洩漏進交付物、subagent 回報 JSON 原樣洩漏 |
| 稽核報告 | `90-audit.md` 不存在、缺「稽核輪次」表頭、輪次與 checklist 不一致、**記分卡未逐檔列出檔名** |

**美工類**（tier 1 降警告，tier 2 才擋——「每句話能不能回溯驗證」）

| 檢查 |
|---|
| ChunkId 遭縮寫為 8 碼 / 非 UUID 格式 / 自編 id 樣式 / 廣域偵測到的縮寫 id |
| Evidence 附錄空白 |
| 機器參照無效（既非 36 字元 ChunkId、也非可重跑 SELECT） |
| 機器參照欄放的是標籤（如「PeopleCode chunk」「OracleMCP」）而證據其實在位置欄 |
| 以**失敗查詢**（ORA- 錯誤、查無此表）當機器參照 |
| 行為邏輯無任何 confidence 標註 |
| wiki frontmatter 缺 key、`status` 值非法 |

**只警告，任何模式都不升級**

wiki 層（`docs/ps-research/wiki/`）是**跨領域共用**的——把它升為違規，會讓
A 領域的畢業被 B 領域的斷鏈鎖死。所以 wikilink 斷鏈、孤兒 entity、
`last_verified` 超過 90 天一律只警告。

同一類的還有：`00-overview.md` 換版落後（SOP-15）、功能地圖缺後續發現項目、
表格欄位數與表頭不一致、「待人工SQL」列數統計（合法待辦，非違規）。

#### 手術工單

有違規時，**最後**會印出一段 `=== 證據修復指令 ===`（印在最後才不會被警告牆
洗掉）。整段複製貼給 `ps-deep-research`，或由 `ps-auto-loop` 自動餵。

工單分三型，**先判型別再動手，判錯型別等於白做**：

| 型別 | 現象 | 修法 |
|---|---|---|
| `[洩漏]` | 模型內部標記寫進了交付物 | **不是刪掉標記就好**——要看標記前後整個區塊有沒有被截斷（表格斷半路、章節缺下半段），補回內容；補不回就記「因寫入脫軌遺失，待重查」 |
| `[欄位]` | 證據在位置欄，機器參照欄放的是標籤 | **純編輯，不重查、不呼叫任何工具**——把可重跑的那一份搬到機器參照欄。證據內容一個字都不准改 |
| `[證據]` | 缺 id、壞 id、或失敗查詢當證據 | 先分 CHUNK 型（委派檢索 flow 重取）或 SQL 型（委派具 oracleMCP 權限的 flow 重跑），都取不到就降級 INFERRED 入 gaps |

`[欄位]` 型**按檔合併**成一個任務（對調欄位是純編輯，一個檔一次改完最省）；
`[洩漏]`／`[證據]` 型逐列開單。

另有一份 **人工處理清單**印在工單之外，**不要貼給模型**——`checklist.md`
（熱檔，整檔重寫可能吃掉未勾項）、`00-overview.md`（已凍結）、`90-audit.md`
（下一輪會整檔重寫）這三類的洩漏，手動刪最安全。

#### `-Domain` 參數消毒

`-Domain` 尾部的空白或點會觸發 Windows 尾字元正規化不對稱：**目錄查得到、
其下檔案全查無**——一個完美的假缺檔。所以參數會先 `Trim()` 並印 WARN；
含隱形字元（FEFF、零寬空格、NBSP）直接 exit 2 並要你跑 `ps-fs-doctor`。

**領域名請用鍵盤手打，不要從別處貼上。**

---

### `ps-auto-loop.ps1` — 單領域自動迴圈

```powershell
# 唯讀驗環境，不取鎖、不啟動任何 session
powershell -File .\scripts\ps-auto-loop.ps1 -Domain <領域> -Preflight

# 開跑
powershell -File .\scripts\ps-auto-loop.ps1 -Domain <領域>
```

每圈：決定相位（research 還是 audit）→ 跑一個 session → lint → 有工單就餵
手術 session → 驗畢業門 → 過了發收據停機，沒過進下一圈。

| 參數 | 預設 | 說明 |
|---|---|---|
| `-Domain` | 必填 | 領域名（手打） |
| `-Tier 1\|2` | 1 | 目標等級。1＝覆蓋畢業，2＝精修畢業 |
| `-MaxCycles` | 20 | 圈數上限（熔絲） |
| `-MaxSurgeryPerCycle` | 3 | 一圈最多連跑幾批手術。真正的收斂煞車是「本批沒讓清單變短就停」，這個只是時間圍欄 |
| `-SurgeryBatchSize` | 7 | 一批塞幾筆工單。本圈最多處理 = 兩者相乘 |
| `-ResearchTimeoutMin` | 60 | research 與**手術** session 的逾時 |
| `-AuditTimeoutMin` | 120 | audit session 的逾時 |
| `-Model` | （空） | 覆寫本次用的模型；留空吃 opencode 全域預設 |
| `-Preflight` | — | 只檢查並列印，不啟動任何 session |

```text
exit 0  畢業（收據已寫）
     1  未畢業
     2  環境或收據錯誤
     3  互斥鎖被占用（另一個迴圈在跑）
```

**逾時是熔絲不是效能參數**，要照實測值設。log 在 `auto-loop-logs\<領域>\`。

`-Preflight` 會印：checklist 未勾／已勾／稽核輪次、起始相位、三個 lint 的
exit、tier 1 的工單數、現有收據有效與否、熔絲設定。**要判斷「現在該不該再
跑一輪」，看這個就夠了。**

---

### `ps-auto-all.ps1` — 多領域批次

```powershell
powershell -File .\scripts\ps-auto-all.ps1 -MaxCyclesPerDomain 8
```

佇列讀 `.opencode/peoplesoft/research-domains.txt`（一行一領域，`#` 註解）。
職責只有：讀佇列 → preflight → 驗收據 → 逐一以**子行程**呼叫 `ps-auto-loop`
→ 記錄。**它不呼叫模型、不寫 checklist、永不寫收據。**

| 參數 | 預設 | 說明 |
|---|---|---|
| `-Tier 0\|1\|2` | 0 | 0＝兩趟（所有領域先到 tier 1，再全部做 tier 2） |
| `-MaxDomains` | 0 | 0＝不限；只計實際 RUN，SKIP 不消耗 |
| `-MaxBatchHours` | 0 | 0＝不限。**只在領域之間檢查，攔不住進行中的領域** |
| `-MaxCyclesPerDomain` | 0 | >0 時透傳給 loop 的 `-MaxCycles`——**跑批務必設這個** |
| `-MaxConsecutiveFailures` | 3 | 連續失敗熔斷 |
| `-Force` | — | 忽略有效收據，全部重驗 |
| `-Model` | （空） | 透傳 |

嚴格循序：領域之間共享 Entity Wiki／oracleMCP／working tree，禁止並行。
子行程呼叫代表**行程死亡時 OS 自動回收互斥鎖**，不會留下 stale lock。

---

### `ps-graduation.ps1` — 收據函式庫

**不直接執行**，由 `ps-auto-loop`（寫收據）與 `ps-auto-all`（驗收據）
dot-source。hash 計算與收據驗證**只有這一份真相**，禁止在別處各抄一份。

三個設計決策值得知道：

- hash 範圍用**排除法**（領域目錄全部 `*.md` 減 `log.md`），不是列舉法——
  列舉法漏掉散檔就會漏出範圍，而 `-Filter` 不支援 `[0-9]` 字元類、會靜默
  匹配失敗。
- 內容先**剝 BOM 與 `\r` 再 hash**——人工搬運與 git autocrlf 不會造成假失效。
- 檔名以 **Ordinal 排序**——`Sort-Object` 是 culture-sensitive，中文檔名跨機
  不定序。

改動 `ps-auto-loop` 的畢業門判定時，**必須手動 bump `GraduationGateVersion`**
——門邏輯不在任何 hash 覆蓋內。

---

### `ps-fs-doctor.ps1` — 檔案系統健檢

```powershell
powershell -File .\scripts\ps-fs-doctor.ps1 -Domain <領域>
powershell -File .\scripts\ps-fs-doctor.ps1 -Domain <領域> -FixBom
```

**每次人工搬運之後都要跑。** 專治「Explorer 看得到、程式找不到」——在
Windows 上這幾乎都是隱形字元或雙副檔名。

輸出最後一行是**結論代號**（可複選，例 `A+D`）：

```text
A  00-overview 其實存在（假缺——當時 lint 的 -Domain 輸入被污染，手打重跑）
B  檔名異常（變體／隱形字元）
C  資料夾雙胞胎或資料夾名異常
D  內文 FEFF 污染（雙 BOM 病；.ps1 可加 -FixBom 自動修）
E  真缺檔或路徑對不上（走 SOP-4 還原）
F  這次輸入的參數含隱形字元
S  腳本語法解析失敗（搬運不完整，重新複製整檔）
G  全部正常
```

**資安設計**：實際路徑與檔名只印在你自己螢幕上。回報維護 session 時
**只需要講代號那一行**，不必貼任何輸出。

---

### `ps-contract.ps1` — Legacy Contract 外環（issue #17 Phase 1）

把已研究的領域翻成「新系統可直接實作」的 Behavior＋Persistence 契約：模型只寫
固定表格 fragment（`contract-parts/screen-<COMPONENT>.md`、`entity-<RECNAME>.md`，
每檔 ≤150 行、值只准 `legacy-contract-vocabulary.md` 的封閉值域、證據只引
NN 附錄的 `E<nn>.<n>` 或本檔查詢表的 `SQL:<n>`；控制項多於頁大小時由外環切成
分頁檔 `screen-<COMPONENT>-p<k>.md`），其餘全是確定性外環：

```powershell
.\scripts\ps-contract.ps1 -Domain 兵役 -Plan         # 抽 NN 事實、寫 contract-parts\manifest.txt
opencode run --command ps-contract-batch --title auto-ct "兵役"   # 模型寫本批 fragment
.\scripts\ps-contract.ps1 -Domain 兵役 -All          # Accept → Merge → Render → Gate（tier 1）
.\scripts\ps-contract.ps1 -Domain 兵役 -Gate -Tier 2 # 零 UNRESOLVED 才過
.\scripts\ps-contract.ps1 -Domain 兵役 -VerifyPlan   # Oracle schema 驗證工單（G16；cookbook §7）
```

產物：`contract/legacy-contract.json`（canonical，單一真相；stable ID 由外環派發）、
`contract/spec/<COMPONENT>.spec.md`（18 節 developer-facing spec，deterministic render，
手改會被 G18 抓）、`contract/contract-gate.json`（G1～G18＋debt 清單，供 Phase 2～5 繼承）、
`contract/contract-ledger.json`（fragment 級收據＋每 Component 控制項頁大小）。exit 0／1／2 同 lint。
`DIRECT_DB_WRITE_APPROVED` 只能由人填 `contract/approvals.md` 產生。
設計備忘：`docs/design/legacy-contract-phase1-decision-memo.md`；操作：SOP-18；教訓：L108。

---

### 遺留腳本

`test-mcp-tools-list.ps1` 與 `test-elasticsearch-mcp-tools-list.ps1` 是前一個
.NET 專案（`src\HanshinChat.Mcp.Server`）的 MCP smoke test，與本框架無關，
也不會被任何流程呼叫。留著只是還沒清。

## 環境紀律

這些不是建議，是踩過坑之後的硬規定（每一條在 `applied.md` 都有對應教訓）：

- **PowerShell 5.1**：沒有三元運算子／`??`／`&&`，`Join-Path` 只吃兩個參數，
  `Get-ChildItem -Filter` 不支援 `[0-9]` 字元類（會靜默匹配失敗）。
- **`scripts/*.ps1` 一律 UTF-8 with BOM**：無 BOM 會讓 PS 5.1 把中文誤解析成
  語法錯誤；雙 BOM 則造成「`#` 不是 cmdlet」或 `InvalidLeftHandSide`。
- **路徑一律 `-LiteralPath`**：`Test-Path -Path` 把路徑當萬用字元，
  會產生「看得到、程式找不到」的假缺檔。
- **檔案搬運後跑 `ps-fs-doctor`**：檢查 D 抓 BOM 污染、檢查 S 比對腳本行數，
  貼上被截斷會在這裡現形。

## 資安邊界

- **`docs/ps-research/**` 是公司機密**：只進內部 git，嚴禁外部 remote 或公開貼出。
- repo 內禁放執行檔與「繞過」類字串。
- oracleMCP 一律 SELECT-only，照 `oracle-query-cookbook.md` 的樣板走，
  且有列數上限。

## 為什麼是這樣設計的

### 要解決的問題

一套跑了 30 年的 PeopleSoft，業務邏輯只存在兩個地方：**老同事的腦袋裡，
和百萬行程式裡**。

> 「免役這個選項在哪裡維護？選了以後系統會執行什麼？」

以前要回答這個問題，得翻程式好幾天，或者去找還記得的人。找不到人、
或人記錯了，就沒有第三條路。

目標是讓人用中文問，AI 在公司內部檢索程式碼與資料庫，**幾分鐘給出附
程式證據的答案**。

### 四個非功能目標（決定了所有技術選擇）

| 目標 | 導出的約束 |
|---|---|
| **機密不出公司** | 地端模型 ＋ 內網 MCP，程式碼與資料零外流。這條直接排除了所有雲端 API 方案，也決定了模型是中型而非最強 |
| **答案附證據** | 每個結論標註出處與可信度，格式不對＝視同捏造。杜絕「一本正經地胡說」 |
| **知識會累積** | 查過的物件歸戶進知識庫，第二次問直接命中——越用越快越準 |
| **錯誤會記取** | 答錯經指正後進入教訓機制，跨 session 不再犯（模型本身不會學習，教訓必須外部化） |

### 研究過的做法與取捨

設計前比較過幾條路。這裡記的是**為什麼沒選另一條**：

| 議題 | 候選做法 | 決定 |
|---|---|---|
| 知識怎麼存 | flat RAG（切塊 ＋ 相似度檢索） | **不選**。2026-07 的研究結論：編譯過的互連 wiki 在多跳檢索上勝過 flat RAG 約 6~8 F1。業務問題幾乎都是多跳的（畫面 → 欄位 → 程式 → 資料表 → 排程） |
| 知識怎麼存 | 編譯過的互連 wiki（一物一檔 ＋ typed 連結） | **選這個**。問答沿 `[[連結]]` 走就能追出完整業務脈絡 |
| 怎麼檢索 | 向量／語意搜尋 | **不選**。ERP 物件名是**精確識別字**（`TW_MILITARY_DATA`），語意相似度在這裡幫不上忙，而且結果不可驗證 |
| 怎麼檢索 | 確定性 index-first（目錄 ＋ 精確比對） | **選這個**。對地端模型更可靠，而且每一步都能重跑驗證 |
| 連結怎麼實作 | 圖資料庫／專用工具 | **不選**。多一個要維護的服務，內網環境每多一個依賴就多一個故障點 |
| 連結怎麼實作 | `[[wikilink]]` 純文字 | **選這個**。backlink 用 grep 就能重建——**不需要任何工具**；順帶白送 Obsidian 當閱讀介面 |
| 長文本怎麼讀 | 整支載入讓模型自己找 | **不選**。中型模型的 context 裝不下，而且撐爆會觸發自動壓縮 |
| 長文本怎麼讀 | 漸進式檢索（搜尋候選 → 精確取段 → 定向展開 → 停止） | **選這個**。這是原始規格三個核心概念之一，PeopleCode／SQL／SQR／SQC 共用同一套協定 |
| 誰來把關品質 | 讓模型自我檢查 | **不選**。同一顆模型不會發現自己的盲點 |
| 誰來把關品質 | 職責分立：寫的人 ≠ 審的人 | **選這個**。研究員 AI 寫、稽核員 AI **不看推理過程自己重新取證**、人工蓋章——借的是審計的獨立性原則 |

### 直接沿用的既有設計

**雙層搜尋**——這個 repo 的前身是一套 HanshinChat 的搜尋系統：
Elasticsearch 負責第一層全文搜尋拿到命中 id，第二層再補完整明細。
那個模式被原樣搬過來變成 **ES 定位 chunk id → Source 取回完整段落**，
連「第一層只定位、第二層才是正式資料」的分工都一樣。

也因此有了證據契約的雛形：**搜尋結果是候選，取回的段落才算數。**

**superpowers 的工作流**——`docs/superpowers/specs/` 與 `plans/` 這個目錄
結構不是自創的，是 superpowers 那套 spec → plan → subagent 逐步實作的
慣例。這個框架的原始需求文件就是照它的格式寫的（`2026-07-16-peoplesoft-
skill-custom-ui-source-addendum.md`），實作也是照 plan 的 checkbox 一項項推。

**Deep research 模式**——`/ps-research` 的形狀（給一個題目 → 自動盤點
子問題清單 → 逐項深查 → 產出文件集 → 可中斷續跑）借自 deep research
類代理的通用做法。差別在於這裡的「子問題清單」是一個**磁碟上的
checklist 檔**而不是模型的記憶——所以中斷之後重打同一個指令就會接著跑。

**MCP（Model Context Protocol）**——工具層全部走 MCP，四個資料源
（程式碼搜尋／原始碼取段／中繼資料反查／Oracle 查詢）各自是獨立 server，
agent 用白名單各拿各的鑰匙。

### 從別處借的形狀

- **entity–observation–relation**：知識庫每個檔的內部結構（一行一個事實 ＋
  帶型別的關係）借自知識圖譜式記憶的慣例，讓「一個物件」成為可獨立載入
  的最小單位——中型模型一次只需要讀一個 entity。
- **Obsidian vault**：`[[wikilink]]`、backlink、graph view 的用法。純選配，
  不裝完全不影響功能（SOP-7）。
- **append-only 帳本**：事實被推翻時不刪除，搬進 `Invalidated` 節標日期與
  原因。「我們曾經以為是這樣」本身是有價值的資訊，而且能防止人工審定過
  的內容被悄悄覆寫。
- **回歸測試套件**：`test-scenarios.md` 的 45 個情境，每一題守住一個踩過的坑，
  改版必跑。把軟體工程的回歸測試觀念套到「規則遵循」上——A~I 類考業務題
  （規矩在已知答案的兵役案例守得住，任何領域就守得住），J 類考框架機制本身。

### 後來的演化

以上是**設計時想清楚的部分**。實際跑起來之後又改了很多——那些改動的
症狀、根因與落點全部記在 `applied.md` 的 L0~L50，包括確定性外環、
三層畢業門與兩段式畢業這些**當初沒有預見、是實跑逼出來的**機制。

要理解某條規則為什麼長成那樣，去那份帳本找它的編號。

## 維護這個框架

改框架之前，**先讀這三份**——對話不是記憶體，歷任維護 session 的所有決策
與因果都在檔案裡：

1. **`AGENTS.md`** — 接手須知、與管理者協作的鐵律（只活在那裡）
2. **`.opencode/peoplesoft/lessons/applied.md`** — L0~L50 教訓帳本，
   每課含症狀／根因／落點。框架的每一條怪規則都能在這裡找到它的屍體。
3. **`.opencode/peoplesoft/SOP.md`** — 現行操作程序

改動規則走**最小新增**（只加不刪）、當天記 `applied.md`、
團隊生效靠內部 git PR。**規則一律從觀察到的行為推導，不從規格書想像。**

---

註：`src/` 底下是與本框架無關的舊有 .NET 範例，不在本文件範圍。
