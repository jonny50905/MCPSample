---
description: Spec 片段批次（ps-spec 外環專用）：$ARGUMENTS＝<jobId>-<attemptId>；只讀該 attempt 的 manifest.md 與 context/ 片段，寫 fragment.md；不讀 NN／wiki、不寫其他檔
argument-hint: <jobId>-<attemptId>
disable-model-invocation: true
---
本指令須由 ps-spec-worker 主代理執行（互動：`claude --agent ps-spec-worker`，進去後再下本指令；外環 headless 已帶 `--agent ps-spec-worker`）。
你若不是 ps-spec-worker，不要執行任何步驟，只回覆一行：
請以 `claude --agent ps-spec-worker` 開新 session 後再下 `/ps-spec-batch $ARGUMENTS`。

對 attempt「$ARGUMENTS」執行**一個 Spec 片段單位**。$ARGUMENTS 的形狀是 `<jobId>-<attemptId>`：
attemptId 是最後一個連字號之後的 `a` 加四位數字（例 `a0003`），其餘全部是 jobId（jobId 本身可含連字號）。

**禁止複述計畫、禁止先解釋你將要做什麼——你的第一個回應必須是工具呼叫：**
`Read .ps-runtime/spec/<jobId>/attempts/<attemptId>/manifest.md`
（Read 失敗 → 回報「無工單，本指令只供 ps-spec 外環呼叫」後結束；不得猜路徑、不得 Glob）。

之後照工單做：
1. 只 Read 工單「## 讀取範圍」列出的片段檔（每檔一次 Read；不讀其他任何檔）。
2. 依「## 條目」逐條整理成「## 事實」表（表頭逐字照工單；來源條目欄只寫條目號數字）；不採用的條目列入「## 未採用」表（原因只准值域內的四個值）。
3. 用 Write 整檔寫入工單「## 輸出」指定的那一個 fragment.md（≤150 行；無圍欄、無雙方括號連結、無 slot 標記、無 JSON）。條目太多寫不下：先把能處置的完整寫完，剩下的不要硬塞、也不要列入未採用——外環只採用已處置的條目，其餘拆成新單位重派。
4. Read 回來確認兩張表都在、每個條目都有去處。

**最終回覆只准一行：「已寫 <路徑>」**。不得反問、不得婉拒。
