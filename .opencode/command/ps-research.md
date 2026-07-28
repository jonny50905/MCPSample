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

之後照系統提示流程逐項處理（**單次 run 至多 6 項**——達上限即停，
提示使用者開新 session 重跑續作）直到 checklist 全勾。收尾稽核規則：本 run
打勾 **≤ 5 項** → 當場自動接一輪稽核（90-audit.md 已存在不是跳過
理由）；**> 5 項** → 不當場稽核，結束時提示使用者開新 session 跑
/ps-audit（或重跑本指令——全勾狀態會自動接稽核）；
稽核新回灌的 A 項一律留給下一次 run。
過程中只在「完成一項」或「遇到 BLOCKED」時簡短回報一行，其餘時間持續行動。
