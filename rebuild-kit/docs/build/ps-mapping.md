# PeopleSoft → .NET／React／MariaDB 對照與陷阱

**Spec 明文永遠優先。** 本檔只在 Spec 沒指定技術做法時提供預設；本檔的預設涉及業務行為時
（例如交易邊界、錯誤是否阻擋），一律同時登記 `A-###`，不能當成 Spec 的事實。

## 1. 概念對照

| PeopleSoft | 本專案 |
|---|---|
| Component | 一個功能模組：後端 `Features/<Component>/`、前端一組路由 |
| Search Record／Search keys | 搜尋頁＋`GET /api/<component>/search`；條件、比對方式（開頭相符、大小寫）照 Spec |
| 操作模式 Add／Update-Display／Update-Display All／Correction | 開啟 API 的 `mode` 參數，後端依權限檢查可用模式；各模式可見資料列與可改欄位照 Spec |
| Page／Subpage／Secondary Page | 頁面中的區塊／分頁／對話框，版面順序照 Spec |
| Scroll／Grid level 0～3 | 元件資料中的巢狀陣列；前端用可編輯表格 |
| Record（SQL Table） | MariaDB 資料表 |
| Derived／Work Record | 只存在元件資料中，不建表 |
| SQL View | 查詢或 MariaDB view，定義照 Spec |
| Field | 欄位，名稱原樣 |
| Translate 值（XLAT） | 代碼值表（欄位名、值、有效日、狀態、長短名稱）＋種子；只放 Spec 用到的欄位與值 |
| Prompt Table | lookup API，篩選條件照 Spec |
| Message Catalog（set／number） | 訊息目錄表：set、number、嚴重度、原文（含 `%1` 這類替換符）；顯示時代入參數 |
| `Error` | 阻擋：該次事件或存檔失敗，回傳訊息 |
| `Warning` | 不阻擋但需使用者確認：回傳警告，前端確認後帶 `confirmWarnings=true` 重送 |
| SQLExec／Rowset／CreateRecord | handler 內的 EF Core 或參數化 SQL，與存檔同一交易 |
| Auto numbering／序號表 | 計數表＋`SELECT … FOR UPDATE` 於存檔交易內取號；格式（前導零、長度）照 Spec |
| Application Engine／SQR／Process Scheduler | 後端服務類別；本機用開發用 API（`POST /api/dev/run/<程序>`）或 CLI 參數觸發；Run Control 變成參數 DTO |
| 檔案介面 | 讀寫本機資料夾（可設定）；欄位順序、長度、編碼、空值格式照 Spec |
| Workflow／Approval／通知 | 只做 Spec 寫到的最小契約；通知寫入 outbox 表，不真的寄出 |
| Permission List／Role／Row-level security | 開發用使用者、角色、權限清單種子＋後端檢查服務 |
| Effective date（EFFDT／EFFSEQ／EFF_STATUS） | 共用 helper：某日有效列＝該日（含）以前最大 EFFDT，同日取最大 EFFSEQ；是否排除 inactive 照 Spec |

## 2. 事件管線

後端每個 Component 一個 handler，依 Spec 實作下列掛點（Spec 沒有的掛點不用實作）。

| PeopleSoft 事件 | 掛點 | 何時呼叫 |
|---|---|---|
| SearchInit／SearchSave | `OnSearchInit`／`OnSearchValidate` | 搜尋頁載入／送出搜尋 |
| FieldDefault | `OnFieldDefault` | 新增主檔或新增列時，對空值欄位 |
| RowInit | `OnRowInit` | 每一列載入或建立後 |
| PostBuild／Activate | `OnPostBuild`／`OnActivate` | 整份資料建好後、頁面顯示前 |
| FieldEdit | `OnFieldEdit` | 欄位變更時先檢核；Error 就退回原值並回訊息 |
| FieldChange | `OnFieldChange` | 檢核通過後，重算相依欄位與欄位狀態 |
| RowInsert／RowDelete | `OnRowInsert`／`OnRowDelete` | 新增列／刪除列 |
| SaveEdit | `OnSaveEdit` | 存檔前檢核；Error 阻擋存檔 |
| SavePreChange | `OnSavePreChange` | 寫入前調整資料 |
| （寫入） | 管線本身 | 依 Spec 的寫入順序 |
| SavePostChange／Workflow | `OnSavePostChange` | 寫入後處理 |

API 形狀（預設）：

- `GET /api/<component>/new`：新增模式的初始資料＋欄位狀態。
- `GET /api/<component>/open?<keys>&mode=`：開啟既有資料。
- `POST /api/<component>/event`：`{ buffer, event: FieldChange|RowInsert|RowDelete…, path }` → 新 buffer＋欄位狀態＋訊息。
- `POST /api/<component>/save`：`{ buffer, mode, confirmWarnings }` → 成功後的新 buffer，或錯誤／警告。

回應統一包含：`buffer`（資料）、`fieldStates`（每個欄位路徑的 visible／editable／required／options）、
`messages`（set、number、嚴重度、已代入的文字、欄位路徑）。

未由 Spec 決定、需登記 `A-###` 的預設：

- 存檔＝ SaveEdit → SavePreChange → 寫入 → SavePostChange 全在同一個 DB 交易內，任何一步 Error 就整筆 rollback。
- 同一事件中多個 Error：回第一個就停止。
- 併發：開啟時帶版本（例如最後更新時間或版本欄），存檔時比對不符就拒絕並回訊息。

## 3. 型別對照

Spec 寫的型別、長度、精度是權威；下表只是換算方式。

| PeopleSoft | MariaDB | C# | TypeScript |
|---|---|---|---|
| Character(n) | `VARCHAR(n)` | `string` | `string` |
| Long Character | `TEXT`／`LONGTEXT` | `string` | `string` |
| Number／Signed Number（整數位 i、小數位 d） | d＝0 且位數小：`INT`／`BIGINT`；否則 `DECIMAL(i+d, d)` | `int`／`long`／`decimal` | `number`（金額以字串傳輸避免精度誤差，ADR 決定） |
| Date | `DATE` | `DateOnly` | `string`（`YYYY-MM-DD`） |
| DateTime | `DATETIME(6)` | `DateTime` | `string`（ISO） |
| Time | `TIME(6)` | `TimeOnly` | `string` |
| Image／Attachment | 只有核心用到才做：附件表（`LONGBLOB`）或本機檔案路徑 | | |

金額、比例一律 `decimal`，不用 `double`。

## 4. 陷阱清單

- **空字串與 NULL**：Oracle 把 `''` 當 NULL；PeopleSoft 字元欄的「空白」通常存成單一空白 `' '`。
  MariaDB 的 `''` 與 NULL 不同。依 Spec 的空值描述；沒寫就用 ADR 的預設（字元欄 `NOT NULL DEFAULT ' '`、
  API 輸出去掉尾端空白、輸入空字串存 `' '`、判斷空白用 `IsBlank`＝NULL 或只有空白），並登記 `A-###`。
- **尾端空白比較**：MariaDB 一般 collation 是 PAD SPACE，`'A' = 'A '` 為真；唯一鍵與比對要考慮。
- **大小寫**：Oracle 比較區分大小寫；MariaDB 預設 `_ci` collation 不區分。代碼、鍵、stored value 欄位用
  `utf8mb4_bin`（ADR 決定全庫預設）；Spec 明寫不分大小寫的搜尋才另外處理。
- **看起來像數字的字元鍵**：保留前導零與固定長度，不轉成數字。
- **日期**：PeopleSoft 的「今天」由伺服器決定；程式一律用可注入的 `IClock` 取日期時間，測試才能驗邊界日。
  不做時區轉換（本機時間），登記於 ADR。
- **有效日期**：未來日期列、歷史列、Correction 模式可改歷史列、同日多筆靠 EFFSEQ；具體規則照 Spec。
- **預設值來源不只一個**：Record 欄位預設、FieldDefault、程式指派的先後照 Spec；Spec 沒寫先後就登記 `A-###`。
- **Translate 值失效**：既有資料上的失效代碼是否仍顯示、是否可再選，照 Spec；沒寫就登記。
- **SetID／Business Unit 對應的 Prompt**：只實作 Spec 用到的那一種解析方式，不做整套 TableSet。
- **訊息原文**：保留原文與替換符，不改寫、不翻譯；測試用 set／number 斷言。
- **畫面欄位條件**：「隱藏」與「唯讀」是不同狀態，必填也可能只在特定模式或狀態成立；逐欄照 Spec。

## 5. 前端做法

- 共用欄位元件（例如 `PsField`）：吃後端的欄位狀態決定顯示、唯讀、必填與選項；欄位 label 用 Spec 原文。
- 欄位離開（blur）或選項改變時送 `event`，用回應整份取代畫面資料與狀態（對應 PeopleSoft 的伺服器往返）。
- 子層資料用可編輯表格；新增列／刪除列走 `event`。
- 訊息區顯示 Error；Warning 用確認對話框，確認後帶 `confirmWarnings=true` 重送。
- 畫面頂端有開發用使用者下拉選單，選擇結果放 `X-Dev-User` header；後端據此套權限。
- 前端不寫業務條件判斷。

## 6. 測試做法

- 驗收測試結構：Arrange＝Spec 的前置條件（用合成資料建）；Act＝依步驟呼叫 `open`／`event`／`save`；
  Assert＝預期結果或訊息（set／number）、預期欄位值與欄位狀態（可見、唯讀、必填）、預期資料庫資料。
- 只驗 HTTP 200 不算驗收；每個預期都要有明確斷言。
- 正例、反例、邊界各自獨立測試；日期邊界用 `IClock` 固定日期。
- 測試庫：連線只讀 `ConnectionStrings__Test`，fixture 套用 migrations 與種子；每個測試類別開始前清空交易類表並重灌種子。
  清表前先確認連線的資料庫名稱與 `ConnectionStrings__Main` 不同，相同就讓測試直接失敗，絕不清主庫。
- 規則與狀態轉移另寫不需 DB 的單元測試。
- `SpecCoverageTests`：讀 `docs/build/spec-index.md` 與 `traceability.md`，核對每個需求鍵都在追蹤表；
  類別 ACCEPTANCE 且狀態 DONE 的鍵，測試組件中一定有相同 `Trait("Spec", 鍵)` 的測試。
  找不到 `spec-input/` 或索引檔時明確失敗並說明原因，不 Skip。
