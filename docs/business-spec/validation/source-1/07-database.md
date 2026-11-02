# 07 資料庫設計

文件：TR-SPEC-07｜版本 0.9｜狀態：已審閱

## 1. 資料表

TR_COURSE_TBL（課程主檔，主鍵 COURSE_ID＋EFFDT，依生效日期）、TR_SESSION_TBL（梯次，主鍵 SESSION_ID）、TR_ENROLL_TBL（報名，主鍵 ENROLL_ID）、TR_ENROLL_LOG（報名狀態異動紀錄，主鍵 ENROLL_ID＋SEQ_NBR）。

## 2. TR_COURSE_TBL 課程主檔

| 欄位 | 型別 | 長度 | 必填 | 說明 |
|---|---|---|---|---|
| COURSE_ID | VARCHAR | 8 | Y | 課程代碼 |
| EFFDT | DATE | — | Y | 生效日期 |
| EFF_STATUS | CHAR | 1 | Y | 課程狀態，見 §6 |
| COURSE_NAME | VARCHAR | 60 | Y | 課程名稱 |
| TR_CATEGORY | CHAR | 1 | Y | 課程類別，見 §6 |
| TR_HOURS | DECIMAL | 4,1 | Y | 課程時數 |
| TR_COST | DECIMAL | 9,2 | N | 課程費用（本期不使用） |

課程名稱、類別、時數等異動時，新增一筆新生效日期的資料，不覆蓋舊資料。報名與出席紀錄一律顯示上課開始日當時有效的課程資料。

## 3. TR_SESSION_TBL 梯次

欄位同 05 §6.2，另有 SESSION_ID（VARCHAR 12，課程代碼＋梯次編號）與 COURSE_ID（VARCHAR 8）。梯次編號在同一課程內遞增。索引：IDX_SESSION_01（COURSE_ID, START_DT）。

## 4. TR_ENROLL_TBL 報名

| 欄位 | 型別 | 長度 | 必填 | 說明 |
|---|---|---|---|---|
| ENROLL_ID | DECIMAL | 10 | Y | 序號 |
| EMPLID | VARCHAR | 11 | Y | 報名員工 |
| SESSION_ID | VARCHAR | 12 | Y | 梯次 |
| SUPV_ID | VARCHAR | 11 | Y | 審核主管：送出時帶入，之後人事異動不改 |
| ENROLL_STATUS | CHAR | 3 | Y | 報名狀態，見 §6 |
| ENROLL_REASON | VARCHAR | 200 | N | 報名理由 |
| MEAL_PREF | CHAR | 1 | N | 用餐需求，見 §6 |
| APPROVER_CMT | VARCHAR | 254 | N | 審核意見 |
| ADMIN_NOTE | VARCHAR | 254 | N | 承辦備註 |
| SUBMIT_DTTM | TIMESTAMP | — | Y | 送出或登記候補的時間 |

索引：IDX_ENROLL_01（SESSION_ID, ENROLL_STATUS）。

## 5. TR_ENROLL_LOG 報名狀態異動紀錄

報名狀態每異動一次寫一筆：原狀態、新狀態、異動人、異動時間。紀錄只增不改，不可刪除。

## 6. 代碼值

| 欄位 | 代碼與意思 |
|---|---|
| EFF_STATUS | A 有效；I 停用（不可再開設新梯次，已開設的梯次不受影響） |
| TR_CATEGORY | T 專業技術；M 管理職能；C 法規遵循 |
| ENROLL_STATUS | SUB 已送出；WTL 候補；APV 主管核准；REJ 主管退回；CNF 已確認；CXL 已取消；CMP 完訓；ABS 缺席 |
| SESSION_STATUS | O 開放報名；D 報名截止；E 已結束；X 已取消 |
| MEAL_FLAG | Y 有供餐；N 無供餐 |
| MEAL_PREF | G 一般；V 素食；N 不用餐 |
