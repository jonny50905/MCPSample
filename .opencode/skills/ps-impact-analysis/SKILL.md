---
name: ps-impact-analysis
description: (選配) 物件變更影響盤點 — UI / PeopleCode / SQL / SQR / AE / Process / Security 引用面與嚴重度分級。
---

# ps-impact-analysis：變更影響分析（選配）

## 職責

給定一個變更目標（Record.Field、Translate Value、SQL Definition、Procedure …），
盤點受影響的物件並分級，供變更評估。

## 工作流

```text
1. 分類目標 origin（ps_get_object_origin）
2. 反查引用（ps_find_source_references：PEOPLECODE / SQL / SQR / SQC）
3. UI 面：ps_search_ui_semantics + ps_get_ui_graph（哪些 Page / Choice 用到）
4. 血緣面：ps_get_data_lineage（上下游讀寫）
5. 執行面：ps_get_process_usage（哪些 Process / Job 會跑到）
6. 安全面：ps_get_security_path（授權是否受影響）
7. 對關鍵引用取精確 Chunk 確認（ps_get_source_chunks）
8. 產出影響清單
```

## Skill Rules

```text
Follow the progressive source retrieval protocol for every long-text lookup —
reference hits are candidates until confirmed by exact chunks.

Classify every impacted object with its origin
(CUSTOM_PREFIX / CUSTOM_REGISTRY / MODIFIED_DELIVERED / DELIVERED / UNKNOWN)
and report custom impacts separately from delivered dependencies.

For each impact item, preserve:
- impacted object and its type
- how it references the change target (usage type)
- severity: BREAKS / BEHAVIOR_CHANGE / COSMETIC / UNKNOWN
- confidence: CONFIRMED / INFERRED / DYNAMIC_RUNTIME
- evidence IDs

Dynamic references (dynamic SQL, dynamic includes, runtime-built names) can
not be enumerated statically — list them as DYNAMIC_RUNTIME risks instead of
claiming full coverage.

State the search scope used; if any source type was not searched, say so —
do not imply the impact list is complete when it is not.
```

## Subagent 模式

Orchestrator 模式下本 skill 不單獨成為 subagent：由 ps-orchestrator 依上方
工作流把第 2～7 步拆派給對應 subagent（ui / 長文本 / metadata），
彙整各 JSON 報告後產出影響清單。

## 相關檔案

- `.opencode/peoplesoft/progressive-source-retrieval.md`
- `.opencode/peoplesoft/customization-profile.yaml`
- `.opencode/peoplesoft/mcp-tool-contracts.md`
