# 18 完成定義

> `clone-0123456789abcdef/18`｜版本 r0001｜狀態 **in_review**｜L1 PASS · L2 PASS · L3 PASS · L4 NOT_APPLICABLE · L5 NOT_APPLICABLE
> 依賴文件：03、04、07、08、09、14、17｜未解問題：無
> 完成條件 7；未解問題 0
> 本檔由 canonical JSON 以程式產生，請勿手改；修改走研究重跑或 19 的決策。

## 完成條件（DOD）

### DOD-001　GLOBAL:BASELINE

- 自然鍵：`GLOBAL:BASELINE`
- 適用範圍：GLOBAL
- 完成條件：
  - 種類：STORED_VALUES_PRESERVED；敘述：狀態碼與選項儲存值與 07 的值域完全相同。；參照：FLD-017（TW_DEMO_REQHDR.REQ_STATUS）；需要的證據：TEST_REPORT
  - 種類：NO_EXCLUDED_FIELDS；敘述：07「不建置的原生欄位」沒有出現在資料結構、畫面與規則。；參照：XF-001（TW_DEMO_REQHDR）；需要的證據：CODE_REFERENCE
  - 種類：BLANK_SEMANTICS_PRESERVED；敘述：空白、0 與 NULL 的比較照共同定義實作。；參照：（無）；需要的證據：TEST_REPORT
  - 種類：TRACE_IDS_RECORDED；敘述：程式與測試都標註實作的 ID。；參照：（無）；需要的證據：CODE_REFERENCE
  - 種類：OPEN_QUESTIONS_CLOSED；敘述：影響本工作項目的 BLOCKING 問題都已在 19 有決策。；參照：（無）；需要的證據：REVIEW_RECORD
- 來源：框架模板

### DOD-002　TASK:FOUNDATION:DATA_AND_SECURITY

- 自然鍵：`TASK:FOUNDATION:DATA_AND_SECURITY`
- 適用範圍：TASK
- 對應工作：TASK-001（資料結構、衍生概念與角色權限）
- 完成條件：
  - 種類：STORED_VALUES_PRESERVED；敘述：實體、欄位、值域與衍生概念照 07 建立。；參照：ENT-001（TW_DEMO_DEPT）、ENT-002（TW_DEMO_EMP）、ENT-003（TW_DEMO_REQHDR）、DRV-001（申請人的部門主管）、DRV-002（申請人的直屬主管）；需要的證據：CODE_REFERENCE
  - 種類：RULES_IMPLEMENTED；敘述：角色與資料範圍照 03 建立。；參照：PERM-001（ROLE:TW_DEMO_APPROVER>COMPONENT:TW_DEMO_APV）、PERM-002（ROLE:TW_DEMO_REQUESTER>COMPONENT:TW_DEMO_REQ）；需要的證據：TEST_REPORT
- 來源：外環計算

### DOD-003　TASK:SLICE:TW_DEMO_APV:APPROVE

- 自然鍵：`TASK:SLICE:TW_DEMO_APV:APPROVE`
- 適用範圍：TASK
- 對應工作：TASK-002（核准申請）
- 完成條件：
  - 種類：TESTS_PASS；敘述：本工作的測試案例全數通過。；參照：TC-001（金額剛好 50000 時一次核准）、TC-002（金額 50000.01 時轉部門主管）、TC-003（具審核角色但不是直屬主管者看不到申請單）、TC-004（高額案件兩段核准）；需要的證據：TEST_REPORT
  - 種類：RULES_IMPLEMENTED；敘述：本工作的轉移、規則與操作都已實作。；參照：TRN-008（020→030）、TRN-007（020→025）、TRN-010（025→030）、OP-001（核准申請）；需要的證據：CODE_REFERENCE
  - 種類：MESSAGES_PRESERVED；敘述：訊息原文與觸發條件與 09 一致。；參照：MSG-004（27000,4）；需要的證據：TEST_REPORT
- 來源：外環計算

### DOD-004　TASK:SLICE:TW_DEMO_APV:RETURN

- 自然鍵：`TASK:SLICE:TW_DEMO_APV:RETURN`
- 適用範圍：TASK
- 對應工作：TASK-003（退回申請）
- 完成條件：
  - 種類：TESTS_PASS；敘述：本工作的測試案例全數通過。；參照：TC-005（未填意見不能退回）、TC-006（填寫意見後退回）；需要的證據：TEST_REPORT
  - 種類：RULES_IMPLEMENTED；敘述：本工作的轉移、規則與操作都已實作。；參照：TRN-006（020→015）、TRN-009（025→015）、BR-005（退回時必須填寫審核意見）、OP-002（退回申請）；需要的證據：CODE_REFERENCE
  - 種類：MESSAGES_PRESERVED；敘述：訊息原文與觸發條件與 09 一致。；參照：MSG-002（27000,2）、MSG-004（27000,4）；需要的證據：TEST_REPORT
- 來源：外環計算

### DOD-005　TASK:SLICE:TW_DEMO_REQ:CREATE

- 自然鍵：`TASK:SLICE:TW_DEMO_REQ:CREATE`
- 適用範圍：TASK
- 對應工作：TASK-004（建立申請）
- 完成條件：
  - 種類：TESTS_PASS；敘述：本工作的測試案例全數通過。；參照：TC-007（金額 0.01 可建立）、TC-008（金額 0 不能建立）、TC-009（建立草稿）、TC-010（主流程：建立、送出、核准）；需要的證據：TEST_REPORT
  - 種類：RULES_IMPLEMENTED；敘述：本工作的轉移、規則與操作都已實作。；參照：TRN-001（新建→010）、BR-002（新單取號）、BR-003（金額必須大於 0）、BR-004（申請人預設為目前使用者）、OP-003（儲存新申請單）；需要的證據：CODE_REFERENCE
  - 種類：MESSAGES_PRESERVED；敘述：訊息原文與觸發條件與 09 一致。；參照：MSG-001（27000,1）；需要的證據：TEST_REPORT
- 來源：外環計算

### DOD-006　TASK:SLICE:TW_DEMO_REQ:SUBMIT

- 自然鍵：`TASK:SLICE:TW_DEMO_REQ:SUBMIT`
- 適用範圍：TASK
- 對應工作：TASK-005（送出申請）
- 完成條件：
  - 種類：TESTS_PASS；敘述：本工作的測試案例全數通過。；參照：TC-011（沒有直屬主管不能送出）、TC-012（退回後補件重新送出）、TC-013（草稿送出）；需要的證據：TEST_REPORT
  - 種類：RULES_IMPLEMENTED；敘述：本工作的轉移、規則與操作都已實作。；參照：TRN-002（010→020）、TRN-004（015→020）、BR-001（送出後通知直屬主管）、BR-003（金額必須大於 0）、BR-006（送出時申請人必須有直屬主管）、OP-004（送出申請）；需要的證據：CODE_REFERENCE
  - 種類：MESSAGES_PRESERVED；敘述：訊息原文與觸發條件與 09 一致。；參照：MSG-001（27000,1）、MSG-003（27000,3）、MSG-004（27000,4）；需要的證據：TEST_REPORT
- 來源：外環計算

### DOD-007　TASK:SLICE:TW_DEMO_REQ:WITHDRAW

- 自然鍵：`TASK:SLICE:TW_DEMO_REQ:WITHDRAW`
- 適用範圍：TASK
- 對應工作：TASK-006（撤回申請）
- 完成條件：
  - 種類：TESTS_PASS；敘述：本工作的測試案例全數通過。；參照：TC-014（撤回草稿）；需要的證據：TEST_REPORT
  - 種類：RULES_IMPLEMENTED；敘述：本工作的轉移、規則與操作都已實作。；參照：TRN-003（010→090）、TRN-005（015→090）、BR-003（金額必須大於 0）、OP-005（撤回申請）；需要的證據：CODE_REFERENCE
  - 種類：MESSAGES_PRESERVED；敘述：訊息原文與觸發條件與 09 一致。；參照：MSG-001（27000,1）、MSG-004（27000,4）；需要的證據：TEST_REPORT
- 來源：外環計算
