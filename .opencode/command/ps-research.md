---
description: 對任一 PeopleSoft 業務領域產生完整文件（總覽＋逐功能深查，輸出 docs/ps-research/<領域>/；中斷後重跑即續跑）
agent: ps-deep-research
---
對業務領域「$ARGUMENTS」執行完整調查並產出文件：

1. 若 `docs/ps-research/$ARGUMENTS/00-overview.md` 不存在 → 先做階段一
   （盤點，產總覽與調查 checklist）。
2. 依總覽的「調查進度」checklist 逐項深查、逐項寫檔、逐項打勾，
   直到全部完成。
3. 本指令可重複執行：已有總覽時自動從第一個未勾選項續跑，
   不重查已完成項。
