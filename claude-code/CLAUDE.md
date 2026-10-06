# CLAUDE.md — Claude Code 專案指引（PeopleSoft 知識庫分析框架）

## 這個專案是什麼

- `.claude/`：框架本體——主代理與子代理（`agents/`）、指令（`commands/`）、skills（`skills/ps-*`）、
  執行期 guard（`hooks/ps-runtime-guard.ps1`）、專案設定（`settings.json`）、環境設定與協定（`peoplesoft/`）。
- `scripts/`：確定性外環（lint／auto-loop／auto-all／收據／fs-doctor／知識索引 ps-knowledge／
  補研究 ps-supplemental／Spec 引擎 ps-spec）。外環以 `claude -p --agent <主代理>` 開新鮮 session。
- 研究產出 `docs/ps-research/**`、Spec 產物 `docs/ps-spec/**`、私有需求包 `.ps-private/**`、
  執行狀態 `.ps-runtime/**` 都是公司機密，只留本機／內部 git。

## 主代理怎麼開

| 要做什麼 | 啟動方式 |
|---|---|
| 業務問答 | `claude --agent ps-orchestrator` |
| 產完整業務文件、稽核、教訓、知識指正 | `claude --agent ps-deep-research`，再下 `/ps-research <領域>`、`/ps-audit <領域>`、`/ps-lesson <描述>`、`/ps-correct <正確知識>` |
| 以 Component 產重建 Spec | `/ps-spec <Component...>`（委派 ps-spec-author），或 `claude --agent ps-spec-author` 直接輸入清單 |
| 框架維護、排錯、看 log | `claude`（一般 session：沒有主代理限制） |

`ps-spec-worker`、`ps-clone-worker` 只由外環 headless 啟動；`/ps-audit-batch`、`/ps-supplement`、`/ps-spec-batch`、
`/ps-clone-batch` 只供外環呼叫。

## PeopleSoft 問題的處理方式

要以一個或多個確切 Component 產生「供獨立 LLM 重建核心功能」的規格，走
`/ps-spec <Component...>`（ps-spec-author），或在 ps-spec-author 對話直接輸入清單。
此路徑不走整個領域研究、不要求手填私有 pack；範圍與深度依 `.claude/peoplesoft/spec/clone-contract.md`。
`docs/ps-spec/**` 同為公司機密、禁止外部 remote；REVIEW_READY 不等於企業 E2E 通過。

收到 PeopleSoft 業務問題（例：兵役資料在哪維護、某選項選了會執行什麼）時：

1. 問答走 `ps-orchestrator` 主代理；要**產完整業務文件**用 `/ps-research <領域>`
   （ps-deep-research 主代理，輸出 docs/ps-research/）。
   不在這兩個主代理下時，載入 `ps-business-discovery` skill 依其流程處理，
   重的檢索用 Agent 工具委派給 ps-* **子代理**（`.claude/agents/*.md` 裡的名字）。
   `.claude/skills/*` 是 skill、不是可委派的 agent：授權／血緣／排程類（ps-security-flow／
   ps-data-lineage／ps-process-flow）一律派 `ps-metadata-flow`，要用的 skill 寫進委派的 prompt。
   主代理工作流的**開線步驟（第 0 步）**（查 wiki、委派、作答之前）固定
   `mcp__oracleMCP__connect`（connection_name＝profile `oracle.connectionName` 原樣，不先 list、
   不從清單挑名字；無條件，見 agent 定義），等 connect 回覆成功才派會查 DB 的子代理。
   執行期只有 `.claude/hooks/ps-runtime-guard.ps1` 的無狀態檢查：connect 的 connection_name
   必須等於 profile 值（否則 `ORACLE_CONNECTION_NOT_CONFIGURED`／`ORACLE_CONNECTION_MISMATCH`，
   工具不執行）、Agent 工具的 subagent_type 必須是可委派的 ps-* 子代理（skill 名、主代理名、內建代理都擋：
   `PS_TASK_TARGET_INVALID`）。**沒有派工前置閘門**——順序是你的責任：先派子代理而 DB 未連 → 它回
   `NOT_CONNECTED`，你再 connect 一次、重派一次，只一次、不迴圈。工具清單裡沒有 `mcp__oracleMCP__` 工具＝掛載故障
   → 不猜工具名、不重派、不多 connect，回報 ORACLE_MCP_DOWN，交管理者在該 session 以 `/mcp` 重新連線 oracleMCP（SOP-21）；
   重新連線後重新 connect，不沿用舊結論。
   第 0 步之後，問答一律**先查知識層**——`docs/ps-research/wiki/`（已歸戶的已驗證知識）與
   `docs/ps-research/<領域>/NN-*.md`（已稽核的研究文件），照
   `.claude/peoplesoft/knowledge-retrieval-contract.md`：以 `docs/ps-research/knowledge/index.md`
   定位（Grep 的 path 給該索引檔、`output_mode="content"`）、只讀對應節、標來源等級、答覆附 `## 來源表`；
   知識沒有或等級不足才現場檢索。
2. 搜尋任何 PeopleSoft 物件前，先讀
   `.claude/peoplesoft/customization-profile.yaml` 與 `business-domain-map.yaml`；
   `TW_` 是強客製訊號但非唯一判斷。**未命中已定義領域時，改用
   `searchPolicy.defaultMode` 繼續搜尋——不得以「領域不存在」拒答。**
3. 長文本鐵律（任何 agent 都適用）：
   - `PeoplecodeElasticSearch` 搜到的 chunk ids / snippet 只是候選（SEARCH_CANDIDATE）；
     必須用 `PeoplecodeSource` 以 chunk id 取回完整段落才能作為證據。
   - 不可一次載入整支 PeopleCode / SQL / SQR / SQC。
4. 子代理回報一律依 `.claude/peoplesoft/subagent-report-contract.md`
   （單一 JSON、單段引用 ≤ 5 行、必附 evidence IDs）。

## 一般 session（沒有 `--agent`）

- 用途是框架維護與排錯（看 log、跑腳本、修設定）。PeopleSoft 業務問題仍照上方流程：建議改用 `claude --agent ps-orchestrator`；
  在一般 session 回答時同樣先開線、查知識層、委派 ps-* 子代理，不自己直接檢索原始碼或查 DB。
- 改了框架檔（`.claude/**`、`scripts/**`、`CLAUDE.md`）要告訴使用者改了哪個檔、為什麼，請使用者回報維護端：
  下次搬運包會把 `scripts/**` 換回維護端版本；`.claude/**` 本機改過的檔會保留，但兩邊都改時另存 `.incoming` 待合併。

## 一般規則

- 用繁體中文回覆。
- 查無證據就照實說，不要編造 PeopleSoft 物件名稱或執行期結果。
- 被使用者指正答錯時，主動提議用 `/ps-lesson <描述>` 登錄教訓（在 ps-deep-research 主代理下執行）。
- 業務知識被指正（如資深同事更正業務邏輯）→ 建議
  `/ps-correct <正確知識>` 更新 wiki（本機立即生效；團隊生效走內部 git PR 審核）。
- 不上網（WebFetch／WebSearch 已關）；不把研究產出、Spec、私有需求包貼到任何外部服務。
