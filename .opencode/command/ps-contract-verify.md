---
description: Legacy Contract 的 Oracle schema 唯讀驗證批次（外環專用）：依 contract-parts/verify-manifest.txt 一單位一委派跑 SELECT，結果只寫 contract-parts/verify-<RECNAME>-<單位>.md
agent: ps-deep-research
---
對 `docs/ps-research/$ARGUMENTS/` 執行**一個 Oracle schema 驗證批次**（issue #17 Phase 1，G16）。
**本指令不是研究模式、不是稽核模式**——不寫 NN、checklist、90-audit、wiki、spec、log.md。
你只做三件事：read verify-manifest → 逐單位委派 @ps-metadata-flow 跑唯讀 SELECT → 把回報**照抄成表**寫進該單位的收據檔。
**你不判 PASS／FAIL**：結果由外環對照 entity fragment 算；你只抄 SQL、關鍵列與執行狀態。

**第一個回應必須是工具呼叫**：`read docs/ps-research/$ARGUMENTS/contract-parts/verify-manifest.txt`
（不存在 → 回報「無 verify-manifest，本指令只供外環呼叫」後結束）。
第二個動作：`read .opencode/peoplesoft/legacy-contract-fragments.md`（「verify 收據」段）。

## 委派規則

- **一個單位一個委派**（manifest 的「## 單位 n」＝一個委派＝一個收據檔），禁止把多個單位或多個樣板族塞進同一委派；同時 ≤ 1（oracleMCP 連線全域單例，L109；查完不得 disconnect）。
- 委派模板（只傳事實，不貼 NN 內容）：
  - OBJ：`[任務] Oracle 物件驗證 Record <RECNAME>／實體表 <PHYSICAL>：照 cookbook §7a OBJECT_EXISTS＋OBJECT_TYPE、§7c RECTYPE／SQLTABLENAME、§7d／§7e 鍵與唯一索引<、§7f 生效日形狀>；每個查詢回報 sql＋keyRows；只准 SELECT。`
  - FLD：`[任務] Oracle 欄位驗證 <PHYSICAL>：照 cookbook §7b 取 ALL_TAB_COLUMNS 整表，回報下列欄位的 COLUMN_NAME／DATA_TYPE／DATA_LENGTH：<欄位清單>；查無回 NOT_FOUND；只准 SELECT。`
  - RQ：`[任務] 執行參考查詢 <RQ id>：<SQL 逐字>；回報 sql（逐字）＋keyRows 摘要；只准 SELECT，不得改寫 SQL。`
- 回報只有 `kind: "SQL"`（sql＋keyRows）才算數；PeoplecodeMetadata 定位不算。
- 委派回報 FAIL(ORACLE_MCP_DOWN) 或 BLOCKED → 該單位收據「## 查詢」整表一列，狀態欄照抄 `ORACLE_MCP_DOWN`／`BLOCKED`，**不得猜結果、不得重試迴圈**。
- 執行成功但查無物件／列 → 狀態 `NOT_FOUND`；ORA- 錯誤 → `FAILED`；有回傳 → `EXECUTED`。

## 輸出（只寫 manifest「## 輸出」列的檔）

每單位一檔 `docs/ps-research/$ARGUMENTS/contract-parts/verify-<RECNAME>-<單位>.md`，形狀照 `legacy-contract-fragments.md`「verify 收據」段：
「## 查詢」表每跑一個樣板一列（單位｜樣板｜SQL｜關鍵列｜狀態）；FLD 檔加「## 欄位」表（Field｜Column｜DATA_TYPE｜DATA_LENGTH，每欄一列，查無寫 NOT_FOUND）；
OBJ 檔加「## 物件」表（檢查｜值：OBJECT_TYPE／RECTYPE／SQLTABLENAME／UNIQUE_INDEX）。RQ 檔「單位」欄填 manifest 給的 RQ id、SQL 逐字。

- 「樣板」只准 verifyCheck 值域；「狀態」只准 verifyQueryState 值域；SQL 欄一律單行、必含列數上限。
- 寫完 **read 回來確認**。**最終回覆只准一行：「已寫 <路徑>;<路徑>…」**。不得反問、不得婉拒。
