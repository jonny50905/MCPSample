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
| 7 | hook 覆蓋率不到 100% 就把前置移到模型迴圈外的 wrapper | 前提待驗：oracleMCP 若是 OpenCode 以 stdio 起的子行程，「目前連線」活在該行程內、行程外連不到；若是遠端（VS Code 端 SQLcl，SOP-12 的說法），wrapper 連得到但擋不住模型的順序。兩種情況 plugin 都是模型迴圈內唯一的確定性層。topology 由 SOP-21 步驟 9 的實驗定案 | 不採（記錄理由；topology 待驗） |
| 8 | AGENTS.md「先查 wiki」與第 0 步衝突 | 成立。AGENTS.md 改寫為「第 0 步之後才先查 wiki」 | 採納 |
| 9 | 靜態守衛保留，補執行紀錄回歸（≥30 次） | 採納：情境 32（靜態）＋ unit（狀態機）＋ e2e（真 binary）＋ 公司機 `test-oracle-gate-runtime.ps1`（B1／B2／B3 各 30 次，判定 executed task before preflight＝0） | 採納 |
| 10 | 不放回 subagent connect | 採納 | 採納 |

## 二、issue 沒提、對碼才發現的事

- **相依安裝會拖住啟動**：`config.ts` 對每個 config 目錄 fork 一個 `npm install @opencode-ai/plugin@<版本>`；
  `Plugin.init` 在有 plugin 時 `waitForDependencies()`。斷網沙箱實測：無 `.npmrc` 72 秒、`offline=true` 2 秒。
  → 隨 plugin 一起搬 `.opencode/.npmrc`（`offline=true`）。
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

## 四、外部 review 四輪與退版重寫（2026-09-08）

review 對 a31c946 的判定：核心 invariant 乾淨（DB-capable task 只在 list 成功 → connect 成功 → READY 之後執行），但有兩個 Must
（per-session READY 看不到共用單例被別人改動；analyzer 沒證明每題都有 chat.message 重置）與三個 Medium／Low。之後三筆修法
（a94a616／dd54ab3／6d56a5f／886d6e2）被判定偏離：

| # | 偏離 | 為什麼不能留 |
|---|---|---|
| D1 | `connection-epoch.json`／`connection-state.json` 跨行程影子狀態 | 真實狀態在 SQLcl MCP 的 current connection；檔案變成第二個真相來源，且 topology（local／remote、行程內／跨行程共用）未證實就先做跨行程協調，還得用 token／交錯補償 |
| D2 | list／connect 失敗 ≥ 2 次 → 退讓放行；`prt_` subtask 無條件退讓 | fail-open：「前置未成功但 DB-capable task 照樣執行」重新成為合法路徑，正是 #29 要消滅的行為 |
| D3 | analyzer 把退讓／祖先放行的 callID 標成豁免 | executedTaskBeforePreflight=0 不再等價於「沒有 DB task 在前置前執行」，acceptance criterion 被實作反向改寫 |

處置：`aa9e42c` 把樹狀態退回 a31c946（歷史保留），再以最小不變量重寫，只移植已證明安全的改善：

| 項目 | 移植？ | 說明 |
|---|---|---|
| turnId＝user 訊息 id；synthetic／同 id 訊息不重置 | 是 | `opencode run --session` 續接是新行程，數字 turn 會歸零；OpenCode 自己也不把全 synthetic 的訊息當真實訊息 |
| task 入場快照（`admitted`） | 是 | 使用者在 task 執行中送下一題時，該 task 的 after 列不被錯標到新題 |
| mcp.status 不快取；回錯誤物件保守擋 | 是 | 退讓是正確性判斷，不能用舊資料；查不到就擋 |
| 多輪 e2e（run --session／serve 同行程／compaction） | 是 | 證明 READY 的 session 真的被下一題重置 |
| analyzer：turnMismatch（id 比對）／turnInvariantViolations（同題內依序 list→connect→task）／orphanTurns／export 落檔 UTF-8／exit code／timeout／exportFailures／pscustomobject | 是 | 全部**無豁免**：oracleMCP 未掛載期間放行的 DB task 照算違反，另以 standDowns／earlyViaStandDown 標來源 |
| SOP-12 舊敘述清理；fs-doctor `-Force`（.npmrc 進 manifest）；全域 `.npmrc`（條件式） | 是 | 文件／搬運正確性 |
| 祖先 READY 放行 | 否（移除） | 目前沒有任何能 task 的 subagent（ps-* 全 task:false，內建覆寫也關），是死碼且是豁免；未來開 subagent_depth>1 再設計 |
| connection-state／epoch | 否 | 先做 SOP-21 步驟 9 的 topology 實驗（T1 跨行程、T2 同行程跨 session、T3 type／回覆原文），再決定 process-level 狀態或跨行程協調 |
| 失敗 ≥ 2 次退讓；`prt_` 退讓 | 否 | DB 掛掉時的正確行為：DB-specific task 被擋／略過、non-DB task 照常；e2e `connect-fail` 鎖住「三次全擋、零 SQL、模型回報 DB 連線建立失敗」 |
| event hook 接「already connected」isError | 否（待驗） | 真 SQLcl 的回覆未驗（R16）；驗完再決定 |
| ps-auditor 混合能力 | 否（另案） | 走 deterministic routing／capability 邊界（拆 agent 或 task 帶確定性 metadata），不在閘門打洞 |
