---
description: OpenCode 內建 scout subagent 的覆寫：封鎖 PeopleSoft 檢索 MCP（內建 agent 不在本專案封鎖體系內，須同名覆寫補鎖）。
mode: subagent
tools:
  "PeoplecodeElasticSearch_*": false
  "PeoplecodeSource_*": false
  "oracleMCP_*": false
  "PeoplecodeMetadata_*": false
---

# scout（內建覆寫）

本檔僅為工具封鎖覆寫：PeopleSoft 檢索一律走 ps-* 專職 subagent。
