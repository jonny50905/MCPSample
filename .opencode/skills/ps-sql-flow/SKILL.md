---
name: ps-sql-flow
description: PeopleSoft SQL 分析（SQL Definition / View / AE SQL）— table 讀寫分類、Meta-SQL、動態 SQL。
---

# ps-sql-flow：SQL 分析

## 職責

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

## 不負責

- UI 結構（→ ps-ui-flow）
- Component Security（→ ps-security-flow）
- Process Scheduler（→ ps-process-flow）
- 完整 SQR Procedure Flow（→ ps-sqr-flow）

## 檢索協定（必遵守）

一律遵守 `.opencode/peoplesoft/progressive-source-retrieval.md`。

語意切片單位（SQL）：

```text
SQL Statement / CTE / UNION Branch / Subquery / MERGE Section
PL/SQL Block / View Select Block
```

Chunk Metadata：

```text
statementType / referencedTables / referencedFields / readWriteType
cteNames / bindVariables / metaSqlTokens
```

## 工具

| 工具 | 用途 |
|---|---|
| `ps_search_source` | `sourceTypes: ["SQL_DEFINITION","AE_SQL","VIEW_SQL","QUERY_SQL"]` |
| `ps_get_source_chunks` | 取精確 SQL 段（正式 Evidence） |
| `ps_expand_source_context` | 展開必要的相鄰 statement / CTE |
| `ps_find_source_references` | 反查 Table / Field 被哪些 SQL 引用 |

## Skill Rules

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

## Context Budget

共用停止規則（見 progressive-source-retrieval.md §5）。

## Subagent 模式

以 OpenCode subagent（`.opencode/agent/ps-sql-flow.md`）執行時：
- 委派 prompt 自帶 domain / searchMode / customPrefixes，直接採用，不重新解析。
- 最終輸出只能是 `.opencode/peoplesoft/subagent-report-contract.md` 的 JSON 報告；
  raw chunks 留在本 context，不回傳（單段引用 ≤ 5 行）。

## 相關檔案

- `.opencode/peoplesoft/progressive-source-retrieval.md`
- `.opencode/peoplesoft/customization-profile.yaml`
