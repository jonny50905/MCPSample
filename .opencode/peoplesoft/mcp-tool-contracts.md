# PeopleSoft MCP Tool Contracts（工具契約總覽）

本文件彙整 ps-* Skill 依賴的 MCP Tool 契約。
**不一定需要全部放在同一個 MCP Server，但 Tool Contract（名稱、輸入、輸出結構）應保持一致**；
既有的 PeopleCode MCP / SQL MCP / SQR MCP 可各做 Adapter 對齊本契約。

> **各 server 的完整工具清單（2026-08 管理者實測確認）**：
>
> | Server | 工具 | 用途 |
> |---|---|---|
> | `PeoplecodeElasticSearch` | `search_chunks` | 搜候選（定位用） |
> | `PeoplecodeElasticSearch` | `get_chunk_by_id` | 依 id 取回，欄位與 Source 版相同——**非解引用正規路徑，見下** |
> | `PeoplecodeSource` | `get_chunks_details` | **解引用（唯一的正式證據來源）** |
> | `PeoplecodeSource` | `get_file_structure` | 檔案結構，先看目錄再定向取段 |
>
> **`get_chunk_by_id` 不封鎖，但它不是解引用的正規路徑。** 管理者實測確認
> 兩邊資料源一致、回傳欄位相同（`ChunkText`／`FilePath`／`StartLine` 等）。
> 之所以仍規定解引用走 `PeoplecodeSource_get_chunks_details`：**索引依定義
> 是副本，CR 上線到索引重建之間會落後**（SOP-11 的整個對齊流程就建立在
> 這個時間差上）——固定走 Source 才能讓「證據失效」在稽核時現形。
>
> 它的**正當用途是交叉檢查**：Source 解引用查無時，用 ES 版同一個 id 再查
> 一次——ES 有、Source 無 ＝ 該 id 曾經真實存在但來源已變（判 stale／
> 重新定位），ES 也無 ＝ 該 id 較可能是捏造。兩種的處置不同，值得分辨。
>
> **不封鎖的理由本身也是一課（L61）**：維護 session 一度把它加進 tools map
> 的 deny，但**deny 一個實際可用的工具＝製造 `unavailable tool` → 重試 →
> doom_loop → headless 死鎖**，那正是本次事故的成因。**封鎖只留給真正有害
> 的東西；「非正規但無害」用規則講，不用封鎖擋。**
>
> **工具身分＝server 前綴＋工具名（L61）**：兩個都對才叫對。已知混淆——
> `get_chunk_by_id` 屬於 **`PeoplecodeElasticSearch`**，**不是** `PeoplecodeSource`；
> `PeoplecodeSource` 的解引用工具叫 `get_chunks_details`。掛錯 server 會得到
> `Model tried to call unavailable tool`，與「名字打錯」「本 agent 對該 server
> 是 deny」三者訊息完全相同，都**不是暫時故障**（重試必然再失敗）。
> 另：ES 的任何回傳一律是**候選**，不得當證據——解引用只能走 Source。

> **現況共三個 MCP**：`PeoplecodeElasticSearch`（搜 chunk ids）、
> `PeoplecodeSource`（chunk id → 完整上下文）、`oracleMCP`（PeopleTools
> metadata，通用 SQL 查詢——§1 / §2 / §4 的角色由它照
> `oracle-query-cookbook.md` 樣板承擔，尚無專用工具）。

長文本五個工具（`ps_search_source`、`ps_get_source_chunks`、`ps_expand_source_context`、
`ps_get_source_outline`、`ps_find_source_references`）的完整 I/O 契約見
`progressive-source-retrieval.md` §6，此處不重複。

> 標記 *(proposed)* 的 Schema 為本次補充規格提出的最小契約，實作 MCP Server 時可擴充欄位，
> 但不可改變既有欄位語意。

---

## 1. 客製化與業務搜尋

### 1.1 `ps_get_customization_profile` *(proposed)*

輸入：

```json
{ "environment": "PROD" }
```

輸出：`customization-profile.yaml` + `business-domain-map.yaml` 的等價 JSON
（profileVersion、customPrefixes、customObjectRegistry、objectOrigins、
searchPolicy、businessDomains）。

### 1.2 `ps_get_object_origin`

輸入：

```json
{
  "objectType": "COMPONENT",
  "objectName": "TW_MILITARY_DATA"
}
```

輸出：

```json
{
  "objectType": "COMPONENT",
  "objectName": "TW_MILITARY_DATA",
  "origin": "CUSTOM_PREFIX",
  "matchedPrefix": "TW_",
  "confidence": 1.0,
  "evidence": []
}
```

`origin` ∈ `CUSTOM_PREFIX | CUSTOM_REGISTRY | MODIFIED_DELIVERED | DELIVERED | UNKNOWN`。

### 1.3 `ps_search_business_domains` *(proposed)*

輸入：

```json
{ "query": "免役有哪些選項？", "topK": 3 }
```

輸出：命中的 domain 清單（domainId、displayName、matchedAlias、rootObjectPolicy、
preferredPrefixes、deliveredFallback、score）。

---

## 2. UI 語意

### 2.1 `ps_search_ui_semantics`

輸入：

```json
{
  "query": "免役",
  "environment": "PROD",
  "languageCode": "ZHT",
  "customizationMode": "CUSTOM_ONLY_ROOTS",
  "customPrefixes": ["TW_"],
  "topK": 20
}
```

輸出：

```json
{
  "results": [
    {
      "matchType": "CHOICE_LABEL",
      "displayText": "免役",
      "storedValue": "E",
      "componentName": "TW_MILITARY_DATA",
      "pageName": "TW_MILITARY_PG",
      "recordName": "TW_MILITARY",
      "fieldName": "MIL_STATUS",
      "objectOrigin": "CUSTOM_PREFIX",
      "score": 1.0
    }
  ]
}
```

`matchType` 例：`DISPLAY_TEXT_EXACT | DISPLAY_TEXT_SEMANTIC | CHOICE_LABEL |
GRID_COLUMN_LABEL | TAB_LABEL | GROUPBOX_LABEL | BUTTON_LABEL | STATIC_TEXT |
OBJECT_DESCRIPTION`。

### 2.2 `ps_get_ui_graph`

輸入（本次補充新增參數）：

```json
{
  "rootType": "COMPONENT",
  "rootName": "TW_MILITARY_DATA",
  "includeSubpages": true,
  "includeControls": true,
  "includeDisplayText": true,
  "includeChoices": true,
  "includeLanguages": ["ZHT", "ENG"],
  "maxDepth": 10
}
```

輸出：節點 + 邊的圖結構。

節點類型：

```text
COMPONENT
PAGE
SUBPAGE
CONTROL
DISPLAY_TEXT
RECORD_FIELD
CHOICE_SET
CHOICE_VALUE
PEOPLECODE_EVENT
```

邊類型：

```text
CONTAINS_PAGE
CONTAINS_CONTROL
DISPLAYS_TEXT
BINDS_TO_FIELD
USES_CHOICE_SET
CONTAINS_CHOICE
TRIGGERS_EVENT
```

### 2.3 `ps_get_field_choices`

輸入：

```json
{
  "componentName": "TW_MILITARY_DATA",
  "pageName": "TW_MILITARY_PG",
  "recordName": "TW_MILITARY",
  "fieldName": "MIL_STATUS",
  "languageCode": "ZHT",
  "includeInactive": false,
  "limit": 100
}
```

輸出：

```json
{
  "field": {
    "recordName": "TW_MILITARY",
    "fieldName": "MIL_STATUS",
    "displayText": "兵役狀態"
  },
  "choiceType": "TRANSLATE_VALUE",
  "choices": [
    {
      "storedValue": "E",
      "displayText": "免役",
      "languageCode": "ZHT",
      "status": "ACTIVE"
    }
  ],
  "dynamic": false,
  "evidence": []
}
```

`choiceType` ∈：

```text
TRANSLATE_VALUE
PROMPT_TABLE
RADIO_BUTTON
DROP_DOWN
LIST_BOX
CHECKBOX
YES_NO
PAGE_STATIC_CHOICE
DYNAMIC_PROMPT
DYNAMIC_PEOPLECODE
UNKNOWN
```

高基數 Prompt Table：**不回傳全部資料**，只回 Prompt Metadata
（promptRecord、keyFields、displayFields、searchFields、securityRecord），
值查詢採 on-demand search，並遵守資料權限與敏感資料遮罩。

---

## 3. 共用長文本（契約見 progressive-source-retrieval.md §6）

```text
ps_search_source
ps_get_source_chunks
ps_expand_source_context
ps_get_source_outline
ps_find_source_references
```

> **現況**：`ps_search_source` 由 `PeoplecodeElasticSearch` 承擔、
> `ps_get_source_chunks` 由 `PeoplecodeSource` 承擔；其餘三個尚未實作
> （過渡做法見 progressive-source-retrieval.md §6.0）。

---

## 4. PeopleSoft Metadata

### 4.1 `ps_get_object_summary` *(proposed)*

輸入：`{ "objectType": "...", "objectName": "..." }`
輸出：物件描述、origin、關聯物件摘要（不含長文本內容）。

### 4.2 `ps_get_ae_graph` *(proposed)*

輸入：`{ "aeName": "TW_MIL_AE", "maxDepth": 5 }`
輸出：AE Section → Step → Action（SQL / PeopleCode / Call Section）圖，
Action 節點附 sourceId 供長文本工具取段。

### 4.3 `ps_get_data_lineage` *(proposed)*

輸入：`{ "recordName": "TW_MILITARY", "fieldName": "MIL_STATUS", "direction": "UPSTREAM | DOWNSTREAM | BOTH", "maxDepth": 5 }`
輸出：Table/Field 層級的讀寫關係
（節點：RECORD_FIELD / SOURCE；邊：READ | INSERT | UPDATE | DELETE | MERGE |
UNKNOWN | DYNAMIC_RUNTIME，附 evidence IDs）。

### 4.4 `ps_get_process_usage` *(proposed)*

輸入：`{ "objectType": "SQR | AE", "objectName": "TW_MIL001" }`
輸出：Process Definition、Job、Recurrence、Run Control Record、
觸發來源（頁面 / 排程），附 origin。

### 4.5 `ps_get_security_path` *(proposed)*

輸入：`{ "componentName": "TW_MILITARY_DATA" }`
輸出：Menu → Component → Permission List → Role（→ User 統計）路徑，
各節點附 origin。
