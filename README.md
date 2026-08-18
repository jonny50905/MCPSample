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
│  ├─ lessons/applied.md           教訓帳本 L1 ~ L50 ★框架唯一完整的歷史
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

使用者的四個入口。指令本身只是一段 prompt ＋ 指定執行的 agent。

四個指令的 frontmatter 都是 `agent: ps-deep-research`——因為只有它有寫檔權限。

| 指令 | 做什麼 |
|---|---|
| `/ps-research <領域>` | 產完整業務文件：總覽 ＋ 逐功能深查 → `docs/ps-research/<領域>/`。中斷後重跑即續跑 |
| `/ps-audit <領域>` | 稽核：逐檔委派 `ps-auditor` 做證據解引用、claim 反駁抽驗、完整性 diff → 產 `90-audit.md`，問題回灌 checklist |
| `/ps-lesson <描述>` | 模型答錯時登錄教訓：自動分類落點、套用最小修改、記進 `applied.md` |
| `/ps-correct <正確知識>` | 業務知識被指正時更新 wiki entity（作廢不刪除、來源標 human、標 verified） |

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
| **tier 1**<br>覆蓋畢業（可用） | 功能查得到、每份文件有實質內容、沒被截斷或污染 | session 正常收場 ＋ 稽核狀態轉移 ＋ `lint -CoverageOnly` 全過 |
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

| 腳本 | 用途 |
|---|---|
| `ps-doc-lint.ps1` | 文件格式與證據稽核。`-CoverageOnly`＝tier 1 門，`-StrictAudit`＝tier 2 門 |
| `ps-auto-loop.ps1` | 單領域自動迴圈駕駛。`-Preflight` 唯讀驗環境，`-Tier 1\|2` 選目標等級 |
| `ps-auto-all.ps1` | 多領域批次排程（兩趟、驗收據、熔絲） |
| `ps-graduation.ps1` | 收據的寫入與驗證邏輯（唯一真相，不得他處抄寫） |
| `ps-fs-doctor.ps1` | 檔案系統健檢（唯讀）：隱形字元、雙胞胎資料夾、雙 BOM、腳本語法 |

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

## 維護這個框架

改框架之前，**先讀這三份**——對話不是記憶體，歷任維護 session 的所有決策
與因果都在檔案裡：

1. **`AGENTS.md`** — 接手須知、與管理者協作的鐵律（只活在那裡）
2. **`.opencode/peoplesoft/lessons/applied.md`** — L1~L50 教訓帳本，
   每課含症狀／根因／落點。框架的每一條怪規則都能在這裡找到它的屍體。
3. **`.opencode/peoplesoft/SOP.md`** — 現行操作程序

改動規則走**最小新增**（只加不刪）、當天記 `applied.md`、
團隊生效靠內部 git PR。**規則一律從觀察到的行為推導，不從規格書想像。**

---

註：`src/` 底下是與本框架無關的舊有 .NET 範例，不在本文件範圍。
