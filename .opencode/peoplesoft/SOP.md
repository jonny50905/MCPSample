# 管理者 SOP（人工作業標準程序）

適用對象：系統管理者（維護規則檔、把關教訓、管理內部 git 的人）。
一般使用者只需要 OpenCode 對話（問答、`/ps-research`、`/ps-audit`、`/ps-lesson`），
不需要本文件。

---

## SOP-1 教訓 PR 審查——最重要的一份

**流程**：同事 `/ps-lesson` → **該機立即生效**（agent 直接修落點檔＋記錄
applied.md）→ 同事 commit ＋ push → 內部 git 開 **PR** → 你審 diff →
merge（全隊採納）或退回。把關點在合併，不在事前。

```text
【審 PR 時看五件事（看 diff 即可，單筆 2~5 分鐘）】
□ 1. 落點優先序對嗎？機械化檢查 > 資料修正 > 窄規則 > AGENTS.md
     （能用 lint / 格式判定 / tools deny 解決的，不該寫成 prose 規則）
□ 2. 是「最小新增」嗎？——只加不刪；有任何既有規則被改寫/移除 → 退回
□ 3. 措辭會不會太寬、誤傷正常行為？
□ 4. 測試檢查點有跟著加進 test-scenarios.md 嗎？
□ 5. 沒把握 → 把 diff 遮敏後貼給較強模型審（物件名可代稱；機密不出機器）

【merge 後】
□ 通知全員 pull ＋ 重啟 OpenCode（教訓才會到每台機器）

【退回時】
□ PR reject ＋ 註明理由
□ 通知該同事在本機 revert 該 commit（他的機器退回原狀）
□ 若教訓本身有價值只是落點/措辭不對 → 修改後重新提交
```

**節奏**：教訓 PR 隨到隨審或每日批次；會導致嚴重錯誤決策的緊急教訓即時處理。
**例外案件**：`pending.md` 裡狀態 PENDING 的（agent 沒把握自動套用的）——
人工判斷落點後自行修改、記錄 applied.md、照常走 PR。

---

## SOP-2 Lint 執行

**時機**：每個領域 `/ps-research` 跑完後；`/ps-audit` 前；懷疑格式壞掉時。

```text
□ 1. PowerShell 貼「一行」執行（絕對路徑，任何目錄皆可、不用 cd）：
     powershell -ExecutionPolicy Bypass -File "<repo路徑>\scripts\ps-doc-lint.ps1" -Domain "<領域>"
□ 1a. 上行被 GPO 擋（PSSecurityException 仍出現）→ 記憶體免疫跑法
      （執行原則只管 .ps1 檔案、不管記憶體），同樣一行：
     & ([scriptblock]::Create((Get-Content "<repo路徑>\scripts\ps-doc-lint.ps1" -Raw -Encoding UTF8))) -Domain "<領域>"
     （指令全部適用舊版 Windows PowerShell 5.1／powershell.exe；
       script 已帶 UTF-8 BOM，5.1 可正確解析中文）
□ 1b. 嫌每次打路徑麻煩：可「自行在本機」建 lint.cmd 捷徑
      （內容一行＝上面 1. 的指令、%* 接參數）——但**嚴禁 commit 進
      repo**（公司安控會擋含可執行檔的 git 下載，見 SOP-3）
□ 2. 綠色 PASS → 結束
□ 3. 紅色 FAIL → 逐項處理：
     - 「checklist 已打勾但檔案不存在」「檔案未列於清單」
       → 對話叫 deep-research 修（或人工補 checklist 行）
     - 「ChunkId 非 UUID / 自編 id」→ 證據捏造，跑 /ps-audit 該領域
     - 「缺章節 / 無 confidence 標註」→ 對話叫 deep-research 重寫該檔該節
     - wiki 類警告（斷鏈 / 孤兒 / 過期 / frontmatter 缺欄）
       → 斷鏈孤兒叫 deep-research 修；stale 排入下次 /ps-research
□ 4. 修完重跑 lint 確認
```

---

## SOP-3 內部 Git

**原則**：產出（docs/ps-research/）與框架（.opencode/）都 commit 到**內部** git；
**嚴禁推到任何外部 remote**。
**repo 禁放可執行檔**（.cmd／.bat／.exe／.vbs 等——公司安控會擋含
可執行檔的 git 下載，2026-07 實測）；自動化一律 .ps1＋SOP 教跑法，
捷徑檔只准使用者自建於本機、不入版控。

```text
□ 何時 commit：
  - 一個領域研究完成或告一段落後
  - /ps-audit 跑完後（含 90-audit.md 與回灌）
  - 教訓套用後（SOP-1 第 9 步）
  - 人工修正文件後
□ Commit message 前綴（讓 git log 可過濾）：
  - kb(research): <領域> 新增/更新研究
  - kb(audit):    <領域> 稽核與回灌
  - kb(fix):      人工修正 <檔案>（含 reviewed 標記）
  - kb(rule):     教訓套用 <L編號>
□ 推送前檢查：git remote -v 確認只有內部 remote
□ 回答「這條事實哪次加的」：git log --follow / git blame <entity檔>
```

---

## SOP-4 回滾（文件被 agent 弄壞時；含「部分還原」）

**部分損壞**（如 lint 報缺章節——覆寫時被寫掉）不必整檔回滾：
`git log --oneline -- <檔路徑>` 找舊版 → `git show <commit>:<檔路徑>`
確認舊版章節完整 → 人工把缺的章節貼回（或貼給 deep-research 合併，
註明「僅補回缺章節，其他內容不動」）。git 裡也沒有 → 該項回
checklist 重查。

```text
□ 1. 先確認災情範圍：git status / git diff（未 commit 的變更）
□ 2. 未 commit 的壞變更 → git checkout -- docs/ps-research/<壞掉的路徑>
□ 3. 已 commit 的壞變更 → git log 找壞 commit → git revert <sha>
     （用 revert 不用 reset——保留歷史）
□ 4. 回滾後把肇因登錄教訓：/ps-lesson <一句話描述 agent 做了什麼壞事>
```

---

## SOP-5 人工修正文件與 reviewed 標記

**時機**：你（或領域專家）確認某份文件 / entity 檔內容有誤，要人工修正。

```text
□ 1. 修正內容時遵守「作廢不刪除」：
     - entity 檔：舊事實移到「## Invalidated」節標日期原因，新事實寫回 Observations
     - 領域文件：錯誤敘述改正，必要時在該段留一行「（更正：原載…，經確認為…）」
□ 2. 該檔 frontmatter 改 reviewed: true
     → 從此 agent 不得覆寫此檔既有內容（只能追加），重生成也會跳過
□ 3. 若這個錯反映系統性問題 → 順手 /ps-lesson 登錄
□ 4. git commit（前綴 kb(fix):）
```

---

## SOP-6 Checklist 人工加項

盤點漏了功能時，兩種方式擇一：

```text
方式 A（推薦）：對話裡講——「把 TW_XXX 加進 <領域> 的調查清單」
方式 B（手改）：編輯該領域目錄 checklist.md 的「調查進度」，照格式加一行：
              - [ ] NN <功能名> `<物件名>` → NN-<物件名>.md
              （舊領域還沒有 checklist.md 時不用手動搬——
              下次 /ps-research 會自動遷移）
之後跑 /ps-research <領域> 就會查它。
```

---

## SOP-7 Obsidian（選配的人類閱讀介面）

不裝完全不影響任何功能。要裝：

```text
□ 1. Obsidian → Open folder as vault → 選 docs/ps-research/
□ 2. 立刻把 .obsidian/ 加進內部 git 的 .gitignore
     （至少 ignore .obsidian/workspace.json——它每次開檔都變）
□ 3. 注意：不要用 Obsidian 的 Properties 圖形介面改 frontmatter
     ——它會重排/改寫 YAML 格式，跟 agent 寫入互相打架產生幻影 diff。
     要改 frontmatter 用純文字模式或編輯器改。
□ 4. 好處：wikilink 點擊跳轉、backlink 面板、graph view、
     全域搜尋 `- [ ]` 看所有未完成調查
```

---

## SOP-8 環境異動時的對齊檢查

```text
□ 新增 MCP server 註冊 → 先在**全部 9 個 agent 檔**的 tools 加
  "<註冊名>_*": false（tools map 是覆寫表：沒列＝預設全開，主 agent 會
  直接呼叫繞過 subagent 架構；其回傳也塞不進證據契約，誘發捏造）。
  之後要用再走正式整合：選定歸屬 subagent → 該檔改 allow ＋補工具
  對照表＋定義證據格式，其餘 agent 檔維持 deny
□ MCP server 註冊名變了 → 改 agent 檔 tools 的 "<註冊名>_*" 前綴
  （含 deny 項），前綴大小寫須完全一致
□ 換模型 → 重跑 Smoke Set（test-scenarios.md §5，9 題）確認規則遵循沒退化
□ OpenCode 升版 → 確認 agent（Tab 清單）、command（/ 清單）、
  skill 都有載入；異常先看 frontmatter 格式
□ PeopleTools 升版 → cookbook 的表名/欄位抽 2~3 條樣板實跑驗證
```

---

## SOP-9 write 工具 JSON 解析失敗排查

畫面出現 `invalid[tool=write, error=... JSON Parse error expected '}']`：

```text
□ 這不是檔案被汙染——是模型產生的「工具呼叫 JSON」本身壞掉；
  最常見原因＝單次寫入內容太長被截斷（大檔整檔覆寫）
□ 規則側已緩解：進度拆到小檔 checklist.md、00-overview 凍結、
  單次寫檔約 150 行上限、同檔失敗 2 次標 ⚠ 跳過（不會卡死）
□ 服務端可做（管理者）：推理伺服器若支援 tool-call 約束解碼
  （vLLM auto tool choice／grammar、Ollama JSON mode 等）→ 打開，
  可大幅降低 JSON 壞格率（**本環境 2026-07 探針已確認輸出上限充足
  ——數到 3000 能完成——故約束解碼是唯一高價值槓桿**）
□ 個案收尾：從 checklist.md 找標 ⚠（寫入失敗）的項，重跑 /ps-research
  讓它補做；反覆失敗的同一檔改用 SOP-5 人工建檔
□ invalid[tool=task] 同根因——委派 prompt 過長（常見：把整份檔案
  貼進委派）；規則側已改「驗檔委派只傳路徑」＋ prompt 約 30 行上限
□ 紅字「閃現後自癒」＝正常：錯誤會回饋給模型、它重試成功就繼續
  ——不需處理。要介入的只有：同一呼叫紅字堆疊不前進（人工標
  BLOCKED 續下一項）、紅字後整個停住（回「做」推一下）、
  幾乎每呼叫都紅（找管理者開約束解碼）
```

---

## SOP-10 Serving 端上限與約束解碼檢查（L6 兩疑點）

先認 stack：開 opencode.json 看 provider baseURL 埠號——
11434＝Ollama／1234＝LM Studio／8000 常見為 vLLM。

```text
□ 1. OpenCode 端宣告：opencode.json 該 model 的 limit（context／output）
     ——TUI 的 context % 按這個算；設太小會提早壓縮、看起來「用滿」
□ 2. Serving 端真實 context：
     - Ollama：ollama show <model>（含 --parameters）；伺服器日誌 n_ctx；
       注意 Ollama 超長輸入「靜默截斷」不報錯（日誌 truncating input prompt）
     - vLLM：curl http://host:8000/v1/models 看 max_model_len；
       或啟動參數 --max-model-len
     - LM Studio：載入模型頁 context length 欄位
     - llama.cpp server：/props 端點 n_ctx；啟動參數 --ctx-size
□ 3. 萬用探針（會報錯的 stack）：PowerShell 丟超長輸入，錯誤訊息
     會寫出真實上限（maximum context length is XXXX）：
       $b=@{model="<名>";messages=@(@{role="user";content=("測 "*200000)})}|ConvertTo-Json -Depth 5
       Invoke-RestMethod -Uri "http://<host>:<port>/v1/chat/completions" -Method Post -ContentType "application/json" -Body $b
□ 4. 輸出上限探針：對話叫它「從 1 數到 3000，每行一個數字」，
     斷點 ≈ 輸出 token 上限；並查 opencode.json 的 maxTokens／limit.output
□ 5. 約束解碼（治 tool-call JSON 壞格）：
     - vLLM：--enable-auto-tool-choice ＋ Qwen 系 tool-call parser
       ＋ guided decoding（xgrammar／outlines）
     - Ollama：升級新版（原生約束 tool-call JSON／structured outputs）
     - llama.cpp：grammar（GBNF）／新版 --jinja 工具支援
□ 6. 建議值：context 不必盲開 262K（KV cache／prefill 代價大）——
     subagent 隔離下 32K～64K 通常足夠；輸出上限建議 ≥ 8K
□ 7. 查到的數字回報對話，據以調整規則（如寫檔行數上限）
```

---

## SOP-11 系統 CR 上線後的知識庫對齊

前提觀念：ES 索引是程式碼**快照**——索引沒更新，稽核驗的是舊
code，全部白驗。oracleMCP 查線上 DB，CR 後立即反映、不需此步；
所以 chunk 證據與 SQL 證據的時效是**不同步**的。

```text
□ 1. CR 上線 → 先依既有索引維護程序重建／增量更新 ES 索引
□ 2. 從 CR 單取「動到的物件清單」（Component / Record / 程式名）
□ 3. 定位受影響知識：對每個物件 grep docs/ps-research/
     （wiki 檔名、aliases、[[物件名]] 反連結都是純文字）
     → 得到受影響的 entity 檔與 NN-*.md 清單
□ 4. 快速標記（二選一）：
     A. 人工：受影響 entity 檔 frontmatter status 改 stale（SOP-5）
     B. 對話：切 PS-DEEP-RESEARCH 說「CR-<編號> 修改了 <物件清單>：
        把對應 entity 檔標 stale，事實變更寫進 Invalidated 節」
□ 5. 重驗更新：對受影響領域 /ps-audit <領域>——被 CR 改掉的 chunk
     會 FAIL／查無 → 自動回灌 A 項 → /ps-research <領域> 消化
     → 文件與 wiki 就地更新（作廢不刪除；reviewed 檔只追加）
□ 6. 不知道影響範圍：跳過 2~4，對可能相關的領域直接 /ps-audit
     ——證據解引用會自己找出變掉的地方（較慢但完備）
□ 7. 兜底：lint 的 90 天過期警示點名久未驗證的 entity；
     大型改版後全領域輪流 /ps-audit 一輪
```
