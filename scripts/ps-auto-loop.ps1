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
# 停機條件（五保險絲）：
#   畢業（audit 後無新 A 項且 lint 全過）／連續 2 圈無進度／連續 2 次逾時／
#   連續 2 次 session 錯誤／圈數上限
# 人的位置：lesson、correct、PR 審核照舊人工；本腳本只驅動內容生產，早上看 log 摘要即可。
param(
    [Parameter(Mandatory = $true)][string]$Domain,
    [int]$MaxCycles = 20,
    [int]$ResearchTimeoutMin = 30,
    [int]$AuditTimeoutMin = 45,
    [string]$Model = ""            # 留空＝opencode 全域預設；填 provider/model-id 可覆寫本次
)

# ── 環境解析 ────────────────────────────────────────────────
$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path $root (Join-Path "docs/ps-research" $Domain)
$lintPath = Join-Path $PSScriptRoot "ps-doc-lint.ps1"
$logRoot = Join-Path $root (Join-Path "auto-loop-logs" $Domain)
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$logFile = Join-Path $logRoot "auto-loop.log"

# opencode 可執行檔（npm shim 是 .cmd，經 cmd.exe 呼叫最穩）
$ocCmd = Get-Command opencode -ErrorAction SilentlyContinue
if (-not $ocCmd) { Write-Error "PATH 找不到 opencode"; exit 2 }
$ocPath = $ocCmd.Source

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

# ── 開一個新鮮 opencode session（逾時整樹強殺）────────────
# $ExtraArgs 例：'--command ps-research' 或 '--agent ps-deep-research'
# 注意：prompt 走 cmd.exe 命令列——內容禁用半形雙引號與 cmd 特殊字元
# （> < & | % ^），中文引號「」不受限；多行內容一律壓成單行。
function Invoke-Opencode {
    param([string]$ExtraArgs, [string]$PromptText, [int]$TimeoutMin, [string]$Tag)
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $outFile = Join-Path $logRoot ("{0}-{1}.out.txt" -f $stamp, $Tag)
    $errFile = Join-Path $logRoot ("{0}-{1}.err.txt" -f $stamp, $Tag)
    $inner = '"' + $ocPath + '" run '
    if ($Model -ne "") { $inner += '--model "' + $Model + '" ' }
    if ($ExtraArgs -ne "") { $inner += $ExtraArgs + ' ' }
    $inner += '--title "auto-' + $Tag + '" '
    $inner += '"' + $PromptText + '" 1> "' + $outFile + '" 2> "' + $errFile + '"'
    Write-Log "SESSION($Tag) 啟動：$ExtraArgs ｜ $PromptText"
    $p = Start-Process -FilePath "cmd.exe" -ArgumentList ('/d /s /c "' + $inner + '"') `
        -WorkingDirectory $root -NoNewWindow -PassThru
    $done = $p.WaitForExit($TimeoutMin * 60 * 1000)
    if (-not $done) {
        & taskkill.exe /PID $p.Id /T /F 2>$null | Out-Null
        Write-Log "SESSION($Tag) 逾時 $TimeoutMin 分，已整樹強制結束（狀態在檔案，無損）"
        return @{ TimedOut = $true; ExitCode = -1 }
    }
    Write-Log "SESSION($Tag) 結束 exit=$($p.ExitCode)，輸出：$outFile"
    return @{ TimedOut = $false; ExitCode = $p.ExitCode }
}

# ── lint（在本 PowerShell 行程內呼叫，繼承現行執行環境）──
function Invoke-Lint {
    if (-not (Test-Path (Join-Path $dir "00-overview.md"))) {
        return @{ Exit = -1; Surgical = @(); Raw = "（領域尚未建立，略過 lint）" }
    }
    $raw = & $lintPath -Domain $Domain 2>&1 | Out-String
    $code = $LASTEXITCODE
    # 擷取手術清單（=== 標記之間的編號行）
    $surgical = @()
    if ($raw -match '(?s)=== 手術式修復指令.*?===(.*?)=== 指令結束 ===') {
        $block = $Matches[1]
        $surgical = @($block -split "`r?`n" | Where-Object { $_ -match '^\s*\d+\.\s' } |
            ForEach-Object { $_.Trim() })
    }
    return @{ Exit = $code; Surgical = $surgical; Raw = $raw }
}

# ── 主迴圈 ──────────────────────────────────────────────────
Write-Log "=== auto-loop 啟動：領域=$Domain MaxCycles=$MaxCycles Model=$(if($Model){$Model}else{'(全域預設)'}) ==="
$timeoutStreak = 0
$errorStreak = 0
$noProgress = 0
$graduated = $false
$stopReason = "圈數上限（$MaxCycles）"

for ($cycle = 1; $cycle -le $MaxCycles; $cycle++) {
    $before = Get-ChecklistState
    Write-Log "── 第 $cycle 圈：未勾=$($before.Unticked) 已勾=$($before.Ticked) 稽核輪次=$($before.Round)"

    # 相位決定：有未勾項→research；全勾→audit；領域不存在→research（階段一建檔）
    if (-not $before.Exists -or $before.Unticked -gt 0) {
        $phase = "research"
        $r = Invoke-Opencode -ExtraArgs '--command ps-research' -PromptText $Domain `
            -TimeoutMin $ResearchTimeoutMin -Tag "research"
    }
    else {
        $phase = "audit"
        $r = Invoke-Opencode -ExtraArgs '--command ps-audit' -PromptText $Domain `
            -TimeoutMin $AuditTimeoutMin -Tag "audit"
    }

    # 保險絲：逾時／session 錯誤
    if ($r.TimedOut) {
        $timeoutStreak++
        if ($timeoutStreak -ge 2) { $stopReason = "連續 2 次逾時（需人工看 session log）"; break }
        continue
    }
    $timeoutStreak = 0
    if ($r.ExitCode -ne 0) {
        $errorStreak++
        Write-Log "SESSION 非零 exit（$errorStreak/2）——看 err 檔"
        if ($errorStreak -ge 2) { $stopReason = "連續 2 次 session 錯誤（需人工看 err log）"; break }
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
        $sPrompt = "lint 手術清單逐筆修復（規則照 A 項 TRUNCATED_ID 修法：filePath 重取、驗貨、收據）：$flat"
        $sr = Invoke-Opencode -ExtraArgs '--agent ps-deep-research' -PromptText $sPrompt `
            -TimeoutMin $ResearchTimeoutMin -Tag "surgery"
        $lint2 = Invoke-Lint
        Write-Log "LINT(術後) exit=$($lint2.Exit) 手術清單=$($lint2.Surgical.Count) 筆"
        $lint = $lint2
    }

    # 進度與畢業判定
    $after = Get-ChecklistState
    if ($phase -eq "audit") {
        if ($after.Unticked -eq 0 -and $lint.Exit -eq 0) {
            $graduated = $true
            $stopReason = "畢業：稽核輪次 $($after.Round) 無新 A 項、lint 全過"
            break
        }
        Write-Log "audit 回灌 $($after.Unticked) 項，續跑"
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
Write-Log "人工待辦：看本檔上方各 session 的 out/err、lint-cycle*.txt；lesson 建議與卡住項在 90-audit.md 與 checklist.md"
if ($graduated) { exit 0 } else { exit 1 }
