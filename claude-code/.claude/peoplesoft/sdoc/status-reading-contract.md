# 狀態圖解讀契約

STATUS 檔是業務單位畫的狀態流程，是 04 流程的權威來源。三位讀者各自獨立解讀同一份檔；外環把三份解讀拆成一項一項的事實比對，三份都有的直接採用，不一致的再逐項問三位讀者（第 2 輪），多數決。採用的事實就是 04 的狀態、轉移、情境，研究只能補細節、不能增減。

所以照圖上畫的寫：不補圖上沒有的東西，也不省略圖上有的東西。看不懂或兩張圖互相矛盾時照實寫出來（`conflicts`），不要自己取捨。

## 共通

- 只讀 STATUS 檔（工單 input.json 的 `statusPath`）；不查程式、資料庫或其他文件。
- 圖的畫法不限：Mermaid flowchart、stateDiagram-v2 都可能出現；大框框可能是 subgraph 或複合狀態；子業務可能獨立畫、合在大圖上，或兩者都有。依圖的意思解讀，不依畫法。
- 行號是 STATUS 檔從 1 起算的實際行號（標題、空行、圖外的說明都算行）。
- 只有 Mermaid 區塊（` ```mermaid ` 到 ` ``` ` 之間）的行要交代；圖外的說明區域由後面的研究處置，不寫進解讀。
- 外環檢查 schema 與逐行交代，不合格會退回重寫；manifest 的「前次未通過的原因」要先修正。

## 第 1 輪：寫一份解讀（工單種類 STATUS_READ）

輸出一個 JSON 物件（schema：`.claude/peoplesoft/sdoc/schemas/status-reading.schema.json`）：

```json
{"schemaVersion": "1.0", "jobId": "<工單 jobId>", "reader": "<工單 reader>", "round": 1,
 "source": {"ref": "status.md", "fingerprint": "<工單 statusFingerprint>"},
 "states": [], "transitions": [], "otherLines": [], "conflicts": []}
```

### 狀態實體

- 一條獨立的狀態流程是一個狀態實體：主業務一個，每個子業務各一個。每個實體取一個大寫代號（英數與底線，例如 `CASE_STATUS`、`DOCREV_STATUS`），整份解讀同一個實體用同一個代號。
- 代號自己取；外環會依引用的行把三位讀者的實體對齊，不必猜別人取什麼。

### states：每個狀態一筆

| 欄位 | 寫法 |
|---|---|
| `entity` | 狀態實體代號 |
| `code` | 三位數字狀態碼（含前導 0，例 `010`） |
| `name` | 圖上的名稱原文 |
| `final` | 是否終點：圖上明示結束，或沒有往外的線 |
| `lines` | 這個狀態出現的所有行（節點宣告、名稱定義、大框框的開頭等） |
| `regions` | 這個狀態裡進行的子業務（大框框裡的子流程、複合狀態裡的平行區塊）：每個子業務 `{"entity": 子業務代號, "lines": [框或區塊開頭的行]}`；沒有就 `[]` |

- 同一個狀態在大圖與獨立圖都出現，只寫一筆，`lines` 列出每個出現的行。
- 子業務的狀態屬於子業務實體，不屬於主業務。

### transitions：每條轉移一筆

| 欄位 | 寫法 |
|---|---|
| `entity` | 狀態實體代號 |
| `from` | 起點狀態碼；從開始符號（`[*]`、圓形開始節點）出發的新建寫 `"*"` |
| `to` | 目標狀態碼 |
| `via` | 經過的判斷節點的文字原文（菱形、choice 等）；沒有就 `[]` |
| `labels` | 線上文字原文中「不是情境類型」的部分；沒有就 `[]` |
| `scenario` | 線上文字表示的情境類型原文（例如「主流程」「退回補件」）；沒有就 `null` |
| `lines` | 構成這條轉移的所有行（線本身、經過的判斷節點的宣告與出線） |

- 一條線經過判斷節點分岔到幾個目標，就是幾條轉移，`via` 都寫那個判斷節點。
- 從大框框（裡面有子業務的狀態）連出去的線，是主業務從那個狀態出發的轉移，線上文字照原文寫。
- 同一段線上文字可以同時是情境類型又帶描述：情境類型寫 `scenario`，其餘原文寫 `labels`。
- 大圖只畫摘要、獨立圖畫完整時，照完整的流程寫。看得出是摘要的捷徑線不寫成轉移，在 `otherLines` 以 `NO_SPEC_CONTENT` 交代（`note` 寫是哪張圖的摘要）；看不出是不是摘要，就寫進 `conflicts`。

### otherLines：沒被引用的每一行

Mermaid 區塊裡每一個非空行，要嘛被 `states`、`regions`、`transitions` 的 `lines` 引用，要嘛列在 `otherLines`，而且只交代一次。

| `disposition` | 什麼行 | 其他欄位 |
|---|---|---|
| `NO_SPEC_CONTENT` | 圖的宣告（`flowchart TD`、`stateDiagram-v2`）、框的結尾（`end`、`}`）、方向、樣式（`classDef`、`style`、`class`）、看得出是摘要的線 | `note` 必填，寫理由；不得寫 `entity`、`code` |
| `TEXT` | 圖上的業務文字，例如 note、狀態描述裡寫「這個階段誰該做什麼」 | 可附 `entity`、`code` 指出在說哪個狀態 |

- 理由相同的行可以合成一筆（例如所有 `end` 寫成一筆 `{"lines": [13, 17, 18], "disposition": "NO_SPEC_CONTENT", "note": "subgraph 的結尾"}`）。
- 已被狀態或轉移引用的行，不要再列進 `otherLines`；同一行不能列兩次。

### conflicts：圖與圖的矛盾

- 同一件事在兩張圖畫得不一樣、又看不出是摘要（例如大圖有 `040→060`，獨立圖沒有）：`{"description": "哪裡不一致", "lines": [相關的行]}`。沒有就 `[]`。

## 第 2 輪：逐項確認（工單種類 STATUS_ROUND2）

工單 input.json 的 `questions` 是第 1 輪三份解讀不一致的事實，每題 `{id, fact, lines}`，`lines` 附了引用的行號與原文。回頭讀 STATUS 檔對應的行，逐題判斷「是不是這樣」：

- `YES`：圖上確實如此。
- `NO`：圖上不是這樣。
- `UNSURE`：圖本身看不出來。只在真的無法判斷時用；仍無多數的事實會交人把 STATUS 檔改清楚。

輸出（schema：`.claude/peoplesoft/sdoc/schemas-runtime/status-round2.schema.json`）：

```json
{"schemaVersion": "1.0", "jobId": "<工單 jobId>", "reader": "<工單 reader>", "round": 2,
 "source": {"ref": "status.md", "fingerprint": "<工單 statusFingerprint>"},
 "answers": [{"id": "F01", "answer": "YES", "note": "第 33 行的線從 020 指向 025"}]}
```

- 每題恰好回答一次；`note` 選填，寫判斷依據。
