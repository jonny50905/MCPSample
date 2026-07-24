---
description: 分類 pending 教訓並產生落檔提案（不直接改規則檔；套用由人工或較強模型審查執行）
agent: ps-deep-research
---
讀 `.opencode/peoplesoft/lessons/pending.md`，對每筆狀態為 PENDING 的教訓：

1. 依檔頭優先序分類落點（機械化檢查 > 資料修正 > 最窄規則檔 > AGENTS.md）。
2. 在該筆下方 append「提案」：目標檔案、建議修改內容（diff 形式）、
   建議新增的測試檢查點；狀態改為 PROPOSED。
3. **不得**修改 `.opencode` 的任何 agent / skill / 規則 / 資料檔——
   套用請把 repo push 後交由人工或較強模型審查執行；套用完成後
   把該筆移到 `applied.md`（附 commit）。
