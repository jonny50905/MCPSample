---
name: ps-peoplecode-flow
description: PeopleCode 事件與分支邏輯分析（FieldChange / SaveEdit / SavePre/PostChange…）— 漸進式取段，不整支載入。
---

# ps-peoplecode-flow：PeopleCode 邏輯分析

## 職責

- 搜尋客製 PeopleCode（依 Customization Profile 過濾 origin / prefix）
- 取得精確 Chunk 並分析事件邏輯（如選了某 choice 值後的條件分支）
- 追蹤 Function / Class / Method 呼叫鏈中「回答問題必要」的部分
- 辨識 UI 狀態變異（Visible / Hide / Gray / DisplayOnly…）——條件式
  控制畫面顯示是業務邏輯，寫入 findings，不當雜訊略過
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

Treat UI state mutations as findings, not noise.
UI mutation patterns (closed set):
  .Visible = / Hide( / UnHide( / HideRow( / HideScroll( /
  Gray( / UnGray( / .DisplayOnly = / .Enabled = / .Required =
For each mutation preserve: the governing condition branch,
the target (RECNAME.FIELDNAME; scroll level for row/scroll mutations),
the state change, the event location, and evidence IDs.
Classify each mutation as businessRelevant (the condition references
a business field or business value) or presentationOnly.

Classify each conclusion as CONFIRMED, INFERRED, or DYNAMIC_RUNTIME.
```

## Context Budget

共用停止規則（見 progressive-source-retrieval.md §5）：

```text
maxSearchResults: 20 / maxSelectedSymbols: 8 / maxInitialChunks: 10
maxTotalChunks: 16 / maxExpansionRounds: 3 / maxChunksPerExpansion: 4
```

## Subagent 模式

以 OpenCode subagent（`.opencode/agent/ps-peoplecode-flow.md`）執行時：
- 委派 prompt 自帶 domain / searchMode / customPrefixes，直接採用，不重新解析。
- 最終輸出只能是 `.opencode/peoplesoft/subagent-report-contract.md` 的 JSON 報告；
  raw chunks 留在本 context，不回傳（單段引用 ≤ 5 行）。

## 相關檔案

- `.opencode/peoplesoft/progressive-source-retrieval.md`
- `.opencode/peoplesoft/customization-profile.yaml`
