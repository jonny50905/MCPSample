# 07 資料設計

> `clone-0123456789abcdef/07`｜版本 r0001｜狀態 **in_review**｜L1 PASS · L2 PASS · L3 PASS · L4 PASS · L5 PASS
> 依賴文件：01｜未解問題：Q-001（NATIVE_UNUSED_BRANCH:TW_DEMO_REQHDR.AMOUNT.SaveEdit:REQ_TYPE=INT）、Q-002（OFF_DIAGRAM_STATE:REQ_STATUS:099）
> 實體 3、欄位 19、衍生概念 2、不建置欄位組 1；未解問題 2
> 本檔由 canonical JSON 以程式產生，請勿手改；修改走研究重跑或 19 的決策。

## 不建置的原生欄位（摘要）

| ID | Record | 欄位 | 資料剖析 |
|---|---|---|---|
| XF-001 | TW_DEMO_REQHDR | OLD_REF_NO、PRIORITY_CD | 非預設 0 筆（全表非空，查詢日 2026-10-01） |

重建時這些欄位不建資料欄、不上畫面、不寫規則。

## 資料實體（ENT）

### ENT-001　TW_DEMO_DEPT

- 自然鍵：`TW_DEMO_DEPT`
- 對應的 Record：OBJ-016（TW_DEMO_DEPT）
- 業務名稱：部門（有效日）
- 這份資料代表什麼：部門資料；本功能只用來找部門主管。
- 儲存型態：SQL_TABLE
- 實體表名（DERIVED_WORK 等寫 NA）：PS_TW_DEMO_DEPT
- 邏輯鍵欄位（依序）：FLD-001（TW_DEMO_DEPT.DEPTID）、FLD-002（TW_DEMO_DEPT.EFFDT）
- 有效日規則：目前有效列＝基準日當天或之前最大 EFFDT（再取最大 EFFSEQ），可限定有效狀態：
  - 種類：EFFDT
  - 目前有效列：
    - 基準日：系統日期
    - 只取有效狀態：是
- 來源：metadata；證據 EV-0007
- 被引用（外環反查）：DRV-001；FLD-001、FLD-002、FLD-003、FLD-004、FLD-005；TASK-001；DOD-002

### ENT-002　TW_DEMO_EMP

- 自然鍵：`TW_DEMO_EMP`
- 對應的 Record：OBJ-017（TW_DEMO_EMP）
- 業務名稱：員工任職（有效日）
- 這份資料代表什麼：員工任職資料；本功能只用來找申請人的部門與直屬主管。
- 儲存型態：SQL_TABLE
- 實體表名（DERIVED_WORK 等寫 NA）：PS_TW_DEMO_EMP
- 邏輯鍵欄位（依序）：FLD-008（TW_DEMO_EMP.EMPLID）、FLD-006（TW_DEMO_EMP.EFFDT）
- 有效日規則：目前有效列＝基準日當天或之前最大 EFFDT（再取最大 EFFSEQ），可限定有效狀態：
  - 種類：EFFDT
  - 目前有效列：
    - 基準日：系統日期
    - 只取有效狀態：是
- 來源：metadata；證據 EV-0007
- 被引用（外環反查）：DRV-001、DRV-002；FLD-004、FLD-005、FLD-006、FLD-007、FLD-008、FLD-009、FLD-015；TASK-001；DOD-002

### ENT-003　TW_DEMO_REQHDR

- 自然鍵：`TW_DEMO_REQHDR`
- 對應的 Record：OBJ-018（TW_DEMO_REQHDR）
- 業務名稱：申請單
- 這份資料代表什麼：一張申請單一列；狀態、金額、事由與審核結果都在這裡。
- 儲存型態：SQL_TABLE
- 實體表名（DERIVED_WORK 等寫 NA）：PS_TW_DEMO_REQHDR
- 邏輯鍵欄位（依序）：FLD-016（TW_DEMO_REQHDR.REQ_ID）
- 有效日規則：目前有效列＝基準日當天或之前最大 EFFDT（再取最大 EFFSEQ），可限定有效狀態：
  - 種類：NONE
- 來源：metadata；證據 EV-0007
- 被引用（外環反查）：FLD-010、FLD-011、FLD-012、FLD-013、FLD-014、FLD-015、FLD-016、FLD-017、FLD-018、FLD-019；XF-001；TASK-001；DOD-002

## 資料欄位（FLD）

### FLD-001　TW_DEMO_DEPT.DEPTID

- 自然鍵：`TW_DEMO_DEPT.DEPTID`
- 所屬實體：ENT-001（TW_DEMO_DEPT）
- 欄位原名：DEPTID
- 業務標籤：部門
- 型別：CHAR
- 長度：10
- Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則：一律（無條件）
- Record 層預設值：不適用：無 Record 層預設值
- 值域；狀態欄位的 xlat 只列狀態圖上的代碼：
  - 自由輸入：是
- 鍵屬性：KEY
- 敏感分類：NONE
- 使用證據等級（供排優先序，不代表排除）：CODE_REFERENCED
- 來源：metadata；證據 EV-0007
- 被引用（外環反查）：DRV-001；ENT-001；FLD-005；TASK-001

### FLD-002　TW_DEMO_DEPT.EFFDT

- 自然鍵：`TW_DEMO_DEPT.EFFDT`
- 所屬實體：ENT-001（TW_DEMO_DEPT）
- 欄位原名：EFFDT
- 業務標籤：生效日
- 型別：DATE
- 長度：不適用：日期型別沒有長度
- Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則：一律（無條件）
- Record 層預設值：不適用：無 Record 層預設值
- 值域；狀態欄位的 xlat 只列狀態圖上的代碼：
  - 自由輸入：是
- 鍵屬性：KEY
- 敏感分類：NONE
- 使用證據等級（供排優先序，不代表排除）：CODE_REFERENCED
- 來源：metadata；證據 EV-0007
- 被引用（外環反查）：ENT-001；TASK-001

### FLD-003　TW_DEMO_DEPT.EFF_STATUS

- 自然鍵：`TW_DEMO_DEPT.EFF_STATUS`
- 所屬實體：ENT-001（TW_DEMO_DEPT）
- 欄位原名：EFF_STATUS
- 業務標籤：有效狀態
- 型別：CHAR
- 長度：1
- Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則：一律（無條件）
- Record 層預設值：不適用：無 Record 層預設值
- 值域；狀態欄位的 xlat 只列狀態圖上的代碼：
  - 值清單：
    - 儲存值：A；文字：有效；有效：是；資料：HAS_DATA
    - 儲存值：I；文字：無效；有效：是；資料：HAS_DATA
- 鍵屬性：（無）
- 敏感分類：NONE
- 使用證據等級（供排優先序，不代表排除）：CODE_REFERENCED
- 來源：metadata；證據 EV-0007
- 被引用（外環反查）：TASK-001

### FLD-004　TW_DEMO_DEPT.MANAGER_ID

- 自然鍵：`TW_DEMO_DEPT.MANAGER_ID`
- 所屬實體：ENT-001（TW_DEMO_DEPT）
- 欄位原名：MANAGER_ID
- 業務標籤：部門主管
- 型別：CHAR
- 長度：11
- Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則：NO
- Record 層預設值：不適用：無 Record 層預設值
- 值域；狀態欄位的 xlat 只列狀態圖上的代碼：
  - 查找來源：
    - 實體：ENT-002（TW_DEMO_EMP）
    - 鍵欄位：FLD-008（TW_DEMO_EMP.EMPLID）
- 鍵屬性：（無）
- 與其他欄位的關聯：
  - 目標：FLD-008（TW_DEMO_EMP.EMPLID）；種類：LOGICAL_FK
- 敏感分類：PERSONAL
- 使用證據等級（供排優先序，不代表排除）：CODE_REFERENCED
- 來源：metadata；證據 EV-0007、EV-0015
- 被引用（外環反查）：DRV-001；TC-001、TC-002、TC-003、TC-004、TC-005、TC-006、TC-010、TC-012、TC-013；TASK-001

### FLD-005　TW_DEMO_EMP.DEPTID

- 自然鍵：`TW_DEMO_EMP.DEPTID`
- 所屬實體：ENT-002（TW_DEMO_EMP）
- 欄位原名：DEPTID
- 業務標籤：部門
- 型別：CHAR
- 長度：10
- Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則：一律（無條件）
- Record 層預設值：不適用：無 Record 層預設值
- 值域；狀態欄位的 xlat 只列狀態圖上的代碼：
  - 查找來源：
    - 實體：ENT-001（TW_DEMO_DEPT）
    - 鍵欄位：FLD-001（TW_DEMO_DEPT.DEPTID）
- 鍵屬性：（無）
- 與其他欄位的關聯：
  - 目標：FLD-001（TW_DEMO_DEPT.DEPTID）；種類：LOGICAL_FK
- 敏感分類：NONE
- 使用證據等級（供排優先序，不代表排除）：CODE_REFERENCED
- 來源：metadata；證據 EV-0007
- 被引用（外環反查）：DRV-001；TC-001、TC-002、TC-003、TC-004、TC-005、TC-006、TC-010、TC-012、TC-013；TASK-001

### FLD-006　TW_DEMO_EMP.EFFDT

- 自然鍵：`TW_DEMO_EMP.EFFDT`
- 所屬實體：ENT-002（TW_DEMO_EMP）
- 欄位原名：EFFDT
- 業務標籤：生效日
- 型別：DATE
- 長度：不適用：日期型別沒有長度
- Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則：一律（無條件）
- Record 層預設值：不適用：無 Record 層預設值
- 值域；狀態欄位的 xlat 只列狀態圖上的代碼：
  - 自由輸入：是
- 鍵屬性：KEY
- 敏感分類：NONE
- 使用證據等級（供排優先序，不代表排除）：CODE_REFERENCED
- 來源：metadata；證據 EV-0007
- 被引用（外環反查）：ENT-002；TASK-001

### FLD-007　TW_DEMO_EMP.EFF_STATUS

- 自然鍵：`TW_DEMO_EMP.EFF_STATUS`
- 所屬實體：ENT-002（TW_DEMO_EMP）
- 欄位原名：EFF_STATUS
- 業務標籤：有效狀態
- 型別：CHAR
- 長度：1
- Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則：一律（無條件）
- Record 層預設值：不適用：無 Record 層預設值
- 值域；狀態欄位的 xlat 只列狀態圖上的代碼：
  - 值清單：
    - 儲存值：A；文字：有效；有效：是；資料：HAS_DATA
    - 儲存值：I；文字：無效；有效：是；資料：HAS_DATA
- 鍵屬性：（無）
- 敏感分類：NONE
- 使用證據等級（供排優先序，不代表排除）：CODE_REFERENCED
- 來源：metadata；證據 EV-0007
- 被引用（外環反查）：TASK-001

### FLD-008　TW_DEMO_EMP.EMPLID

- 自然鍵：`TW_DEMO_EMP.EMPLID`
- 所屬實體：ENT-002（TW_DEMO_EMP）
- 欄位原名：EMPLID
- 業務標籤：員工編號
- 型別：CHAR
- 長度：11
- Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則：一律（無條件）
- Record 層預設值：不適用：無 Record 層預設值
- 值域；狀態欄位的 xlat 只列狀態圖上的代碼：
  - 自由輸入：是
- 鍵屬性：KEY
- 敏感分類：PERSONAL
- 使用證據等級（供排優先序，不代表排除）：CODE_REFERENCED
- 來源：metadata；證據 EV-0007
- 被引用（外環反查）：DRV-001、DRV-002；ENT-002；FLD-004、FLD-009、FLD-011、FLD-015；TASK-001

### FLD-009　TW_DEMO_EMP.SUPERVISOR_ID

- 自然鍵：`TW_DEMO_EMP.SUPERVISOR_ID`
- 所屬實體：ENT-002（TW_DEMO_EMP）
- 欄位原名：SUPERVISOR_ID
- 業務標籤：直屬主管
- 型別：CHAR
- 長度：11
- Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則：NO
- Record 層預設值：不適用：無 Record 層預設值
- 值域；狀態欄位的 xlat 只列狀態圖上的代碼：
  - 查找來源：
    - 實體：ENT-002（TW_DEMO_EMP）
    - 鍵欄位：FLD-008（TW_DEMO_EMP.EMPLID）
- 鍵屬性：（無）
- 與其他欄位的關聯：
  - 目標：FLD-008（TW_DEMO_EMP.EMPLID）；種類：LOGICAL_FK
- 敏感分類：PERSONAL
- 使用證據等級（供排優先序，不代表排除）：CODE_REFERENCED
- 來源：metadata；證據 EV-0007、EV-0014
- 被引用（外環反查）：DRV-002；IF-001；TC-001、TC-002、TC-003、TC-004、TC-005、TC-006、TC-007、TC-008、TC-009、TC-010、TC-011、TC-012、TC-013；TASK-001

### FLD-010　TW_DEMO_REQHDR.AMOUNT

- 自然鍵：`TW_DEMO_REQHDR.AMOUNT`
- 所屬實體：ENT-003（TW_DEMO_REQHDR）
- 欄位原名：AMOUNT
- 業務標籤：金額
- 型別：NUMBER
- 長度：11
- 小數位數：2
- Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則：一律（無條件）
- Record 層預設值：不適用：無 Record 層預設值
- 值域；狀態欄位的 xlat 只列狀態圖上的代碼：
  - 自由輸入：是
- 鍵屬性：（無）
- 敏感分類：NONE
- 使用證據等級（供排優先序，不代表排除）：DATA_HAS_VALUE
- 來源：metadata；證據 EV-0007
- 被引用（外環反查）：TRN-007、TRN-008；IF-001；UI-002、UI-008；BR-003；OP-003、OP-004；TC-001、TC-002、TC-003、TC-004、TC-007、TC-008、TC-009、TC-010、TC-013、TC-014；TASK-001、TASK-002、TASK-003、TASK-004、TASK-005、TASK-006

### FLD-011　TW_DEMO_REQHDR.APPROVER_EMPLID

- 自然鍵：`TW_DEMO_REQHDR.APPROVER_EMPLID`
- 所屬實體：ENT-003（TW_DEMO_REQHDR）
- 欄位原名：APPROVER_EMPLID
- 業務標籤：核准者
- 型別：CHAR
- 長度：11
- Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則：NO
- Record 層預設值：不適用：無 Record 層預設值
- 值域；狀態欄位的 xlat 只列狀態圖上的代碼：
  - 自由輸入：是
- 鍵屬性：（無）
- 與其他欄位的關聯：
  - 目標：FLD-008（TW_DEMO_EMP.EMPLID）；種類：LOGICAL_FK
- 敏感分類：PERSONAL
- 使用證據等級（供排優先序，不代表排除）：DATA_HAS_VALUE
- 來源：metadata；證據 EV-0007
- 被引用（外環反查）：TRN-008、TRN-010；TC-001、TC-004、TC-010；TASK-001、TASK-002

### FLD-012　TW_DEMO_REQHDR.APPROVE_DT

- 自然鍵：`TW_DEMO_REQHDR.APPROVE_DT`
- 所屬實體：ENT-003（TW_DEMO_REQHDR）
- 欄位原名：APPROVE_DT
- 業務標籤：核准日
- 型別：DATE
- 長度：不適用：日期型別沒有長度
- Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則：NO
- Record 層預設值：不適用：無 Record 層預設值
- 值域；狀態欄位的 xlat 只列狀態圖上的代碼：
  - 自由輸入：是
- 鍵屬性：（無）
- 敏感分類：NONE
- 使用證據等級（供排優先序，不代表排除）：DATA_HAS_VALUE
- 來源：metadata；證據 EV-0007
- 被引用（外環反查）：TRN-008、TRN-010；TC-001；TASK-001、TASK-002

### FLD-013　TW_DEMO_REQHDR.COMMENTS

- 自然鍵：`TW_DEMO_REQHDR.COMMENTS`
- 所屬實體：ENT-003（TW_DEMO_REQHDR）
- 欄位原名：COMMENTS
- 業務標籤：審核意見
- 型別：CHAR
- 長度：254
- Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則：CONDITIONAL
- Record 層預設值：不適用：無 Record 層預設值
- 值域；狀態欄位的 xlat 只列狀態圖上的代碼：
  - 自由輸入：是
- 鍵屬性：（無）
- 敏感分類：NONE
- 使用證據等級（供排優先序，不代表排除）：DATA_HAS_VALUE
- 來源：metadata；證據 EV-0007
- 被引用（外環反查）：UI-003；BR-005；OP-001、OP-002；TC-005、TC-006、TC-012；TASK-001、TASK-002、TASK-003

### FLD-014　TW_DEMO_REQHDR.REASON

- 自然鍵：`TW_DEMO_REQHDR.REASON`
- 所屬實體：ENT-003（TW_DEMO_REQHDR）
- 欄位原名：REASON
- 業務標籤：申請事由
- 型別：CHAR
- 長度：254
- Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則：一律（無條件）
- Record 層預設值：不適用：無 Record 層預設值
- 值域；狀態欄位的 xlat 只列狀態圖上的代碼：
  - 自由輸入：是
- 鍵屬性：（無）
- 敏感分類：NONE
- 使用證據等級（供排優先序，不代表排除）：DATA_HAS_VALUE
- 來源：metadata；證據 EV-0007
- 被引用（外環反查）：UI-004、UI-009；OP-003、OP-004；TC-007、TC-008、TC-009、TC-010；TASK-001、TASK-002、TASK-003、TASK-004、TASK-005

### FLD-015　TW_DEMO_REQHDR.REQUESTER_EMPLID

- 自然鍵：`TW_DEMO_REQHDR.REQUESTER_EMPLID`
- 所屬實體：ENT-003（TW_DEMO_REQHDR）
- 欄位原名：REQUESTER_EMPLID
- 業務標籤：申請人
- 型別：CHAR
- 長度：11
- Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則：一律（無條件）
- Record 層預設值：不適用：無 Record 層預設值
- 值域；狀態欄位的 xlat 只列狀態圖上的代碼：
  - 查找來源：
    - 實體：ENT-002（TW_DEMO_EMP）
    - 鍵欄位：FLD-008（TW_DEMO_EMP.EMPLID）
- 鍵屬性：（無）
- 與其他欄位的關聯：
  - 目標：FLD-008（TW_DEMO_EMP.EMPLID）；種類：LOGICAL_FK
- 敏感分類：PERSONAL
- 使用證據等級（供排優先序，不代表排除）：DATA_HAS_VALUE
- 來源：metadata；證據 EV-0007
- 被引用（外環反查）：DRV-001、DRV-002；PERM-002；TRN-002、TRN-003、TRN-004、TRN-005；IF-001；BR-004；OP-004、OP-005；TC-001、TC-002、TC-003、TC-004、TC-005、TC-006、TC-007、TC-008、TC-009、TC-010、TC-011、TC-012、TC-013、TC-014；TASK-001、TASK-004、TASK-005、TASK-006

### FLD-016　TW_DEMO_REQHDR.REQ_ID

- 自然鍵：`TW_DEMO_REQHDR.REQ_ID`
- 所屬實體：ENT-003（TW_DEMO_REQHDR）
- 欄位原名：REQ_ID
- 業務標籤：申請單號
- 型別：CHAR
- 長度：10
- Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則：一律（無條件）
- Record 層預設值：'NEW'
- 值域；狀態欄位的 xlat 只列狀態圖上的代碼：
  - 自由輸入：是
- 鍵屬性：KEY、SEARCH_KEY
- 敏感分類：NONE
- 使用證據等級（供排優先序，不代表排除）：DATA_HAS_VALUE
- 來源：metadata；證據 EV-0007
- 被引用（外環反查）：ENT-003；IF-001；UI-001、UI-007；BR-002；OP-001、OP-002、OP-003、OP-004、OP-005；TC-009；TASK-001、TASK-002、TASK-003、TASK-004、TASK-005、TASK-006

### FLD-017　TW_DEMO_REQHDR.REQ_STATUS

- 自然鍵：`TW_DEMO_REQHDR.REQ_STATUS`
- 所屬實體：ENT-003（TW_DEMO_REQHDR）
- 欄位原名：REQ_STATUS
- 業務標籤：狀態
- 型別：CHAR
- 長度：3
- Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則：一律（無條件）
- Record 層預設值：'010'
- 值域；狀態欄位的 xlat 只列狀態圖上的代碼：
  - 值清單：
    - 儲存值：010；文字：草稿；有效：是；資料：HAS_DATA
    - 儲存值：015；文字：退回補件；有效：是；資料：HAS_DATA
    - 儲存值：020；文字：待主管審核；有效：是；資料：HAS_DATA
    - 儲存值：025；文字：待部門主管審核；有效：是；資料：HAS_DATA
    - 儲存值：030；文字：核准；有效：是；資料：HAS_DATA
    - 儲存值：090；文字：作廢；有效：是；資料：HAS_DATA
- 鍵屬性：（無）
- 敏感分類：NONE
- 使用證據等級（供排優先序，不代表排除）：DATA_HAS_VALUE
- 來源：metadata；證據 EV-0007、EV-0011
- 被引用（外環反查）：PERM-001；STATE-001、STATE-002、STATE-003、STATE-004、STATE-005、STATE-006；TRN-001、TRN-002、TRN-003、TRN-004、TRN-005、TRN-006、TRN-007、TRN-008、TRN-009、TRN-010；FR-001、FR-002、FR-004、FR-005；UI-003、UI-005、UI-006、UI-008、UI-009、UI-010、UI-011、UI-012、UI-013；BR-001；OP-001、OP-002、OP-003、OP-004、OP-005；TC-001、TC-002、TC-003、TC-004、TC-005、TC-006、TC-011、TC-012、TC-013、TC-014；TASK-001、TASK-002、TASK-003、TASK-004、TASK-005、TASK-006；DOD-001；Q-002

### FLD-018　TW_DEMO_REQHDR.REQ_TYPE

- 自然鍵：`TW_DEMO_REQHDR.REQ_TYPE`
- 所屬實體：ENT-003（TW_DEMO_REQHDR）
- 欄位原名：REQ_TYPE
- 業務標籤：申請類別
- 型別：CHAR
- 長度：3
- Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則：一律（無條件）
- Record 層預設值：'GEN'
- 值域；狀態欄位的 xlat 只列狀態圖上的代碼：
  - 值清單：
    - 儲存值：GEN；文字：一般；有效：是；資料：HAS_DATA
    - 儲存值：URG；文字：急件；有效：是；資料：HAS_DATA
    - 儲存值：INT；文字：內部；有效：否；資料：NO_DATA
- 鍵屬性：（無）
- 敏感分類：NONE
- 使用證據等級（供排優先序，不代表排除）：DATA_HAS_VALUE
- 來源：metadata；證據 EV-0007、EV-0023、EV-0024
- 被引用（外環反查）：UI-011；OP-003、OP-004；TASK-001、TASK-004、TASK-005；Q-001

### FLD-019　TW_DEMO_REQHDR.SUBMIT_DT

- 自然鍵：`TW_DEMO_REQHDR.SUBMIT_DT`
- 所屬實體：ENT-003（TW_DEMO_REQHDR）
- 欄位原名：SUBMIT_DT
- 業務標籤：送出日
- 型別：DATE
- 長度：不適用：日期型別沒有長度
- Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則：NO
- Record 層預設值：不適用：無 Record 層預設值
- 值域；狀態欄位的 xlat 只列狀態圖上的代碼：
  - 自由輸入：是
- 鍵屬性：（無）
- 敏感分類：NONE
- 使用證據等級（供排優先序，不代表排除）：DATA_HAS_VALUE
- 來源：metadata；證據 EV-0007
- 被引用（外環反查）：TRN-002、TRN-004；TC-012、TC-013；TASK-001、TASK-005

## 衍生概念（查找規則）（DRV）

### DRV-001　申請人的部門主管

- 自然鍵：`REQUESTER_DEPT_MANAGER`
- 概念名稱（例：申請人的直屬主管）：申請人的部門主管
- 業務意義：申請人目前任職部門的主管；025（高額）由此人審核。
- 輸入參數與來源：
  - 名稱：REQUESTER；起：FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID）
- 結果型別：PERSON_ID
- 查找規則：從哪些表、怎麼串、篩選、取哪一欄：
  - 來源實體：ENT-002（TW_DEMO_EMP）、ENT-001（TW_DEMO_DEPT）
  - 串接：
    - 左：FLD-008（TW_DEMO_EMP.EMPLID）；右：參數 REQUESTER
    - 左：FLD-001（TW_DEMO_DEPT.DEPTID）；右：FLD-005（TW_DEMO_EMP.DEPTID）
  - 篩選：一律（無條件）
  - 有效日規則：
    - 實體：ENT-002（TW_DEMO_EMP）；規則：CURRENT_ROW；基準日：系統日期；只取有效狀態：是
    - 實體：ENT-001（TW_DEMO_DEPT）；規則：CURRENT_ROW；基準日：系統日期；只取有效狀態：是
  - 取值欄位：FLD-004（TW_DEMO_DEPT.MANAGER_ID）
  - 同值處理：不適用：兩個實體都取目前有效列，結果唯一
- 查無結果時的行為（訊息與阻擋寫在 09）：
  - 結果：EMPTY
  - 說明：部門沒有目前有效列或 MANAGER_ID 為空白時結果為空；原系統對此沒有檢查，案件會停在 025，審核清單中沒有人看得到。
- 多筆時的取法：
  - 規則：UNIQUE_BY_KEY
  - 說明：兩個實體的目前有效列各只有一列。
- 原系統實作位置：OBJ-012（TW_DEMO_REQWRK.APPROVE_PB.FieldChange）、OBJ-013（TW_DEMO_REQWRK.RETURN_PB.FieldChange）
- 來源：程式；證據 EV-0031、EV-0015
- 被引用（外環反查）：PERM-001；ACT-002；TRN-009、TRN-010；FR-001、FR-002；OP-001、OP-002；TASK-001、TASK-002、TASK-003；DOD-002

### DRV-002　申請人的直屬主管

- 自然鍵：`REQUESTER_SUPERVISOR`
- 概念名稱（例：申請人的直屬主管）：申請人的直屬主管
- 業務意義：申請人目前任職資料上登記的直屬主管；送出時必須存在，020 由此人審核。
- 輸入參數與來源：
  - 名稱：REQUESTER；起：FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID）
- 結果型別：PERSON_ID
- 查找規則：從哪些表、怎麼串、篩選、取哪一欄：
  - 來源實體：ENT-002（TW_DEMO_EMP）
  - 串接：
    - 左：FLD-008（TW_DEMO_EMP.EMPLID）；右：參數 REQUESTER
  - 篩選：一律（無條件）
  - 有效日規則：
    - 實體：ENT-002（TW_DEMO_EMP）；規則：CURRENT_ROW；基準日：系統日期；只取有效狀態：是
  - 取值欄位：FLD-009（TW_DEMO_EMP.SUPERVISOR_ID）
  - 同值處理：不適用：鍵（EMPLID＋EFFDT）加目前有效列規則保證只有一列
- 查無結果時的行為（訊息與阻擋寫在 09）：
  - 結果：EMPTY
  - 說明：查無目前有效的任職列，或 SUPERVISOR_ID 為空白時結果為空；送出時由 09 的規則擋下。
- 多筆時的取法：
  - 規則：UNIQUE_BY_KEY
  - 說明：目前有效列規則下每位員工只有一列。
- 原系統實作位置：OBJ-014（TW_DEMO_REQWRK.SUBMIT_PB.FieldChange）、OBJ-012（TW_DEMO_REQWRK.APPROVE_PB.FieldChange）、OBJ-013（TW_DEMO_REQWRK.RETURN_PB.FieldChange）
- 來源：程式；證據 EV-0030、EV-0014
- 被引用（外環反查）：PERM-001；ACT-001；TRN-006、TRN-007、TRN-008；FR-001、FR-002；BR-006；OP-001、OP-002；TC-001、TC-002、TC-003、TC-004、TC-005、TC-006、TC-012；TASK-001、TASK-002、TASK-003、TASK-005；DOD-002

## 不建置的原生欄位（XF）

### XF-001　TW_DEMO_REQHDR

- 自然鍵：`TW_DEMO_REQHDR`
- 所屬實體：ENT-003（TW_DEMO_REQHDR）
- 判定無用的欄位：OLD_REF_NO、PRIORITY_CD
- 資料剖析結論：非預設 0 筆（全表非空，查詢日 2026-10-01）
- 程式面查法結果：
  - 查法 a：PeopleCode 交叉參照：核心路徑沒有指名引用。
  - 查法 b：核心路徑沒有 AE、SQR 或 SQL 物件讀寫這兩欄。
  - 查法 c：既有研究文件沒有指名引用的紀錄。
- 來源：資料；證據 EV-0012、EV-0013
- 被引用（外環反查）：DOD-001
