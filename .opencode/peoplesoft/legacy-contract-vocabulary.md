# Legacy Contract 封閉值域（單一真相）

vocabularyVersion: 1

本檔是 Legacy Contract（issue #17）所有封閉值域的**唯一**定義：
`scripts/ps-contract-lib.ps1` 機械解析本檔（`## 值域名` 標題＋其下表格的第一欄＝合法值），
模型寫 fragment 時**只准逐字使用**本檔列出的值。規則：

- 只加不刪；新增值時 `vocabularyVersion` 加一（收據記版本，舊 contract 需重驗）。
- 每個值域都含「未知」出口：`UNRESOLVED`＝查不到／不確定；`NOT_APPLICABLE`＝不適用（只在標明的值域）。
  缺值**不得留空、不得自創詞**（黑名單見文末）。
- 值一律大寫英數與底線；表格第二欄是給人看的說明，腳本不讀。

## controlType

| 值 | 說明 |
|---|---|
| EDIT_BOX | 單行輸入框 |
| LONG_EDIT | 多行輸入框 |
| DROP_DOWN | 下拉選單 |
| CHECKBOX | 核取方塊 |
| RADIO | 單選鈕 |
| PUSH_BUTTON | 按鈕 |
| HYPERLINK | 超連結 |
| GRID | Grid |
| SCROLL | Scroll Area |
| GROUP_BOX | Group Box（PSPNLFIELD.FIELDTYPE=2） |
| SUBPAGE | Subpage（FIELDTYPE=11） |
| SECONDARY_PAGE | Secondary Page 連結 |
| STATIC_TEXT | 靜態文字 |
| IMAGE | 圖片 |
| TREE | 樹狀 |
| OTHER | 其他已知型但本表未列 |
| UNRESOLVED | 查不到 |

## choiceType

| 值 | 說明 |
|---|---|
| TRANSLATE_VALUE | Translate value（PSXLATITEM） |
| PROMPT_TABLE | Prompt table |
| RADIO_BUTTON | 頁面單選鈕組 |
| DROP_DOWN | 頁面下拉（非 XLAT） |
| LIST_BOX | List box |
| CHECKBOX | 核取方塊值 |
| YES_NO | Y/N |
| PAGE_STATIC_CHOICE | 頁面靜態選項 |
| DYNAMIC_PROMPT | 動態 prompt |
| DYNAMIC_PEOPLECODE | PeopleCode 動態指定選項 |
| NONE | 非選項型控制項 |
| UNRESOLVED | 查不到 |

## languageCode

| 值 | 說明 |
|---|---|
| ZHT | 繁體中文 |
| ENG | 英文 |
| OTHER | 其他語系 |
| UNRESOLVED | 查不到 |

## yesNo

| 值 | 說明 |
|---|---|
| YES | 是 |
| NO | 否 |
| DYNAMIC_RUNTIME | 由 PeopleCode 執行期決定 |
| NOT_APPLICABLE | 不適用 |
| UNRESOLVED | 查不到 |

## stateProperty

| 值 | 說明 |
|---|---|
| VISIBLE | 顯示／隱藏 |
| ENABLED | 啟用／停用 |
| DISPLAY_ONLY | 唯讀 |
| REQUIRED | 必填 |
| LABEL | 動態 label |
| VALUE | 動態值 |
| OPTIONS | 動態選項 |
| STYLE | 樣式 |
| ROW_VISIBLE | 列／scroll 層級顯示（無 Record.Field，解析 NOT_APPLICABLE） |
| UNRESOLVED | 查不到 |

## eventTrigger

| 值 | 說明 |
|---|---|
| FIELD_CHANGE | FieldChange |
| FIELD_EDIT | FieldEdit |
| FIELD_DEFAULT | FieldDefault |
| FIELD_FORMULA | FieldFormula |
| ROW_INIT | RowInit |
| ROW_INSERT | RowInsert |
| ROW_DELETE | RowDelete |
| ROW_SELECT | RowSelect |
| SAVE_EDIT | SaveEdit |
| SAVE_PRE_CHANGE | SavePreChange |
| SAVE_POST_CHANGE | SavePostChange |
| WORKFLOW | Workflow |
| PRE_BUILD | Component PreBuild |
| POST_BUILD | Component PostBuild |
| PAGE_ACTIVATE | Page Activate |
| SEARCH_INIT | SearchInit |
| SEARCH_SAVE | SearchSave |
| ITEM_SELECTED | ItemSelected |
| BUTTON_CLICK | 按鈕 FieldChange |
| BATCH | 批次（AE／SQR／Process） |
| OTHER | 其他已知事件 |
| UNRESOLVED | 查不到 |

## effectType

| 值 | 說明 |
|---|---|
| SET_STATE | 改控制項狀態（配 stateProperty） |
| SET_VALUE | 設值 |
| SET_DEFAULT | 設預設值 |
| CLEAR_VALUE | 清值 |
| SHOW_MESSAGE | 顯示訊息 |
| NAVIGATE | 導覽／轉頁 |
| INVOKE_OPERATION | 觸發業務操作 |
| REFRESH_OPTIONS | 重算選項 |
| CALL_FUNCTION | 呼叫函式庫 |
| DYNAMIC_RUNTIME | 效果由執行期決定 |
| UNRESOLVED | 查不到 |

## messageKind

| 值 | 說明 |
|---|---|
| ERROR | 錯誤（阻擋） |
| WARNING | 警告（可續） |
| INFO | 資訊 |
| CONFIRM | 確認 |
| UNRESOLVED | 查不到 |

## navigationKind

| 值 | 說明 |
|---|---|
| MENU_ENTRY | 選單入口 |
| TRANSFER | Transfer 到其他 Component |
| TRANSFER_PAGE | TransferPage |
| SECONDARY_PAGE | 開 Secondary Page |
| MODAL | Modal |
| RETURN | 返回 |
| DYNAMIC_RUNTIME | 目標由執行期決定 |
| UNRESOLVED | 查不到 |

## componentMode

| 值 | 說明 |
|---|---|
| ADD | Add |
| UPDATE | Update/Display |
| UPDATE_ALL | Update/Display All |
| CORRECTION | Correction |
| DATA_ENTRY | Data Entry |
| UNRESOLVED | 查不到 |

## resolution

| 值 | 說明 |
|---|---|
| RESOLVED | 目標已解析到控制項 |
| NOT_APPLICABLE | scroll 層級等無 Record.Field 可解析 |
| UNRESOLVED | 解析不到 |

## origin

| 值 | 說明 |
|---|---|
| CUSTOM_PREFIX | 名稱符合客製 Prefix |
| CUSTOM_REGISTRY | 客製登錄表內 |
| MODIFIED_DELIVERED | 原生名稱、內容已被修改 |
| DELIVERED | 原生未改 |
| UNKNOWN | 無法確認 |

## domainGate

| 值 | 說明 |
|---|---|
| DOMAIN_ROOT | 業務根物件 |
| DEPENDENCY | 依附／共用物件 |
| OUT_OF_SCOPE | 域外 |

## storageKind

| 值 | 說明 |
|---|---|
| SQL_TABLE | SQL Table |
| SQL_VIEW | SQL View |
| DYNAMIC_VIEW | Dynamic View |
| QUERY_VIEW | Query View |
| DERIVED_WORK | Derived/Work（無實體表） |
| SUBRECORD | Subrecord（無實體表） |
| TEMP_TABLE | Temporary Table |
| OTHER_LOGICAL | 其他邏輯結構（無實體表） |
| UNRESOLVED | 查不到 |

## dataType

| 值 | 說明 |
|---|---|
| CHAR | Character |
| VARCHAR | Variable character |
| NUMBER | Number |
| SIGNED_NUMBER | Signed number |
| DATE | Date |
| TIME | Time |
| DATETIME | DateTime |
| LONG_CHAR | Long character |
| IMAGE | Image |
| IMAGE_REF | Image reference |
| OTHER | 其他 |
| UNRESOLVED | 查不到 |

## keyFlag

| 值 | 說明 |
|---|---|
| K | Key |
| A | Alternate search key |
| S | Search key |
| D | Duplicate order key |
| N | 非鍵 |
| UNRESOLVED | 查不到 |

## effdtRule

| 值 | 說明 |
|---|---|
| NONE | 無生效日 |
| EFFDT_ONLY | 只有 EFFDT |
| EFFDT_STATUS | EFFDT＋EFF_STATUS |
| EFFDT_EFFSEQ | EFFDT＋EFFSEQ |
| EFFDT_EFFSEQ_STATUS | EFFDT＋EFFSEQ＋EFF_STATUS |
| CUSTOM | 非標準生效日邏輯（內容寫在讀取語意） |
| UNRESOLVED | 查不到 |

## asOfSource

| 值 | 說明 |
|---|---|
| SYSDATE | 系統日 |
| PARAMETER | 呼叫端參數 |
| TRANSACTION_DATE | 交易日期欄 |
| NOT_APPLICABLE | 無生效日 |
| UNRESOLVED | 查不到 |

## effdtSelection

| 值 | 說明 |
|---|---|
| MAX_EFFDT_LE_ASOF | 取 EFFDT ≤ as-of 的最大 EFFDT |
| MAX_EFFDT_LE_ASOF_MAX_EFFSEQ | 同上，同 EFFDT 內取最大 EFFSEQ |
| ALL_ROWS | 取全部歷史列 |
| CUSTOM | 非標準（內容寫在讀取語意） |
| NOT_APPLICABLE | 無生效日 |
| UNRESOLVED | 查不到 |

## readSemanticKind

| 值 | 說明 |
|---|---|
| SOURCE | 來源物件 |
| JOIN | Join 路徑 |
| FILTER | 過濾條件 |
| LOOKUP | 查表／prompt／translate 對映 |
| SETID | SETID 解析 |
| BUSINESS_UNIT | Business Unit 相依查表 |
| LANGUAGE | 語系／翻譯表 |
| DERIVED | 衍生／計算值規則 |
| ROW_SECURITY | 列層級安全 |
| ORDER | 排序規則 |

## referenceQueryState

| 值 | 說明 |
|---|---|
| EXECUTED | 已由 verify 收據（REFERENCE_QUERY 單位）證實可執行——**外環寫，模型不得填** |
| FAILED | verify 收據證實執行失敗——**外環寫，模型不得填** |
| PENDING | 尚未經 verify 收據證實（模型在 fragment 只能寫這個或 NOT_APPLICABLE） |
| NOT_APPLICABLE | 無需查詢 |

## persistenceOperation

| 值 | 說明 |
|---|---|
| INSERT | 新增列 |
| UPDATE | 更新列 |
| DELETE | 刪除列 |
| MERGE | Merge/Upsert |
| EFFDT_INSERT | 新增生效日列（保留歷史） |
| CORRECTION | Correction 模式改寫現行列 |
| COPY_ROW | 複製現行列再改 |
| UNKNOWN | 操作型別查不到 |
| DYNAMIC_RUNTIME | 目標表或操作由執行期決定 |

## accessStrategy

| 值 | 說明 |
|---|---|
| DIRECT_DB_READ | 新系統可直接讀 Oracle |
| PS_MEDIATED_READ | 經 PeopleSoft（CI／API／頁面）讀 |
| PS_MEDIATED_WRITE | 經 PeopleSoft 寫（安全預設） |
| DIRECT_DB_WRITE_APPROVED | 直接寫 Oracle——**只能由 approvals.md 人工核准產生，模型不得填** |
| UNRESOLVED | 未決 |

## verificationState

| 值 | 說明 |
|---|---|
| PASS | 已驗通過 |
| FAIL | 已驗不符 |
| NOT_RUN | 尚未跑（含通道未掛） |
| NOT_APPLICABLE | 此維度不適用 |
| UNRESOLVED | 有跑但判不出 |

## evidenceKind

| 值 | 說明 |
|---|---|
| CHUNK | 程式碼 chunk（36 字元 ChunkId） |
| SQL | 實際執行過的 SELECT＋關鍵列 |
| PENDING_MANUAL | NN 附錄「待人工SQL」 |
| UNRESOLVED | 無證據 |

## confidence

| 值 | 說明 |
|---|---|
| CONFIRMED | 有直接證據 |
| INFERRED | 推論 |
| DYNAMIC_RUNTIME | 執行期決定 |

## verifyCheck

| 值 | 說明 |
|---|---|
| OBJECT_EXISTS | 實體物件存在 |
| OBJECT_TYPE | TABLE／VIEW 型別 |
| COLUMN_TYPE | 欄位存在與型別／長度（FLD 單位；逐欄結果在「## 欄位」表） |
| KEY_METADATA | 鍵／唯一索引 |
| EFFDT_SHAPE | 生效日查詢形狀可執行 |
| REFERENCE_QUERY | 參考查詢可執行 |

## verifyQueryState

| 值 | 說明 |
|---|---|
| EXECUTED | SELECT 已執行且有回傳 |
| FAILED | 執行失敗（ORA- 錯誤） |
| NOT_FOUND | 執行成功但查無物件／列 |
| BLOCKED | 逾時／無回應 |
| ORACLE_MCP_DOWN | 通道未掛 |

## fragmentStatus

| 值 | 說明 |
|---|---|
| PENDING | 待寫 |
| DONE | 收據完整 |
| INVALID | 不變量未過 |
| BLOCKED | 兩次 INVALID（內容有變仍不過）或頁大小已到最小仍超容量，交人工 |

## gateState

| 值 | 說明 |
|---|---|
| PASS | 通過 |
| FAIL | 未通過 |
| NOT_APPLICABLE | 不適用 |
| UNRESOLVED | 分母不可得或含未決 |

## claimDomain

| 值 | 說明 |
|---|---|
| BEHAVIOR | 行為契約 |
| PERSISTENCE | 持久化契約 |

## 自由 token 黑名單

下列字樣出現在任何值域欄位＝fragment INVALID（外環掃描，不分大小寫）：

| 字樣 |
|---|
| probablyDirectWritable |
| maybeCurrentRow |
| specialDataLogic |
| PROBABLY |
| MAYBE |
| 大概 |
| 可能 |
| 應該 |
| 似乎 |
