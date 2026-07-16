---
name: ps-ae-flow
description: Use when analyzing PeopleSoft Application Engine (AE) programs — section/step/action structure, call-section chains, which SQL and PeopleCode actions run and in what order, state records and bind usage. Delegates SQL/PeopleCode action content to ps-sql-flow / ps-peoplecode-flow.
---

# ps-ae-flow：Application Engine 分析

## 職責

- 取得 AE 的 Section → Step → Action 結構（`ps_get_ae_graph`）
- 追蹤 Call Section 鏈（含跨 AE 呼叫），只展開回答問題必要的 Section
- 識別 State Record 與 %Bind 的使用
- SQL Action 內容 → 交給 `ps-sql-flow`（sourceType `AE_SQL`）
- PeopleCode Action 內容 → 交給 `ps-peoplecode-flow`（AE PeopleCode Action 切片）
- AE 如何被執行（Process Definition / 排程）→ 交給 `ps-process-flow`

## 前置

載入 `.opencode/peoplesoft/customization-profile.yaml`，
用 `ps_get_object_origin` 分類 AE 及其呼叫對象的 origin；
domain 為 CUSTOM_ONLY_ROOTS 時，原生 AE 只能列為 DEPENDENCY。

## Skill Rules

```text
Start from the AE graph (sections, steps, actions), not from raw source.

Follow only the sections and call chains required to answer the question.
Do not expand every section of a large AE by default.

For each analyzed step, preserve:
- section, step, and action type
- do-when / do-select conditions relevant to the question
- state records and bind variables involved
- evidence IDs

Analyze SQL action content under the ps-sql-flow rules (AE_SQL source type),
and PeopleCode action content under the ps-peoplecode-flow rules.

If a section name, SQL text, or call target is constructed at runtime,
mark it as DYNAMIC_RUNTIME.

Classify each conclusion as CONFIRMED, INFERRED, or DYNAMIC_RUNTIME.
```

## 工具

| 工具 | 用途 |
|---|---|
| `ps_get_ae_graph` | AE Section / Step / Action 圖（Action 附 sourceId） |
| `ps_search_source` / `ps_get_source_chunks` | 取 AE_SQL / AE PeopleCode Action 精確段 |
| `ps_get_process_usage` | AE 的執行方式（交由 ps-process-flow 解讀） |

## 相關檔案

- `.opencode/peoplesoft/progressive-source-retrieval.md`（AE_SQL 遵守共用協定）
- `.opencode/peoplesoft/customization-profile.yaml`
