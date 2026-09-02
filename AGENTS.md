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
   重的檢索用 @ 委派給 ps-* subagent。
   問答一律**先查 `docs/ps-research/wiki/`**（已歸戶的已驗證知識），
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
   main 上沒有框架）。功能分支 `claude/issue-17-legacy-contract-phase1`
   （自 handover 的 `3d523dc` 開，issue #17 Phase 1）**必須併回 handover 分支**。版線以維護 session 為節點串接——新的維護
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
- 規則修改走**最小新增**（只加不刪）、當天記 applied.md、
  團隊生效靠內部 git PR——實驗先行、規則後補，規則一律從
  觀察到的行為推導，不從規格書想像。
