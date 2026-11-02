---
description: 輸入一個或多個 Component，自動產生／續跑照 bizspec/standard.md 寫的繁體中文業務需求文件（第 0～10 章＋附錄，含證據章）
agent: ps-spec-author
subtask: false
---

為以下 Component 產製或續跑業務需求文件：

$ARGUMENTS

依 ps-spec-author 的輸入驗證與執行流程操作。不要要求使用者選擇內部步驟，或輸出整份文件到對話。
若清單缺漏，只問確切 Component 名稱。相同清單續跑同一工作；只有使用者明確要求才 Retry 或 NoQuery。
人工輸入檔（status.md、project.md、answers.md）由使用者自己編輯；模型只在 `.opencode/peoplesoft/sdoc/model.yaml` 設定。
