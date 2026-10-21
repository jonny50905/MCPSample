# AGENTS.md — OpenCode 專案指引

## 這個 repo 是什麼

- 根目錄 `README.md`：PeopleSoft 知識庫分析框架的入口（做什麼、怎麼跑、
  兩段式畢業、環境紀律、資安邊界）。
- `.opencode/`：框架本體——skills（ps-*）、subagent 定義（agent/）、
  環境設定與協定（peoplesoft/）。架構總覽：`.opencode/peoplesoft/README.md`。
- `scripts/`：確定性外環（lint／auto-loop／auto-all／收據／fs-doctor／知識索引 ps-knowledge／
  補研究 ps-supplemental／Spec 引擎 ps-spec；共用 lib：ps-knowledge-lib／ps-session-lib／ps-supplemental-lib／ps-spec-lib）。
- `claude-code/`：同一框架的 **Claude Code 版**（`CLAUDE.md`＋`.claude/`：agents／commands／skills／hooks／peoplesoft），
  部署到公司機時去掉 `claude-code/` 前綴；`scripts/` 兩版共用（`ps-cli-lib.ps1` 依 `.claude/peoplesoft` 是否存在認版本）。
  說明與對照表見 `claude-code/README.md`。
  Spec 文件流程（00-index＋14 份＋90；`scripts/ps-sdoc*.ps1`、agents ps-status-reader／ps-sdoc-worker／ps-spec-reader／ps-spec-judge）
  兩版都有，`/ps-spec` 都走它（DOC1）：Claude Code 版的契約在 `claude-code/.claude/peoplesoft/sdoc/`；OpenCode 版在
  `.opencode/peoplesoft/sdoc/`，外環加 `-Cli opencode`，人工輸入、執行狀態、產出與 log 各放 `*-opencode` 目錄
  （與 Claude Code 版同一資料夾並存時各自一份工作），外環 session 的模型只在 `.opencode/peoplesoft/sdoc/model.yaml` 設定。
  單一 spec.md 的 CLONE1 仍可直接跑 `scripts/ps-spec-build.ps1`。
- `rebuild-kit/`：拿公司 Spec 在**新專案**重建 JO 的 prompt 套件（.NET＋React＋MariaDB 本機 MVP；
  lead／reviewer 用 Opus、dev 用 Sonnet）。複製到新專案使用，不在本 repo 執行；不假設 Spec 格式。
  說明見 `rebuild-kit/HOW-TO-USE.md`。

## PeopleSoft 問題的處理方式

要以一個或多個確切 Component 產生「供獨立 LLM 重建功能」的 Spec 文件（00-index、14 份文件、90 問題清單），走
`/ps-spec <Component...>`（ps-spec-author），或在 ps-spec-author 對話直接輸入清單。
此路徑不走整個領域研究、不要求手填私有 pack；人工輸入只有 `.ps-private/sdoc-opencode/<jobId>/` 的 status.md（狀態圖，必備）、
project.md、decisions.md、approvals.md。研究規則依 `.opencode/peoplesoft/sdoc/research-contract.md`，結論碼見
`.opencode/peoplesoft/spec/support-codes.md` 的 DOC1；外環 session 的模型只在 `.opencode/peoplesoft/sdoc/model.yaml` 設定。
`docs/ps-spec-opencode/**`、`docs/ps-spec/**` 同為公司機密、禁止外部 remote；REVIEW_READY 不等於企業 E2E 通過。

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
   第 0 步之後，問答一律**先查知識層**——`docs/ps-research/wiki/`（已歸戶的已驗證知識）與
   `docs/ps-research/<領域>/NN-*.md`（已稽核的研究文件），照
   `.opencode/peoplesoft/knowledge-retrieval-contract.md`：以 `docs/ps-research/knowledge/index.md`
   定位（grep 用 `path=目錄`＋`include=檔名`）、只讀對應節、標來源等級、答覆附 `## 來源表`；
   知識沒有或等級不足才現場檢索。
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
4. **維護版線**：`main` 是正式版線（最近一次：2026-10-21 再由 `claude/blissful-edison-7hbeqr` 快轉併入
   盤點紀錄補說明（筆數「未統計」不是 0、「不列」是不寫進研究文件、按鈕依 Destination 分四個代碼合計 1131）與 R6C 各代碼筆數 SQL，
   框架檔未動，各份重生，併入前 `main` 頭 `e363e02`；同日稍早同一分支併入
   盤點紀錄改寫（`docs/design/ui-control-sql-record.md` 改成每支 SQL 盤點什麼、結果代碼表、輸出怎麼解讀；框架檔未動，AGENTS.md 在 OpenCode 搬運包裡，各份重生），
   併入前 `main` 頭 `b9eef9c`；同日稍早同一分支併入
   盤點 SQL 紀錄（`docs/design/ui-control-sql-record.md`）與 Windows 5.1 CI 鎖測試誤判修正（walk 組改用共用 helper、等 60 秒；L154），各份重生，
   併入前 `main` 頭 `997d414`；同日稍早同一分支併入
   元件代碼 10／15／23／24 以 App Designer 確認後進 §2l（10 Scroll Bar、15 External Link 按鈕、24 Tab Separator 解碼，23 Horizontal Rule 不列；L153）、
   第五輪結果與第六輪驗證 SQL（`docs/design/ui-metadata-check-r6.md`），各份重生，併入前 `main` 頭 `7bc739a`；
   2026-10-20 同一分支併入
   畫面元件與設計期屬性進研究範本（cookbook §2l、NN「## 畫面元件」、ps-deep-research／ps-ui-flow `pageControls[]`、補研究與 Spec 引擎 `UI.CONTROLS`；L151）、
   Component 動作與搜尋 Record（cookbook §2m，寫成「## 畫面元件」第一列；元件名稱改成 App Designer 的叫法；L152）、第四輪結果、
   官方對照與第五輪驗證 SQL（`docs/design/ui-metadata-check-r5.md`），各份重生，併入前 `main` 頭 `e78f5f6`；
   2026-10-19 同一分支併入 agent 唯讀帳號的表名改帶擁有者前綴（兩版 cookbook 規則 1a 與 61 處樣板、ps-ui-flow／ps-metadata-flow／ps-ae-flow／ps-auditor、profile 註解、
   ps-doc-lint 導覽證據比對、SOP-30；L150）、第四輪驗證 SQL（`docs/design/ui-metadata-check-r4.md`）與第三輪結果，各份重生，併入前 `main` 頭 `e86d8a6`；
   同日稍早同一分支併入第三輪驗證 SQL（`docs/design/ui-metadata-check-r3.md`：依特徵自動判代碼、以相關顯示算唯讀位元、必填旁證、唯讀帳號 A 測試）與第二輪結果（框架檔未動、搬運包不變），併入前 `main` 頭 `5b60f84`；
   同日稍早同一分支併入第二輪驗證 SQL（`docs/design/ui-metadata-check-r2.md`：欄位 Y/N 探查、找校準頁、核對代碼 10 以上）與第一輪結果完結記錄（框架檔未動、搬運包不變），併入前 `main` 頭 `b9f6762`；
   同日稍早同一分支併入 G1（Group Box 以形狀確認）、V3c（Page 欄位補查）、唯讀帳號檢查改成免 ALTER SESSION＋同義字備案、ORA-02421 說明、結果續記（框架檔未動、搬運包不變），併入前 `main` 頭 `9d5f04c`；
   2026-10-16 同一分支併入 V6 輕量版（只看客製頁面）、agent 唯讀帳號的授權清單與檢查 SQL、第一輪結果續記（框架檔未動、搬運包不變），併入前 `main` 頭 `12012d5`；
   同日稍早同一分支併入第一輪驗證說明加第 0 步（設 CURRENT_SCHEMA）與部分結果（備忘 §7.1、HANDOFF；框架檔未動、搬運包不變），併入前 `main` 頭 `2d91149`；
   2026-10-14 同一分支併入第一輪 metadata 驗證 SQL（`docs/design/ui-metadata-check-r1.md`／`.sql`）與備忘 §7（先 SQL 驗證、改走補查存進知識層；框架檔未動、搬運包不變），併入前 `main` 頭 `20cce49`；
   同日稍早同一分支併入畫面元件、Prompt／Lookup 與欄位間規則的缺口盤點（提案 `docs/design/ui-control-lookup-dependency-memo.md`＋HANDOFF 一行；框架檔未動、搬運包不變），併入前 `main` 頭 `f76ef5e`；
   同日稍早由 `claude/magical-hawking-txsbn2` 快轉併入
   ——跟 deep-research 比：拿掉寫完 Read 回、讀者／判定 effort low、分段 20、時間軸檔、ps-sdoc-diag 一行回報（L149），併入前 `main` 頭 `a4152d8`；
   同日稍早同一分支併入 ps-sdoc-diag 診斷腳本（代號回報）、每次回應綁小（分段 40 行、研究頁外環上限）、外環設 Claude Code 環境預設、session 失敗但產出合格照收（L148），併入前 `main` 頭 `0c79d43`；
   同日稍早同一分支併入 Claude Code 版撞 gateway 504 的根因、模型端數據行、卡住提前結束（L147），併入前 `main` 頭 `da14021`；
   2026-10-13 由 `claude/jolly-tesla-3l8lp5` 快轉併入 session slot 依前端分開、兩版可以同時跑（L146），併入前 `main` 頭 `beadc2b`；
   同日稍早同一分支併入 Spec 文件流程的 OpenCode 版備案（`ps-sdoc.ps1 -Cli opencode`、模型只在 `.opencode/peoplesoft/sdoc/model.yaml`、與 Claude Code 版並行，
   `claude-code/` 未動；L145），併入前 `main` 頭 `df83c1b`；
   同日稍早由 `claude/brave-dirac-4q469u` 快轉併入 Windows 5.1 CI 的端到端測試拆三組平行、部署版面不重跑長測試（L143），併入前 `main` 頭 `3457765`；
   同日稍早同一分支併入 ps-sdoc 的 Component 用空白分開不再誤塞給 -TimeoutMin（L142），併入前 `main` 頭 `48578f1`；
   同日稍早同一分支併入狀態圖解讀分段寫出、Windows 5.1 CI 改成需要時才跑（L141），併入前 `main` 頭 `e906726`；
   同日稍早同一分支併入模型端 504 判讀、session 上限預設 60 分、ps-spec-author 每次一個 session（L140），併入前 `main` 頭 `cf42295`；
   2026-10-12 同一分支併入搬運包分份（L139），併入前 `main` 頭 `a9abd37`；同日稍早同一分支併入 issue #37 Claude Code 版 Spec 文件流程與
   Windows PowerShell 5.1 CI，併入前 `main` 頭 `baae9f9`；再之前由 `claude/peoplesoft-framework-handover-0u6b5g`
   快轉而來；更早接續自 `claude/review-implement-requirement-svqhqt` 的 `67e9b36`）。
   新的維護 session 從 `main` 頭開自己的分支，交接時併回 `main` 並**回來更新本行**；
   前後 `main` 頭的 diff＝該任 session 的全部改動（review 邊界）。

與管理者（使用者）協作的鐵律（只活在這裡，別的檔案沒有）：

- **併回 `main` 已授權**（2026-10-13 管理者）：改動在本機測試（需要時加 5.1 CI）驗證過，就直接快轉併回 `main`，
  不必等管理者說「併回 main」；照樣更新上面的維護版線、重產搬運包，回覆裡說明併回了什麼並附搬運清單。
- 使用者在**公司內網 Windows＋PowerShell 5.1＋OpenCode CLI** 操作，
  目標模型是本機部署（見 applied.md L6）；一切只經 opencode cli，
  沒有任何 web UI。
- 公司網路封鎖 git 下載 → **人工搬運**：你改完檔案只列「改動檔案
  路徑清單」，使用者自己開 GitHub 網頁 Raw 複製整檔貼回本機——
  **禁止在對話中貼整檔內容**（浪費 token，使用者開得了 GitHub）。
- **兩個前端、只搬一版**：公司機只裝 OpenCode 版或 Claude Code 版其中之一，搬運清單只列該版
  （OpenCode＝`scripts/**`＋`.opencode/**`，manifest `scripts/ps-transfer-manifest.json`；Claude Code＝`scripts/**`＋
  `claude-code/` 去前綴的 `CLAUDE.md`／`.claude/**`，manifest `scripts/ps-transfer-manifest.claude.json`，每列 `repo` 欄＝GitHub 位置）。
  改模型讀的規則時兩版對應檔都要改（Claude Code 版只換機制用語）；`scripts/tests/test-claude-variant.ps1` 驗兩版檔案一一對應。
  管理者要兩版並行時（OpenCode 版的 Spec 文件流程當 Claude Code 版的備案），另搬 OpenCode 版搬運包；可以解在同一個資料夾
  （`scripts/**` 兩版共用、`.claude/` 不動；有 `CLAUDE.md` 時 Claude Code 不讀 `AGENTS.md`），也可以另開資料夾。
  同一個資料夾時交接清單兩版搬運包都列（共用 scripts 與兩份 manifest 要同一次交接，ps-fs-doctor 才兩版都一致；SOP-29 第 1 步）。
- **搬運包（優先）**：`ps-fs-doctor -WriteManifest` 會把每版要搬的檔收成幾份文字檔（每份約 500 KB 以內，只在檔與檔之間切）
  `transfer/ps-bundle-opencode-01ofNN.txt`…／`transfer/ps-bundle-claude-01ofNN.txt`…，公司機把各份放進同一個資料夾，以
  `scripts\ps-bundle.ps1 -Bundle <資料夾>` 解開（逐份驗證、整包驗證、三方比對保留本機改過的檔、衝突另存 `.incoming`）。
  交接時清單只列「該版搬運包的各份」（第一次另列 `scripts/ps-bundle.ps1`），逐份與整包驗證取代逐檔核對；不用搬運包時才給下面的逐檔清單。
- 搬運清單必附**核對欄**（2026-08 管理者要求）：每檔一列——路徑／
  新增或修改／行數（供編輯器總行數核對，允許 ±1 行尾差異）；
  `.ps1` 標註「存 UTF-8 with BOM」。搬完整波跑一次
  `ps-fs-doctor -Domain <領域>`（檢查 D 抓雙 BOM/FEFF 污染）。
- 使用者受公司規範限制**無法提供真實檔名與機敏值**——以編號、
  類別、遮罩值溝通，不要追問原文。
- 研究產出（docs/ps-research/**）、Spec 私有需求包（.ps-private/**）與 Spec 執行狀態
  （.ps-runtime/**）是公司機密：研究產出只進**內部** git，後兩者連內部 git 都不進（已 gitignore，
  知識索引 docs/ps-research/knowledge/ 同為本機快取），嚴禁外部 remote 或公開貼出；
  對維護端只回報結論碼（KNOW1／SUPP1／SPEC1／CLONE1／DOC1，見 `.opencode/peoplesoft/spec/support-codes.md`）與 enum 值，
  不回報路徑、物件名、hash、requestId。
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
