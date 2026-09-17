---
description: Spec 片段批次（ps-spec 外環專用）：$ARGUMENTS＝<jobId>-<attemptId>；只讀該 attempt 的 manifest.md 與 context/ 片段，寫 fragment.md；不讀 NN／wiki、不寫其他檔
agent: ps-spec-worker
---
對 attempt「$ARGUMENTS」執行**一個 Spec 片段單位**。$ARGUMENTS 的形狀是 `<jobId>-<attemptId>`：
attemptId 是最後一個連字號之後的 `a` 加四位數字（例 `a0003`），其餘全部是 jobId（jobId 本身可含連字號）。

**禁止複述計畫、禁止先解釋你將要做什麼——你的第一個回應必須是工具呼叫：**
`read .ps-runtime/spec/<jobId>/attempts/<attemptId>/manifest.md`
（read 失敗 → 回報「無工單，本指令只供 ps-spec 外環呼叫」後結束；不得猜路徑、不得 glob）。

之後照工單做：
1. 只 read 工單「## 讀取範圍」列出的片段檔（每檔一次 read；不讀其他任何檔）。
2. 依「## 條目」逐條整理成「## 事實」表（表頭逐字照工單）；不採用的條目列入「## 未採用」表（原因只准值域內的四個值）。
3. 用 write 整檔寫入工單「## 輸出」指定的那一個 fragment.md（≤150 行；無圍欄、無雙方括號連結、無 slot 標記、無 JSON）。
4. read 回來確認兩張表都在、每個條目都有去處。

**最終回覆只准一行：「已寫 <路徑>」**。不得反問、不得婉拒。
