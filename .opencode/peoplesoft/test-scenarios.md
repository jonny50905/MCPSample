# PeopleSoft Skills 測試情境（本地模型準確度驗收）

用來測試本地模型（目標：Qwen 3.5 9B）掛上 `.opencode/` 的 ps-* Skill 後，
是否遵守 Plan Addendum 的規則。共 27 題，分 6 類（F 類需 subagent 架構），全部基於
`test-fixtures.yaml` 的假想環境（TW_MILITARY_DATA 兵役案例）。

---

## 1. 三階段測試法

| 階段 | 需要什麼 | 測什麼 | 用哪些題 |
|---|---|---|---|
| **S1 路由測試** | 只要 Skill 檔，不需 MCP | 問題 → 選對 Skill、解析對 domain / 搜尋模式 | 全部題目的「預期路由」欄 |
| **S2 規則遵循** | Mock MCP 回傳 fixtures | 工具呼叫順序、防呆（不 dump、不拿 snippet 當證據） | B、C、D、F 類為主 |
| **S3 答案準確度** | 同 S2 完整跑完 | 最終回答內容對不對、格式對不對 | 全部，重點 E 類 |

S1 可以大量快跑（每題只看模型第一步宣告）；S2/S3 需要記錄**完整工具呼叫
transcript** 才能評分。

---

## 2. 評分方式

- 每題有數個檢查點，標 `[致命]` / `[主要]` / `[次要]`。
- **任何 [致命] 檢查點失敗 → 該題 0 分**（防呆被突破）。
- 否則該題得分 = 通過檢查點數 ÷ 檢查點總數。
- 總準確度 = 各題平均；另外分類統計（A~E）找弱項。
- 同一題建議跑 3 次取平均（小模型輸出不穩定）。

### LLM 評分者 Prompt 模板

```text
你是評分者。輸入：(1) 測試情境含檢查點 (2) 受測模型完整回答與工具呼叫紀錄。
逐一判定每個檢查點 PASS / FAIL，並引用紀錄中的證據。
任何 [致命] 檢查點 FAIL 則整題 0 分。
輸出 JSON：
{ "scenarioId": "...", "checkpoints": [ { "id": 1, "verdict": "PASS", "evidence": "..." } ],
  "fatalTriggered": false, "score": 0.8 }
```

### 結果記錄欄位（CSV）

```text
scenarioId, stage(S1/S2/S3), model, runDate, run#, score, fatalTriggered, notes
```

---

## 3. 測試資料

所有題目以 `test-fixtures.yaml` 為標準答案來源，重點物件：

| 物件 | Origin | 用途 |
|---|---|---|
| `TW_MILITARY_DATA` Component（→ `TW_MILITARY_PG` / `TW_MILITARY`） | CUSTOM_PREFIX | 兵役根物件 |
| `MIL_SVC_TRACKING` Component | DELIVERED | **陷阱**：描述與兵役相似的原生物件 |
| `HR_NAME_SYNC` Record | CUSTOM_REGISTRY | 無 TW_ 前綴的客製（登錄表判定） |
| `PERSONAL_DATA` Record | MODIFIED_DELIVERED | 原生名稱、內容已改 |
| `MIL_STATUS` 欄位 | — | Translate：N/S/D/E/A ↔ 未服役/服役中/已退伍/免役/替代役 |
| `HANDLER_EMPLID` 欄位 | — | **陷阱**：高基數 Prompt（PERSONAL_DATA，約 3 萬筆） |
| `EXEMPT_RSN` 欄位 | — | Label 與選項由 PeopleCode 動態指定 |
| `TW_MIL001` SQR + `TWMILUTIL` SQC | CUSTOM_PREFIX | 長文本漸進檢索、動態 table |
| `TW_MIL_AE` AE、`TW_MIL_UPD_SQL` SQL、`TWMIL001` Process | CUSTOM_PREFIX | SQL 分類、排程、血緣 |
| `HR_COMMON_UTIL` FUNCLIB | DELIVERED | 被 TW_ PeopleCode 呼叫的原生 Utility（只能是 Dependency） |

---

## 4. 情境清單

## A 類：業務發現與客製政策（ps-business-discovery）

### A1 兵役根物件定位（基本盤）
- **輸入**：`兵役資料在哪裡維護？`
- **預期路由**：ps-business-discovery；domain=`military_service`（alias 兵役）；mode=`CUSTOM_ONLY_ROOTS`
- **標準答案要點**：根物件 `TW_MILITARY_DATA`（CUSTOM_PREFIX）→ `TW_MILITARY_PG`；回報 domain / scope / policy / origins / fallback
- **檢查點**：
  1. [主要] 搜尋前先載入 / 引用 customization profile 與 domain map
  2. [主要] 正確回報 domain=military_service、mode=CUSTOM_ONLY_ROOTS
  3. [致命] 沒有把 `MIL_SVC_TRACKING`（DELIVERED）當成根物件
  4. [主要] 根物件=TW_MILITARY_DATA 且 origin=CUSTOM_PREFIX
  5. [次要] 回報 deliveredFallbackUsed=false

### A2 Alias 變形
- **輸入**：`役男的資料要去哪個畫面改？`
- **預期路由**：同 A1（alias 役男 命中 military_service）
- **檢查點**：
  1. [主要] 由 alias「役男」解析到 military_service（不是字面搜「役男」物件名）
  2. [主要] 答案同 A1 根物件
  3. [次要] 有指出 Page（TW_MILITARY_PG）

### A3 原生描述相似陷阱
- **輸入**：`我看到有個 Military Service Tracking 的功能，兵役是不是用它做的？`
- **標準答案要點**：不是。該物件為 DELIVERED；此 domain 是 CUSTOM_ONLY_ROOTS，兵役實作在 TW_MILITARY_DATA；MIL_SVC_TRACKING 未被客製流程使用（fixtures 中無相依關係）
- **檢查點**：
  1. [致命] 沒有因描述相似就把 MIL_SVC_TRACKING 當成兵役主要實作
  2. [主要] 有查 / 引用 object origin（DELIVERED）
  3. [主要] 明確說出正確根物件 TW_MILITARY_DATA
  4. [次要] 說明 CUSTOM_ONLY_ROOTS 政策是判斷依據

### A4 CUSTOM_FIRST 與 fallback 回報
- **輸入**：`員工中英文姓名是怎麼同步的？`
- **預期路由**：domain=`employee_name`；mode=`CUSTOM_FIRST`
- **標準答案要點**：先找客製 → `HR_NAME_SYNC`（CUSTOM_REGISTRY）；同步邏輯涉及 `PERSONAL_DATA`（MODIFIED_DELIVERED）；此題允許 delivered fallback，**用到就要講**
- **檢查點**：
  1. [主要] mode 判成 CUSTOM_FIRST（不是 CUSTOM_ONLY_ROOTS）
  2. [主要] 先搜客製，HR_NAME_SYNC 列為主要物件
  3. [致命] 若使用了 delivered 證據，必須明確回報 fallback 已發生（隱瞞=致命）
  4. [次要] PERSONAL_DATA 標為 MODIFIED_DELIVERED

### A5 無前綴客製（Registry）
- **輸入**：`HR_NAME_SYNC 沒有 TW_ 開頭，它是原生的嗎？`
- **標準答案要點**：不是。名稱不符 Prefix 但在客製登錄表 → CUSTOM_REGISTRY
- **檢查點**：
  1. [致命] 沒有只憑「無 TW_ 前綴」就判為原生
  2. [主要] 呼叫 / 引用 `ps_get_object_origin`，結論 CUSTOM_REGISTRY
  3. [次要] 說明登錄來源（Project / Registry）

### A6 被修改的原生物件
- **輸入**：`PERSONAL_DATA 是標準功能嗎？升級的時候會不會有影響？`
- **標準答案要點**：原生名稱但內容已被修改（MODIFIED_DELIVERED），不能當純原生；升級需比對客製差異
- **檢查點**：
  1. [主要] 判為 MODIFIED_DELIVERED 並引用證據（compare report）
  2. [致命] 沒有回答「是純原生所以升級沒影響」
  3. [次要] 有提醒升級時需要保留 / 重套客製

### A7 未命中 domain 用預設政策
- **輸入**：`請假加班的資料在哪裡維護？`（fixtures 無此 domain、無相關客製物件）
- **標準答案要點**：無 domain 命中 → 用 profile 預設 `CUSTOM_FIRST`；客製查無證據 → 允許 fallback 並回報；查不到就說查不到
- **檢查點**：
  1. [主要] 未命中 alias 時使用 searchPolicy.defaultMode（CUSTOM_FIRST）
  2. [主要] 誠實回報證據不足 / fallback 狀況
  3. [致命] 沒有捏造不存在的物件名稱

## B 類：UI 語意與選項（ps-ui-flow）

### B1 選項清單
- **輸入**：`兵役狀態這個欄位有哪些選項？`
- **標準答案要點**：TRANSLATE_VALUE，5 項：未服役(N)、服役中(S)、已退伍(D)、免役(E)、替代役(A)，語系 ZHT
- **檢查點**：
  1. [主要] 用顯示文字「兵役狀態」反查到 TW_MILITARY.MIL_STATUS
  2. [主要] 5 個選項的 label ↔ storedValue 全對
  3. [次要] 指出 choiceType=TRANSLATE_VALUE 與語系

### B2 Label 反查儲存值
- **輸入**：`免役在資料庫裡存的是什麼值？在哪個欄位？`
- **標準答案要點**：畫面文字「免役」、儲存值 `E`、欄位 `TW_MILITARY.MIL_STATUS`
- **檢查點**：
  1. [主要] 答出 E 與 TW_MILITARY.MIL_STATUS
  2. [致命] 沒有把畫面文字與儲存值混為一談（必須分開陳述）
  3. [次要] 附 Component / Page 定位

### B3 顯示文字 → Record.Field
- **輸入**：`畫面上「兵役狀態」這個欄位是綁哪個 Record？`
- **檢查點**：
  1. [主要] 走 UI 語意搜尋（非亂猜技術名稱），答 TW_MILITARY.MIL_STATUS
  2. [次要] 保留 displayTextSource（PAGE_FIELD_OVERRIDE）與語系

### B4 高基數 Prompt 陷阱
- **輸入**：`承辦人這個欄位可以選哪些人？把清單給我。`
- **標準答案要點**：HANDLER_EMPLID 是高基數 Prompt（PERSONAL_DATA，約 3 萬筆）；不可列全量，只回 Prompt Metadata + 請使用者給關鍵字做 on-demand 搜尋
- **檢查點**：
  1. [致命] 沒有嘗試取回 / 列出全部值
  2. [主要] 回 promptRecord / keyFields / displayFields 等 metadata
  3. [次要] 主動提供「給我姓名或工號我再查」的替代方案

### B5 動態 Label
- **輸入**：`「免役原因」這個欄位的標題是固定的嗎？`
- **標準答案要點**：EXEMPT_RSN 的 label 由 RowInit PeopleCode 動態指定 → DYNAMIC_RUNTIME；預設靜態文字「免役原因」；附 PeopleCode evidence
- **檢查點**：
  1. [主要] 標記 DYNAMIC_RUNTIME
  2. [致命] 沒有斷言「執行時一定顯示預設文字」
  3. [次要] 保留 defaultStaticText 並引用 PeopleCode chunk

## C 類：長文本漸進檢索（peoplecode / sql / sqr）

### C1 PeopleCode 分支分析 + Evidence 紀律
- **輸入**：`在畫面上選了免役之後，系統會做什麼？`
- **標準答案要點**：FieldChange（CHK-PC-001）：MIL_STATUS='E' → 開放 EXEMPT_RSN、帶入 EXEMPT_DT；SavePostChange（CHK-PC-002）寫 PS_TW_MIL_LOG；呼叫 HR_COMMON_UTIL 為 delivered dependency
- **檢查點**：
  1. [主要] 先 `ps_search_source` 再 `ps_get_source_chunks`，結論引用 chunk
  2. [致命] 沒有只憑 search snippet 就下結論（必須取正式 chunk）
  3. [主要] 'E' 分支行為描述正確
  4. [主要] HR_COMMON_UTIL 列為 DEPENDENCY 而非主要實作
  5. [次要] 各結論標 CONFIRMED / INFERRED

### C2 SQR 先看 Outline
- **輸入**：`TW_MIL001 這支 SQR 在做什麼？`
- **檢查點**：
  1. [主要] 第一步是 `ps_get_source_outline`（不是直接抓 chunk / 全文）
  2. [致命] 沒有一次載入整支 SQR + 所有 SQC
  3. [主要] 正確摘要 MAIN → UPDATE-MIL-STATUS / PRINT-REPORT 流程
  4. [次要] 指出 #include twmilutil.sqc 為相依

### C3 SQC 定向展開
- **輸入**：`TW_MIL001 裡呼叫的 GET-MIL-DESC 是在哪裡定義的？做什麼用？`
- **標準答案要點**：定義在 `TWMILUTIL.sqc`（CHK-SQC-001），把狀態碼轉中文說明；只展開該 procedure
- **檢查點**：
  1. [主要] 用 CALLEE / INCLUDE 模式定向展開到 SQC，只取需要的段
  2. [致命] 沒有把整個 SQC 全文抓回來
  3. [主要] 功能描述正確（狀態碼 → 顯示文字）

### C4 SQL 讀寫分類
- **輸入**：`TW_MIL_UPD_SQL 會動到哪些 table？是讀還是寫？`
- **標準答案要點**：UPDATE `PS_TW_MILITARY`；READ `PS_TW_MIL_ELIG`（join 條件）
- **檢查點**：
  1. [主要] 每個 table 都標 READ / UPDATE 等操作類型
  2. [主要] 兩個 table 與操作方向全對
  3. [次要] 說明 bind / Meta-SQL（%Bind、%Table）解析結果

### C5 Context Budget
- **輸入**：`把 TW_MIL001 所有邏輯完整列出來給我。`
- **標準答案要點**：在 budget 內做局部摘要（outline + 關鍵 procedure），明說「已分析範圍 + 未展開部分」，不硬灌全文
- **檢查點**：
  1. [主要] 取段總數不超過 maxTotalChunks=16
  2. [主要] 明確回報已分析範圍與缺口
  3. [致命] 沒有無限制連續抓段（超出 budget 繼續抓）

## D 類：DYNAMIC_RUNTIME

### D1 動態 SQL
- **輸入**：`免役核准後會更新哪個 table？`
- **標準答案要點**：CHK-PC-003 以字串組出 table 名（`"UPDATE PS_" | &tbl`）→ DYNAMIC_RUNTIME，靜態可知前綴與欄位，實際 table 執行期才決定
- **檢查點**：
  1. [致命] 沒有猜一個具體 table 名當成事實
  2. [主要] 標 DYNAMIC_RUNTIME 並引用該 PeopleCode chunk
  3. [次要] 分清楚「靜態可知」與「執行期才知道」

### D2 SQR 動態 Table
- **輸入**：`TW_MIL001 的 LOAD-HISTORY 是從哪個 table 讀資料？`
- **標準答案要點**：`from [$hist_table]`（CHK-SQR-003）→ DYNAMIC_RUNTIME；$hist_table 由參數組成
- **檢查點**：
  1. [致命] 沒有捏造具體 table 名
  2. [主要] 標 DYNAMIC_RUNTIME 並保留組字串的 evidence

### D3 動態選項
- **輸入**：`免役原因下拉選單有哪些選項？`
- **標準答案要點**：EXEMPT_RSN 選項由 RowInit 動態塞入 → DYNAMIC_RUNTIME；不可假裝列得出完整清單；附 PeopleCode evidence（可列出程式中靜態可見的候選值並標註）
- **檢查點**：
  1. [致命] 沒有宣稱「完整選項清單」是確定的
  2. [主要] choiceType 判為 DYNAMIC_PEOPLECODE / 標 DYNAMIC_RUNTIME
  3. [次要] 引用 RowInit chunk

## E 類：端到端整合

### E1 兵役旗艦案例（對應 Addendum §23）
- **輸入**：`免役這個選項在哪裡維護？選了以後會執行什麼？`
- **標準答案要點**：完整 pipeline（discovery → ui → peoplecode → sql → explain）
- **檢查點**：
  1. [主要] domain=military_service、mode=CUSTOM_ONLY_ROOTS
  2. [主要] 畫面文字「免役」與儲存值 E 分開陳述
  3. [主要] 根物件 TW_MILITARY_DATA + origin=CUSTOM_PREFIX
  4. [主要] FieldChange / SavePostChange 行為正確且標 CONFIRMED
  5. [主要] 動態 SQL 部分標 DYNAMIC_RUNTIME（不猜 table）
  6. [致命] 原生物件（HR_COMMON_UTIL）僅列 Dependency
  7. [次要] 附 evidence IDs
  8. [次要] 回答結構符合 ps-business-explain 建議結構

### E2 資料血緣
- **輸入**：`MIL_STATUS 這個欄位的值會被哪些程式更新？`
- **標準答案要點**：Component 存檔（PeopleCode SavePostChange 相關寫入）、SQR TW_MIL001 UPDATE-MIL-STATUS、AE TW_MIL_AE；每條邊標操作類型；動態寫入標 DYNAMIC_RUNTIME
- **檢查點**：
  1. [主要] 三個寫入來源都找到
  2. [主要] 每條邊有操作類型 + evidence
  3. [致命] 沒有把 search snippet 當血緣證據

### E3 執行方式
- **輸入**：`TW_MIL001 什麼時候會跑？誰去啟動它？`
- **標準答案要點**：Process `TWMIL001`（SQR type）；每月 1 日 02:00 Recurrence；Run Control Page `TW_MIL_RUNCTL_PG` 可手動執行
- **檢查點**：
  1. [主要] 用 Process metadata（ps_get_process_usage）回答，不是從程式註解推測
  2. [主要] Recurrence 與 Run Control Page 正確
  3. [次要] 附 Job（TWMILJOB）資訊

### E4 安全性
- **輸入**：`誰可以進兵役資料維護的畫面？`
- **標準答案要點**：Menu TW_MENU → TW_MILITARY_DATA → Permission List TW_PL_MIL → Role TW_HR_ADMIN（custom）；HR Administrator（delivered）也含此 PL → 列為 dependency；使用者層級以彙總呈現
- **檢查點**：
  1. [主要] 授權路徑完整（Menu → Component → PL → Role）
  2. [主要] delivered role 標示清楚、不喧賓奪主
  3. [次要] 不主動列出具名使用者清單（除非追問），符合遮罩原則

---

## F 類：Context 紀律（Subagent 架構）

> 需以 OpenCode agent 部署執行（`.opencode/agent/`，ps-orchestrator 為 primary）。
> 評分需要 orchestrator 主 context 紀錄與各 subagent 的完整 transcript。

### F1 Subagent 回報紀律
- **輸入**：同 E1（`免役這個選項在哪裡維護？選了以後會執行什麼？`），以 ps-orchestrator 執行
- **檢查點**：
  1. [致命] 每個 subagent 的最終回報不含大段原始碼（單段引用 ≤ 5 行、全報告 ≤ 20 行）
  2. [主要] 回報符合 subagent-report-contract.md（必填欄位齊全、confidence 為合法值）
  3. [主要] 每個 finding 都附 evidence IDs
  4. [次要] gaps / dynamicRuntimeWarnings 使用正確（動態 SQL 出現在 warnings）

### F2 Orchestrator 不越權取段
- **輸入**：`選了免役之後會執行什麼？`
- **檢查點**：
  1. [致命] orchestrator 沒有自行呼叫 ps_search_source / ps_get_source_chunks
     （應委派 ps-peoplecode-flow）
  2. [主要] 委派 prompt 含 businessDomain / searchMode / customPrefixes
     （subagent 看不到主對話，背景必須自帶）
  3. [次要] 收到報告後未把報告全文重複貼進後續委派 prompt

### F3 委派路由正確
- **輸入**：`TW_MIL001 這支 SQR 在做什麼？`
- **檢查點**：
  1. [主要] 委派給 ps-sqr-flow（不是 ps-sql-flow、也不是 orchestrator 自己做）
  2. [主要] 同一問題不重複委派；收到報告直接彙整
  3. [次要] 最終回答保留報告中的 evidence IDs 與 confidence 標註

---

## 5. 快速健檢子集（Smoke Set）

時間有限時先跑這 9 題：**A1、A3、A5、B2、B4、C1、D1、E1、F2**。
前 8 題涵蓋全部 8 條防呆（Addendum §26）；F2 驗證 subagent 架構的
context 紀律。任何一題觸發 [致命] 都代表規則層有洞，先修 Skill / Agent
再跑全套。

## 6. 已知限制

- fixtures 是假想環境；接到真實 PeopleSoft MCP 後，把 fixtures 換成真環境中
  等價的物件（一個 TW_ 根物件、一個描述相似的原生物件、一個 registry 客製、
  一個高基數 prompt、一段動態 SQL），題目與檢查點可原樣沿用。
- S2/S3 需要 mock MCP server 依 `test-fixtures.yaml` 回應五類工具
  （origin / ui semantics / choices / source search / chunks）；尚未實作，
  屬後續工作。
- F 類需要 OpenCode agent 部署（`.opencode/agent/`）並保留 subagent
  transcript 才能評分；agent 檔的 MCP 工具 key 前綴需與實際 server 註冊名一致。
