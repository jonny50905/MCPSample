# tests/claude-code — Claude Code 版的真 CLI 端到端測試

給**維護 session 的沙箱**用（Linux；需要已登入的 `claude` CLI、node ≥ 22、pwsh）；**會花 API 費用，手動跑**。
不在搬運 manifest 內，公司機不必搬。日常的一致性與 hook／外環版本層測試是 `scripts/tests/test-claude-variant.ps1`（不花費用）。

| 檔 | 用途 |
|---|---|
| `run-e2e.mjs` | 建部署模擬目錄（scripts＋claude-code/* 去前綴）、掛假 MCP、標記信任，以真 `claude -p` 跑四情境：qa（`--agent ps-orchestrator` 問答：第 0 步 connect＝profile 值、主對話不直接檢索、委派只到 ps-* 子代理、hook 無誤擋）、cmd（錯的主代理下 `/ps-research` 只回提示不寫檔）、worker（`claude -p --agent ps-spec-worker "/ps-spec-batch …"` 只寫 fragment.md、工單外讀取被路徑 hook 擋）、plain（一般 session 可委派內建 Explore 做維護排錯） |
| `mock-source-mcp.mjs` | 假 PeoplecodeElasticSearch（`search_chunks`）／PeoplecodeSource（`get_chunks_details`、`get_file_structure`）；假 oracleMCP 共用 `tests/runtime-guard/mock-oracle-mcp.mjs` |

跑法：`PWSH=<pwsh 路徑> node tests/claude-code/run-e2e.mjs [--model haiku|sonnet] [--only qa,cmd,worker] [--keep]`
（hook 以 `powershell` 名稱呼叫，腳本會在臨時 PATH 放一個指向 pwsh 的連結；結束後從 `~/.claude.json` 移除臨時信任）。
