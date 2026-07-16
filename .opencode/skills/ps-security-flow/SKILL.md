---
name: ps-security-flow
description: Use when answering PeopleSoft security questions — who can access a component/page, which permission lists and roles grant it, the menu → component → permission list → role → user path, and row-level security records involved.
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
```

## 工具

| 工具 | 用途 |
|---|---|
| `ps_get_security_path` | 取授權路徑（Menu → Component → PL → Role） |
| `ps_get_object_origin` | 分類授權鏈上物件的 origin |

## 相關檔案

- `.opencode/peoplesoft/customization-profile.yaml`
- `.opencode/peoplesoft/mcp-tool-contracts.md`
