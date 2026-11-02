---
description: 輸入一個或多個 Component，自動產生／續跑照 bizspec/standard.md 寫的繁體中文業務需求文件（第 0～10 章＋附錄，含證據章）
argument-hint: <Component...>
disable-model-invocation: true
---

主代理是 ps-spec-author（`claude --agent ps-spec-author`）時直接照流程做；其他 session 以 Agent 工具委派 ps-spec-author
（`subagent_type`＝`ps-spec-author`，prompt 只傳下列清單與產文意圖）。沒有 Agent 工具時不要執行任何步驟，只回覆一行：
請以 `claude --agent ps-spec-author` 開新 session 輸入清單。

為以下 Component 產製或續跑業務需求文件：

$ARGUMENTS

依 ps-spec-author 的輸入驗證與執行流程操作。不要要求使用者選擇內部步驟，或輸出整份文件到對話。
若清單缺漏，只問確切 Component 名稱。相同清單續跑同一工作；只有使用者明確要求才 Retry 或 NoQuery。
人工輸入檔（status.md、project.md、answers.md）由使用者自己編輯。
