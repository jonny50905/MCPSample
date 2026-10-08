# 09 業務邏輯

> `clone-0123456789abcdef/09`｜版本 r0001｜狀態 **in_review**｜L1 PASS · L2 PASS · L3 PASS · L4 PASS · L5 PASS
> 依賴文件：01、02、04、05、06、07｜未解問題：無
> 訊息 4、規則 6；未解問題 0
> 本檔由 canonical JSON 以程式產生，請勿手改；修改走研究重跑或 19 的決策。

## PeopleCode 程式處置（覆蓋率分母）

| 程式 | 處置 | 對應項目 |
|---|---|---|
| OBJ-007（TW_DEMO_APV.PostBuild） | OFF_DIAGRAM_ONLY | —；只有狀態圖外的「核准後重開為草稿」邏輯，列入 90 問題清單。 |
| OBJ-008（TW_DEMO_REQ.SavePostChange） | BUSINESS_RULES | BR-001 |
| OBJ-009（TW_DEMO_REQ.SavePreChange） | BUSINESS_RULES | BR-002 |
| OBJ-010（TW_DEMO_REQHDR.AMOUNT.SaveEdit） | BUSINESS_RULES、NATIVE_UNUSED_BRANCH | BR-003；另有一段已證明不會執行的原生分支，不重建（見 90）。 |
| OBJ-011（TW_DEMO_REQHDR.REQUESTER_EMPLID.FieldDefault） | BUSINESS_RULES | BR-004 |
| OBJ-012（TW_DEMO_REQWRK.APPROVE_PB.FieldChange） | TRANSITION_IMPL | TRN-008、TRN-007、TRN-010 |
| OBJ-013（TW_DEMO_REQWRK.RETURN_PB.FieldChange） | TRANSITION_IMPL、BUSINESS_RULES | TRN-006、TRN-009、BR-005 |
| OBJ-014（TW_DEMO_REQWRK.SUBMIT_PB.FieldChange） | TRANSITION_IMPL、BUSINESS_RULES | TRN-002、TRN-004、BR-006 |
| OBJ-015（TW_DEMO_REQWRK.WITHDRAW_PB.FieldChange） | TRANSITION_IMPL | TRN-003、TRN-005 |

## 訊息（MSG）

### MSG-001　27000,1

- 自然鍵：`27000,1`
- 訊息集：27000
- 訊息編號：1
- 訊息原文：金額必須大於 0。
- 嚴重度：ERROR
- 來源：metadata；證據 EV-0009
- 被引用（外環反查）：BR-003；TC-008；DOD-005、DOD-006、DOD-007

### MSG-002　27000,2

- 自然鍵：`27000,2`
- 訊息集：27000
- 訊息編號：2
- 訊息原文：退回時必須填寫審核意見。
- 嚴重度：ERROR
- 來源：metadata；證據 EV-0009
- 被引用（外環反查）：BR-005；TC-005；DOD-004

### MSG-003　27000,3

- 自然鍵：`27000,3`
- 訊息集：27000
- 訊息編號：3
- 訊息原文：找不到直屬主管，無法送出。
- 嚴重度：ERROR
- 來源：metadata；證據 EV-0009
- 被引用（外環反查）：BR-006；TC-011；DOD-006

### MSG-004　27000,4

- 自然鍵：`27000,4`
- 訊息集：27000
- 訊息編號：4
- 訊息原文：此申請單已被其他使用者更新，請重新查詢。
- 嚴重度：ERROR
- 來源：metadata；證據 EV-0009
- 被引用（外環反查）：OP-001、OP-002、OP-004、OP-005；DOD-003、DOD-004、DOD-006、DOD-007

## 業務規則（BR）

### BR-001　送出後通知直屬主管

- 自然鍵：`TW_DEMO_REQ.SavePostChange:NOTIFY_SUPERVISOR`
- 規則名稱：送出後通知直屬主管
- 規則種類：SIDE_EFFECT
- 適用的功能：FR-004（送出申請）
- 觸發事件、元件、轉移、模式：
  - 事件：SAVE_POST_CHANGE
  - 轉移：TRN-002（010→020）、TRN-004（015→020）
- 精確條件：FLD-017（TW_DEMO_REQHDR.REQ_STATUS） ＝ '020'（STATE-003 待主管審核）
- 動作：
  - 種類：NOTIFY
  - 介面：IF-001（送審通知）
- 同一觸發點內的執行順序：1
- NULL／空白／0／日期邊界的處理：不適用：沒有數值或日期判斷
- 不同模式或角色的差異：不適用：只在送出成功的存檔執行
- 原系統實作位置：
  - 物件：OBJ-008（TW_DEMO_REQ.SavePostChange）
  - 事件：SavePostChange
- 來源：程式；證據 EV-0028
- 被引用（外環反查）：OBJ-008；TC-013；TASK-005；DOD-006

### BR-002　新單取號

- 自然鍵：`TW_DEMO_REQ.SavePreChange:ASSIGN_REQ_ID`
- 規則名稱：新單取號
- 規則種類：DEFAULTING
- 適用的功能：FR-003（建立申請）
- 觸發事件、元件、轉移、模式：
  - 事件：SAVE_PRE_CHANGE
  - 轉移：TRN-001（新建→010）
  - 模式：ADD
- 精確條件：FLD-016（TW_DEMO_REQHDR.REQ_ID） ＝ 'NEW'
- 動作：
  - 種類：SET_VALUE
  - 指派：FLD-016（TW_DEMO_REQHDR.REQ_ID） ← 現有最大 REQ_ID 的數值加 1，左補零到 10 碼
- 同一觸發點內的執行順序：1
- NULL／空白／0／日期邊界的處理：第一張單取 0000000001；兩張新單同時存檔可能取到同號，後存檔者因主鍵重複而失敗（原系統沒有重試）。
- 不同模式或角色的差異：只在新增模式。
- 原系統實作位置：
  - 物件：OBJ-009（TW_DEMO_REQ.SavePreChange）
  - 事件：SavePreChange
- 來源：程式；證據 EV-0027
- 被引用（外環反查）：OBJ-009；TC-009；TASK-004；DOD-005

### BR-003　金額必須大於 0

- 自然鍵：`TW_DEMO_REQHDR.AMOUNT.SaveEdit:AMOUNT_POSITIVE`
- 規則名稱：金額必須大於 0
- 規則種類：VALIDATION
- 適用的功能：FR-003（建立申請）、FR-004（送出申請）、FR-005（撤回申請）
- 觸發事件、元件、轉移、模式：
  - 事件：SAVE_EDIT
  - 模式：ADD、UPDATE_DISPLAY
- 精確條件：FLD-010（TW_DEMO_REQHDR.AMOUNT） ≤ 0
- 動作：
  - 種類：REJECT
  - 訊息：MSG-001（27000,1）
- 同一觸發點內的執行順序：1
- NULL／空白／0／日期邊界的處理：0 拒絕；最小可接受 0.01（小數 2 位）；未輸入時數值欄存 0，視同 0 拒絕。
- 不同模式或角色的差異：不適用：新增與修改相同
- 原系統實作位置：
  - 物件：OBJ-010（TW_DEMO_REQHDR.AMOUNT.SaveEdit）
  - 事件：SaveEdit
- 來源：程式；證據 EV-0021
- 被引用（外環反查）：OBJ-010；OP-003、OP-004、OP-005；TC-007、TC-008；TASK-004、TASK-005、TASK-006；DOD-005、DOD-006、DOD-007

### BR-004　申請人預設為目前使用者

- 自然鍵：`TW_DEMO_REQHDR.REQUESTER_EMPLID.FieldDefault:REQUESTER_DEFAULT`
- 規則名稱：申請人預設為目前使用者
- 規則種類：DEFAULTING
- 適用的功能：FR-003（建立申請）
- 觸發事件、元件、轉移、模式：
  - 事件：FIELD_DEFAULT
  - 模式：ADD
- 精確條件：FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） 為空白（字元欄為 NULL 或單一空白）
- 動作：
  - 種類：SET_VALUE
  - 指派：FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID） ← 目前使用者員工編號
- 同一觸發點內的執行順序：1
- NULL／空白／0／日期邊界的處理：不適用：沒有數值或日期判斷
- 不同模式或角色的差異：只在新增模式；修改模式不會重設申請人。
- 原系統實作位置：
  - 物件：OBJ-011（TW_DEMO_REQHDR.REQUESTER_EMPLID.FieldDefault）
  - 事件：FieldDefault
- 來源：程式；證據 EV-0026
- 被引用（外環反查）：OBJ-011；TC-009；TASK-004；DOD-005

### BR-005　退回時必須填寫審核意見

- 自然鍵：`TW_DEMO_REQWRK.RETURN_PB.FieldChange:RETURN_COMMENT_REQUIRED`
- 規則名稱：退回時必須填寫審核意見
- 規則種類：VALIDATION
- 適用的功能：FR-002（退回申請）
- 觸發事件、元件、轉移、模式：
  - 事件：FIELD_CHANGE
  - 元件：UI-006（退回）
  - 轉移：TRN-006（020→015）、TRN-009（025→015）
- 精確條件：FLD-013（TW_DEMO_REQHDR.COMMENTS） 為空白（字元欄為 NULL 或單一空白）
- 動作：
  - 種類：REJECT
  - 訊息：MSG-002（27000,2）
- 同一觸發點內的執行順序：1
- NULL／空白／0／日期邊界的處理：只輸入空白字元視同未填寫。
- 不同模式或角色的差異：不適用：直屬主管與部門主管相同
- 原系統實作位置：
  - 物件：OBJ-013（TW_DEMO_REQWRK.RETURN_PB.FieldChange）
  - 事件：FieldChange
- 來源：程式；證據 EV-0020
- 被引用（外環反查）：OBJ-013；OP-002；TC-005；TASK-003；DOD-004

### BR-006　送出時申請人必須有直屬主管

- 自然鍵：`TW_DEMO_REQWRK.SUBMIT_PB.FieldChange:SUPERVISOR_REQUIRED`
- 規則名稱：送出時申請人必須有直屬主管
- 規則種類：VALIDATION
- 適用的功能：FR-004（送出申請）
- 觸發事件、元件、轉移、模式：
  - 事件：FIELD_CHANGE
  - 元件：UI-012（送出）
  - 轉移：TRN-002（010→020）、TRN-004（015→020）
- 精確條件：〈申請人的直屬主管〉（DRV-002） 查不到（結果為空）
- 動作：
  - 種類：REJECT
  - 訊息：MSG-003（27000,3）
- 同一觸發點內的執行順序：1
- NULL／空白／0／日期邊界的處理：SUPERVISOR_ID 為空白（單一空白）視同找不到。
- 不同模式或角色的差異：不適用：只在按送出時檢查
- 原系統實作位置：
  - 物件：OBJ-014（TW_DEMO_REQWRK.SUBMIT_PB.FieldChange）
  - 事件：FieldChange
- 來源：程式；證據 EV-0016、EV-0030
- 被引用（外環反查）：OBJ-014；OP-004；TC-011；TASK-005；DOD-006
