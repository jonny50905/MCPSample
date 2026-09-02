---
description: 分批稽核（auto-loop 專用）：依 auto-loop-logs/<領域>/audit-manifest.txt 只稽核本批檔案／範圍，結果寫 audit-parts/
agent: ps-audit-orchestrator
---
對 `docs/ps-research/$ARGUMENTS/` 執行**一個稽核批次**。

**第一個回應必須是工具呼叫**：`read docs/ps-research/$ARGUMENTS/audit-parts/manifest.txt`
——那是外環產生的本批工單（目標輪次、旗標、檔案與 Evidence 範圍、
任務 B claims、領域任務、唯一可寫路徑）。照 manifest 做、只做 manifest
上的、只寫 manifest 指定的那一個 part 檔（見你 system prompt 的輸出格式）。

不得改 checklist.md、90-audit.md、任何 NN 檔——輪次遞增、A／D 回灌、
歸檔、報告合併全部由外環在你結束後執行。不得反問、不得婉拒。
**交付＝檔案，不是對話**：結束前必須 `write` manifest 指定的 part 檔並
`read` 回來確認；只在對話裡印出表格而沒有 write＝本批視同白做。
最終回覆只准一行「已寫 <路徑>」。
（$ARGUMENTS 應為單一領域目錄名；read 失敗且含空白時取第一個詞重試一次。）
