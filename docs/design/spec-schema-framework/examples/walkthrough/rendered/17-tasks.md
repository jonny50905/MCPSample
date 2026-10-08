# 17 工作拆解與相依

> `clone-0123456789abcdef/17`｜版本 r0001｜狀態 **in_review**｜L1 PASS · L2 PASS · L3 PASS · L4 NOT_APPLICABLE · L5 NOT_APPLICABLE
> 依賴文件：02、03、04、05、07、08、09、14｜未解問題：無
> 工作項 6；未解問題 0
> 本檔由 canonical JSON 以程式產生，請勿手改；修改走研究重跑或 19 的決策。

## 建議順序

| 順序 | 工作 | 依賴 |
|---|---|---|
| 1 | TASK-001 資料結構、衍生概念與角色權限 | — |
| 2 | TASK-004 建立申請 | TASK-001 |
| 3 | TASK-005 送出申請 | TASK-001、TASK-004 |
| 4 | TASK-006 撤回申請 | TASK-001、TASK-004 |
| 5 | TASK-002 核准申請 | TASK-001、TASK-005 |
| 6 | TASK-003 退回申請 | TASK-001、TASK-005 |

## 工作項（TASK）

### TASK-001　資料結構、衍生概念與角色權限

- 自然鍵：`FOUNDATION:DATA_AND_SECURITY`
- 工作種類：FOUNDATION
- 對應功能：不適用：基礎工作，不對應單一功能
- 工作名稱：資料結構、衍生概念與角色權限
- 建議順序：1
- 前置工作：（無）
- 本工作涵蓋的項目：
  - 實體：ENT-001（TW_DEMO_DEPT）、ENT-002（TW_DEMO_EMP）、ENT-003（TW_DEMO_REQHDR）
  - 欄位：
    - FLD-001（TW_DEMO_DEPT.DEPTID）
    - FLD-002（TW_DEMO_DEPT.EFFDT）
    - FLD-003（TW_DEMO_DEPT.EFF_STATUS）
    - FLD-004（TW_DEMO_DEPT.MANAGER_ID）
    - FLD-005（TW_DEMO_EMP.DEPTID）
    - FLD-006（TW_DEMO_EMP.EFFDT）
    - FLD-007（TW_DEMO_EMP.EFF_STATUS）
    - FLD-008（TW_DEMO_EMP.EMPLID）
    - FLD-009（TW_DEMO_EMP.SUPERVISOR_ID）
    - FLD-010（TW_DEMO_REQHDR.AMOUNT）
    - FLD-011（TW_DEMO_REQHDR.APPROVER_EMPLID）
    - FLD-012（TW_DEMO_REQHDR.APPROVE_DT）
    - FLD-013（TW_DEMO_REQHDR.COMMENTS）
    - FLD-014（TW_DEMO_REQHDR.REASON）
    - FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID）
    - FLD-016（TW_DEMO_REQHDR.REQ_ID）
    - FLD-017（TW_DEMO_REQHDR.REQ_STATUS）
    - FLD-018（TW_DEMO_REQHDR.REQ_TYPE）
    - FLD-019（TW_DEMO_REQHDR.SUBMIT_DT）
  - 衍生概念：DRV-001（申請人的部門主管）、DRV-002（申請人的直屬主管）
  - 角色：ROLE-001（審核主管）、ROLE-002（申請人）
- 交付物：DATA_STRUCTURE、SECURITY
- 來源：外環計算
- 被引用（外環反查）：TASK-002、TASK-003、TASK-004、TASK-005、TASK-006；DOD-002

### TASK-002　核准申請

- 自然鍵：`SLICE:TW_DEMO_APV:APPROVE`
- 工作種類：SLICE
- 對應功能：FR-001（核准申請）
- 工作名稱：核准申請
- 建議順序：5
- 前置工作：TASK-001（資料結構、衍生概念與角色權限）、TASK-005（送出申請）
- 本工作涵蓋的項目：
  - 欄位：
    - FLD-010（TW_DEMO_REQHDR.AMOUNT）
    - FLD-011（TW_DEMO_REQHDR.APPROVER_EMPLID）
    - FLD-012（TW_DEMO_REQHDR.APPROVE_DT）
    - FLD-013（TW_DEMO_REQHDR.COMMENTS）
    - FLD-014（TW_DEMO_REQHDR.REASON）
    - FLD-016（TW_DEMO_REQHDR.REQ_ID）
    - FLD-017（TW_DEMO_REQHDR.REQ_STATUS）
  - 衍生概念：DRV-001（申請人的部門主管）、DRV-002（申請人的直屬主管）
  - 角色：ROLE-001（審核主管）
  - 轉移：TRN-008（020→030）、TRN-007（020→025）、TRN-010（025→030）
  - 活動：ACT-001（直屬主管審核申請）、ACT-002（部門主管審核高額申請）
  - 元件：UI-002（金額）、UI-003（審核意見）、UI-004（申請事由）、UI-005（核准）
  - 規則：（無）
  - 操作：OP-001（核准申請）
  - 測試：TC-001（金額剛好 50000 時一次核准）、TC-002（金額 50000.01 時轉部門主管）、TC-003（具審核角色但不是直屬主管者看不到申請單）、TC-004（高額案件兩段核准）
- 交付物：OPERATIONS、SCREENS、RULES、TESTS
- 來源：外環計算
- 被引用（外環反查）：DOD-003

### TASK-003　退回申請

- 自然鍵：`SLICE:TW_DEMO_APV:RETURN`
- 工作種類：SLICE
- 對應功能：FR-002（退回申請）
- 工作名稱：退回申請
- 建議順序：6
- 前置工作：TASK-001（資料結構、衍生概念與角色權限）、TASK-005（送出申請）
- 本工作涵蓋的項目：
  - 欄位：FLD-010（TW_DEMO_REQHDR.AMOUNT）、FLD-013（TW_DEMO_REQHDR.COMMENTS）、FLD-014（TW_DEMO_REQHDR.REASON）、FLD-016（TW_DEMO_REQHDR.REQ_ID）、FLD-017（TW_DEMO_REQHDR.REQ_STATUS）
  - 衍生概念：DRV-001（申請人的部門主管）、DRV-002（申請人的直屬主管）
  - 角色：ROLE-001（審核主管）
  - 轉移：TRN-006（020→015）、TRN-009（025→015）
  - 活動：ACT-001（直屬主管審核申請）、ACT-002（部門主管審核高額申請）
  - 元件：UI-002（金額）、UI-003（審核意見）、UI-004（申請事由）、UI-006（退回）
  - 規則：BR-005（退回時必須填寫審核意見）
  - 操作：OP-002（退回申請）
  - 測試：TC-005（未填意見不能退回）、TC-006（填寫意見後退回）
- 交付物：OPERATIONS、SCREENS、RULES、TESTS
- 來源：外環計算
- 被引用（外環反查）：DOD-004

### TASK-004　建立申請

- 自然鍵：`SLICE:TW_DEMO_REQ:CREATE`
- 工作種類：SLICE
- 對應功能：FR-003（建立申請）
- 工作名稱：建立申請
- 建議順序：2
- 前置工作：TASK-001（資料結構、衍生概念與角色權限）
- 本工作涵蓋的項目：
  - 欄位：
    - FLD-010（TW_DEMO_REQHDR.AMOUNT）
    - FLD-014（TW_DEMO_REQHDR.REASON）
    - FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID）
    - FLD-016（TW_DEMO_REQHDR.REQ_ID）
    - FLD-017（TW_DEMO_REQHDR.REQ_STATUS）
    - FLD-018（TW_DEMO_REQHDR.REQ_TYPE）
  - 衍生概念：（無）
  - 角色：ROLE-002（申請人）
  - 轉移：TRN-001（新建→010）
  - 元件：UI-008（金額）、UI-009（申請事由）、UI-010（狀態）、UI-011（申請類別）
  - 規則：BR-002（新單取號）、BR-003（金額必須大於 0）、BR-004（申請人預設為目前使用者）
  - 操作：OP-003（儲存新申請單）
  - 測試：TC-007（金額 0.01 可建立）、TC-008（金額 0 不能建立）、TC-009（建立草稿）、TC-010（主流程：建立、送出、核准）
- 交付物：OPERATIONS、SCREENS、RULES、TESTS
- 來源：外環計算
- 被引用（外環反查）：TASK-005、TASK-006；DOD-005

### TASK-005　送出申請

- 自然鍵：`SLICE:TW_DEMO_REQ:SUBMIT`
- 工作種類：SLICE
- 對應功能：FR-004（送出申請）
- 工作名稱：送出申請
- 建議順序：3
- 前置工作：TASK-001（資料結構、衍生概念與角色權限）、TASK-004（建立申請）
- 本工作涵蓋的項目：
  - 欄位：
    - FLD-010（TW_DEMO_REQHDR.AMOUNT）
    - FLD-014（TW_DEMO_REQHDR.REASON）
    - FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID）
    - FLD-016（TW_DEMO_REQHDR.REQ_ID）
    - FLD-017（TW_DEMO_REQHDR.REQ_STATUS）
    - FLD-018（TW_DEMO_REQHDR.REQ_TYPE）
    - FLD-019（TW_DEMO_REQHDR.SUBMIT_DT）
  - 衍生概念：DRV-002（申請人的直屬主管）
  - 角色：ROLE-002（申請人）
  - 轉移：TRN-002（010→020）、TRN-004（015→020）
  - 元件：UI-008（金額）、UI-009（申請事由）、UI-010（狀態）、UI-011（申請類別）、UI-012（送出）
  - 規則：BR-001（送出後通知直屬主管）、BR-003（金額必須大於 0）、BR-006（送出時申請人必須有直屬主管）
  - 操作：OP-004（送出申請）
  - 測試：TC-011（沒有直屬主管不能送出）、TC-012（退回後補件重新送出）、TC-013（草稿送出）
- 交付物：OPERATIONS、SCREENS、RULES、TESTS
- 來源：外環計算
- 被引用（外環反查）：TASK-002、TASK-003；DOD-006

### TASK-006　撤回申請

- 自然鍵：`SLICE:TW_DEMO_REQ:WITHDRAW`
- 工作種類：SLICE
- 對應功能：FR-005（撤回申請）
- 工作名稱：撤回申請
- 建議順序：4
- 前置工作：TASK-001（資料結構、衍生概念與角色權限）、TASK-004（建立申請）
- 本工作涵蓋的項目：
  - 欄位：FLD-010（TW_DEMO_REQHDR.AMOUNT）、FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID）、FLD-016（TW_DEMO_REQHDR.REQ_ID）、FLD-017（TW_DEMO_REQHDR.REQ_STATUS）
  - 衍生概念：（無）
  - 角色：ROLE-002（申請人）
  - 轉移：TRN-003（010→090）、TRN-005（015→090）
  - 元件：UI-010（狀態）、UI-013（撤回）
  - 規則：BR-003（金額必須大於 0）
  - 操作：OP-005（撤回申請）
  - 測試：TC-014（撤回草稿）
- 交付物：OPERATIONS、SCREENS、RULES、TESTS
- 來源：外環計算
- 被引用（外環反查）：DOD-007
