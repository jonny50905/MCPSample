---
description: 稽核 deep-research 文件（證據解引用、claim 反駁抽驗、完整性 diff），產 90-audit.md 並把問題回灌調查 checklist
agent: ps-deep-research
---
對 `docs/ps-research/$ARGUMENTS/` 執行稽核模式（見你 system prompt 的
「稽核模式」章節）。

**禁止複述計畫——第一個回應必須是工具呼叫：先 read
`docs/ps-research/$ARGUMENTS/checklist.md` 取得已完成項清單
（舊格式領域則在 00-overview.md 的「調查進度」），
然後立刻委派第一個稽核任務。**

流程提要：

1. **全量**：逐一「全部」已完成檔案委派 ps-auditor 做證據解引用驗證
   （任務 A）——範圍不是只有上輪回灌項；每檔抽 3~5 條標 CONFIRMED
   的重要 claim 做反駁驗證（任務 B）。
2. 以總覽的核心資料表清單做換角度完整性盤點（任務 C），與功能地圖 diff。
3. **先回灌＋輪次遞增**：read `checklist.md` 的「稽核輪次：N」
   （沒有該行視為 0）；任何非 PASS／VERIFIED 判定（FAIL／DISPUTED／
   自創詞一律算）與遺漏候選，**以檔為單位彙整、一檔一行**加進
   `checklist.md` 的調查進度（格式：`- [ ] A<n> 補查 <NN-檔名>：
   FAIL <x>／DISPUTED <y>／UNVERIFIABLE <z>（稽核）`；禁止逐筆開項），
   輪次行更新為 N+1。
4. **後寫** `90-audit.md`：**整檔重寫**，表頭「稽核輪次：N+1」＋本日
   日期；判定只准來自本輪 auditor 回報，**禁止 read 舊 90-audit.md、
   禁止沿用其數字或內容**；記分卡＝本輪**全量**數字（第 2 輪起另填
   「上輪回灌項覆核」節：屬實／誤報／不可查——**該節不取代記分卡**）；
   「已回灌」節逐行抄錄步驟 3 加的行。
   非 PASS ≥ 1 而 checklist.md 無新 A 行＝流程錯誤，不得寫記分卡。
5. 出現系統性錯誤（同類 FAIL ≥ 2）→ 提議我執行 `/ps-lesson`。
6. 結束前最後一個動作：read `checklist.md` 確認回灌行都在——
   缺就立刻補上再結束。
