---
description: 對任一 PeopleSoft 業務領域產生完整文件（總覽＋逐功能深查，輸出 docs/ps-research/<領域>/；中斷後重跑即續跑）
agent: ps-deep-research
---
對業務領域「$ARGUMENTS」執行完整調查並產出文件。

**禁止複述計畫、禁止先解釋你將要做什麼——你的第一個回應必須是工具呼叫。
現在立刻開始：**

第一個動作：用 glob／read 檢查 `docs/ps-research/$ARGUMENTS/00-overview.md`
是否存在。

- **不存在** → 立刻執行系統提示的「階段一：盤點」——下一個動作是
  read `.opencode/peoplesoft/customization-profile.yaml`。
- **存在** → read 同目錄 `checklist.md`（沒有就先照系統提示做一次性
  遷移），立刻對**第一個未勾選項**執行「階段二：逐項深查」。

之後照系統提示流程逐項做到 checklist 全勾（含收尾自動稽核一輪——
本 run 有勾掉 A 項時必跑，90-audit.md 已存在不是跳過理由；
稽核新回灌的 A 項留給下一次 run）。
過程中只在「完成一項」或「遇到 BLOCKED」時簡短回報一行，其餘時間持續行動。
