---
name: ps-security-flow
description: PeopleSoft 授權分析 — Menu → Component → Permission List → Role 路徑與 Row-level Security。
---

# ps-security-flow：安全性分析

## 職責

- Menu → Component → Permission List → Role（→ User 統計）授權路徑
- Page-level 權限（Display Only / 可更新）
- Row-level Security（Search Record / Security Record，含 Prompt 的 securityRecord）
- 供 ps-business-explain 說明「誰能維護這個畫面 / 欄位」

## Skill Rules

```text
Resolve access paths from metadata (ps_get_security_path), not from guesses
based on object names.

For each access path, preserve:
- menu, component, and page
- permission list and page-level access (display-only vs update)
- roles granting the permission list
- row-level security record if any
- origin classification of each object

Report user-level results as aggregates (counts, role membership) unless the
question explicitly requires named users; respect data permissions and
sensitive-data masking.

When the domain policy is custom-only, delivered roles or permission lists
that merely include the custom component are dependencies — the custom
component remains the business root.

The access path resolved here is an AUTHORIZATION chain built from
PSAUTHITEM joined to PSMENUITEM (cookbook §4). Its menu segment is technical
authorization metadata, not a user-visible navigation path: never render it
as 選單路徑 / 操作路徑 / 導覽入口, and never merge it with Portal Registry
entries into one claim. Questions of the form "which entry point does this
role actually see" need Portal Registry entries (cookbook §2k) crossed with
CREF/folder security and runtime context — not implemented in this version,
so answer with a gap rather than an inferred entry point.
```

## 工具

| 工具 | 用途 |
|---|---|
| `ps_get_security_path` | 取授權路徑（Menu → Component → PL → Role） |
| `ps_get_object_origin` | 分類授權鏈上物件的 origin |

## Subagent 模式

本 skill 由 `.opencode/agent/ps-metadata-flow.md` subagent 承載（授權類問題）：
- 委派 prompt 自帶 domain / searchMode 與問題，直接採用。
- 最終輸出只能是 `.opencode/peoplesoft/subagent-report-contract.md` 的 JSON 報告。

## 相關檔案

- `.opencode/peoplesoft/customization-profile.yaml`
- `.opencode/peoplesoft/mcp-tool-contracts.md`
