# 08 操作契約（API）

> `clone-0123456789abcdef/08`｜版本 r0001｜狀態 **in_review**｜L1 PASS · L2 PASS · L3 PASS · L4 PASS · L5 PASS
> 依賴文件：01、02、03、04、05、06、07、09｜未解問題：無
> 操作 5；未解問題 0
> 本檔由 canonical JSON 以程式產生，請勿手改；修改走研究重跑或 19 的決策。

## 操作契約（OP）

### OP-001　核准申請

- 自然鍵：`TW_DEMO_APV:APPROVE:APPROVE`
- 所屬功能：FR-001（核准申請）
- 操作名稱：核准申請
- 操作種類：TRANSITION
- 觸發的畫面元件：UI-005（核准）
- 誰能執行：（（FLD-017（TW_DEMO_REQHDR.REQ_STATUS） ＝ '020'（STATE-003 待主管審核））且（（目前使用者帳號 具有角色 ROLE-001（審核主管））且（〈申請人的直屬主管〉（DRV-002） ＝ 目前使用者員工編號）））或（（FLD-017（TW_DEMO_REQHDR.REQ_STATUS） ＝ '025'（STATE-004 待部門主管審核））且（（目前使用者帳號 具有角色 ROLE-001（審核主管））且（〈申請人的部門主管〉（DRV-001） ＝ 目前使用者員工編號）））
- 輸入：
  - 名稱：REQ_ID；欄位：FLD-016（TW_DEMO_REQHDR.REQ_ID）；必填：是
  - 名稱：COMMENTS；欄位：FLD-013（TW_DEMO_REQHDR.COMMENTS）；必填：否
- 輸出：
  - 名稱：REQ_STATUS；欄位：FLD-017（TW_DEMO_REQHDR.REQ_STATUS）
- 前置條件：FLD-017（TW_DEMO_REQHDR.REQ_STATUS） 屬於 {'020'（STATE-003 待主管審核）、'025'（STATE-004 待部門主管審核）}
- 套用的檢核規則：（無）
- 轉移、寫入、觸發的介面：
  - 轉移：TRN-008（020→030）、TRN-007（020→025）、TRN-010（025→030）
  - 寫入：FLD-013（TW_DEMO_REQHDR.COMMENTS） ← 參數 COMMENTS
- 交易語意：
  - 交易邊界：SINGLE_UNIT
  - 寫入順序：單一列更新（TW_DEMO_REQHDR）；通知在交易提交後才排入。
  - 失敗時：
    - 種類：ROLLBACK_ALL
    - 說明：任何檢核失敗或存檔錯誤時整筆不寫入，狀態不變。
  - 併發：
    - 策略：STALE_DATA_CHECK
    - 原系統行為：開啟後到存檔之間若資料已被他人更新，存檔被拒絕並顯示訊息，該筆維持先存檔者的結果，本次輸入不寫入。
    - 訊息：MSG-004（27000,4）
  - 重複執行：
    - 可重複：否
    - 行為：核准後按鈕隱藏；同一狀態不能重複核准。
- 原系統對應的物件與事件鏈：
  - 物件：OBJ-012（TW_DEMO_REQWRK.APPROVE_PB.FieldChange）
  - 事件鏈：FieldChange、SaveEdit
- 來源：推導；推導自 FR-001；證據 EV-0018、EV-0028
- 被引用（外環反查）：TC-001、TC-002、TC-004、TC-010；TASK-002；DOD-003；Q-003

### OP-002　退回申請

- 自然鍵：`TW_DEMO_APV:RETURN:RETURN`
- 所屬功能：FR-002（退回申請）
- 操作名稱：退回申請
- 操作種類：TRANSITION
- 觸發的畫面元件：UI-006（退回）
- 誰能執行：（（FLD-017（TW_DEMO_REQHDR.REQ_STATUS） ＝ '020'（STATE-003 待主管審核））且（（目前使用者帳號 具有角色 ROLE-001（審核主管））且（〈申請人的直屬主管〉（DRV-002） ＝ 目前使用者員工編號）））或（（FLD-017（TW_DEMO_REQHDR.REQ_STATUS） ＝ '025'（STATE-004 待部門主管審核））且（（目前使用者帳號 具有角色 ROLE-001（審核主管））且（〈申請人的部門主管〉（DRV-001） ＝ 目前使用者員工編號）））
- 輸入：
  - 名稱：REQ_ID；欄位：FLD-016（TW_DEMO_REQHDR.REQ_ID）；必填：是
  - 名稱：COMMENTS；欄位：FLD-013（TW_DEMO_REQHDR.COMMENTS）；必填：是
- 輸出：
  - 名稱：REQ_STATUS；欄位：FLD-017（TW_DEMO_REQHDR.REQ_STATUS）
- 前置條件：FLD-017（TW_DEMO_REQHDR.REQ_STATUS） 屬於 {'020'（STATE-003 待主管審核）、'025'（STATE-004 待部門主管審核）}
- 套用的檢核規則：BR-005（退回時必須填寫審核意見）
- 轉移、寫入、觸發的介面：
  - 轉移：TRN-006（020→015）、TRN-009（025→015）
  - 寫入：FLD-013（TW_DEMO_REQHDR.COMMENTS） ← 參數 COMMENTS
- 交易語意：
  - 交易邊界：SINGLE_UNIT
  - 寫入順序：單一列更新（TW_DEMO_REQHDR）；通知在交易提交後才排入。
  - 失敗時：
    - 種類：ROLLBACK_ALL
    - 說明：任何檢核失敗或存檔錯誤時整筆不寫入，狀態不變。
  - 併發：
    - 策略：STALE_DATA_CHECK
    - 原系統行為：開啟後到存檔之間若資料已被他人更新，存檔被拒絕並顯示訊息，該筆維持先存檔者的結果，本次輸入不寫入。
    - 訊息：MSG-004（27000,4）
  - 重複執行：
    - 可重複：否
    - 行為：退回後按鈕隱藏；同一狀態不能重複退回。
- 原系統對應的物件與事件鏈：
  - 物件：OBJ-013（TW_DEMO_REQWRK.RETURN_PB.FieldChange）
  - 事件鏈：FieldChange、SaveEdit
- 來源：推導；推導自 FR-002；證據 EV-0020、EV-0028
- 被引用（外環反查）：TC-005、TC-006、TC-012；TASK-003；DOD-004

### OP-003　儲存新申請單

- 自然鍵：`TW_DEMO_REQ:CREATE:SAVE_NEW`
- 所屬功能：FR-003（建立申請）
- 操作名稱：儲存新申請單
- 操作種類：CREATE
- 觸發的畫面元件：不適用：新增模式的工具列儲存，不是頁面上的元件
- 誰能執行：目前使用者帳號 具有角色 ROLE-002（申請人）
- 輸入：
  - 名稱：AMOUNT；欄位：FLD-010（TW_DEMO_REQHDR.AMOUNT）；必填：是
  - 名稱：REASON；欄位：FLD-014（TW_DEMO_REQHDR.REASON）；必填：是
- 輸出：
  - 名稱：REQ_ID；欄位：FLD-016（TW_DEMO_REQHDR.REQ_ID）
  - 名稱：REQ_STATUS；欄位：FLD-017（TW_DEMO_REQHDR.REQ_STATUS）
- 前置條件：不適用：新建沒有前置狀態
- 套用的檢核規則：BR-003（金額必須大於 0）
- 轉移、寫入、觸發的介面：
  - 轉移：TRN-001（新建→010）
  - 寫入：FLD-010（TW_DEMO_REQHDR.AMOUNT） ← 參數 AMOUNT、FLD-014（TW_DEMO_REQHDR.REASON） ← 參數 REASON
- 交易語意：
  - 交易邊界：SINGLE_UNIT
  - 寫入順序：新增一列（TW_DEMO_REQHDR）。
  - 失敗時：
    - 種類：ROLLBACK_ALL
    - 說明：任何檢核失敗或存檔錯誤時整筆不寫入，狀態不變。
  - 併發：
    - 策略：NOT_APPLICABLE
    - 原系統行為：新單不存在併發更新；取號的併發行為見 09 的取號規則。
  - 重複執行：
    - 可重複：否
    - 行為：存檔後畫面轉為修改模式，再按儲存不會建立第二張單。
- 原系統對應的物件與事件鏈：
  - 物件：OBJ-003（TW_DEMO_REQ）
  - 事件鏈：FieldDefault、SaveEdit、SavePreChange
- 來源：推導；推導自 FR-003；證據 EV-0004
- 被引用（外環反查）：TC-007、TC-008、TC-009、TC-010；TASK-004；DOD-005

### OP-004　送出申請

- 自然鍵：`TW_DEMO_REQ:SUBMIT:SUBMIT`
- 所屬功能：FR-004（送出申請）
- 操作名稱：送出申請
- 操作種類：TRANSITION
- 觸發的畫面元件：UI-011（送出）
- 誰能執行：（目前使用者帳號 具有角色 ROLE-002（申請人））且（FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 目前使用者員工編號）
- 輸入：
  - 名稱：REQ_ID；欄位：FLD-016（TW_DEMO_REQHDR.REQ_ID）；必填：是
  - 名稱：AMOUNT；欄位：FLD-010（TW_DEMO_REQHDR.AMOUNT）；必填：是
  - 名稱：REASON；欄位：FLD-014（TW_DEMO_REQHDR.REASON）；必填：是
- 輸出：
  - 名稱：REQ_STATUS；欄位：FLD-017（TW_DEMO_REQHDR.REQ_STATUS）
- 前置條件：FLD-017（TW_DEMO_REQHDR.REQ_STATUS） 屬於 {'010'（STATE-001 草稿）、'015'（STATE-002 退回補件）}
- 套用的檢核規則：BR-006（送出時申請人必須有直屬主管）、BR-003（金額必須大於 0）
- 轉移、寫入、觸發的介面：
  - 轉移：TRN-002（010→020）、TRN-004（015→020）
  - 寫入：FLD-010（TW_DEMO_REQHDR.AMOUNT） ← 參數 AMOUNT、FLD-014（TW_DEMO_REQHDR.REASON） ← 參數 REASON
  - 介面：IF-001（送審通知）
- 交易語意：
  - 交易邊界：SINGLE_UNIT
  - 寫入順序：單一列更新（TW_DEMO_REQHDR）；通知在交易提交後才排入。
  - 失敗時：
    - 種類：ROLLBACK_ALL
    - 說明：任何檢核失敗或存檔錯誤時整筆不寫入，狀態不變。
  - 併發：
    - 策略：STALE_DATA_CHECK
    - 原系統行為：開啟後到存檔之間若資料已被他人更新，存檔被拒絕並顯示訊息，該筆維持先存檔者的結果，本次輸入不寫入。
    - 訊息：MSG-004（27000,4）
  - 重複執行：
    - 可重複：否
    - 行為：送出後按鈕隱藏；同一張單不能重複送出。
- 原系統對應的物件與事件鏈：
  - 物件：OBJ-014（TW_DEMO_REQWRK.SUBMIT_PB.FieldChange）
  - 事件鏈：FieldChange、SaveEdit、SavePostChange
- 來源：推導；推導自 FR-004；證據 EV-0016、EV-0028
- 被引用（外環反查）：TC-010、TC-011、TC-012、TC-013；TASK-005；DOD-006

### OP-005　撤回申請

- 自然鍵：`TW_DEMO_REQ:WITHDRAW:WITHDRAW`
- 所屬功能：FR-005（撤回申請）
- 操作名稱：撤回申請
- 操作種類：TRANSITION
- 觸發的畫面元件：UI-012（撤回）
- 誰能執行：（目前使用者帳號 具有角色 ROLE-002（申請人））且（FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ＝ 目前使用者員工編號）
- 輸入：
  - 名稱：REQ_ID；欄位：FLD-016（TW_DEMO_REQHDR.REQ_ID）；必填：是
- 輸出：
  - 名稱：REQ_STATUS；欄位：FLD-017（TW_DEMO_REQHDR.REQ_STATUS）
- 前置條件：FLD-017（TW_DEMO_REQHDR.REQ_STATUS） 屬於 {'010'（STATE-001 草稿）、'015'（STATE-002 退回補件）}
- 套用的檢核規則：BR-003（金額必須大於 0）
- 轉移、寫入、觸發的介面：
  - 轉移：TRN-003（010→090）、TRN-005（015→090）
  - 寫入：（無）
- 交易語意：
  - 交易邊界：SINGLE_UNIT
  - 寫入順序：單一列更新（TW_DEMO_REQHDR）。
  - 失敗時：
    - 種類：ROLLBACK_ALL
    - 說明：任何檢核失敗或存檔錯誤時整筆不寫入，狀態不變。
  - 併發：
    - 策略：STALE_DATA_CHECK
    - 原系統行為：開啟後到存檔之間若資料已被他人更新，存檔被拒絕並顯示訊息，該筆維持先存檔者的結果，本次輸入不寫入。
    - 訊息：MSG-004（27000,4）
  - 重複執行：
    - 可重複：否
    - 行為：撤回後按鈕隱藏；作廢的單不能再操作。
- 原系統對應的物件與事件鏈：
  - 物件：OBJ-015（TW_DEMO_REQWRK.WITHDRAW_PB.FieldChange）
  - 事件鏈：FieldChange、SaveEdit
- 來源：推導；推導自 FR-005；證據 EV-0017、EV-0028
- 被引用（外環反查）：TC-014；TASK-006；DOD-007
