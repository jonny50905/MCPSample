# 知識檢索、Spec 引擎與跨迴路補研究——issue #33／#34／#35／#36 決策備忘（第二版）

> **採信基礎**：本備忘只採信本次逐行實看的碼與文件（handover HEAD `0a4e2f3`、#17 功能分支 `0dd11b5` 唯讀 worktree、OpenCode 1.18.29 原始碼 `packages/opencode/src/tool/{read,grep}.ts`、`packages/core/src/v1/config/permission.ts`）。
> issue 的 Part B 候選方案與協作者留言（四篇）一律視為主張，逐條對碼裁決；第一版設計再經七個鏡頭的對抗審查（小模型可行性、PS 5.1／Windows、並行與 crash、機密邊界、pipeline 不變量、範疇契合、issue 作者 48 個設計問題），裁決見 §10。所有「檔案:行號」皆為實看，推測處標明。
> 日期：2026-09-17。分支：`claude/peoplesoft-framework-handover-0u6b5g`。

---

## 1. 四張 issue 的問題定性（獨立判定）

| issue | 問題成立？ | 一句定性（碼證據） |
|---|---|---|
| #33 知識檢索 | **成立** | 問答只看 wiki（ps-orchestrator.md:59-68；README.md:183-184；test-scenarios I2），NN 檔從未被當成檢索來源；deep-research 更明文「不回讀已完成的 NN」（ps-deep-research.md:77、:522）。NN 是經 lint／稽核／畢業的成品，卻對問答不可見。 |
| #34 Spec 分母 | **成立** | #17 的 `-Plan` 以整個領域全部 NN 為分母（ps-contract.ps1:68；ps-contract-lib.ps1:290-293、:574-605），共用 Record 只要出現在任一 NN 資料流就升成 entity unit；沒有「入口＝Component＋需求」的概念。公司 Template／Checklist 機密＝需求必須以資料（不是文字）跨界。 |
| #35 Spec 長文本外環 | **成立** | #17 只有 CLI 動詞，沒有外環駕駛（其決策備忘 §4 明列延後）；且經沙箱實跑證實 `-Accept` 會把 NN 內容已變、fragment 未重寫的舊片段簽成 DONE（ps-contract.ps1:120-140）。單一對話產整份 Spec 與早期 Research 同病（L2／L8／L27）。 |
| #36 跨迴路補研究 | **成立** | 外環對 deep-research 只有五種 session（research／audit-batch／surgery／distill／entity 升級，ps-auto-loop.ps1:1729、:1869、:2025、:2303、:2315），沒有「指定 NN＋指定問題」的入口；checklist 列型別封閉（A／U／D／調查項），外部列會被債務判定、Unticked 門、身分調帳誤判（ps-auto-loop.ps1:183-185、:1841、:2157-2178、:345-347）。 |

**#17 的處置**：不合併、不修補、不作依賴：(a) 分母設計錯在骨架；(b) 舊片段洗白是驗收層漏洞（沙箱重現）；(c) 兩個 command 檔的開線措辭已被 #29～#32 取代；(d) `git merge-tree` 乾跑 HANDOFF.md 與 manifest 衝突。**但其中與分母無關、已被 111 個判定驗過的通用函式逐字取用**（改前綴、註明出處）：正規化 hash／Ordinal 排序／canonical JSON 的做法（本版由 ps-knowledge-lib 提供同義函式）、固定表格 fragment 解析器骨架（`Read-CtFragment` L370-450）、`Test-CtSelectOnly`、`Get-CtId`／`Get-CtUniqueId`、`New-CtGateResult`＋tier 聚合、render parity 門。重寫的只有分母（`Get-CtUnits`／`Get-CtNnFiles`）、18 節 renderer、`-Accept` 路徑。

---

## 2. 對 Part B 與協作者提案的逐條裁決

| # | 主張（出處） | 裁決 | 理由（碼證據） |
|---|---|---|---|
| 1 | 檢索順序 Wiki → NN → 現查（#33 Part B） | **修正** | 「閱讀成本排序不是信任排序」成立。索引一次搜兩種來源、依**品質等級**排序；wiki `verified`／`reviewed` 與 NN `AUDITED_CLEAN` 同級可直接引用；衝突不以固定順位覆蓋（§4.4）。 |
| 2 | 只載入與問題相關的 NN 片段（#33 Part B；協作者「預切片段」） | **採納但不預切** | `read` 有 `offset`／`limit`（read.ts:30-35、:266-269），`grep` 回檔名＋行號（grep.ts:96-97）。索引只記節的 `offset/limit`，模型讀原檔片段——不另存切片檔、不需要新工具。 |
| 3 | 索引放 `.ps-runtime/knowledge/`（協作者）／放內部 git（第一版） | **修正：gitignore 的本機快取** | 審查證實索引的等級欄依賴單機檔（graduation.json、audit-r<N>.done.json），進 git 必衝突。改為本機快取：管理機由 auto-loop 在 safe point 重建；其他機 pull 後 `ps-knowledge -Rebuild`（SOP）；`ps-spec -Plan` 先自動重建。落點 `docs/ps-research/knowledge/`（保留名；不在領域目錄 → 不進畢業 hash、lint 領域掃描看不到；只有 wiki 的 `-Recurse` 連結掃描會讀 → 索引檔**不寫 `[[ ]]`**）。 |
| 4 | 品質不壓成一個 confidence 分數（協作者） | **採納** | 檔頭狀態、90-audit 燈號、待補 A／U 列、稽核後是否改過、畢業 tier 分欄；模型契約只用一個封閉**等級**（§4.3）。 |
| 5 | 新增 `ps-knowledge-reader` agent（協作者） | **不採** | orchestrator 本來就有 read／grep／glob；多一個 agent＝多一份 system prompt 與委派失敗面（L27）。 |
| 6 | `KnowledgeNeed` 與 request 分兩層 schema（協作者） | **合併** | `need` 就是 request 的內容欄位；requestId／consumer／domain 是外殼。 |
| 7 | 每 request 一檔＋另寫 result、create-only（#36 Part B） | **採納並修正** | 檔名改為 workKey 決定（`S-<workKey24>-g<n>`），create-only 的 Move 衝突就是去重；隨機 id 會讓兩個 producer 各建一檔（審查 blocker）。 |
| 8 | request 轉成 checklist A／U／D 列（#36 討論） | **修正** | 碼上不透明（:185、:1841、:2157-2178、:345-347）。補研究由外環驅動的 **manifest session** 做；唯一例外＝目標尚無 NN 時，**外環**寫一列文法合規的 D 列（它本來就是 D 列的唯一機械寫者，:1476-1486），走既有研究相位建檔。 |
| 9 | Research 完成點＝畢業＋Wiki 同步（#36 問題 9） | **修正** | 畢業收據先發、distill 在後、失敗不撤（:2288、:2296-2320）。Research 結果只宣告「研究到哪些 NN、hash、證據列、當時稽核輪次」；可信等級由知識索引在消費時判定（§5.6）；Spec 端多一個 `WAITING_AUDIT` 狀態，不重送。 |
| 10 | Spec 入口＝Component＋Spec Definition Pack（#34 Part B） | **採納** | 需求以資料跨界；pack 只含 opaque ID、capability 代碼、slot id、條件、基數；模板原文只在公司機（§6.2）。 |
| 11 | capability catalog 固定、內部只做 mapping（#34／#35） | **採納並縮小** | 首版只承諾能從 NN 八節與 wiki 確定性抽取的能力，加少量 worker 固定表格的組合能力；找不到就 `UNSUPPORTED`；新能力用只含公開詞彙的申請單（§6.9）。 |
| 12 | Contract 停在 generic knowledge，私有投影另一層（#34 Part B） | **採納** | facts（generic）→ slot 綁定（私有 pack）→ 模板（私有檔、公司機）。 |
| 13 | 18 節固定 Spec、Canonical Contract JSON 為 SoT（#17） | **不採** | 章節是公司的；SoT 是 facts＋片段收據＋trace，render 是投影。 |
| 14 | 短碼診斷 `4-17-42-110`（#35 Part B） | **採納並定格式** | `SPEC1-<stage>-<code>[-<count>]`；drill-down `-Drill` 只回固定數值 tuple；opaque 需求 ID（Rnn）與 factKind 可傳（issue 明文允許）；hash／路徑／文字不出。三個 CLI 家族都有結論碼（KNOW1／SUPP1／SPEC1；§3.5）。 |
| 15 | worker 明確 deny 全部 MCP（協作者 #35） | **採納並機械化** | 四 MCP 全關、task 關、bash 關；`permission.read` 逐路徑只開 attempt 目錄（agent.ts:293 合併 `permission`；permission.ts 允許 `{glob: allow|deny}`）；外環驗收另擋 fragment 含模板文字。 |
| 16 | per-job mutex、WAITING_KNOWLEDGE 釋放鎖（協作者 #35） | **採納並補共用鎖** | job 狀態用 `Global\MCPSample-Spec-<jobId>`；**每次 opencode session 另持共用 session-slot 鎖** `Global\MCPSample-OpencodeSession`（兩個 loop 共用一台本機模型，否則互相把對方逾時熔絲打爆）。 |
| 17 | 純版面改動走 Reuse 收據（協作者 #35） | **簡化** | `contentHash`（需求／條件／selector／證據政策）與 `bindingHash`（slot／模板）分開；只有 bindingHash 變 → 收據全部有效、只重 render。 |
| 18 | 20 個並行 producer、跨主機佇列（協作者 #36） | **縮小** | 同一內部 git 樹、多 producer（create-only）、單一 Research writer（既有全域鎖）；跨機靠內部 git（外環快照會 stage `supplemental/`）。 |
| 19 | Wiki projection manifest 與 stale 傳播（協作者 #36） | **部分** | 不改 distill 機制（#15 的題）。索引對每個 entity 算有效性（frontmatter stale／來源 ChunkId 在最新稽核明細 FAIL／超過 90 天）；補研究發布結果時把受影響的非人工 entity 標 `stale`（人工的在 Invalidated 追加一行）；PROJECTED 層另要求 `last_verified ≥ completedAt`。 |
| 20 | `ps-audit-batch` 加定向驗證 manifest（協作者 #36） | **延後** | 現行 manifest 只有連續範圍（:1266-1268；ps-auditor.md:81-84）。補研究改動的 NN 在下一輪稽核被全量重驗（hash 變 → PENDING，:1577-1579）——首版靠這條。 |

---

## 3. 共用地基

### 3.1 目錄與保留名（`docs/ps-research/` 底下保留：`wiki`、`knowledge`、`supplemental`、`spec`）

```text
docs/ps-research/
  <領域>/                          既有；graduation hash 只看此層 *.md（log.md 除外）
    audit-done.json                稽核合併時外環另存的各檔 hash（非 .md → 不進 hash、lint 不掃；進內部 git → 各機都能判「稽核後未改」）
    supplemental-parts/            補研究 session 的 manifest／收據／outcome（子目錄；gitignore 同 audit-parts；結果發布後搬到 auto-loop-logs）
  wiki/                            既有
  knowledge/                       #33 索引：index.md（NN＋Wiki 表）、objects.md（物件彙總表）、index.json——本機快取，gitignore
  supplemental/requests/           #36 request（create-only；進內部 git；外環快照 stage）
  supplemental/results/            #36 result（create-only；同上）
auto-loop-logs/<領域>/             既有（gitignore）；supplemental-done/ 存已發布 request 的 parts
.ps-private/spec/<packId>/         私有需求包＋模板副本（gitignore；fs-doctor 不列管）
.ps-runtime/spec/<jobId>/          Spec job 狀態、plans、attempts、receipts、outputs（gitignore）
```

`.gitignore` 新增：`docs/ps-research/knowledge/`、`docs/ps-research/*/supplemental-parts/`、`.ps-private/`、`.ps-runtime/`（test-auto-loop 情境 34 守衛；SOP 要求公司內部 git 的 .gitignore 加同樣四行）。機密集合擴大為 `docs/ps-research/**`、`.ps-private/**`、`.ps-runtime/**`（README／AGENTS）。
`ps-auto-all.ps1` 佇列 preflight 加保留名 `knowledge`／`supplemental`／`spec`。

### 3.2 原子寫入與路徑（PS 5.1／.NET Framework）

- **create-only**：`<目標>.tmp-<guid>` → `[System.IO.File]::Move(tmp, 目標)`；目標存在即 IOException＝輸家（讀贏家、回其身分）。
- **mutable**：tmp → `Replace(tmp, 目標, <備份檔>)`（備份名必須真實，`$null` 在 PS 會變空字串）→ 刪備份；目標被別的行程開著（Windows sharing violation）→ 重試 5 次、200ms 退避，仍失敗＝保留舊版、刪 tmp、回 `$false`（呼叫端印 `PUBLISH_DEFERRED`、不中斷）。
- 半寫殘留 `*.tmp-<guid>`／`*.bak-<guid>` 只清超過 10 分鐘的。
- 一切交給 `[System.IO.*]` 的路徑都是絕對路徑（`Join-Path $root …` 自 `$PSScriptRoot`；CLI 路徑參數 `GetFullPath`）；列舉一律 `-LiteralPath`。
- JSON：自製 canonical 序列化（insertion order、LF、2 空格、非 ASCII 原樣、只逃逸 `"` `\` 控制字元／U+2028／U+2029；數值 InvariantCulture、double 用 `R`）；**需要跨機一致的 hash（workKey、inputFingerprint）用 `-SortKeys`（逐層 Ordinal 排序鍵）**；讀用 `ConvertFrom-Json`。不用 `ConvertTo-Json`（5.1 逃逸 `<>'`、Depth 預設 2）。
- 時間戳 `Get-PsKnUtcStamp`（`yyyy-MM-dd'T'HH':'mm':'ss'Z'`，InvariantCulture）；日期鍵 `yyyyMMdd`；隨機 hex 取自 GUID 位元組（不用 System.Random）。
- 所有 `## `／`### ` 標題以陣列記錄（同名可重複；`duplicateSections` 計數），不以標題作 JSON 鍵（`ConvertFrom-Json` 對大小寫變體鍵會拋錯、完全重複會靜默吃掉）。

### 3.3 hash 與版本

- 檔案 hash 一律「剝 BOM／`\r` 後 UTF-8 SHA256 大寫」（與 ps-graduation.ps1:29-39 同；test-knowledge 斷言兩者相等）；排序 Ordinal。
- 每個 schema 帶 `schemaVersion`；每個 lib 檔頭 `$script:Ps<X>LibVersion`，dot-source 後版本守衛。
- 身分文法：`jobId`／`packId` `^[a-z0-9][a-z0-9-]{0,31}$`（小寫：mutex 名區分大小寫、NTFS 不分）；`requestId` `^S-[0-9a-f]{24}-g\d+$`；`attemptId` 零填序號 `a0001…`；PeopleSoft 物件名 `^[A-Z0-9_][A-Z0-9_.$#-]{0,59}$`；`requirementRef` `^[A-Z][A-Z0-9_]{0,15}$`。

### 3.4 Session 啟動（`scripts/ps-session-lib.ps1`）

把 ps-auto-loop.ps1 的 `Select-OpencodeShim`／`Invoke-Opencode`（cmd.exe shim、rc 檔、`.Handle`、taskkill 樹、心跳、FailureKind）抽成有明確參數的 lib（`-OcPath -Root -LogRoot -Model -ExtraArgs -PromptText -TimeoutMin -Tag`）；ps-auto-loop 保留同名薄包裝（呼叫點與 test-auto-loop 的 28 個 AST 函式清單不變）。每次 session 前取共用 `Global\MCPSample-OpencodeSession`（有界等待、abandoned＝取得），逾時從取得 slot 起算。prompt 仍限單行、無雙引號與 cmd 中繼字元（:868-870）。

### 3.5 結論碼（三個 CLI 家族）

每個 CLI 動詞最後一行都是**唯一的結論碼**（fs-doctor「結論代號」樣式），上面的內容一律本機用：`KNOW1-<stage>-<code>[-<count>]`、`SUPP1-…`、`SPEC1-…`（碼表在 `.opencode/peoplesoft/spec/support-codes.md`，含 KNOW／SUPP 家族）。結論碼**不含**路徑、檔名、物件名、hash、requestId；`-Check STALE` 只印變動檔**數**（檔名寫到 `auto-loop-logs/knowledge-doctor.txt`）。test 斷言結論碼符合 `^(KNOW|SUPP|SPEC)1-\d-\d\d(-\d+)?$` 且不含 `/`、`.md`、`TW_`、CJK。公司機驗收列（test-scenarios）只回報 PASS／FAIL、結論碼、enum 值。

---

## 4. #33 知識檢索層

### 4.1 建置（`scripts/ps-knowledge-lib.ps1`＋`scripts/ps-knowledge.ps1`；已實作，82 個判定）

輸入（確定性解析、不呼叫模型、不查 DB）：

| 來源 | 抽什麼 |
|---|---|
| `<領域>/NN`（`^\d\d-`、非 `00|90`） | 標題 `[[主物件]]`、檔頭 `狀態`／`Origin`、每個 `##`／`###` 的 start／end（陣列、重複計數）、相關物件表（物件＋角色）、畫面與欄位列數（「（無」＝NOT_APPLICABLE）、行為邏輯三種信心計數、資料流列（表／操作／來源／信心）、執行方式／權限是否空洞、未解事項條數、Evidence 附錄列數與種類（CHUNK／SQL／PENDING_MANUAL／UNRESOLVED）、全文 `[[連結]]`、正規化 hash |
| `<領域>/00-overview.md` | 功能地圖（物件／功能／類型／Origin） |
| `<領域>/90-audit.md` | 稽核輪次；記分卡每檔一列（PASS／FAIL／UNVERIFIABLE／VERIFIED／DISPUTED／燈號）；明細列；**完整性節的候選表**（候選物件／型別／經由表／方向／origin／分類／理由 → `domainGate[]`） |
| `<領域>/checklist.md` | 未勾 A／U 列所指 NN 檔（待補）、未勾 D／調查項數 |
| `<領域>/audit-done.json`（新，進 git）→ 退而 `auto-loop-logs/<領域>/audit-r<N>.done.json` | 各檔稽核時 hash → `hashSinceAudit` |
| `<領域>/graduation.json`（單機） | tier、files hash → `receiptTier`（顯示用，不影響等級） |
| `wiki/*.md`（非 index.md） | frontmatter（aliases／type／origin／status／confidence／last_verified／sources／reviewed）、Observations 條數、Relations、Invalidated 條數、hash、被哪些 NN 引用 |

**NN 等級（封閉）**：`BLOCKED`（檔頭）／`PARTIAL`（檔頭）／`AUDITED_CLEAN`（COMPLETE＋最新記分卡有該檔列且 FAIL=0、DISPUTED=0、非未稽核＋無待補 A／U＋稽核後未改（有 done 資料且 hash 相同；無資料＝unknown、不降級））／`AUDITED_ISSUES`（有記分卡列但 FAIL／DISPUTED>0、或有待補、或稽核後已改）／`UNAUDITED`（無記分卡列或列為未稽核）。tier 不參與等級（單機事實）。

**Wiki 有效性（封閉）**：`verified`／`draft`／`stale`／`STALE_BY_SOURCE`（來源 ChunkId 出現在任一領域最新 90-audit 明細 FAIL 列）／`EXPIRED`（`last_verified` 超過 90 天；格式非 `yyyy-MM-dd` 亦視為 EXPIRED）；`reviewed` 另欄。

**輸出**（gitignore 的本機快取）：

- `index.json`（腳本讀；`sections` 為陣列 `[{level,name,start,end}]`；不含 builtAt 以外的時間；`generation`＝所有輸入「相對路徑＋hash」Ordinal 排序後 SHA256）。
- `index.md`（模型讀）：檔頭（用法兩行）＋ `## 領域`、`## Wiki`、`## NN` 三表——**每筆一列、不含 `[[`**；NN 列的節欄＝`節名@offset/limit`（`@缺`＝該節不存在；`重複標題×n`）；主物件欄永遠是純物件名（cell 錨定才找得到），續篇檔另以「續篇」欄標「是」。
- `objects.md`（模型讀）：`## 物件` 一物件一列彙總（類型／主物件於／引用 NN 數／引用於≤10）——與 index.md 分檔，hub 物件不會吃掉 grep 的 100 筆上限。
- 動詞：`-Rebuild`（原子替換三檔；`PUBLISH_DEFERRED` 時 exit 1）、`-Check`（`CURRENT`／`STALE`／`MISSING`；exit 0／1／2；結論碼只帶變動檔數）、`-Find <詞>`、`-Slice <NN> -Section <節>`。
- **觸發**：ps-auto-loop safe point（啟動歸檔 commit 後、每圈末 git 快照前、收據＋distill 後；`try/catch` 不中斷）；`-SupplementalOnly` 結尾；`ps-spec -Plan` 開頭（STALE 即重建）；SOP：pull 後、`/ps-correct` 後手跑；`ps-auto-all` preflight 跑 `-Check`，STALE 即重建。

### 4.2 讀取契約（`.opencode/peoplesoft/knowledge-retrieval-contract.md`，模型讀；取代 ps-orchestrator 第 3 步）

1. **定位**（≤4 次 grep；只用下列呼叫形狀）：
   - `grep(pattern="[|] <物件名> [|]", path="docs/ps-research/knowledge", include="index.md")`（cell 錨定；直線放字元類別，不靠反斜線——經 JSON 參數傳遞反斜線常掉；先 NN／Wiki 表）；
   - 沒中 → `grep(pattern="<業務詞或 alias>", path="docs/ps-research/knowledge", include="index.md")`（aliases 欄）；
   - 沒中 → `grep(pattern="[|] <物件名> [|]", path="docs/ps-research/knowledge", include="objects.md")`；
   - 仍沒中或索引不存在 → `grep(pattern="<物件名>", path="docs/ps-research", include="[0-9][0-9]-*.md")` 一次；命中的 NN 一律視為 `UNAUDITED`、來源標「索引過時」；索引檔不存在則答覆註明「知識索引未建（管理者跑 ps-knowledge -Rebuild）」。
2. **挑選**：wiki 列 ≤3（整檔 read）、NN ≤3（等級 AUDITED_CLEAN ＞ AUDITED_ISSUES ＞ UNAUDITED ＞ PARTIAL ＞ BLOCKED；同級取稽核輪次新者）；同主物件的續篇算同一個 NN 名額。
3. **片段讀取**：依問題型別只讀對應節（選項／欄位→畫面與欄位；行為／條件→行為邏輯＋資料流；批次／排程→執行方式；授權→權限；入口→功能定位；證據→Evidence）；`read(filePath, offset=<offset>, limit=<limit>)`（offset／limit 直接用，不加減）；**只檢查第一行：必須以 `## ` 開頭且標題名（去括號註記）以該節名開頭**，否則（或 read 回 `Offset … out of range`）以 `grep(pattern="^## <節名>", path="docs/ps-research/<領域>", include="<NN 檔名>")` 重新定位一次（取第一筆），並把該檔等級視為 UNAUDITED、標「索引過時」。預算：每個 NN ≤2 節、每節一次 read、每個 NN ≤1 次重定位；總 ≤400 行、≤6 次 read（wiki 不計）；超過就換下一等級的 NN 或標「片段未讀完」。
4. **足夠 vs 現查**（子問句覆蓋）：每個子問句要有一條帶證據參照的主張才算覆蓋。**必須現查**：無覆蓋；問**現況**（值分布、筆數、還在不在用、誰現在能進）；關鍵主張只有 INFERRED／DYNAMIC_RUNTIME；來源等級非 AUDITED_CLEAN 且無 wiki verified 可佐；**wiki 與 NN 對同一事實矛盾（並陳＋必現查＋以現查為準；`reviewed: true` 或 `human:<日期>` 較新只影響並陳順序）**；索引過時。其餘：「知識（wiki＋NN）沒有或不足才現查」。
5. **來源標註**：`wiki（已驗證）`／`wiki（人工審定）`／`NN：<領域>/<檔>（AUDITED_CLEAN，第 N 輪）`／`NN：…（UNAUDITED／AUDITED_ISSUES／PARTIAL，未經現查）`／`NN：…（索引過時）`／`本次現查`；證據參照逐字複製 NN 附錄的 ChunkId／SQL。
6. **答覆結尾固定 `## 來源表`**：`| 子問句 | 來源 | 等級 | 證據參照 | 現查 |`（封閉值；test-scenarios I2 以 regex 驗：每列來源與證據參照非空；等級∉{AUDITED_CLEAN, wiki verified} ⇒ 現查=是）。
7. **輕稽核（第 7 步）**：wiki verified 與 NN AUDITED_CLEAN 的證據免驗；其他等級被引用的關鍵證據委派 @ps-auditor 任務 A 精簡版（只傳路徑＋「只驗 Evidence 附錄第 a~b 筆」）。
8. **「查不到」門檻不變**；建議補研究時印出固定指令 `powershell … ps-supplemental.ps1 -New -Target COMPONENT:<名> -FactKind <碼> -Properties <…> -DomainHint <領域>`（模型不寫 request 檔；QA／MANUAL request 由人跑 CLI）。

同步修改：ps-orchestrator（第 3／7／8 步、硬規則）、ps-business-explain（來源標籤）、ps-business-discovery（入口一句）、AGENTS.md、`.opencode/peoplesoft/README.md`、test-scenarios I2（含 grep 呼叫形狀 [致命] 檢查點）、`/ps-correct` 結尾提示 `-Rebuild`。ps-deep-research 的「不回讀已完成 NN」（研究相位）不變。

### 4.3 為什麼這樣就夠

沒有新工具；沒有第二份真相（索引只有定位與旗標，內容永遠讀原檔；過時的傷害＝行號漂移，契約有雙端自檢＋一次重定位）；小 context；可機械驗（`-Check`、test-knowledge、來源表 regex）。

---

## 5. #36 補研究協定（Supplemental Research）

### 5.1 資料模型

**request**（`docs/ps-research/supplemental/requests/<requestId>.json`，create-only；沒有任何自由文字欄位）：

```json
{
  "schemaVersion": 1,
  "requestId": "S-<workKey 前 24 hex>-g1",
  "workKey": "<canonical(need) 的 SHA256（-SortKeys）>",
  "generation": 1,
  "createdAt": "<yyyy-MM-ddTHH:mm:ssZ>",
  "consumer": { "kind": "SPEC | QA | MANUAL", "jobId": "<小寫識別>", "requirementRef": "R17" },
  "domain": "<提交時決定的路由領域>",
  "need": {
    "target": { "type": "COMPONENT", "name": "TW_DEMO_A" },
    "context": { "operation": "IMPORT" },
    "factKind": "DATA.FILE_INPUT",
    "properties": ["present", "layout", "fields"],
    "evidencePolicy": "AUDITED | STATIC | ANY",
    "freshness": "CURRENT | AS_OF"
  }
}
```

- 檔名＝requestId＝workKey 決定；**同 need 的並行 Submit 落到同一檔名，Move 輸家讀贏家**（去重不需要掃描）。`generation` 只在明確 `-Resubmit`（既有結果為終局）時 +1。
- `domain` 在 Submit 時決定：`-DomainHint`（必須存在 `docs/ps-research/<D>/00-overview.md`）＞ 知識索引中以 target 為主物件的 NN 所在領域（唯一）＞ 多個候選＝Ordinal 最小並記錄 ＞ 零候選且無 hint＝exit 2 `ROUTING_REQUIRED`（不建檔）。
- 驗證（Submit 與 intake 都做）：未知欄位拒收；`target.type` ∈ COMPONENT／RECORD／FIELD／PAGE／AE／SQR／SQC／SQL／PROCESS／MENU；名稱／factKind／properties／context 鍵／evidencePolicy／freshness／consumer.kind／jobId／requirementRef 各依 §3.3 與能力目錄；Research 端重算 workKey 不符即拒收。
- Submit 回傳 `{requestId, state}`，state ∈ `CREATED`／`PENDING`（既有、未終局）／`RESOLVED`／`PARTIAL`／`UNRESOLVED`／`OUT_OF_SCOPE`（既有終局）；`-Resubmit` 才建新 generation（舊 generation 由外環發 `SUPERSEDED`）。`-GitCommit` 時把 request 檔 `git add`＋commit（只 commit、不 push；失敗只記）。

**result**（`docs/ps-research/supplemental/results/<requestId>.json`，create-only，只由 Research 外環在 mini-run 末端寫；Move 遇到已存在＝冪等成功）：

```json
{
  "schemaVersion": 1, "requestId": "…", "workKey": "…", "domain": "…",
  "outcome": "RESOLVED | PARTIAL | UNRESOLVED | OUT_OF_SCOPE | SUPERSEDED",
  "dispositionCode": "RESEARCHED | ALREADY_COVERED | NO_EVIDENCE | WORKER_FAILED | CRASH | NOT_IN_DOMAIN | UNSUPPORTED | SUPERSEDED",
  "auditRoundAtCompletion": 4,
  "affected": [ { "file": "03-TW_DEMO_A.md", "hashBefore": "…", "hashAfter": "…", "sections": ["行為邏輯","Evidence 附錄"], "evidenceRows": [13, 14] } ],
  "attempts": 1, "completedAt": "…"
}
```

- 結果不宣告可信等級；`ALREADY_COVERED` 只准在 affected 列出的 NN 主物件＝target 且相關節非空洞時成立（否則不算）。

### 5.2 Research 端執行：`ps-auto-loop.ps1 -Domain D -SupplementalOnly`（獨立 mini-run，不在主迴圈加相位）

主迴圈一行不動（避免與 research／audit 的進度熔絲、drain、timeoutStreak 互相污染）。mini-run：

1. 取全域 Research 鎖；知識索引 STALE 即重建；`Get-SupplementalPending -Domain D`＝`requests/` 中 `domain==D`、無 result、非被 supersede、attempts<2。
2. 每個 request（≤`-SupplementalPerRun`，預設 2）：
   - **目標無 NN**（以 lint 同款 regex `^\d\d-<obj>(-\d+)?\.md$` 掃領域目錄，索引只當提示；領域沒有 00-overview／checklist → result `OUT_OF_SCOPE／NOT_IN_DOMAIN`）→ 外環在 checklist 末尾寫一列 `- [ ] D<輪次>-<seq> 新發現 <物件>：補研究 <requestId>（稽核）`（seq 承接該輪最大序號；D 治理去重），request 留 pending（`-Status` 顯示 `WAITING_RESEARCH`）；不派 session。
   - **有 NN** → 寫 attempt manifest `supplemental-parts/<requestId>.a<n>.manifest.md`（create-only；內容只來自 `need`＋目標 NN 檔名與節 offset／limit＋一跳 callee NN 的執行方式／資料流節（相關物件角色 ∈ 呼叫／啟動／排程／執行 且索引型別 ∈ AE／SQR／SQC／PROCESS）＋可寫的收據路徑；不含 consumer／requirementRef／jobId、不含 `[[`）→ 更新 mutable 指標 `supplemental-parts/current.manifest.md` → 取 session-slot 鎖 → `Invoke-Opencode --command ps-supplement`，prompt＝領域名 → 回來立刻寫 `supplemental-parts/<requestId>.a<n>.outcome.json`（timedOut／exitCode／FailureKind）→ NN 破壞防衛快照比對（restored 必須＝0）。
   - **收據**（`supplemental-parts/<requestId>.a<n>.md`，模型唯一可寫）：`## 處置`＝`| 處置 | 查法收據 |`（RESEARCHED／ALREADY_COVERED／NO_EVIDENCE／NOT_IN_DOMAIN／UNSUPPORTED）；`## 追加事實`＝`| 節 | 信心 | 敘述 | 證據# |`；`## 追加證據`＝`| 位置 | 說明 | 機器參照 |`（證據#＝追加證據表內序號）。驗收：兩表齊、≤150 行、無 ``` 圍欄、無 `[[`、無洩漏標記、節名 ∈ 八節、信心 ∈ 三值、證據# 在追加證據範圍內、機器參照 ∈ 完整 UUID／SELECT…FROM／待人工SQL、不含 requirementRef／jobId 樣式。
   - **合併（外環確定性）**：追加證據列編號＝現有附錄最大 `#`+1 起；追加事實依節：條列節（行為邏輯／未解事項）在節末追加條列（證據# 換成 `（附錄 #n）`）；表格節（畫面與欄位／資料流）在表末追加列；文字節（執行方式／權限／功能定位）在節末追加段落；節不存在 → 在 `## 未解事項` 前插入標題。合併前保留原 bytes；合併後 lint `-CoverageOnly` 的 blocking 違規數不得高於合併前，否則還原 bytes、該 attempt 記 `LINT_REGRESSION`。
   - 每個 attempt 的 outcome 寫完後才做既有的 reconcile／integrity；integrity FAIL → 還原（既有 `Invoke-ChecklistRecovery` 只在 -GitCommit 下），本 request 不發 result。
3. mini-run 末端（safe point）：對每個「本 run 有合格合併」的 request 檢查 affected 檔 hash 仍＝hashAfter → 發 result（RESEARCHED）；attempts 用盡 → `UNRESOLVED`（最後 outcome 缺＝`CRASH`、否則 `WORKER_FAILED`）；被 supersede 的舊 generation → `SUPERSEDED`；發布後把該 request 的 parts 搬到 `auto-loop-logs/<D>/supplemental-done/`；受影響的非 reviewed wiki entity 標 `status: stale`（reviewed 的在 Invalidated 追加一行「來源 NN 已補研究 <requestId>」）；重建索引；`-GitCommit` 時快照 stage `docs/ps-research/<D>`、`wiki`、`supplemental`。exit **4**（`SUPPLEMENTAL_DONE`；印 `SUPPLEMENTAL：results=<n> pending=<m>`）。
4. attempts 定義：manifest 檔數；outcome 缺＝crash（也算一次）。

**ps-auto-all**：每個領域在收據判定之前，若有 pending 且 `domain==D` 的 request → 先跑 mini-run（預期 exit 4；exit 1 計 NEEDS_ATTENTION、其餘 SYSTEM_ERROR）；之後照常判收據（NN 變了 → 收據無效 → RUN → 稽核重驗 → 畢業）。preflight 加 `ps-knowledge -Check`（STALE 即重建）。

### 5.3 ps-supplement command（agent ps-deep-research）

`.opencode/command/ps-supplement.md`：第一個回應必須是 `read docs/ps-research/$ARGUMENTS/supplemental-parts/current.manifest.md`；本指令**不是研究模式**（不讀 checklist、不從未勾項續跑、不寫 checklist／90-audit／log／NN／wiki）；**必須** read manifest 指定的 NN 節與 callee 節（系統提示的不回讀規則在此不適用）；依 factKind 走既定深度鏈委派（`supplemental-contract.md` 的表）；缺證據走既有出口（SQL 型→待人工SQL 列在追加證據；CHUNK 型→不寫、處置 NO_EVIDENCE＋查法收據）；只寫 manifest 指定的收據檔；回一行「已寫 <收據路徑>」。不引用 requestId 以外的任何識別。

### 5.4 消費端

- 消費者查 `results/<requestId>.json`；再查知識索引 affected 檔的等級；`AUDITED` 層＝等級 AUDITED_CLEAN 且該領域索引 `auditRound > auditRoundAtCompletion`；`hash ≠ hashAfter` 只是「已再修改、重讀」，不是降級。
- Spec 規劃器：need 已有 RESOLVED／PARTIAL 結果但等級低於 evidencePolicy → **不重送**，job phase `WAITING_AUDIT`（`SPEC1-5-04`）；`UNRESOLVED`／`OUT_OF_SCOPE` → unit `BLOCKED_KNOWLEDGE`（`SPEC1-5-05`）；只有 hash≠hashAfter 且事實仍缺才 `-Resubmit`。

### 5.5 完成邊界

| 層 | 誰判 | 依據 |
|---|---|---|
| RESEARCHED | Research mini-run | result 存在、outcome RESOLVED／PARTIAL |
| AUDITED | 知識索引 | affected 檔 AUDITED_CLEAN 且 auditRound > auditRoundAtCompletion（各機以 `audit-done.json` 判「稽核後未改」） |
| GRADUATED | 知識索引（單機欄） | receiptTier ≥1 且 receipt files hash == 現況 |
| PROJECTED | 知識索引 | target 的 wiki 有效性 ∈ {verified, draft} 且 `last_verified ≥ completedAt` |

### 5.6 v1 明確不做

事件日誌與 work 快照（attempts 由 manifest／outcome／result 檔推導）；跨主機佇列；定向稽核 manifest（等下一輪全量重驗）；Spec 直接寫 NN／wiki（永不）。

---

## 6. #34／#35 Spec 引擎

### 6.1 三層責任

```text
Generic engine（本 repo）                 Private adapter（公司機）                  Machine verification（本 repo）
  scripts/ps-spec-lib.ps1 / ps-spec.ps1    .ps-private/spec/<packId>/pack.json         ps-spec -ValidatePack / -Gate / -Doctor
  .opencode/peoplesoft/spec/               .ps-private/spec/<packId>/template-bound.md  scripts/tests/test-spec.ps1
    capabilities.json, pack.schema.json,   （只插 {{slot:Sxx}} 標記，不改 generic 檔）  support-codes.md（結論碼＋drill tuple）
    support-codes.md, troubleshooting-matrix.md, examples/pack-a, pack-b
  .opencode/agent/ps-spec-worker.md / .opencode/command/ps-spec-batch.md
```

### 6.2 私有需求包（`pack.json`；`pack.schema.json` 公開；PS 5.1 自製 validator、拒未知欄位）

```json
{
  "schemaVersion": 1, "packId": "demo", "packVersion": 3, "reviewedVersion": 3,
  "template": "template-bound.md",
  "slots": ["S01", "S02", "S03"],
  "checklist": ["C01", "C02", "C03"],
  "requirements": [
    { "id": "R01", "slot": "S01", "checklistRefs": ["C01"], "factKind": "UI.COMPONENT_IDENTITY", "required": true,
      "applicability": { "op": "ALWAYS" }, "cardinality": "ONE", "evidencePolicy": "AUDITED" },
    { "id": "R05", "slot": "S02", "checklistRefs": ["C02"], "factKind": "UI.FIELD_INVENTORY", "required": true,
      "applicability": { "op": "ALWAYS" }, "cardinality": "ALL_DISCOVERED", "evidencePolicy": "STATIC" },
    { "id": "R17", "slot": "S03", "checklistRefs": ["C03"], "factKind": "DATA.FILE_INPUT", "required": true,
      "applicability": { "op": "FACT_TRUE", "fact": "DATA.FILE_INPUT.present" }, "cardinality": "ANY", "evidencePolicy": "AUDITED" }
  ]
}
```

- 模板副本只插 `{{slot:Sxx}}`；引擎只認標記。`reviewedVersion`＝公司內部人員核可的版本（≠packVersion → `SPEC1-8-01 MAPPING_UNSIGNED`）。
- `applicability.op` ∈ ALWAYS／FACT_TRUE／FACT_FALSE／ALL／ANY／NOT；三值；UNKNOWN 永不變 N/A；條件圖無環。
- 驗證能保證：ID 唯一、每個 checklist id 至少被一個 requirement 引用、每個 slot 在模板出現且模板每個標記在 slots、factKind／properties／context 在目錄內、依賴無環、`required` 為 bool。**不能**保證映射語意——由內部覆核。

### 6.3 能力目錄（`capabilities.json`，公開）

| factKind | 模式 | 來源 | closure |
|---|---|---|---|
| UI.COMPONENT_IDENTITY | EXTRACT | NN 標題主物件、檔頭 Origin、00-overview 功能地圖 | 單值 |
| UI.NAVIGATION | EXTRACT | `### 導覽入口` 表、`### Technical Menu` | 表列數；未確認句＝UNKNOWN |
| UI.FIELD_INVENTORY | EXTRACT | `## 畫面與欄位` 表 | 列數；「（無」＝NOT_APPLICABLE |
| BEHAVIOR.RULES | EXTRACT | `## 行為邏輯` 條列（信心） | 條數 |
| DATA.FLOW | EXTRACT | `## 資料流` 表（READ／WRITE 由操作欄分） | 列數 |
| PROCESS.EXECUTION | EXTRACT（`follow`） | `## 執行方式` ＋ 00-overview 批次表 ＋ 一跳 callee NN 同節 | 段落存在 |
| SECURITY.ACCESS | EXTRACT | `## 權限` | 非空洞 |
| RELATED.OBJECTS | EXTRACT | `## 相關物件`（物件／角色）＋wiki type＋`domainGate` 分類（UNCLASSIFIED 亦列） | 列數 |
| GAPS | EXTRACT | `## 未解事項` | 條數 |
| EVIDENCE.APPENDIX | EXTRACT | `## Evidence 附錄` | 列數 |
| ENTITY.DETAIL | EXTRACT（一跳） | DATA.FLOW 的 Record → wiki entity Observations／Relations（只 requirement 指名時） | 每 Record 一筆 |
| BEHAVIOR.VALIDATIONS | COMPOSE | worker：行為邏輯條目＋證據列 → `| 來源條目 | 觸發 | 條件 | 訊息 | 證據 |` | 條目覆蓋率（外環算） |
| DATA.FILE_INPUT／DATA.FILE_OUTPUT | COMPOSE（`follow`） | worker：行為邏輯／資料流／執行方式（含一跳 callee 節）→ `present`＋`| 來源條目 | 欄位 | 格式 | 說明 | 證據 |` | 條目覆蓋率 |
| DATA.RECORD_USAGE | COMPOSE | worker：每個 DATA.FLOW Record → `| 來源條目 | 欄位 | 用途(READ/LOOKUP/WRITE) | 證據 |` | 條目覆蓋率 |

`follow`＝planner 可把相關物件表中角色 ∈ {呼叫, 啟動, 排程, 執行} 且索引型別 ∈ {AE, SQR, SQC, PROCESS} 的 NN 同節加入 read set（只一跳、記在 sourceRefs、該 NN 等級低於 evidencePolicy 則改為 KnowledgeNeed target=<callee>）。目錄外 → `UNSUPPORTED`。

### 6.4 規劃（`ps-spec.ps1 -Plan -JobId x -Component TW_X -Pack <packId> [-DomainHint d]`）

1. 驗 jobId／packId 文法、pack、目錄；知識索引 STALE 即重建。
2. 目標身分：索引 objects 主物件＝Component 的 NN（含續篇）；多領域→ domainHint 或最高等級，其餘記 `IDENTITY_AMBIGUOUS`。
3. 逐 requirement：applicability（三值）→ EXTRACT 直接產 facts `{factId, factKind, requirementIds[], subject, value, sourceRefs[{domain,file,hash,section,lines}], evidenceRefs[{file,row}], grade}` → COMPOSE 產 unit（`unitId`＝`<requirementId>.<subjectKey>`；subjectKey 文法：BEHAVIOR.VALIDATIONS `<Component>@行為邏輯:L<a>-<b>`、DATA.FILE_* `<Component>`、DATA.RECORD_USAGE `<Component>@<Record>`）→ 來源缺／等級低於 evidencePolicy → KnowledgeNeed → 查既有 result（§5.4 規則）→ 需要時 Submit（consumer=SPEC）。
4. 範圍：只沿 requirement 的 factKind、只從目標 Component 的 NN；`follow` 一跳；ENTITY.DETAIL 一跳；其餘物件只列名稱／角色／分類；OUT_OF_SCOPE／DEPENDENCY 分類原封照抄索引 `domainGate`，不改寫。
5. 寫 immutable `plans/<planHash>/plan.json`；`job.json`（mutable）記 `currentPlanRef`；`contentHash`／`bindingHash` 分開。

### 6.5 外環（`ps-spec.ps1 -Run -JobId x [-MaxSessions n]`）

- per-job 具名 mutex（ctor 例外→exit 2；WaitOne(0) false→exit 3；abandoned＝取得；WAITING 狀態以 ReleaseMutex＋Dispose 釋放）；phase ∈ PLANNED／RUNNING／WAITING_KNOWLEDGE／WAITING_AUDIT／READY／PUBLISHED／BLOCKED。
- pending unit 集合＝plan units ＋ `plans/<planHash>/splits/*.json`（拆分持久化）－ `receipts/` 中 inputFingerprint 相符者；**不信任 job.json 的單位狀態**。
- 每個 unit：`attempts/<attemptId>/`（零填序號）：先寫 `input.json`（read set 每檔 hash＋每節內容 hash；create-only）→ 從該快照切 `context/*.md`（每檔 ≤150 行、總 ≤400 行；manifest 列舉可計數的條目編號）→ `manifest.md` → 取 session-slot 鎖 → `--command ps-spec-batch`，prompt＝`<jobId>-<attemptId>` → worker 只寫 `attempts/<attemptId>/fragment.md`。
- 驗收：存在、≤150 行、無圍欄、無洩漏標記、章節與表頭逐字、enum 值域、`來源條目` 必在 manifest 列舉內、證據參照 ∈ read set 的 `<檔>#<列>`、不含 `{{slot:` 或模板副本的任一非標題行；**closure 由外環算**（列舉條目全在 fragment 列或 `## 未採用` 表 → COMPLETE，否則 PARTIAL）；`input.json` 與現在來源比對，來源已變 → 拒收、**不記 attempt**、要求 re-plan。通過 → `receipts/<unitId>.<inputFingerprint16>.json`（immutable，含 attempt 相對路徑與 fragmentHash、input.json 全文）。attempts≥2（健康 session 仍不合格）→ BLOCKED（`SPEC1-4-xx`）。容量事件（>150 行／JSON 洩漏）不記 attempt、寫 `splits/<unitId>.json` 對半切（不可切→BLOCKED_CAPACITY）。
- 先派完所有可派 unit，再進 WAITING_KNOWLEDGE／WAITING_AUDIT（釋放鎖、exit 0、印 `SPEC：WAITING_… n=<數>`）；等待中重跑 `-Run`＝無新 result 即 no-op。

### 6.6 產出與門（`ps-spec.ps1 -Render -JobId x`；`-Gate`）

- 確定性：facts＋accepted fragments → 每 requirement 一個 block（固定 renderer）→ slot＝其 requirements 的 block 串接 → `template-bound.md` 置換標記 → `outputs/<generation>/spec.md`、`trace.md`（requirement → facts → 來源檔 hash／證據列／一跳）、`gate.json`；**render 前重驗每個 sourceRef／receipt 指紋**，不符 → `SPEC1-6-xx SOURCE_CHANGED`、不換 `current.json`；重 render byte 相同（parity）。`-Render`／`-Gate` 不印任何內容。
- Gate：required 且 applicable 的 requirement 齊、cardinality（ALL_DISCOVERED 需 closure COMPLETE 或 EXTRACT 來源表存在）、grade ≥ evidencePolicy、證據參照可解、UNKNOWN 條件列 debt、checklist 覆蓋、UNSUPPORTED／BLOCKED／WAITING 全列；verdict `SPEC_COMPLETE`／`SPEC_PARTIAL`／`BLOCKED`。
- Doctor stage 0：`scripts/ps-spec*.ps1`、`.opencode/peoplesoft/spec/**`、worker agent／command 對 manifest hash 比對，不符 → `SPEC1-0-01 GENERIC_MODIFIED`。

### 6.7 私有接入（SOP 條目，公司機可搬）

(1) 複製 `.opencode/peoplesoft/spec/examples/pack-a/` 為 `.ps-private/spec/<packId>/`；(2) 對照公司 Template 逐章節插 `{{slot:Sxx}}`、登錄 slots；(3) 對照 Checklist 逐項登錄 `C<nn>`，每項映射到 ≥1 requirement（factKind 從目錄挑；挑不到填 `UNSUPPORTED`）；(4) `ps-spec -ValidatePack`；(5) `test-spec.ps1` 全綠；(6) 對一個已研究的 Component 跑 `-Plan/-Run/-Render`；(7) 內部覆核後填 `reviewedVersion`。**可改**：`.ps-private/**`。**禁改**：`scripts/**`、`.opencode/peoplesoft/spec/**`、worker agent／command（doctor stage 0 機械驗）。只回報結論碼與 drill tuple；template／checklist 原文與 `.ps-private` 內容不出公司。

### 6.8 短碼與 drill-down

`SPEC1-<stage>-<code>[-<count>]`，stage ∈ 0 integrity／1 pack／2 plan／3 dispatch／4 accept／5 knowledge／6 render／7 gate／8 mapping；`ps-spec -Doctor -JobId x [-Drill <stage>-<code>]` 每筆一行固定 tuple（例 `D7-21 R05 UI.FIELD_INVENTORY EXTRACT a=0 c=PARTIAL`；只有 opaque ID、factKind、模式、計數、封閉值），`troubleshooting-matrix.md` 給 stage→責任方（1／8 私有映射、2／3／4／6／7 引擎、5 Research）。

### 6.9 能力申請單（不洩漏 checklist 原文）

`CAP-REQ: sources=[NN 節名…], subject=<物件型別>, output=[公開欄名…], cardinality=<enum>`；禁止 checklist／template 文字與 C／S／R id；維護端只用合成 fixtures 實作。

---

## 7. 相依與實作順序

```text
#33 knowledge lib/CLI（已實作）＋契約＋orchestrator＋test-knowledge
  → 共用：ps-session-lib（session-slot 鎖）、.gitignore、auto-loop（audit-done.json、快照路徑、-SupplementalOnly）、auto-all
    → #36 supplemental lib/CLI＋ps-supplement command＋supplemental-contract＋test-supplemental
      → #34／#35 spec lib/CLI＋目錄／schema／examples＋worker agent／command＋support-codes＋test-spec
        → 靜態守衛（test-auto-loop 情境 34、test-ps51-static）＋文件（SOP-22～24、applied、HANDOFF、test-scenarios）＋manifest＋搬運
```

不動的東西：畢業門邏輯與 GateVersion、checklist 文法（外環寫的 D 列在文法內）、lint 規則、distill 機制（只加 stale 標記與 distill 條件一句）、runtime guard、主迴圈相位選擇。

---

## 8. 驗收（沙箱可做；合成 fixtures，臨時目錄，無公司資料）

| 套件 | 情境 |
|---|---|
| test-knowledge（82） | NN 解析（節 offset／續篇／PARTIAL／BLOCKED／缺節／重複標題／CRLF＋BOM／中文路徑）、90-audit（🟢🟡🔴⛔）、checklist 待補、audit-done／graduation 有無、wiki 有效性五態、等級表、index.md 無 `[[`、表序、物件彙總、原子替換與 tmp 年齡、確定性、-Check 三態、CLI exit、canonical JSON（-SortKeys 三源一致）、create-only |
| test-ps51-static | AST 走訪 scripts/**/*.ps1：三元／`??`／`?.`／`&&`／`-Parallel`／`-AsHashtable`／`ConvertFrom-Json -Depth`／`-Encoding utf8NoBOM`／三參數 `Join-Path`／`Split-Path -LeafBase`／`Test-Json`／`File.Move` 三參數／`Path.GetRelativePath`／`Get-Date -Format` 無 culture／`Get-Content` 無 `-Encoding UTF8` |
| test-supplemental | New／Submit 驗證負例、同 need 並行 20 次只一檔且 requestId 相同、路由三態、-Resubmit generation、manifest 不含 consumer／`[[`、收據驗收負例（缺表／非法處置／證據#越界／`[[`／洩漏標記／requirementRef）、確定性合併（條列／表格／文字節、附錄編號、缺節插入）、lint 回歸還原、attempts 由 manifest 推導、outcome 缺＝CRASH、目標無 NN → D 列、result create-only 冪等、SUPERSEDED、wiki stale 標記、結論碼形狀 |
| test-spec | pack 驗證負例、兩套假 pack 對同一合成 NN 產不同 spec、EXTRACT facts、COMPOSE manifest／context／條目列舉、假 worker 合格／不合格／超長／含模板行、input.json 快照與來源改變後拒收（不記 attempt）、receipt 鍵含指紋、re-plan 重用、WAITING_KNOWLEDGE／WAITING_AUDIT 不重送、render parity、render 前來源重驗、gate 覆蓋與 UNKNOWN、drill tuple 形狀、doctor stage 0、jobId 文法 |
| test-auto-loop 情境 34 | .gitignore 四行、快照三處路徑一致、auto-all 保留名、agent-doc-lint 對新模型檔零違規、合成識別字允許清單（TW_ 樣式） |

公司機驗收（test-scenarios 7b／J）：只回報 PASS／FAIL、結論碼、enum。

---

## 9. 已知限制

- 索引是本機快取：pull 後要重建（SOP）；契約用雙端自檢＋一次重定位兜底。
- 「稽核後未改」在有 `audit-done.json` 的領域才可判；舊領域第一次稽核合併後才有。
- Research 只回答 generic need；映射錯誤機械驗不出，靠內部覆核與 `reviewedVersion`。
- 補研究的合併只追加，不改寫既有句子；矛盾由下一輪稽核（DISPUTED→A 列）處理。
- Spec COMPOSE 首版四種；其餘 EXTRACT；不在目錄的需求 `UNSUPPORTED`。
- PS 5.1 只做語法紀律＋靜態守衛，實跑在沙箱 pwsh 7.6；公司機首跑走 fs-doctor 檢查 S。
- 目標尚無 NN 時要等研究相位建檔（D 列）；Domain Gate 由請求方的 domain 斷言取代（記錄在 D 列來源文字）。

---

## 10. 對抗審查裁決（第一版 → 第二版）

| 鏡頭 | 主要發現 | 裁決 |
|---|---|---|
| 小模型 | grep 不能指定單檔（grep.ts:60-68）；物件表吃掉 100 筆上限；行號算術；矛盾規則重複；worker 改寫 NN 是已知失敗路徑；agent-doc-lint 會擋日期例 | 全採：呼叫形狀寫進契約、表序 Wiki→NN、objects.md 分檔、`名@offset/limit`、雙端自檢、來源表、worker 只寫 delta 收據由外環合併、佔位符 |
| PS 5.1／Windows | 只有語法紀律沒有機械守衛；canonical JSON 未定序；標題作 JSON 鍵；jobId 未驗；Invoke-Opencode 不可重用；Replace sharing violation；民國曆；相對路徑 | 全採：test-ps51-static、`-SortKeys`、sections 陣列、身分文法、ps-session-lib、Replace 重試、InvariantCulture、絕對路徑 |
| 並行／crash | result 在 rollback 窗內發布；隨機 requestId 讓去重成競態；receipt 以 unitId 為鍵；指紋在驗收時算；attempt 未定義；補研究相位污染熔絲；auto-all 把補研究算失敗；路由丟單；快照不 stage supplemental；兩個 loop 搶同一模型 | 全採：mini-run 末端發布、workKey 檔名、receipt 含指紋、input.json 先寫、attempt＝manifest 數、獨立 mini-run（不加相位）、exit 4、Submit 時路由、快照路徑、session-slot 鎖 |
| 機密 | 只有 Spec 有結論碼；.gitignore 未加；能力申請會洩漏 checklist；worker 讀取未機械限制；jobId 自由文字；記憶體例子用了非合成物件名；examples 不在搬運集合 | 全採：三家族結論碼、.gitignore＋守衛、CAP-REQ 表單、permission.read 逐路徑、身分文法、合成識別字守衛、examples 移入 .opencode |
| pipeline 不變量 | 新 NN 無 checklist 列＝MANUAL_ONLY 停機；相位熔絲；快照路徑；供 parts 的 `[[` 進 WIKI_MISSING；索引含單機輸入不可 commit | 全採：外環寫 D 列、mini-run、快照路徑、收據禁 `[[`＋發布後搬走、索引改本機快取＋audit-done.json 進 git |
| 範疇契合 | 未研究 Component 走不通；RESOLVED 永遠到不了 AUDITED；一跳 callee；#17 通用函式應逐字取用；drill-down 缺；ALREADY_COVERED 死鎖 | 全採：D 列、WAITING_AUDIT＋auditRound 定義、`follow` 一跳、逐字取用、`-Drill`、ALREADY_COVERED 定義 |
| 作者 48 問 | 38 具體、10 模糊／缺（見上列） | 缺項全部在本版補上（§4.2 衝突鍵、§6.3 domainGate、DATA.RECORD_USAGE、subjectKey 文法、doctor stage 0、QA request 由人跑 CLI、WAITING 重跑 no-op、wiki stale 標記） |

## 11. 對抗審查修正（實作後第二輪：find 六鏡頭 → 每項兩名獨立 refuter，refuter 以 Opus 跑）

### 11.1 知識索引／補研究／auto-loop（32 項提出、13 項兩名 refuter 都確認；被駁回但順手修掉的另列）

| # | 確認的發現 | 修法（落點） |
|---|---|---|
| 8 | create-only 把任何 IOException 當「輸掉競賽」：request／result 靜靜消失、CLI 回 PENDING exit 0 | `Write-PsKnCreateOnlyText` 三態 `$true`／`$false`（目標已存在）／`$null`（重試 5 次仍寫不進＝WRITE_DEFERRED）；Submit 回 `WRITE_FAILED`（`SUPP1-1-06` exit 2）；Publish 回 Reason；manifest `CreateDeferred` 撤回 |
| 9 | builtAt 依目前文化（民國曆 115） | InvariantCulture |
| 11 | Test-PsKnHollow 對「標題緊接下一標題」的節切片錯 | `$Start -ge $End` 即空洞 |
| 1 | 中斷後重跑把已合併的 attempt 再派一次（雙重合併、UNRESOLVED 蓋掉已合併 NN） | outcome 記 `merged／terminal／code／targetFile／hashAfter／affected`；迷你圈啟動先掃「已合併未發布」的 attempt 直接發布，不重派 |
| 4 | current.manifest.md 寫不進被忽略：session 讀到舊指標、燒掉 attempt | `New-PsSuppManifest` 回 `CurrentWritten`；寫不進就撤回工單檔、本 run 提前結束 |
| 16 | prompt 安全閘門把含 `A > B > C` 的手術提示全擋（每圈 lint 修復停擺） | `Test-PsOcPromptSafe` 只擋 CR／LF／雙引號／%（cmd 特殊字元由 shim 檔承接）；test-auto-loop 對三個提示常值做閘門驗證 |
| 17 | SLOT_BUSY 被當逾時：稽核 attempts 被燒、「未查成」入檔、停機原因說謊 | `-SlotWaitMin 1440`（每 5 分鐘心跳）；等滿才回 SLOT_BUSY；稽核批次不計 attempts 直接回傳、手術／提煉／升級中止、主迴圈停機原因寫 slot |
| 18 | 迷你圈 exit 1（永遠是崩潰）被 auto-all 記 NEEDS_ATTENTION 後繼續 | 迷你圈 try／catch → `SUPP1-3-03` exit 2；auto-all 的 exit 1 進連續失敗保險絲、不重複計數 |
| 26 | wiki 有效性 EXPIRED／STALE_BY_SOURCE／UNKNOWN 無規則無標籤；draft／stale wiki 與 BLOCKED NN 沒有 §5 標籤 | 契約：有效性 → 標籤對照表、來源表一律 `wiki stale`；新增「wiki（草稿，未經現查）」「wiki（已過期／來源失效，未經現查）」「NN：…（BLOCKED，未經現查）」；orchestrator／explain skill 同步 |
| 31 | 契約叫模型整檔 read wiki 卻沒寫檔路徑規則 | `docs/ps-research/wiki/<物件名>.md`（物件名取自 Wiki 列第一欄） |
| 21 | 模型寫進 `supplemental/requests|results/`、`wiki/` 的檔被當權威入庫 | 迷你圈圍欄快照／還原（新增檔刪除、變更檔還原、記 fenceViolations、該次作廢） |
| 22 | request 內容未驗證就進工單與檔名 | `Get-PsSuppRequests` intake 驗證（id＝檔名、schemaVersion、domain 文法、generation、need 值域、workKey 重算）；拒收列在 log |
| 24 | 情境 34 讀 .gitignore（不在搬運集合） | 檔不存在＝跳過並印 SKIP |

被駁回但順手修掉（成本低、不改行為）：`[regex]::Replace` 改實例 Replace(count)；暫存檔清掃擴到領域／wiki／supplemental；JSON escaper 改 regex＋List；
Get-Date 規則改寫＋`ToString('日期格式')` 警告；目標 NN 位元組比對還原；`Restore-PsSuppBytes` 原子；`DOMAIN_MISSING`；auto-all 不重複計數；
Invoke-GitSnapshot 只 commit 有暫存檔的路徑；`limit` 直接用＋只檢查首行前綴；`/ps-supplement` 第 0 步先於 read 工單；空表與格內直線規則；
`[|] 物件 [|]` pattern；索引「節」欄用實際標題名；續篇另欄；合成識別字守衛去掉非合成名。

另外在寫測試時抓到一類新陷阱：`return , $arr` 的函式被 `@(函式 …)` 直接包住時，空陣列會數成 1（`@(f)` 得到 `@(@())`）——
auto-all／auto-loop 三處改「先指派再 @()」，test-ps51-static 新增 BLOCK 規則。

### 11.2 Spec 引擎（28 項提出、13 項兩名 refuter 都確認：行號漂移 ×3、零單位 render ×2、規劃時等級、RECORD hashAfter、Get-PsSpProp、時間戳、gate 指標、factKind、歷史收據、拆分回傳；其餘 15 項被駁回但一併修掉）

| # | 發現 | 修法（落點） |
|---|---|---|
| 1／7／13 | 派工用規劃時行號切片與標條目，指紋卻不含行號：讀取集合外插一行＝條目標錯、片段照樣驗收、收據被重用 | `Get-PsSpLiveInput` 依現況文字重定位每個條目（同節 hash 必須相同、行仍在該節條目集合內），切片／工單／input.json／驗收全用重定位後的清單；對不上＝SOURCE_CHANGED 不派 |
| 2／11 | 零單位 COMPOSE requirement 讓 -Render 崩潰（`@($null)`） | `ContainsKey`；7-11 c=NONE 可達 |
| 3 | gate 用規劃時等級 | -Run／-Render／-Gate 先重建 STALE 索引；`Test-PsSpSources` 回 LiveGrades；低於政策 → `7-22 GRADE_DROPPED`（SPEC_PARTIAL） |
| 4 | RECORD need 每次 -Plan 重送新世代 | `Resolve-PsSpNeed` 比對 `result.affected[].hashAfter` 與該檔現況；未變＝BLOCKED_KNOWLEDGE 不重送 |
| 5 | callee 角色子字串比對 | 開頭比對（同 `Get-PsSuppCallees`） |
| 6 | 身分 need 無 plan | `New-PsSpNeedOnlyPlan`：提交 need 並寫 WAITING_KNOWLEDGE plan；-Run 5-01／5-06；result 到達後 -Plan 換 planHash |
| 8 | `Get-PsSpProp` 管線展開 | `return , $value`；空清單＝FALSE；所有 `@(Get-PsSpProp …)` 改先指派 |
| 9 | CONTEXT_OVERFLOW 當一般無效 attempt | 容量事件：拆分、不計 attempt |
| 10 | PS7 job.json 時間戳文化格式 | `Write-PsSpJob` 以 `Get-PsKnUtcStamp` 序列化 `[datetime]` |
| 12 | -Gate 不更新 current.json | gateGeneration／gateVerdict／gateHash 指標 |
| 14 | 指紋不含 factKind | `Get-PsSpFingerprint -FactKind`；收據匹配也比 factKind |
| 15 | 歷史收據全被當 SOURCE_CHANGED | 只看現行 plan 各單位綁定的收據；PENDING／BLOCKED 不算 |
| 16 | phase 卡 RUNNING | 每條離開路徑寫回相位；CLI try／finally |
| 17 | NN 讀兩次 | `Get-PsKnNnFacts -Text` 單次讀 |
| 18 | 拆分寫檔回傳沒看；create-only `$null` | 所有寫入點分辨 `$null`（延後）與 `$false`；延後 → `3-07-n` 停止不重派、plan 延後 → 2-07 |
| 19 | PARTIAL 片段當終局收據 | `4-07 PARTIAL_SPLIT`：已處置條目成 part＋收據（COMPLETE），其餘拆新 part 重派；兩表皆空＝`NO_COVERAGE`（計 attempt） |
| 20 | 詞彙表形狀驗收拒收 | parser 收 `#k`、`a;b`、`檔#E3`、路徑前綴檔名、`NOT_APPLICABLE`；工單印字面範例列 |
| 21／27／23／28／24／26 | worker 圍欄涵蓋整個 job 樹、worktree 相對前綴、websearch 等未關 | tools 補關 list／patch／websearch／skill／todowrite／lsp（1.18.29 沒有 codesearch／todoread）；read `*.ps-runtime/spec/*/attempts/*`、edit `*.ps-runtime/spec/*/attempts/*/fragment.md`，寬 pattern 移除 |
| 22 | -RuntimeRoot 在 repo 外 worker 全 deny | 派真 worker 時 RuntimeRoot 必須＝`<Root>/.ps-runtime/spec`，否則 `9-07` |
| 25 | 派工前不檢查容量 | 條目數＋7 > 150 直接拆分、不派 session |

### 11.3 修正 diff 的第二輪（六鏡頭 find 與 refuter 全用 Opus；19 項提出、14 項確認 → 6 件事）

| 件 | 發現 | 裁決／修法 |
|---|---|---|
| A | 已合併未發布的復原只認檔案 hash 沒動；同 run 兩張 request 打同一 NN → 第一張不發布、下次重派、雙重合併 | 同 run 同 NN 只合併一張；已合併 attempt 永不重派——`Test-PsSuppMergePresent`（收據的證據參照與事實敘述仍在 NN）成立就發布（hash 移動用現況 hash），不成立（被回捲）才重派 |
| B | 圍欄把 session 期間別的行程合法建立的 request／result 當違規刪掉（`ps-spec -Plan`、`ps-supplemental -Submit` 不取 session slot） | requests／results 新增檔先過 `Test-PsSuppRequestFile`／`Test-PsSuppResultFile`（與 intake 共用）：合格留著不算違規、不合格刪；既有檔改寫／刪除仍還原；wiki 不變 |
| C | Invoke-GitSnapshot 拿 git 印出的檔名比前綴，core.quotepath 讓中文路徑永遠比不中 → 快照靜默停止（blocker） | 逐候選路徑 `git diff --cached --name-only -- <path>` 判有無輸出，不解析檔名；情境 34 用中文目錄的真 git repo 回歸 |
| D | `Get-PsSpProp` 改 `return ,` 後漏改 `Test-PsSpPack` 的管線呼叫：≥2 個 checklistRefs 的需求包一律 SPEC1-1-03（blocker） | 先指派再 foreach；pack-b 範例與測試加雙 checklistRefs；靜態守衛新增「comma-return 函式接管線」BLOCK |
| E | 契約「第一行必須以 `## ` 開頭」對不上 read 真實輸出（`<content>` 後每行 `行號: ` 前綴；自 1.18.29 binary 核對） | 契約／orchestrator／test-scenarios 改成去掉前綴後的第一個內容行，且行號須等於 offset |
| F | ENTITY.DETAIL 規劃只看 wiki 等級、gate 的 LiveGrades 混入 NN 等級 → 首次 -Gate 誤報 7-22 且無法消除 | LiveGrades 對 ENTITY.DETAIL 只採 WIKI 來源；情境 21 |
| G | 掃除非合成名時把它原文寫進 HANDOFF | 改寫敘述；合成識別字守衛擴到 HANDOFF／docs/design／auto-loop 腳本與測試 |

駁回 5 項不採（復原只讀最後一個 attempt 的 outcome、Evidence 附錄前綴規則、`/ps-supplement` 的 `｜` 禁令、worker 跨 attempt 圍欄 ×2）；其中 `/ps-supplement` 的分格例外順手補上。

## 12. Template 綁定改為標題綁定（headings）

原設計要人在 Template 插 `{{slot:Sxx}}`；管理者指出 Template 已有自帶意義的 `{{…}}` 參數與引導式佔位符、章節也已定好，要填的是章節底下的內容。
裁決：`bindingMode: headings`——slot＝章節標題（必須唯一）＋（可選）章節內恰一次出現的原生佔位符；有佔位符就取代、沒有就補在章節末；
文件參數 `placeholders: [{text, fact}]` 有值就代入、無值保留並在 trace 列 待人工；其他 `{{…}}` 不動；headings 模式禁止 `{{slot:`。
綁定 hash 含 bindingMode／標題／佔位符，綁定一改就等同模板改版。`-InitPack` 從 Template 掃標題與佔位符產骨架（一節恰一個佔位符才自動綁，
兩個以上留給人決定）。`{{slot:Sxx}}`（markers）保留給合成範例與相容。結論碼與 drill 永不印標題或佔位符文字。
