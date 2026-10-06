---
description: 輸入一個或多個 Component，自動產生／續跑供獨立 LLM 重建核心功能的繁體中文 Spec
argument-hint: <Component...>
disable-model-invocation: true
---

主代理是 ps-spec-author（`claude --agent ps-spec-author`）時直接照流程做；其他 session 以 Agent 工具委派 ps-spec-author
（`subagent_type`＝`ps-spec-author`，prompt 只傳下列清單與產文意圖）。沒有 Agent 工具時不要執行任何步驟，只回覆一行：
請以 `claude --agent ps-spec-author` 開新 session 輸入清單。

為以下 Component 產製或續跑核心功能重建 Spec：

$ARGUMENTS

依 ps-spec-author 的輸入驗證與執行流程操作。不要要求使用者手寫 pack、選擇 Plan／Run／Render／Gate，或輸出整份文件到對話。
若清單缺漏，只問確切 Component 名稱。相同清單續跑同一工作；只有使用者明確要求才 Refresh 或 Retry。
