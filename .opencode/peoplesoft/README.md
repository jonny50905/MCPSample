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
│  ├─ SOP.md                           管理者人工作業 SOP（教訓 PR 審查/lint/git/回滾…）
│  ├─ customization-profile.yaml       環境規則與 TW_（Prefix、Registry、searchPolicy）
│  ├─ business-domain-map.yaml         兵役等全客製業務領域（alias、rootObjectPolicy）
│  ├─ progressive-source-retrieval.md  PeopleCode/SQL/SQR/SQC 共用檢索規則 + 長文本工具契約
│  ├─ mcp-tool-contracts.md            全部 MCP Tool 契約總覽
│  ├─ oracle-query-cookbook.md         oracleMCP 的 PeopleTools 查詢樣板（SELECT-only）
│  ├─ subagent-report-contract.md      Subagent 回報契約（JSON 格式與硬規則）
│  ├─ report-templates/
│  │  ├─ overview-template.md          Deep research 總覽模板（階段一寫完即凍結）
│  │  ├─ checklist-template.md         調查進度狀態檔模板（唯一反覆改寫的小檔）
│  │  ├─ function-detail-template.md   Deep research 單功能細查模板
│  │  ├─ entity-template.md            Entity wiki 物件檔模板（Observations/Relations）
│  │  └─ audit-template.md             稽核報告（90-audit）模板
│  ├─ lessons/
│  │  ├─ pending.md                    例外案件（agent 無把握判斷落點時才進這裡）
│  │  └─ applied.md                    已套用教訓的逐筆記錄（不進 context）
│  ├─ test-scenarios.md                本地模型準確度測試情境（30 題 + 評分規則）
│  └─ test-fixtures.yaml               測試用假想環境資料（mock MCP 標準答案）
├─ agent/
│  ├─ ps-orchestrator.md               Primary：問答模式（domain 解析 + 委派 + 彙整，唯讀）
│  ├─ ps-deep-research.md              Primary：文件生成模式（盤點 + 逐項深查 + 寫檔，可續跑）
│  ├─ ps-ui-flow.md                    Subagent：UI 語意檢索
│  ├─ ps-peoplecode-flow.md            Subagent：PeopleCode
│  ├─ ps-sql-flow.md                   Subagent：SQL
│  ├─ ps-sqr-flow.md                   Subagent：SQR / SQC
│  ├─ ps-ae-flow.md                    Subagent：Application Engine
│  ├─ ps-metadata-flow.md              Subagent：血緣 / 排程 / 授權（三合一）
│  └─ ps-auditor.md                    Subagent：稽核（證據解引用 / claim 反駁 / 換角度盤點）
├─ command/
│  ├─ ps-research.md                   /ps-research <領域> — 文件生成（可續跑）
│  ├─ ps-audit.md                      /ps-audit <領域> — 稽核 + 回灌 checklist
│  └─ ps-lesson.md                     /ps-lesson <描述> — 登錄教訓並本機立即生效（團隊走 PR）
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
獨立維護，避免單一 SKILL.md 過大（目標模型 Qwen3.6-35B-A3B——
MoE，每 token 活躍參數約 3B，**程序紀律屬小模型等級**）。

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

## Subagent 架構（地端模型）

針對地端模型（Qwen3.6-35B-A3B，262K：MoE active ~3B——程序紀律屬
小模型等級；名目 context 大，但長 context 中段品質與 KV cache 成本
仍受限），提供 OpenCode agent 部署（`.opencode/agent/`，OpenCode 1.x）：

```text
ps-orchestrator（primary，TUI 中 Tab 切換選用）
  主 context 只保留：業務問題、domain/policy 摘要、各 subagent 的 JSON 報告
  ├─ @ps-ui-flow          （只掛 UI 三工具 + origin）
  ├─ @ps-peoplecode-flow  （只掛長文本五工具 + origin）
  ├─ @ps-sql-flow         （同上）
  ├─ @ps-sqr-flow         （同上）
  ├─ @ps-ae-flow          （+ ps_get_ae_graph）
  └─ @ps-metadata-flow    （血緣 / 排程 / 授權三合一）
```

省 context 的三個層次：

1. **Raw source chunks 只存在 subagent context**——回報依
   `subagent-report-contract.md` 只帶結論 + evidence IDs（單段引用 ≤ 5 行）。
2. **每個 subagent 的 tools 白名單只開它需要的 MCP 工具**，tool schema 不疊加。
3. **Skill 全文只在對應 subagent 內載入**，orchestrator 不疊五份 skill 全文。

使用方式與注意事項：

- OpenCode 開在本專案 → Tab 切到 `ps-orchestrator` 問業務問題；
  或在對話中 `@ps-sqr-flow` 手動指派單項檢索。
- 專案根目錄的 `AGENTS.md`（常駐 context）提供路由安全網：
  即使沒切 orchestrator、skill 沒觸發，也會導向正確流程並強制兩條長文本鐵律。
- **現行 MCP 對映（三個）**：`PeoplecodeElasticSearch`（搜 chunk ids，候選）、
  `PeoplecodeSource`（chunk id → 完整上下文，Evidence）、`oracleMCP`
  （PeopleTools metadata：translate values / label / Page 對映 / 排程 / 授權 /
  origin / AE 結構——查詢一律照 `oracle-query-cookbook.md` 樣板，SELECT-only）。
  tools 白名單用 `"<註冊名>_*"` wildcard，前綴必須與 opencode.json 的
  mcp 註冊 key 完全一致（含大小寫）。**注意：OpenCode 的 tools 是覆寫表，
  沒列出的工具預設開啟——不該用某 server 的 agent 必須明確設 `false`，
  不能靠不列**（orchestrator 對三個 MCP 全 deny，主 context 物理上碰不到
  chunk / SQL）。UI 全文語意搜尋（Semantic Index）仍未建，
  相關查詢會以 gaps / BLOCKED 回報。
- Skill / 協定文件內的 `ps_*` 工具名是**協定角色名**；實際工具對映見各 agent
  檔的「工具對映（現行環境）」與 progressive-source-retrieval.md §6.0。
- Subagent 看不到主對話——orchestrator 的委派 prompt 模板會自帶
  domain / searchMode / prefixes，這是規則不是選項。
- 若 orchestrator 的 task 委派在你的版本不可用，改用 @ 提及手動委派，
  流程與委派 prompt 模板相同。
- Trade-off：subagent 每次啟動需重載 system prompt，總 token 較高、延遲較長；
  換取主 context 峰值小、各階段 context 乾淨——對地端模型幾乎必然
  划算（主 context 乾淨的價值不因名目 262K 而消失：中段記憶劣化與
  KV cache 成本仍在）。

## Deep Research 文件生成模式

問答模式（ps-orchestrator，唯讀）之外的第二個入口：對**任一**業務領域
產出人類可讀的 markdown 文件集——領域**不必**先登錄在 domain map
（30 年系統，多數領域沒登錄是常態）。

```text
/ps-research 轉職        ← 或 Tab 切到 ps-deep-research 直接下指令
  ↓ 階段一：多角度盤點 → docs/ps-research/轉職/00-overview.md ＋ checklist.md
    （總覽：功能地圖、批次、核心表、掃描範圍聲明；進度只在 checklist.md）
  ↓ 階段二：逐項深查（復用問答模式的深度鏈）→ NN-<物件>.md、逐項打勾
```

特性：

- **可中斷續跑**：狀態就是 checklist.md——中斷後重跑
  `/ps-research <領域>`，從第一個未勾選項繼續，不重查已完成項。
- **checklist 可人工編輯**：覺得盤點漏了功能，直接在 checklist.md 的
  「調查進度」加一行，系統照著查。
- **領域未登錄照樣跑**：未命中 domain map 時自展同義詞＋CUSTOM_FIRST，
  完成後總覽附「建議 domain 登錄」YAML 片段，人工決定是否收錄對照表。
- **輸出進「內部」git**：`docs/ps-research/` commit 到內部 repo
  （**嚴禁外部 remote**，見 SOP-3）；git diff / blame 提供審閱與溯源。
- **逐項自動快驗**：每檔寫完、打勾前先委派 ps-auditor 驗證據；
  全部打勾後自動接一輪完整稽核＋回灌（單次 run 最多一輪；
  稽核新回灌項由下一次 run 處理，輪次記錄於 checklist.md）。
- **知識歸戶**：每項深查完成即把核心物件寫入 Entity Wiki（見下節）。
- **操作日誌**：每次 run 追加 `log.md` 一行（不依賴 git 的時間軸）。
- **全跑注意**：一次跑到底可能中斷（serving 端 context 上限、當機）
  ——沒關係，斷了就重跑指令續跑；每項完成即寫檔＋打勾，進度不會遺失。

## Entity Wiki 層（知識歸戶與問答飛輪）

領域敘事文件之上的**跨領域物件層**：`docs/ps-research/wiki/`，
一個 PeopleSoft 物件一個檔（**檔名＝物件名**），
格式見 `report-templates/entity-template.md`
（frontmatter：aliases / status / confidence / last_verified / sources /
reviewed；內容：Observations ＋ typed Relations `[[wikilink]]`）。

```text
研究：deep-research 每查完一項 → 物件發現「歸戶」到 wiki
      （先查重 grep 檔名＋aliases → 就地更新，同物件永遠一個檔）
問答：orchestrator 先讀 wiki/index.md → 命中 entity 檔直接引用
      （verified 免重查）→ wiki 沒有才委派現查 → 回答標註來源
修正：答錯的事實修在 entity 檔（作廢不刪除）→ 之後每次問答都對
CR：系統改版上線 → 重建 ES 索引 → audit 找出失效證據 → research 更新（SOP-11）
```

設計依據（2026-07 研究結論）：編譯過的互連 wiki 對多跳檢索勝過
flat RAG 約 6~8 F1；確定性 index-first 檢索是地端模型的可靠路徑；
`[[wikilink]]` 是純文字，backlink 用 grep 即可重建——**不需要任何工具**。
Obsidian 桌面版可直接開 `docs/ps-research/` 當 vault 閱讀（選配，
見 SOP-7；`.obsidian/` 要 gitignore）。

## 稽核與教訓迴路

**稽核**（`/ps-audit <領域>`）——不信模型說了什麼，驗它引用了什麼：

1. **證據解引用**：每筆 CHUNK 證據以 ChunkId 重查、quote 做子字串比對；
   SQL 證據重跑比對 keyRows；非 UUID 的 id 直接判捏造。
2. **反駁抽驗**：每檔抽 3~5 條重要 claim，由乾淨 context 的 ps-auditor
   以「反駁為目標」重新取證判定 VERIFIED / DISPUTED / UNVERIFIABLE。
3. **換角度完整性**：從核心資料表反推物件清單，與功能地圖 diff 抓遺漏。
4. 產 `90-audit.md` 記分卡；**問題回灌 checklist**（標「（稽核）」），
   下次 `/ps-research` 續跑自動補查——研究→稽核→補查閉環。
5. 格式層另有確定性 lint：`.\scripts\ps-doc-lint.ps1 -Domain <領域>`
   （checklist 對帳、必要章節、confidence 標註、UUID 格式）。

**教訓迴路**（跨 session 記取教訓）——模型不會學習，教訓必須外部化：

```text
被指正 / 稽核發現系統性錯誤
  → /ps-lesson <描述>   登錄＋分類＋**本機立即套用**
                        （事實類修文件·作廢不刪除；規則類最小新增·只加不刪）
  → 記錄 applied.md ＋ 對應測試檢查點（防回歸）
  → commit / push → 內部 git PR ── 人工審 diff 把關（SOP-1）
  → merge 後全員 pull ＋ 重啟 → 教訓擴散到所有機器
```

原則：**本機即時生效、團隊生效必經 PR 人審**——AI 的規則修改永遠有人
守在合併關卡；套用限「最小新增」（只加不刪，改壞可 revert）。
能機械化的教訓優先機械化（lint / 稽核判定 / tools deny），
prose 規則是最後手段。

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
