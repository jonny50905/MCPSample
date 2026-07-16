# PeopleSoft Skills：客製化優先、UI 業務語意與長文本檢索

依《PeopleSoft Skill Plan Addendum：客製化優先、UI 業務語意與長文本檢索》實作
（原始需求見 `docs/superpowers/specs/2026-07-16-peoplesoft-skill-custom-ui-source-addendum.md`）。

## 三個核心概念

1. **Customization Profile** — 環境客製規則獨立成設定檔，`TW_` 是強訊號但非唯一判斷。
2. **UI Semantic Index** — Page 最終顯示文字與選項文字是第一級業務語意，優先於技術物件名稱。
3. **Unified Progressive Source Retrieval** — PeopleCode / SQL / SQR / SQC 共用
   「搜尋候選 → 精確取段 → 定向展開 → 停止」協定；Search Index 只定位，DB Chunk 才是 Evidence。

## 目錄結構

```text
.opencode/
├─ peoplesoft/
│  ├─ README.md                        本檔
│  ├─ customization-profile.yaml       環境規則與 TW_（Prefix、Registry、searchPolicy）
│  ├─ business-domain-map.yaml         兵役等全客製業務領域（alias、rootObjectPolicy）
│  ├─ progressive-source-retrieval.md  PeopleCode/SQL/SQR/SQC 共用檢索規則 + 長文本工具契約
│  ├─ mcp-tool-contracts.md            全部 MCP Tool 契約總覽
│  ├─ test-scenarios.md                本地模型準確度測試情境（24 題 + 評分規則）
│  └─ test-fixtures.yaml               測試用假想環境資料（mock MCP 標準答案）
└─ skills/
   ├─ ps-business-discovery/SKILL.md   業務問題 → 根物件（入口）
   ├─ ps-ui-flow/SKILL.md              UI 結構 + 語意（顯示文字、選項）
   ├─ ps-peoplecode-flow/SKILL.md      PeopleCode 邏輯
   ├─ ps-sql-flow/SKILL.md             SQL 分析
   ├─ ps-sqr-flow/SKILL.md             SQR / SQC 分析
   ├─ ps-ae-flow/SKILL.md              Application Engine
   ├─ ps-data-lineage/SKILL.md         資料血緣
   ├─ ps-process-flow/SKILL.md         Process Scheduler
   ├─ ps-security-flow/SKILL.md        安全性
   ├─ ps-business-explain/SKILL.md     業務說明產出（終點）
   └─ ps-impact-analysis/SKILL.md      變更影響分析（選配）
```

各 Skill 只描述該分析領域的決策與輸出；環境規則、共用檢索協定、工具契約
獨立維護，避免單一 SKILL.md 過大（目標模型 Qwen 3.5 9B）。

## 整合流程

```text
使用者業務問題
  ↓ ps-business-discovery：載入 Profile → 解析 Domain → 決定
    CUSTOM_ONLY_ROOTS / CUSTOM_FIRST / MIXED / DELIVERED_ALLOWED
  ↓ ps-ui-flow：搜尋 UI 顯示文字 / 選項文字 → 映射 Component / Page / Record.Field
  ↓ ps-peoplecode-flow / ps-sql-flow / ps-sqr-flow / ps-ae-flow：
    搜尋客製 Chunk → 取精確 DB Chunk（共用 progressive-source-retrieval）
  ↓ ps-data-lineage / ps-process-flow / ps-security-flow：
    追蹤資料、執行、安全，必要時加入 Delivered Dependency
  ↓ ps-business-explain：產出業務說明
```

## 兵役案例（端到端）

使用者：「免役這個選項在哪裡維護？選了以後會執行什麼？」

```text
1. ps-business-discovery   命中 military_service，Search Mode = CUSTOM_ONLY_ROOTS
2. ps_search_ui_semantics  命中 Choice Label「免役」→ TW_MILITARY_DATA /
                           TW_MILITARY_PG / TW_MILITARY.MIL_STATUS，Stored Value = E
3. ps-ui-flow              取 Component、Page、Control、Field 與
                           FieldChange / SavePreChange / SavePostChange Event
4. ps-peoplecode-flow      搜 TW_ 客製 PeopleCode → 取精確 Chunk → 分析選 E 後的分支
5. ps-sql-flow             分析相關 SQL Definition 或動態 SQL
6. ps-sqr-flow             若後續 Process 執行 TW_ SQR，追蹤必要 Procedure
7. ps-data-lineage         整理讀取、更新資料
8. ps-business-explain     產出業務說明
```

最終結論必須區分：畫面文字（免役）/ 儲存值（E）/ 業務根物件（TW_MILITARY_DATA，
CUSTOM_PREFIX）/ PeopleCode 分支與 SQL 更新的 CONFIRMED / INFERRED / DYNAMIC_RUNTIME /
原生物件僅列 Dependency。

## 最重要的 Skill 防呆（全 Skill 適用）

```text
Do not assume a delivered PeopleSoft object implements the customer's business
process when the customization profile marks the domain as custom-only.

Do not treat TW_ as the only way to identify customization.

Do not ignore page display text.
User-visible labels are primary business search signals.

Do not ignore option labels.
Choice display text and stored values are part of the business logic.

Do not use Elastic Search snippets as final evidence.

Do not retrieve complete PeopleCode, SQL, SQR, or SQC source by default.

Do not return all prompt values from a high-cardinality table.

Do not call a delivered object the root business implementation when it is only
a dependency of a TW_ custom object.
```

## Definition of Done 對照

### Customization

- [x] 支援 `TW_` Prefix → `customization-profile.yaml` `customPrefixes`
- [x] Prefix 來自環境設定，不是散落在 Prompt → 各 Skill 一律先載入 profile
- [x] 支援 Custom Object Registry → `customObjectRegistry` + `ps_get_object_origin`
- [x] 支援 Modified Delivered Object → origin `MODIFIED_DELIVERED`
- [x] 支援 Business Domain Alias → `business-domain-map.yaml`
- [x] 支援 CUSTOM_ONLY_ROOTS / CUSTOM_FIRST → domain `rootObjectPolicy` + discovery 規則
- [x] 報告 Delivered Fallback 是否發生 → discovery 輸出 `deliveredFallbackUsed`

### UI Semantic

- [x] 索引 Page 最終靜態顯示文字 / Grid Column / Tab / Group Box / Button / Static Text
      → ps-ui-flow「應索引的 UI 文字」
- [x] 保留語系 → `languageCode` / `fallbackLanguageCode`
- [x] 可由顯示文字反查 Component / Page / Record.Field → `ps_search_ui_semantics`
- [x] 動態 Label 標記 DYNAMIC_RUNTIME → ps-ui-flow 規則

### Choice

- [x] Translate Value / Prompt Table / Radio / Drop-down / Checkbox → `ps_get_field_choices`
- [x] 低基數索引、高基數 on-demand → ps-ui-flow「選項」節
- [x] 動態 Choice 標記 DYNAMIC_RUNTIME
- [x] 可由「免役」反查儲存值與 Field → `ps_search_ui_semantics`（CHOICE_LABEL）

### Long Text

- [x] PeopleCode / SQL / SQR / SQC 採 Progressive Retrieval → 四個 flow Skill 皆引用共用協定
- [x] Search Index 只作 Candidate；Database Chunk 作正式 Evidence
- [x] 支援 Outline → `ps_get_source_outline`
- [x] 支援 Neighbor / Symbol Expansion → `ps_expand_source_context`
- [x] 支援防重 / Context Budget → progressive-source-retrieval.md §5
- [x] 支援 DYNAMIC_RUNTIME → 全協定與各 Skill 規則

> 註：以上為 Skill / 設定層的完成定義。`mcp-tool-contracts.md` 中標 *(proposed)*
> 的工具（如 `ps_search_ui_semantics`、`ps_get_field_choices` 的伺服器端實作與
> UI Semantic Index 的建置）屬 MCP Server / Indexer 端工作，不在本次範圍。
