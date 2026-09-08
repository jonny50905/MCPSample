# tests/oracle-gate — Oracle 前置閘門（plugin）的沙箱測試組

給**維護 session 的沙箱**用（需要 node ≥ 22 與 OpenCode 1.18.29 binary）；不在搬運 manifest 內，
公司機不必搬。公司機的執行紀錄回歸請用 `scripts/tests/test-oracle-gate-runtime.ps1`（SOP-21）。

受測物：`.opencode/plugin/ps-oracle-preflight-gate.js`——主 agent 未依序完成
`oracleMCP_list_connections` → `oracleMCP_connect` 之前，會查 DB 的 subagent 委派（task）在執行前被擋下。

| 檔 | 用途 | 跑法 |
|---|---|---|
| `unit.test.mjs` | 狀態機單元測試（假 client；11 組：DB 判定／list→connect 順序／NOT_CONNECTED 退回與 disconnect／observe 模式／MCP 未掛載退讓與祖先 READY／連線 epoch（同行程別 session、跨行程改檔、disconnect）／mcp 狀態不快取／synthetic 訊息不重置／connect 交錯只有最後一個 READY／task 執行中送下一題的 after 列用入場快照／list 成功後 connect 失敗兩次退讓） | `node --test tests/oracle-gate/unit.test.mjs` |
| `mock-oracle-mcp.mjs` | 假 SQLcl MCP（stdio JSON-RPC；tools：list_connections／connect／run_sql／disconnect；未 connect 就 run_sql 回 not connected） | 由 e2e 的 opencode.json 啟動 |
| `mock-model.mjs` | 假 OpenAI 相容模型（SSE 串流），依「最後一則 user 訊息之後」的工具呼叫序列決定下一步；`MOCK_MODEL_SCENARIO`：task-first／connect-first／compliant／stubborn／nodb／epoch | 由 e2e 啟動 |
| `run-e2e.mjs` | 真 OpenCode（`OPENCODE_BIN` 或 PATH）＋假 MCP＋假模型跑 `opencode run --agent ps-orchestrator`，讀閘門 jsonl、`opencode export` 交叉比對，7 情境斷言 | `OPENCODE_BIN=<binary> node tests/oracle-gate/run-e2e.mjs [--repeat N] [--only <情境>] [--keep]` |

e2e 七情境與證明的事：

| 情境 | 模型劇本 | 證明 |
|---|---|---|
| task-first | 先 task → 被擋 → list → connect → task | 錯序被擋（transcript 該 task 件是 error、含 PS_ORACLE_PREFLIGHT_REQUIRED）、前置後放行、subagent SQL 在 connect 之後 |
| connect-first | 先 connect（跳過 list）→ task | connect 先於 list 不算（狀態留在 NEED_LIST），仍需 list→connect |
| compliant | list → connect → task | 照做不擋 |
| stubborn | 只會 task ×4 | 四次全擋、零 SQL、零 NOT_CONNECTED |
| nodb | 派 ps-peoplecode-flow | 不查 DB 的委派不受閘門影響（basis=run_sql:disabled） |
| observe | task-first＋`PS_ORACLE_GATE_MODE=observe` | 只記錄（observe-would-block），task 早於前置執行、subagent 回 NOT_CONNECTED——探測證據 |
| mcp-down | oracleMCP `enabled:false` | 閘門退讓（note=gate stands down: mcp-status:disabled） |
| multi-turn | 同 session 兩題，第二題 `opencode run --session <id>`（新行程） | 兩個 chat.message、turnId 不同；每題各自被擋→前置→放行；export 的 user 訊息＝2 |
| multi-turn-serve | `opencode serve` 同一行程對同一 session 連送兩題（HTTP API） | 第二則 chat.message 到來時 session 仍 READY，被重置為 NEED_LIST；兩題各自被擋→前置→放行（約 40 秒；serve 啟動後第一個請求可能掛住，執行器每個探測 20 秒逾時後重試，`serve.stdout.txt` 有 `[harness]` 計時行） |
| epoch | list → connect → 假模型改寫 connection-epoch.json（模擬另一行程 connect）→ task | 被擋且 note=shared connection changed、模型收到「共用的 Oracle 連線已被改動過（來源）」；重做 list→connect 後放行 |
| compaction-serve | 同 multi-turn-serve，但兩題之間 `POST /session/:id/summarize`（compaction） | export 有 3 則 user 訊息（其中 1 則只有 compaction part）、chat.message 只有 2 則且 id＝兩則真實題目；閘門與 analyzer 的題目比對不受 compaction 影響 |

取得 binary（沙箱）：`npm pack opencode-linux-x64@1.18.29` 解開後 `package/bin/opencode`。
e2e 每個情境約 15 秒（含臨時 XDG 目錄的首次初始化）；`--keep` 保留工作目錄（含 run.stdout／stderr、閘門 jsonl、mcp／model 紀錄）。
注意：OpenCode 用 `PWD` 環境變數決定專案目錄（run.ts），執行器已為子行程設定 `PWD`。
