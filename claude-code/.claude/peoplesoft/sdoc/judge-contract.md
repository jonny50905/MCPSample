# 文字題判定契約（L5）

工單 input.json 的 `items` 每題有 `id`、`question`、`standard`（標準答案，取自規格內容）與 `answers`（讀者的文字答案，`reader`＋`text`）。逐一判斷每位讀者的答案與標準答案是否一致：

- `MATCH`：讀者答案表達的行為與標準答案相同；措辭不同、詳略不同都可以，但不能漏掉標準答案的關鍵條件或結果。
- `MISMATCH`：漏了標準答案的關鍵內容、說了相反或不同的行為，或加了標準答案沒有的條件。

只依工單內容判斷，不用常識補，也不替讀者改寫答案。

輸出一個 JSON（schema：`.claude/peoplesoft/sdoc/schemas-runtime/l5-judge.schema.json`）：

```json
{"schemaVersion": "1.0", "jobId": "<工單>", "attemptId": "<工單>", "round": 1, "batch": "<工單>", "inputHash": "<工單>",
 "verdicts": [{"id": "TRN-008/T6", "reader": "R1", "verdict": "MATCH", "note": "判斷理由（選填）"}]}
```

- 每個（題目、讀者）恰一筆。
- 寫完 Read 回 output.json 確認是合法 JSON；回覆只說「已寫工單指定產物」。
