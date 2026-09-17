---
description: 補研究（auto-loop 專用）：依 docs/ps-research/<領域>/supplemental-parts/current.manifest.md 只補工單指定的事實，結果只寫工單指定的收據檔；不寫 NN、不寫 wiki、不寫 checklist
agent: ps-deep-research
---
對 `docs/ps-research/$ARGUMENTS/` 執行**一張補研究工單**。
**本指令不是研究模式**：你 system prompt 的階段一／階段二／稽核模式／提煉模式在此**都不適用**
——不讀 checklist、不從未勾項續跑、不寫 checklist.md、不寫 90-audit.md、不寫 log.md、
不改任何 NN 檔、不寫 wiki。你只做三件事：read 工單 → 依工單讀指定 NN 節並委派補查 →
把結果寫成收據（三張表）到工單「## 輸出」指定的**那一個**檔。

**先做你 system prompt 的第 0 步（Oracle 連線）**，接著就 read 工單（兩者之間不做別的事）：
`read docs/ps-research/$ARGUMENTS/supplemental-parts/current.manifest.md`
（$ARGUMENTS 是單一領域目錄名；工單不存在 → 回報「無工單，本指令只供 auto-loop 呼叫」後結束）。

規則全部在 `.opencode/peoplesoft/supplemental-contract.md`（事實類別 → 委派鏈、收據三張表的欄名與值域、
表格節敘述的分格規則、機器參照三種形式、處置值域、硬規則）——照它做，不要自由發揮。

要點：
- **必須** read 工單「讀取範圍」表列出的每個檔的每個節（用表上的 offset／limit；`@缺` 的不讀）；
  「不回讀已完成 NN」的規則對本指令不適用。工單沒列的檔不讀。
- 只補「要補的屬性」列出的事實；委派對象只准表裡的 ps-\* agent，一個委派一個聚焦問題；
  會查 oracleMCP 的委派同時 ≤3（連線由你在第 0 步建立；BLOCKED(NOT_CONNECTED) 只重連重派一次）。
- 缺證據走出口：SQL 型寫 `待人工SQL` 證據列；CHUNK 型不寫該事實、處置 NO_EVIDENCE＋查法收據。
- 收據 ≤150 行、無三反引號圍欄、無 `[[ ]]`、不引用工單以外的任何識別；格內不出現 `|`／`｜`
  （表格節敘述的固定分格 `｜` 除外；SQL 的 `||` 改 CONCAT()、選項用 `/` 分隔）；查無時兩張表只留表頭與分隔列。
- 寫收據用整檔 write，寫完 read 回來確認三張表都在。**最終回覆只准一行：「已寫 <收據路徑>」**。
  不得反問、不得婉拒、不得先輸出計畫。
