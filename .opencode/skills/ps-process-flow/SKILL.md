---
name: ps-process-flow
description: Use when explaining how a PeopleSoft batch object (SQR, AE, COBOL, Crystal) is executed — Process Definition, Process Type, Job/JobSet, Recurrence/schedule, Run Control record and page, and where users launch it from. Based on Oracle Process Scheduler metadata.
---

# ps-process-flow：Process Scheduler 分析

## 職責

- 由物件（SQR / AE …）反查 Process Definition 與 Process Type
- Job / JobSet 組成與執行順序
- Recurrence / 排程設定
- Run Control Record 與 Run Control Page（使用者從哪裡發動）
- 供 `ps-sqr-flow` / `ps-ae-flow` 回答「這支程式怎麼被執行」

## Skill Rules

```text
Use Oracle Process Scheduler metadata (via ps_get_process_usage) as the source
of truth for how a program is executed. Do not infer scheduling from source
code comments.

For each process, preserve:
- process name and process type
- containing jobs / jobsets and their order
- recurrence or trigger (on-demand run control page)
- run control record and page
- origin classification of each object

Distinguish:
- CONFIRMED   metadata directly shows the linkage
- INFERRED    linkage assembled from multiple metadata rows
- DYNAMIC_RUNTIME  process name or parameters built at runtime

When the domain policy is custom-only, report delivered processes only as
dependencies of the custom root.
```

## 工具

| 工具 | 用途 |
|---|---|
| `ps_get_process_usage` | Process Definition / Job / Recurrence / Run Control |
| `ps_get_object_origin` | 分類 Process 相關物件的 origin |
| `ps_get_ui_graph` | Run Control Page 的欄位與顯示文字（交 ps-ui-flow 規則） |

## 相關檔案

- `.opencode/peoplesoft/customization-profile.yaml`
- `.opencode/peoplesoft/mcp-tool-contracts.md`
