# Oracle 前置閘門（issue #29）決策備忘——issue 主張逐條對碼

日期：2026-09-08。對象：OpenCode 1.18.29（`anomalyco/opencode` tag v1.18.29 原始碼）。
結論：採 plugin 執行期閘門；issue 的方向對，細節有五處與原始碼／框架既有規則不合，逐條記錄取捨。

## 一、issue 的主張 vs 核對結果

| # | issue 主張 | 核對結果 | 採納 |
|---|---|---|---|
| 1 | 順序只是 prompt 指令，執行是機率性的 | 成立。`task` 從回合一開始就在工具清單裡；情境 31 只驗文字 | 採納（根因） |
| 2 | 用 `tool.execute.before` 擋 `task`，throw 即阻擋 | 成立。`session/tools.ts`：registry 工具（含 task）與 MCP 工具都先 `Plugin.trigger("tool.execute.before")` 再執行；hook 的 promise reject → AI SDK `tool-error` → `processor.failToolCall` 把 `error.message` 寫進 tool part，模型下一步看得到 | 採納 |
| 3 | 狀態機 NEED_LIST→NEED_CONNECT→READY；擋而不改參數 | 成立。成功判定：MCP `isError` 會在 `McpCatalog.convertTool` throw，`tool.execute.after` 不觸發，所以 after 觸發＝成功；另加保守的失敗文字樣式（ORA-／TNS-／not connected…）防「成功回傳但內容是錯誤」 | 採納 |
| 4 | 擋「所有 task」直到 READY | **不採**。ps-peoplecode-flow／ps-sql-flow／ps-sqr-flow 的 tools 表 `oracleMCP_*: false`，不碰 DB；擋全部會讓 DB 掛掉時純 ES／Source 的題也無法委派，與第 0 步「非 DB 部分照常作答」矛盾。改為只擋 tools 表 `oracleMCP_run_sql` 為開的 subagent（最後匹配者優先、沒列＝開、不認識的名字＝開） | 修正 |
| 5 | 互動與 headless 的 hook 行為可能不同，要分開驗 | 原始碼是同一條路（`opencode run` 用 in-process server，`Server.Default().app.fetch`）；沙箱 e2e 已在 headless 驗過 7 情境。互動路徑仍列公司機驗證（`-AnalyzeAll`） | 部分採納 |
| 6 | 先做「印每次 before 的探針」跑 20 次目測 | 改成機械判定：閘門交易紀錄的 task 次數 ＝ `opencode export` transcript 的 task 件數（逐 session）；observe 模式就是探針 | 修正 |
| 7 | hook 覆蓋率不到 100% 就把前置移到模型迴圈外的 wrapper | 不可行：SQLcl MCP 是 OpenCode 以 stdio 起的子行程，「目前連線」活在該行程內；行程外的 wrapper 連不到同一條連線。plugin 已是最外層 | 不採（記錄理由） |
| 8 | AGENTS.md「先查 wiki」與第 0 步衝突 | 成立。AGENTS.md 改寫為「第 0 步之後才先查 wiki」 | 採納 |
| 9 | 靜態守衛保留，補執行紀錄回歸（≥30 次） | 採納：情境 32（靜態）＋ unit（狀態機）＋ e2e（真 binary）＋ 公司機 `test-oracle-gate-runtime.ps1`（B1／B2／B3 各 30 次，判定 executed task before preflight＝0） | 採納 |
| 10 | 不放回 subagent connect | 採納 | 採納 |

## 二、issue 沒提、對碼才發現的事

- **相依安裝會拖住啟動**：`config.ts` 對每個 config 目錄（全域 `~/.config/opencode` ＋ 專案 `.opencode`）各 fork 一個
  `npm install @opencode-ai/plugin@<版本>`；`Plugin.init` 在有 plugin 時 `waitForDependencies()` 等**全部**。斷網沙箱實測：
  無 `.npmrc` 72 秒；只放專案那份仍 72 秒（全域目錄在等）；兩份都 `offline=true` 2 秒。
  → 隨 plugin 一起搬 `.opencode/.npmrc`，並在全域設定目錄手動放一份（SOP-21 步驟 1）。
- **舊式 plugin 載入器要求每個匯出都是函式**（`getLegacyPlugins`）：plugin 檔只能有一個具名匯出（情境 32 守衛）。
- **`opencode run` 用 `process.env.PWD`** 決定專案目錄（run.ts:333）——自動化從別的 cwd 啟動時要設 PWD（e2e 執行器已處理；
  Windows cmd 不設 PWD，走 `process.cwd()`，`ps-auto-loop.ps1` 不受影響）。
- **`chat.message` 帶 agent、每則訊息觸發**：閘門用它做「每則訊息重置」，正好對應第 0 步「不因上一題已連過就省略」。
- **子 session 不會呼叫 task**（`subagent_depth` 預設 1；ps-* subagent 全 `task: false`），但閘門仍會沿 `parentID`
  找 READY 的祖先（防未來開深度時死鎖）。

## 三、閘門的邊界（有意）

- 只擋、不改參數、不代模型 connect（模型仍要自己做第 0 步；閘門把「應該」變「必須」）。
- oracleMCP 未掛載（`/mcp` 非 connected）退讓；狀態查不到（SDK 例外）保守仍擋。
- 每則訊息重置；同回合中途斷線閘門看不到，靠 subagent 回 NOT_CONNECTED 把狀態退回 NEED_CONNECT。
- observe 模式只給探測與緊急停用。

## 四、外部 review（2026-09-08，五點）逐條

| # | review 主張 | 核對 | 落點 |
|---|---|---|---|
| R1 | 連線是全域單例，per-session READY 會失真（別的 session connect／disconnect 後仍 READY；最壞查錯庫） | **成立**。L109 已定案單例；公司機 oracleMCP 若是遠端（VS Code 端 SQLcl），單例還跨 OpenCode 行程 | 連線 epoch：任何 connect／disconnect 嘗試推進 `connection-epoch.json`（跨行程）；READY 需 readyEpoch＝目前 epoch，否則退回 NEED_LIST 並擋。e2e `epoch`＋單元測試 |
| R2 | analyzer 只證 task hook 覆蓋率，沒證 chat.message 每題都 fire；需要 per-turn 不變量與真正的多 turn 測試 | **成立** | turnId＝user 訊息 id；analyzer 加 turnMismatch／turnInvariantViolations（都判定）；e2e `multi-turn`（run --session）＋`multi-turn-serve`（serve 同行程兩題，斷言 READY→NEED_LIST 的重置） |
| R3 | ps-auditor 混合能力，按 agent 能力判定會過度 gate；應拆 agent 或給 task 帶 metadata | **成立但暫不改**：task 工具無 metadata 通道；任務 A 檔級 evidence 混 CHUNK／SQL，拆不開；只在「MCP 有掛載但 connect 失敗」時受影響 | 記為已知限制（SOP-21 第 8 條 b）；拆 agent 另開 issue |
| R4 | mcp.status 15 秒快取不能當正確性放行依據 | **成立** | 拿掉快取，每次即時查；單元測試 |
| R5 | SOP-12 殘留舊協定敘述 | **成立** | 就地改為現況＋標【已作廢】 |

review 沒提、本輪順手修的：`opencode run --session` 續接是**新行程**——plugin 的 in-memory 狀態與數字 turn 計數器都歸零，
所以 turn 識別必須用 user 訊息 id；同時這也表示 headless 的每一次 run 都從 NEED_LIST 起步（與 per-turn 重置同義）。
