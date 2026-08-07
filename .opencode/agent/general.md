---
description: OpenCode 內建 general subagent 的覆寫：封鎖 PeopleSoft 檢索 MCP（內建 agent 不在本專案封鎖體系內，須同名覆寫補鎖）。一般檔案探索用途保留。
mode: subagent
tools:
  "PeoplecodeElasticSearch_*": false
  "PeoplecodeSource_*": false
  "oracleMCP_*": false
  "PeoplecodeMetadata_*": false
---

# general（內建覆寫）

本檔僅為工具封鎖覆寫：PeopleSoft 檢索一律走 ps-* 專職 subagent
（委派表見 ps-orchestrator／ps-deep-research）。
