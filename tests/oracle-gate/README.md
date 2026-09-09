# tests/oracle-gate — Oracle 前置閘門（plugin）的沙箱測試組

給**維護 session 的沙箱**用（需要 node ≥ 22 與 OpenCode 1.18.29 binary）；不在搬運 manifest 內，
公司機不必搬。公司機的執行紀錄回歸請用 `scripts/tests/test-oracle-gate-runtime.ps1`（SOP-21）。

受測物：`.opencode/plugin/ps-oracle-preflight-gate.js`——主 agent 未依序完成
`oracleMCP_list_connections` → `oracleMCP_connect` 之前，會查 DB 的 subagent 委派（task）在執行前被擋下。
不變量刻意最小（SOP-21）：每則真實訊息 NEED_LIST→NEED_CONNECT→READY 才放行；唯一例外＝目標沒有 Oracle 能力；
沒有環境層退讓（oracleMCP 未掛載也擋，訊息走 ORACLE_MCP_DOWN 協定）；沒有「失敗幾次就放行」、沒有跨 session／跨行程協調、沒有祖先放行。
呼叫配對：before 留入場快照，after 依 session:callID 配對；上一題晚到的回覆標 stale、不替新題完成前置也不作廢新題；成功判定三態
（有文字且不命中失敗樣式＝true、isError／失敗樣式＝false、空輸出＝"unknown"），false 與 unknown 都不前進。

| 檔 | 用途 | 跑法 |
|---|---|---|
| `unit.test.mjs` | 狀態機單元測試（假 client；19 組：DB 判定與 dbCapable／list→connect 順序與三態／無入場快照的 after／NOT_CONNECTED 退回與 disconnect／observe 模式／MCP 狀態五種→擋與不快取／synthetic 與同 id 不重置／task 執行中換題與晚到 NOT_CONNECTED／晚到的 connect、list、disconnect／await 期間換題／沒有 fail-open／沒有祖先放行／跨 session callID 不互撞／擋下訊息的連線規則／connect 目標執行前比對（未填、不一致、一致、observe）／connect 嘗試作廢 READY 與較晚嘗試取代／同題連線世代／報告解析七種輸出＋run_sql 三態／第 0 步提醒注入——主 agent 有、subagent／synthetic／同 id／build 無、FILL_ME 變體、env 與 profile 關閉）。每次工具呼叫都送 before＋after（與真 host 一致），只有刻意驗「晚到」「沒有快照」的案例才拆開。外部 review 探測對照：R1→狀態機、R2→晚到 connect、R3→晚到 NOT_CONNECTED、R4→三態、R5→無快照、R6→未掛載擋、R7→await 期間換題、G1→目標比對、G2→同題世代、G3→嘗試作廢、G4→報告解析（analyzer 端在 test-auto-loop 情境 33） | `node --test tests/oracle-gate/unit.test.mjs` |
| `mock-oracle-mcp.mjs` | 假 SQLcl MCP（stdio JSON-RPC；tools：list_connections／connect／run_sql／disconnect；未 connect 就 run_sql 回 not connected；`MOCK_ORACLE_CONNECT_FAIL=1` connect 一律 isError；`MOCK_ORACLE_EMPTY_CONNECT=1` connect 回空 content；`MOCK_ORACLE_CONNECT_DELAY_FIRST_MS` 第一次 connect 延遲；`MOCK_ORACLE_CONNECT_FAIL_FROM=N` 第 N 次起 connect 回 isError） | 由 e2e 的 opencode.json 啟動 |
| `mock-model.mjs` | 假 OpenAI 相容模型（SSE 串流），依「最後一則 user 訊息之後」的工具呼叫序列決定下一步；`MOCK_MODEL_SCENARIO`：task-first／connect-first／compliant／stubborn／nodb／connect-fail／stale-probe／reconnect-probe；每次請求記下可見的 task／oracleMCP_ 工具名（驗允許清單）與最後一則 user 訊息的尾端（驗提醒有送到模型） | 由 e2e 啟動 |
| `run-e2e.mjs` | 真 OpenCode（`OPENCODE_BIN` 或 PATH）＋假 MCP＋假模型跑 `opencode run --agent ps-orchestrator`（或 `opencode serve` 同行程多輪），讀閘門 jsonl、`opencode export` 交叉比對，17 情境斷言 | `OPENCODE_BIN=<binary> node tests/oracle-gate/run-e2e.mjs [--repeat N] [--only <情境>] [--keep]` |

e2e 十七情境與證明的事（每個情境都另斷言：閘門看到的 task 次數＝export 的 task 件數；chat.message 的 turnId 集合＝export 真實題目 id 集合；
閘門每列的 turnId＝export 裡該 tool part 所屬 assistant 訊息的 parentID（before／after 都比）；每個 task 列都有 dbCapable；
除 observe 外，會查 DB 的 task 入場時一律 READY；臨時專案的 profile oracle.connectionName 寫成 HR_DEV（閘門在 connect 執行前比對它）；
正向情境另驗已執行的 DB task 列 reportStatus=COMPLETE、childSessionID 指向子 session，且子 session 的 jsonl 有 run_sql ok:true——這是 analyzer「完成」的定義；
每則真實題目在 export 裡帶一個 synthetic「Oracle 第 0 步」提醒 part（使用者文字原樣）、主 agent 的每次模型請求尾端看得到它、chat.message 列 reminder=true）：

| 情境 | 模型劇本 | 證明 |
|---|---|---|
| task-first | 先 task → 被擋 → list → connect → task | 錯序被擋（transcript 該 task 件是 error、含 PS_ORACLE_PREFLIGHT_REQUIRED）、前置後放行、subagent SQL 在 connect 之後；執行列帶入場快照（admitted／turnId／callID／attribution=current）與解析後的報告（COMPLETE、子 session id）；list／connect 的 after 都配對到 before；connect 的 before 列 decision=allow、gen=1、profileConnection=HR_DEV；**subagent 可見的 Oracle 工具只有 run_sql、主 agent 只有 list_connections＋connect**（允許清單） |
| connect-first | 先 connect（跳過 list）→ task | connect 先於 list 不算（狀態留在 NEED_LIST），仍需 list→connect |
| compliant | list → connect → task | 照做不擋；允許清單同上 |
| stubborn | 只會 task ×4 | 四次全擋、零 SQL、零 NOT_CONNECTED |
| nodb | 派 ps-peoplecode-flow | 不查 DB 的委派不受閘門影響（dbCapable=false） |
| observe | task-first＋`PS_ORACLE_GATE_MODE=observe` | 只記錄（observe-would-block），task 早於前置執行、subagent 回 NOT_CONNECTED——探測證據；執行列 admitted=observe-would-block、reportStatus=BLOCKED／blockedReason=NOT_CONNECTED、子 session 沒有成功的 run_sql |
| mcp-down | oracleMCP `enabled:false` | **擋**（note=oracleMCP not mounted (mcp-status:disabled)），錯誤訊息帶 ORACLE_MCP_DOWN 協定、零 MCP 呼叫、模型回報 ORACLE_MCP_DOWN 不重試 |
| mcp-failed | oracleMCP 指令不存在（/mcp 狀態 failed） | 同上（mcp-status:failed）——每次即時查 status |
| connect-fail | 假 oracleMCP 的 connect 一律 isError | 三次 task 全擋（NEED_LIST、NEED_CONNECT、NEED_CONNECT；blocked 1→3，第三次帶「本題不派 DB 委派」提示）、零 SQL、connect 的 after 永不觸發、模型回報「DB 連線建立失敗」——沒有 fail-open |
| empty-connect | connect「成功」但回空 content | 兩次 connect 的 after 都 ok:"unknown"（empty tool output）、狀態停在 NEED_CONNECT、三次 task 全擋、零 SQL——空輸出不是成功 |
| multi-turn | 同 session 兩題，第二題 `opencode run --session <id>`（新行程） | 兩個 chat.message、turnId 不同；每題各自被擋→前置→放行；export 真實題目＝2 |
| multi-turn-serve | `opencode serve` 同一行程對同一 session 連送兩題（HTTP API） | 第二則 chat.message 到來時 session 仍 READY，被重置為 NEED_LIST；兩題各自被擋→前置→放行；沒有 stale 列 |
| compaction-serve | 同 multi-turn-serve，但兩題之間 `POST /session/:id/summarize`（compaction） | export 有 3 則 user 訊息（其中 1 則只有 compaction part）、chat.message 只有 2 則且 id＝兩則真實題目 |
| stale-connect-serve | 第一題 list → connect（假 MCP 延遲 5 秒）；connect 一開始就送第二題（不等第一題結束） | 第二則 chat.message 在第一題 NEED_CONNECT 時到達並重置；第一題的 connect 晚到：after 列 attribution=stale、turnId＝第一題、replyTurnId＝第二題、不前進（NEED_LIST→NEED_LIST）；export 裡該 connect 屬第一題（parentID）；第二題自己 list→connect：task 先被擋（NEED_CONNECT）再放行；mcp 順序 list、connect、list、connect、run_sql |
| wrong-target | profile oracle.connectionName=HR_UAT；模型 connect(HR_DEV)（connect-fail 劇本） | connect 在執行前被擋（before 列 decision=block、note=ORACLE_CONNECTION_MISMATCH、connection=HR_DEV、profileConnection=HR_UAT）、沒有 after 列、假 MCP 只收到 list_connections；task 三次全擋（NEED_LIST、NEED_CONNECT、NEED_CONNECT）、零 SQL；connect 的 tool part 是 error 且帶錯誤碼；模型回報「Oracle 連線未設定」 |
| not-configured | profile 是 FILL_ME | 同上，note=ORACLE_CONNECTION_NOT_CONFIGURED |
| reconnect-fail | list → connect（READY）→ 再 connect（假 MCP 從第 2 次起 isError）→ task… | 第二個 connect 的 before 列 state=READY→next=NEED_CONNECT、gen 依序 1～4、note=connect attempt invalidates READY…；只有第一個 connect 有 after；之後三次 task 全擋（NEED_CONNECT）、零 SQL；模型回報「DB 連線建立失敗」 |

取得 binary（沙箱）：`npm pack opencode-linux-x64@1.18.29` 解開後 `package/bin/opencode`。
e2e 每個情境約 10～30 秒（含臨時 XDG 目錄的首次初始化），serve 類約 30～35 秒；`--keep` 保留工作目錄（含 run.stdout／stderr、閘門 jsonl、export.json、mcp／model 紀錄）。
注意：OpenCode 用 `PWD` 環境變數決定專案目錄（run.ts），執行器已為子行程設定 `PWD`。
analyzer 交叉驗證：`--keep` 之後可用 PowerShell 以 AST 抽出 `Get-SessionVerdict`（同 test-auto-loop 情境 33 的做法）對每個情境的 jsonl＋export.json 判讀，
預期 observe 為 early=1／turnViol=1、mcp-down／mcp-failed 為 mcpDownBlocks=1、empty-connect 為 unknownResults=2、stale-connect-serve 為 staleReplies=1，其餘全 0 且 callMismatch 全 0。
