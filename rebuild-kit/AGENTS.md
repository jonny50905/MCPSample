# AGENTS.md — JO 核心功能重建（.NET＋React＋MariaDB）

本檔是本專案所有 agent 的常駐規則。流程在 `docs/build/KICKOFF.md`，PeopleSoft 對照與陷阱在
`docs/build/ps-mapping.md`，目前進度在 `docs/build/status.md`，管理者操作在 `HOW-TO-USE.md`。

## 這個專案是什麼

- 依公司交付的 Spec，從零重建 PeopleSoft JO（職缺）核心功能，做出**能在本機執行的 MVP**：
  業務功能完整，非業務需求只做到「能跑、不擋業務驗證」。
- **唯一業務真相是 `spec-input/`**（唯讀）。`spec-previous/` 是上一版 Spec，只在 Spec 更新時比對差異用，
  不是需求來源。Spec 的格式、章節與 checklist 由公司 template 決定，本專案不預設格式：
  第 1 階段由 lead 讀懂結構並寫成 `docs/build/spec-map.md`，之後所有人照它定位。
- PeopleSoft 本體、Oracle、PeopleCode 檢索工具都不是本專案的來源。Spec 沒寫的業務行為不得自行補上，
  也不得用「PeopleSoft 一般做法」推定；缺的東西登記成假設（見「Spec 使用規則」）。

## 角色

| agent | 模型 | 職責 |
|---|---|---|
| `rebuild-lead`（primary） | Opus | 讀 Spec、建需求索引與架構、切 slice、派工、驗收、維護 `docs/build/` |
| `rebuild-dev`（subagent） | Sonnet | 依單張工單實作一個 slice（DB→規則→API→畫面→測試）並回報 |
| `rebuild-reviewer`（subagent） | Opus | 獨立覆核一個 slice 是否忠於 Spec；不改程式 |

只有 lead 會 commit、寫 `docs/build/`、與使用者對話。dev 與 reviewer 只回報給 lead。

## 範圍

要做：

- Spec 定義為核心（及其必要依賴）的全部業務行為：流程、畫面與逐欄條件、資料、規則、狀態、交易、
  介面／批次、權限、驗收情境（以 Spec 實際有寫的為準）。Spec 沒有區分核心與依賴時，範圍內全部視為核心。
- 必要依賴（部門、職務代碼、人員等其他系統的資料或服務）只做**最小替代**：資料表＋合成種子資料＋
  Spec 寫到的輸入／輸出／錯誤。不做它的維護畫面，除非核心流程需要有人在畫面上操作它。
- 權限規則用「開發用身分切換」驗證（畫面頂端選使用者），不是正式登入。

本次不做（非業務需求，不要花時間完善）：

- 正式登入／SSO／密碼、HTTPS 憑證、CSRF、速率限制等安全強化
- 部署、容器、CI/CD、監控、集中 log、效能調校、快取、高可用
- 多語系（畫面文字照 Spec 的原始 label）、RWD／行動版、無障礙細修、視覺美化
- 從 PeopleSoft 搬資料、真實排程器、真實寄信（通知寫入本機 outbox 表即可）
- Spec 標為排除的物件，以及 Spec 沒提到的功能

## 技術棧（預設；偏離要寫 ADR 並由 lead 決定）

- 後端：ASP.NET Core Web API（C#），目標框架用本機已安裝的 LTS SDK（有 .NET 10 用 10，否則 .NET 8）。
- 資料庫：MariaDB 10.11 以上。存取用 EF Core＋`Pomelo.EntityFrameworkCore.MySql`：先查公司套件來源實際有的
  Pomelo 主版號，EF Core 用同一個主版號（目標框架另外決定，不必跟著換）。`ServerVersion` 明確寫成
  `MariaDbServerVersion`，不用 AutoDetect。
- Schema：`db/migrations/V0001__<說明>.sql` 版本化 SQL，由 API 啟動時的 migration runner 依序套用並記錄
  於 `__schema_history`；種子資料在 `db/seed/`，須可重複執行。collation 在 migration 中逐表／逐欄明寫。
  不用 EF migrations、不需 dotnet-ef 工具。
- 前端：React＋TypeScript＋Vite、React Router；UI 元件庫預設 Ant Design（zh_TW 語系）。前端骨架手寫
  `package.json` 與設定檔後 `npm.cmd --prefix web install`，不用互動式 scaffold（`npm create`、`npx`）。
  `web` 的 `build` script 先跑 `tsc --noEmit` 再 `vite build`，型別錯誤會讓建置失敗。
  開發時經 Vite proxy 呼叫 `/api`；本機執行時由 API 直接提供 `web/dist`。
- 測試：xUnit＋`WebApplicationFactory`＋本機 MariaDB 測試庫；前端以 `npm.cmd --prefix web run build` 驗證。
- 本機啟動：`scripts\run-local.cmd`（見下方 Windows 紀律）。
- 不以 Docker 為前提。新增任何 NuGet／npm 套件前先經 lead 同意並記在 ADR。

## 架構鐵律

1. **業務規則只在後端（C#）**。前端不重寫規則，只做型別、長度這類輸入格式提示。
2. **欄位狀態由後端計算**：可見／可編輯／必填／選項／預設值依 Spec 算好，與資料一起回傳；前端照著渲染。
   這樣規則只有一份，畫面條件也能用 API 測試驗證。
3. **PeopleCode 事件對應成後端的元件事件管線**：載入、欄位預設、欄位檢核、欄位變更、插入列／刪除列、
   存檔（存檔前檢核 → 寫入前調整 → 寫入 → 寫入後處理）。實際事件與順序以 Spec 為準；對照見
   `ps-mapping.md`。
4. **API 無狀態**：前端持有整份元件資料（主檔＋各層子列），每次事件送整份，後端回新資料＋欄位狀態＋訊息。
5. **一次存檔＝一個 DB 交易**，除非 Spec 明文寫了不同的交易邊界。
6. **保留原始識別字**：Spec 有給 Record／Field 名稱時，資料表名對應 Record 名、欄位名照 Field 名原樣；
   stored value、訊息編號與訊息原文一字不改。資料表是否加 `PS_` 前綴由 ADR 決定，全專案一致。
7. **不做通用 PeopleSoft 執行引擎**：事件管線是薄的慣例（介面＋每個 Component 各自的 handler 類別），
   畫面是逐頁手寫的 React，共用少量欄位元件。不要做 metadata 驅動的直譯器。

## Spec 使用規則

- 需求鍵（requirement key）的形式與定位方法寫在 `docs/build/spec-map.md`；全部需求鍵列在
  `docs/build/spec-index.md`。程式、測試、追蹤表一律用這個鍵，不自創第二套編號。
- 需求鍵只用 ASCII `[A-Za-z0-9._-]`，一經發布就不改；Spec 更新時舊鍵保留，對應關係記在 spec-map。
- 不一次讀整份 Spec；先查 spec-index 找到位置，只讀需要的段落。
- Spec 忠實度優先於「現代最佳實務」：條件式、stored value、訊息原文、事件先後、狀態轉移都照 Spec。
  技術實作（類別切分、API 形狀、元件寫法）可以自由選擇。
- Spec 缺漏、矛盾、標示未完成／待確認／UNKNOWN，或看不懂的地方：不要猜，也不要憑常識補。
  登記到 `docs/build/assumptions.md`（`A-###`：缺什麼、暫定做法、影響的需求鍵、該問誰），
  暫定做法選最保守的（不擴充行為），程式碼標 `// ASSUMPTION A-###`。
- 標為排除的物件不實作；Spec 沒提的欄位、規則、訊息不加。
- `spec-input/` 與 `spec-previous/` 唯讀，任何 agent 都不得修改。

## 追蹤

- 規則、狀態轉移、交易、權限的實作處加 `// SPEC: <需求鍵>`。
- 每個 ACCEPTANCE 需求鍵至少一個自動化測試，加 `[Trait("Spec", "<需求鍵>")]`，測試方法名包含需求鍵
  （把 `.`、`-` 換成 `_`）。Spec 沒有驗收情境時，lead 由流程、規則、狀態需求鍵衍生 ACCEPTANCE 鍵並標「衍生」。
- `docs/build/traceability.md`：每個需求鍵一列，狀態只用
  `TODO／DONE／PARTIAL／ASSUMPTION／GAP／EXCLUDED`。
- `SpecCoverageTests` 只讀 `docs/build/` 的索引與追蹤表（不讀 `spec-input/`），機械核對：spec-index 的每個鍵
  都在追蹤表；狀態 DONE 或 ASSUMPTION 的 ACCEPTANCE 鍵都找得到相同 Trait 的測試。

## 測試失敗的唯一暫存方式

- 不 Skip、不刪測試、不改期望值去遷就程式。
- slice 經兩輪修正仍有測試失敗而記為 PARTIAL 時，只有 lead 可以在那些測試加
  `[Trait("Known", "Failing")]` 與註解 `// KNOWN-FAILING S##: <原因與 A-### 或待解事項>`，並列入 status.md。
- 關卡指令用 `dotnet test --filter "Known!=Failing"`；每次也跑一次完整 `dotnet test`，照實回報已知失敗數。
  問題修好就移除標記。

## Windows／PowerShell 5.1／OpenCode 紀律

- 使用者環境：公司內網 Windows＋PowerShell 5.1＋OpenCode CLI。
- shell 指令一次一個，不用 `&&`、`||` 串接（5.1 不支援），也不靠 `cd` 切目錄：.NET 指令在根目錄跑
  （根目錄有方案檔），前端用 `npm.cmd --prefix web …`；含空白的路徑加引號。
- **不要在 shell 工具前景啟動長駐程式**（`dotnet run`、`dotnet watch`、`npm run dev`、`vite`、`run-local`）：
  會卡到逾時。驗證用 build 與 test；需要看畫面時請使用者自己啟動。
- 公司執行原則會擋 `.ps1` 子行程，所以使用者要執行的腳本寫成 `.cmd`：只用 ASCII、逐行直敘
  （不用 label、goto、括號區塊），直接呼叫 `dotnet` 與 `npm.cmd`。不寫任何調整執行原則的參數。
- 不下載執行檔、不改系統設定、不裝全域工具、不改套件來源設定。套件只從機器上已設定的來源還原；
  還原失敗就停下回報，不自行換來源。
- 不用 webfetch／websearch；不把 Spec 或程式內容送到任何外部服務。

## 機密

- `spec-input/`、`spec-previous/`、`docs/build/`、程式碼都含公司業務內容：不加外部 remote、不 `git push`。
  是否進公司內部 git 由使用者依公司規範決定；兩個 Spec 資料夾在 `.gitignore`。
- 本專案 `opencode.json` 已關閉 session 分享；不要改。
- 測試與種子資料一律合成，並在檔案或資料中標明「合成」；不向使用者要真實資料。
- 使用者受公司規範限制無法提供真實名稱與機敏值：以編號、類別、遮罩值溝通，不追問原文。
- DB 密碼只放環境變數，不寫進檔案、不出現在對話；檢查環境變數時只看「有沒有設」，不印出值。

## 溝通

- 用繁體中文回覆；技術名稱、stored value、訊息原文保留原樣。
- 查無就照實說。不宣稱「與 PeopleSoft 等價」或「已通過企業驗收」——本專案的測試只證明符合 Spec 的寫法。
- 測試數字照實際輸出回報。
- 對話不是記憶體：lead 在每個步驟完成時更新 `docs/build/status.md`，新 session 從那裡接續。
