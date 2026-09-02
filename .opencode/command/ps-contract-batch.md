---
description: Legacy Contract 批次（外環專用）：依 docs/ps-research/<領域>/contract-parts/manifest.txt 只寫本批 fragment 檔（固定表格）；不寫 NN、checklist、90-audit、spec
agent: ps-deep-research
---
對 `docs/ps-research/$ARGUMENTS/` 執行**一個 Legacy Contract 批次**（issue #17 Phase 1）。
**本指令不是研究模式、不是稽核模式**：你 system prompt 的階段一／階段二／稽核／提煉章節在此
**全部不適用**——不打勾、不寫 NN 檔、不寫 checklist.md、不寫 90-audit.md、不寫 wiki、不寫 log.md、
不遞增輪次、不歸檔。你只做三件事：read manifest → 逐單位 read 來源 NN 檔（缺料才委派）→
照 `.opencode/peoplesoft/legacy-contract-fragments.md` 把事實**填進固定表格**寫成 manifest 指定的檔。

**第一個回應必須是工具呼叫**：`read docs/ps-research/$ARGUMENTS/contract-parts/manifest.txt`
（$ARGUMENTS 應為單一領域目錄名；read 失敗且含空白時取第一個詞重試一次；
manifest 不存在 → 回報「無 manifest，本指令只供外環呼叫」後結束）。
第二個動作：`read .opencode/peoplesoft/legacy-contract-fragments.md`；第三個：`read .opencode/peoplesoft/legacy-contract-vocabulary.md`。
manifest 是外環產生的唯讀工單：每個單位給輸出檔路徑、來源 NN 檔、預抽事實（本檔該寫哪些欄位、資料流、
可用證據 token）。**不在「## 輸出」清單內的檔一律不碰；單位怎麼列你怎麼做，不多不少。**

## 每個單位的作法

1. read 來源 NN 檔（manifest 給路徑）。把「畫面與欄位」「行為邏輯」「資料流」「權限」「Evidence 附錄」的內容**搬成表格列**：
   - screen：manifest 列給本檔的每個欄位 → 控制項表一列（不寫 manifest 沒列的欄位）；行為邏輯的每一條 →
     狀態／互動／驗證表擇一（UI 顯示隱藏唯讀必填→狀態；設值帶入清除轉頁→互動；存檔擋錯訊息→驗證）；
     資料流 → 業務操作表的「寫入」欄；權限節 → 權限表；沒有委派就在「查詢證據」寫一列全 NOT_APPLICABLE。
   - screen 分頁檔（screen-<COMP>-p<k>.md）：只寫「## 畫面」（component／page／sourceNn）＋「## 控制項」（manifest 列的那一頁欄位）。
   - entity：資料流中該 Record 的操作 → 寫入表；欄位表只列鍵欄位、EFFDT 類、NN 提到的欄位；其餘鍵值查不到寫 UNRESOLVED。
2. **證據欄只准逐字抄 manifest 列出的 `E<nn>.<n>` token**（nn＝來源 NN 前兩碼）、本檔查詢表的 `SQL:<n>`、或 `UNRESOLVED`。不抄 ChunkId、不自創。
3. 缺料才委派，且一個單位至多 2 個委派、會查 oracleMCP 的同時 ≤ 3：
   - screen 缺 Page 清單／modes／Search Record／欄位盤點 → 委派 @ps-ui-flow：`[任務] Component <名> 的 Page 清單、Search Record、各 Page 的 Record.Field 盤點（cookbook §2d／§2e／§4 PSPNLGRPDEFN）`
   - entity 缺 RECTYPE／SQLTABLENAME／欄位／鍵 → 委派 @ps-metadata-flow：`[任務] Record <名> 結構：RECTYPE、SQLTABLENAME、欄位清單與鍵（cookbook §6／§7）`
   - 委派回報的 SQL 證據（sql＋keyRows）抄進本檔查詢表（screen：查詢證據；entity：參考查詢，狀態 PENDING），再以 `SQL:<n>` 引用。
   - 委派失敗一次即改填 UNRESOLVED，不重試第三次。
4. 值只准值域裡的字；不確定就 `UNRESOLVED`；不適用就 `NOT_APPLICABLE`。**禁止 `可能`／`大概`／`應該`／`probably`／`maybe` 等自由 token。**
5. **DIRECT_DB_WRITE_APPROVED 永遠不准寫**（存取策略 write 只能 PS_MEDIATED_WRITE 或 UNRESOLVED）；參考查詢狀態只能 PENDING／NOT_APPLICABLE。
6. 一檔 ≤150 行；容量由 manifest 分頁決定，你不自估、不加「續」列。

## 交付＝檔案，不是對話

寫 fragment 用**整檔 write**（一次寫完），寫完 **read 回來確認**每個章節與表頭都在，再做下一單位。
只在對話裡印表格而沒有 write＝本批白做（外環只驗檔案）。
**最終回覆只准一行：「已寫 <路徑>;<路徑>…」**。不得反問、不得婉拒、不得先輸出計畫。
