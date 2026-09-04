# MCP Tool 提案規格（未來實作用——agent 不讀本檔）

本檔存放尚未實作的 ps_* 工具完整 I/O 規格,自
`.opencode/peoplesoft/mcp-tool-contracts.md` 移出(2026-08):完整 JSON
範例對執行中的 agent 是危險雜訊——長得像可呼叫的工具,呼叫必得
unavailable tool。實作 MCP server 時以本檔為最小契約,可擴充欄位、
不可改變既有欄位語意。現況各角色由誰承擔見 mcp-tool-contracts.md。

## 1.1 ps_get_customization_profile

輸入:

```json
{ "environment": "PROD" }
```

輸出:`customization-profile.yaml` + `business-domain-map.yaml` 的等價 JSON
(profileVersion、customPrefixes、customObjectRegistry、objectOrigins、
searchPolicy、businessDomains)。

## 1.2 ps_get_object_origin

輸入:

```json
{ "objectType": "COMPONENT", "objectName": "TW_MILITARY_DATA" }
```

輸出:

```json
{
  "objectType": "COMPONENT",
  "objectName": "TW_MILITARY_DATA",
  "origin": "CUSTOM_PREFIX",
  "matchedPrefix": "TW_",
  "confidence": 1.0,
  "evidence": []
}
```

`origin` ∈ `CUSTOM_PREFIX | CUSTOM_REGISTRY | MODIFIED_DELIVERED | DELIVERED | UNKNOWN`。

## 1.3 ps_search_business_domains

輸入:

```json
{ "query": "免役有哪些選項？", "topK": 3 }
```

輸出:命中的 domain 清單(domainId、displayName、matchedAlias、
rootObjectPolicy、preferredPrefixes、deliveredFallback、score)。

## 2.1 ps_search_ui_semantics

輸入:

```json
{
  "query": "免役",
  "environment": "PROD",
  "languageCode": "ZHT",
  "customizationMode": "CUSTOM_ONLY_ROOTS",
  "customPrefixes": ["TW_"],
  "topK": 20
}
```

輸出:

```json
{
  "results": [
    {
      "matchType": "CHOICE_LABEL",
      "displayText": "免役",
      "storedValue": "E",
      "componentName": "TW_MILITARY_DATA",
      "pageName": "TW_MILITARY_PG",
      "recordName": "TW_MILITARY",
      "fieldName": "MIL_STATUS",
      "objectOrigin": "CUSTOM_PREFIX",
      "score": 1.0
    }
  ]
}
```

`matchType` 例:`DISPLAY_TEXT_EXACT | DISPLAY_TEXT_SEMANTIC | CHOICE_LABEL |
GRID_COLUMN_LABEL | TAB_LABEL | GROUPBOX_LABEL | BUTTON_LABEL | STATIC_TEXT |
OBJECT_DESCRIPTION`。

## 2.2 ps_get_ui_graph

輸入:

```json
{
  "rootType": "COMPONENT",
  "rootName": "TW_MILITARY_DATA",
  "includeSubpages": true,
  "includeControls": true,
  "includeDisplayText": true,
  "includeChoices": true,
  "includeLanguages": ["ZHT", "ENG"],
  "maxDepth": 10
}
```

輸出:節點＋邊的圖結構(節點/邊類型見 mcp-tool-contracts.md §2 詞彙表)。

## 2.3 ps_get_field_choices

輸入:

```json
{
  "componentName": "TW_MILITARY_DATA",
  "pageName": "TW_MILITARY_PG",
  "recordName": "TW_MILITARY",
  "fieldName": "MIL_STATUS",
  "languageCode": "ZHT",
  "includeInactive": false,
  "limit": 100
}
```

輸出:

```json
{
  "field": { "recordName": "TW_MILITARY", "fieldName": "MIL_STATUS", "displayText": "兵役狀態" },
  "choiceType": "TRANSLATE_VALUE",
  "choices": [
    { "storedValue": "E", "displayText": "免役", "languageCode": "ZHT", "status": "ACTIVE" }
  ],
  "dynamic": false,
  "evidence": []
}
```

高基數 Prompt Table:不回傳全部資料,只回 Prompt Metadata
(promptRecord、keyFields、displayFields、searchFields、securityRecord),
值查詢採 on-demand search,遵守資料權限與敏感資料遮罩。

## 4.1 ps_get_object_summary

輸入:`{ "objectType": "...", "objectName": "..." }`
輸出:物件描述、origin、關聯物件摘要(不含長文本內容)。

## 4.2 ps_get_ae_graph

輸入:`{ "aeName": "TW_MIL_AE", "maxDepth": 5 }`
輸出:AE Section → Step → Action(SQL / PeopleCode / Call Section)圖,
Action 節點附 sourceId 供長文本工具取段。

## 4.3 ps_get_data_lineage

輸入:`{ "recordName": "TW_MILITARY", "fieldName": "MIL_STATUS", "direction": "UPSTREAM | DOWNSTREAM | BOTH", "maxDepth": 5 }`
輸出:Table/Field 層級的讀寫關係(節點:RECORD_FIELD / SOURCE;
邊:READ | INSERT | UPDATE | DELETE | MERGE | UNKNOWN | DYNAMIC_RUNTIME,
附 evidence IDs)。

## 4.4 ps_get_process_usage

輸入:`{ "objectType": "SQR | AE", "objectName": "TW_MIL001" }`
輸出:Process Definition、Job、Recurrence、Run Control Record、
觸發來源(頁面/排程),附 origin。

## 4.5 ps_get_security_path

輸入:`{ "componentName": "TW_MILITARY_DATA" }`
輸出:Menu → Component → Permission List → Role(→ User 統計)路徑,
各節點附 origin。

## 4.6 ps_get_navigation_entries（issue #24）

輸入:`{ "componentName": "USERMAINT", "menuName": "MAINTAIN_SECURITY", "market": "GBL",
        "portalName": "EMPLOYEE", "languageCode": "ZHT", "includeAlternateEntries": true }`
輸出:`{ "technicalMenuLocations": [ { "menuName": "...", "barName": "...", "itemName": "..." } ],
        "navigationEntries": [ { "portalName": "...", "entryType": "PORTAL_REGISTRY",
          "crefObjectName": "...", "labels": [ { "displayText": "...", "languageCode": "ZHT",
          "displayTextSource": "LANG|BASE", "fallbackLanguageCode": "ENG" } ],
          "visibility": "REGISTRY_DEFINED", "confidence": "CONFIRMED" } ],
        "gaps": [ "alternate navigation surfaces not fully inspected" ] }`
現況實作＝cookbook §2k（值域見 mcp-tool-contracts.md §3）。
`technicalMenuLocations` 與 `navigationEntries` 是兩個不同 claim,**不得合併或互相 fallback**。
