# 90 問題清單

> `clone-0123456789abcdef/90`｜版本 r0001｜狀態 **in_review**｜L1 PASS · L2 PASS · L3 NOT_APPLICABLE · L4 NOT_APPLICABLE · L5 NOT_APPLICABLE
> 依賴文件：01、07、08｜未解問題：無
> 問題 3（OPEN 1、ANSWERED 1、WITHDRAWN 1）；未解 BLOCKING 0；只計數的定義值 2
> 本檔由 canonical JSON 以程式產生，請勿手改；修改走研究重跑或 19 的決策。

只存在於值域定義、沒有資料也沒有核心程式使用的狀態碼：2 個（REQ_STATUS=040、REQ_STATUS=050），只計數、不列題。

## 問題（Q）

### Q-001　OFF_DIAGRAM_STATE:REQ_STATUS:099

- 自然鍵：`OFF_DIAGRAM_STATE:REQ_STATUS:099`
- 問題類別：OFF_DIAGRAM_STATE
- 是否阻擋完成：INFO
- 圖外分級：HIGH＝PROD 有資料；LOW＝僅核心程式賦值：HIGH
- 問題敘述：PROD 有 REQ_STATUS＝099 的資料，但狀態圖沒有這個狀態。是歷史資料（只需資料移轉對應），還是狀態圖漏畫？
- 受影響的規格項目：FLD-017（TW_DEMO_REQHDR.REQ_STATUS）
- 觀察到的狀態碼／轉移／位置：
  - 狀態實體：REQ_STATUS
  - 代碼：099
- 提出來源：RESEARCH
- 狀態（ANSWERED／ACCEPTED_AS_GAP 由 19 的決策反查）：OPEN
- 來源：外環計算；證據 EV-0011

### Q-002　OFF_DIAGRAM_TRANSITION:REQ_STATUS:030>010

- 自然鍵：`OFF_DIAGRAM_TRANSITION:REQ_STATUS:030>010`
- 問題類別：OFF_DIAGRAM_TRANSITION
- 是否阻擋完成：INFO
- 圖外分級：HIGH＝PROD 有資料；LOW＝僅核心程式賦值：LOW
- 問題敘述：TW_DEMO_APV.PostBuild 在特殊參數下會把 030 改回 010（核准後重開），狀態圖沒有這條轉移。要不要重建？
- 受影響的規格項目：OBJ-007（TW_DEMO_APV.PostBuild）
- 觀察到的狀態碼／轉移／位置：
  - 狀態實體：REQ_STATUS
  - 起：030
  - 迄：010
  - 位置：TW_DEMO_APV.PostBuild
- 提出來源：RESEARCH
- 狀態（ANSWERED／ACCEPTED_AS_GAP 由 19 的決策反查）：ANSWERED
- 研究端建議的答案（不等於決策）：看起來是管理者的資料維護入口，不是業務流程。
- 來源：外環計算；證據 EV-0025
- 被引用（外環反查）：DEC-001

### Q-003　READER_UNDERSPECIFIED:TW_DEMO_APV:APPROVE:APPROVE#concurrency

- 自然鍵：`READER_UNDERSPECIFIED:TW_DEMO_APV:APPROVE:APPROVE#concurrency`
- 問題類別：READER_UNDERSPECIFIED
- 是否阻擋完成：BLOCKING
- 問題敘述：兩位審核者同時核准同一張單時，後存檔者看到什麼、資料變成怎樣，文件沒有說明（原文只寫「原系統有檢查」）。
- 受影響的規格項目：OP-001（核准申請）
- 提出來源：READER
- 狀態（ANSWERED／ACCEPTED_AS_GAP 由 19 的決策反查）：WITHDRAWN
- 來源：外環計算
