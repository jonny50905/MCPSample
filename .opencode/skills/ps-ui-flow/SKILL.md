---
name: ps-ui-flow
description: PeopleSoft UI 分析 — 畫面顯示文字、選項 label 與儲存值對映、由文字反查 Component / Page / Record.Field。
---

# ps-ui-flow：UI 結構 + 業務語意

## 職責

回傳的不只是結構：

```text
Component → Page → Control → Display Text → Choice Values → Record.Field → PeopleCode Event
```

Page 上使用者**真正看到的文字**（含選項文字）是第一級業務語意，
優先級高於 Record Name / Field Name / PeopleCode Symbol / AE Name / SQL Name。

## UI Semantic Index：應索引的 UI 文字

```text
Page Field Label / Grid Column Label / Tab Label / Group Box Label
Button Label / Hyperlink Label / Static Text / Page Title
Component Label / Menu Label / Prompt Label
Radio Button Label / Drop-down Display Text / Checkbox Label
Instruction Text / Message Text
```

每筆顯示文字需記錄來源（`displayTextSource`）：

```text
PAGE_FIELD_OVERRIDE / RECORD_FIELD_LABEL / FIELD_LABEL / STATIC_TEXT
GRID_COLUMN_LABEL / TAB_LABEL / GROUPBOX_LABEL / BUTTON_LABEL
MENU_LABEL / COMPONENT_LABEL / MESSAGE_CATALOG / DYNAMIC_PEOPLECODE / UNKNOWN
```

## 最終顯示文字解析優先序

```text
1. Page Field 明確覆寫的 Label
2. Page / Grid / Control 專用 Label
3. Record Field Label
4. Field Label
5. Component / Menu Label
```

文字由 PeopleCode 動態指定時：標 `status: DYNAMIC_RUNTIME`，
保留 `defaultStaticText` 與 `dynamicLabelEvidence`，
**不可假設執行時一定顯示預設文字**。

語系必須保留：`languageCode` / `displayText` / `fallbackLanguageCode`。

## 業務搜尋權重

```text
最高： Page 最終顯示文字 exact match、選項顯示文字 exact match
高：   Page 顯示文字 semantic match、Grid/Tab/Group Box 文字、客製 Object Description
中：   Record Field Label、PeopleCode / SQL / SQR Chunk
較低： 純技術 Object Name、原生物件相似描述
```

## 選項（Choice）是業務邏輯的一部分

畫面選項文字（未服役/服役中/已退伍/免役/替代役）比儲存值（N/S/D/E/A）
更接近業務語意，必須可**反向追蹤**到 Record.Field 與 stored value。

Choice Type：

```text
TRANSLATE_VALUE / PROMPT_TABLE / RADIO_BUTTON / DROP_DOWN / LIST_BOX
CHECKBOX / YES_NO / PAGE_STATIC_CHOICE / DYNAMIC_PROMPT / DYNAMIC_PEOPLECODE / UNKNOWN
```

各類型需保留欄位：

- Translate Value：`fieldName / storedValue / displayText / languageCode / effectiveDate / status`
- Prompt Table：`promptRecord / keyFields / displayFields / searchFields / securityRecord`
  - 低基數（十幾種狀態/類別）：Value + Label 建索引，可直接答「免役是哪個值」。
  - 高基數（員工/部門/職位）：**不可**全量塞給 LLM，只索引 Prompt Metadata，
    查特定值時透過 MCP on-demand search，遵守資料權限與敏感資料遮罩。
- Radio / Drop-down（page-specific）：`storedValue / displayText / controlType / pageName / recordName / fieldName`
- Checkbox：`checkedValue / uncheckedValue / checkedLabel / uncheckedLabel`
- Dynamic Prompt（Prompt Record / Edit Table / 選項由 PeopleCode 動態指定）：
  標 `DYNAMIC_RUNTIME` 並追蹤相關 PeopleCode Evidence。

## 工具

| 工具 | 用途 |
|---|---|
| `ps_search_ui_semantics` | 由顯示文字 / 選項文字反查 Component / Page / Record.Field |
| `ps_get_ui_graph` | 取 UI 圖（含 controls、display text、choices、languages） |
| `ps_get_field_choices` | 取某欄位的 choice type 與選項清單（label ↔ stored value） |

圖節點 / 邊定義與參數契約見 `.opencode/peoplesoft/mcp-tool-contracts.md` §2。

## Skill Rules

```text
Treat user-visible UI text as first-class business metadata.

When resolving a business term:
1. Search final page display text.
2. Search choice labels.
3. Search grid, tab, group box, button, and static text.
4. Map matching text to Page, Component, Record, and Field.
5. Only then expand to PeopleCode, SQL, AE, SQR, and security logic.

Prefer page-specific display text over generic field labels.

Always preserve:
- language
- display text source
- component
- page
- control type
- record and field
- stored value for choice items

For fields with selectable values:
- retrieve the choice type
- retrieve low-cardinality choices
- map display labels to stored values
- identify prompt records
- mark runtime-generated choices as DYNAMIC_RUNTIME

Do not load all values from a high-cardinality prompt table.
Search values on demand through MCP.

When display text is dynamically assigned by PeopleCode:
- preserve the default static label
- include PeopleCode evidence
- mark the final runtime text as DYNAMIC_RUNTIME
```

## Context 控制

```text
UI 搜尋首次最多 20 個 UI Semantic Candidates，
只保留 5～8 個不同 Component / Field。

Choice Values：低基數最多回傳 100 個；
高基數只回傳查詢命中的 20～50 個。
```

## Subagent 模式

以 OpenCode subagent（`.opencode/agent/ps-ui-flow.md`）執行時：
- 委派 prompt 自帶 domain / searchMode / customPrefixes，直接採用，不重新解析。
- 最終輸出只能是 `.opencode/peoplesoft/subagent-report-contract.md` 的 JSON 報告；
  raw 資料留在本 context，不回傳（單段引用 ≤ 5 行）。

## 相關檔案

- `.opencode/peoplesoft/customization-profile.yaml`（origin / prefix 過濾）
- `.opencode/peoplesoft/mcp-tool-contracts.md`
