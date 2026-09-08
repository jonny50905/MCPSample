# Oracle 前置閘門（issue #29）決策備忘——issue 主張逐條對碼

日期：2026-09-08。對象：OpenCode 1.18.29（`anomalyco/opencode` tag v1.18.29 原始碼）。
結論：採 plugin 執行期閘門；issue 的方向對，細節有五處與原始碼／框架既有規則不合，逐條記錄取捨。

## 一、issue 的主張 vs 核對結果

| # | issue 主張 | 核對結果 | 採納 |
|---|---|---|---|
| 1 | 順序只是 prompt 指令，執行是機率性的 | 成立。`task` 從回合一開始就在工具清單裡；情境 31 只驗文字 | 採納（根因） |
| 2 | 用 `tool.execute.before` 擋 `task`，throw 即阻擋 | 成立。`session/tools.ts`：registry 工具（含 task）與 MCP 工具都先 `Plugin.trigger("tool.execute.before")` 再執行；hook 的 promise reject → AI SDK `tool-error` → `processor.failToolCall` 把 `error.message` 寫進 tool part，模型下一步看得到 | 採納 |
| 3 | 狀態機 NEED_LIST→NEED_CONNECT→READY；擋而不改參數 | 成立。成功判定：MCP `isError` 會在 `McpCatalog.convertTool` throw，`tool.execute.after` 不觸發，所以 after 觸發＝成功；另加保守的失敗文字樣式（ORA-／TNS-／not connected…）防「成功回傳但內容是錯誤」 | 採納 |
| 4 | 擋「所有 task」直到 READY | **不採**。ps-peoplecode-flow／ps-sql-flow／ps-sqr-flow 的 tools 表 `oracleMCP_*: false`，不碰 DB；擋全部會讓 DB 掛掉時純 ES／Source 的題也無法委派，與第 0 步「非 DB 部分照常作答」矛盾。改為只擋 tools 表 `oracleMCP_run_sql` 為開的 subagent（最後匹配者優先、沒列＝開、不認識的名字＝開）。注意這是能力判定：ps-auditor 的純 chunk 任務也過閘門（見 §四 R3 的退讓） | 修正 |
| 5 | 互動與 headless 的 hook 行為可能不同，要分開驗 | 原始碼是同一條路（`opencode run` 用 in-process server，`Server.Default().app.fetch`）；沙箱 e2e 已在 headless 驗過 7 情境。互動路徑仍列公司機驗證（`-AnalyzeAll`） | 部分採納 |
| 6 | 先做「印每次 before 的探針」跑 20 次目測 | 改成機械判定：閘門交易紀錄的 task 次數 ＝ `opencode export` transcript 的 task 件數（逐 session）；observe 模式就是探針 | 修正 |
| 7 | hook 覆蓋率不到 100% 就把前置移到模型迴圈外的 wrapper | 部分成立的前提待驗：oracleMCP 若是 OpenCode 以 stdio 起的子行程，「目前連線」活在該行程內、行程外連不到；若是遠端（VS Code 端 SQLcl，SOP-12 的說法），wrapper 連得到但擋不住模型的順序。兩種情況 plugin 都是模型迴圈內唯一的確定性層。**管理者請確認公司機 opencode.json 的 oracleMCP `type`**（local／remote），寫回 SOP-12 | 不採（記錄理由；transport 待驗） |
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
| R1 | 連線是全域單例，per-session READY 會失真（別的 session connect／disconnect 後仍 READY；最壞查錯庫） | **成立**。L109 已定案單例；公司機 oracleMCP 若是遠端（VS Code 端 SQLcl），單例還跨 OpenCode 行程 | 共用連線身分（`connection-state.json` 記連線名，跨行程）：換名或 disconnect 才作廢別人的 READY，同名重連不作廢；作廢退回 NEED_CONNECT 並擋、訊息標來源。e2e `shared-switch`＋單元測試（第一版 epoch 對每次嘗試推進，第三輪改掉：見 S1b） |
| R2 | analyzer 只證 task hook 覆蓋率，沒證 chat.message 每題都 fire；需要 per-turn 不變量與真正的多 turn 測試 | **成立** | turnId＝user 訊息 id；analyzer 加 turnMismatch／turnInvariantViolations（都判定）；e2e `multi-turn`（run --session）＋`multi-turn-serve`（serve 同行程兩題，斷言 READY→NEED_LIST 的重置） |
| R3 | ps-auditor 混合能力，按 agent 能力判定會過度 gate；應拆 agent 或給 task 帶 metadata | **成立**：task 工具無 metadata 通道；任務 A 檔級 evidence 混 CHUNK／SQL，拆不開；閘門的軸是能力，SOP-12 併發上限的軸是實際呼叫 | 不拆 agent（另案）；改閘門只擋順序不擋可用性：list 成功後 connect 失敗 ≥ 2 次 → 退讓，交 NOT_CONNECTED 協定，稽核批次不卡死（SOP-21） |
| R4 | mcp.status 15 秒快取不能當正確性放行依據 | **成立** | 拿掉快取，每次即時查；單元測試 |
| R5 | SOP-12 殘留舊協定敘述 | **成立** | 就地改為現況＋標【已作廢】 |

review 沒提、本輪順手修的：`opencode run --session` 續接是**新行程**——plugin 的 in-memory 狀態與數字 turn 計數器都歸零，
所以 turn 識別必須用 user 訊息 id；同時這也表示 headless 的每一次 run 都從 NEED_LIST 起步（與 per-turn 重置同義）。

對本輪修法再做一次對抗式驗證（15 個獨立視角＋1 個批評者）後補的：

| # | 抓到的洞 | 修法 |
|---|---|---|
| S1 | epoch 的 before／after TOCTOU：兩 session 的 connect 交錯，兩邊都 READY | connect 的 before 記住當時共用狀態版本，after 核對版本與名字：交錯到不同名只有最後起跑的算 READY，同名交錯兩邊都算 |
| S1b | （第三輪）epoch 對每次 connect 嘗試推進，同名重連（每題第 0 步常態）也作廢別人 → 互動視窗與 auto-loop 互相 ping-pong、誤計放棄提示 | 共用狀態改記**連線名**（`connection-state.json`）：換名或 disconnect 才作廢；作廢退回 NEED_CONNECT、不計 blocked、訊息標來源與下一步 |
| S2 | 過期訊息一律怪「別的 session」，看不出是誰動的 | epoch 檔記 tool／session／pid，訊息與 note 標來源 |
| S3 | epoch 檔寫失敗無聲（Windows 防毒鎖檔） | rename 重試 3 次，仍失敗記 `_plugin.log`＋列上 `epochWriteError` |
| S4 | task 執行中送下一題 → after 列被錯標到新 turn，假 early／turnViol | task 入場時快照 turnId／turn／state（`admitted`），after 列用快照 |
| S5 | `turnMismatch` 計數比對被 compaction／`/undo`／`--fork` 誤判 | 真實題目 id 逐一比對 chat.message turnId；孤兒只記 orphanTurns；e2e `compaction-serve` |
| S6 | PS 5.1 的 `Measure-Object -Property` 不吃 hashtable | verdict 改 `[pscustomobject]`；情境 33 加總測試 |
| S7 | e2e 第二 turn 落到 build agent | `--agent ps-orchestrator` |
| S8 | `-AnalyzeAll` 對子 session 也跑 export（慢） | 先看 jsonl 判定子 session 再決定要不要 export |
| S9 | command 驅動的 subtask（handleSubtask，callID `prt_`）沒有 tool-error 通道，throw 殺掉整個 prompt | 閘門退讓並記 note；e2e `subtask-command` |
| S10 | list 連失敗不退讓；NOT_CONNECTED 後計數不歸零，退讓再也不觸發 | list 失敗 ≥ 2 次也退讓；NOT_CONNECTED 歸零計數 |
| S11 | `admitted`／`pending` 以裸 callID 為鍵，OpenAI 相容端點的 call_0 會跨 session 互撞；await 之間狀態可能已變；祖先檢查改父狀態 | 鍵改 `session:callID`；await 後重判；祖先檢查純讀 |
| S12 | SQLcl「已連線再 connect」若回 isError，after 永不觸發 | `event` hook 接 connect 錯誤件：already connected 視為成功，其他記 failureMatch=isError；SOP-21 快篩加第二題 |
| S13 | analyzer：PS 5.1 主控台解碼弄壞 export JSON；`taskkill 2>$null` 在 EAP=Stop 下終止腳本；rc 檔沒讀 | export 落檔以 UTF-8 讀、exportFailures 判 FAIL；taskkill 走 cmd；exitCode／timedOut 判 FAIL |
| S14 | 紀錄量：每個 subagent session 一檔＋每句 run_sql 一列 | 不記 run_sql、純 subagent 不建檔、session.deleted 清記憶 |
| S15 | mcp-down 情境的刻意退讓被 analyzer 算成違反 | callID 配對把退讓／祖先放行排除，另計 standDowns |
