# 10 證據

## 10.1 證據清單
| 證據編號 | 類型 | 位置 | 原文摘錄 |
|---|---|---|---|
| E-001 | 檔案 | docs/business-spec/sample-jo/source/project.md §本期目標 | 用人主管與招募人員在系統上建立職缺並送審，取代紙本職缺申請單的簽核。 |
| E-002 | 檔案 | docs/business-spec/sample-jo/source/project.md §本期目標 | 職缺依開缺人數走一層或兩層核准，核准後立即開放徵才。 |
| E-003 | 檔案 | docs/business-spec/sample-jo/source/project.md §本期目標 | 招募人員可暫停、恢復、關閉職缺；已錄取人數達到開缺人數時，職缺自動標示為補足。 |
| E-004 | 檔案 | docs/business-spec/sample-jo/source/project.md §本期目標 | 送審、退回、核准、補足時，相關人員收到通知。 |
| E-005 | 檔案 | docs/business-spec/sample-jo/source/project.md §補充說明 | 本期不含應徵者管理與錄用作業；「已錄取人數」由現有的錄用作業回寫。 |
| E-006 | 檔案 | docs/business-spec/sample-jo/source/project.md §補充說明 | 職位、部門、工作地點與主管關係以人事資料為準，不在職缺功能內維護。 |
| E-007 | 檔案 | docs/business-spec/sample-jo/source/project.md §補充說明 | 本期不含對外招募網站：職缺核准後不自動刊登到公司徵才網站，刊登仍由招募人員人工處理。 |
| E-008 | 檔案 | docs/business-spec/sample-jo/source/project.md §補充說明 | 本期不含面試排程：面試時間的安排沿用現行做法，不在本系統處理。 |
| E-009 | 檔案 | docs/business-spec/sample-jo/source/project.md §補充說明 | 舊有的紙本職缺申請單不轉入系統。 |
| E-010 | 檔案 | docs/business-spec/sample-jo/source/status.md §狀態圖 | state "已核准（開放徵才）" as Approved |
| E-011 | 檔案 | docs/business-spec/sample-jo/source/status.md §各狀態的意思 | 「已核准」：所有核准層級都已核准，職缺開放徵才，可以接受應徵者。 |
| E-012 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §1 | TW_DEMO_JO_REQ \| Component \| 職缺維護（建立、修改、送審、取消、暫停、恢復、關閉） |
| E-013 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §6 | 角色 \| 認定方式 \| 可用畫面 \| 可做的動作 \| 資料範圍 |
| E-014 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §8 | 情境 1（一層核准）：假設開缺 3 人的職缺為「待核准」；當上層主管按「核准」；則狀態改為「已核准」，招募人員與用人主管收到核准通知。 |
| E-015 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §2 | 開缺人數 1 到 5 人：第一層核准者核准後，狀態改為「已核准」。 |
| E-016 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §7 | 資料與批次（實作說明） |
| E-017 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §7 | 狀態異動歷史 TW_DEMO_JO_STS_HIST 在每次狀態變更時新增一筆：原狀態、新狀態、異動人、異動時間，不刪除。 |
| E-018 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §2 | 一筆職缺以「職缺編號」區分；同一職位再次開缺時建立新的職缺，取得新的職缺編號。 |
| E-019 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §2 | 一筆職缺可以招募多人，人數以「開缺人數」為準。 |
| E-020 | 檔案 | docs/business-spec/sample-jo/source/project.md §補充說明 | 職缺編號由系統給號，不沿用紙本申請單的編號。 |
| E-021 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §5 | 「D」＝草稿；「P」＝待核准；「A」＝已核准；「H」＝暫停；「R」＝已退回；「F」＝已補足；「C」＝已關閉；「X」＝已取消。 |
| E-022 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §5 | 「N」＝新增（新設的人力）；「R」＝遞補（補離職或調職員工的空缺）；「T」＝約聘（有合約期限）。 |
| E-023 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §4 | 關閉原因選項：「需求取消」「內部調任補足」「其他」；選「其他」時須在「關閉說明」填寫原因。 |
| E-024 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §7 | 審核紀錄 TW_DEMO_JO_APPR_TBL 以 TW_DJO_ID＋TW_DJO_APPR_LVL＋TW_DJO_SEQ 為鍵，每次核准或退回新增一筆。 |
| E-025 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §3 | 審核意見 \| TW_DJO_APPR_CMT \| 否 \| — \| 一律可改 \| 一律顯示 \| 核准或退回時的意見，會留在審核紀錄 |
| E-026 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §4 | R01 \| 儲存時 \| 開缺人數小於 1 或大於 20（1 與 20 都可以） \| 不得儲存 \| 「開缺人數須介於 1 到 20 之間」 |
| E-027 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §4 | R02 \| 送審時 \| 職缺類型為「遞補」且未選遞補對象 \| 不得送審 \| 「遞補職缺請選擇遞補對象」 |
| E-028 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §4 | R03 \| 送審時 \| 遞補對象在人事資料中的狀態不是「離職」也不是「調職」 \| 不得送審 \| 「遞補對象須為已離職或已調職的員工」 |
| E-029 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §4 | R04 \| 儲存時 \| 職缺類型為「約聘」且約聘迄日早於預計到職日 \| 不得儲存 \| 「約聘迄日不可早於預計到職日」 |
| E-030 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §4 | R05 \| 儲存時 \| 預計到職日早於今天（今天可以） \| 不得儲存 \| 「預計到職日不可早於今天」 |
| E-031 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §4 | R06 \| 送審時 \| 預計到職日距送審日 14 天內 \| 顯示警告，按「確定」後仍可送審 \| 「預計到職日距今不足 14 天，招募時間可能不足」 |
| E-032 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §4 | R07 \| 送審時 \| 同一職位已有狀態為「待核准」「已核准」「暫停」的其他職缺 \| 不得送審 \| 「此職位已有進行中的職缺，不可重複送審」 |
| E-033 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §4 | R08 \| 儲存時 \| 薪資範圍有填，且下限大於上限 \| 不得儲存 \| 「薪資範圍下限不可大於上限」 |
| E-034 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §2 | 開缺人數 6 人以上（含 6 人）：第一層核准後狀態仍為「待核准」，送人資主管做第二層核准；人資主管核准後狀態改為「已核准」。 |
| E-035 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §5 | R11 \| 按「退回」時 \| 未填退回原因 \| 不得退回 \| 「退回時請填寫退回原因」 |
| E-036 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §5 | R12 \| 按「核准」時 \| 核准者就是這個職缺的建立者 \| 不得核准 \| 「不可核准自己建立的職缺」 |
| E-037 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §5 | R13 \| 按「暫停」時 \| 未填暫停原因 \| 不得暫停 \| 「請填寫暫停原因」 |
| E-038 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §5 | R14 \| 按「關閉職缺」時 \| 未選關閉原因 \| 不得關閉 \| 「請選擇關閉原因」 |
| E-039 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §5 | R15 \| 按「關閉職缺」時 \| 關閉原因為「其他」且未填關閉說明 \| 不得關閉 \| 「關閉原因為其他時，請填寫關閉說明」 |
| E-040 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §5 | R16 \| 錄用作業回寫時 \| 已錄取人數等於開缺人數 \| 狀態改為「已補足」 \| 無 |
| E-041 | 檔案 | docs/business-spec/sample-jo/source/status.md §各狀態的意思 | 「草稿」：招募人員或用人主管建立職缺後、尚未送審的狀態，建立者可修改、送審或取消。 |
| E-042 | 檔案 | docs/business-spec/sample-jo/source/status.md §狀態圖 | [*] --> Draft : 建立職缺 |
| E-043 | 檔案 | docs/business-spec/sample-jo/source/status.md §各狀態的意思 | 「待核准」：已送審、等待核准者審核；這段期間建立者不可修改職缺內容。 |
| E-044 | 檔案 | docs/business-spec/sample-jo/source/status.md §各狀態的意思 | 「暫停」：暫時停止徵才，不接受新的應徵者。 |
| E-045 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §4 | 「暫停」的職缺不接受新的應徵者，已在甄選中的應徵者照常進行。 |
| E-046 | 檔案 | docs/business-spec/sample-jo/source/status.md §各狀態的意思 | 「已退回」：核准者退回，建立者可依退回原因修改後重新送審。 |
| E-047 | 檔案 | docs/business-spec/sample-jo/source/status.md §各狀態的意思 | 「已補足」：已錄取人數等於開缺人數，不再接受新的應徵者。 |
| E-048 | 檔案 | docs/business-spec/sample-jo/source/status.md §各狀態的意思 | 「已關閉」：職缺結束，不可重新開啟；要再招募須建立新職缺。 |
| E-049 | 檔案 | docs/business-spec/sample-jo/source/status.md §狀態圖 | Closed --> [*] |
| E-050 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §4 | 「已關閉」與「已取消」的職缺不可重新開啟；要再招募須建立新職缺。 |
| E-051 | 檔案 | docs/business-spec/sample-jo/source/status.md §各狀態的意思 | 「已取消」：職缺在核准前就取消，不可重新開啟。 |
| E-052 | 檔案 | docs/business-spec/sample-jo/source/status.md §狀態圖 | Canceled --> [*] |
| E-053 | 檔案 | docs/business-spec/sample-jo/source/status.md §誰觸發 | 建立職缺：招募人員或用人主管。 |
| E-054 | 檔案 | docs/business-spec/sample-jo/source/status.md §狀態圖 | Draft --> Pending : 送審 |
| E-055 | 檔案 | docs/business-spec/sample-jo/source/status.md §誰觸發 | 送審、取消、修改後重新送審：該職缺的建立者。 |
| E-056 | 檔案 | docs/business-spec/sample-jo/source/status.md §狀態圖 | Draft --> Canceled : 取消 |
| E-057 | 檔案 | docs/business-spec/sample-jo/source/status.md §狀態圖 | Pending --> Approved : 最後一層核准 |
| E-058 | 檔案 | docs/business-spec/sample-jo/source/status.md §誰觸發 | 核准、退回：核准者；第一層是用人主管的直屬主管，開缺人數 6 人以上（含 6 人）再加人資主管做第二層。 |
| E-059 | 檔案 | docs/business-spec/sample-jo/source/status.md §狀態圖 | Pending --> Returned : 退回 |
| E-060 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §2 | 任一層核准者按「退回」，狀態改為「已退回」，並通知建立者。 |
| E-061 | 檔案 | docs/business-spec/sample-jo/source/status.md §狀態圖 | Returned --> Pending : 修改後重新送審 |
| E-062 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §2 | 建立者修改後再按「送審」，從第一層重新核准；重新送審的次數不限。 |
| E-063 | 檔案 | docs/business-spec/sample-jo/source/status.md §狀態圖 | Returned --> Canceled : 取消 |
| E-064 | 檔案 | docs/business-spec/sample-jo/source/status.md §狀態圖 | Approved --> OnHold : 暫停 |
| E-065 | 檔案 | docs/business-spec/sample-jo/source/status.md §誰觸發 | 「暫停」與「恢復」只有招募人員可以執行；用人主管要暫停職缺時，須請招募人員處理。 |
| E-066 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §4 | 用人主管或招募人員可將「已核准」的職缺改為「暫停」，暫停時須填「暫停原因」。 |
| E-067 | 檔案 | docs/business-spec/sample-jo/source/status.md §狀態圖 | OnHold --> Approved : 恢復 |
| E-068 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §4 | 招募人員可將「暫停」的職缺恢復為「已核准」。 |
| E-069 | 檔案 | docs/business-spec/sample-jo/source/status.md §狀態圖 | Approved --> Filled : 錄取人數達開缺人數 |
| E-070 | 檔案 | docs/business-spec/sample-jo/source/status.md §誰觸發 | 「已核准」改為「已補足」：系統在已錄取人數達到開缺人數時自動變更。 |
| E-071 | 檔案 | docs/business-spec/sample-jo/source/status.md §狀態圖 | Approved --> Closed : 關閉 |
| E-072 | 檔案 | docs/business-spec/sample-jo/source/status.md §誰觸發 | 關閉「已核准」或「暫停」的職缺：招募人員。 |
| E-073 | 檔案 | docs/business-spec/sample-jo/source/status.md §狀態圖 | OnHold --> Closed : 關閉 |
| E-074 | 檔案 | docs/business-spec/sample-jo/source/status.md §狀態圖 | Filled --> Closed |
| E-075 | 檔案 | docs/business-spec/sample-jo/source/status.md §狀態圖 | 職缺（Job Opening）從建立到結束的狀態如下圖；圖下說明各狀態的意思與誰觸發轉移。 |
| E-076 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §9 | 人資主管請假時，第二層核准是否有代理人：未確認。 |
| E-077 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §6 | 人事資料 \| 取得 \| 職位清單，以及所選職位的部門、工作地點、部門主管 \| 職缺主頁選擇職位時 \| 取不到時不得儲存，顯示「查無此職位的人事資料，請洽人資」 |
| E-078 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §6 | 人事資料 \| 取得 \| 用人主管的直屬主管（第一層核准者） \| 送審時 \| 取不到時不得送審，顯示「找不到核准者，請洽人資」 |
| E-079 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §6 | 人事資料 \| 取得 \| 遞補對象的在職狀態 \| 送審時 \| 取不到時不得送審 |
| E-080 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §6 | 錄用作業 \| 取得 \| 已錄取人數（每錄用一人加 1） \| 錄用確認時 \| — |
| E-081 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §6 | 核准者（通知） \| 送出 \| 待審通知：職缺編號、職稱、送審人 \| 送審時；第一層核准後送第二層時 \| 見下方說明 |
| E-082 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §6 | 建立者（通知） \| 送出 \| 退回通知：職缺編號、職稱、退回原因 \| 退回時 \| 見下方說明 |
| E-083 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §6 | 招募人員、用人主管（通知） \| 送出 \| 核准通知：職缺編號、職稱、開缺人數 \| 狀態改為「已核准」時 \| 見下方說明 |
| E-084 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §6 | 招募人員、用人主管（通知） \| 送出 \| 補足通知：職缺編號、職稱、已錄取人數 \| 狀態改為「已補足」時 \| 見下方說明 |
| E-085 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §6 | 通知以公司電子郵件寄送。 |
| E-086 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §6 | 通知寄送失敗時不影響狀態變更，由招募人員視需要另行聯絡。 |
| E-087 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §6 | 招募人員 \| 被指派「招募人員」角色的人資同仁 \| 職缺維護 \| 新增；修改、送審、取消自己建立的職缺；修改任一職缺的「招募人員」欄位 \| 全部職缺 |
| E-088 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §6 | 用人主管 \| 人事資料中擔任部門主管的員工 \| 職缺維護 \| 新增；修改、送審、取消自己建立的職缺 \| 自己部門的職缺 |
| E-089 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §6 | 上層主管（第一層核准者） \| 用人主管在人事資料中的直屬主管 \| 職缺審核 \| 核准、退回 \| 輪到自己審核的職缺 |
| E-090 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §6 | 人資主管（第二層核准者） \| 被指派「人資主管」角色的同仁 \| 職缺審核、職缺維護（唯讀） \| 核准、退回開缺人數 6 人以上的職缺 \| 全部職缺 |
| E-091 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §4 | 招募人員可將「已核准」或「暫停」的職缺關閉，關閉時須選「關閉原因」。 |
| E-092 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §2 | 招募人員或用人主管用「職缺維護」建立職缺，填寫職稱、職位、開缺人數等資料後送審。 |
| E-093 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.1 | 查詢畫面有「新增職缺」按鈕，按下後開啟空白的職缺主頁，狀態為「草稿」。 |
| E-094 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §2 | 建立者在「職缺維護」按「送審」，通過檢核後狀態由「草稿」或「已退回」改為「待核准」。 |
| E-095 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §2 | 送審時從人事資料取得「用人主管」的直屬主管，作為第一層核准者。 |
| E-096 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §2 | 狀態改為「已核准」時，職缺開放徵才，並通知招募人員與用人主管。 |
| E-097 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.3 | 送審 \| TW_DJO_SUBMIT_PB \| 狀態為「草稿」「已退回」時顯示 \| 檢核通過後狀態改為「待核准」，並通知第一層核准者（見 02 §2） |
| E-098 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.3 | 取消職缺 \| TW_DJO_CANCEL_PB \| 狀態為「草稿」「已退回」時顯示 \| 顯示「確定要取消這個職缺嗎？」，按「是」後狀態改為「已取消」 |
| E-099 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §4 | 暫停 \| TW_DJO_HOLD_PB \| 狀態為「已核准」時顯示 \| 填暫停原因後狀態改為「暫停」 |
| E-100 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §4 | 恢復 \| TW_DJO_RESUME_PB \| 狀態為「暫停」時顯示 \| 狀態改為「已核准」 |
| E-101 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §4 | 關閉職缺 \| TW_DJO_CLOSE_PB \| 狀態為「已核准」「暫停」時顯示 \| 選關閉原因後狀態改為「已關閉」 |
| E-102 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §4 | 每錄用一人，錄用作業回寫「已錄取人數」加 1。 |
| E-103 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §4 | 已錄取人數等於開缺人數時，職缺自動改為「已補足」，並通知招募人員與用人主管。 |
| E-104 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.1 | 進入「職缺維護」先顯示查詢畫面，可用「職缺編號」「職稱」「部門」「狀態」任一條件查詢。 |
| E-105 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.1 | 查詢結果清單顯示：職缺編號、職稱、部門、開缺人數、狀態、建立日。 |
| E-106 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.1 | 查詢結果依建立日由新到舊排序。 |
| E-107 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.2 | 職缺編號 \| TW_DJO_ID \| — \| 「系統給號」 \| 唯讀 \| 一律顯示 \| 第一次儲存時由系統給號 |
| E-108 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.2 | 狀態 \| TW_DJO_STATUS \| — \| 「草稿」 \| 唯讀 \| 一律顯示 \| 職缺目前的狀態；代碼見 §5 |
| E-109 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.2 | 職稱 \| TW_DJO_TITLE \| 是 \| — \| 「草稿」「已退回」時可改 \| 一律顯示 \| 對外顯示的職缺名稱 |
| E-110 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.2 | 職位 \| TW_DJO_POSN \| 是 \| — \| 「草稿」「已退回」時可改 \| 一律顯示 \| 從人事資料的職位清單選擇；檢核見 R07 |
| E-111 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.2 | 部門 \| TW_DJO_DEPT \| 是 \| 依所選職位帶入 \| 唯讀 \| 一律顯示 \| 職位所屬的部門 |
| E-112 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.2 | 工作地點 \| TW_DJO_LOCATION \| 是 \| 依所選職位帶入 \| 「草稿」「已退回」時可改 \| 一律顯示 \| 實際上班地點，可改成職位預設以外的地點 |
| E-113 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.2 | 職缺類型 \| TW_DJO_TYPE \| 是 \| 「新增」 \| 「草稿」「已退回」時可改 \| 一律顯示 \| 選項見 §5 |
| E-114 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.2 | 遞補對象 \| TW_DJO_REPL_EMPL \| 職缺類型為「遞補」時必填 \| — \| 「草稿」「已退回」時可改 \| 職缺類型為「遞補」時顯示 \| 要遞補的原任員工；檢核見 R02、R03 |
| E-115 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.2 | 約聘迄日 \| TW_DJO_CONTRACT_END \| 職缺類型為「約聘」時必填 \| — \| 「草稿」「已退回」時可改 \| 職缺類型為「約聘」時顯示 \| 約聘合約的結束日；檢核見 R04 |
| E-116 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.2 | 開缺人數 \| TW_DJO_OPENINGS \| 是 \| 1 \| 「草稿」「已退回」時可改 \| 一律顯示 \| 這個職缺要招募的人數；檢核見 R01 |
| E-117 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.2 | 預計到職日 \| TW_DJO_TARGET_DT \| 是 \| — \| 「草稿」「已退回」時可改 \| 一律顯示 \| 希望新人到職的日期；檢核見 R05、R06 |
| E-118 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.2 | 薪資範圍 \| TW_DJO_SAL_RANGE \| 待確認 \| — \| 「草稿」「已退回」時可改 \| 一律顯示 \| 預計提供的月薪下限與上限；檢核見 R08 |
| E-119 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.2 | 用人主管 \| TW_DJO_HIRING_MGR \| 是 \| 職位所屬部門的主管（人事資料） \| 「草稿」「已退回」時可改 \| 一律顯示 \| 提出用人需求、面試後決定錄取的主管 |
| E-120 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.2 | 招募人員 \| TW_DJO_RECRUITER \| 是 \| — \| 「草稿」「已退回」「已核准」「暫停」時可改 \| 一律顯示 \| 負責這個職缺的招募人員 |
| E-121 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.2 | 職務說明 \| TW_DJO_JOB_DESCR \| 是 \| — \| 「草稿」「已退回」時可改 \| 一律顯示 \| 工作內容與應徵資格 |
| E-122 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.2 | 退回原因 \| TW_DJO_RETURN_RSN \| — \| — \| 唯讀 \| 狀態為「已退回」時顯示 \| 核准者退回時填寫的原因 |
| E-123 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.2 | 已錄取人數 \| TW_DJO_HIRED_CNT \| — \| 0 \| 唯讀 \| 狀態為「已核准」「暫停」「已補足」「已關閉」時顯示 \| 已確認錄用的人數，由錄用作業回寫 |
| E-124 | 檔案 | docs/business-spec/sample-jo/source/research/01-job-opening-create.md §3.3 | 儲存 \| （工具列） \| 狀態為「草稿」「已退回」「已核准」「暫停」時顯示 \| 存檔，狀態不變 |
| E-125 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §3 | 核准者進入「職缺審核」，清單只顯示輪到自己審核、狀態為「待核准」的職缺。 |
| E-126 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §3 | 清單顯示：職缺編號、職稱、部門、開缺人數、送審人、送審日，依送審日由舊到新排序。 |
| E-127 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §3 | 點選一筆後顯示職缺主頁的全部欄位（唯讀），下方有「審核意見」與「退回原因」兩個欄位。 |
| E-128 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §3 | 退回原因 \| TW_DJO_RETURN_RSN \| 按「退回」時必填 \| — \| 一律可改 \| 一律顯示 \| 退回的原因，會顯示在職缺主頁；未填訊息見 R11 |
| E-129 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §3 | 「核准」按鈕：按下後依 §2 第 3、4 步處理；檢核見 R12。 |
| E-130 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §3 | 「退回」按鈕：按下後狀態改為「已退回」，並通知建立者。 |
| E-131 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §8 | 情境 2（兩層核准）：假設開缺 8 人的職缺為「待核准」；當上層主管按「核准」；則狀態仍為「待核准」，人資主管收到待審通知。 |
| E-132 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §8 | 情境 3（退回未填原因）：假設職缺為「待核准」；當核准者未填退回原因就按「退回」；則顯示「退回時請填寫退回原因」，狀態仍為「待核准」。 |
| E-133 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §8 | 情境 4（補足）：假設開缺 2 人的職缺為「已核准」且已錄取 1 人；當錄用第 2 人；則狀態改為「已補足」，招募人員與用人主管收到補足通知。 |
| E-134 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §8 | 情境 5（關閉後不可重開）：假設職缺為「已關閉」；當招募人員開啟該職缺；則畫面上沒有任何可變更狀態的按鈕。 |
| E-135 | 檔案 | docs/business-spec/sample-jo/source/research/02-job-opening-approval.md §9 | 「暫停」的職缺是否還能接受應徵：已確認，見 §4（不接受新的應徵者）。 |

## 10.2 補查紀錄
無補查
