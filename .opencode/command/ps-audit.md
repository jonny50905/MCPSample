---
description: 稽核 deep-research 文件（證據解引用、claim 反駁抽驗、完整性 diff），產 90-audit.md 並把問題回灌調查 checklist
agent: ps-deep-research
---
對 `docs/ps-research/$ARGUMENTS/` 執行稽核模式（見你 system prompt 的
「稽核模式」章節）。

**禁止複述計畫——第一個回應必須是工具呼叫：先 read
`docs/ps-research/$ARGUMENTS/00-overview.md` 取得已完成項清單，
然後立刻委派第一個稽核任務。**

流程提要：

1. 逐一已完成檔案委派 ps-auditor 做證據解引用驗證（任務 A）；
   每檔抽 3~5 條標 CONFIRMED 的重要 claim 做反駁驗證（任務 B）。
2. 以總覽的核心資料表清單做換角度完整性盤點（任務 C），與功能地圖 diff。
3. 依 audit 模板產出 `90-audit.md` 記分卡。
4. DISPUTED / FAIL / 遺漏候選逐項回灌 `00-overview.md` 的調查進度
   （格式：`- [ ] A<n> 補查 <說明>（稽核）`）。
5. 出現系統性錯誤（同類 FAIL ≥ 2）→ 提議我執行 `/ps-lesson`。
