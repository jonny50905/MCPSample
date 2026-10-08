# 00 索引

> `clone-0123456789abcdef`｜版本 r0001｜整體狀態 **DRAFT**｜Component：TW_DEMO_APV、TW_DEMO_REQ
> 本檔由外環產生，是閱讀入口；規格內容以各文件為準。

## 閱讀順序

1. 16 AI 實作指引（怎麼讀、什麼不能做）
2. 01 專案概覽 → 04 流程與狀態機 → 02 功能需求
3. 07 資料設計 → 03 角色與權限 → 05 畫面與互動 → 09 業務邏輯 → 06 系統架構 → 08 操作契約
4. 14 測試與驗收 → 17 工作拆解 → 18 完成定義
5. 19 決策紀錄、90 問題清單（實作前確認沒有影響自己工作的未解問題）

## 文件與檢核

| 文件 | 狀態 | L1 | L2 | L3 | L4 | L5 | 摘要 |
|---|---|---|---|---|---|---|---|
| [01 專案概覽](01-overview.md) | in_review | PASS | PASS | PASS | PASS | NOT_APPLICABLE | 目標 1、決策責任 2、物件 23；未解問題 1 |
| [02 功能需求](02-functional-requirements.md) | in_review | PASS | PASS | PASS | PASS | PASS | 功能 5；未解問題 0 |
| [03 角色與權限](03-roles-permissions.md) | in_review | PASS | PASS | PASS | PASS | PASS | 角色 2、權限 2；未解問題 0 |
| [04 流程與狀態機](04-workflow.md) | in_review | PASS | PASS | PASS | PASS | PASS | 狀態 6、轉移 10、情境 4、活動 2；未解問題 0 |
| [05 畫面與互動](05-ui.md) | in_review | PASS | PASS | PASS | PASS | PASS | 畫面元件 13；未解問題 0 |
| [06 系統架構（技術中立）](06-architecture.md) | in_review | PASS | PASS | PASS | PASS | PASS | 介面 1；未解問題 0 |
| [07 資料設計](07-database.md) | in_review | PASS | PASS | PASS | PASS | PASS | 實體 3、欄位 19、衍生概念 2、不建置欄位組 1；未解問題 2 |
| [08 操作契約（API）](08-api.md) | in_review | PASS | PASS | PASS | PASS | PASS | 操作 5；未解問題 0 |
| [09 業務邏輯](09-business-logic.md) | in_review | PASS | PASS | PASS | PASS | PASS | 訊息 4、規則 6；未解問題 0 |
| [14 測試與驗收](14-testing.md) | draft | PASS | PASS | FAIL | PASS | NOT_APPLICABLE | 測試案例 14；未解問題 0 |
| [16 AI 實作指引](16-ai-instructions.md) | in_review | PASS | PASS | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | 條款 12 |
| [17 工作拆解與相依](17-tasks.md) | in_review | PASS | PASS | PASS | NOT_APPLICABLE | NOT_APPLICABLE | 工作項 6；未解問題 0 |
| [18 完成定義](18-definition-of-done.md) | in_review | PASS | PASS | PASS | NOT_APPLICABLE | NOT_APPLICABLE | 完成條件 7；未解問題 0 |
| [19 決策紀錄](19-decision-log.md) | in_review | PASS | PASS | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | 決策 1 |
| [90 問題清單](90-questions.md) | in_review | PASS | PASS | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | 問題 4（OPEN 2、ANSWERED 1、WITHDRAWN 1）；未解 BLOCKING 0；只計數的定義值 2 |

## 未通過的檢核

- 14-testing/L3：C07 TRN-005（015>090）沒有測試案例；C07 TRN-009（025>015）沒有測試案例

## ID 前綴對照

| 前綴 | 項目 | 定義所在 |
|---|---|---|
| `GOAL` | 專案目標 | [01 專案概覽](01-overview.md) |
| `RESP` | 決策責任 | [01 專案概覽](01-overview.md) |
| `OBJ` | 舊系統物件 | [01 專案概覽](01-overview.md) |
| `AI` | AI 指引條款 | [16 AI 實作指引](16-ai-instructions.md) |
| `ENT` | 資料實體 | [07 資料設計](07-database.md) |
| `FLD` | 資料欄位 | [07 資料設計](07-database.md) |
| `DRV` | 衍生概念 | [07 資料設計](07-database.md) |
| `XF` | 不建置原生欄位 | [07 資料設計](07-database.md) |
| `ROLE` | 角色 | [03 角色與權限](03-roles-permissions.md) |
| `PERM` | 權限 | [03 角色與權限](03-roles-permissions.md) |
| `STATE` | 狀態 | [04 流程與狀態機](04-workflow.md) |
| `TRN` | 狀態轉移 | [04 流程與狀態機](04-workflow.md) |
| `FLOW` | 情境流程 | [04 流程與狀態機](04-workflow.md) |
| `ACT` | 狀態活動 | [04 流程與狀態機](04-workflow.md) |
| `IF` | 介面／批次 | [06 系統架構（技術中立）](06-architecture.md) |
| `FR` | 功能需求 | [02 功能需求](02-functional-requirements.md) |
| `UI` | 畫面／元件 | [05 畫面與互動](05-ui.md) |
| `MSG` | 訊息 | [09 業務邏輯](09-business-logic.md) |
| `BR` | 業務規則 | [09 業務邏輯](09-business-logic.md) |
| `OP` | 操作契約 | [08 操作契約（API）](08-api.md) |
| `TC` | 測試案例 | [14 測試與驗收](14-testing.md) |
| `TASK` | 工作項 | [17 工作拆解與相依](17-tasks.md) |
| `DOD` | 完成條件 | [18 完成定義](18-definition-of-done.md) |
| `Q` | 問題 | [90 問題清單](90-questions.md) |
| `DEC` | 決策 | [19 決策紀錄](19-decision-log.md) |

## 追溯矩陣（以功能為列，外環反查產生）

| 功能 | 轉移 | 情境 | 元件 | 規則 | 操作 | 測試 | 工作 |
|---|---|---|---|---|---|---|---|
| FR-001 核准申請 | TRN-007、TRN-008、TRN-010 | FLOW-001、FLOW-004 | UI-002、UI-003、UI-004、UI-005 | — | OP-001 | TC-001、TC-002、TC-003、TC-004 | TASK-002 |
| FR-002 退回申請 | TRN-006、TRN-009 | FLOW-003 | UI-002、UI-003、UI-004、UI-006 | BR-005 | OP-002 | TC-005、TC-006 | TASK-003 |
| FR-003 建立申請 | TRN-001 | FLOW-001 | UI-008、UI-009、UI-010、UI-011 | BR-002、BR-003、BR-004 | OP-003 | TC-007、TC-008、TC-009、TC-010 | TASK-004 |
| FR-004 送出申請 | TRN-002、TRN-004 | FLOW-001、FLOW-003 | UI-008、UI-009、UI-010、UI-011、UI-012 | BR-001、BR-003、BR-006 | OP-004 | TC-011、TC-012、TC-013 | TASK-005 |
| FR-005 撤回申請 | TRN-003、TRN-005 | FLOW-002 | UI-010、UI-013 | BR-003 | OP-005 | TC-014 | TASK-006 |

## 問題摘要

- BLOCKING 未解：0
- 資訊類未解：2（圖外 HIGH 1、LOW 0；原生未使用分支 1）
- 已回答：1；已撤回：1
- 只計數的定義值：2

欄位統計：範圍內 Record 4；已判定 3；判不了 1（NO_TABLE 1）；不建置欄位 3（1 個 Record）
