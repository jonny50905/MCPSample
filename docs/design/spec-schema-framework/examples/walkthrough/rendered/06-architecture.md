# 06 系統架構（技術中立）

> `clone-0123456789abcdef/06`｜版本 r0001｜狀態 **in_review**｜L1 PASS · L2 PASS · L3 PASS · L4 PASS · L5 PASS
> 依賴文件：01、04、07｜未解問題：無
> 介面 1；未解問題 0
> 本檔由 canonical JSON 以程式產生，請勿手改；修改走研究重跑或 19 的決策。

## 介面與批次（IF）

### IF-001　送審通知

- 自然鍵：`AE:TW_DEMO_NTFY`
- 介面型別：NOTIFICATION
- 原系統物件：OBJ-001（TW_DEMO_NTFY）
- 業務名稱：送審通知
- 方向：OUTBOUND
- 觸發方式：
  - 種類：ON_TRANSITION
  - 轉移：TRN-002（010→020）、TRN-004（015→020）
  - 說明：送出成功後由 SavePostChange 排入程序，非同步執行。
- 本介面執行的狀態轉移：（無）
- 讀取欄位：FLD-016（TW_DEMO_REQHDR.REQ_ID）、FLD-015（TW_DEMO_REQHDR.REQUESTER_EMPLID）、FLD-010（TW_DEMO_REQHDR.AMOUNT）、FLD-009（TW_DEMO_EMP.SUPERVISOR_ID）
- 寫入欄位：（無）
- 參數／Run Control：
  - 名稱：REQ_ID；來源：FLD-016（TW_DEMO_REQHDR.REQ_ID）
- 格式、編碼、欄位順序：不適用：不是檔案介面
- 錯誤處理：寄送失敗只寫入程序紀錄，不影響申請單狀態。
- 重試：不適用：原系統不重試
- 重送／重複執行的結果：同一張單重複排入會重複寄送通知。
- 來源：程式；證據 EV-0028、EV-0033
- 被引用（外環反查）：BR-001；OP-004
