# 教訓登錄簿（pending）

> 登錄：`/ps-lesson <一句話描述>`（任何 session 發現錯誤時）。
> 分類提案：`/ps-lesson-apply`（只產提案，不改規則檔）。
> 套用：由**人工或較強模型**審查提案後修改目標檔，
> 並把該筆移到 `applied.md`（附 commit）。

## 登錄格式

```text
### L<流水號> <一句話標題>（YYYY-MM-DD）
- 症狀：模型做了什麼錯事
- 根因：為什麼會犯
- 錯誤行為 → 正確行為：
- 建議落點：機械化檢查 / 資料修正（哪個檔）/ 窄規則（哪個 agent 或 skill）/ AGENTS.md
- 建議測試檢查點：
- 狀態：PENDING | PROPOSED
```

落點分類優先序（永遠先問排在前面的做不做得到）：

```text
1. 機械化檢查   lint / 稽核判定 / 格式規則 / tools deny —— 模型無法違反
2. 資料修正     cookbook 表名、domain alias、fixtures —— 零 context 成本
3. 窄規則       只寫進會犯這個錯的那一個 agent / skill
4. 通用規則     AGENTS.md（常駐稅，最後手段）
```

---
<!-- 從這行以下登錄 -->
