# 16 AI 實作指引

> `clone-0123456789abcdef/16`｜版本 r0001｜狀態 **in_review**｜L1 PASS · L2 PASS · L3 NOT_APPLICABLE · L4 NOT_APPLICABLE · L5 NOT_APPLICABLE
> 依賴文件：無｜未解問題：無
> 條款 10
> 本檔由 canonical JSON 以程式產生，請勿手改；修改走研究重跑或 19 的決策。

## 條款（AI）

### AI-001　READING

- 自然鍵：`AI:01`
- 條款類別：READING
- 條款內容：先讀 00-index：閱讀順序、ID 前綴對照、本版狀態。看到任何 ID，到前綴對照表指定的文件找定義；以 ID 為準，不以章節位置為準。
- 來源：框架模板

### AI-002　SCOPE

- 自然鍵：`AI:02`
- 條款類別：SCOPE
- 條款內容：只實作 01～19 本體列出的項目。90 問題清單中的圖外狀態與圖外轉移不實作，除非 19 有決策把它納入。
- 來源：框架模板

### AI-003　DATA

- 自然鍵：`AI:03`
- 條款類別：DATA
- 條款內容：07「不建置的原生欄位」所列欄位不建資料欄、不上畫面、不寫規則。DEPENDENCY 實體只建文件列出的欄位（最小介面）。
- 來源：框架模板

### AI-004　DATA

- 自然鍵：`AI:04`
- 條款類別：DATA
- 條款內容：狀態碼、選項儲存值、訊息原文一律保留原值；畫面文字可以調整，但不得更改儲存值。
- 來源：框架模板

### AI-005　LOGIC

- 自然鍵：`AI:05`
- 條款類別：LOGIC
- 條款內容：條件的空白語意照共同定義實作：字元欄空白＝NULL 或單一空白；數值欄未輸入視為 0；日期欄未輸入為 NULL。
- 來源：框架模板

### AI-006　UNKNOWN_HANDLING

- 自然鍵：`AI:06`
- 條款類別：UNKNOWN_HANDLING
- 條款內容：遇到 UNRESOLVED 或文件沒有說明的行為，不要自行補上；記下 ID 與問題回報，等待 19 的決策。
- 來源：框架模板

### AI-007　UNKNOWN_HANDLING

- 自然鍵：`AI:07`
- 條款類別：UNKNOWN_HANDLING
- 條款內容：NOT_APPLICABLE 表示已查證「沒有」，不要補做；它不是待辦。
- 來源：框架模板

### AI-008　SCOPE

- 自然鍵：`AI:08`
- 條款類別：SCOPE
- 條款內容：文件不指定技術。不要把原系統的 Component、Page、Record 結構當成必須照搬的架構；要保留的是可觀測行為與資料語意。
- 來源：框架模板

### AI-009　TRACEABILITY

- 自然鍵：`AI:09`
- 條款類別：TRACEABILITY
- 條款內容：在程式、測試與提交訊息標註實作的 ID（FR、BR、TC…），讓驗收能逐項對照 18 的完成條件。
- 來源：框架模板

### AI-010　CHANGE_DISCIPLINE

- 自然鍵：`AI:10`
- 條款類別：CHANGE_DISCIPLINE
- 條款內容：發現規格矛盾或錯誤時不要自行修改規格；回報 ID 與證據，由 19 的決策處理後再實作。
- 來源：框架模板
