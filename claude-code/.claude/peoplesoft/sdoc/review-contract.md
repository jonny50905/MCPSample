# Spec 文件覆核契約

你是獨立 session 的覆核者。另一個 session 寫了一頁研究包（工單 input.json 的 `packet`）；外環已驗過格式、參照、分母與上游需求的處置。你要核對的是內容：每個項目有沒有證據、對不對、完不完整。通過的研究包才會寫進文件。

## 怎麼覆核

- 先讀本契約、`.claude/peoplesoft/sdoc/research-contract.md` 的通用規則與本單元一節、工單的 `fields.md`、可引用清單與已驗收文件中相關的部分。
- 不沿用研究者的 `summary` 與自評。逐項重取決策性原始證據：CHUNK 用 PeoplecodeSource 取回該段落、SQL 重查（同樣只准單一 SELECT／WITH）、NN／wiki 讀該行。委派、開線、上限與禁止事項照研究契約的「查證方法」。
- 逐項核對：
  - 證據真的支持項目內容（不是只有相關）；摘錄與原始來源一致。
  - 條件、儲存值、Record.Field、事件、訊息原文正確；AND／OR、優先序、空白／0／NULL／日期邊界沒有漏。
  - 本單元必須處置的分母鍵，寫成項目的有內容、開 EVIDENCE_GAP 的確實查不到（不是沒去查）。
  - `INFERRED` 的推論鏈站得住；`NA` 有理由與證據，不是把查不到寫成不適用。
  - 沒有把範圍外、未使用的功能寫進來；沒有描述範圍單元判定不建置的欄位。
  - 與已驗收的其他頁、其他 Component 沒有矛盾（同一欄位、狀態碼、交易、介面的說法一致）。
- 各單元特別檢查：
  - scope：EXCLUDED 沒有誤排業務在用的物件；XF 的資料彙總是全表、非預設值有比對預設常數、環境是 PROD、查法 a／b／c 都有結果；`fieldUsage` 與證據一致；分母清單沒有漏頁、漏欄位。
  - data：狀態欄位的值域只列圖上代碼；衍生概念的查找規則、查無與多筆的處理有證據。
  - workflow：守衛與觸發和線上文字一致；守門轉移的條件與檢查時機照程式；圖外分級（HIGH／LOW／只計數）正確。
  - texts：每行的處置合理，活動的 `behavior` 是該行原文，負責人對應到角色或衍生概念。
  - rules：每支程式的處置對得上程式內容；原生未使用分支的證明成立（SQL 查全表、沒有漏掉會寫入該值的路徑、範圍外情境真的在範圍外）。
  - functions、operations、testing：推導的來源項目確實存在且被正確引用；測試覆蓋規則分支與拒絕路徑，不是只有樂觀路徑。
- 來源不足以判斷完整性、或工具故障無法重取證據時判 BLOCKED，不能只看 JSON 合法就 PASS。

## 輸出

只寫 input.json 的 `outputPath`（schema：`.claude/peoplesoft/sdoc/schemas-runtime/review.schema.json`）：

```json
{"schemaVersion": "1.0", "jobId": "<本工單>", "attemptId": "<本工單>", "unit": "<本工單>", "subject": "<本工單>",
 "page": 1, "inputHash": "<本工單>", "verdict": "PASS",
 "checkedKeys": ["FLD/TW_X.AMOUNT"], "findings": [], "summary": "逐項重取證據核對的結果"}
```

- `jobId`、`attemptId`、`unit`、`subject`、`page`、`inputHash` 照本次覆核的工單（不是研究包的）。
- `checkedKeys`：確實逐項核對過的項目，寫「型別/自然鍵」（例 `FLD/TW_X.AMOUNT`）。
- `PASS`：`checkedKeys` 正好是研究包全部項目，`findings` 空。
- `FAIL`：`findings` 至少一筆，每筆 `{"key": "型別/自然鍵 或 TOPIC", "code": …, "detail": "可修的具體差異"}`；研究者下一次會看到 `detail`，寫清楚錯在哪、正確的是什麼、證據在哪。整頁層級的缺漏用 `TOPIC`。
- `BLOCKED`：工具故障或來源不足；`findings` 寫原因（例 `TOOL_BLOCKED`）。

| code | 用在 |
|---|---|
| `MISSING_DETAIL` | 缺必要細節（條件、欄位、例外、邊界） |
| `MISSING_BRANCH` | 漏了分支或拒絕路徑 |
| `EVIDENCE_MISMATCH` | 證據不支持內容，或摘錄與來源不符 |
| `SCOPE_NOISE` | 寫進了範圍外、未使用或判定不建置的東西 |
| `CONTRADICTION` | 與其他已驗收內容矛盾 |
| `LANGUAGE` | 不是繁體中文，或翻譯了應保留原文的識別字 |
| `TOOL_BLOCKED` | 工具故障、權限不足，無法重取證據 |
| `VAGUE_TERM` | 用了未定義的概念（例如「長官」沒有對應到角色或衍生概念） |
| `INFERENCE_UNSUPPORTED` | 推論缺證據鏈 |
| `DUPLICATE_KEY` | 同一件事換了自然鍵重複寫 |

- PASS 不代表企業實跑或重建等價驗證已完成。
- 寫完 Read 回 output.json 確認是合法 JSON；回覆只說「已寫工單指定產物」。
