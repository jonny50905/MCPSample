<!-- 來源：2026-09 三角度調查＋對抗驗證 workflow 的合成備忘（issue #22）。L106／L107 落地時採其骨、去其重：不做 journal、不做 finalizer session、不做 taskId 級收據。保留此文供後續精修分批稽核參考。 -->

# PS-Audit 容量事件決策備忘（issue 22 裁決與最小可行設計）

> **採信基礎**：三個調查角度共 12 條發現，只有 levers-F2（ps-audit.md「規模再大也照樣執行」是 L63 反拒答條款、parent 端三個累積源無分批）通過對抗驗證；其餘 11 條被反駁。但反駁方各自寫下的「修正後主張」與「殘餘建議」高度收斂，本備忘只採信 (a) 通過的 F2、(b) 反駁方修正主張中我已逐條回碼核實的部分。被反駁發現中仍保留的元素在第 4 節說明理由。所有「檔案:行號」皆為本次 Read/Grep 實看；推測處標明。

---

## 1. 爆炸點定性

**主爆點（管理者實測、且碼上唯一無上限的工作單位）＝ ps-auditor 單檔「任務 A」委派的輸入側。** 子代理是獨立 context（ps-auditor.md:3 `mode: subagent`；:9 `task: false` 不能再分攤），每委派一檔（ps-audit.md:20-21），其 context 由「該檔 Evidence 筆數 × 每筆 get_chunks_details 完整 ChunkText（:73-79；progressive-source-retrieval.md:260）× 失聯時三管道二次定位且翻頁到底（:80-99、:97 引 §5.1 :218-219「翻到最後一頁」、:242「翻頁到全量」，實測一個 AE 名 semantic 命中 59 chunk :234-236）× 旗標下查無抽驗全量（:119-127）」決定，而硬規則「回報筆數少於該檔 Evidence 筆數＝無效」（:206-209）禁止部分回報。對照同一契約任務 C 有「>5 張只做前 5、其餘退回 gaps」的對稱防守（:161-163，L27 applied.md:504-507「需要壓縮才做得完的委派＝委派切錯了」），任務 A 沒有。repo 已有同型實錄：L60「偏偏卡在第 14 檔——該檔證據量大」（applied.md:1320-1324）。**主導成長項不是 NN 檔總數，是單檔 Evidence 列數與失聯比例**；NN 總數只透過四條間接通道放大：(i) 檔越多、最重那檔越重、每輪 170+ 次委派必中重尾；(ii) 索引重建後每筆都走三管道（L64 applied.md:1463-1475）；(iii) 85 檔壓力下 3B parent 違反「一委派一檔」把多檔塞進同一委派或以 task_id 續用同一 auditor（L67 applied.md:1572-1586 前案；task_id 續用屬推測，需看 export）；(iv) wiki entity 的 Observations 隨連結它的 NN 檔線性成長，1b 每輪抽 5 個 entity 跑任務 A（ps-deep-research.md:262-267、:373-384；entity-template.md:15-21 無編號欄）。

**次爆點（issue 22 的定性）＝ parent（deep-research 稽核 session）線性累積。** 契約上逐條成立：85 檔 × ［任務 A 逐筆 JSON（:206-209）＋ parent 自己 read 每個 NN 抽 3~5 條 CONFIRMED claim（ps-deep-research.md:259-261，與 :464「已完成檔案內容不回讀進主 context」相衝）＋任務 B JSON］＋ wiki 5 檔＋任務 C 各批＋ step 4 整檔重寫 85 列記分卡（:338-345，撞 :453-455「單次寫檔 ≤150 行」）。但 **實測未證**：被引為指紋的 L29 是「管理者假說待證」（applied.md:558-563）、L69 是值域洞不是壓縮（:1654-1657）、L73 未診斷成因（:1782-1792）；同領域已在 ~85 檔規模跑到 r60~r67（:2641、:2701、:2723）而無記分卡塌縮紀錄。

**環境層前置疑點（成本最低、可能是硬錯的真因）**：管理者看到的是 `Context length exceeded` 硬錯，而 repo 唯一子代理撐滿實錄 L27 是「觸發 auto-compact 續作」（applied.md:495-497）。硬錯而非壓縮，指向 opencode.json 宣告 `limit.context` 高於 serving 端真實上限，使 OpenCode 的溢出判定永遠不先觸發（推測；L6 applied.md:124-125 疑點至今未回填；SOP-10 SOP.md:265-277 探針就是為此而設；:290-291 建議 32K~64K）。

**與外環的關係**：scripts/ 整個目錄 grep 不到 context/overflow/exceeded 任何字樣（零偵測）；非零 exit 只摘 err 尾 5 行（ps-auto-loop.ps1:1231-1237）；且子代理輸出不流到父行程 stderr（:854-855、L48 applied.md:941-942），OpenCode 的 task 錯誤是回給 parent 模型當工具結果（推測）→ 子代理溢出多半以 exit 0 收場、走不到 :1226 的錯誤分支。**「loop 停了」究竟觸發的是 errorStreak（:1239）、逾時（:1216）、auditStall（:1531-1539）還是 MaxCycles，repo 判不出，需看該圈 rc/err/auto-loop.log。**

**吻合度**：issue 22 的 Current Behavior 與五條根因逐條在碼上成立，但它把爆炸點放在 parent、把 Task A Evidence budget 當附帶句，與管理者觀察相左；管理者觀察正確指向子代理，但「NN 越多→auditor 爆」的機制是間接的。兩者都對一半，需要兩套修法，且子代理那套要先上。

---

## 2. issue 22 逐條裁決表

| # | 項目 | 裁決 | 一句理由（碼證據） |
|---|---|---|---|
| 根因 1 | 新 session≠無限 context，無分批續跑 | **成立** | ps-audit.md:8-10 為 L63 反拒答修補（applied.md:1447-1453），非容量保證；audit 相位＝單一 Invoke-Opencode、prompt 只有 $Domain（ps-auto-loop.ps1:1195-1198） |
| 根因 2 | Task B 讓 parent 逐份讀 NN | **成立** | ps-deep-research.md:259-261「由你從該檔抽 3~5 條」，與 :464 相衝 |
| 根因 3 | Task A result 隨 Evidence 成長，需 evidence budget／分頁 | **部分** | 方向對、機制錯：先爆的是輸入側（完整 chunk＋三管道翻頁，ps-auditor.md:73-99），非 JSON 輸出；且分頁若無確定性對帳會製造半檔假綠燈（lint 只量檔名提及，ps-doc-lint.ps1:808-810） |
| 根因 4 | 無跨 session checkpoint | **成立** | Get-AuditTransition 只有輪次＋hash（ps-auto-loop.ps1:160-174）；L73「只證明動過」（applied.md:1793-1796）；90-audit 每輪整檔重寫＝半途結果無處落地 |
| 根因 5 | auto-loop 未把 overflow 當容量事件 | **成立但不足** | scripts/ 零 context 字樣；:1225-1239 只看 exit code；但子代理溢出多半不進 exit≠0 分支（:19、:854-855）——分類必須掃 out＋err 且不以 exit 為前提 |
| 實作 1 | Deterministic Audit Manifest（含 fileHash） | **採納（檔級＋範圍級）** | Get-NormalizedFileHash 可直接重用（ps-graduation.ps1:29-39）；claimId／taskId 級延後 |
| 實作 2 | PowerShell 確定性抽 Task B claim | **採納** | 模板 CONFIRMED 只有兩種形狀（function-detail-template.md:36、:43）；lint 本就對 3B 寫的 markdown 做形狀解析（ps-doc-lint.ps1:557、:641-648）；抽到 0 條走 fail-closed；seed 抽法不可行（parent／auditor 皆 bash:false，算不出 hash） |
| 實作 3 | Bounded batch（檔數＋evidence 兩維 budget） | **採納（最必要）** | oracle ≤3 已存在（ps-audit.md:24-26、SOP.md:447-451）；檔數維在 parent、evidence 維在子代理契約＋manifest |
| 實作 4 | 外環捕捉 strict JSON＋schema 驗證後寫 receipt | **部分** | 不可行處：auditor JSON 只回 parent、write:false（ps-auditor.md:10、:214-218）、OutFile 從未被讀（僅 :892/:914/:1187）；改為「part 檔通過確定性不變量 → 檔級收據」 |
| 實作 5 | 從 receipts 重建 90-audit（resumable finalization） | **部分** | 表格節、合計、A 列、覆蓋率可機械 render；D 項 Domain Gate／上輪覆核／系統性觀察是語意工作，交 bounded finalizer 寫小檔、外環拼接；finalizer 禁 read NN |
| 實作 6 | CONTEXT_OVERFLOW 分類＋拆批只重跑失敗批 | **部分** | 分類採納（掃 out＋err）；「拆批」對任務 A 不能 binary split（已是一檔一委派；L102 applied.md:2631-2633 已否決盲目拆批）→ 改「收據續跑＋單檔頁減半＋最小單元 BLOCKED」 |
| 實作 7 | 精簡稽核 orchestrator agent | **採納（低成本配套）** | ps-audit.md:3 frontmatter 改 agent 即可；ps-deep-research.md 470 行全載入是固定成本；但需 `mode: primary` |
| 不接受 1 | 只提高 AuditTimeoutMin | 同意 | L59：真實時長未知，設寬是為了量（ps-auto-loop.ps1:63-68） |
| 不接受 2 | 只換更大 context 模型 | 同意，**但**「量 serving 真值並把宣告 limit 對齊」不是換模型，是必做前置（SOP-10；L6 未回填） |
| 不接受 3 | 只調 subagent 併發 | 同意 | L67／L83：併發不是變數 |
| 不接受 4 | 只調 auto-compaction／pruning | 同意 | 對齊宣告 limit 不屬此類（是讓既有壓縮機制能觸發，不是調壓縮參數） |
| 不接受 5 | overflow 後原樣重跑 | 同意 | 現況正是如此（:1094-1199 下圈同 prompt） |
| 不接受 6 | 降低全量覆蓋 | 同意 | 記分卡每檔一列仍是 tier 1 門（L69） |
| 不接受 7 | 省略 Evidence verdict | 同意 | ps-auditor.md:206-209 守衛保留，改為「範圍內筆數」 |
| 不接受 8 | auditor 自選 Task B claims | 同意 | seed 規則抽亦否決：L103 根因四「沒寫取哪幾項→挑軟柿子」（applied.md:2683-2685） |
| 不接受 9 | 只縮 system prompt 仍單 session | 同意 | 精簡 agent 只當配套，不當替代 |

---

## 3. 採納的設計（按價值／成本排序，全部以現有零件拼）

### D0. 診斷前置（零改碼、當天可做，決定 D1~D4 哪些真的要上）
- **改哪裡**：不改碼。管理者在公司機執行：(a) SOP-10 步驟 1~3（SOP.md:265-277）比對 opencode.json 該 model `limit.context` 與 serving 真實 n_ctx／max_model_len，並查 `compaction.auto`；宣告 > 真值即先校正。(b) 翻停機那圈 `auto-loop-logs\<領域>\*-audit.rc.txt／.err.txt／.out.txt`（ps-auto-loop.ps1:810-811、:817）：rc 是否 0、err 有無 context 字樣、auto-loop.log 的「=== auto-loop 停機」行是哪種熔絲。(c) `opencode session list --format json` 取 title 為 `auto-audit`（:821）的 session → `opencode export` 看 task tool part 的 input（含幾個 NN 路徑、是否同時 A＋B、是否帶 task_id）與 `metadata.sessionId`，再 export 子 session 數工具呼叫與回傳長度。**不要加 `--print-logs`**（走 stderr，污染 :1234 尾 5 行與 :847-853 mtime 心跳，L59 強殺判讀會被固定在「調上限」那一側）。
- **接線**：既有 log 檔與 OpenCode CLI；零新介面。
- **殘餘風險**：session list 只列根 session（子 session 需從 parent export 的 metadata 取）；版本若非 v1.17.15 行為可能不同（ps-auto-loop.ps1:6 註明鎖定版本）。

### D1. 子代理層容量：契約上限＋Evidence 範圍委派（對準管理者觀察；獨立可先上）
- **改哪裡**：`.opencode/agent/ps-auditor.md` 任務 A；`.opencode/peoplesoft/progressive-source-retrieval.md` §5.1。
- **改什麼**：
  1. 把 :97-99 與 §5.1 :218-219／:242 的「翻頁到全量」與 §5 :165-171／:207／:212／:217 的預算條款寫成**一句不矛盾的上限**：二次定位每管道 search_chunks 最多 2 頁（§5 maxSearchResults 20）、get_file_structure 後只取含目標行號的單元 1 批（maxExpansionRounds 3 內）、semantic 第三管道最多 2 頁；到頂仍無 → 該筆 `FAIL(NOT_FOUND)`，reason 附最後一次查法收據（管道／參數／頁數）。**沿用既有值域與 reason code，不新增 BUDGET_EXHAUSTED、不要模型數呼叫次數**（3B 不會數，L6 applied.md:117-119；新 reason code 要三處落點，L69 :1656-1657）。
  2. 任務 A 委派 prompt 可帶「只驗 Evidence 附錄第 a~b 筆（以 `#` 欄為準）」；wiki 檔以「第 a~b 條 Observation」計。硬規則 :206-209 改為「回報筆數少於**委派範圍內**筆數＝無效」，**且此改動只准與 D2 的 manifest 同一 commit 上線**（範圍由外環算、parent 只照抄，不做機率性切段與聯集）。
  3. 「查無全量抽驗」旗標維持一次性（ps-deep-research.md:253-256、:336-337），不拆新任務型；旗標由外環持有、所有批次看到同一值（見 D5），杜絕批 1 翻掉後批 2~M 只抽樣的假綠燈。
- **接線**：值域三詞（ps-auditor.md:128-129）、`FAIL(NOT_FOUND)`→A 項→research 補查的既有生命週期（ps-deep-research.md:314-317、:131）、L79 的 ID_RELINK 回灌工單（ps-doc-lint.ps1:837-940）全部不動。
- **殘餘風險**：上限數字（2 頁）是契約估值，需 D0(c) 的實測回校；單筆真的需要 >2 頁的尾巴會成 NOT_FOUND → A 項，由 research 用 flow 子代理（有 §5 預算）再試，代價可承受。

### D2. Parent 分批：外環 manifest＋精簡稽核 agent＋批次 command（每 session K 檔 → part 檔）
- **改哪裡**：`scripts/ps-auto-loop.ps1` audit 分支（:1194-1198）；新增 `.opencode/agent/ps-audit-orchestrator.md`（primary；tools 同 ps-deep-research.md:6-19：read/grep/glob/task/write，四 MCP deny，bash false；system prompt 只含稽核批次流程＋委派模板＋硬規則，不含研究／提煉章節）；新增 `.opencode/command/ps-audit-batch.md`（agent 指向新 agent）；`scripts/ps-doc-lint.ps1` 加 `-EvidenceStats` 唯讀開關。
- **改什麼**：
  1. 外環每圈 audit 相位前產生 `auto-loop-logs\<領域>\audit-manifest.txt`（模型唯讀；不放領域目錄免進 Get-DomainContentHash ps-graduation.ps1:45-47 與 git 快照 :1030-1032）。內容：目標輪次 N+1；policyHash（ps-auditor.md＋兩個新檔的 Get-NormalizedFileHash）；旗標狀態；本批檔案清單（K 預設 6，對齊 ps-deep-research.md:81-83／:385 的每 session 6 件）；每檔 Evidence 列數（來自 lint `-EvidenceStats` 印的 `EVIDENCE_ROWS：<檔>=<n>`，複用 :641-648 的 `$evRealRows`，L75 禁止第二份實作）、範圍切段（頁大小 `-AuditEvidencePageSize` 預設 15，待校準）、每檔 fileHash；每檔 3~5 條 Task B claim（regex 抓 `## 行為邏輯` 節的 `- **CONFIRMED**：` 行與資料流表 `| … | CONFIRMED |` 列；抓到 0 條 → manifest 註記 `CLAIMS_NONE`，auditor 對該檔 claims 回單筆 `UNVERIFIABLE(行為邏輯節無可機械抽取的 CONFIRMED 行)`——落既有值域，並由 lint 出警告）；領域級批（batch 0）另列：任務 C 表清單（≤5 張／委派）、wiki 抽驗 5 個 entity（外環依 frontmatter last_verified 挑）。
  2. `ps-audit-batch.md`：第一動作 read manifest（固定路徑，不用 $ARGUMENTS 第二個詞——:16-17 的取詞是 read 失敗後的補救，不是參數解析器）；只稽核清單內檔、每檔每範圍一個任務 A 委派、任務 B 委派用 manifest 的 claim；**只寫** `docs/ps-research/<領域>/audit-parts/part-<批號>.md`（模板兩張表；記分卡一列＝一檔一範圍，檔案欄寫 `01-X.md [1–15]`，合併時由外環按檔加總——parent 不做聯集）；batch 0 另寫 `audit-parts/domain.md`（任務 C 結構化候選表＋覆蓋率行＋wiki 結果）；明文禁止改 checklist.md、90-audit.md、輪次行、旗標行、任何 NN 檔；保留 ps-audit.md:8-10 的「不得反問、不得婉拒」，刪「規模再大也照樣執行」。子目錄 `audit-parts/` 對所有掃描隱形（lint :504 / 洩漏 :1019 / NN 防衛 :748 / hash :45 皆非遞迴），且模型可寫（ps-deep-research.md:38）；外環在合併後刪除。
  3. 外環：audit 相位改為「依 manifest 逐批 Invoke-Opencode（`--command ps-audit-batch`，Tag `audit-b<i>`，逾時沿用 AuditTimeoutMin，L48 沉默基線 30 分不可縮到 30）；每批前後照手術迴圈（:1344-1346）重拍 NN 快照與 checklist inventory 並跑 Invoke-NnDestructionGuard／Invoke-PostSessionReconcile；session 級故障（逾時／exit≠0）連 2 批即停本圈 audit（同 :1364-1375 的獨立 streak，不污染 research streak）」；新參數 `-AuditBatchesPerCycle`（預設全部）作時間圍欄。
- **接線**：手術批次迴圈骨架（:1327-1348）、Invoke-Opencode、NN 防衛、調帳邊界全部複用；ps-audit.md 原指令保留給人工互動（改為呼叫同一 agent 的全量版）。
- **殘餘風險**：3B parent 可能無視 manifest 仍全量 read——只耗時間，不致假綠（收據由 D3 對帳）；part 檔內若有洩漏標記，外環合併前用 lint 同一 `$leakPattern`（:1017）掃，命中＝該批無效。

### D3. Part 驗收不變量 → 檔級收據（續跑不重做的基礎）
- **改哪裡**：`scripts/ps-auto-loop.ps1` 新函式 `Test-AuditPart`＋台帳 `auto-loop-logs\<領域>\audit-ledger.json`（獨立於 surgery-ledger：後者每次存檔對 lint 現況剪枝 :624-641，塞異質 key 會被剪掉且干擾排水判定 :1172-1179）。
- **改什麼**：每批結束後解析 part 檔（沿用 lint :854-881 的明細列解析與 :69-86 Test-NnMentioned 語意；解析器放進 lint 以 `-AuditPart <路徑> -NnSubset <清單>` 開關由外環呼叫，不抽到第三個 ps1——否則覆蓋判定逃出收據的 lintScriptHash 覆蓋，ps-graduation.ps1:139-143）。每檔通過條件：(i) 該檔所有範圍列都在；(ii) 記分卡 PASS＋FAIL＋UNVERIFIABLE 合計 **＝** 該 fileHash 版本的 Evidence 列數（查無抽驗結果要求 auditor 另放 JSON 陣列 `negativeChecks`、parent 在明細以類型「查無抽驗」列出、不計入三欄——否則只能用「≥」，會留 1~2 列 slack 讓半檔漏網；`FAIL(FALSE_NEGATIVE)` 目前只在 ps-auditor.md:125、不在 audit-template.md:26-28 詞彙表，順手補齊，L69 同型洞）；(iii) 明細中該檔每筆 UUID ⊆ 該檔 Evidence 附錄 UUID 集合；(iv) 每筆非 PASS 列 reason 非空。通過 → 寫收據 {file, fileHash, round=N+1, policyHash, evidenceRows, counts, partFile, stamp}；不通過 → 該檔無收據、attempts＋1（只在健康 session 記，同 :1410-1426），attempts≥2 → BLOCKED 點名檔名。
- **續跑規則**：圈首讀台帳，收據存在 ∧ fileHash 同 ∧ round 同 ∧ policyHash 同 → 該檔不進 manifest。中途 Ctrl+C／crash：輪次尚未遞增（遞增在 D5 合併時），下圈自然續跑剩餘檔；期間若 research 相位改了某檔 → hash 變 → 只重驗該檔。合併完成後台帳歸檔為 `audit-r<N+1>.done.json`。
- **接線**：Get-NormalizedFileHash（ps-graduation.ps1:29-39）；surgery ledger 的 attempts/BLOCKED 語意（:1419-1426）借用不共用。
- **殘餘風險（要講明）**：收據證明的是「parent 寫的數字通過不變量」，不是「子代理真的跑過」——3B parent 為子代理死掉的檔捏造全 PASS 列仍抓不到（無明細列可驗 UUID）。這與現況風險相同，不是新引入；長期解＝外環直接驅動 auditor（第 4 節延後項）或 D0(c) 的 export 人工抽查。

### D4. Context overflow 分類與拆批續跑政策
- **改哪裡**：`scripts/ps-auto-loop.ps1` Invoke-Opencode 回傳物件加 `FailureKind`；audit 批次迴圈的重排政策。
- **改什麼**：
  1. 每批結束後（**不論 exit code**）對 out＋err 全文 regex `(?i)context.?length|maximum context|context window|truncating input|exceeded`；命中 → `FailureKind=CONTEXT_OVERFLOW` 寫主 log（不改 :1234 尾 5 行邏輯、不改熔絲語意），並在訊息明寫「無此字樣≠無溢出」（Ollama 靜默截斷不報錯，SOP.md:269）。
  2. 拆批政策（有界、以收據為準，不做盲目 binary split——與 L102 applied.md:2631-2633 相容）：本批 **零收據**（推定 parent 側或環境）→ 下批該清單以 K/2 重排（K 最小 1）；本批 **部分收據** → 只重排無收據的檔；無收據的檔若 Evidence 列數 > 頁大小 → 該檔頁大小減半重切（推定子代理側）；頁大小已達最小（例如 3）仍失敗、或 attempts≥2 → BLOCKED，寫台帳並在停機／GATE 訊息點名「檔名＋列數」，人工出路＝依 ps-deep-research.md:455 拆續篇 `NN-X-2.md` 讓單檔證據縮小（本來就是規則）。
  3. 已是最小單元仍溢出且 D0(a) 未校正 → 訊息指向 SOP-10。
- **接線**：:883-891 逾時三分判讀照舊；:1364-1375 型獨立 streak。
- **殘餘風險**：regex 只是標籤，真正的偵測是 D3 不變量；「零收據＝parent 側」是啟發式（推測）。

### D5. 合併器與順序：回灌／輪次／旗標／歸檔在分批下的所有權
- **改哪裡**：`scripts/ps-auto-loop.ps1` 新函式 `Invoke-AuditMerge`；新增 `.opencode/command/ps-audit-finalize.md`（同 D2 agent）。
- **順序（全部批次收據齊備後才開始）**：
  1. 外環從 part 檔確定性產 `90-audit.md` 表格節：表頭「稽核輪次：N+1」＋日期＋範圍；記分卡一檔一列（範圍加總）＋合計列＋燈號；明細串接；wiki 列照 :262-267 格式；BLOCKED 檔寫「未稽核（原因）」列——**lint 在 -CoverageOnly／-StrictAudit 下把「未稽核」列判違規（AUDIT_ONLY）**，避免檔名被提及即過門的假綠燈（ps-doc-lint.ps1:807-815 只量提及）。
  2. 外環依記分卡機械產 A 列寫入 checklist.md「## 調查進度」節（格式 ps-deep-research.md:319；一檔一行；序號由外環連號；僅含 PENDING_MANUAL 的檔不生 A 列，:314-317）；「已回灌」節由外環逐行抄錄——H1 檢查點 3、4、7、9（test-scenarios.md:427-438）從此機械保證。
  3. 外環把輪次行改 N+1、旗標行改「已執行（第 N+1 輪）」（沿用 Invoke-ChecklistReconcile :319-328 的最小插入寫法）。
  4. **finalizer session**（bounded）：read 合併後 90-audit.md、checklist.md、`audit-parts/domain.md`、manifest 附的上輪 A 清單（外環從 `checklist-archive-r<N>.md` 抽）；做 Domain Gate 三分（:288-313）寫 D 列進 checklist；把「上輪回灌項覆核」「完整性（含任務 C 覆蓋行、依附／域外物件）」「系統性錯誤觀察」寫成 `audit-parts/final-sections.md`（<150 行）；**明文禁 read NN、禁改 90-audit.md 與表格**。
  5. 外環把 final-sections.md 拼進 90-audit.md 對應章節（缺節→模板佔位「無」＋log），刪 audit-parts/，取 `$auditAfter` 快照，再 Invoke-ChecklistArchiveCommit（:1284，依 checklist 輪次命名 r<N+1>，:532-541）→ D 項熔絲（:1288-1298 對圈首 $preInv，finalizer 的 D 列照算）→ FixHeadings → lint → 手術迴圈（現有）。
- **接線**：歸檔外環化（L105）延伸到「A 列＋輪次＋旗標」三個 durable state；Invoke-DItemGovernance（:404）照舊裁決 D 提案；90-audit.md 從此只由外環寫，模型端 :453-455 的 150 行上限不再約束報告長度。
- **殘餘風險**：finalizer 若不寫或崩潰 → 語意節為「無」＋log 警示，表格節與回灌不受影響（fail-safe 方向正確）；「上輪覆核」的屬實／誤報判斷仍是模型語意，外環只預填骨架。

### D6. 門、版本與時長公式
- **改哪裡**：`scripts/ps-auto-loop.ps1` :1456-1467；`scripts/ps-graduation.ps1`:25；`scripts/ps-auto-all.ps1`:21-23；`SOP.md`:521-523。
- **改什麼**：WORK_TRANSITION_OK 重定義＝「本輪所有 NN（＋wiki 抽驗 5 檔）收據齊備 ∧ finalizer session exit 0 ∧ 90-audit.md 由合併器寫出且 lint 輪次一致」——原「輪次 -gt ∧ hash 變」在外環自己遞增下退化為恆真，必須改；`GraduationGateVersion` 2→3（舊收據全部失效屬預期，ps-graduation.ps1:14-16、:103-105）；`-MaxNewDPerAudit` 與 auditStall 改以「整輪」計；最壞時長公式改 `MaxCycles×(M×AuditTimeoutMin＋finalizer＋60×MaxSurgeryPerCycle)`，Preflight 印出 M。
- **殘餘風險**：門更嚴 → 85 檔領域首輪可能停在 BLOCKED 檔點名——這是設計目標（點名而非空轉）。

**上線順序**：D0 → D1（可單獨先上，直接對應管理者症狀）→ D2+D3+D5+D6 同一 commit（拆開會留下 M 倍中間態：批次各自遞增輪次、旗標被批 1 翻掉）→ D4。

---

## 4. 拒絕或延後的項目與理由

| 項目 | 處置 | 理由 |
|---|---|---|
| taskId／claimId 級 manifest 與 receipt、normalized claim hash | 延後 | 檔級＋範圍級已能證明「每筆落位」（D3 不變量）；claim 級只增加 3B parent 要抄的識別碼 |
| 外環對 auditor JSON 做 schema validation | 拒絕 | subagent 回報只回 parent、不進 stdout（ps-auditor.md:214-218；OutFile 從未被讀）；改用 part 檔不變量 |
| seed 規則抽 claim（parent 給 seed、auditor 自抽） | 拒絕 | parent／auditor 皆 `bash: false`（ps-deep-research.md:13、ps-auditor.md:12）算不出 hash；改用輪次 seed 後是無人能驗的 prose 計數；等於 auditor 自報選了哪條（L103 根因四） |
| 新 verdict／reason code（BUDGET_EXHAUSTED、PAGE_MISSING、CONTEXT_OVERFLOW 當判定） | 拒絕 | L69：每個判定字面要在值域／JSON／模板三處落點；溢出改由外環以「未稽核」列＋lint 違規表示 |
| `--print-logs` 或改 `--format json` 取觀測 | 拒絕 | stderr 污染尾 5 行與 mtime 心跳（:847-853、:1234），且 v1.17.15 不含子 session 事件；用 `opencode export` |
| 批次盲目 binary split、每批 30 分逾時 | 拒絕 | L102 :2631-2633；L48 沉默基線 30 分（:854-857）——30 分熔絲會殺健康批 |
| 外環直接 `opencode run --agent ps-auditor` 逐檔驅動 | 延後 | ps-auditor 是 `mode: subagent`＋`write: false`，是否可被 run 未實測；需薄包裝 primary agent；每檔一個 session 重拉四個 MCP 且撞 SOP-12 單通道（SOP.md:435-438）。列為 D3 殘餘風險的長期解，等 D0 數據 |
| relink 台帳／確定性 relink 波、成批查無第 3 筆短路 | 拒絕 | L79 路徑（lint→同圈手術）已封掉每輪重付（ps-doc-lint.ps1:837-940、ps-auto-loop.ps1:1281-1329）；「≥3 檔」是跨檔訊號、單檔子代理無從得知（ps-auditor.md:57-58）；PS 5.1 無 MCP 客戶端 |
| 90-audit-partial 檔放領域根目錄、每輪一檔追加 | 拒絕 | `^\d\d-` 命名會被 NN 防衛還原（:748-750、:795）；每輪一檔必超 150 行（L2）；改子目錄每批一檔、合併後刪 |
| 「不接受清單」中其實該做的最小修法 | **接受**：(1) 校正 opencode.json 宣告 limit 至 serving 真值（SOP-10）——不是換模型、不是調壓縮參數，是讓既有壓縮機制能觸發；(2) 精簡稽核 agent 作配套（issue 自己的實作 7） | L6 疑點未回填（applied.md:124-125）；ps-audit.md:3 一行改 agent |

---

## 5. 具體編輯清單（行為規格，不寫碼）

**`.opencode/agent/ps-auditor.md`**
- 任務 A 步驟 2（:80-99）：三管道各設頁數上限（search 2 頁、file_structure 1 批、semantic 2 頁），到頂→`FAIL(NOT_FOUND)`＋查法收據；刪「必須 offset 續翻到完」「逐批取完」改為「至上限」。
- 步驟 1（:66-72）：加「委派指定 Evidence 範圍（第 a~b 筆／第 a~b 條 Observation）時只驗該範圍」。
- 步驟 4（:119-127）：查無抽驗結果改放 JSON 新陣列 `negativeChecks`（不進 `evidence`）。
- 回報格式（:181-201）：加 `negativeChecks` 陣列（欄位同 evidence）。
- 硬規則（:206-209）：「回報筆數少於**委派範圍內** Evidence 筆數＝無效；未指定範圍＝全檔」。

**`.opencode/peoplesoft/progressive-source-retrieval.md`**
- §5.1 :218-219、:242：加「翻頁到全量以 §5 maxSearchResults 為上限；到頂仍無＝合格查無收據（附頁數）」，消除與 :207／:217 的矛盾。

**`.opencode/agent/ps-audit-orchestrator.md`（新）**
- frontmatter：`mode: primary`、tools 同 ps-deep-research.md:6-19。
- 內容：委派顆粒度與併發（ps-audit.md:19-27 原文）；manifest 讀法；任務 A／B／C／wiki 委派模板（:389-412 原文）；part 檔格式（audit-template 兩張表＋範圍後綴）；禁改清單（checklist／90-audit／輪次／旗標／NN）；就近映射規則（ps-deep-research.md:353-358）；硬規則（先做事後說話、寫檔禁圍欄、不得反問）。

**`.opencode/command/ps-audit-batch.md`（新）**、**`ps-audit-finalize.md`（新）**
- batch：第一動作 read `auto-loop-logs/<領域>/audit-manifest.txt`；不存在→read checklist 走全量（人工路徑）；只寫 `audit-parts/part-<批號>.md`（batch 0 加 `domain.md`）。
- finalize：read 合併後 90-audit.md、checklist.md、domain.md；Domain Gate 寫 D 列；語意節寫 `audit-parts/final-sections.md`；禁 read NN、禁改表格。

**`.opencode/command/ps-audit.md`**
- :3 agent 改 `ps-audit-orchestrator`；:8-10 刪「規模再大也照樣執行」保留反拒答句；註明「auto-loop 走 ps-audit-batch；本指令＝人工全量路徑」。

**`.opencode/agent/ps-deep-research.md`**
- :248-368 稽核模式：加「headless 由外環分批，見 ps-audit-batch；本節僅供人工 /ps-audit」；:259-261 加「claim 優先取 manifest 所給」；:325-329 歸檔所有權段加「A 列生成／輪次遞增／旗標翻轉在分批模式下同屬外環」。

**`.opencode/peoplesoft/report-templates/audit-template.md`**
- :26-28 詞彙表補 `FALSE_NEGATIVE`；明細表註記加「查無抽驗」類型列不計入記分卡三欄；記分卡註記加「未稽核（BLOCKED）列＝lint 違規」。

**`scripts/ps-doc-lint.ps1`**
- 新開關 `-EvidenceStats`：對每 NN 檔印 `EVIDENCE_ROWS：<檔>=<$evRealRows>`（複用 :641-648）、對 wiki 檔印 Observations 行數。
- 新開關 `-AuditPart <路徑> -NnSubset <清單>`：解析 part 檔（複用 :854-881、:69-86），輸出每檔合計／UUID 集合／reason 空欄數，供外環對帳。
- 90-audit 檢查（:796-816 附近）：記分卡列含「未稽核」→ `-CoverageOnly`／`-StrictAudit` 違規（訊息以 `90-audit.md` 開頭以歸 AUDIT_ONLY :1119）；`.gitignore` 加 `docs/ps-research/*/audit-parts/`。
- Task B claim 抽取：新開關 `-ClaimSample <檔> -N 5` 輸出前 N 條 CONFIRMED 行（兩形狀）；0 條→警告「行為邏輯節無可機械抽取的 CONFIRMED 行」。

**`scripts/ps-auto-loop.ps1`**
- 參數：`-AuditBatchSize`（6）、`-AuditEvidencePageSize`（15）、`-AuditBatchesPerCycle`（0＝全部）。
- Invoke-Opencode：回傳加 `FailureKind`（掃 out＋err regex，不看 exit）。
- 新函式：`New-AuditManifest`、`Test-AuditPart`、`Get/Save-AuditLedger`、`Invoke-AuditMerge`（表格＋A 列＋輪次＋旗標＋拼接 final-sections）。
- audit 分支（:1194-1198）：改為批次迴圈（每批前後快照／調帳／防衛；獨立 streak；拆批政策 D4）→ 收據齊 → 合併 → finalizer → `$auditAfter` → 歸檔 commit → D 熔絲。
- 畢業門（:1456-1467）：transition 重定義；auditStall／MaxNewDPerAudit 以整輪計；Preflight 印 M 與台帳 BLOCKED 數。
- 停機訊息：BLOCKED 檔點名＋列數＋「拆續篇」出路（L74 原則）。

**`scripts/ps-graduation.ps1`**：`GraduationGateVersion` 2→3。
**`scripts/ps-auto-all.ps1`:21-23、`SOP.md`:521-523**：最壞時長公式加 M 因子；SOP-10 加「宣告 limit > 真值＝壓縮永不先觸發、硬錯落在先撐滿的 session」一句；`lessons/applied.md` 新增 L106（本備忘取捨＋「反 cherry-pick 選擇權須在確定性層」「context 溢出先分端再修」）；`test-scenarios.md` 加 J7~J14；`ps-transfer-manifest.json` 加新檔。

---

## 6. 回歸測試情境（J 類，PowerShell 5.1 fixture 可跑，不需模型）

- **J7 manifest 生成**：3 NN → 1 批；85 NN、K=6 → 15 批＋batch 0；某檔 Evidence 40 列、頁 15 → 三個範圍 [1–15][16–30][31–40]；wiki 檔依 last_verified 取最舊 5；claim 兩形狀各抽到；0 條 → `CLAIMS_NONE` 且 lint 警告；旗標「待執行」→ 每批 manifest 皆帶全量註記。
- **J8 收據與續跑**：收據存在∧hash 同∧round 同∧policyHash 同 → 不進 manifest；任一不符 → 重驗；policyHash 因 ps-auditor.md 改動而變 → 全檔重驗；台帳存在但輪次未遞增（模擬 crash on merge 前）→ 下圈只補缺檔、不重跑已收據檔、輪次不變。
- **J9 part 不變量**：合計＝列數∧UUID⊆附錄 → 收據；少 1 列 → 無收據＋attempts 1；明細 UUID 不在附錄 → 無收據；reason 空 → 無收據；part 含 `</think>` → 該批無效；part 缺檔 → 批失敗；「查無抽驗」列不計入三欄。
- **J10 overflow 分類**：out 含「Context length exceeded」且 rc=0 → FailureKind=CONTEXT_OVERFLOW 記 log、errorStreak 不變；rc=1 同；無字樣 → generic；訊息含「無此字樣≠無溢出」。
- **J11 拆批政策**：K=6 批零收據＋overflow → 重排 K=3；部分收據 → 只重排無收據檔；單檔 40 列頁 15 失敗 → 頁 7 → 頁 3 → BLOCKED 點名檔名與列數；attempts≥2 → BLOCKED；BLOCKED 檔不阻擋後方檔（跳頭）。
- **J12 合併與順序**：兩範圍列加總為一列；PENDING_MANUAL-only 檔不生 A 列；A 序號連號；輪次 N+1 與旗標翻轉只在收據齊備後；finalizer 前 90-audit 表格節 hash＝finalizer 後（外環拼接不動表格）；final-sections 缺節 → 佔位「無」＋log；歸檔檔名 `r<N+1>`；D 熔絲計入 finalizer 新增 D 列。
- **J13 門**：缺任一收據 → transition FAIL 不畢業；記分卡「未稽核」列 → CoverageOnly／StrictAudit 違規、AUDIT_ONLY 分類；gateVersion 2 舊收據對 gate 3 無效；手動 lint 不擋（SOP-2）。
- **J14 lint 診斷開關**：`-EvidenceStats` 對含表頭／分隔列／裸 id 傾倒／`| — |` 列的附錄各算對；`-ClaimSample` 對粗體行與表格欄兩形狀各抽到，對 `###` 變體 0 條。
- **J15 現有回歸不退化**：J1~J6 全綠；手術迴圈與 surgery-ledger 行為不變（audit-ledger 獨立）；`audit-parts/` 對 lint／NN 防衛／contentHash 隱形（fixture 放檔驗零影響）。

---

## 7. 未決問題（需管理者在公司機提供）

1. **serving 端真實 context 上限**與 opencode.json 該 model 的 `limit.context`／`compaction.auto` 值（SOP-10 步驟 1~3）——決定硬錯是否為設定失配；D1 的頁數上限與 D2 的頁大小都要用這個數反推。
2. **停機那圈的指紋**：`*-audit.rc.txt` 值、err 是否含 context 字樣、auto-loop.log 停機行是哪種熔絲。
3. **出事委派的形狀**（`opencode export` parent session）：task input 含幾個 NN 路徑、是否 A＋B 同委派、是否帶 task_id、`metadata.sessionId`；子 session 的工具呼叫數、get_chunks_details 單次回傳字元數、search_chunks 翻了幾頁。
4. **單檔 Evidence 列數分布**（跑 lint `-EvidenceStats` 即得）：最大值、p95、以及 wiki entity 中 Observations 最多的前 5 檔——決定頁大小預設與 wiki 是否為「隨 85 檔成長」的真正子代理通道。
5. **索引重建狀態**：上輪 90-audit 有無「⚠ 本輪成批查無」行、ID_RELINK／NOT_FOUND 列數——決定 D1 上限數字對當前輪次的影響。
6. **每檔稽核時長**（out 檔委派時間戳）：校準 AuditTimeoutMin 是否改為每批上限、M 的合理值。
7. **OpenCode 版本**是否仍為 v1.17.15（ps-auto-loop.ps1:6）；`opencode run --agent <subagent 模式的 agent>` 是否被接受——決定第 4 節「外環直接驅動 auditor」何時可解封。
8. **L29 追記的壓縮假說**：該輪 session 紀錄有無壓縮事件（applied.md:563 待證）——決定 parent 側 D2 的優先級是否需要提前。