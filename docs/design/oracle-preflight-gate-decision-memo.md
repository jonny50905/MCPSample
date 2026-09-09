# Oracle 前置閘門（issue #29）決策備忘——issue 主張逐條對碼

日期：2026-09-08。對象：OpenCode 1.18.29（`anomalyco/opencode` tag v1.18.29 原始碼）。
結論：採 plugin 執行期閘門；issue 的方向對，細節有五處與原始碼／框架既有規則不合，逐條記錄取捨。

## 一、issue 的主張 vs 核對結果

| # | issue 主張 | 核對結果 | 採納 |
|---|---|---|---|
| 1 | 順序只是 prompt 指令，執行是機率性的 | 成立。`task` 從回合一開始就在工具清單裡；情境 31 只驗文字 | 採納（根因） |
| 2 | 用 `tool.execute.before` 擋 `task`，throw 即阻擋 | 成立。`session/tools.ts`：registry 工具（含 task）與 MCP 工具都先 `Plugin.trigger("tool.execute.before")` 再執行；hook 的 promise reject → AI SDK `tool-error` → `processor.failToolCall` 把 `error.message` 寫進 tool part，模型下一步看得到 | 採納 |
| 3 | 狀態機 NEED_LIST→NEED_CONNECT→READY；擋而不改參數 | 成立。成功判定：MCP `isError` 會在 `McpCatalog.convertTool` throw，`tool.execute.after` 不觸發，所以 after 觸發＝成功；另加保守的失敗文字樣式（ORA-／TNS-／not connected…）防「成功回傳但內容是錯誤」 | 採納 |
| 4 | 擋「所有 task」直到 READY | **不採**。ps-peoplecode-flow／ps-sql-flow／ps-sqr-flow 的 tools 表 `oracleMCP_*: false`，不碰 DB；擋全部會讓 DB 掛掉時純 ES／Source 的題也無法委派，與第 0 步「非 DB 部分照常作答」矛盾。改為只擋 tools 表 `oracleMCP_sql_run` 為開的 subagent（最後匹配者優先、沒列＝開、不認識的名字＝開） | 修正 |
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
- **子 session 不會呼叫 task**（`subagent_depth` 預設 1；ps-* subagent 全 `task: false`）；早期版本沿 `parentID` 找 READY 的祖先，
  退版重寫時移除（死碼且是豁免，見 §四）。

## 三、閘門的邊界（有意）

- 只擋、不改參數、不代模型 connect（模型仍要自己做第 0 步；閘門把「應該」變「必須」）。
- oracleMCP 未掛載（`/mcp` 非 connected）一樣擋，錯誤訊息改走 ORACLE_MCP_DOWN 協定（review 第二輪後；之前是退讓）；狀態查不到（SDK 例外）保守仍擋。
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

## 五、外部 review 第二輪（2026-09-08，對 d544ec3）逐條

| # | review 主張 | 核對 | 處置 |
|---|---|---|---|
| P1-1 | list／connect 沒保存呼叫所屬題目，晚到回覆跨題污染（重現：A 題 connect 晚到替 B 題完成前置） | 成立。d544ec3 的 after 用「現在」的 session 狀態與 turnId。原始碼：`chat.message` 在訊息送進來當下觸發（prompt.ts createUserMessage），忙碌 session 的新訊息併入正在跑的迴圈（ensureRunning），晚到確實可能；單一 session 內 tool 循序，review 的精確交錯（B 的 list 先於 A 的 connect 完成）排不出來，但 hook 層仍要正確 | 落地：入場快照＋callID 配對＋stale／unknown 不前進＋await 後重判 turnId；e2e stale-connect-serve 在真 host 重現「第二題在第一題 connect 期間送進來」 |
| P1-2 | task 快照只修 log，NOT_CONNECTED 晚到會作廢新題的 READY | 成立 | 落地：NOT_CONNECTED 只在入場 turnId＝目前 turnId 時退狀態；「連線世代」屬第二批 |
| P1-3 | per-session READY 不是共用連線有效性的保證 | 成立；記載限制不等於修復 | 另案（第二批）：SOP-21 已知限制 (b) 改寫為「不證明共用連線仍是預期連線、不證明查詢跑在正確 DB」；先做 topology 實驗 |
| P1-4 | 每題無條件 connect ≠ 安全的 ensure-connected；「否則清單第一個」＝靜默連錯 DB | 連線選擇成立、先修；其餘是規格變更 | 落地：profile 必填且在清單裡，否則回「Oracle 連線未設定」、不 connect；不在閘門加「跳過 connect」的例外；ensure-connected／owner／DUAL 探測屬第二批 |
| P2-1 | subagent Oracle 權限是排除清單，sqlcl_run 等仍開 | 成立（OpenCode permission `findLast` 最後匹配者優先；`disabled()` 把 deny 的工具從模型工具清單拿掉） | 落地：`"oracleMCP_*": false` → `"oracleMCP_sql_run": true`；e2e 驗 subagent 可見 Oracle 工具只剩 sql_run、主 agent 只剩 list_connections＋connect |
| P2-2 | analyzer 用 basis 字串篩能力漏 unknown-agent；缺 callID 級配對；零違規≠可用 | 成立 | 落地：dbCapable 欄位、callMismatch（before／after／export parentID）、安全／可用兩條驗收、-ExpectDbTask |
| P2-3 | MCP down 退讓與「絕不在 READY 前執行」矛盾；空輸出當成功 | 成立 | 落地：未掛載改為擋（ORACLE_MCP_DOWN 協定訊息，不重試）；三態 ok；文件不再宣稱環境層退讓；MCP isError 仍靠 OpenCode throw（after 不觸發＝失敗） |

第二批（連線生命週期改版，另案，需同步改 agent／cookbook／plugin／驗收，不能只改 prompt）：題目狀態與資源狀態分離
（UNKNOWN→PREPARING→READY→DEGRADED、連線世代）、owner 與目標驗證、DUAL 探測（SYS_CONTEXT DB_NAME／SESSION_USER／CURRENT_SCHEMA）
先於業務查詢、同一輪只一次復原、SQL 與連線操作在真實資源邊界排程、真 SQLcl repeated-connect 契約（R16／topology T1～T3）。
驗收結論的措辭（採 review 建議）：已修正 subagent 自行管理共用連線的權限路徑、派工前置閘門與跨題晚到回覆的歸屬；共用連線的有效性、
目標一致性、集中復原與真 SQLcl repeated-connect 契約尚未驗證——目前是「部分修正」，不是「共用連線問題已完整解決」。

## 六、外部 review 第三輪（2026-09-08，對 e0b1c75）逐條

| # | review 主張 | 核對 | 處置 |
|---|---|---|---|
| F1 | analyzer 的「完成」＝沒回 NOT_CONNECTED，BLOCKED(QUERY_TIMEOUT／SCHEMA_UNRESOLVED)／非 JSON 都算成功（G4） | 成立 | plugin 的 task after 解析報告（status／blockedReason／taskState／childSessionID），子 session 的 sql_run after 記 ok；analyzer 完成＝COMPLETE 且子 session sql_run ok；PARTIAL／BLOCKED／INVALID／COMPLETE-無-SQL 分開計；情境 33 加假成功反例；e2e 正向情境驗子 session sql_run ok |
| F2 | connectionName 只是模型規則，plugin 未比對 connect 參數（G1） | 成立 | connect 的 before 在執行前比對 profile：未填 → NOT_CONFIGURED、不一致 → MISMATCH，工具不執行；快照存 validated target 供 after 核對；e2e wrong-target／not-configured |
| F3 | 同題不同連線世代未隔離（G2） | 成立（hook 層可重現；真 host 排程未證實） | 採 review 選項 2 的 session 內版本：connect 嘗試世代、task 入場記世代、舊世代的 NOT_CONNECTED 不作廢新世代；跨 session 協調另案 |
| F4 | 已 READY 後再 connect 失敗 READY 不作廢（G3） | 成立 | 嘗試開始即作廢 READY，只由該次嘗試成功恢復；較晚嘗試取代較早；e2e reconnect-fail。「同名已連線再 connect」的真 SQLcl 契約仍待 R16／R20 |
| — | 保留七個回歸案例 | 已在 unit 中（對照：R1→狀態機、R2→晚到 connect、R3→晚到 NOT_CONNECTED、R4→三態、R5→無快照、R6→未掛載擋、R7→await 期間換題） | tests README 加對照表 |
| — | 重生 manifest、保留內網設定 | 是 | HANDOFF 註明已填 connectionName／currentSchema 不得被 FILL_ME 覆蓋，且 connectionName 必須與 SQLcl 已儲存連線名完全一致（閘門現在強制） |

review 的驗收結論採納：對「受控 subagent 自己開／關共用連線」的原始路徑，在受控配置下已切斷；「subagent 任何時候都能用正確 Oracle
連線」仍不能宣告——共用連線持續有效性、跨 session 集中復原、真 SQLcl repeated-connect 契約、DB／schema 一致性是另一階段。

## 七、「第 0 步常被略過」：併入工作流＋訊息注入提醒（2026-09-09，公司機實測後）

| 選項 | 可行？ | 取捨 |
|---|---|---|
| 獨立「## 第 0 步」章節（原做法） | 已證明常被跳過 | 章節不是模型執行的計畫；工作流清單才是 |
| 併入工作流編號步驟 | 採 | ps-orchestrator 第 2 步（載入 profile 之後、查 wiki 之前）、deep-research 啟動與續跑第 0 項、audit-orchestrator 第一動作第 1 項；名字保留「第 0 步」 |
| 閘門在每則真實訊息注入 synthetic 提醒 part | 採 | OpenCode 的 `chat.message` hook 拿到的 parts 陣列在持久化前可加（OpenCode 自己用同一機制對模型下指令）；synthetic text part 會送給模型、export 看得到、不算「真實題目」的判定依據（有非 synthetic part 才算）；只給 primary 且有 list＋connect 的 agent；不擋、不查狀態；可關 |
| plugin 自己做 list→connect（確定性 owner） | 1.18.29 不可行 | server 只有 `/experimental/tool`（list／ids），沒有呼叫工具的 route；MCP client 不暴露給 plugin；owner 設計屬第二批，且要同時解決共用連線的生命週期 |
| 閘門把「派 task」自動改寫成「先 connect」 | 不採 | 閘門只擋不改參數（既定邊界）；改寫工具呼叫＝隱性副作用，review 已明確反對 |

副作用與邊界：session 標題由第一則訊息生成時可能帶到提醒字樣（cosmetic）；提醒讓 blockedRuns 下降是機率行為，硬性保證仍只有擋；
analyzer／e2e 的「真實題目」判定看非 synthetic part，不受注入影響。

## 八、公司機第五輪：萬用字元 deny 隱藏整個 MCP、list_connections 清單黏合（2026-09-09）

| 問題 | 事實 | 決定 |
|---|---|---|
| 主 agent 說「沒有掛載 list_connections／connect」 | tools 表 `"oracleMCP_*": false` 之後再開個別 true；公司機 OpenCode 把整個 MCP 對該 agent 隱藏、true 救不回；沙箱 1.18.29 是最後匹配者優先——版本行為不同 | 逐工具明寫（主 agent：list／connect true、disconnect／sql_run／sqlcl_run false；DB subagent：sql_run true、其餘 false）；全關的 agent 才用萬用字元；閘門載入時記 wildcardDenyMix 警告；情境 31 擋混寫回流 |
| list_connections 回 `Name:ABCReadonlyConnect string: {…}`，模型讀成 ABCReadonlyConnect | 名稱與連線字串黏在一起、沒有分隔；從清單挑名字必然讀錯 | 第 0 步不 list：直接 connect profile `oracle.connectionName`（原樣照抄；閘門在執行前比對）；list 只在 connect 兩次失敗後呼叫一次、把原文附給管理者核對 |
| 閘門不變量 | NEED_LIST 這一段只是在要求一個沒有價值（且有害）的步驟 | 縮成 `NEED_CONNECT ─connect 成功→ READY`；list 的 after 只記錄不改狀態；disconnect／新訊息退回 NEED_CONNECT；analyzer turnInvariantViolations 只看 connect→READY，多 listCalls 觀察值 |

| 選項 | 可行？ | 取捨 |
|---|---|---|
| 閘門解析清單、驗 profile 值在不在清單裡 | 不採 | 清單格式黏合、不同 SQLcl 版本可能不同；解析錯誤會變成閘門永遠不開。profile 值就是唯一真相，connect 失敗本身就是驗證 |
| 閘門依公司機語義重算工具可見性（萬用字元 deny＝整個 MCP 隱藏） | 不採 | 公司機版本與規則未證實；閘門只在載入時警告混寫，判定仍用 1.18.29 的最後匹配（混寫者保守視為會查 DB） |
| 主 agent 保留 list_connections 工具 | 採 | 只作 connect 失敗後的診斷附件；正常題目零 list（R24 / listCalls=0） |

驗證：單元 20、e2e 17（connect-first→list-first；stale-connect-serve 改成第一題 connect 未回就送第二題；放棄路徑 list 一次附清單）、
test-auto-loop 情境 31／32／33。

## 九、模型有機率沒先列 todo 就開工：第三層閘門「todowrite 先於一切」（2026-09-09）

| 問題 | 事實 | 決定 |
|---|---|---|
| 有 todo 的題一次做一項、等 connect 回來再派；沒有 todo 的題 connect 未回就派 subagent → NOT_CONNECTED | 公司機：GPT-LUNA 多半先列、Claude Sonnet 多半不列 | 不靠 prompt，靠擋：主 agent 每題第一個工具呼叫必須是 todowrite（含第 0 步一項） |
| 為什麼是機率 | OpenCode 只對 id 含 claude 的模型注入 TodoWrite 指令（anthropic.txt）；gpt-4／o1／o3 用 beast.txt（markdown todo，不是工具）；其他 id（含走相容端點的 Sonnet）拿 default.txt——零 todo 指令；工具說明只有「When in doubt, use it」 | 任何 prompt 措辭都做不到 100%；hook 層可以 |

| 選項 | 可行？ | 取捨 |
|---|---|---|
| 在 agent 檔／提醒 part 加「先 todowrite」規則 | 採（第二道） | 同 L0：純 prose 對某些模型效力弱；只當說明，不當保證 |
| plugin 擋 todowrite 之前的任何工具（PS_TODO_FIRST_REQUIRED） | 採 | 與第 0 步同一模式：只擋、不改參數、不代寫；task 也先被這層擋，輪不到前置閘門；todo 缺第 0 步一項也擋，補寫即可；同題黏住 |
| 要求 todo 第一項就是 connect | 不採 | 工作流第 1 步是載入 profile；只要求「含開線一項且排在 task 之前」，順序交給 todo |
| plugin 自己寫 todo | 不採 | 沒有 plugin 呼叫工具的 API（同 §七）；且 todo 內容該由模型依題目寫 |
| 擋 assistant 純文字回覆（沒有工具就作答） | 不可行 | hook 看不到 assistant 文字；沒有工具呼叫就沒有「開工」，也沒有連線問題 |

邊界：模型在同一步同時送 todowrite＋其他工具 → 其他工具仍被擋（after 未回）；重來一次即可。observe 模式只記 hook=todo-first 列，不佔 before 列
（task 件數才與 transcript 對得上）。驗證：單元 23、e2e 19（no-todo／todo-noconnect）、test-auto-loop。
