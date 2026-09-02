# Legacy Contract Fragment 寫法（模型側契約）

fragmentFormatVersion: 1

本檔規定 `/ps-contract-batch` 與 `/ps-contract-verify` 產出的 **fragment／收據檔**長什麼樣。
外環（`scripts/ps-contract.ps1`）逐字比對章節標題與表頭、逐格比對值域（`legacy-contract-vocabulary.md`）、
逐格解析證據、對照 manifest 的欄位範圍；任何不符＝該檔無收據＝白做。
Canonical contract JSON、stable ID、spec.md、驗證結果（PASS／FAIL）全部由外環產生，
**你不寫 ID、不寫 JSON、不寫 spec、不判 PASS／FAIL**。

## 硬規則（違反即無收據）

1. 只寫 manifest「## 輸出」列出的那些檔；路徑、檔名照抄。不碰 NN 檔、checklist、90-audit、wiki、spec。
2. 章節標題與表頭**逐字**照本檔（含欄數、欄序、全形／半形）。不加欄、不省欄、不改名。
3. 每一格只准：本檔指定值域的值、自然鍵（Record.Field／Component／Page／操作鍵）、數字、`;` 分隔的多值、
   `label=value` 成對選項、或 `UNRESOLVED`／`NOT_APPLICABLE`（依欄位允許）。**不得留空格、不得寫句子、不得自創詞。**
   說明類欄位（「說明」「條件」「內容」「訊息」「列選擇」「業務語意」「用途」「關鍵列」）可寫短句，但不得含 `|`。
4. 「證據」欄只准三種 token，全部**逐字抄 manifest 印出的清單**：
   `E<nn>.<n>`（nn＝來源 NN 檔前兩碼、n＝該檔 Evidence 附錄第 n 列，如 `E03.5`）、
   `SQL:<n>`（screen＝本檔「查詢證據」表第 n 列；entity＝本檔「參考查詢」表第 n 列）、`UNRESOLVED`。
   多個以 `;` 分隔。**不抄 ChunkId、不自創、不用 manifest 沒列的 E token。**
5. 自然鍵一律大寫，`Record.Field` 恰含一個點；各段（COMPONENT、PAGE、RECNAME、FIELDNAME、OPKEY）內不得有 `.`、`;`、`|`、空白。
   操作鍵符合 `^[A-Z][A-Z0-9_]{1,30}$`。
6. 一檔 ≤150 行。**容量由 manifest 決定**：控制項表只寫 manifest 列給本檔的那一頁欄位（不多不少）；
   其餘欄位由 `screen-<COMPONENT>-p<k>.md` 分頁檔承載（manifest 另列單位）。寫不下＝外環會縮頁重排，你不用自估。
7. 缺值：查不到＝`UNRESOLVED`；不適用＝`NOT_APPLICABLE`。整個表格不適用時保留標題與表頭，只寫一列全 `NOT_APPLICABLE`。
8. 禁止在檔內出現 subagent 契約 JSON、`"findings"`、`"evidence"` 等字樣或三反引號圍欄。
9. 委派取得的 SQL 型事實（sql＋keyRows）**抄進本檔的查詢表**（screen：查詢證據；entity：參考查詢），再以 `SQL:<n>` 引用。
   entity「參考查詢」的狀態欄**只准 `PENDING`／`NOT_APPLICABLE`**——EXECUTED／FAILED 由 verify 收據決定。
10. `DIRECT_DB_WRITE_APPROVED` 永遠不准寫（存取策略 write 只能 `PS_MEDIATED_WRITE` 或 `UNRESOLVED`）。
11. 寫完 **read 回來確認**表格都在；最終回覆只准一行：`已寫 <路徑>;<路徑>…`。

## screen fragment（`contract-parts/screen-<COMPONENT>.md`，一個 Component 一檔）

來源＝manifest 指定的 NN 檔（read 它的「畫面與欄位」「行為邏輯」「資料流」「權限」「Evidence 附錄」）。
缺料才委派：Page 欄位盤點／modes／Search Record → @ps-ui-flow（cookbook §2d／§2e／§4）；其餘不委派。
委派回報的 SQL 證據抄進「## 查詢證據」。

```markdown
## 畫面
| 鍵 | 值 |
|---|---|
| component | <COMPONENT> |
| pages | <PAGE1>;<PAGE2> |
| searchRecord | <RECNAME 或 UNRESOLVED> |
| modes | ADD;UPDATE（componentMode，多值） |
| menuPath | <選單路徑短句 或 UNRESOLVED> |
| origin | <origin> |
| sourceNn | <NN 檔名，照 manifest> |

## 控制項
| 頁 | Record.Field | 顯示文字 | 語系 | 控制型 | 選項型 | 選項 | 預設 | 可見 | 可編輯 | 必填 | 證據 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| <PAGE> | <REC.FIELD> | <文字> | <languageCode> | <controlType> | <choiceType> | <label=value;…或 NOT_APPLICABLE> | <值或 UNRESOLVED> | <yesNo> | <yesNo> | <yesNo> | E03.1 |

## 狀態
| 目標 Record.Field | 屬性 | 條件 | 觸發事件 | 解析 | 證據 |
|---|---|---|---|---|---|
| <REC.FIELD> | <stateProperty> | <條件短句> | <eventTrigger> | <resolution> | E03.1 |

## 互動
| 觸發事件 | 條件 | 效果型 | 目標 | 說明 | 證據 |
|---|---|---|---|---|---|
| <eventTrigger> | <條件短句或 NOT_APPLICABLE> | <effectType> | <REC.FIELD／Component／操作鍵／NOT_APPLICABLE> | <短句> | E03.1 |

## 驗證
| 觸發事件 | 條件 | 訊息型 | 訊息 | 證據 |
|---|---|---|---|---|
| <eventTrigger> | <條件短句> | <messageKind> | <set,number 或文字> | E03.2 |

## 導覽
| 來源 | 目標 | 型 | 證據 |
|---|---|---|---|
| <MENU／Component／Page> | <Component／Page> | <navigationKind> | E03.3 |

## 業務操作
| 操作鍵 | 觸發 | 模式 | 說明 | 寫入 | 證據 |
|---|---|---|---|---|---|
| <OPKEY> | <eventTrigger> | <componentMode> | <短句> | <RECNAME:persistenceOperation;…或 NOT_APPLICABLE> | E03.4 |

## 權限
| Permission List | Role | 人數 | Search Record | 證據 |
|---|---|---|---|---|
| <CLASSID 或 UNRESOLVED> | <ROLENAME 或 UNRESOLVED> | <數字或 UNRESOLVED> | <RECNAME 或 UNRESOLVED> | <證據或 UNRESOLVED> |

## 查詢證據
| 用途 | SQL | 關鍵列 |
|---|---|---|
| <短句> | <單行 SELECT … FETCH FIRST 200 ROWS ONLY> | <關鍵列摘要> |
```

- 「寫入」欄的 `RECNAME` 必須與某個 entity fragment 的 `record` 相同（外環據此連結 effect）。
- 控制項表**只寫 manifest 給本檔的欄位**（第 1 頁）；每個都要有一列。NN 申報「（無——…）」時寫一列全 `NOT_APPLICABLE`。
- 「查詢證據」無委派時寫一列全 `NOT_APPLICABLE`。

## screen 分頁檔（`contract-parts/screen-<COMPONENT>-p<k>.md`，k ≥ 2；只在 manifest 列出時寫）

```markdown
## 畫面
| 鍵 | 值 |
|---|---|
| component | <COMPONENT> |
| page | <k> |
| sourceNn | <NN 檔名，照 manifest> |

## 控制項
| 頁 | Record.Field | 顯示文字 | 語系 | 控制型 | 選項型 | 選項 | 預設 | 可見 | 可編輯 | 必填 | 證據 |
|---|---|---|---|---|---|---|---|---|---|---|---|
```

- 只寫 manifest 給本頁的欄位，不多不少；證據 token 同主檔規則（本頁沒有查詢證據表，只能用 `E<nn>.<n>`／`UNRESOLVED`）。

## entity fragment（`contract-parts/entity-<RECNAME>.md`，一個 Record 一檔）

來源＝manifest 列的 NN 檔（資料流表、行為邏輯、Evidence 附錄）。缺料才委派：
Record 結構（RECTYPE／SQLTABLENAME／欄位／鍵）→ @ps-metadata-flow（cookbook §6／§7），SQL 證據抄進「## 參考查詢」（狀態 PENDING）。

```markdown
## 實體
| 鍵 | 值 |
|---|---|
| record | <RECNAME，不含 PS_> |
| businessMeaning | <一句業務語意> |
| storageKind | <storageKind> |
| physicalObject | <PS_… 或 NOT_APPLICABLE（Derived/Subrecord）或 UNRESOLVED> |
| origin | <origin> |
| domainGate | <domainGate> |
| sourceNn | <NN 檔名;…，照 manifest> |

## 欄位
| Field | Column | 型別 | 長度 | 鍵 | 必填 | 選項來源 | 證據 |
|---|---|---|---|---|---|---|---|
| <FIELDNAME> | <COLUMN 或 NOT_APPLICABLE> | <dataType> | <數字或 UNRESOLVED> | <keyFlag;…> | <yesNo> | <XLAT／PROMPT:<REC>／NONE／UNRESOLVED> | E03.4 |

## 鍵
| 鍵 | 值 |
|---|---|
| psKeys | <FIELD;FIELD 或 UNRESOLVED> |
| businessKey | <FIELD;… 或 UNRESOLVED> |
| physicalUniqueKey | <FIELD;… 或 UNRESOLVED 或 NOT_APPLICABLE> |
| parentRecord | <RECNAME 或 NOT_APPLICABLE 或 UNRESOLVED> |
| rowIdentity | <短句：哪些欄位唯一定位一列> |

## 生效日
| 鍵 | 值 |
|---|---|
| effdtRule | <effdtRule> |
| asOf | <asOfSource> |
| selection | <effdtSelection> |
| activeOnly | <yesNo> |

## 讀取語意
| 型 | 內容 | 證據 |
|---|---|---|
| <readSemanticKind> | <短句：來源／join／filter／lookup 對映…> | E03.4 |

## 參考查詢
| 用途 | SQL | 關鍵列 | 狀態 |
|---|---|---|---|
| <短句> | <單行 SELECT … FETCH FIRST 200 ROWS ONLY> | <關鍵列摘要或 NOT_APPLICABLE> | PENDING |

## 寫入
| 操作鍵 | 操作 | 列選擇 | 變更欄位 | 伴隨效果 | 證據 |
|---|---|---|---|---|---|
| <OPKEY> | <persistenceOperation> | <短句：鍵＋生效日怎麼選列> | <FIELD;… 或 DYNAMIC_RUNTIME> | <RECNAME:persistenceOperation;… 或 NOT_APPLICABLE> | E03.2 |

## 存取策略
| 鍵 | 值 |
|---|---|
| read | <accessStrategy，不得 DIRECT_DB_WRITE_APPROVED> |
| write | <PS_MEDIATED_WRITE 或 UNRESOLVED；不得 DIRECT_DB_WRITE_APPROVED> |
| approvalRef | <留 NOT_APPLICABLE；核准由人填 approvals.md> |
```

- 「欄位」表只列：鍵欄位、EFFDT／EFFSEQ／EFF_STATUS、NN 畫面與欄位或資料流提到的欄位（全欄位盤點不在本階段）。
- 「寫入」表的操作鍵必須與 screen fragment「業務操作」的操作鍵相同（外環據此連結）。
- 參考查詢只准 SELECT、必含列數上限、不得含省略號；不得對業務大表做無鍵全掃；狀態一律 `PENDING`。
- `storageKind` 為 `DERIVED_WORK`／`SUBRECORD`／`OTHER_LOGICAL` 時 `physicalObject` 必須 `NOT_APPLICABLE`，且「寫入」表寫一列全 `NOT_APPLICABLE`。

## verify 收據（`contract-parts/verify-<RECNAME>-<單位>.md`，`/ps-contract-verify` 產；一單位一委派一檔）

單位由 verify-manifest 給：`OBJ`（物件層）、`FLD-<a>-<b>`（欄位第 a～b 個）、`RQ-<n>`（第 n 個參考查詢）。
每檔必有「## 查詢」表（每跑一個樣板一列，SQL 逐字、狀態只寫執行狀態）；`FLD` 檔另有「## 欄位」表、`OBJ` 檔另有「## 物件」表。
**你不判 PASS／FAIL**（那是外環對照 entity fragment 算的）；查無就 `NOT_FOUND`，通道未掛整表一列 `ORACLE_MCP_DOWN`，逾時 `BLOCKED`。

```markdown
## 查詢
| 單位 | 樣板 | SQL | 關鍵列 | 狀態 |
|---|---|---|---|---|
| PS_TW_MILITARY | OBJECT_EXISTS | SELECT OBJECT_NAME, OBJECT_TYPE FROM ALL_OBJECTS WHERE OBJECT_NAME='PS_TW_MILITARY' FETCH FIRST 10 ROWS ONLY | PS_TW_MILITARY TABLE | EXECUTED |

## 物件
| 檢查 | 值 |
|---|---|
| OBJECT_TYPE | TABLE |
| RECTYPE | 0 |
| SQLTABLENAME | PS_TW_MILITARY |
| UNIQUE_INDEX | EMPLID;EFFDT |
```

```markdown
## 查詢
| 單位 | 樣板 | SQL | 關鍵列 | 狀態 |
|---|---|---|---|---|
| PS_TW_MILITARY | COLUMN_TYPE | SELECT COLUMN_NAME, DATA_TYPE, DATA_LENGTH FROM ALL_TAB_COLUMNS WHERE TABLE_NAME='PS_TW_MILITARY' ORDER BY COLUMN_ID FETCH FIRST 200 ROWS ONLY | 12 列 | EXECUTED |

## 欄位
| Field | Column | DATA_TYPE | DATA_LENGTH |
|---|---|---|---|
| EMPLID | EMPLID | VARCHAR2 | 11 |
| EFFDT | EFFDT | DATE | 7 |
| EXEMPT_RSN | NOT_FOUND | NOT_FOUND | NOT_FOUND |
```

```markdown
## 查詢
| 單位 | 樣板 | SQL | 關鍵列 | 狀態 |
|---|---|---|---|---|
| RQ.TW_MILITARY.1 | REFERENCE_QUERY | <逐字照 manifest 的 SQL> | 1 列 | EXECUTED |
```

- 「樣板」∈ verifyCheck；「狀態」∈ verifyQueryState；SQL 必須是本次實際執行的單行 SELECT（外環驗 SELECT-only）。
- RQ 單位的「單位」欄填 manifest 給的 RQ id、SQL 逐字照 manifest（外環比對 hash，改寫一字即不算）。
