# 08 API 與外部介接

文件：TR-SPEC-08｜版本 0.9｜狀態：已審閱

## 1. 共通

- 基底路徑 /api/tr/v1，格式 JSON；以 Bearer token 驗證，角色不符回 403。
- 錯誤回應：{ "code": "TR-E-004", "message": "…" }，訊息文字見 09 §6。

## 2. 內部 API

| 方法 | 路徑 | 用途 | 可呼叫角色 |
|---|---|---|---|
| GET | /api/tr/v1/sessions | 查詢梯次 | 全部 |
| POST | /api/tr/v1/enrollments | 送出報名或登記候補 | 員工 |
| POST | /api/tr/v1/enrollments/{id}/approve | 核准 | 直屬主管 |
| POST | /api/tr/v1/enrollments/{id}/reject | 退回 | 直屬主管 |
| POST | /api/tr/v1/enrollments/{id}/confirm | 確認 | 訓練承辦 |
| POST | /api/tr/v1/enrollments/{id}/cancel | 取消報名 | 依 03 §2 |
| PUT | /api/tr/v1/enrollments/{id}/attendance | 登錄出席結果 | 訓練承辦 |
| POST | /api/tr/v1/sessions/{id}/cancel | 取消梯次 | 訓練承辦 |

名額已滿時，POST /api/tr/v1/enrollments 回 409。

## 3. 外部介接
### 3.1 人事資料服務：取得直屬主管

| 項目 | 內容 |
|---|---|
| 時機 | 開啟報名單時帶出姓名、部門、直屬主管；送出時再查一次直屬主管，寫入審核主管 |
| 呼叫 | GET {HR_BASE}/employees/{emplid}/supervisor |
| 回傳 | supervisorId、supervisorName、deptId |
| 逾時與重試 | 逾時 3 秒，重試 2 次 |

### 3.2 郵件通知服務：審核結果通知

| 項目 | 內容 |
|---|---|
| 時機 | 主管核准或退回後 |
| 收件者 | 核准：員工、訓練承辦；退回：員工 |
| 內容 | 課程名稱、上課日期、審核結果、審核意見 |
| 呼叫 | POST {NOTIFY_BASE}/mail，範本 TR_MAIL_APV／TR_MAIL_REJ |
| 失敗 | 通知僅為告知；寄送失敗不影響報名狀態 |
