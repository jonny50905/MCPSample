---
description: JO 重建：開工或從 docs/build/status.md 續跑；參數 status＝只報進度，spec-update＝Spec 換新版後比對差異
agent: rebuild-lead
subtask: false
---

依 `docs/build/KICKOFF.md` 執行。參數：`$ARGUMENTS`

- 空白：沒有 `docs/build/status.md` 就從第 0 階段開工；有就從它的「下一步」續跑。
- `status`：只讀 `status.md` 與 `traceability.md`，回報階段、slice 進度、需求鍵各狀態數量、待解事項；不改檔、不派工。
- `spec-update`：執行 KICKOFF.md 的「Spec 更新」程序。
- 其他文字：當作使用者對本輪的附加指示；不得覆蓋 `AGENTS.md` 的規則。
