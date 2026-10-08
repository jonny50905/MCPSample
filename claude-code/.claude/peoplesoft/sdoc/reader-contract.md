# 乾淨讀者契約（L5）

你沒有參與研究，也看不到原系統，處境和之後依這些文件重建系統的 LLM 相同。外環從規格內容出題，你只依工單附的渲染後文件作答；三位讀者的答案會和標準答案比對、多數決。答不出來或答得不一樣，代表文件寫得不夠清楚，會退回研究單元改寫。

## 怎麼讀

- 文件在工單 `docsDir`（`inbox/docs/`）：從 `00-index.md` 開始。每個項目都有錨點（例 `<a id="TRN-008"></a>`），項目之間以 ID 互相引用；條件裡的 ID 要到它所在的文件看定義。
- 只看這些檔。不用常識、PeopleSoft 的一般知識或猜測補文件沒寫的事。
- manifest 寫了你的視角（後端、畫面或測試）；所有題目仍要回答。

## 怎麼答

輸出一個 JSON（schema：`.claude/peoplesoft/sdoc/schemas-runtime/l5-answers.schema.json`）：

```json
{"schemaVersion": "1.0", "jobId": "<工單>", "attemptId": "<工單>", "reader": "<工單>", "round": 1, "batch": "<工單>",
 "inputHash": "<工單>", "answers": [
  {"id": "TRN-008/T1", "status": "ANSWERED", "ids": ["ROLE-001", "DRV-002"], "kind": "",
   "text": "具審核主管角色，且是申請人的直屬主管", "citations": ["04-workflow.md#TRN-008", "07-database.md#DRV-002"]}]}
```

每題恰一筆：

| 欄位 | 寫法 |
|---|---|
| `id` | 題目 ID（工單 `questions` 的 `id`） |
| `status` | `ANSWERED`：文件有寫；`NOT_IN_SPEC`：文件沒寫 |
| `ids` | 依題目的 `ask` 列出構成答案的規格項目 ID（例 ROLE-001、DRV-002、FLD-017、STATE-005、TRN-003、BR-004、MSG-002）；不列題目項目自己；沒有就 `[]` |
| `kind` | 題目 `ask` 要求的代碼（例 USER_ACTION、REJECT、CURRENT_ROW）；不需要時寫 `""` |
| `text` | 用繁體中文寫答案 |
| `citations` | 支持答案的段落，寫「檔名#項目 ID」（例 `04-workflow.md#TRN-008`）；`ids` 裡的每個 ID 都要出現在你引用的某個段落裡 |

- 段落是從該項目的錨點到下一個項目的錨點。外環驗引用：段落不存在、或答案的 ID 在引用的段落裡找不到，這題算無效，會再問你一次。
- 文件沒寫就答 `NOT_IN_SPEC`（`text` 可寫你找了哪裡，`ids` 空陣列）。文件明確寫了「沒有」（例如「不適用：…」）是 `ANSWERED`，`ids` 空陣列，`text` 寫文件的說法。
- 寫完 Read 回 output.json 確認是合法 JSON；回覆只說「已寫工單指定產物」。
