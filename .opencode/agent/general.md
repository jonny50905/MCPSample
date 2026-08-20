---
description: OpenCode 內建 general subagent 的覆寫：封鎖 PeopleSoft 檢索 MCP（內建 agent 不在本專案封鎖體系內，須同名覆寫補鎖）。一般檔案探索用途保留。
mode: subagent
tools:
  # L46：tools map 是覆寫表——沒列＝預設開。內建 agent 的 bash/write
  # 也必須顯式封鎖（委派漏到內建時才不會執行 shell 或寫檔）
  # 補鎖檔不得再委派（L66）：它們四個 MCP 全封＝零工具，若被誤派任務又能
  # 轉委派，就會在「自己做不到、再丟給別人」之間轉圈到逾時（實案：手術 session
  # 誤派 general 修 truncated chunk id，空轉 90 分）。ps-* subagent 全數 task:false，
  # 這三個內建覆寫檔漏了——沒列＝預設開（L1）。
  task: false
  bash: false
  write: false
  edit: false
  webfetch: false
  "PeoplecodeElasticSearch_*": false
  "PeoplecodeSource_*": false
  "oracleMCP_*": false
  "PeoplecodeMetadata_*": false
---

# general（內建覆寫）

本檔僅為工具封鎖覆寫：PeopleSoft 檢索一律走 ps-* 專職 subagent
（委派表見 ps-orchestrator／ps-deep-research）。
