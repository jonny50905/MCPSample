# 01 專案概覽

> `clone-0123456789abcdef/01`｜版本 r0001｜狀態 **in_review**｜L1 PASS · L2 PASS · L3 PASS · L4 PASS · L5 NOT_APPLICABLE
> 依賴文件：無｜未解問題：無
> 目標 1、決策責任 2、物件 22；未解問題 0
> 本檔由 canonical JSON 以程式產生，請勿手改；修改走研究重跑或 19 的決策。

## 範圍摘要

| 分類 | 物件 |
|---|---|
| CORE | OBJ-002 TW_DEMO_APV、OBJ-003 TW_DEMO_REQ、OBJ-005 TW_DEMO_APVPG、OBJ-006 TW_DEMO_REQPG、OBJ-007 TW_DEMO_APV.PostBuild、OBJ-008 TW_DEMO_REQ.SavePostChange、OBJ-009 TW_DEMO_REQ.SavePreChange、OBJ-010 TW_DEMO_REQHDR.AMOUNT.SaveEdit、OBJ-011 TW_DEMO_REQHDR.REQUESTER_EMPLID.FieldDefault、OBJ-012 TW_DEMO_REQWRK.APPROVE_PB.FieldChange、OBJ-013 TW_DEMO_REQWRK.RETURN_PB.FieldChange、OBJ-014 TW_DEMO_REQWRK.SUBMIT_PB.FieldChange、OBJ-015 TW_DEMO_REQWRK.WITHDRAW_PB.FieldChange、OBJ-018 TW_DEMO_REQHDR、OBJ-019 TW_DEMO_REQWRK |
| DEPENDENCY | OBJ-001 TW_DEMO_NTFY、OBJ-004 27000、OBJ-016 TW_DEMO_DEPT、OBJ-017 TW_DEMO_EMP、OBJ-020 TW_DEMO_APPROVER、OBJ-021 TW_DEMO_REQUESTER |
| EXCLUDED | OBJ-022 TW_DEMO_REQSEC |

專案輸入檔：PROVIDED。不建置的原生欄位見 07。

## 專案目標（GOAL）

### GOAL-001　取代舊的申請審核功能

- 自然鍵：`GOAL:01`
- 目標名稱：取代舊的申請審核功能
- 目標敘述：以新系統取代舊的申請審核功能，狀態流程與審核規則維持不變。
- 成功標準（可判定的敘述）：狀態圖上每條轉移在新系統都可操作，結果與 04、09 的規格一致。、14 的測試案例全數通過。
- 來源：專案輸入；證據 EV-0001

## 決策責任（RESP）

### RESP-001　QUESTION_RESOLUTION

- 自然鍵：`RESP:QUESTION_RESOLUTION`
- 負責範圍：QUESTION_RESOLUTION
- 負責者（不寫人名）：業務承辦窗口
- 來源：專案輸入；證據 EV-0003

### RESP-002　SPEC_APPROVAL

- 自然鍵：`RESP:SPEC_APPROVAL`
- 負責範圍：SPEC_APPROVAL
- 負責者（不寫人名）：業務單位主管
- 來源：專案輸入；證據 EV-0002

## 範圍（舊系統物件）（OBJ）

### OBJ-001　TW_DEMO_NTFY

- 自然鍵：`AE:TW_DEMO_NTFY`
- 物件型別：AE
- PeopleSoft 物件原名：TW_DEMO_NTFY
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：DEPENDENCY
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：TW_DEMO_REQ.SavePostChange 在送出成功後排入
- 使用鏈上的物件：OBJ-008（TW_DEMO_REQ.SavePostChange）
- 何時使用：送出（010／015→020）成功後
- 納入／排除理由：送審通知
- 來源：metadata；證據 EV-0024、EV-0029
- 被引用（外環反查）：IF-001

### OBJ-002　TW_DEMO_APV

- 自然鍵：`COMPONENT:TW_DEMO_APV`
- 物件型別：COMPONENT
- PeopleSoft 物件原名：TW_DEMO_APV
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：CORE
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：使用者指定的根
- 何時使用：不適用：入口物件，進入即使用
- 納入／排除理由：使用者指定的核心 Component（主管審核）
- 來源：metadata；證據 EV-0005
- 被引用（外環反查）：OBJ-005；PERM-001；TRN-006、TRN-007、TRN-008、TRN-009、TRN-010；FR-001、FR-002；UI-001

### OBJ-003　TW_DEMO_REQ

- 自然鍵：`COMPONENT:TW_DEMO_REQ`
- 物件型別：COMPONENT
- PeopleSoft 物件原名：TW_DEMO_REQ
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：CORE
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：使用者指定的根
- 何時使用：不適用：入口物件，進入即使用
- 納入／排除理由：使用者指定的核心 Component（申請）
- 來源：metadata；證據 EV-0004
- 被引用（外環反查）：OBJ-006、OBJ-022；PERM-002；TRN-001、TRN-002、TRN-003、TRN-004、TRN-005；FR-003、FR-004、FR-005；UI-007；OP-003

### OBJ-004　27000

- 自然鍵：`MESSAGE_SET:27000`
- 物件型別：MESSAGE_SET
- PeopleSoft 物件原名：27000
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：DEPENDENCY
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：核心 PeopleCode 以 MsgGet 讀取
- 何時使用：檢核失敗時
- 納入／排除理由：提供四則錯誤訊息原文
- 來源：metadata；證據 EV-0009

### OBJ-005　TW_DEMO_APVPG

- 自然鍵：`PAGE:TW_DEMO_APVPG`
- 物件型別：PAGE
- PeopleSoft 物件原名：TW_DEMO_APVPG
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：CORE
- 上層物件（Page 的 Component 等）：OBJ-002（TW_DEMO_APV）
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：TW_DEMO_APV 的主頁
- 使用鏈上的物件：OBJ-002（TW_DEMO_APV）
- 何時使用：不適用：入口物件，進入即使用
- 納入／排除理由：審核畫面
- 來源：metadata；證據 EV-0005
- 被引用（外環反查）：OBJ-018、OBJ-019；UI-001

### OBJ-006　TW_DEMO_REQPG

- 自然鍵：`PAGE:TW_DEMO_REQPG`
- 物件型別：PAGE
- PeopleSoft 物件原名：TW_DEMO_REQPG
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：CORE
- 上層物件（Page 的 Component 等）：OBJ-003（TW_DEMO_REQ）
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：TW_DEMO_REQ 的主頁
- 使用鏈上的物件：OBJ-003（TW_DEMO_REQ）
- 何時使用：不適用：入口物件，進入即使用
- 納入／排除理由：申請畫面
- 來源：metadata；證據 EV-0004
- 被引用（外環反查）：OBJ-018、OBJ-019；UI-007

### OBJ-007　TW_DEMO_APV.PostBuild

- 自然鍵：`PEOPLECODE:TW_DEMO_APV.PostBuild`
- 物件型別：PEOPLECODE
- PeopleSoft 物件原名：TW_DEMO_APV.PostBuild
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：CORE
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：掛在 TW_DEMO_APV 核心路徑上的程式
- 何時使用：不適用：事件觸發即執行
- 納入／排除理由：載入時處理（含圖外的重開邏輯）
- PEOPLECODE 物件的事件：POST_BUILD
- 來源：metadata；證據 EV-0006、EV-0025
- 被引用（外環反查）：Q-002；DEC-001

### OBJ-008　TW_DEMO_REQ.SavePostChange

- 自然鍵：`PEOPLECODE:TW_DEMO_REQ.SavePostChange`
- 物件型別：PEOPLECODE
- PeopleSoft 物件原名：TW_DEMO_REQ.SavePostChange
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：CORE
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：掛在 TW_DEMO_REQ 核心路徑上的程式
- 何時使用：不適用：事件觸發即執行
- 納入／排除理由：送出後排入通知
- PEOPLECODE 物件的事件：SAVE_POST_CHANGE
- 來源：metadata；證據 EV-0006、EV-0024
- 被引用（外環反查）：OBJ-001；BR-001

### OBJ-009　TW_DEMO_REQ.SavePreChange

- 自然鍵：`PEOPLECODE:TW_DEMO_REQ.SavePreChange`
- 物件型別：PEOPLECODE
- PeopleSoft 物件原名：TW_DEMO_REQ.SavePreChange
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：CORE
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：掛在 TW_DEMO_REQ 核心路徑上的程式
- 何時使用：不適用：事件觸發即執行
- 納入／排除理由：新單取號
- PEOPLECODE 物件的事件：SAVE_PRE_CHANGE
- 來源：metadata；證據 EV-0006、EV-0023
- 被引用（外環反查）：BR-002

### OBJ-010　TW_DEMO_REQHDR.AMOUNT.SaveEdit

- 自然鍵：`PEOPLECODE:TW_DEMO_REQHDR.AMOUNT.SaveEdit`
- 物件型別：PEOPLECODE
- PeopleSoft 物件原名：TW_DEMO_REQHDR.AMOUNT.SaveEdit
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：CORE
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：掛在 TW_DEMO_REQ 核心路徑上的程式
- 何時使用：不適用：事件觸發即執行
- 納入／排除理由：金額檢核
- PEOPLECODE 物件的事件：SAVE_EDIT
- 來源：metadata；證據 EV-0006、EV-0021
- 被引用（外環反查）：BR-003

### OBJ-011　TW_DEMO_REQHDR.REQUESTER_EMPLID.FieldDefault

- 自然鍵：`PEOPLECODE:TW_DEMO_REQHDR.REQUESTER_EMPLID.FieldDefault`
- 物件型別：PEOPLECODE
- PeopleSoft 物件原名：TW_DEMO_REQHDR.REQUESTER_EMPLID.FieldDefault
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：CORE
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：掛在 TW_DEMO_REQ 核心路徑上的程式
- 何時使用：不適用：事件觸發即執行
- 納入／排除理由：申請人預設
- PEOPLECODE 物件的事件：FIELD_DEFAULT
- 來源：metadata；證據 EV-0006、EV-0022
- 被引用（外環反查）：BR-004

### OBJ-012　TW_DEMO_REQWRK.APPROVE_PB.FieldChange

- 自然鍵：`PEOPLECODE:TW_DEMO_REQWRK.APPROVE_PB.FieldChange`
- 物件型別：PEOPLECODE
- PeopleSoft 物件原名：TW_DEMO_REQWRK.APPROVE_PB.FieldChange
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：CORE
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：掛在 TW_DEMO_APV 核心路徑上的程式
- 何時使用：不適用：事件觸發即執行
- 納入／排除理由：核准
- PEOPLECODE 物件的事件：FIELD_CHANGE
- 來源：metadata；證據 EV-0006、EV-0018
- 被引用（外環反查）：OBJ-016、OBJ-017；DRV-001、DRV-002；TRN-007、TRN-008、TRN-010；OP-001

### OBJ-013　TW_DEMO_REQWRK.RETURN_PB.FieldChange

- 自然鍵：`PEOPLECODE:TW_DEMO_REQWRK.RETURN_PB.FieldChange`
- 物件型別：PEOPLECODE
- PeopleSoft 物件原名：TW_DEMO_REQWRK.RETURN_PB.FieldChange
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：CORE
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：掛在 TW_DEMO_APV 核心路徑上的程式
- 何時使用：不適用：事件觸發即執行
- 納入／排除理由：退回
- PEOPLECODE 物件的事件：FIELD_CHANGE
- 來源：metadata；證據 EV-0006、EV-0020
- 被引用（外環反查）：DRV-001、DRV-002；TRN-006、TRN-009；BR-005；OP-002

### OBJ-014　TW_DEMO_REQWRK.SUBMIT_PB.FieldChange

- 自然鍵：`PEOPLECODE:TW_DEMO_REQWRK.SUBMIT_PB.FieldChange`
- 物件型別：PEOPLECODE
- PeopleSoft 物件原名：TW_DEMO_REQWRK.SUBMIT_PB.FieldChange
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：CORE
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：掛在 TW_DEMO_REQ 核心路徑上的程式
- 何時使用：不適用：事件觸發即執行
- 納入／排除理由：送出
- PEOPLECODE 物件的事件：FIELD_CHANGE
- 來源：metadata；證據 EV-0006、EV-0016
- 被引用（外環反查）：OBJ-017；DRV-002；TRN-002、TRN-004；BR-006；OP-004

### OBJ-015　TW_DEMO_REQWRK.WITHDRAW_PB.FieldChange

- 自然鍵：`PEOPLECODE:TW_DEMO_REQWRK.WITHDRAW_PB.FieldChange`
- 物件型別：PEOPLECODE
- PeopleSoft 物件原名：TW_DEMO_REQWRK.WITHDRAW_PB.FieldChange
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：CORE
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：掛在 TW_DEMO_REQ 核心路徑上的程式
- 何時使用：不適用：事件觸發即執行
- 納入／排除理由：撤回
- PEOPLECODE 物件的事件：FIELD_CHANGE
- 來源：metadata；證據 EV-0006、EV-0017
- 被引用（外環反查）：TRN-003、TRN-005；OP-005

### OBJ-016　TW_DEMO_DEPT

- 自然鍵：`RECORD:TW_DEMO_DEPT`
- 物件型別：RECORD
- PeopleSoft 物件原名：TW_DEMO_DEPT
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：DEPENDENCY
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：高額案件（025）核准時查申請人部門的主管
- 使用鏈上的物件：OBJ-012（TW_DEMO_REQWRK.APPROVE_PB.FieldChange）
- 何時使用：狀態 025 的核准與退回、審核清單查詢
- 納入／排除理由：只提供部門主管的最小介面
- 原生欄位判定結論；type RECORD 且 CORE／DEPENDENCY 時必填：
  - 無可排除：
    - 查詢日：2026-10-01
- 來源：metadata；證據 EV-0027、EV-0015
- 被引用（外環反查）：ENT-001

### OBJ-017　TW_DEMO_EMP

- 自然鍵：`RECORD:TW_DEMO_EMP`
- 物件型別：RECORD
- PeopleSoft 物件原名：TW_DEMO_EMP
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：DEPENDENCY
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：送出、核准、退回時查申請人的直屬主管與部門；審核清單的資料範圍
- 使用鏈上的物件：OBJ-014（TW_DEMO_REQWRK.SUBMIT_PB.FieldChange）、OBJ-012（TW_DEMO_REQWRK.APPROVE_PB.FieldChange）
- 何時使用：送出、審核清單查詢、核准、退回時
- 納入／排除理由：只提供直屬主管與部門的最小介面
- 原生欄位判定結論；type RECORD 且 CORE／DEPENDENCY 時必填：
  - 無可排除：
    - 查詢日：2026-10-01
- 來源：metadata；證據 EV-0026、EV-0014
- 被引用（外環反查）：ENT-002

### OBJ-018　TW_DEMO_REQHDR

- 自然鍵：`RECORD:TW_DEMO_REQHDR`
- 物件型別：RECORD
- PeopleSoft 物件原名：TW_DEMO_REQHDR
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：CORE
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：兩個主頁的主要 Record
- 使用鏈上的物件：OBJ-006（TW_DEMO_REQPG）、OBJ-005（TW_DEMO_APVPG）
- 何時使用：不適用：兩頁一律讀寫
- 納入／排除理由：申請單主檔
- 原生欄位判定結論；type RECORD 且 CORE／DEPENDENCY 時必填：
  - 排除：
    - 欄數：2
- 來源：metadata；證據 EV-0007
- 被引用（外環反查）：ENT-003

### OBJ-019　TW_DEMO_REQWRK

- 自然鍵：`RECORD:TW_DEMO_REQWRK`
- 物件型別：RECORD
- PeopleSoft 物件原名：TW_DEMO_REQWRK
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：CORE
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：按鈕所在的工作記錄
- 使用鏈上的物件：OBJ-006（TW_DEMO_REQPG）、OBJ-005（TW_DEMO_APVPG）
- 何時使用：不適用：頁面載入即存在
- 納入／排除理由：承載送出、撤回、核准、退回四個按鈕事件
- 原生欄位判定結論；type RECORD 且 CORE／DEPENDENCY 時必填：
  - 判不了：
    - 代碼：NO_TABLE
    - 說明：工作記錄沒有實體表，欄位都是按鈕
- 來源：metadata；證據 EV-0007

### OBJ-020　TW_DEMO_APPROVER

- 自然鍵：`ROLE:TW_DEMO_APPROVER`
- 物件型別：ROLE
- PeopleSoft 物件原名：TW_DEMO_APPROVER
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：DEPENDENCY
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：TW_DEMO_APV 的元件權限
- 何時使用：進入審核畫面時
- 納入／排除理由：審核主管角色
- 來源：metadata；證據 EV-0008
- 被引用（外環反查）：ROLE-001

### OBJ-021　TW_DEMO_REQUESTER

- 自然鍵：`ROLE:TW_DEMO_REQUESTER`
- 物件型別：ROLE
- PeopleSoft 物件原名：TW_DEMO_REQUESTER
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：DEPENDENCY
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：TW_DEMO_REQ 的元件權限
- 何時使用：進入申請畫面時
- 納入／排除理由：申請人角色
- 來源：metadata；證據 EV-0008
- 被引用（外環反查）：ROLE-002

### OBJ-022　TW_DEMO_REQSEC

- 自然鍵：`SECONDARY_PAGE:TW_DEMO_REQSEC`
- 物件型別：SECONDARY_PAGE
- PeopleSoft 物件原名：TW_DEMO_REQSEC
- 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED：EXCLUDED
- 上層物件（Page 的 Component 等）：OBJ-003（TW_DEMO_REQ）
- 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）：TW_DEMO_REQ 內有定義，但頁面上沒有按鈕、連結或程式會開啟它
- 何時使用：不適用：核心路徑不會進入
- 納入／排除理由：元件內存在、核心路徑沒有入口
- 來源：metadata；證據 EV-0010
