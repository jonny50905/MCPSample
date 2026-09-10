# tests/runtime-guard — ps-runtime-guard（plugin）的沙箱測試組

給**維護 session 的沙箱**用（需要 node ≥ 22 與 OpenCode 1.18.29 binary）；不在搬運 manifest 內，
公司機不必搬。公司機的執行紀錄驗收請用 `scripts/tests/test-oracle-runtime.ps1`（SOP-21）。

受測物：`.opencode/plugin/ps-runtime-guard.js`——三件無狀態的小事，**沒有派工前置閘門、沒有 todo 閘門、沒有 READY／turn／世代狀態**：

1. connect 目標 guard：`oracleMCP_connect` 執行前比對本次 `connection_name` 與 profile `oracle.connectionName`
   （未填／FILL_ME → `ORACLE_CONNECTION_NOT_CONFIGURED`；不一致 → `ORACLE_CONNECTION_MISMATCH`；throw、工具不執行、不改參數）。
2. task 目標檢查：`subagent_type` 是 `.opencode/skills/<名>` 而不是 `.opencode/agent/<名>.md` → `PS_TASK_TARGET_INVALID`
   （訊息指出承載 agent）；task 回覆的報告 `suggestedNext[].agent` 是 skill 名或不存在的 agent → 回覆末尾附 `[ps-runtime-guard]` 註記。
3. oracleMCP 診斷與受控重掛（預設 off）：`mcp.tools.changed` 事件、/mcp 狀態快照、模型呼叫看不到的工具（invalid）、工具 part 錯誤的遮罩摘要；
   自動重掛只在 host 證據（狀態 failed、或先前執行過的工具對允許它的 agent 變成 invalid）觸發、每個故障事件一次、在途呼叫先等、
   disabled／needs_auth 不碰、失敗即停、恢復後在下一次回覆附註要重新 connect 與 `SELECT 1 FROM DUAL`。

| 檔 | 用途 | 跑法 |
|---|---|---|
| `unit.test.mjs` | 單元測試（假 client；10 組）：connect 目標 guard 三種擋法＋observe＋ORA 引文不算失敗／沒有派工閘門（task 在 connect 前一律放行、列上沒有 state）／skill 名擋下並指出承載 agent／報告解析與 suggestedNext 附註／chat.message 只記錄／診斷（auto off：would-remount、catalog suspect、part error 遮罩）／invalid 呼叫三種判讀（錯名、權限過濾、目錄遺失）／受控重掛（auto on：一次 disconnect+connect、恢復附註每 session 一次、verified-by-call）／邊界（同時多證據只一次、未驗證再故障＝失敗、失敗後 suppressed、disabled／needs_auth／absent 不重掛、在途先等）／載入紀錄與 wildcardDenyMix WARN | `node --test tests/runtime-guard/unit.test.mjs` |
| `mock-oracle-mcp.mjs` | 假 SQLcl MCP（stdio JSON-RPC；tools：list_connections／connect／sql_run／disconnect；清單仿真 SQLcl 的黏合格式；未 connect 就 sql_run 回 not connected）。故障注入（配合 `MOCK_ORACLE_FAULT_MARKER` 只注入一次）：`MOCK_ORACLE_VANISH_AFTER_CALLS=N`（第 N 次呼叫後送 tools/list_changed、之後工具目錄為空）、`MOCK_ORACLE_EXIT_AFTER_CALLS=N`（第 N 次呼叫後行程結束＝transport 關閉）；另有 `MOCK_ORACLE_CONNECT_FAIL`／`_FAIL_FROM`／`_EMPTY_CONNECT`／`_CONNECT_DELAY_FIRST_MS` | 由 e2e 的 opencode.json 啟動 |
| `mock-model.mjs` | 假 OpenAI 相容模型（SSE 串流），依「最後一則 user 訊息之後」的工具呼叫序列決定下一步；`MOCK_MODEL_SCENARIO`：compliant／task-first／nodb／connect-fail／skill-as-agent／suggested-skill／down-aware／down-probe；每次請求記下可見的 task／oracleMCP_ 工具名（驗允許清單與工具消失） | 由 e2e 啟動 |
| `run-e2e.mjs` | 真 OpenCode（`OPENCODE_BIN` 或 PATH）＋假 MCP＋假模型跑 `opencode run --agent ps-orchestrator`（或 `opencode serve` 同行程多 session、兩個 host），讀 guard 的 jsonl／`_mcp-diag.jsonl`、`opencode export` 交叉比對，13 情境斷言 | `OPENCODE_BIN=<binary> node tests/runtime-guard/run-e2e.mjs [--repeat N] [--only <情境>] [--keep]` |

e2e 十三情境（每個 session 都另斷言：紀錄列沒有 state／next／turnId／gen；guard 看到的 task 次數＝export 的 task 件數；
chat.message 的 messageID 集合＝export 真實題目 id 集合；task before 列的 messageID＝export 該 tool part 所屬 assistant 訊息的 parentID；
使用者訊息沒有任何 synthetic part；正向情境驗 DB task 列 reportStatus=COMPLETE、childSessionID 指向子 session 且子 session jsonl 有 sql_run ok:true）：

| 情境 | 劇本 | 證明 |
|---|---|---|
| compliant | connect → task | 零擋；mcp 順序 connect、sql_run；connect before 列 decision=allow、connection＝profileConnection＝HR_DEV；主 agent 只見 list_connections＋connect、subagent 只見 sql_run |
| task-first | 先 task（DB 未連）→ subagent 回 NOT_CONNECTED → connect 一次 → 重派 → COMPLETE | 沒有派工閘門（task 不被擋）；mcp 順序 sql_run（未連）、connect、sql_run；task 列 [BLOCKED NOT_CONNECTED, COMPLETE]；只有一次 connect（不迴圈）；NOT_CONNECTED 不觸發 recovery |
| nodb | 派 ps-peoplecode-flow | dbCapable=false 只是紀錄；零 mcp 呼叫；COMPLETE |
| connect-fail | connect 一律 isError | connect ×2 → list ×1 → 回報「DB 連線建立失敗」＋清單原文；零 task；part-error 列 2；ORA／TNS 錯誤不是重掛證據（零 recovery 列） |
| wrong-target／not-configured | profile HR_UAT 對 connect(HR_DEV)／profile FILL_ME | connect 執行前被擋（before 列 decision=block、note=錯誤碼）、假 MCP 零呼叫、tool part 是 error 帶錯誤碼、模型回報設定錯誤、零 task |
| mcp-down／mcp-failed | oracleMCP enabled:false／指令不存在 | 主 agent 看不到 oracleMCP_ 工具；模型回報 ORACLE_MCP_DOWN、零 connect、零 invalid（不猜名）、零 task |
| skill-as-agent | connect → task(ps-security-flow) → 改派 ps-metadata-flow | 第一個 task 件 error 含 PS_TASK_TARGET_INVALID＋ps-metadata-flow＋SKILL.md 路徑、不含 ORACLE_MCP_DOWN；guard 列 decision=block note=PS_TASK_TARGET_INVALID:skill carrier=ps-metadata-flow；第二個 task COMPLETE；路由錯誤沒有多 connect、沒有 recovery |
| suggested-skill | subagent 報告 suggestedNext 帶 ps-security-flow | 第一個 task 列 suggestedNextInvalid；task 回覆末尾（export 的 tool output）有 `[ps-runtime-guard]` 註記指出 ps-metadata-flow；主 agent 改派 ps-metadata-flow，從未派 ps-security-flow |
| vanish-auto（serve，auto on，host A＋B） | A1 正常後假 MCP 目錄變空（list_changed）；A2 新 session 看不到工具、模型憑記憶呼叫 connect → invalid；A3 新 session | diag：event tools.changed、snapshot connected、catalog suspect、invalid-tool（seenBefore=true、allowedByAgent=true）、recovery [remount-start, remount-ok, verified-by-call]；假 MCP 起過兩次（不同 pid）；A2 第一個請求零 oracle 工具、模型回報 DOWN 不重試；A3 恢復、第一個 oracleMCP 回覆附「恢復世代 1」註記；host B 兩題都 COMPLETE、只掛載一次、零 recovery |
| vanish-observe（serve，auto off） | 同上 | recovery 列只有 would-remount；假 MCP 只起一次；A3 仍看不到工具、模型回報 DOWN |
| transport-close（serve，auto on） | 假 MCP 行程結束（狀態 failed: Connection closed） | 事件觸發：recovery [transport-closed remount-start, remount-ok, verified-by-call]；假 MCP 起過兩次；A2 新 session 恢復、零 invalid、connect 回覆附註 |

取得 binary（沙箱）：`npm pack opencode-linux-x64@1.18.29` 解開後 `package/bin/opencode`。
e2e 每個 run 類情境約 12～30 秒（含臨時 XDG 目錄的首次初始化），serve 類 35～80 秒；`--keep` 保留工作目錄
（含 run.stdout／stderr、guard jsonl、`_mcp-diag.jsonl`、export.json、mcp／model 紀錄）。
注意：OpenCode 用 `PWD` 環境變數決定專案目錄（run.ts），執行器已為子行程設定 `PWD`；`serve` 啟動後第一個請求可能掛住（執行器 20 秒逾時重試）。
analyzer 交叉驗證：`--keep` 之後可用 PowerShell 以 AST 抽出 `Get-SessionVerdict`（同 test-auto-loop 情境 33 的做法）對每個情境的 jsonl＋export.json 判讀，
預期 task-first 為 notConnectedReports=1／reconnects=1／reconnectLoops=0、skill-as-agent 為 routingBlocks=1、suggested-skill 為 suggestedNextInvalid=1、
wrong-target／not-configured 為 connectBlocks≥1、vanish 類的 A2 為 invalidOracleCalls=1，其餘 0。
