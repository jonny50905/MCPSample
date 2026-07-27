---
description: 登錄教訓並「本機立即生效」——自動分類落點、套用最小修改、記錄 applied.md；團隊生效走內部 git PR 審核
agent: ps-deep-research
---
把以下錯誤登錄成教訓並直接套用：

$ARGUMENTS

步驟：
1. 依 lessons 檔頭格式整理（症狀／根因／落點；從對話還原得到的就填，
   不確定的寫「待補」，**不要編造**）。
2. 分類落點，優先序：機械化檢查 > 資料修正 > 最窄規則檔 > AGENTS.md。
3. **直接套用**：
   - 事實類（`docs/ps-research/**`）→ 修正文件／entity 檔（作廢不刪除）。
   - 規則類（`.opencode/**`）→ 在落點檔做**最小新增**——只加不刪、
     不改寫任何既有規則；同時把對應測試檢查點加進 test-scenarios.md。
4. 完整記錄到 `lessons/applied.md`（症狀／根因／落點／實際修改摘要／日期）。
5. 回覆提醒使用者兩件事：(a) 重啟 OpenCode 後本機生效；
   (b) 團隊生效需 commit 後走**內部 git PR 審核**（SOP-1），merge 後
   其他同事 pull＋重啟才會生效。
6. 唯一例外：無法有把握判斷落點時，登錄 PENDING 到 pending.md 請人工
   決定——**不亂套用**。
