---
name: ps-sqr-flow
description: SQR / SQC 程式分析 — outline 優先、procedure call graph、SQC include、Run Control 與報表輸出。
---

# ps-sqr-flow：SQR / SQC 分析

## 職責

- SQR / SQC Hybrid Search
- 取得 Program Outline
- Procedure Call Graph
- SQC Include Graph
- SQL Block 分析（細節交給 ps-sql-flow 規則）
- Input Parameter
- Run Control 使用方式
- File / Report Output
- Business Rule
- Dynamic Procedure / Include 警告

## 執行方式

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

**不可一次載入完整 SQR 與所有 SQC。**

## 檢索協定（必遵守）

一律遵守 `.opencode/peoplesoft/progressive-source-retrieval.md`。

語意切片單位（SQR）：

```text
BEGIN-PROGRAM / BEGIN-SETUP / BEGIN-HEADING / BEGIN-FOOTING
BEGIN-PROCEDURE / BEGIN-SELECT / BEGIN-SQL / DO Call / #include
```

SQC 切片單位：

```text
Procedure / Include Section / Shared SQL Block / Declaration Block
```

Chunk Metadata（SQR）：

```text
sectionType / procedureName / calledProcedures / includedFiles
referencedTables / referencedFields
```

## 工具

| 工具 | 用途 |
|---|---|
| `ps_get_source_outline` | 先取程式骨架（Section / Procedure / Include 清單） |
| `ps_search_source` | `sourceTypes: ["SQR","SQC"]` hybrid 搜尋 |
| `ps_get_source_chunks` | 取精確 Procedure / SQL Block（正式 Evidence） |
| `ps_expand_source_context` | 追蹤必要 DO Call / #include（CALLEE / INCLUDE 模式） |
| `ps_find_source_references` | 反查 Procedure / Table 被誰引用 |

## Skill Rules

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

## Context Budget

共用停止規則（見 progressive-source-retrieval.md §5）。

## Subagent 模式

以 OpenCode subagent（`.opencode/agent/ps-sqr-flow.md`）執行時：
- 委派 prompt 自帶 domain / searchMode / customPrefixes，直接採用，不重新解析。
- 最終輸出只能是 `.opencode/peoplesoft/subagent-report-contract.md` 的 JSON 報告；
  raw chunks 留在本 context，不回傳（單段引用 ≤ 5 行）。

## 相關檔案

- `.opencode/peoplesoft/progressive-source-retrieval.md`
- `.opencode/peoplesoft/customization-profile.yaml`
