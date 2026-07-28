---
aliases: []                # 中英文別名、口語簡稱——查重與反查靠這個，必填
type: RECORD               # RECORD | COMPONENT | PAGE | FIELD | SQR | SQC | AE | SQL | PROCESS | OTHER
origin: CUSTOM_PREFIX      # CUSTOM_PREFIX | CUSTOM_REGISTRY | MODIFIED_DELIVERED | DELIVERED | UNKNOWN
status: draft              # draft（未驗證）| verified（稽核通過）| stale（來源已變/逾期）
confidence: 0.5            # 0.0 ~ 1.0
last_verified: YYYY-MM-DD
sources: []                # 依據的 chunk UUID / SQL 摘要（時效偵測鍵）
reviewed: false            # true = 人工審定——agent 不得覆寫既有內容，只能追加
---
# <物件名>

<一句話定位：這個物件是什麼、屬於哪個業務。>

## Observations

<!-- 一行一個事實：- [分類] 事實 (evidence)。分類例：結構 / 行為 / 資料 / 選項 / 排程 / 權限 -->
- [結構] MIL_STATUS 為 Translate value，共 5 值（chunk `3f2a9c1e-7b4d-4e8a-9c6f-1d2e3a4b5c6d` / SQL）

<!-- chunk id 一律完整 36 字元 UUID（如上例），禁止縮寫成前 8 碼 -->
- [行為] 值 'E' 時開放 EXEMPT_RSN 並帶入日期（`<filePath>:<行號>`）

## Relations

<!-- 一行一條 typed 關係，目標一律 [[wikilink]]。
     常用：part_of / contains / reads / writes_to / written_by /
           called_by / calls / triggered_by / secured_by -->
- part_of [[兵役]]
- written_by [[TW_MIL001]]

## Invalidated（作廢紀錄——只追加，不刪除）

<!-- 事實變更時：舊事實移到這裡標日期與原因，新事實寫回 Observations -->
- YYYY-MM-DD 作廢：「<舊事實>」→ 改為「<新事實>」（原因 / evidence）
