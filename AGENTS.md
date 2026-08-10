# AGENTS.md — OpenCode 專案指引

## 這個 repo 是什麼

- `src/`：HanshinChat MCP + OData 範例（.NET 8），詳見根目錄 README.md。
- `.opencode/`：PeopleSoft 分析框架——skills（ps-*）、subagent 定義（agent/）、
  環境設定與協定（peoplesoft/）。架構總覽：`.opencode/peoplesoft/README.md`。

## PeopleSoft 問題的處理方式

收到 PeopleSoft 業務問題（例：兵役資料在哪維護、某選項選了會執行什麼）時：

1. 問答走 `ps-orchestrator` agent（Tab 切換）；要**產完整業務文件**用
   `/ps-research <領域>`（ps-deep-research，輸出 docs/ps-research/）。
   在一般 agent 下則載入 `ps-business-discovery` skill 依其流程處理，
   重的檢索用 @ 委派給 ps-* subagent。
   問答一律**先查 `docs/ps-research/wiki/`**（已歸戶的已驗證知識），
   wiki 沒有或未驗證才現場檢索。
2. 搜尋任何 PeopleSoft 物件前，先讀
   `.opencode/peoplesoft/customization-profile.yaml` 與 `business-domain-map.yaml`；
   `TW_` 是強客製訊號但非唯一判斷。**未命中已定義領域時，改用
   `searchPolicy.defaultMode` 繼續搜尋——不得以「領域不存在」拒答。**
3. 長文本鐵律（任何 agent 都適用）：
   - `PeoplecodeElasticSearch` 搜到的 chunk ids / snippet 只是候選（SEARCH_CANDIDATE）；
     必須用 `PeoplecodeSource` 以 chunk id 取回完整段落才能作為證據。
   - 不可一次載入整支 PeopleCode / SQL / SQR / SQC。
4. Subagent 回報一律依 `.opencode/peoplesoft/subagent-report-contract.md`
   （單一 JSON、單段引用 ≤ 5 行、必附 evidence IDs）。

## 一般規則

- 用繁體中文回覆。
- 查無證據就照實說，不要編造 PeopleSoft 物件名稱或執行期結果。
- 被使用者指正答錯時，主動提議用 `/ps-lesson <描述>` 登錄教訓
- 業務知識被指正（如資深同事更正業務邏輯）→ 建議
  `/ps-correct <正確知識>` 更新 wiki（本機立即生效；團隊走內部 git PR）
  （本機立即生效；團隊生效走內部 git PR 審核）。
