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
□ 1. PowerShell 執行（絕對路徑，任何目錄皆可、不用 cd）：
     powershell -File "<repo路徑>\scripts\ps-doc-lint.ps1" -Domain "<領域>"
     （適用舊版 Windows PowerShell 5.1；script 已帶 UTF-8 BOM）
□ 1a. 被執行原則擋（PSSecurityException）→ 依序：
     (1) Unblock-File 該 .ps1 後重試
     (2) 請 IT 對 scripts\ps-doc-lint.ps1 簽章或加白名單
     (3) 「執行原則替代跑法」——**實際指令不入 repo**（安控會掃
         繞過類字樣，連純文字都擋，2026-07 實測）：由管理者存於
         本機筆記，需要時向系統維護者索取
□ 1b. 可「自行在本機」建捷徑檔——**嚴禁 commit 進 repo**
      （公司安控會擋含可執行檔的 git 下載，見 SOP-3）
□ 2. 綠色 PASS → 結束
□ 3. 紅色 FAIL → 逐項處理：
     - 「checklist 已打勾但檔案不存在」「檔案未列於清單」
       → 對話叫 deep-research 修（或人工補 checklist 行）
     - 「ChunkId 遭縮寫為 8 碼」→ **lint 清單驅動的手術式修復**：
       把 lint 列的 檔×id 清單直接貼給 PS-DEEP-RESEARCH 逐筆修
       （每筆委派重取 chunk、必附「舊→新」收據）；修復波前後各
       commit 一次內部 git（快照可回滾）
     - 「ChunkId 非 UUID / 自編 id」（非 8 碼樣式）→ 證據捏造，
       跑 /ps-audit 該領域
     - 「缺章節 / 無 confidence 標註」→ 對話叫 deep-research 重寫該檔該節
     - wiki 類警告（斷鏈 / 孤兒 / 過期 / frontmatter 缺欄）
       → 斷鏈孤兒叫 deep-research 修；stale 排入下次 /ps-research
□ 4. 修完重跑 lint 確認
□ 5. 附註：-StrictAudit 參數是 auto-loop 畢業門專用（issue #2——
     90-audit.md 的結構性警告升為 FAIL，擋「稽核沒真的做完」的誤畢業）；
     人工執行**不加**此參數，行為與以往完全相同
□ 6. 手術波跑完 lint **未減項**時的升級梯（L32）：
     (1) fresh session 原樣重貼一次（排除新鮮度變因）
     (2) 仍無效＝寫入鏈不可信 → 切「**模型查、人工貼**」：委派改為
         「只在回覆輸出對照表『舊值 → 新完整UUID』、驗貨照舊、
         **禁止寫任何檔案**」，人工照表逐筆貼
     (3) 環境事實：tool-call 約束解碼（SOP-10 第 5 步）經公司政策
         否決（2026-08）——寫入不可靠是**永久條件**，本升級梯是
         標準程序不是例外
     (4) 個位數殘項＋模型持續「判定不用做」→ **人工直通**，不再纏鬥：
         chunk 類＝build/直通測試直接呼叫 search_chunks（結構化參數），
         從工具回傳原文抄 UUID；oracle 類＝自己開 SQL Developer 跑
         cookbook 樣板（記得先 ALTER SESSION SET CURRENT_SCHEMA），
         keyRows 逐字抄——模型的「無須更動」判斷不參與，lint 說缺
         就是缺
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
□ OpenCode 升版 → 驗 tools 圍堵仍生效：agent 檔的 tools 布林表自
  v1.1.1 起屬 deprecated（併入 permission 設定）——升版後抽測主
  agent 是否仍不碰檢索 MCP；失效即把各 agent 的 deny 改寫成
  permission 格式（圍堵牆騎在 deprecated 機制上，升版是唯一風險點）
□ OpenCode 升版 → 檢查是否**新增內建 agent／subagent**（如 general／
  explore／scout）——內建不吃本專案的封鎖，須在 .opencode/agent/
  放**同名覆寫檔**補封 4 個 MCP（2026-08 實測：委派會漏到內建
  explore 直呼 MCP）
□ PeopleTools 升版 → cookbook 的表名/欄位抽 2~3 條樣板實跑驗證
□ MCP server **程式修改**（bug fix／功能變更）→ 至少直通測試該
  server 的每個 tool；修的是檢索類 server → 歷史「查無」判定與
  文件 gaps 全帶嫌疑，下輪 audit 的二次定位會自動平反，**不必**
  專案式重查；若涉及**重建索引** → chunk id 輪換，走 SOP-11
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
□ **【L60】headless 下多了一個致命環節**：連續 invalid 重試會觸發
  opencode 的 `doom_loop` 保護，跳出「continue after repeated failures?」
  詢問（pattern 顯示為 `invalid`）。該權限**預設是 "ask"**，而 headless
  沒有 TTY 可以回答＝**永遠阻塞**，提示還畫在 TTY 上、log 裡看不到。
  症狀只剩「輸出靜止」，逾時上限開多大都一樣撞滿、產出為零。
  → 跑 auto-loop 前**必須**先照 SOP-17 第 0 條把 `doom_loop` 設 "allow"，
    本行的「逾時熔絲自動處理」才成立。沒設＝每次都燒滿整個上限。
□ subagent 鬼打牆（不斷重複相同產出、沒有盡頭）＝退化迴圈（L34）：
  **不用等，直接中斷、開新 session 重跑**——checklist 未勾＝進度
  不會丟，fresh session 通常一次就過（抽樣事故非確定性障礙）。
  auto-loop 下不需人工：逾時熔絲自動處理（強殺→一致性檢查→
  下圈 fresh 重跑→連續 2 次才熔斷給人工）；覺得反應太慢可調短
  -ResearchTimeoutMin／-AuditTimeoutMin
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
□ 5a. thinking 標記洩漏（輸出出現 </think>、<|im_end|> 等）＝
     chat template／reasoning parser 未對齊：對齊 model card 的模板
     （vLLM 開對應 reasoning parser）；工具密集用途可評估**關閉
     thinking**（enable_thinking=false／prompt 加 /no_think）——
     通常 tool-call 更穩、更快；lint 會抓漏進文件的髒標記
□ 6. 建議值：context 不必盲開 262K（KV cache／prefill 代價大）——
     subagent 隔離下 32K～64K 通常足夠；輸出上限建議 ≥ 8K
□ 7. 查到的數字回報對話，據以調整規則（如寫檔行數上限）
```

---

## SOP-16 兩段式畢業與廣度優先排程

**為什麼**：畢業門原本只有一級——未勾=0＋lint 全綠＋StrictAudit 全綠，
那是 100 分門。但 100 分的尾巴是漸近線（SOP-13 已載明「修復寫入會以低
固定率播下新小瑕疵」），加上稽核每輪回灌新項，單一領域可以無限追下去。
結果是**第一個領域追完美、其餘領域停在零分**——而 wiki 的價值在「每個
領域都查得到」，不在「一個領域完美」。

```text
tier 1＝覆蓋畢業（可用／80 分）
  門：SESSION_OK ＋ WORK_TRANSITION_OK ＋ lint -CoverageOnly 全過
  保證：功能查得到、每份文件有實質內容、沒被截斷或污染
  不保證：每句話能逐條回溯驗證（證據 id／機器參照／confidence 屬美工）
  未勾項：留著不擋——稽核回灌的補強項是建議不是債（SOP-13）

tier 2＝精修畢業（100 分）
  門：現行三層門（未勾=0 ＋ lint 全綠 ＋ StrictAudit 全綠），一字未改
```

```text
□ 單領域：powershell -File .\scripts\ps-auto-loop.ps1 -Domain <領域>
  （預設 -Tier 1）；要精修再跑一次加 -Tier 2
□ 批次：ps-auto-all 預設**兩趟**——所有領域先到 tier 1，全部跑完才開
  第二趟做 tier 2。只跑一趟用 -Tier 1 或 -Tier 2
□ 收據記 tier：tier 1 收據放不了 tier 2 的行（第二趟會照常重跑該領域）；
  tier 2 收據涵蓋 tier 1
□ 相位判定（tier 1）**不看未勾數，看缺料還在不在**——照未勾數判會因
  「勾 2 個、回灌 3 個」而永遠進不了 audit＝永遠畢不了業（實案：一輪
  回灌 11 項）。進度熔絲同理改量「缺料違規數」
□ 分類是白名單：只有明確列在 lint 的 $polishPatterns 才算美工，
  其餘一律缺料（fail-safe：漏分類只會讓門更嚴，不會放水）
□ 標準凍結紀律：衝刺期不加新 lint 檢查——每加一條＝所有既有檔案重新
  不合格＋所有收據失效，終點線自己在移動
```

---

## SOP-17 無人看管排程（衝刺期夜間跑批）

**目標不是「讓它一直跑」，是「讓它跑到全部畢業為止」。** 全部 tier 2 畢業
之後就該切維運節奏（SOP-13），不再夜夜開跑——連續迴圈＝永動工單機。

用 Windows 工作排程器叫 `ps-auto-all.ps1`，不要自己寫 sleep 迴圈守著
（那需要一個行程永遠活著，當機沒人重啟，也沒有 OS 層的重疊保護）。

```text
□ 1. 觸發：每日一次，挑**下班後的離峰時段**起跑
     （批次期間＝重載期，SOP-12：禁手動 /ps-research、/ps-audit、查 DB 問答）
□ 2. 動作：powershell.exe
     引數：-NoProfile -ExecutionPolicy Bypass -File "<repo>\scripts\ps-auto-all.ps1"
           -MaxCyclesPerDomain 6 -MaxBatchHours 9 -MaxConsecutiveFailures 3
     起始於：<repo>（工作目錄一定要設，腳本用相對路徑找 docs/ 與 .opencode/）
□ 3. 設定頁勾「如果工作已在執行，不要啟動新的執行個體」
     （雙保險：ps-auto-loop 自己也有互斥鎖，重疊會 exit 3 停批）
□ 4. **不要**加 -Force（那是忽略收據全部重驗，夜跑用它等於每晚重跑全部領域）
□ 5. 圍欄要用 -MaxCyclesPerDomain 收斂：MaxBatchHours 只在**領域之間**檢查，
     攔不住進行中的領域（單領域最壞＝MaxCycles×120 分）
□ 0. **【必要前提】headless 權限設定**（L60；不設就會每晚卡死一次）：
     opencode 有兩個權限預設是 "ask"——`doom_loop`（重複的相同工具呼叫）
     與 `external_directory`（專案目錄外的路徑）。headless 沒有 TTY 可以
     回答，"ask" ＝**永遠阻塞**到逾時強殺，而且提示在 log 裡看不到。
     TUI 點「always allow」只在該互動 session 內有效、**不落檔**。
     在**本機全域** `~/.config/opencode/opencode.json`（就是已經註冊 MCP
     的那份；內含公司內部主機名，**不進 repo**）加：
     ```json
     "permission": { "doom_loop": "deny", "external_directory": "allow" }
     ```
     · `doom_loop: **deny**`（L60 二次修正，2026-08 實測定案）：提示原文是
       「continue after **repeated failures**?」——它管的是**反覆失敗的呼叫**，
       不是「反覆呼叫同一個東西」。三種設定的實際行為：
         `ask`（預設）＝跳提示、headless 無人可答 → 卡死，**但看得見**；
         `allow`＝**無限重試失敗的呼叫** → 卡死，**完全看不見**（實測：
           subagent 讀一個不存在的 tool-output 檔，靜止 30 分以上、零輸出、
           零提示）；
         `deny`＝停止重試 → **快速失敗、看得見**。
       確定性失敗（檔不存在、工具名錯、掛錯 server）重試一萬次結果相同
       ——L61 已立此原則，`allow` 等於在設定層打開無限重試，與該原則相反。
       **無人環境的判準：看得見的失敗 ＞ 看不見的重試。**
     · `external_directory: allow`——**opencode 自己會把過長的工具回傳寫進
       `%TEMP%` 再讓模型讀回來**（管理者實測觀察）。那個路徑在專案目錄外，
       設 deny 會讓 subagent 讀不到自己剛存的資料；設 ask 就是現在這個
       永遠阻塞的死鎖。這也最能解釋「為什麼偏偏卡在第 14 檔」——
       那個檔的證據量大到觸發暫存機制。
     · `doom_loop: allow`——稽核會對同一個 chunk id 重複取用（不同檔引用
       同一段程式碼），那是正當行為；設 deny 會擋掉真的驗證。
     · 這兩個設定放行／封鎖的只是「路徑範圍」與「失敗後續試」；agent 的
       `tools` 白名單照常生效，subagent 的 bash／write／edit 仍然是封的。
       跑飛仍由**外環逾時／一致性檢查**熔斷（框架本來就是這個分工）。
     · **不要用 `--auto`**：那是把所有非 deny 的 ask 一次放行，範圍過大。
     · 原則：**無人環境只有 allow 或 deny 兩種安全狀態，沒有第三種**——
       "ask" 在沒有 TTY 的地方一律等於死鎖。
     改完**重啟 opencode**，先手動跑一次 `/ps-audit <領域>` 確認不再跳提示。
□ 6. 環境前提（沒滿足就不是無人看管，是每晚失敗一次）：
     · 地端模型服務必須是**常駐服務**，不是登入才啟動的東西
     · opencode 必須在該排程帳號的 PATH 上（.cmd 型，L46）
     · 若勾「不論使用者是否登入都執行」，先手動用該帳號跑一次 -Preflight 驗證
□ 7. 早上只看一行：auto-loop-logs\batch-*.log 的 Summary
     GRADUATED／NEEDS_ATTENTION／MUTEX_BUSY／SYSTEM_ERROR／SKIPPED
□ 8. 退場：領域 tier 2 畢業後從 research-domains.txt **註解移出**
     ——留在佇列＝每晚重驗，正是 SOP-13 要避免的永動工單機
```

**已知缺口（現階段靠人看，不做自動化）**：某個領域若每晚都
NEEDS_ATTENTION，排程會每晚重燒它幾小時而沒有人知道。要不要加「連敗
N 晚自動除役」得先有實測基線（L48：門檻照實測設，不照直覺設）——
目前領域數與夜跑次數都不足以定那個 N。**在此之前，每天早上看 Summary
那一行就是這條熔絲**。

---

## SOP-13 維運節奏（領域畢業後的營運模式）

領域完成衝刺（畢業）後，**不再**「每次 research 後緊接 audit」——
修復寫入本身會以低固定率播下新小瑕疵（寫入攪動地板），連續迴圈
＝永動工單機。改為：

```text
□ 問答：隨時（系統存在的目的）
□ lint：任何寫入波之後跑（30 秒，確定性）
□ research：只在「有想處理的工單」時跑——回灌 A 項是建議不是債，
  躺著沒關係；縮寫類用 lint 手術指令按波清理
□ audit：CR 上線後（SOP-11）或月度一次；判讀看趨勢與基準線，
  不追單輪絕對值
□ 慢性類（縮寫涓流／欄位錯）：照對應機制處理，不為它們加開稽核輪
```

---

## SOP-12 oracleMCP 單通道操作紀律

oracleMCP＝VS Code SQL Developer extension 的 SQLcl。實測（2026-08）
**輕量查詢可並發**（3 subagent 同呼成功）；問題出在**重載**：
稽核 SQL 風暴期間並行查詢會排隊逾時（>30s → BLOCKED），
且各 session 的 disconnect 可能互拆共用連線。

```text
□ 原則：**重載期間不並行**——audit／research 跑 SQL 重驗段時，
  避免在其他視窗問需要查 DB 的問題（wiki 已有／純程式碼題不限）；
  平時輕量查詢並行無妨
□ 批次（ps-auto-all，SOP-14）執行時段**整段視同重載期間**——期間禁止
  手動 /ps-research、/ps-audit 與需查 DB 的問答（相位不可預測，且手動
  寫入會落在批次的畢業門與收據之間，讓收據認證未驗證的內容）
□ 常見症狀：問答說「DB 通道忙碌／逾時」、稽核出現成批
  UNVERIFIABLE(逾時／view 不可用)——先想「是不是兩個視窗在搶」
□ 快篩三步：(1) VS Code 與 SQL Developer extension 活著？
  (2) 無並發時 build 模式直通測試（叫它用 oracleMCP 查 SELECT 1）
  (3) 只有並發時失敗＝搶用確認，錯開時間即可
□ 通道死透（無並發也失敗）→ 重啟 VS Code／extension 再測
□ view/table not found → 檢查 customization-profile.yaml 的
  oracle.currentSchema 已填（cookbook 生命週期第 3 步）
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
□ 8. **收據不會自動失效（L64）**：contentHash 只看檔案內容，索引重建
     不動任何 .md——已畢業領域的收據照樣有效、batch 照樣 SKIP，
     而它的每條引用都已是死的。重建完成的檢查清單**必含**：
     對已畢業領域逐一手動 /ps-audit（回灌 A 項→內容變→收據自然失效），
     或 batch 加 -Force 全部重驗
□ 9. **整庫 chunk id 輪替**（重建而非增量）＝所有領域證據全滅：
     第一輪 audit 預期成批查無——auditor 會標「疑似索引已重建」並
     全部判 stale 走二次定位（L64），**不是**成批捏造；tier 1 仍會
     照常畢業（驗證層屬 tier 2 契約），重建後第一輪要看 90-audit.md
     的回灌清單，不要只看畢業訊息
```

---

## SOP-14 批次多領域研究（ps-auto-all）

佇列 `.opencode/peoplesoft/research-domains.txt`（人工維護、一行一領域、
`#` 註解；只回答「要研究什麼」，不存進度）。收據
`docs/ps-research/<領域>/graduation.json` 只由 ps-auto-loop 畢業時寫入，
排程器只驗不寫；**收據＝單機事實**——不進 git（.gitignore 已擋），
各機各自畢業，batch 只在管理機跑。

```text
□ 啟動前：Unblock-File 四支腳本（auto-all／auto-loop／doc-lint／graduation
  ——auto-all 用子 powershell 跑 auto-loop，執行原則須四支都放行）
□ 跑批：powershell -File "<repo>\scripts\ps-auto-all.ps1"
  （選配熔絲 -MaxDomains 10 -MaxBatchHours 8 -MaxConsecutiveFailures 3；
  -Force＝忽略收據全部重驗；-MaxCyclesPerDomain 可縮單領域天花板。
  注意 MaxBatchHours 只在領域之間檢查——單領域最壞時長
  ＝MaxCycles×(audit 120m＋surgery 60m×MaxSurgeryPerCycle)，
  要硬圍欄就縮 MaxCyclesPerDomain，別指望 MaxBatchHours）
□ 批次時段＝重載期間（SOP-12）：禁手動 /ps-research、/ps-audit、查 DB 問答
□ 領域畢業後：從佇列**註解移出**——維運期月度 audit 會使收據失效，
  留在佇列＝batch 每次自動重跑（SOP-13 明文要避免的永動工單機）；
  重新排入時機由人決定（CR 後、要清消 A 項時）
□ 早上看 auto-loop-logs\batch-*.log 的 Summary：
  GRADUATED＝畢業（收據已驗）；NEEDS_ATTENTION＝該領域卡住（看
  auto-loop-logs\<領域>\ 的 GATE 行與 strict-cycle*.txt），不擋其他領域；
  MUTEX_BUSY＝鎖被外部持有（錯開重跑即可，非損壞）；
  SYSTEM_ERROR＝automation 不可信（環境級，修完才准重跑）
□ 批次被 Ctrl+C 中斷：對當時進行中的領域跑一次 lint（SOP-2）確認無半寫
  損壞再重啟批次；收據不會半寫誤判（寫入後回讀重驗＋壞 JSON 一律當無效）
□ exit 0 但收據無效＝兩端判準不一致（版本歪斜？）——停批屬設計行為，
  先核對四支腳本是否同版（gateVersion／schemaVersion 常數在 ps-graduation.ps1）
□ lint／收據腳本的修改要**攢批**（2026-08 管理者裁決）：ps-doc-lint.ps1
  或 ps-graduation.ps1 任何改動（含純措辭）＝全部已畢業領域收據失效、
  下次 batch 每領域重燒一輪 audit session——措辭類小改不單獨上，
  攢到 CR 後／月度 audit 等本來就要全面重驗的時點一起改
```

---

## SOP-15 00-overview 換版（凍結快照的刷新程序）

00-overview 階段一寫完即凍結（L2：防大檔覆寫截斷與破壞性覆寫），
從此**不隨輪次更新**——它是「盤點快照」不是現況；現況真相在
checklist／NN 檔／wiki。lint 會在領域歷 3 輪稽核後開始提醒落後。

```text
□ 1. 時機：畢業收尾、CR 對齊後、或 lint 落後提醒且你覺得導航頁已失真
□ 2. 開 fresh session 對 PS-DEEP-RESEARCH 說：
     「依 checklist-archive、NN 檔與 wiki 現況，重製 00-overview 的
      內容草稿，寫到 00-overview-draft.md——不要動 00-overview.md」
     （agent 對凍結檔維持零寫入；草稿是新檔＝真 append 哲學）
□ 2a. 併入清單：lint 的「功能地圖缺 N 個後續發現的項目」警告就是
      換版必併清單（機械 diff，checklist＋archive 對 overview 內文）
      ——換版後重跑 lint 該警告應消失，否則草稿漏抄
□ 3. 人工審草稿 → 滿意就人工把內容覆蓋進 00-overview.md：
     產生日期改當天，並在檔頭引言區加一行**照這串字寫**：
       > 第 2 版（於稽核輪次 20 換版）
     R＝換版當下 checklist.md 的稽核輪次。lint 用這串字算「落後幾輪」——
     寫成別的格式（缺輪次數字、換句話說）會被判成沒換版而繼續提醒（L54）。
     → 刪草稿檔
□ 4. lint 確認 → commit（kb(fix): 00-overview 換版）
□ 5. 換版使 graduation 收據 contentHash 失效＝下次 batch 重驗——
     屬預期行為（文件變了本該重驗）；想省成本就攢在 CR 後一起做
```
