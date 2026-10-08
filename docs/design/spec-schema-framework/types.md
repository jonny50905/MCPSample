# 14 類文件型別定義（Layer B）

> [設計提案](../spec-schema-framework.md)的附件。
>
> - **欄位表**：由 `schemas/` 產生（`tools/build.py`）；兩者不一致時以 schema 為準。
> - **共同欄位**：`id`、`key`、`lifecycle`、`basis`、`certainty`、`evidence` 等，以及值的三態、條件式，見主文件 §5。
> - **型別欄的「｜NA」「｜UNRESOLVED」**：表示該欄允許 NOT_APPLICABLE 或 UNRESOLVED；沒標的欄位只能是具體值。
> - **參照欄**：列出該欄可以指向的 ID 前綴（含條件式裡的運算元）。
> - **「最小合法項目」**：只示範 L1 結構；參照完整性（L2）需要上游文件。整份最小文件見 [examples/minimal/](examples/minimal/)，完整範例見 [walkthrough.md](walkthrough.md)。

## 目錄

- [01 專案概覽](#01-專案概覽01-overview)
- [02 功能需求](#02-功能需求02-functional-requirements)
- [03 角色與權限](#03-角色與權限03-roles-permissions)
- [04 流程與狀態機](#04-流程與狀態機04-workflow)
- [05 畫面與互動](#05-畫面與互動05-ui)
- [06 系統架構（技術中立）](#06-系統架構技術中立06-architecture)
- [07 資料設計](#07-資料設計07-database)
- [08 操作契約（API）](#08-操作契約api08-api)
- [09 業務邏輯](#09-業務邏輯09-business-logic)
- [14 測試與驗收](#14-測試與驗收14-testing)
- [16 AI 實作指引](#16-ai-實作指引16-ai-instructions)
- [17 工作拆解與相依](#17-工作拆解與相依17-tasks)
- [18 完成定義](#18-完成定義18-definition-of-done)
- [19 決策紀錄](#19-決策紀錄19-decision-log)
- [90 問題清單](#90-問題清單90-questions)
- [證據登錄（evidence.json）](#證據登錄evidencejson)

---

## 01 專案概覽（01-overview）

- **用途**：定義重建範圍與目標。讀者從這裡知道要做哪些 Component、哪些物件在範圍內、哪些刻意不做。
- **輸入來源**：專案輸入檔（目標、決策責任）；範圍研究（OBJ）；原生欄位判定結論。
- **何時產生**：GOAL、RESP 在輸入檢查時就能產生；OBJ 在第 1 階段。
- **渲染章節**：範圍摘要（CORE、DEPENDENCY、EXCLUDED）、目標與成功標準、決策責任、範圍物件明細。不建置欄位的數量會寫在這裡，明細連到 07。
- **外殼欄位**：

<!-- GEN:extra:01-overview -->
| 外殼欄位 | 型別 | 必填 | 值域／限制 | 說明 |
|---|---|---|---|---|
| `projectInputStatus` | 列舉 | ✓ | PROVIDED／NOT_PROVIDED | 專案輸入檔是否提供 |
<!-- /GEN -->

### GOAL 專案目標

<!-- GEN:fields:GOAL -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `GOAL:<序號>` |  | 外環據以派發 ID |
| `name` | 文字 | ✓ |  |  | 目標名稱 |
| `statement` | 文字 | ✓ |  |  | 目標敘述 |
| `successCriteria` | 陣列〈文字〉 | ✓ | ≥1 |  | 成功標準（可判定的敘述） |
<!-- /GEN -->

### RESP 決策責任

<!-- GEN:fields:RESP -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `RESP:<範圍>` |  | 外環據以派發 ID |
| `area` | 列舉 | ✓ | SPEC_APPROVAL／QUESTION_RESOLUTION／BUSINESS_RULE_OWNER／DATA_OWNER／OTHER |  | 負責範圍 |
| `holder` | 文字 | ✓ | 只寫職稱或單位類別 |  | 負責者（不寫人名） |
<!-- /GEN -->

### OBJ 舊系統物件（範圍）

<!-- GEN:fields:OBJ -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `<物件型別>:<原名>` |  | 外環據以派發 ID |
| `objectType` | 列舉 | ✓ | COMPONENT／PAGE／SUBPAGE／SECONDARY_PAGE／RECORD／PEOPLECODE／APP_PACKAGE／AE／SQR／SQC／SQL_OBJECT／MESSAGE_SET／PERMISSION_LIST／ROLE／QUERY／IB_SERVICE／FILE_LAYOUT／COMPONENT_INTERFACE／OTHER |  | 物件型別 |
| `objectName` | 原名 | ✓ |  |  | PeopleSoft 物件原名 |
| `inclusion` | 列舉 | ✓ | CORE／DEPENDENCY／EXCLUDED |  | 範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED |
| `parent` | ID 參照 |  |  | OBJ | 上層物件（Page 的 Component 等） |
| `usedBy` | 文字 | ✓ |  |  | 使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」） |
| `usedByRefs` | 陣列〈ID〉 |  |  | OBJ | 使用鏈上的物件 |
| `condition` | 文字｜NA | ✓ |  |  | 何時使用 |
| `reason` | 文字 | ✓ |  |  | 納入／排除理由 |
| `pcEvent` | 列舉 |  | PeopleCode 事件 |  | PEOPLECODE 物件的事件 |
| `fieldUsage` | 三擇一物件 |  | excluded{count}／noneExcludable{checkedOn}／undetermined{code} |  | 原生欄位判定結論；type RECORD 且 CORE／DEPENDENCY 時必填 |
<!-- /GEN -->

**完整性與審查準則**

- 每個使用者指定的 Component 都是 CORE。
- 每個 DEPENDENCY 都有使用鏈（`usedBy`＋`usedByRefs`）與使用條件。
- 每個 EXCLUDED 都有理由。
- 每個範圍內 Record 都有 `fieldUsage` 結論，排除欄數與 07 的 XF 一致（C06）。
- 沒有目標時，`projectInputStatus＝NOT_PROVIDED`，開一筆 INPUT_MISSING（INFO）問題。
- 人工審查：確認 EXCLUDED 清單沒有誤排業務在用的物件。

**最小合法項目（OBJ）**

<!-- GEN:minimal:OBJ -->
```json
{
  "id": "OBJ-018",
  "key": "RECORD:TW_DEMO_REQHDR",
  "lifecycle": "ACTIVE",
  "basis": "METADATA",
  "certainty": "CONFIRMED",
  "evidence": [
    "EV-0007"
  ],
  "objectType": "RECORD",
  "objectName": "TW_DEMO_REQHDR",
  "inclusion": "CORE",
  "usedBy": "兩個主頁的主要 Record",
  "condition": {
    "na": "兩頁一律讀寫"
  },
  "reason": "申請單主檔",
  "fieldUsage": {
    "excluded": {
      "count": 2
    }
  }
}
```
<!-- /GEN -->

---

## 02 功能需求（02-functional-requirements）

- **用途**：列出使用者（或批次）能執行的每一個業務操作。FR 是 17 的切片單位，也是 14 的覆蓋分母。
- **輸入來源**：04 的轉移與情境；01 的 Component 入口與模式；03 的角色。
- **何時產生**：第 6 階段（04 完成後）。
- **渲染章節**：功能清單；每個功能的明細，包含反查到的畫面、規則、操作、測試、工作。

<!-- GEN:fields:FR -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `<Component>:<操作代號>` |  | 外環據以派發 ID |
| `name` | 文字 | ✓ |  |  | 功能名稱 |
| `description` | 文字 | ✓ |  |  | 功能說明 |
| `frKind` | 列舉 | ✓ | TRANSITION／MAINTAIN／QUERY／BATCH／OUTPUT |  | 功能種類 |
| `entry` | 物件 | ✓ |  | OBJ | 入口物件與模式 |
| `actors` | 陣列〈角色｜衍生概念｜情境〉 | ✓ | ≥1 | ROLE、DRV | 操作者摘要（判定細節在 04 的 actor） |
| `realizes` | 陣列〈ID〉 | ✓ | TRANSITION 時≥1，其他種類必須為空 | TRN | 實現的狀態轉移 |
| `preconditions` | 條件式｜NA | ✓ |  | FLD、DRV、STATE、ROLE | 前置條件 |
| `outcome` | 文字 | ✓ |  |  | 完成後的結果 |
| `priority` | 列舉 | ✓ | MUST／SHOULD／COULD（預設 MUST） |  | 優先序 |
<!-- /GEN -->

**完整性與審查準則**

- 每條轉移至少被一個 FR 實現（C02）。
- TRANSITION 類 FR 的 `realizes` 不得為空，其他種類必須為空（schema）。
- FR 入口的 Component 與其轉移的觸發 Component 一致（R09）。
- 每個 FR 都有操作契約（C08）與正例（C07）。
- 粒度：同一個入口、同一個動作只算一個 FR，不要把一個情境拆成重複的 FR。

**最小合法項目**

<!-- GEN:minimal:FR -->
```json
{
  "id": "FR-004",
  "key": "TW_DEMO_REQ:SUBMIT",
  "lifecycle": "ACTIVE",
  "basis": "DERIVED",
  "certainty": "CONFIRMED",
  "evidence": [],
  "derivedFrom": [
    "TRN-002"
  ],
  "name": "送出申請",
  "description": "申請人把草稿或退回補件中的申請單送出給直屬主管審核。",
  "frKind": "TRANSITION",
  "entry": {
    "object": "OBJ-003",
    "modes": [
      "UPDATE_DISPLAY"
    ]
  },
  "actors": [
    {
      "role": "ROLE-002"
    }
  ],
  "realizes": [
    "TRN-002"
  ],
  "preconditions": {
    "left": {
      "fld": "FLD-017"
    },
    "op": "IN",
    "right": [
      {
        "state": "STATE-001"
      },
      {
        "state": "STATE-002"
      }
    ]
  },
  "outcome": "狀態變為 020，記錄送出日，並排入送審通知。",
  "priority": "MUST"
}
```
<!-- /GEN -->

---

## 03 角色與權限（03-roles-permissions）

- **用途**：誰能進入哪個畫面、做哪些動作、看到哪些資料列，以及無權時會怎樣。
- **輸入來源**：security 研究（Permission List、Role、列層級安全、PeopleCode 裡的權限檢查）；07 的欄位與衍生概念（資料範圍要用）。
- **何時產生**：第 3 階段。
- **渲染章節**：角色清單；權限矩陣（角色 × 資源 × 動作）；資料範圍條件；無權時的效果。

### ROLE 角色

<!-- GEN:fields:ROLE -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `<主體型別>:<原名>` |  | 外環據以派發 ID |
| `principalType` | 列舉 | ✓ | ROLE／PERMISSION_LIST／DYNAMIC_ROLE／OTHER |  | 主體型別 |
| `object` | ID 參照 | ✓ |  | OBJ | 對應的原系統物件 |
| `name` | 文字 | ✓ |  |  | 業務名稱 |
| `membership` | 物件 | ✓ | kind＝STATIC_ASSIGNMENT／DYNAMIC_RULE（後者必附 DRV） | DRV | 使用者如何取得此角色 |
<!-- /GEN -->

### PERM 權限

<!-- GEN:fields:PERM -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `<主體鍵>><資源鍵>` |  | 外環據以派發 ID |
| `principal` | ID 參照 | ✓ |  | ROLE | 權限主體 |
| `resource` | ID 參照 | ✓ |  | OBJ | 受控資源（Component／Page／程序） |
| `actions` | 陣列〈列舉〉 | ✓ | ADD／UPDATE_DISPLAY／UPDATE_DISPLAY_ALL／CORRECTION／DISPLAY_ONLY／RUN_PROCESS／VIEW_ONLY |  | 允許的動作 |
| `dataScope` | ALL_ROWS｜物件 | ✓ | condition 只能用資料運算元 | FLD、DRV | 資料範圍（列層級） |
| `denial` | 物件 | ✓ | NOT_IN_NAVIGATION／ACCESS_DENIED_MESSAGE／ROWS_FILTERED／CONTROL_HIDDEN／CONTROL_DISABLED |  | 無權時的效果 |
| `enforcement` | 列舉 | ✓ | COMPONENT_SECURITY／ROW_LEVEL_SECURITY／PEOPLECODE_CHECK／PAGE_DISPLAY_CONTROL |  | 檢查位置 |
<!-- /GEN -->

**完整性與審查準則**

- 04 每條轉移的操作者條件中用到的角色，都要對觸發 Component 有 PERM（R12）。
- 資料範圍只能用資料運算元（schema：`dataCondition`），所以不會往下游引用 04。
- 不寫人名。
- 「配置上看得到」不等於「目前的使用者已被授權」（沿用 clone-contract）。

**最小合法項目（PERM）**

<!-- GEN:minimal:PERM -->
```json
{
  "id": "PERM-002",
  "key": "ROLE:TW_DEMO_REQUESTER>COMPONENT:TW_DEMO_REQ",
  "lifecycle": "ACTIVE",
  "basis": "CODE",
  "certainty": "CONFIRMED",
  "evidence": [
    "EV-0008"
  ],
  "principal": "ROLE-002",
  "resource": "OBJ-003",
  "actions": [
    "ADD"
  ],
  "dataScope": {
    "condition": {
      "left": {
        "fld": "FLD-015"
      },
      "op": "EQ",
      "right": {
        "ctx": "CURRENT_USER_EMPLID"
      }
    },
    "note": "只看得到自己的申請單。"
  },
  "denial": {
    "effect": "ROWS_FILTERED",
    "note": "查詢結果不含他人的申請單。"
  },
  "enforcement": "ROW_LEVEL_SECURITY"
}
```
<!-- /GEN -->

---

## 04 流程與狀態機（04-workflow）

- **用途**：狀態、轉移、情境。內容是 STATUS 文件的權威內容，加上程式研究得到的「怎麼做」。
- **輸入來源**：STATUS 文件（flowchart＋stateDiagram-v2）；程式研究；07 的狀態欄位；03 的角色。
- **何時產生**：骨架在第 0 階段（解析兩圖後派 ID），細節在第 4 階段。
- **渲染章節**：狀態圖（由 STATE、TRN 重新產生的 stateDiagram-v2，邊上標 TRN ID 與守衛）；情境流程圖（flowchart，邊上標情境類型與 TRN ID）；狀態、轉移、情境明細。
- **外殼欄位**：

<!-- GEN:extra:04-workflow -->
| 外殼欄位 | 型別 | 必填 | 值域／限制 | 說明 |
|---|---|---|---|---|
| `diagramSources` | 陣列〈物件〉 | ✓ | ≥1 | 狀態圖來源（每個狀態實體一組 flowchart＋stateDiagram-v2） |
<!-- /GEN -->

### STATE 狀態

<!-- GEN:fields:STATE -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `<狀態實體>:<狀態碼>` |  | 外環據以派發 ID |
| `entityKey` | 代號 | ✓ |  |  | 狀態實體（輸入檔的狀態圖分組） |
| `stateKind` | 列舉 | ✓ | SIMPLE／COMPOSITE |  | 狀態種類 |
| `code` | 原文 |  | SIMPLE 必填 |  | 狀態碼（儲存值） |
| `name` | 原文 | ✓ |  |  | 狀態圖上的名稱 |
| `parent` | ID 參照 |  |  | STATE | 所屬複合狀態 |
| `binding` | ID 參照 |  | SIMPLE 必填 | FLD | 保存狀態碼的欄位 |
| `domainLabel` | 原文｜NA |  | SIMPLE 必填 |  | 值域中的顯示文字（Translate／對照表） |
| `isInitialTarget` | 布林 | ✓ |  |  | 是否由 [*] 進入（新建） |
| `isFinal` | 布林 | ✓ |  |  | 是否為終點（→[*]） |
| `dataPresence` | 列舉 |  | SIMPLE 必填 |  | PROD 是否有此狀態碼的資料 |
<!-- /GEN -->

### TRN 狀態轉移

<!-- GEN:fields:TRN -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `<狀態實體>:<起>><迄>（新建的起點寫 *）` |  | 外環據以派發 ID |
| `entityKey` | 代號 | ✓ |  |  | 狀態實體 |
| `from` | ID 參照｜INITIAL | ✓ |  | STATE | 起始狀態（新建為 INITIAL） |
| `to` | ID 參照 | ✓ |  | STATE | 目標狀態 |
| `via` | 陣列〈原文〉 |  |  |  | 收合掉的 choice／fork／join 節點 |
| `trigger` | 物件｜UNRESOLVED | ✓ | kind＝USER_ACTION／BATCH／SYSTEM_EVENT／INTERFACE | OBJ | 觸發方式、所在物件與動作原名 |
| `actor` | 條件式｜NA｜UNRESOLVED | ✓ | 非 BATCH 觸發不得 NA（schema） | FLD、DRV、STATE、ROLE | 誰能觸發（角色、資格的判定方式）；只有批次觸發可以是 NA |
| `guard` | 條件式｜NA｜UNRESOLVED | ✓ | 有 via（經 choice 收合）時不得 NA（schema） | FLD、DRV、STATE、ROLE | 轉移條件（選擇此目標的條件） |
| `writes` | 陣列〈指派〉｜UNRESOLVED | ✓ | 必含狀態欄位＝目標狀態碼 | FLD、DRV、STATE、ROLE | 轉移時寫入的欄位與值 |
| `sideEffects` | 陣列〈物件〉｜NA | ✓ |  | FLD | 其他副作用（通知、介面等於 06／09 反查） |
| `implementedAt` | 陣列〈物件〉｜UNRESOLVED | ✓ | 找不到＝UNRESOLVED（DIAGRAM_EDGE_UNIMPLEMENTED） | OBJ | 原系統實作位置 |
| `reentry` | 文字｜UNRESOLVED | ✓ |  |  | 重複觸發或同時操作時的行為 |
<!-- /GEN -->

### FLOW 情境流程

<!-- GEN:fields:FLOW -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `<狀態實體>:<情境類型原文>` |  | 外環據以派發 ID |
| `entityKey` | 代號 | ✓ |  |  | 狀態實體 |
| `scenarioType` | 原文 | ✓ | flowchart 邊標籤原文 |  | 情境類型 |
| `narrative` | 文字 | ✓ |  |  | 情境說明 |
| `steps` | 陣列〈物件〉 | ✓ | 每條同標籤的邊恰一步 | TRN | 情境步驟（依拓撲順序） |
| `entryStates` | 陣列〈ID｜INITIAL〉 | ✓ | ≥1 | STATE | 進入此情境的狀態 |
| `exitStates` | 陣列〈ID〉 | ✓ | ≥1 | STATE | 離開此情境的狀態 |
| `preconditions` | 條件式｜NA | ✓ |  | FLD、DRV、STATE、ROLE | 前置條件 |
| `exceptions` | 文字｜NA | ✓ |  |  | 例外與中斷 |
<!-- /GEN -->

**完整性與審查準則**

- 與兩張圖完全一致，不多不少（C01）。
- 每條轉移寫入狀態欄位＝目標狀態碼；經 choice 收合的轉移必有守衛（R06）。
- 狀態碼屬於綁定欄位的值域（R07）。
- `actor` 只有在觸發方式是 BATCH 時可以是 NA。
- `implementedAt` 找不到時填 UNRESOLVED，並開 DIAGRAM_EDGE_UNIMPLEMENTED（BLOCKING）。
- 圖外發現只記錄位置與起迄，寫進 90。
- 人工審查：每條轉移的守衛是否足以實作（L5 的 T3 題）。

**最小合法項目（TRN）**

<!-- GEN:minimal:TRN -->
```json
{
  "id": "TRN-008",
  "key": "REQ_STATUS:020>030",
  "lifecycle": "ACTIVE",
  "basis": "AUTHORITATIVE_DOC",
  "certainty": "CONFIRMED",
  "evidence": [
    "EV-0050"
  ],
  "entityKey": "REQ_STATUS",
  "from": "STATE-003",
  "to": "STATE-005",
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
<!-- /GEN -->

---

## 05 畫面與互動（05-ui）

- **用途**：畫面、區塊、元件、綁定、顯示與可編輯條件、選項、純畫面互動。
- **輸入來源**：ui 研究（Page metadata；PeopleCode 中的 Hide、Gray、Visible、DisplayOnly 等）；07 的欄位；02 的功能。
- **何時產生**：第 7 階段。
- **渲染章節**：畫面清單；每個畫面的區塊與元件明細，包含反查到的規則與測試。

<!-- GEN:fields:UI -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `<Component>.<Page>[.<Record>.<欄位>]` |  | 外環據以派發 ID |
| `uiKind` | 列舉 | ✓ | SCREEN／CONTROL |  | 畫面或元件 |
| `usedBy` | 陣列〈ID〉 | ✓ | ≥1 | FR | 使用此畫面／元件的功能 |
| `component` | ID 參照 |  | SCREEN 必填 | OBJ | Component |
| `page` | ID 參照 |  | SCREEN 必填 | OBJ | Page |
| `title` | 原文 |  | SCREEN 必填 |  | 畫面標題 |
| `pageRole` | 列舉 |  | MAIN／SUBPAGE／SECONDARY／SEARCH／MODAL；SCREEN 必填 |  | 頁面角色 |
| `modes` | 陣列〈列舉〉 |  | SCREEN 必填 |  | 可用模式 |
| `searchKeys` | 陣列〈ID〉｜NA |  | SCREEN 必填 | FLD | 查詢鍵 |
| `regions` | 陣列〈物件〉 |  | SCREEN 必填 |  | 區塊與 scroll level |
| `screen` | ID 參照 |  | CONTROL 必填 | UI | 所屬畫面 |
| `region` | 代號 |  | CONTROL 必填 |  | 所屬區塊 |
| `controlType` | 列舉 |  | EDIT_BOX／DROP_DOWN／…／PUSH_BUTTON…；CONTROL 必填 |  | 控制項型別 |
| `binding` | 物件｜NA |  | CONTROL 必填 | FLD、DRV | 綁定的欄位或衍生值（按鈕寫 NA） |
| `label` | 原文｜NA |  | CONTROL 必填 |  | 畫面文字 |
| `presence` | 列舉 |  | VISIBLE／CONDITIONAL／HIDDEN_TECHNICAL；CONTROL 必填 |  | 出現方式 |
| `visibility` | ALWAYS｜條件式 |  | CONTROL 必填 | FLD、DRV、STATE、ROLE | 顯示條件 |
| `editability` | ALWAYS｜NEVER｜條件式 |  | CONTROL 必填 | FLD、DRV、STATE、ROLE | 可編輯條件 |
| `options` | 陣列〈物件〉 |  | 儲存值須屬於欄位值域 |  | 選項：顯示文字↔儲存值 |
| `valueSource` | 物件 |  | CONTROL 必填 | ENT、FLD、DRV、STATE、ROLE | 值來源 |
| `displayDefault` | 運算元｜NA |  | CONTROL 必填 | FLD、DRV、STATE、ROLE | 畫面初值（寫入資料的預設在 09） |
| `interactions` | 陣列〈物件〉 |  |  | UI | 純畫面互動（會拒絕或寫資料的邏輯寫在 09） |
<!-- /GEN -->

**完整性與審查準則**

- 頁面欄位清單（扣除不建置欄位）每個都有元件（C03）。
- `presence＝CONDITIONAL` 的元件，`visibility` 不能是 ALWAYS（schema）。
- 選項的儲存值屬於欄位值域（R05）。
- 會拒絕或寫資料的邏輯不寫在這裡，寫在 09，並以 `trigger.control` 指回元件。
- 畫面文字與儲存值分開寫；頁面上隱藏的技術欄位標 HIDDEN_TECHNICAL。

**最小合法項目（按鈕元件）**

<!-- GEN:minimal:UI -->
```json
{
  "id": "UI-011",
  "key": "TW_DEMO_REQ.TW_DEMO_REQPG.TW_DEMO_REQWRK.SUBMIT_PB",
  "lifecycle": "ACTIVE",
  "basis": "METADATA",
  "certainty": "CONFIRMED",
  "evidence": [
    "EV-0004"
  ],
  "uiKind": "CONTROL",
  "usedBy": [
    "FR-004"
  ],
  "screen": "UI-007",
  "region": "ACTIONS",
  "controlType": "PUSH_BUTTON",
  "binding": {
    "na": "按鈕；原系統以工作記錄欄位承載事件，不保存資料"
  },
  "label": "送出",
  "presence": "CONDITIONAL",
  "visibility": {
    "left": {
      "fld": "FLD-017"
    },
    "op": "IN",
    "right": [
      {
        "state": "STATE-001"
      },
      {
        "state": "STATE-002"
      }
    ]
  },
  "editability": "ALWAYS",
  "valueSource": {
    "kind": "NONE"
  },
  "displayDefault": {
    "na": "顯示資料庫中的值"
  }
}
```
<!-- /GEN -->

---

## 06 系統架構（技術中立）（06-architecture）

- **用途**：舊系統的邏輯架構：Component 地圖、介面與批次、資料流。讓實作者知道有哪些系統邊界，但不規定新系統怎麼切。
- **輸入來源**：interfaces 研究；01 的物件；04 的轉移。
- **何時產生**：第 5 階段。
- **渲染章節**：
  - 元件地圖（由 01 投影）。
  - 介面與批次明細（IF）。
  - 資料流（由 08、06 的讀寫投影）。
  - 交易邊界總覽（由 08 投影）。

<!-- GEN:fields:IF -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `<物件型別>:<原名>` |  | 外環據以派發 ID |
| `ifType` | 列舉 | ✓ | BATCH_AE／BATCH_SQR／IB_SERVICE／FILE_IN／FILE_OUT／EMAIL／NOTIFICATION／OTHER |  | 介面型別 |
| `object` | ID 參照 | ✓ |  | OBJ | 原系統物件 |
| `name` | 文字 | ✓ |  |  | 業務名稱 |
| `direction` | 列舉 | ✓ | INBOUND／OUTBOUND／INTERNAL |  | 方向 |
| `trigger` | 物件 | ✓ | kind＝SCHEDULE／ON_DEMAND／ON_TRANSITION／ON_SAVE／EVENT | TRN | 觸發方式 |
| `performs` | 陣列〈ID〉 | ✓ | 可空 | TRN | 本介面執行的狀態轉移 |
| `reads` | 陣列〈ID〉 | ✓ | 可空 | FLD | 讀取欄位 |
| `writes` | 陣列〈ID〉 | ✓ | 可空 | FLD | 寫入欄位 |
| `parameters` | 陣列〈物件〉｜NA | ✓ |  | FLD、DRV | 參數／Run Control |
| `format` | 物件｜NA | ✓ | 檔案型才需要 | FLD | 格式、編碼、欄位順序 |
| `errorHandling` | 文字｜UNRESOLVED | ✓ |  |  | 錯誤處理 |
| `retry` | 文字｜NA｜UNRESOLVED | ✓ |  |  | 重試 |
| `idempotency` | 文字｜UNRESOLVED | ✓ |  |  | 重送／重複執行的結果 |
<!-- /GEN -->

**完整性與審查準則**

- 範圍內每個 AE、SQR、IB、檔案物件，都有 IF 或排除理由。
- `trigger.kind＝ON_TRANSITION` 時必須列出轉移（schema）。
- 不出現任何技術選型（覆核）。

**最小合法項目**

<!-- GEN:minimal:IF -->
```json
{
  "id": "IF-001",
  "key": "AE:TW_DEMO_NTFY",
  "lifecycle": "ACTIVE",
  "basis": "CODE",
  "certainty": "CONFIRMED",
  "evidence": [
    "EV-0024"
  ],
  "ifType": "NOTIFICATION",
  "object": "OBJ-001",
  "name": "送審通知",
  "direction": "OUTBOUND",
  "trigger": {
    "kind": "ON_TRANSITION",
    "transitions": [
      "TRN-002",
      "TRN-004"
    ],
    "note": "送出成功後由 SavePostChange 排入程序，非同步執行。"
  },
  "performs": [],
  "reads": [
    "FLD-016"
  ],
  "writes": [],
  "parameters": [
    {
      "name": "REQ_ID",
      "source": {
        "fld": "FLD-016"
      }
    }
  ],
  "format": {
    "na": "不是檔案介面"
  },
  "errorHandling": "寄送失敗只寫入程序紀錄，不影響申請單狀態。",
  "retry": {
    "na": "原系統不重試"
  },
  "idempotency": "同一張單重複排入會重複寄送通知。"
}
```
<!-- /GEN -->

---

## 07 資料設計（07-database）

- **用途**：資料語意的權威：實體、欄位、值域、鍵、有效日、衍生概念（例如「長官」怎麼查）、不建置欄位。
- **輸入來源**：data 研究；原生欄位判定；metadata 欄位清單；PROD 剖析。
- **何時產生**：第 2 階段；衍生概念也可能在後續階段經 `requests` 補進來。
- **渲染章節**：實體清單；欄位明細；衍生概念（查找規則）；不建置的原生欄位。

### ENT 資料實體

<!-- GEN:fields:ENT -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `<Record 原名>` |  | 外環據以派發 ID |
| `record` | ID 參照 | ✓ | OBJ 的 RECORD | OBJ | 對應的 Record |
| `name` | 文字 | ✓ |  |  | 業務名稱 |
| `businessMeaning` | 文字 | ✓ |  |  | 這份資料代表什麼 |
| `storageKind` | 列舉 | ✓ | SQL_TABLE／SQL_VIEW／DYNAMIC_VIEW／DERIVED_WORK／SUBRECORD／TEMP_TABLE／QUERY_VIEW／OTHER_LOGICAL |  | 儲存型態 |
| `physicalName` | 原名｜NA | ✓ |  |  | 實體表名（DERIVED_WORK 等寫 NA） |
| `keys` | 陣列〈ID〉｜NA | ✓ | 有序 | FLD | 邏輯鍵欄位（依序） |
| `effectiveDating` | 物件 | ✓ | kind＝NONE／EFFDT／EFFDT_EFFSEQ；有效日時必附 currentRow | FLD、DRV | 有效日規則：目前有效列＝基準日當天或之前最大 EFFDT（再取最大 EFFSEQ），可限定有效狀態 |
| `parent` | 物件 |  |  | ENT、FLD | 父子關係與鍵對應 |
<!-- /GEN -->

### FLD 資料欄位

<!-- GEN:fields:FLD -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `<Record>.<欄位>` |  | 外環據以派發 ID |
| `entity` | ID 參照 | ✓ |  | ENT | 所屬實體 |
| `fieldName` | 原名 | ✓ |  |  | 欄位原名 |
| `label` | 文字 | ✓ |  |  | 業務標籤 |
| `dataType` | 列舉 | ✓ | CHAR／LONG_CHAR／NUMBER／SIGNED_NUMBER／DATE／DATETIME／TIME／IMAGE／ATTACHMENT |  | 型別 |
| `length` | 整數｜NA | ✓ |  |  | 長度 |
| `decimals` | 整數 |  | NUMBER／SIGNED_NUMBER |  | 小數位數 |
| `required` | 列舉 | ✓ | ALWAYS／CONDITIONAL／NO |  | Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則 |
| `default` | 運算元｜NA | ✓ |  | FLD、DRV | Record 層預設值 |
| `valueDomain` | 五擇一物件 | ✓ | xlat[]／prompt{}／range{}／free／derived | ENT、FLD、DRV | 值域；狀態欄位的 xlat 只列狀態圖上的代碼 |
| `keyRoles` | 陣列〈列舉〉 | ✓ | KEY／DUP_ORDER_KEY／SEARCH_KEY／ALT_SEARCH_KEY／LIST_BOX_ITEM；可空 |  | 鍵屬性 |
| `relations` | 陣列〈物件〉 |  |  | FLD | 與其他欄位的關聯 |
| `sensitivity` | 列舉 | ✓ | NONE／PERSONAL／CONFIDENTIAL |  | 敏感分類 |
| `usageEvidence` | 列舉 | ✓ | DATA_HAS_VALUE／CODE_REFERENCED／METADATA_ONLY／NOT_CHECKED |  | 使用證據等級（供排優先序，不代表排除） |
<!-- /GEN -->

### DRV 衍生概念

<!-- GEN:fields:DRV -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `<代號>` |  | 外環據以派發 ID |
| `name` | 文字 | ✓ |  |  | 概念名稱（例：申請人的直屬主管） |
| `meaning` | 文字 | ✓ |  |  | 業務意義 |
| `inputs` | 陣列〈物件〉 | ✓ | 可空 | FLD、DRV | 輸入參數與來源 |
| `resultType` | 列舉 | ✓ | PERSON_ID／CODE／NUMBER／DATE／TEXT／BOOLEAN／ROW_SET |  | 結果型別 |
| `resolution` | 物件 | ✓ | sources≥1；有效日實體須各有一條 effectiveDating | ENT、FLD、DRV | 查找規則：從哪些表、怎麼串、篩選、取哪一欄 |
| `whenNotFound` | 物件 | ✓ | result＝EMPTY／FALLBACK | DRV | 查無結果時的行為（訊息與阻擋寫在 09） |
| `whenMultiple` | 物件 | ✓ | rule＝UNIQUE_BY_KEY／FIRST_BY_ORDER／ALL_ROWS | FLD | 多筆時的取法 |
| `implementedAt` | 陣列〈ID〉 | ✓ | ≥1 | OBJ | 原系統實作位置 |
<!-- /GEN -->

### XF 不建置的原生欄位

<!-- GEN:fields:XF -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `<Record 原名>` |  | 外環據以派發 ID |
| `entity` | ID 參照 | ✓ |  | ENT | 所屬實體 |
| `fields` | 陣列〈原名〉 | ✓ | ≥1 |  | 判定無用的欄位 |
| `dataCheck` | 固定格式 | ✓ | 非預設 0 筆（全表非空，查詢日 YYYY-MM-DD） |  | 資料剖析結論 |
| `codeChecks` | 物件 | ✓ | a／b／c 三種查法都要有結果 |  | 程式面查法結果 |
<!-- /GEN -->

**完整性與審查準則**

- 範圍內實體表的欄位清單（扣除不建置欄位）每個都有 FLD（C04）。
- 狀態欄位的值域只列圖上代碼（R07）。
- 衍生概念對每個有效日實體都有有效日規則（R08）。
- DRV 必有 `whenNotFound` 與 `whenMultiple`（schema）。
- DEPENDENCY 實體只列核心用到的欄位與鍵（最小替代介面，沿用 clone-contract）。
- XF 的格式沿用 clone-contract 的「原生欄位無用判定」。
- 人工審查：DRV 的查找規則業務單位要認得。

**最小合法項目（DRV）**

<!-- GEN:minimal:DRV -->
```json
{
  "id": "DRV-002",
  "key": "REQUESTER_SUPERVISOR",
  "lifecycle": "ACTIVE",
  "basis": "CODE",
  "certainty": "CONFIRMED",
  "evidence": [
    "EV-0026"
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
    "OBJ-014"
  ]
}
```
<!-- /GEN -->

---

## 08 操作契約（API）（08-api）

- **用途**：新後端必須提供的業務操作，而且技術中立：輸入、輸出、授權、前置條件、檢核順序、效果、交易語意。不寫 HTTP 方法、路徑、資料格式。
- **輸入來源**：02、04、09、06；交易研究（存檔邊界、回復、併發、重送）。
- **何時產生**：第 9 階段。
- **渲染章節**：操作清單；每個操作明細，錯誤與訊息由檢核規則反查。

<!-- GEN:fields:OP -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `<FR 鍵>:<操作代號>` |  | 外環據以派發 ID |
| `fr` | ID 參照 | ✓ |  | FR | 所屬功能 |
| `name` | 文字 | ✓ |  |  | 操作名稱 |
| `opKind` | 列舉 | ✓ | LOAD／SEARCH／CREATE／UPDATE／TRANSITION／DELETE／LOOKUP／BATCH_RUN |  | 操作種類 |
| `invokedFrom` | 陣列〈ID〉｜NA | ✓ |  | UI | 觸發的畫面元件 |
| `authorization` | 條件式 | ✓ |  | FLD、DRV、STATE、ROLE | 誰能執行 |
| `inputs` | 陣列〈物件〉 | ✓ | 可空 | FLD、DRV | 輸入 |
| `outputs` | 陣列〈物件〉 | ✓ | 可空 | FLD、DRV | 輸出 |
| `preconditions` | 條件式｜NA | ✓ |  | FLD、DRV、STATE、ROLE | 前置條件 |
| `validations` | 陣列〈ID〉 | ✓ | 依執行順序；可空 | BR | 套用的檢核規則 |
| `effects` | 物件｜NA | ✓ | 唯讀操作寫 NA | TRN、FLD、DRV、STATE、ROLE、IF | 轉移、寫入、觸發的介面 |
| `transaction` | 物件 | ✓ | boundary／writeOrder／onFailure／concurrency／idempotency | MSG | 交易語意 |
| `legacyOrigin` | 物件 | ✓ |  | OBJ | 原系統對應的物件與事件鏈 |
<!-- /GEN -->

**完整性與審查準則**

- 每個 FR 至少一個 OP（C08）。
- OP 的轉移屬於它的 FR（R11）。
- 檢核清單包含所有會在此操作觸發的拒絕型規則，並依執行順序排列（C08）。
- `transaction` 的五項都要有值，或標 UNRESOLVED。
- 轉移本身的寫入在 04；`effects.writes` 只列操作另外寫入的欄位（例如使用者輸入）。

**最小合法項目**

<!-- GEN:minimal:OP -->
```json
{
  "id": "OP-004",
  "key": "TW_DEMO_REQ:SUBMIT:SUBMIT",
  "lifecycle": "ACTIVE",
  "basis": "DERIVED",
  "certainty": "CONFIRMED",
  "evidence": [
    "EV-0016"
  ],
  "derivedFrom": [
    "FR-004"
  ],
  "fr": "FR-004",
  "name": "送出申請",
  "opKind": "TRANSITION",
  "invokedFrom": [
    "UI-011"
  ],
  "authorization": {
    "all": [
      {
        "left": {
          "ctx": "CURRENT_USER_OPRID"
        },
        "op": "HAS_ROLE",
        "right": {
          "role": "ROLE-002"
        }
      },
      {
        "left": {
          "fld": "FLD-015"
        },
        "op": "EQ",
        "right": {
          "ctx": "CURRENT_USER_EMPLID"
        }
      }
    ]
  },
  "inputs": [
    {
      "name": "REQ_ID",
      "field": "FLD-016",
      "required": true
    }
  ],
  "outputs": [
    {
      "name": "REQ_STATUS",
      "field": "FLD-017"
    }
  ],
  "preconditions": {
    "left": {
      "fld": "FLD-017"
    },
    "op": "IN",
    "right": [
      {
        "state": "STATE-001"
      },
      {
        "state": "STATE-002"
      }
    ]
  },
  "validations": [
    "BR-006"
  ],
  "effects": {
    "transitions": [
      "TRN-002",
      "TRN-004"
    ],
    "writes": [
      {
        "field": "FLD-010",
        "value": {
          "param": "AMOUNT"
        }
      },
      {
        "field": "FLD-014",
        "value": {
          "param": "REASON"
        }
      }
    ],
    "interfaces": [
      "IF-001"
    ]
  },
  "transaction": {
    "boundary": "SINGLE_UNIT",
    "writeOrder": "單一列更新（TW_DEMO_REQHDR）；通知在交易提交後才排入。",
    "onFailure": {
      "kind": "ROLLBACK_ALL",
      "note": "任何檢核失敗或存檔錯誤時整筆不寫入，狀態不變。"
    },
    "concurrency": {
      "strategy": "STALE_DATA_CHECK",
      "legacyBehavior": "開啟後到存檔之間若資料已被他人更新，存檔被拒絕並顯示訊息，該筆維持先存檔者的結果，本次輸入不寫入。",
      "message": "MSG-004"
    },
    "idempotency": {
      "repeatable": false,
      "behavior": "送出後按鈕隱藏；同一張單不能重複送出。"
    }
  },
  "legacyOrigin": {
    "object": "OBJ-014",
    "events": [
      "FieldChange",
      "SaveEdit",
      "SavePostChange"
    ]
  }
}
```
<!-- /GEN -->

---

## 09 業務邏輯（09-business-logic）

- **用途**：檢核、計算、預設、衍生、副作用規則與訊息原文；核心 PeopleCode 程式的處置。
- **輸入來源**：rules 研究；05 的元件；04 的轉移；06 的介面。
- **何時產生**：第 8 階段。
- **渲染章節**：程式處置表；規則清單與明細；訊息表。
- **外殼欄位**：

<!-- GEN:extra:09-business-logic -->
| 外殼欄位 | 型別 | 必填 | 值域／限制 | 說明 |
|---|---|---|---|---|
| `programDispositions` | 陣列〈物件〉 | ✓ | 核心 PeopleCode 清單每支恰一筆；items 只能指 BR／MSG／TRN／DRV／UI／IF | PeopleCode 程式處置（覆蓋率分母） |
<!-- /GEN -->

### MSG 訊息

<!-- GEN:fields:MSG -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `<訊息集>,<編號>｜TEXT:<雜湊>` |  | 外環據以派發 ID |
| `messageSet` | 整數｜NA | ✓ | 寫死字串寫 NA |  | 訊息集 |
| `messageNumber` | 整數｜NA | ✓ |  |  | 訊息編號 |
| `text` | 原文 | ✓ |  |  | 訊息原文 |
| `severity` | 列舉 | ✓ | ERROR／WARNING／MESSAGE／CANCEL |  | 嚴重度 |
| `parameters` | 陣列〈文字〉 |  |  |  | 參數意義（依序） |
<!-- /GEN -->

### BR 業務規則

<!-- GEN:fields:BR -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `<實作位置>:<規則代號>` |  | 外環據以派發 ID |
| `name` | 文字 | ✓ |  |  | 規則名稱 |
| `brKind` | 列舉 | ✓ | VALIDATION／CALCULATION／DEFAULTING／DERIVATION／AUTHORIZATION／SIDE_EFFECT／CONSTRAINT |  | 規則種類 |
| `appliesTo` | 陣列〈ID〉 | ✓ | ≥1 | FR | 適用的功能 |
| `trigger` | 物件 | ✓ | event 必填 | UI、TRN | 觸發事件、元件、轉移、模式 |
| `condition` | 條件式 | ✓ | 無條件寫 ALWAYS | FLD、DRV、STATE、ROLE | 精確條件 |
| `action` | 物件 | ✓ | REJECT／WARN 必附 message；SET_VALUE 必附 assignments；INVOKE_INTERFACE／NOTIFY 必附 interface | MSG、FLD、DRV、STATE、ROLE、IF | 動作 |
| `order` | 整數｜UNRESOLVED | ✓ |  |  | 同一觸發點內的執行順序 |
| `boundaries` | 文字｜NA | ✓ |  |  | NULL／空白／0／日期邊界的處理 |
| `modeDifferences` | 文字｜NA | ✓ |  |  | 不同模式或角色的差異 |
| `implementedAt` | 物件 | ✓ |  | OBJ | 原系統實作位置 |
<!-- /GEN -->

**完整性與審查準則**

- 核心 PeopleCode 程式每支恰一筆處置（C05）。
- REJECT、WARN 必附訊息（schema）。
- 觸發元件屬於規則適用的功能（R10）。
- 條件只能用運算元，所以「需要長官審核」這類寫法不可能出現。
- `boundaries` 要寫具體的邊界：空白、0、NULL、日期。

**最小合法項目（BR）**

<!-- GEN:minimal:BR -->
```json
{
  "id": "BR-006",
  "key": "TW_DEMO_REQWRK.SUBMIT_PB.FieldChange:SUPERVISOR_REQUIRED",
  "lifecycle": "ACTIVE",
  "basis": "CODE",
  "certainty": "CONFIRMED",
  "evidence": [
    "EV-0016"
  ],
  "name": "送出時申請人必須有直屬主管",
  "brKind": "VALIDATION",
  "appliesTo": [
    "FR-004"
  ],
  "trigger": {
    "event": "FIELD_CHANGE",
    "control": "UI-011",
    "transitions": [
      "TRN-002",
      "TRN-004"
    ]
  },
  "condition": {
    "left": {
      "drv": "DRV-002"
    },
    "op": "NOT_EXISTS"
  },
  "action": {
    "kind": "REJECT",
    "message": "MSG-003"
  },
  "order": 1,
  "boundaries": "SUPERVISOR_ID 為空白（單一空白）視同找不到。",
  "modeDifferences": {
    "na": "只在按送出時檢查"
  },
  "implementedAt": {
    "object": "OBJ-014",
    "event": "FieldChange"
  }
}
```
<!-- /GEN -->

---

## 14 測試與驗收（14-testing）

- **用途**：可以直接寫成自動化測試或人工驗收的案例：正例、反例、邊界、端到端。本設計不實跑，案例是待執行的驗收設計。
- **輸入來源**：02、04、05、08、09。
- **何時產生**：第 10 階段。
- **渲染章節**：覆蓋摘要（外環計算每個 FR、BR、TRN、FLOW 有哪些案例）；案例明細。

<!-- GEN:fields:TC -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `<FR 鍵>:<類型>:<代號>` |  | 外環據以派發 ID |
| `name` | 文字 | ✓ |  |  | 案例名稱 |
| `scenarioType` | 列舉 | ✓ | POSITIVE／NEGATIVE／BOUNDARY |  | 正例／反例／邊界 |
| `fr` | ID 參照 | ✓ |  | FR | 主要功能 |
| `covers` | 物件 | ✓ | 至少一類 | BR、TRN、FLOW、UI、OP | 覆蓋的規則／轉移／情境／元件／操作 |
| `preconditions` | 物件 | ✓ | synthetic 必為 true | STATE、FLD、DRV、ROLE | 前置狀態、操作者、前置資料（合成） |
| `steps` | 陣列〈物件〉 | ✓ | ≥1 | UI、OP、FLD | 操作步驟 |
| `expected` | 物件 | ✓ | 至少一項 | MSG、STATE、UI、FLD | 預期訊息、狀態、元件、資料 |
| `verification` | 文字 | ✓ |  |  | 如何核對 |
<!-- /GEN -->

**完整性與審查準則**

- C07 全過：
  - 每個 FR 有正例。
  - 每條拒絕型規則有反例。
  - 條件含大小比較或區間的規則與守衛有邊界例。
  - 每條轉移、每個情境都有案例。
- 前置資料一律是合成資料（`synthetic＝true`）。
- 預期結果至少一項（schema）。

**最小合法項目**

<!-- GEN:minimal:TC -->
```json
{
  "id": "TC-011",
  "key": "TW_DEMO_REQ:SUBMIT:NEGATIVE:NO_SUPERVISOR",
  "lifecycle": "ACTIVE",
  "basis": "DERIVED",
  "certainty": "CONFIRMED",
  "evidence": [],
  "derivedFrom": [
    "FR-004"
  ],
  "name": "沒有直屬主管不能送出",
  "scenarioType": "NEGATIVE",
  "fr": "FR-004",
  "covers": {
    "rules": [
      "BR-006"
    ]
  },
  "preconditions": {
    "actor": {
      "left": {
        "fld": "FLD-015"
      },
      "op": "EQ",
      "right": {
        "ctx": "CURRENT_USER_EMPLID"
      }
    },
    "data": [
      {
        "field": "FLD-015",
        "value": "E1001"
      },
      {
        "field": "FLD-017",
        "value": "010"
      },
      {
        "field": "FLD-009",
        "value": " ",
        "note": "E1001 的目前有效任職列為單一空白"
      }
    ],
    "synthetic": true,
    "state": "STATE-001"
  },
  "steps": [
    {
      "seq": 1,
      "action": "以 E1001 按「送出」",
      "control": "UI-011",
      "operation": "OP-004"
    }
  ],
  "expected": {
    "message": "MSG-003",
    "noDataChange": true
  },
  "verification": "畫面顯示訊息 27000,3；該列 REQ_STATUS 仍為 010。"
}
```
<!-- /GEN -->

---

## 16 AI 實作指引（16-ai-instructions）

- **用途**：給重建端 AI 的固定條款，內容由框架模板提供，每個 job 都一樣。
- **條款**（範例中的 10 條）：
  - 閱讀順序與 ID 前綴對照。
  - 只實作本體、圖外不做。
  - 不建置欄位不建。
  - 儲存值保留原值。
  - 空白語意。
  - UNRESOLVED 不自行補。
  - NOT_APPLICABLE 不是待辦。
  - 不照搬原系統結構。
  - 程式與測試標註 ID。
  - 發現矛盾時回報，不自行修改規格。

<!-- GEN:fields:AI -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `AI:<序號>` |  | 外環據以派發 ID |
| `category` | 列舉 | ✓ | READING／SCOPE／DATA／LOGIC／UNKNOWN_HANDLING／CHANGE_DISCIPLINE／TRACEABILITY／LANGUAGE |  | 條款類別 |
| `clause` | 文字 | ✓ |  |  | 條款內容 |
<!-- /GEN -->

**完整性與審查準則**：條款不含個案內容；修改條款要提高框架的 schema 版本。

**最小合法項目**

<!-- GEN:minimal:AI -->
```json
{
  "id": "AI-001",
  "key": "AI:01",
  "lifecycle": "ACTIVE",
  "basis": "TEMPLATE",
  "certainty": "CONFIRMED",
  "evidence": [],
  "category": "READING",
  "clause": "先讀 00-index：閱讀順序、ID 前綴對照、本版狀態。看到任何 ID，到前綴對照表指定的文件找定義；以 ID 為準，不以章節位置為準。"
}
```
<!-- /GEN -->

---

## 17 工作拆解與相依（17-tasks）

- **用途**：重建端的工作骨架：一個基礎工作（資料結構、衍生概念、角色），加上每個 FR 一個垂直切片。
- **產生方式**（外環計算）：
  - `members` 由反查得到。
  - 順序：從新建開始，對狀態圖做廣度優先，依各 FR 最早轉移的層級排序。
  - 相依：到達前置狀態的第一條轉移，所屬的 FR 就是前置工作。
- **重建端**：可以再細分、估時，但不回寫 Spec。

<!-- GEN:fields:TASK -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `FOUNDATION:<代號>｜SLICE:<FR 鍵>` |  | 外環據以派發 ID |
| `taskKind` | 列舉 | ✓ | SLICE／FOUNDATION |  | 工作種類 |
| `fr` | ID 參照｜NA | ✓ | FOUNDATION 寫 NA | FR | 對應功能 |
| `name` | 文字 | ✓ |  |  | 工作名稱 |
| `order` | 整數 | ✓ |  |  | 建議順序 |
| `dependsOn` | 陣列〈ID〉 | ✓ | 可空 | TASK | 前置工作 |
| `members` | 物件 | ✓ | 外環計算 | ENT、FLD、DRV、ROLE、TRN、UI、BR、OP、TC | 本工作涵蓋的項目 |
| `deliverables` | 陣列〈列舉〉 | ✓ | DATA_STRUCTURE／OPERATIONS／SCREENS／RULES／SECURITY／TESTS |  | 交付物 |
<!-- /GEN -->

**完整性與審查準則**：每個 FR 恰一個切片（C10）；相依無循環。

**最小合法項目**

<!-- GEN:minimal:TASK -->
```json
{
  "id": "TASK-005",
  "key": "SLICE:TW_DEMO_REQ:SUBMIT",
  "lifecycle": "ACTIVE",
  "basis": "COMPUTED",
  "certainty": "CONFIRMED",
  "evidence": [],
  "taskKind": "SLICE",
  "fr": "FR-004",
  "name": "送出申請",
  "order": 3,
  "dependsOn": [
    "TASK-001"
  ],
  "members": {
    "fields": [
      "FLD-010",
      "FLD-014",
      "FLD-015",
      "FLD-016",
      "FLD-017",
      "FLD-018"
    ],
    "derivations": [
      "DRV-002"
    ],
    "roles": [
      "ROLE-002"
    ],
    "transitions": [
      "TRN-002",
      "TRN-004"
    ],
    "controls": [
      "UI-008",
      "UI-009",
      "UI-010",
      "UI-011"
    ],
    "rules": [
      "BR-001",
      "BR-003",
      "BR-006"
    ],
    "operations": [
      "OP-004"
    ],
    "tests": [
      "TC-011",
      "TC-012",
      "TC-013"
    ]
  },
  "deliverables": [
    "OPERATIONS"
  ]
}
```
<!-- /GEN -->

---

## 18 完成定義（18-definition-of-done）

- **用途**：每個工作的完成條件與要交的證據，另有一份全域條件。重建端用它判定完成；Spec 端不標記完成。
- **產生方式**：外環計算。全域條件來自框架模板；工作條件由工作成員反查得到（測試、規則、訊息）。

<!-- GEN:fields:DOD -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `GLOBAL:<代號>｜TASK:<工作鍵>` |  | 外環據以派發 ID |
| `scope` | 列舉 | ✓ | GLOBAL／TASK |  | 適用範圍 |
| `task` | ID 參照 |  | scope＝TASK 時必填 | TASK | 對應工作 |
| `criteria` | 陣列〈物件〉 | ✓ | kind／statement／refs／evidenceRequired | GOAL、RESP、OBJ、ENT、FLD、DRV、XF、ROLE、PERM、STATE、TRN、FLOW、IF、FR、UI、MSG、BR、OP、TC、TASK | 完成條件 |
<!-- /GEN -->

**完整性與審查準則**：每個 TASK 都有 DOD（C10）；`refs` 指向的項目都存在（R01）。

**最小合法項目**

<!-- GEN:minimal:DOD -->
```json
{
  "id": "DOD-006",
  "key": "TASK:SLICE:TW_DEMO_REQ:SUBMIT",
  "lifecycle": "ACTIVE",
  "basis": "COMPUTED",
  "certainty": "CONFIRMED",
  "evidence": [],
  "scope": "TASK",
  "task": "TASK-005",
  "criteria": [
    {
      "kind": "TESTS_PASS",
      "statement": "本工作的測試案例全數通過。",
      "refs": [
        "TC-011",
        "TC-012",
        "TC-013"
      ],
      "evidenceRequired": "TEST_REPORT"
    }
  ]
}
```
<!-- /GEN -->

---

## 19 決策紀錄（19-decision-log）

- **用途**：人對問題的裁決，包含背景、選項、理由、影響。
- **輸入來源**：只有人工裁決檔（`decisions.md`）；模型不產生決策。
- **規則**：
  - 決策者只寫職稱或單位類別。
  - 被取代的決策保留並標 SUPERSEDED。
  - 撤銷的決策標 REVOKED。

<!-- GEN:fields:DEC -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `DEC:<四位序號>` |  | 外環據以派發 ID |
| `title` | 文字 | ✓ |  |  | 決策標題 |
| `context` | 文字 | ✓ |  |  | 背景 |
| `options` | 陣列〈物件〉 |  | ≥2 |  | 考慮過的選項 |
| `decision` | 文字 | ✓ |  |  | 決定 |
| `rationale` | 文字 | ✓ |  |  | 理由 |
| `decidedBy` | 文字 | ✓ | 只寫職稱或單位類別 |  | 決策者 |
| `decidedOn` | 日期 | ✓ |  |  | 決策日期 |
| `status` | 列舉 | ✓ | ACCEPTED／SUPERSEDED／REVOKED |  | 決策狀態 |
| `supersedes` | ID 參照 |  |  | DEC | 取代的舊決策 |
| `resolves` | 陣列〈ID〉 | ✓ | 可空 | Q | 回答的問題 |
| `affects` | 陣列〈ID〉 | ✓ | 可空 | GOAL、RESP、OBJ、ENT、FLD、DRV、XF、ROLE、PERM、STATE、TRN、FLOW、IF、FR、UI、MSG、BR、OP、TC | 影響的規格項目 |
| `effect` | 列舉 | ✓ | NO_CHANGE／DROP／ADD_SCOPE／ACCEPT_GAP／AMEND_INPUT |  | 對規格的效果 |
<!-- /GEN -->

**最小合法項目**

<!-- GEN:minimal:DEC -->
```json
{
  "id": "DEC-001",
  "key": "DEC:0001",
  "lifecycle": "ACTIVE",
  "basis": "HUMAN_DECISION",
  "certainty": "CONFIRMED",
  "evidence": [
    "EV-0064"
  ],
  "title": "不重建「核准後重開為草稿」",
  "context": "Q-002：TW_DEMO_APV.PostBuild 有一段狀態圖外的 030→010 邏輯。",
  "decision": "不重建。",
  "rationale": "這是管理者以特殊參數做的資料維護，不是業務流程；STATUS 文件不納入。",
  "decidedBy": "業務單位主管",
  "decidedOn": "2026-10-08",
  "status": "ACCEPTED",
  "resolves": [
    "Q-002"
  ],
  "affects": [
    "OBJ-007"
  ],
  "effect": "DROP"
}
```
<!-- /GEN -->

---

## 90 問題清單（90-questions）

- **用途**：所有未解或待裁決的問題：
  - 圖外狀態與圖外轉移（分級）。
  - 找不到實作的轉移。
  - 證據缺口。
  - 讀者不一致。
  - 範圍候選。
  - 輸入缺漏。
- **產生方式**：外環彙整研究、解析、讀者、檢核的結果。問題的 ANSWERED、ACCEPTED_AS_GAP 狀態由 19 的決策反查。
- **外殼欄位**：

<!-- GEN:extra:90-questions -->
| 外殼欄位 | 型別 | 必填 | 值域／限制 | 說明 |
|---|---|---|---|---|
| `suppressed` | 物件 | ✓ |  | 只存在於值域定義、沒有資料也沒有核心程式使用的狀態碼（只計數，不列題） |
<!-- /GEN -->

<!-- GEN:fields:Q -->
| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |
|---|---|---|---|---|---|
| `key` | 自然鍵 | ✓ | `<類別>:<自然鍵>` |  | 外環據以派發 ID |
| `category` | 列舉 | ✓ | OFF_DIAGRAM_STATE／OFF_DIAGRAM_TRANSITION／DIAGRAM_EDGE_UNIMPLEMENTED／SCOPE_CANDIDATE／EVIDENCE_GAP／READER_*／INPUT_MISSING |  | 問題類別 |
| `severity` | 列舉 | ✓ | 圖外與 INPUT_MISSING 必為 INFO，其餘必為 BLOCKING |  | 是否阻擋完成 |
| `grade` | 列舉 |  | 圖外類必填 |  | 圖外分級：HIGH＝PROD 有資料；LOW＝僅核心程式賦值 |
| `question` | 文字 | ✓ |  |  | 問題敘述 |
| `affects` | 陣列〈ID〉 | ✓ | 可空 | GOAL、RESP、OBJ、ENT、FLD、DRV、XF、ROLE、PERM、STATE、TRN、FLOW、IF、FR、UI、MSG、BR、OP、TC | 受影響的規格項目 |
| `observed` | 物件 |  | 圖外類必填 |  | 觀察到的狀態碼／轉移／位置 |
| `raisedBy` | 列舉 | ✓ | PARSER／RESEARCH／REVIEW／READER／GATE |  | 提出來源 |
| `status` | 列舉 | ✓ | OPEN／ANSWERED／WITHDRAWN／ACCEPTED_AS_GAP |  | 狀態（ANSWERED／ACCEPTED_AS_GAP 由 19 的決策反查） |
| `proposedAnswer` | 文字 |  | 僅供參考 |  | 研究端建議的答案（不等於決策） |
<!-- /GEN -->

**完整性與審查準則**

- 圖外類必為 INFO，且有分級與觀察值（schema）。
- 找不到實作、範圍候選、證據缺口、讀者類必為 BLOCKING（schema）。
- 人工審查：HIGH 級逐一裁決；BLOCKING 必須為 0，或有 ACCEPT_GAP 決策。

**最小合法項目**

<!-- GEN:minimal:Q -->
```json
{
  "id": "Q-001",
  "key": "OFF_DIAGRAM_STATE:REQ_STATUS:099",
  "lifecycle": "ACTIVE",
  "basis": "COMPUTED",
  "certainty": "CONFIRMED",
  "evidence": [
    "EV-0011"
  ],
  "category": "OFF_DIAGRAM_STATE",
  "severity": "INFO",
  "grade": "HIGH",
  "question": "PROD 有 REQ_STATUS＝099 的資料，但狀態圖沒有這個狀態。是歷史資料（只需資料移轉對應），還是狀態圖漏畫？",
  "affects": [
    "FLD-017"
  ],
  "observed": {
    "entityKey": "REQ_STATUS",
    "code": "099"
  },
  "raisedBy": "RESEARCH",
  "status": "OPEN"
}
```
<!-- /GEN -->

---

## 證據登錄（evidence.json）

每個版本一份。項目以 `EV-<4 碼>` 引用；格式見 `schemas/evidence.schema.json` 與主文件 §5.7。

| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| `id` | `EV-<4 碼以上>` | ✓ | 證據 ID |
| `kind` | 列舉 | ✓ | CHUNK、SQL、NN、WIKI、STATUS_DOC、PROJECT_INPUT、METADATA_RECEIPT、HUMAN_DECISION |
| `locator` | 原文 | ✓ | CHUNK：完整 UUID；SQL：實際執行的 SELECT；檔案類：`<檔>#L<行>` 或 `#L<起>-L<迄>` |
| `excerpt` | 原文 | ✓ | 關鍵摘錄，最多 5 行 |
| `capturedOn` | 日期 |  | 取得日期 |
