# ps-auto-loop.ps1 — research→audit→lint 自動迴圈駕駛
# 設計：確定性外環（本腳本）＋模型內步（opencode run 新鮮 session）＋確定性驗收（lint／checklist 解析）
# 用法：.\scripts\ps-auto-loop.ps1 -Domain 轉職
#       .\scripts\ps-auto-loop.ps1 -Domain 轉職 -MaxCycles 12 -Model "provider/model-id"
#
# opencode headless 事實（v1.17.15 原始碼確認）：
#   - run 訊息裡的 "/指令" 不展開（slash 只在互動編輯器）——用 --command <名> 帶入，
#     訊息成為 $ARGUMENTS；command frontmatter 的 agent/model 生效
#   - 【L60 更正，原註解是錯的】不加 --auto **不會**自動拒絕 ask 類權限——
#     headless 沒有 TTY 可以回答，權限詢問會**永遠阻塞**直到逾時強殺，
#     而且提示畫在 TTY 上、stdout/stderr 重導後在 log 裡完全看不到。
#     opencode 只有兩個權限預設是 "ask"：doom_loop（重複的相同工具呼叫）
#     與 external_directory（專案目錄外的路徑），其餘預設 "allow"。
#     TUI 上點「always allow」**只在該互動 session 內有效、不落檔**，
#     所以 headless 每次開新 session 都會再撞一次。
#     → 無人看管的前提：在**本機全域** opencode.json 的 permission 區塊
#       把這兩個明確設成 allow／deny（見 SOP-17）；不要用 --auto 一次全開，
#       那會連 agent tools 以外的 ask 類一併放行。
#   - exit code：0＝正常收場、1＝session 錯誤；最終回覆進 stdout、裝飾與錯誤進 stderr
#
# 停機條件（七保險絲）：
#   畢業（三層門全過，見下）／連續 2 圈無進度／連續 2 次逾時／
#   連續 2 次 session 錯誤／強殺後檔案一致性 FAIL／
#   audit 相位連續 2 圈零回灌未畢業（活鎖熔斷）／圈數上限
# 兩段式畢業（tier）——廣度優先，避免「一個領域追完美、其餘領域停在零」：
#   -Tier 1（預設）＝**覆蓋畢業／可用（80 分）**：功能查得到、每份文件有實質
#     內容、無明顯錯誤。門＝SESSION_OK＋WORK_TRANSITION_OK＋COVERAGE_OK
#     （lint -CoverageOnly 全過）。**不要求未勾=0、不要求 StrictAudit**——
#     稽核回灌的補強項留著（SOP-13：A 項是建議不是債），不擋出貨。
#   -Tier 2＝**精修畢業（100 分）**：現行三層門原封不動（未勾=0＋lint 全綠＋
#     StrictAudit 全綠）。批次先讓所有領域到 tier 1，再回頭做 tier 2。
# 畢業三層門（issue #2：模型說自己做完不算，只有 observable state transition 才算）：
#   SESSION_OK＝audit session 正常收場（exit 0）
#   WORK_TRANSITION_OK＝稽核輪次遞增＋90-audit.md hash 改變
#     （快照緊貼 audit session 前後——不得跨過手術 session：ps-deep-research
#      在 checklist 全勾時可能於手術 session 內自行接跑稽核，跨步驟比對會污染）
#   VALIDATION_OK＝lint 全過＋StrictAudit 全過（結果落 strict-cycle<N>.txt）
# 人的位置：lesson、correct、PR 審核照舊人工；本腳本只驅動內容生產，早上看 log 摘要即可。
param(
    [Parameter(Mandatory = $true)][string]$Domain,
    # 1＝覆蓋畢業（可用／80 分，預設）；2＝精修畢業（現行三層門）
    [ValidateSet(1, 2)][int]$Tier = 1,
    [int]$MaxCycles = 20,
    # 一圈最多連跑幾批手術（L58）：只要每批都讓手術清單變短就繼續，
    # 免得每修 7 筆就先燒一個稽核 session。真正的收斂煞車是下方「本批沒讓
    # 清單變短就停」；本上限只是時間圍欄（最壞 MaxSurgeryPerCycle×
    # ResearchTimeoutMin 分）。
    [int]$MaxSurgeryPerCycle = 3,
    # 一批塞幾筆工單（L70）：原本硬編碼 7——44 筆工單＝7 批，一圈只給 3 批，
    # 要 3 圈才清得完，而圈 2／圈 3 的前置 session 對清工單零貢獻。
    [int]$SurgeryBatchSize = 7,
    # Domain Gate 保險絲（issue #12／L104）：單輪稽核新增 D 項超過此數＝
    # 疑似 scope creep（共用表反查沿依賴圖外擴）——停機要求人工 scope
    # review。數量上限只是熔絲，不是 Domain Gate 的替代品（gate 在稽核
    # 契約：DOMAIN_ROOT 才准成 D）。
    [int]$MaxNewDPerAudit = 10,
    # 分批稽核（issue #22／L107）：每個稽核 session 處理幾個 NN 檔（parent 分批）
    [int]$AuditBatchSize = 6,
    # 單檔任務 A 每次委派驗幾筆 Evidence（子代理分頁）——實測 37 列即爆、p95=26、
    # 中位 12：從中位以下起跳，溢出自動對半（最小 3），到底 BLOCKED 點名
    [int]$AuditEvidencePageSize = 10,
    # 一圈最多跑幾個稽核批次（0＝跑完整輪）——時間圍欄；未跑完的批次下圈續跑
    [int]$AuditBatchesPerCycle = 0,
    # 單一稽核批次的逾時（分）：批次小、沿用 L48 沉默基線 30 分的兩倍
    [int]$AuditBatchTimeoutMin = 60,
    # 逾時＝熔絲不是效能參數，照實測基線設（L48）：research 曾在 30 分上限被
    # 強殺（＝上限訂太緊，把健康的 session 砍掉），放寬到 60 分後未再撞上限。
    # 注意手術 session 沿用 ResearchTimeoutMin，改這個值等於同步放寬手術上限；
    # 批次單領域最壞＝MaxCycles×(AuditTimeoutMin＋ResearchTimeoutMin×
    # MaxSurgeryPerCycle) 分，要硬圍欄改用 -MaxCyclesPerDomain。
    [int]$ResearchTimeoutMin = 60,
    # audit 上限刻意設寬（L59）：實測 34 分→>60 分被強殺，且**強殺當下輸出
    # 仍在增加**＝不是卡死，是稽核量隨檔案數成長。真實時長目前**不知道**
    # （被殺掉了量不到），所以先設 120 分**把它跑完、量出來**，拿到完成
    # 時長之後再照實測 ×1.5 收斂。設寬的成本是「壞掉時多等一小時」，
    # 設窄的成本是「永遠不知道要多久，而且每輪白燒」。
    [int]$AuditTimeoutMin = 120,
    [string]$Model = "",           # 留空＝opencode 全域預設；填 provider/model-id 可覆寫本次
    [switch]$Preflight,            # 只檢查環境／相位／lint／收據並列印，不啟動 session、不取鎖
    # 每圈結束 commit 一次該領域目錄（L83）：session 崩在半路是這個系統的
    # 常態故障，有還原點才敢讓它無人看管。**只 commit、永不 push**。
    [switch]$GitCommit
)

# ── 參數消毒（L28）：尾部空白/點＝Win32 假缺檔陷阱；隱形字元直接拒跑 ──
$rawDomain = $Domain
$Domain = $Domain.Trim().TrimEnd('.', ' ')
if ($Domain -cne $rawDomain) {
    Write-Host "WARN：-Domain 參數頭尾含空白/點，已自動修剪" -ForegroundColor Yellow
}
foreach ($ch in $Domain.ToCharArray()) {
    $cp = [int]$ch
    if ($cp -lt 32 -or $cp -eq 127 -or $cp -eq 0x00A0 -or
        ($cp -ge 0x200B -and $cp -le 0x200F) -or $cp -eq 0xFEFF) {
        Write-Error "-Domain 參數含隱形字元（字元碼 $cp）——用鍵盤重新輸入"; exit 2
    }
}

# ── 環境解析 ────────────────────────────────────────────────
$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path $root (Join-Path "docs/ps-research" $Domain)
$lintPath = Join-Path $PSScriptRoot "ps-doc-lint.ps1"
$logRoot = Join-Path $root (Join-Path "auto-loop-logs" $Domain)
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$logFile = Join-Path $logRoot "auto-loop.log"

# opencode 可執行檔（L46）：**必須挑 .cmd/.exe/.bat 型 shim**。
# npm 同時裝 opencode / opencode.cmd / opencode.ps1；PowerShell 的 Get-Command
# 會優先回 **.ps1**（它把 .ps1 當一等公民）——把 .ps1 丟給 cmd.exe 不會執行，
# Windows 會用「檔案關聯」開啟它＝**跳出記事本並阻塞**，關掉後 cmd 回 exit 0，
# 外環誤判 session 正常結束 → 整圈空轉、完全沒有 session 真的跑過。
function Select-OpencodeShim {
    param($Candidates)
    foreach ($ext in @('.cmd', '.exe', '.bat')) {
        foreach ($c in $Candidates) {
            if ($c.Source -and $c.Source.ToLowerInvariant().EndsWith($ext)) { return $c.Source }
        }
    }
    return $null
}
$ocAll = @(Get-Command opencode -All -ErrorAction SilentlyContinue)
if ($ocAll.Count -eq 0) { Write-Error "PATH 找不到 opencode"; exit 2 }
$ocPath = Select-OpencodeShim -Candidates $ocAll
if (-not $ocPath) {
    Write-Error ("PATH 上的 opencode 是 " + $ocAll[0].Source + "（非 .cmd/.exe/.bat）——" +
        "cmd.exe 會用檔案關聯開啟它（記事本）而不是執行它。請確認 npm 的 opencode.cmd 在 PATH 上")
    exit 2
}

# ── 畢業收據共用邏輯（issue #3）——缺檔／版本不符要在取鎖前快炸，
#    不能拖到數小時後畢業瞬間才發現人工搬運不完整
$gradLibPath = Join-Path $PSScriptRoot "ps-graduation.ps1"
if (-not (Test-Path -LiteralPath $gradLibPath)) {
    Write-Error "缺 scripts/ps-graduation.ps1（人工搬運不完整？）"; exit 2
}
. $gradLibPath
if ($GraduationSchemaVersion -ne 2) {
    Write-Error "ps-graduation.ps1 版本不符（schemaVersion=$GraduationSchemaVersion，本腳本要求 2）——人工搬運不完整？"; exit 2
}

function Write-Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    Write-Host $line
}

# ── checklist 狀態解析（機械、不經模型）───────────────────
function Get-ChecklistState {
    $clPath = Join-Path $dir "checklist.md"
    if (-not (Test-Path $clPath)) {
        return @{ Exists = $false; Unticked = -1; Ticked = -1; Round = -1 }
    }
    $lines = Get-Content $clPath -Encoding UTF8
    $unticked = @($lines | Where-Object { $_ -match '^\s*-\s*\[ \]' }).Count
    $ticked = @($lines | Where-Object { $_ -match '^\s*-\s*\[[xX]\]' }).Count
    $round = -1
    foreach ($l in $lines) {
        if ($l -match '稽核輪次[：:]\s*(\d+)') { $round = [int]$Matches[1]; break }
    }
    return @{ Exists = $true; Unticked = $unticked; Ticked = $ticked; Round = $round }
}

# ── audit 狀態轉移快照（畢業門第 2 層：WORK_TRANSITION_OK）──────
# Round 正規化：checklist 缺「稽核輪次」行視為 0（與 ps-audit 契約「沒有該行
# 視為 N=0」對齊——外環用 -1 哨兵會造成首輪 off-by-one 誤判）；取「最後一個」
# 匹配（防模型追加新行未刪舊行時撈到舊值）；只認半形數字（全形數字 cast 會炸）。
# Hash：90-audit.md 不存在＝空字串（首輪合法狀態）；只用內容 hash、不用
# mtime（工具重存同內容、殭屍進程觸碰都會動 mtime）。
function Get-AuditTransition {
    $round = 0
    $clPath = Join-Path $dir "checklist.md"
    if (Test-Path $clPath) {
        foreach ($l in (Get-Content $clPath -Encoding UTF8)) {
            if ($l -match '稽核輪次[：:]\s*([0-9]+)') { $round = [int]$Matches[1] }
        }
    }
    $hash = ""
    $auditPath = Join-Path $dir "90-audit.md"
    if (Test-Path $auditPath) {
        $hash = (Get-FileHash -Path $auditPath -Algorithm SHA256).Hash
    }
    return @{ Round = $round; Hash = $hash }
}

# ── checklist＋歸檔分片的勾選項總數（一致性檢查用）──────────────
# 打勾項歸檔只會「移動」到 checklist-archive-r<N>.md、不會消失——
# 合併總數變少＝有項目在強殺中遺失。
function Get-ItemTotal {
    $total = 0
    $files = @()
    $clPath = Join-Path $dir "checklist.md"
    if (Test-Path $clPath) { $files += $clPath }
    $files += @(Get-ChildItem -Path $dir -Filter "checklist-archive*.md" -File -ErrorAction SilentlyContinue |
        ForEach-Object { $_.FullName })
    foreach ($f in $files) {
        $total += @(Get-Content $f -Encoding UTF8 | Where-Object { $_ -match '^\s*-\s*\[' }).Count
    }
    return $total
}

# ── checklist 完整性（L89）：**每個 session 之後都驗，不只強殺後**──
# 實案：乾淨退場（exit 0）的 session 把「## 調查進度」整節吃掉，第 56 輪
# 吃、57 輪別的 session 寫回、58 輪又吃——舊檢查只掛在強殺路徑上，
# 這種腐蝕閃爍了四輪才被人肉發現。判準兩條（皆機械）：
#   (1) checklist.md 存在則必含「## 調查進度」與「## Gaps」節標題；
#   (2) checklist＋全部 archive 的合併項目總數不得下降
#       （歸檔是搬移、FixArchive 刪流程標籤都在基準重取之後，不誤傷）。
function Test-ChecklistIntegrity {
    param([int]$PreTotal)
    $r = @{ Lost = @(); Cosmetic = @() }
    $clPath = Join-Path $dir "checklist.md"
    if (Test-Path $clPath) {
        $t = Get-Content $clPath -Raw -Encoding UTF8
        if ([string]::IsNullOrEmpty($t)) { $r.Lost += "checklist.md 空檔" }
        else {
            if ($t -notmatch '##\s*調查進度') { $r.Cosmetic += "「## 調查進度」節標題消失" }
            if ($t -notmatch '##\s*Gaps') { $r.Cosmetic += "「## Gaps 彙整」節標題消失" }
        }
        $now = Get-ItemTotal
        if ($now -lt $PreTotal) { $r.Lost += "項目總數下降 $PreTotal→$now（含歸檔合併計數）" }
    }
    return $r
}

# ── checklist 身分清點與確定性調帳（issue #6／L93）──────────────
# 原則：LLM 可以提出狀態變更，但不能當 durable state 的 transaction manager。
# 每個 session 前拍身分快照、session 後逐 id 對帳：合法去向只有「還在活頁」
# 或「已搬進歸檔」；兩邊都沒有＝silent loss，由本層直接補回——不停機、
# 不等下一個 session 概率性自癒。總數比對抓不到「掉一補一」，身分比對抓得到。
# 身分錨點優先序：工單編號（A/U/D）→ 列內 NN 檔名 → 正規化文字 hash
# （hash 是最後手段：列被改寫會誤判成消失＋新增，錨點型不會）。
function Get-RowIdentity {
    param([string]$Row)
    $m = [regex]::Match($Row, '^\s*-\s*\[[ xX]\]\s*([AUDaud]\d+-\d+)')
    if ($m.Success) { return 'wo:' + $m.Groups[1].Value.ToUpperInvariant() }
    $m = [regex]::Match($Row, '(\d\d-[^\s（）()：:]+\.md)')
    if ($m.Success) { return 'nn:' + $m.Groups[1].Value.ToLowerInvariant() }
    $norm = $Row -replace '^\s*-\s*\[[ xX]\]\s*', ''
    $norm = $norm -replace '⚠.*$', ''
    $norm = (($norm -replace '\s+', ' ')).Trim().ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($norm))
    $sha.Dispose()
    return 'hash:' + ((@($bytes | ForEach-Object { $_.ToString('x2') })) -join '').Substring(0, 16)
}

# 復活防衛（L96）：身分消失 ≠ 列遺失——session 可能把工單列「改寫」成
# 別的格式（打勾時重寫文字／改編號）。改寫的列，其錨點（工單編號、
# NN 檔名、物件名）仍會出現在活頁某處；真被吃掉的列什麼都不剩。
# 只有「所有錨點都消失」才准補回，否則補回＝跟模型拔河＝重複列與
# 假性無進度（D63 實案：一勾一未勾並存、未勾 3→3 卡死）。
function Test-RowStillRepresented {
    param([string]$Row, [string]$ActiveRaw)
    $anchors = @()
    $m = [regex]::Match($Row, '([AUDaud]\d+-\d+)')
    if ($m.Success) { $anchors += $m.Groups[1].Value }
    $m = [regex]::Match($Row, '(\d\d-[^\s（）()：:]+\.md)')
    if ($m.Success) { $anchors += $m.Groups[1].Value }
    $m = [regex]::Match($Row, '新發現\s+([^\s：:（(]+)')
    if ($m.Success) { $anchors += $m.Groups[1].Value }
    foreach ($a in $anchors) {
        if ($a.Length -ge 4 -and $ActiveRaw.IndexOf($a, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    return $false
}

function Get-ChecklistInventory {
    $inv = @{}
    $files = @()
    $clPath = Join-Path $dir "checklist.md"
    if (Test-Path $clPath) { $files += , @{ Path = $clPath; Loc = 'active' } }
    foreach ($af in @(Get-ChildItem -Path $dir -Filter "checklist-archive*.md" -File -ErrorAction SilentlyContinue)) {
        $files += , @{ Path = $af.FullName; Loc = $af.Name }
    }
    foreach ($f in $files) {
        $raw = Get-Content $f.Path -Raw -Encoding UTF8
        if ([string]::IsNullOrEmpty($raw)) { continue }
        foreach ($m in [regex]::Matches($raw, '(?m)^\s*-\s*\[[ xX]\]\s*.+$')) {
            $row = $m.Value.TrimEnd()
            $id = Get-RowIdentity -Row $row
            if (-not $inv.ContainsKey($id)) { $inv[$id] = @{ Raw = $row; Loc = $f.Loc } }
        }
    }
    return $inv
}

# session 後調帳＋骨架保證。骨架修復採**最小插入**：既有內容一字不動，
# 只插回消失的節標題／輪次行；補回的列進「## 調查進度」之後。
# 流程標籤列（任務 A/B/C、批次 N/M）不補——補回等於復活 lint 違規。
# checklist.md 整檔消失＝本函式不管（交回滾／停機路徑）。
function Invoke-ChecklistReconcile {
    param([hashtable]$PreInv, [int]$PreRound)
    if ($PreRound -lt 0) { $PreRound = 0 }
    $result = @{ Restored = 0; Rebuilt = @(); SkippedTransformed = 0; SkippedRepeat = 0; Deduped = 0 }
    $clPath = Join-Path $dir "checklist.md"
    if (-not (Test-Path $clPath)) { return $result }
    $post = Get-ChecklistInventory
    $raw = Get-Content $clPath -Raw -Encoding UTF8
    if ($null -eq $raw) { $raw = "" }
    $lost = @()
    if ($null -ne $PreInv) {
        # 復活斷路器（L96）：同一列補回過一次、又消失＝它在被 session 改寫，
        # 不是被吃掉——再補回就是無限拔河。台帳跨圈持久（logRoot 下）。
        $ledgerPath = Join-Path $logRoot "reconcile-restored.txt"
        $ledger = @{}
        if (Test-Path -LiteralPath $ledgerPath) {
            foreach ($l in @(Get-Content -LiteralPath $ledgerPath -Encoding UTF8)) {
                $t = $l.Trim(); if ($t -ne '') { $ledger[$t] = $true }
            }
        }
        foreach ($id in @($PreInv.Keys)) {
            if ($post.ContainsKey($id)) { continue }
            $row = [string]$PreInv[$id].Raw
            # 垃圾（流程標籤）不復活——但帶 A/U/D 編號或檔名錨點的列是
            # 合法工單（D 項來源常寫「任務C 反查」），不受此過濾（L96）
            $isWorkOrder = ($row -match '^\s*-\s*\[[ xX]\]\s*[AUDaud]\d+-\d+' -or
                            $row -match '\d\d-[^\s（）()：:]+\.md')
            if ((-not $isWorkOrder) -and ($row -match '(任務|task)\s*[ABC]|批次\s*\d+\s*[/／]\s*\d+')) { continue }
            if (Test-RowStillRepresented -Row $row -ActiveRaw $raw) { $result.SkippedTransformed++; continue }
            if ($ledger.ContainsKey($id)) { $result.SkippedRepeat++; continue }
            $lost += $row
        }
        if ($lost.Count -gt 0) {
            foreach ($rr in $lost) { Add-Content -Path $ledgerPath -Value (Get-RowIdentity -Row $rr) -Encoding UTF8 }
        }
    }
    $needWrite = $false
    if ($raw -notmatch '稽核輪次[：:]\s*[0-9]+') {
        $lines = @($raw -split "`r?`n")
        if ($lines.Count -gt 1 -and $lines[0] -match '^#\s') {
            $raw = (@($lines[0], '', ('稽核輪次：' + $PreRound)) + @($lines[1..($lines.Count - 1)])) -join "`r`n"
        }
        else {
            $raw = ('稽核輪次：' + $PreRound + "`r`n`r`n") + $raw
        }
        $result.Rebuilt += '稽核輪次行'
        $needWrite = $true
    }
    if ($raw -notmatch '(?m)^##\s*調查進度') {
        # 插在第一個勾選列之前（列本來就住這節下）；沒有勾選列就插檔尾
        $lines = @($raw -split "`r?`n")
        $newLines = @()
        $inserted = $false
        foreach ($ln in $lines) {
            if (-not $inserted -and $ln -match '^\s*-\s*\[[ xX]\]') {
                $newLines += '## 調查進度'
                $newLines += ''
                $inserted = $true
            }
            $newLines += $ln
        }
        if (-not $inserted) { $newLines += @('', '## 調查進度', '') }
        $raw = $newLines -join "`r`n"
        $result.Rebuilt += '調查進度節標題'
        $needWrite = $true
    }
    if ($raw -notmatch '(?m)^##\s*Gaps') {
        $raw = $raw.TrimEnd() + "`r`n`r`n## Gaps 彙整（隨深查更新）`r`n`r`n- （無）`r`n"
        $result.Rebuilt += 'Gaps 節標題'
        $needWrite = $true
    }
    if ($lost.Count -gt 0) {
        $lines = @($raw -split "`r?`n")
        $newLines = @()
        $inserted = $false
        foreach ($ln in $lines) {
            $newLines += $ln
            if (-not $inserted -and $ln -match '^##\s*調查進度') {
                foreach ($rr in $lost) { $newLines += $rr }
                $inserted = $true
            }
        }
        if ($inserted) {
            $raw = $newLines -join "`r`n"
            $result.Restored = $lost.Count
            $needWrite = $true
        }
    }
    # 同文重複列收斂（L96）：勾選列全文（含勾選框）完全相同＝零資訊損失
    # 才准刪——一勾一未勾、或編號同內容異的列**不動**（可能各有語意，
    # 留給 D 項防呆／人工裁決）。
    $dedupSeen = @{}
    $dedupLines = @()
    foreach ($ln in @($raw -split "`r?`n")) {
        if ($ln -match '^\s*-\s*\[[ xX]\]') {
            $key = $ln.Trim()
            if ($dedupSeen.ContainsKey($key)) { $result.Deduped++; $needWrite = $true; continue }
            $dedupSeen[$key] = $true
        }
        $dedupLines += $ln
    }
    if ($result.Deduped -gt 0) { $raw = $dedupLines -join "`r`n" }
    if ($needWrite) {
        [System.IO.File]::WriteAllText($clPath, $raw, (New-Object System.Text.UTF8Encoding($true)))
    }
    return $result
}

# ── D 項治理（issue #8／L99）：物件身分層的確定性防重 ─────────────
# 任務 C 的 diff 基準是凍結的功能地圖——後續新發現永遠不在基準內，
# 每輪都會被重新「發現」；而查重規則是模型自律（機率性），L98 的 lint
# 守衛又只是事後偵測。本層把「已知物件集」收進外環：模型寫的 D 列
# 一律視為**提案**，session 邊界上裁決——同物件已有 NN 檔或已有 D 列
# ＝重複提案，整列刪除；同號異物件＝重配號。無論模型守不守散文規則，
# 重複列活不過一個邊界。lint 的 L98 守衛降格為最後 assertion。
function Get-CanonicalObject {
    param([string]$Name)
    $n = $Name.Trim().ToLowerInvariant()
    $n = $n -replace '^ps_', ''
    return $n
}

function Invoke-DItemGovernance {
    $result = @{ Removed = 0; Renumbered = 0 }
    $clPath = Join-Path $dir "checklist.md"
    if (-not (Test-Path $clPath)) { return $result }
    $dRowPattern = '^\s*-\s*\[([ xX])\]\s*[Dd](\d+)-(\d+)\s[^\r\n]*?新發現\s+([^\s：:（(]+)'
    # KnownObjects＝NN 檔主物件（去編號、去續篇尾碼、去 PS_ 前綴、
    # 大小寫不敏感）＋歷史 D 列物件（active 已勾＋全部 archive，勾否皆算
    # ——歷史 D 列代表該物件已被受理過）
    $known = @{}
    $maxSeqByRound = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter "*.md" -File |
            Where-Object { $_.Name -match '^\d\d-' -and $_.Name -notmatch '^(00|90)-' })) {
        $m = [regex]::Match($f.Name, '^\d\d-(.+?)(-\d+)?\.md$')
        if ($m.Success) { $known[(Get-CanonicalObject $m.Groups[1].Value)] = 'NN 檔 ' + $f.Name }
    }
    foreach ($af in @(Get-ChildItem -LiteralPath $dir -Filter "checklist-archive*.md" -File -ErrorAction SilentlyContinue)) {
        $t = Get-Content $af.FullName -Raw -Encoding UTF8
        if ([string]::IsNullOrEmpty($t)) { continue }
        foreach ($m in [regex]::Matches($t, ('(?m)' + $dRowPattern))) {
            $k = Get-CanonicalObject $m.Groups[4].Value
            if (-not $known.ContainsKey($k)) { $known[$k] = '歸檔 D 列' }
            $rnd = [int]$m.Groups[2].Value
            $seq = [int]$m.Groups[3].Value
            if (-not $maxSeqByRound.ContainsKey($rnd) -or $seq -gt $maxSeqByRound[$rnd]) { $maxSeqByRound[$rnd] = $seq }
        }
    }
    $raw = Get-Content $clPath -Raw -Encoding UTF8
    if ($null -eq $raw) { return $result }
    $lines = @($raw -split "`r?`n")
    # 第一遍：活頁全部 D 列的編號上限；已勾 D 列的物件入已知集
    $seenIds = @{}
    foreach ($ln in $lines) {
        $m = [regex]::Match($ln, $dRowPattern)
        if (-not $m.Success) { continue }
        $rnd = [int]$m.Groups[2].Value
        $seq = [int]$m.Groups[3].Value
        if (-not $maxSeqByRound.ContainsKey($rnd) -or $seq -gt $maxSeqByRound[$rnd]) { $maxSeqByRound[$rnd] = $seq }
        if ($m.Groups[1].Value -ne ' ') {
            $rid = 'D' + $m.Groups[2].Value + '-' + $m.Groups[3].Value
            $seenIds[$rid] = $true
            $k = Get-CanonicalObject $m.Groups[4].Value
            if (-not $known.ContainsKey($k)) { $known[$k] = ('已勾 D 列 ' + $rid) }
        }
    }
    # 第二遍：未勾 D 列逐列裁決——重複物件刪、同號異物件重配號
    $out = @()
    $seenActive = @{}
    $changed = $false
    foreach ($ln in $lines) {
        $m = [regex]::Match($ln, $dRowPattern)
        if (-not $m.Success -or $m.Groups[1].Value -ne ' ') { $out += $ln; continue }
        $rid = 'D' + $m.Groups[2].Value + '-' + $m.Groups[3].Value
        $obj = $m.Groups[4].Value
        $k = Get-CanonicalObject $obj
        if ($known.ContainsKey($k) -or $seenActive.ContainsKey($k)) {
            $src = if ($known.ContainsKey($k)) { $known[$k] } else { ('本頁 D 列 ' + $seenActive[$k]) }
            Write-Log "D 項治理：刪除重複提案 $rid（$obj）——同物件已有 $src"
            $result.Removed++
            $changed = $true
            continue
        }
        if ($seenIds.ContainsKey($rid)) {
            $rnd = [int]$m.Groups[2].Value
            $newSeq = $maxSeqByRound[$rnd] + 1
            $maxSeqByRound[$rnd] = $newSeq
            $newId = 'D' + $rnd + '-' + $newSeq.ToString('00')
            $ln = ([regex]'[Dd]\d+-\d+').Replace($ln, $newId, 1)
            Write-Log "D 項治理：重號 $rid（$obj）→ $newId（同號異物件，各批未聯集先編）"
            $seenIds[$newId] = $true
            $seenActive[$k] = $newId
            $out += $ln
            $result.Renumbered++
            $changed = $true
            continue
        }
        $seenIds[$rid] = $true
        $seenActive[$k] = $rid
        $out += $ln
    }
    if ($changed) {
        [System.IO.File]::WriteAllText($clPath, ($out -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
    }
    return $result
}

# 跨檔同文去重（L103 追記二）：「歸檔＝搬移」的刪活頁半步由外環保證。
# 模型抄不搬已成慣性（88 列清完又生 11 列）——照 L101 哲學：誰能保證
# 做對誰修。只動**已勾**的活頁列（已完成列的家在歸檔）；活頁未勾×
# 歸檔已存＝「重開 vs 誤歸檔」歧義，留人工。刪除量進 LegitRemoved
# 記帳（L100），完整性守衛不誤報。
function Invoke-ArchiveDedup {
    $clPath = Join-Path $dir "checklist.md"
    if (-not (Test-Path -LiteralPath $clPath)) { return 0 }
    $arc = @{}
    foreach ($af in @(Get-ChildItem -LiteralPath $dir -Filter "checklist-archive*.md" -File -ErrorAction SilentlyContinue)) {
        $t = Get-Content -LiteralPath $af.FullName -Raw -Encoding UTF8
        if ([string]::IsNullOrEmpty($t)) { continue }
        foreach ($m in [regex]::Matches($t, '(?m)^\s*-\s*\[[ xX]\]\s*(.+?)\s*$')) { $arc[$m.Groups[1].Value] = $true }
    }
    if ($arc.Count -eq 0) { return 0 }
    $raw = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8
    if ([string]::IsNullOrEmpty($raw)) { return 0 }
    $removed = 0
    $keep = @()
    foreach ($ln in ($raw -split "`r?`n")) {
        $m = [regex]::Match($ln, '^\s*-\s*\[[xX]\]\s*(.+?)\s*$')
        if ($m.Success -and $arc.ContainsKey($m.Groups[1].Value)) { $removed++; continue }
        $keep += $ln
    }
    if ($removed -gt 0) {
        [System.IO.File]::WriteAllText($clPath, ($keep -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
        Write-Log "跨檔同文去重：活頁已勾且歸檔已存 $removed 列——外環補完「搬移」的刪活頁半步"
    }
    return $removed
}

# 歸檔所有權在外環（issue #13／L105）：模型只維護 checklist 列狀態與
# 輪次行；「已勾列 → checklist-archive-r<N>.md」的搬移由本函式單一負責。
# 順序＝先寫 archive、寫後逐列驗證、驗證全過才刪活頁——驗證失敗活頁
# 不動（舊態完整）；兩寫之間的崩潰窗留下跨檔重複，由 Invoke-ArchiveDedup
# 在下個調帳邊界確定性收斂——不需 journal 即達成「終態收斂」。
# 同輪重跑＝讀舊檔合併寫（外環沒有模型 write 的大檔限制；-FixArchive 同
# 先例）。搬移對 Get-ItemTotal 總數中性（兩檔合併計數），不動完整性基準。
function Invoke-ChecklistArchiveCommit {
    $clPath = Join-Path $dir "checklist.md"
    if (-not (Test-Path -LiteralPath $clPath)) { return 0 }
    $raw = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8
    if ([string]::IsNullOrEmpty($raw)) { return 0 }
    $mRound = [regex]::Match($raw, '稽核輪次[：:]\s*([0-9]+)')
    if (-not $mRound.Success) { return 0 }
    $round = [int]$mRound.Groups[1].Value
    $ticked = @()
    $keep = @()
    foreach ($ln in ($raw -split "`r?`n")) {
        if ($ln -match '^\s*-\s*\[[xX]\]\s*\S') { $ticked += $ln.TrimEnd() } else { $keep += $ln }
    }
    if ($ticked.Count -eq 0) { return 0 }
    $arPath = Join-Path $dir ("checklist-archive-r{0}.md" -f $round)
    $have = @{}
    $existing = @()
    if (Test-Path -LiteralPath $arPath) {
        foreach ($el in @(Get-Content -LiteralPath $arPath -Encoding UTF8)) {
            $existing += $el
            $t = ([string]$el).Trim(); if ($t -ne '') { $have[$t] = $true }
        }
    }
    $add = @($ticked | Where-Object { -not $have.ContainsKey($_.Trim()) })
    $arOut = @($existing) + $add
    [System.IO.File]::WriteAllText($arPath, ((($arOut | Where-Object { $null -ne $_ }) -join "`r`n").TrimEnd() + "`r`n"),
        (New-Object System.Text.UTF8Encoding($true)))
    $check = Get-Content -LiteralPath $arPath -Raw -Encoding UTF8
    foreach ($t in $ticked) {
        if ($check.IndexOf($t.Trim()) -lt 0) {
            Write-Log "歸檔 commit 驗證失敗：「$($t.Trim().Substring(0, [Math]::Min(40, $t.Trim().Length)))…」未落檔——活頁不動（舊態完整），下邊界重試"
            return 0
        }
    }
    [System.IO.File]::WriteAllText($clPath, ($keep -join "`r`n"),
        (New-Object System.Text.UTF8Encoding($true)))
    Write-Log "歸檔 commit（外環）：$($ticked.Count) 列已勾 → checklist-archive-r$round.md（寫後驗證通過，活頁同步刪除）"
    return $ticked.Count
}

# 統一調帳邊界（P0-4）：任何 session 之後都走這裡——log 有跡可查
function Invoke-PostSessionReconcile {
    param([hashtable]$PreInv, [int]$PreRound, [string]$Tag)
    $rec = Invoke-ChecklistReconcile -PreInv $PreInv -PreRound $PreRound
    if ($rec.Rebuilt.Count -gt 0) { Write-Log "CHECKLIST 骨架修復（$Tag）：$($rec.Rebuilt -join '、')——確定性重建，不停機不等自癒" }
    if ($rec.Restored -gt 0) { Write-Log "CHECKLIST 調帳（$Tag）：補回 $($rec.Restored) 列 silent loss（身分比對；總數比對抓不到掉一補一）" }
    if ($rec.SkippedTransformed -gt 0) { Write-Log "CHECKLIST 調帳（$Tag）：$($rec.SkippedTransformed) 列身分消失但錨點仍在活頁＝被改寫非遺失——不復活（session 不該改寫工單列文字，見 L96）" }
    if ($rec.SkippedRepeat -gt 0) { Write-Log "CHECKLIST 調帳（$Tag）：$($rec.SkippedRepeat) 列二次消失（上次已補回過）＝持續被改寫——斷路器生效，不再復活" }
    if ($rec.Deduped -gt 0) { Write-Log "CHECKLIST 調帳（$Tag）：收斂 $($rec.Deduped) 列同文重複" }
    # D 項治理（issue #8）：調帳之後、下個 session 之前裁決 D 提案——
    # 重複列活不過這個邊界（明細 log 由治理函式自己寫）
    $gov = Invoke-DItemGovernance
    # 合法刪列記帳（L100）：治理刪提案＋去重收斂都是**外環自己**的合法
    # 刪除，完整性守衛的基準必須同步下修——否則守衛把自家清潔工的
    # работу當竊案報（實案：第一圈治理刪重複 D 提案 → 總數下降 →
    # 誤判「列遺失」停機）。FixArchive 的基準重取是同款先例。
    $adx = Invoke-ArchiveDedup
    $rec.LegitRemoved = $rec.Deduped + $gov.Removed + $adx
    return $rec
}

# ── 手術佇列生命週期（issue #11／L102）─────────────────────────
# lint 永遠是「工單存在與否」的唯一真相；台帳只 overlay 生命週期
# metadata（attempts／blocked），且每次存檔即對 lint 現況剪枝——
# lint 已不出的工單不得被台帳「復活」。指紋＝去編號的工單文字
# （編號隨清單縮短漂移，不是身分）。
$surgeryLedgerPath = Join-Path $logRoot "surgery-ledger.json"

function Get-OrderFingerprint {
    param([string]$Line)
    $t = (($Line -replace '^\s*\d+\.\s*', '')).Trim()
    # 行號不是身分（L103）：工單文字帶「檔.md:行號」時，同檔任何其他編輯都會
    # 使行號漂移——舊指紋消失＋新指紋出現＝幻影 resolved（假進度）、attempts
    # 全數歸零，BLOCKED 永遠到不了（實案：15 筆卡 5 圈不動、台帳空白）。
    # [欄位] 型的「（行 a、b、c）」清單同理剝除；「N 列」數量是真實狀態
    # （只在實際修復或新增違規時變動），保留作為身分的一部分。
    # 只剝**半形冒號**行號——lint 的行號一律 `檔.md:120`；全形「：」是
    # 型別分隔符，後面可能緊跟計數（「27-TW_A.md：12 列」），吃掉它
    # 會把不同狀態的工單合流（自己的測試抓到）。
    $t = $t -replace '(\.md):\d+(?:-\d+)?', '$1'
    $t = $t -replace '（行 [^）]*）', ''
    return $t.Trim()
}

function Get-SurgeryLedger {
    if (-not (Test-Path -LiteralPath $surgeryLedgerPath)) { return @{} }
    try {
        $j = Get-Content -LiteralPath $surgeryLedgerPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $h = @{}
        foreach ($p in $j.PSObject.Properties) {
            $h[$p.Name] = @{ attempts = [int]$p.Value.attempts; blocked = [bool]$p.Value.blocked }
        }
        return $h
    }
    catch { return @{} }
}

function Save-SurgeryLedger {
    param($Ledger, [string[]]$CurrentSurgical)
    # 剪枝：lint 已不出的工單＝已解決，metadata 一併清（lint 是唯一真相）
    $current = @{}
    foreach ($ln in @($CurrentSurgical)) { $current[(Get-OrderFingerprint $ln)] = $true }
    $keep = @{}
    foreach ($k in @($Ledger.Keys)) {
        if ($current.ContainsKey($k)) { $keep[$k] = $Ledger[$k] }
    }
    $o = [ordered]@{}
    foreach ($k in ($keep.Keys | Sort-Object)) {
        $o[$k] = [pscustomobject]@{ attempts = $keep[$k].attempts; blocked = $keep[$k].blocked }
    }
    [System.IO.File]::WriteAllText($surgeryLedgerPath,
        (ConvertTo-Json ([pscustomobject]$o) -Depth 3),
        (New-Object System.Text.UTF8Encoding($false)))
    return $keep
}

# 選批跳過 BLOCKED（毒丸靠邊，後方健康工單照常服務——公平性保證）
function Select-SurgeryBatch {
    param([string[]]$Surgical, $Ledger, [int]$Size)
    $batch = @()
    foreach ($ln in @($Surgical)) {
        $fp = Get-OrderFingerprint $ln
        if ($Ledger.ContainsKey($fp) -and $Ledger[$fp].blocked) { continue }
        $batch += $ln
        if ($batch.Count -ge $Size) { break }
    }
    return , $batch
}

function Get-ActionableSurgicalCount {
    param([string[]]$Surgical, $Ledger)
    $n = 0
    foreach ($ln in @($Surgical)) {
        $fp = Get-OrderFingerprint $ln
        if (-not ($Ledger.ContainsKey($fp) -and $Ledger[$fp].blocked)) { $n++ }
    }
    return $n
}

# 自動復原（L90）：回滾整個領域目錄到上一圈快照＋清掉本圈新生的未追蹤檔
# ——本圈作廢（含正當寫入），換一圈重來。快照只在完整性通過後才拍，
# HEAD 恆為乾淨還原點。回 $true＝已回滾。
function Invoke-ChecklistRecovery {
    if (-not $GitCommit) { return $false }
    $tracked = (& git -C $root ls-tree -r HEAD -- "docs/ps-research/$Domain" 2>&1 | Out-String)
    if ([string]::IsNullOrWhiteSpace($tracked)) { return $false }
    & git -C $root checkout HEAD -- "docs/ps-research/$Domain" 2>&1 | Out-Null
    $untracked = @(& git -C $root ls-files --others --exclude-standard -- "docs/ps-research/$Domain" 2>&1 |
        Where-Object { $_ -and $_.ToString().Trim() -ne '' })
    foreach ($u in $untracked) {
        $up = Join-Path $root $u.ToString().Trim()
        if (Test-Path -LiteralPath $up) { Remove-Item -LiteralPath $up -Force }
    }
    Write-Log "已回滾 docs/ps-research/$Domain 至上一圈快照（清除本圈新檔 $($untracked.Count) 個）"
    return $true
}

# ── 檔案一致性檢查（強殺後執行；純唯讀，絕不觸發修復 session）────
# 原則：只驗「圈前存在的東西沒變壞」——新領域缺檔屬合法狀態（vacuous PASS），
# 首圈逾時不因此誤停。啟發式只採高置信訊號（缺檔／0 byte／項目總數減少／
# lint 無法執行）——「檔尾像截斷」這類過敏判定一律不做。
function Test-FsConsistency {
    param([bool]$HadChecklist, [int]$PreItemTotal)
    $problems = @()
    $clPath = Join-Path $dir "checklist.md"
    if ($HadChecklist) {
        if (-not (Test-Path $clPath)) { $problems += "checklist.md 消失" }
        elseif ((Get-Item $clPath).Length -eq 0) { $problems += "checklist.md 變成空檔（0 byte）" }
        else {
            $postTotal = Get-ItemTotal
            if ($postTotal -lt $PreItemTotal) {
                $problems += "checklist＋archive 勾選項總數減少（$PreItemTotal → $postTotal）——強殺疑似吃掉內容"
            }
        }
    }
    if (Test-Path $dir) {
        foreach ($z in @(Get-ChildItem $dir -Filter "*.md" -File | Where-Object { $_.Length -eq 0 })) {
            $problems += "空檔（0 byte）：$($z.Name)"
        }
        # lint 以「僅回報」身分跑一次驗證它自己能執行——exit 0/1 都算可執行
        # （FAIL 內容交給正常迴圈處理）；這裡絕不接手術路徑
        if (Test-Path (Join-Path $dir "00-overview.md")) {
            & $lintPath -Domain $Domain *> $null
            if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1) {
                $problems += "lint 無法正常執行（exit=$LASTEXITCODE）"
            }
        }
    }
    return , $problems
}

# ── NN 檔破壞防衛（L103）─────────────────────────────────
# session 可能整檔重寫 NN 檔並吃掉正典章節（實案：一檔被改到只剩不完整
# 的 Evidence 附錄，靠人工 git 才救回）。checklist 有完整性檢查與調帳層，
# NN 檔過去只有 0-byte 檢查——「有內容但被掏空」完全裸奔。
# 快照＝位元組層（原編碼原樣還原，不經解碼再編碼）；判定只採高置信訊號：
#   (a) session 前存在的 ## 級標題 session 後消失——規則禁刪固定節，
#       合法操作只增不減；比對前剝（gaps）尾註與空白，FixHeadings 類
#       的合法正規化不誤傷
#   (b) 原檔 ≥ 40 行且行數掉到 30% 以下（節標題還在、內容被掏空）
# 命中即還原該檔 session 前位元組——該 session 對本檔的改動作廢；工單
# 自然還在 → attempts 記帳 → 兩次即 BLOCKED 進人工清單，不會無聲循環。
# 90-audit.md 每輪全量重寫、checklist*.md 有自己的守備——都不在範圍。
function Get-NnHeadKeys {
    param([string]$Text)
    $keys = @{}
    foreach ($m in [regex]::Matches($Text, '(?m)^##[ \t]+(.+?)[ \t]*$')) {
        $k = $m.Groups[1].Value -replace '（gaps）|\(gaps\)', '' -replace '\s', ''
        if ($k -ne '') { $keys[$k] = $true }
    }
    return $keys
}

function Get-NnGuardSnapshot {
    $snap = @{}
    if (-not (Test-Path $dir)) { return $snap }
    # 歸檔檔也在防衛範圍（L103 追記，r60 實案：checklist-archive*.md 於
    # session 中整檔消失——調帳層只能把列復活回「活頁」這個錯的家，
    # 種下 88 列跨檔重複）。agent 禁改寫歸檔的硬規則給了乾淨判準：
    # session 視窗內歸檔檔只准長大（新增歸檔檔合法）——消失或變短＝違規。
    # FixArchive 的合法刪列跑在圈首快照之前，不誤傷。
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter "*.md" -File |
            Where-Object { ($_.Name -match '^\d\d-' -and $_.Name -ne '90-audit.md') -or
                           $_.Name -like 'checklist-archive*' })) {
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
        if ($null -eq $text) { $text = "" }
        $kind = if ($f.Name -like 'checklist-archive*') { 'archive' } else { 'nn' }
        $snap[$f.Name] = @{
            Bytes = $bytes
            Heads = (Get-NnHeadKeys $text)
            Lines = @($text -split "`n").Count
            Kind  = $kind
        }
    }
    return $snap
}

function Invoke-NnDestructionGuard {
    param($Snap, [string]$Tag)
    $restored = 0
    foreach ($name in @($Snap.Keys)) {
        $p = Join-Path $dir $name
        $before = $Snap[$name]
        $reason = $null
        if (-not (Test-Path -LiteralPath $p)) { $reason = "檔案消失" }
        else {
            $now = Get-Content -LiteralPath $p -Raw -Encoding UTF8
            if ($null -eq $now) { $now = "" }
            $nowLines = @($now -split "`n").Count
            if ($before.Kind -eq 'archive') {
                # 歸檔檔：session 視窗內只准長大（r60 實案）——變短即違規
                if ($nowLines -lt $before.Lines) {
                    $reason = "歸檔檔縮短（$($before.Lines)→$nowLines 行）——agent 禁改寫歸檔"
                }
            }
            else {
                $nowHeads = Get-NnHeadKeys $now
                $lost = @($before.Heads.Keys | Where-Object { -not $nowHeads.ContainsKey($_) })
                if ($lost.Count -gt 0) {
                    $reason = "正典節消失：$($lost -join '、')（$($before.Lines)→$nowLines 行）"
                }
                elseif ($before.Lines -ge 40 -and $nowLines -lt [int]($before.Lines * 0.3)) {
                    $reason = "整檔掏空（$($before.Lines)→$nowLines 行，節標題雖在）"
                }
            }
        }
        if ($reason) {
            [System.IO.File]::WriteAllBytes($p, $before.Bytes)
            Write-Log "破壞防衛（$Tag）：$name $reason——已還原 session 前內容，該 session 對本檔改動作廢"
            $restored++
        }
    }
    return $restored
}

# ── 容量事件標籤（issue #22／L106）──────────────────────────
# 子代理 context 溢出通常以 exit 0 收場（OpenCode 的 task 錯誤回給 parent
# 當工具結果，不進父行程 stderr）——只看 exit code 永遠看不到。不論 exit
# 都掃 out＋err 全文。這是**標籤不是判定**：無此字樣≠無溢出（Ollama 類
# 靜默截斷不報錯），完整性仍由 lint／StrictAudit 守。
function Get-SessionFailureKind {
    param([string]$OutFile, [string]$ErrFile)
    $pat = '(?i)context.?length|maximum context|context window|context_length_exceeded|truncating input|input (?:is )?too long'
    foreach ($f in @($OutFile, $ErrFile)) {
        if ($f -and (Test-Path -LiteralPath $f)) {
            $t = Get-Content -LiteralPath $f -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($t -and ($t -match $pat)) { return 'CONTEXT_OVERFLOW' }
        }
    }
    return 'NONE'
}

# ── 開一個新鮮 opencode session（逾時整樹強殺）────────────
# $ExtraArgs 例：'--command ps-research' 或 '--agent ps-deep-research'
# 注意：prompt 走 cmd.exe 命令列——內容禁用半形雙引號與 cmd 特殊字元
# （> < & | % ^），中文引號「」不受限；多行內容一律壓成單行。
function Invoke-Opencode {
    param([string]$ExtraArgs, [string]$PromptText, [int]$TimeoutMin, [string]$Tag)
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $outFile = Join-Path $logRoot ("{0}-{1}.out.txt" -f $stamp, $Tag)
    $errFile = Join-Path $logRoot ("{0}-{1}.err.txt" -f $stamp, $Tag)
    # 結束碼落檔（L49）：**不相信 Process 物件的 .ExitCode**——PowerShell 的
    # -PassThru 物件在只用 WaitForExit(ms) 等待時 .ExitCode 常為 $null，而
    # $null -eq 0 為 false ＝ 每個正常 session 都被判成錯誤（假的「連續 2 次
    # session 錯誤」停機、SESSION_OK 恆假＝永不畢業）。改讓 cmd 把 ERRORLEVEL
    # 寫進檔案——同框架哲學：**要可觀測的事實，不要 API 承諾**。
    $rcFile = Join-Path $logRoot ("{0}-{1}.rc.txt" -f $stamp, $Tag)
    $inner = '"' + $ocPath + '" run '
    if ($Model -ne "") { $inner += '--model "' + $Model + '" ' }
    if ($ExtraArgs -ne "") { $inner += $ExtraArgs + ' ' }
    $inner += '--title "auto-' + $Tag + '" '
    $inner += '"' + $PromptText + '" 1> "' + $outFile + '" 2> "' + $errFile + '"'
    # %^ERRORLEVEL% ＋ call：延後展開，取得的才是 opencode 的真實結束碼
    $inner += ' & call echo %^ERRORLEVEL% > "' + $rcFile + '"'
    Write-Log "SESSION($Tag) 啟動：$ExtraArgs ｜ $PromptText"
    $p = Start-Process -FilePath "cmd.exe" -ArgumentList ('/d /s /c "' + $inner + '"') `
        -WorkingDirectory $root -NoNewWindow -PassThru
    # L49：**必須先取用 .Handle** 把行程 handle 快取住，否則 -PassThru 物件在
    # 只用 WaitForExit(ms) 等待時，.ExitCode 會是 $null（PowerShell 已知行為）
    # ——而 $null -eq 0 為 false，等於「每個正常結束的 session 都被判成錯誤」，
    # 導致假的「連續 2 次 session 錯誤」停機，且 SESSION_OK 永遠假＝永不畢業。
    try { $null = $p.Handle } catch { }
    # 心跳（L46 附帶）：session 期間 opencode 輸出全被重導到檔案，console 會
    # 完全安靜——每 5 分鐘印一行「還活著＋已耗時」，同時累積真實耗時數據
    # 供調整 timeout（逾時是熔絲不是效能參數，要照實測值設）
    $sessStart = Get-Date
    $lastBeat = $sessStart
    $done = $false
    while (((Get-Date) - $sessStart).TotalMinutes -lt $TimeoutMin) {
        if ($p.WaitForExit(30000)) { $done = $true; break }
        if (((Get-Date) - $lastBeat).TotalMinutes -ge 5) {
            $mins = [int]((Get-Date) - $sessStart).TotalMinutes
            # 沉默停滯偵測（確定性、只警告不強殺）：輸出檔多久沒長大——
            # 「持續吐字」＝模型在生成；「久無新輸出」＝多半卡在工具呼叫
            # （實案：auditor 逐檔委派後靜止 30 分，疑 oracleMCP 通道死）
            $lastOut = $sessStart
            foreach ($lf in @($outFile, $errFile)) {
                if (Test-Path -LiteralPath $lf) {
                    $wt = (Get-Item -LiteralPath $lf).LastWriteTime
                    if ($wt -gt $lastOut) { $lastOut = $wt }
                }
            }
            $silent = [int]((Get-Date) - $lastOut).TotalMinutes
            # 門檻照**實測基線**設（L48）：委派期間 subagent 輸出不流到父行程
            # stderr，實測健康的 audit 沉默可達 30 分（總計 35 分完成）——
            # 門檻設 10 分會每次都叫，把真訊號淹掉。20 分才提、且措辭中性
            $note = if ($silent -ge 20) { "；輸出已靜止 $silent 分（委派期間長時間無輸出屬常態，實測健康可達 30 分；接近逾時上限仍無輸出才需依 SOP-12 查 oracleMCP 通道）" } else { "" }
            Write-Log "SESSION($Tag) 進行中…已 $mins 分（逾時上限 $TimeoutMin 分）$note"
            $lastBeat = Get-Date
        }
    }
    if (-not $done) { $done = $p.WaitForExit(1000) }
    if ($done) {
        # 無參數版：確保行程狀態與 ExitCode 完全就緒（配合上方 .Handle 快取）
        try { $p.WaitForExit() } catch { }
        try { $p.Refresh() } catch { }
    }
    if (-not $done) {
        & taskkill.exe /PID $p.Id /T /F 2>$null | Out-Null
        # 強殺當下就下判讀（L59）：使用者事後翻心跳行才能拼出「卡死 vs 跑得久」，
        # 而那兩種的處置完全相反——一個要查通道、一個要調上限。輸出檔的
        # mtime 是現成的可觀測事實，判讀寫在強殺那一行，不必事後考古。
        $killSilent = -1
        $lastOutK = $sessStart
        foreach ($lf in @($outFile, $errFile)) {
            if (Test-Path -LiteralPath $lf) {
                $wt = (Get-Item -LiteralPath $lf).LastWriteTime
                if ($wt -gt $lastOutK) { $lastOutK = $wt }
            }
        }
        $killSilent = [int]((Get-Date) - $lastOutK).TotalMinutes
        Write-Log "SESSION($Tag) 逾時 $TimeoutMin 分，已整樹強制結束（狀態在檔案，無損）"
        if ($killSilent -le 5) {
            Write-Log "SESSION($Tag) 判讀：強殺當下輸出仍在增加（靜止僅 $killSilent 分）＝**上限太短，不是卡死**——把 -$(if ($Tag -eq 'audit') { 'AuditTimeoutMin' } else { 'ResearchTimeoutMin' }) 調高後重跑，不要去查 MCP 通道"
        }
        elseif ($killSilent -ge 20) {
            Write-Log "SESSION($Tag) 判讀：輸出已靜止 $killSilent 分才被強殺＝**疑似卡在工具呼叫**——依 SOP-12 查 oracleMCP／模型服務通道，調高上限沒有用"
        }
        else {
            Write-Log "SESSION($Tag) 判讀：強殺當下靜止 $killSilent 分（介於兩者之間）——先看 out 檔尾端停在哪個步驟再決定調上限或查通道"
        }
        $fkT = Get-SessionFailureKind -OutFile $outFile -ErrFile $errFile
        if ($fkT -ne 'NONE') { Write-Log "SESSION($Tag) 容量事件：$fkT（out/err 含 context 溢出字樣）——逾時前已撞 context 上限，調時間無用；見 SOP-10 校正宣告 limit 與 L106" }
        return @{ TimedOut = $true; ExitCode = -1; ErrFile = $errFile; OutFile = $outFile; FailureKind = $fkT }
    }
    # 優先讀落檔的結束碼（可觀測事實），讀不到才退回 Process 物件
    $code = $null
    if (Test-Path -LiteralPath $rcFile) {
        $rcTxt = (Get-Content -LiteralPath $rcFile -Raw -ErrorAction SilentlyContinue)
        if ($rcTxt) {
            $rcTxt = $rcTxt.Trim()
            $parsed = 0
            if ([int]::TryParse($rcTxt, [ref]$parsed)) { $code = $parsed }
        }
    }
    if ($null -eq $code) {
        try { $code = $p.ExitCode } catch { $code = $null }
    }
    if ($null -eq $code) {
        # 仍讀不到＝環境層面拿不到結束碼；**視為 0（正常）並大聲記錄**——
        # 反向（視為錯誤）已實證會把健康的 run 誤停（L49）
        Write-Log "SESSION($Tag) 警告：ExitCode 讀不到，視為 0（正常結束）——若後續行為異常請回報此行"
        $code = 0
    }
    Write-Log "SESSION($Tag) 結束 exit=$code 耗時 $([int]((Get-Date) - $sessStart).TotalMinutes) 分，輸出：$outFile"
    $fk = Get-SessionFailureKind -OutFile $outFile -ErrFile $errFile
    if ($fk -ne 'NONE') { Write-Log "SESSION($Tag) 容量事件：$fk（out/err 含 context 溢出字樣；exit=$code 不代表沒事——子代理溢出多半 exit 0）——無此字樣≠無溢出；處置見 SOP-10／L106，不要只調 timeout" }
    return @{ TimedOut = $false; ExitCode = $code; ErrFile = $errFile; OutFile = $outFile; FailureKind = $fk }
}

# ── lint（在本 PowerShell 行程內呼叫，繼承現行執行環境）──
# ── 缺料分類（L75）：Preflight 與迴圈**共用這一份**───────────────
# 相位判斷曾經有兩份實作（迴圈改成三分類後 Preflight 還停在兩分法，
# 於是 Preflight 印 research、實際會走 audit——外環自己說謊）。
# 解析不到分類行時 AuditOnly／ManualOnly 皆為 0＝退回舊行為（fail-safe）。
function Get-CoverageBreakdown {
    param([string]$Raw)
    $total = 0; $auditOnly = 0; $manualOnly = 0
    $m = [regex]::Match($Raw, '(?m)^FAIL：(\d+) 項違規')
    if ($m.Success) { $total = [int]$m.Groups[1].Value }
    $m = [regex]::Match($Raw, '(?m)^AUDIT_ONLY：(\d+) 項')
    if ($m.Success) { $auditOnly = [int]$m.Groups[1].Value }
    $m = [regex]::Match($Raw, '(?m)^MANUAL_ONLY：(\d+) 項')
    if ($m.Success) { $manualOnly = [int]$m.Groups[1].Value }
    return @{ Total = $total; AuditOnly = $auditOnly; ManualOnly = $manualOnly
        Auto = ($total - $auditOnly - $manualOnly)
    }
}

# 歸戶儀表（L86）：lint 的 WIKI_MISSING 行——本領域 [[連結]] 無 entity 的數量。
# 舊版 lint 無此行＝回 0（不觸發提煉，fail-safe）。
function Get-WikiMissing {
    $l = Invoke-Lint
    $m = [regex]::Match($l.Raw, '(?m)^WIKI_MISSING：(\d+)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return 0
}

# -Strict＝畢業門專用（ps-doc-lint.ps1 -StrictAudit）：90-audit 結構性問題升 FAIL
# -Coverage＝覆蓋畢業門（tier 1）專用（ps-doc-lint.ps1 -CoverageOnly）：
#   只收缺料類違規，美工類（證據 id／機器參照／confidence／frontmatter）降警告
function Invoke-Lint {
    param([switch]$Strict, [switch]$Coverage)
    if (-not (Test-Path (Join-Path $dir "00-overview.md"))) {
        return @{ Exit = -1; Surgical = @(); Raw = "（領域尚未建立，略過 lint）" }
    }
    # L44：必須 *>&1（全流合併）——lint 用 Write-Host 輸出（information stream），
    # 2>&1 抓不到 → $raw 空 → 下方 PASS 防呆把每次成功誤判成 exit 3
    # （VALIDATION_OK 永遠假＝永遠畢不了業），工單擷取也永遠落空
    if ($Strict) { $raw = & $lintPath -Domain $Domain -StrictAudit *>&1 | Out-String }
    elseif ($Coverage) { $raw = & $lintPath -Domain $Domain -CoverageOnly *>&1 | Out-String }
    else { $raw = & $lintPath -Domain $Domain *>&1 | Out-String }
    $code = $LASTEXITCODE
    # 防呆：lint 若中途死亡未跑到 exit，$LASTEXITCODE 是上一個原生命令的殘值
    # ——exit 0 但輸出無 PASS 標記＝不得當通過
    if ($code -eq 0 -and $raw -notmatch 'PASS：') { $code = 3 }
    # 擷取手術清單（=== 標記之間的編號行）
    $surgical = @()
    # 標題兩版都認（L44：改 lint 輸出標題時漏改此處＝工單永遠擷取不到）
    if ($raw -match '(?s)=== (?:證據|手術式)修復指令.*?===(.*?)=== 指令結束 ===') {
        $block = $Matches[1]
        $surgical = @($block -split "`r?`n" | Where-Object { $_ -match '^\s*\d+\.\s' } |
            ForEach-Object { $_.Trim() })
    }
    return @{ Exit = $code; Surgical = $surgical; Raw = $raw }
}

# ── 啟動前檢查（-Preflight：唯讀、不啟動 session、不取鎖）────────
# 第一次跑或搬運後用它確認管線，10 秒內把「跑到一半才爆」的問題前移
if ($Preflight) {
    Write-Host "=== auto-loop 啟動前檢查（唯讀）===" -ForegroundColor Cyan
    Write-Host "領域目錄  ：$dir"
    Write-Host "opencode  ：$ocPath$(if ($ocAll.Count -gt 1) { "（PATH 上共 $($ocAll.Count) 個候選，已選 .cmd/.exe/.bat 型）" })"
    Write-Host "收據邏輯  ：$gradLibPath（schema=$GraduationSchemaVersion gate=$GraduationGateVersion）"
    $st = Get-ChecklistState
    if (-not $st.Exists) {
        Write-Host "checklist ：不存在（新領域——首圈會走 research 建檔）" -ForegroundColor Yellow
        $ph = "research（階段一建檔）"
    }
    else {
        Write-Host "checklist ：未勾=$($st.Unticked) 已勾=$($st.Ticked) 稽核輪次=$($st.Round)"
        $ph = if ($st.Unticked -gt 0) { "research（消化 $($st.Unticked) 個未勾項）" } else { "audit（全勾→直接進稽核）" }
    }
    $lc = Invoke-Lint -Coverage
    # tier 1 的相位不看未勾數，看「缺料還在不在」——且只看**自動修得動**的那份
    # （L72／L74：僅 audit 可修的與需人工的都不該把相位鎖在 research）
    $bd = Get-CoverageBreakdown -Raw $lc.Raw
    if ($Tier -eq 1) {
        if (-not $st.Exists) { $ph = "research（階段一建檔）" }
        elseif ($bd.Auto -gt 0) { $ph = "research（尚有 $($bd.Auto) 項自動可修的缺料）" }
        elseif ($bd.AuditOnly -gt 0) { $ph = "audit（自動項已清，剩 $($bd.AuditOnly) 項僅 audit 修得了）" }
        elseif ($bd.ManualOnly -gt 0) { $ph = "**不會啟動**（剩 $($bd.ManualOnly) 項需人工——見下方 MANUAL_ONLY，處理完再跑）" }
        else { $ph = "audit（缺料已清→可爭取覆蓋畢業）" }
    }
    Write-Host "目標等級  ：tier $Tier（$(if ($Tier -eq 1) { '覆蓋畢業／可用 80 分' } else { '精修畢業／100 分' })）" -ForegroundColor Green
    Write-Host "起始相位  ：$ph" -ForegroundColor Green
    $l = Invoke-Lint
    Write-Host "lint      ：exit=$($l.Exit)（0=全過 1=有違規 -1=領域未建立）｜工單 $($l.Surgical.Count) 筆"
    Write-Host "CoverageOnly：exit=$($lc.Exit)（tier 1 畢業門用：0=缺料已清）｜tier 1 工單 $($lc.Surgical.Count) 筆"
    Write-Host "缺料分類  ：共 $($bd.Total) 項＝自動 $($bd.Auto)／僅 audit 可修 $($bd.AuditOnly)／需人工 $($bd.ManualOnly)（相位只看『自動』那份）"
    $ls = Invoke-Lint -Strict
    Write-Host "StrictAudit：exit=$($ls.Exit)（tier 2 畢業門用；tier 1 不看）"
    $rc = Test-GraduationReceipt -DomainDir $dir -Domain $Domain `
        -LintScriptPath $lintPath -GateScriptPath $gradLibPath -RequiredTier $Tier
    Write-Host "現有收據  ：$(if ($rc.Valid) { "有效（本領域已達 tier $Tier，跑下去會重驗）" } else { $rc.Reason })"
    Write-Host "熔絲設定  ：MaxCycles=$MaxCycles｜research 逾時 $ResearchTimeoutMin 分｜audit 逾時 $AuditTimeoutMin 分"
    Write-Host "手術節流  ：一批 $SurgeryBatchSize 筆 × 一圈 $MaxSurgeryPerCycle 批＝本圈最多 $($SurgeryBatchSize * $MaxSurgeryPerCycle) 筆"
    Write-Host "git 快照  ：$(if ($GitCommit) { '開（每圈 commit 該領域目錄，永不 push）' } else { '關（加 -GitCommit 開啟）' })"
    Write-Host "log 位置  ：$logRoot"
    Write-Host "=== 檢查結束（未啟動任何 session）===" -ForegroundColor Cyan
    exit 0
}

# ── git 快照（L83）：每圈一個可回溯的還原點 ─────────────────────
# **只 commit，永不 push**——研究產出是公司機密，嚴禁外部 remote。
# 範圍**限定該領域目錄**：工作樹裡常有人工搬運中的腳本，`git add -A` 會掃進去。
# 收據（graduation.json）與 auto-loop-logs 已在 .gitignore，不會被帶入。
# git 不可用／未設 user.name／commit 失敗一律**只記 log 不中斷**——
# 快照是加值，不該變成新的停機原因。
function Invoke-GitSnapshot {
    param([string]$Note)
    if (-not $GitCommit) { return }
    try {
        $rel = "docs/ps-research/$Domain"
        $relWiki = "docs/ps-research/wiki"
        & git -C $root add -- $rel $relWiki 2>&1 | Out-Null
        $staged = (& git -C $root diff --cached --name-only -- $rel $relWiki 2>&1 | Out-String)
        if ([string]::IsNullOrWhiteSpace($staged)) { return }
        $n = @($staged -split "`r?`n" | Where-Object { $_.Trim() -ne '' }).Count
        $msg = "kb(auto): $Domain $Note"
        $out = (& git -C $root commit -m $msg -- $rel $relWiki 2>&1 | Out-String)
        if ($LASTEXITCODE -eq 0) { Write-Log "GIT 快照：$msg（$n 檔）" }
        else { Write-Log "GIT 快照失敗（不中斷）：$($out.Trim())" }
    }
    catch {
        Write-Log "GIT 快照例外（不中斷）：$($_.Exception.Message)"
    }
}

# ── 自動化互斥鎖（issue #3）──────────────────────────────────
# 擋「兩個自動迴圈同時跑」（共享 wiki／oracleMCP／working tree）。
# 批次由 ps-auto-all 以**子行程**逐領域呼叫本腳本——行程死亡時 OS 自動
# 回收鎖（前任死亡＝AbandonedMutexException＝視為取得），無 stale lock。
# 互動式 OpenCode 問答不經此鎖，靠 SOP-12／SOP-14 操作紀律。
# exit code 語意：0 畢業（收據已寫）／1 未畢業／2 環境或收據錯誤／3 鎖被占用
$mutex = $null
$mutexHeld = $false
try {
    $mutex = New-Object System.Threading.Mutex($false, 'Global\MCPSample-PeopleSoftResearch')
    try { $mutexHeld = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $mutexHeld = $true }
}
catch { $mutexHeld = $false }   # UnauthorizedAccessException 等一律歸「拿不到」
if (-not $mutexHeld) {
    Write-Log "自動化互斥鎖被占用——另一個 ps-auto-loop／批次正在執行，本次拒跑（exit 3）"
    Write-Error "自動化互斥鎖被占用：錯開時間再跑（不是環境損壞）"
    if ($null -ne $mutex) { $mutex.Dispose() }
    exit 3
}

# ── 分批稽核（issue #22／L107）：manifest／收據／合併器／回合驅動 ──────
# 爆點（實測）：auditor 單檔任務 A 的**輸入側**——Evidence 列數×每筆完整
# chunk 內文×失聯筆二次定位；37 列即爆、p95=26、中位 12；rc=1 分不清
# parent 是否也爆。serving 真值拿不到 → **自校準**：頁大小從中位以下起跳，
# 失敗才縮；K 檔／session 分批讓 parent 也有上限。
# 所有權：外環凍結本輪工作（manifest，模型唯讀）→ session 只寫
# audit-parts/part-<i>.md → 外環驗不變量（合計＝列數、範圍覆蓋、明細 id⊆
# 附錄）發**檔級收據** → 收據齊備才由外環合併 90-audit.md、機械產 A／D 列、
# 遞增輪次、翻旗標。溢出＝容量事件：K 對半、單檔頁對半、到底 BLOCKED
# 點名——不 binary split、不原樣重跑。中途崩潰：輪次未遞增、收據持久，
# 下圈只補缺檔。
$auditLedgerPath = Join-Path $logRoot "audit-ledger.json"
$auditPartsDir = Join-Path $dir "audit-parts"
# manifest 放領域目錄內（模型天天讀寫 docs/ps-research，排除「讀不到 auto-loop-logs」
# 的路徑層風險）；auto-loop-logs 另留一份副本給人看
$auditManifestPath = Join-Path $auditPartsDir "manifest.txt"
$auditManifestCopy = Join-Path $logRoot "audit-manifest.txt"
$uuidRx = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

function Get-AuditLedger {
    if (-not (Test-Path -LiteralPath $auditLedgerPath)) { return $null }
    try {
        $j = Get-Content -LiteralPath $auditLedgerPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $files = @{}
        if ($null -ne $j.files) {
            foreach ($p in $j.files.PSObject.Properties) {
                $v = $p.Value
                $d = @(); if ($null -ne $v.detail) { $d = @($v.detail | Where-Object { $null -ne $_ }) }
                $files[$p.Name] = @{ hash = [string]$v.hash; rows = [int]$v.rows; status = [string]$v.status
                    attempts = [int]$v.attempts; pageSize = [int]$v.pageSize; reason = [string]$v.reason
                    pass = [int]$v.pass; fail = [int]$v.fail; unver = [int]$v.unver; pending = [int]$v.pending
                    verified = [int]$v.verified; disputed = [int]$v.disputed; detail = $d }
            }
        }
        $wiki = @(); if ($null -ne $j.wiki) { $wiki = @($j.wiki | Where-Object { $null -ne $_ }) }
        return @{ round = [int]$j.round; batchK = [int]$j.batchK; domainDone = [bool]$j.domainDone
            domainAttempts = [int]$j.domainAttempts; domainReason = [string]$j.domainReason; files = $files; wiki = $wiki }
    }
    catch { return $null }
}

function Save-AuditLedger {
    param($Ledger)
    $o = [ordered]@{ round = $Ledger.round; batchK = $Ledger.batchK; domainDone = $Ledger.domainDone
        domainAttempts = $Ledger.domainAttempts; domainReason = $Ledger.domainReason; wiki = @($Ledger.wiki); files = [ordered]@{} }
    foreach ($k in ($Ledger.files.Keys | Sort-Object)) {
        $f = $Ledger.files[$k]
        $o.files[$k] = [ordered]@{ hash = $f.hash; rows = $f.rows; status = $f.status; attempts = $f.attempts
            pageSize = $f.pageSize; reason = $f.reason; pass = $f.pass; fail = $f.fail; unver = $f.unver
            pending = $f.pending; verified = $f.verified; disputed = $f.disputed; detail = @($f.detail) }
    }
    [System.IO.File]::WriteAllText($auditLedgerPath, (ConvertTo-Json $o -Depth 6),
        (New-Object System.Text.UTF8Encoding($false)))
}

# 每檔 Evidence 資料列數：只有 lint 的一份實作（-EvidenceStats），外環只解析
function Get-EvidenceRowCounts {
    $raw = & $lintPath -Domain $Domain -EvidenceStats *>&1 | Out-String
    $h = @{}
    foreach ($m in [regex]::Matches($raw, '(?m)^EVIDENCE_ROWS：(?<f>[^=\r\n]+)=(?<n>\d+)')) {
        $h[$m.Groups['f'].Value.Trim()] = [int]$m.Groups['n'].Value
    }
    return $h
}

# 任務 B claim 由確定性層抽（反 cherry-pick 的選擇權不在被審的模型手上）：
# 模板兩種形狀——行為邏輯的「- **CONFIRMED**：…」行、資料流表的「| … | CONFIRMED |」列
function Get-ClaimSample {
    param([string]$Path, [int]$Max = 5)
    $out = @()
    if (-not (Test-Path -LiteralPath $Path)) { return , $out }
    $t = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrEmpty($t)) { return , $out }
    foreach ($m in [regex]::Matches($t, '(?m)^\s*-\s*\*\*CONFIRMED\*\*\s*[：:]\s*(.+?)\s*$')) {
        $c = ($m.Groups[1].Value -replace '\|', '／').Trim()
        if ($c.Length -gt 120) { $c = $c.Substring(0, 120) + '…' }
        if ($c -ne '') { $out += $c }
        if ($out.Count -ge $Max) { return , $out }
    }
    foreach ($m in [regex]::Matches($t, '(?m)^\s*\|(?<row>[^\r\n]*\|\s*CONFIRMED\s*\|[^\r\n]*)\r?$')) {
        $cells = @($m.Groups['row'].Value -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and $_ -ne 'CONFIRMED' })
        $c = ($cells -join '／')
        if ($c.Length -gt 120) { $c = $c.Substring(0, 120) + '…' }
        if ($c -ne '') { $out += $c }
        if ($out.Count -ge $Max) { return , $out }
    }
    return , $out
}

# wiki 抽驗：本領域 NN 檔 [[連結]] 到的 entity，依 last_verified 最舊優先取 5
function Get-WikiPicks {
    param([int]$Max = 5)
    $wikiDir = Join-Path $root "docs/ps-research/wiki"
    $picks = @()
    if (-not (Test-Path -LiteralPath $wikiDir)) { return , $picks }
    $names = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter "*.md" -File | Where-Object { $_.Name -match '^\d\d-' -and $_.Name -ne '90-audit.md' })) {
        $t = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
        if ([string]::IsNullOrEmpty($t)) { continue }
        foreach ($m in [regex]::Matches($t, '\[\[([^\]\|#]+)')) { $names[$m.Groups[1].Value.Trim()] = $true }
    }
    $cands = @()
    foreach ($n in $names.Keys) {
        $p = Join-Path $wikiDir ($n + ".md")
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $lv = "0000-00-00"
        $head = Get-Content -LiteralPath $p -TotalCount 30 -Encoding UTF8
        foreach ($l in @($head)) { if ($l -match '^last_verified\s*:\s*(\S+)') { $lv = $Matches[1]; break } }
        $cands += [pscustomobject]@{ Name = $n; LastVerified = $lv }
    }
    foreach ($c in @($cands | Sort-Object LastVerified, Name | Select-Object -First $Max)) {
        $picks += ("docs/ps-research/wiki/" + $c.Name + ".md")
    }
    return , $picks
}

function New-AuditManifest {
    param([int]$TargetRound, [bool]$FullSweep, $Files, [int]$BatchIndex, [int]$BatchTotal, [bool]$DomainTasks, $WikiPicks)
    $ln = @()
    $ln += "# 稽核批次 manifest（外環產生，模型唯讀——不得修改；不在清單內的檔一律不碰）"
    $ln += "領域：$Domain"
    $ln += "目標輪次：$TargetRound"
    $ln += "查無全量抽驗：$(if ($FullSweep) { '待執行（每個任務 A 委派末尾加註「本檔查無宣告抽驗全量做」）' } else { '照常（每檔抽 1~2 筆）' })"
    $ln += "批次：$BatchIndex/$BatchTotal"
    $ln += ""
    $ln += "## 檔案（每檔每範圍一個任務 A 委派；任務 B 只用下列 claims，不得自選）"
    if ($Files.Count -eq 0) { $ln += "（本批無檔案任務）" }
    foreach ($f in $Files) {
        $rg = @()
        $n = [int]$f.Rows; $ps = [int]$f.PageSize
        if ($n -le 0) { $rg += "全" }
        else { $s = 1; while ($s -le $n) { $e = [Math]::Min($n, $s + $ps - 1); $rg += "$s-$e"; $s = $e + 1 } }
        $cl = "（無可機械抽取的 CONFIRMED 行——任務 B 回單筆 UNVERIFIABLE）"
        if ($f.Claims.Count -gt 0) { $cl = ($f.Claims -join "；") }
        $ln += "- $($f.Name)｜Evidence 列數=$n｜範圍=$($rg -join ',')｜claims=$cl"
    }
    $ln += ""
    $ln += "## 領域任務"
    if ($DomainTasks) {
        $ln += "- 任務 C：核心資料表清單取自 00-overview.md，每批 ≤5 張表一個委派；候選逐一過 Domain Gate 三分（DOMAIN_ROOT／DEPENDENCY／OUT_OF_SCOPE）"
        if ($WikiPicks.Count -gt 0) { $ln += "- wiki 抽驗（任務 A，只傳路徑）：" + ($WikiPicks -join "、") } else { $ln += "- wiki 抽驗：無候選" }
    }
    else { $ln += "（無）" }
    $ln += ""
    $ln += "## 輸出（唯一可寫的路徑）"
    if ($DomainTasks) { $ln += "- docs/ps-research/$Domain/audit-parts/domain.md" }
    else { $ln += "- docs/ps-research/$Domain/audit-parts/part-$BatchIndex.md" }
    if (-not (Test-Path -LiteralPath $auditPartsDir)) { New-Item -ItemType Directory -Path $auditPartsDir -Force | Out-Null }
    [System.IO.File]::WriteAllText($auditManifestPath, (($ln -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
    try { Copy-Item -LiteralPath $auditManifestPath -Destination $auditManifestCopy -Force } catch { }
    return $auditManifestPath
}

# part 檔不變量（收據的唯一依據）——parent 寫的數字必須自洽且對得上檔案：
#   (i) 檔的所有範圍列都在且覆蓋 1..列數；(ii) PASS+FAIL+UNVERIFIABLE+
#   PENDING_MANUAL 合計＝該檔 Evidence 列數；(iii) 明細「內容」欄的 id 都在
#   該檔附錄裡（捏造判定抓得到）；(iv) 有非 PASS 判定必有明細列。
function Test-AuditPart {
    param([string]$PartPath, [hashtable]$Expected)
    $res = @{ Files = @{}; Invalid = @{} }
    if (-not (Test-Path -LiteralPath $PartPath)) {
        foreach ($n in $Expected.Keys) { $res.Invalid[$n] = 'part 檔不存在' }
        return $res
    }
    $t = Get-Content -LiteralPath $PartPath -Raw -Encoding UTF8
    if ([string]::IsNullOrEmpty($t)) { foreach ($n in $Expected.Keys) { $res.Invalid[$n] = 'part 檔空白' }; return $res }
    if ($t -match '</?think(ing)?>|<\|im_(start|end)\|>|</?tool_call>|<function=|invalid\[tool=') {
        foreach ($n in $Expected.Keys) { $res.Invalid[$n] = 'part 檔含模型內部標記（洩漏）' }
        return $res
    }
    $sec = ''; $sc = @(); $dt = @()
    foreach ($ln in ($t -split "`r?`n")) {
        if ($ln -match '^##\s*(.+)$') { $sec = $Matches[1].Trim(); continue }
        if ($ln -notmatch '^\s*\|') { continue }
        if ($ln -match '^\s*\|[\s:|-]+\|?\s*$') { continue }
        if ($sec -match '記分卡') { $sc += $ln } elseif ($sec -match '明細') { $dt += $ln }
    }
    $acc = @{}
    foreach ($row in $sc) {
        $c = @($row.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
        if ($c.Count -lt 8 -or $c[0] -match '^檔案') { continue }
        $f = $c[0]
        if (-not $Expected.ContainsKey($f)) { continue }
        $nums = @(); $ok = $true
        for ($i = 2; $i -le 7; $i++) { $v = 0; if ([int]::TryParse($c[$i], [ref]$v)) { $nums += $v } else { $ok = $false } }
        if (-not $ok) { $res.Invalid[$f] = "記分卡欄位非數字：$($row.Trim())"; continue }
        if (-not $acc.ContainsKey($f)) { $acc[$f] = @{ pass = 0; fail = 0; unver = 0; pending = 0; verified = 0; disputed = 0; ranges = @(); detail = @() } }
        $a = $acc[$f]
        $a.pass += $nums[0]; $a.fail += $nums[1]; $a.unver += $nums[2]; $a.pending += $nums[3]; $a.verified += $nums[4]; $a.disputed += $nums[5]
        if ($c[1] -match '(\d+)\s*[-–~]\s*(\d+)') { $a.ranges += , @([int]$Matches[1], [int]$Matches[2]) }
        else { $a.ranges += , @(1, [Math]::Max(1, [int]$Expected[$f])) }
    }
    foreach ($row in $dt) {
        $c = @($row.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
        if ($c.Count -lt 3 -or $c[0] -match '^檔案') { continue }
        $f = $c[0]
        if ($acc.ContainsKey($f)) { $acc[$f].detail += , @($row.Trim(), $c[2]) }
    }
    foreach ($f in @($acc.Keys)) {
        if ($res.Invalid.ContainsKey($f)) { continue }
        $a = $acc[$f]
        $exp = [Math]::Max(1, [int]$Expected[$f])   # 無 Evidence 節＝單筆 NO_EVIDENCE_SECTION
        $sum = $a.pass + $a.fail + $a.unver + $a.pending
        if ($sum -ne $exp) { $res.Invalid[$f] = "證據判定合計 $sum ≠ Evidence 列數 $exp"; continue }
        $covered = New-Object bool[] ($exp + 1)
        foreach ($r in $a.ranges) { for ($i = [Math]::Max(1, $r[0]); $i -le [Math]::Min($exp, $r[1]); $i++) { $covered[$i] = $true } }
        $gap = @(); for ($i = 1; $i -le $exp; $i++) { if (-not $covered[$i]) { $gap += $i } }
        if ($gap.Count -gt 0) { $res.Invalid[$f] = "範圍未覆蓋第 $($gap -join ',') 筆"; continue }
        $nnP = Join-Path $dir $f
        if (Test-Path -LiteralPath $nnP) {
            $nnT = Get-Content -LiteralPath $nnP -Raw -Encoding UTF8
            if ($null -eq $nnT) { $nnT = "" }
            $bad = $null
            foreach ($d in $a.detail) {
                foreach ($u in [regex]::Matches($d[1], $uuidRx)) {
                    if ($nnT.IndexOf($u.Value, [StringComparison]::OrdinalIgnoreCase) -lt 0) { $bad = $u.Value; break }
                }
                if ($bad) { break }
            }
            if ($bad) { $res.Invalid[$f] = "明細「內容」引用的 id $bad 不在該檔 Evidence 附錄（疑似捏造判定）"; continue }
        }
        if (($a.fail + $a.unver + $a.pending + $a.disputed) -gt 0 -and $a.detail.Count -eq 0) {
            $res.Invalid[$f] = "有非 PASS 判定卻無明細列"; continue
        }
        $res.Files[$f] = @{ pass = $a.pass; fail = $a.fail; unver = $a.unver; pending = $a.pending
            verified = $a.verified; disputed = $a.disputed; detail = @($a.detail | ForEach-Object { $_[0] }) }
    }
    foreach ($n in $Expected.Keys) {
        if (-not $res.Files.ContainsKey($n) -and -not $res.Invalid.ContainsKey($n)) { $res.Invalid[$n] = '記分卡無此檔列' }
    }
    return $res
}

# domain.md（批次 0）：完整性宣告＋任務 C 候選（含 Domain Gate 分類）＋wiki 結果
function Read-DomainPart {
    $p = Join-Path $auditPartsDir "domain.md"
    $r = @{ Ok = $false; Integrity = @(); Candidates = @(); WikiRows = @(); WikiDetail = @(); Reason = '' }
    if (-not (Test-Path -LiteralPath $p)) { $r.Reason = 'domain.md 不存在'; return $r }
    $t = Get-Content -LiteralPath $p -Raw -Encoding UTF8
    if ([string]::IsNullOrEmpty($t)) { $r.Reason = 'domain.md 空白'; return $r }
    if ($t -notmatch '任務\s*C\s*覆蓋.*\d+.*\d+') { $r.Reason = '缺「任務 C 覆蓋：完成 N／共 M 批」宣告'; return $r }
    $sec = ''
    foreach ($ln in ($t -split "`r?`n")) {
        if ($ln -match '^##\s*(.+)$') { $sec = $Matches[1].Trim(); continue }
        if ($sec -match '完整性') {
            if ($ln.Trim() -ne '' -and $ln -notmatch '^\s*\|[\s:|-]+\|?\s*$') {
                if ($ln -match '^\s*\|') {
                    $c = @($ln.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
                    if ($c.Count -ge 7 -and $c[0] -notmatch '^候選') { $r.Candidates += , $c }
                    else { $r.Integrity += $ln }
                }
                else { $r.Integrity += $ln }
            }
        }
        elseif ($sec -match 'wiki' -and $sec -match '記分卡') {
            if ($ln -match '^\s*\|' -and $ln -notmatch '^\s*\|[\s:|-]+\|?\s*$' -and $ln -notmatch '^\s*\|\s*檔案') { $r.WikiRows += $ln.Trim() }
        }
        elseif ($sec -match 'wiki' -and $sec -match '明細') {
            if ($ln -match '^\s*\|' -and $ln -notmatch '^\s*\|[\s:|-]+\|?\s*$' -and $ln -notmatch '^\s*\|\s*檔案') { $r.WikiDetail += $ln.Trim() }
        }
    }
    $r.Ok = $true
    return $r
}

# 在「## 調查進度」節尾插列（最小插入，其餘內容一字不動）
function Add-ChecklistRows {
    param([string[]]$Rows)
    if ($Rows.Count -eq 0) { return }
    $clPath = Join-Path $dir "checklist.md"
    if (-not (Test-Path -LiteralPath $clPath)) { return }
    $lines = @((Get-Content -LiteralPath $clPath -Raw -Encoding UTF8) -split "`r?`n")
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^##\s*調查進度') { $start = $i; break } }
    if ($start -lt 0) { $lines += ''; $lines += '## 調查進度'; $start = $lines.Count - 1 }
    $end = $lines.Count
    for ($i = $start + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^##\s') { $end = $i; break } }
    $ins = $end
    while ($ins -gt $start + 1 -and $lines[$ins - 1].Trim() -eq '') { $ins-- }
    $out = @()
    if ($ins -gt 0) { $out += $lines[0..($ins - 1)] }
    $out += $Rows
    if ($ins -lt $lines.Count) { $out += $lines[$ins..($lines.Count - 1)] }
    [System.IO.File]::WriteAllText($clPath, ($out -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
}

function Set-ChecklistRoundAndFlag {
    param([int]$NewRound)
    $clPath = Join-Path $dir "checklist.md"
    if (-not (Test-Path -LiteralPath $clPath)) { return }
    $raw = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8
    if ([string]::IsNullOrEmpty($raw)) { return }
    $raw = [regex]::Replace($raw, '(?m)^(\s*稽核輪次[：:]\s*)[0-9]+', ('${1}' + $NewRound))
    $raw = [regex]::Replace($raw, '(?m)^(\s*查無全量抽驗[：:]\s*)待執行[^\r\n]*', ('${1}已執行（第 ' + $NewRound + ' 輪）'))
    [System.IO.File]::WriteAllText($clPath, $raw, (New-Object System.Text.UTF8Encoding($true)))
}

# 合併器：收據齊備（DONE 或 BLOCKED，無 PENDING）後由外環寫 90-audit.md、
# 機械產 A 列（一檔一行）與 D 列（僅 DOMAIN_ROOT）、遞增輪次、翻旗標。
# 模板六章節全數就位（lint 認標題）；語意類章節寫誠實佔位，不由模型覆核。
function Invoke-AuditMerge {
    param($Ledger, [int]$TargetRound)
    $dp = Read-DomainPart
    $sc = @(); $dt = @(); $aRows = @(); $dRows = @()
    $tp = 0; $tf = 0; $tu = 0; $tv = 0; $td = 0; $g = 0; $y = 0; $rd = 0; $blocked = @()
    $seq = 0
    foreach ($f in ($Ledger.files.Keys | Sort-Object)) {
        $e = $Ledger.files[$f]
        if ($e.status -eq 'BLOCKED') {
            $sc += "| $f | 未稽核（BLOCKED：$($e.reason)） | - | - | - | - | ⛔ |"
            $blocked += $f
            continue
        }
        $u = $e.unver + $e.pending
        $light = if ($e.fail -gt 0 -or $e.disputed -gt 0) { '🔴' } elseif ($u -gt 0) { '🟡' } else { '🟢' }
        if ($light -eq '🔴') { $rd++ } elseif ($light -eq '🟡') { $y++ } else { $g++ }
        $sc += "| $f | $($e.pass) | $($e.fail) | $u | $($e.verified) | $($e.disputed) | $light |"
        $tp += $e.pass; $tf += $e.fail; $tu += $u; $tv += $e.verified; $td += $e.disputed
        foreach ($d in @($e.detail)) { $dt += $d }
        if (($e.fail + $e.disputed + $e.unver) -gt 0) {
            $seq++
            $aRows += ("- [ ] A{0}-{1:D2} 補查 {2}：FAIL {3}／DISPUTED {4}／UNVERIFIABLE {5}（稽核）" -f $TargetRound, $seq, $f, $e.fail, $e.disputed, $e.unver)
        }
    }
    foreach ($w in $dp.WikiRows) {
        $c = @($w.Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
        if ($c.Count -lt 8) { continue }
        $nums = @(); $ok = $true
        for ($i = 2; $i -le 7; $i++) { $v = 0; if ([int]::TryParse($c[$i], [ref]$v)) { $nums += $v } else { $ok = $false } }
        if (-not $ok) { continue }
        $u = $nums[2] + $nums[3]
        $light = if ($nums[1] -gt 0 -or $nums[5] -gt 0) { '🔴' } elseif ($u -gt 0) { '🟡' } else { '🟢' }
        $sc += "| $($c[0]) | $($nums[0]) | $($nums[1]) | $u | $($nums[4]) | $($nums[5]) | $light |"
        if (($nums[1] + $nums[5] + $nums[2]) -gt 0) {
            $seq++
            $aRows += ("- [ ] A{0}-{1:D2} 補查 {2}：FAIL {3}／DISPUTED {4}／UNVERIFIABLE {5}（稽核）" -f $TargetRound, $seq, $c[0], $nums[1], $nums[5], $nums[2])
        }
    }
    foreach ($w in $dp.WikiDetail) { $dt += $w }
    # D 列：只有 Domain Gate 判 DOMAIN_ROOT 的候選；重複提案交 Invoke-DItemGovernance 裁決
    $dseq = 0
    foreach ($c in $dp.Candidates) {
        if ($c[5] -notmatch '(?i)DOMAIN_ROOT') { continue }
        $obj = $c[0] -replace '[`\[\]]', ''
        if ($obj -eq '') { continue }
        $dseq++
        $why = $c[6]; if ($why.Length -gt 80) { $why = $why.Substring(0, 80) + '…' }
        $dRows += ("- [ ] D{0}-{1:D2} 新發現 {2}：{3}（稽核）" -f $TargetRound, $dseq, $obj, $why)
    }
    # 系統性觀察：明細「類型」欄同類 ≥2 機械統計
    $typeCount = @{}
    foreach ($d in $dt) {
        $c = @($d.Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
        if ($c.Count -ge 2) { $k = $c[1]; if ($typeCount.ContainsKey($k)) { $typeCount[$k]++ } else { $typeCount[$k] = 1 } }
    }
    $sys = @(); foreach ($k in ($typeCount.Keys | Sort-Object)) { if ($typeCount[$k] -ge 2) { $sys += "- 「$k」×$($typeCount[$k])——同類 ≥2，建議 /ps-lesson 檢視" } }
    if ($sys.Count -eq 0) { $sys += "- 無" }
    $today = Get-Date -Format "yyyy-MM-dd"
    $totalFiles = $Ledger.files.Count
    $o = @()
    $o += "# $Domain 稽核報告（90-audit）"
    $o += ""
    $o += "> 稽核輪次：$TargetRound　稽核日期：$today　範圍：已完成的 $totalFiles 個檔案（分批稽核，外環合併；BLOCKED $($blocked.Count) 檔）　執行：auto-loop 分批稽核（issue #22）"
    $o += ""
    $o += "## 總覽記分卡"
    $o += ""
    $o += "| 檔案 | 證據 PASS | FAIL | UNVERIFIABLE | Claim VERIFIED | DISPUTED | 燈號 |"
    $o += "|---|---|---|---|---|---|---|"
    $o += $sc
    $o += "| **合計** | **$tp** | **$tf** | **$tu** | **$tv** | **$td** | 🟢$g／🟡$y／🔴$rd$(if ($blocked.Count -gt 0) { '／⛔' + $blocked.Count } else { '' }) |"
    $o += ""
    $o += "燈號：🟢 無 FAIL / DISPUTED；🟡 僅 UNVERIFIABLE；🔴 有 FAIL 或 DISPUTED；⛔ 未稽核（BLOCKED，見 audit-ledger.json，處理後刪台帳重跑）"
    $o += ""
    $o += "## FAIL / DISPUTED / UNVERIFIABLE 明細"
    $o += ""
    $o += "| 檔案 | 類型 | 內容 | 原因 | 處置 |"
    $o += "|---|---|---|---|---|"
    if ($dt.Count -eq 0) { $o += "| （無） | - | - | - | - |" } else { $o += $dt }
    $o += ""
    $o += "## 上輪回灌項覆核（第 2 輪起必填；首輪寫「無上輪」）"
    $o += ""
    $o += "- 分批稽核由外環合併，本節不由模型覆核：上輪 A 項的處置結果以本輪記分卡的全量重驗數字為準（同檔仍非 PASS＝未修成／已修成則本輪不再開單）。"
    $o += ""
    $o += "## 完整性（換角度 diff）"
    $o += ""
    if ($dp.Ok) {
        $o += $dp.Integrity
        if ($dp.Candidates.Count -gt 0) {
            $o += ""
            $o += "| 候選物件 | 型別 | 經由表 | 方向 | origin | 分類 | 理由 |"
            $o += "|---|---|---|---|---|---|---|"
            foreach ($c in $dp.Candidates) { $o += ("| " + ($c -join " | ") + " |") }
        }
    }
    else {
        $o += "- 任務 C 覆蓋：完成 0／共 1 批（未完成批次：領域批次未產出 domain.md——$($dp.Reason)）"
        $o += "- 資料角度發現、功能地圖沒有的物件：本輪未查成（非「無」）"
    }
    $o += ""
    $o += "## 已回灌 checklist 的行動項"
    $o += ""
    if (($aRows.Count + $dRows.Count) -eq 0) { $o += "- 無（本輪全量 PASS／VERIFIED）" } else { $o += $aRows; $o += $dRows }
    $o += ""
    $o += "## 系統性錯誤觀察（同類 FAIL ≥ 2 → 建議 /ps-lesson）"
    $o += ""
    $o += $sys
    $o += ""
    # 順序：先回灌 checklist，再寫報告（模板約束：行動項必須「先」在 checklist）
    Add-ChecklistRows -Rows (@($aRows) + @($dRows))
    Set-ChecklistRoundAndFlag -NewRound $TargetRound
    [System.IO.File]::WriteAllText((Join-Path $dir "90-audit.md"), ($o -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
    return @{ ARows = $aRows.Count; DRows = $dRows.Count; Blocked = $blocked; Files = $totalFiles }
}

# 回合驅動：凍結本輪 → 逐批 session → 驗收發收據 → 齊備即合併。
# 回傳與 Invoke-Opencode 同形的 $r（下游守衛／熔絲照舊）。
function Invoke-AuditRound {
    $clPath = Join-Path $dir "checklist.md"
    $curRound = 0; $fullSweep = $false
    if (Test-Path -LiteralPath $clPath) {
        foreach ($l in (Get-Content -LiteralPath $clPath -Encoding UTF8)) {
            if ($l -match '稽核輪次[：:]\s*([0-9]+)') { $curRound = [int]$Matches[1] }
            if ($l -match '查無全量抽驗[：:]\s*待執行') { $fullSweep = $true }
        }
    }
    $target = $curRound + 1
    $ledger = Get-AuditLedger
    if ($null -eq $ledger -or $ledger.round -ne $target) {
        $ledger = @{ round = $target; batchK = $AuditBatchSize; domainDone = $false; domainAttempts = 0; domainReason = ''; files = @{}; wiki = @() }
        Write-Log "稽核輪次 $target 開始（分批）：新台帳"
    }
    else { Write-Log "稽核輪次 $target 續跑：台帳已有 $(@($ledger.files.Values | Where-Object { $_.status -eq 'DONE' }).Count) 檔收據" }
    $rows = Get-EvidenceRowCounts
    $nn = @(Get-ChildItem -LiteralPath $dir -Filter "*.md" -File | Where-Object { $_.Name -match '^\d\d-' -and $_.Name -ne '90-audit.md' } | Sort-Object Name)
    foreach ($f in $nn) {
        $h = Get-NormalizedFileHash -LiteralPath $f.FullName
        $n = 0; if ($rows.ContainsKey($f.Name)) { $n = [int]$rows[$f.Name] }
        if ($ledger.files.ContainsKey($f.Name)) {
            $e = $ledger.files[$f.Name]
            if ($e.hash -ne $h) { $e.hash = $h; $e.rows = $n; $e.status = 'PENDING'; $e.attempts = 0; $e.reason = '' ; Write-Log "稽核：$($f.Name) 內容已變，收據作廢重驗" }
        }
        else {
            $ledger.files[$f.Name] = @{ hash = $h; rows = $n; status = 'PENDING'; attempts = 0; pageSize = $AuditEvidencePageSize; reason = ''
                pass = 0; fail = 0; unver = 0; pending = 0; verified = 0; disputed = 0; detail = @() }
        }
    }
    foreach ($k in @($ledger.files.Keys)) { if (-not (Test-Path -LiteralPath (Join-Path $dir $k))) { $ledger.files.Remove($k) } }
    if (-not (Test-Path -LiteralPath $auditPartsDir)) { New-Item -ItemType Directory -Path $auditPartsDir -Force | Out-Null }
    Save-AuditLedger -Ledger $ledger
    $failStreak = 0; $batchesRun = 0; $progress = 0
    $script:auditRoundProgress = 0
    # 批次 0：領域任務（任務 C＋wiki 抽驗）
    if (-not $ledger.domainDone) {
        $wp = Get-WikiPicks
        $ledger.wiki = @($wp)
        $null = New-AuditManifest -TargetRound $target -FullSweep $fullSweep -Files @() -BatchIndex 0 -BatchTotal 0 -DomainTasks $true -WikiPicks $wp
        $sr = Invoke-AuditBatchSession -Tag "audit-b0"
        $batchesRun++
        $dp = Read-DomainPart
        if ($dp.Ok) { $ledger.domainDone = $true; $ledger.domainReason = ''; $failStreak = 0; $progress++; Write-Log "稽核批次 0（領域）完成：候選 $($dp.Candidates.Count) 筆、wiki 列 $($dp.WikiRows.Count)" }
        else {
            $ledger.domainAttempts++
            $ledger.domainReason = $dp.Reason
            Write-Log "稽核批次 0（領域）未達標：$($dp.Reason)（attempts=$($ledger.domainAttempts)）"
            if ($ledger.domainAttempts -ge 2) { $ledger.domainDone = $true; Write-Log "稽核批次 0 兩次未達標——本輪完整性節以「未查成」記錄，不再重試" }
            if ($sr.TimedOut -or $sr.ExitCode -ne 0 -or $sr.FailureKind -eq 'CONTEXT_OVERFLOW') { $failStreak++ }
        }
        Save-AuditLedger -Ledger $ledger
    }
    # 檔案批次
    $bi = 0
    while ($true) {
        if ($AuditBatchesPerCycle -gt 0 -and $batchesRun -ge $AuditBatchesPerCycle) { Write-Log "稽核：本圈批次上限 $AuditBatchesPerCycle 已達，餘檔下圈續跑"; break }
        if ($failStreak -ge 2) { Write-Log "稽核：連續 2 批 session 級故障——本圈停止，餘檔下圈續跑（收據保留）"; break }
        $pending = @($ledger.files.Keys | Where-Object { $ledger.files[$_].status -eq 'PENDING' } | Sort-Object)
        if ($pending.Count -eq 0) { break }
        $k = [Math]::Max(1, [int]$ledger.batchK)
        $batch = @($pending | Select-Object -First $k)
        $bi++
        $files = @()
        foreach ($f in $batch) { $e = $ledger.files[$f]; $files += @{ Name = $f; Rows = $e.rows; PageSize = [Math]::Max(1, $e.pageSize); Claims = @(Get-ClaimSample -Path (Join-Path $dir $f) -Max 5) } }
        $totalB = [int][Math]::Ceiling($pending.Count / [double]$k)
        $null = New-AuditManifest -TargetRound $target -FullSweep $fullSweep -Files $files -BatchIndex $bi -BatchTotal $totalB -DomainTasks $false -WikiPicks @()
        Write-Log "稽核第 $bi 批（待驗 $($pending.Count) 檔、以 K=$k 估餘 $totalB 批）：$($batch -join '、')｜列數 $(($files | ForEach-Object { $_.Rows }) -join ',')"
        $sr = Invoke-AuditBatchSession -Tag "audit-b$bi"
        $batchesRun++
        $exp = @{}
        foreach ($f in $batch) { $exp[$f] = [int]$ledger.files[$f].rows }
        $partPath = Join-Path $auditPartsDir ("part-{0}.md" -f $bi)
        # stdout 回收（實案：session exit 0、沒逾時、part 檔不存在＝模型把兩張表
        # 印在對話裡當結案，沒 write）。stdout 裡有「## 記分卡」就整份當 part 檔驗
        # ——不變量照驗，過不了照樣無收據；只是「講了沒寫」不再等於白跑一批。
        if (-not (Test-Path -LiteralPath $partPath) -and $sr.OutFile -and (Test-Path -LiteralPath $sr.OutFile)) {
            $ot = Get-Content -LiteralPath $sr.OutFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($ot -and ($ot -match '(?m)^\s*#+\s*記分卡')) {
                [System.IO.File]::WriteAllText($partPath, $ot, (New-Object System.Text.UTF8Encoding($true)))
                Write-Log "稽核第 $bi 批：part-$bi.md 不存在但 session stdout 含記分卡表——已回收 stdout 為 part 檔驗收（模型講了沒寫）"
            }
        }
        $res = Test-AuditPart -PartPath $partPath -Expected $exp
        $got = 0
        foreach ($f in $batch) {
            $e = $ledger.files[$f]
            if ($res.Files.ContainsKey($f)) {
                $v = $res.Files[$f]
                $e.status = 'DONE'; $e.reason = ''
                $e.pass = $v.pass; $e.fail = $v.fail; $e.unver = $v.unver; $e.pending = $v.pending; $e.verified = $v.verified; $e.disputed = $v.disputed; $e.detail = @($v.detail)
                $got++
            }
        }
        $healthy = (-not $sr.TimedOut) -and ($sr.ExitCode -eq 0)
        $overflow = ($sr.FailureKind -eq 'CONTEXT_OVERFLOW')
        $partWritten = Test-Path -LiteralPath $partPath
        foreach ($f in $batch) {
            $e = $ledger.files[$f]
            if ($e.status -eq 'DONE') { continue }
            $why = $res.Invalid[$f]; if (-not $why) { $why = '無收據' }
            # attempts 只在「模型有寫 part 檔、但該檔驗不過」時記（實案：模型整批沒寫
            # 任何檔＝session 級故障，連兩批就把同 3 檔冤枉成 BLOCKED——那不是檔案的錯）
            if ($healthy -and $partWritten) { $e.attempts++ }
            $e.reason = $why
            if ($overflow -and $e.rows -gt $e.pageSize) { $e.pageSize = [Math]::Max(3, [int][Math]::Floor($e.pageSize / 2)); Write-Log "稽核：$f 溢出→頁大小減半為 $($e.pageSize)" }
            if ($e.attempts -ge 2 -or ($overflow -and $e.pageSize -le 3 -and $e.rows -gt 3)) {
                $e.status = 'BLOCKED'
                Write-Log "稽核 BLOCKED：$f（列數 $($e.rows)，attempts=$($e.attempts)）——$why；出路＝人工拆續篇 NN-X-2.md 縮小單檔證據，或修正後刪 audit-ledger.json 重跑"
            }
        }
        if ($got -eq 0) {
            $failStreak++
            # 零收據的逐檔原因必印（觀測缺口實案：管理者只看到「K 減半」，看不到是 part 檔沒寫還是合計不符）
            $whyAll = (($batch | ForEach-Object { $_ + '（' + $ledger.files[$_].reason + '）' }) -join '、')
            $partExists = Test-Path -LiteralPath (Join-Path $auditPartsDir ("part-{0}.md" -f $bi))
            Write-Log "稽核第 $bi 批零收據｜part-$bi.md $(if ($partExists) { '存在' } else { '不存在（session 沒寫或寫錯路徑）' })｜$(if ($overflow) { 'CONTEXT_OVERFLOW' } else { 'session exit=' + $sr.ExitCode + ' timeout=' + $sr.TimedOut })｜逐檔：$whyAll"
            # out 檔尾 3 行直接進主 log（同 err 檔尾 5 行的先例）：不用翻檔就看得到模型最後在幹嘛
            if ($sr.OutFile -and (Test-Path -LiteralPath $sr.OutFile)) {
                $tailO = @(Get-Content -LiteralPath $sr.OutFile -Tail 12 -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 3)
                foreach ($tl in $tailO) { $t1 = $tl; if ($t1.Length -gt 160) { $t1 = $t1.Substring(0, 160) + '…' }; Write-Log "  out> $t1" }
            }
            if ($overflow -or ($healthy -and $partExists)) { $ledger.batchK = [Math]::Max(1, [int][Math]::Floor($k / 2)); Write-Log "稽核：批次 K 減半為 $($ledger.batchK)（零收據且有寫檔＝疑似容量或格式；格式問題縮 K 沒用，看上一行逐檔原因）" }
            elseif (-not $partExists) { Write-Log "稽核：part 檔不存在＝session 級故障（模型沒 write）——不減 K、不記檔案 attempts；連 2 批即停本圈，看 out> 行與 SOP" }
        }
        else { $failStreak = 0; $progress += $got; Write-Log "稽核批次 $bi：收據 $got/$($batch.Count)$(if ($res.Invalid.Count -gt 0) { '；未達標：' + (($res.Invalid.Keys | ForEach-Object { $_ + '（' + $res.Invalid[$_] + '）' }) -join '、') } else { '' })" }
        Save-AuditLedger -Ledger $ledger
    }
    $script:auditRoundProgress = $progress
    $left = @($ledger.files.Keys | Where-Object { $ledger.files[$_].status -eq 'PENDING' }).Count
    if ($left -gt 0 -or -not $ledger.domainDone) {
        Write-Log "稽核輪次 $target 未完成：剩 $left 檔待驗（本圈收據 +$progress）——輪次不遞增、收據保留，下圈續跑"
        return @{ TimedOut = $false; ExitCode = 0; ErrFile = $null; OutFile = $null; FailureKind = 'NONE'; RoundComplete = $false }
    }
    $mg = Invoke-AuditMerge -Ledger $ledger -TargetRound $target
    $null = Invoke-DItemGovernance
    Write-Log "稽核輪次 $target 合併完成：$($mg.Files) 檔、A 列 $($mg.ARows)、D 列 $($mg.DRows)、BLOCKED $($mg.Blocked.Count)$(if ($mg.Blocked.Count -gt 0) { '（' + ($mg.Blocked -join '、') + '——記分卡標未稽核，lint 擋畢業）' } else { '' })"
    $done = Join-Path $logRoot ("audit-r{0}.done.json" -f $target)
    Copy-Item -LiteralPath $auditLedgerPath -Destination $done -Force
    Remove-Item -LiteralPath $auditLedgerPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $auditPartsDir -Recurse -Force -ErrorAction SilentlyContinue
    return @{ TimedOut = $false; ExitCode = 0; ErrFile = $null; OutFile = $null; FailureKind = 'NONE'; RoundComplete = $true }
}

# 單一稽核批次 session：前後照手術批次的守備（NN 快照／破壞防衛／調帳邊界）
function Invoke-AuditBatchSession {
    param([string]$Tag)
    $snap = Get-NnGuardSnapshot
    $preInvB = Get-ChecklistInventory
    $preRoundB = 0
    $clPath = Join-Path $dir "checklist.md"
    if (Test-Path -LiteralPath $clPath) { foreach ($l in (Get-Content -LiteralPath $clPath -Encoding UTF8)) { if ($l -match '稽核輪次[：:]\s*([0-9]+)') { $preRoundB = [int]$Matches[1] } } }
    $sr = Invoke-Opencode -ExtraArgs '--command ps-audit-batch' -PromptText $Domain -TimeoutMin $AuditBatchTimeoutMin -Tag $Tag
    $null = Invoke-NnDestructionGuard -Snap $snap -Tag $Tag
    $rec = Invoke-PostSessionReconcile -PreInv $preInvB -PreRound $preRoundB -Tag $Tag
    if ($rec.LegitRemoved -gt 0) { $script:preItemTotal -= $rec.LegitRemoved; Write-Log "完整性基準調整（$Tag）：外環合法刪列 $($rec.LegitRemoved) → 基準 $($script:preItemTotal)" }
    return $sr
}

# ── 主迴圈 ──────────────────────────────────────────────────
Write-Log "=== auto-loop 啟動：領域=$Domain MaxCycles=$MaxCycles Model=$(if($Model){$Model}else{'(全域預設)'}) ==="
# 啟動即結清歸檔（issue #13）：人工跑過 /ps-audit 的殘留已勾列在此搬進
# archive——外環是唯一歸檔者，不分列是誰打的勾
$null = Invoke-ChecklistArchiveCommit
$corruptStreak = 0
$timeoutStreak = 0
$errorStreak = 0
$noProgress = 0
$auditStall = 0
$drainNoProgress = 0    # 排水圈熔絲（issue #11）：連 2 圈排水無進度 → 退回正常相位
$surgeryFailStreak = 0  # 手術 session 獨立熔絲（issue #11 P0-6）：不污染 research 的 streak
$graduated = $false
$gradContentHash = $null
$gradAuditRound = 0
$auditRoundProgress = 0   # 分批稽核本圈收據數（輪次未合併時不計零回灌熔絲）
$stopReason = "圈數上限（$MaxCycles）"

for ($cycle = 1; $cycle -le $MaxCycles; $cycle++) {
    $before = Get-ChecklistState
    Write-Log "── 第 $cycle 圈：未勾=$($before.Unticked) 已勾=$($before.Ticked) 稽核輪次=$($before.Round)"

    # 一致性檢查的圈前基準（強殺後用「圈前存在的東西沒變壞」判定）
    $preHadChecklist = Test-Path (Join-Path $dir "checklist.md")
    $preItemTotal = if ($preHadChecklist) { Get-ItemTotal } else { 0 }
    # 身分快照（issue #6）：調帳用——比總數多一層「每一筆都還在」的保證
    $preInv = if ($preHadChecklist) { Get-ChecklistInventory } else { $null }
    $preRound = if ($before.Round -ge 0) { $before.Round } else { 0 }
    # audit 轉移快照——每圈重算的區域值（跨圈黏著旗標會讓舊圈證據放行新圈畢業）
    $auditBefore = $null
    $auditAfter = $null

    # 相位決定
    #   tier 2（精修）：有未勾項→research；全勾→audit（＝原本的規則）
    #   tier 1（覆蓋）：**不看未勾數，看缺料還在不在**——lint -CoverageOnly
    #     FAIL→research 補料；PASS→audit 爭取覆蓋畢業。
    #     理由：稽核每輪回灌補強項，若照未勾數決定相位，未勾數只會越積越多、
    #     永遠進不了 audit＝永遠畢不了業（實案：一輪就回灌 11 項）。補強項是
    #     建議不是債（SOP-13），不該擋出貨。
    # 領域不存在一律 research（階段一建檔）。
    $coverBefore = $null
    $goResearch = (-not $before.Exists)
    if (-not $goResearch) {
        if ($Tier -eq 1) {
            $coverBefore = Invoke-Lint -Coverage
            # 相位只看「research 修得動」的缺料（L72）：90-audit.md 類
            # （記分卡塌縮、輪次不一致…）只有 audit 相位重寫得了。把它算進
            # 相位判斷＝唯一能修它的相位被它自己擋住＝活鎖（L63 同族）。
            # 畢業門仍看**全部**缺料，標準一點都沒放寬。
            $cv = Get-CoverageBreakdown -Raw $coverBefore.Raw
            $cvTotal = $cv.Total
            $cvAuditOnly = $cv.AuditOnly
            $cvManualOnly = $cv.ManualOnly
            $cvAuto = $cv.Auto
            $goResearch = ($cvAuto -gt 0)
            if ($cvAuditOnly -gt 0 -or $cvManualOnly -gt 0) {
                Write-Log "COVERAGE(圈前) 缺料 $cvTotal 項＝自動 $cvAuto／僅 audit 可修 $cvAuditOnly／需人工 $cvManualOnly——相位只看自動那 $cvAuto 項"
            }
            # 沒有任何自動路徑可走時，**立刻**停機並指名待辦（L74）——
            # 讓它跑滿兩圈再報「無進度」＝燒兩個 session 講一句本來就知道的話，
            # 而且停機理由完全沒提到人要做什麼。
            if ($cvAuto -le 0 -and $cvAuditOnly -le 0 -and $cvManualOnly -gt 0) {
                # 停機前先試一次自動處置（L82）：歸檔未勾列多半是失敗的委派
                # 紀錄或純批次標籤，lint -FixArchive 判得出來也改得動——
                # **agent 做不到**（它的 write 沒有 append，重寫大檔會撐爆），
                # 但那是模型工具層的限制，PowerShell 沒有。本分支一圈只走一次。
                Write-Log "剩 $cvManualOnly 項需人工 → 先試 lint -FixArchive 自動處置"
                $fx = & $lintPath -Domain $Domain -FixArchive *>&1 | Out-String
                Add-Content -Path (Join-Path $logRoot ("fixarchive-cycle{0}.txt" -f $cycle)) `
                    -Value $fx -Encoding UTF8
                $coverBefore = Invoke-Lint -Coverage
                $cv = Get-CoverageBreakdown -Raw $coverBefore.Raw
                $cvTotal = $cv.Total
                $cvAuditOnly = $cv.AuditOnly
                $cvManualOnly = $cv.ManualOnly
                $cvAuto = $cv.Auto
                $goResearch = ($cvAuto -gt 0)
                Write-Log "FixArchive 後：缺料 $cvTotal 項＝自動 $cvAuto／僅 audit $cvAuditOnly／需人工 $cvManualOnly（處置明細見 fixarchive-cycle$cycle.txt）"
                # FixArchive 會合法刪列（流程標籤）——完整性基準必須重取，
                # 否則本圈 session 後的檢查會拿舊基準誤報「列被吃掉」
                $preItemTotal = Get-ItemTotal
                $preInv = Get-ChecklistInventory
            }
            if ($cvAuto -le 0 -and $cvAuditOnly -le 0 -and $cvManualOnly -gt 0) {
                $stopReason = "剩 $cvManualOnly 項需人工（-FixArchive 也判不出來：可能是『沒做完』與『打勾掉了』分不出的列）——清單見 coverage-cycle$cycle-pre.txt 的 MANUAL_ONLY 段、處置紀錄見 fixarchive-cycle$cycle.txt；處理完再啟動"
                Add-Content -Path (Join-Path $logRoot ("coverage-cycle{0}-pre.txt" -f $cycle)) `
                    -Value $coverBefore.Raw -Encoding UTF8
                Write-Log "COVERAGE(圈前) exit=$($coverBefore.Exit)｜自動處置後仍無路可走 → 停機"
                break
            }
            # 落檔（L71）：畢業門的 coverage-cycle*.txt 只在 audit 相位寫——
            # 卡在 research 相位時完全不會產生，而那正是最需要看缺料清單的時候。
            Add-Content -Path (Join-Path $logRoot ("coverage-cycle{0}-pre.txt" -f $cycle)) `
                -Value $coverBefore.Raw -Encoding UTF8
            Write-Log "COVERAGE(圈前) exit=$($coverBefore.Exit)（0=缺料已清）→ 相位 $(if ($goResearch) { 'research' } else { 'audit' })｜清單見 coverage-cycle$cycle-pre.txt"
        }
        else {
            $goResearch = ($before.Unticked -gt 0)
        }
    }
    # ── 排水圈（issue #11／L102）：可執行手術債優先於 producer ─────────
    # budget 用盡是 checkpoint 不是完工——債清完之前不先啟動會新增工作面的
    # research/audit（backpressure）。BLOCKED（台帳停滯）不算可執行債；
    # 連 2 圈排水無進度 → 退回正常相位（防排水活鎖，殘債見台帳與停機訊息）。
    $drainCycle = $false
    $actionableD = 0
    if ($before.Exists -and $drainNoProgress -lt 2) {
        $ledgerD = Get-SurgeryLedger
        $preLint = if ($Tier -eq 1) {
            if ($null -ne $coverBefore) { $coverBefore } else { Invoke-Lint -Coverage }
        }
        else { Invoke-Lint }
        $actionableD = Get-ActionableSurgicalCount -Surgical $preLint.Surgical -Ledger $ledgerD
        if ($actionableD -gt 0) { $drainCycle = $true }
    }
    # 破壞防衛快照（L103）：producer session 前拍——drain 圈不跑 producer，
    # 快照留給下方手術迴圈自己每批重拍
    $nnSnap = Get-NnGuardSnapshot
    if ($drainCycle) {
        $phase = "drain"
        Write-Log "排水圈：既存可執行手術債 $actionableD 筆——本圈跳過 producer，直接續清（checkpoint≠完工）"
        $r = @{ TimedOut = $false; ExitCode = 0; ErrFile = $null; OutFile = $null }
    }
    elseif ($goResearch) {
        $phase = "research"
        $r = Invoke-Opencode -ExtraArgs '--command ps-research' -PromptText $Domain `
            -TimeoutMin $ResearchTimeoutMin -Tag "research"
    }
    else {
        $phase = "audit"
        $auditBefore = Get-AuditTransition
        # 分批稽核（issue #22／L107）：manifest → K 檔/session → 收據 → 齊備才合併
        $r = Invoke-AuditRound
    }

    # 保險絲：逾時（強殺後先驗檔案一致性——FAIL 即停機進人工，不進下一圈）
    if ($r.TimedOut) {
        # 破壞防衛先跑（L103）：強殺半寫的 NN 檔能確定性還原就還原，
        # 別讓一致性檢查對「已可救回」的傷停機
        $null = Invoke-NnDestructionGuard -Snap $nnSnap -Tag "$phase-強殺後"
        $fsProblems = Test-FsConsistency -HadChecklist $preHadChecklist -PreItemTotal $preItemTotal
        if ($fsProblems.Count -gt 0) {
            foreach ($pb in $fsProblems) { Write-Log "CONSISTENCY FAIL：$pb" }
            $stopReason = "強殺後一致性檢查 FAIL（$($fsProblems.Count) 項，見上方 CONSISTENCY 行）——人工處理後再啟動"
            break
        }
        Write-Log "強殺後一致性檢查 PASS（唯讀）——維持既有重試邏輯"
        # 強殺半寫也走調帳（issue #6）：能確定性救回的列不留給下一圈賭
        $null = Invoke-PostSessionReconcile -PreInv $preInv -PreRound $preRound -Tag "$phase-強殺後"
        $timeoutStreak++
        if ($timeoutStreak -ge 2) { $stopReason = "連續 2 次逾時（需人工看 session log）"; break }
        continue
    }
    $timeoutStreak = 0
    # 破壞防衛（L103）：healthy exit 不代表沒掏空 NN 檔——實案正是正常
    # 結束的 session 把檔改到只剩 Evidence 節；drain 圈無 producer 免驗
    if ($phase -ne "drain") { $null = Invoke-NnDestructionGuard -Snap $nnSnap -Tag $phase }
    # 轉移快照的 after 點：緊貼 audit session 返回、在 lint／手術之前
    if ($phase -eq "audit") { $auditAfter = Get-AuditTransition }
    $sessionOk = ($r.ExitCode -eq 0)
    if (-not $sessionOk) {
        $errorStreak++
        Write-Log "SESSION 非零 exit（$errorStreak/2）——err 檔：$($r.ErrFile)"
        # 錯誤原因直接摘進主 log（否則「早上看 log 摘要即可」不成立——
        # 停機原因只寫「連續 2 次 session 錯誤」，真因還埋在 err 檔裡）
        if ($r.ErrFile -and (Test-Path -LiteralPath $r.ErrFile)) {
            # -Encoding UTF8 必要（L49）：opencode 輸出 UTF-8，PS 5.1 預設用 ANSI
            # 解碼 → 中文全亂碼，錯誤訊息等於讀不到
            $tail = @(Get-Content -LiteralPath $r.ErrFile -Tail 5 -Encoding UTF8 -ErrorAction SilentlyContinue |
                    Where-Object { $_.Trim() -ne '' })
            foreach ($tl in $tail) { Write-Log "  err> $tl" }
            if ($tail.Count -eq 0) { Write-Log "  err> （err 檔為空——session 可能在啟動階段就死，檢查 opencode 與模型服務）" }
        }
        if ($errorStreak -ge 2) { $stopReason = "連續 2 次 session 錯誤（需人工看 err log）"; break }
        # session 自行異常結束也可能留半寫檔（crash mid-write）——同樣驗一致性
        $fsProblems = Test-FsConsistency -HadChecklist $preHadChecklist -PreItemTotal $preItemTotal
        if ($fsProblems.Count -gt 0) {
            foreach ($pb in $fsProblems) { Write-Log "CONSISTENCY FAIL（session 錯誤後）：$pb" }
            $stopReason = "session 錯誤後一致性檢查 FAIL（$($fsProblems.Count) 項）——人工處理後再啟動"
            break
        }
    }
    else { $errorStreak = 0 }

    # 確定性調帳（issue #6／L93）：先調帳再驗完整性——節標題／輪次行由本層
    # 直接重建、silent loss 列由本層直接補回；下方 L90 檢查降格為最後一道
    # assertion（調帳修不了的才會走到回滾／停機）。
    $recB = Invoke-PostSessionReconcile -PreInv $preInv -PreRound $preRound -Tag $phase
    if ($recB.LegitRemoved -gt 0) {
        $preItemTotal -= $recB.LegitRemoved
        Write-Log "完整性基準調整：外環合法刪列 $($recB.LegitRemoved)（D 項治理／同文去重）→ 基準 $preItemTotal"
    }

    # checklist 完整性（L90 分級）：每 session 必驗，反應看傷勢——
    # 節標題消失、項目數未損＝閃爍性腐蝕，下個 session 整檔重寫會自然修復
    # （實測 57 輪默默修回 56 輪吃掉的節）→ 只記 WARN，不停不滾；
    # 項目總數下降＝列真的丟了，**不會自癒** → 回滾上一圈快照、本圈作廢
    # 重來；連續 2 圈仍發才停（系統性）。無人看管優先：能自己救就不叫人。
    $ci = Test-ChecklistIntegrity -PreTotal $preItemTotal
    if ($ci.Cosmetic.Count -gt 0 -and $ci.Lost.Count -eq 0) {
        foreach ($pb in $ci.Cosmetic) { Write-Log "CHECKLIST WARN（可自癒）：$pb——待下個 session 整檔重寫時修復" }
    }
    if ($ci.Lost.Count -gt 0) {
        foreach ($pb in $ci.Lost) { Write-Log "CHECKLIST 完整性 FAIL：$pb" }
        if (Invoke-ChecklistRecovery) {
            $corruptStreak++
            if ($corruptStreak -ge 2) { $stopReason = "連續 2 圈 checklist 列遺失（回滾後仍再發）——系統性問題，人工檢查後重啟"; break }
            Write-Log "本圈作廢（腐蝕連續計數 $corruptStreak/2），下一圈重來"
            continue
        }
        $stopReason = "checklist 列遺失且無法回滾（未開 -GitCommit 或 HEAD 無此領域）——人工依歸檔／快照修復（參考：git checkout HEAD -- 領域目錄）後重啟"
        break
    }
    $corruptStreak = 0

    if ($phase -eq "audit") {
        # 歸檔 commit（issue #13／L105）：稽核 session 只遞增輪次與打勾，
        # 已勾列的搬移在這裡由外環單一執行
        $null = Invoke-ChecklistArchiveCommit
        # Domain Gate 保險絲（issue #12／L104）：本輪新增未勾 D 項計數——
        # 超限＝疑似共用表反查外擴，停機交人工 scope review。
        # 上限是熔絲不是 gate：gate 在稽核契約（DOMAIN_ROOT 才准成 D）。
        $postInvD = Get-ChecklistInventory
        $newD = 0
        foreach ($k in $postInvD.Keys) {
            if ($k -notmatch '^wo:D') { continue }
            if ($null -ne $preInv -and $preInv.ContainsKey($k)) { continue }
            if ($postInvD[$k].Raw -match '^\s*-\s*\[ \]') { $newD++ }
        }
        if ($newD -gt $MaxNewDPerAudit) {
            $stopReason = "本輪稽核新增 D 項 $newD 筆 > 上限 $MaxNewDPerAudit（-MaxNewDPerAudit）——疑似 scope creep（共用表反查沿依賴圖外擴）。人工 scope review 未勾 D 提案：域根留、依附／域外整列刪，確認後再啟動"
            break
        }
    }

    # 標題正規化（L101／issue #10）：LLM 寫錯結構語法 → 確定性層修，
    # 不再回頭叫 LLM 修語法。冪等、無變體時零寫入；在 lint 評估前跑，
    # 「假缺章節」到不了工單。
    $fhRaw = & $lintPath -Domain $Domain -FixHeadings *>&1 | Out-String
    $fhN = @([regex]::Matches($fhRaw, '\[標題正規化\]')).Count
    if ($fhN -gt 0) { Write-Log "標題正規化：確定性修正 $fhN 個變體標題" }

    # 每個 session 後跑 lint；FAIL 且有手術清單→自動餵修復 session。
    # **手術用的尺必須跟 tier 一致**（L70）：tier 1 用 CoverageOnly——它的工單
    # 只出缺料類（[洩漏] 型）。用基礎 lint 會讓 tier 1 燒好幾個 session 去修
    # [欄位]／[證據] 這些不擋覆蓋畢業的美工類工單，那是 tier 2 的工作。
    $lint = if ($Tier -eq 1) { Invoke-Lint -Coverage } else { Invoke-Lint }
    Add-Content -Path (Join-Path $logRoot ("lint-cycle{0}.txt" -f $cycle)) -Value $lint.Raw -Encoding UTF8
    Write-Log "LINT exit=$($lint.Exit) 手術清單=$($lint.Surgical.Count) 筆"
    # L58：一圈可連跑多批手術（預設 3），條件是**上一批確實讓清單變短**。
    # 原本一圈只修 7 筆，而 tier 1 的相位多半是 audit——等於每修 7 筆就先燒
    # 一個 60 分的稽核 session（實案：錯放＋缺證據共 60 餘列，逐批要 6 圈
    # ≈12 小時，其中一半是白跑的稽核）。清單沒變短就停，避免空轉活鎖。
    $fatalStop = $false
    $cycleRedo = $false
    $surgeryRound = 0
    $surgeryLedger = Get-SurgeryLedger
    # 有工單就修，不綁 exit（L79）：[回灌] 型是「稽核已查到答案」的機械修復，
    # 本身不是違規——lint 可能 exit 0 卻仍有工單，綁 exit 會讓它永遠不被套用。
    # 選批跳過 BLOCKED（issue #11）：毒丸靠邊，後方健康工單照常服務；
    # 煞車改「身分尺」：舊工單有被解決才算進度（掉 A 生 D 的總數平手＝有進度）。
    while ((Get-ActionableSurgicalCount -Surgical $lint.Surgical -Ledger $surgeryLedger) -gt 0 -and
        $surgeryRound -lt $MaxSurgeryPerCycle) {
        $surgeryRound++
        $beforeSet = @{}
        foreach ($sLn in $lint.Surgical) { $beforeSet[(Get-OrderFingerprint $sLn)] = $true }
        $batch = Select-SurgeryBatch -Surgical $lint.Surgical -Ledger $surgeryLedger -Size $SurgeryBatchSize
        if ($batch.Count -eq 0) { break }
        if ($lint.Surgical.Count -gt $batch.Count) { Write-Log "手術清單 $($lint.Surgical.Count) 筆（含 BLOCKED），本批修 $($batch.Count) 筆（第 $surgeryRound/$MaxSurgeryPerCycle 批）" }
        $flat = ($batch -join "；") -replace '"', "'"
        # 禁令必要：ps-deep-research 在 checklist 全勾時會自行接跑稽核（agent 啟動
        # 規則），改寫 90-audit.md／輪次會污染本圈的畢業判定與下圈的轉移基準
        # L43：prompt 與 lint 工單同步——先判型別再動手，B 型委派 oracle flow、
        # 禁 peoplecode 代償、有合法終止出口（否則 B 型項目＝無限迴圈）
        # L53／L57：清單混有三種型別——prompt 必須先分流，否則洩漏型／欄位型
        # 會被套上證據型的修法（去找 chunk id）而做無解的事（L43 同族）
        $sPrompt = "lint 修復清單逐筆處理，先看方括號型別再動手。[回灌] 型＝稽核已經查到答案（來自 90-audit.md 明細的處置欄）：**純字串替換，不要重查、不要呼叫任何檢索工具**——read 該檔，把工單所給的舊 UUID 的**所有出現處**換成新 UUID（同一 chunk 常被多列引用，漏換等於下輪再開一次單）；只用新 id 呼叫一次 get_chunks_details 驗貨，回傳 ChunkText 必須含該列原引文，不含＝抓錯 chunk，禁止硬填、該筆記收據跳過；舊 UUID 在該檔找不到＝該列已被改過或刪除，記收據跳過不要硬塞；更新行號／更新數值同理，依所給新值改該列，內容一個字都不動。[欄位] 型＝證據其實在位置欄、機器參照欄放的是標籤：**純編輯，不要重查也不要呼叫任何工具**，把可重跑的那一份（完整36字元ChunkId 或 SELECT…FROM…）搬到機器參照欄，位置欄改放 filePath:行號 或表名鍵值；證據內容一個字都不要改，改短或憑印象重打就是捏造。[洩漏] 型＝模型內部標記寫進交付物：read 該檔看標記前後整個區塊有無被截斷（表格斷半路、章節缺下半段、混進推理獨白或工具回傳原文），刪標記與所有非交付內容，補回被截斷的內容（證據照原有 chunk id 或 SQL 重取，禁止憑印象重寫）；補不回＝該段已遺失，在該檔未解事項記一行「章節因寫入脫軌遺失待重查」後停止該筆，不得編造。[章節] 型＝檔案缺必要模板章節：**補研究不是機械修**——read 該檔辨識主角物件，既有內容與既有證據全部保留；所缺章節依 function-detail 模板補寫，內容須經委派檢索取證（委派對象限 ps-peoplecode-flow／ps-sql-flow／ps-sqr-flow／ps-ae-flow／ps-metadata-flow 五者），Evidence 附錄要完整36字元ChunkId 且逐字取自工具回傳；取證不到的節照實寫「查無＋查法收據」進未解事項，不得編造充版面；該節對物件型別不適用時（如 Function Library 無使用者畫面之於畫面與欄位）＝章節標題仍要就位、內文寫（無——一句原因），誠實申報不適用即合格，只有標題缺席才是違規，禁止為湊內容編造畫面。[附錄] 型＝Evidence 附錄是裸 ChunkId 清單、不是模板表格：read 該檔並 read report-templates 的 function-detail-template.md 的 Evidence 附錄節，把附錄重建為四欄表格（表頭欄名逐字照抄模板：編號、位置、說明、機器參照），節內每個裸 ChunkId 各委派一次解引用（get_chunks_details）取得 filePath 行號與內容摘要後逐筆成列，機器參照欄放完整36字元UUID；解不了的 id 該筆移除並在該檔未解事項記一行查法收據；禁止憑印象編位置或說明，本文其他章節一字不動。[證據] 型＝先判 CHUNK 或 SQL：CHUNK 型（程式碼）＝filePath 重取、驗貨（回傳須含原引文）、只補完整36字元id，委派對象限 ps-peoplecode-flow／ps-sql-flow／ps-sqr-flow／ps-ae-flow／ps-metadata-flow 五者之一（禁 general、explore、scout——四個MCP全封等於零工具，派過去必然轉圈到逾時；CHUNK型也禁 ps-ui-flow，它沒有ES與Source），首選查無時改派 ps-ae-flow 或 ps-metadata-flow（四工具全譜）再試一次、兩個管道都查無才算查無；SQL／metadata 型（DB 表如 PSPRCSRQST）＝委派具 oracleMCP 權限的 flow（ps-metadata-flow 等）照 cookbook 重查、機器參照改寫成 SQL：SELECT…、你自己沒有 SQL 工具是圍堵設計、禁止改查 peoplecode 代償；皆不可得＝該筆輸出收據「舊值 → 待人工SQL」或「移除入gaps」後停止該筆。每筆附收據；只准修改清單所列檔案，禁止修改 checklist.md 與 90-audit.md，禁止執行稽核：$flat"
        # 每批手術前重拍身分快照（前批的合法改動不能算進本批的損失）
        $sPreInv = Get-ChecklistInventory
        # 破壞防衛快照（L103）：每批重拍——前批的合法改寫是新基準
        $sNnSnap = Get-NnGuardSnapshot
        $sr = Invoke-Opencode -ExtraArgs '--agent ps-deep-research' -PromptText $sPrompt `
            -TimeoutMin $ResearchTimeoutMin -Tag "surgery"
        # 破壞防衛（L103）：實案的「只剩 Evidence 節」正是手術路徑寫壞的
        $null = Invoke-NnDestructionGuard -Snap $sNnSnap -Tag "surgery-第$surgeryRound批"
        # 手術 session 也在保險絲與一致性檢查的守備範圍（原本 $sr 沒人看＝
        # 強殺後半寫狀態恰好發生在唯一沒人看的路徑上）
        if ($sr.TimedOut) {
            $fsProblems = Test-FsConsistency -HadChecklist $preHadChecklist -PreItemTotal $preItemTotal
            if ($fsProblems.Count -gt 0) {
                foreach ($pb in $fsProblems) { Write-Log "CONSISTENCY FAIL（手術後）：$pb" }
                $stopReason = "手術 session 強殺後一致性檢查 FAIL（$($fsProblems.Count) 項）——人工處理後再啟動"
                $fatalStop = $true
                break
            }
            Write-Log "手術 session 逾時強殺——一致性檢查 PASS，續跑"
        }
        elseif ($sr.ExitCode -ne 0) { Write-Log "手術 session 非零 exit=$($sr.ExitCode)（記錄；不計入 research 的 errorStreak）" }
        # 手術 session 獨立熔絲（issue #11 P0-6）：session 級故障（逾時／非零
        # exit）不冤枉工單（不計 attempts）、不污染 research streak，但也不能
        # 無聲反覆燒整個 timeout——連 2 次即停本圈手術。
        $srHealthy = ((-not $sr.TimedOut) -and ($sr.ExitCode -eq 0))
        if (-not $srHealthy) {
            $surgeryFailStreak++
            if ($surgeryFailStreak -ge 2) {
                Write-Log "手術 session 連續 $surgeryFailStreak 次異常（逾時/非零 exit）——本圈手術停用，工單不計 attempts（session 級故障非工單故障），下一圈再試"
                break
            }
        }
        else { $surgeryFailStreak = 0 }
        $recS = Invoke-PostSessionReconcile -PreInv $sPreInv -PreRound $preRound -Tag "surgery-$surgeryRound"
        if ($recS.LegitRemoved -gt 0) {
            $preItemTotal -= $recS.LegitRemoved
            Write-Log "完整性基準調整（手術後）：外環合法刪列 $($recS.LegitRemoved) → 基準 $preItemTotal"
        }
        $ci = Test-ChecklistIntegrity -PreTotal $preItemTotal
        if ($ci.Cosmetic.Count -gt 0 -and $ci.Lost.Count -eq 0) {
            foreach ($pb in $ci.Cosmetic) { Write-Log "CHECKLIST WARN（可自癒，手術第 $surgeryRound 批）：$pb" }
        }
        if ($ci.Lost.Count -gt 0) {
            foreach ($pb in $ci.Lost) { Write-Log "CHECKLIST 完整性 FAIL（手術第 $surgeryRound 批）：$pb" }
            if (Invoke-ChecklistRecovery) {
                $corruptStreak++
                if ($corruptStreak -ge 2) { $stopReason = "連續 2 圈 checklist 列遺失——系統性問題，人工檢查後重啟"; $fatalStop = $true }
                else { $cycleRedo = $true }
            }
            else {
                $stopReason = "checklist 列遺失且無法回滾——人工修復後重啟"
                $fatalStop = $true
            }
            break
        }
        $lint2 = if ($Tier -eq 1) { Invoke-Lint -Coverage } else { Invoke-Lint }
        Write-Log "LINT(術後第 $surgeryRound 批) exit=$($lint2.Exit) 手術清單=$($lint2.Surgical.Count) 筆"
        $lint = $lint2
        # 身分尺進度＋attempts 記帳（issue #11 P0-3/P0-5）：
        #   resolved＝session 前存在、session 後消失的工單數（count 平手也可能
        #   有進度：掉 A 生 D）。只有**健康 session** 才記 attempts——批內工單
        #   仍在＝該筆得到公平嘗試而未解，attempts≥2 → BLOCKED（跳頭、可見、
        #   人工清單＝surgery-ledger.json；lint 一旦不出該單即自動剪枝）。
        $afterSet = @{}
        foreach ($sLn in $lint.Surgical) { $afterSet[(Get-OrderFingerprint $sLn)] = $true }
        $resolved = 0
        foreach ($k in $beforeSet.Keys) { if (-not $afterSet.ContainsKey($k)) { $resolved++ } }
        if ($srHealthy) {
            $seenFp = @{}
            foreach ($bLn in $batch) {
                $fp = Get-OrderFingerprint $bLn
                # 正規化後同指紋只記一次（L103）：同檔同型多列剝行號後會合流，
                # 不去重會一批灌兩次 attempts、首批就冤枉 BLOCKED
                if ($seenFp.ContainsKey($fp)) { continue }
                $seenFp[$fp] = $true
                if (-not $afterSet.ContainsKey($fp)) { continue }   # 已解，剪枝交給 Save
                if (-not $surgeryLedger.ContainsKey($fp)) { $surgeryLedger[$fp] = @{ attempts = 0; blocked = $false } }
                $surgeryLedger[$fp].attempts++
                if ($surgeryLedger[$fp].attempts -ge 2 -and -not $surgeryLedger[$fp].blocked) {
                    $surgeryLedger[$fp].blocked = $true
                    $fpShow = $fp
                    if ($fpShow.Length -gt 80) { $fpShow = $fpShow.Substring(0, 80) + "…" }
                    Write-Log "手術停滯 BLOCKED（attempts=2）：$fpShow ——跳頭續修後方，人工清單見 surgery-ledger.json"
                }
            }
        }
        $surgeryLedger = Save-SurgeryLedger -Ledger $surgeryLedger -CurrentSurgical $lint.Surgical
        if ($resolved -eq 0) {
            Write-Log "本批零解決（身分尺：舊單消失 0 筆；總數 $($lint.Surgical.Count)）——停止本圈續修，交下一圈或台帳隔離"
            break
        }
        Write-Log "本批解決 $resolved 筆（身分尺）"
    }
    if ($fatalStop) { break }
    if ($cycleRedo) { Write-Log "本圈作廢（腐蝕連續計數 $corruptStreak/2），下一圈重來"; continue }

    # 進度與畢業判定
    $after = Get-ChecklistState
    $gitNoteLint = "lint exit=$($lint.Exit) 工單 $($lint.Surgical.Count) 筆"
    if ($phase -eq "drain") {
        # 排水圈進度＝可執行債有沒有變少（身分尺）；未勾數／缺料數與本圈
        # 無關，不得餵給 research／audit 的熔絲（issue #11 P0-7）
        $ledgerAfterD = Get-SurgeryLedger
        $actionableAfter = Get-ActionableSurgicalCount -Surgical $lint.Surgical -Ledger $ledgerAfterD
        if ($actionableAfter -ge $actionableD) {
            $drainNoProgress++
            Write-Log "排水圈無進度（$drainNoProgress/2）：可執行債 $actionableD→$actionableAfter——達 2 退回正常相位（殘債見 surgery-ledger.json）"
        }
        else {
            $drainNoProgress = 0
            Write-Log "排水圈進度：可執行債 $actionableD→$actionableAfter"
        }
    }
    elseif ($phase -eq "audit") {
        # 三層畢業門（issue #2）——外環保證「有沒有做」，內層約束「怎麼做」
        # ★ 改動本門判定＝必須 bump ps-graduation.ps1 的 GraduationGateVersion，
        #   否則舊門發的收據對新門永久有效（門邏輯不在任何 hash 覆蓋內）
        # 第 2 層：輪次比對用 -gt 不用嚴格 +1（research 圈的當場稽核也會 +1、
        # 模型可能跳號——遞增即可證明「本 session 寫過」，嚴格等號只會誤殺）
        $transitionOk = $false
        if ($null -ne $auditAfter) {
            $transitionOk = ($auditAfter.Round -gt $auditBefore.Round) -and
                            ($auditAfter.Hash -ne "") -and
                            ($auditAfter.Hash -ne $auditBefore.Hash)
        }
        # 第 3 層：驗收檢查——依 tier 換一把尺（其餘兩層兩個 tier 共用）
        #   tier 1：lint -CoverageOnly 全過＝缺料已清（美工類降警告，不擋）
        #   tier 2：未勾=0＋基礎 lint 全過＋StrictAudit 全過（原判定，一字未改）
        $strictDesc = "未評（基礎條件未過）"
        $validationOk = $false
        if ($Tier -eq 1) {
            $coverAfter = Invoke-Lint -Coverage
            Add-Content -Path (Join-Path $logRoot ("coverage-cycle{0}.txt" -f $cycle)) `
                -Value $coverAfter.Raw -Encoding UTF8
            $validationOk = ($coverAfter.Exit -eq 0)
            $strictDesc = if ($validationOk) { "CoverageOnly OK（缺料已清）" } else { "CoverageOnly FAIL（見 coverage-cycle$cycle.txt）" }
        }
        elseif ($after.Unticked -eq 0 -and $lint.Exit -eq 0) {
            $strict = Invoke-Lint -Strict
            Add-Content -Path (Join-Path $logRoot ("strict-cycle{0}.txt" -f $cycle)) `
                -Value $strict.Raw -Encoding UTF8
            $validationOk = ($strict.Exit -eq 0)
            $strictDesc = if ($validationOk) { "OK" } else { "StrictAudit FAIL（見 strict-cycle$cycle.txt）" }
        }
        $tDesc = if ($null -ne $auditAfter) {
            "輪次 $($auditBefore.Round)→$($auditAfter.Round)、hash$(if ($auditAfter.Hash -ne $auditBefore.Hash -and $auditAfter.Hash -ne '') {'已變'} else {'未變'})"
        }
        else { "無快照" }
        Write-Log "GATE(tier $Tier)：session=$(if ($sessionOk) {'OK'} else {'exit≠0'}) transition=$(if ($transitionOk) {'OK'} else {'FAIL'})（$tDesc） validation=$strictDesc"
        # 基礎條件：tier 1 不看未勾數與基礎 lint（那是美工；補強項留給 tier 2）
        $baseOk = $true
        if ($Tier -eq 2) { $baseOk = ($after.Unticked -eq 0 -and $lint.Exit -eq 0) }
        if ($sessionOk -and $transitionOk -and $baseOk -and $validationOk) {
            $graduated = $true
            # 過門當下快照 contentHash——寫收據時重算比對（TOCTOU 防護）；
            # auditRound 用轉移快照的正規化輪次，不在寫收據時重讀 checklist
            $gradContentHash = Get-DomainContentHash -DomainDir $dir
            $gradAuditRound = $auditAfter.Round
            if ($Tier -eq 1) {
                $stopReason = "覆蓋畢業（tier 1／可用）：稽核輪次 $($auditAfter.Round)、缺料已清；未勾 $($after.Unticked) 項屬補強類，留待 tier 2"
                # 畢業收尾提醒（L52）：00-overview 是**凍結快照**，不隨輪次更新
                # ——畢業當下它多半已經落後好幾輪。SOP-15 的第一個觸發時機就是
                # 「畢業收尾」，但那需要人記得；把 lint 的機械 diff 結果在這裡
                # 講出來，換版才不會靠人自己想到（實案：領域畢業後導航頁仍停在
                # 一個月前，且畢業訊息完全沒提這件事）。
                $mapWarn = [regex]::Match($coverAfter.Raw, '功能地圖缺 (\d+) 個後續發現的項目')
                if ($mapWarn.Success) {
                    Write-Log "畢業收尾待辦：00-overview 功能地圖缺 $($mapWarn.Groups[1].Value) 個後續發現的項目——凍結快照已落後，照 SOP-15 換版（人工程序；換版會使本收據 contentHash 失效，屬預期）"
                }
                else {
                    Write-Log "畢業收尾檢查：00-overview 功能地圖無缺頁（機械 diff）——但產生日期仍是階段一那天，內容是否需要換版由人判斷（SOP-15）"
                }
            }
            else {
                $stopReason = "精修畢業（tier 2）：三層門全過（稽核輪次 $($auditAfter.Round)、無新 A 項、lint＋StrictAudit 全過）"
            }
            break
        }
        if ($after.Unticked -gt 0 -or $auditRoundProgress -gt 0) {
            if ($after.Unticked -gt 0) { Write-Log "audit 回灌 $($after.Unticked) 項，續跑" }
            else { Write-Log "audit 輪次分批進行中（本圈收據 +$auditRoundProgress，尚未合併）——不計零回灌，續跑" }
            $auditStall = 0
        }
        else {
            # 零回灌又未畢業＝被門擋下（transition／strict／session）——這種圈沒有
            # 自動修復管道（strict 違規不產手術清單、audit prompt 也收不到 lint 結果），
            # 連續發生只會空轉活鎖，熔斷進人工
            $auditStall++
            Write-Log "audit 圈零回灌且未畢業（$auditStall/2）——擋下原因見上方 GATE 行"
            if ($auditStall -ge 2) {
                # 停機訊息帶殘債實況（issue #11 P0-7）：只剩 BLOCKED 時要講清楚
                # 人工要做什麼，不是一句「無自動修復管道」帶過
                $ledgerStop = Get-SurgeryLedger
                $blockedN = @($ledgerStop.Keys | Where-Object { $ledgerStop[$_].blocked }).Count
                $blockedHint = ""
                if ($blockedN -gt 0) { $blockedHint = "；另有 $blockedN 筆 BLOCKED 手術工單需人工（清單與 attempts 見 auto-loop-logs\$Domain\surgery-ledger.json，處理完刪該檔即重新放行）" }
                $stopReason = "audit 相位連續 2 圈零回灌未畢業（門檻擋下、無自動修復管道）——看 GATE 行與 strict-cycle*.txt 後人工處理$blockedHint"
                break
            }
        }
        $noProgress = 0
        $drainNoProgress = 0
    }
    else {
        # 進度量測也要換尺（否則 tier 1 會被自己的成功誤殺）：
        #   tier 1 量「缺料違規數有沒有變少」——未勾數在補料期本來就會長大
        #     （勾掉 2 個、稽核回灌 3 個＝未勾淨增，但實際做了 5 項的工），
        #     照未勾數量進度＝把正在推進的 run 判成卡住。
        #   tier 2 量未勾數（原判定）——該階段不再有新覆蓋，未勾只該往下走。
        $stalled = $false
        $howDesc = ""
        if ($Tier -eq 1) {
            if ($null -ne $coverBefore) {
                $coverAfterR = Invoke-Lint -Coverage
                $cb = @([regex]::Matches($coverBefore.Raw, '(?m)^FAIL：(\d+) 項違規'))
                $ca = @([regex]::Matches($coverAfterR.Raw, '(?m)^FAIL：(\d+) 項違規'))
                $nb = if ($cb.Count -gt 0) { [int]$cb[0].Groups[1].Value } else { 0 }
                $na = if ($ca.Count -gt 0) { [int]$ca[0].Groups[1].Value } else { 0 }
                $stalled = ($na -ge $nb -and $nb -gt 0)
                Add-Content -Path (Join-Path $logRoot ("coverage-cycle{0}-post.txt" -f $cycle)) `
                    -Value $coverAfterR.Raw -Encoding UTF8
                $howDesc = "缺料違規 $nb→$na（清單見 coverage-cycle$cycle-post.txt）"
            }
        }
        else {
            $stalled = ($before.Exists -and $after.Unticked -ge $before.Unticked -and $before.Unticked -gt 0)
            $howDesc = "未勾 $($before.Unticked)→$($after.Unticked)"
        }
        # 供人工判讀：未勾數的走向照樣記，只是 tier 1 不拿它當熔絲
        Write-Log "research 圈進度：$howDesc｜未勾 $($before.Unticked)→$($after.Unticked)（tier 1 不以未勾數判進度）"
        if ($stalled) {
            $noProgress++
            Write-Log "research 圈無進度（$noProgress/2）：$howDesc"
            if ($noProgress -ge 2) { $stopReason = "連續 2 圈無進度（$howDesc；卡住的項需人工裁決）"; break }
        }
        else { $noProgress = 0 }
        $drainNoProgress = 0
    }
    # 每圈一個還原點（L83）：session 崩在半路是常態故障，
    # 有 commit 才敢讓它無人看管——只 commit、永不 push。
    Invoke-GitSnapshot -Note "第 $cycle 圈 $phase｜$gitNoteLint｜$(if ($graduated) { "畢業 tier $Tier" } else { '未畢業' })"
}

# ── 收場摘要 ────────────────────────────────────────────────
$final = Get-ChecklistState
Invoke-GitSnapshot -Note "收場｜$stopReason"
Write-Log "=== auto-loop 停機：$stopReason ==="
Write-Log "最終狀態：未勾=$($final.Unticked) 已勾=$($final.Ticked) 稽核輪次=$($final.Round) tier=$Tier 畢業=$graduated"
if ($graduated -and $Tier -eq 1) {
    Write-Log "本領域已達 tier 1（可用／80 分）：未勾 $($final.Unticked) 項屬補強類，可留待 tier 2 精修圈處理（SOP-13：建議不是債）"
}
Write-Log "人工待辦：缺料清單→跑 ps-doc-lint.ps1 -Domain $Domain -CoverageOnly（現況，不是快照）；歷程→coverage-cycle*-pre/post.txt 與 lint-cycle*.txt；session 細節→同目錄 out/err；tier 2 門→strict-cycle*.txt；卡住項與 lesson 建議→90-audit.md 與 checklist.md"

# 畢業收據（issue #3）：只在畢業門全過後寫；寫入失敗＝automation 不可信（exit 2）
# 收據記 tier——tier 1 收據放不了 tier 2 的行（Test-GraduationReceipt -RequiredTier）
if ($graduated) {
    $rcResult = Write-GraduationReceipt -DomainDir $dir -Domain $Domain `
        -AuditRound $gradAuditRound -LintScriptPath $lintPath `
        -GateScriptPath $gradLibPath -ExpectedContentHash $gradContentHash -Tier $Tier
    if ($rcResult.Ok) {
        Write-Log "畢業收據已寫入 graduation.json（tier=$Tier auditRound=$gradAuditRound）"
        # ── 歸戶提煉（L86）：wiki 只在畢業後從 NN 提煉。收據**先發**（wiki 在
        #    領域目錄外，不影響 contentHash）；提煉失敗不撤畢業，餘量下次畢業續跑。
        #    session 禁委派禁檢索＝純 read NN／write wiki，不佔 MCP。
        $wm = Get-WikiMissing
        $distillRound = 0
        while ($wm -gt 0 -and $distillRound -lt 4) {
            $distillRound++
            Write-Log "歸戶提煉第 $distillRound 輪：待歸戶 $wm 個物件"
            $dPrompt = "歸戶提煉：照你 system prompt 的「提煉模式」處理 docs/ps-research/$Domain/ 的 NN 檔。只 read NN 檔與 wiki、只 write wiki 與 index；禁止委派、禁止任何檢索；evidence 逐字複製 NN 檔既有的 ChunkId 與 SQL。"
            $dPreInv = Get-ChecklistInventory
            $dr = Invoke-Opencode -ExtraArgs '--agent ps-deep-research' -PromptText $dPrompt `
                -TimeoutMin $ResearchTimeoutMin -Tag "distill"
            # 提煉 session 規則上不碰 checklist——調帳在此是守門不是修復
            $null = Invoke-PostSessionReconcile -PreInv $dPreInv -PreRound $final.Round -Tag "distill-$distillRound"
            $wm2 = Get-WikiMissing
            Write-Log "歸戶提煉第 $distillRound 輪結束：待歸戶 $wm → $wm2"
            if ($wm2 -ge $wm) { Write-Log "提煉未收斂——停止（餘 $wm2 個記人工或下次畢業續跑）"; break }
            $wm = $wm2
        }
        if ($Tier -eq 2) {
            $uPrompt = "entity 升級：照你 system prompt 的「提煉模式」第 3 條處理 docs/ps-research/$Domain/——本領域 NN 檔 [[連結]] 到的 entity 中 status: draft 改 verified（reviewed 與 stale 不動）。只 read／write wiki，禁止委派與檢索。"
            $uPreInv = Get-ChecklistInventory
            $ur = Invoke-Opencode -ExtraArgs '--agent ps-deep-research' -PromptText $uPrompt `
                -TimeoutMin $ResearchTimeoutMin -Tag "distill-upgrade"
            $null = Invoke-PostSessionReconcile -PreInv $uPreInv -PreRound $final.Round -Tag "distill-upgrade"
            Write-Log "entity 升級 session 結束（tier 2）"
        }
        Invoke-GitSnapshot -Note "歸戶提煉收尾（餘 $wm 待歸戶）"
    }
    else {
        Write-Log "畢業收據寫入失敗：$($rcResult.Reason)——exit 2（system error）"
        $mutex.ReleaseMutex(); $mutex.Dispose()
        exit 2
    }
}
$mutex.ReleaseMutex(); $mutex.Dispose()
if ($graduated) { exit 0 } else { exit 1 }
