# 14 測試與驗收

> `clone-0123456789abcdef/14`｜版本 r0001｜狀態 **draft**｜L1 PASS · L2 PASS · L3 FAIL · L4 PASS · L5 NOT_APPLICABLE
> 依賴文件：02、03、04、05、07、08、09｜未解問題：無
> 測試案例 14；未解問題 0
> 本檔由 canonical JSON 以程式產生，請勿手改；修改走研究重跑或 19 的決策。

## 測試案例（TC）

### TC-001　金額剛好 50000 時一次核准

- 自然鍵：`TW_DEMO_APV:APPROVE:BOUNDARY:AMOUNT_AT_LIMIT`
- 案例名稱：金額剛好 50000 時一次核准
- 正例／反例／邊界：BOUNDARY
- 主要功能：FR-001（核准申請）
- 覆蓋的規則／轉移／情境／元件／操作／活動：
  - 轉移：TRN-008（020→030）
- 前置狀態、操作者、前置資料（合成）：
  - 操作者：〈申請人的直屬主管〉（DRV-002） ＝ 目前使用者員工編號
  - 資料：
    - FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 'E1001'
    - FLD-009（TW_DEMO_EMP.SUPERVISOR_ID） ＝ 'E2001'（E1001 的目前有效任職列）
    - FLD-005（TW_DEMO_EMP.DEPTID） ＝ 'D100'（E1001 的目前有效任職列）
    - FLD-004（TW_DEMO_DEPT.MANAGER_ID） ＝ 'E3001'（D100 的目前有效列）
    - FLD-017（TW_DEMO_REQHDR.REQ_STATUS） ＝ '020'
    - FLD-010（TW_DEMO_REQHDR.AMOUNT） ＝ '50000.00'
  - 合成資料：是
  - 狀態：STATE-003（020 待主管審核）
- 操作步驟：
  - 序：1；動作：以 E2001 開啟該申請單並按「核准」；元件：UI-005（核准）；操作：OP-001（核准申請）
- 預期訊息、狀態、元件、資料：
  - 結果狀態：STATE-005（030 核准）
  - 資料：FLD-011（TW_DEMO_REQHDR.APPROVER_EMPLID） ＝ 'E2001'、FLD-012（TW_DEMO_REQHDR.APPROVE_DT） ＝ '測試當日'
- 如何核對：查該列 REQ_STATUS＝030、APPROVER_EMPLID＝E2001、APPROVE_DT＝測試當日。
- 來源：推導；推導自 FR-001
- 被引用（外環反查）：TASK-002；DOD-003

### TC-002　金額 50000.01 時轉部門主管

- 自然鍵：`TW_DEMO_APV:APPROVE:BOUNDARY:AMOUNT_OVER_LIMIT`
- 案例名稱：金額 50000.01 時轉部門主管
- 正例／反例／邊界：BOUNDARY
- 主要功能：FR-001（核准申請）
- 覆蓋的規則／轉移／情境／元件／操作／活動：
  - 轉移：TRN-007（020→025）
- 前置狀態、操作者、前置資料（合成）：
  - 操作者：〈申請人的直屬主管〉（DRV-002） ＝ 目前使用者員工編號
  - 資料：
    - FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 'E1001'
    - FLD-009（TW_DEMO_EMP.SUPERVISOR_ID） ＝ 'E2001'（E1001 的目前有效任職列）
    - FLD-005（TW_DEMO_EMP.DEPTID） ＝ 'D100'（E1001 的目前有效任職列）
    - FLD-004（TW_DEMO_DEPT.MANAGER_ID） ＝ 'E3001'（D100 的目前有效列）
    - FLD-017（TW_DEMO_REQHDR.REQ_STATUS） ＝ '020'
    - FLD-010（TW_DEMO_REQHDR.AMOUNT） ＝ '50000.01'
  - 合成資料：是
  - 狀態：STATE-003（020 待主管審核）
- 操作步驟：
  - 序：1；動作：以 E2001 開啟該申請單並按「核准」；元件：UI-005（核准）；操作：OP-001（核准申請）
- 預期訊息、狀態、元件、資料：
  - 結果狀態：STATE-004（025 待部門主管審核）
- 如何核對：查該列 REQ_STATUS＝025；APPROVER_EMPLID 未寫入。
- 來源：推導；推導自 FR-001
- 被引用（外環反查）：TASK-002；DOD-003

### TC-003　具審核角色但不是直屬主管者看不到申請單

- 自然鍵：`TW_DEMO_APV:APPROVE:NEGATIVE:NOT_SUPERVISOR`
- 案例名稱：具審核角色但不是直屬主管者看不到申請單
- 正例／反例／邊界：NEGATIVE
- 主要功能：FR-001（核准申請）
- 覆蓋的規則／轉移／情境／元件／操作／活動：
  - 轉移：TRN-008（020→030）
- 前置狀態、操作者、前置資料（合成）：
  - 操作者：（目前使用者帳號 具有角色 ROLE-001（審核主管））且（〈申請人的直屬主管〉（DRV-002） ≠ 目前使用者員工編號）
  - 資料：
    - FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 'E1001'
    - FLD-009（TW_DEMO_EMP.SUPERVISOR_ID） ＝ 'E2001'（E1001 的目前有效任職列）
    - FLD-005（TW_DEMO_EMP.DEPTID） ＝ 'D100'（E1001 的目前有效任職列）
    - FLD-004（TW_DEMO_DEPT.MANAGER_ID） ＝ 'E3001'（D100 的目前有效列）
    - FLD-017（TW_DEMO_REQHDR.REQ_STATUS） ＝ '020'
    - FLD-010（TW_DEMO_REQHDR.AMOUNT） ＝ '1000.00'
  - 合成資料：是
  - 狀態：STATE-003（020 待主管審核）
- 操作步驟：
  - 序：1；動作：以 E2999（具審核角色、但不是 E1001 的直屬主管）查詢該申請單
- 預期訊息、狀態、元件、資料：
  - 資料不變：是
- 如何核對：查詢結果不含此單；該列資料不變。
- 來源：推導；推導自 FR-001
- 被引用（外環反查）：TASK-002；DOD-003

### TC-004　高額案件兩段核准

- 自然鍵：`TW_DEMO_APV:APPROVE:POSITIVE:HIGH_AMOUNT_END_TO_END`
- 案例名稱：高額案件兩段核准
- 正例／反例／邊界：POSITIVE
- 主要功能：FR-001（核准申請）
- 覆蓋的規則／轉移／情境／元件／操作／活動：
  - 情境：FLOW-004（高額審核）
  - 轉移：TRN-007（020→025）、TRN-010（025→030）
- 前置狀態、操作者、前置資料（合成）：
  - 操作者：〈申請人的直屬主管〉（DRV-002） ＝ 目前使用者員工編號
  - 資料：
    - FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 'E1001'
    - FLD-009（TW_DEMO_EMP.SUPERVISOR_ID） ＝ 'E2001'（E1001 的目前有效任職列）
    - FLD-005（TW_DEMO_EMP.DEPTID） ＝ 'D100'（E1001 的目前有效任職列）
    - FLD-004（TW_DEMO_DEPT.MANAGER_ID） ＝ 'E3001'（D100 的目前有效列）
    - FLD-017（TW_DEMO_REQHDR.REQ_STATUS） ＝ '020'
    - FLD-010（TW_DEMO_REQHDR.AMOUNT） ＝ '80000.00'
  - 合成資料：是
  - 狀態：STATE-003（020 待主管審核）
- 操作步驟：
  - 序：1；動作：以 E2001 按「核准」，狀態轉為 025；元件：UI-005（核准）；操作：OP-001（核准申請）
  - 序：2；動作：以 E3001（D100 部門主管）開啟同一張單並按「核准」；元件：UI-005（核准）；操作：OP-001（核准申請）
- 預期訊息、狀態、元件、資料：
  - 結果狀態：STATE-005（030 核准）
  - 資料：FLD-011（TW_DEMO_REQHDR.APPROVER_EMPLID） ＝ 'E3001'
- 如何核對：第一步後 REQ_STATUS＝025；第二步後 REQ_STATUS＝030、APPROVER_EMPLID＝E3001。
- 來源：推導；推導自 FR-001
- 被引用（外環反查）：TASK-002；DOD-003

### TC-005　未填意見不能退回

- 自然鍵：`TW_DEMO_APV:RETURN:NEGATIVE:BLANK_COMMENT`
- 案例名稱：未填意見不能退回
- 正例／反例／邊界：NEGATIVE
- 主要功能：FR-002（退回申請）
- 覆蓋的規則／轉移／情境／元件／操作／活動：
  - 規則：BR-005（退回時必須填寫審核意見）
- 前置狀態、操作者、前置資料（合成）：
  - 操作者：〈申請人的直屬主管〉（DRV-002） ＝ 目前使用者員工編號
  - 資料：
    - FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 'E1001'
    - FLD-009（TW_DEMO_EMP.SUPERVISOR_ID） ＝ 'E2001'（E1001 的目前有效任職列）
    - FLD-005（TW_DEMO_EMP.DEPTID） ＝ 'D100'（E1001 的目前有效任職列）
    - FLD-004（TW_DEMO_DEPT.MANAGER_ID） ＝ 'E3001'（D100 的目前有效列）
    - FLD-017（TW_DEMO_REQHDR.REQ_STATUS） ＝ '020'
    - FLD-013（TW_DEMO_REQHDR.COMMENTS） ＝ ' '（單一空白，即未填）
  - 合成資料：是
  - 狀態：STATE-003（020 待主管審核）
- 操作步驟：
  - 序：1；動作：以 E2001 不填審核意見，按「退回」；元件：UI-006（退回）；操作：OP-002（退回申請）
- 預期訊息、狀態、元件、資料：
  - 訊息：MSG-002（27000,2）
  - 資料不變：是
- 如何核對：畫面顯示訊息 27000,2；該列 REQ_STATUS 仍為 020。
- 來源：推導；推導自 FR-002
- 被引用（外環反查）：TASK-003；DOD-004

### TC-006　填寫意見後退回

- 自然鍵：`TW_DEMO_APV:RETURN:POSITIVE:RETURN_WITH_COMMENT`
- 案例名稱：填寫意見後退回
- 正例／反例／邊界：POSITIVE
- 主要功能：FR-002（退回申請）
- 覆蓋的規則／轉移／情境／元件／操作／活動：
  - 轉移：TRN-006（020→015）
- 前置狀態、操作者、前置資料（合成）：
  - 操作者：〈申請人的直屬主管〉（DRV-002） ＝ 目前使用者員工編號
  - 資料：
    - FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 'E1001'
    - FLD-009（TW_DEMO_EMP.SUPERVISOR_ID） ＝ 'E2001'（E1001 的目前有效任職列）
    - FLD-005（TW_DEMO_EMP.DEPTID） ＝ 'D100'（E1001 的目前有效任職列）
    - FLD-004（TW_DEMO_DEPT.MANAGER_ID） ＝ 'E3001'（D100 的目前有效列）
    - FLD-017（TW_DEMO_REQHDR.REQ_STATUS） ＝ '020'
  - 合成資料：是
  - 狀態：STATE-003（020 待主管審核）
- 操作步驟：
  - 序：1；動作：以 E2001 填寫審核意見「請補附件」，按「退回」；元件：UI-006（退回）；操作：OP-002（退回申請）；輸入：FLD-013（TW_DEMO_REQHDR.COMMENTS） ＝ '請補附件'
- 預期訊息、狀態、元件、資料：
  - 結果狀態：STATE-002（015 退回補件）
  - 資料：FLD-013（TW_DEMO_REQHDR.COMMENTS） ＝ '請補附件'
- 如何核對：查該列 REQ_STATUS＝015、COMMENTS＝請補附件。
- 來源：推導；推導自 FR-002
- 被引用（外環反查）：TASK-003；DOD-004

### TC-007　金額 0.01 可建立

- 自然鍵：`TW_DEMO_REQ:CREATE:BOUNDARY:AMOUNT_MIN`
- 案例名稱：金額 0.01 可建立
- 正例／反例／邊界：BOUNDARY
- 主要功能：FR-003（建立申請）
- 覆蓋的規則／轉移／情境／元件／操作／活動：
  - 規則：BR-003（金額必須大於 0）
- 前置狀態、操作者、前置資料（合成）：
  - 操作者：FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 目前使用者員工編號
  - 資料：FLD-009（TW_DEMO_EMP.SUPERVISOR_ID） ＝ 'E2001'（E1001 的目前有效任職列）
  - 合成資料：是
  - 狀態：（新建）
- 操作步驟：
  - 序：1；動作：以 E1001 在新增模式輸入金額 0.01 與事由後儲存；元件：UI-008（金額）；操作：OP-003（儲存新申請單）；輸入：FLD-010（TW_DEMO_REQHDR.AMOUNT） ＝ '0.01'、FLD-014（TW_DEMO_REQHDR.REASON） ＝ '測試'
- 預期訊息、狀態、元件、資料：
  - 結果狀態：STATE-001（010 草稿）
- 如何核對：產生一列，REQ_STATUS＝010、AMOUNT＝0.01。
- 來源：推導；推導自 FR-003
- 被引用（外環反查）：TASK-004；DOD-005

### TC-008　金額 0 不能建立

- 自然鍵：`TW_DEMO_REQ:CREATE:NEGATIVE:AMOUNT_ZERO`
- 案例名稱：金額 0 不能建立
- 正例／反例／邊界：NEGATIVE
- 主要功能：FR-003（建立申請）
- 覆蓋的規則／轉移／情境／元件／操作／活動：
  - 規則：BR-003（金額必須大於 0）
- 前置狀態、操作者、前置資料（合成）：
  - 操作者：FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 目前使用者員工編號
  - 資料：FLD-009（TW_DEMO_EMP.SUPERVISOR_ID） ＝ 'E2001'（E1001 的目前有效任職列）
  - 合成資料：是
  - 狀態：（新建）
- 操作步驟：
  - 序：1；動作：以 E1001 在新增模式輸入金額 0 與事由後儲存；元件：UI-008（金額）；操作：OP-003（儲存新申請單）；輸入：FLD-010（TW_DEMO_REQHDR.AMOUNT） ＝ '0'、FLD-014（TW_DEMO_REQHDR.REASON） ＝ '測試'
- 預期訊息、狀態、元件、資料：
  - 訊息：MSG-001（27000,1）
  - 資料不變：是
- 如何核對：畫面顯示訊息 27000,1；沒有新增任何列。
- 來源：推導；推導自 FR-003
- 被引用（外環反查）：TASK-004；DOD-005

### TC-009　建立草稿

- 自然鍵：`TW_DEMO_REQ:CREATE:POSITIVE:CREATE_DRAFT`
- 案例名稱：建立草稿
- 正例／反例／邊界：POSITIVE
- 主要功能：FR-003（建立申請）
- 覆蓋的規則／轉移／情境／元件／操作／活動：
  - 轉移：TRN-001（新建→010）
  - 規則：BR-002（新單取號）、BR-004（申請人預設為目前使用者）
- 前置狀態、操作者、前置資料（合成）：
  - 操作者：FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 目前使用者員工編號
  - 資料：FLD-009（TW_DEMO_EMP.SUPERVISOR_ID） ＝ 'E2001'（E1001 的目前有效任職列）
  - 合成資料：是
  - 狀態：（新建）
- 操作步驟：
  - 序：1；動作：以 E1001 在新增模式輸入金額 1000 與事由後儲存；操作：OP-003（儲存新申請單）；輸入：FLD-010（TW_DEMO_REQHDR.AMOUNT） ＝ '1000'、FLD-014（TW_DEMO_REQHDR.REASON） ＝ '測試'
- 預期訊息、狀態、元件、資料：
  - 結果狀態：STATE-001（010 草稿）
  - 資料：FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 'E1001'、FLD-016（TW_DEMO_REQHDR.REQ_ID） ＝ '10 碼數字（不是 NEW）'
- 如何核對：產生一列，REQ_STATUS＝010、REQUESTER_EMPLID＝E1001、REQ_ID 為 10 碼數字。
- 來源：推導；推導自 FR-003
- 被引用（外環反查）：TASK-004；DOD-005

### TC-010　主流程：建立、送出、核准

- 自然鍵：`TW_DEMO_REQ:CREATE:POSITIVE:MAIN_FLOW_END_TO_END`
- 案例名稱：主流程：建立、送出、核准
- 正例／反例／邊界：POSITIVE
- 主要功能：FR-003（建立申請）
- 覆蓋的規則／轉移／情境／元件／操作／活動：
  - 情境：FLOW-001（主流程）
  - 轉移：TRN-001（新建→010）、TRN-002（010→020）、TRN-008（020→030）
- 前置狀態、操作者、前置資料（合成）：
  - 操作者：FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 目前使用者員工編號
  - 資料：
    - FLD-009（TW_DEMO_EMP.SUPERVISOR_ID） ＝ 'E2001'（E1001 的目前有效任職列）
    - FLD-005（TW_DEMO_EMP.DEPTID） ＝ 'D100'（E1001 的目前有效任職列）
    - FLD-004（TW_DEMO_DEPT.MANAGER_ID） ＝ 'E3001'（D100 的目前有效列）
  - 合成資料：是
  - 狀態：（新建）
- 操作步驟：
  - 序：1；動作：以 E1001 建立金額 1000 的申請單；操作：OP-003（儲存新申請單）；輸入：FLD-010（TW_DEMO_REQHDR.AMOUNT） ＝ '1000'、FLD-014（TW_DEMO_REQHDR.REASON） ＝ '測試'
  - 序：2；動作：以 E1001 按「送出」；元件：UI-012（送出）；操作：OP-004（送出申請）
  - 序：3；動作：以 E2001 開啟該單並按「核准」；元件：UI-005（核准）；操作：OP-001（核准申請）
- 預期訊息、狀態、元件、資料：
  - 結果狀態：STATE-005（030 核准）
  - 資料：FLD-011（TW_DEMO_REQHDR.APPROVER_EMPLID） ＝ 'E2001'
- 如何核對：各步驟後 REQ_STATUS 依序為 010、020、030。
- 來源：推導；推導自 FR-003
- 被引用（外環反查）：TASK-004；DOD-005

### TC-011　沒有直屬主管不能送出

- 自然鍵：`TW_DEMO_REQ:SUBMIT:NEGATIVE:NO_SUPERVISOR`
- 案例名稱：沒有直屬主管不能送出
- 正例／反例／邊界：NEGATIVE
- 主要功能：FR-004（送出申請）
- 覆蓋的規則／轉移／情境／元件／操作／活動：
  - 規則：BR-006（送出時申請人必須有直屬主管）
- 前置狀態、操作者、前置資料（合成）：
  - 操作者：FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 目前使用者員工編號
  - 資料：FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 'E1001'、FLD-017（TW_DEMO_REQHDR.REQ_STATUS） ＝ '010'、FLD-009（TW_DEMO_EMP.SUPERVISOR_ID） ＝ ' '（E1001 的目前有效任職列為單一空白）
  - 合成資料：是
  - 狀態：STATE-001（010 草稿）
- 操作步驟：
  - 序：1；動作：以 E1001 按「送出」；元件：UI-012（送出）；操作：OP-004（送出申請）
- 預期訊息、狀態、元件、資料：
  - 訊息：MSG-003（27000,3）
  - 資料不變：是
- 如何核對：畫面顯示訊息 27000,3；該列 REQ_STATUS 仍為 010。
- 來源：推導；推導自 FR-004
- 被引用（外環反查）：TASK-005；DOD-006

### TC-012　退回後補件重新送出

- 自然鍵：`TW_DEMO_REQ:SUBMIT:POSITIVE:RESUBMIT_AFTER_RETURN`
- 案例名稱：退回後補件重新送出
- 正例／反例／邊界：POSITIVE
- 主要功能：FR-004（送出申請）
- 覆蓋的規則／轉移／情境／元件／操作／活動：
  - 情境：FLOW-003（退回補件）
  - 轉移：TRN-006（020→015）、TRN-004（015→020）
- 前置狀態、操作者、前置資料（合成）：
  - 操作者：〈申請人的直屬主管〉（DRV-002） ＝ 目前使用者員工編號
  - 資料：
    - FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 'E1001'
    - FLD-009（TW_DEMO_EMP.SUPERVISOR_ID） ＝ 'E2001'（E1001 的目前有效任職列）
    - FLD-005（TW_DEMO_EMP.DEPTID） ＝ 'D100'（E1001 的目前有效任職列）
    - FLD-004（TW_DEMO_DEPT.MANAGER_ID） ＝ 'E3001'（D100 的目前有效列）
    - FLD-017（TW_DEMO_REQHDR.REQ_STATUS） ＝ '020'
  - 合成資料：是
  - 狀態：STATE-003（020 待主管審核）
- 操作步驟：
  - 序：1；動作：以 E2001 填寫意見後按「退回」；元件：UI-006（退回）；操作：OP-002（退回申請）；輸入：FLD-013（TW_DEMO_REQHDR.COMMENTS） ＝ '請補附件'
  - 序：2；動作：以 E1001 修改事由後按「送出」；元件：UI-012（送出）；操作：OP-004（送出申請）
- 預期訊息、狀態、元件、資料：
  - 結果狀態：STATE-003（020 待主管審核）
  - 資料：FLD-019（TW_DEMO_REQHDR.SUBMIT_DT） ＝ '測試當日'
- 如何核對：第一步後 REQ_STATUS＝015；第二步後 020，SUBMIT_DT 更新。
- 來源：推導；推導自 FR-004
- 被引用（外環反查）：TASK-005；DOD-006

### TC-013　草稿送出

- 自然鍵：`TW_DEMO_REQ:SUBMIT:POSITIVE:SUBMIT_FROM_DRAFT`
- 案例名稱：草稿送出
- 正例／反例／邊界：POSITIVE
- 主要功能：FR-004（送出申請）
- 覆蓋的規則／轉移／情境／元件／操作／活動：
  - 轉移：TRN-002（010→020）
  - 規則：BR-001（送出後通知直屬主管）
- 前置狀態、操作者、前置資料（合成）：
  - 操作者：FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 目前使用者員工編號
  - 資料：
    - FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 'E1001'
    - FLD-009（TW_DEMO_EMP.SUPERVISOR_ID） ＝ 'E2001'（E1001 的目前有效任職列）
    - FLD-005（TW_DEMO_EMP.DEPTID） ＝ 'D100'（E1001 的目前有效任職列）
    - FLD-004（TW_DEMO_DEPT.MANAGER_ID） ＝ 'E3001'（D100 的目前有效列）
    - FLD-017（TW_DEMO_REQHDR.REQ_STATUS） ＝ '010'
    - FLD-010（TW_DEMO_REQHDR.AMOUNT） ＝ '1000.00'
  - 合成資料：是
  - 狀態：STATE-001（010 草稿）
- 操作步驟：
  - 序：1；動作：以 E1001 按「送出」；元件：UI-012（送出）；操作：OP-004（送出申請）
- 預期訊息、狀態、元件、資料：
  - 結果狀態：STATE-003（020 待主管審核）
  - 資料：FLD-019（TW_DEMO_REQHDR.SUBMIT_DT） ＝ '測試當日'
- 如何核對：查該列 REQ_STATUS＝020、SUBMIT_DT＝測試當日；送審通知程序已排入一筆。
- 來源：推導；推導自 FR-004
- 被引用（外環反查）：TASK-005；DOD-006

### TC-014　撤回草稿

- 自然鍵：`TW_DEMO_REQ:WITHDRAW:POSITIVE:WITHDRAW_DRAFT`
- 案例名稱：撤回草稿
- 正例／反例／邊界：POSITIVE
- 主要功能：FR-005（撤回申請）
- 覆蓋的規則／轉移／情境／元件／操作／活動：
  - 情境：FLOW-002（撤回作廢）
  - 轉移：TRN-003（010→090）
- 前置狀態、操作者、前置資料（合成）：
  - 操作者：FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 目前使用者員工編號
  - 資料：FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 'E1001'、FLD-017（TW_DEMO_REQHDR.REQ_STATUS） ＝ '010'、FLD-010（TW_DEMO_REQHDR.AMOUNT） ＝ '1000.00'
  - 合成資料：是
  - 狀態：STATE-001（010 草稿）
- 操作步驟：
  - 序：1；動作：以 E1001 按「撤回」；元件：UI-013（撤回）；操作：OP-005（撤回申請）
- 預期訊息、狀態、元件、資料：
  - 結果狀態：STATE-006（090 作廢）
- 如何核對：查該列 REQ_STATUS＝090；畫面不再顯示送出與撤回按鈕。
- 來源：推導；推導自 FR-005
- 被引用（外環反查）：TASK-006；DOD-007
