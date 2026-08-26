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
            if ((-not $isWorkOrder) -and ($row -match '任務\s*[ABC]|批次\s*\d+\s*[/／]\s*\d+')) { continue }
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

# 統一調帳邊界（P0-4）：任何 session 之後都走這裡——log 有跡可查
function Invoke-PostSessionReconcile {
    param([hashtable]$PreInv, [int]$PreRound, [string]$Tag)
    $rec = Invoke-ChecklistReconcile -PreInv $PreInv -PreRound $PreRound
    if ($rec.Rebuilt.Count -gt 0) { Write-Log "CHECKLIST 骨架修復（$Tag）：$($rec.Rebuilt -join '、')——確定性重建，不停機不等自癒" }
    if ($rec.Restored -gt 0) { Write-Log "CHECKLIST 調帳（$Tag）：補回 $($rec.Restored) 列 silent loss（身分比對；總數比對抓不到掉一補一）" }
    if ($rec.SkippedTransformed -gt 0) { Write-Log "CHECKLIST 調帳（$Tag）：$($rec.SkippedTransformed) 列身分消失但錨點仍在活頁＝被改寫非遺失——不復活（session 不該改寫工單列文字，見 L96）" }
    if ($rec.SkippedRepeat -gt 0) { Write-Log "CHECKLIST 調帳（$Tag）：$($rec.SkippedRepeat) 列二次消失（上次已補回過）＝持續被改寫——斷路器生效，不再復活" }
    if ($rec.Deduped -gt 0) { Write-Log "CHECKLIST 調帳（$Tag）：收斂 $($rec.Deduped) 列同文重複" }
    return $rec
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
        return @{ TimedOut = $true; ExitCode = -1; ErrFile = $errFile; OutFile = $outFile }
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
    return @{ TimedOut = $false; ExitCode = $code; ErrFile = $errFile; OutFile = $outFile }
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

# ── 主迴圈 ──────────────────────────────────────────────────
Write-Log "=== auto-loop 啟動：領域=$Domain MaxCycles=$MaxCycles Model=$(if($Model){$Model}else{'(全域預設)'}) ==="
$corruptStreak = 0
$timeoutStreak = 0
$errorStreak = 0
$noProgress = 0
$auditStall = 0
$graduated = $false
$gradContentHash = $null
$gradAuditRound = 0
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
    if ($goResearch) {
        $phase = "research"
        $r = Invoke-Opencode -ExtraArgs '--command ps-research' -PromptText $Domain `
            -TimeoutMin $ResearchTimeoutMin -Tag "research"
    }
    else {
        $phase = "audit"
        $auditBefore = Get-AuditTransition
        $r = Invoke-Opencode -ExtraArgs '--command ps-audit' -PromptText $Domain `
            -TimeoutMin $AuditTimeoutMin -Tag "audit"
    }

    # 保險絲：逾時（強殺後先驗檔案一致性——FAIL 即停機進人工，不進下一圈）
    if ($r.TimedOut) {
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
    $null = Invoke-PostSessionReconcile -PreInv $preInv -PreRound $preRound -Tag $phase

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
    # 有工單就修，不綁 exit（L79）：[回灌] 型是「稽核已查到答案」的機械修復，
    # 本身不是違規——lint 可能 exit 0 卻仍有工單，綁 exit 會讓它永遠不被套用。
    while ($lint.Surgical.Count -gt 0 -and $surgeryRound -lt $MaxSurgeryPerCycle) {
        $surgeryRound++
        $beforeSurgical = $lint.Surgical.Count
        $batch = @($lint.Surgical | Select-Object -First $SurgeryBatchSize)
        if ($lint.Surgical.Count -gt $SurgeryBatchSize) { Write-Log "手術清單 $($lint.Surgical.Count) 筆，本批先修 $SurgeryBatchSize 筆（第 $surgeryRound/$MaxSurgeryPerCycle 批；本圈最多處理 $($SurgeryBatchSize * $MaxSurgeryPerCycle) 筆，其餘交下一圈）" }
        $flat = ($batch -join "；") -replace '"', "'"
        # 禁令必要：ps-deep-research 在 checklist 全勾時會自行接跑稽核（agent 啟動
        # 規則），改寫 90-audit.md／輪次會污染本圈的畢業判定與下圈的轉移基準
        # L43：prompt 與 lint 工單同步——先判型別再動手，B 型委派 oracle flow、
        # 禁 peoplecode 代償、有合法終止出口（否則 B 型項目＝無限迴圈）
        # L53／L57：清單混有三種型別——prompt 必須先分流，否則洩漏型／欄位型
        # 會被套上證據型的修法（去找 chunk id）而做無解的事（L43 同族）
        $sPrompt = "lint 修復清單逐筆處理，先看方括號型別再動手。[回灌] 型＝稽核已經查到答案（來自 90-audit.md 明細的處置欄）：**純字串替換，不要重查、不要呼叫任何檢索工具**——read 該檔，把工單所給的舊 UUID 的**所有出現處**換成新 UUID（同一 chunk 常被多列引用，漏換等於下輪再開一次單）；只用新 id 呼叫一次 get_chunks_details 驗貨，回傳 ChunkText 必須含該列原引文，不含＝抓錯 chunk，禁止硬填、該筆記收據跳過；舊 UUID 在該檔找不到＝該列已被改過或刪除，記收據跳過不要硬塞；更新行號／更新數值同理，依所給新值改該列，內容一個字都不動。[欄位] 型＝證據其實在位置欄、機器參照欄放的是標籤：**純編輯，不要重查也不要呼叫任何工具**，把可重跑的那一份（完整36字元ChunkId 或 SELECT…FROM…）搬到機器參照欄，位置欄改放 filePath:行號 或表名鍵值；證據內容一個字都不要改，改短或憑印象重打就是捏造。[洩漏] 型＝模型內部標記寫進交付物：read 該檔看標記前後整個區塊有無被截斷（表格斷半路、章節缺下半段、混進推理獨白或工具回傳原文），刪標記與所有非交付內容，補回被截斷的內容（證據照原有 chunk id 或 SQL 重取，禁止憑印象重寫）；補不回＝該段已遺失，在該檔未解事項記一行「章節因寫入脫軌遺失待重查」後停止該筆，不得編造。[章節] 型＝檔案缺必要模板章節：**補研究不是機械修**——read 該檔辨識主角物件，既有內容與既有證據全部保留；所缺章節依 function-detail 模板補寫，內容須經委派檢索取證（委派對象限 ps-peoplecode-flow／ps-sql-flow／ps-sqr-flow／ps-ae-flow／ps-metadata-flow 五者），Evidence 附錄要完整36字元ChunkId 且逐字取自工具回傳；取證不到的節照實寫「查無＋查法收據」進未解事項，不得編造充版面。[證據] 型＝先判 CHUNK 或 SQL：CHUNK 型（程式碼）＝filePath 重取、驗貨（回傳須含原引文）、只補完整36字元id，委派對象限 ps-peoplecode-flow／ps-sql-flow／ps-sqr-flow／ps-ae-flow／ps-metadata-flow 五者之一（禁 general、explore、scout——四個MCP全封等於零工具，派過去必然轉圈到逾時；CHUNK型也禁 ps-ui-flow，它沒有ES與Source），首選查無時改派 ps-ae-flow 或 ps-metadata-flow（四工具全譜）再試一次、兩個管道都查無才算查無；SQL／metadata 型（DB 表如 PSPRCSRQST）＝委派具 oracleMCP 權限的 flow（ps-metadata-flow 等）照 cookbook 重查、機器參照改寫成 SQL：SELECT…、你自己沒有 SQL 工具是圍堵設計、禁止改查 peoplecode 代償；皆不可得＝該筆輸出收據「舊值 → 待人工SQL」或「移除入gaps」後停止該筆。每筆附收據；只准修改清單所列檔案，禁止修改 checklist.md 與 90-audit.md，禁止執行稽核：$flat"
        # 每批手術前重拍身分快照（前批的合法改動不能算進本批的損失）
        $sPreInv = Get-ChecklistInventory
        $sr = Invoke-Opencode -ExtraArgs '--agent ps-deep-research' -PromptText $sPrompt `
            -TimeoutMin $ResearchTimeoutMin -Tag "surgery"
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
        elseif ($sr.ExitCode -ne 0) { Write-Log "手術 session 非零 exit=$($sr.ExitCode)（記錄；不計入 errorStreak）" }
        $null = Invoke-PostSessionReconcile -PreInv $sPreInv -PreRound $preRound -Tag "surgery-$surgeryRound"
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
        if ($lint.Surgical.Count -ge $beforeSurgical) {
            Write-Log "本批未讓手術清單變短（$beforeSurgical → $($lint.Surgical.Count)）——停止本圈續修，交下一圈或人工處理"
            break
        }
    }
    if ($fatalStop) { break }
    if ($cycleRedo) { Write-Log "本圈作廢（腐蝕連續計數 $corruptStreak/2），下一圈重來"; continue }

    # 進度與畢業判定
    $after = Get-ChecklistState
    $gitNoteLint = "lint exit=$($lint.Exit) 工單 $($lint.Surgical.Count) 筆"
    if ($phase -eq "audit") {
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
        if ($after.Unticked -gt 0) {
            Write-Log "audit 回灌 $($after.Unticked) 項，續跑"
            $auditStall = 0
        }
        else {
            # 零回灌又未畢業＝被門擋下（transition／strict／session）——這種圈沒有
            # 自動修復管道（strict 違規不產手術清單、audit prompt 也收不到 lint 結果），
            # 連續發生只會空轉活鎖，熔斷進人工
            $auditStall++
            Write-Log "audit 圈零回灌且未畢業（$auditStall/2）——擋下原因見上方 GATE 行"
            if ($auditStall -ge 2) {
                $stopReason = "audit 相位連續 2 圈零回灌未畢業（門檻擋下、無自動修復管道）——看 GATE 行與 strict-cycle*.txt 後人工處理"
                break
            }
        }
        $noProgress = 0
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
