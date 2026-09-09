# tests/oracle-gate — Oracle 前置閘門（plugin）的沙箱測試組

給**維護 session 的沙箱**用（需要 node ≥ 22 與 OpenCode 1.18.29 binary）；不在搬運 manifest 內，
公司機不必搬。公司機的執行紀錄回歸請用 `scripts/tests/test-oracle-gate-runtime.ps1`（SOP-21）。

受測物：`.opencode/plugin/ps-oracle-preflight-gate.js`——主 agent 未完成 `oracleMCP_connect`（connection_name＝profile
`oracle.connectionName` 原樣）之前，會查 DB 的 subagent 委派（task）在執行前被擋下。
不變量刻意最小（SOP-21）：每則真實訊息 NEED_CONNECT→READY 才放行；list_connections 不是前置（清單把名稱與連線字串黏在一起，不拿來挑名字；
閘門對它只記錄、不改狀態）；唯一例外＝目標沒有 Oracle 能力；
沒有環境層退讓（oracleMCP 未掛載也擋，訊息走 ORACLE_MCP_DOWN 協定）；沒有「失敗幾次就放行」、沒有跨 session／跨行程協調、沒有祖先放行。
呼叫配對：before 留入場快照，after 依 session:callID 配對；上一題晚到的回覆標 stale、不替新題完成前置也不作廢新題；成功判定三態
（有文字且不命中失敗樣式＝true、isError／失敗樣式＝false、空輸出＝"unknown"），false 與 unknown 都不前進。

| 檔 | 用途 | 跑法 |
|---|---|---|
| `unit.test.mjs` | 狀態機單元測試（假 client；23 組：DB 判定與 dbCapable／connect 三態＋list 只記錄＋完全不 list 也能 READY／無入場快照的 after／NOT_CONNECTED 退回與 disconnect／observe 模式／MCP 狀態五種→擋與不快取／synthetic 與同 id 不重置／task 執行中換題與晚到 NOT_CONNECTED／晚到的 connect、list、disconnect／await 期間換題／沒有 fail-open／沒有祖先放行／跨 session callID 不互撞／擋下訊息的連線規則／connect 目標執行前比對（未填、不一致、一致、observe）／connect 嘗試作廢 READY 與較晚嘗試取代／同題連線世代／報告解析七種輸出＋sql_run 三態／第 0 步提醒注入——主 agent 有、subagent／synthetic／同 id／build 無、FILL_ME 變體、env 與 profile 關閉／tools 表萬用字元 deny＋個別 true 的混寫在 _plugin.log 記 WARN／成功回覆引用 ORA-nnnnn 不算失敗、五種失敗句型不前進／先列 todo 層：todowrite 之前的 read／task／connect 都擋、缺開線項擋、補寫放行且黏住、重置與 synthetic、stale todowrite 不算、FILL_ME 變體、subagent／build 不管、observe 只記、env／profile 關／提醒 part 的 todo 句）。tempProject 預設 `todoFirst: off`（狀態機測試不受先列 todo 影響），先列 todo 的測試自己開 on。每次工具呼叫都送 before＋after（與真 host 一致），只有刻意驗「晚到」「沒有快照」的案例才拆開。外部 review 探測對照：R1→狀態機、R2→晚到 connect、R3→晚到 NOT_CONNECTED、R4→三態、R5→無快照、R6→未掛載擋、R7→await 期間換題、G1→目標比對、G2→同題世代、G3→嘗試作廢、G4→報告解析（analyzer 端在 test-auto-loop 情境 33） | `node --test tests/oracle-gate/unit.test.mjs` |
| `mock-oracle-mcp.mjs` | 假 SQLcl MCP（stdio JSON-RPC；tools：list_connections／connect／sql_run／disconnect；list 的輸出仿真 SQLcl 的黏合格式 `Name:<名>Connect string: {…}`；未 connect 就 sql_run 回 not connected；`MOCK_ORACLE_CONNECT_FAIL=1` connect 一律 isError；`MOCK_ORACLE_EMPTY_CONNECT=1` connect 回空 content；`MOCK_ORACLE_CONNECT_DELAY_FIRST_MS` 第一次 connect 延遲；`MOCK_ORACLE_CONNECT_FAIL_FROM=N` 第 N 次起 connect 回 isError） | 由 e2e 的 opencode.json 啟動 |
| `mock-model.mjs` | 假 OpenAI 相容模型（SSE 串流），依「最後一則 user 訊息之後」的工具呼叫序列決定下一步；`MOCK_MODEL_SCENARIO`：task-first／list-first／compliant／stubborn／nodb／connect-fail／stale-probe／reconnect-probe／no-todo／todo-noconnect；每題劇本都先 todowrite（三項，第一項＝第 0 步 connect），no-todo／todo-noconnect 例外；主 agent 劇本只 connect `MOCK_MODEL_CONNECT_NAME`（預設 HR_DEV＝臨時 profile 的值），從不解析清單；每次請求記下可見的 task／oracleMCP_ 工具名（驗允許清單）與最後一則 user 訊息的尾端（驗提醒有送到模型） | 由 e2e 啟動 |
| `run-e2e.mjs` | 真 OpenCode（`OPENCODE_BIN` 或 PATH）＋假 MCP＋假模型跑 `opencode run --agent ps-orchestrator`（或 `opencode serve` 同行程多輪），讀閘門 jsonl、`opencode export` 交叉比對，19 情境斷言 | `OPENCODE_BIN=<binary> node tests/oracle-gate/run-e2e.mjs [--repeat N] [--only <情境>] [--keep]` |

e2e 十九情境與證明的事（每個情境都另斷言：閘門看到的 task 次數＝export 的 task 件數；chat.message 的 turnId 集合＝export 真實題目 id 集合；
閘門每列的 turnId＝export 裡該 tool part 所屬 assistant 訊息的 parentID（before／after 都比）；每個 task 列都有 dbCapable；
除 observe 外，會查 DB 的 task 入場時一律 READY；任何列都沒有 NEED_LIST；list_connections 的 after 列 state＝next 且 note 含 informational；臨時專案的 profile oracle.connectionName 寫成 HR_DEV（閘門在 connect 執行前比對它）；
正向情境另驗已執行的 DB task 列 reportStatus=COMPLETE、childSessionID 指向子 session，且子 session 的 jsonl 有 sql_run ok:true——這是 analyzer「完成」的定義；
每則真實題目在 export 裡帶一個 synthetic「Oracle 第 0 步」提醒 part（使用者文字原樣；開頭要求第一個工具是 todowrite）、主 agent 的每次模型請求尾端看得到它、chat.message 列 reminder=true；
先列 todo：每題至少一次 todowrite 成功列（current、3 項）、同題含第 0 步的 todowrite 先於第一個非 todo 的 before 列、沒有 TODO_FIRST 擋（no-todo／todo-noconnect 除外）、export 的 todowrite 件都 completed）：

| 情境 | 模型劇本 | 證明 |
|---|---|---|
| task-first | 先 task → 被擋 → connect → task | 錯序被擋（transcript 該 task 件是 error、含 PS_ORACLE_PREFLIGHT_REQUIRED，指示只要 connect、明說不必先 list）、前置後放行、subagent SQL 在 connect 之後；mcp 順序 connect、sql_run（零 list）；執行列帶入場快照（admitted／turnId／callID／attribution=current）與解析後的報告（COMPLETE、子 session id）；connect 的 after 配對到 before；connect 的 before 列 decision=allow、gen=1、profileConnection=HR_DEV；**subagent 可見的 Oracle 工具只有 sql_run、主 agent 只有 list_connections＋connect**（允許清單，逐工具明寫） |
| list-first | 先 list（多做的）→ task → 被擋 → connect → task | list 成功不算前置（after 列 NEED_CONNECT→NEED_CONNECT、informational）、task 仍被擋；connect 才放行；mcp 順序 list、connect、sql_run |
| compliant | connect → task | 照做不擋（第一個呼叫就是 connect、零 list）；允許清單同上 |
| stubborn | 只會 task ×4 | 四次全擋、零 SQL、零 NOT_CONNECTED |
| nodb | 派 ps-peoplecode-flow | 不查 DB 的委派不受閘門影響（dbCapable=false） |
| observe | task-first＋`PS_ORACLE_GATE_MODE=observe` | 只記錄（observe-would-block），task 早於前置執行、subagent 回 NOT_CONNECTED——探測證據；執行列 admitted=observe-would-block、reportStatus=BLOCKED／blockedReason=NOT_CONNECTED、子 session 沒有成功的 sql_run |
| mcp-down | oracleMCP `enabled:false` | **擋**（note=oracleMCP not mounted (mcp-status:disabled)），錯誤訊息帶 ORACLE_MCP_DOWN 協定、零 MCP 呼叫、模型回報 ORACLE_MCP_DOWN 不重試 |
| mcp-failed | oracleMCP 指令不存在（/mcp 狀態 failed） | 同上（mcp-status:failed）——每次即時查 status |
| connect-fail | 假 oracleMCP 的 connect 一律 isError | 三次 task 全擋（NEED_CONNECT ×3；blocked 1→3，第三次帶「本題不派 DB 委派、list 一次附清單原文」提示）、零 SQL、connect 的 after 永不觸發、放棄時 list 一次（after 列 informational）、模型回報「DB 連線建立失敗」＋清單原文（Name:HR_DEVConnect string…）——沒有 fail-open；mcp 順序 connect、connect、list |
| empty-connect | connect「成功」但回空 content | 兩次 connect 的 after 都 ok:"unknown"（empty tool output）、狀態停在 NEED_CONNECT、三次 task 全擋、零 SQL——空輸出不是成功 |
| multi-turn | 同 session 兩題，第二題 `opencode run --session <id>`（新行程） | 兩個 chat.message、turnId 不同；每題各自被擋→前置→放行；export 真實題目＝2 |
| multi-turn-serve | `opencode serve` 同一行程對同一 session 連送兩題（HTTP API） | 第二則 chat.message 到來時 session 仍 READY，被重置為 NEED_CONNECT；兩題各自被擋→connect→放行；沒有 stale 列 |
| compaction-serve | 同 multi-turn-serve，但兩題之間 `POST /session/:id/summarize`（compaction） | export 有 3 則 user 訊息（其中 1 則只有 compaction part）、chat.message 只有 2 則且 id＝兩則真實題目 |
| stale-connect-serve | 第一題 connect（假 MCP 延遲 5 秒）；connect 一開始就送第二題（不等第一題結束） | 第二則 chat.message 在第一題 connect 進行中到達並重置（turn 2）；第一題的 connect 晚到：after 列 attribution=stale、turnId＝第一題、replyTurnId＝第二題、gen=1、不前進（NEED_CONNECT→NEED_CONNECT）；export 裡該 connect 屬第一題（parentID）；第二題自己 connect（gen=2）：task 先被擋（NEED_CONNECT）再放行；mcp 順序 connect、connect、sql_run |
| wrong-target | profile oracle.connectionName=HR_UAT；模型 connect(HR_DEV)（connect-fail 劇本） | connect 在執行前被擋（before 列 decision=block、note=ORACLE_CONNECTION_MISMATCH、connection=HR_DEV、profileConnection=HR_UAT）、沒有 after 列、假 MCP 零呼叫（也沒有 list）；task 三次全擋（NEED_CONNECT ×3）、零 SQL；connect 的 tool part 是 error 且帶錯誤碼；模型回報「Oracle 連線未設定」 |
| not-configured | profile 是 FILL_ME | 同上，note=ORACLE_CONNECTION_NOT_CONFIGURED |
| no-todo | 不寫 todo 就 connect → 被擋 → todowrite → connect → task | 第一個 connect 的 before 列 decision=block、note=TODO_FIRST:NO_TODO、todoBlocked=1，transcript 該件 error 含 PS_TODO_FIRST_REQUIRED 與 todowrite 指示；假 MCP 沒收到那次 connect（mcp 順序 connect、sql_run）；順序＝被擋 connect → 含第 0 步的 todowrite → connect allow → READY → task |
| todo-noconnect | todo 缺第 0 步一項 → connect 被擋 → 補寫 todo → connect → task | todowrite 列兩筆（connectItem false → true）；擋下列 note=TODO_FIRST:TODO_NO_CONNECT_ITEM；其餘同 no-todo |
| reconnect-fail | connect（READY）→ 再 connect（假 MCP 從第 2 次起 isError）→ task… | 第二個 connect 的 before 列 state=READY→next=NEED_CONNECT、gen 依序 1～4、note=connect attempt invalidates READY…；只有第一個 connect 有 after；之後三次 task 全擋（NEED_CONNECT）、零 SQL；放棄時 list 一次（informational）；模型回報「DB 連線建立失敗」；mcp 順序 connect ×4、list |

取得 binary（沙箱）：`npm pack opencode-linux-x64@1.18.29` 解開後 `package/bin/opencode`。
e2e 每個情境約 10～30 秒（含臨時 XDG 目錄的首次初始化），serve 類約 30～35 秒；`--keep` 保留工作目錄（含 run.stdout／stderr、閘門 jsonl、export.json、mcp／model 紀錄）。
注意：OpenCode 用 `PWD` 環境變數決定專案目錄（run.ts），執行器已為子行程設定 `PWD`。
analyzer 交叉驗證：`--keep` 之後可用 PowerShell 以 AST 抽出 `Get-SessionVerdict`（同 test-auto-loop 情境 33 的做法）對每個情境的 jsonl＋export.json 判讀，
預期 observe 為 early=1／turnViol=1、mcp-down／mcp-failed 為 mcpDownBlocks=1、empty-connect 為 unknownResults=2、stale-connect-serve 為 staleReplies=1、
wrong-target／not-configured 為 connectBlocks=2、listCalls 只有 list-first／connect-fail／empty-connect／reconnect-fail 為 1（其餘 0），其餘全 0 且 callMismatch 全 0（v6 沙箱實跑一致）。
