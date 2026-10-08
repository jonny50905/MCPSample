# 03 角色與權限

> `clone-0123456789abcdef/03`｜版本 r0001｜狀態 **in_review**｜L1 PASS · L2 PASS · L3 PASS · L4 PASS · L5 PASS
> 依賴文件：01、07｜未解問題：無
> 角色 2、權限 2；未解問題 0
> 本檔由 canonical JSON 以程式產生，請勿手改；修改走研究重跑或 19 的決策。

## 角色（ROLE）

### ROLE-001　審核主管

- 自然鍵：`ROLE:TW_DEMO_APPROVER`
- 主體型別：ROLE
- 對應的原系統物件：OBJ-020（TW_DEMO_APPROVER）
- 業務名稱：審核主管
- 使用者如何取得此角色：
  - 種類：STATIC_ASSIGNMENT
  - 說明：由系統管理者指派給擔任主管的人；指派作業不在本功能範圍。
- 來源：metadata；證據 EV-0008
- 被引用（外環反查）：PERM-001；TRN-006、TRN-007、TRN-008、TRN-009、TRN-010；FR-001、FR-002；OP-001、OP-002；TC-003；TASK-001、TASK-002、TASK-003

### ROLE-002　申請人

- 自然鍵：`ROLE:TW_DEMO_REQUESTER`
- 主體型別：ROLE
- 對應的原系統物件：OBJ-021（TW_DEMO_REQUESTER）
- 業務名稱：申請人
- 使用者如何取得此角色：
  - 種類：STATIC_ASSIGNMENT
  - 說明：一般員工皆有；指派作業不在本功能範圍。
- 來源：metadata；證據 EV-0008
- 被引用（外環反查）：PERM-002；TRN-001、TRN-002、TRN-003、TRN-004、TRN-005；FR-003、FR-004、FR-005；OP-003、OP-004、OP-005；TASK-001、TASK-004、TASK-005、TASK-006

## 權限（PERM）

### PERM-001　ROLE:TW_DEMO_APPROVER>COMPONENT:TW_DEMO_APV

- 自然鍵：`ROLE:TW_DEMO_APPROVER>COMPONENT:TW_DEMO_APV`
- 權限主體：ROLE-001（審核主管）
- 受控資源（Component／Page／程序）：OBJ-002（TW_DEMO_APV）
- 允許的動作：UPDATE_DISPLAY
- 資料範圍（列層級）：
  - condition：（FLD-017（TW_DEMO_REQHDR.REQ_STATUS） 屬於 {'020'、'025'}）且（（〈申請人的直屬主管〉（DRV-002） ＝ 目前使用者員工編號）或（〈申請人的部門主管〉（DRV-001） ＝ 目前使用者員工編號））
  - 說明：審核清單只列出待審（020、025）且自己是直屬主管或部門主管的申請單。
- 無權時的效果：
  - 效果：ROWS_FILTERED
  - 說明：查詢結果不含他人的申請單。
- 檢查位置：ROW_LEVEL_SECURITY
- 來源：程式；證據 EV-0008、EV-0036
- 被引用（外環反查）：DOD-002

### PERM-002　ROLE:TW_DEMO_REQUESTER>COMPONENT:TW_DEMO_REQ

- 自然鍵：`ROLE:TW_DEMO_REQUESTER>COMPONENT:TW_DEMO_REQ`
- 權限主體：ROLE-002（申請人）
- 受控資源（Component／Page／程序）：OBJ-003（TW_DEMO_REQ）
- 允許的動作：ADD、UPDATE_DISPLAY
- 資料範圍（列層級）：
  - condition：FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 目前使用者員工編號
  - 說明：只看得到自己的申請單。
- 無權時的效果：
  - 效果：ROWS_FILTERED
  - 說明：查詢結果不含他人的申請單。
- 檢查位置：ROW_LEVEL_SECURITY
- 來源：程式；證據 EV-0008、EV-0037
- 被引用（外環反查）：DOD-002
