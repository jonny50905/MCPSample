# PeopleSoft Skill Plan Addendum：客製化優先、UI 業務語意與長文本檢索

## 1. 本次調整結論

既有架構需要增加三個核心概念：

1. **Customization Profile**
   - 說明此 PeopleSoft 環境的客製命名規則、客製物件清單與業務領域。
   - `TW_` 是強烈的客製訊號，但不可當成唯一判斷條件。

2. **UI Semantic Index**
   - Page 最終顯示文字、Grid 欄位名稱、Tab、Group Box、Button、選項文字，應視為第一級業務語意。
   - 業務問題搜尋時，UI 顯示文字的優先級應高於純技術 Object Name。

3. **Unified Progressive Source Retrieval**
   - PeopleCode、SQL、SQR、SQC 全部採用相同的「搜尋候選 → 精確取段 → 定向展開 → 停止」協定。
   - Search Index 只負責定位，Database 完整分段才是正式 Evidence。

調整後建議核心 Skill 為 10 個：

```text
1. ps-business-discovery
2. ps-ui-flow
3. ps-peoplecode-flow
4. ps-sql-flow
5. ps-sqr-flow
6. ps-ae-flow
7. ps-data-lineage
8. ps-process-flow
9. ps-security-flow
10. ps-business-explain
```

選配：

```text
11. ps-impact-analysis
```

---

# 2. 不要把 `TW_` 規則只硬寫在 SKILL.md

`TW_` 規則應存在一份環境專用的設定檔，由 Skill 讀取或由 MCP 提供。

原因：

- 未來可能增加其他 Prefix。
- 有些全客製物件可能不符合 `TW_`。
- 有些原生名稱物件可能已被修改。
- 不同 PeopleSoft Environment 可能有不同命名規則。
- 業務領域可能有不同搜尋策略。

建議檔案：

```text
.opencode/peoplesoft/customization-profile.yaml
```

範例：

```yaml
profileVersion: 1
environment: PROD
defaultLanguage: ZHT

customization:
  customPrefixes:
    - TW_

  customObjectRegistry:
    enabled: true
    source: oracle-mcp

  objectOrigins:
    - CUSTOM_PREFIX
    - CUSTOM_REGISTRY
    - MODIFIED_DELIVERED
    - DELIVERED
    - UNKNOWN

searchPolicy:
  defaultMode: CUSTOM_FIRST
  allowDeliveredFallback: true
  allowDeliveredDependencies: true

businessDomains:
  military_service:
    displayName: 兵役
    aliases:
      - 兵役
      - 役別
      - 役男
      - 服役
      - 退伍
      - 免役
      - 替代役
      - 軍種
      - 兵役狀態

    rootObjectPolicy: CUSTOM_ONLY_ROOTS
    preferredPrefixes:
      - TW_

    allowDeliveredDependencies: true
    deliveredFallback: false

  employee_name:
    displayName: 員工姓名
    aliases:
      - 員工姓名
      - 姓名同步
      - 中英文姓名

    rootObjectPolicy: CUSTOM_FIRST
    preferredPrefixes:
      - TW_

    allowDeliveredDependencies: true
    deliveredFallback: true
```

---

# 3. Object Origin 不應只靠 Prefix 判斷

每個 PeopleSoft Object 應先分類來源：

```text
CUSTOM_PREFIX
CUSTOM_REGISTRY
MODIFIED_DELIVERED
DELIVERED
UNKNOWN
```

## 3.1 `CUSTOM_PREFIX`

名稱符合客製 Prefix，例如：

```text
TW_
```

這是高可信度的客製物件。

## 3.2 `CUSTOM_REGISTRY`

雖然名稱不符合 Prefix，但已在客製物件登錄表中。

客製登錄可來自：

- 手動管理的 Object Registry
- Project Migration 清單
- Compare Report
- 客製套件清單
- 版本控管匯出結果
- PeopleTools Project Definition
- 自訂 Oracle Table

## 3.3 `MODIFIED_DELIVERED`

物件名稱是原生名稱，但實際內容已被修改。

此類物件不能因為沒有 `TW_` 就當成純原生物件。

## 3.4 `DELIVERED`

確認為 PeopleSoft 原生，且未被修改。

## 3.5 `UNKNOWN`

無法確認來源。

## 3.6 建議 MCP Tool

```text
ps_get_object_origin
```

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

---

# 4. 業務領域搜尋政策

## 4.1 Search Scope

Skill 應明確使用以下搜尋模式：

```text
CUSTOM_ONLY_ROOTS
CUSTOM_FIRST
MIXED
DELIVERED_ALLOWED
```

### `CUSTOM_ONLY_ROOTS`

只允許客製物件成為業務流程的根物件。

原生物件仍可作為：

- 被呼叫 Utility
- 共用 Record
- Framework
- Security
- Process Scheduler
- 基礎 API
- 相依物件

但不可因為原生物件名稱或描述相似，就把它當成此業務流程的主要實作。

「兵役」適合使用：

```text
CUSTOM_ONLY_ROOTS
```

### `CUSTOM_FIRST`

先找客製物件。

如果找不到足夠證據，才查原生物件。

### `MIXED`

客製與原生流程同等重要。

### `DELIVERED_ALLOWED`

無特定客製限制。

---

# 5. `ps-business-discovery` 調整

## 5.1 新搜尋順序

當使用者輸入業務問題，例如：

```text
兵役資料在哪裡維護？
免役有哪些選項？
兵役狀態是怎麼決定的？
```

應依以下順序搜尋：

```text
1. Business Domain Alias
2. Page 實際顯示文字
3. Page 欄位選項文字
4. 客製 Object Description
5. 客製 Record / Field Label
6. 客製 PeopleCode Chunk
7. 客製 SQL Chunk
8. 客製 SQR / SQC Chunk
9. 客製 Object 關聯
10. 原生物件 fallback
```

在 `CUSTOM_ONLY_ROOTS` 模式下，第 10 步預設不執行。

## 5.2 Custom Root 與 Delivered Dependency

範例：

```text
TW_MILITARY_DATA Component
  → TW_MILITARY Page
  → TW_MILITARY_REC
  → PeopleCode
  → 呼叫原生共用 Utility
```

最終結論應是：

```text
業務根物件：TW_MILITARY_DATA
來源：CUSTOM_PREFIX

原生相依物件：某 PeopleSoft Utility
角色：DEPENDENCY
```

不可將原生 Utility 說成「兵役功能的主要實作」。

## 5.3 搜尋結果輸出

```json
{
  "businessDomain": {
    "domainId": "military_service",
    "displayName": "兵役",
    "matchedAlias": "免役",
    "rootObjectPolicy": "CUSTOM_ONLY_ROOTS"
  },
  "searchScope": {
    "mode": "CUSTOM_ONLY_ROOTS",
    "customPrefixes": [
      "TW_"
    ],
    "deliveredFallbackUsed": false
  },
  "candidateRoots": [
    {
      "objectType": "COMPONENT",
      "objectName": "TW_MILITARY_DATA",
      "origin": "CUSTOM_PREFIX",
      "status": "CONFIRMED",
      "evidenceIds": [
        "UI-E001",
        "OBJ-E001"
      ]
    }
  ],
  "dependencies": [],
  "warnings": []
}
```

---

# 6. `ps-business-discovery` Skill Rule Patch

加入以下規則：

```text
Before searching PeopleSoft objects, load the environment customization profile.

Classify each candidate as:
- CUSTOM_PREFIX
- CUSTOM_REGISTRY
- MODIFIED_DELIVERED
- DELIVERED
- UNKNOWN

A custom prefix is a strong ranking signal, but it is not the only evidence
that an object is customized.

Resolve the business domain before selecting root objects.

When the business domain uses CUSTOM_ONLY_ROOTS:
- Only customized objects may be selected as root business objects.
- Delivered objects may be included only as dependencies.
- Do not use a delivered object merely because its description resembles
  the business question.
- Do not perform delivered fallback unless the profile explicitly allows it.

When the business domain uses CUSTOM_FIRST:
- Search customized objects first.
- Search delivered objects only if customized evidence is insufficient.
- Clearly report when delivered fallback was used.

Prefer business-facing UI text and option labels over technical object names
when resolving a business question.

Always report:
- the resolved business domain
- the search scope
- the root object policy
- object origins
- whether delivered fallback was used
```

---

# 7. Page 實際顯示文字是第一級業務語意

Page 上使用者真正看到的文字，通常比以下內容更貼近業務：

- Record Name
- Field Name
- PeopleCode Symbol Name
- AE Name
- SQL Name

因此必須建立：

```text
UI Semantic Index
```

## 7.1 應索引的 UI 文字

至少包含：

```text
Page Field Label
Grid Column Label
Tab Label
Group Box Label
Button Label
Hyperlink Label
Static Text
Page Title
Component Label
Menu Label
Prompt Label
Radio Button Label
Drop-down Display Text
Checkbox Label
Instruction Text
Message Text
```

## 7.2 顯示文字來源

每一筆顯示文字需記錄來源：

```text
PAGE_FIELD_OVERRIDE
RECORD_FIELD_LABEL
FIELD_LABEL
STATIC_TEXT
GRID_COLUMN_LABEL
TAB_LABEL
GROUPBOX_LABEL
BUTTON_LABEL
MENU_LABEL
COMPONENT_LABEL
MESSAGE_CATALOG
DYNAMIC_PEOPLECODE
UNKNOWN
```

## 7.3 最終顯示文字解析

應盡量解析 Page 上的最終靜態顯示文字。

建議優先順序：

```text
1. Page Field 明確覆寫的 Label
2. Page / Grid / Control 專用 Label
3. Record Field Label
4. Field Label
5. Component / Menu Label
```

如果文字由 PeopleCode 動態指定：

```text
status: DYNAMIC_RUNTIME
```

並保留：

```text
defaultStaticText
dynamicLabelEvidence
```

不可假設執行時一定顯示預設文字。

## 7.4 語系

UI Semantic Index 必須保留語系：

```text
languageCode
displayText
fallbackLanguageCode
```

例如：

```json
{
  "componentName": "TW_MILITARY_DATA",
  "pageName": "TW_MILITARY_PG",
  "recordName": "TW_MILITARY",
  "fieldName": "MIL_STATUS",
  "languageCode": "ZHT",
  "displayText": "兵役狀態",
  "displayTextSource": "PAGE_FIELD_OVERRIDE"
}
```

## 7.5 業務搜尋權重

搜尋排序建議：

```text
最高：
- Page 最終顯示文字 exact match
- 選項顯示文字 exact match

高：
- Page 最終顯示文字 semantic match
- Grid Column / Tab / Group Box 文字
- 客製 Object Description

中：
- Record Field Label
- PeopleCode / SQL / SQR Chunk

較低：
- 純技術 Object Name
- 原生物件相似描述
```

---

# 8. `ps-ui-flow` 調整為結構加語意

`ps-ui-flow` 不只回傳：

```text
Component
→ Page
→ Record.Field
```

還要回傳：

```text
Component
→ Page
→ Control
→ Display Text
→ Choice Values
→ Record.Field
→ PeopleCode Event
```

## 8.1 建議節點

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

## 8.2 建議 Edge

```text
CONTAINS_PAGE
CONTAINS_CONTROL
DISPLAYS_TEXT
BINDS_TO_FIELD
USES_CHOICE_SET
CONTAINS_CHOICE
TRIGGERS_EVENT
```

## 8.3 建議 MCP Tool

原本：

```text
ps_get_ui_graph
```

增加參數：

```json
{
  "rootType": "COMPONENT",
  "rootName": "TW_MILITARY_DATA",
  "includeSubpages": true,
  "includeControls": true,
  "includeDisplayText": true,
  "includeChoices": true,
  "includeLanguages": [
    "ZHT",
    "ENG"
  ],
  "maxDepth": 10
}
```

---

# 9. Page 欄位選項是業務邏輯的一部分

使用者在畫面上選擇的內容，常直接代表：

- 狀態
- 業務分類
- 核准類型
- 身分
- 原因
- 結果
- 流程分支

例如：

```text
未服役
服役中
已退伍
免役
替代役
```

這些文字比實際儲存值：

```text
N
S
D
E
A
```

更接近業務語意。

因此選項文字必須被索引並可反向追蹤到 Record.Field。

---

# 10. Choice Type

至少支援以下類型：

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

## 10.1 Translate Value

保留：

```text
fieldName
storedValue
displayText
languageCode
effectiveDate
status
```

## 10.2 Prompt Table

保留：

```text
promptRecord
keyFields
displayFields
searchFields
securityRecord
```

### 低基數 Prompt

例如只有十幾種狀態或類別：

- 可將 Value + Label 建立搜尋索引。
- 可直接支援「免役是哪個值」的查詢。

### 高基數 Prompt

例如員工、部門、職位：

- 不可將所有資料塞給 LLM。
- 只索引 Prompt Metadata。
- 使用者查詢特定值時，再透過 MCP 搜尋。
- 必須遵守資料權限與敏感資料遮罩。

## 10.3 Radio Button / Drop-down

應保存 Page-specific 的：

```text
storedValue
displayText
controlType
pageName
recordName
fieldName
```

## 10.4 Checkbox

應保存：

```text
checkedValue
uncheckedValue
checkedLabel
uncheckedLabel
```

## 10.5 Dynamic Prompt

如果 Prompt Record、Edit Table 或選項由 PeopleCode 動態指定：

```text
status: DYNAMIC_RUNTIME
```

並追蹤相關 PeopleCode Evidence。

---

# 11. `ps_get_field_choices`

建議增加 MCP Tool：

```text
ps_get_field_choices
```

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

---

# 12. UI Semantic Search

建議增加：

```text
ps_search_ui_semantics
```

輸入：

```json
{
  "query": "免役",
  "environment": "PROD",
  "languageCode": "ZHT",
  "customizationMode": "CUSTOM_ONLY_ROOTS",
  "customPrefixes": [
    "TW_"
  ],
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

---

# 13. `ps-ui-flow` Skill Rule Patch

```text
Treat user-visible UI text as first-class business metadata.

When resolving a business term:
1. Search final page display text.
2. Search choice labels.
3. Search grid, tab, group box, button, and static text.
4. Map matching text to Page, Component, Record, and Field.
5. Only then expand to PeopleCode, SQL, AE, SQR, and security logic.

Prefer page-specific display text over generic field labels.

Always preserve:
- language
- display text source
- component
- page
- control type
- record and field
- stored value for choice items

For fields with selectable values:
- retrieve the choice type
- retrieve low-cardinality choices
- map display labels to stored values
- identify prompt records
- mark runtime-generated choices as DYNAMIC_RUNTIME

Do not load all values from a high-cardinality prompt table.
Search values on demand through MCP.

When display text is dynamically assigned by PeopleCode:
- preserve the default static label
- include PeopleCode evidence
- mark the final runtime text as DYNAMIC_RUNTIME
```

---

# 14. PeopleCode、SQL、SQR、SQC 共用長文本檢索協定

不建議每個 Skill 各自發明一套 Chunk Retrieval 規則。

應建立共用規格：

```text
progressive-source-retrieval.md
```

每個長文本 Skill 都遵守：

```text
Search
→ Select
→ Fetch Exact Chunks
→ Analyze
→ Expand Required Context
→ Stop
→ Produce Evidence
```

---

# 15. 共用 Source Type

```text
PEOPLECODE
SQL_DEFINITION
AE_SQL
VIEW_SQL
QUERY_SQL
SQR
SQC
```

---

# 16. 共用 MCP Contract

不一定要把現有 MCP 合併成同一個 Server，但 Tool Schema 應一致。

建議 Tool：

```text
ps_search_source
ps_get_source_chunks
ps_expand_source_context
ps_get_source_outline
ps_find_source_references
```

如已有不同 MCP，可做 Adapter：

```text
PeopleCode MCP
SQL MCP
SQR MCP
```

但對 Skill 暴露相同的概念與回應結構。

---

# 17. `ps_search_source`

輸入：

```json
{
  "sourceTypes": [
    "PEOPLECODE",
    "SQL_DEFINITION",
    "SQR",
    "SQC"
  ],
  "query": "兵役狀態 免役",
  "searchMode": "HYBRID",
  "filters": {
    "environment": "PROD",
    "objectOrigins": [
      "CUSTOM_PREFIX",
      "CUSTOM_REGISTRY",
      "MODIFIED_DELIVERED"
    ],
    "objectNamePrefixes": [
      "TW_"
    ],
    "businessDomain": "military_service"
  },
  "topK": 20,
  "collapseBy": "PARENT_SYMBOL"
}
```

輸出：

```json
{
  "results": [
    {
      "sourceType": "SQR",
      "sourceId": "SQR-TW_MIL001",
      "chunkId": "CHK-0001",
      "parentSymbol": "BEGIN-PROCEDURE UPDATE-MIL-STATUS",
      "objectName": "TW_MIL001",
      "objectOrigin": "CUSTOM_PREFIX",
      "score": 0.93,
      "snippet": "..."
    }
  ]
}
```

Search Result 只能作為：

```text
SEARCH_CANDIDATE
```

不可直接作為最終 Evidence。

---

# 18. `ps_get_source_chunks`

輸入：

```json
{
  "sourceType": "SQR",
  "chunkIds": [
    "CHK-0001"
  ],
  "includeMetadata": true,
  "maxTotalCharacters": 40000
}
```

輸出：

```json
{
  "chunks": [
    {
      "sourceType": "SQR",
      "sourceId": "SQR-TW_MIL001",
      "chunkId": "CHK-0001",
      "chunkSequence": 3,
      "parentSymbol": "UPDATE-MIL-STATUS",
      "startLine": 100,
      "endLine": 160,
      "sourceHash": "sha256...",
      "content": "..."
    }
  ]
}
```

Database Chunk 才是正式 Evidence。

---

# 19. 不同 Source Type 的語意切片

## 19.1 PeopleCode

優先切分：

```text
Event
Function
Class
Method
Property
AE PeopleCode Action
```

## 19.2 SQL

優先切分：

```text
SQL Statement
CTE
UNION Branch
Subquery
MERGE Section
PL/SQL Block
View Select Block
```

SQL Chunk Metadata：

```text
statementType
referencedTables
referencedFields
readWriteType
cteNames
bindVariables
metaSqlTokens
```

## 19.3 SQR

優先切分：

```text
BEGIN-PROGRAM
BEGIN-SETUP
BEGIN-HEADING
BEGIN-FOOTING
BEGIN-PROCEDURE
BEGIN-SELECT
BEGIN-SQL
DO Call
#include
```

SQR Chunk Metadata：

```text
sectionType
procedureName
calledProcedures
includedFiles
referencedTables
referencedFields
```

## 19.4 SQC

優先切分：

```text
Procedure
Include Section
Shared SQL Block
Declaration Block
```

---

# 20. `ps-sql-flow`

SQL 不應只存在 `ps-data-lineage` 裡。

由於已有 SQL 全文切片與 MCP，建議增加獨立 Skill：

```text
ps-sql-flow
```

## 20.1 責任

- 搜尋 SQL Definition
- 分析 View SQL
- 分析 AE SQL Action
- 分析 SQR SQL Block
- 追蹤 Table / Field
- 分析條件與 Join
- 分析 UPDATE / INSERT / DELETE / MERGE
- 辨識 Meta-SQL
- 辨識 Dynamic SQL
- 產生 SQL 局部摘要
- 將結果交給 `ps-data-lineage`

## 20.2 不負責

- UI 結構
- Component Security
- Process Scheduler
- 完整 SQR Procedure Flow

## 20.3 Skill Rule

```text
Use progressive source retrieval for SQL.

Search results are candidates only.
Retrieve exact database chunks before concluding.

Analyze SQL by statement or semantic block.
Do not retrieve the entire SQL object unless the statement cannot be understood
from selected blocks.

Always classify table and field operations as:
- READ
- INSERT
- UPDATE
- DELETE
- MERGE
- UNKNOWN
- DYNAMIC_RUNTIME

Resolve Meta-SQL where metadata is available.
If table, field, or condition is built dynamically, mark it as DYNAMIC_RUNTIME.

Pass confirmed data operations to ps-data-lineage.
```

---

# 21. `ps-sqr-flow`

由於 SQR 與 SQC 已有切片與 MCP，`ps-sqr-source-flow` 應升級為核心：

```text
ps-sqr-flow
```

## 21.1 責任

- SQR / SQC Hybrid Search
- 取得 Program Outline
- Procedure Call Graph
- SQC Include Graph
- SQL Block 分析
- Input Parameter
- Run Control 使用方式
- File / Report Output
- Business Rule
- Dynamic Procedure / Include 警告

## 21.2 執行方式

```text
取得 SQR Outline
→ 找入口 Section
→ 取得相關 Procedure
→ 追蹤必要 DO Call
→ 取得相關 SQL Block
→ 追蹤必要 SQC Include
→ 停止
→ 產出局部摘要與 Evidence
```

不可一次載入完整 SQR 與所有 SQC。

## 21.3 Skill Rule

```text
Use progressive source retrieval for SQR and SQC.

Start with the program outline.
Do not retrieve the entire SQR program by default.

Follow only procedures, includes, and SQL blocks required to answer the question.

For each analyzed procedure, preserve:
- procedure name
- caller
- callee
- source chunk
- referenced tables
- output effect
- evidence IDs

Treat SQC includes as dependencies.
Retrieve only the required include procedure or SQL block.

If a procedure name, include file, SQL statement, or file path is dynamically
constructed, mark it as DYNAMIC_RUNTIME.

Use Oracle Process metadata through ps-process-flow to explain how the SQR is run.
```

---

# 22. `ps-business-discovery` 的整合流程

調整後的業務搜尋流程：

```text
使用者業務問題
  ↓
載入 Customization Profile
  ↓
解析 Business Domain
  ↓
決定 CUSTOM_ONLY_ROOTS / CUSTOM_FIRST / MIXED
  ↓
搜尋 UI 顯示文字
  ↓
搜尋選項文字
  ↓
映射 Component / Page / Record.Field
  ↓
搜尋客製 PeopleCode / SQL / SQR / SQC Chunk
  ↓
取得精確 Database Chunk
  ↓
追蹤 AE / Process / Security / Data Lineage
  ↓
必要時加入 Delivered Dependency
  ↓
ps-business-explain
```

---

# 23. 兵役案例

使用者：

```text
免役這個選項在哪裡維護？選了以後會執行什麼？
```

預期流程：

```text
1. ps-business-discovery
   - 命中 military_service
   - Search Mode = CUSTOM_ONLY_ROOTS

2. ps_search_ui_semantics
   - 命中 Choice Label「免役」
   - Component = TW_MILITARY_DATA
   - Page = TW_MILITARY_PG
   - Record.Field = TW_MILITARY.MIL_STATUS
   - Stored Value = E

3. ps-ui-flow
   - 取得 Component、Page、Control、Field
   - 取得 FieldChange / SavePreChange / SavePostChange Event

4. ps-peoplecode-flow
   - 搜尋 TW_ 客製 PeopleCode
   - 取得精確 Chunk
   - 分析選擇 E 後的條件分支

5. ps-sql-flow
   - 分析相關 SQL Definition 或動態 SQL

6. ps-sqr-flow
   - 如果後續 Process 執行 TW_ SQR，追蹤必要 Procedure

7. ps-data-lineage
   - 整理讀取、更新資料

8. ps-business-explain
   - 產出業務說明
```

最終結論必須區分：

```text
畫面文字：免役
儲存值：E
業務根物件：TW_MILITARY_DATA
物件來源：CUSTOM_PREFIX
PeopleCode 分支：CONFIRMED / INFERRED
SQL 更新：CONFIRMED / DYNAMIC_RUNTIME
原生物件：僅列為 Dependency
```

---

# 24. 更新後的 MCP Tool 建議

## 客製化與業務搜尋

```text
ps_get_customization_profile
ps_get_object_origin
ps_search_business_domains
```

## UI 語意

```text
ps_search_ui_semantics
ps_get_ui_graph
ps_get_field_choices
```

## 共用長文本

```text
ps_search_source
ps_get_source_chunks
ps_expand_source_context
ps_get_source_outline
ps_find_source_references
```

## PeopleSoft Metadata

```text
ps_get_object_summary
ps_get_ae_graph
ps_get_data_lineage
ps_get_process_usage
ps_get_security_path
```

不一定需要全部放在同一個 MCP Server，但 Tool Contract 應保持一致。

---

# 25. Context 控制

## 25.1 UI 搜尋結果

首次最多：

```text
20 個 UI Semantic Candidates
```

只保留：

```text
5～8 個不同 Component / Field
```

## 25.2 Choice Values

低基數：

```text
最多回傳 100 個
```

高基數：

```text
只回傳查詢命中的 20～50 個
```

## 25.3 Source Chunk

建議：

```text
maxSearchResults: 20
maxSelectedSymbols: 8
maxInitialChunks: 10
maxTotalChunks: 16
maxExpansionRounds: 3
maxChunksPerExpansion: 4
```

PeopleCode、SQL、SQR、SQC 共用相同的停止規則。

---

# 26. 最重要的 Skill 防呆

```text
Do not assume a delivered PeopleSoft object implements the customer's business
process when the customization profile marks the domain as custom-only.

Do not treat TW_ as the only way to identify customization.

Do not ignore page display text.
User-visible labels are primary business search signals.

Do not ignore option labels.
Choice display text and stored values are part of the business logic.

Do not use Elastic Search snippets as final evidence.

Do not retrieve complete PeopleCode, SQL, SQR, or SQC source by default.

Do not return all prompt values from a high-cardinality table.

Do not call a delivered object the root business implementation when it is only
a dependency of a TW_ custom object.
```

---

# 27. Definition of Done

## Customization

- [ ] 支援 `TW_` Prefix
- [ ] Prefix 來自環境設定，不是散落在 Prompt
- [ ] 支援 Custom Object Registry
- [ ] 支援 Modified Delivered Object
- [ ] 支援 Business Domain Alias
- [ ] 支援 CUSTOM_ONLY_ROOTS
- [ ] 支援 CUSTOM_FIRST
- [ ] 報告 Delivered Fallback 是否發生

## UI Semantic

- [ ] 索引 Page 最終靜態顯示文字
- [ ] 索引 Grid Column
- [ ] 索引 Tab / Group Box / Button / Static Text
- [ ] 保留語系
- [ ] 可由顯示文字反查 Component / Page / Record.Field
- [ ] 動態 Label 標記 DYNAMIC_RUNTIME

## Choice

- [ ] 支援 Translate Value
- [ ] 支援 Prompt Table
- [ ] 支援 Radio Button
- [ ] 支援 Drop-down
- [ ] 支援 Checkbox
- [ ] 索引低基數 Choice Label
- [ ] 高基數 Prompt 採 On-demand Search
- [ ] 動態 Choice 標記 DYNAMIC_RUNTIME
- [ ] 可由「免役」反查儲存值與 Field

## Long Text

- [ ] PeopleCode 採 Progressive Retrieval
- [ ] SQL 採 Progressive Retrieval
- [ ] SQR 採 Progressive Retrieval
- [ ] SQC 採 Progressive Retrieval
- [ ] Search Index 只作 Candidate
- [ ] Database Chunk 作正式 Evidence
- [ ] 支援 Outline
- [ ] 支援 Neighbor / Symbol Expansion
- [ ] 支援防重
- [ ] 支援 Context Budget
- [ ] 支援 DYNAMIC_RUNTIME

---

# 28. 最終建議

不需要把這些規則全部塞進單一 `SKILL.md`。

建議拆成：

```text
.opencode/
├─ peoplesoft/
│  ├─ customization-profile.yaml
│  ├─ business-domain-map.yaml
│  └─ progressive-source-retrieval.md
└─ skills/
   ├─ ps-business-discovery/
   │  └─ SKILL.md
   ├─ ps-ui-flow/
   │  └─ SKILL.md
   ├─ ps-peoplecode-flow/
   │  └─ SKILL.md
   ├─ ps-sql-flow/
   │  └─ SKILL.md
   ├─ ps-sqr-flow/
   │  └─ SKILL.md
   └─ ...
```

其中：

- `customization-profile.yaml`：環境規則與 `TW_`
- `business-domain-map.yaml`：兵役等全客製業務領域
- `progressive-source-retrieval.md`：PeopleCode、SQL、SQR、SQC 共用檢索規則
- 各 Skill：只描述該分析領域的決策與輸出

這樣可以避免 Qwen 3.5 9B 的單一 Skill 過大，也能讓環境規則獨立維護。
