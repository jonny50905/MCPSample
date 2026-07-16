# Progressive Source Retrieval（共用長文本檢索協定）

PeopleCode、SQL、SQR、SQC 全部採用**同一套**「搜尋候選 → 精確取段 → 定向展開 → 停止」協定。
各長文本 Skill（`ps-peoplecode-flow`、`ps-sql-flow`、`ps-sqr-flow`、`ps-ae-flow` 的 AE SQL 部分）
不得各自發明 Chunk Retrieval 規則，一律遵守本文件。

核心原則：

- **Search Index 只負責定位**（結果只能是 `SEARCH_CANDIDATE`），
  **Database 完整分段（Chunk）才是正式 Evidence**。
- 不可預設載入完整 PeopleCode / SQL / SQR / SQC 原始碼。
- 動態組出的名稱、SQL、路徑一律標記 `DYNAMIC_RUNTIME`，不可猜測執行期結果。

---

## 1. 協定步驟

```text
Search
→ Select
→ Fetch Exact Chunks
→ Analyze
→ Expand Required Context
→ Stop
→ Produce Evidence
```

| 步驟 | 說明 | 使用工具 |
|---|---|---|
| Search | Hybrid 搜尋候選 chunk，套用 Customization Profile 的 origin / prefix 過濾 | `ps_search_source` |
| Select | 只挑選與問題直接相關的候選（受 Context Budget 限制） | — |
| Fetch Exact Chunks | 用 chunkId 取回資料庫中的精確分段 | `ps_get_source_chunks` |
| Analyze | 依 Source Type 的語意單位分析（見 §4） | — |
| Expand Required Context | 只展開「回答問題必要」的鄰近段 / 符號 | `ps_expand_source_context` |
| Stop | 觸及停止規則即停（見 §5） | — |
| Produce Evidence | 產出帶 evidence ID 的結論 | — |

輔助工具：

- `ps_get_source_outline` — 先取 Outline（程式骨架）再決定要抓哪些段，SQR 必用。
- `ps_find_source_references` — 反查某符號 / Table / Field 被哪些來源引用。

---

## 2. 共用 Source Type

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

## 3. Evidence 規則

1. `ps_search_source` 的結果（含 snippet）只能作為 `SEARCH_CANDIDATE`，
   **不可直接作為最終 Evidence**。
2. 只有 `ps_get_source_chunks` / `ps_expand_source_context` 回傳的資料庫 Chunk
   （含 `sourceHash`、`startLine`/`endLine`）才是正式 Evidence。
3. 每個結論必須標記狀態：

```text
CONFIRMED        由精確 Chunk 直接證實
INFERRED         由多個 Chunk 合理推論（需列出依據的 evidence IDs）
DYNAMIC_RUNTIME  執行期才決定（動態 SQL / 動態 Procedure / 動態 Include / 動態路徑）
```

---

## 4. 各 Source Type 的語意切片

### 4.1 PeopleCode

優先切分單位：

```text
Event
Function
Class
Method
Property
AE PeopleCode Action
```

### 4.2 SQL

優先切分單位：

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

### 4.3 SQR

優先切分單位：

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

### 4.4 SQC

優先切分單位：

```text
Procedure
Include Section
Shared SQL Block
Declaration Block
```

---

## 5. Context Budget 與停止規則

PeopleCode、SQL、SQR、SQC 共用相同的停止規則：

```text
maxSearchResults: 20
maxSelectedSymbols: 8
maxInitialChunks: 10
maxTotalChunks: 16
maxExpansionRounds: 3
maxChunksPerExpansion: 4
```

停止條件（任一成立即 Stop）：

1. 問題已可由既有 Chunk 回答（不再「順便」展開）。
2. 達到 `maxTotalChunks` 或 `maxExpansionRounds` 上限。
3. 下一步展開目標為 `DYNAMIC_RUNTIME`（記錄警告後停止，不猜測）。
4. 展開目標已取過（防重：同一 chunkId / 同一 symbol 不重複取）。

超出 Budget 仍未能回答時：回報「已分析範圍 + 缺口」，不可硬灌整支程式。

---

## 6. MCP Tool Contract（長文本共用）

不一定要把現有 MCP 合併成同一個 Server，但 Tool Schema 必須一致；
如已有 PeopleCode MCP / SQL MCP / SQR MCP，可各做 Adapter，
對 Skill 暴露相同的概念與回應結構。

### 6.0 現行環境對映

實際部署為兩個 MCP server（工具 key 前綴以 opencode.json 的註冊名為準）：

| Server | 承擔的協定角色 |
|---|---|
| `PeoplecodeElasticSearch` | `ps_search_source` — 搜尋候選 chunk ids（只能當 SEARCH_CANDIDATE） |
| `PeoplecodeSource` | `ps_get_source_chunks` — 以 chunk id 取完整上下文（正式 Evidence） |

`ps_expand_source_context`、`ps_get_source_outline`、`ps_find_source_references`
尚未實作，過渡做法：需要展開 / outline / 反查時，以符號、程式名或鄰近關鍵字
再搜 ES 取得 chunk ids，再用 PeoplecodeSource 取段；仍補不到的記入報告 `gaps`。
本文其餘章節的工具名一律視為**協定角色名**，不是實際工具 id。

### 6.1 `ps_search_source`

輸入：

```json
{
  "sourceTypes": ["PEOPLECODE", "SQL_DEFINITION", "SQR", "SQC"],
  "query": "兵役狀態 免役",
  "searchMode": "HYBRID",
  "filters": {
    "environment": "PROD",
    "objectOrigins": ["CUSTOM_PREFIX", "CUSTOM_REGISTRY", "MODIFIED_DELIVERED"],
    "objectNamePrefixes": ["TW_"],
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

結果只能作為 `SEARCH_CANDIDATE`。

### 6.2 `ps_get_source_chunks`

輸入：

```json
{
  "sourceType": "SQR",
  "chunkIds": ["CHK-0001"],
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

### 6.3 `ps_expand_source_context`（定向展開）

輸入（擇一展開方式）：

```json
{
  "sourceType": "SQR",
  "from": { "chunkId": "CHK-0001" },
  "expand": {
    "mode": "NEIGHBOR | SYMBOL | CALLEE | INCLUDE",
    "symbolName": "UPDATE-MIL-STATUS",
    "direction": "BEFORE | AFTER | BOTH",
    "maxChunks": 4
  }
}
```

輸出：與 `ps_get_source_chunks` 相同的 `chunks` 結構，另附 `expandedFrom` 與
`truncated` 旗標。

### 6.4 `ps_get_source_outline`

輸入：

```json
{
  "sourceType": "SQR",
  "sourceId": "SQR-TW_MIL001",
  "maxDepth": 3
}
```

輸出：程式骨架（Section / Procedure / Include / SQL Block 清單與行號範圍），
**不含**完整原始碼內容。

### 6.5 `ps_find_source_references`

輸入：

```json
{
  "symbol": "TW_MILITARY.MIL_STATUS",
  "symbolKind": "RECORD_FIELD | PROCEDURE | FUNCTION | TABLE | SQC_INCLUDE",
  "sourceTypes": ["PEOPLECODE", "SQL_DEFINITION", "SQR", "SQC"],
  "filters": { "objectOrigins": ["CUSTOM_PREFIX", "CUSTOM_REGISTRY", "MODIFIED_DELIVERED"] },
  "topK": 20
}
```

輸出：引用清單（sourceId、chunkId、parentSymbol、objectOrigin、usageType），
仍屬 `SEARCH_CANDIDATE`，需回 `ps_get_source_chunks` 取正式 Evidence。

---

## 7. 防呆（長文本共用）

```text
Do not use Elastic Search snippets as final evidence.

Do not retrieve complete PeopleCode, SQL, SQR, or SQC source by default.

If a procedure name, include file, SQL statement, table, field, condition,
or file path is dynamically constructed, mark it as DYNAMIC_RUNTIME.

Search results are candidates only.
Retrieve exact database chunks before concluding.
```
