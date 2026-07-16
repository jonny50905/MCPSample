---
name: ps-peoplecode-flow
description: Use when analyzing PeopleSoft PeopleCode logic — what happens on FieldChange/SaveEdit/SavePreChange/SavePostChange, how an event branches on a stored value (e.g. MIL_STATUS = 'E'), which functions/classes/methods are involved. Uses progressive source retrieval; never loads whole programs.
---

# ps-peoplecode-flow：PeopleCode 邏輯分析

## 職責

- 搜尋客製 PeopleCode（依 Customization Profile 過濾 origin / prefix）
- 取得精確 Chunk 並分析事件邏輯（如選了某 choice 值後的條件分支）
- 追蹤 Function / Class / Method 呼叫鏈中「回答問題必要」的部分
- 辨識動態 SQL / 動態 Label / 動態 Prompt 指定，標 `DYNAMIC_RUNTIME`
- 把確認的資料操作交給 `ps-sql-flow` / `ps-data-lineage`

## 檢索協定（必遵守）

一律遵守 `.opencode/peoplesoft/progressive-source-retrieval.md`：

```text
Search → Select → Fetch Exact Chunks → Analyze
→ Expand Required Context → Stop → Produce Evidence
```

語意切片單位（PeopleCode）：

```text
Event / Function / Class / Method / Property / AE PeopleCode Action
```

## 工具

| 工具 | 用途 |
|---|---|
| `ps_search_source` | `sourceTypes: ["PEOPLECODE"]`，hybrid 搜尋候選 chunk |
| `ps_get_source_chunks` | 取精確 Chunk（正式 Evidence） |
| `ps_expand_source_context` | 展開必要的呼叫對象 / 鄰近段 |
| `ps_get_source_outline` | 大型 Class / Event 先看骨架 |
| `ps_find_source_references` | 反查 Record.Field / Function 被誰引用 |

## Skill Rules

```text
Use progressive source retrieval for PeopleCode.

Search results are candidates only.
Retrieve exact database chunks before concluding.

Analyze PeopleCode by event, function, class, method, or AE action.
Do not retrieve an entire event or class unless the logic cannot be understood
from selected chunks.

Follow only the calls required to answer the question.
Treat delivered utility functions as dependencies, not as the business
implementation, when the domain policy is custom-only.

For each analyzed unit, preserve:
- program location (component / record / event, or class and method)
- condition branches relevant to the question
- referenced records and fields
- called functions and methods
- evidence IDs

If SQL text, labels, prompts, or transfers are built dynamically,
mark them as DYNAMIC_RUNTIME and keep the PeopleCode evidence.

Classify each conclusion as CONFIRMED, INFERRED, or DYNAMIC_RUNTIME.
```

## Context Budget

共用停止規則（見 progressive-source-retrieval.md §5）：

```text
maxSearchResults: 20 / maxSelectedSymbols: 8 / maxInitialChunks: 10
maxTotalChunks: 16 / maxExpansionRounds: 3 / maxChunksPerExpansion: 4
```

## 相關檔案

- `.opencode/peoplesoft/progressive-source-retrieval.md`
- `.opencode/peoplesoft/customization-profile.yaml`
