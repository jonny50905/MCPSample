# HANDOFF — PeopleSoft 知識庫分析框架（2026-09-02 交接）

> 給下一個 session（或明天的自己）。開發分支 `claude/peoplesoft-framework-handover-0u6b5g`，
> HEAD 見 `git log -1`。本檔在 manifest 範圍外，不需搬到公司機。

## 0. 一句話現況

大領域（67 個 NN 檔）的稽核在單一 session 內撞 context 上限（auditor 子代理、單檔 37 列即爆），
已改成**分批稽核**（L107）：外環 manifest → 每 session K 檔 → part 檔不變量發收據 → 收據齊備由外環
合併 90-audit.md。第一次實跑失敗在「模型 exit 0 卻不寫任何檔」（b0/b1/b2 零產出），已把批次指令
改掛回實證能寫檔的 `ps-deep-research`（80196ee），**待管理者搬檔重跑驗證**。職缺領域（第二領域）
政策定案 CUSTOM_FIRST、已入佇列，等大領域告一段落再開。

**接手追記（2026-09-02，第二個 session）**：manifest 在 80196ee 後未重生——c6dae63 新增的
`scripts/tests/test-auto-loop.ps1` 落在 fs-doctor 的搬運集合（scripts 全樹）內卻不在 manifest、且無 BOM。
已補 BOM、以 `ps-fs-doctor -WriteManifest` 重生為 55 檔；測試組在 pwsh 7.4.6（Linux）實跑
**全部情境 PASS**（98 個 Assert）。§1 步驟 1 已改為 5 檔＋核對欄。程式碼零改動。
其後前一 session 又推 ab1ee40（分批稽核 K 改 AIMD：每圈從 `-AuditBatchSize` 重新起算，圈內整批全收據
→K 翻倍至上限、零收據且有寫檔→對半；修「台帳持久＝K 永遠 1、65 檔跑 65 個 session」）——
本 session 已 pull、逐行讀過、測試組在 ab1ee40 上重跑全 PASS。**同一分支目前有兩個維護 session 在推**，
push 前先 `git pull`。

**追記（2026-09-03，oracleMCP 連線根因）**：管理者三個實驗定案 oracleMCP 連線是 server 全域單例
（誰 disconnect 全員斷線；L109、SOP-12 補述）。已改模型側契約：cookbook 生命週期「不得 disconnect、
connect 冪等」、三個 flow agent 同步、四個 subagent tools 表硬性 `"oracleMCP_disconnect": false`（ps-auditor 也在內）、會查 oracleMCP 的委派同時 ≤ 3 → ≤ 1（ps-audit-batch／ps-audit／
ps-deep-research／ps-audit-orchestrator）、`.gitignore` 補 audit-parts。**ps-auto-loop.ps1 一行未動**
（外環斷路器草案留解凍後，見 L109「有意不做」；立即緩解可加 `-AuditBatchesPerCycle 4`）。
搬運清單見 §1 步驟 1a。功能分支 `claude/issue-17-legacy-contract-phase1` 已 merge 本修正並另改
ps-contract-batch／ps-contract-verify。

## 1. 管理者下一步（按序）

1. 搬 5 檔（核對欄：行數＝編輯器總行數，允許 ±1 行尾差異）：

   | 檔案 | 新增／修改 | 行數 | 備註 |
   |---|---|---|---|
   | `scripts/ps-auto-loop.ps1` | 修改 | 2270 | 存 UTF-8 with BOM；含 ab1ee40 的 K AIMD |
   | `.opencode/command/ps-audit-batch.md` | 修改 | 108 | 掛 ps-deep-research（80196ee） |
   | `.opencode/agent/ps-audit-orchestrator.md` | 修改 | 138 | 備用、未掛載，但 manifest 要對 |
   | `scripts/tests/test-auto-loop.ps1` | 新增（新目錄 `scripts\tests\`） | 502 | 存 UTF-8 with BOM；公司機以 `pwsh -NoProfile -File` 跑 |
   | `scripts/ps-transfer-manifest.json` | 修改 | 336 | 最後搬；搬完跑 `ps-fs-doctor` 應報 55 檔一致（其印出的基準 commit 欄是 cc14f32＝另一 session 本機值，本 repo 無此 commit；雜湊內容對應 ab1ee40，已逐檔核對） |
1a. oracleMCP 根因修正（2026-09-03；若步驟 1 的 5 檔尚未搬，兩批一起搬；manifest 只搬最新）：

   | 檔案 | 新增／修改 | 行數 | 備註 |
   |---|---|---|---|
   | `.opencode/peoplesoft/oracle-query-cookbook.md` | 修改（生命週期＋平行規則） | 360 | |
   | `.opencode/agent/ps-ui-flow.md` | 修改（生命週期） | 115 | |
   | `.opencode/agent/ps-metadata-flow.md` | 修改（生命週期） | 102 | |
   | `.opencode/agent/ps-ae-flow.md` | 修改（生命週期） | 90 | |
   | `.opencode/agent/ps-auditor.md` | 修改（tools 硬性 deny＋規則） | 236 | |
   | `.opencode/command/ps-audit-batch.md` | 修改（oracleMCP 委派 ≤ 1） | 108 | |
   | `.opencode/command/ps-audit.md` | 修改（≤ 1） | 71 | |
   | `.opencode/agent/ps-deep-research.md` | 修改（三處 ≤ 1） | 476 | |
   | `.opencode/agent/ps-audit-orchestrator.md` | 修改（≤ 1） | 138 | |
   | `.opencode/peoplesoft/SOP.md` | 修改（只加 SOP-12 補述） | 597 | |
   | `.opencode/peoplesoft/lessons/applied.md` | 修改（只加 L109） | 2912 | |
   | `scripts/ps-transfer-manifest.json` | 修改 | 335 | 最後搬；fs-doctor 應報 55 檔一致（commit 欄＝產生時 HEAD，早一步屬預期） |

   `.gitignore`、`HANDOFF.md` 不在搬運集合；ps-auto-loop.ps1 本批未動。
2. 清殘留：`auto-loop-logs\<領域>\audit-ledger.json`、`docs\ps-research\<領域>\audit-parts\`。
3. 重跑 `ps-auto-loop.ps1 -Domain <領域> -Tier 2`。
4. **b0 結束時看 `audit-parts\domain.md` 有沒有出現**：有＝agent 層病因確認已修；沒有＝看 log
   新增的 `out>` 三行（模型最後說的話）——剩下兩種可能：模型印表沒 write（新版 stdout 回收會過）、
   或 `write` 被 opencode.json 的 permission `ask` 規則擋（建議 doom_loop ask→deny，見 L60 二次修正；
   但依 L60 實測 headless 的 ask 是**阻塞到逾時**，不會 exit 0——b0 實案 12 分鐘 exit 0，此假說先驗不成立，
   剩「agent 未被認到」（80196ee 已消滅變數）與「印表沒寫」（stdout 回收已接住）兩種）。
5. 成功後觀察：「稽核第 i 批…收據 x/y」累積、「稽核 BLOCKED」（若有，先試 `-AuditEvidencePageSize 5`）、
   「稽核輪次 N 合併完成」。首輪後 lint 若報「未稽核」列＝有檔 BLOCKED，不得畢業。
6. 大領域收尾：查無全量抽驗蓋章（旗標由外環翻）、待人工SQL 回填、畢業（GraduationGateVersion 3，
   舊收據作廢屬預期）。
7. 職缺領域：`ps-auto-loop.ps1 -Domain 職缺 -Tier 1`（一次只跑一個領域；oracleMCP 單通道）。

## 2. 本 session 落地的機制（L103～L107，全在 `.opencode/peoplesoft/lessons/applied.md`）

| 教訓 | 一句話 | 關鍵碼 |
|---|---|---|
| L103 | 守衛的三個素樸假設：指紋剝行號、[附錄] 形狀守衛、NN 檔＋歸檔檔破壞防衛、取項順序、[回灌] 陳舊壓下、不適用節、ChunkId 誤判修正、查無抽驗落後警告 | auto-loop `Get-OrderFingerprint`／`Invoke-NnDestructionGuard`；lint `[附錄]`／`-FixHeadings` |
| L104 | Domain Gate：任務 C 只是候選產生器，DOMAIN_ROOT 才准成 D；`-MaxNewDPerAudit` 熔絲 | auditor 結構化候選；deep-research 稽核模式步驟 3 |
| L105 | 歸檔所有權外環化：模型只打勾，`Invoke-ChecklistArchiveCommit` 唯一歸檔者；`Invoke-ArchiveDedup` 降為 crash recovery | auto-loop；ps-audit／deep-research 歸檔段 |
| L106 | context 溢出先分端再修：auditor 二次定位頁數上限、`FailureKind` 標籤、lint `-EvidenceStats` | ps-auditor；progressive-source-retrieval §5.1 |
| L107 | 稽核分批化：manifest／檔級收據／part 不變量／外環合併／溢出＝容量事件（K 對半、頁對半、BLOCKED→未稽核→lint 違規） | auto-loop 分批稽核塊（`Invoke-AuditRound` 等）；`ps-audit-batch` 指令 |

外部協作者 issue #12／#13／#22 皆已逐條對碼驗證並回帖（成立處落地、分歧處註明理由）。
分批稽核的完整設計備忘：`docs/design/audit-batching-decision-memo.md`。

## 3. 操作知識（不看對話也要知道的）

- **搬運**：公司網路封鎖 git，人工從 GitHub Raw 複製；`.ps1` 存 UTF-8 with BOM；搬完跑
  `scripts/ps-fs-doctor.ps1` 做 manifest 雜湊對照；維護端每批 push 前 `-WriteManifest`（公司機不跑）。
- **研究產出 `docs/ps-research/**` 是公司機密**：只進內部 git，本 repo 不含。本機 `opencode.json`
  含公司主機名，不進 repo。
- **台帳與其刪除語義**（都在 `auto-loop-logs\<領域>\`）：
  `surgery-ledger.json`（手術工單 attempts/BLOCKED，處理完刪＝放行）、
  `audit-ledger.json`（分批稽核檔級收據，輪次合併後自動歸檔為 `audit-r<N>.done.json`；系統性故障後刪＝重置）、
  `reconcile-restored.txt`（復活斷路器）。`docs\ps-research\<領域>\audit-parts\` 是分批稽核的暫存，
  合併後自刪。
- **主要參數**（ps-auto-loop.ps1）：`-Tier 1|2`、`-AuditBatchSize 6`（每圈起算值＝AIMD 上限，ab1ee40）、`-AuditEvidencePageSize 10`
  （唯一尚未實測校準的參數；實測 Evidence 列數最大 37／p95 26／中位 12）、`-AuditBatchesPerCycle 0`、
  `-AuditBatchTimeoutMin 60`、`-MaxNewDPerAudit 10`、`-SurgeryBatchSize 7`、`-MaxSurgeryPerCycle 3`。
- **log 訊號詞彙**：「排水圈」「本批解決 N 筆（身分尺）」「手術停滯 BLOCKED」「破壞防衛」
  「歸檔 commit（外環）」「跨檔同文去重」「容量事件：CONTEXT_OVERFLOW」「批次 K 減半為／升為」「稽核第 i 批…收據 x/y」
  「稽核 BLOCKED」「稽核輪次 N 合併完成」「本輪稽核新增 D 項 N 筆 > 上限」。
- **cmd 傳遞限制**：session prompt 禁半形雙引號與 `> < & | % ^`；findstr 對 UTF-8 中文不可靠，
  一律 `powershell Get-Content -Encoding UTF8`。
- **測試**：`pwsh -File scripts/tests/test-auto-loop.ps1`（26 個真實函式 AST 抽取、63+ 判定，
  含 lint fixture）。改 auto-loop／lint 後必跑。

## 4. 未決與風險

- 分批稽核「模型不寫檔」的真因未定（agent 未被認到／印表沒寫／write 被 ask 擋）——重跑一次即定案。
- `-AuditEvidencePageSize` 未校準；serving 端 context 真值不可得，靠自校準（溢出對半）。
- Domain Gate 只擋新增，存量 67 檔內的依附／域外物件不回溯清洗（人工 scope review 可選）。
- 收據證明「parent 寫的數字通過不變量」，不證明「子代理真跑過」——與現況同，未新增風險。
- 文件漂移（下一波有其他改動時一併搬，不為此單獨搬大檔）：`ps-deep-research.md:251` 仍寫
  「ps-audit-batch（agent ps-audit-orchestrator）」，80196ee 後實掛 ps-deep-research（僅註解性文字，
  該節對批次指令本就不適用）；`SOP.md` 未收 L104～L107 的操作知識（台帳刪除語義、分批稽核參數、
  log 訊號詞只在本檔 §3，而本檔不搬公司機）——建議下一波以「只加不刪」補一節進 SOP。
- 舊掛起：已畢業領域貼 U 項工單；PENDING_MANUAL 人工 SQL（SOP-2 第 4 階）；`-GitCommit` 觀察期
  結束後恢復；畢業後端到端測試；opencode.json 的 doom_loop ask→deny。
