---
description: OpenCode 內建 scout subagent 的覆寫：封鎖 PeopleSoft 檢索 MCP（內建 agent 不在本專案封鎖體系內，須同名覆寫補鎖）。
mode: subagent
tools:
  # L46：tools map 是覆寫表——沒列＝預設開。內建 agent 的 bash/write
  # 也必須顯式封鎖（委派漏到內建時才不會執行 shell 或寫檔）
  bash: false
  write: false
  edit: false
  webfetch: false
  "PeoplecodeElasticSearch_*": false
  "PeoplecodeSource_*": false
  "oracleMCP_*": false
  "PeoplecodeMetadata_*": false
---

# scout（內建覆寫）

本檔僅為工具封鎖覆寫：PeopleSoft 檢索一律走 ps-* 專職 subagent。
