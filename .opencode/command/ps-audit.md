---
description: 稽核 deep-research 文件（證據解引用、claim 反駁抽驗、完整性 diff），產 90-audit.md 並把問題回灌調查 checklist
agent: ps-deep-research
---
對 `docs/ps-research/$ARGUMENTS/` 執行稽核模式（見你 system prompt 的
「稽核模式」章節）。

**你這個 session 就是規模門（L29）指定的「新 session 稽核」——當場稽核
上限對本指令不適用（不論已完成檔數多少）。不得反問、不得婉拒、不得
建議再開 session：規模再大也照樣執行，分批委派本來就是你的作業方式。**

**禁止複述計畫——第一個回應必須是工具呼叫：先 read
`docs/ps-research/$ARGUMENTS/checklist.md` 取得已完成項清單
（舊格式領域則在 00-overview.md 的「調查進度」），
然後立刻委派第一個稽核任務。**
（$ARGUMENTS 應為單一領域目錄名；read 失敗且 $ARGUMENTS 含空白時，
取第一個詞當領域名重試一次——多打的字不是路徑的一部分。）

**委派一律循序（L66：oracleMCP 是單工有狀態的單一連線）**：一次只派一個
subagent，**等它回報後才派下一個**——任務 A 與任務 C 不得交錯並行、
同一任務的多個批次也不得同時派出。實測（2026-08）：一次派 6 個委派
（A 項 3 批＋任務 C 3 批）→ 各 subagent 的 connect／disconnect 在單一連線上
互拆 → **全體靜止、零輸出、零錯誤訊息**；改循序後同一份稽核順利跑完。
SOP-12 原本只規範「跨視窗不並行」，本條把它補成「**同一 session 內也不並行**」。

流程提要：

0. **旗標**：checklist.md 有「查無全量抽驗：待執行」行 → 每個任務 A
   委派末尾加註「本檔查無宣告抽驗全量做（不只抽 1~2 筆）」；
   步驟 3 回灌時把該行改為「已執行（第 N 輪）」。沒有該行＝照常抽驗。
1. **全量**：逐一「全部」已完成檔案委派 ps-auditor 做證據解引用驗證
   （任務 A）——範圍不是只有上輪回灌項；每檔抽 3~5 條標 CONFIRMED
   的重要 claim 做反駁驗證（任務 B）。
2. 以總覽的核心資料表清單做換角度完整性盤點（任務 C）——**每批
   至多 5 張表分批委派**，委派方聯集各批結果再與功能地圖 diff
   （整份一次委派會讓 subagent 觸發 context 自動壓縮，清單不可信）。
3. **先回灌＋輪次遞增**：read `checklist.md` 的「稽核輪次：N」
   （沒有該行視為 0）；任何非 PASS／VERIFIED 判定（FAIL／DISPUTED／
   自創詞一律算）與遺漏候選，**以檔為單位彙整、一檔一行**加進
   `checklist.md` 的調查進度（格式：`- [ ] A<n> 補查 <NN-檔名>：
   FAIL <x>／DISPUTED <y>／UNVERIFIABLE <z>（稽核）`；禁止逐筆開項），
   輪次行更新為 N+1；同時把所有**已打勾**項寫成**新檔**
   `checklist-archive-r<N+1>.md` 後從 checklist.md 移除
   （**禁止 read／改寫既有 archive 檔**——追加舊檔＝整檔重寫，
   檔案隨輪次變大必撐爆 write；每輪一個新檔＝真追加）。
4. **後寫** `90-audit.md`：**整檔重寫**，表頭「稽核輪次：N+1」＋本日
   日期；判定只准來自本輪 auditor 回報，**禁止 read 舊 90-audit.md、
   禁止沿用其數字或內容**；記分卡＝本輪**全量**數字（第 2 輪起另填
   「上輪回灌項覆核」節：屬實／誤報／不可查——**該節不取代記分卡**）；
   「已回灌」節逐行抄錄步驟 3 加的行。
   非 PASS ≥ 1 而 checklist.md 無新 A 行＝流程錯誤，不得寫記分卡。
5. 出現系統性錯誤（同類 FAIL ≥ 2）→ 提議我執行 `/ps-lesson`。
6. 結束前最後一個動作：read `checklist.md` 確認回灌行都在——
   缺就立刻補上再結束。
