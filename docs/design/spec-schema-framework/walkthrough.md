# 貫穿範例：申請／審核（合成）

> [設計提案](../spec-schema-framework.md)的附件。全部是合成資料：
>
> - Component：`TW_DEMO_REQ`（申請）、`TW_DEMO_APV`（審核）。
> - 狀態碼：010～090。
> - 人員：E1001 申請人、E2001 直屬主管、E3001 部門主管。
>
> 本範例的檔案：
>
> - [input/](examples/walkthrough/input/)：使用者提供的輸入。
> - [canonical/](examples/walkthrough/canonical/)：外環產生的 JSON。
> - [rendered/](examples/walkthrough/rendered/00-index.md)：讀者看到的 Markdown。
> - [readings/](examples/walkthrough/readings/)：三位讀者的狀態圖解讀（本範例三份相同）。
> - [gate-report.json](examples/walkthrough/gate-report.json)：檢核結果。
>
> §9 另用第二組合成資料示範子業務守門，以及三份解讀不一致時怎麼處理，檔案在 [examples/gate/](examples/gate/)。
>
> 以上都由同一份 schema 與範例定義產生並驗證（設計期腳本，未放進 repo）；本頁的表格與程式碼區塊也是同一次產生的。

## 1. 情境

- **主流程**：員工在申請畫面建立申請單（金額、事由），存檔後是草稿（010）。送出後（020）由直屬主管審核：
  - 金額不超過 50000：核准即結案（030）。
  - 金額超過 50000：轉給部門主管再審（025），部門主管核准後結案（030）。
- **退回**：審核者可以填意見退回（015）；申請人補件後重新送出，回到直屬主管審核。
- **撤回**：草稿或退回中的申請單可以撤回作廢（090）。

舊系統另有幾個「產品內建、業務沒在用」或「圖上沒有」的東西，用來示範主文件 §8.6、§8.8 的處理（本頁 §8）：

- 審核 Component 載入時，有一段程式在特殊參數下會把核准單改回草稿（030→010），狀態圖沒有這條轉移。
- PROD 還有舊制的狀態碼 099 的資料。
- 狀態欄位的值域另定義了 040、050，但沒有資料，也沒有核心程式使用。
- 申請單主檔有兩個原生欄位（`OLD_REF_NO`、`PRIORITY_CD`）全表沒有值，核心程式也沒有引用。
- 金額檢核程式有一段原生分支：申請類別是 INT（內部）時改查內部預算。PROD 沒有 INT 的資料，INT 在值清單也已停用。

STATUS 檔圖下方的說明區域寫了幾個階段誰該做什麼，用來示範說明文字的處置（本頁 §7）。

## 2. 輸入

[STATUS 文件](examples/walkthrough/input/status-REQ_STATUS.md)內有兩張圖。flowchart 的邊標情境類型：

```mermaid
flowchart TD
    START((開始)) -->|主流程| N010["010 草稿"]
    N010 -->|主流程| N020["020 待主管審核"]
    N020 -->|主流程| D1{金額判斷}
    D1 -->|主流程| N030["030 核准"]
    D1 -->|高額審核| N025["025 待部門主管審核"]
    N025 -->|高額審核| N030
    N020 -->|退回補件| N015["015 退回補件"]
    N025 -->|退回補件| N015
    N015 -->|退回補件| N020
    N010 -->|撤回作廢| N090["090 作廢"]
    N015 -->|撤回作廢| N090
```

stateDiagram-v2 的線上沒有描述，金額分岔用 `<<choice>>`：

```mermaid
stateDiagram-v2
    state "010 草稿" as S010
    state "015 退回補件" as S015
    state "020 待主管審核" as S020
    state "025 待部門主管審核" as S025
    state "030 核准" as S030
    state "090 作廢" as S090
    state amount_check <<choice>>
    [*] --> S010
    S010 --> S020
    S015 --> S020
    S020 --> amount_check
    amount_check --> S030
    amount_check --> S025
    S025 --> S030
    S020 --> S015
    S025 --> S015
    S010 --> S090
    S015 --> S090
    S030 --> [*]
    S090 --> [*]
```

圖下方的說明區域寫的是「這個階段誰該做什麼」（§7）：

```markdown
## 說明

- 020 待主管審核：直屬主管審核申請內容。
- 025 待部門主管審核：部門主管審核。
- 090 作廢：作廢的申請單不能再修改。
```

[專案輸入檔](examples/walkthrough/input/project.md)提供目標與決策責任（業務單位主管、業務承辦窗口）。

狀態圖全部在同一份 STATUS 檔。這個範例只有一個狀態實體 `REQ_STATUS`；它的狀態欄位 `TW_DEMO_REQHDR.REQ_STATUS` 由資料研究提出，外環檢查欄位值域包含圖上每個狀態碼（R07）。

## 3. 外環先做的事：三份解讀與比對

研究開始前，三位讀者各自讀整份 STATUS 檔，寫狀態圖解讀（主文件 §8.2）。讀者看得懂兩張圖畫的是同一件事：

- `D1{金額判斷}` 與 `amount_check` 是判斷節點，不是狀態；經過它的轉移記下 `via`。
- 線上的標籤都是情境類型，所以每條轉移都歸入一個情境，沒有要帶進轉移的描述。
- 終點看 stateDiagram 的 `X --> [*]`。

下面是讀者 R1 的解讀節錄（完整檔在 [readings/R1.json](examples/walkthrough/readings/R1.json)）。每個狀態與轉移都指出出自哪幾行；兩張圖的宣告沒被引用，列在其他行：

```json
{
  "reader": "R1",
  "states": [
    {
      "entity": "REQ_STATUS",
      "code": "030",
      "name": "030 核准",
      "final": true,
      "lines": [12, 30, 44],
      "regions": []
    },
    "…"
  ],
  "transitions": [
    {
      "entity": "REQ_STATUS",
      "from": "020",
      "to": "030",
      "via": [
        "amount_check"
      ],
      "labels": [],
      "scenario": "主流程",
      "lines": [11, 12, 32, 36, 37]
    },
    "…"
  ],
  "otherLines": [
    {
      "lines": [8, 25],
      "disposition": "NO_SPEC_CONTENT",
      "note": "圖的宣告"
    }
  ]
}
```

外環檢查三份解讀都逐行交代、引用都在圖內，再拆成事實比對。本範例三份完全一致：

| 項目 | 結果 |
|---|---|
| 讀者 | R1、R2、R3（三份解讀完全一致） |
| Mermaid 區塊的行數 | 33（每份解讀都逐行交代） |
| 拆成的事實 | 28 項，三份一致 28 項 |
| 狀態碼 | 010、015、020、025、030、090 |
| 轉移 | 新建→010、010→020、010→090、015→020、015→090、020→015、020→025、020→030、025→015、025→030（共 10 條） |
| 經過判斷節點的轉移 | 020→025（amount_check）、020→030（amount_check） |
| 終點 | 030、090 |
| 情境「主流程」 | 新建→010、010→020、020→030 |
| 情境「撤回作廢」 | 010→090、015→090 |
| 情境「退回補件」 | 015→020、020→015、025→015 |
| 情境「高額審核」 | 020→025、025→030 |
| 說明（L3） | 本檔是 STATUS 權威文件的合成範例。所有狀態圖寫在同一份檔案；這個範例只有一個狀態實體（申請單的狀態），同時提供 flowchart 與 stateDiagram-v2。 |
| 說明（L50） | 020 待主管審核：直屬主管審核申請內容。 |
| 說明（L51） | 025 待部門主管審核：部門主管審核。 |
| 說明（L52） | 090 作廢：作廢的申請單不能再修改。 |

這 10 條轉移與 4 種情境就是 04 的分母：研究只能補細節，不能增減。圖下方說明區域的每一行（標題、空行除外），外環逐行列出，交給 04 處置（§7）。

## 4. ID 派發

外環依自然鍵的字元碼順序派號（主文件 §7.2）。所以 FR-001 是「核准」而不是「建立」：ID 不代表順序，17 另有 `order` 欄。

| ID | 自然鍵 | 名稱 |
|---|---|---|
| STATE-001 | `REQ_STATUS:010` | 010 草稿 |
| STATE-002 | `REQ_STATUS:015` | 015 退回補件 |
| STATE-003 | `REQ_STATUS:020` | 020 待主管審核 |
| STATE-004 | `REQ_STATUS:025` | 025 待部門主管審核 |
| STATE-005 | `REQ_STATUS:030` | 030 核准 |
| STATE-006 | `REQ_STATUS:090` | 090 作廢 |
| TRN-001 | `REQ_STATUS:*>010` | 新建→010 |
| TRN-002 | `REQ_STATUS:010>020` | 010→020 |
| TRN-003 | `REQ_STATUS:010>090` | 010→090 |
| TRN-004 | `REQ_STATUS:015>020` | 015→020 |
| TRN-005 | `REQ_STATUS:015>090` | 015→090 |
| TRN-006 | `REQ_STATUS:020>015` | 020→015 |
| TRN-007 | `REQ_STATUS:020>025` | 020→025 |
| TRN-008 | `REQ_STATUS:020>030` | 020→030 |
| TRN-009 | `REQ_STATUS:025>015` | 025→015 |
| TRN-010 | `REQ_STATUS:025>030` | 025→030 |
| FLOW-001 | `REQ_STATUS:主流程` | 主流程 |
| FLOW-002 | `REQ_STATUS:撤回作廢` | 撤回作廢 |
| FLOW-003 | `REQ_STATUS:退回補件` | 退回補件 |
| FLOW-004 | `REQ_STATUS:高額審核` | 高額審核 |
| ACT-001 | `REQ_STATUS:020:01` | 直屬主管審核申請 |
| ACT-002 | `REQ_STATUS:025:01` | 部門主管審核高額申請 |
| FR-001 | `TW_DEMO_APV:APPROVE` | 核准申請 |
| FR-002 | `TW_DEMO_APV:RETURN` | 退回申請 |
| FR-003 | `TW_DEMO_REQ:CREATE` | 建立申請 |
| FR-004 | `TW_DEMO_REQ:SUBMIT` | 送出申請 |
| FR-005 | `TW_DEMO_REQ:WITHDRAW` | 撤回申請 |

## 5. 從一個功能往下看（反向追溯）

issue 裡「FR-001 往下展開」的樹，在這套設計中不是誰手寫的。FR-001 只記錄自己往上游的參照：實現的轉移、操作者。下面這棵樹由外環從下游項目的參照反查得到，00-index 的追溯矩陣也是同樣算法。

```text
FR-001 核准申請
 ├─ 角色：ROLE-001 審核主管
 ├─ 衍生概念：DRV-002 申請人的直屬主管、DRV-001 申請人的部門主管
 ├─ 狀態轉移：TRN-007 020→025、TRN-008 020→030、TRN-010 025→030
 ├─ 狀態活動：ACT-001 直屬主管審核申請、ACT-002 部門主管審核高額申請
 ├─ 情境：FLOW-001 主流程、FLOW-004 高額審核
 ├─ 畫面元件：UI-001 申請單審核、UI-002 金額、UI-003 審核意見、UI-004 申請事由、UI-005 核准
 ├─ 操作契約：OP-001 核准申請
 ├─ 寫入／讀取的欄位（經 TRN、OP）：FLD-010 TW_DEMO_REQHDR.AMOUNT、FLD-011 TW_DEMO_REQHDR.APPROVER_EMPLID、FLD-012 TW_DEMO_REQHDR.APPROVE_DT、FLD-013 TW_DEMO_REQHDR.COMMENTS、FLD-016 TW_DEMO_REQHDR.REQ_ID、FLD-017 TW_DEMO_REQHDR.REQ_STATUS
 ├─ 測試案例：TC-001 金額剛好 50000 時一次核准、TC-002 金額 50000.01 時轉部門主管、TC-003 具審核角色但不是直屬主管者看不到申請單、TC-004 高額案件兩段核准
 └─ 工作項：TASK-002 核准申請
```

## 6. 「長官」怎麼寫

轉移 020→030（TRN-008）的操作者條件不寫「需要長官審核」，而是兩個運算元：

- 使用者具有審核主管角色（ROLE-001）。
- 使用者是〈申請人的直屬主管〉（DRV-002）。

```json
{
  "id": "TRN-008",
  "key": "REQ_STATUS:020>030",
  "lifecycle": "ACTIVE",
  "basis": "AUTHORITATIVE_DOC",
  "certainty": "CONFIRMED",
  "evidence": [
    "EV-0054",
    "EV-0055",
    "EV-0018",
    "EV-0019"
  ],
  "entityKey": "REQ_STATUS",
  "from": "STATE-003",
  "to": "STATE-005",
  "via": [
    "amount_check"
  ],
  "exitMode": "NORMAL",
  "trigger": {
    "kind": "USER_ACTION",
    "object": "OBJ-002",
    "action": "按「核准」（TW_DEMO_REQWRK.APPROVE_PB）",
    "event": "FIELD_CHANGE"
  },
  "actor": {
    "all": [
      {
        "left": {
          "ctx": "CURRENT_USER_OPRID"
        },
        "op": "HAS_ROLE",
        "right": {
          "role": "ROLE-001"
        }
      },
      {
        "left": {
          "drv": "DRV-002"
        },
        "op": "EQ",
        "right": {
          "ctx": "CURRENT_USER_EMPLID"
        }
      }
    ]
  },
  "guard": {
    "left": {
      "fld": "FLD-010"
    },
    "op": "LE",
    "right": {
      "const": "50000",
      "type": "NUMBER"
    }
  },
  "writes": [
    {
      "field": "FLD-017",
      "value": {
        "const": "030",
        "type": "CHAR"
      }
    },
    {
      "field": "FLD-011",
      "value": {
        "ctx": "CURRENT_USER_EMPLID"
      }
    },
    {
      "field": "FLD-012",
      "value": {
        "ctx": "CURRENT_DATE"
      }
    }
  ],
  "sideEffects": {
    "na": "轉移本身沒有其他副作用；送出通知由 09 的規則觸發"
  },
  "implementedAt": [
    {
      "object": "OBJ-012",
      "event": "FieldChange"
    }
  ],
  "reentry": "核准後按鈕隱藏；兩位審核者同時核准時，後存檔者被拒絕（見 08 的併發行為）。"
}
```

「申請人的直屬主管」在 07 定義成一筆衍生概念，寫明：

- 從哪張表、用什麼串接、取哪一欄。
- 有效日怎麼取（目前有效列、只取有效狀態）。
- 查不到時結果為空，由 09 的規則在送出時擋下。
- 為什麼不會有多筆。

```json
{
  "id": "DRV-002",
  "key": "REQUESTER_SUPERVISOR",
  "lifecycle": "ACTIVE",
  "basis": "CODE",
  "certainty": "CONFIRMED",
  "evidence": [
    "EV-0030",
    "EV-0014"
  ],
  "name": "申請人的直屬主管",
  "meaning": "申請人目前任職資料上登記的直屬主管；送出時必須存在，020 由此人審核。",
  "inputs": [
    {
      "name": "REQUESTER",
      "from": {
        "fld": "FLD-015"
      }
    }
  ],
  "resultType": "PERSON_ID",
  "resolution": {
    "sources": [
      "ENT-002"
    ],
    "joins": [
      {
        "left": "FLD-008",
        "right": {
          "param": "REQUESTER"
        }
      }
    ],
    "filter": "ALWAYS",
    "effectiveDating": [
      {
        "entity": "ENT-002",
        "rule": "CURRENT_ROW",
        "asOf": {
          "ctx": "CURRENT_DATE"
        },
        "effStatusActiveOnly": true
      }
    ],
    "pick": "FLD-009",
    "tieBreak": {
      "na": "鍵（EMPLID＋EFFDT）加目前有效列規則保證只有一列"
    }
  },
  "whenNotFound": {
    "result": "EMPTY",
    "note": "查無目前有效的任職列，或 SUPERVISOR_ID 為空白時結果為空；送出時由 09 的規則擋下。"
  },
  "whenMultiple": {
    "rule": "UNIQUE_BY_KEY",
    "note": "目前有效列規則下每位員工只有一列。"
  },
  "implementedAt": [
    "OBJ-014",
    "OBJ-012",
    "OBJ-013"
  ]
}
```

讀者在 04 看到的是外環渲染出的句子：

```markdown
### TRN-008　020→030

- 自然鍵：`REQ_STATUS:020>030`
- 狀態實體：REQ_STATUS
- 起始狀態（新建為 INITIAL）：STATE-003（020 待主管審核）
- 目標狀態：STATE-005（030 核准）
- 經過的判斷節點（菱形、choice 等；取多數讀者的寫法）：amount_check
- 離開方式：NORMAL
- 觸發方式、所在物件與動作原名（COMPLETION＝條件成立時由系統自動轉移）：
  - 種類：USER_ACTION
  - 物件：OBJ-002（TW_DEMO_APV）
  - 動作：按「核准」（TW_DEMO_REQWRK.APPROVE_PB）
  - 事件：FIELD_CHANGE
- 誰能觸發（角色、資格的判定方式）：（目前使用者帳號 具有角色 ROLE-001（審核主管））且（〈申請人的直屬主管〉（DRV-002） ＝ 目前使用者員工編號）
- 轉移條件（選擇此目標的條件；守門轉移要含每個子業務與守門活動，R13）：FLD-010（TW_DEMO_REQHDR.AMOUNT） ≤ 50000
- 轉移時寫入的欄位與值：FLD-017（TW_DEMO_REQHDR.REQ_STATUS） ← '030'、FLD-011（TW_DEMO_REQHDR.APPROVER_EMPLID） ← 目前使用者員工編號、FLD-012（TW_DEMO_REQHDR.APPROVE_DT） ← 系統日期
- 其他副作用（通知、介面等於 06／09 反查；INTERRUPT 要寫明未完成的子業務資料怎麼處理）：不適用：轉移本身沒有其他副作用；送出通知由 09 的規則觸發
- 原系統實作位置：
  - 物件：OBJ-012（TW_DEMO_REQWRK.APPROVE_PB.FieldChange）；事件：FieldChange
- 重複觸發或同時操作時的行為：核准後按鈕隱藏；兩位審核者同時核准時，後存檔者被拒絕（見 08 的併發行為）。
- 來源：狀態權威文件；證據 EV-0054、EV-0055、EV-0018、EV-0019
- 被引用（外環反查）：OBJ-012；ACT-001；FLOW-001；FR-001；OP-001；TC-001、TC-003、TC-010；TASK-002；DOD-003
```

## 7. 說明區域與狀態活動

STATUS 檔圖下方的說明區域，寫的是各階段誰該做什麼。外環把圖外的每一行說明逐行列出（標題、空行、表頭除外），04 必須每一行都處置（主文件 §8.7）：

| 位置 | 原文 | 處置 | 寫進的項目或理由 |
|---|---|---|---|
| `L3` | 本檔是 STATUS 權威文件的合成範例。所有狀態圖寫在同一份檔案；這個範例只有一個狀態實體（申請單的狀態），同時提供 flowchart 與 stateDiagram-v2。 | NO_SPEC_CONTENT | 說明這份檔案的內容，沒有規格內容。 |
| `L50` | 020 待主管審核：直屬主管審核申請內容。 | MAPPED | ACT-001（直屬主管審核申請） |
| `L51` | 025 待部門主管審核：部門主管審核。 | MAPPED | ACT-002（部門主管審核高額申請） |
| `L52` | 090 作廢：作廢的申請單不能再修改。 | MAPPED | STATE-006（090 作廢）；090 是終點；畫面在 090 不顯示送出與撤回按鈕（見 05）。 |

- 兩行是活動，都由轉移完成（BY_TRANSITION）：直屬主管或部門主管按「核准」或「退回」，就離開這個狀態。所以活動不另寫完成條件，而是列出完成它的轉移。
- 「090 作廢」那一行寫進 090 這個狀態，並說明畫面在 090 不顯示按鈕。
- 檔案開頭的說明沒有規格內容，寫明理由即可。
- 不是每個狀態都有活動。沒寫的狀態就沒有活動，不會因此被擋下；要擋的只有「寫了卻沒處置」。
- 原文的「直屬主管」「部門主管」，在活動的 `actors` 必須是衍生概念（DRV-002、DRV-001），不能停在文字。

```json
{
  "id": "ACT-001",
  "key": "REQ_STATUS:020:01",
  "lifecycle": "ACTIVE",
  "basis": "AUTHORITATIVE_DOC",
  "certainty": "CONFIRMED",
  "evidence": [
    "EV-0068",
    "EV-0019"
  ],
  "entityKey": "REQ_STATUS",
  "state": "STATE-003",
  "name": "直屬主管審核申請",
  "behavior": "直屬主管審核申請內容",
  "actors": [
    {
      "drv": "DRV-002"
    }
  ],
  "enforcement": "BY_TRANSITION",
  "realizedBy": [
    "TRN-008",
    "TRN-007",
    "TRN-006"
  ],
  "completion": {
    "na": "核准或退回（離開 020）即完成；系統沒有另外記錄審核進度"
  }
}
```

需要系統檢查的活動（SYSTEM_GATE）與守門轉移，見 §9 的第二個範例。

## 8. 圖外發現與原生未使用分支

| 發現 | 證據 | 處理 |
|---|---|---|
| PROD 有狀態碼 099 的資料，圖上沒有 | 狀態欄位的 distinct 值查詢 | Q-002，OFF_DIAGRAM_STATE，HIGH，INFO，OPEN；不進 04，也不進 07 的值域 |
| `TW_DEMO_APV.PostBuild` 在特殊參數下把 030 改回 010 | 程式段落 | Q-003，OFF_DIAGRAM_TRANSITION，LOW，INFO；人工裁決 DEC-001「不重建」後標 ANSWERED。這支程式在 09 的處置是 OFF_DIAGRAM_ONLY |
| 值域有 040、050，但沒有資料、核心程式不用 | 值域定義 | 不列題，90 與 00-index 只顯示「只計數的定義值 2」 |
| `OLD_REF_NO`、`PRIORITY_CD` 全表非預設 0 筆、核心路徑沒有指名引用 | 資料彙總與交叉參照 SQL | 07 的 XF-001；其他文件不得出現這兩個欄位名（R04） |
| 金額檢核程式在申請類別＝INT 時改查內部預算 | 分支段落；全表分布、值清單、PeopleCode 交叉參照 SQL | Q-001，NATIVE_UNUSED_BRANCH，INFO，附證明；09 的金額規則不帶這個條件，程式處置標 NATIVE_UNUSED_BRANCH（R14 檢查兩邊對得上）。申請類別欄位照常建立：GEN、URG 都有資料，只有 INT 不會出現 |

圖外問題與原生未使用分支都是 INFO，不擋完成；HIGH 級圖外問題要人逐一裁決。

原生未使用分支的證明寫在問題裡。這一題用的是 DATA_VALUE_ABSENT：值在 PROD 全表 0 筆，而且沒有任何路徑會產生它（值清單停用、頁面不提供、核心程式不寫入、Record 預設值不是它）。少了其中任何一項，就證明不了，分支照常寫進 09。

這段分支裡還用到三樣東西。它們只在這段分支裡被用到，所以跟著分支一起排除（主文件 §8.8「分支裡的引用不算數」）：

| 分支裡用到的東西 | 不排除的話 | 排除後 |
|---|---|---|
| 內部預算表 `TW_DEMO_INTBUDGET` | 算成核心路徑會讀的表，列為 DEPENDENCY，07 要定義、新系統要建 | 01 列為 EXCLUDED，理由指向 Q-001 |
| 申請單的預算代碼欄位（全表都是空白） | 原生欄位判定的查法 a 看到有程式引用，不能判為無用，新系統要建 | 列入 07 的不建置欄位（XF-001 從 2 欄變成 3 欄） |
| 訊息 27000,5「內部預算不足。」 | 列進 09 的訊息 | 不列 |

這三樣都記在 Q-001 證明的 `branchReferences`。人工裁決若把分支納入（ADD_SCOPE），它們會重新研究、重新列入。

```json
{
  "id": "Q-001",
  "key": "NATIVE_UNUSED_BRANCH:TW_DEMO_REQHDR.AMOUNT.SaveEdit:REQ_TYPE=INT",
  "lifecycle": "ACTIVE",
  "basis": "COMPUTED",
  "certainty": "CONFIRMED",
  "evidence": [
    "EV-0022",
    "EV-0023",
    "EV-0024",
    "EV-0025"
  ],
  "category": "NATIVE_UNUSED_BRANCH",
  "severity": "INFO",
  "question": "金額檢核程式有一段「申請類別＝INT（內部）時改查內部預算」的原生分支。PROD 沒有 INT 的資料，INT 在值清單已停用、頁面不提供，核心路徑也沒有程式寫入 INT，所以不重建這段分支；分支內讀取的內部預算表、預算代碼欄位與一則訊息也不列入規格。新系統若要支援內部申請，需要另外決策。",
  "affects": [
    "OBJ-018",
    "OBJ-010",
    "FLD-018"
  ],
  "observed": {
    "location": "TW_DEMO_REQHDR.AMOUNT.SaveEdit"
  },
  "proof": {
    "kind": "DATA_VALUE_ABSENT",
    "branchCondition": "If TW_DEMO_REQHDR.REQ_TYPE = \"INT\" Then",
    "field": "TW_DEMO_REQHDR.REQ_TYPE",
    "absentValues": [
      "INT"
    ],
    "branchReferences": [
      "RECORD:TW_DEMO_INTBUDGET",
      "FIELD:TW_DEMO_REQHDR.BUDGET_CODE",
      "MESSAGE:27000,5"
    ],
    "statement": "PROD 全表沒有 INT（GEN 900 筆、URG 312 筆）；INT 在值清單已停用，頁面選項不含 INT；PeopleCode 交叉參照只有這支程式讀取 REQ_TYPE，核心路徑沒有寫入 INT 的程式；Record 預設值是 GEN。",
    "checkedOn": "2026-10-01"
  },
  "raisedBy": "RESEARCH",
  "status": "OPEN"
}
```

## 9. 子業務守門（第二個合成範例）

這一節用另一組合成資料（[examples/gate/](examples/gate/)）示範主業務等待子業務。案件的某些階段裡同時進行子業務，離開的線上寫明往下走的條件：

- 040 處理中：裡面進行文件審查、付款兩個子業務。兩者都到終點，而且承辦人已上傳結案報告，案件才自動進入 050。
- 050 結案審核：裡面進行主管覆核。主管覆核完成，案件自動進入 060 結案。

### 9.1 STATUS 檔的畫法

[STATUS 檔](examples/gate/input/status-CASE_STATUS.md)照管理者檔案的畫法：大圖的 flowchart 用 subgraph 畫大框框，框裡再用 subgraph 畫子業務；大框框連出去的線上寫描述，其他線上寫情境類型。

```mermaid
flowchart TD
    subgraph M040 [040 處理中]
        subgraph DOCS [文件審查]
            DS((開始)) -->|文件審查| D010["010 待審查"]
            D010 -->|文件審查| D090["090 審查完成"]
        end
        subgraph PAYS [付款]
            PS((開始)) -->|付款| P010["010 待付款"]
            P010 -->|付款| P090["090 已付款"]
        end
    end
    subgraph M050 [050 結案審核]
        subgraph APVS [主管覆核]
            AS((開始)) -->|主管覆核| A010["010 待覆核"]
            A010 -->|主管覆核| A090["090 覆核完成"]
        end
    end
    START((開始)) -->|主流程| N010["010 受理"]
    N010 -->|承辦人開始處理| M040
    M040 -->|文件審查與付款都完成，且已上傳結案報告| M050
    M050 -->|主管覆核完成| N060["060 結案"]
    N010 -->|撤案| N090["090 撤案"]
    M040 -->|承辦人撤案，不必等文件審查與付款| N090
```

大圖的 stateDiagram 只畫主業務，不畫框，線上也沒有文字：

```mermaid
stateDiagram-v2
    state "010 受理" as M010
    state "040 處理中" as M040
    state "050 結案審核" as M050
    state "060 結案" as M060
    state "090 撤案" as M090
    [*] --> M010
    M010 --> M040
    M040 --> M050
    M050 --> M060
    M010 --> M090
    M040 --> M090
    M060 --> [*]
    M090 --> [*]
```

文件審查另外獨立畫了一組 flowchart 與 stateDiagram，內容與大框框裡的那一段相同（見原檔）；付款與主管覆核只畫在大圖的框裡。圖下方的說明區域：

```markdown
## 說明

- 040 處理中：承辦人追蹤文件審查與付款，並上傳結案報告。
- 文件審查 010 待審查：審查人員逐份審查文件。
- 付款 010 待付款：會計人員依核定金額付款。
- 050 結案審核：主管確認案件資料完整後按「覆核完成」。
- 結案後由系統寄發結案通知給承辦人。
```

### 9.2 三份解讀的比對

三位讀者各自讀這份檔（解讀在 [readings/](examples/gate/readings/)）。讀者看得懂：大框框 040、050 是主業務的狀態，框裡的 subgraph 是在其中進行的子業務；stateDiagram 的 040 就是同一個狀態；獨立的文件審查圖與大框框裡的那一段是同一個子業務。

範例刻意讓兩位讀者各錯一點：R2 把文件審查取名為 `CASE_DOC_STATUS`，也沒把付款看成 040 裡的子業務（把那個框列為沒有規格內容）；R3 漏看付款 010→090 那條線。

- R2 把 `CASEDOC_STATUS` 取名為 `CASE_DOC_STATUS`；外環依引用的行對齊，代號取多數讀者用的 `CASEDOC_STATUS`。
- Mermaid 區塊共 46 行，三份解讀都逐行交代。拆成 47 項事實，三份一致 44 項，不一致 3 項。

第 2 輪：外環把不一致的事實連同引用的行逐項問三位讀者，多數決。

| 事實 | 引用的行 | 第 1 輪（有：沒有） | 第 2 輪（同意：不同意） | 結果 |
|---|---|---|---|---|
| CASE_STATUS 的 040 裡進行子業務 CASEPAY_STATUS | L14 | 2:1 | 3:0 | ACCEPTED |
| CASEPAY_STATUS 010→090 屬於情境「付款」 | L16 | 2:1 | 3:0 | ACCEPTED |
| 轉移 CASEPAY_STATUS 010→090 | L16 | 2:1 | 3:0 | ACCEPTED |

採用的事實（04 的分母）：

| 狀態實體 | 狀態碼 | 轉移 | 終點 | 情境 |
|---|---|---|---|---|
| `CASEAPV_STATUS` | 010、090 | 新建→010、010→090 | 090 | 主管覆核：新建→010、010→090 |
| `CASEDOC_STATUS` | 010、090 | 新建→010、010→090 | 090 | 文件審查：新建→010、010→090 |
| `CASEPAY_STATUS` | 010、090 | 新建→010、010→090 | 090 | 付款：新建→010、010→090 |
| `CASE_STATUS` | 010、040、050、060、090 | 新建→010、010→040、010→090、040→050、040→090、050→060 | 060、090 | 主流程：新建→010、010→040、040→050、050→060；撤案：010→090、040→090 |

| 主業務的狀態 | 其中的子業務 | 離開的線 |
|---|---|---|
| `CASE_STATUS` 040 | CASEDOC_STATUS、CASEPAY_STATUS | 040→050、040→090 |
| `CASE_STATUS` 050 | CASEAPV_STATUS | 050→060 |

| 轉移 | 線上文字（原文帶進轉移） |
|---|---|
| `CASE_STATUS` 010→040 | 承辦人開始處理 |
| `CASE_STATUS` 040→050 | 文件審查與付款都完成，且已上傳結案報告 |
| `CASE_STATUS` 040→090 | 承辦人撤案，不必等文件審查與付款 |
| `CASE_STATUS` 050→060 | 主管覆核完成 |

- 範例裡第 2 輪的回答是合成的：讀者看到引用的行之後，改回正確的解讀。實際執行時，第 2 輪仍沒有過半就開 STATUS_READING_CONFLICT 交人。
- 子業務沒有 stateDiagram 也沒關係：讀者從 flowchart 看得出付款、主管覆核的 090 沒有往外的線，是終點。
- 線上文字由外環原文帶進轉移的 `diagramLabels`。040 有兩條離開的線：「文件審查與付款都完成，且已上傳結案報告」是守門（ON_COMPLETION）；「承辦人撤案，不必等文件審查與付款」是中斷（INTERRUPT）。描述是判定的權威依據，研究再用程式確認；兩者矛盾時開 DIAGRAM_CODE_CONFLICT，交人裁決。
- 「主流程」「撤案」「文件審查」這類標籤是情境類型，只用來歸入情境，不帶進轉移。

### 9.3 說明區域的處置

| 位置 | 原文 | 處置 | 寫進的項目或理由 |
|---|---|---|---|
| `L3` | 本檔是 STATUS 權威文件的合成範例：flowchart 用 subgraph 畫主業務的大框框，框內再用 subgraph 畫子業務；stateDiagram-v2 只畫主業務。 | NO_SPEC_CONTENT | 說明這份檔案的畫法，沒有規格內容。 |
| `L52` | 文件審查另有獨立的圖。 | NO_SPEC_CONTENT | 說明圖的位置，沒有規格內容。 |
| `L71` | 040 處理中：承辦人追蹤文件審查與付款，並上傳結案報告。 | MAPPED | ACT-004（追蹤文件審查與付款）、ACT-005（上傳結案報告） |
| `L72` | 文件審查 010 待審查：審查人員逐份審查文件。 | MAPPED | ACT-002（審查文件） |
| `L73` | 付款 010 待付款：會計人員依核定金額付款。 | MAPPED | ACT-003（付款） |
| `L74` | 050 結案審核：主管確認案件資料完整後按「覆核完成」。 | MAPPED | ACT-001（主管覆核） |
| `L75` | 結案後由系統寄發結案通知給承辦人。 | MAPPED | TRN-012（050→060）；系統的副作用，寫在 050→060 轉移的 sideEffects。 |

- 「040 處理中」那一行有兩個活動：「追蹤文件審查與付款」系統不記錄也不檢查（EXPECTED_ONLY）；「上傳結案報告」系統會在離開 040 前檢查（SYSTEM_GATE）。
- 「結案後由系統寄發結案通知給承辦人」不是誰要做的事，寫進 050→060 的副作用。

### 9.4 守門轉移怎麼寫

```json
{
  "id": "TRN-010",
  "key": "CASE_STATUS:040>050",
  "lifecycle": "ACTIVE",
  "basis": "AUTHORITATIVE_DOC",
  "certainty": "CONFIRMED",
  "evidence": [
    "EV-0034",
    "EV-0035",
    "EV-0009",
    "EV-0010",
    "EV-0011",
    "EV-0008"
  ],
  "entityKey": "CASE_STATUS",
  "from": "STATE-008",
  "to": "STATE-009",
  "diagramLabels": [
    "文件審查與付款都完成，且已上傳結案報告"
  ],
  "exitMode": "ON_COMPLETION",
  "trigger": {
    "kind": "COMPLETION",
    "object": "OBJ-005",
    "action": "共用函式 TW_DEMO_CHKCLOSE 檢查守門條件，成立時把案件改為 050",
    "evaluatedAfter": [
      "TRN-004",
      "TRN-006",
      "ACT-005"
    ]
  },
  "actor": {
    "na": "條件成立時由系統自動轉移，沒有操作者"
  },
  "guard": {
    "all": [
      {
        "rows": "ENT-002",
        "quantifier": "ALL",
        "where": {
          "left": {
            "fld": "FLD-008"
          },
          "op": "EQ",
          "right": {
            "state": "STATE-004"
          }
        },
        "whenEmpty": "NOT_MET"
      },
      {
        "rows": "ENT-003",
        "quantifier": "ALL",
        "where": {
          "left": {
            "fld": "FLD-012"
          },
          "op": "EQ",
          "right": {
            "state": "STATE-006"
          }
        },
        "whenEmpty": "MET"
      },
      {
        "left": {
          "act": "ACT-005"
        },
        "op": "DONE"
      }
    ]
  },
  "writes": [
    {
      "field": "FLD-003",
      "value": {
        "const": "050",
        "type": "CHAR"
      }
    }
  ],
  "sideEffects": {
    "na": "轉入 050 時同一段程式把主管覆核狀態設為 010，寫在主管覆核的新建轉移"
  },
  "implementedAt": [
    {
      "object": "OBJ-005",
      "event": "FieldFormula（由 TW_DEMO_DOCREV、TW_DEMO_PAYMNT、TW_DEMO_CASE 的 SavePostChange 呼叫）"
    }
  ],
  "reentry": "只在案件仍為 040 時轉移；轉為 050 之後再存檔不會重複轉移。"
}
```

- `exitMode` 是 ON_COMPLETION；`diagramLabels` 是線上的原文。觸發是 COMPLETION：條件成立時由系統自動轉移，`evaluatedAfter` 寫明系統在哪些動作之後檢查（審查完成、付款完成、上傳結案報告）。
- 守衛逐項對應解讀裡的子業務與活動（R13）：
  - 文件審查：案件的每一份文件都是 090；一份文件都沒有時不算完成（whenEmpty＝NOT_MET）。
  - 付款：每一筆付款都是 090；沒有付款時算完成（whenEmpty＝MET）。
  - 守門活動「上傳結案報告」已完成（DONE）。
- 兩個 whenEmpty 不同，是看資料決定的：已進入 050、060 的案件中，沒有文件的 0 件、沒有付款的 117 件（證據中的 SQL）。「等全部完成」最常漏講的就是這一句，所以 ALL 與 NONE 一定要寫 whenEmpty，schema 會擋。
- 050→060（TRN-012）的子業務「主管覆核」記在案件本身的欄位，不是子表，所以守衛直接寫「主管覆核狀態＝090」，不用逐列條件。
- 進入 050 時，主管覆核從 010 開始。這是主管覆核的新建轉移（TRN-001）：觸發是 SYSTEM_EVENT，寫明在 040→050 之後連帶執行。

守門活動寫成一筆 ACT：負責人是角色，完成條件是結案報告附件有值；守門轉移以 DONE 引用它。

```json
{
  "id": "ACT-005",
  "key": "CASE_STATUS:040:02",
  "lifecycle": "ACTIVE",
  "basis": "AUTHORITATIVE_DOC",
  "certainty": "CONFIRMED",
  "evidence": [
    "EV-0056",
    "EV-0018",
    "EV-0010"
  ],
  "entityKey": "CASE_STATUS",
  "state": "STATE-008",
  "name": "上傳結案報告",
  "behavior": "上傳結案報告",
  "actors": [
    {
      "role": "ROLE-002"
    }
  ],
  "enforcement": "SYSTEM_GATE",
  "completion": {
    "left": {
      "fld": "FLD-005"
    },
    "op": "IS_NOT_BLANK"
  }
}
```

### 9.5 讀者看到的

外環從 STATE、TRN 重新產生狀態圖：主業務的狀態裡畫出子業務（這裡用 stateDiagram 的複合狀態與 `--`），線上標出原文描述，以及守門或中斷。原檔用 flowchart 的 subgraph 畫大框框，重繪換了一種畫法，內容相同。

```mermaid
stateDiagram-v2
    state "010 受理" as S010
    state "040 處理中" as S040 {
        state "010 待審查" as R040_1_010
        state "090 審查完成" as R040_1_090
        [*] --> R040_1_010 : TRN-003
        R040_1_010 --> R040_1_090 : TRN-004
        R040_1_090 --> [*]
        --
        state "010 待付款" as R040_2_010
        state "090 已付款" as R040_2_090
        [*] --> R040_2_010 : TRN-005
        R040_2_010 --> R040_2_090 : TRN-006
        R040_2_090 --> [*]
    }
    state "050 結案審核" as S050 {
        state "010 待覆核" as R050_1_010
        state "090 覆核完成" as R050_1_090
        [*] --> R050_1_010 : TRN-001
        R050_1_010 --> R050_1_090 : TRN-002
        R050_1_090 --> [*]
    }
    state "060 結案" as S060
    state "090 撤案" as S090
    [*] --> S010 : TRN-007
    S010 --> S040 : TRN-008 承辦人開始處理
    S010 --> S090 : TRN-009
    S040 --> S050 : TRN-010 文件審查與付款都完成，且已上傳結案報告（守門）
    S040 --> S090 : TRN-011 承辦人撤案，不必等文件審查與付款（中斷子業務）
    S050 --> S060 : TRN-012 主管覆核完成（守門）
    S060 --> [*]
    S090 --> [*]
```

```markdown
### TRN-010　040→050

- 自然鍵：`CASE_STATUS:040>050`
- 狀態實體：CASE_STATUS
- 起始狀態（新建為 INITIAL）：STATE-008（040 處理中）
- 目標狀態：STATE-009（050 結案審核）
- 圖上這條線的描述原文（情境類型以外的線上文字）；守衛與觸發必須與它一致：文件審查與付款都完成，且已上傳結案報告
- 離開方式：ON_COMPLETION
- 觸發方式、所在物件與動作原名（COMPLETION＝條件成立時由系統自動轉移）：
  - 種類：COMPLETION
  - 物件：OBJ-005（TW_DEMO_CASEWRK.CHKCLOSE.FieldFormula）
  - 動作：共用函式 TW_DEMO_CHKCLOSE 檢查守門條件，成立時把案件改為 050
  - 在這些之後檢查：TRN-004（010→090）、TRN-006（010→090）、ACT-005（上傳結案報告）
- 誰能觸發（角色、資格的判定方式）：不適用：條件成立時由系統自動轉移，沒有操作者
- 轉移條件（選擇此目標的條件；守門轉移要含每個子業務與守門活動，R13）：（ENT-002（TW_DEMO_CASEDOC） 中對應這一筆的每一列都符合（FLD-008（TW_DEMO_CASEDOC.DOC_STATUS） ＝ '090'（STATE-004 審查完成））；沒有任何對應的列時視為不成立）且（ENT-003（TW_DEMO_CASEPAY） 中對應這一筆的每一列都符合（FLD-012（TW_DEMO_CASEPAY.PAY_STATUS） ＝ '090'（STATE-006 已付款））；沒有任何對應的列時視為成立）且（活動 ACT-005（上傳結案報告） 已完成）
- 轉移時寫入的欄位與值：FLD-003（TW_DEMO_CASE.CASE_STATUS） ← '050'
- 其他副作用（通知、介面等於 06／09 反查；INTERRUPT 要寫明未完成的子業務資料怎麼處理）：不適用：轉入 050 時同一段程式把主管覆核狀態設為 010，寫在主管覆核的新建轉移
- 原系統實作位置：
  - 物件：OBJ-005（TW_DEMO_CASEWRK.CHKCLOSE.FieldFormula）；事件：FieldFormula（由 TW_DEMO_DOCREV、TW_DEMO_PAYMNT、TW_DEMO_CASE 的 SavePostChange 呼叫）
- 重複觸發或同時操作時的行為：只在案件仍為 040 時轉移；轉為 050 之後再存檔不會重複轉移。
- 來源：狀態權威文件；證據 EV-0034、EV-0035、EV-0009、EV-0010、EV-0011、EV-0008
- 被引用（外環反查）：FLOW-004；TRN-001；TC-003、TC-004、TC-005、TC-006、TC-007
```

### 9.6 守門的測試

C07 要求守門轉移有正例與反例；逐列條件有 whenEmpty 時，還要有「一列都沒有」的邊界例；守門活動也要有案例：

| 案例 | 類型 | 前置（合成資料） | 操作 | 預期 |
|---|---|---|---|---|
| TC-001 不是主管的人不能覆核，案件停在 050 | NEGATIVE | CASE_STATUS＝050；APV_STATUS＝010 | 以承辦人（沒有主管角色）開啟案件，嘗試按「覆核完成」 | 案件 050 結案審核 |
| TC-002 主管覆核完成時自動結案 | POSITIVE | CASE_STATUS＝050；APV_STATUS＝010 | 以主管開啟案件並按「覆核完成」 | 案件 060 結案 |
| TC-003 沒有任何文件時上傳報告也不會轉入 050 | BOUNDARY | CASE_STATUS＝040；CLOSE_RPT_ATT＝空白（尚未上傳）；TW_DEMO_CASEDOC 沒有任何一列；TW_DEMO_CASEPAY 沒有任何一列 | 以承辦人上傳結案報告並存檔 | 案件 040 處理中 |
| TC-004 最後上傳結案報告時自動轉入 050 | POSITIVE | CASE_STATUS＝040；CLOSE_RPT_ATT＝空白（尚未上傳）；DOC_STATUS＝090（文件第 1 列）；PAY_STATUS＝090（付款第 1 列） | 以承辦人上傳結案報告並存檔 | 案件 050 結案審核 |
| TC-005 文件尚未審查完成時，付款完成不會轉入 050 | NEGATIVE | CASE_STATUS＝040；CLOSE_RPT_ATT＝RPT0001；DOC_STATUS＝010（文件第 1 列）；PAY_STATUS＝010（付款第 1 列） | 以會計人員把付款第 1 列標為付款完成 | 案件 040 處理中 |
| TC-006 尚未上傳結案報告時，付款完成不會轉入 050 | NEGATIVE | CASE_STATUS＝040；CLOSE_RPT_ATT＝空白（尚未上傳）；DOC_STATUS＝090（文件第 1 列）；PAY_STATUS＝010（付款第 1 列） | 以會計人員把付款第 1 列標為付款完成 | 案件 040 處理中 |
| TC-007 最後一筆付款完成時自動轉入 050 | POSITIVE | CASE_STATUS＝040；CLOSE_RPT_ATT＝RPT0001；DOC_STATUS＝090（文件第 1 列）；PAY_STATUS＝010（付款第 1 列） | 以會計人員把付款第 1 列標為付款完成 | 案件 050 結案審核 |

本範例只產生 01、02、03、04、07、14，只跑 L1、R01、C01、R13 與守門的 C02、C07，結果見 [gate-report.json](examples/gate/gate-report.json)（沒有任何發現）。其他檢核需要完整的 job。

## 10. 檢核結果

L1～L3 是設計期腳本實際執行的結果。L4、L5 是示意值：範例假設已執行並通過，沒有真的跑覆核與讀者。

| 文件 | 狀態 | L1 | L2 | L3 | L4 | L5 |
|---|---|---|---|---|---|---|
| 01 專案概覽 | in_review | PASS | PASS | PASS | PASS | NOT_APPLICABLE |
| 02 功能需求 | in_review | PASS | PASS | PASS | PASS | PASS |
| 03 角色與權限 | in_review | PASS | PASS | PASS | PASS | PASS |
| 04 流程與狀態機 | in_review | PASS | PASS | PASS | PASS | PASS |
| 05 畫面與互動 | in_review | PASS | PASS | PASS | PASS | PASS |
| 06 系統架構（技術中立） | in_review | PASS | PASS | PASS | PASS | PASS |
| 07 資料設計 | in_review | PASS | PASS | PASS | PASS | PASS |
| 08 操作契約（API） | in_review | PASS | PASS | PASS | PASS | PASS |
| 09 業務邏輯 | in_review | PASS | PASS | PASS | PASS | PASS |
| 14 測試與驗收 | draft | PASS | PASS | FAIL | PASS | NOT_APPLICABLE |
| 16 AI 實作指引 | in_review | PASS | PASS | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE |
| 17 工作拆解與相依 | in_review | PASS | PASS | PASS | NOT_APPLICABLE | NOT_APPLICABLE |
| 18 完成定義 | in_review | PASS | PASS | PASS | NOT_APPLICABLE | NOT_APPLICABLE |
| 19 決策紀錄 | in_review | PASS | PASS | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE |
| 90 問題清單 | in_review | PASS | PASS | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE |

未通過的檢核：

- `14-testing/L3` C07 TRN-005（015>090）沒有測試案例
- `14-testing/L3` C07 TRN-009（025>015）沒有測試案例

範例故意少寫兩個測試案例：「退回補件中撤回」（015→090）、「部門主管退回」（025→015）。L3 的 C07 抓到後，14 停在 draft，整體狀態是 DRAFT，00-index 的「未通過的檢核」也會列出來。補上兩個案例重跑，14 才會變成 in_review。

### 壞範例：刻意破壞後由哪一層擋下

設計期腳本對兩個範例做 20 種破壞（貫穿範例 10 種、守門範例 10 種），每一種都被對應的檢核擋下，結果見 [negative-report.json](examples/negative-report.json)。這就是 issue 完成標準所說的「能檢查缺欄位、缺引用或含未確認假設」。L0 READ 表示研究前就把那份解讀退回：漏交代一行，或引用了 Mermaid 區塊以外的行。

| 破壞方式 | 預期 | 結果 | 檢核訊息 |
|---|---|---|---|
| 缺欄位：TRN-008 刪掉 guard | L1 S01 | 擋下 | TRN-008 （項目）：'guard' is a required property |
| 模糊條件：BR-006 的條件寫成「需要長官審核」 | L1 S01 | 擋下 | BR-006 condition：'需要長官審核' is not valid under any of the given schemas |
| 填充字：FR-004 的說明寫「待確認」 | L1 S01 | 擋下 | FR-004 description：命中禁用的填充字 |
| 未標示推論：DRV-002 改成 INFERRED 卻沒寫推論鏈 | L1 S01 | 擋下 | DRV-002 （項目）：'inference' is a required property |
| 推測寫成事實：OP-001 的併發行為寫「應該是後存檔者覆蓋」 | L1 S07 | 標出（警告） | OP-001 CONFIRMED 項目出現推測用語「應該是」（警告，交覆核） |
| 缺引用：OP-004 的檢核清單指向不存在的 BR-099 | L2 R01 | 擋下 | OP-004 參照不存在的 BR-099 |
| 往下游參照：FLD-010 宣稱推導自 TC-001 | L2 R03 | 擋下 | FLD-010 往下游參照 TC-001 |
| 不建置欄位寫進正文：BR-003 的邊界提到 OLD_REF_NO | L2 R04 | 擋下 | BR-003 正文寫到不建置欄位 OLD_REF_NO |
| 圖外轉移寫進 04：新增 030→010 | L3 C01 | 擋下 | 04 有狀態圖沒有的轉移 ['030>010'] |
| 原生未使用分支寫回正文：BR-003 的條件加上「申請類別≠INT」 | L2 R14 | 擋下 | BR-003 的條件比對 TW_DEMO_REQHDR.REQ_TYPE＝INT，但 Q-001 已證明這個值不會出現 |
| 守門範例：TRN-010（040→050）的守衛漏掉付款子業務 | L2 R13 | 擋下 | TRN-010 的守衛沒有要求子業務 CASEPAY_STATUS 的資料全部到終點 090 |
| 守門範例：TRN-010 的守衛漏掉「上傳結案報告」 | L2 R13 | 擋下 | TRN-010 的守衛沒有要求守門活動 ACT-005 完成 |
| 守門範例：逐列條件 ALL 沒寫 whenEmpty | L1 S01 | 擋下 | TRN-010 guard.all.0：'whenEmpty' is a required property |
| 守門範例：處理中撤案（TRN-011）的 exitMode 寫成 NORMAL | L3 C01 | 擋下 | TRN-011 從有子業務的 STATE-008 離開，exitMode 不得為 NORMAL |
| 守門範例：DONE 指向以轉移完成的活動 ACT-002 | L2 R13 | 擋下 | TRN-010 以 DONE 引用的 ACT-002 不是 SYSTEM_GATE 活動 |
| 守門範例：TRN-010 漏帶線上文字 | L3 C01 | 擋下 | TRN-010 的線上文字與解讀不符（解讀：文件審查與付款都完成，且已上傳結案報告） |
| 守門範例：說明區域「審查人員逐份審查文件」那一行沒有處置 | L3 C01 | 擋下 | STATUS 文字 status-CASE_STATUS.md#L72「文件審查 010 待審查：審查人員逐份審查文件。」沒有處置 |
| 守門範例：守門活動沒有功能可完成（FR-002 拿掉 performs） | L3 C02 | 擋下 | ACT-005 是守門活動，但沒有功能讓操作者完成它 |
| 守門範例：讀者 R1 的解讀漏交代「M040 --> M090」那一行 | L0 READ | 擋下 | R1 的解讀退回：第 45 行沒有交代：M040 --> M090 |
| 守門範例：讀者 R3 把 010→040 引用到說明區域的行 | L0 READ | 擋下 | R3 的解讀退回：第 71 行不在 Mermaid 區塊內，卻被引用 |

「推測寫成事實」是 L1 的警告（S07）而不是失敗：用語比對無法證明一句話是假設，所以只負責把它標出來，交給 L4 覆核確認，或改開問題。

## 11. 乾淨讀者（示意）

三位讀者（後端實作者、畫面實作者、測試設計者）各自作答，再多數決（主文件 §11.4）。下面四個情況示範投票怎麼判定；範例資料是修正後的最終版，Q-004 記錄了第一個情況，狀態是 WITHDRAWN。

**情況一：描述太簡略（UNDERSPECIFIED）**

第一版 OP-001 的併發行為只寫「原系統有檢查」。O2 題「兩人同時核准會怎樣」：

| 讀者 | 答案 | 歸類 |
|---|---|---|
| 後端實作者 | NOT_IN_SPEC | 文件沒寫 |
| 畫面實作者 | NOT_IN_SPEC | 文件沒寫 |
| 測試設計者 | 「後存檔者覆蓋先存檔者」，引用 08-api.md#OP-001 | 不符 |

- **判定**：2 票文件沒寫 → UNDERSPECIFIED。外環開 Q-004（BLOCKING），工單退回操作研究。
- **修正**：補成「開啟後到存檔之間若已被他人更新，存檔被拒絕並顯示 MSG-004，該筆維持先存檔者的結果」。
- **第 2 輪**：三位新讀者都答出 STALE_DATA_CHECK 與 MSG-004，3 票相符 → CONSISTENT；Q-004 改為 WITHDRAWN。

**情況二：有歧義（DIVERGENT）**

第一版 BR-003 的邊界只寫「金額須為正數」。B4 題「空白、0、邊界怎麼算」：

| 讀者 | 答案 | 歸類 |
|---|---|---|
| 後端實作者 | 最小 0.01 | 相符 |
| 畫面實作者 | 最小 1（以為是整數） | 不符 |
| 測試設計者 | NOT_IN_SPEC | 文件沒寫 |

- **判定**：沒有任何一種答案拿到 2 票 → DIVERGENT，退回規則研究。
- **修正**：補成「0 拒絕；最小可接受 0.01（小數 2 位）；未輸入時存 0，視同 0 拒絕」，並由 TC-007 覆蓋 0.01。

**情況三：少數意見不擋（CONSISTENT）**

T4 題「轉移 020→030（TRN-008）之後哪些欄位變成什麼值」：

| 讀者 | 答案 | 歸類 |
|---|---|---|
| 後端實作者 | REQ_STATUS＝030、APPROVER_EMPLID＝核准者、APPROVE_DT＝系統日期 | 相符 |
| 畫面實作者 | 同上 | 相符 |
| 測試設計者 | 只答 REQ_STATUS＝030 | 不符 |

- **判定**：2 票相符 → CONSISTENT。測試設計者漏答的部分記為少數意見，給覆核參考，不擋。

**情況四：讀者腦補（無效答案）**

F2 題「核准後會發生什麼」，有一位讀者另外答了「寄信通知申請人」，但沒有有效引用（文件沒有這件事）。

- 這個答案無效、不計票，同一輪重問那位讀者一次。
- 如果有 2 位讀者都腦補了「寄信通知申請人」，表示文件沉默反而引人假設，判定 UNDERSPECIFIED：研究端要把「核准後不通知任何人」寫成明確的否定事實（若程式確實如此）。

## 12. 讀者看到的檔案

| 檔案 | 內容 |
|---|---|
| [00-index.md](examples/walkthrough/rendered/00-index.md) | 閱讀順序、各文件檢核、ID 前綴對照、追溯矩陣、問題摘要、欄位統計 |
| [04-workflow.md](examples/walkthrough/rendered/04-workflow.md) | 由資料重新產生的狀態圖與情境圖；狀態圖文字的處置；狀態、轉移、情境、活動明細 |
| [07-database.md](examples/walkthrough/rendered/07-database.md) | 實體、欄位、衍生概念（直屬主管、部門主管）、不建置欄位 |
| [09-business-logic.md](examples/walkthrough/rendered/09-business-logic.md) | 程式處置表、規則、訊息 |
| [14-testing.md](examples/walkthrough/rendered/14-testing.md) | 14 個案例；開頭標示 draft 與 L3 FAIL |
| [90-questions.md](examples/walkthrough/rendered/90-questions.md) | 4 個問題（含原生未使用分支的證明）與只計數的定義值 |
| [gate/rendered/04-workflow.md](examples/gate/rendered/04-workflow.md) | 守門範例的 04：子業務、守門轉移、中斷轉移、活動、狀態圖解讀的第 2 輪 |
| [gate/readings/](examples/gate/readings/) | 守門範例的三份合成解讀（R2、R3 各有刻意的錯） |

其餘文件（01、02、03、05、06、08、16、17、18、19）在同一個目錄。每個項目末尾的「被引用」都由外環反查。
