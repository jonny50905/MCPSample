---
name: ps-security-flow
description: >-
  PeopleSoft 授權分析技能（Menu → Component → Permission List → Role 路徑與 Row-level Security），
  不是可供 task 委派的 agent。授權問題一律委派 ps-metadata-flow，再由該 agent 讀取本 SKILL.md。
  不得使用 subagent_type=ps-security-flow。
---

# ps-security-flow：安全性分析（skill，不是 agent）

## 承載 agent 與讀取方式

- 本檔是知識與操作規則，**不是執行單位**：沒有 `.opencode/agent/ps-security-flow.md`，
  `task(subagent_type=ps-security-flow)` 會失敗（執行期 guard 回 `PS_TASK_TARGET_INVALID`）。
- 授權／Permission List／Role／誰能進哪個畫面 → 委派 **`ps-metadata-flow`**，在 task 文字指定讀本檔：

```json
{
  "description": "查核授權路徑",
  "subagent_type": "ps-metadata-flow",
  "prompt": "讀取 .opencode/skills/ps-security-flow/SKILL.md，依 oracle-query-cookbook.md 第 4 節查核授權鏈，回傳既定 JSON 報告。"
}
```

- ps-metadata-flow 讀本檔後：委派 prompt 自帶 domain / searchMode 與問題，直接採用；
  最終輸出只能是 `.opencode/peoplesoft/subagent-report-contract.md` 的 JSON 報告；
  報告的 `suggestedNext[].agent` 也只能寫 agent 名（授權類寫 ps-metadata-flow），不得寫本 skill 名。

## 職責

- Menu → Component → Permission List → Role（→ User 統計）授權路徑
- Page-level 權限（Display Only / 可更新）
- Row-level Security（Search Record / Security Record，含 Prompt 的 securityRecord）
- 供 ps-business-explain 說明「誰能維護這個畫面 / 欄位」

## Skill Rules

```text
Resolve access paths from metadata (cookbook §4 SELECTs over PSAUTHITEM / PSMENUITEM /
PSROLECLASS via oracleMCP_sql_run), not from guesses based on object names.

For each access path, preserve:
- menu, component, and page
- permission list and page-level access (display-only vs update)
- roles granting the permission list
- row-level security record if any
- origin classification of each object (cookbook §1)

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

## 實際可執行的途徑（唯一可呼叫的工具是 `oracleMCP_sql_run`）

| 職責 | 現行途徑 |
|---|---|
| 授權鏈查證 | ps-metadata-flow 用 `oracleMCP_sql_run`，照 `oracle-query-cookbook.md` §4 的樣板（只 SELECT、有列數上限） |
| 物件 origin 查證 | 同一承載 agent，照 cookbook §1 |
| 未連線 | SQL 工具回未連線 → 報告 `status: BLOCKED`、`blockedReason: NOT_CONNECTED`，不 connect、不重試 |
| 工具清單沒有 oracleMCP_ 工具 | 報告 `blockedReason: ORACLE_MCP_DOWN`，不猜工具名（cookbook 7a） |

`ps_get_security_path`／`ps_get_object_origin` 是 `mcp-tool-contracts.md` 的**協定角色**，目前**不是可呼叫的工具**——
呼叫必得 unavailable tool。

## 相關檔案

- `.opencode/agent/ps-metadata-flow.md`（承載 agent）
- `.opencode/peoplesoft/oracle-query-cookbook.md` §4／§1
- `.opencode/peoplesoft/customization-profile.yaml`
- `.opencode/peoplesoft/mcp-tool-contracts.md`
