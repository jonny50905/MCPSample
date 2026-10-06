---
description: 登錄教訓並「本機立即生效」——自動分類落點、套用最小修改、記錄 applied.md；團隊生效走內部 git PR 審核
argument-hint: <描述>
disable-model-invocation: true
---
本指令須由 ps-deep-research 主代理執行（互動：`claude --agent ps-deep-research`，進去後再下本指令；外環 headless 已帶 `--agent ps-deep-research`）。
你若不是 ps-deep-research——例如你沒有 Write 工具——不要執行任何步驟，只回覆一行：
請以 `claude --agent ps-deep-research` 開新 session 後再下 `/ps-lesson $ARGUMENTS`。

把以下錯誤登錄成教訓並直接套用：

$ARGUMENTS

**禁止複述計畫——第一個回應必須是工具呼叫：先 Read
`.claude/peoplesoft/lessons/applied.md`（本機帳本，編號 `C<n>`）取得下一個流水號，
然後立刻進行分類與套用。**

步驟：
1. 依 lessons 檔頭格式整理（症狀／根因／落點；從對話還原得到的就填，
   不確定的寫「待補」，**不要編造**）。
2. 分類落點，優先序：機械化檢查 > 資料修正 > 最窄規則檔 > CLAUDE.md。
3. **直接套用**：
   - 事實類（`docs/ps-research/**`）→ 修正文件／entity 檔（作廢不刪除）。
   - 規則類（`.claude/**`）→ 在落點檔做**最小新增**——只加不刪、
     不改寫任何既有規則；同時把對應測試檢查點寫進該筆帳本的『測試檢查點』欄。
4. 完整記錄到 `lessons/applied.md`（症狀／根因／落點／實際修改摘要／日期）。
5. 回覆提醒使用者兩件事：(a) 開新的 Claude Code session 後本機生效（agent／skill／command 檔在 session 啟動時載入）；
   (b) 團隊生效需 commit 後走**內部 git PR 審核**（SOP-1），merge 後
   其他同事 pull＋開新 session 才會生效。
6. 唯一例外：無法有把握判斷落點時，登錄 PENDING 到 pending.md 請人工
   決定——**不亂套用**。
