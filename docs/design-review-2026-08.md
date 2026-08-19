# 對抗式設計審查報告（2026-08）

> 分支 `claude/peoplesoft-design-review-0u6b5g`／基準 `42b1150`。**本報告只診斷，未修改任何規則或程式。**

## 方法

```text
Find    九個獨立視角平行盲掃（腳本交叉／lint 深掘／工具權限／agent 規則／
        SOP 全掃／證據契約端到端／實測回歸／文件對現實／死鎖與門—修復配對）
        → 81 筆原始指控（互不知情、未交叉查證）
Dedup   語意去重（分批＋跨批）→ 62 筆
Verify  每筆配一個「懷疑者」，**親自開檔讀原文**後裁決
        CONFIRMED 需附自己讀到的引句；REFUTED 需附能化解矛盾的原文
```

**結果：CONFIRMED 51／REFUTED 11／PLAUSIBLE 0**
（原始 81 → 去重 62 → 通過驗證 51；**11 筆指控被駁回**，其中包含原判 fatal 的一筆）

嚴重度分布：**fatal 1／major 20／minor 30**

---

## 致命（fatal）　1 筆

### F1. 「待人工SQL」合法終止出口在稽核端零定義：auditor 依字面必判 FAIL(WRONG_KIND)／UNVERIFIABLE，回灌規則無條件開 A 項——tier 2 變成 research↔audit 乒乓的 A 項永動機，熔絲全數失效、只能撞 MaxCycles，停機訊息不指向真正的人工動作

**涉及**：.opencode/agent/ps-auditor.md, .opencode/agent/ps-deep-research.md, .opencode/command/ps-audit.md, scripts/ps-doc-lint.ps1, scripts/ps-auto-loop.ps1

**指控**：【原批內已合併 2 筆重複視角，皆 fatal 規則互撞】寫入端三方（lint、模板、deep-research）都把「待人工SQL」定義為合法終止出口（lint 755-756「該筆輸出「舊值 → 待人工SQL」收據並停止該筆…不得換工具重試」；ps-doc-lint.ps1:611-614「合法的終止出口…不算違規」；function-detail-template.md:68「查不到時的合法出口」），但稽核鏈完全不認識它：ps-auditor.md、ps-audit.md、audit-template.md 對「待人工SQL」零命中（全 repo grep 確認），判定詞彙只有 PASS/FAIL/UNVERIFIABLE、無任何 pending/申報類判定。auditor 任務 A 要求逐筆判定（ps-auditor.md:109），SQL 型規則（91-96 行）明文「sql 欄非 SELECT → FAIL(WRONG_KIND)」——「待人工SQL」非 SELECT，照字面必判 FAIL；即使寬判 UNVERIFIABLE，回灌規則（ps-audit.md:31-34、ps-deep-research.md:184-187）是「任何非 PASS／VERIFIED 的判定（FAIL／DISPUTED／UNVERIFIABLE…一律算）」→ 每輪必開 A 項。結果：凡是真的需要管理者自跑 SQL 的合法待辦列，tier 2 迴圈就變成 research（勾掉 A 項）↔ audit（再回灌）的乒乓——未勾數 1→0 有遞減所以 noProgress 熔絲不觸發、每輪回灌 ≥1 所以 auditStall 熔絲不觸發——只剩 MaxCycles=20 圈上限（每圈 audit 120 分＋research 60 分），停機理由「圈數上限」完全不指向「SOP-2 升級梯第 4 階管理者自跑 SQL 回填」這個唯一正解。夜間批次（SOP-17）下該領域無收據，每晚重燒。這正是 L56 自己的原則「規則寫在模型看不到的地方，等於沒有規則」的現行違反。

**驗證**：親自開檔逐條核對，指控的每一個環節都在檔案裡成立，且沒有任何檔案提供豁免。(1) 寫入端三方確實把「待人工SQL」定為合法終止出口（lint 判定不算違規只發警告、模板明寫「查不到時的合法出口」、ps-deep-research 明寫「查不到時的合法出口（L56）」）。(2) 稽核端零定義：我對 ps-auditor.md、ps-audit.md、audit-template.md 三檔各自全檔讀完＋grep，「待人工SQL」零命中（全 repo 只命中 scripts/ps-doc-lint.ps1、ps-auto-loop.ps1、ps-deep-research.md、function-detail-template.md、lessons/applied.md）。ps-auditor.md 判定詞彙只有 PASS/FAIL/UNVERIFIABLE，且第 3 條對「sql 欄非 SELECT」寫死 FAIL(WRONG_KIND)、明文「不執行、也不判 UNVERIFIABLE」；若改當 CHUNK 型看，第 2 條末「其他樣式 → FAIL(FABRICATED)」更糟——任一讀法都是非 PASS。(3) 回灌規則無條件：ps-audit.md:31-32 與 ps-deep-research.md:184-185 都是「任何非 PASS／VERIFIED 的判定…一律算」，audit-template.md:53-54 還把「非 PASS ≥1 而 checklist 無 A 行＝流程錯誤」寫成硬約束，等於強制每輪開 A 項。(4) 熔絲確實全失效：ps-auto-loop.ps1:626-628 只要 Unticked>0 就把 auditStall 歸零；:663 tier-2 進度尺是 `$after.Unticked -ge $before.Unticked`，research 把 1→0 即判有進度、:673 noProgress 歸零。剩下唯一停機是 :425 預設 stopReason「圈數上限（20）」，而 MaxCycles=20、Audit…

**原文佐證**：
```
【稽核端零定義（我自己 grep＋全檔讀）】grep '待人工SQL' 於 .opencode/agent/ps-auditor.md、.opencode/command/ps-audit.md、.opencode/peoplesoft/report-templates/audit-template.md 三檔皆 0 命中；全 repo 命中僅 scripts/ps-doc-lint.ps1、scripts/ps-auto-loop.ps1、.opencode/agent/ps-deep-research.md、.opencode/peoplesoft/report-templates/function-detail-template.md、.opencode/peoplesoft/lessons/applied.md。

【auditor 必判非 PASS】/home/user/MCPSample/.opencode/agent/ps-auditor.md:94-96「`sql` 欄**非 SELECT**（如 AE 的 UPDATE、程式內語句）→ `FAIL(WRONG_KIND)`（程式碼語句應改用 CHUNK 證據）——**不執行**、也不判 UNVERIFIABLE。」
ps-auditor.md:90「其他樣式 → `FAIL(FABRICATED)`。」
ps-auditor.md:109「每筆判 `PASS` / `FAIL(原因)` / `UNVERIFIABLE(工具不可用/逾時)`。」
（對照：同檔 :35-38 已存在一個「免解引用」先例——「sources 含 `human:<日期>`…判 `PASS(HUMAN_VERIFIED)`」——證明機制做得到，只是沒給待人工SQL。）

【回灌無條件】/home/user/MCPSample/.opencode/command/ps-audit.md:31-34「任何非 PASS／VERIFIED 判定（FAIL／DISPUTED／自創詞一律算）與遺漏候選，**以檔為單位彙整、一檔一行**加進 `checklist.md`…」
/home/user/MCPSample/.opencode/agent/ps-deep-research.md:184-186「回灌對象＝**任何非 PASS／VERIFIED 的判定**（FAIL／DISPUTED／UNVERIFIABLE／自創詞一律算）與遺漏候選」
/home/user/MCPSample/.opencode/peoplesoft/repor…
```

**建議最小修法**：在 ps-auditor.md 任務 A 加一條與既有 PASS(HUMAN_VERIFIED)（:35-38）同形的出口：「機器參照欄為『待人工SQL』→ 判 `PASS(PENDING_HUMAN_SQL)`，不解引用、不判 FAIL(WRONG_KIND)／UNVERIFIABLE，該筆一句寫進 gaps（待管理者照 SOP-2 升級梯第 4 階自跑 SQL 回填）」，並同步在 ps-audit.md:31-34 與 ps-deep-research.md:184-186 的回灌規則明文豁免「PASS(PENDING_HUMAN_SQL) 不回灌、不開 A 項」、audit-template.md 詞彙表與明細表加該詞（記為「人工待辦」列而非非過判定）。另在 ps-auto-loop.ps1 畢業／停機訊息把該類筆數列出，讓停機理由指向人工動作而非「圈數上限」。


## 重大（major）　20 筆

### M1. function-detail 模板的 SQL 證據示範列（SELECT 放位置欄、keyRows 放機器參照欄）正是 lint 判定的「欄位錯放」——照模板寫必被點名進 [欄位] 手術工單，且與模板自己三行後的註解、lint 的修法規格、L57 裁定全部相反

**涉及**：.opencode/peoplesoft/report-templates/function-detail-template.md, scripts/ps-doc-lint.ps1, .opencode/agent/ps-deep-research.md, .opencode/peoplesoft/lessons/applied.md, scripts/ps-auto-loop.ps1

**指控**：【跨批合併：原批內已合併的 4 筆（設計矛盾／template-vs-lint／文件與程式不符／doc-code-mismatch）＋另一批的 major 版「模板示範列違反 L57 裁定」共 6 個視角，同一根本矛盾】function-detail-template.md:62 的 Evidence 標準範例第 2 列「| 2 | SQL：`SELECT … FROM PSXLATITEM …` | 選項清單 | keyRows：E=免役… |」把 SELECT 放「位置」欄、keyRows 放「機器參照」欄；ps-doc-lint.ps1 的 L55/L57 逐列判定對這種列（四欄制、整列有 SELECT、但最後一欄非 UUID/SELECT/待人工SQL）必記 $misplacedRefRows → 警告點名＋開 [欄位] 型手術工單，工單修法（733 行「SQL 型：位置欄＝表名與鍵值，機器參照欄＝SQL：SELECT … FROM …」、753 行「機器參照欄改寫成『SQL：可重跑的 SELECT』，說明欄放 keyRows」）要求把欄位對調成與模板範例完全相反的樣子。模板列 62 同時違反模板自己 65-68 行的註解（機器參照欄只准三種：完整 36 字元 ChunkId／可重跑 SELECT／待人工SQL，keyRows 不在其中）與 ps-deep-research.md:133-134 的同一條規則。更根本的過期宣稱：L57（applied.md:1192-1199）已把「機器參照『OracleMCP』＋位置欄放 SQL」定性為欄位寫反、明定「機器參照放 SQL（正確）」，並歸因「模型對欄位語意的掌握不穩」——但模板的標準範例親自教的正是被判錯的那型，小模型看 worked example 學格式，框架卻把 example 教出來的結果記成模型缺陷。自動化路徑使其永久化：只要同域存在任何其他違規（lint exit 1），手術迴圈就反覆餵「把模板教的寫法對調回來」的工單，下一輪產文又照模板寫回來——產文/開刀永久往復。

**驗證**：我逐檔打開並逐行核對，指控的每一個具體引用都對得上，且我用等價正規式重跑了 lint 的判定邏輯，結果與指控一致。

(1) 模板確實把兩欄寫反。function-detail-template.md:55 表頭是「| # | 位置 | 說明 | 機器參照 |」，:62 的第 2 列把 `SELECT … FROM PSXLATITEM …` 放在**位置欄**、把 `keyRows：E=免役…` 放在**機器參照欄**。這一列不在任何 HTML 註解內（前一個註解在 :59-61 已以 `-->` 收尾），也沒有任何「錯誤示範」標記——它就是模板要模型照抄的樣板列，而 ps-deep-research.md:34 明文規定 NN 檔照本模板寫。

(2) 它違反同檔三行後自己的規則。:65-68「機器參照欄只准放三種東西之一（lint 逐列檢查，L55）：(a) 完整 36 字元 ChunkId (b) 可重跑的 SELECT … FROM … (c) 待人工SQL」——`keyRows：E=免役…` 三者皆非。ps-deep-research.md:133-134 是同一條規則的另一份複本。

(3) lint 真的會點名。我照 ps-doc-lint.ps1:363-365 的三個正規式與 :398-418 的判定，把 :62 這一列逐字餵進等價實作：`isEvHeader=False`（該列不含「機器參照」四字）→ okSelect=True → 四欄制（split '|' 去空白後 cells=4）→ lastCell=` keyRows：E=免役… ` 三個 -notmatch 全成立 → `$misplacedRefRows += ...`。後果是 :618 的 WARN 點名，以及 :681/:704 的 `"$i. [欄位] ${fn}：... 列欄位錯放"` 工單——:681 的條件只看 `$misplacedRefRows.Count -gt 0`，與 exit code 無關，CoverageOnly（:650-658 只降級 `$violati…

**原文佐證**：
```
【模板自打規則】
/home/user/MCPSample/.opencode/peoplesoft/report-templates/function-detail-template.md:55
`| # | 位置 | 說明 | 機器參照 |`
同檔:62
`| 2 | SQL：\`SELECT … FROM PSXLATITEM …\` | 選項清單 | keyRows：E=免役… |`
同檔:65-68
`<!-- 機器參照欄只准放三種東西之一（lint 逐列檢查，L55）：`
`     (a) 完整 36 字元 ChunkId`
`     (b) 可重跑的 SELECT … FROM …`
`     (c) 待人工SQL ← **查不到時的合法出口**`

【偵測邏輯（我自己核對過的行）】
/home/user/MCPSample/scripts/ps-doc-lint.ps1:364
`$realSelect = '(?i)\bSELECT\b[\s\S]{0,400}?\bFROM\b'`
同檔:397
`$isEvHeader = ($line -match '機器參照') -or ($line -match '^\|\s*編號\s*\|')`
同檔:411-415
`if ($cells.Count -ge 4) {`
`    $lastCell = $cells[$cells.Count - 1]`
`    if ($lastCell -notmatch $fullUuid -and $lastCell -notmatch $realSelect -and`
`        $lastCell -notmatch $pendingMark) {`
`        $misplacedRefRows += "${name}:${evLineNo}"`
（我用等價正規式對 :62 原文重跑：isEvHeader=False、okSelect=True、cells=4、lastCell=" keyRows：E=免役… " → misplaced=True）

【工單與修法：與模板相反】
同檔:681
`if (($truncatedIds.Count + $missingIds.Count + $leakDelegable.Count + $misplacedRefRows.Count) -gt 0) {`
同檔:704
`Write-Host "$i. [欄位] ${fn}：$($lns.Count) 列欄位錯放（行 $($lns -…
```

**建議最小修法**：改 /home/user/MCPSample/.opencode/peoplesoft/report-templates/function-detail-template.md:62 這一列，照 ps-doc-lint.ps1:733/753 的欄位語意三欄對調成：`| 2 | `PSXLATITEM`（FIELDNAME='MIL_STATUS'） | keyRows：E=免役／S=服役中 | SQL：`SELECT FIELDVALUE, XLATLONGNAME FROM PSXLATITEM WHERE FIELDNAME='MIL_STATUS'` |`（位置欄＝表名與鍵值、說明欄＝keyRows、機器參照欄＝可重跑 SELECT）；同時在 :65-68 註解末尾補一句「SQL 型範例見上列第 2 列：SELECT 放機器參照欄、keyRows 放說明欄」，讓模板的 worked example 與 lint 的 [欄位] 修法規格一致。


### M2. Tier 1 的 auditStall 活鎖熔絲在其設計場景中永遠不觸發，且「回灌 N 項」log 為假陳述

**涉及**：scripts/ps-auto-loop.ps1

**指控**：第七熔絲之一「audit 相位連續 2 圈零回灌未畢業（活鎖熔斷）」（ps-auto-loop.ps1:24）在 tier 1 實質死路：熔絲重置條件用「$after.Unticked -gt 0」（626-628 行），但 tier 1 的相位判定不看未勾數（449-452 行）、且 tier 1 明文允許帶著未勾項畢業（607 行「未勾 N 項屬補強類」，444 行還引實案「一輪就回灌 11 項」）。因此 tier 1 audit 圈只要存在任何既有補強項（＝tier 1 的常態），即使本圈零回灌、被 transition 門連擋 20 圈，auditStall 每圈都被重置為 0，熔絲永不觸發，只能靠 MaxCycles（最壞 20×300 分≈100 小時）收場——這正是 631-633 行自述『這種圈沒有自動修復管道…連續發生只會空轉活鎖，熔斷進人工』要防的場景，也違反框架自己的 L53（擋門違規必須配修復路徑或人工出口，否則自動迴圈活鎖）。附帶：627 行 log「audit 回灌 $($after.Unticked) 項」在 tier 1 是假的——印的是當下未勾總數，不是本圈回灌數。

**驗證**：親自讀完 ps-auto-loop.ps1 全部相關段落，指控的每一句都對得上，而且我找到審查者沒抓到的根因：熔絲重置條件與那行 log 都是照 **tier 2 的進入不變式**寫的，tier 1 打破了該不變式卻沒有同步改。

(1) 重置量錯了。Get-ChecklistState 的 Unticked 是把 checklist.md 裡所有 `^- [ ]` 行數出來的**當下存量**（132/138 行），不是本圈增量。tier 2 只有在 `$before.Unticked -eq 0` 時才進 audit（455 行），所以在 tier 2 裡「$after.Unticked -gt 0」⟺「本圈真的回灌了東西」——重置條件與 627 行的「回灌 N 項」在 tier 2 都是正確的。tier 1 的相位完全不看未勾數（449-452 行），進 audit 時未勾數可以是任意正數，同一個表達式就退化成「checklist 裡還有沒有任何未勾項」，與本圈有無進度無關。

(2) 在 tier 1 這個條件恆真。607 行明文允許帶著未勾項畢業、682 行再講一次「未勾 N 項屬補強類」、443 行引實案「一輪就回灌 11 項」、598-599 行 baseOk 對 tier 1 直接 $true——存量未勾>0 是 tier 1 的**設計常態**。⇒ 每圈重置 ⇒ auditStall 永遠到不了 2 ⇒ 熔絲死。

(3) 被擋的 audit 圈在 tier 1 真的可達且會自我重複。gate 是 session∧transition∧baseOk(恆真)∧validation。若 coverage 仍過但 transition FAIL（模型沒 bump 稽核輪次或 90-audit.md hash 未變，569-571 行），下一圈 coverBefore 仍 exit 0 → 又進 audit → 無限重跑。這正是 631-633 行自述「被門擋下（transition／strict／session）…沒有自動修復管道…連續發生只會空轉活鎖」要防的…

**原文佐證**：
```
全部引自我自己開檔讀到的原文：

/home/user/MCPSample/scripts/ps-auto-loop.ps1:24
`#   audit 相位連續 2 圈零回灌未畢業（活鎖熔斷）／圈數上限`

熔絲量測的是「存量」不是「增量」——
/home/user/MCPSample/scripts/ps-auto-loop.ps1:132,138
`    $unticked = @($lines | Where-Object { $_ -match '^\s*-\s*\[ \]' }).Count`
`    return @{ Exists = $true; Unticked = $unticked; Ticked = $ticked; Round = $round }`

關鍵反證（審查者沒抓到的根因）：tier 2 進 audit 的前提就是未勾=0，所以同一條件在 tier 2 才等價於「本圈回灌」——
/home/user/MCPSample/scripts/ps-auto-loop.ps1:454-456
`        else {`
`            $goResearch = ($before.Unticked -gt 0)`
`        }`

tier 1 相位完全不看未勾數——
/home/user/MCPSample/scripts/ps-auto-loop.ps1:449-452
`        if ($Tier -eq 1) {`
`            $coverBefore = Invoke-Lint -Coverage`
`            $goResearch = ($coverBefore.Exit -ne 0)`
`            Write-Log "COVERAGE(圈前) exit=$($coverBefore.Exit)（0=缺料已清）→ 相位 $(if ($goResearch) { 'research' } else { 'audit' })"`

tier 1 明文允許帶未勾項畢業（＝未勾>0 是常態）——
/home/user/MCPSample/scripts/ps-auto-loop.ps1:597-599
`        # 基礎條件：tier 1 不看未勾數與基礎 lint（那是美工；補強項留給 tier 2）`
`        $baseOk = $true`
`        if ($Tier -eq 2) { $baseOk = ($af…
```

**建議最小修法**：改 ps-auto-loop.ps1:626-628，把存量改成增量（$before 已在 428 行取得，同圈可用）：`$reflow = $after.Unticked - $before.Unticked; if ($reflow -gt 0) { Write-Log "audit 回灌 $reflow 項（未勾 $($before.Unticked)→$($after.Unticked)），續跑"; $auditStall = 0 }`——一併修好死熔絲與假 log。若要對「勾掉 X 又回灌 X」的淨零圈也保守熔斷，把 else 分支的條件再與 transitionOk 取聯集（`if ($reflow -le 0 -or -not $transitionOk) { $auditStall++ }`）；同時把 641 行的 `$noProgress = 0` 移進回灌成立的分支，別讓被擋的 audit 圈連帶重置無進度熔絲。


### M3. ps-auto-loop 對領域路徑全面使用萬用字元敏感的 Test-Path/-Path/Get-FileHash -Path，違反框架自宣的 PS5.1 陷阱紀律；佇列 preflight 又不擋「[」「]」

**涉及**：scripts/ps-auto-loop.ps1, scripts/ps-auto-all.ps1, scripts/ps-doc-lint.ps1, scripts/ps-graduation.ps1

**指控**：框架明知 Test-Path -Path／-Filter 有萬用字元陷阱（ps-graduation.ps1:9-10 明文寫「FileSystem provider 的 -Filter 不支援 [0-9] 字元類，會靜默匹配失敗」，ps-doc-lint 與 ps-graduation 全面用 -LiteralPath），但 ps-auto-loop 對同一批領域衍生路徑一律用萬用字元敏感版本：Get-ChecklistState 的 Test-Path/Get-Content（128、131 行）、Get-AuditTransition 的 Test-Path 與 Get-FileHash -Path（150、157-158 行）、Get-ItemTotal 的 Get-ChildItem -Path（171 行）、圈前基準 Test-Path（432 行）、Invoke-Lint 的 Test-Path（333 行）、Test-FsConsistency（188、197-198 行）。而 ps-auto-all 的佇列 preflight 黑名單（66 行）擋了 <>:"/\|?*&%^` 卻沒擋「[」「]」——含中括號的領域名可以合法進佇列，然後在 auto-loop 端靜默匹配失敗。

**驗證**：親自開檔逐行核對，指控的每一個引用行都逐字屬實，且框架的「自宣鐵律」比審查者引用的更硬——審查者只找到 ps-graduation.ps1:9-10（那其實是 -Filter 不支援 [0-9] 字元類，是相鄰但不同的陷阱），我另外查到兩處直指本案的明文硬規定：README.md「環境紀律」段開宗明義寫「這些不是建議，是踩過坑之後的硬規定」，其下第 254-255 行即「路徑一律 -LiteralPath」；applied.md L39 更是同一個 bug 的事故報告，第 743 行白紙黑字點名「路徑或領域名含 [ ] 時，存在的檔案照樣判不存在」。

矛盾成立且範圍比指控更大。我 grep 出 ps-auto-loop.ps1 共 16 處對領域衍生路徑使用萬用字元敏感呼叫（指控列了 9 處，漏掉 82、174、189、198、203 等），而同一檔案裡對「非領域衍生」的路徑卻用了 9 次 -LiteralPath（如 111 行檢查 ps-graduation.ps1），證明作者知道這個參數存在、只是沒套用到領域路徑上——這是檔案內部的自我不一致，不是不知情。

對照組也精確成立：ps-doc-lint.ps1 的領域衍生 $dir（103 行 Join-Path $researchRoot $Domain）在 107 行確實用 -LiteralPath；lint 殘存的非 literal 呼叫（513、519 行）打的是 $wikiDir——512 行寫死為 "docs/ps-research/wiki"，不含中繼字元，其餘（211、269、523、549）是列舉後的 $_.FullName。也就是說 lint 對「使用者可控的領域路徑」百分之百守紀律，auto-loop 百分之零。

佇列缺口比指控說的更嚴重：不只 ps-auto-all.ps1:66 的黑名單漏了 [ ]，連 research-domains.txt:8-10 的人工文件也逐項列舉禁用字元卻同樣沒有 [ ]——等於中括號領域名是被文件「明文允許」的合法輸入，然後在 auto-loop 端靜默失…

**原文佐證**：
```
【框架自宣鐵律——我讀到的原文，比指控引用的更直接】
/home/user/MCPSample/README.md:248「這些不是建議，是踩過坑之後的硬規定（每一條在 `applied.md` 都有對應教訓）：」
/home/user/MCPSample/README.md:254-255「- **路徑一律 `-LiteralPath`**：`Test-Path -Path` 把路徑當萬用字元，會產生「看得到、程式找不到」的假缺檔。」
/home/user/MCPSample/.opencode/peoplesoft/lessons/applied.md:742-744「根因（兩個都修）：(1) **`Test-Path -Path` 會把路徑當萬用字元樣式解析**——路徑或領域名含 `[` `]` 時，存在的檔案照樣判不存在；doctor 用 `[IO.File]::Exists()`（字面）故找得到，兩者結論相反。」
/home/user/MCPSample/.opencode/peoplesoft/lessons/applied.md:753-754「原則：**路徑一律 LiteralPath**——PowerShell 的 `-Path` 是樣式不是路徑」
/home/user/MCPSample/.opencode/peoplesoft/lessons/applied.md:748-749「落點：機械化——(1) lint 全面改 `-LiteralPath`／`Get-Content -LiteralPath`（11 處）」（＝落點只寫 lint，auto-loop 從未納入，無任何明文豁免）

【違規現場——ps-auto-loop.ps1，全部領域衍生路徑】
/home/user/MCPSample/scripts/ps-auto-loop.ps1:79「$dir = Join-Path $root (Join-Path "docs/ps-research" $Domain)」
:82「New-Item -ItemType Directory -Path $logRoot -Force | Out-Null」
:128「    if (-not (Test-Path $clPath)) {」
:131「    $lines = Get-Content $clPath -Encoding UTF8」
:150「    if (Test-Path $clPath) {」
:157-158「    if (Test-Path $auditPath)…
```

**建議最小修法**：兩處機械修補，缺一不可（只補 preflight 擋不住直接呼叫 ps-auto-loop 的路徑）：

(1) ps-auto-loop.ps1 — 把全部 16 處領域衍生路徑改成字面版：128/150/157/170/188/197/203/333/432 行的 `Test-Path X` → `Test-Path -LiteralPath X`；131/151/174 行 `Get-Content X` → `Get-Content -LiteralPath X`；158 行 `Get-FileHash -Path` → `Get-FileHash -LiteralPath`；171/198 行 `Get-ChildItem -Path $dir -Filter …` → `Get-ChildItem -LiteralPath $dir -Filter …`；189 行 `Get-Item $clPath` → `Get-Item -LiteralPath $clPath`。注意 82 行的 `New-Item -ItemType Directory -Path $logRoot`：PS 5.1 的 New-Item **沒有** -LiteralPath 參數，改用 `[System.IO.Directory]::CreateDirectory($logRoot) | O…


### M4. wiki 共用層的空檔／frontmatter／status 檢查是『違規』不是警告：跨領域鎖死所有領域的畢業門，且無工單、無人工出口——同時與 lint 檔頭自宣的隔離原則、SOP-2 的『wiki 類警告』分類矛盾

**涉及**：scripts/ps-doc-lint.ps1, .opencode/peoplesoft/SOP.md, scripts/ps-auto-loop.ps1, scripts/ps-auto-all.ps1

**指控**：【跨批合併：原批內已合併 2 筆，另一批的「wiki 空檔違規跨領域鎖死畢業門」為同一根本矛盾的子集】lint 檔頭宣示「wiki 類警告任何模式都不升級（跨領域共用層，會讓 A 領域的畢業被 B 領域的斷鏈鎖死）」、SOP-2 也把「frontmatter 缺欄」列在『wiki 類警告』清單下；但實作裡 wiki 空檔（0 byte）、frontmatter 缺 key、status 值非法三項直接進 $violations：wiki『空檔』訊息不在 polish 白名單＝缺料類，連每個領域的 tier 1 CoverageOnly 都一起 FAIL；frontmatter／status 雖落在 polish 白名單（tier 1 放行），卻擋所有領域的 tier 2（「基礎 lint 全綠」是 tier 2 門）。任一領域某次 crash（如 research session 被強殺、entity 檔寫到一半）留下的 0-byte wiki 檔，會讓整個批次每個領域 coverage FAIL → 相位鎖死在 research（research 只消化自己領域的 checklist，不會碰別領域的 wiki 檔）→ 缺料違規數不動 → 連續 2 圈無進度熔斷 → NEEDS_ATTENTION；ps-auto-all 連續 3 個領域失敗即停批並誤導為「疑似環境級問題（MCP／模型服務／DB）」。這些 wiki 違規完全不進手術工單（工單四類來源只掃領域目錄），也不進人工處理清單，lint 對空檔給的唯一指引只有「疑似寫入中斷」——跨領域、無管道、擋門三者齊備，正是 L53「每一條會擋門的違規，都必須配一條可執行的修復路徑，或一個明確的人工出口；兩者皆無的檢查不是防線，是死結」的現行違反。附帶：SOP-2 把 frontmatter 缺欄歸為「警告」與 lint 實判違規不符，且只給了斷鏈孤兒與 stale 的處置、對 frontmatter 缺欄連修復指引都沒有，照 SOP 判讀的人會低估其擋門效果。

**驗證**：我逐檔開啟核對，指控引用的每一行都存在且語意如其所述，無誤讀。實測鏈條完整成立：

1) 跨領域鎖死為真。ps-doc-lint.ps1:511-513 自己聲明 wiki/ 是「跨領域共用層」，且掃描路徑是固定的 docs/ps-research/wiki（與 -Domain 無關），所以任一 wiki 檔的違規會出現在**每一個領域**的 lint 結果裡。
2) 分級為真。$polishPatterns（:631-642）只含 'frontmatter 缺 ' 與 'status 值非法'；:525 的空檔訊息「wiki/X.md：空檔（0 byte／無內容）——疑似寫入中斷」不含任何白名單子串，Test-IsPolishViolation 用 .Contains 比對必然回 false → CoverageOnly 不降級 → 擋每個領域的 tier 1。frontmatter/status 雖降 tier 1，仍讓 lint exit=1 → 擋 tier 2（:599 baseOk 要求 $lint.Exit -eq 0），也讓 SOP-2「綠色 PASS → 結束」的手動流程永遠不綠。
3) 無修復管道為真。工單只由 $leakDelegable/$misplacedRefRows/$truncatedIds/$missingIds 組成（:681-712），人工清單只吃 $leakManual（:769-780），兩者都不含 wiki；auto-loop 的 $lint.Surgical 是從「=== 證據修復指令 … === 指令結束 ===」區塊擷取編號行（ps-auto-loop.ps1:349-352），wiki 違規從不進該區塊 → 手術 session 永遠拿不到它。research session 的 prompt 只有領域名（:460-461），lint 結果完全不傳給它。
4) 活鎖路徑為真。tier 1 相位純看 CoverageOnly exit（:449-452），FAIL 就永遠 research；進度以缺料違規數衡量（:651…

**原文佐證**：
```
【lint 自宣的隔離原則】
scripts/ps-doc-lint.ps1:13-14
  "# 手動執行不加此開關——維持警告不擋（SOP-2）。wiki 類警告任何模式都不升級
   # （跨領域共用層，會讓 A 領域的畢業被 B 領域的斷鏈鎖死）。"
scripts/ps-doc-lint.ps1:511-512
  "# 3) Entity Wiki 檢查（wiki/ 為跨領域共用層，存在才檢）
   $wikiDir = Join-Path $root "docs/ps-research/wiki""
  （路徑不含 $Domain＝每個領域的 lint 都掃同一份）

【三項直接進 violations】
scripts/ps-doc-lint.ps1:524-526
  "if ([string]::IsNullOrEmpty($t)) {
       $violations += "wiki/$($n.Name)：空檔（0 byte／無內容）——疑似寫入中斷"
       continue"
scripts/ps-doc-lint.ps1:529-531
  "if ($t -notmatch "(?m)^${key}\s*:") {
       $violations += "wiki/$($n.Name)：frontmatter 缺 $key""
scripts/ps-doc-lint.ps1:534-536
  "if ($Matches[1] -notin @('draft', 'verified', 'stale')) {
       $violations += "wiki/$($n.Name)：status 值非法：$($Matches[1])""
（對照：同區的 :541 stale、:555 斷鏈、:562 孤兒才是 $warnings）

【白名單漏掉空檔＝tier 1 也被擋】
scripts/ps-doc-lint.ps1:631-642
  "$polishPatterns = @( 'Evidence 附錄空白', 'ChunkId 遭縮寫為 8 碼', … 'frontmatter 缺 ', 'status 值非法' )"
scripts/ps-doc-lint.ps1:645-647
  "foreach ($pat in $polishPatterns) { if ($Msg.Contains($pat)) { return $true } } return $false"
  → :525 訊息無任一…
```

**建議最小修法**：ps-doc-lint.ps1 兩處最小改動：(1) 把 :522-537 的 wiki 三項改寫成推入新的 $wikiManual 陣列而非 $violations（維持 :13-14 的跨領域隔離＝不擋任何領域的門），並在 :769 的 $leakManual 區塊後仿照它印一段「=== wiki：人工處理清單（跨領域共用層，不擋畢業）===」，逐檔附修法：0-byte → 從內部 git 還原該 entity 檔或刪檔後重跑其來源領域；缺 key／status 非法 → 照 report-templates/entity-template.md 補齊 aliases/status/last_verified。(2) 若要保留擋門效果，至少把 '空檔（0 byte' 加進 :631-642 的 $polishPatterns（解除 tier 1 跨領域鎖死），並把該人工清單同時輸出到 lint 尾段，讓 L53 的「明確人工出口」成立。另 SOP.md:66-67 把「frontmatter 缺欄」自「wiki 類警告」移出並補上處置行（照 entity-template 補欄），與 lint 實判一致。


### M5. checklist-archive 含未勾項＝擋兩個 tier 的違規，但唯一修法（改寫 archive）被框架自己明文禁止，且無工單、無人工出口

**涉及**：scripts/ps-doc-lint.ps1, .opencode/agent/ps-deep-research.md

**指控**：ps-doc-lint.ps1:213-215 把「archive 含未打勾項」記為違規（訊息：「含 N 個未打勾項——歸檔只准搬已勾項（未勾項被搬走＝調查進度隱形消失）」），不在 $polishPatterns → 缺料類，擋 tier 1 與 tier 2。但修這條唯一的方法是把未勾項從 archive 搬回 checklist——而 ps-deep-research.md:193 明文「**禁止 read 或改寫任何既有 checklist-archive*.md**」，lint 自己也在 585 行把 archive 定性為「熱檔（整檔重寫會吃掉未勾項）」不可委派。該違規不進三型手術工單、不進「人工處理清單」（769-780 只印 $leaks 的不可委派項），違規訊息本身也沒給任何修復路徑。這同時踩中 L53（擋門無管道＝活鎖）與 L63（補救路徑被規則自己封死、未明文豁免）。

**驗證**：我逐一打開了被引用的每個位置，四個關鍵環節全部屬實，且互相咬合成一個「擋門但無管道」的閉環：

1) 違規存在且是缺料類（擋兩個 tier）。ps-doc-lint.ps1:213-215 確實把 archive 含未勾項寫進 $violations。我核對了 $polishPatterns 全表（ps-doc-lint.ps1:631-642，共 10 條：Evidence 附錄空白／ChunkId 遭縮寫為 8 碼／ChunkId 非 UUID 格式／出現自編 id 樣式／疑似縮寫 chunk id／當機器參照／機器參照無效／行為邏輯無任何 confidence 標註／frontmatter 缺／status 值非法），該訊息一條都不匹配，故 CoverageOnly 的降級迴圈（650-658）留下它 → tier 1 門 FAIL；基礎 lint 也 FAIL → tier 2 門 FAIL（auto-loop 574-575 明列兩門判準）。

2) 不進工單。auto-loop 的手術清單是從 lint 輸出的「=== 證據修復指令 …=== 指令結束 ===」區塊用 `^\s*\d+\.\s` 擷取（ps-auto-loop.ps1:349-352），而該區塊的產生條件與內容只有 $truncatedIds／$missingIds／$leakDelegable／$misplacedRefRows 四類（ps-doc-lint.ps1:681, 687-713）。archive 違規四類皆不屬於，永遠不會被擷取。實際後果：lint.Exit=1 但 Surgical.Count 可能為 0，手術迴圈（ps-auto-loop.ps1:521 的 `-and $lint.Surgical.Count -gt 0`）根本不進入。

3) 不進人工出口清單。ps-doc-lint.ps1:769-780 的「洩漏：人工處理清單」只迭代 $leakManual（即 $leaks 中 Delegable=false 者，574-588），archive 違規不在 $l…

**原文佐證**：
```
【違規本體，無修復路徑】/home/user/MCPSample/scripts/ps-doc-lint.ps1:213-215
```
$untickedInArchive = @([regex]::Matches($afText, '(?m)^\s*-\s*\[ \]')).Count
if ($untickedInArchive -gt 0) {
    $violations += "$($af.Name)：含 $untickedInArchive 個未打勾項——歸檔只准搬已勾項（未勾項被搬走＝調查進度隱形消失）"
```

【美工白名單全表，不含此訊息 → 缺料類擋 tier 1】/home/user/MCPSample/scripts/ps-doc-lint.ps1:631-642
```
$polishPatterns = @(
    'Evidence 附錄空白', 'ChunkId 遭縮寫為 8 碼', 'ChunkId 非 UUID 格式',
    '出現自編 id 樣式', '疑似縮寫 chunk id', '當機器參照', '機器參照無效',
    '行為邏輯無任何 confidence 標註', 'frontmatter 缺 ', 'status 值非法')
```
/home/user/MCPSample/scripts/ps-doc-lint.ps1:654-655
```
if (Test-IsPolishViolation $v) { $warnings += "[美工／不擋覆蓋畢業] $v"; $downgraded++ }
else { $kept += $v }
```

【工單只收四類，archive 不在其中】/home/user/MCPSample/scripts/ps-doc-lint.ps1:681
```
if (($truncatedIds.Count + $missingIds.Count + $leakDelegable.Count + $misplacedRefRows.Count) -gt 0) {
```
/home/user/MCPSample/scripts/ps-auto-loop.ps1:349-352
```
if ($raw -match '(?s)=== (?:證據|手術式)修復指令.*?===(.*?)=== 指令結束 ===') {
    $surgical = @($block -split "`r?`n" | Where-Object { $_ -match '^\s*…
```

**建議最小修法**：在 ps-doc-lint.ps1 收集一份 $archiveManual（第 213-215 行偵測到時，除了 $violations 再 push @{File=$af.Name; Count=$untickedInArchive}），並把第 769-780 行的人工清單區塊從「只印 $leakManual」擴為「$leakManual + $archiveManual」，archive 項附明文修法：「人工手動編輯：把該檔內 `- [ ]` 整列剪回 checklist.md 的『## 調查進度』節，archive 只留已勾項；**不得委派模型**（整檔重寫會吃掉未勾項）」；同時把第 215 行的違規訊息尾端補上「→ 見下方人工處理清單」，讓紅燈本身指得到出口。若要讓自動迴圈自行收斂，另需在 ps-deep-research.md:193 加一句明文豁免：「唯一例外：lint 指出某 archive 檔含未勾項時，准許對**該檔**做一次移除未勾列的重寫（把未勾列寫回 checklist.md），此例外不適用於任何其他 archive 讀寫。」


### M6. subagent 契約 JSON 洩漏（lint 2.4 節／L47）擋 tier 1 畢業門但零修復管道：不進 [洩漏] 工單、不進人工清單、research 相位收不到 lint 結果——正是本檔 583-585 行自己宣告「必然活鎖」的同一缺陷

**涉及**：scripts/ps-doc-lint.ps1, scripts/ps-auto-loop.ps1, .opencode/peoplesoft/lessons/applied.md

**指控**：【跨批合併：兩批各留一筆的同一缺陷（2.4 節 JSON 洩漏無工單／L47 檢查擋門零管道）】2.4 節（ps-doc-lint.ps1:435-460）掃契約 JSON 洩漏並記違規（458：「subagent 回報 JSON 原樣洩漏進文件（命中 N 個契約鍵）……刪除該段並依契約內容重寫」）；該訊息不在 $polishPatterns → 缺料類、擋 tier 1。但 $leaks 只由 2.6 節的 $leakPattern 掃描填入（574-591），2.4 的違規既不進 [洩漏] 手術工單（工單組成條件只看 $truncatedIds＋$missingIds＋$leakDelegable＋$misplacedRefRows 四類）、也不進人工處理清單（769-780 只吃 $leakManual）。純 JSON 洩漏（無 <think>/<tool_call> 標記，模型直接把契約 JSON 貼進 NN 檔或 90-audit.md）只觸發 2.4 違規、零工單項：auto-loop 手術迴圈條件是 Surgical.Count -gt 0，拿不到任何指令；tier 1 相位因 coverage FAIL 永遠停在 research，而 research session 只收到領域名（收不到 lint 結果）修不了；若洩漏在 90-audit.md 更形成循環——修復要靠下一輪稽核整檔重寫，但 coverage FAIL 使 audit 相位永遠不被排入。最終只能靠「連續 2 圈無進度」熔斷（先燒掉 2 個 60 分 session）停機進人工，而人工清單裡也沒有這一筆。這正是同檔 583-585 行對標記型洩漏自我宣告的鐵律：「洩漏原本只產違規、不產工單＝擋得住門卻沒有修復管道，自動迴圈必然活鎖（L43 同族）」——L53 只修了 marker 型，漏了 JSON 型。

**驗證**：親自逐行核對後，指控的每一個機械事實都成立，且構成框架自宣鐵律 L53 的直接違反。(1) 2.4 節（ps-doc-lint.ps1:435-460）掃到契約 JSON 洩漏後**只做 $violations +=**，完全沒有寫進 $leaks——而 $leaks 根本是在 574 行才第一次被建立（`$leaks = @()`），在 2.4 執行時尚不存在，結構上不可能有資料流。(2) 它確實擋 tier 1：621-630 的分類註解白紙黑字把「契約 JSON 洩漏」列進缺料類，且 631-642 的 $polishPatterns 白名單沒有任何一條 pattern 命中 458 行那句訊息，CoverageOnly 只降級白名單內的訊息（650-657），所以它原封不動留在 $violations → exit 1 → tier 1 門 FAIL。(3) 零管道：681 行工單條件只看 $truncatedIds/$missingIds/$leakDelegable/$misplacedRefRows；769 行人工清單只吃 $leakManual；兩者都源自 $leaks，故純 JSON 洩漏（無 <think>/<tool_call>）兩邊都進不去。(4) auto-loop 拿不到指令：手術迴圈條件是 `$lint.Surgical.Count -gt 0`（521），而 Surgical 只擷取「=== 指令結束 ===」區塊內的編號行（328-354），JSON 洩漏不產生任何編號行；research 相位呼叫只帶 `-PromptText $Domain`（460-461），ps-research.md 通篇未提 lint，模型收不到違規內容。(5) 90-audit.md 的循環也成立：tier 1 相位判定 `$goResearch = ($coverBefore.Exit -ne 0)`（451），coverage FAIL 就永遠不排 audit 相位，而 90-audit 的既定處置（L47:930「下一輪稽核整檔重寫」）正需要 aud…

**原文佐證**：
```
【擋門為真】ps-doc-lint.ps1:624（CoverageOnly 分類註解）：「缺料＝讀者讀不到或讀到壞東西：缺檔、空檔、缺章節、空殼章節、checklist 對帳不符、**模型標記或契約 JSON 洩漏**（疑似被截斷）。」；白名單 ps-doc-lint.ps1:631-642 `$polishPatterns = @('Evidence 附錄空白','ChunkId 遭縮寫為 8 碼','ChunkId 非 UUID 格式','出現自編 id 樣式','疑似縮寫 chunk id','當機器參照','機器參照無效','行為邏輯無任何 confidence 標註','frontmatter 缺 ','status 值非法')` — 無任一 pattern 命中 JSON 洩漏訊息。

【只產違規、不產工單素材】ps-doc-lint.ps1:452-459：`if ($keyHits -ge 3) { … $violations += "${tname}:${ln}：subagent 回報 JSON 原樣洩漏進文件（命中 $keyHits 個契約鍵）——契約 JSON 是**原料**，必須消化成報告文字；刪除該段並依契約內容重寫（同段常伴模型推理獨白，一併清）" }`（整段結束於 460 行的 `}`，全節無任何 `$leaks +=`）。對照 ps-doc-lint.ps1:574 `$leaks = @()` — $leaks 在 2.4 節之後才建立；ps-doc-lint.ps1:588（唯一填充點，位於 2.6 marker 掃描內）：`$leaks += @{ File = $lf.Name; Line = $lline; Marker = $m.Value; Delegable = $delegable }`。

【兩條管道都排除它】ps-doc-lint.ps1:679-681：`$leakDelegable = @($leaks | Where-Object { $_.Delegable })` / `$leakManual = @($leaks | Where-Object { -not $_.Delegable })` / `if (($truncatedIds.Count + $missingIds.Count + $leakDelegable.Count + $misplacedRefRows.Count) -gt 0) {`；ps-doc-lint.ps1:769：`if ($leakManual.Count -gt…
```

**建議最小修法**：在 ps-doc-lint.ps1 把 `$leaks = @()`（現 574 行）上移到 2.4 節之前（例如 434 行附近），並在 2.4 命中時除了 `$violations +=` 再補一筆工單素材：`$leaks += @{ File = $tname; Line = $ln; Marker = '契約 JSON 原樣洩漏'; Delegable = ($tname -match '^\d\d-' -and $tname -notmatch '^(00|90)-') }`——NN 檔即進 [洩漏] 手術工單（719 行的修法步驟已明寫「刪掉…契約 JSON」，prompt 不必改），90-audit.md 則自動落入 $leakManual 人工清單（775 行既有理由「下一輪稽核會整檔重寫」正好適用）。同時在 applied.md L53 落點補一句「洩漏＝marker 型與契約 JSON 型兩種簽名皆須進工單/人工清單」，避免下次新增檢查再漏。


### M7. 內建覆寫檔（explore/general/scout）沒封 task——與 ps-* subagent 全數明列 task: false 不同步，被封的 4 個 MCP 可經「內建 agent 再委派 ps-*」繞回

**涉及**：.opencode/agent/explore.md, .opencode/agent/general.md, .opencode/agent/scout.md, .opencode/agent/ps-orchestrator.md

**指控**：全部 7 個 ps-* subagent 都明確寫 task: false（＝專案自己認定 subagent 的 task 預設開、必須顯式封），但三個內建覆寫檔的 tools map 沒列 task。依「沒列＝預設開」，委派一旦漏到內建（L15 已實證會發生），該內建 agent 可用 task 再委派 ps-*（如四 MCP 全開的 ps-metadata-flow）取回覆寫檔宣稱要封鎖的 PeopleSoft 檢索能力——覆寫檔的存在目的（「封鎖 PeopleSoft 檢索 MCP」）被自己漏掉的 task 繞空；同時繞過 ps-orchestrator 的 oracleMCP 序列化紀律（不受「一次只准一個」約束的第二條委派源）。L46 的補鎖原則「同族側門要一起封」只補了 bash/write/edit/webfetch，task 這個同族側門漏封。

**驗證**：我逐檔開過，指控的每一項事實都對得上，且找不到任何明文豁免。(1) 三個內建覆寫檔的 tools map 我親自讀完整段（explore.md:4-14、general.md:4-14、scout.md:4-14 三檔逐字相同），確實只有 bash/write/edit/webfetch + 4 個 MCP 共 8 個 false，**沒有 task 這一項**。(2) grep 全 .opencode/agent/ 的 `task:`，7 個 ps-* subagent 全數明寫 `task: false`（ps-ae-flow:10、ps-auditor:9、ps-metadata-flow:10、ps-peoplecode-flow:10、ps-sql-flow:10、ps-sqr-flow:10、ps-ui-flow:10），只有兩個 primary（ps-orchestrator:16、ps-deep-research:10）是 true——這是專案自己用 7 檔行為宣告「subagent 的 task 預設開、必須顯式封」。三個覆寫檔自身寫 `mode: subagent`，與 ps-* 同類，沒有理由例外。(3) 覆寫檔缺的不是無關工具：ps-metadata-flow.md:16-23 四個 MCP 全 true，是完整的 PeopleSoft 檢索能力，經 task 一跳即可取回覆寫檔宣稱要封的東西。(4) 「沒列＝預設開」不是我外加的前提，是覆寫檔自己第 5 行寫的、也是 README.md:113 與 L1（applied.md:17-19）的鐵律。(5) L46（applied.md:909-912）正是同一邏輯的前例：當初也是「只封了 4 個 MCP，bash 沒列＝預設開」，補了 bash/write/edit/webfetch 並下結論「同族側門要一起封」——task 是同一族卻漏掉。(6) L15（applied.md:386-387）實證委派會漏到內建。(7) 附帶風險屬實：ps-orchestrator.md:50-52 的 orac…

**原文佐證**：
```
【覆寫檔實際內容——三檔逐字相同，確認無 task】
/home/user/MCPSample/.opencode/agent/explore.md:3-14
  mode: subagent
  tools:
    # L46：tools map 是覆寫表——沒列＝預設開。內建 agent 的 bash/write
    # 也必須顯式封鎖（委派漏到內建時才不會執行 shell 或寫檔）
    bash: false
    write: false
    edit: false
    webfetch: false
    "PeoplecodeElasticSearch_*": false
    "PeoplecodeSource_*": false
    "oracleMCP_*": false
    "PeoplecodeMetadata_*": false
（general.md:3-14、scout.md:3-14 完全相同，同樣無 task 項）

/home/user/MCPSample/.opencode/agent/explore.md:19-20
  本檔僅為工具封鎖覆寫：PeopleSoft 檢索一律走 ps-* 專職 subagent。
  explore 只探索本機 repo 檔案——它查不到 PeopleSoft，也不該被派去查。
  ← 目的宣告＋散文護欄，不含任何 task 豁免

【專案自宣：subagent 的 task 必須顯式封（grep .opencode/agent/ 的 task:）】
  ps-ae-flow.md:10        task: false
  ps-metadata-flow.md:10  task: false
  ps-peoplecode-flow.md:10 task: false
  ps-auditor.md:9         task: false
  ps-sql-flow.md:10       task: false
  ps-sqr-flow.md:10       task: false
  ps-ui-flow.md:10        task: false
  ps-orchestrator.md:16   task: true   ← primary
  ps-deep-research.md:10  task: true   ← primary
  （7/7 subagent 顯式封，0 例外；三個覆寫檔亦為 mode: subagent…
```

**建議最小修法**：在 /home/user/MCPSample/.opencode/agent/explore.md、general.md、scout.md 三檔的 tools map（各檔第 7-14 行那段）各補一行 `task: false`，並把上方 L46 註解改成「內建 agent 的 bash/write/task 也必須顯式封鎖——task 沒封＝可再委派 ps-* 取回本檔要封的檢索能力，且不受 orchestrator 的 oracleMCP 序列化約束」；同時在 SOP.md:198-201 的升版檢查項把「補封 4 個 MCP」改為「補封 4 個 MCP ＋ bash/write/edit/webfetch/task」，讓下次新增內建 agent 時清單完整。


### M8. mcp-tool-contracts.md 宣稱「現況共三個 MCP」且「各 server 的完整工具清單」只列兩個 server——第四個 MCP（PeoplecodeMetadata）與 oracleMCP 的實際工具在契約總覽全文零蹤

**涉及**：.opencode/peoplesoft/mcp-tool-contracts.md, .opencode/agent/ps-metadata-flow.md, .opencode/agent/ps-ae-flow.md, .opencode/agent/ps-ui-flow.md

**指控**：契約檔自稱工具契約總覽並斷言「現況共三個 MCP」，但實況是四個：12 個 agent 檔全數明列 PeoplecodeMetadata_*，其中 4 個 agent 開 true 並在內文依賴其三個工具（find_field_usage／search_component_metadata／get_ae_sql_metadata，2026-07-27 已正式整合）。契約檔全文 grep 這四個字串零命中；標榜「2026-08 管理者實測確認」的「完整工具清單」表也只列 ES 與 Source 兩個 server（oracleMCP 實際用到的 list-connections/connect/disconnect 同樣不在表上）。這正是 L61 事故的已記載根源——『契約總覽漏列→repo 查無被誤讀成不存在→差點寫進假規則』——當時的修補只補了兩個 server 的清單，同一顆地雷對第三、四個 server 原樣重埋；且「三個 MCP」一句是對第四個 server 存在性的正面否定，與每個 agent 檔的 tools map 直接互撞。（與另兩筆「三個 MCP」的差異：本筆落在契約總覽本身＝工具清單的權威來源，修法是補上兩個 server 的完整工具表。）

**驗證**：親自開檔核對，指控三段事實全部成立，且無任何明文範圍／豁免可化解：

(1) 契約總覽的自宣範圍是無條件的。mcp-tool-contracts.md:7 的表頭寫「各 server 的完整工具清單」，沒有「僅列檢索路徑兩個 server」之類的限定；表身（:9-14）確實只有 PeoplecodeElasticSearch 與 PeoplecodeSource 四個工具。:27-30 更進一步做正面存在性斷言「現況共三個 MCP」並逐一點名，PeoplecodeMetadata 全無蹤影。我對該檔 grep `PeoplecodeMetadata|find_field_usage|search_component_metadata|get_ae_sql_metadata|list-connections|disconnect` → **No matches found**（零命中，指控的 grep 結果屬實）。整檔 288 行我全讀過，無任何補述或指向他檔的例外說明。

(2) 第四個 server 不是提案而是已上線並被四個 agent 依賴。ps-ae-flow.md:22、ps-auditor.md:19、ps-metadata-flow.md:23、ps-ui-flow.md:20 均為 `"PeoplecodeMetadata_*": true`（其餘八檔明列 false，合計 12 檔全數列出＝L1 覆寫表紀律已套用），且內文把它寫成**強制的第一步**（ps-metadata-flow.md:44「**先用 PeoplecodeMetadata 定位**（免連線）」、ps-ui-flow.md:40 同語、ps-ae-flow.md:54 對映表）。applied.md:29-33、37-39 記載 2026-07-27 已「正式整合」三個工具。契約檔卻在 2026-08 的「實測確認」標記下說只有三個 MCP——**時間上晚於整合，內容上否定它**，與 12 個 agent 檔的 tools map 直接互撞。

(3) 這正是 L61 已記載的同一顆…

**原文佐證**：
```
【契約檔的無條件宣稱與零命中】
/home/user/MCPSample/.opencode/peoplesoft/mcp-tool-contracts.md:7
> **各 server 的完整工具清單（2026-08 管理者實測確認）**：
mcp-tool-contracts.md:9-14（表身全文，只有兩個 server）
> | Server | 工具 | 用途 |
> | `PeoplecodeElasticSearch` | `search_chunks` | 搜候選（定位用；回傳是候選不是證據） |
> | `PeoplecodeElasticSearch` | `get_chunk_by_id` | 依 id 取回（欄位同 Source 版）——**僅供交叉檢查，非解引用路徑** |
> | `PeoplecodeSource` | `get_chunks_details` | **解引用（唯一的正式證據來源）** |
> | `PeoplecodeSource` | `get_file_structure` | 檔案結構（先看目錄再定向取段） |
mcp-tool-contracts.md:27-30
> **現況共三個 MCP**：`PeoplecodeElasticSearch`（搜 chunk ids）、
> `PeoplecodeSource`（chunk id → 完整上下文）、`oracleMCP`（PeopleTools
> metadata，通用 SQL 查詢——§1 / §2 / §4 的角色由它照
> `oracle-query-cookbook.md` 樣板承擔，尚無專用工具）。
（我對該檔 grep「PeoplecodeMetadata|find_field_usage|search_component_metadata|get_ae_sql_metadata|list-connections|disconnect」→ No matches found；全檔 288 行讀畢，無其他補述。）

【實況：第四個 server 已整合並被四個 agent 依賴】
/home/user/MCPSample/.opencode/agent/ps-metadata-flow.md:21-23
>   # PeoplecodeMetadata：欄位用途反查（find_field_usage）／Component 關鍵字
>   # 搜尋（search_component_metadata）——回傳只作定位線索，證據仍走 SQL／C…
```

**建議最小修法**：改 /home/user/MCPSample/.opencode/peoplesoft/mcp-tool-contracts.md 檔頭兩處：(1) 在 :9-14 表格補三列 `PeoplecodeMetadata`——`find_field_usage`（只吃欄位名）、`search_component_metadata`（只吃 Component 關鍵字）、`get_ae_sql_metadata`（只吃 AE 程式名 aeApplid），用途欄一律標「定位線索，不得作 evidence（證據僅 CHUNK／SQL）；空／稀少≠不存在，必回退 cookbook／ES」，並補一列 `oracleMCP` 指向 `oracle-query-cookbook.md` §使用規則 7 與 §連線生命週期（list-connections／connect／disconnect，工具名以 /mcp 清單為準）；工具清單以 cookbook:31-34 為準（含第四個 `get_process_schedule_list`），勿只抄 agent 檔的三個。(2) 把 :27「**現況共三個 MCP**」改成「**現況共四個 MCP**」並加一句 `PeoplecodeMetadata`（自製索引，定位用、免連線，回傳一律候選）。


### M9. 規模門殘餘矛盾：/ps-research 收尾規則仍是純打勾數版，且其替代補救路徑「重跑本指令——全勾狀態會自動接稽核」在給出建議的情境下幾乎必然是死路

**涉及**：.opencode/command/ps-research.md, .opencode/agent/ps-deep-research.md

**指控**：【跨批合併：兩批各留一筆（收尾規則未帶入 L29 規模門／括號內替代路徑撞規模門），同一根本矛盾】ps-research.md 的收尾稽核規則完全沒有帶入 L29 前置規模門（以「已完成 NN 檔總數 > 5」為準、優先於打勾數），導致同一個 session 同時收到「打勾 ≤5 → 當場自動接一輪稽核」（user prompt）與「已完成檔總數 > 5 時本 run 不接稽核」（system prompt）兩條互斥指令。其括號內的替代路徑「或重跑本指令——全勾狀態會自動接稽核」在 >5 檔領域下為假：單次 run 上限 6 項，打勾 >5 幾乎必然意味已完成檔 >5，照建議重跑的新 session 到場即被規模門擋、再吐一句「請開新 session 執行 /ps-audit」收場，白燒一個 session——這是 L63 修掉主幹後留在指令檔的同型殘留（補救指示指向會讀到禁令的環境）。

**驗證**：親自開檔核對，指控的兩半都屬實，且沒有任何明文可以化解。

(1) 命令檔的收尾規則確實是「純打勾數版」。ps-research.md 全檔只有 24 行，我逐行讀完：第 19-23 行的收尾稽核規則只以「本 run 打勾 ≤5 / >5」分流，全檔無一字提到「已完成 NN 檔總數」。而 system prompt（ps-deep-research.md:152-155）的前置規模門是以「已完成 NN 檔總數 > 5」為準、且明寫「不跟本 run 打勾數走」。於是 15 檔領域、本 run 只打勾 3 項的 session 會同時吃到「≤5 → 當場自動接一輪稽核（90-audit.md 已存在不是跳過理由）」與「已完成檔總數 > 5 → 本 run 不接稽核」兩條互斥指令。

(2) 沒有任何明文裁決優先權。ps-deep-research.md:152 的優先宣告只寫「優先於**本節**其餘條款」——本節＝system prompt 內那一節，文字上管不到命令檔；我另外 grep 了 .opencode/ 全樹與 AGENTS.md，找不到任何「指令檔與系統提示衝突時以系統提示為準」的通則。這正是框架自己 L63 原則所禁止的「範圍靠暗示＝沒有範圍（對小模型尤其如此）」，而模型是 temperature 0.1 的 Qwen3.6-35B-A3B。

(3) 框架自己的驗收表把這條行為列為致命：test-scenarios.md:413-415 檢查點 8 標 [致命]，明寫「不論本 run 打勾幾項」——命令檔第 19-23 行的規則正是以打勾數為唯一變數，與該致命檢查點直接對立。

(4) 括號內替代路徑確為死路。該括號只出現在「>5 項」分支；同檔第 18 行寫「單次 run 至多 6 項」，故該分支成立時本 run 至少打勾 6 項；打勾項不論是新查功能項或稽核回灌的 `A<n> 補查 <NN-檔名>`（一檔一行，見 ps-deep-research.md:186-187）都對應到已存在或新產生的 NN 檔，因此已完成檔必 >5。照建議「重跑本指令」開的新…

**原文佐證**：
```
【矛盾主體：命令檔只有打勾數】
/home/user/MCPSample/.opencode/command/ps-research.md:18-23
「之後照系統提示流程逐項處理（**單次 run 至多 6 項**——達上限即停，
提示使用者開新 session 重跑續作）直到 checklist 全勾。收尾稽核規則：本 run
打勾 **≤ 5 項** → 當場自動接一輪稽核（90-audit.md 已存在不是跳過
理由）；**> 5 項** → 不當場稽核，結束時提示使用者開新 session 跑
/ps-audit（或重跑本指令——全勾狀態會自動接稽核）；
稽核新回灌的 A 項一律留給下一次 run。」
（該檔共 24 行，我全檔讀過：無「已完成」「檔總數」「規模門」等字樣。）

【對立文本：system prompt 以檔總數為準】
/home/user/MCPSample/.opencode/agent/ps-deep-research.md:152-156
「- **前置規模門（L29，優先於本節其餘條款）**：稽核＝全量重驗，工作量
  跟「已完成 NN 檔總數」走、不跟本 run 打勾數走——已完成檔總數 > 5
  時**本 run 不接稽核**，結束總結告知：
  「本領域規模超過當場稽核上限，請開新 session 執行 /ps-audit <領域>」。
  實測：15 檔領域的 in-run 稽核記分卡缺 15 列（塌縮），≤5 勾門檻擋不住。」

【優先宣告只及於「本節」，管不到命令檔；豁免名單不含「重跑 ps-research」】
/home/user/MCPSample/.opencode/agent/ps-deep-research.md:148-151
「**本節只管「research run 收尾的自動接跑稽核」。收到明確稽核指令的
session（/ps-audit、或 headless 的 --command ps-audit）＝規模門指定的
那個「新 session 稽核」本身——本節全部條款（含規模門）對它不適用：
立刻執行稽核模式，不得反問、不得婉拒、不得建議再開 session（L63）。**」
（對照：/home/user/MCPSample/.opencode/command/ps-audit.md:8-10「**你這個 session 就是規模門（L29）指定的「新 session 稽核」——當場稽核上限對本指令不適用（不論已完成檔數多少）…**」＝正確寫法的樣板，ps-research.md 沒有對應句。…
```

**建議最小修法**：改 /home/user/MCPSample/.opencode/command/ps-research.md 第 19-23 行，把收尾規則改成帶規模門且刪掉死路括號，例如：「收尾稽核規則（以系統提示『前置規模門 L29』為準，優先於打勾數）：**已完成 NN 檔總數 > 5** → 本 run 一律不當場稽核，結束時告知『本領域規模超過當場稽核上限，請開新 session 執行 /ps-audit <領域>』（不要建議重跑本指令）；**總數 ≤ 5 且本 run 打勾 ≤ 5 項** → 當場自動接一輪稽核（90-audit.md 已存在不是跳過理由）；稽核新回灌的 A 項一律留給下一次 run。」


### M10. L64 成批查無規則放在無法執行它的 agent 身上：per-file auditor 觀測不到「≥3 檔」，且被禁寫 90-audit.md

**涉及**：.opencode/agent/ps-auditor.md, .opencode/agent/ps-deep-research.md, .opencode/command/ps-audit.md

**指控**：L64 的觸發條件（本輪 ≥3 檔 id 查無）與後續動作（在 90-audit.md 表頭加 ⚠ 行）都寫在 ps-auditor.md，但 auditor 是一次一檔委派、無跨檔／跨呼叫狀態，永遠看不到「本輪已有 ≥3 檔」；且 auditor write:false、硬規則明定「不寫任何檔案」，卻被指示改 90-audit.md。而真正持有跨檔視野並執筆 90-audit.md 的 ps-deep-research 稽核模式與 ps-audit.md 完全沒有成批查無的彙整條款或 ⚠ 行規格——L64 在整個系統裡無處可以觸發。另外 L64 指示的判定詞「stale」不在契約五詞內，主 agent 的就近映射規則會把它歸 FAIL，環境訊號被折回一般 FAIL；L64 只宣告「優先於上一條」（ES 交叉檢查），對任務 A 步驟 2 的 FAIL(NOT_FOUND) 判定階梯的優先序未宣告。

**驗證**：親自讀完三個被引檔＋契約/模板/SOP/教訓後，核心矛盾屬實：L64 的觸發條件與後續動作都只寫在 ps-auditor.md，而 auditor 在架構上（a）一次只收一個檔案路徑、無跨檔跨呼叫狀態，觀測不到「本輪 ≥3 檔」；（b）frontmatter write:false ＋硬規則「不寫任何檔案」，卻被指示在 90-audit.md 加 ⚠ 行。我用 grep 全庫確認「成批」「疑似索引」「⚠ 本輪」等字樣只出現在 ps-auditor.md、mcp-tool-contracts.md:25、SOP.md:465、applied.md（L64 教訓本體）——ps-deep-research.md 稽核模式（166-213）、ps-audit.md 全文、audit-template.md 全文皆無彙整條款、無 ⚠ 表頭欄位。也就是說：真正持筆 90-audit.md 的 ps-deep-research 沒有收訊窗口（auditor JSON 也沒有 bulkNotFound 之類欄位，只有自由文字 gaps），⚠ 行在整個系統確實沒有任何可觸發點。更嚴重的是 SOP-11 第 9 條明文要管理者預期「auditor 會標『疑似索引已重建』」——重建後管理者去找一個永遠不會出現的橫幅。兩點對指控做修正（不改變 CONFIRMED，但影響嚴重度評估）：(1) 「stale 折回 FAIL」的實害被 ps-deep-research.md:204-205「原因欄逐字取自 auditor 回報」大幅緩解，環境訊號仍以文字留在明細表；(2) 實質防護未全滅——步驟 2 的三管道二次定位本來就是強制的，且 FAIL(FABRICATED) 僅發生於「id 非 UUID 格式且非 8 碼 hex」（ps-auditor.md:87-90），合法 UUID 查無走的是 FAIL(NOT_FOUND)，所以「成批誤判捏造」的最壞情況比 L64 教訓假設的輕。失效的是報告層的環境訊號彙整與橫幅，不是防捏造機制本身。因此仍是 major（死規則＋SOP 指向不存在的產物），不到…

**原文佐證**：
```
【L64 條款本體，寫在無法執行它的 agent 上】
/home/user/MCPSample/.opencode/agent/ps-auditor.md:56-61
「- **成批查無＝環境訊號，不是成批捏造（L64，優先於上一條）**：本輪已有
  **≥3 檔**出現 id 查無（含 ES 也無）＝索引重建／chunk id 輪替的訊號——
  捏造是零星的，不會 15 檔同時全滅。此時**全部判 stale、逐筆走二次定位**
  （ObjectName＋事件名結構化搜尋取新 id），一律不判 FABRICATED，並在
  90-audit.md 表頭下加一行「⚠ 本輪成批查無 N 檔——疑似索引已重建，
  舊 id 全面失效」。」

【auditor 無筆】
/home/user/MCPSample/.opencode/agent/ps-auditor.md:10「  write: false」
/home/user/MCPSample/.opencode/agent/ps-auditor.md:12「  bash: false」
/home/user/MCPSample/.opencode/agent/ps-auditor.md:175「- 不修文件、不寫任何檔案。」
/home/user/MCPSample/.opencode/agent/ps-auditor.md:153「## 回報格式（最終輸出只有這份 JSON）」（欄位僅 evidence/claims/discoveredObjects/gaps，無跨檔訊號欄位——:156-168）

【auditor 一次一檔、無跨檔視野】
/home/user/MCPSample/.opencode/agent/ps-deep-research.md:168-169「**稽核範圍＝checklist 全部已打勾項（全量重驗）……**。一次一檔，oracle 類委派依序：」
/home/user/MCPSample/.opencode/agent/ps-deep-research.md:175-176「1. 每檔委派 @ps-auditor（任務 A：證據解引用……）——**委派只傳檔案路徑，不貼內容**」
/home/user/MCPSample/.opencode/agent/ps-deep-research.md:233-234「- 驗檔類委派（快驗／稽核任務 A）只傳**檔案路徑**：`[任務] read docs/ps-research/<領域>/<檔名> 執行任務 A（證據解引用）`」…
```

**建議最小修法**：把 L64 拆成「per-file 觀測」與「跨檔彙整」兩半，各放在做得到的 agent 上：(1) ps-auditor.md:56-61 改為只做本檔份內事——「本檔出現 id 查無（含 ES get_chunk_by_id 也無）≥2 筆時，本檔一律走二次定位、不判 FABRICATED（合法 UUID 最壞判 FAIL(NOT_FOUND)），並在回報 JSON 的 gaps 固定加一行 `BULK_NOT_FOUND: <檔名> <n> 筆 id 查無（ES 亦無）`」，刪掉「並在 90-audit.md 表頭下加一行…」整句（與 :10 write:false／:175 不寫任何檔案 直接抵觸）。(2) ps-deep-research.md 稽核模式步驟 4（約 198-210 行）與 ps-audit.md 流程第 4 點各加一句：「彙整本輪各檔 auditor gaps 的 `BULK_NOT_FOUND` 行；≥3 檔命中 → 90-audit.md 表頭下加一行『⚠ 本輪成批查無 N 檔——疑似索引已重建，舊 id 全面失效』，且該輪這些檔的證據判定一律映射為 FAIL(NOT_FOUND)／FAIL(ID_RELINK)，不得記為捏造（L64）」，並在 audit-template.md:3 表頭後補一列 `<!-- 成批查無時在此加 ⚠ 行（L64） --…


### M11. 「啟動與續跑（每次被呼叫先做這個）」與收尾自動稽核無豁免條款，正面撞上手術 prompt、/ps-lesson、/ps-correct 的第一動作與禁令（L63 同型殘缺）

**涉及**：.opencode/agent/ps-deep-research.md, scripts/ps-auto-loop.ps1, .opencode/command/ps-lesson.md, .opencode/command/ps-correct.md

**指控**：【跨批合併：兩批各留一筆（啟動規則無豁免撞三條路徑／L63 落點只給 /ps-audit 豁免），同一根本矛盾】agent 的啟動規則無條件要求每次被呼叫先檢查 00-overview → 續跑階段二（含更新 checklist 打勾）→ 全勾時 0 勾也算 ≤5 → 當場接稽核，但只有 /ps-audit 一條路徑拿到明文豁免（148-151）。手術 session（--agent ps-deep-research＋$sPrompt）、/ps-lesson、/ps-correct 三條路徑都沒有豁免：手術 prompt 明令「禁止修改 checklist.md 與 90-audit.md，禁止執行稽核」「只准修改清單所列檔案」（連系統 prompt 規定每 run 必 append 的 log.md 都被此句禁掉），與系統 prompt 的續跑／打勾／接稽核義務直接互斥；auto-loop 自己的註解也承認 agent 啟動規則會讓手術 session 自行接跑稽核，只用 user-message 層 prompt 禁令單邊圍堵（靠模型優先序運氣壓 system prompt），未依 L63「補救指示指定的路徑必須被明文豁免」在 agent 檔開口。手術 session 若遵啟動規則去做階段二，60 分 session 燒掉、工單不減，觸發「本批未讓手術清單變短」提前放棄。/ps-lesson 與 /ps-correct 的「第一個回應必須先 read applied.md／先 grep wiki」同樣與啟動規則的第一動作互撞、無豁免。

**驗證**：我逐檔開過，指控的核心屬實，而且不是靠推測——腳本自己的註解就是自白。

1) ps-deep-research.md 的「啟動與續跑」節（:40-49）我整段讀過，**沒有任何範圍或豁免文字**：標題直接寫「每次被呼叫先做這個」，內文是無條件的 00-overview→checklist→從第一個未勾項續跑階段二。階段二 step 5 會改寫 checklist.md 打勾，接著 :147-164 的收尾條款在「全勾重跑的 0 勾也算 ≤5」時**當場接稽核**（改寫 90-audit.md＋輪次 +1）。

2) 全檔唯一的明文豁免在 :148-151，措辭是「**本節**全部條款（含規模門）對它不適用」——「本節」指的是「全部打勾後接稽核」那一節，受益者只有 /ps-audit 與 headless --command ps-audit。它既沒有豁免「啟動與續跑」，也沒有提到手術／lesson／correct 任何一條路徑。我另外 grep 過 ps-deep-research.md 的「手術／lint 修復／surgery／指令覆寫」，全檔對 lint 修復 session 這種呼叫模式**零提及**（只有 :120 一個無關的「同手術流程」用語）。

3) 對照組證明框架自己知道該怎麼修：ps-audit.md:8-10 就有對稱明文聲明（L63 落點 2 的產物）。同一套修法沒有套到手術 prompt 這條路徑上。

4) 手術路徑的碰撞是實測而非假設：ps-auto-loop.ps1:527-528 註解寫「ps-deep-research 在 checklist 全勾時**會**自行接跑稽核（agent 啟動規則）」，:35-36 又寫「可能於手術 session 內自行接跑稽核，跨步驟比對會污染」——腳本承認 agent 系統 prompt 會這樣做，卻只在 :533 的 user-message 層用一句禁令單邊圍堵（靠模型把 user prompt 壓過 system prompt 的運氣）。這正是 applied.md:1448-1452 L63…

**原文佐證**：
```
【啟動規則無條件、無豁免】
.opencode/agent/ps-deep-research.md:40「## 啟動與續跑（每次被呼叫先做這個）」
:42-44「1. 檢查 `docs/ps-research/<領域>/00-overview.md`：／- **不存在** → 執行階段一（總覽）。／- **存在** → read `checklist.md`，從**第一個未勾選項**繼續階段二。」
（:40-49 整節我逐行讀過，無任何「本節只管／不適用於」字樣）
:96-97「5. 更新 `checklist.md`（read → 整檔覆寫）：該項打勾；BLOCKED 也照樣寫檔…」
:157-159「- 本 run 打勾數 **≤ 5**（含 A 項；全勾重跑的 0 勾也算）→ 當場執行一輪稽核模式（見下節）再結束。**「90-audit.md 已存在」不是跳過的理由**——那是上一輪的舊報告，必須重驗重寫。」

【唯一豁免只綁 /ps-audit、且只及於「本節」】
:148-151「**本節只管「research run 收尾的自動接跑稽核」。收到明確稽核指令的／session（/ps-audit、或 headless 的 --command ps-audit）＝規模門指定的／那個「新 session 稽核」本身——本節全部條款（含規模門）對它不適用：／立刻執行稽核模式，不得反問、不得婉拒、不得建議再開 session（L63）。**」
（對照組，證明修法模式只套了一條路徑）.opencode/command/ps-audit.md:8-10「**你這個 session 就是規模門（L29）指定的「新 session 稽核」——當場稽核／上限對本指令不適用（不論已完成檔數多少）。不得反問、不得婉拒、不得／建議再開 session…**」

【log.md 每 run 必寫】
.opencode/agent/ps-deep-research.md:242-243「每次 run 結束前，append 一行到 `docs/ps-research/<領域>/log.md`／（沒有就建）：`## [日期] <動作摘要> | 動到的檔案清單`。」

【手術 prompt 的相反禁令（user-message 層單邊圍堵）】
scripts/ps-auto-loop.ps1:533（$sPrompt 結尾）「…每筆附收據；只准修改清單所列檔案，禁止修改 checklist.md 與 90-audit.md，禁止執行稽核：$flat」
:534「$sr = Invoke…
```

**建議最小修法**：在 .opencode/agent/ps-deep-research.md:40 的節標題下（進入第 1 步之前）補一段明文範圍，照 :148-151 的既有句式寫：「**本節只管「未指定具體任務的 research run」（/ps-research 或空 prompt）。收到明確任務清單／指令的 session——lint 修復手術 prompt、/ps-lesson、/ps-correct、/ps-audit——本節全部條款對它不適用：直接執行該指令的第一動作與範圍，不續跑階段二、不改 checklist.md 打勾、不接稽核（L63）。唯一共同義務是收尾 append log.md。**」同時把 scripts/ps-auto-loop.ps1:533 $sPrompt 的「只准修改清單所列檔案」改成「只准修改清單所列檔案（外加 log.md 收尾追加一行）」，解掉與 agent :242 的互斥。


### M12. SOP-17 的「-ExecutionPolicy Bypass」字串直接寫進 repo，撞上 SOP-2/SOP-3/AGENTS 自己宣示的「安控掃繞過類字樣、連純文字都擋」鐵律

**涉及**：.opencode/peoplesoft/SOP.md, AGENTS.md

**指控**：SOP-2 明文規定執行原則替代跑法的「實際指令不入 repo」，因為公司安控會掃「繞過」類字樣（連純文字都擋，2026-07 實測），AGENTS.md 也重申「repo 禁放…『繞過』類字串（SOP-2／3）」；但 SOP-17 第 2 步把排程器引數「-NoProfile -ExecutionPolicy Bypass -File …」原文寫進同一個 repo 的 SOP.md。兩者不可能同時成立：若 2026-07 的實測宣稱為真，SOP-17 這行會讓整個 repo 被安控擋下載；若安控其實不擋，SOP-2 1a(3) 的「永久程序」（指令存本機筆記、向維護者索取）就是過期宣稱。

**驗證**：我逐檔打開查證，指控引用的每一行都存在且文字與指控一致，且**全 repo 找不到任何明文豁免或範圍限縮**。

1. 禁令確實存在，且其自訂範圍精準涵蓋 SOP-17 那一行。SOP-2 1a(3) 禁的不是泛稱的「繞過」二字，而是點名「**執行原則替代跑法**」的**實際指令**不入 repo。`-ExecutionPolicy Bypass` 就是「執行原則替代跑法的實際指令」本身——所以即使採最窄讀法（禁令只涵蓋執行原則替代指令，不涵蓋 SOP.md:186、applied.md:14 那種講「繞過 subagent 架構」的中文用法），SOP.md:336 仍然正中禁令核心。這條不依賴「安控掃中文還是英文」的推測。

2. 違規字串確實入庫。`git ls-files --error-unmatch .opencode/peoplesoft/SOP.md` 成功；`.gitignore` 只擋 bin/obj/auto-loop-logs/graduation.json，沒擋 `.opencode/`。SOP-3（SOP.md:92-93）本來就明文要求 `.opencode/` 要 commit。所以「不入 repo」的要求被同一份被 commit 的檔案自己打破。

3. 沒有豁免。我讀完整個 SOP-17 區塊（SOP.md:324-388）、AGENTS.md 全文 76 行、README 資安邊界節（261-264），並 grep `applied.md` 的「安控／排程器／執行原則／Unblock-File／可執行檔／白名單／簽章」——零筆例外說明。依框架自宣的 L63「補救指示指定的路徑必須明文豁免，否則遞迴死路；範圍靠標題暗示＝沒有範圍」，「這是排程器引數所以不算」正是典型的「靠上下文暗示的範圍」＝沒有範圍。

4. 唯一性佐證：跨 `*.md/*.ps1/*.json/*.yaml/*.txt`（排除 `src/` 與 `.review-findings.json`）grep `Bypass|ExecutionPolicy`，**全 repo…

**原文佐證**：
```
【禁令原文｜我親自讀到】
/home/user/MCPSample/.opencode/peoplesoft/SOP.md:50-52
  50	     (3) 「執行原則替代跑法」——**實際指令不入 repo**（安控會掃
  51	         繞過類字樣，連純文字都擋，2026-07 實測）：由管理者存於
  52	         本機筆記，需要時向系統維護者索取

【違規原文｜同一份檔案，相隔 285 行】
/home/user/MCPSample/.opencode/peoplesoft/SOP.md:335-336
 335	□ 2. 動作：powershell.exe
 336	     引數：-NoProfile -ExecutionPolicy Bypass -File "<repo>\scripts\ps-auto-all.ps1"

【鐵律重申｜兩處】
/home/user/MCPSample/AGENTS.md:73
  73	  誤解析成語法錯誤）；repo 禁放執行檔與「繞過」類字串（SOP-2／3）。
/home/user/MCPSample/README.md:262
 262	- repo 內禁放執行檔與「繞過」類字串。

【合規替代路徑已存在（使違規成為多餘）】
/home/user/MCPSample/.opencode/peoplesoft/SOP.md:482-483
 482	□ 啟動前：Unblock-File 四支腳本（auto-all／auto-loop／doc-lint／graduation
 483	  ——auto-all 用子 powershell 跑 auto-loop，執行原則須四支都放行）
/home/user/MCPSample/.opencode/peoplesoft/SOP.md:47-49
  47	□ 1a. 被執行原則擋（PSSecurityException）→ 依序：
  48	     (1) Unblock-File 該 .ps1 後重試
  49	     (2) 請 IT 對 scripts\ps-doc-lint.ps1 簽章或加白名單

【分發鏈受影響之證據】
/home/user/MCPSample/AGENTS.md:61-63
  61	- 公司網路封鎖 git 下載 → **人工搬運**：你改完檔案只列「改動檔案
  62	  路徑清單」，使用者自己開 GitHub 網頁 Raw 複製整檔貼回本機——
/home/user/MCPSample/.open…
```

**建議最小修法**：改 /home/user/MCPSample/.opencode/peoplesoft/SOP.md 的 SOP-17 第 2 步（335-336 行），把引數改為不含替代跑法指令的合規版：

□ 2. 動作：powershell.exe
     引數：-NoProfile -File "<repo>\scripts\ps-auto-all.ps1"
           -MaxCyclesPerDomain 6 -MaxBatchHours 9 -MaxConsecutiveFailures 3
     （執行原則放行照 SOP-14 啟動前 Unblock-File 四支腳本；仍被擋依
      SOP-2 1a(2)(3)——替代跑法的實際指令不入 repo）

即刪掉 `-ExecutionPolicy Bypass` 六個字並補一行指回 SOP-14／SOP-2 1a。此改法零功能損失（SOP-14:482-483 對同一批腳本本來就教 Unblock-File），且順帶消除 SOP-14 與 SOP-17 對同一組腳本兩套放行路線的不一致。

若管理者實測後認定 2026-07 的安控宣稱已過期，則改走另一端：一併刪除 SOP.md:50-52 的 1a(3)、AGENTS.md:73 與 README.md:262 的「繞過」類字串禁令，並在 applied.…


### M13. SOP-17 單領域最壞時長公式過期：寫「MaxCycles×120 分」，SOP-14 與兩支腳本都是 MaxCycles×(120＋60×MaxSurgeryPerCycle)＝預設 300 分/圈，低估 2.5 倍

**涉及**：.opencode/peoplesoft/SOP.md, scripts/ps-auto-loop.ps1, scripts/ps-auto-all.ps1

**指控**：SOP-17 第 5 步教人用 -MaxCyclesPerDomain 當硬圍欄時，附的最壞時長公式漏掉手術 session（每圈最多 MaxSurgeryPerCycle=3 批×ResearchTimeoutMin=60 分）。照 SOP-17 建議值 MaxCyclesPerDomain=6 算，宣稱上限 12 小時、真實上限 30 小時——夜跑圍欄的尺寸判斷建立在錯 2.5 倍的數字上。L59 記載「auto-all／SOP-14 的最壞時長公式同步更新」，SOP-17 這處被漏掉。

**驗證**：親自開檔逐行核對，指控引用的每一行都存在且原文與指控一致，沒有任何暗示或明文範圍能化解。

1) SOP.md:343 確實寫「單領域最壞＝MaxCycles×120 分」，且該行就在 SOP-17 第 5 步、緊接 SOP.md:337 建議值 `-MaxCyclesPerDomain 6 -MaxBatchHours 9`。我讀了 SOP.md:324-350 整段 SOP-17，這段標題是「無人看管排程（衝刺期夜間跑批）」、動作是 ps-auto-all.ps1，主題與 SOP-14 完全同一件事（同一支腳本、同一個參數、同一個單位「分」），**沒有任何限縮語**（沒有「不含手術」「僅 audit 相位」之類）。所以這不是兩個不同定義各有範圍，是同一個量的兩個互斥數字。

2) 我全庫 grep「最壞」與「MaxCycles×」，全部出現處只有四個：SOP.md:343（×120）、SOP.md:487-489、ps-auto-all.ps1:22、ps-auto-loop.ps1:50-51。後三者一致含手術項，SOP.md:343 是唯一的落單值。不存在第三種定義或別處的豁免條款。

3) 我不只信註解，還讀了 ps-auto-loop.ps1 的實際迴圈確認長公式是真的：line 521 的 while 以 `$surgeryRound -lt $MaxSurgeryPerCycle` 為界，line 535 的手術 session 傳 `-TimeoutMin $ResearchTimeoutMin`（沿用 60 分，非獨立參數），line 467 的 audit 傳 `-TimeoutMin $AuditTimeoutMin`（120 分），line 46 `$MaxSurgeryPerCycle = 3` 為預設。所以每圈最壞 120＋60×3＝300 分屬實，×120 少算的正是每圈 180 分的手術上限。

4) 算術與後果核對無誤：照 SOP.md:337 自己建議的 MaxCyclesPerDomain 6，SOP-17 讓人算出 6×120＝…

**原文佐證**：
```
以下皆為我自行開檔讀到的原文：

/home/user/MCPSample/.opencode/peoplesoft/SOP.md:336-337（SOP-17 建議值）
「     引數：-NoProfile -ExecutionPolicy Bypass -File "<repo>\scripts\ps-auto-all.ps1"
           -MaxCyclesPerDomain 6 -MaxBatchHours 9 -MaxConsecutiveFailures 3」

/home/user/MCPSample/.opencode/peoplesoft/SOP.md:342-343（過期公式，唯一落單處）
「□ 5. 圍欄要用 -MaxCyclesPerDomain 收斂：MaxBatchHours 只在**領域之間**檢查，
     攔不住進行中的領域（單領域最壞＝MaxCycles×120 分）」

/home/user/MCPSample/.opencode/peoplesoft/SOP.md:487-489（SOP-14 正確公式）
「  注意 MaxBatchHours 只在領域之間檢查——單領域最壞時長
  ＝MaxCycles×(audit 120m＋surgery 60m×MaxSurgeryPerCycle)，
  要硬圍欄就縮 MaxCyclesPerDomain，別指望 MaxBatchHours）」

/home/user/MCPSample/scripts/ps-auto-all.ps1:22-23
「#       單領域最壞＝MaxCycles×(120＋60×MaxSurgeryPerCycle) 分；跑批務必用
#       -MaxCyclesPerDomain 收斂（MaxBatchHours 攔不住進行中的領域）。」

/home/user/MCPSample/scripts/ps-auto-loop.ps1:50-51
「    # 批次單領域最壞＝MaxCycles×(AuditTimeoutMin＋ResearchTimeoutMin×
    # MaxSurgeryPerCycle) 分，要硬圍欄改用 -MaxCyclesPerDomain。」

/home/user/MCPSample/scripts/ps-auto-loop.ps1:46,52,58（預設值）
「    [int]$MaxSurgeryPerCycle = 3,」
「    [int]$ResearchTimeoutMi…
```

**建議最小修法**：把 /home/user/MCPSample/.opencode/peoplesoft/SOP.md:343 的「（單領域最壞＝MaxCycles×120 分）」改成與 SOP-14／兩支腳本同一式：「（單領域最壞＝MaxCycles×(audit 120m＋surgery 60m×MaxSurgeryPerCycle)＝預設每圈 300 分；MaxCyclesPerDomain 6 ≒ 30 小時，非 12 小時）」，並順手校正 SOP.md:337 的 -MaxBatchHours 9 建議值或加註「MaxBatchHours 只在領域之間檢查、攔不住單一領域的 30 小時」，避免同段兩個數字互相打臉。


### M14. tier 1 畢業門把「全部未勾項」一律標成 SOP-13 的「回灌補強項」，但機制上分不出原始盤點項／SOP-6 人工加項——「功能查得到」的保證沒有任何機械檢查支撐

**涉及**：.opencode/peoplesoft/SOP.md, scripts/ps-auto-loop.ps1, scripts/ps-doc-lint.ps1

**指控**：SOP-13 的「建議不是債」只講畢業後的『稽核回灌 A 項』；L50 自己也列明未勾項有三個來源，其中 (a)『新物件探勘前緣』不是補強。但 SOP-16 與 auto-loop 把整個未勾數不看（相位只看 CoverageOnly），而 lint 的 checklist 對帳只驗「已打勾項的檔案存在」——未勾的原始盤點項（該功能根本沒建檔、wiki 查不到）產生零違規。結果：只要既有檔案乾淨，領域可以帶著從未研究過的原始項（甚至 SOP-6 承諾『之後跑 /ps-research 就會查它』的人工加項）通過 tier 1，畢業訊息還斷言「未勾 N 項屬補強類」；SOP-16 宣稱的 tier 1 保證「功能查得到」對這些項不成立。極端情形：階段一只建 checklist＋overview、零 NN 檔時 CoverageOnly 空集合全綠，覆蓋門空洞通過。

**驗證**：每一條引用我都親自開檔核對，行號與原文全部對得上，且我另外找到一項指控者沒查到的關鍵事實，它讓矛盾更確定（而非化解）。

核心事實鏈（全部實讀）：
(1) tier 1 相位與門確實完全不看未勾數：ps-auto-loop.ps1:449-452 相位只讀 Invoke-Lint -Coverage 的 exit；:598-599 `$baseOk = $true`，只有 Tier 2 才加 `$after.Unticked -eq 0`。這部分是刻意設計（L50 的活鎖修正），本身不是矛盾。
(2) 矛盾在「斷言」而非「門」：:607 與 :682 在畢業訊息裡把**整個未勾數**斷言為「屬補強類」並掛 SOP-13「建議不是債」，但產生該數字的 Get-ChecklistState（:127-131）只做 `^\s*-\s*\[ \]` 的整批計數，完全不分型別。腳本對「這 N 項是什麼」零檢查，卻照常宣判——正是 L49「判定輸入讀不到時外環不會沉默失效，它會照常宣判、而且判錯」的同型錯誤。
(3) 框架自己否證這個斷言：applied.md:992-993 明列未勾項三來源，(a) 新物件探勘前緣不是補強；SOP.md:399-406 的 SOP-13 通篇是「維運節奏（領域畢業後的營運模式）」，其「回灌 A 項是建議不是債」範圍限畢業後的 A 項——SOP.md:300 把它擴張成「全部未勾項」。
(4) lint 側確實對未勾項零檢查：ps-doc-lint.ps1:222-227 的對帳只在 `tick='x'` 時驗檔案存在，另一向只驗「NN 檔要被列到」。未勾的原始盤點項（無檔）兩向都不觸發，零違規。
(5) 空覆蓋確實可全綠：NN 檔集合由 :264-265 的 `^\d\d-` 且非 00/90 決定；零檔時 :500 的記分卡檢查被 `$nnNames.Count -gt 0` 跳過、:61 直接 return，90-audit 不存在只在 StrictAudit 才算違規（:505-508），而 tier 1 不跑 StrictAudit。我另…

**原文佐證**：
```
【保證與擴張——SOP.md】
:298 「  保證：功能查得到、每份文件有實質內容、沒被截斷或污染」
:300 「  未勾項：留著不擋——稽核回灌的補強項是建議不是債（SOP-13）」
:392 「## SOP-13 維運節奏（領域畢業後的營運模式）」
:401 「□ research：只在「有想處理的工單」時跑——回灌 A 項是建議不是債，」
（SOP-13 標題明寫範圍＝畢業後的維運節奏，:300 把它套到全部未勾項）
README.md:208 「| **tier 1**<br>覆蓋畢業（可用） | 功能查得到、每份文件有實質內容、沒被截斷或污染 | session 正常收場 ＋ 稽核狀態轉移 ＋ `lint -CoverageOnly` 全過 |」

【框架自己列出的反例——applied.md（L50）】
:992-993 「未勾項的三個來源裡只有一個會自己收斂：\n  (a) 新物件探勘前緣——有限，會收斂；」

【未驗證即斷言——scripts/ps-auto-loop.ps1】
:607 「                $stopReason = "覆蓋畢業（tier 1／可用）：稽核輪次 $($auditAfter.Round)、缺料已清；未勾 $($after.Unticked) 項屬補強類，留待 tier 2"」
:682 「    Write-Log "本領域已達 tier 1（可用／80 分）：未勾 $($final.Unticked) 項屬補強類，可留待 tier 2 精修圈處理（SOP-13：建議不是債）"」
:131 「    $unticked = @($lines | Where-Object { $_ -match '^\s*-\s*\[ \]' }).Count」（整批計數，無型別）
:450-451 「            $coverBefore = Invoke-Lint -Coverage\n            $goResearch = ($coverBefore.Exit -ne 0)」
:598-599 「        $baseOk = $true\n        if ($Tier -eq 2) { $baseOk = ($after.Unticked -eq 0 -and $lint.Exit -eq 0) }」

【未勾項零違規——scripts/ps-doc-lint.ps1】
:220 「    # 1) checklist 對帳：打勾項的目標檔必須存在；NN 檔必須被 checkl…
```

**建議最小修法**：最小修法分兩刀，都不新增 lint 檢查（守 SOP-16:318 標準凍結紀律）、也不把 tier 1 門綁回未勾數（避免重蹈 L50 活鎖）：

(1) 讓斷言有機械支撐——改 scripts/ps-auto-loop.ps1 的 Get-ChecklistState（:127-138）：除 `$unticked` 外，用已存在的格式約定（checklist-template.md:15）多算兩個值，`$untickedAudit = @($lines | Where-Object { $_ -match '^\s*-\s*\[ \]\s*A\d' }).Count`、`$untickedOriginal = $unticked - $untickedAudit`；:607 與 :682 的訊息改成報分項，並把「屬補強類」這句設成條件式——`$untickedOriginal -eq 0` 才印原句，否則印「其中 <Z> 項為原始盤點／人工加項（從未研究，tier 1 不保證這些功能查得到），留待 tier 2」。純訊息與計數變更，不動門判定，故不必 bump GateVersion。

(2) 把超賣的保證改成真話——SOP.md:298 與 README.md:208 的「功能查得到」改為「**已建檔功能**查得到」，並在 SOP-16 的 tier 1 區塊（SOP.md…


### M15. peoplesoft/README 宣稱「現行 MCP 對映（三個）」，現實是四個 server（PeoplecodeMetadata 已整合啟用），且與根 README 的「四個資料源」互相打架

**涉及**：.opencode/peoplesoft/README.md, README.md, .opencode/agent/ps-ui-flow.md, .opencode/agent/ps-auditor.md

**指控**：peoplesoft/README 兩處宣稱現行只有三個 MCP、orchestrator「對三個 MCP 全 deny」，但 agent 檔顯示第四個 server PeoplecodeMetadata 已整合：ps-ui-flow / ps-metadata-flow / ps-auditor 對它明確 `true`（有專屬使用規則與 F5 測試情境「整合後紀律」），ps-deep-research 自述「本 agent 對四個 MCP 全部 deny」。根 README 也寫「四個資料源…各自是獨立 server」。在 L1（tools map 是覆寫表，沒列＝預設開）的世界裡，「現在有幾個 server」是圍堵體系的地基事實，兩份對外文件卻各說各話，且架構總覽是過期的那份。test-scenarios.md 的已知限制節（line 649）同樣停留在「現行真實環境三個 MCP」。（與另兩筆「三個 MCP」的差異：本筆落在架構總覽＋根 README 的互相打架，修法是同步兩份對外文件與 test-scenarios 的已知限制節。）

**驗證**：我逐檔打開驗證，指控引用的每一行都存在且如實。關鍵事實：

1. **peoplesoft/README.md（根 README:48 明文稱它為「架構總覽」）完全不知道第四個 server 存在。** 我對該檔 grep `Metadata` 得到**零命中**（全檔 304 行）。它在 :114 列舉「現行 MCP 對映（三個）」，在 :121 說「orchestrator 對三個 MCP 全 deny」。

2. **這兩處不是可被範圍化解的模糊敘述，而是圍堵指令本身。** :114 的上下文明說「tools 白名單用 `"<註冊名>_*"` wildcard，前綴必須與 opencode.json 的 mcp 註冊 key 完全一致」——它自我定位為**註冊表對映**，不是「證據三源」的子集；:121 更是緊接在「不該用某 server 的 agent 必須明確設 false，不能靠不列」之後，正是 L1 覆寫表教義的落地示例。全檔無任何豁免或範圍限縮文字。

3. **:121 是可證偽的事實陳述，而它是錯的。** ps-orchestrator.md 實際 deny **四個**（:21/:22/:23/:25）。

4. **第四個 server 早已正式整合啟用**，不是待辦：四個 agent 檔設 `true` 並各有專屬使用規則（ps-ui-flow:20、ps-auditor:19、ps-metadata-flow:23，另 ps-ae-flow:22 指控未列），lessons/applied.md 有「正式整合（2026-07-27）」條目，test-scenarios.md:347 有 F5「整合後紀律」，subagent-report-contract.md:34、oracle-query-cookbook.md:32 都已納入。

5. **兩份對外文件確實互相打架**：根 README:326-328「四個資料源…各自是獨立 server」vs 架構總覽「三個」。而且**根 README 自己也內部打架**（:117「把三個檢索 MCP…

**原文佐證**：
```
【過期的架構總覽——本筆核心】
/home/user/MCPSample/.opencode/peoplesoft/README.md:114
「- **現行 MCP 對映（三個）**：`PeoplecodeElasticSearch`（搜 chunk ids，候選）、」
/home/user/MCPSample/.opencode/peoplesoft/README.md:115-116
「  `PeoplecodeSource`（chunk id → 完整上下文，Evidence）、`oracleMCP`（PeopleTools metadata：…）」
/home/user/MCPSample/.opencode/peoplesoft/README.md:117-118（證明 :114 自我定位為註冊表，非「證據三源」子集）
「  tools 白名單用 `"<註冊名>_*"` wildcard，前綴必須與 opencode.json 的 mcp 註冊 key 完全一致（含大小寫）。」
/home/user/MCPSample/.opencode/peoplesoft/README.md:118-121（錯誤陳述緊貼 L1 教義）
「**注意：OpenCode 的 tools 是覆寫表，沒列出的工具預設開啟——不該用某 server 的 agent 必須明確設 `false`，不能靠不列**（orchestrator 對三個 MCP 全 deny，主 context 物理上碰不到 chunk / SQL）。」
※ 我對該檔全文 grep 「Metadata」＝**0 命中**（檔長 304 行），第四個 server 在架構總覽中完全不存在。

【:121 的事實錯誤——orchestrator 實際 deny 四個】
/home/user/MCPSample/.opencode/agent/ps-orchestrator.md:21-25
「  "PeoplecodeElasticSearch_*": false
  "PeoplecodeSource_*": false
  "oracleMCP_*": false
  # 尚未整合的新 MCP 一律先 deny（tools map 是覆寫表：沒列＝預設開）：
  "PeoplecodeMetadata_*": false」

【第四個 server 已整合啟用，且有專屬紀律】
/home/user/MCPSample/.opencode/agent/ps-ui-flow.md:18-20
「  # Pe…
```

**建議最小修法**：同步三處過期計數為「四個」：(1) `.opencode/peoplesoft/README.md:114` 改標題為「**現行 MCP 對映（四個）**」並補上第四項 `PeoplecodeMetadata`（`find_field_usage`／`search_component_metadata`；免連線定位線索，**不作 evidence**，證據仍走 ES/Source/oracleMCP），同檔 :121 的「orchestrator 對三個 MCP 全 deny」改為「四個」；(2) `README.md:117` 的「三個檢索 MCP」改為「四個檢索 MCP」，與同檔 :326「四個資料源」對齊；(3) `.opencode/peoplesoft/test-scenarios.md:649` 的「現行真實環境三個 MCP」改為「四個 MCP」並補一句指向 F5（PeoplecodeMetadata 僅作定位）。附帶把 `ps-orchestrator.md:24` 與 `ps-deep-research.md:18` 的過期註解「尚未整合的新 MCP 一律先 deny」改為「已整合但不歸本 agent 的 MCP 一律 deny」（deny 值本身正確，不動）。治本作法：在 `scripts/ps-doc-lint.ps1` 加一條機械檢查——以 agent 檔 t…


### M16. 強殺判讀只指向 SOP-12 通道排查，遺漏框架自認的 headless 頭號無聲死鎖（L60 權限 ask）——症狀相同、log 無痕，人被導去查錯的東西；Preflight 也不驗 SOP-17 第 0 條前提

**涉及**：scripts/ps-auto-loop.ps1, .opencode/peoplesoft/SOP.md, .opencode/peoplesoft/lessons/applied.md

**指控**：L60 確立：headless 下權限 ask（doom_loop/external_directory，或未來新增的任何 ask）＝永遠阻塞、提示畫在 TTY、log 一個字都看不到、唯一症狀是「輸出靜止」。但 auto-loop 的強殺當下判讀對「靜止 ≥20 分」這個簽名只給一條路：「疑似卡在工具呼叫——依 SOP-12 查 oracleMCP／模型服務通道」；心跳提示（267 行）同樣只指 SOP-12。ask 死鎖與 MCP 通道死的可觀測簽名完全相同，判讀卻只列其一，停機理由「連續 2 次逾時（需人工看 session log）」指向的 log 依 L60 什麼都沒有——這違反 L59 自己的原則（判讀要寫在事件發生的那一行，因為兩種成因的處置完全相反）。同時 -Preflight 的宣示目的為「把跑到一半才爆的問題前移」，卻不檢查 SOP-17 第 0 條這個 SOP 自己標為【必要前提】（不設就會每晚卡死一次）的設定。

**驗證**：親自開檔逐行核對，指控的兩半都屬實，且不是盲掃誤讀。

(1) 強殺判讀確實只列兩因、漏掉 L60。ps-auto-loop.ps1:283-301 的三分支只有「靜止≤5＝上限太短」「靜止≥20＝疑似卡在工具呼叫→SOP-12」「中間＝看 out 檔尾端」。而 applied.md:1270-1271 記載 L60 的實際症狀就是「audit session 做完 13/15 檔（約 10 分鐘）後輸出永遠靜止，60／90／120 分三種上限都一樣撞滿」——這條路徑百分之百落進 killSilent≥20 分支，被印上「依 SOP-12 查 oracleMCP／模型服務通道」。

(2) 這個轉介確實把人導去查錯的東西，而且框架自己已經記過這個錯。我讀了 SOP-12 全文（SOP.md:410-432）：快篩三步是「VS Code 與 extension 活著？／無並發時直通測 SELECT 1／只有並發時失敗＝搶用」，通篇沒有一個字提 permission／ask／headless。applied.md:1278-1279 明寫「接著懷疑通道死。但另開 console 測 MCP 正常——這其實不能證明什麼（新 session 開新連線，測不到卡住那個 session 手上那條）」——也就是說 SOP-12 那條路在 L60 成因下已被實證為無效路徑（該次定位共燒 4.5 小時）。

(3) 停機理由與 log 可見性互斥。ps-auto-loop.ps1:480 的 stopReason 是「連續 2 次逾時（需人工看 session log）」，但 applied.md:1286-1287 明寫「權限提示是畫在 TTY 上的互動元件，stdout/stderr 重導到檔案後在 log 裡一個字都看不到」，SOP.md:347 同樣寫「提示在 log 裡看不到」。指向的 log 在該成因下必然空手而回。

(4) 這違反的是框架自己的 L59。applied.md:1242 標題「判讀要寫在事件發生的那一行——事後翻心跳拼真相，等於沒有儀器」，1265-1266…

**原文佐證**：
```
— 強殺判讀（我讀到的原文）
/home/user/MCPSample/scripts/ps-auto-loop.ps1:296-298
    elseif ($killSilent -ge 20) {
        Write-Log "SESSION($Tag) 判讀：輸出已靜止 $killSilent 分才被強殺＝**疑似卡在工具呼叫**——依 SOP-12 查 oracleMCP／模型服務通道，調高上限沒有用"
    }
（同函式內三分支 283-301，無任何 permission／L60 分支）

/home/user/MCPSample/scripts/ps-auto-loop.ps1:267
    $note = if ($silent -ge 20) { "；輸出已靜止 $silent 分（委派期間長時間無輸出屬常態，實測健康可達 30 分；接近逾時上限仍無輸出才需依 SOP-12 查 oracleMCP 通道）" } else { "" }

/home/user/MCPSample/scripts/ps-auto-loop.ps1:480
    if ($timeoutStreak -ge 2) { $stopReason = "連續 2 次逾時（需人工看 session log）"; break }

— 被指向的 SOP-12 全文，沒有 ask／permission 分支
/home/user/MCPSample/.opencode/peoplesoft/SOP.md:426-429
    □ 快篩三步：(1) VS Code 與 SQL Developer extension 活著？
      (2) 無並發時 build 模式直通測試（叫它用 oracleMCP 查 SELECT 1）
      (3) 只有並發時失敗＝搶用確認，錯開時間即可
    □ 通道死透（無並發也失敗）→ 重啟 VS Code／extension 再測

— 框架自己記載這條路無效
/home/user/MCPSample/.opencode/peoplesoft/lessons/applied.md:1278-1279
    2. 接著懷疑通道死。但另開 console 測 MCP 正常——這其實不能證明什麼
       （新 session 開新連線，測不到卡住那個 session 手上那條）。

— 症狀簽名相同（必然落進 ≥20 分支）
/home/user/MCPSample/.opencode/peoplesoft/les…
```

**建議最小修法**：一、把 L60 補進判讀那一行：ps-auto-loop.ps1:296-298 的 ≥20 分支改成先列權限死鎖再列通道，例如「輸出已靜止 $killSilent 分才被強殺＝**無聲阻塞**——(1) 先確認本機全域 ~/.config/opencode/opencode.json 的 permission.doom_loop／external_directory 皆非 ask（SOP-17 第 0 條；提示畫在 TTY，log 裡看不到，另開 console 測 MCP 正常不能排除它）；(2) 排除後再依 SOP-12 查 oracleMCP／模型服務通道。調高上限對兩者都沒用」；267 行心跳提示與 480 行 stopReason（改為「連續 2 次逾時（先驗 SOP-17 第 0 條權限，再看 session log）」）同步改。二、Preflight 補一條唯讀檢查：在 389-390 之間讀 $env:USERPROFILE\.config\opencode\opencode.json，取 permission.doom_loop／external_directory，兩者皆為 allow/deny 才印綠字，缺檔、缺鍵或值為 ask 一律印紅字「headless 會死鎖（SOP-17 第 0 條），不是可選項」——檔案不在預期路徑時降級為黃字警告並要求人工確認（…


### M17. 打勾語法兩套文法：auto-loop 認 [xX]，doc-lint 對帳只認小寫 [ x]——「- [X]」列被外環算已勾、被 lint 判成該檔未列於 checklist

**涉及**：scripts/ps-auto-loop.ps1, scripts/ps-doc-lint.ps1

**指控**：ps-auto-loop 的 Get-ChecklistState（133 行）明確接受大寫勾「\[[xX]\]」（顯示已預期模型會寫 [X]）；但 ps-doc-lint 的 checklist 對帳 regex（222 行）與功能地圖 diff（245 行）都只認「[ x]」小寫。一列「- [X] … → 10-foo.md」：外環算已勾（tier 2 相位判「全勾→audit」會採計）、Get-ItemTotal 一致性總數也採計（174 行 `\[` 任意），但 lint 對帳完全看不見這列——目標檔存在時被誤判「檔案未列於調查進度 checklist」（233 行，缺料類違規，直接擋 tier 1/tier 2 門且無手術工單）、目標檔不存在時「已打勾但檔案不存在」永不觸發。兩腳本讀同一份 checklist 用了不相容的文法，lint 的機械稽核結論與駕駛的機械相位判定可以對同一列各執一詞。

**驗證**：親自開檔逐行核對，指控的機械事實全部成立，且比審查者寫的更嚴重。

【核心不對稱是語言層級的，不只是字元類寫錯】
ps-auto-loop 用 PowerShell `-match` 運算子（預設**大小寫不敏感**），ps-doc-lint 用 `[regex]::Matches()`（.NET API，預設**大小寫敏感**，兩行都沒傳 RegexOptions）。所以：外環就算把 `[[xX]]` 寫成 `[x]` 照樣吃下 `[X]`；lint 就算作者本意想吃大寫也吃不到。這不是一個字元的筆誤，是兩套 API 預設值的結構性歧異——修掉 133 行的 `[xX]` 並不會讓兩邊對齊。

【我實際查證的三件事，審查者沒查】
1. 全 repo 沒有任何正規化：ps-doc-lint 內 `(?i)` 只出現在 364 行（SELECT）與 480 行（partial_pass），與 checklist 無關；無 ToLower。我盤點了 scripts/ 全部 5 條打勾框 regex（auto-loop:132/133、doc-lint:213/222/245），lint 側 3 條全是小寫或純空白。
2. 沒有任何 lint 規則會抓「勾選框語法錯誤」。checklist 專屬檢查只有 187 行（缺節標題）與 213 行（archive 含未勾項），都不看勾號大小寫。所以 `[X]` 不會被點名、不會產生可修的訊息。
3. 這條違規確實擋雙門且無工單：`檔案未列於調查進度 checklist` 不在 `$polishPatterns`（631-642），CoverageOnly（650-657）只降級白名單內的美工類，它被 `$kept` 留下 → tier 1 的 CoverageOnly 綠亮不起來；tier 2 的 `$lint.Exit -eq 0`（599）同樣卡住。手術工單區塊（681）的觸發條件只有 truncatedIds／missingIds／leakDelegable／misplacedRefRows 四類，這條完全不進單。

【對審查…

**原文佐證**：
```
【外環：大小寫不敏感，`[X]` 算已勾／不算未勾】
scripts/ps-auto-loop.ps1:132-133
    $unticked = @($lines | Where-Object { $_ -match '^\s*-\s*\[ \]' }).Count
    $ticked = @($lines | Where-Object { $_ -match '^\s*-\s*\[[xX]\]' }).Count
（`-match` 為 PowerShell 運算子，預設大小寫不敏感）

【外環：相位與門走 Unticked，`[X]` 使其歸零】
scripts/ps-auto-loop.ps1:371
    $ph = if ($st.Unticked -gt 0) { "research（消化 $($st.Unticked) 個未勾項）" } else { "audit（全勾→直接進稽核）" }
scripts/ps-auto-loop.ps1:599
    if ($Tier -eq 2) { $baseOk = ($after.Unticked -eq 0 -and $lint.Exit -eq 0) }

【lint：大小寫敏感 API＋只認小寫，`[X]` 完全不可見】
scripts/ps-doc-lint.ps1:220-227
    # 1) checklist 對帳：打勾項的目標檔必須存在；NN 檔必須被 checklist 列到
    $listed = @{}
    foreach ($m in [regex]::Matches($checklistSrc, '- \[(?<tick>[ x])\]\s+\S+.*?→\s*(?<file>\S+\.md)')) {
        $f = $m.Groups['file'].Value
        $listed[$f] = $true
        if ($m.Groups['tick'].Value -eq 'x' -and -not (Test-Path -LiteralPath (Join-Path $dir $f))) {
            $violations += "checklist 已打勾但檔案不存在：$f"
        }
    }
（`[regex]::Matches` 只傳兩個參數＝RegexOptions.None＝大小寫敏感）

scripts/ps-doc-lint.ps1:229-235
    Get-Ch…
```

**建議最小修法**：改 scripts/ps-doc-lint.ps1 兩處字元類，把大寫勾納入：222 行 `'- \[(?<tick>[ x])\]…'` → `'- \[(?<tick>[ xX])\]…'`，且 225 行的判斷改為 `$m.Groups['tick'].Value -ne ' '`（原本 `-eq 'x'` 會讓 `[X]` 列漏掉「已打勾但檔案不存在」檢查）；245 行 `'- \[[ x]\]…'` → `'- \[[ xX]\]…'`。若要根治語法漂移，再於 181 行的 checklist 檢查區加一條機械規則：掃 `(?m)^\s*-\s*\[(?![ x]\])(.)\]`，命中即產違規「checklist 勾選框語法非法（只准 `[ ]` 或小寫 `[x]`），行 N」並附「把該列勾號改成小寫 x」的可執行修法，讓它有工單、不再是無解訊息。


### M18. 150 行單次寫檔上限 vs 90-audit「整檔重寫＋非過判定每筆一列」：大規模失敗輪（L64 成批查無）無拆檔出口，畢業門 hash 又綁死這個檔

**涉及**：.opencode/agent/ps-deep-research.md, scripts/ps-auto-loop.ps1, .opencode/peoplesoft/report-templates/audit-template.md

**指控**：五份模板本身皆 ≤77 行（audit 63、function-detail 77），不撞上限；衝突在 90-audit 的規定內容：明細表要求「三種非過判定每筆一列——UNVERIFIABLE 也要列」且整檔單次重寫，而 150 行上限的拆檔出口只給 NN 檔（拆 NN-*-2.md），90-audit 沒有拆檔或分次寫的合法路徑（lint 的記分卡覆蓋與輪次檢查也只讀 90-audit.md 單檔）。在 L64 成批查無情境（15 檔全滅、每列證據皆非 PASS）明細列數必然遠超 150，寫入按 agent 自述會被截斷；「同一檔案寫入連續失敗 2 次 → 停止該項、checklist 標 ⚠」的出口對 90-audit 無意義，而 WORK_TRANSITION_OK 恰恰要求 90-audit.md hash 改變——大失敗輪寫不出合規報告、過不了轉移門，只剩 auditStall 熔斷。

**驗證**：我逐行打開三個被引用的檔案（外加 ps-doc-lint.ps1、ps-audit.md、ps-auditor.md、SOP.md、applied.md 交叉查證），指控引的每一句都逐字屬實，且**沒有任何檔案提供 90-audit 的拆檔／分次／合併出口**。

成立的四段閉環：
1. 90-audit.md 必須「整檔重寫」（ps-deep-research.md:199），明細表「三種非過判定每筆一列——UNVERIFIABLE 也要列」（:204-205），模板端同樣寫死「每一筆都要有一列」「不得只出現在記分卡數字」（audit-template.md:21-22）。列數隨判定數無上界成長。
2. 150 行上限的拆檔出口**只點名 NN 檔**（:270-273），全庫 grep「拆檔／續篇／150」在 .opencode/ 下只有這一處，90-audit 不在列。
3. 我另外查到框架**自己封死了唯一替代解**：「工具層沒有 append，『追加舊檔』實為整檔重寫」（:193-194）——所以「分兩次寫」在本框架定義下不存在，這條是我讀到的、指控沒引的加強證據。
4. 拆檔即使做了也會撞 lint：ps-doc-lint.ps1 只讀單檔 `$auditPath = Join-Path $dir "90-audit.md"`（:464），不存在直接判 StrictAudit 違規（:508），記分卡覆蓋率也只在該單檔文字內找（:499-503）；hash 門同樣只取該單檔（ps-auto-loop.ps1:156-158 → :569-571）。

而且觸發情境是框架**自己承諾會處理**的情境，不是我或審查者假想的：ps-auditor.md:56-61 與 SOP.md:464-468 明寫「整庫 chunk id 輪替＝所有領域證據全滅、第一輪 audit 預期成批查無」，且 SOP 要求「重建後第一輪要看 90-audit.md 的回灌清單」——偏偏那一輪的 90-audit.md 正是寫不出來的那一份。L64 的處置是「全部判 stale、逐筆走…

**原文佐證**：
```
【衝突的兩端，同一個 agent 檔內】
/home/user/MCPSample/.opencode/agent/ps-deep-research.md:199
「**整檔重寫** `90-audit.md`：表頭寫「稽核輪次：N+1」與本日日期；」
/home/user/MCPSample/.opencode/agent/ps-deep-research.md:204-206
「**明細表三種非過 / 判定每筆一列——UNVERIFIABLE 也要列，原因欄逐字取自 auditor 回報** / （只在記分卡出現數字、明細查無其列＝報告不完整）；」
/home/user/MCPSample/.opencode/agent/ps-deep-research.md:270-273
「- **單次寫檔上限約 150 行**：一次 write 的內容太長會讓工具呼叫本身 / 被截斷（畫面出現 invalid[tool=write] JSON Parse error）。NN 文件預估 / 會超過 → 拆 `NN-<物件名>-2.md` 續篇並互相連結；00-overview.md 只在 / 階段一寫一次；反覆改寫的狀態一律集中在小的 checklist.md。」
  → 出口只有 NN 檔；全庫 grep「拆檔｜續篇｜150 行」在 .opencode/ 僅命中此處與 SOP.md:219、applied.md:54 的同義複述，皆無 90-audit。

【框架自己封死「分兩次寫」這個逃生口——指控未引，我讀到的加強證據】
/home/user/MCPSample/.opencode/agent/ps-deep-research.md:193-195
「**禁止 read 或改寫任何既有 checklist-archive*.md**——工具層沒有 / append，「追加舊檔」實為整檔重寫，archive 隨輪次變大必撐爆 / write（卡死根因）；」

【失敗出口對 90-audit 無意義】
/home/user/MCPSample/.opencode/agent/ps-deep-research.md:274-276
「- **失敗就換策略，禁止重試迴圈**：同一檔案寫入連續失敗 2 次 → / 停止該項、checklist 標 ⚠（寫入失敗）、繼續下一項—— / 不得反覆重試同一個編輯。」

【模板端把「每筆一列」也寫死】
/home/user/MCPSample/.opencode/peoplesoft/report-templates/audit-t…
```

**建議最小修法**：在 /home/user/MCPSample/.opencode/agent/ps-deep-research.md 步驟 4（:204-206「每筆一列」那句）後面明文加一條體積出口，並在 audit-template.md:21-23 的註解同步一句：「同輪、同檔、同原因的非過判定（典型即 L64 成批 stale／ID_RELINK）**得合併為一列**，內容欄寫 id 範圍或筆數、原因欄逐字保留 auditor 原話，並在列末註明『合併 N 筆』；明細表硬上限 60 列，仍超過時只保留每檔各原因的代表列，其餘移到 `90-audit-detail-r<N+1>.md` 續篇（單獨小 write）並在 90-audit.md 明細節留一行連結與合計。」——記分卡、回灌節、表頭一律仍留在 90-audit.md，所以 ps-auto-loop.ps1:569-571 的 hash 門與 ps-doc-lint.ps1:499-503 的覆蓋率檢查都不需要動。同時把 :270-273 那條 150 行規則的拆檔句從只列 NN 檔改為「NN 文件拆續篇；90-audit.md 明細超量走步驟 4 的合併／續篇規則」，讓上限規則本身指得到出口。


### M19. SOP-9 末條的熔絲敘述與實作不符：手術 session 逾時不計入「連續 2 次逾時」熔絲；且「覺得反應太慢可調短 timeout」撞上框架自己的 L48/L59『逾時是熔絲不是效能參數、照實測基線設』與 Research/手術共用上限

**涉及**：.opencode/peoplesoft/SOP.md, scripts/ps-auto-loop.ps1

**指控**：SOP-9 宣稱鬼打牆在 auto-loop 下由「強殺→一致性檢查→下圈 fresh 重跑→連續 2 次才熔斷給人工」處理；但程式對手術 session 的逾時只記 log、續跑，不累計 timeoutStreak——退化的手術 session 每圈可白燒 60 分而永遠不觸發該 2 次熔斷（僅靠清單未縮短 break 與相位熔絲間接止血）。同條接著建議「覺得反應太慢可調短 -ResearchTimeoutMin／-AuditTimeoutMin」，直接違反同一支腳本註解裡的鐵律（逾時照實測基線設；30 分上限曾砍掉健康 session；改 ResearchTimeoutMin＝同步縮手術上限；audit 設窄＝永遠量不到真實時長）——SOP 邀請的正是 L48/L59 明文禁止的憑感覺調窄。

**驗證**：我逐行開檔核對，兩半指控都成立，而且我特地去找了「有沒有別的熔絲間接接住」的反駁路徑，結果反而排除了它。

第一半（手術逾時不計入 2 次熔絲）：`grep -n timeoutStreak scripts/ps-auto-loop.ps1` 全檔只有 4 個命中——418（初始化 0）、479（++）、480（>=2 熔斷）、483（歸零）。479-483 位在 research/audit 那一段（`if ($r.TimedOut)`）。手術 session 的逾時分支在 539-547（`if ($sr.TimedOut)`），一致性檢查 PASS 後只有一行 Write-Log 就落到 `$lint2 = Invoke-Lint`，全程沒有任何計數器遞增。所以 SOP-9 的「連續 2 次才熔斷給人工」對手術 session 永不成立——事實正確。

我進一步查了兩個可能接住它的跨圈熔絲，兩個都接不住：
- audit 相位熔絲（626-639）在 `$after.Unticked -gt 0` 時 `$auditStall = 0` 歸零。而腳本自己在 516 註明「tier 1 的相位多半是 audit」、L50 記錄稽核「一輪回灌 11 項」——穩態下每圈都有回灌，auditStall 永遠歸零。
- noProgress 熔絲（668-673）只在 `else`（research 相位）分支裡，而且量的是「缺料違規數」的圈前後差，不看手術 session 燒了多久。research 只要有推進就歸零。
結論：research/audit 正常推進、手術 session 退化的組合下，每圈白燒一個 ResearchTimeoutMin（預設 60 分），唯一的止血是 552-556 的「清單沒變短就 break」（只省下同圈第 2、3 批）與 MaxCycles=20 的硬上限。最壞 20 圈 × 60 分 ≈ 20 小時，停機原因還會寫成「圈數上限」，完全不指向真因。指控說的「僅靠清單未縮短 break 與相位熔絲間接止血」描述精確。

第二半（調短 t…

**原文佐證**：
```
【SOP 端·指控引用的原文，我親自讀到】
/home/user/MCPSample/.opencode/peoplesoft/SOP.md:239-244
```
□ subagent 鬼打牆（不斷重複相同產出、沒有盡頭）＝退化迴圈（L34）：
  **不用等，直接中斷、開新 session 重跑**——checklist 未勾＝進度
  不會丟，fresh session 通常一次就過（抽樣事故非確定性障礙）。
  auto-loop 下不需人工：逾時熔絲自動處理（強殺→一致性檢查→
  下圈 fresh 重跑→連續 2 次才熔斷給人工）；覺得反應太慢可調短
  -ResearchTimeoutMin／-AuditTimeoutMin
```

【程式端·熔絲只長在 research/audit 路徑】
`grep -n "timeoutStreak" /home/user/MCPSample/scripts/ps-auto-loop.ps1` 全檔僅 4 命中：
```
418:$timeoutStreak = 0
479:        $timeoutStreak++
480:        if ($timeoutStreak -ge 2) { $stopReason = "連續 2 次逾時（需人工看 session log）"; break }
483:    $timeoutStreak = 0
```
478-481（research/audit 的 `if ($r.TimedOut)` 內）：
```
478:        Write-Log "強殺後一致性檢查 PASS（唯讀）——維持既有重試邏輯"
479:        $timeoutStreak++
480:        if ($timeoutStreak -ge 2) { $stopReason = "連續 2 次逾時（需人工看 session log）"; break }
481:        continue
```

【程式端·手術逾時分支：無任何計數器】
/home/user/MCPSample/scripts/ps-auto-loop.ps1:539-548
```
539:        if ($sr.TimedOut) {
540:            $fsProblems = Test-FsConsistency -HadChecklist $preHadChecklist -PreItemTotal $preItemTotal
541:…
```

**建議最小修法**：兩處各一刀，程式一刀、文件一刀。

(1) 程式補人工出口（scripts/ps-auto-loop.ps1:546）：把 `Write-Log "手術 session 逾時強殺——一致性檢查 PASS，續跑"` 換成累計獨立計數器並熔斷，例如在迴圈外初始化 `$surgeryTimeoutStreak = 0`（比照 418），546 改為 `$surgeryTimeoutStreak++; Write-Log "手術 session 逾時強殺——一致性檢查 PASS，續跑（$surgeryTimeoutStreak/2）"; if ($surgeryTimeoutStreak -ge 2) { $stopReason = "連續 2 次手術 session 逾時（需人工看 surgery session log）"; $fatalStop = $true; break }`，並在手術 session 未逾時的路徑（548 的 elseif 之後或 549 之前）歸零。理由：現行 626-628 的 auditStall 每圈被回灌歸零、668-673 的 noProgress 只看缺料數，兩者都接不住每圈白燒 60 分的退化手術 session，違反 L53「必須配可執行修復路徑或明確人工出口」。

(2) 文件改回實測基線（.opencode/peoplesoft/SOP.m…


### M20. 缺 00-overview 而 checklist 完好時，auto 迴圈的「修復」是重跑階段一——階段一無 checklist 既存防護，會依模板重寫 checklist.md 銷毀進度，且正常收場不觸發任何一致性檢查

**涉及**：.opencode/agent/ps-deep-research.md, .opencode/command/ps-research.md, scripts/ps-auto-loop.ps1, scripts/ps-doc-lint.ps1

**指控**：lint 對「缺 00-overview.md」配的人工出口是 fs-doctor／SOP-4 git 還原，但 headless 迴圈不會走人工出口：Invoke-Lint 見 overview 缺檔回 -1→tier-1 相位判 research→/ps-research 規則「不存在→立刻執行階段一」→階段一步驟 3 明文「並依 checklist 模板寫 checklist.md」，而規則只寫了單向遷移（overview 有、checklist 無），完全沒有「checklist 已存在則保留」的反向防護——現存未勾項與 Gaps 會被模板覆寫。外環的 Get-ItemTotal 不變量（「打勾項歸檔只會移動、不會消失」）只在強殺/session 錯誤後檢查，正常 exit 0 的破壞性覆寫無人攔截；下一圈起迴圈把整個領域當新領域重查，收據自然失效、進度靜默歸零。自動路徑與 SOP-4 的人工還原配對互撞：機器搶在人工之前用破壞性方式「修復」了本該 git 還原的狀態。

**驗證**：每一環我都親自打開讀過，鏈條完整成立，且比指控寫得更嚴重一點。

(1) 相位判定：Get-ChecklistState 的 Exists 指的是 **checklist.md**（ps-auto-loop.ps1:127-130），所以「checklist 完好」時 `$goResearch = (-not $before.Exists)` 為 false；接著 tier 1 走 Invoke-Lint -Coverage，而 Invoke-Lint 第一件事就是 overview 缺檔即 `return @{ Exit = -1 }`（333-334），於是 `$goResearch = ($coverBefore.Exit -ne 0)` 為 true → 開 `--command ps-research`（450-461）。tier 2 只要未勾>0 也同樣進 research（455）。指控引的行號全部正確。

(2) 內步：ps-research.md:10-13 只檢查 00-overview.md，不存在＝「立刻執行階段一」；ps-deep-research.md:61-63 階段一步驟 3 明文要寫 checklist.md，而 42-49 的啟動／遷移規則只有「overview 存在但 checklist 不存在」這個單向分支——我 grep 過整份 agent 與 command 檔，**沒有任何一句「checklist 已存在則保留／禁止覆寫」**。唯一沾邊的是 266-269 的「小檔一律整檔覆寫…必須保留原有其他內容一字不動」，但那條講的是「打勾／維護型寫入」的機制，不是階段一建檔的前置條件，對小模型不構成機械防護（框架自己的 L0：能機械化就不寫 prose）。

(3) 無人攔截：grep 全檔，Test-FsConsistency 只有三個呼叫點 472（逾時）、502（session 錯誤）、539（手術逾時），全在強殺／錯誤路徑；正常 exit 0 完全不驗。而它正是唯一會抓到這件事的檢查（191-194 比對 Get-ItemTo…

**原文佐證**：
```
【外環：checklist 存在也會被判 research】
/home/user/MCPSample/scripts/ps-auto-loop.ps1:127-130
    $clPath = Join-Path $dir "checklist.md"
    if (-not (Test-Path $clPath)) {
        return @{ Exists = $false; Unticked = -1; Ticked = -1; Round = -1 }
    }
/home/user/MCPSample/scripts/ps-auto-loop.ps1:333-334
    if (-not (Test-Path (Join-Path $dir "00-overview.md"))) {
        return @{ Exit = -1; Surgical = @(); Raw = "（領域尚未建立，略過 lint）" }
/home/user/MCPSample/scripts/ps-auto-loop.ps1:447-452
    $goResearch = (-not $before.Exists)
    if (-not $goResearch) {
        if ($Tier -eq 1) {
            $coverBefore = Invoke-Lint -Coverage
            $goResearch = ($coverBefore.Exit -ne 0)
/home/user/MCPSample/scripts/ps-auto-loop.ps1:459-461
        $phase = "research"
        $r = Invoke-Opencode -ExtraArgs '--command ps-research' -PromptText $Domain `

【內步：階段一無條件重寫 checklist】
/home/user/MCPSample/.opencode/command/ps-research.md:13-14
- **不存在** → 立刻執行系統提示的「階段一：盤點」——下一個動作是
  read `.opencode/peoplesoft/customization-profile.yaml`。
/home/user/MCPSample/.opencode/agent/ps-deep-research.md:61-63
3.…
```

**建議最小修法**：在 ps-auto-loop.ps1 的相位決定前（第 446 行 `$coverBefore = $null` 之後、458 行 `if ($goResearch)` 之前）加確定性守門：`if ($before.Exists -and -not (Test-Path -LiteralPath (Join-Path $dir "00-overview.md"))) { Write-Log "CONSISTENCY FAIL：checklist.md 存在但 00-overview.md 缺——階段一會依模板覆寫 checklist 銷毀進度；本圈拒跑，走 SOP-4 git 還原／ps-fs-doctor"; $stopReason = "缺 overview 但 checklist 有進度（人工 SOP-4 還原後再啟動）"; break }`（同時把 333 行的 Test-Path 改 -LiteralPath，以免含 `[]` 的領域名誤觸）。並在 ps-deep-research.md:61-63 步驟 3 補一句反向防護：「checklist.md **已存在則一字不動、只補寫 00-overview.md**——現有未勾項與 Gaps 一律保留，不得依模板重建」。


## 次要（minor）　30 筆

### M1. L56 型別綁定出口 vs 手術 prompt 的無型別「或」出口：CHUNK 型可被合法停在「待人工SQL」且漏掉 INFERRED 降級

**涉及**：scripts/ps-auto-loop.ps1, .opencode/agent/ps-deep-research.md, scripts/ps-doc-lint.ps1

**指控**：L56 規定出口按型別走：SQL/metadata 型 → 待人工SQL；CHUNK 型 → 移除該列＋主張降級 INFERRED。手術 prompt 卻給無型別的二選一（「舊值 → 待人工SQL」或「移除入gaps」），且完全沒提 INFERRED 降級——模型可把 CHUNK 型死路標成待人工SQL（管理者自跑 SQL 永遠生不出 chunk id）或移除列後留 CONFIRMED 主張。lint 的 okPending 對待人工SQL 也不驗型別，該列從此綠燈；auditor 任務 A 不驗待人工SQL 列，無人能清。lint 自己印的 C 分支「A 與 B 都取不到 → 移除＋降級 INFERRED」又與同段「先判型別再動手（判錯型別＝白做）」矛盾——先判型別下 A/B 互斥，「A 與 B 都取不到」的前提不成立。三份出口規格互不一致，而實際到達手術模型的只有最寬鬆的那份（$surgical 只擷取編號行，lint 的說明區塊不進 prompt）。

**驗證**：核心指控成立，但論證鏈有一半是誤讀，故降級。

【成立的部分（我親自讀到）】L56 的出口確實是型別綁定的，且這條規則在三個模型看得到的地方一致：ps-deep-research.md:135-137、function-detail-template.md:72-74、lessons/applied.md:1179-1181，全部寫「SQL／metadata 型→待人工SQL；CHUNK 型→移除該列＋降級 INFERRED」。而 ps-auto-loop.ps1:533 的 $sPrompt 出口子句是「皆不可得＝該筆輸出收據『舊值 → 待人工SQL』或『移除入gaps』後停止該筆」——逐字比對：沒有把兩個出口綁到型別上，也完全沒有「降級 INFERRED」四個字。這不是措辭差異：同一行上方的註解（ps-auto-loop.ps1:529）自宣「L43：prompt 與 lint 工單同步——先判型別再動手」，而 lint 工單（ps-doc-lint.ps1:755-758）確實有第三條路 C（移除＋降級 INFERRED），prompt 卻只搬了 A/B 沒搬 C 的降級動作——這正是框架自己 L42 追記（applied.md:817-825）定性的「只改一半的機械化＝製造兩個互相矛盾的指示」。後果可驗證：lint 對 confidence 只做存在性檢查（ps-doc-lint.ps1:283 `if ($text -notmatch 'CONFIRMED|INFERRED|DYNAMIC_RUNTIME')`），一條被移除證據列的主張若仍掛 CONFIRMED，機械面完全抓不到，只剩 auditor 任務 B 抽 3~5 條的抽樣。

【被我推翻的部分】
1. 「lint 自己印的 C 分支與同段『先判型別再動手』矛盾」＝誤讀。B 路線在 :755-756 自帶出口（委派後仍不可得→待人工SQL），C 在 :757 承接的是 A 路線失敗與型別判不出的列——這剛好等於 L56 的「CHUNK 型取不到→移除＋INFERRED」。applied.md:820-…

**原文佐證**：
```
/home/user/MCPSample/.opencode/agent/ps-deep-research.md:133-137：「**查不到時的合法出口（L56）**：機器參照欄只准放三種東西——完整 36 字元 ChunkId／可重跑的 `SELECT … FROM …`／`待人工SQL`。取不到證據時**照型別走對應出口**：SQL／metadata 型（查 DB 表）→ 寫 `待人工SQL`（管理者自跑後回填）；CHUNK 型（程式碼）→ **移除該列**並把該主張降級 INFERRED。」

/home/user/MCPSample/scripts/ps-auto-loop.ps1:533（$sPrompt 尾段，逐字）：「…SQL／metadata 型（DB 表如 PSPRCSRQST）＝委派具 oracleMCP 權限的 flow（ps-metadata-flow 等）照 cookbook 重查、機器參照改寫成 SQL：SELECT…、你自己沒有 SQL 工具是圍堵設計、禁止改查 peoplecode 代償；皆不可得＝該筆輸出收據「舊值 → 待人工SQL」或「移除入gaps」後停止該筆。」——全句無「INFERRED」，兩個出口未綁型別。

/home/user/MCPSample/scripts/ps-auto-loop.ps1:529（同段自宣同步）：「# L43：prompt 與 lint 工單同步——先判型別再動手、B 型委派 oracle flow、」

/home/user/MCPSample/scripts/ps-doc-lint.ps1:755-758（工單三條路，與 L56 一致）：「委派後仍不可得（通道忙／權限）→ 該筆輸出「舊值 → 待人工SQL」收據並**停止該筆**」／「 C. A 與 B 都取不到 → 該列移除、主張降級 INFERRED、未解事項記一行查法收據（查了什麼、怎麼查、結果）」

/home/user/MCPSample/scripts/ps-doc-lint.ps1:283（confidence 僅存在性檢查，抓不到未降級的 CONFIRMED）：「if ($text -notmatch 'CONFIRMED|INFERRED|DYNAMIC_RUNTIME') {」

/home/user/MCPSample/scripts/ps-auto-loop.ps1:534（手術 session 掛的是 ps-deep-research，故 L56 在 context 內——推翻「只有最寬鬆那份到達模型」）：「$…
```

**建議最小修法**：改 /home/user/MCPSample/scripts/ps-auto-loop.ps1:533 的 $sPrompt 出口子句：把「皆不可得＝該筆輸出收據「舊值 → 待人工SQL」或「移除入gaps」後停止該筆」換成型別綁定版，逐字對齊 lint:755-758 與 L56——「SQL／metadata 型委派後仍不可得＝輸出「舊值 → 待人工SQL」收據；CHUNK 型重取失敗＝移除該列、該主張降級 INFERRED、未解事項記一行查法收據，輸出「舊值 → 移除入gaps」收據；兩者皆停止該筆，CHUNK 型一律不得寫待人工SQL（管理者自跑 SQL 生不出 chunk id）」。（同時可把 lint:614/756 指向的「SOP-2 第 4 階」修成真正描述人工自跑 SQL 的 SOP 位置，屬另案。）


### M2. [欄位] 型指令「不要呼叫任何工具」使修復不可執行，並直撞 act-first「第一個回應必須是工具呼叫」

**涉及**：scripts/ps-auto-loop.ps1, scripts/ps-doc-lint.ps1, .opencode/agent/ps-deep-research.md

**指控**：手術 prompt 與 lint 對 [欄位] 型都寫「純編輯，不要重查也不要呼叫任何工具」，但工單只帶檔名＋行號（「N 列欄位錯放（行 x、y）」），不含列內容——不 read 就不知道欄位裡是什麼，不 write/edit 就搬不了欄位；read/write/edit 都是工具呼叫。逐字遵守＝任務不可執行；同時 agent 硬規則要求「收到任務後的第一個回應必須是工具呼叫」，若批次首筆是 [欄位] 型，系統 prompt 要求先呼叫工具、手術 prompt 禁止呼叫任何工具，兩令互斥（同一 prompt 的 [洩漏] 型又明示「read 該檔」，證明「任何工具」的字面範圍未被界定）。對宣稱的 3B-active 小模型與 headless 無人環境，這是 L53/L63 型的無出口指令。

**驗證**：我逐行打開三個檔，指控引用的每一句都逐字存在，且沒有任何明文豁免。(1) 工單確實只有檔名＋行號、零列內容（ps-doc-lint.ps1:704），而 auto-loop 餵給模型的 $flat 只擷取「^\d+\.」的編號行（ps-auto-loop.ps1:347-350），lint 那段【欄位】型的「現象／修法」解說用「  1)」「  現象：」開頭，一律擷取不到——所以自動迴圈裡模型手上只有「檔名＋行 x、y」。(2) 同一句話要求「純編輯…把可重跑的那一份搬到機器參照欄」卻同時說「不要呼叫任何工具」；欄位對調必須 read（不知道那兩行寫什麼）＋write/edit（搬），而該 agent 的 tools map 明確開了 read/write/edit（ps-deep-research.md:7-13），可見 read/write/edit 就是工具呼叫。逐字遵守＝不可執行。(3) 全 repo grep「不要呼叫任何工具／純編輯／不要重查」只有 3 個命中（ps-auto-loop.ps1:533、ps-doc-lint.ps1:691、728），沒有任何一處把「工具」界定成「檢索工具」，也沒有 read/write/edit 的明文豁免——而框架自己的 L63 正是「補救指示指定的路徑必須明文豁免，否則遞迴死路」，靠讀者自行推斷範圍在本框架的標準下不算數；同一段 prompt 的 [洩漏] 型又明寫「read 該檔」，證明作者在別型別是明說工具的，唯獨 [欄位] 沒界定。(4) 硬規則「第一個回應必須是工具呼叫（read／glob／task）」確實在 ps-deep-research.md:249-250，批次首筆若是 [欄位]（順序是 洩漏→欄位→證據，無洩漏時欄位就是第 1 筆）即為系統 prompt 與任務 prompt 互斥。唯一的抗辯是同句「純編輯」構成自我註解（可推論「工具」指檢索），但那是推論不是明文，對 Qwen3.6-35B-A3B、temperature 0.1 的小模型不可靠。severity 我下修為 minor：指控把它掛在 L…

**原文佐證**：
```
1) 禁令原文（手術 prompt）——/home/user/MCPSample/scripts/ps-auto-loop.ps1:533：
「[欄位] 型＝證據其實在位置欄、機器參照欄放的是標籤：**純編輯，不要重查也不要呼叫任何工具**，把可重跑的那一份（完整36字元ChunkId 或 SELECT…FROM…）搬到機器參照欄」
同一行、同一 prompt 對別型別卻明寫工具：「[洩漏] 型＝…：read 該檔看標記前後整個區塊有無被截斷」——證明「任何工具」的字面範圍未被界定。

2) 禁令原文（lint）——/home/user/MCPSample/scripts/ps-doc-lint.ps1:728：
「Write-Host "【欄位】型（**最便宜：純編輯，不要重查、不要呼叫任何工具**）："」

3) 工單只有檔名＋行號——/home/user/MCPSample/scripts/ps-doc-lint.ps1:704：
「Write-Host "$i. [欄位] ${fn}：$($lns.Count) 列欄位錯放（行 $($lns -join '、')）"」
且自動迴圈只吃編號行——/home/user/MCPSample/scripts/ps-auto-loop.ps1:349-350：
「$surgical = @($block -split "`r?`n" | Where-Object { $_ -match '^\s*\d+\.\s' } | ForEach-Object { $_.Trim() })」
（lint 的【欄位】型解說是「  現象：」「  修法：」開頭，擷取不到＝模型看不到列內容）

4) act-first 硬規則——/home/user/MCPSample/.opencode/agent/ps-deep-research.md:249-251：
「- **先做事，後說話**：收到任務後的第一個回應**必須是工具呼叫**
  （read／glob／task）——不得先輸出計畫、摘要或複述指令內容；
  說明留到有結果之後，且每次只簡短一行。」

5) read/write/edit 確實是本 agent 的工具（故「任何工具」字面上包含它們）——/home/user/MCPSample/.opencode/agent/ps-deep-research.md:6-13：
「# 與 ps-orchestrator 同樣不碰檢索 MCP（委派 subagent）；差異是本 agent 有筆（write/edit）
tools:…
```

**建議最小修法**：把兩處禁令的「工具」明文縮到檢索／委派，並明文豁免 read＋write：ps-auto-loop.ps1:533 的 [欄位] 段改成「**純編輯：不要重查、不要委派 task、不要用任何檢索工具；只准 read＋write**——read 該檔（工單已給行號）確認該列四欄內容後，整檔 write 覆寫搬欄位」；ps-doc-lint.ps1:728 的標題同步改成「【欄位】型（**最便宜：純編輯，只用 read＋write，不重查、不委派**）」。這同時消掉與 ps-deep-research.md:249-250「第一個回應必須是工具呼叫（read／glob／task）」的互斥（read 成為合法首呼叫）。


### M3. SOP-9 仍把 tool-call 約束解碼當「唯一高價值槓桿」並教人「找管理者開約束解碼」，但 SOP-2 已明載該路徑經公司政策否決（2026-08）為永久條件——升級出口是死路

**涉及**：.opencode/peoplesoft/SOP.md, .opencode/peoplesoft/lessons/applied.md

**指控**：SOP-2 升級梯 (3) 宣告約束解碼（SOP-10 第 5 步）被公司政策永久否決、「寫入不可靠是永久條件」；但 SOP-9 兩處未更新：仍指示管理者「打開」約束解碼並稱其為唯一高價值槓桿，且把「幾乎每呼叫都紅」這種最嚴重症狀的唯一處置寫成「找管理者開約束解碼」——照 SOP-2 這是做不到的事，等於 L53 型『擋得住症狀卻沒有可執行修復路徑』：該症狀在現行文件裡沒有合法出口。

**驗證**：親自開檔核對，四處引文全部屬實且無任何豁免或範圍限定。SOP.md 同一份檔案內：第 77-79 行宣告約束解碼經公司政策否決、寫入不可靠是「永久條件」；第 220-223 行仍以「服務端可做（管理者）…→ 打開」的祈使句指示啟用，且該括號明說「**本環境** 2026-07 探針…故約束解碼是唯一高價值槓桿」——是對本環境的斷言，不是對其他環境的泛論，故無法用「範圍不同」化解。第 231 行把最嚴重症狀的唯一處置寫成「找管理者開約束解碼」，指向 SOP-2 已判定做不到的動作。我 grep 全 .opencode/：「政策否決／公司政策／永久條件」只出現在 SOP.md:77-78 與 applied.md:605 兩處，SOP-9（及 SOP-10 第 5 步 SOP.md:270-274）確實漏改，無明文豁免＝符合「補救指示指向不可達路徑」型缺陷。但指控的加重理由有誤：它說「該症狀在現行文件裡沒有合法出口」，實際上 SOP.md:219（同檔失敗 2 次標 ⚠ 跳過、不會卡死）、224-225（反覆失敗改走 SOP-5 人工建檔）、以及 SOP-2 升級梯 74-85（模型查人工貼→人工直通，且自稱「標準程序不是例外」）都是針對此永久條件的合法出口，只是沒有從 231 那一行連過去。且 SOP-9 是人工看畫面的分流（開頭即「畫面出現 invalid[...]」），不是機器畢業門，headless 的卡死另由 L60／逾時熔絲（232-244）處理，故 L53 活鎖屬類比而非命中。結論：陳舊指示的矛盾成立（CONFIRMED），但只是兩行文件失同步、不擋門、不造成 headless 死鎖，故降為 minor。

**原文佐證**：
```
SOP.md:77-79「(3) 環境事實：tool-call 約束解碼（SOP-10 第 5 步）經公司政策／否決（2026-08）——寫入不可靠是**永久條件**，本升級梯是／標準程序不是例外」
SOP.md:220-223「□ 服務端可做（管理者）：推理伺服器若支援 tool-call 約束解碼／（vLLM auto tool choice／grammar、Ollama JSON mode 等）→ 打開，／可大幅降低 JSON 壞格率（**本環境 2026-07 探針已確認輸出上限充足／——數到 3000 能完成——故約束解碼是唯一高價值槓桿**）」
SOP.md:231「  幾乎每呼叫都紅（找管理者開約束解碼）」
applied.md:604-605「- 根因：(1) 寫入鏈不可靠且**不可修**——tool-call 約束解碼／（SOP-10 第 5 步、L8 認定的唯一高價值槓桿）經公司政策否決；」
（化解「無出口」那半段的原文，故降級：）SOP.md:219「□ 規則側已緩解：…同檔失敗 2 次標 ⚠ 跳過（不會卡死）」；SOP.md:224-225「□ 個案收尾：從 checklist.md 找標 ⚠（寫入失敗）的項，重跑 /ps-research／讓它補做；反覆失敗的同一檔改用 SOP-5 人工建檔」；SOP.md:74-76「(2) 仍無效＝寫入鏈不可信 → 切「**模型查、人工貼**」…」；SOP.md:80「(4) 個位數殘項＋模型持續「判定不用做」→ **人工直通**，不再纏鬥」
（覆蓋範圍佐證：grep 全 .opencode/ 之「政策否決／公司政策／永久條件」僅命中 SOP.md:77-78 與 applied.md:605，SOP-9 與 SOP-10 第 5 步 SOP.md:270-274 皆無註記。）
```

**建議最小修法**：改 SOP.md 兩處：(a) 第 220-223 行在「服務端可做（管理者）」開頭加註「**本環境已經公司政策否決（2026-08，見 SOP-2 第 6 步(3)）——以下僅供未來政策鬆綁或換環境時參考，勿再送申請**」，並把「故約束解碼是唯一高價值槓桿」改為「故唯一高價值槓桿（約束解碼）在本環境不可得，治法一律走 SOP-2 第 6 步升級梯」；(b) 第 231 行把「幾乎每呼叫都紅（找管理者開約束解碼）」改為「幾乎每呼叫都紅＝寫入鏈整體不可信 → 直接進 SOP-2 第 6 步升級梯（模型查、人工貼／個位數殘項人工直通），並依本節 ⚠ 跳過規則收尾」。順手把 SOP-10 第 5 步標題加一行「（本環境政策否決，見 SOP-2 第 6 步(3)；此步僅作環境現況檢查）」。


### M4. sourceHash／「chunk hash」是幽靈欄位：回報契約列為必要項，但契約自己的欄位表、現行工具回傳、entity sources 格式都沒有它，規則 8 又禁止補值——auditor 卻被要求驗它

**涉及**：.opencode/peoplesoft/subagent-report-contract.md, .opencode/peoplesoft/progressive-source-retrieval.md, .opencode/agent/ps-auditor.md, .opencode/peoplesoft/report-templates/entity-template.md

**指控**：subagent-report-contract.md:13 宣告「evidence ID（chunkId + 行號 + sourceHash）才是必要項」，但同檔規則 7（22-28 行）的 CHUNK 欄位表（id/filePath/lines/quote＋選填 objectName/event/fieldName）沒有 sourceHash、JSON 範例（79-87 行）也沒有；現行唯一正式證據來源 PeoplecodeSource_get_chunks_details 的回傳欄位（progressive-source-retrieval.md:253：ChunkText/ChunkId/FilePath/StartLine/EndLine/ComponentType/ObjectName/EventName/FieldName）不含任何 hash——sourceHash 只存在於尚未實作的 proposed 協定 §6.2（329 行）。同檔規則 8（41-42 行）又規定「工具沒提供的欄位一律省略，不得補一個「看起來像」的值」——必要項在現行環境永遠交不出來，下游 auditor 卻被要求驗它。

**驗證**：我逐行核對四個檔案，指控引用的每一行都存在且逐字如其所述：sourceHash 確實在回報契約被列為「必要項」，卻不在該檔的 CHUNK 欄位表、不在 JSON 範例、不在現行 get_chunks_details 回傳欄位清單、也不在 entity 模板的 sources 定義裡；它只活在 §6.2 那份 proposed schema（連 chunkId 都還寫成 "CHK-0001" 的舊樣式，與現行 UUID 鐵律不相容，可證該節非現況）。同檔規則 8 又明令「工具沒提供的欄位一律省略，不得補一個『看起來像』的值」——一個永遠拿不到的欄位被宣告為必要項，這是同一檔案內第 13 行與第 41-42 行的直接互斥，且違反框架自宣的證據契約（只有完整 36 字元 ChunkId 與可重跑 SELECT 算證據，沒有第三項）。ps-auditor.md:33 的「chunk hash」同樣是幽靈術語：entity-template.md:8 把 sources 定義成「chunk UUID / SQL 摘要 / human:<日期>」，沒有任何 hash。

但指控在嚴重度上明顯過重，理由是我另外查證出三道它沒查的化解層（盲掃漏掉的部分）：(1) 真正的收錄門是規則 7 的「證據格式三鐵律」（37-40 行），三條只認完整 36 字元 ChunkId、行號對應、禁止縮寫——sourceHash 不在裡面，所以沒有任何 finding 會因缺它被踢進 gaps；(2) 規則 8 那句「工具沒提供的欄位一律省略」本身就是通用出口，明文告訴 subagent 該怎麼辦（省略），所以不構成 L53 活鎖，也沒有遞迴死路；(3) 我 grep 全 repo 並讀了 ps-doc-lint.ps1，機械稽核的證據判準只有三種形態（完整 UUID／真 SELECT／待人工SQL），完全沒有 hash 檢查——沒有任何畢業門會卡在這個欄位上。auditor 端同理：第 33 行雖寫「chunk hash」，但其可執行程序（步驟 2，64-67 行）從頭到尾只做「以 ChunkId 呼叫…

**原文佐證**：
```
【矛盾成立的原文，全部我親自讀到】

1) /home/user/MCPSample/.opencode/peoplesoft/subagent-report-contract.md:13
   「   - 引用永遠可省略；evidence ID（chunkId + 行號 + sourceHash）才是必要項」

2) 同檔:23-27（CHUNK 欄位逐字表——無 sourceHash）
   「   - `CHUNK`（來自 ES / Source）：欄位**逐字取自** `get_chunks_details` 回傳——
     `id` ← `ChunkId`（Elasticsearch chunk UUID；**非 UUID 格式＝捏造**）、
     `filePath` ← `FilePath`、`lines` ← `StartLine`-`EndLine`、
     `quote` ← `ChunkText` 節錄（≤ 5 行）；選填 `objectName` ← `ObjectName`、
     `event` ← `EventName`、`fieldName` ← `FieldName`。」

3) 同檔:41-42（互斥的另一半）
   「8. **禁止捏造識別碼**：id / filePath / lines 只能來自工具回傳；
   工具沒提供的欄位一律省略，不得補一個「看起來像」的值。」

4) 同檔:79-87 JSON 範例（kind/id/filePath/lines/objectName/quote，無 sourceHash）
   「          "kind": "CHUNK",
          "id": "9b2f5c1e-4a3d-4f0a-8f21-7e5d0c9a1b2c",
          "filePath": "sqr/TWMIL001.sqr",
          "lines": "61-120",
          "objectName": "TW_MIL001",
          "quote": "UPDATE PS_TW_MILITARY SET MIL_STATUS = 'D' ..."」

5) /home/user/MCPSample/.opencode/peoplesoft/progressive-source-retrieval.md:253（現行環境對映，回傳欄位無 hash）
   「| `PeoplecodeSource`（tool `get_ch…
```

**建議最小修法**：三處刪字/改字即可，皆為單行局部修正：(1) subagent-report-contract.md:13 刪掉「+ sourceHash」，改成「evidence ID（chunkId + 行號）才是必要項」，與同檔 37-40 行三鐵律及 ps-doc-lint.ps1:363-365 的證據判準對齊；(2) ps-auditor.md:33 把「chunk hash」改成「chunk UUID」，與 entity-template.md:8「依據的 chunk UUID…（時效偵測鍵）」用同一術語；(3) progressive-source-retrieval.md:64 的「（含 `sourceHash`、`startLine`/`endLine`）」後面補一句明文豁免：「※ `sourceHash` 屬 §6.2 proposed schema，現行 `get_chunks_details`（見 §6.0）不回傳，依報告契約規則 8 一律省略、不得補值」——避免只靠 §6.0 標題暗示範圍（框架自身 L63：範圍靠標題暗示＝沒有範圍）。


### M5. 根 README 三處宣稱教訓帳本止於 L0~L50，實際已到 L64

**涉及**：README.md, .opencode/peoplesoft/lessons/applied.md

**指控**：README.md 把 applied.md 描述為「L0 ~ L50」共三處，但帳本實際記到 L64（applied.md:1455 有「### L64 索引重建＝全部 chunk id 輪替…」），L51~L64 共 14 課（含兩段式畢業細節、headless 死鎖 L60、工具身分 L61、補救路徑 L63、成批查無 L64 等大件）在 README 的歷史指引裡不存在。

**驗證**：親自開檔核對，指控的三處引文逐字屬實，帳本實際範圍也屬實。README.md:50、347、358 三處把 applied.md 標為 L0~L50，但 applied.md 的 `^### L[0-9]` 標題連續跑到 1455 行的 L64，L51~L64 共 14 課全在 README 宣告的上限之外，且包含 L60（headless 阻塞）、L61（工具身分＝前綴＋名稱）、L63（補救路徑不得被規則自封）、L64（成批查無＝環境訊號）這幾條鐵律。三處皆無任何範圍限定或快照凍結說明：README:346-348 的「以上是設計時想清楚的部分」限定的是它前面那段散文，接著那句反而斷言實跑後的改動「全部記在 L0~L50」，屬直接錯誤，不構成豁免。另有旁證顯示這是失修而非刻意凍結——同一段檔案樹的 README:49 寫「SOP-1 ~ SOP-16」，但 SOP.md 實際有 17 個 `## SOP-` 標題、最末為 SOP-17。且 AGENTS.md:5 明文把根 README 當作框架入口，這份標籤確實在接手動線上。判 CONFIRMED。惟原判 major 過重：這三個數字不是任何門檻或 lint 的輸入，不造成兩條規則互斥，執行期（lint／畢業門／收據）完全不讀它；維護者一開 applied.md 就會看到 64 課，錯誤即自我修正。這是散文裡手維護計數的失修（正是框架 L0「能機械化就不寫prose」所警告的模式），非設計矛盾，故修正為 minor。

**原文佐證**：
```
README.md:50「│  ├─ lessons/applied.md           教訓帳本 L0 ~ L50 ★框架唯一完整的歷史」
README.md:347-348「症狀、根因與落點全部記在 `applied.md` 的 L0~L50，包括確定性外環、\n三層畢業門與兩段式畢業這些**當初沒有預見、是實跑逼出來的**機制。」
README.md:358-359「2. **`.opencode/peoplesoft/lessons/applied.md`** — L0~L50 教訓帳本，\n   每課含症狀／根因／落點。框架的每一條怪規則都能在這裡找到它的屍體。」
applied.md:1455「### L64 索引重建＝全部 chunk id 輪替——收據不知外部世界、成批查無不是成批捏造（2026-08）」
applied.md:1269「### L60 headless 的權限詢問不會被拒絕，它會永遠阻塞——而且 log 裡看不到（2026-08）」
applied.md:1334「### L61 名字對、server 錯——工具身分是「前綴＋名稱」，錯一半就等於不存在（2026-08）」
applied.md:1422「### L63 補救路徑被規則自己封死——「請開新 session」的那個 session 讀到同一條禁令（2026-08）」
旁證（同類失修，非指控範圍內）README.md:49「│  ├─ SOP.md                       人工作業程序 SOP-1 ~ SOP-16」 vs SOP.md:324「## SOP-17 無人看管排程（衝刺期夜間跑批）」
接手動線佐證 AGENTS.md:5「- 根目錄 `README.md`：PeopleSoft 知識庫分析框架的入口（做什麼、怎麼跑、」
```

**建議最小修法**：改 README.md 三處，去掉手維護的上界而非改成 L64（改數字下輪照樣失修）：line 50 改為「教訓帳本 L0 起逐課累加 ★框架唯一完整的歷史」；line 347-348 改為「…全部記在 `applied.md`（L0 起的完整帳本，以檔內最末一課為準）」；line 358 改為「**`.opencode/peoplesoft/lessons/applied.md`** — 教訓帳本（L0 起）」。順手把 line 49 的「SOP-1 ~ SOP-16」改為「SOP.md 人工作業程序（編號見檔內標題）」。若要機械化（合 L0），在既有 lint 加一條檢查：grep applied.md 的 `^### L(\d+)` 取最大值、grep README 的 `L0\s*~\s*L(\d+)`，兩者不符即報違規。


### M6. 根 README 宣稱 SOP-1 ~ SOP-16，實際現有 17 條（SOP-17 已存在）

**涉及**：README.md, .opencode/peoplesoft/SOP.md

**指控**：【跨批合併：兩批各留一筆的同一過期計數】README.md 目錄結構把 SOP.md 標為「人工作業程序 SOP-1 ~ SOP-16」，但 SOP.md 現有 SOP-1 到 SOP-17 共 17 條——漏掉的 SOP-17 正是「無人看管排程（衝刺期夜間跑批）」，是 headless 鐵律（L60 權限死鎖）落地的那份程序。編號 1~17 皆存在、無缺號，僅檔內排序非遞增（SOP-16/17 插在 SOP-10 與 SOP-13 之間，之後為 13、12、11、14、15），照 README 的線性描述找不到 SOP-17。

**驗證**：我逐項打開檔案核對，指控的每一個可查證細節都成立，沒有可化解的明文範圍或豁免。

1) README 的宣稱：`grep -n 'SOP' README.md` 全檔只有 4 處提到 SOP，其中唯一給範圍的就是目錄樹第 49 行「SOP-1 ~ SOP-16」。README 其他 3 處（336、360 行）都不帶範圍，也沒有任何「本清單為節錄／不完整」之類的豁免語。

2) 實際條數：`grep -c '^## SOP-' .opencode/peoplesoft/SOP.md` = 17，最大編號 SOP-17 在第 324 行。1~17 全數存在、無缺號（章節序 1,2,3,4,5,6,7,8,9,10,16,17,13,12,11,14,15），所以這是「少算一條」而非「編號跳號」。

3) 排序非遞增也屬實：SOP-16（287）與 SOP-17（324）插在 SOP-10（249）與 SOP-13（392）之間，之後是 12（410）、11（436）、14（473）、15（511）。SOP.md 檔頭（1~8 行）沒有目錄索引，全檔 535 行——照 README 的線性描述看到 SOP-16 就會以為到底了，而 SOP-17 其實還在後面。

4) 被漏掉的正是 headless 命脈，這是本案唯一有實害的地方：SOP.md:237 明寫跑 auto-loop 前「**必須**先照 SOP-17 第 0 條把 doom_loop 設 allow」，scripts/ps-auto-loop.ps1:17 也指向 SOP-17。也就是說 README 漏掉的那一條，正是 headless 鐵律（無人環境只有 allow/deny，會問人＝死鎖且 log 看不到）的落地程序。

我另外查了有沒有機械閘門會擋這件事：`grep -rn 'SOP' scripts/` 顯示各 .ps1 只是在訊息裡引用 SOP 編號，**沒有任何 lint 規則讀 README 的 SOP 範圍**，所以這條不會被 ps-doc-lint 抓到，只能靠人工維護——正好是 L0「能…

**原文佐證**：
```
【README 的過期宣稱】
/home/user/MCPSample/README.md:49
│  ├─ SOP.md                       人工作業程序 SOP-1 ~ SOP-16

【實際存在的第 17 條】
/home/user/MCPSample/.opencode/peoplesoft/SOP.md:324
## SOP-17 無人看管排程（衝刺期夜間跑批）

（同檔 `grep -c '^## SOP-'` = 17；章節行號序 9,39,90,115,133,149,164,181,211,249(SOP-10),287(SOP-16),324(SOP-17),392(SOP-13),410(SOP-12),436(SOP-11),473(SOP-14),511(SOP-15)——編號 1~17 無缺號，僅排序非遞增，與指控一致。）

【漏掉的這條是 headless 死鎖的解方，非可有可無】
/home/user/MCPSample/.opencode/peoplesoft/SOP.md:235-238
  沒有 TTY 可以回答＝**永遠阻塞**，提示還畫在 TTY 上、log 裡看不到。
  症狀只剩「輸出靜止」，逾時上限開多大都一樣撞滿、產出為零。
  → 跑 auto-loop 前**必須**先照 SOP-17 第 0 條把 `doom_loop` 設 "allow"，
    本行的「逾時熔絲自動處理」才成立。沒設＝每次都燒滿整個上限。

/home/user/MCPSample/scripts/ps-auto-loop.ps1:17
#       把這兩個明確設成 allow／deny（見 SOP-17）；不要用 --auto 一次全開，

【無豁免、無機械閘門】
README.md 全檔僅 4 處提及 SOP（49、336、360 行），只有 49 行給範圍且無「節錄／不完整」註記；
`grep -rn 'SOP' scripts/` 中各 .ps1 僅在訊息文字引用 SOP 編號，無任何規則校驗 README 的 SOP 範圍。
```

**建議最小修法**：改 /home/user/MCPSample/README.md:49 一行，把手工計數換成不會漂移的描述：`│  ├─ SOP.md                       管理者人工作業程序（SOP-1 ~ SOP-17，檔內非依序排列）`。若要更貼合 L0「能機械化就不寫 prose」，直接拿掉數字範圍寫成「管理者人工作業程序（編號 SOP-N，章節非遞增，以檔內標題為準）」，並在 ps-doc-lint.ps1 加一條機械檢查：比對 README 該行的最大編號與 `.opencode/peoplesoft/SOP.md` 中 `^## SOP-(\d+)` 的最大值，不一致就出警告（警告不擋畢業，符合 SOP-2 手動執行維持警告不擋的既有分級）。順帶檢查 README:50 的「L0 ~ L50」是否同樣落後於 applied.md 的實際最大教訓編號。


### M7. 根 README 對 test-scenarios 的分類宣稱自相矛盾：第 55 行說「A~F 類業務題」，第 344 行說「A~I 類考業務題」

**涉及**：README.md, .opencode/peoplesoft/test-scenarios.md

**指控**：同一份 README 對回歸題庫的範圍給了兩個不同版本：目錄結構節說 A~F 類業務題＋J 類，設計沿革節說 45 個情境、A~I 類業務題＋J 類。現行 test-scenarios.md 檔頭是「共 45 題，分 10 類（A~I 為業務題…J 類是框架機制檢查點）」——第 55 行是過期版本，G/H/I 三類（deep-research／稽核迴路／Entity Wiki 共 7 題）被漏掉。

**驗證**：親自開檔逐行核對，指控三句引文全部逐字屬實，且矛盾成立。

1. README.md:55 與 README.md:341 確實對同一份 test-scenarios.md 給出兩個不同的業務題範圍（A~F vs A~I）。
2. 以 `grep -c "^### [A-J][0-9]"` 機械清點 test-scenarios.md，總數正好 45 題，分佈為 A(7) B(5) C(6) D(3) E(4) F(7) G(2) H(3) I(2) J(6)，共 10 類。G/H/I 三類確實存在且正好 7 題（G1-G2、H1-H3、I1-I2），與指控所述完全一致。
3. 故 README.md:341（A~I）為正確版本，README.md:55（A~F）是過期版本，漏掉 G/H/I 共 7 題。
4. 已排除豁免可能：第 55 行位於純目錄樹 code block 內的單行檔案註解，前後（第 45~70 行）無任何限縮語或明文範圍宣告。依框架 L63「範圍靠標題暗示＝沒有範圍」，此處連暗示都沒有。

額外發現（審查者漏掉，同一缺陷的第三個版本）：.opencode/peoplesoft/README.md:35 寫「30 題」，比 README.md:55 更過期。修法應一併掃掉。

嚴重度下修 major → minor：矛盾為真，但落點是目錄樹的路標式註解，無任何可執行後果——沒有畢業門、lint 規則、證據契約或 scripts/*.ps1 讀取 README.md:55；權威檔頭只隔一跳，且同一份 README 在第 341 行已給出正確範圍。誤導的是人工速讀者，不是機械外環，未觸及 tier1/tier2 門或 L53 活鎖條件。

**原文佐證**：
```
【自讀原文，非複述指控】

/home/user/MCPSample/README.md:55
│  ├─ test-scenarios.md            回歸題庫（A~F 類業務題 ＋ J 類機制檢查點）

/home/user/MCPSample/README.md:340-341
- **回歸測試套件**：`test-scenarios.md` 的 45 個情境，每一題守住一個踩過的坑，
  改版必跑。把軟體工程的回歸測試觀念套到「規則遵循」上——A~I 類考業務題

/home/user/MCPSample/.opencode/peoplesoft/test-scenarios.md:4-6（權威檔頭）
是否遵守 Plan Addendum 的規則。共 45 題，分 10 類（A~I 為業務題：F 類需 subagent
架構、G/H/I 類需 deep-research / wiki 模式；**J 類是框架機制檢查點**，測外環／
lint／畢業門本身，不測業務），全部基於

【G/H/I 確實存在——自讀章節標題】
/home/user/MCPSample/.opencode/peoplesoft/test-scenarios.md:383  ## G 類：Deep Research（文件生成模式）
/home/user/MCPSample/.opencode/peoplesoft/test-scenarios.md:390  ### G1 總覽與 checklist 生成
/home/user/MCPSample/.opencode/peoplesoft/test-scenarios.md:400  ### G2 逐項深查與續跑
/home/user/MCPSample/.opencode/peoplesoft/test-scenarios.md:418  ## H 類：稽核與教訓迴路
/home/user/MCPSample/.opencode/peoplesoft/test-scenarios.md:420  ### H1 稽核執行與回灌
/home/user/MCPSample/.opencode/peoplesoft/test-scenarios.md:446  ### H2 教訓登錄即生效（本機套用、PR 把關）
/home/user/MCPSample/.opencode/peoplesoft/test-scenarios.md:456  ### H3 人工指正知識更新（/ps-correct）
/home/user/MCPS…
```

**建議最小修法**：改 /home/user/MCPSample/README.md:55，把 `回歸題庫（A~F 類業務題 ＋ J 類機制檢查點）` 改成 `回歸題庫（45 題：A~I 類業務題 ＋ J 類機制檢查點）`，與同檔第 341 行及 test-scenarios.md:5 檔頭對齊。同時順手修 /home/user/MCPSample/.opencode/peoplesoft/README.md:35，把 `（30 題 + 評分規則）` 改成 `（45 題 + 評分規則）`，否則同一缺陷仍留一份更過期的副本。


### M8. peoplesoft/README 宣稱 test-scenarios 為「30 題」，實際 45 題

**涉及**：.opencode/peoplesoft/README.md, .opencode/peoplesoft/test-scenarios.md

**指控**：.opencode/peoplesoft/README.md 的目錄說明把 test-scenarios.md 標為「30 題 + 評分規則」，但該檔檔頭與實際情境數都是 45 題（A7+B5+C6+D3+E4+F7+G2+H3+I2+J6=45）——G/H/I/J 四類（deep-research、稽核迴路、wiki、外環機制檢查點共 13 題）是 30 題時代之後加的，架構總覽沒跟上。

**驗證**：親自開檔核對，兩端數字確實不符，且不存在任何明文範圍或豁免。

1. README.md 的「目錄結構」樹是全域結構清單（第 15-64 行，涵蓋 .opencode/ 底下所有檔案），第 35 行對 test-scenarios.md 的註解寫死「30 題」。該行前後沒有任何「僅計業務題」「不含框架機制題」之類的範圍限定，README 全檔也沒有第二處提到題數（grep `[0-9]+ 題` 在 README 只命中這一行）。

2. test-scenarios.md 第 5 行檔頭自稱「共 45 題，分 10 類」，且該行同時把 J 類定義為「框架機制檢查點」納入總數，所以 45 是含 J 的官方口徑。

3. 我用 grep `^### [A-J][0-9]+ ` 機械清點實際情境標題，得 45 個，逐類為 A7(75-129行)、B5、C6、D3、E4、F7(F1~F5、F7、F6，編號亂序但共 7 題)、G2、H3、I2、J6 —— 與指控的算式 7+5+6+3+4+7+2+3+2+6=45 完全一致。30 與 45 兩邊都不是四捨五入或口徑差，是純粹的陳舊註解。

補充交叉證據（強化「這個數字被手抄在三個地方、必然漂移」）：docs/system-overview.html:395 寫「39 個回歸測試情境」，其表格只列 A~I（39 = 45 − J 類 6 題），第三個地方又是第三個數字。

嚴重度修正理由：事實成立，但這是 README 目錄樹裡一個描述性括號註解過期，不擋任何門、不進 lint、不影響 agent 行為、不牽涉證據契約或 L53 活鎖。真正的影響只是人讀架構總覽時低估測試覆蓋。相對於框架其他「會造成遞迴死路／永不畢業」等級的矛盾，major 過重，降為 minor。

**原文佐證**：
```
/home/user/MCPSample/.opencode/peoplesoft/README.md:35
`│  ├─ test-scenarios.md                本地模型準確度測試情境（30 題 + 評分規則）`

/home/user/MCPSample/.opencode/peoplesoft/test-scenarios.md:5
`是否遵守 Plan Addendum 的規則。共 45 題，分 10 類（A~I 為業務題：F 類需 subagent`
（第 6-7 行續：`架構、G/H/I 類需 deep-research / wiki 模式；**J 類是框架機制檢查點**，測外環／` / `lint／畢業門本身，不測業務），全部基於`）

實際清點（grep `^### [A-J][0-9]+ ` on test-scenarios.md，共 45 個標題）：
A: 75 A1 / 86 A2 / 94 A3 / 103 A4 / 113 A5 / 121 A6 / 129 A7  → 7
B: 141 B1 / 149 B2 / 157 B3 / 163 B4 / 171 B5  → 5
C: 181 C1 / 191 C2 / 199 C3 / 207 C4 / 215 C5 / 223 C6  → 6
D: 241 D1 / 249 D2 / 256 D3  → 3
E: 266 E1 / 279 E2 / 287 E3 / 295 E4  → 4
F: 310 F1 / 318 F2 / 327 F3 / 336 F4 / 347 F5 / 364 F7 / 373 F6  → 7
G: 390 G1 / 400 G2  → 2
H: 420 H1 / 446 H2 / 456 H3  → 3
I: 470 I1 / 481 I2  → 2
J: 497 J1 / 515 J2 / 528 J3 / 554 J4 / 586 J5 / 604 J6  → 6

第三處手抄數字（旁證，非指控範圍）：
/home/user/MCPSample/docs/system-overview.html:395
`    <div class="sec-kicker">APPENDIX ─ 39 個回歸測試情境</div>`
（其表格分類列 A7/B5/C6/D3/E4/F7/G2/H3/I2 = 39，無 J 類列）
```

**建議最小修法**：改 /home/user/MCPSample/.opencode/peoplesoft/README.md:35，把寫死的題數拿掉而不是改成 45（同一數字現已手抄在三個檔、三個值，改數字只會再漂移一次）：`│  ├─ test-scenarios.md                本地模型準確度測試情境（題庫＋評分規則；題數與分類以該檔檔頭為準）`。若堅持保留數字，則需同步 README.md:35（30→45）與 docs/system-overview.html:395（39→45，並補上 J 類 6 題的表格列），且應在 ps-doc-lint.ps1 加一條機械對帳（grep `^### [A-J][0-9]+ ` 計數 vs 檔頭「共 N 題」）——否則違反 L0「能機械化就不寫 prose」。


### M9. peoplesoft/README 稽核流程宣稱「非 UUID 的 id 直接判捏造」，與現行 ps-auditor 的 TRUNCATED_ID／二次定位／L64 成批查無規則正面互撞

**涉及**：.opencode/peoplesoft/README.md, .opencode/agent/ps-auditor.md

**指控**：架構總覽描述的稽核判定是舊版：非 UUID id 一律判捏造。現行 ps-auditor 明文相反——恰為 8 碼 hex 的 id 判 FAIL(TRUNCATED_ID)（「證據本體可能為真」，修法＝補全，不判捏造）；id 查無時判 FAIL 前必做二次定位；L64 更規定本輪 ≥3 檔成批查無「一律不判 FABRICATED」全部判 stale。照 README 的版本操作（或人工覆核時拿它當判準）會把可修復證據與索引重建訊號整批誤判成捏造，正是 L64 要修帳的那個錯誤。

**驗證**：我親自打開兩個檔案逐行讀過，README.md:194-195 的原文確實存在，且確實停留在 L9 教訓之前的舊版判定；ps-auditor.md:87-90 的 8 碼 hex 分流也確實存在。兩者在「稽核判定」這個同一個槽位上正面互撞：README 說「非 UUID 的 id 直接判捏造」，8 碼 hex 正是非 UUID，而 auditor 明文說那是 TRUNCATED_ID、「證據本體可能為真」、修法＝補全，不判捏造。這不是我複述指控，是我讀到的字面差異。

交叉查證後，我要修正指控的兩點與嚴重度：

(1) 指控的三個撞點只有第一個成立。README:194-195 整句只談「格式」（非 UUID 樣式）與 SQL 重跑，**完全沒有提到 id 查無時怎麼判**。「二次定位」（ps-auditor.md:71-82）與 L64 成批查無（:56-61）處理的是**格式合法的完整 UUID 解引用查無**——README 沒有對那個情境下任何判定，所以那兩條是「未提及」而非「相反規定」。指控寫的「把…索引重建訊號整批誤判成捏造」是延伸推論，不是 README 的字面主張。真正的撞點只有 TRUNCATED_ID 這一半。

(2) 其他三條可執行路徑早已正確分流，只有 README 這張 prose 概覽沒跟上：
- lint（機械層，scripts/ps-doc-lint.ps1:308-315）已對 8 碼給專屬訊息並收進 $truncatedIds，與「疑似捏造」分開；
- 人工 SOP（SOP.md:63）已明文豁免「（非 8 碼樣式）」才判捏造；
- 教訓 L9（lessons/applied.md:413-424）列的落點 (1)~(6) 本來就沒把 README 列進去。
換言之這是 L9 套用時漏掉的一張敘事文件，屬**文件時效債**，不影響 headless 迴路任何一條可執行路徑（auditor 讀 agent 檔、lint 讀 ps1、人工讀 SOP）。README 也沒有「以本檔為準」的宣告可讓它凌駕 agent 檔。

風險僅剩「人工…

**原文佐證**：
```
【撞點 A：README 舊版判定，我讀到的原文】
/home/user/MCPSample/.opencode/peoplesoft/README.md:192-195
「**稽核**（`/ps-audit <領域>`）——不信模型說了什麼，驗它引用了什麼：
1. **證據解引用**：每筆 CHUNK 證據以 ChunkId 重查、quote 做子字串比對；
   SQL 證據重跑比對 keyRows；非 UUID 的 id 直接判捏造。」
（注意：整句只涵蓋「格式」與 SQL 重跑，全句無一字提到 id 查無的處置。）

【撞點 B：現行 auditor 的分流，原文】
/home/user/MCPSample/.opencode/agent/ps-auditor.md:87-90
「id 非 UUID 格式時分兩種（都不用查 MCP）：
   **恰為 8 碼 hex（UUID 首段樣式）→ `FAIL(TRUNCATED_ID)`**——
   id 遭縮寫，證據本體可能為真，修法＝依 filePath＋行號重找補全；
   其他樣式 → `FAIL(FABRICATED)`。」

【降級依據 1：機械層早已分流】
/home/user/MCPSample/scripts/ps-doc-lint.ps1:308-315
「                if ($id -match '^[0-9a-fA-F]{8}$') {
                    $violations += "${name}：ChunkId 遭縮寫為 8 碼（須完整 36 字元 UUID）：$id"
                    $truncatedIds += [pscustomobject]@{ File = $name; Id = $id }
                }
                else {
                    $violations += "${name}：ChunkId 非 UUID 格式（疑似捏造）：$id"
                }」

【降級依據 2：人工 SOP 已明文豁免 8 碼】
/home/user/MCPSample/.opencode/peoplesoft/SOP.md:63
「     - 「ChunkId 非 UUID / 自編 id」（非 8 碼樣式）→ 證據捏造，
       跑 /ps-audit 該領域」
（同檔 SOP.md:59-62 另有「Chunk…
```

**建議最小修法**：改 /home/user/MCPSample/.opencode/peoplesoft/README.md:194-195 第 1 點末句，把「非 UUID 的 id 直接判捏造」換成與 L9 一致的分流＋權威指向，例如：「id 恰為 8 碼 hex → `FAIL(TRUNCATED_ID)`（縮寫，證據可能為真，修法＝依 filePath＋行號補全）；其他非 UUID 樣式才判 `FAIL(FABRICATED)`。判定細則（二次定位、L64 成批查無判 stale）以 `agent/ps-auditor.md` 為準。」——單行 prose 修正，不動任何可執行路徑。


### M10. system-overview.html 三處宣稱 39 個回歸測試情境（實際 45），附錄清單整類漏掉 J 類——恰好是測外環／畢業門機制的那 6 題

**涉及**：docs/system-overview.html, .opencode/peoplesoft/test-scenarios.md

**指控**：對外簡報頁 stat tile、品質關卡、附錄標題都寫 39 題，附錄明細表只列 A~I 類（7+5+6+3+4+7+2+3+2=39），現行題庫是 45 題含 J 類 6 題（J1 三層畢業門、J2 強殺一致性、J3 畢業收據與排程、J4 假缺檔、J5 判定可讀性、J6 兩段式畢業）。被漏掉的整類正是後來演化出的外環機制檢查點，與本頁同樣漏掉外環機制（見另一筆）互為印證：這頁停在 auto-loop 時代之前。

**驗證**：我逐行打開了兩個檔案，指控的每一個座標都對得上，且沒有任何可化解的明文範圍或豁免。

(1) 三處 39 全部存在且位置與行號完全正確（:138 stat tile、:320 品質關卡、:395 附錄標題）。

(2) 附錄明細表確實止於 I 類。我讀了 :401-453 整張表，最後一列是 :451 的 I2，:452 就是 `</tbody>`、:453 `</table>`。分類列的題數標註逐一核對：A 7 + B 5 + C 6 + D 3 + E 4 + F 7 + G 2 + H 3 + I 2 = 39，與標題自洽——也就是說 39 不是筆誤，是整份附錄真的只涵蓋 A~I。

(3) 題庫確為 45 題含 J 類 6 題。test-scenarios.md:5 明寫「共 45 題，分 10 類」，:491 起 J 類，子節標題 J1(:497)／J2(:515)／J3(:528)／J4(:554)／J5(:586)／J6(:604) 恰好 6 題。39 + 6 = 45，數字閉合，漏的正好是一整個 J 類。

(4) 我特地找過豁免：對 HTML 全檔 grep `45|J 類|外環|auto-loop|畢業|業務題|僅列|不含`，唯一命中是 CSS 的 `--warn:#b45309`（色碼裡的 45）。也就是說整頁從未提及外環、auto-loop、畢業門，也沒有任何「本頁僅列業務題」之類的範圍聲明。附錄開頭 :397-400 只講「完整定義見 test-scenarios.md」與題材為何選兵役，沒有縮小範圍。依框架 L63「範圍靠標題暗示＝沒有範圍」，而此處標題還反向寫死了「39 個」這個硬數字，連暗示性範圍都談不上——是明確的錯誤計數。

(5) 指控關於「漏掉的正是外環機制」的解讀也有原文支撐：test-scenarios.md:6-7 自己就把 J 類定義為「**J 類是框架機制檢查點**，測外環／lint／畢業門本身，不測業務」，J 類標題(:491)與導言(:493-495)也明指對 `scripts/ps-auto-loop.ps1` 與…

**原文佐證**：
```
【docs/system-overview.html — 我讀到的原文】

:138  `    <div class="tile"><div class="num">39</div><div class="lbl">回歸測試情境（品質驗收）</div></div>`

:320  `      <div class="gate"><div class="g-ic">✅</div><b>4. 回歸測試</b><span>39 個測試情境守住歷史教訓，改版必跑，不走回頭路</span></div>`

:395  `    <div class="sec-kicker">APPENDIX ─ 39 個回歸測試情境</div>`

附錄表尾（證明整類 J 缺席）：
:449  `        <tr class="cat"><td colspan="3">I 類 ─ Entity Wiki 層（2 題）</td></tr>`
:450  `        <tr><td>I1</td><td>歸戶與查重</td><td>深查完成後 wiki 有建檔／更新，同物件不重複建檔</td></tr>`
:451  `        <tr><td>I2</td><td>問答 wiki-first 與來源標註</td><td>已驗證條目直接引用，且標明來源出自 wiki</td></tr>`
:452  `      </tbody>`
:453  `    </table>`
（I2 之後直接收表，無 J 類列）

附錄導言無任何範圍限縮：
:397  `    <p style="margin-top:8px">完整定義（檢查點與評分）見 <code>test-scenarios.md</code>；日常快速健檢用其中 9 題的 Smoke Set。</p>`

分類列題數（相加恰為 39，證明非筆誤而是整體停留在舊版）：
:404 `A 類 ─ 業務發現與客製政策（7 題）`／:412 `B 類 ─ UI 語意與選項（5 題）`／:418 `C 類 ─ 長文本漸進檢索（6 題）`／:425 `D 類 ─ DYNAMIC_RUNTIME 動態行為（3 題）`／:429 `E 類 ─ 端到端整合（4 題）`／:434 `F 類 ─ Context 紀律／Subagent 架構（7 題）`／:442 `G 類 ─ Deep Research 文件生成（2 題）`／:445 `H 類 ─ 稽核與教訓迴路（3 題）`／:449 `I 類 ─ Entity Wiki 層（2 題）…
```

**建議最小修法**：改 /home/user/MCPSample/docs/system-overview.html 一個檔即可，兩步：(1) 把 :138、:320、:395 三處「39」改為「45」（:395 標題改為「APPENDIX ─ 45 個回歸測試情境」）。(2) 在 :451（I2 那列）之後、:452 `</tbody>` 之前補上 J 類六列，比照現有格式加一列分類列 `<tr class="cat"><td colspan="3">J 類 ─ auto-loop 外環畢業門／框架機制（6 題）</td></tr>`，再依 test-scenarios.md:497-604 補 J1 三層畢業門（session／transition／validation）、J2 強殺後檔案一致性檢查（唯讀）、J3 畢業收據與多領域排程、J4 假缺檔防線（L28）、J5 判定輸入可讀性（L49）、J6 兩段式畢業（L50／SOP-16）六列。若不想補明細，最低限度也要把三處數字改為 45 並在 :397 明寫「本表僅列 A~I 業務題；J 類 6 題為框架機制檢查點，見 test-scenarios.md:491」——即用明文範圍取代錯誤計數，避免僅靠標題暗示範圍。


### M11. system-overview.html 宣稱「SOP.md（13 份核取清單）」，實際 17 條

**涉及**：docs/system-overview.html, .opencode/peoplesoft/SOP.md

**指控**：權責表把管理者依據標為 SOP.md 共 13 份核取清單，現行 SOP.md 有 SOP-1~SOP-17 共 17 條——漏掉的 SOP-14（批次多領域研究）、SOP-15（overview 換版）、SOP-16（兩段式畢業）、SOP-17（無人看管排程）恰好都是外環／畢業機制的管理程序。

**驗證**：數字確實過期，且我用 git 史證實那個「13」本來就是**應與 SOP.md 標題總數同步**的計數，不是任何範圍限定。

一、事實核對（我自己讀到的）：`grep -c "^## SOP-" SOP.md` = **17**；HTML 仍寫 13。指控引的四個行號 :287／:324／:473／:511 全部精確命中（SOP.md 標題順序是亂的——SOP-16/17 排在 SOP-10 之後、SOP-11~15 之前——盲掃很容易漏，但行號對）。

二、我另外查了兩條可能翻案的路，兩條都死了：
1. 「核取清單」是否只算含 □ 的節？我逐節數 □：17 節裡有 **16 節**含核取項（只有 SOP-6 為 0）。所以 13 既不等於標題數（17）也不等於核取清單數（16）——兩種讀法都救不了。
2. HTML 是否為凍結快照／有免責範圍？沒有。該列「依據」欄直接指整份 `SOP.md`，無日期、無版本、無快照聲明；SOP-15 管的是知識庫的 `00-overview.md`（「00-overview 階段一寫完即凍結」），與 `docs/system-overview.html` 是不同檔，對本頁零覆蓋。

三、決定性反證（git）：最後一次動這行的 commit 776d278（2026-08-12）標題就叫 **"Presentation: SOP count is 13"**，diff 是 `11 份` → `13 份`；而我 checkout 該 commit 的 SOP.md 一數，剛好 **13** 個標題。也就是說這個數字歷來是被人工同步維護的總數計數，維護者自己認定它該等於標題數。之後 SOP-14（08-13）、SOP-15（08-14）、SOP-16／17（08-18）陸續加入，這行再沒跟上（今天 08-19）。

四、但審查者的**因果解讀是錯的**，這影響評級。他說漏掉的四條「恰好都是外環／畢業機制的管理程序」，暗示存在對外環／畢業機制的系統性盲區。git 史顯示那純粹是時序漂移：漏的四條就是最後同步（08-12）之後新增的**全部**…

**原文佐證**：
```
【指控行，我親自讀到】
docs/system-overview.html:363
  `<tr><td><span class="role admin">管理者</span></td><td>批准教訓套用、lint 健檢、內部 git 版控、回滾、人工修正標記</td><td><code>SOP.md</code>（13 份核取清單）</td></tr>`
（前後文 :359-364 只有 角色／做什麼／依據 三欄，無日期、無版本、無快照或範圍聲明）

【實際 17 條，行號全部核對無誤】
`grep -c "^## SOP-" .opencode/peoplesoft/SOP.md` → 17
.opencode/peoplesoft/SOP.md:287 `## SOP-16 兩段式畢業與廣度優先排程`
.opencode/peoplesoft/SOP.md:324 `## SOP-17 無人看管排程（衝刺期夜間跑批）`
.opencode/peoplesoft/SOP.md:473 `## SOP-14 批次多領域研究（ps-auto-all）`
.opencode/peoplesoft/SOP.md:511 `## SOP-15 00-overview 換版（凍結快照的刷新程序）`

【決定性反證：這個數字本來就該等於標題總數】
`git show --format=%s -s 776d278` → `Presentation: SOP count is 13`
`git show 776d278 -- docs/system-overview.html`：
  `-        ...<code>SOP.md</code>（11 份核取清單）</td></tr>`
  `+        ...<code>SOP.md</code>（13 份核取清單）</td></tr>`
`git show 776d278:.opencode/peoplesoft/SOP.md | grep -c "^## SOP-"` → 13
（即該 commit 當下標題數 13，HTML 同步為 13 —— 計數＝標題總數，無疑義）

【漏的四條 = 同步之後新增的全部四條（時序漂移，非分類盲點）】
`git log -S"## SOP-14 " -- SOP.md` → 52ee656 2026-08-13
`git log -S"## SOP-15 " -- SOP.md` → 72c40f2 2026-08-14
`git log -S"## SOP-16 " -…
```

**建議最小修法**：最小修法：把 docs/system-overview.html:363 的「（13 份核取清單）」改成「（17 份核取清單）」。但這行已漂移兩次（11→13→現又落後 4 條）且無任何 lint 看管，建議一併去掉硬編數字，改為「<code>SOP.md</code>（管理程序核取清單）」，或在 scripts/ps-doc-lint.ps1 加一條機械檢查：比對 HTML 該括號內數字與 `grep -c "^## SOP-" SOP.md` 是否相等，不符即警告（符合 L0「能機械化就不寫 prose」）。


### M12. system-overview.html（架構與使用指南）完全沒有確定性外環：ps-auto-loop／ps-auto-all、兩段式 tier 畢業、graduation.json 收據、熔絲全數缺席；agent 數宣稱 8 亦與現行 9 不符

**涉及**：docs/system-overview.html, README.md, scripts/ps-auto-loop.ps1

**指控**：根 README 開宗明義說框架核心是「確定性外環驗收、模型說自己做完不算數、畢業門／收據」，但對外架構頁的架構圖、四道品質關卡、腳本清單（只列 ps-doc-lint.ps1 一支）與角色表對 ps-auto-loop / ps-auto-all / ps-graduation / ps-fs-doctor、tier 1/tier 2 兩段式畢業、graduation.json 收據、七保險絲隻字未提——整層「確定性外環（PowerShell）」在這份唯一的圖解文件裡不存在。另 stat tile「8 分工 AI Agent（含稽核員）」與現行 9 個 ps-agent（2 primary＋6 flow subagent＋auditor；另有 3 個內建覆寫檔共 12 個 agent 定義）對不上。

**驗證**：我逐檔開過，指控的三項事實全部屬實，且沒有任何明文範圍或豁免可以化解。

（1）外環全數缺席：docs/system-overview.html 全檔 463 行，grep -i 「auto-loop / auto-all / tier / 畢業 / graduat / 收據 / receipt / 熔絲 / 保險絲 / fs-doctor」命中數＝0。腳本只出現一支（:291 ps-doc-lint.ps1），而 scripts/ 實際有 ps-auto-all.ps1、ps-auto-loop.ps1、ps-doc-lint.ps1、ps-fs-doctor.ps1、ps-graduation.ps1 五支生產腳本。TRUST 段（:312-321）把可信度說成「四道品質關卡」——證據紀律／獨立稽核／教訓機制／回歸測試——恰好把根 README:5-7、:9-17 宣稱的第一支柱「確定性外環驗收、模型說自己做完了不算數、畢業門／收據」整層漏掉。

（2）沒有明文範圍可救：全 repo 除了 .review-findings.json（本次審查產物）以外，沒有任何檔案引用 system-overview.html，它也不在 ps-doc-lint 的掃描範圍內（ps-doc-lint.ps1:98 $researchRoot = docs/ps-research，:512 wiki 目錄，全檔不碰 .html）。頁面唯一的委外指標在 :457 footer，把「架構」指向 .opencode/peoplesoft/README.md——但我 grep 該檔「auto-loop|auto-all|graduation|畢業|收據|tier|外環」同樣命中 0（該檔只在 :201 提 ps-doc-lint）。也就是說：照這頁自己指的架構路徑走下去，讀者永遠遇不到外環。依 L63「範圍靠標題暗示＝沒有範圍」，「內部系統簡報／使用指南」的標題不構成豁免。

（3）數字對不上，而且不是「寫的時候還沒有」：:136 tile 寫 8；.opencode/agent/ 現有 12…

**原文佐證**：
```
【指控成立的原文】
docs/system-overview.html:136  `<div class="tile"><div class="num">8</div><div class="lbl">分工 AI Agent（含稽核員）</div></div>`
docs/system-overview.html:291  `<tr><td><code>ps-doc-lint.ps1</code></td><td>文件格式健檢腳本（終端機執行）</td><td><span class="role admin">管理者</span></td></tr>`  ← 全檔唯一一支 .ps1
docs/system-overview.html:312  `<h2>四道品質關卡，專治 AI「一本正經地胡說」</h2>`（:314-320 四關＝證據紀律／獨立稽核／教訓機制／回歸測試，無外環）
docs/system-overview.html:363  `<td><code>SOP.md</code>（13 份核取清單）</td>`（實際 17 條）
機械事實：`grep -c -i -E "auto-loop|tier|畢業|graduat|收據|熔絲|保險絲" docs/system-overview.html` → `0`

【對照組：外環確實是框架自宣核心】
README.md:5-7  「這個框架的核心假設是**模型會出錯、會偷懶、會宣稱做了沒做的事**——所以每一份產出都要有機器可重跑的證據，每一輪工作都由確定性的外環驗收，模型說自己做完了不算數。」
README.md:16  「畢業門 / 收據                     回灌待辦項」（首張架構圖左欄「確定性外環（PowerShell）」）
README.md:240-244  `ps-doc-lint.ps1｜ps-auto-loop.ps1｜ps-auto-all.ps1｜ps-graduation.ps1｜ps-fs-doctor.ps1` 五支腳本表
scripts/ps-auto-loop.ps1:21-24  「# 停機條件（七保險絲）：/ 畢業（三層門全過，見下）／連續 2 圈無進度／連續 2 次逾時／連續 2 次 session 錯誤／強殺後檔案一致性 FAIL／audit 相位連續 2 圈零回灌未畢業（活鎖熔斷）／圈數上限」
scripts/ps-auto-loop.ps1:25-31  「# 兩段式畢業（tier）……門＝SESSION_OK＋WORK_TRANSITION_O…
```

**建議最小修法**：最小修法（改 docs/system-overview.html 三處）：(1) 指令速查表 :291 補四列管理者腳本——ps-auto-loop.ps1（單領域自動迴圈，-Preflight／-Tier 1|2）、ps-auto-all.ps1（多領域批次兩趟）、ps-graduation.ps1（收據寫入與驗證）、ps-fs-doctor.ps1（檔案系統健檢）；(2) TRUST 段 :313-321 的 gates 由四道改五道，新增「確定性外環：tier 1／tier 2 兩段式畢業門＋graduation.json 收據＋七道熔絲，模型說做完不算數」（文案直接沿用 README.md:200-233）；(3) 修數字：:136 的 8 改 9，:363 的「13 份」改 17。若不想維護內容，替代做法是在 :132 meta 行加一句明文範圍「本頁只涵蓋互動使用者路徑；無人值守外環（自動迴圈／畢業門／收據）見 README.md 與 SOP-14／SOP-16」——但依 L0，最好同時在 scripts/ps-doc-lint.ps1 加一條機械檢查：比對 :291 表列的 .ps1 名稱集合與 scripts/*.ps1 實檔集合、以及 tile 數字與 .opencode/agent/ps-*.md 檔數，不一致即 FAIL，免得下次再漂。


### M13. 空殼章節／缺章節／checklist 對帳類缺料違規全數無自動修復管道，且 agent 被明文禁止重查已勾項；熔絲會誤殺有進度的 run、tier-1 auditStall 停機訊息指向不存在的 strict-cycle*.txt

**涉及**：scripts/ps-doc-lint.ps1, scripts/ps-auto-loop.ps1, .opencode/agent/ps-deep-research.md

**指控**：CoverageOnly 缺料類中「缺章節」「章節空白（空殼）」「checklist 缺節標題」「已打勾但檔案不存在／檔案未列於 checklist」「archive 含未勾項」全部：(1) 不進手術工單（工單只收洩漏/欄位/證據三型）；(2) research 相位收不到 lint 結果（prompt 只有領域名）；(3) 出問題的檔多半已打勾，而 agent 規則明文「不重查已打勾項、不回讀已完成的 NN-*.md 內容」——制度上根本沒有任何 session 會被叫去修。後果一：tier-1 進度尺量「缺料違規數有沒有變少」，一條修不掉的違規讓 na≥nb 恆成立，正在消化 checklist 的健康 run 也被判「連續 2 圈無進度」停機——與程式自己 644-648 行寫的設計意圖（避免把正在推進的 run 判成卡住）直接互撞。後果二：tier-1 的 auditStall 熔斷訊息硬編碼「看 GATE 行與 strict-cycle*.txt」，但 tier 1 只寫 coverage-cycle*.txt、從不寫 strict-cycle*.txt——停機訊息指向不存在的檔。（其中 archive 未勾項另有獨立矛盾：唯一修法被 agent 規則明文禁止，見該筆。）

**驗證**：親自打開三個檔逐行核對，指控引用的行號全部屬實，非盲掃誤讀：

【屬實部分】
1) 缺料類確實不進手術工單。ps-doc-lint.ps1 的工單觸發條件只看 truncatedIds／missingIds／leakDelegable／misplacedRefRows 四個集合（681），缺章節（279）、章節空白（297）、checklist 缺節標題（187）、已勾但檔不存在（226）、檔案未列 checklist（233）、archive 未勾（215）、空檔（273）、wiki 空檔（525）都只進 $violations，且都不在 631-642 的 $polishPatterns 白名單內＝CoverageOnly 下原封不動保留為擋 tier-1 門的違規。auto-loop 的工單擷取只認「=== 證據/手術式修復指令 … === 指令結束 ===」區塊內的編號行（ps-auto-loop.ps1:349-353），所以這些訊息連被貼給模型的機會都沒有。
2) research 相位確實收不到 lint 結果：`-PromptText $Domain`（460-461），只有領域名。
3) agent 規則 44-45 確實明文「不重查已打勾項、不回讀已完成的 NN-*.md 內容」。
4) 後果二完全屬實且最無爭議：637 的停機訊息硬編碼 strict-cycle*.txt，但 578-583 的 tier 1 分支只寫 coverage-cycle{N}.txt，587 的 strict-cycle 只在 tier 2 分支寫；而 auditStall 這段（630-639）兩個 tier 共用。tier 1 跑到這條熔斷時，訊息指的檔一定不存在（tier 2 在「未勾≠0 或 lint≠0」時同樣沒有該檔）。
5) 後果一方向屬實但措辭過強。「一條修不掉的違規讓 na≥nb 恆成立」不對——只要其他違規有減少 na<nb。但真正的失效模式成立：tier 1 只有 coverage FAIL 才進 research（450-452），而 resea…

**原文佐證**：
```
【屬實】
/home/user/MCPSample/scripts/ps-doc-lint.ps1:279 — `$violations += "${name}：缺章節「$sec」"`
/home/user/MCPSample/scripts/ps-doc-lint.ps1:297 — `$violations += "${name}：章節「$sec」空白（有標題無實質內容——空殼／僅註解／「同前」類省略語；git 考古或開重查工單）"`
/home/user/MCPSample/scripts/ps-doc-lint.ps1:215 — `$violations += "$($af.Name)：含 $untickedInArchive 個未打勾項——歸檔只准搬已勾項…"`
/home/user/MCPSample/scripts/ps-doc-lint.ps1:681 — `if (($truncatedIds.Count + $missingIds.Count + $leakDelegable.Count + $misplacedRefRows.Count) -gt 0) {`（工單只由這四個集合組成，缺料類不在內）
/home/user/MCPSample/scripts/ps-auto-loop.ps1:349-351 — `if ($raw -match '(?s)=== (?:證據|手術式)修復指令.*?===(.*?)=== 指令結束 ===') { $block = $Matches[1]; $surgical = @($block -split "\`r?\`n" | Where-Object { $_ -match '^\s*\d+\.\s' } …`
/home/user/MCPSample/scripts/ps-auto-loop.ps1:460-461 — `$r = Invoke-Opencode -ExtraArgs '--command ps-research' -PromptText $Domain \`` / `    -TimeoutMin $ResearchTimeoutMin -Tag "research"`
/home/user/MCPSample/.opencode/agent/ps-deep-research.md:45 — `不重查已打勾項、不回讀已完成的 NN-*.md 內容。`
/home/user/MCPSample/scripts/ps-auto-loop.ps1:658 — `$stalled = ($…
```

**建議最小修法**：兩處最小改動，都在 /home/user/MCPSample/scripts/ps-auto-loop.ps1：(1) 第 637 行把硬編碼檔名改成依 tier 分流，例如 `$logHint = if ($Tier -eq 1) { "coverage-cycle$cycle.txt" } else { "strict-cycle$cycle.txt（未寫出則看 lint-cycle$cycle.txt）" }`，訊息改成「看 GATE 行與 $logHint 後人工處理」；(2) 第 658 行的 tier-1 熔絲加「勾掉項目也算進度」的除外條款：`$stalled = ($na -ge $nb -and $nb -gt 0 -and $after.Ticked -le $before.Ticked)`，讓正在消化 checklist 的圈不被判無進度（卡住的結構違規最終仍由 tier-1 畢業門擋下並照 SOP-2 第 3 步／L33 開 A<n> 工單人工處理）。若要再進一步，可在 ps-doc-lint.ps1 第 768 行的「人工處理清單」區塊比照 leakManual，把缺章節／空殼／checklist 對帳類另印一段「人工出口（貼 SOP-2 第 3 步／L33：開 A<n> 重查工單）」，使該類違規在 headless log 內也有明文出口。


### M14. ps-doc-lint 檔頭宣稱 -StrictAudit 會把「缺模板章節」升為 FAIL，程式已改為任何模式都只留警告（節內註解 462-463 同樣過期）

**涉及**：scripts/ps-doc-lint.ps1

**指控**：【原批內已合併 2 筆：同一過期宣稱的兩種措辭】檔頭（11-12 行）宣稱 -StrictAudit 把四類 90-audit 結構性問題（缺檔／缺模板章節／缺輪次表頭／記分卡範圍塌縮）由警告升 FAIL；但程式裡「缺模板章節」在 471-477 行無條件只進 $warnings，且註解明說是 L36 的刻意改動（標題飄移只留警告，改驗結構化全量覆蓋）。其餘三類確有升級（483-486 缺輪次表頭、493-496 輪次不一致、500-503 記分卡覆蓋塌縮、505-509 檔案不存在）。檔頭列舉是改 L36 前的過期宣稱；同節註解 462-463 也仍寫「-StrictAudit 時本節的結構性問題升為違規」。讀檔頭／註解設計 tier 2 門檻的人會以為 StrictAudit 綠＝模板章節齊全、缺模板章節會擋畢業，實際兩者都不成立。

**驗證**：我親自打開 /home/user/MCPSample/scripts/ps-doc-lint.ps1 並逐行核對，指控屬實且無任何可化解的明文豁免。

(1) 檔頭 11-12 行確實把「缺模板章節」列進「-StrictAudit 由警告升為 FAIL」的四類清單。
(2) 但 471-477 行的模板章節迴圈**完全沒有 $StrictAudit 分支**，無條件 `$warnings +=`。我用 Grep 掃過全檔 $StrictAudit 的每一處出現（3/11/18/463/485/495/502/505/508 行），確認全檔沒有第二個地方處理 $auditSections——485（缺輪次表頭）、495（輪次不一致）、502（記分卡覆蓋塌縮）、505-508（檔案不存在）四處確有 `if ($StrictAudit) { $violations }`，唯獨模板章節沒有。指控對「其餘三類確有升級」的描述也正確。
(3) 473-474 行的程式註解明說這是 L36 的**刻意**改動，不是漏寫。
(4) 我進一步交叉查證 .opencode/peoplesoft/lessons/applied.md 的 L36 條目，699-700 行白紙黑字寫「(3) 模板章節缺失一律降為警告」——設計意圖與程式一致，過期的是檔頭那句 prose。
(5) 節內註解 462-463「-StrictAudit 時本節的結構性問題升為違規——僅限本節」同樣過期，且比檔頭更誤導：本節六個 $auditSections 檢查與 480-481 的契約外詞彙檢查都不升級，只有三個檢查升級。註意 478-479 行有為契約外詞彙寫明「任何模式都只警告」的豁免說明，卻**沒有**替模板章節在 462-463 補同樣的更正——這正好反證作者更新註解時漏了這條。

後果與框架鐵律相關：tier2 門＝未勾0＋基礎lint綠＋StrictAudit綠。讀檔頭設計 tier2 的人會推論「StrictAudit 綠＝90-audit.md 模板章節齊全」，實際不成立；反向也不成立（缺模板章節不…

**原文佐證**：
```
以下皆為我自己讀到的原文：

scripts/ps-doc-lint.ps1:11-12
```
# -StrictAudit＝auto-loop 畢業門專用（issue #2）：90-audit.md 的結構性問題
# （缺檔／缺模板章節／缺輪次表頭／記分卡範圍塌縮）由警告升為 FAIL。
```

scripts/ps-doc-lint.ps1:462-463（節內註解，同樣過期）
```
# 2.5) 90-audit.md 模板符合度（每輪稽核會重寫，偏離記警告不擋；
#      -StrictAudit 時本節的結構性問題升為違規——僅限本節，wiki 類不升級）
```

scripts/ps-doc-lint.ps1:471-477（實際行為：無 $StrictAudit 分支）
```
    foreach ($sec in $auditSections) {
        if ($auditText -notmatch [regex]::Escape($sec)) {
            # 標題飄移只留警告（L36）——畢業門改驗「結構化全量覆蓋」的事實，
            # 綁標題字串會讓純命名問題變成無修復管道的活鎖
            $warnings += "90-audit.md：缺模板章節「$sec」（報告偏離模板；若記分卡改名，覆蓋檢查仍會驗全量）"
        }
    }
```

對照組——其餘三類確有升級（scripts/ps-doc-lint.ps1:485、495、502、505-508）
```
485:        if ($StrictAudit) { $violations += $msg } else { $warnings += $msg }
495:        if ($StrictAudit) { $violations += $msg } else { $warnings += $msg }
502:        if ($StrictAudit) { $violations += $msg } else { $warnings += $msg }
505: elseif ($StrictAudit) {
508:     $violations += "90-audit.md 不存在（StrictAudit：畢業門要求稽核報告存在）"
```

交叉查證設計意圖 —— .opencode/peoplesoft/lessons/applied.md:697-7…
```

**建議最小修法**：兩處 prose 對齊程式（不動邏輯）：
1) scripts/ps-doc-lint.ps1:11-12 的括號清單刪掉「缺模板章節」，改成「（缺檔／缺輪次表頭／輪次不一致／記分卡範圍塌縮）由警告升為 FAIL；缺模板章節任何模式都只警告（L36：畢業門驗結構化全量覆蓋的事實，不驗標題字串）」。
2) scripts/ps-doc-lint.ps1:463 改為「-StrictAudit 時本節的『事實類』問題（輪次表頭／輪次一致性／記分卡覆蓋）升為違規；『措辭類』（缺模板章節、契約外詞彙）任何模式都只警告——僅限本節，wiki 類不升級」。


### M15. ps-doc-lint 註解稱欄位錯放「不進手術單」，實際碼把 misplacedRefRows 印進手術式修復指令並由 auto-loop 餵給手術 session（且只剩此類時 exit 0 使工單永不被餵入）

**涉及**：scripts/ps-doc-lint.ps1, scripts/ps-auto-loop.ps1

**指控**：【跨批合併：原批內已合併 2 筆＋另一批同一過期註解一筆】402-406 行註解對欄位錯放的定性是「整列有可重跑的東西＝證據沒丟，稽核追得到——**降為警告**，不擋門也不進手術單；但要點名」；但工單輸出的觸發條件（681 行）把 $misplacedRefRows.Count 納入總和，694-704 行把它們按檔合併印成「[欄位]」編號行，727-737 還印整段【欄位】型修法——編號行正是 ps-auto-loop Invoke-Lint（349-353 行）擷取的手術清單，auto-loop 的手術 prompt（533 行）也專門寫了 [欄位] 型修法。同檔前後兩段註解與行為互撞：前段說不進單，後段（691-693 行）解釋怎麼進單。「不擋門」為真、「不進手術單」為假——是 L55 時代（applied.md:1149-1150「不擋門、不進手術單」）的殘留，L57（applied.md:1200-1202「不是違規（證據追得到）但要進工單，因為修它最便宜」）改版後未更新。附帶的實際行為缺口：當領域只剩欄位錯放（警告、exit 0）時，lint 會印出 PASS 加一張「現在從第 1 筆開始」的工單，而 auto-loop 的手術迴圈條件是 $lint.Exit -eq 1——這張工單永遠不會被自動餵入，只有伴隨其他違規時才會被修；按檔合併的設計理由（「auto-loop 一圈只吃 7 筆」）在該狀態下落空，只剩人工複製貼上一條路，文件未說明。

**驗證**：親自開檔逐行核對，指控的每一點都成立，且無任何明文範圍／豁免可化解。

(1) 註解與行為互撞為真。ps-doc-lint.ps1:402-405 的註解明寫「不擋門也不進手術單」，但同檔 681 行的工單觸發條件把 $misplacedRefRows.Count 納入總和，694-704 行把它們按檔合併印成「$i. [欄位] …」編號行，727-737 行再印整段【欄位】型修法。同檔 691-693 行的註解甚至反過來解釋「怎麼進單、為何按檔合併」——前後兩段註解自相矛盾。

(2) 「不擋門」為真、「不進手術單」為假。misplacedRefRows 全檔只出現 5 處（262 宣告、415 收集、617-618 加 warnings、681 併入工單條件、695/727 印工單），從未進過 $violations，所以 exit code 不受影響（666-673）；但它確實進了工單。

(3) 是 L55→L57 的過期殘留。applied.md:1149-1150（L55）確實寫「不擋門、不進手術單」，與 ps-doc-lint.ps1:404-405 逐字同源；applied.md:1200-1202（L57）已改版為「不是違規（證據追得到）但要進工單，因為修它最便宜」，且明寫「auto-loop 的手術 prompt 同步加 [欄位] 分流（放在最前面）」——腳本照做了（ps-auto-loop.ps1:533 prompt 開頭即 [欄位] 分流），只有 404-405 的註解沒跟著改。

(4) 編號行確實是 auto-loop 的手術清單來源：ps-auto-loop.ps1:349-353 從「=== 證據|手術式修復指令 … === 指令結束 ===」之間只擷取 ^\s*\d+\.\s 開頭的編號行；ps-doc-lint.ps1:765 正是印出 "=== 指令結束 ==="。故 [欄位] 編號行 100% 會被餵進手術 session。

(5) 附帶的 exit 0 缺口也為真且我逐行確認：misplacedRefRows 只走 617-…

**原文佐證**：
```
— 過期註解（我讀到的原文）
/home/user/MCPSample/scripts/ps-doc-lint.ps1:402-405
「# 欄位錯放（管理者實測）：證據其實在「位置」欄，機器參照欄
 # 只寫「PeopleCode chunk」這種標籤。整列有可重跑的東西＝
 # 證據沒丟，稽核追得到——**降為警告**，不擋門也不進手術單；
 # 但要點名，否則表格會一路歪下去。」

— 但同檔實際把它印進工單
/home/user/MCPSample/scripts/ps-doc-lint.ps1:681
「if (($truncatedIds.Count + $missingIds.Count + $leakDelegable.Count + $misplacedRefRows.Count) -gt 0) {」
/home/user/MCPSample/scripts/ps-doc-lint.ps1:685
「    Write-Host "（[欄位] 型已按檔合併＝一個檔一個任務；[洩漏]／[證據] 型逐列）"」
/home/user/MCPSample/scripts/ps-doc-lint.ps1:691-693（同檔後段註解，與 404-405 互撞）
「    # [欄位] 型按**檔**合併成一個任務：對調欄位是純編輯，一個檔一次改完最省
     # ——逐列開單會把 30 列變成 30 個任務，而 auto-loop 一圈只吃 7 筆（實案：
     # 錯放 30 餘列，逐列開單要 5 圈、每圈還先燒一個稽核 session）」
/home/user/MCPSample/scripts/ps-doc-lint.ps1:702-704
「        $i++
         $lns = @($swapByFile[$fn])
         Write-Host "$i. [欄位] ${fn}：$($lns.Count) 列欄位錯放（行 $($lns -join '、')）"」
/home/user/MCPSample/scripts/ps-doc-lint.ps1:727-728
「    if ($misplacedRefRows.Count -gt 0) {
         Write-Host "【欄位】型（**最便宜：純編輯，不要重查、不要呼叫任何工具**）："」

— 只進 warnings、不進 violations（故「不擋門」為真、exit 0）
/home/user/MCPSample/scripts/p…
```

**建議最小修法**：兩處最小修法：(1) 把 /home/user/MCPSample/scripts/ps-doc-lint.ps1:404-405 的註解改成 L57 的定性，例如「證據沒丟，稽核追得到——**降為警告不擋門**，但仍進手術單（[欄位] 型：純編輯零工具呼叫，修它最便宜，見 L57）；並點名列號」，刪掉「也不進手術單」。(2) 補上 exit 0 的餵入路徑：把 /home/user/MCPSample/scripts/ps-auto-loop.ps1:521 的條件由 `$lint.Exit -eq 1 -and $lint.Surgical.Count -gt 0` 改為 `($lint.Exit -eq 1 -or $lint.Exit -eq 0) -and $lint.Surgical.Count -gt 0`（保留排除 exit -1／3 的死亡與未建檔情形），使「只剩欄位錯放、lint PASS」時那張工單仍會被自動吃掉；若刻意不修，則需在 691-693 註解明寫「exit 0 時本單只能人工貼」的例外。


### M16. 手術工單的 [洩漏] 行把 </think>、<|im_start|> 等原樣標記注入 opencode prompt，違反 Invoke-Opencode 自己宣告的「prompt 禁用 > < & | % ^」契約

**涉及**：scripts/ps-auto-loop.ps1, scripts/ps-doc-lint.ps1

**指控**：【跨批合併：兩批各留一筆的同一契約違反】ps-auto-loop.ps1:215-216 宣告 prompt 走 cmd.exe 命令列，「內容禁用半形雙引號與 cmd 特殊字元（> < & | % ^）」。但 ps-doc-lint 的 [洩漏] 工單行（689 行）原樣印出洩漏標記 $($t.Marker)，標記集合（575 行 leakPattern）全是 </think>、<|im_start|>、<|im_end|>、<|endoftext|>、</tool_call>、<function= 這類含 < > | 的字串；auto-loop 把工單行 join 進 $flat（526 行，只把半形雙引號換單引號）再嵌入 $sPrompt（533 行）送上 cmd.exe 命令列。框架自己的管線系統性產生違反自己 prompt 契約的內容，未經任何消毒或豁免註記——目前僅靠命令列各層雙引號包裹未爆，但依契約這種 prompt 根本不該被組出來，依產生器這種 prompt 每次有洩漏工單都會被組出來。

**驗證**：I opened both files and traced the whole chain; every cited line exists verbatim and the links between them hold.

1. The contract is real and is stated as a property of PromptText generally (not scoped to hand-written literals): the comment sits directly above `function Invoke-Opencode` and says "內容禁用" — content, not "literals in this file".
2. The marker set at ps-doc-lint.ps1:575 does consist entirely of strings containing `<`, `>`, and/or `|`.
3. The marker is stored raw (`Marker = $m.Value`, line 588) and printed raw at line 689.
4. Critically — I checked the extraction window, which the accusation did not spell out but which the claim depends on. Line 689 sits inside the `if` block opened at 681, whose banner is printed at 683 (`=== 證據修復指令…===`) and whose terminator is at 765 (`=== 指令結束 ===`). That is exactly the window ps-auto-loop.ps1:349 matches, and lines 351-352 pull the numbe…

**原文佐證**：
```
CONTRACT — /home/user/MCPSample/scripts/ps-auto-loop.ps1:215-216 (immediately above `function Invoke-Opencode` on line 217):
"# 注意：prompt 走 cmd.exe 命令列——內容禁用半形雙引號與 cmd 特殊字元
 # （> < & | % ^），中文引號「」不受限；多行內容一律壓成單行。"

VIOLATING PAYLOAD — /home/user/MCPSample/scripts/ps-doc-lint.ps1:575:
"$leakPattern = '</?think(ing)?>|<\|im_(start|end)\|>|<\|endoftext\|>|</?tool_call>|<function='"

/home/user/MCPSample/scripts/ps-doc-lint.ps1:588 (stored raw):
"$leaks += @{ File = $lf.Name; Line = $lline; Marker = $m.Value; Delegable = $delegable }"

/home/user/MCPSample/scripts/ps-doc-lint.ps1:689 (printed raw):
"Write-Host \"$i. [洩漏] $($t.File):$($t.Line)：$($t.Marker)\""

EXTRACTION WINDOW — proves line 689 is inside the block auto-loop scrapes:
/home/user/MCPSample/scripts/ps-doc-lint.ps1:683:
"Write-Host \"=== 證據修復指令（複製整段貼給 PS-DEEP-RESEARCH；超過 7 筆請分批貼）===\" -ForegroundColor Cyan"
/home/user/MCPSample/scripts/ps-doc-lint.ps1:765 (same if-block, opened at 681, closed at 767):
"Write-Host \"=== 指令結束 ===\" -ForegroundColor Cyan"

VERBATIM CAPTURE — /home/user/MCPSample/scripts/ps-auto-loop.ps1:349-352:…
```

**建議最小修法**：Fix the sanitizer, not the marker: at ps-auto-loop.ps1:526 extend the scrub to the character that actually survives cmd's quote wrapper, e.g. `$flat = ($batch -join "；") -replace '"', "'" -replace '%', '％'` (full-width `％` keeps the ticket readable to the model while killing cmd variable expansion — the same trick the contract already sanctions for 「」). Then amend the ps-auto-loop.ps1:215-216 comment to state the real, testable rule and grant the explicit exemption L63 demands, e.g. "PromptText 一律被外層雙引號包住，故 > < & | ^ 在引號內失去特殊意義（lint 洩漏工單的 </think>、<|im_start|> 等標記據此豁免）；唯半形雙引號與 % 仍會破壞引號／被展開——動態…


### M17. Get-ChecklistState 仍用 \d+ 加 [int] cast 解析稽核輪次——同檔 Get-AuditTransition 的註解明文記載「全形數字 cast 會炸」且只修了自己

**涉及**：scripts/ps-auto-loop.ps1

**指控**：Get-AuditTransition 的註解（142-144 行）記載兩個教訓：「取『最後一個』匹配（防模型追加新行未刪舊行時撈到舊值）；只認半形數字（全形數字 cast 會炸）」，並照做（152 行 [0-9]+、無 break）。但十幾行外的 Get-ChecklistState（136 行）解析同一個 checklist 欄位仍用 .NET \d（會匹配全形數字）＋[int] cast＋首個匹配即 break：模型寫出全形輪次時，136 行的 [int]$Matches[1] 正是註解宣告會炸的那個 cast，炸點在每圈開頭的 $before = Get-ChecklistState（428 行），$before 變 null 後相位判定連鎖失真；模型追加新輪次行未刪舊行時，首匹配撈到舊值。同一檔案對同一欄位存在「已知正確」與「已知會炸」兩套解析並存。

**驗證**：親自開檔逐行核對，指控引用的三處原文一字不差，且交叉查證後比指控更成立。ps-auto-loop.ps1:136 的 Get-ChecklistState 確實用 .NET `\d+`＋`break`＋`[int]` cast；十六行外 142-144 的註解明文寫下兩條教訓，152 行的 Get-AuditTransition 照做（`[0-9]+`、無 break）。機制成立：PowerShell 的 `-match` 不帶 RegexOptions.ECMAScript，`\d` 匹配 Unicode Nd 類（含全形 U+FF10-FF19），而 .NET 數字解析在 InvariantCulture 下只收半形，故 136 行確實會走到註解點名的那個炸點。

決定性的補強證據（審查者沒做的交叉查證）：全 repo 對「稽核輪次」這個同一欄位的其他四處解析，全都已遵守這兩條教訓——ps-doc-lint.ps1:148-152 用 `[0-9]+`＋foreach Matches 取最後一個＋同樣的 -1 哨兵，ps-doc-lint.ps1:165、490 亦為 `[0-9]+`。136 行是全庫唯一同時違反兩條教訓的孤例，可見這是通則而非 Get-AuditTransition 的函式內特例。ps-doc-lint.ps1:164 註解「容忍全形／半形括號」更證明框架自己知道本模型會產出全形字元。

指控的推論有兩處該修正，但都不能救該行：一、Get-ChecklistState 的 .Round 只用於顯示（370／429／680），相位判定在 447／455 走 .Exists 與 .Unticked，「相位判定連鎖失真」屬誇大；二、cast 失敗在 PowerShell 是 terminating error，$before 不會變 null，而是例外直接往上拋——428 行外無任何 try/catch（403 的 try 只包 mutex），無人值守迴圈當場整支死掉，比指控描述更糟而非更輕（mutex 尚可靠 406 的 AbandonedMutex…

**原文佐證**：
```
親自讀到的原文：

1) ps-auto-loop.ps1:134-137（Get-ChecklistState，違規側）
```
    $round = -1
    foreach ($l in $lines) {
        if ($l -match '稽核輪次[：:]\s*(\d+)') { $round = [int]$Matches[1]; break }
    }
```

2) ps-auto-loop.ps1:142-144（明文教訓註解）
```
# Round 正規化：checklist 缺「稽核輪次」行視為 0（與 ps-audit 契約「沒有該行
# 視為 N=0」對齊——外環用 -1 哨兵會造成首輪 off-by-one 誤判）；取「最後一個」
# 匹配（防模型追加新行未刪舊行時撈到舊值）；只認半形數字（全形數字 cast 會炸）。
```

3) ps-auto-loop.ps1:150-154（Get-AuditTransition，合規側：半形＋無 break）
```
    if (Test-Path $clPath) {
        foreach ($l in (Get-Content $clPath -Encoding UTF8)) {
            if ($l -match '稽核輪次[：:]\s*([0-9]+)') { $round = [int]$Matches[1] }
        }
    }
```

4) 全庫通則佐證——ps-doc-lint.ps1:148-153（同欄位、同 -1 哨兵，但半形＋取最後一個）
```
$clRound = -1
if ($null -ne $checklistOnly) {
    foreach ($m in [regex]::Matches($checklistOnly, '稽核輪次[：:]\s*([0-9]+)')) {
        $clRound = [int]$m.Groups[1].Value
    }
}
```

5) ps-doc-lint.ps1:164-165（框架自認模型會寫全形）
```
    # 容忍全形／半形括號、有無「於」、冒號與空白差異：只要「稽核輪次<數字>…換版」
    $mv = [regex]::Match($ovText, '稽核輪次\s*[：:]?\s*([0-9]+)\s*[^0-9]{0,6}?換版')
```

6) ps-auto-loop.ps1:427-429（炸點…
```

**建議最小修法**：把 ps-auto-loop.ps1:136 改成與 152 行／ps-doc-lint.ps1:150 一致的解析法：`if ($l -match '稽核輪次[：:]\s*([0-9]+)') { $round = [int]$Matches[1] }`——正則改半形 `[0-9]+`、刪掉 `break` 讓最後一個匹配勝出。保留 134 行 `$round = -1` 的哨兵初值不動（Get-ChecklistState 用 -1 表示「無該行」供顯示，與 Get-AuditTransition 刻意正規化為 0 的畢業門語意不同，142-143 註解已說明此差異）。


### M18. Test-FsConsistency 以裸 $LASTEXITCODE 判「lint 無法正常執行」，未套用同檔 Invoke-Lint 明文記載的殘值防呆

**涉及**：scripts/ps-auto-loop.ps1

**指控**：Invoke-Lint（343-345 行）明文記載並防堵殘值陷阱：「防呆：lint 若中途死亡未跑到 exit，$LASTEXITCODE 是上一個原生命令的殘值——exit 0 但輸出無 PASS 標記＝不得當通過」。但 Test-FsConsistency（204-205 行）對同一支 lint 的同型呼叫「& $lintPath -Domain $Domain *> $null; if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1)」沒有任何等價防呆，且輸出被 *> $null 丟棄、連 PASS 標記都無從查驗。此檢查唯一的存在目的就是抓「lint 無法正常執行」，而它抓不到的正是 lint 死在半路未跑到 exit 的情況——此時 $LASTEXITCODE 是強殺路徑上前一個原生命令 taskkill（279 行）的殘值（成功殺樹＝0），落在 0/1 白名單內，一致性誤判 PASS、迴圈續跑。同一條自家教訓（L44/L49「要可觀測事實不要 API 承諾」）在同檔兩處只套用了一處。

**驗證**：親自開檔逐行核對，指控的三個錨點全部屬實，且我另外找到第四個佐證與一條「無法辯護」的關鍵事實。

(1) 兩處呼叫確實存在且不對稱：Invoke-Lint（342-345）先把 $LASTEXITCODE 存進 $code，再用「輸出有無 PASS：標記」做交叉驗證；Test-FsConsistency（204-207）對同一支 lint 做同型呼叫，卻直接裸讀 $LASTEXITCODE，且用 *> $null 把輸出整個丟掉——連做 PASS 標記交叉驗證的原料都沒有。全檔 grep LASTEXITCODE 只有 205、206、342、343 四筆，205/206 前後沒有任何 sentinel 重設（例如 $global:LASTEXITCODE = 99），確認防呆是真的缺席、不是換個寫法藏在別處。

(2) 殘值前提在本 repo 成立，不是理論風險：ps-doc-lint.ps1 全檔只有 35、101、111 三個早退 exit 2 與 783 的 exit $exitCode，沒有任何 top-level try/finally、trap 或 Set-StrictMode 兜底。lint 若在中段丟出 terminating error，就永遠跑不到 783 的 exit，$LASTEXITCODE 不會被更新——這正是 343-344 註解自己寫下的那個陷阱。

(3) 殘值來源與呼叫路徑吻合：Test-FsConsistency 的三個呼叫點（472、502、539）中，472 與 539 都在 $r.TimedOut／$sr.TimedOut 分支內，也就是剛跑完 279 行 taskkill 的強殺路徑；從 279 到 204 之間只有 Write-Log、Get-Item、Test-Path、Get-ChildItem 這些 cmdlet（不動 $LASTEXITCODE），所以殘值就是 taskkill 的結束碼，成功殺樹＝0，正落在 0/1 白名單內。$LASTEXITCODE 是 global 自動變數，跨函式可見，函式邊界不會隔離它…

**原文佐證**：
```
【缺防呆的一側】/home/user/MCPSample/scripts/ps-auto-loop.ps1:201-207
        # lint 以「僅回報」身分跑一次驗證它自己能執行——exit 0/1 都算可執行
        # （FAIL 內容交給正常迴圈處理）；這裡絕不接手術路徑
        if (Test-Path (Join-Path $dir "00-overview.md")) {
            & $lintPath -Domain $Domain *> $null
            if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1) {
                $problems += "lint 無法正常執行（exit=$LASTEXITCODE）"
            }
        }

【有防呆的一側，同檔同一支 lint】/home/user/MCPSample/scripts/ps-auto-loop.ps1:342-345
    $code = $LASTEXITCODE
    # 防呆：lint 若中途死亡未跑到 exit，$LASTEXITCODE 是上一個原生命令的殘值
    # ——exit 0 但輸出無 PASS 標記＝不得當通過
    if ($code -eq 0 -and $raw -notmatch 'PASS：') { $code = 3 }

【殘值來源：強殺路徑上的前一個原生命令】/home/user/MCPSample/scripts/ps-auto-loop.ps1:278-279
    if (-not $done) {
        & taskkill.exe /PID $p.Id /T /F 2>$null | Out-Null

【呼叫點確實在強殺分支，且 PASS 後 continue 跳過有防呆的 lint】/home/user/MCPSample/scripts/ps-auto-loop.ps1:471-481
    if ($r.TimedOut) {
        $fsProblems = Test-FsConsistency -HadChecklist $preHadChecklist -PreItemTotal $preItemTotal
        ...
        Write-Log "強殺後一致性檢查 PASS（唯讀）——維持既有重試邏輯"…
```

**建議最小修法**：在 /home/user/MCPSample/scripts/ps-auto-loop.ps1 把 Test-FsConsistency 的 203-208 行改為直接複用同檔已有的 Invoke-Lint（它已內建 PASS 標記防呆；兩函式都在呼叫點 472 之前定義完畢，PowerShell 不受宣告順序限制），即 `if (Test-Path (Join-Path $dir "00-overview.md")) { $lr = Invoke-Lint; if ($lr.Exit -ne 0 -and $lr.Exit -ne 1) { $problems += "lint 無法正常執行（exit=$($lr.Exit)）" } }`——lint 中途死亡時 Exit 會被防呆改成 3，落在 0/1 白名單外而正確攔下；Invoke-Lint 只回傳字串不印 console、呼叫端忽略 .Surgical，維持「純唯讀、絕不接手術路徑」的原則。


### M19. 證據列只要任何欄含「機器參照」四個字就被當表頭整列跳過——與同段自己宣示的 fail-safe 原則（判不出來就驗）相反

**涉及**：scripts/ps-doc-lint.ps1

**指控**：ps-doc-lint.ps1:393-396 註解明定範圍原則：「**不能靠「看到分隔列才開始」**：缺分隔列的表格會讓整段一列都不驗……改成直接認表頭欄名——fail-safe 方向：判不出來就驗，不要略過」。但實作（397）`$isEvHeader = ($line -match '機器參照') -or ($line -match '^\|\s*編號\s*\|')` 是對整列做子字串比對，不是認表頭欄位——任何資料列只要某一格出現「機器參照」字樣（例如說明欄寫「機器參照待補」）就被當表頭，整列逃過正面表列、待人工SQL、欄位錯放全部檢查。這重開了 L55 修掉的同型洞（整列不進判定＝不是判它合格，是根本沒判過）。

**驗證**：我逐行讀了 ps-doc-lint.ps1 的 351-431，指控對機制的描述完全屬實，且比指控寫的更明確：

1. 397 行的 `$line -match '機器參照'` 在 PowerShell 是**未錨定的整列子字串比對**（`-match` 對整個字串做 regex 搜尋，非等值比對），不是「認表頭欄位」。398 行 `-not $isEvHeader` 把整個正面表列區塊（399-429：okUuid/okSelect/okPending 判定、$pendingSqlRows 計數、$misplacedRefRows 欄位錯放、$violations、$missingIds 工單）全部跳過。所以任何一格出現「機器參照」四字的資料列，確實零違規零工單。

2. 我另外查證了指控沒提、但**加重**其可信度的一點：實際模板的表頭是 `| # | 位置 | 說明 | 機器參照 |`（function-detail-template.md:55），第一欄是 `#` 不是「編號」——所以 397 行第二個分支 `^\|\s*編號\s*\|` 對真正在用的模板**永遠不會命中**，整列子字串比對是唯一的表頭偵測器，這條路徑是承重的、不是備援。

3. 同段註解（393-396）與 applied.md:1151-1154 的 L55 自述用字一致：「改成直接認表頭欄名……fail-safe 方向：判不出來就驗，不要略過」。實作是 fail-open（判不出來就跳過），與自宣方向相反，且重開 L55 自己記載的「整列不進判定」同型洞（applied.md:1138「整列不進判定」）。

4. 觸發路徑不是假想：模板 65-72 與 ps-deep-research.md:133 都在教模型「機器參照欄寫 `待人工SQL`」，425 行的違規訊息也對模型說「機器參照欄應放可重跑的那一份」——小模型把欄名連同值寫進格子（「機器參照：待人工SQL」「機器參照待補」）是自然回寫行為。一旦發生，該列連 $pendingSqlRows 都不計數，還會反過來讓 599 行「宣稱環境…

**原文佐證**：
```
/home/user/MCPSample/scripts/ps-doc-lint.ps1:393-397（我讀到的原文）
```
                # 表頭列不驗（欄名不是證據）——但**不能靠「看到分隔列才開始」**：
                # 缺分隔列的表格會讓整段一列都不驗（與 L51 同型的範圍錯誤，
                # 自己的測試抓到）。改成直接認表頭欄名，缺分隔列時仍照驗
                # ——fail-safe 方向：判不出來就驗，不要略過。
                $isEvHeader = ($line -match '機器參照') -or ($line -match '^\|\s*編號\s*\|')
```
/home/user/MCPSample/scripts/ps-doc-lint.ps1:398（整個正面表列區塊的閘門）
```
                if ($line -match '^\|' -and $line -notmatch '^\|[\s:|-]+$' -and -not $isEvHeader) {
```
/home/user/MCPSample/scripts/ps-doc-lint.ps1:419-421（被一併跳過的合法出口計數）
```
                    if ($okPending -and -not ($okUuid -or $okSelect)) {
                        $pendingSqlRows += "${name}:${evLineNo}"
                    }
```
/home/user/MCPSample/.opencode/peoplesoft/report-templates/function-detail-template.md:55（實際表頭第一欄是 `#`，不是「編號」→ 397 行第二分支對真模板永不命中）
```
| # | 位置 | 說明 | 機器參照 |
```
/home/user/MCPSample/.opencode/peoplesoft/lessons/applied.md:1151-1154（自宣原則）
```
- 自己踩到的範圍錯誤：第一版用「看到分隔列 `|---|` 才開始驗」，遇到缺
  分隔列的表格會整段一列都不驗（與 L51 同型，被自己的回歸測試抓到）。
  改成直接認表頭欄名，缺分隔列時照驗——**…
```

**建議最小修法**：把 ps-doc-lint.ps1:397 的整列子字串比對改成**整格**比對（真正「認表頭欄名」），並補上模板實際用的 `#` 首欄：`$isEvHeader = ($line -match '\|\s*機器參照\s*\|\s*$') -or ($line -match '^\|\s*(#|編號|序號)\s*\|')`。這樣 `| 4 | x.pcode:1-9 | 機器參照待補 | 待補 |` 因該欄不是純欄名而照驗（fail-safe 方向一致），真表頭 `| # | 位置 | 說明 | 機器參照 |` 仍被跳過；同時在 test-scenarios.md 補一條回歸：說明欄含「機器參照」四字且無 UUID／SELECT／待人工SQL 的列必須產生違規。


### M20. 人工清單宣稱 90-audit 的洩漏「下一輪稽核會整檔重寫、自然消失」，但 tier 1 相位規則使那一輪稽核在洩漏修掉之前永遠不會發生

**涉及**：scripts/ps-doc-lint.ps1, scripts/ps-auto-loop.ps1

**指控**：【跨批合併：兩批各留一筆的同一遞迴死路】lint 人工清單（ps-doc-lint.ps1:775）對 90-audit 的洩漏給的理由是「90-audit 下一輪稽核會整檔重寫、自然消失；要現在乾淨就手動刪該段」；lint 註解 586 同句。但 90-audit 裡的洩漏標記是缺料類違規（582 行進 $violations、不在 polish 白名單）→ -CoverageOnly FAIL；而 auto-loop tier 1 的相位規則（ps-auto-loop.ps1:449-452）是 coverage FAIL → research、PASS 才 audit——洩漏違規本身讓 audit 相位永遠排不進來，「下一輪稽核」在自動迴圈裡是不可達狀態，「自然消失」的宣稱在 tier 1 下不成立。這正是 L63 定義的遞迴死路型（有管道，但管道被規則自身堵住）；實際收場只剩 2 圈無進度熔絲＋人工手刪，而等「自然消失」的操作者會先等到熔斷。

**驗證**：我逐檔開過所有被引用的行，五個環節全部屬實，且合起來確實封閉成環：

(1) 洩漏掃描不挑檔、90-audit 命中會進 $violations（ps-doc-lint.ps1:576-582，foreach 掃 $dir 下全部 *.md）。
(2) 該訊息不在美工白名單：$polishPatterns（:631-641）十條沒有任何一條 Contains 得到「模型內部標記洩漏」；而且 :623 的分界線註解把「模型標記或契約 JSON 洩漏」明文歸類為**缺料**。所以 -CoverageOnly 的降級迴圈（:650-657）會把它留在 $violations → exit 1 → tier 1 覆蓋門 FAIL。
(3) 90-audit 不可委派、不進工單，只進「**不要**貼給模型」的人工清單（:587 的 -notmatch '^(00|90)-'、:680、:770）。
(4) tier 1 相位規則就是拿這個 exit code 決定相位（ps-auto-loop.ps1:450-451）：coverage FAIL → research，PASS 才 audit。洩漏本身讓 coverage 永遠 FAIL，audit 相位永遠排不進來。
(5) 我另外查了兩條「可能化解矛盾」的旁路，兩條都被堵死：
    a. 手術（correct）session 是唯一會被自動餵 lint 清單的路徑，但它的 prompt 明文「禁止修改 checklist.md 與 90-audit.md，禁止執行稽核」（ps-auto-loop.ps1:533）。
    b. research run 收尾可自動接跑一輪稽核（會整檔重寫 90-audit），但前置規模門優先：ps-deep-research.md:152-156「已完成檔總數 > 5 時**本 run 不接稽核**」。所以只有 ≤5 檔的小領域能靠 research 自接稽核清掉；任何規模正常的領域（註解自己舉例 15 檔）在 tier 1 下永遠等不到那一輪。

因此 :775 給操作者的理由「下一輪…

**原文佐證**：
```
【擋門的一端】
/home/user/MCPSample/scripts/ps-doc-lint.ps1:582
`$violations += "$($lf.Name):${lline}：模型內部標記洩漏（寫入脫軌）：$($m.Value)——檢查該行**前後整個區塊**（常見：表格斷在半路＋思考文字），刪污染並補回被截斷的內容；補不回就開重查工單"`

ps-doc-lint.ps1:623（美工／缺料分界線註解，明文把洩漏歸缺料）
`#   缺料＝讀者讀不到或讀到壞東西：缺檔、空檔、缺章節、空殼章節、`
ps-doc-lint.ps1:624
`#         checklist 對帳不符、模型標記或契約 JSON 洩漏（疑似被截斷）。`

ps-doc-lint.ps1:631-641（$polishPatterns 全文，無任何一條命中洩漏訊息）
`$polishPatterns = @(` / `'Evidence 附錄空白',` / `'ChunkId 遭縮寫為 8 碼',` / `'ChunkId 非 UUID 格式',` / `'出現自編 id 樣式',` / `'疑似縮寫 chunk id',` / `'當機器參照',` / `'機器參照無效',` / `'行為邏輯無任何 confidence 標註',` / `'frontmatter 缺 ',` / `'status 值非法'` / `)`

【不可委派、不進工單】
ps-doc-lint.ps1:587
`$delegable = ($lf.Name -match '^\d\d-' -and $lf.Name -notmatch '^(00|90)-')`
ps-doc-lint.ps1:770
`Write-Host "=== 洩漏：人工處理清單（**不要**貼給模型）===" -ForegroundColor Yellow`

【被指控的宣稱本身】
ps-doc-lint.ps1:775
`elseif ($t.File -like '90-*') { $why = "90-audit 下一輪稽核會整檔重寫、自然消失；要現在乾淨就手動刪該段" }`
ps-doc-lint.ps1:586（同句的註解版）
`# （agent 零寫入）、90-audit 下輪稽核整檔重寫會自然消失。`

【堵住管道的一端：tier 1 相位規則】
/home/user/MCPSample/scripts/ps-auto-loop.ps1:449-452
`        if ($Tier -eq…
```

**建議最小修法**：改 ps-doc-lint.ps1:775 的理由字串，把「會自然消失」的無條件宣稱降為有條件並把手動刪提為主路徑，例如：`$why = "90-audit 只有 audit 相位會整檔重寫；tier 1 的相位門是「coverage PASS 才 audit」，這條洩漏本身就讓 coverage FAIL，自動迴圈不會自己走到那一輪（>5 檔領域連 research 收尾接稽核也被規模門擋掉）→ **現在手動刪該段**，或改跑 tier 2／單獨執行 /ps-audit <領域>"`。同步把 :586 的註解「90-audit 下輪稽核整檔重寫會自然消失」改成「90-audit 只有 audit 相位重寫，tier 1 下需人工刪或單跑 /ps-audit」，免得下一個讀 code 的人再照舊註解推理。


### M21. 契約 JSON 洩漏檢查只掃 90-audit＋NN 檔，checklist.md 不在範圍——同檔上一節才以 L51 宣示「模型寫得到的檔就掃得到，不要挑檔」

**涉及**：scripts/ps-doc-lint.ps1

**指控**：標記型洩漏掃描（ps-doc-lint.ps1:567-591）依 L51 掃領域內全部 .md，註解（569-570）明寫實案「checklist 的「Gaps 彙整」節混進 <think>，而該領域照樣通過 tier 1 畢業門。模型寫得到的檔就掃得到，不要挑檔」。緊鄰的 2.4 契約 JSON 洩漏檢查（439-441）卻用挑檔清單：`$rawJsonTargets` 只收 90-audit.md 與 $nnNames——checklist.md／checklist-archive*.md 都是模型反覆整檔覆寫的檔（ps-deep-research.md:95：read → 整檔覆寫），貼進 checklist Gaps 的 subagent JSON（不帶 <think> 標記時）完全無人看。

**驗證**：親自讀檔後，指控的每一項事實都成立，且找不到任何可化解矛盾的明文豁免。

1) 2.4 的範圍確實是挑檔清單。ps-doc-lint.ps1:439-441 把 $rawJsonTargets 限定為 90-audit.md ＋ $nnNames；而 $nnNames 在 264-265 被定義為「檔名符合 ^\d\d- 且不是 00-/90- 開頭」。因此 checklist.md、checklist-archive*.md、00-overview.md 全部落在 2.4 掃描之外。註解 438 只寫「掃 90-audit 與 NN 檔。」——那是範圍**陳述**，不是豁免理由，全節沒有任何一句說明為什麼 checklist 不掃（L63 要求的「明文豁免」不存在）。

2) 同檔 130 行後確實以 L51 宣示相反原則。567-570 的區塊標題明寫「**領域內全部 .md 統一掃描**」，並以實案說明「模型寫得到的檔就掃得到，不要挑檔」；577 的實作也如實用 Get-ChildItem -Filter "*.md" 列舉全部檔案，沒有白名單。

3) L51 的原則在教訓檔裡是**通則**而非只綁 <think> 標記：applied.md:1044-1046 寫「凡是『對某類檔做某種檢查』的規則，範圍就是規則的一半」「一條只覆蓋部分目標的檢查，比沒有檢查更危險」。2.4 正是「對某類檔做某種檢查」而範圍只涵蓋一部分。

4) 缺口是真實可達的，不是假想。ps-deep-research.md:92-97 顯示**同一個主 agent** 既委派 subagent（因而手上有契約 JSON），又對 checklist.md 做「read → 整檔覆寫」並把重大缺口寫進「Gaps 彙整」。契約鍵定義在 subagent-report-contract.md:56-59。所以 L47 的失敗簽名（原料未加工就出貨）在 checklist 上完全同型可發生。

5) 沒有任何替代管道補上。grep 全 scripts/ 只有 ps-doc-lint.ps1 有 ke…

**原文佐證**：
```
【挑檔清單（本人讀到的原文）】
/home/user/MCPSample/scripts/ps-doc-lint.ps1:438-441
  438: # 但簽名不同——這裡是「原料未加工就出貨」。掃 90-audit 與 NN 檔。
  439: $rawJsonTargets = @()
  440: if (Test-Path -LiteralPath (Join-Path $dir "90-audit.md")) { $rawJsonTargets += (Join-Path $dir "90-audit.md") }
  441: foreach ($n in $nnNames) { $rawJsonTargets += (Join-Path $dir $n) }

【$nnNames 的定義證明 checklist 不在內】
/home/user/MCPSample/scripts/ps-doc-lint.ps1:264-265
  264: Get-ChildItem -LiteralPath $dir -Filter "*.md" |
  265:     Where-Object { $_.Name -match '^\d\d-' -and $_.Name -notmatch '^(00|90)-' } |

【同檔宣示的相反鐵律】
/home/user/MCPSample/scripts/ps-doc-lint.ps1:567-570, 577
  567: # ── 模型內部標記洩漏：**領域內全部 .md 統一掃描**（L41／L51）─────────
  568: # L51：原本只掃 NN 檔，於是 checklist.md／00-overview.md／90-audit.md 的
  569: # 洩漏完全沒人看——實案：checklist 的「Gaps 彙整」節混進 <think>，而該領域
  570: # 照樣通過 tier 1 畢業門。模型寫得到的檔就掃得到，不要挑檔。
  577:     foreach ($lf in (Get-ChildItem -LiteralPath $dir -Filter "*.md" -File | Sort-Object Name)) {

【L51 是通則，不是只綁標記】
/home/user/MCPSample/.opencode/peoplesoft/lessons/applied.md:1041, 1044-1046
  1041:   每個標記只報一次）。不挑檔：**模型寫得到…
```

**建議最小修法**：把 ps-doc-lint.ps1:439-441 的挑檔清單換成與 577 相同的全檔列舉：`$rawJsonTargets = @(Get-ChildItem -LiteralPath $dir -Filter "*.md" -File | Sort-Object Name | ForEach-Object { $_.FullName })`（並把 438 註解的「掃 90-audit 與 NN 檔。」改成「掃領域內全部 .md（L51：不挑檔）」，順手刪掉現在多餘的 Test-Path 與 444 的空檔 continue 保留即可）；同時在 test-scenarios.md 的 J6 補一條 [致命] 檢查點把契約 JSON 的範圍也釘成「領域目錄下全部 *.md」，否則依 L51 原則範圍仍是沒被測試釘住的一半規則。458 的違規訊息已含人工修復路徑（「刪除該段並依契約內容重寫」），L53 出口不需另補；但此改動會變動 lintScriptHash → 既有收據全部失效，依 L51 的成本紀律應在領域畢業後才動手。


### M22. Evidence 義務檢查的範圍是「附錄標題到檔尾」而非到下一節，且 lint 不驗章節順序——Evidence 之後的任何表格列都會被派「補 chunk id」的無解工單

**涉及**：scripts/ps-doc-lint.ps1

**指控**：ps-doc-lint.ps1:353-355：`$evIdx = $text.IndexOf('## Evidence 附錄'); $evText = $text.Substring($evIdx)`——evText 一路取到檔尾，不像同檔的空心章節檢查（291-295）以下一個 `\n## ` 收界。requiredSections（256）只驗五個標題存在、不驗順序；模板雖把 Evidence 放最後，但 lint 的設計前提是「模型會自創標題／偏離模板」（53-56 行自述）。一旦模型把任何含表格的章節（如資料流、畫面與欄位）寫在 Evidence 附錄之後，那些表格列全數被套上證據義務：無 UUID 無 SELECT → 每列一條「機器參照無效」違規＋一筆 $missingIds 工單，指揮模型去替資料流表格「補完整 36 字元 id」——L42/L53 同族的無解工單。

**驗證**：親自讀檔逐點核對，指控的四個事實全部屬實，且沒有任何明文豁免化解它。

(1) 範圍確實取到檔尾。ps-doc-lint.ps1:353-355 用 `IndexOf` 定位後直接 `Substring($evIdx)`，沒有第二參數、沒有下一節收界；其後 366-368（附錄空白）與 376-431（逐列證據義務）全部吃這個 `$evText`。

(2) 對照組確實有收界。同檔 291-295 的空心章節檢查以 `` $after.IndexOf("`n## ") `` 取下一節為界，兩者寫法不一致這點成立。lessons/applied.md:643 也把該檢查明寫為「標題到下一個 ## 之間」，證明收界是本框架自己的既定寫法，Evidence 這裡是漏做不是刻意。

(3) 順序確實沒人驗。256 的 `$requiredSections` 只有五個標題，277-280 只做 `-notmatch` 存在性判斷；template 有九個 `## ` 章節（相關物件／畫面與欄位／執行方式／權限四個根本不在必驗清單裡），ps-deep-research.md 只有 prose 的「依 function-detail 模板寫」（第 78 行），無任何機械順序約束——L0「能機械化就不寫 prose」在此落空。

(4) 落到表格列上確實會派無解工單。397 的表頭豁免只認 `機器參照` 或 `^\|\s*編號\s*\|`，所以 `| 表 | 操作 | 來源 | 信心 |`（資料流）與 `| 欄位 | 顯示文字 | …`（畫面與欄位）連表頭都不豁免；422-428 對每一列補一條「機器參照無效」＋一筆 `$missingIds`。而 681 的手術單區塊**不受 `-CoverageOnly` 影響**（它讀 `$missingIds` 而非 `$violations`），所以 tier1 也照樣把這些列餵進 auto-loop；739 起的工單只有 A(補 chunk id)／B(貼 SELECT)／C(移除該列) 三個分支，對資料流表格三個都是錯的，走 C 還會把內…

**原文佐證**：
```
— 無收界（本案）：
/home/user/MCPSample/scripts/ps-doc-lint.ps1:353-355
```
        $evIdx = $text.IndexOf('## Evidence 附錄')
        if ($evIdx -ge 0) {
            $evText = $text.Substring($evIdx)
```

— 有收界（對照組，同一檔）：
/home/user/MCPSample/scripts/ps-doc-lint.ps1:293-295
```
                $after = $text.Substring($secIdx + $sec.Length)
                $nextIdx = $after.IndexOf("`n## ")
                $body = if ($nextIdx -ge 0) { $after.Substring(0, $nextIdx) } else { $after }
```

— 只驗存在、不驗順序，且只列五節：
/home/user/MCPSample/scripts/ps-doc-lint.ps1:256
```
$requiredSections = @('## 功能定位', '## 行為邏輯', '## 資料流', '## 未解事項', '## Evidence 附錄')
```
/home/user/MCPSample/scripts/ps-doc-lint.ps1:277-280
```
        foreach ($sec in $requiredSections) {
            if ($text -notmatch [regex]::Escape($sec)) {
                $violations += "${name}：缺章節「$sec」"
            }
```

— 表頭豁免認不出資料流／畫面與欄位的表頭：
/home/user/MCPSample/scripts/ps-doc-lint.ps1:397-398
```
                $isEvHeader = ($line -match '機器參照') -or ($line -match '^\|\s*編號\s*\|')
                if ($line -match '^\|' -and $line -notmatch '…
```

**建議最小修法**：在 /home/user/MCPSample/scripts/ps-doc-lint.ps1:355 比照 294-295 收界：`$evAfter = $text.Substring($evIdx); $evNext = $evAfter.IndexOf("`n## "); $evText = if ($evNext -ge 0) { $evAfter.Substring(0, $evNext) } else { $evAfter }`（$evStartLine 的算法不動，行號仍正確）。同時在 277-280 的必驗章節迴圈後補一條**警告**（非違規，避免 L53 活鎖）：若 `$text.LastIndexOf('## ') -ne $evIdx`，警告「Evidence 附錄不是最後一節——證據義務只驗到下一個 ## 為止，其後章節不受檢；請照 function-detail 模板把 Evidence 移到檔尾」，讓收界後被排除的證據列不會靜默漏驗。


### M23. SOP-8 的封鎖程序數字過期：「全部 9 個 agent 檔」與「補封 4 個 MCP」都不含／鎖死現況——照字面執行，下一個新註冊 MCP 會在三個內建覆寫檔預設全開，L15 側門對每個新 server 重新打開

**涉及**：.opencode/peoplesoft/SOP.md, .opencode/agent/explore.md, .opencode/agent/general.md, .opencode/agent/scout.md

**指控**：【跨批合併：兩批各留一筆的同一過期程序數字】SOP-8 的「新增 MCP server 註冊」檢查項寫死「先在全部 9 個 agent 檔的 tools 加 deny」，但 agent 檔現況是 12 個（9 個 ps-* ＋ 3 個內建覆寫檔，ls 實測）；同一份 SOP 的內建 agent 檢查項也把補鎖範圍寫死為「補封 4 個 MCP」。照字面走程序，第 5 個 MCP 只會被 deny 進 9 個 ps-* 檔，3 個覆寫檔沒列＝預設開（框架自己的 L1 教義），內建 agent 側門對每個未來新 server 自動重開，重演 SOP-8 自己後段記載的 2026-08 實測漏洞（委派漏到內建 explore 直呼 MCP）——同檔兩條規則（第一條的計數 vs 後段的內建覆寫要求）互相打架，正面違反 L15 收錄的原則「平台的預設能力（現在有的＋未來空降的）都在封鎖體系的守備範圍」。

**驗證**：親自開檔核對，指控的三項事實全部成立，且我另外查了「有沒有機械化補救」也沒有。

(1) SOP-8 第一條的數字寫死為 9，而實際 agent 檔是 12。`ls -la /home/user/MCPSample/.opencode/agent/` 實測共 12 個 .md：explore.md、general.md、scout.md ＋ 9 個 ps-*（ps-ae-flow / ps-auditor / ps-deep-research / ps-metadata-flow / ps-orchestrator / ps-peoplecode-flow / ps-sql-flow / ps-sqr-flow / ps-ui-flow）。「全部 9 個」正好等於 ps-* 的數量，literally 把 3 個內建覆寫檔排除在外——這不是模糊措辭可以救的，是精確計數。

(2) 三個覆寫檔確實只明列 4 個 server 前綴 deny，且檔內自己寫著「沒列＝預設開」的教義。三檔 frontmatter 完全相同，deny 清單止於 PeoplecodeMetadata_*。所以第 5 個 MCP 若只照第一條走，在這三檔一定是預設開。

(3) 後段內建 agent 檢查項也把範圍寫死成「補封 4 個 MCP」，且它的觸發條件是「OpenCode 升版」，不是「新增 MCP server 註冊」——就算未來管理者手動想到要補，這條的字面範圍也停在 4。兩條檢查項對「新 server × 內建覆寫檔」這個交叉格子都沒有覆蓋。

(4) 與框架自宣原則正面衝突：L15 的原則句明文說「現在有的＋未來空降的」都在守備範圍，而這正是 L1（新註冊 MCP 預設全開）的機械化落點。SOP.md:186 自己還寫明後果包含「其回傳也塞不進證據契約，誘發捏造」——即照字面執行 SOP 會重演它自己記載過的實測事故。

(5) 我特別查過有沒有 lint 當補網：`ls /home/user/MCPSample/scripts/` 只有 7 支，`grep -rln "agent"…

**原文佐證**：
```
【過期數字 1／9 vs 12】
/home/user/MCPSample/.opencode/peoplesoft/SOP.md:184-186
「□ 新增 MCP server 註冊 → 先在**全部 9 個 agent 檔**的 tools 加
  "<註冊名>_*": false（tools map 是覆寫表：沒列＝預設全開，主 agent 會
  直接呼叫繞過 subagent 架構；其回傳也塞不進證據契約，誘發捏造）。」

【實際檔數＝12（ls -la /home/user/MCPSample/.opencode/agent/ 實測輸出）】
explore.md / general.md / scout.md / ps-ae-flow.md / ps-auditor.md /
ps-deep-research.md / ps-metadata-flow.md / ps-orchestrator.md /
ps-peoplecode-flow.md / ps-sql-flow.md / ps-sqr-flow.md / ps-ui-flow.md
（其中 ps-* 恰為 9 個 → 「全部 9 個」literally 不含三個覆寫檔）

【過期數字 2／補鎖範圍寫死 4】
/home/user/MCPSample/.opencode/peoplesoft/SOP.md:198-201
「□ OpenCode 升版 → 檢查是否**新增內建 agent／subagent**（如 general／
  explore／scout）——內建不吃本專案的封鎖，須在 .opencode/agent/
  放**同名覆寫檔**補封 4 個 MCP（2026-08 實測：委派會漏到內建
  explore 直呼 MCP）」

【覆寫檔現況：只列 4 個前綴，且檔內自陳「沒列＝預設開」】
/home/user/MCPSample/.opencode/agent/explore.md:5-14
「  # L46：tools map 是覆寫表——沒列＝預設開。內建 agent 的 bash/write
  # 也必須顯式封鎖（委派漏到內建時才不會執行 shell 或寫檔）
  bash: false
  write: false
  edit: false
  webfetch: false
  "PeoplecodeElasticSearch_*": false
  "PeoplecodeSource_*": false
  "oracleMCP_*": false…
```

**建議最小修法**：改 /home/user/MCPSample/.opencode/peoplesoft/SOP.md 兩處寫死的數字，改成以目錄枚舉為準而非計數：第 184 行「全部 9 個 agent 檔」→「`.opencode/agent/` 底下**每一個** agent 檔（現為 12：9 個 ps-* ＋ 3 個內建覆寫檔 explore／general／scout；以 `ls .opencode/agent/*.md` 實際枚舉為準，不得靠記憶中的檔數）」；第 200 行「補封 4 個 MCP」→「補封**當前已註冊的全部 MCP server 前綴**（現為 4 個，以其他 agent 檔的 deny 清單為對照基準）」。同時把 lessons/applied.md:388-389 的「封 4 個 MCP」比照改為「封當前全部已註冊 MCP 前綴」以免下次再被當成權威數字抄走。若要真正機械化（符合 L0），可在 scripts/ps-doc-lint.ps1 加一條檢查：蒐集 .opencode/agent/*.md 中出現過的所有 `"<prefix>_*"` 前綴聯集，任一 agent 檔缺任一前綴即報違規並列出缺項（修復路徑明確＝符合 L53）。


### M24. 稽核模式任務 B 要求主 agent 從已完成檔抽 3~5 條 claim，硬規則卻禁止回讀已完成檔內容——無豁免

**涉及**：.opencode/agent/ps-deep-research.md, .opencode/agent/ps-auditor.md

**指控**：稽核模式步驟 1 要主 agent「每檔抽 3~5 條標 CONFIRMED 的重要 claim 再委派（任務 B）」，而 auditor 任務 B 契約是「給定 claims」（由委派方提供）——抽 claim 必須讀 NN 檔內容；但啟動規則與硬規則都無條件禁止回讀已完成檔（「不回讀已完成的 NN-*.md 內容」「已完成檔案的內容不回讀進主 context」），且 148-151 的稽核豁免只解除「收尾稽核章節」的條款，不解除硬規則。每一次稽核 run 都被迫違反其中一條（讀檔違硬規則，或不給 claims 違 auditor 契約）。

**驗證**：親自開檔後，核心矛盾屬實：稽核模式步驟 1 由**主 agent**執行「抽 claim」（整份編號清單都是給主 agent 的指令，「抽…再委派」的主詞是主 agent），而 claim 只能來自 NN 檔內文；同一份檔案的硬規則第 279 行卻無條件禁止把已完成檔內容回讀進主 context，且 148-151 的豁免明文只及「本節」（＝「全部打勾後接稽核」節，其內容是規模門與當場稽核禁令，152-164 行），不及硬規則。auditor 端契約確實是「給定 claims」（由委派方提供），且 DISPUTED 病歷要求「原 claim 一句摘要」，claim 文字必須由委派方帶入——auditor 沒有 task 權限（ps-auditor.md:9 `task: false`），也無法自行轉包。更關鍵的是委派瘦身條款把「只傳檔案路徑」明文限定在**任務 A**（:233「驗檔類委派（快驗／稽核任務 A）只傳檔案路徑」），反證任務 B 的委派本來就要帶 claim 內容。我另外查過 /ps-audit 指令檔（:24-26 同樣要求抽 claim，也無豁免）、README、lessons/applied.md、audit-template、ps-doc-lint.ps1，全庫沒有任何一處明文豁免主 agent 為抽 claim 而讀 NN 檔——這正好踩到框架自宣的 L63「範圍靠暗示＝沒有範圍／必須明文豁免」。

對指控做兩點修正（但不改變裁決）：(1) 審查者引的 :45 其實是有範圍的——它縮排在「啟動與續跑」步驟 1 的「存在 →…繼續階段二」分支底下，只約束續跑路徑，不是「無條件」；真正卡住的是 :279 那條硬規則。(2) 有一項減輕情狀但不足以化解：test-scenarios.md:407 的「已完成項的檔案內容未回讀進主 context」檢查點只掛在 G2（逐項深查與續跑）類，H1 稽核類（:420-444）十一個檢查點裡沒有這條——顯示設計者心裡的紀律範圍是研究迴圈；但依框架自己的 L63，這種靠位置／類別暗示的範圍＝沒有範圍，不算明文豁免。…

**原文佐證**：
```
【要求主 agent 抽 claim】/home/user/MCPSample/.opencode/agent/ps-deep-research.md:175-177（「## 稽核模式（/ps-audit 觸發）」節）：
「1. 每檔委派 @ps-auditor（任務 A：證據解引用——ChunkId 重查、quote 子字串
   比對、SQL 重跑）——**委派只傳檔案路徑，不貼內容**；每檔抽 3~5 條
   標 CONFIRMED 的重要 claim 再委派（任務 B：反駁驗證）。」

【硬規則無條件禁止回讀】/home/user/MCPSample/.opencode/agent/ps-deep-research.md:279（「## 硬規則」節，247 行起）：
「- 已完成檔案的內容不回讀進主 context；需要引用時給檔名連結即可。」

【豁免只及「本節」】/home/user/MCPSample/.opencode/agent/ps-deep-research.md:147-151：
「**全部打勾後接稽核（每次 run 最多一輪；長 run 不當場稽核）**：
**本節只管「research run 收尾的自動接跑稽核」。收到明確稽核指令的
session（/ps-audit、或 headless 的 --command ps-audit）＝規模門指定的
那個「新 session 稽核」本身——本節全部條款（含規模門）對它不適用：
立刻執行稽核模式，不得反問、不得婉拒、不得建議再開 session（L63）。**」
（該節後續 152-164 行全是規模門與當場稽核禁令，可證「本節」不含 247 行起的硬規則。）

【auditor 契約：claims 由委派方給】/home/user/MCPSample/.opencode/agent/ps-auditor.md:111-115：
「### B. Claim 反駁驗證（抽樣）

給定 claims：逐條**自己重新取證**（不採用文件附的推理），
**以反駁為目標**——證據不足以支撐 → `DISPUTED`；明確支撐 →
`VERIFIED`；取不到證據 → `UNVERIFIABLE`。」

【claim 原文必須隨委派帶入】/home/user/MCPSample/.opencode/agent/ps-auditor.md:132-134：
「2. **附可裁決病歷**：每筆 DISPUTED 必附三要素——原 claim 一句摘要、
   你實際取到的證據（ChunkId:行號…
```

**建議最小修法**：在 /home/user/MCPSample/.opencode/agent/ps-deep-research.md:279 該條硬規則加明文豁免，例如改成：「已完成檔案的內容不回讀進主 context；需要引用時給檔名連結即可。**唯一例外：稽核模式步驟 1 為抽 3~5 條 CONFIRMED claim，可 read 該 NN 檔（只取 claim 句，委派任務 B 後即丟，不留在 context）**。」並同步在同檔 :177 與 /home/user/MCPSample/.opencode/command/ps-audit.md:25-26 的抽 claim 句尾註明「（此處 read 屬硬規則明文豁免）」，避免小模型改用「略過任務 B」解衝突。


### M25. SOP-17 與 L60 同時保留兩個互斥的「元兇」定案：doom_loop『實測確認就是這個』vs external_directory『最能解釋為什麼偏偏卡在第 14 檔／主嫌改判』；L60 落點 JSON 還留著會造成故障的 external_directory: deny

**涉及**：.opencode/peoplesoft/SOP.md, .opencode/peoplesoft/lessons/applied.md

**指控**：同一次「卡在第 14 檔」事故，SOP-17 第 0 條在 doom_loop 條目寫『實測確認就是這個』（含提示原文），又在 external_directory 條目寫『這也最能解釋為什麼偏偏卡在第 14 檔』；L60 更同時載有『最後由管理者實際看到提示文字才定案（doom_loop）』與『主嫌從 doom_loop 改判為 external_directory』兩個相反結論，未收斂。另外 L60 的落點行仍寫 `"external_directory": "deny"`，而同一課後段與 SOP-17 都明載 deny 會讓 subagent 讀不到 %TEMP% 暫存＝真實故障——照 L60 落點行照抄設定會複製地雷。附帶：SOP-9 的必要前提只點名『把 doom_loop 設 allow…才成立』，但依 SOP-17 自己的敘述 external_directory 留在 ask 一樣永遠死鎖，該充分條件宣稱不完整。

**驗證**：親自開檔逐行核對，指控的兩個核心事實屬實，且比指控描述的更糟一層。

(1) L60 內部確有兩個未收斂的相反定案，且錯的那個是最後一句。applied.md:1298 用「【實測確認】觸發的是 doom_loop」定案；1306-1311 更明白把改判 external_directory 標為「**過度修正**」，並直接寫 external_directory「只是不是這次的元兇」。但緊接的下一則 bullet 1316 又用粗體寫「主嫌從 doom_loop 改判為 external_directory」。兩句在同一課、相鄰 bullet、無任何「以下為當時判斷／歷史記錄」的範圍標記，而錯的那句位置更後 —— 順讀者最後看到的是被本課自己判定為過度修正的那個結論。這不是可解釋的分工，是漏刪的殘留。

(2) L60 落點行確實仍載地雷，且該行對「SOP-17 現在寫什麼」是錯的事實陳述。applied.md:1295 以「落點：…SOP-17 加第 0 條」的語氣寫 `"external_directory": "deny"`，但 SOP.md:352 的實際內容是 allow；同一課 1312-1314 又寫「初版寫 deny，管理者當場擋下——**那會造成故障**」，1318-1321 原則零整段就是在檢討這個 deny。所以 1295 同時是（a）過時的事實錯誤、（b）本課自己認定會造成真實故障的設定值、（c）唯一可整段複製的 JSON。AGENTS.md:46-47 明訂 applied.md 是「本框架唯一完整的歷史」且是接手維護 session 的第一順位必讀 —— 這個地雷正好埋在被指定第一個讀的檔裡。

(3) SOP-17 側的雙重歸因也屬實但較輕：SOP.md:354 說 doom_loop「實測確認就是這個」，SOP.md:363 又說 external_directory「這也**最能**解釋『為什麼偏偏卡在第 14 檔』」。兩者其實共用同一個上游條件（該檔證據量大），機制上不互斥，但「最能解釋」是最高級宣稱，與 applied.md:13…

**原文佐證**：
```
【L60 內部相反定案 — 我自己讀到的原文】
/home/user/MCPSample/.opencode/peoplesoft/lessons/applied.md:1298
「· **【實測確認】觸發的是 `doom_loop`**：提示文字「continue after repeated」
applied.md:1306-1308
「· 判斷過程的曲折要記下來：維護 session 先猜 doom_loop（對），被 / 管理者的「subagent 會用暫存檔」觀察一講就改口 external_directory / （**過度修正**），最後由管理者實際看到提示文字才定案。」
applied.md:1310-1311
「管理者那個觀察沒有白費：external_directory / 設 deny 確實會擋掉暫存檔讀取，那個故障是真的，只是不是這次的元兇。」
applied.md:1316（本課最後一句相關結論，粗體，無任何範圍標記）
「所以前 13 檔沒事。**主嫌從 doom_loop 改判為 external_directory。**」

【落點行仍載地雷，且與 SOP-17 實況不符】
applied.md:1294-1295
「- 落點：檔頭註解全部改寫成查證過的事實；SOP-17 加第 0 條「必要前提」—— … / 設 `"permission": { "doom_loop": "allow", "external_directory": "deny" }`。」
applied.md:1312-1314
「· external_directory 設 **allow**（初版寫 deny，管理者當場擋下——**那會 / 造成故障**）：opencode 自己會把過長的工具回傳寫進 `%TEMP%` 再讓模型 / 讀回來，那個路徑在專案目錄外；設 deny＝subagent 讀不到自己剛存的資料。」
/home/user/MCPSample/.opencode/peoplesoft/SOP.md:352（SOP-17 實際內容，與 1295 相反）
「     "permission": { "doom_loop": "allow", "external_directory": "allow" }」

【SOP-17 雙重歸因】
SOP.md:354-355
「     · `doom_loop: allow` ← **實測確認就是這個**（2026-08）：提示文字是 / 「continue after repeated failures…
```

**建議最小修法**：三處最小改動，全部只動 prose，不動任何可執行設定：
1. applied.md:1295（落點行）把 `"external_directory": "deny"` 改成 `"allow"`，並在該行尾加「（初版誤寫 deny，見下方修正；現行值以 SOP-17 第 0 條為準）」——消除唯一可整段複製的地雷 JSON。
2. applied.md:1316 刪掉整句「**主嫌從 doom_loop 改判為 external_directory。**」，改寫為「**本項是另一個真實故障，不是本次元兇**——元兇定案見上一則【實測確認】與 L61 的三層診斷鏈。」讓 L60 只剩一個定案。
3. SOP.md:363 把「這也最能解釋「為什麼偏偏卡在第 14 檔」」改為「deny 會另外造成暫存檔讀不到的真實故障（與本次元兇無關）」，並刪去 364 行的第 14 檔歸因——「為什麼偏偏是那一檔」的唯一說法交還 L61:1360（抽樣事故）。


### M26. SOP-3 引用「SOP-1 第 9 步」，但現行 SOP-1 沒有編號到 9 的步驟——懸空引用

**涉及**：.opencode/peoplesoft/SOP.md

**指控**：SOP-3 的 commit 時機清單寫「教訓套用後（SOP-1 第 9 步）」；現行 SOP-1 只有 5 個編號審查項加上『merge 後』1 項與『退回時』3 項的未編號核取格，沒有任何「第 9 步」，且「教訓套用」在 SOP-1 裡是流程敘述（agent 直接修落點檔）而非任何一個核取步驟——引用指向早已改寫掉的舊版編號。

**驗證**：我親自讀完整份 SOP.md 並交叉查證，指控屬實但屬純文件衛生問題。(1) SOP.md:102 確實寫「教訓套用後（SOP-1 第 9 步）」。(2) SOP-1 全文只到 SOP.md:9-31，標題行 L16 自己寫明「審 PR 時看五件事」，編號項只有 □1~□5；其後【merge 後】1 個、【退回時】3 個都是無編號核取格，全篇沒有任何「9」。(3) 「教訓套用」在 SOP-1 裡出現在 L11 的流程敘述（agent 直接修落點檔＋記錄 applied.md），不是任何一個核取步驟——指控這點也讀對了。(4) 我另外查證了本 repo 的交叉引用慣例：SOP.md:77 的「SOP-10 第 5 步」對到 SOP.md:270 的「□ 5.」，applied.md:1119 的「SOP-15 第 3 步」對到 SOP.md:526 的「□ 3.」，可見「第 N 步」＝編號核取項 N，因此「第 9 步」無指涉對象。(5) grep 全 repo，SOP-1 只在 SOP.md 定義一處，不存在另一份有 9 步的版本可以化解。唯一對指控稍有利的反面事實：SOP-1 若把無編號格一起數，總計恰為 9 個 □；但第 9 個是「□ 若教訓本身有價值只是落點/措辭不對 → 修改後重新提交」（退回路徑），與「教訓套用後 commit」無關，寬鬆解讀也接不上。屬懸空引用無誤。至於嚴重度：這條不觸犯任何鐵律（不擋畢業門、無 L53 活鎖、不影響證據契約），該行語意本身自足（「教訓套用後」就是可執行的 commit 時機），錯的只有括號指標，minor 判得剛好。

**原文佐證**：
```
SOP.md:102（引用端，位於 SOP-3「□ 何時 commit」清單）：「  - 教訓套用後（SOP-1 第 9 步）」

SOP.md:16（SOP-1 標題行自證只有五項）：「【審 PR 時看五件事（看 diff 即可，單筆 2~5 分鐘）】」

SOP.md:17-22（SOP-1 僅有的編號項，止於 5）：
「□ 1. 落點優先序對嗎？機械化檢查 > 資料修正 > 窄規則 > AGENTS.md」
「□ 2. 是「最小新增」嗎？——只加不刪；有任何既有規則被改寫/移除 → 退回」
「□ 3. 措辭會不會太寬、誤傷正常行為？」
「□ 4. 測試檢查點有跟著加進 test-scenarios.md 嗎？」
「□ 5. 沒把握 → 把 diff 遮敏後貼給較強模型審（物件名可代稱；機密不出機器）」

SOP.md:24-30（其後全為無編號核取格，無 6~9 編號）：
「【merge 後】」「□ 通知全員 pull ＋ 重啟 OpenCode（教訓才會到每台機器）」
「【退回時】」「□ PR reject ＋ 註明理由」「□ 通知該同事在本機 revert 該 commit（他的機器退回原狀）」「□ 若教訓本身有價值只是落點/措辭不對 → 修改後重新提交」

SOP.md:11（「教訓套用」確為流程敘述而非核取步驟）：「**流程**：同事 `/ps-lesson` → **該機立即生效**（agent 直接修落點檔＋記錄 applied.md）→ 同事 commit ＋ push → 內部 git 開 **PR** → 你審 diff →」

交叉引用慣例佐證（「第 N 步」＝編號核取項 N，兩處皆可解）：
SOP.md:77「     (3) 環境事實：tool-call 約束解碼（SOP-10 第 5 步）經公司政策」→ SOP.md:270「□ 5. 約束解碼（治 tool-call JSON 壞格）：」
lessons/applied.md:1119「     canonical 字串同步寫進 overview-template 與 SOP-15 第 3 步。」→ SOP.md:526「□ 3. 人工審草稿 → 滿意就人工把內容覆蓋進 00-overview.md：」
```

**建議最小修法**：把 /home/user/MCPSample/.opencode/peoplesoft/SOP.md:102 的「  - 教訓套用後（SOP-1 第 9 步）」改成不帶步號的指涉，例如「  - 教訓套用後（SOP-1 流程：agent 修落點檔＋記錄 applied.md 之後）」；若想保留可驗證的交叉引用，則改為指向真實存在的編號項或在 SOP-1 的【merge 後】/【退回時】核取格補上接續編號（□6~□9）後再引用「第 9 步」。


### M27. auditor 會產出 FAIL(FALSE_NEGATIVE)，但 audit-template 的 FAIL 詞彙表與 deep-research 的 A 項修復分支都沒有這個類型

**涉及**：.opencode/agent/ps-auditor.md, .opencode/peoplesoft/report-templates/audit-template.md, .opencode/agent/ps-deep-research.md

**指控**：ps-auditor.md:100-107（任務 A 步驟 4「查無宣告抽驗」）定義「查得到 → FAIL(FALSE_NEGATIVE)（附找到的 chunk id；負面結論失效，該項需回灌補查）」，但 audit-template.md:26-28 的「FAIL 類型詞彙表（原因欄使用）」枚舉八種（TRUNCATED_ID／FABRICATED／WRONG_KIND／STALE_DATA／ID_RELINK／NOT_FOUND／MISSING_CHUNK_ID／INCOMPLETE_CHUNK）不含 FALSE_NEGATIVE；ps-deep-research.md:100-126 的 A 項處理清單逐一列了 TRUNCATED_ID／STALE_DATA／ID_RELINK／LINE_DRIFT／MISSING_CHUNK_ID／INCOMPLETE_CHUNK／WRONG_KIND 的修法，唯獨沒有 FALSE_NEGATIVE 分支——而它的正確修法（把被平反的物件／邏輯補進調查）與清單第一條通用修法「重新取證修正該檔的引用」完全不同型。契約定義的判定在報告模板與修復路徑兩端同時缺席。

**驗證**：我逐檔開過三個引用點，指控的三處原文都與所述一致，不是盲掃誤讀：(1) ps-auditor.md:100-107 確實定義了 `FAIL(FALSE_NEGATIVE)` 這個判定類型（查無宣告抽驗查得到時）；(2) audit-template.md:26-28 的「FAIL 類型詞彙表（原因欄使用）」確實只枚舉八種、無 FALSE_NEGATIVE，且該表在框架裡是被當成正式落點維護的（applied.md:334-335 L18「落點：subagent-report-contract／audit-template FAIL 詞彙表／F7 測試情境」；applied.md:421 前例加新 FAIL 型時同步改「A 項處理」清單），所以它不是示例而是規範表；(3) ps-deep-research.md:100-126 的 A 項分支確實逐條列了 TRUNCATED_ID／STALE_DATA／ID_RELINK／LINE_DRIFT／MISSING_CHUNK_ID／INCOMPLETE_CHUNK／WRONG_KIND，唯獨沒有 FALSE_NEGATIVE，而首條通用修法「重新取證修正該檔的引用」型別不合（FALSE_NEGATIVE 沒有「該筆引用」可修，要修的是被推翻的查無敘述＋補進新發現的物件）。溯源也支持：FALSE_NEGATIVE 是 L24 追記（applied.md:250-251）新增的判定，該筆 lesson 的落點只寫了 auditor，漏了這兩個同步點——典型的加型未同步。\n\n但幾項不利於「嚴重」的事實我也查了：ps-doc-lint.ps1 全域搜不到任何 FAIL 型詞彙的機械檢查（scripts/ 只有一處 MISSING_CHUNK_ID 註解），所以詞彙表缺項不會產生 lint 違規；ps-audit.md:31-32「任何非 PASS／VERIFIED 判定（FAIL／DISPUTED／自創詞一律算）…加進 checklist」與 audit-template.md:55-57「auditor 自創詞就近映射（證據→F…

**原文佐證**：
```
1) /home/user/MCPSample/.opencode/agent/ps-auditor.md:106-107 —「**查得到 → `FAIL(FALSE_NEGATIVE)`**（附找到的 chunk id；／負面結論失效，該項需回灌補查）；仍查無 → PASS。」（同檔 100-101 行為「4. **查無宣告抽驗**：掃描該檔內文與 gaps 中的「查無／不存在／無～邏輯」類負面宣告」）\n\n2) /home/user/MCPSample/.opencode/peoplesoft/report-templates/audit-template.md:26-29 —「FAIL 類型詞彙表（原因欄使用）：TRUNCATED_ID／FABRICATED／／WRONG_KIND／STALE_DATA／ID_RELINK／NOT_FOUND／MISSING_CHUNK_ID／／INCOMPLETE_CHUNK；行號漂移但 quote 命中＝PASS(LINE_DRIFT) 附／新行號，不是 FAIL。」——八項，無 FALSE_NEGATIVE。\n\n3) /home/user/MCPSample/.opencode/agent/ps-deep-research.md:100-126 —「**稽核回灌項（A<n>）的處理**（取代標準深度鏈，做定向補查）：／- FAIL 證據：重新取證（chunk 重取／SQL 重跑）修正該檔的引用。」其後分支依序為 101 FAIL 證據通用、102 FAIL(TRUNCATED_ID)、113 FAIL(STALE_DATA)、115 FAIL(ID_RELINK)、117 LINE_DRIFT、119 FAIL(MISSING_CHUNK_ID／NO_CHUNK_ID)、123 FAIL(INCOMPLETE_CHUNK)、125 FAIL(WRONG_KIND)，全清單無 FALSE_NEGATIVE。同檔唯一提及在 284 行且只是寫入端註記：「查無宣告未來可被稽核重測（FALSE_NEGATIVE），收據就是重測依據。」——不是修復分支。\n\n4) 該表屬規範落點的證據：/home/user/MCPSample/.opencode/peoplesoft/lessons/applied.md:334-335 —「落點：subagent-report-contract／／audit-template FAIL 詞彙表／F7 測試情境（總數 39）。」；漏同步來源：applied.md:250-251 —「(…
```

**建議最小修法**：兩處各補一行：(1) audit-template.md:26-28 的 FAIL 類型詞彙表加入 `FALSE_NEGATIVE`（並註明「查無宣告被推翻，原因欄須附找到的完整 36 字元 ChunkId」）；(2) ps-deep-research.md 的 A 項處理清單（第 126 行 WRONG_KIND 之後）插入分支：「- FAIL(FALSE_NEGATIVE)：原查無宣告被推翻——**不是修引用**：以稽核附的 chunk id 解引用取回內容，刪除／改寫該筆查無敘述與對應 gaps，把該物件／邏輯照標準深度鏈補進本檔（含新證據列與查法收據）。」


### M28. mcp-tool-contracts 宣稱 outline 角色「尚未實作」，同檔工具表與 progressive-source-retrieval §6.0 都說 get_file_structure 已承擔它——過期宣稱互撞

**涉及**：.opencode/peoplesoft/mcp-tool-contracts.md, .opencode/peoplesoft/progressive-source-retrieval.md

**指控**：mcp-tool-contracts.md:251-253 說「現況：ps_search_source 由 PeoplecodeElasticSearch 承擔、ps_get_source_chunks 由 PeoplecodeSource 承擔；其餘三個尚未實作」——「其餘三個」包含 ps_get_source_outline。但同檔開頭的 server 工具表（13-14 行）就列著 PeoplecodeSource_get_file_structure「檔案結構（先看目錄再定向取段）」，而 progressive-source-retrieval.md §6.0（254 行）明確把 get_file_structure(fileId) 對映為 ps_get_source_outline 並稱它是「file-mode 的核心工具」、257 行說只有 expand 與 references 兩個尚未實作。兩份契約文件對「outline 是否可用」說法相反；依 L61（unavailable tool 不可重試、要改做法）的紀律，讀到「尚未實作」的 agent 會迴避一個實際存在且被指定為核心的工具。

**驗證**：親自開檔逐行核對，指控引用的每一行都存在且語意如其所述。

1) mcp-tool-contracts.md §3 的五工具清單（243-249 行）明列 ps_search_source / ps_get_source_chunks / ps_expand_source_context / ps_get_source_outline / ps_find_source_references，共五個；緊接的 251-253 行說只有前兩個有人承擔、「其餘三個尚未實作」——算術上「其餘三個」必然包含 ps_get_source_outline，這不是解讀，是清單相減的唯一結果。

2) 同一檔第 14 行的 server 工具表（表頭第 7 行自稱「2026-08 管理者實測確認」）就列著 PeoplecodeSource / get_file_structure。同檔一邊說實測確認存在、一邊說「尚未實作」，屬檔內自撞。

3) progressive-source-retrieval.md §6.0 第 254 行把 get_file_structure(fileId) 明確對映成 ps_get_source_outline 並稱「file-mode 的核心工具」；257 行的未實作名單只有兩個（expand、find_references），且過渡做法只針對那兩個寫。也就是說：讀到「outline 尚未實作」的 agent 若照 253 行指引去 §6.0 找過渡做法，會發現 §6.0 根本沒給 outline 過渡做法（因為 §6.0 認為它已實作）——兩份契約對「outline 是否可用」的結論相反。

4) 影響非虛構：全 repo grep 顯示 ps-peoplecode-flow.md:37/50/58/71、ps-sql-flow.md:37/47/63、ps-sqr-flow.md:35/48/63、ps-ae-flow.md:55/71、ps-auditor.md:45/76、ps-deep-research.md:103/128、applied.md…

**原文佐證**：
```
【自讀原文】

/home/user/MCPSample/.opencode/peoplesoft/mcp-tool-contracts.md:243-249（五工具清單）
```
243 ```text
244 ps_search_source
245 ps_get_source_chunks
246 ps_expand_source_context
247 ps_get_source_outline
248 ps_find_source_references
249 ```
```

/home/user/MCPSample/.opencode/peoplesoft/mcp-tool-contracts.md:251-253
「> **現況**：`ps_search_source` 由 `PeoplecodeElasticSearch` 承擔、
> `ps_get_source_chunks` 由 `PeoplecodeSource` 承擔；其餘三個尚未實作
> （過渡做法見 progressive-source-retrieval.md §6.0）。」
→ 5 − 2 = 3，「其餘三個」必含 247 行的 ps_get_source_outline。

/home/user/MCPSample/.opencode/peoplesoft/mcp-tool-contracts.md:7（表頭）
「> **各 server 的完整工具清單（2026-08 管理者實測確認）**：」
/home/user/MCPSample/.opencode/peoplesoft/mcp-tool-contracts.md:14
「> | `PeoplecodeSource` | `get_file_structure` | 檔案結構（先看目錄再定向取段） |」

/home/user/MCPSample/.opencode/peoplesoft/progressive-source-retrieval.md:254
「| `PeoplecodeSource`（tool `get_file_structure(fileId)`） | `ps_get_source_outline` — 以 fileId 取該檔完整結構（回傳 `File.FilePath` 與段落清單）；file-mode 的核心工具 |」

/home/user/MCPSample/.opencode/peoplesoft/progressive-source-retrieval.md:257-259
「`ps…
```

**建議最小修法**：把 /home/user/MCPSample/.opencode/peoplesoft/mcp-tool-contracts.md:251-253 的「現況」段改寫為與 §6.0 一致的三行對映，並把數字換成明列名稱以免再度失同步：「**現況**：`ps_search_source` 由 `PeoplecodeElasticSearch_search_chunks` 承擔、`ps_get_source_chunks` 由 `PeoplecodeSource_get_chunks_details` 承擔、`ps_get_source_outline` 由 `PeoplecodeSource_get_file_structure` 承擔（file-mode 核心工具）；僅 `ps_expand_source_context`、`ps_find_source_references` 尚未實作（過渡做法見 progressive-source-retrieval.md §6.0）。實作狀態一律以 §6.0 表格為準。」


### M29. peoplesoft/README 的 deep-research 收尾稽核描述停在 L29 之前：只寫「本 run 處理量 > 5 項」門檻，漏掉優先生效的「已完成檔總數 > 5」規模門

**涉及**：.opencode/peoplesoft/README.md, .opencode/agent/ps-deep-research.md

**指控**：架構總覽說全部打勾後自動接一輪稽核、只有「本 run 處理量 > 5 項的長 run」才改開新 session。現行 ps-deep-research 的規模門（L29）優先於該條款且以「已完成 NN 檔總數 > 5」為準——例如 15 檔領域續跑只補 1 項時，README 說會當場接稽核，實際 agent 被規定禁止當場稽核、必須提示開新 session（實測 in-run 稽核在 15 檔領域塌縮）。單次 run 至多 6 項的上限也未反映。

**驗證**：親自開檔逐行核對，指控引用的三處原文全部屬實，且不是「摘要省略」而是**停留在已被推翻的舊規則**。

1. README:158-161 的收尾稽核描述，其唯一守門變數是「本 run 處理量 > 5 項」——這正是 L29 事故報告點名「用錯的那個變數」。applied.md:545-546 寫得很白：「接稽核規則『本 run 打勾數 ≤ 5』守的是**回灌處理量**，但稽核＝全量重驗（範圍是全部已完成檔）——工作量隨**檔案總數**成長」，而 applied.md:551 的落點是「已完成 NN 檔總數 > 5 一律禁止當場稽核」。ps-deep-research.md:152-156 已照此改寫並明文標「優先於本節其餘條款」。README 沒改。

2. 因此指控舉的 15 檔／本 run 只補 1 項情境，兩檔給出**相反指令**：照 README 讀是「≤5 → 當場接一輪完整稽核」，照 agent 讀是「已完成檔總數 > 5 → 本 run 不接稽核，提示開新 session」。這不是措辭寬鬆，是把 L29 存在的理由（15 檔 in-run 稽核記分卡塌縮 15 列）那一格反向填寫。

3. git 佐證漂移屬實：README 該段最後一次異動是 2026-07-28 `c6bc6ba "Defer end-of-run audits past a 5-item threshold"`（＝舊的本 run 門），而 ps-deep-research.md 的規模門／L63 豁免是 2026-08-19 `f6ebef6`。README 從未跟上。

4. 「6 項上限未反映」也成立：README 全檔 grep「6 項／至多／上限」在該節零命中，且 164-165 行的「一次跑到底可能中斷…斷了就重跑指令續跑」把停跑歸因於 serving 端 context 上限與當機，讀不出「達 6 項是規則性停止」。

我也查了三個可能化解矛盾的出口，都不存在：README 全檔沒有任何「以 agent 檔為準／此處為簡述」的豁免或指向（grep「為準／詳見／規範」在…

**原文佐證**：
```
【README 停在舊規則——本人讀到的原文】
/home/user/MCPSample/.opencode/peoplesoft/README.md:158-161
「- **逐項自動快驗**：每檔寫完、打勾前先委派 ps-auditor 驗證據；
  全部打勾後自動接一輪完整稽核＋回灌（單次 run 最多一輪；本 run
  處理量 > 5 項的長 run 改為提示開新 session 稽核——長對話尾端
  品質差；稽核新回灌項由下一次 run 處理，輪次記錄於 checklist.md）。」

/home/user/MCPSample/.opencode/peoplesoft/README.md:164-165
「- **全跑注意**：一次跑到底可能中斷（serving 端 context 上限、當機）
  ——沒關係，斷了就重跑指令續跑；每項完成即寫檔＋打勾，進度不會遺失。」
（全檔無「6 項」「至多」字樣，單次 run 上限零反映）

【agent 檔的現行規則——優先且以檔案總數為準】
/home/user/MCPSample/.opencode/agent/ps-deep-research.md:152-156
「- **前置規模門（L29，優先於本節其餘條款）**：稽核＝全量重驗，工作量
  跟「已完成 NN 檔總數」走、不跟本 run 打勾數走——已完成檔總數 > 5
  時**本 run 不接稽核**，結束總結告知：
  「本領域規模超過當場稽核上限，請開新 session 執行 /ps-audit <領域>」。
  實測：15 檔領域的 in-run 稽核記分卡缺 15 列（塌縮），≤5 勾門檻擋不住。」

/home/user/MCPSample/.opencode/agent/ps-deep-research.md:70-71
「對每個未勾選項，**一次只處理一項**；**單次 run 至多處理 6 項**
（含 A 項）——達 6 即停止，結束總結提示使用者開新 session 重跑」

【L29 事故本體：README 現行寫法正是被判定失效的那個門】
/home/user/MCPSample/.opencode/peoplesoft/lessons/applied.md:545-549
「- 根因：接稽核規則「本 run 打勾數 ≤ 5」守的是**回灌處理量**，但稽核
  ＝全量重驗（範圍是全部已完成檔）——工作量隨**檔案總數**成長。
  15 檔的全量塞進 research session 尾端 context 必塌……
```

**建議最小修法**：改 `.opencode/peoplesoft/README.md:158-161` 的括號內容，把守門變數換成 L29 的檔案總數並標明優先序：「全部打勾後接一輪完整稽核＋回灌（單次 run 最多一輪；**前置規模門 L29：已完成 NN 檔總數 > 5 時本 run 一律不接稽核**，改提示開新 session 執行 `/ps-audit <領域>`——該 session 不受本條款限制；檔總數 ≤ 5 且本 run 打勾數 ≤ 5 才當場接一輪；新回灌項由下一次 run 處理，輪次記錄於 checklist.md）。」同時在 150-151 行「可中斷續跑」項補一句「**單次 run 至多處理 6 項**，達 6 即停止並提示開新 session 續作」，並把 164-165「一次跑到底」改為「跑到 6 項上限或中斷都會停」，以免與硬上限相衝。


### M30. peoplesoft/README 目錄樹過期：漏 research-domains.txt 與 explore/general/scout 三個補鎖覆寫檔（L15 圍堵機制）

**涉及**：.opencode/peoplesoft/README.md, .opencode/agent/explore.md

**指控**：架構總覽的目錄結構樹停在較早版本：peoplesoft/ 節點沒有 research-domains.txt（auto-all 批次佇列，實際存在且根 README 有列），agent/ 節點只列 9 個 ps-* 檔、沒有 explore.md / general.md / scout.md 三個同名覆寫檔——那是 L15「內建 subagent 側門」的補鎖手段，根 README 明言其「唯一目的是補鎖」；在 L1（沒列＝預設開）的體系下，圍堵拼圖從架構總覽的地圖上消失不是無害省略。

**驗證**：我逐檔開過，指控的每一項事實都成立，且沒有任何明文範圍或豁免可以化解。

(1) 漏檔屬實。`.opencode/peoplesoft/README.md` 的「## 目錄結構」樹（:13-64）根節點就是 `.opencode/`，沒有任何「僅列核心檔」之類的範圍限縮語。peoplesoft/ 節（:18-36）以 `└─ test-fixtures.yaml` 收尾，全節無 research-domains.txt；但 `ls` 實測該檔存在（1135 bytes），我也讀過其內容（批次佇列，`.\scripts\ps-auto-all.ps1` 的輸入）。agent/ 節（:37-46）以 `└─ ps-auditor.md` 收尾，恰好 9 個 ps-* 檔；`ls` 實測 `.opencode/agent/` 有 12 個 .md，另有 explore.md／general.md／scout.md。

(2) 漏掉的正是圍堵拼圖。我開過那三個覆寫檔，內容確實只有補鎖：frontmatter 顯式 deny 四個 MCP 前綴 ＋ bash/write/edit/webfetch，正文明說「本檔僅為工具封鎖覆寫」。教訓帳本 applied.md:379 的 L15 標題就是「OpenCode 內建 subagent 側門——同名覆寫補鎖」，落點 (1) 明寫「.opencode/agent/ 放 general／explore／scout **同名覆寫檔**封 4 個 MCP」，並定調「平台的預設能力都在封鎖體系的守備範圍——同名覆寫是唯一可預先部署的鎖」。

(3) 比審查者說的更嚴一點：根 README.md:48 明文把這份檔案定位成「架構總覽（三個核心概念、**完整檔案說明**）」——是它自己宣告「完整」，因此「省略」不能用簡述辯護。同一份根 README:56 有列 research-domains.txt、:109 有列三個覆寫檔並註明「唯一目的是補鎖」，:113-116 更把 L1/L46 覆寫表鐵律寫成「兩條非讀不可的設計規則」。也就是說框架自己…

**原文佐證**：
```
【漏 research-domains.txt】
/home/user/MCPSample/.opencode/peoplesoft/README.md:13-15（樹的宣告範圍＝整個 .opencode/，無限縮語）
  ## 目錄結構
  ```text
  .opencode/
/home/user/MCPSample/.opencode/peoplesoft/README.md:35-37（peoplesoft/ 節結尾，無 research-domains.txt）
  │  ├─ test-scenarios.md                本地模型準確度測試情境（30 題 + 評分規則）
  │  └─ test-fixtures.yaml               測試用假想環境資料（mock MCP 標準答案）
  ├─ agent/
實測存在：`ls -la /home/user/MCPSample/.opencode/peoplesoft/` → `-rw-r--r-- 1 root root 1135 Aug 13 16:36 research-domains.txt`
其內容（/home/user/MCPSample/.opencode/peoplesoft/research-domains.txt:1,14）：
  # research-domains.txt — 批次研究的領域佇列（issue #3）
  # 用法：.\scripts\ps-auto-all.ps1

【漏三個覆寫檔】
/home/user/MCPSample/.opencode/peoplesoft/README.md:38,45-46（agent/ 節首尾，恰 9 個 ps-*，以 ps-auditor 收尾）
  │  ├─ ps-orchestrator.md               Primary：問答模式（domain 解析 + 委派 + 彙整，唯讀）
  │  ├─ ps-metadata-flow.md              Subagent：血緣 / 排程 / 授權（三合一）
  │  └─ ps-auditor.md                    Subagent：稽核（證據解引用 / claim 反駁 / 換角度盤點）
實測 12 檔：`ls -la /home/user/MCPSample/.opencode/agent/` → explore.md(786)、general.md(748)、scout.md(657)…
```

**建議最小修法**：改 /home/user/MCPSample/.opencode/peoplesoft/README.md 的目錄樹（:15-64）兩處：peoplesoft/ 節把 `└─ test-fixtures.yaml`（:36）改回 `├─`，其後補 `│  └─ research-domains.txt              auto-all 批次佇列（一行一領域，人工維護）`；agent/ 節把 `└─ ps-auditor.md`（:46）改回 `├─`，其後補三行 `│  ├─ explore.md ／ │  ├─ general.md ／ │  └─ scout.md    內建同名覆寫：唯一目的是補鎖（L15，封 4 個 MCP + bash/write）`。順手把 SOP.md:184 的「全部 9 個 agent 檔」改成「全部 12 個 agent 檔（含 explore／general／scout 覆寫檔）」，否則新增 MCP 時側門會重開。


---

## 被駁回的指控　11 筆

這些看起來像矛盾、實際不是。**記錄下來同樣重要——避免下一任維護者又去「修」它。**

### X1. 互動提問工具（question 類）不在任何一個 tools map——依框架自身「沒列＝預設開」教義，12 個 agent 在 headless 下全數保留一條「問人」死鎖通道

**為什麼不成立**：指控建立在一個未經證實的前提上：「OpenCode 存在一個 question 類的互動提問『工具』」。我打開了它引用的全部 4 個 agent 檔（以及其餘 8 個，共 12 檔）、SOP-17 全段、L60/L61/L63 全段、MCP 契約總表與外環腳本，找不到任何支撐該前提的東西，而三條可查證的線索全部指向相反方向：

(1) **互動阻塞面在 permission 層，不在 tools 層，且框架已實測列舉完畢。** SOP.md:345 的「opencode 有兩個權限預設是 ask」是管理者 2026-08 親眼看到提示文字後定案的（applied.md:1306-1311 記錄了這個從推理改為實證的過程）。指控說 SOP-17 第 0 條「只處置兩個權限、對提問類零覆蓋」——但那一段本來就是在說 opencode 的 ask 預設就只有這兩個。tools map deny 不到 permission ask，permission 也不是工具。

(2) **L63 的「反問」是模型的散文輸出，不是工具呼叫，因此在定義上無法用 tools deny 機械化。** applied.md:1424-1425 引的症狀原文是模型講的一句話（「……需要我幫你做別的嗎？」），沒有任何工具被呼叫。指控說「tools deny 是框架自己認定效果最好的機械化修法卻從未套用到這一類」——這是類別錯誤：這一類沒有東西可以 deny。框架對它採取的是當時唯一可用的機制（明文範圍豁免，applied.md:1440-1443 落點 1-3，已落在 ps-deep-research.md:148-151 與 ps-audit.md:8-10），加上外環的確定性熔絲。

(3) **就算真有這種工具，外環也不是活鎖而是強殺。** ps-auto-loop.ps1:249-292 的逾時…

### X2. 「待人工SQL」列若照 lint 自己的指示附上失敗原因（ORA-/查無此表），會被 381-384 行判成違規——合法出口與失敗查詢檢查互撞，且該違規無工單

**為什麼不成立**：指控的機械描述有一半屬實（381-384 的條件確實沒列 $pendingMark 豁免），但它的因果鏈——「lint 自己的指示在引導模型把失敗原因跟 待人工SQL 寫在同一列」——是誤讀，而且是關鍵誤讀：全 repo 沒有任何一處教這種寫法，教的全是相反的。

(1) 收據格式是「取代」不是「並列」。工單 B 路線寫的是「舊值 → 待人工SQL」，這跟同段收據格式表裡的「舊值 → 新完整UUID」「舊值 → SQL：SELECT…」是同一個箭頭語意：把機器參照欄的舊內容（那句 ORA-／查無此表）換成 待人工SQL。指控把「舊值 → 待人工SQL」讀成「保留舊值再加上待人工SQL」，整條攻擊建立在這個誤讀上。auto-loop 的手術 prompt（ps-auto-loop.ps1:533）用的是同一句話，語意一致。

(2) 收據落在 log，不落在 Evidence 表。收據是模型回覆文字，auto-loop 只把 lint 原文與 session 輸出 Add-Content 進 logs/lint-cycle*.txt；沒有任何路徑把「舊值 → 新值」這種箭頭字串寫回 NN 檔的 Evidence 附錄。所以連收據本身都不會變成被 381 掃到的 `|` 列。

(3) 正典格式明文規定該欄只能是三個 token 之一、且明文禁止敘述。模板第 63 行的示範列就是裸的 `待人工SQL`；模板 65-71 與 ps-deep-research.md:133-142 都寫「機器參照欄只准放三種東西之一」並把「用敘述搪塞機器參照欄」列為嚴禁三件事之一。指控構造的那列「待人工SQL（委派後 ORA-00942 查無此表）」正是被明文禁止的敘述搪塞——它被判違規不是出口與檢查互撞，是它根本不是合法出口的形狀。

(4) 失敗原因有明文的、且不在掃描範圍內的去處。模板與 a…

### X3. entity-template 把「SQL 摘要」與裸「SQL」標籤合法化為 wiki 證據——正是 L55 明令的「標籤不是證據」，auditor 對它無可重跑路徑

**為什麼不成立**：指控的三個支點逐一與原文對不上。

(1) 最關鍵的一點：entity-template.md:18 那個「教壞人」的範例，**自己帶著完整 36 字元 UUID**，不是裸標籤。L55 的判定單位是它自己明文寫的「以**列**為單位，不以欄為單位」（applied.md:1150），正面表列第 (a) 款就是「完整 36 字元 UUID」（applied.md:1144）。這一列有 UUID＝稽核重跑得了＝合格。lint 的實作也是同一邏輯：`$okUuid = ($line -match $fullUuid)`（ps-doc-lint.ps1:399），命中就走 406 行那支「整列有可重跑的東西＝證據沒丟…**降為警告**，不擋門也不進手術單」。所以就算把這一列原封搬進 Evidence 附錄，lint 也不會判違規。旁邊那個「/ SQL」是型別註記，不是證據本體——L55 罵的是「整列只有『OracleMCP SQL』一行字」（applied.md:1129-1131），與此不同型。而且模板 :20 還明文加碼「chunk id 一律完整 36 字元 UUID（如上例），禁止縮寫成前 8 碼」，方向與證據契約一致，不是相反。

(2)「SQL 摘要」不是證據本體，是**參照鍵**。entity-template.md:8 那個欄位自己標了「（時效偵測鍵）」——它是拿來偵測來源有沒有變的鍵，不是拿來重跑的證據；而且「SQL 摘要」正是框架自己的既有術語：ps-auditor 的輸出契約 `{ "ref": "<ChunkId 或 SQL 摘要>" }`（ps-auditor.md:161）用的就是同一個詞當每筆證據的識別欄。用同一個詞在兩處指同一種東西＝定義一致，不是矛盾。

(3) L55／lint 的範圍本來就是 Evidence 附錄的機器參照欄，不是 wiki…

### X4. ps-auto-all：連續失敗熔斷屬「停批」且自判「疑似環境級問題」，卻以 exit 0（批次完成）收場，與檔頭 exit 契約矛盾

**為什麼不成立**：指控把腳本內部的迴圈控制旗標 `$stopBatch` 當成檔頭 exit 契約裡的「停批」，但檔案原文顯示這是兩個不同的詞。四項原文證據：

(1) **檔頭是封閉列舉，不是開放類別。** 第 24-25 行對 exit 2 給的是明文三項清單「system error／鎖被占用／preflight 失敗」，而第 224 行檢查的正是 `SYSTEM_ERROR` 與 `MUTEX_BUSY`（preflight／依賴缺失在 92/98/102/120 行提早 exit 2）——逐項對得上，沒有落差。同一行對 exit 0 還明寫「可含 NEEDS_ATTENTION」。

(2) **熔斷路徑本來就是 NEEDS_ATTENTION 路徑。** 熔斷只長在 `$code -eq 1` 分支裡（196-204 行），進去前先 `$counts.NEEDS_ATTENTION++`（199 行）。也就是說熔斷結束的批次，依定義就是檔頭明文允許 exit 0 的「含 NEEDS_ATTENTION」批次。要它 exit 2 反而會牴觸檔頭。

(3) **`$stopBatch` 與「停批」不同義，這點在檔內可證。** MaxBatchHours（145-146 行）與 MaxDomains（149-152 行）同樣設 `$stopBatch = $true`、同樣把其餘領域計 NOT_RUN、同樣 exit 0——這兩者是無爭議的正常配額停止。可見 `$stopBatch` 是迴圈控制旗標。更直接的是措辭：全 repo 中「停批」一詞只出現在 SYSTEM_ERROR（193、211 行）與 MUTEX_BUSY（207 行）三個分支的訊息裡；熔斷分支（200-203 行）**不寫「停批」**，它寫的是 NEEDS_ATTENTION。指控引用的 NOT_RUN 與熔斷，用…

### X5. 心跳註解與 L59 強殺判讀對「沉默 20-30 分」給出互相矛盾的裁決

**為什麼不成立**：兩條規則的作用域是互斥的，而且 267 行**自己就明文預告**了 296-297 行那條規則的觸發條件——不是同一門檻推出兩條互斥規則。

1) 267 行的 `$silent -ge 20` 分支位於 249-271 行的心跳 while 迴圈內，只在 **session 還活著、還有機會跑完** 時輸出。它的措辭中性，但同一句話裡就寫死了升級出口：「**接近逾時上限仍無輸出才需依 SOP-12 查 oracleMCP 通道**」。

2) 296-297 行的 `$killSilent -ge 20` 分支在 `if (-not $done)`（278 行）之內、`taskkill /T /F`（279 行）之後才求值。它**只可能**在「已經撞到逾時上限、且撞上限那一刻仍無輸出」時執行——這正是 267 行指定要查 SOP-12 的那個條件。267 行說「常態」的是「委派期間中途沉默」，不是「撞上限時仍沉默」；兩者不是同一訊號。

3) 指控的反例（沉默 25 分、於上限被強殺的「健康」session）在本 repo 的實測基線下不成立：健康基線是「沉默約 30 分、**總計 35 分正常完成**」（applied.md:939），而 audit 上限被刻意設成 **120 分**（ps-auto-loop.ps1:58）就是為了不讓健康 session 撞邊界。一個跑滿 120 分、末尾靜止 20 分以上的 session，正是 L60 記載的實案簽名（13/15 檔約 10 分做完後永久靜止，60／90／120 三種上限都照撞，applied.md:1271）——對那個 case，「調高上限沒有用」是實證結論而非誤判。

4) 280-282 行的「兩種處置完全相反」是在描述**強殺當下**兩個分支（≤5 分調上限 vs ≥20 分查通道）的分流理由，並非在比較…

### X6. 「連續 2 次逾時／連續 2 次 session 錯誤」兩條熔絲的重置不對稱：逾時與錯誤交替時兩條都不觸發，錯誤夾逾時時卻以「連續」之名觸發

**為什麼不成立**：指控的兩個後果中，撐起 severity 的那一半（後果 1「交替失敗時兩條熔絲都不斷、一路燒到 MaxCycles 20 圈」）在程式碼上是假的，而且被指控自己的 evidence 欄推翻。

關鍵事實：$errorStreak 全檔只有兩個寫入點——488 行 ++、509 行歸零（且 509 是 `if (-not $sessionOk){…} else {…}` 的 else 分支，只有 exit 0 才走到）。逾時路徑 471-481 完全不觸碰 $errorStreak，481 行 `continue` 直接跳過 509。也就是說 **errorStreak 會跨過逾時圈黏著存活**。指控在 evidence 欄自己寫了「errorStreak 不重置、不遞增」，卻在 claim 欄推論成「errorStreak 也到不了 2」——兩句互斥，後者不成立。

實際走 timeout→error→timeout→error 的交替序列：
- 圈1 逾時：timeoutStreak=1，errorStreak=0，continue。
- 圈2 錯誤：483 行 timeoutStreak=0；488 行 errorStreak=1，未達 2，續跑。
- 圈3 逾時：timeoutStreak=1（errorStreak 仍為 1，未被碰），continue。
- 圈4 錯誤：483 行 timeoutStreak=0；488 行 errorStreak=2 → 500 行 break，停機理由「連續 2 次 session 錯誤（需人工看 err log）」。
最壞 4 圈就熔斷，不是 20 圈；「每一個 session 都失敗卻兩條熔絲都不斷」不存在。同理 timeout→error→error 於圈 3 停、timeout→無進度成功→timeout→無進度成功…

### X7. ps-orchestrator／ps-deep-research 的 frontmatter 註解仍稱「三個 MCP 必須明確 deny」「尚未整合的新 MCP」——PeoplecodeMetadata 早已正式整合，system prompt 每輪載入過期狀態

**為什麼不成立**：指控引的三行原文確實存在、字句無誤，PeoplecodeMetadata 也確實已於 2026-07-27 正式整合——但「設計矛盾」不成立，因為指控的傷害機制（L62：每輪載入的 system prompt 帶過期狀態 → orchestrator 誤判第四個 MCP 全體不可用）被檔案本身推翻：

1. 位置錯判。ps-orchestrator.md 的 frontmatter 到第 26 行 `---` 才結束，body 從第 28 行 `# PeopleSoft 業務分析 Orchestrator` 起；ps-deep-research.md 的 `---` 在第 20 行。指控引的 :8／:24／:18 三行全部是 YAML 區塊內的 `#` 設定註解，被 YAML parser 吃掉，不是 body prompt 文字。全 repo 慣例也證實這層是寫給維護者的：ps-ui-flow.md:24「未來上線後取消註解並對齊註冊名」是對編輯檔案的人下的指令，對模型毫無意義；ps-sql-flow.md:21-22 同型。

2. 真正被載入的 body 已經是最新狀態，且說的正好是「四個」。ps-deep-research.md:131-132 明寫「本 agent 對四個 MCP **全部 deny**」——同一檔的 prompt 層沒有「三個」也沒有「尚未整合」。ps-orchestrator body 則整段從未提及 PeoplecodeMetadata（grep 全檔只有 :25 的 tools key），「現況（哪些 subagent 已可用）」節（:97-105）是按能力面向寫的，沒有任何「第四個 MCP 不可用」的敘述可供 orchestrator 據以誤判委派。指控的因果鏈缺最後一環。

3. L62 自己的落點就不含 frontmatter。app…

### X8. ps-orchestrator 工作流第 1 步指模型「或用 MCP ps_get_customization_profile」——同檔 frontmatter 自己宣告該工具未實作、且本 agent 四個 MCP 全 deny：規則檔把模型導向保證不可用的路徑

**為什麼不成立**：指控的兩隻腳只有一隻站得住，而那一隻被它自己引用的那句話當場化解。

(b) 事實錯誤（我親自核對 tools map 全文）：ps-orchestrator.md 的 deny 只有四個前綴 —— PeoplecodeElasticSearch_ / PeoplecodeSource_ / oracleMCP_ / PeoplecodeMetadata_。而依同檔 :11 自己寫的完整工具身分，這個工具的前綴是 `peoplesoft_`，**不在 deny 清單裡**；我另外 grep 全 .opencode/agent/ 也沒有任何一檔出現 `peoplesoft` 開頭的 key。依框架自家 L1 覆寫表教義（同檔 :7「沒列出的工具一律預設開啟」），`peoplesoft_*` 一旦實作就是**預設開**。指控說「即使實作，本 agent tools map 對所有 MCP 都是 deny」是把「四個具名前綴」讀成「所有 MCP」——正好犯了 L61 自己警告的「工具身分＝前綴＋名稱，錯一半就等於不存在」的反向錯誤。

(a) 屬實但無害：mcp-tool-contracts.md:43 確實把它標 *(proposed)*，:27-30 也寫「現況共三個 MCP」，所以今天呼叫必得 unavailable tool。但指控把它描述成「工作流第 1 步指模型『或用 MCP』…導向保證不可用的路徑」，這是錯讀句構。第 1 步的**主詞是祈使句 Read**，MCP 只是括號內的替代選項；而 Read 的兩個目標檔我實際 ls 過，兩個都存在（customization-profile.yaml 2987 bytes、business-domain-map.yaml 3188 bytes），agent 也有 read: true。也就是說**可走的路就寫在同一句的前半…

### X9. ps-deep-research 的 A 項修法用第一人稱操作句教「可先 search_chunks(...) 結構化過濾直達」「重跑 cookbook 樣板取新值」，但本 agent 四個 MCP 全 deny——同一節兩條指示互撞

**為什麼不成立**：指控的引文逐字屬實（:113-114、:119-122 確實沒有「委派」二字），但「同一節兩條指示互撞」的結構不成立，理由有三，其中第一條直接推翻指控的核心機制。

(1) 指控的因果鏈建立在「澄清句排在後面、小模型先讀到操作句就會照做」。這個排序前提是錯的：本檔**正文第一句**（:25-26，在 A 項清單之前 75 行）就是「你自己不檢索——一律委派 subagent」，frontmatter 註解（:5）也寫「不碰檢索 MCP（委派 subagent）」。也就是說模型無論怎麼順讀，先撞到的都是委派鐵律，不是操作句。指控只掃到 :127-132 那條，漏了 :5 與 :25-26 兩個更早、更醒目的宣告，另外還漏了 :252 硬規則。全檔一共四處明文，不是一處補丁。

(2) L63 說的是「範圍靠**標題暗示**＝沒有範圍」。這裡的範圍不是靠標題暗示，是四處明文散文陳述；而且 :127-132 這條就在**同一份清單內**，不但宣告四個 MCP 全 deny，還特地把裸名 `search_chunks` 對映成 `PeoplecodeElasticSearch_search_chunks`——這條 bullet 存在的目的就是替全清單出現的裸工具名做身分正規化。指控把「為了解決這個問題而寫的那條」當成「來不及救場的那條」。

(3) L53／L43 要求的「可執行修復路徑或明確人工出口」在同一清單裡有：:133-137 的 L56 出口按型別分流——SQL／metadata 型（涵蓋 STALE_DATA 的 cookbook 重跑）→ 寫 `待人工SQL`；CHUNK 型（涵蓋 MISSING_CHUNK_ID）→ 移除該列＋降級 INFERRED，兩者都要記查法收據。所以 L43 症狀裡那個「無限迴圈／亂代償」的關鍵缺件（合法終點）並不缺，L61 的不可重試鏈也…

### X10. lint 指定的人工出口路徑「SOP-2 第 4 階」在 SOP-2 裡不存在——□4 是「重跑 lint」，人工自跑 SQL 藏在 □6 升級梯第 (4) 級且進入條件不符

**為什麼不成立**：審查者把「階」誤讀成「□」編號。框架內部有一致且互斥的兩層編號詞彙：**□N ＝「第 N 步」，升級梯的 (N) ＝「第 N 階」**，兩者在多處交叉互證：

1. 「步」＝□：SOP.md:77 的 □6(3) 自己引用「tool-call 約束解碼（SOP-10 第 5 步）」，而 SOP-10 的 □5 正是 SOP.md:270「□ 5. 約束解碼（治 tool-call JSON 壞格）」——完全對上。applied.md:610 也稱 □6 為「SOP-2 第 6 步手術升級梯」。
2. 「階」＝升級梯的 (N)：applied.md:631 是**同一份規則的權威落點紀錄**，明寫「SOP-2 升級梯補第 4 階：個位數殘項人工直通——…oracle 類自己開 SQL Developer 跑 cookbook 樣板（先設 CURRENT_SCHEMA）」。加寫這條的 git commit message 本身就叫「SOP-2 升級梯第 4 階：個位數殘項人工直通」。
3. 指標的目標唯一且精準：SOP-2 全段只有 □6 有 (1)-(4) 四項編號梯，其第 (4) 階（SOP.md:80-85）恰恰就是 lint 描述的動作——「管理者自跑 SQL 後回填」。lint:756 該段的上下文是 B 路線（SQL／oracle 型），對應 (4) 階裡的「oracle 類＝自己開 SQL Developer 跑 cookbook 樣板…keyRows 逐字抄」，一字不差。

所以「SOP-2 第 4 階」不是指 □4（那是「第 4 步」，內容為重跑 lint），而是 □6 升級梯第 (4) 階，解析得到、且解析結果唯一。L63 要求的「補救路徑明文存在」在此成立：人工出口的操作指引（含 ALTER SESSION SET CURRENT_SCHEMA、cookb…

### X11. headless 死鎖向量總盤點結論：全部「提議／提示使用者」措辭都是收場型、不阻塞；但「同類 FAIL ≥ 2 → 提議 /ps-lesson」的教訓迴路訊號在無人批次下結構性失聯

**為什麼不成立**：指控的死鎖盤點部分屬實（那些行都在，且 L63 豁免確實落檔），但它唯一宣稱的「實質斷點」建立在一個我親自讀檔即可推翻的事實錯誤上，因此整條「教訓迴路在無人模式下結構性失聯」不成立：

(1) 事實錯誤：指控說「這個提議只落在 auto-loop-logs/<領域>/<時間戳>-audit.out.txt 裡」。實際上「系統性錯誤觀察」是 90-audit.md 的**模板強制章節**（audit-template.md:61），而且被 lint **機械檢查**（ps-doc-lint.ps1:468-470 把 '## 系統性錯誤觀察' 列進 $auditSections，缺就發警告 :475）。也就是說訊號落在領域交付物這個持久化、受稽核的檔案裡，不是只落在暫態 stdout。這正是 L0「能機械化就不寫 prose」的做法。

(2) 人工出口確實存在且機械化：ps-auto-loop.ps1:684 在**每次停機**（畢業與否都寫）都往該領域 log 印出明文指路：「lesson 建議與卡住項在 90-audit.md 與 checklist.md」。SOP-17 第 7 條的「只看一行」是**夜跑熔絲判讀**（該節自己說「每天早上看 Summary 那一行就是這條熔絲」SOP.md:387-388），不是「人這輩子只讀這一行」的全域宣告。

(3) 沒有自我矛盾：框架從未宣稱教訓迴路在無人模式下自動運轉，反而**明文把它劃出自動化範圍**——ps-auto-loop.ps1:38「人的位置：lesson、correct、PR 審核照舊人工；本腳本只驅動內容生產」。教訓迴路的入口在兩份 README 都是人觸發的（/ps-lesson 是使用者打的 slash command；README.md:288 的條件是「答錯**經指正**後」）。明文範圍聲明 ≠ 斷線…
