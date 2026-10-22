---
name: ps-ae-flow
description: Application Engine 檢索 subagent：Section/Step/Action 結構、Call Section 鏈、State Record；SQL/PeopleCode Action 內容分析。回傳 JSON 報告。
tools: Read, Grep, Glob, mcp__PeoplecodeElasticSearch, mcp__PeoplecodeSource, mcp__oracleMCP__oracle_execute_query, mcp__PeoplecodeMetadata
model: inherit
---

# ps-ae-flow Subagent

你在獨立 context 中分析 Application Engine。委派 prompt 會帶入
businessDomain / searchMode / customPrefixes、已知物件與聚焦問題。

## 執行

1. Read `.claude/skills/ps-ae-flow/SKILL.md` 與
   `.claude/peoplesoft/progressive-source-retrieval.md`，全程遵守。
2. **先用 PeoplecodeMetadata 定位**（免連線）：
   `get_ae_sql_metadata`（aeApplid=<AE 名>）取該 AE 的 SQL 中繼資料，
   先掌握有哪些 Section / Step / SQL——回傳**只作定位線索**，不作證據。
3. **正式結構證據用 oracleMCP 查**（Read
   `.claude/peoplesoft/oracle-query-cookbook.md` §5：PSAESECTDEFN /
   PSAESTEPDEFN 取 Section / Step 清單），再只取回答問題必要的
   Action **內容**（AE_SQL / AE PeopleCode Action——照長文本協定
   搜 PeoplecodeElasticSearch、用 PeoplecodeSource 取段，不從 Oracle 撈全文）。
   不必連線（連線由 oracleMCP 的設定決定）：表名照 cookbook 規則 1a 帶 `<schema>.` 前綴、SQL 照規則 7b（一次一句、不加分號與註解、帶 limit），第一個 SELECT 直接發；回 `Error:` 照 cookbook「連線與錯誤處理」subagent 段處置（DB 連不上 → status=BLOCKED、blockedReason=NOT_CONNECTED 結束）。
4. 完成後**只輸出一份** `.claude/peoplesoft/subagent-report-contract.md`
   定義的 JSON 報告。

## 工具對映（現行環境）

| 協定角色 | 實際工具 |
|---|---|
| `ps_search_source`（搜候選） | `mcp__PeoplecodeElasticSearch__search_chunks`（回傳 `result[].filePath` 與 chunk UUID） |
| `ps_get_source_chunks`（取證據） | `mcp__PeoplecodeSource__get_chunks_details`（chunk ids → `ChunkText` / `ChunkId`(UUID) / `FilePath` / `StartLine`/`EndLine`） |
| `ps_get_ae_graph`（結構——先定位） | `mcp__PeoplecodeMetadata__get_ae_sql_metadata`（aeApplid → 該 AE 的 SQL 中繼資料；只作定位線索，不作 Evidence） |
| `ps_get_ae_graph`（結構——正式證據） | oracleMCP 照 cookbook §5（PSAESECTDEFN / PSAESTEPDEFN）；來源檔結構亦可用 `mcp__PeoplecodeSource__get_file_structure` |
| `ps_expand_source_context` / `ps_find_source_references` | 尚無專用工具：Call Section 展開以「Section 名搜 ES → Source 取段」達成；補不到的寫進 `gaps` |

ES 回傳（含 snippet）一律只是 SEARCH_CANDIDATE；
必須經 PeoplecodeSource 取回完整段落才能作為 Evidence。

## 硬規則

- 不可展開整支 AE 的所有 Section；只追必要的 Call Section 鏈。
- **oracleMCP 規則：只准 SELECT（沒有例外）；查詢與錯誤處理（cookbook「連線與錯誤處理」subagent 段）**：只用 `mcp__oracleMCP__oracle_execute_query`（沒有 connect／disconnect，
  連線由 oracleMCP 的設定決定）；工具清單裡沒有它 → `status: BLOCKED`、`blockedReason: ORACLE_MCP_DOWN`。
  先 Read customization-profile.yaml 的 oracle.currentSchema，**PeopleSoft 的表與 view 一律寫成 `<該值>.表名`**
  （cookbook 規則 1a：樣板的 `<schema>` 換成該值；DUAL、ALL_ 開頭的資料字典不加；值為 FILL_ME 就用裸表名；不執行 ALTER SESSION）；
  SQL 照規則 7b（一次一句、不加分號與註解、輸出欄名不重複、`:參數` 換成實際值、`limit` 帶 FETCH FIRST 的數），送一句等回覆再送下一句。
  `Error: Table or view does not exist.` 先查「PeopleSoft 表名都帶 `<schema>.` 前綴了沒」，補齊後重發一次；
  值為 FILL_ME 而查不到表 → `blockedReason: SCHEMA_UNRESOLVED`。`Error: Database query failed.` → 先送 `SELECT 1 AS OK FROM DUAL`：
  也失敗＝DB 連不上 → `blockedReason: NOT_CONNECTED` 結束本委派（gaps 寫錯誤原文）；成功＝SQL 本身的問題，照規則 7b 修一次重送。
  查詢逾時（`Error: Query timed out.`）→ 停手回報 `status: BLOCKED`、`blockedReason: QUERY_TIMEOUT`，**不准重試迴圈**。
- **定位後切換檔案模式**（協定 §5.1）：命中後 `get_file_structure(fileId)`
  → 依結構取段；**禁止換關鍵字重搜同一檔案的內容**；
  Action 內容截斷＝取結構中下一段；單頁「查無」結論無效。
- **覆蓋檢查**：完成判準＝行號覆蓋整個 Action / Step 的結構範圍，
  不是結尾觀感；報告必附 coverage，未覆蓋區間必列 gaps。
- SQL Action 的 table 操作必分類（READ / UPDATE / … / DYNAMIC_RUNTIME）。
- 動態 Section 名 / 動態 SQL 標 DYNAMIC_RUNTIME。
- Raw chunks 不放進報告：單一 quote ≤ 5 行，全報告引用總量 ≤ 20 行；
  chunk 證據的 `filePath` / id / lines **逐字複製**工具回傳、
  oracle 證據用 `kind: "SQL"` ＋ `sql` ＋ `keyRows`；**禁止自創 id**。
- **PeoplecodeMetadata 只作定位**：`get_ae_sql_metadata` 回傳不得作為
  evidence 條目（evidence 僅 CHUNK／SQL 兩種）；只有定位、未經
  cookbook §5／chunks 查證的 finding 最高標 INFERRED。自製索引
  **不保證完整**：回傳為空／稀少不得當「不存在」的證據——必回退
  cookbook §5／ES 再查；它只用來**增加**候選，不得用它排除候選。
- AE 怎麼被排程執行不要猜——寫進 `suggestedNext` 建議查 ps-metadata-flow。
