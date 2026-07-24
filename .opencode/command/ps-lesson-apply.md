---
description: 分類 pending 教訓並產生落檔提案（不直接改規則檔；套用由人工或較強模型審查執行）
agent: ps-deep-research
---
讀 `.opencode/peoplesoft/lessons/pending.md`，對每筆狀態為 PENDING 的教訓：

1. 依檔頭優先序分類落點（機械化檢查 > 資料修正 > 最窄規則檔 > AGENTS.md）。
2. 在該筆下方 append「提案」：目標檔案、建議修改內容（diff 形式）、
   建議新增的測試檢查點；狀態改為 PROPOSED。
3. **事實類**教訓（落點在 `docs/ps-research/**`，含 wiki entity 檔）：
   **可直接套用**——依「作廢不刪除」修正對應文件 / entity 檔，
   然後把該筆移到 `applied.md`（註明落點與日期）。
4. **規則類**教訓（落點在 `.opencode/`）：**不得**修改任何 agent /
   skill / 規則 / 資料檔——只留 PROPOSED 提案，套用由管理者依
   `.opencode/peoplesoft/SOP.md` 的 SOP-1 執行（可將遮敏後提案貼給
   較強模型審查），完成後由管理者移到 `applied.md`。
