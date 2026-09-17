# 補研究契約（Supplemental Research：指定 NN＋指定問題的定向補查）

適用：`/ps-supplement <領域>` 指令（由 ps-auto-loop 的補研究迷你圈啟動；不是給人手動下的指令）。
目的：對**已有 NN 檔**的物件，只補「工單指定的事實類別與屬性」，把結果寫成**收據**；
外環確定性地把收據合併進 NN 檔、發布結果、標記 wiki。模型不寫 NN、不寫 wiki、不寫 checklist。

## 1. 工單（manifest）——外環寫、你只讀

路徑固定：`docs/ps-research/<領域>/supplemental-parts/current.manifest.md`。內容只有：

- 目標（型別＋物件名）、事實類別（能力目錄代號）、要補的屬性、情境、證據政策、時效。
- **讀取範圍表**：`| 檔 | 節 | offset | limit |`——只准 read 這些檔的這些節（`read(filePath, offset, limit)`）；
  `@缺`＝該節不存在，不讀。表裡可能含一跳 callee NN（AE／SQR／SQC／PROCESS）的「執行方式」「資料流」節。
- 委派鏈提示與唯一可寫的收據路徑。

工單沒列的檔不讀、沒列的事實不查。工單不存在 → 回一行「無工單，本指令只供 auto-loop 呼叫」後結束。

## 2. 事實類別 → 委派鏈（一個委派一個聚焦問題；委派對象只准 ps-\* agent）

| 事實類別 | 委派鏈（依序） | 缺證據出口 |
|---|---|---|
| UI.COMPONENT_IDENTITY、UI.NAVIGATION、UI.FIELD_INVENTORY | @ps-ui-flow（導覽入口依 cookbook §2k canonical） | SQL 型→追加證據寫 `待人工SQL` |
| BEHAVIOR.RULES、BEHAVIOR.VALIDATIONS | @ps-peoplecode-flow →（規則讀 View 時）@ps-sql-flow | CHUNK 型→不寫該事實、處置 NO_EVIDENCE＋查法收據 |
| DATA.FLOW、DATA.RECORD_USAGE | @ps-sql-flow → @ps-peoplecode-flow | 同上 |
| DATA.FILE_INPUT、DATA.FILE_OUTPUT | @ps-peoplecode-flow（File 物件／Rowset 讀寫）→ callee：@ps-sqr-flow（SQR／SQC）、@ps-ae-flow（AE） | 同上 |
| PROCESS.EXECUTION | @ps-metadata-flow（帶 ps-process-flow skill）→ @ps-ae-flow／@ps-sqr-flow | SQL 型→`待人工SQL` |
| SECURITY.ACCESS | @ps-metadata-flow（帶 ps-security-flow skill） | SQL 型→`待人工SQL` |
| RELATED.OBJECTS | @ps-metadata-flow（帶 ps-data-lineage skill）→ @ps-peoplecode-flow | 同上 |

工單類別不在表內（GAPS、EVIDENCE.APPENDIX、ENTITY.DETAIL 由外環直接抽取，不會發工單）→ 處置 `UNSUPPORTED`。
會查 oracleMCP 的委派同時 ≤3；Oracle 連線由你在第 0 步建立（照你 system prompt 的第 0 步，比 read 工單更早）；
BLOCKED(NOT_CONNECTED) 只重連重派一次。

## 3. 收據（唯一可寫；路徑照工單「## 輸出」）

三張表、欄名逐字、≤150 行、不得有三反引號圍欄、不得有 `[[ ]]`（物件名用反引號或裸字）、
不得出現 requirementRef／jobId／packId／consumer 字樣、不得寫工單以外的任何識別。

```markdown
## 處置
| 處置 | 查法收據 |
|---|---|
| RESEARCHED | ps-peoplecode-flow 搜 TW_DEMO_A SavePostChange 3 筆 chunk；ps-sqr-flow 查 TWSQR_DEMO 讀檔段 |

## 追加事實
| 節 | 信心 | 敘述 | 證據# |
|---|---|---|---|
| 行為邏輯 | CONFIRMED | 匯入時逐列讀取 CSV，第 1 欄為員工編號、第 2 欄為生效日 | 1 |
| 資料流 | CONFIRMED | PS_DEMO_STG｜INSERT｜SQR TWSQR_DEMO 讀檔後寫入 | 2 |
| 未解事項 | INFERRED | 檔案編碼未在程式中指定，疑為系統預設 | 無 |

## 追加證據
| 位置 | 說明 | 機器參照 |
|---|---|---|
| `peoplecode/TW_DEMO_A/.../SavePostChange.pcode:40-58` | File 物件讀取迴圈 | ChunkId `3f2a9c1e-7b4d-4e8a-9c6f-1d2e3a4b5c6d` |
| `sqr/TWSQR_DEMO.sqr:120-140` | 讀檔後 INSERT | ChunkId `9b2f5c1e-4a3d-4f0a-8f21-7e5d0c9a1b2c` |
```

規則（外環機械驗收，任一不符＝本次白做）：

- 處置 ∈ `RESEARCHED`（有追加事實）／`ALREADY_COVERED`（工單要的事實 NN 該節已寫、且非空洞——外環會核對）／
  `NO_EVIDENCE`（現查仍無；查法收據必填，可附 `待人工SQL` 證據列與未解事項）／`NOT_IN_DOMAIN`／`UNSUPPORTED`。
  查法收據：用什麼工具、什麼參數、查了幾頁——沒有查法的查無不得寫。
- 節 ∈ 相關物件／功能定位／畫面與欄位／行為邏輯／資料流／執行方式／權限／未解事項（八節；不得寫 Evidence 附錄，證據走第三張表）。
- 信心 ∈ CONFIRMED／INFERRED／DYNAMIC_RUNTIME；CONFIRMED 必須有證據#。
- 證據#＝追加證據表的列序（1 起算），多筆用 `;`；無＝`無`。外環會把它換成 NN 附錄的新編號。
- **表格節的敘述**用全形直線 `｜` 分格，格數固定：畫面與欄位 5 格（欄位｜顯示文字｜類型｜選項｜生命狀態）、
  資料流 3 格（表｜操作｜來源；信心由信心欄補上）、相關物件 2 格（物件｜角色）。條列節（行為邏輯、未解事項）與
  文字節（功能定位、執行方式、權限）寫一句完整敘述。
- 機器參照只准三種：完整 36 字元 ChunkId／可重跑的 `SELECT … FROM …`／`待人工SQL`。ChunkId 不得縮寫。
- **空表**：處置不是 RESEARCHED 時（NO_EVIDENCE／ALREADY_COVERED／NOT_IN_DOMAIN／UNSUPPORTED），「## 追加事實」與
  「## 追加證據」兩張表仍要出現，只留表頭列與分隔列，不寫任何資料列（不寫「無」列、不寫「（空）」）。
- **格內不得出現 `|` 或 `｜`**（表格節敘述的固定分格除外）：SQL 的字串連接 `||` 改寫成 `CONCAT()`，
  選項值之間用 `/` 分隔，文字裡的「或」用字寫出，不用直線。
- 只追加、不改寫：你補的事實會被追加到 NN 該節末尾；與既有敘述矛盾時照實寫你查到的，矛盾由稽核處理。

查無時的收據長這樣（兩張空表只有表頭與分隔列；查法收據必填）：

```markdown
## 處置
| 處置 | 查法收據 |
|---|---|
| NO_EVIDENCE | ps-peoplecode-flow 搜 TW_DEMO_A 全部事件 2 頁無 File 物件；ps-sqr-flow 搜 TWSQR_DEMO 無 open／read 段 |

## 追加事實
| 節 | 信心 | 敘述 | 證據# |
|---|---|---|---|

## 追加證據
| 位置 | 說明 | 機器參照 |
|---|---|---|
```

## 4. 硬規則

- 本指令**不是研究模式**：不讀 checklist、不從未勾項續跑、不寫 checklist／90-audit／log／NN／wiki。
- **必須** read 工單列出的 NN 節（系統提示的「不回讀已完成 NN」在此不適用）——補研究就是要知道既有寫了什麼。
- 寫收據用整檔 write，寫完 read 回來確認三張表都在，再結束。最終回覆只准一行：「已寫 <收據路徑>」。
- 不得反問、不得婉拒、不得先輸出計畫；第 0 步（Oracle 連線）照你 system prompt 先做，接著就 read 工單
  （兩者之間不做別的事）。
