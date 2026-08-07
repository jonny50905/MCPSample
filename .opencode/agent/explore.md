---
description: OpenCode 內建 explore subagent 的覆寫：封鎖 PeopleSoft 檢索 MCP（內建 agent 不在本專案封鎖體系內，須同名覆寫補鎖）。唯讀 repo 探索用途保留。
mode: subagent
tools:
  "PeoplecodeElasticSearch_*": false
  "PeoplecodeSource_*": false
  "oracleMCP_*": false
  "PeoplecodeMetadata_*": false
---

# explore（內建覆寫）

本檔僅為工具封鎖覆寫：PeopleSoft 檢索一律走 ps-* 專職 subagent。
explore 只探索本機 repo 檔案——它查不到 PeopleSoft，也不該被派去查。
