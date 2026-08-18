# ps-auto-loop.ps1 — research→audit→lint 自動迴圈駕駛
# 設計：確定性外環（本腳本）＋模型內步（opencode run 新鮮 session）＋確定性驗收（lint／checklist 解析）
# 用法：.\scripts\ps-auto-loop.ps1 -Domain 轉職
#       .\scripts\ps-auto-loop.ps1 -Domain 轉職 -MaxCycles 12 -Model "provider/model-id"
#
# opencode headless 事實（v1.17.15 原始碼確認）：
#   - run 訊息裡的 "/指令" 不展開（slash 只在互動編輯器）——用 --command <名> 帶入，
#     訊息成為 $ARGUMENTS；command frontmatter 的 agent/model 生效
#   - 不加 --auto：ask 類權限自動拒絕（doom loop 之類會被自動擋下＝特性）；
#     agent tools 圍堵照常生效。本腳本刻意不用 --auto
#   - exit code：0＝正常收場、1＝session 錯誤；最終回覆進 stdout、裝飾與錯誤進 stderr
#
# 停機條件（七保險絲）：
#   畢業（三層門全過，見下）／連續 2 圈無進度／連續 2 次逾時／
#   連續 2 次 session 錯誤／強殺後檔案一致性 FAIL／
#   audit 相位連續 2 圈零回灌未畢業（活鎖熔斷）／圈數上限
# 畢業三層門（issue #2：模型說自己做完不算，只有 observable state transition 才算）：
#   SESSION_OK＝audit session 正常收場（exit 0）
#   WORK_TRANSITION_OK＝稽核輪次遞增＋90-audit.md hash 改變
#     （快照緊貼 audit session 前後——不得跨過手術 session：ps-deep-research
#      在 checklist 全勾時可能於手術 session 內自行接跑稽核，跨步驟比對會污染）
#   VALIDATION_OK＝lint 全過＋StrictAudit 全過（結果落 strict-cycle<N>.txt）
# 人的位置：lesson、correct、PR 審核照舊人工；本腳本只驅動內容生產，早上看 log 摘要即可。
param(
    [Parameter(Mandatory = $true)][string]$Domain,
    [int]$MaxCycles = 20,
    # 逾時＝熔絲不是效能參數，照實測基線設（L48）：實測 audit 34 分正常完成、
    # research 曾在 30 分上限被強殺（＝上限訂太緊，把健康的 session 砍掉）。
    # 兩者統一 60 分——留 ~2× 餘裕，讓「逾時」重新代表「真的卡死」而非「跑得久」。
    # 注意手術 session 沿用 ResearchTimeoutMin，改這個值等於同步放寬手術上限；
    # 批次的單領域最壞時長＝MaxCycles×(60＋60) 分，要硬圍欄改用 -MaxCyclesPerDomain。
    [int]$ResearchTimeoutMin = 60,
    [int]$AuditTimeoutMin = 60,
    [string]$Model = "",           # 留空＝opencode 全域預設；填 provider/model-id 可覆寫本次
    [switch]$Preflight             # 只檢查環境／相位／lint／收據並列印，不啟動 session、不取鎖
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
if ($GraduationSchemaVersion -ne 1) {
    Write-Error "ps-graduation.ps1 版本不符（schemaVersion=$GraduationSchemaVersion）"; exit 2
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
        Write-Log "SESSION($Tag) 逾時 $TimeoutMin 分，已整樹強制結束（狀態在檔案，無損）"
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
# -Strict＝畢業門專用（ps-doc-lint.ps1 -StrictAudit）：90-audit 結構性問題升 FAIL
function Invoke-Lint {
    param([switch]$Strict)
    if (-not (Test-Path (Join-Path $dir "00-overview.md"))) {
        return @{ Exit = -1; Surgical = @(); Raw = "（領域尚未建立，略過 lint）" }
    }
    # L44：必須 *>&1（全流合併）——lint 用 Write-Host 輸出（information stream），
    # 2>&1 抓不到 → $raw 空 → 下方 PASS 防呆把每次成功誤判成 exit 3
    # （VALIDATION_OK 永遠假＝永遠畢不了業），工單擷取也永遠落空
    if ($Strict) { $raw = & $lintPath -Domain $Domain -StrictAudit *>&1 | Out-String }
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
    Write-Host "起始相位  ：$ph" -ForegroundColor Green
    $l = Invoke-Lint
    Write-Host "lint      ：exit=$($l.Exit)（0=全過 1=有違規 -1=領域未建立）｜工單 $($l.Surgical.Count) 筆"
    $ls = Invoke-Lint -Strict
    Write-Host "StrictAudit：exit=$($ls.Exit)（畢業門用；現在紅不影響 research 相位）"
    $rc = Test-GraduationReceipt -DomainDir $dir -Domain $Domain `
        -LintScriptPath $lintPath -GateScriptPath $gradLibPath
    Write-Host "現有收據  ：$(if ($rc.Valid) { '有效（本領域已畢業，跑下去會重驗）' } else { $rc.Reason })"
    Write-Host "熔絲設定  ：MaxCycles=$MaxCycles｜research 逾時 $ResearchTimeoutMin 分｜audit 逾時 $AuditTimeoutMin 分"
    Write-Host "log 位置  ：$logRoot"
    Write-Host "=== 檢查結束（未啟動任何 session）===" -ForegroundColor Cyan
    exit 0
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
    # audit 轉移快照——每圈重算的區域值（跨圈黏著旗標會讓舊圈證據放行新圈畢業）
    $auditBefore = $null
    $auditAfter = $null

    # 相位決定：有未勾項→research；全勾→audit；領域不存在→research（階段一建檔）
    if (-not $before.Exists -or $before.Unticked -gt 0) {
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

    # 每個 session 後跑 lint；FAIL 且有手術清單→自動餵一個修復 session（一圈最多一次、≤7 筆）
    $lint = Invoke-Lint
    Add-Content -Path (Join-Path $logRoot ("lint-cycle{0}.txt" -f $cycle)) -Value $lint.Raw -Encoding UTF8
    Write-Log "LINT exit=$($lint.Exit) 手術清單=$($lint.Surgical.Count) 筆"
    if ($lint.Exit -eq 1 -and $lint.Surgical.Count -gt 0) {
        $batch = @($lint.Surgical | Select-Object -First 7)
        if ($lint.Surgical.Count -gt 7) { Write-Log "手術清單 $($lint.Surgical.Count) 筆，本圈先修 7 筆（分批紀律）" }
        $flat = ($batch -join "；") -replace '"', "'"
        # 禁令必要：ps-deep-research 在 checklist 全勾時會自行接跑稽核（agent 啟動
        # 規則），改寫 90-audit.md／輪次會污染本圈的畢業判定與下圈的轉移基準
        # L43：prompt 與 lint 工單同步——先判型別再動手，B 型委派 oracle flow、
        # 禁 peoplecode 代償、有合法終止出口（否則 B 型項目＝無限迴圈）
        $sPrompt = "lint 證據修復清單逐筆處理，先判型別再動手：CHUNK 型（程式碼）＝filePath 重取、驗貨（回傳須含原引文）、只補完整36字元id；SQL／metadata 型（DB 表如 PSPRCSRQST）＝委派具 oracleMCP 權限的 flow（ps-metadata-flow 等）照 cookbook 重查、機器參照改寫成 SQL：SELECT…、你自己沒有 SQL 工具是圍堵設計、禁止改查 peoplecode 代償；皆不可得＝該筆輸出收據「舊值 → 待人工SQL」或「移除入gaps」後停止該筆。每筆附收據；只准修改清單所列檔案，禁止修改 checklist.md 與 90-audit.md，禁止執行稽核：$flat"
        $sr = Invoke-Opencode -ExtraArgs '--agent ps-deep-research' -PromptText $sPrompt `
            -TimeoutMin $ResearchTimeoutMin -Tag "surgery"
        # 手術 session 也在保險絲與一致性檢查的守備範圍（原本 $sr 沒人看＝
        # 強殺後半寫狀態恰好發生在唯一沒人看的路徑上）
        if ($sr.TimedOut) {
            $fsProblems = Test-FsConsistency -HadChecklist $preHadChecklist -PreItemTotal $preItemTotal
            if ($fsProblems.Count -gt 0) {
                foreach ($pb in $fsProblems) { Write-Log "CONSISTENCY FAIL（手術後）：$pb" }
                $stopReason = "手術 session 強殺後一致性檢查 FAIL（$($fsProblems.Count) 項）——人工處理後再啟動"
                break
            }
            Write-Log "手術 session 逾時強殺——一致性檢查 PASS，續跑"
        }
        elseif ($sr.ExitCode -ne 0) { Write-Log "手術 session 非零 exit=$($sr.ExitCode)（記錄；不計入 errorStreak）" }
        $lint2 = Invoke-Lint
        Write-Log "LINT(術後) exit=$($lint2.Exit) 手術清單=$($lint2.Surgical.Count) 筆"
        $lint = $lint2
    }

    # 進度與畢業判定
    $after = Get-ChecklistState
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
        # 第 3 層：基礎 lint 過了才值得跑 strict（否則擋下原因已在基礎 lint）
        $strictDesc = "未評（基礎條件未過）"
        $validationOk = $false
        if ($after.Unticked -eq 0 -and $lint.Exit -eq 0) {
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
        Write-Log "GATE：session=$(if ($sessionOk) {'OK'} else {'exit≠0'}) transition=$(if ($transitionOk) {'OK'} else {'FAIL'})（$tDesc） validation=$strictDesc"
        if ($sessionOk -and $transitionOk -and $after.Unticked -eq 0 -and
            $lint.Exit -eq 0 -and $validationOk) {
            $graduated = $true
            # 過門當下快照 contentHash——寫收據時重算比對（TOCTOU 防護）；
            # auditRound 用轉移快照的正規化輪次，不在寫收據時重讀 checklist
            $gradContentHash = Get-DomainContentHash -DomainDir $dir
            $gradAuditRound = $auditAfter.Round
            $stopReason = "畢業：三層門全過（稽核輪次 $($auditAfter.Round)、無新 A 項、lint＋StrictAudit 全過）"
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
        if ($before.Exists -and $after.Unticked -ge $before.Unticked -and $before.Unticked -gt 0) {
            $noProgress++
            Write-Log "research 圈未減少未勾數（$noProgress/2）"
            if ($noProgress -ge 2) { $stopReason = "連續 2 圈無進度（卡住的項需人工裁決）"; break }
        }
        else { $noProgress = 0 }
    }
}

# ── 收場摘要 ────────────────────────────────────────────────
$final = Get-ChecklistState
Write-Log "=== auto-loop 停機：$stopReason ==="
Write-Log "最終狀態：未勾=$($final.Unticked) 已勾=$($final.Ticked) 稽核輪次=$($final.Round) 畢業=$graduated"
Write-Log "人工待辦：看本檔上方各 session 的 out/err、lint-cycle*.txt、strict-cycle*.txt（畢業門明細）；lesson 建議與卡住項在 90-audit.md 與 checklist.md"

# 畢業收據（issue #3）：只在三層門全過後寫；寫入失敗＝automation 不可信（exit 2）
if ($graduated) {
    $rcResult = Write-GraduationReceipt -DomainDir $dir -Domain $Domain `
        -AuditRound $gradAuditRound -LintScriptPath $lintPath `
        -GateScriptPath $gradLibPath -ExpectedContentHash $gradContentHash
    if ($rcResult.Ok) {
        Write-Log "畢業收據已寫入 graduation.json（auditRound=$gradAuditRound）"
    }
    else {
        Write-Log "畢業收據寫入失敗：$($rcResult.Reason)——exit 2（system error）"
        $mutex.ReleaseMutex(); $mutex.Dispose()
        exit 2
    }
}
$mutex.ReleaseMutex(); $mutex.Dispose()
if ($graduated) { exit 0 } else { exit 1 }
