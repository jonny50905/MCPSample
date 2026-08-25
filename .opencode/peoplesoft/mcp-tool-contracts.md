# PeopleSoft MCP Tool Contracts（工具契約總覽）

`ps_*` 名稱一律是**協定角色**，不是可呼叫的工具。呼叫前對照下表與
「角色 ↔ 現況」——**呼叫任何「尚未實作」的角色名必得 unavailable tool**。

## 現有工具（唯一可呼叫的清單）

| Server | 工具 | 用途 |
|---|---|---|
| `PeoplecodeElasticSearch` | `search_chunks` | 搜候選（定位用；回傳是候選不是證據） |
| `PeoplecodeElasticSearch` | `get_chunk_by_id` | 依 id 取回——僅供稽核交叉檢查，非解引用路徑 |
| `PeoplecodeSource` | `get_chunks_details` | **解引用（唯一的正式證據來源）** |
| `PeoplecodeSource` | `get_file_structure` | 檔案結構（先看目錄再定向取段） |
| `oracleMCP` | （SQLcl 唯讀查詢） | PeopleTools metadata——**一律照 `oracle-query-cookbook.md` 樣板** |
| `PeoplecodeMetadata` | find_field_usage 等 | 只作定位線索，**不得作 evidence** |

工具身分＝server 前綴＋工具名，兩個都對才叫對；`unavailable tool`
（名字錯／掛錯 server／本 agent deny）不是暫時故障，重試必然再失敗。
解引用與 componentType 規則見 `progressive-source-retrieval.md` §6.0／§5.1。

## 角色 ↔ 現況

| 協定角色 | 現況實作 |
|---|---|
| ps_get_customization_profile | 直接 read `customization-profile.yaml`＋`business-domain-map.yaml` |
| ps_get_object_origin | Prefix 比對 profile＋cookbook §1（PSPROJECTITEM／LASTUPDOPRID） |
| ps_search_business_domains | read `business-domain-map.yaml` 的 aliases |
| ps_search_ui_semantics | cookbook §2（XLAT／Label 反查） |
| ps_get_ui_graph | cookbook §2d／2e 逐段拼；條件 UI（Group Box／Subpage／受影響控制項）§2h～2j |
| ps_get_field_choices | cookbook §2a／2f／2g |
| ps_search_source／ps_get_source_chunks | ES `search_chunks`／Source `get_chunks_details`（契約見 progressive-source-retrieval.md §6） |
| ps_get_source_outline | Source `get_file_structure` |
| ps_expand_source_context／ps_find_source_references | 尚未實作——符號名搜 ES → Source 取段，補不到記 gaps |
| ps_get_object_summary | cookbook §1／§6 |
| ps_get_ae_graph | cookbook §5（內容另走 ES＋Source） |
| ps_get_data_lineage | ES table 名搜尋＋cookbook §6 反查交叉 |
| ps_get_process_usage | cookbook §3 |
| ps_get_security_path | cookbook §4 |

未來實作這些角色的完整 I/O 規格：`docs/mcp-tool-proposals.md`（agent 不讀）。

## 2. UI 分類詞彙表（報告與分析用）

`choiceType`：

```text
TRANSLATE_VALUE
PROMPT_TABLE
RADIO_BUTTON
DROP_DOWN
LIST_BOX
CHECKBOX
YES_NO
PAGE_STATIC_CHOICE
DYNAMIC_PROMPT
DYNAMIC_PEOPLECODE
UNKNOWN
```

UI 圖節點：

```text
COMPONENT
PAGE
SUBPAGE
CONTROL
DISPLAY_TEXT
RECORD_FIELD
CHOICE_SET
CHOICE_VALUE
PEOPLECODE_EVENT
```

UI 圖邊：

```text
CONTAINS_PAGE
CONTAINS_CONTROL
DISPLAYS_TEXT
BINDS_TO_FIELD
USES_CHOICE_SET
CONTAINS_CHOICE
TRIGGERS_EVENT
```

`origin` 值域見 `customization-profile.yaml` 的 `objectOrigins`。
高基數 Prompt Table：不回傳全部資料——先 COUNT，只回 Prompt Metadata
與彙總，遵守遮罩原則（cookbook 使用規則 3／4）。
