---
name: ps-data-lineage
description: Use when tracing where a PeopleSoft record/field's data comes from or goes to — which PeopleCode, SQL, AE, SQR reads or writes it, upstream sources and downstream consumers. Consumes confirmed data operations from ps-sql-flow / ps-peoplecode-flow / ps-sqr-flow.
---

# ps-data-lineage：資料血緣

## 職責

- 以 Record.Field 為中心整理**讀取 / 寫入**關係（UPSTREAM / DOWNSTREAM）
- 彙整來自 `ps-sql-flow`、`ps-peoplecode-flow`、`ps-sqr-flow`、`ps-ae-flow`
  的 **confirmed data operations**
- 用 `ps_get_data_lineage` / `ps_find_source_references` 補足引用面
- 標記每條邊的操作類型與可信度

## 操作類型分類（每條血緣邊必標）

```text
READ / INSERT / UPDATE / DELETE / MERGE / UNKNOWN / DYNAMIC_RUNTIME
```

## Skill Rules

```text
Build lineage only from confirmed evidence chunks, not from search snippets.

Each lineage edge must carry:
- source object (and its origin classification)
- target record and field
- operation type (READ / INSERT / UPDATE / DELETE / MERGE / UNKNOWN / DYNAMIC_RUNTIME)
- evidence IDs

If a write target or condition is dynamically constructed, keep the edge but
mark it DYNAMIC_RUNTIME — do not guess the runtime table or field.

Distinguish custom roots from delivered dependencies in the lineage output,
using the customization profile's origin classification.

Do not expand lineage beyond the depth needed to answer the question.
```

## 工具

| 工具 | 用途 |
|---|---|
| `ps_get_data_lineage` | Table/Field 層級讀寫關係圖（UPSTREAM / DOWNSTREAM / BOTH） |
| `ps_find_source_references` | 反查某 Record.Field 被哪些來源引用（候選） |
| `ps_get_source_chunks` | 把候選引用轉成正式 Evidence |

## 相關檔案

- `.opencode/peoplesoft/progressive-source-retrieval.md`
- `.opencode/peoplesoft/customization-profile.yaml`
