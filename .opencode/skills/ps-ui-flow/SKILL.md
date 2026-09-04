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
導覽入口的**每一段**（Portal → Folder → … → CREF）同樣要各自保留這三項
再加 `displayTextSource`（`LANG`＝PSPRSMDEFNLANG 覆寫／`BASE`＝PSPRSMDEFN 原生）——
逐段記錄才做得到「ZHT 優先、缺翻譯 fallback ENG」而不是整條路徑一個語系（issue #24）。

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

## 條件 UI（UI 狀態變異的目標解析）

輸入＝ps-peoplecode-flow 偵測到的 UI 狀態變異（如 `REC.FIELD.Visible = False`
與其條件式）。解析流程（查詢樣板：cookbook §2h～§2j）：

1. Record.Field → 控制項（§2h，**不濾 FIELDTYPE**），依 FIELDTYPE 分流：
   - 一般控制項 → 受影響者即其自身，解析完成。
   - 2（Group Box）→ `PTHIDEFIELDS = 1` 才展開框內控制項（§2i）；
     `PTHIDEFIELDS = 0` ＝只隱藏外框，標 presentationOnly、不展開。
   - 11（Subpage）→ 以 SUBPNLNAME 展開（§2j）。
2. 展開結果含 FIELDTYPE=11 → 遞迴展開；追蹤 `visitedPages`（去重）、
   `maxSubpageDepth: 8`。
3. 目標所在 PNLNAME 查 §2e 無 Component（＝它是 Subpage）→ 先向上解析
   （§2j 第二式）找掛載 Page 再對映 Component；多個 Component 候選
   全保留，以 PeopleCode 證據所在者優先。
4. 受影響清單只列**業務資料欄位**（濾掉 static text／frame／純裝飾
   控制項），最多 15 項＋「其餘 N 項」一句；欄位缺 LBLTEXT → §2c 補 label。

解析結果值域（封閉）：`RESOLVED / NOT_APPLICABLE / UNRESOLVED`。
scroll 層級變異（HideRow／HideScroll 等，無 Record.Field 可解析）
＝ `NOT_APPLICABLE`，不是失敗、不寫 gaps。
幾何包含（§2i）＝推斷：「欄位在框內」的結論最高標 INFERRED；
座標與 metadata 事實本身仍是 SQL 證據（sql＋keyRows）。

## 工具

| 工具 | 用途 |
|---|---|
| `ps_search_ui_semantics` | 由顯示文字 / 選項文字反查 Component / Page / Record.Field |
| `ps_get_ui_graph` | 取 UI 圖（含 controls、display text、choices、languages） |
| `ps_get_field_choices` | 取某欄位的 choice type 與選項清單（label ↔ stored value） |
| `ps_get_navigation_entries` | 取 Portal Registry 導覽入口（複數；含 entryType／labels／visibility）與 technicalMenuLocations |

圖節點／邊的詞彙表見 `.opencode/peoplesoft/mcp-tool-contracts.md` §2；
導覽入口的 `navigationEntryType`／`navigationVisibility` 值域見同檔 §3。

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

Navigation entries (issue #24):
- PSMENUITEM MENUNAME/BARNAME/ITEMNAME is technical menu metadata only.
  Never render it as a user-facing navigation path and never use it as a
  fallback when Portal Registry lookup finds nothing.
- Always return navigationEntries as a list; one CREF row is one path, and
  multiple CREF rows (target plus links) are multiple entries. Never collapse.
- Without user/security context, visibility is REGISTRY_DEFINED at best.
  Use UNKNOWN_VISIBILITY for hidden-from-nav ancestors, expired CREFs,
  walks that never reach the root, and un-inspected surfaces.
  Never emit AUTHORIZED_FOR_CONTEXT in this version.
- Report Navigation Collection, Fluid tile and NavBar as gaps even when no
  such rows are found — absence of rows is not proof of a single entry point.
```

## Context 控制

```text
UI 搜尋首次最多 20 個 UI Semantic Candidates，
只保留 5～8 個不同 Component / Field。

Choice Values：低基數最多回傳 100 個；
高基數只回傳查詢命中的 20～50 個。

條件 UI 解析單次委派最多 8 筆變異；
超出的逐筆列在 gaps 退回（標「本次未處理」）。
```

## Subagent 模式

以 OpenCode subagent（`.opencode/agent/ps-ui-flow.md`）執行時：
- 委派 prompt 自帶 domain / searchMode / customPrefixes，直接採用，不重新解析。
- 最終輸出只能是 `.opencode/peoplesoft/subagent-report-contract.md` 的 JSON 報告；
  raw 資料留在本 context，不回傳（單段引用 ≤ 5 行）。

## 相關檔案

- `.opencode/peoplesoft/customization-profile.yaml`（origin / prefix 過濾）
- `.opencode/peoplesoft/mcp-tool-contracts.md`
