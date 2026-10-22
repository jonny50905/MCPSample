# tests/runtime-guard — ps-runtime-guard（plugin）的沙箱測試組

給**維護 session 的沙箱**用（需要 node ≥ 22 與 OpenCode 1.18.29 binary）；不在搬運 manifest 內，
公司機不必搬。公司機的執行紀錄驗收請用 `scripts/tests/test-oracle-runtime.ps1`（SOP-21）。

受測物：`.opencode/plugin/ps-runtime-guard.js`——無狀態的小事，**沒有派工前置閘門、沒有 todo 閘門、沒有 READY／turn／世代狀態**。
oracleMCP＝@vdeserto/oracle-mcp-server：沒有 connect 工具，guard 不攔任何 oracleMCP_ 呼叫（只記錄）：

1. task 目標檢查：`subagent_type` 是 `.opencode/skills/<名>` 而不是 `.opencode/agent/<名>.md` → `PS_TASK_TARGET_INVALID`
   （訊息指出承載 agent）；task 回覆的報告 `suggestedNext[].agent` 是 skill 名或不存在的 agent → 回覆末尾附 `[ps-runtime-guard]` 註記。
2. oracleMCP 診斷與受控重掛（預設 off）：`mcp.tools.changed` 事件、/mcp 狀態快照、模型呼叫看不到的工具（invalid）、工具 part 錯誤的遮罩摘要；
   自動重掛只在 host 證據（狀態 failed、或先前執行過的工具對允許它的 agent 變成 invalid）觸發、每個故障事件一次、在途呼叫先等、
   disabled／needs_auth 不碰、失敗即停、恢復後在下一次回覆附註要先以 `SELECT 1 AS OK FROM DUAL` 驗證。

| 檔 | 用途 | 跑法 |
|---|---|---|
| `unit.test.mjs` | 單元測試（假 client；10 組）：oracleMCP 呼叫只記錄不擋、回覆三態（`Error:` 開頭＝ok:false）／沒有派工閘門（task 一律放行、列上沒有 state）／skill 名擋下並指出承載 agent／報告解析與 suggestedNext 附註／chat.message 只記錄／診斷（auto off：would-remount、catalog suspect、part error 遮罩）／invalid 呼叫三種判讀（錯名、權限過濾、目錄遺失）／受控重掛（auto on：一次 disconnect+connect、恢復附註每 session 一次、verified-by-call）／邊界（同時多證據只一次、未驗證再故障＝失敗、失敗後 suppressed、disabled／needs_auth／absent 不重掛、在途先等）／載入紀錄與 wildcardDenyMix WARN | `node --test tests/runtime-guard/unit.test.mjs` |
| `mock-oracle-mcp.mjs` | 假 oracleMCP（仿 @vdeserto/oracle-mcp-server 1.0.0；stdio JSON-RPC；五個工具同名；`oracle_execute_query` 照真 server 的送出前檢查拒絕分號／註解／DML 字等，回葡萄牙文 `Error:`；成功回 markdown 表格）。`MOCK_ORACLE_DB_DOWN=1`／`MOCK_ORACLE_DB_DOWN_CALLS=N`＝查詢回 `Error: Database query failed.`；故障注入（配合 `MOCK_ORACLE_FAULT_MARKER` 只注入一次）：`MOCK_ORACLE_VANISH_AFTER_CALLS=N`（第 N 次呼叫後送 tools/list_changed、之後工具目錄為空）、`MOCK_ORACLE_EXIT_AFTER_CALLS=N`（第 N 次呼叫後行程結束＝transport 關閉） | 由 e2e 的 opencode.json 啟動 |
| `mock-model.mjs` | 假 OpenAI 相容模型（SSE 串流），依「最後一則 user 訊息之後」的工具呼叫序列決定下一步；`MOCK_MODEL_SCENARIO`：compliant／redispatch-once／nodb／stale-connect／skill-as-agent／suggested-skill／down-aware／down-probe；subagent 劇本：委派 prompt 含 [DB] 才查、`Database query failed` 就送 `SELECT 1 AS OK FROM DUAL` 判連線；每次請求記下可見的 task／oracleMCP_ 工具名（驗允許清單與工具消失） | 由 e2e 啟動 |
| `run-e2e.mjs` | 真 OpenCode（`OPENCODE_BIN` 或 PATH）＋假 MCP＋假模型跑 `opencode run --agent ps-orchestrator`（或 `opencode serve` 同行程多 session、兩個 host），讀 guard 的 jsonl／`_mcp-diag.jsonl`、`opencode export` 交叉比對，12 情境斷言 | `OPENCODE_BIN=<binary> node tests/runtime-guard/run-e2e.mjs [--repeat N] [--only <情境>] [--keep]` |

e2e 十二情境（每個 session 都另斷言：紀錄列沒有 state／next／turnId／gen；guard 看到的 task 次數＝export 的 task 件數；
chat.message 的 messageID 集合＝export 真實題目 id 集合；task before 列的 messageID＝export 該 tool part 所屬 assistant 訊息的 parentID；
使用者訊息沒有任何 synthetic part；正向情境驗 DB task 列 reportStatus=COMPLETE、childSessionID 指向子 session 且子 session jsonl 有 oracle_execute_query ok:true）：

| 情境 | 劇本 | 證明 |
|---|---|---|
| compliant | task → subagent 查詢 | 零擋；mcp 只有一次 oracle_execute_query（沒有 connect）；主 agent 看不到任何 oracleMCP_ 工具、subagent 只見 oracle_execute_query；紀錄列沒有 connect 目標欄位 |
| db-flaky | DB 前兩次查詢失敗 | subagent 業務查詢＋`SELECT 1 AS OK FROM DUAL` 都回 `Error: Database query failed.` → BLOCKED(NOT_CONNECTED) → 主 agent 重派一次 → COMPLETE；失敗的那次子 session 兩列 ok:false；零 recovery |
| db-down | DB 一直連不上 | NOT_CONNECTED → 重派一次 → 又 NOT_CONNECTED → 回報「DB 連線失敗…SOP-21」、不再派；四次查詢（兩次探測）；零 recovery |
| nodb | 派 ps-peoplecode-flow | dbCapable=false（basis execute_query:disabled）只是紀錄；零 mcp 呼叫；COMPLETE |
| stale-connect | 主 agent 憑記憶呼叫舊的 oracleMCP_connect | OpenCode 判 invalid、guard 記「多半是錯名」（seenBefore=false）、不擋不重掛；照常完成 |
| mcp-down／mcp-failed | oracleMCP enabled:false／指令不存在 | 沒有 agent 看得到 oracleMCP_ 工具；subagent 回 ORACLE_MCP_DOWN、主 agent 不重派、回報 DOWN；零 invalid（不猜名）；零 mcp 呼叫 |
| skill-as-agent | task(ps-security-flow) → 改派 ps-metadata-flow | 第一個 task 件 error 含 PS_TASK_TARGET_INVALID＋ps-metadata-flow＋SKILL.md 路徑、不含 ORACLE_MCP_DOWN；guard 列 decision=block note=PS_TASK_TARGET_INVALID:skill carrier=ps-metadata-flow；第二個 task COMPLETE；沒有 recovery |
| suggested-skill | subagent 報告 suggestedNext 帶 ps-security-flow | 第一個 task 列 suggestedNextInvalid；task 回覆末尾（export 的 tool output）有 `[ps-runtime-guard]` 註記指出 ps-metadata-flow；主 agent 改派 ps-metadata-flow，從未派 ps-security-flow |
| vanish-auto（serve，auto on，host A＋B） | A1 正常後假 MCP 目錄變空（list_changed）；A2 新 session 的 subagent 看不到工具、憑記憶呼叫查詢 → invalid；A3 新 session | diag：event tools.changed、snapshot connected、catalog suspect、invalid-tool（seenBefore=true）、recovery [remount-start, remount-ok, verified-by-call]；假 MCP 起過兩次；A2 subagent 回 DOWN、主 agent 不重派；A3 恢復、第一個查詢回覆附「恢復世代 1…SELECT 1 AS OK FROM DUAL」註記；host B 兩題都 COMPLETE、只掛載一次、零 recovery |
| vanish-observe（serve，auto off） | 同上 | recovery 列只有 would-remount；假 MCP 只起一次；A3 仍看不到工具、回報 DOWN |
| transport-close（serve，auto on） | 假 MCP 行程結束（狀態 failed: Connection closed） | 事件觸發：recovery [transport-closed remount-start, remount-ok, verified-by-call]；假 MCP 起過兩次；A2 新 session 恢復、零 invalid、查詢回覆附註 |

另外兩支 smoke（同樣是真 OpenCode＋localhost 劇本模型、不連 MCP，與 plugin 無關）：

| 檔 | 驗什麼 | 跑法 |
|---|---|---|
| `run-clone-smoke.mjs` | `/ps-spec`（ps-spec-author）只准 `powershell -NoProfile -File scripts/ps-sdoc.ps1 -Cli opencode …`（舊的 ps-spec-build 與漏了 `-Cli opencode` 的命令都擋）、`-Status` 回 DOC1-0-01；`/ps-clone-batch`（ps-clone-worker）只寫 packet.json | `OPENCODE_BIN=<binary> node tests/runtime-guard/run-clone-smoke.mjs` |
| `run-sdoc-smoke.mjs` | Spec 文件外環的四個 agent（ps-status-reader／ps-sdoc-worker／ps-spec-reader／ps-spec-judge）照外環的叫法 `opencode run --agent <名> --model <model> "<jobId>/<attemptId>"` 啟動：沒有退回預設 agent、回覆來自 `--model`；read／write 權限只放行工單範圍（讀者讀不到 attempt 的標準答案與研究、只寫 inbox/output.json，狀態圖讀者只寫 output-part-NN.json／output.json）；看得到的工具（讀者與判定只有 read／write＋共用 edit 權限的 edit）；`OPENCODE_DISABLE_CLAUDE_CODE=1` 時不載入 `~/.claude/CLAUDE.md`；專案是 git repo、`.ps-runtime/`／`.ps-private/` 在 .gitignore 裡照樣讀寫 | `OPENCODE_BIN=<binary> node tests/runtime-guard/run-sdoc-smoke.mjs` |

取得 binary（沙箱）：`npm pack opencode-linux-x64@1.18.29` 解開後 `package/bin/opencode`。PATH 上要有 `powershell`（沙箱用 pwsh 的同名連結）。
e2e 每個 run 類情境約 12～30 秒（含臨時 XDG 目錄的首次初始化），serve 類 35～80 秒；`--keep` 保留工作目錄
（含 run.stdout／stderr、guard jsonl、`_mcp-diag.jsonl`、export.json、mcp／model 紀錄）。
注意：OpenCode 用 `PWD` 環境變數決定專案目錄（run.ts），執行器已為子行程設定 `PWD`；`serve` 啟動後第一個請求可能掛住（執行器 20 秒逾時重試）。
analyzer 交叉驗證：`--keep` 之後可用 PowerShell 以 AST 抽出 `Get-SessionVerdict`（同 test-auto-loop 情境 33 的做法）對每個情境的 jsonl＋export.json 判讀，
預期 db-flaky 為 notConnectedReports=1／redispatches=1／redispatchLoops=0、db-down 為 notConnectedReports=2／redispatchLoops=0、skill-as-agent 為 routingBlocks=1、
suggested-skill 為 suggestedNextInvalid=1、stale-connect 為 oldToolCalls=1、vanish 類的 A2 子 session 為 invalidOracleCalls=1，其餘 0。
