# AGENTS.md — OpenCode 專案指引

## 這個 repo 是什麼

- 根目錄 `README.md`：PeopleSoft 知識庫分析框架的入口（做什麼、怎麼跑、
  兩段式畢業、環境紀律、資安邊界）。
- `.opencode/`：框架本體——skills（ps-*）、subagent 定義（agent/）、
  環境設定與協定（peoplesoft/）。架構總覽：`.opencode/peoplesoft/README.md`。
- `scripts/`：確定性外環（lint／auto-loop／auto-all／收據／fs-doctor）。
- `src/`：與本框架無關的舊有 .NET 範例，不維護、不在文件範圍。

## PeopleSoft 問題的處理方式

收到 PeopleSoft 業務問題（例：兵役資料在哪維護、某選項選了會執行什麼）時：

1. 問答走 `ps-orchestrator` agent（Tab 切換）；要**產完整業務文件**用
   `/ps-research <領域>`（ps-deep-research，輸出 docs/ps-research/）。
   在一般 agent 下則載入 `ps-business-discovery` skill 依其流程處理，
   重的檢索用 task 委派給 ps-* **agent**（`.opencode/agent/*.md` 裡的名字）。
   `.opencode/skills/*` 是 skill、不是可委派的 agent：授權／血緣／排程類（ps-security-flow／
   ps-data-lineage／ps-process-flow）一律派 `ps-metadata-flow`，要用的 skill 寫進 task 文字。
   主 agent 工作流的**開線步驟（第 0 步）**（查 wiki、委派、作答之前）固定
   `oracleMCP_connect`（connection_name＝profile `oracle.connectionName` 原樣，不先 list、
   不從清單挑名字；無條件，見 agent 定義），等 connect 回覆成功才派會查 DB 的 subagent。
   執行期只有 `.opencode/plugin/ps-runtime-guard.js` 的兩個無狀態檢查：connect 的 connection_name
   必須等於 profile 值（否則 `ORACLE_CONNECTION_NOT_CONFIGURED`／`ORACLE_CONNECTION_MISMATCH`，
   工具不執行）、task 的 subagent_type 不得是 skill 名（`PS_TASK_TARGET_INVALID`）。**沒有派工前置
   閘門**——順序是你的責任：先派 subagent 而 DB 未連 → 它回 `NOT_CONNECTED`，你再 connect 一次、
   重派一次，只一次、不迴圈。工具清單裡沒有 oracleMCP_ 工具＝掛載故障 → 不猜工具名、不重派、
   不多 connect，回報 ORACLE_MCP_DOWN，交管理者依 SOP-21 重掛；重掛後重新 connect，不沿用舊結論。
   第 0 步之後，問答一律**先查 `docs/ps-research/wiki/`**（已歸戶的已驗證知識），
   wiki 沒有或未驗證才現場檢索。
2. 搜尋任何 PeopleSoft 物件前，先讀
   `.opencode/peoplesoft/customization-profile.yaml` 與 `business-domain-map.yaml`；
   `TW_` 是強客製訊號但非唯一判斷。**未命中已定義領域時，改用
   `searchPolicy.defaultMode` 繼續搜尋——不得以「領域不存在」拒答。**
3. 長文本鐵律（任何 agent 都適用）：
   - `PeoplecodeElasticSearch` 搜到的 chunk ids / snippet 只是候選（SEARCH_CANDIDATE）；
     必須用 `PeoplecodeSource` 以 chunk id 取回完整段落才能作為證據。
   - 不可一次載入整支 PeopleCode / SQL / SQR / SQC。
4. Subagent 回報一律依 `.opencode/peoplesoft/subagent-report-contract.md`
   （單一 JSON、單段引用 ≤ 5 行、必附 evidence IDs）。

## 一般規則

- 用繁體中文回覆。
- 查無證據就照實說，不要編造 PeopleSoft 物件名稱或執行期結果。
- 被使用者指正答錯時，主動提議用 `/ps-lesson <描述>` 登錄教訓
- 業務知識被指正（如資深同事更正業務邏輯）→ 建議
  `/ps-correct <正確知識>` 更新 wiki（本機立即生效；團隊走內部 git PR）
  （本機立即生效；團隊生效走內部 git PR 審核）。

## 框架維護協作須知（給接手的 AI 維護 session）

對話不是記憶體——歷任維護 session 的全部決策與因果都在檔案裡。接手前先讀：

1. `.opencode/peoplesoft/lessons/applied.md`——L 編號帳本，每課含
   症狀／根因／落點，是本框架**唯一完整的歷史**；編號以 repo 為準。
2. `.opencode/peoplesoft/SOP.md`——現行操作程序（含環境異動對齊檢查）。
3. git log——每筆 commit 訊息都寫了為什麼。
4. **維護版線**：最新在 `claude/peoplesoft-framework-handover-0u6b5g`
   （自 `claude/review-implement-requirement-svqhqt` 的 `67e9b36` 接續；
   main 上沒有框架）。版線以維護 session 為節點串接——新的維護
   session 從最新版線頭開自己的分支，交接時**回來更新本行**；
   前後版線的 diff＝該任 session 的全部改動（review 邊界）。

與管理者（使用者）協作的鐵律（只活在這裡，別的檔案沒有）：

- 使用者在**公司內網 Windows＋PowerShell 5.1＋OpenCode CLI** 操作，
  目標模型是本機部署（見 applied.md L6）；一切只經 opencode cli，
  沒有任何 web UI。
- 公司網路封鎖 git 下載 → **人工搬運**：你改完檔案只列「改動檔案
  路徑清單」，使用者自己開 GitHub 網頁 Raw 複製整檔貼回本機——
  **禁止在對話中貼整檔內容**（浪費 token，使用者開得了 GitHub）。
- 搬運清單必附**核對欄**（2026-08 管理者要求）：每檔一列——路徑／
  新增或修改／行數（供編輯器總行數核對，允許 ±1 行尾差異）；
  `.ps1` 標註「存 UTF-8 with BOM」。搬完整波跑一次
  `ps-fs-doctor -Domain <領域>`（檢查 D 抓雙 BOM/FEFF 污染）。
- 使用者受公司規範限制**無法提供真實檔名與機敏值**——以編號、
  類別、遮罩值溝通，不要追問原文。
- 研究產出（docs/ps-research/**）是公司機密：只進**內部** git，
  嚴禁外部 remote 或公開貼出。
- `scripts/*.ps1` 一律 **UTF-8 with BOM**（PS 5.1 無 BOM 會把中文
  誤解析成語法錯誤）；repo 禁放執行檔與「繞過」類字串（SOP-2／3）。
- `.opencode/plugin/*.js` 是 OpenCode 執行期的無狀態 guard 與診斷（connect 目標比對、task 目標
  是不是 agent、oracleMCP 掛載診斷；**不是派工閘門**，不保存 READY／todo 狀態）：
  **零外部 import**（只准 `node:` 內建；公司網路封鎖 npm）、只擋不改參數；
  `.opencode/.npmrc` 的 `offline=true` 不可拿掉（否則有 plugin 時啟動會等
  相依安裝逾時）。改 plugin 必跑 `node --test tests/runtime-guard/unit.test.mjs`
  與 `tests/runtime-guard/run-e2e.mjs`（真 OpenCode＋假 oracleMCP＋假模型）。
- 規則修改走**最小新增**（只加不刪）、當天記 applied.md、
  團隊生效靠內部 git PR——實驗先行、規則後補，規則一律從
  觀察到的行為推導，不從規格書想像。
- **模型讀的檔（`.opencode/agent`、`skills`、`command`、`peoplesoft/*.md`、
  `report-templates`）只留規則本身、做法、值域在哪**：出處（issue 編號、日期）、
  審查／舊版／已廢止之類的變更敘述、外環或 lint 的實作機制，一律寫進
  `lessons/applied.md`／`SOP.md`／`HANDOFF.md`／commit 訊息，不寫進模型檔。
  「只加不刪」指規則語意，錯句直接改對、不另加「釐清」段。
  `scripts/ps-agent-doc-lint.ps1` 會擋（`ps-fs-doctor -WriteManifest` 先跑它）。
