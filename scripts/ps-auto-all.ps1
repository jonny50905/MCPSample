# ps-auto-all.ps1 — 多領域批次排程器（issue #3）
# 責任只有：讀佇列 → preflight → 驗收據 → 逐一以子行程呼叫 ps-auto-loop → 記錄。
# 不理解 PeopleSoft、不呼叫模型、不寫 checklist、不做 audit、**永不寫收據**。
#
# 佇列：.opencode/peoplesoft/research-domains.txt（人工維護：一行一領域、# 註解）
# 收據：docs/ps-research/<領域>/graduation.json（只由 ps-auto-loop 畢業時寫入；
#       驗證＝純 hash 比對，不跑 lint——新領域無目錄＝無收據＝RUN，不會誤判錯誤）
# V1 嚴格 sequential：領域間共享 Entity Wiki／oracleMCP／working tree，禁止並行。
# 子行程呼叫（powershell -File）＝互斥鎖由各 ps-auto-loop 行程持有，行程死亡
# OS 自動回收；exit code 取 $proc.ExitCode，不受 $LASTEXITCODE 殘值污染。
#
# 用法：.\scripts\ps-auto-all.ps1
#       .\scripts\ps-auto-all.ps1 -MaxDomains 10 -MaxBatchHours 8 -MaxConsecutiveFailures 3
#       .\scripts\ps-auto-all.ps1 -Force        # 忽略收據，全部重新驗證
# 注意：MaxBatchHours 只在「領域之間」檢查，不強殺進行中的領域——單領域最壞
#       時長由 ps-auto-loop 的 MaxCycles×timeout 決定，要縮小圍欄用透傳參數。
# exit：0＝批次完成（可含 NEEDS_ATTENTION）／2＝停批（system error／鎖被占用／
#       preflight 失敗）
param(
    [int]$MaxDomains = 0,                # 0＝不限；只計實際 RUN，SKIP 不消耗
    [double]$MaxBatchHours = 0,          # 0＝不限；領域之間檢查
    [int]$MaxConsecutiveFailures = 3,    # 連續 exit 1 熔斷（SKIP 透明不重置；GRADUATED 才重置）
    [switch]$Force,                      # 忽略有效收據、全部重新進 ps-auto-loop
    [string]$Model = "",                 # 透傳 ps-auto-loop -Model
    [int]$MaxCyclesPerDomain = 0         # >0 時透傳 ps-auto-loop -MaxCycles（縮小單領域天花板）
)

$root = Split-Path $PSScriptRoot -Parent
$queuePath = Join-Path $root (Join-Path ".opencode/peoplesoft" "research-domains.txt")
$autoLoopPath = Join-Path $PSScriptRoot "ps-auto-loop.ps1"
$lintPath = Join-Path $PSScriptRoot "ps-doc-lint.ps1"
$gradLibPath = Join-Path $PSScriptRoot "ps-graduation.ps1"
$researchRoot = Join-Path $root (Join-Path "docs" "ps-research")
$logRoot = Join-Path $root "auto-loop-logs"
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
# stamp 加 PID：兩個批次同秒啟動不撞檔
$batchLog = Join-Path $logRoot ("batch-{0}-{1}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"), $PID)

function Write-BatchLog([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -Path $batchLog -Value $line -Encoding UTF8
    Write-Host $line
}

# ── 佇列 preflight（純函式，回傳違規清單；空清單＝過）─────────
# 領域名最終流入 directory path 與 cmd.exe prompt 參數，一項違規整批拒跑。
function Get-QueuePreflightErrors {
    param([string[]]$Domains)
    $problems = @()
    $seen = @{}
    $deviceNames = @('CON', 'PRN', 'AUX', 'NUL', 'CONIN$', 'CONOUT$')
    foreach ($i in 1..9) { $deviceNames += "COM$i"; $deviceNames += "LPT$i" }
    foreach ($d in $Domains) {
        $key = $d.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { $problems += "重複領域（trim/大小寫後）：$d"; continue }
        $seen[$key] = $true
        if ($key -eq 'wiki') { $problems += "保留名（共用 Entity Wiki 目錄）：$d" }
        if ($d -match '[<>:"/\\|?*&%^`]') { $problems += "含 path/cmd 不安全字元：$d" }
        if ($d.Contains('..')) { $problems += "含「..」：$d" }
        if ($d.StartsWith('-')) { $problems += "以「-」開頭（會被當參數旗標吃掉）：$d" }
        if ($d.StartsWith('.') -or $d.EndsWith('.')) { $problems += "以「.」開頭或結尾：$d" }
        if ($d.Length -gt 50) { $problems += "領域名過長（>50 字元，MAX_PATH 風險）：$d" }
        foreach ($ch in $d.ToCharArray()) {
            $cp = [int]$ch
            if ($cp -lt 32 -or ($cp -ge 0x200B -and $cp -le 0x200F) -or $cp -eq 0xFEFF) {
                $problems += "含控制／零寬字元：$d"; break
            }
        }
        # 裝置名以「第一個點前的基名」比對——AUX.md 之類仍是 Windows 保留裝置
        $base = $d
        $dotIdx = $base.IndexOf('.')
        if ($dotIdx -ge 0) { $base = $base.Substring(0, $dotIdx) }
        if ($deviceNames -contains $base.ToUpperInvariant()) {
            $problems += "Windows 保留裝置名：$d"
        }
    }
    return , $problems
}

# ── 環境自檢：缺任何依賴＝automation 不可信，直接 exit 2 ─────
foreach ($dep in @($autoLoopPath, $lintPath, $gradLibPath)) {
    if (-not (Test-Path -LiteralPath $dep)) {
        Write-BatchLog "SYSTEM ERROR：缺 $dep（人工搬運不完整？）"
        exit 2
    }
}
. $gradLibPath
if ($GraduationSchemaVersion -ne 1) {
    Write-BatchLog "SYSTEM ERROR：ps-graduation.ps1 版本不符（schemaVersion=$GraduationSchemaVersion）"
    exit 2
}
if (-not (Test-Path -LiteralPath $queuePath)) {
    Write-BatchLog "SYSTEM ERROR：佇列檔不存在：$queuePath（打錯路徑？）"
    exit 2
}

# ── 讀佇列 ───────────────────────────────────────────────────
$domains = @()
foreach ($ln in (Get-Content -LiteralPath $queuePath -Encoding UTF8)) {
    $t = $ln.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $domains += $t
}
if ($domains.Count -eq 0) {
    Write-BatchLog "佇列沒有任何生效領域（全空／全註解）——無事可做，正常結束"
    exit 0
}
$pfErrors = Get-QueuePreflightErrors -Domains $domains
if ($pfErrors.Count -gt 0) {
    foreach ($p in $pfErrors) { Write-BatchLog "PREFLIGHT FAIL：$p" }
    Write-BatchLog "SYSTEM ERROR：preflight $($pfErrors.Count) 項違規——整批不跑，修 research-domains.txt 後重來"
    exit 2
}

# ── 主迴圈（嚴格 sequential）─────────────────────────────────
$batchStart = Get-Date
$counts = [ordered]@{ SKIPPED = 0; GRADUATED = 0; NEEDS_ATTENTION = 0; MUTEX_BUSY = 0; SYSTEM_ERROR = 0; NOT_RUN = 0 }
$consecFail = 0
$ranCount = 0
$stopBatch = $false
$stopWhy = ''
$idx = 0
Write-BatchLog "=== PeopleSoft Research Batch：$($domains.Count) 個領域 ｜ Force=$Force MaxDomains=$MaxDomains MaxBatchHours=$MaxBatchHours ==="

foreach ($d in $domains) {
    $idx++
    $tag = "[$idx/$($domains.Count)] $d"
    if ($stopBatch) { $counts.NOT_RUN++; continue }

    # 領域之間的批次熔絲（不強殺進行中）
    if ($MaxBatchHours -gt 0 -and ((Get-Date) - $batchStart).TotalHours -ge $MaxBatchHours) {
        $stopBatch = $true; $stopWhy = "MaxBatchHours（$MaxBatchHours h）已到"
        $counts.NOT_RUN++; continue
    }
    if ($MaxDomains -gt 0 -and $ranCount -ge $MaxDomains) {
        $stopBatch = $true; $stopWhy = "MaxDomains（$MaxDomains）已到"
        $counts.NOT_RUN++; continue
    }

    $domainDir = Join-Path $researchRoot $d
    if (-not $Force) {
        $rc = Test-GraduationReceipt -DomainDir $domainDir -Domain $d `
            -LintScriptPath $lintPath -GateScriptPath $gradLibPath
        if ($rc.Valid) {
            Write-BatchLog "$tag 收據有效 → SKIP"
            $counts.SKIPPED++; continue    # SKIP 對連敗計數透明（不加不重置）
        }
        Write-BatchLog "$tag 收據：$($rc.Reason) → RUN"
    }
    else {
        Write-BatchLog "$tag -Force → RUN"
    }

    $ranCount++
    # 子行程呼叫：領域名已過 preflight（無 " 與 cmd 特殊字元），雙引號包裹安全
    $argStr = '-NoProfile -File "{0}" -Domain "{1}"' -f $autoLoopPath, $d
    if ($Model -ne '') { $argStr += ' -Model "{0}"' -f $Model }
    if ($MaxCyclesPerDomain -gt 0) { $argStr += ' -MaxCycles {0}' -f $MaxCyclesPerDomain }
    $code = $null
    try {
        $p = Start-Process -FilePath "powershell.exe" -ArgumentList $argStr `
            -WorkingDirectory $root -NoNewWindow -PassThru -Wait
        $code = $p.ExitCode
    }
    catch { $code = $null }

    if ($code -eq 0) {
        # exit 0 仍不能直接當 GRADUATED——必須重驗收據（issue #3 核心規則）
        $rc2 = Test-GraduationReceipt -DomainDir $domainDir -Domain $d `
            -LintScriptPath $lintPath -GateScriptPath $gradLibPath
        if ($rc2.Valid) {
            Write-BatchLog "$tag exit 0＋收據有效 → GRADUATED"
            $counts.GRADUATED++; $consecFail = 0
        }
        else {
            Write-BatchLog "$tag exit 0 但收據無效（$($rc2.Reason)）→ SYSTEM ERROR，停批"
            $counts.SYSTEM_ERROR++; $stopBatch = $true; $stopWhy = "exit 0 但收據無效：$d"
        }
    }
    elseif ($code -eq 1) {
        $consecFail++
        Write-BatchLog "$tag exit 1 → NEEDS_ATTENTION（連續失敗 $consecFail/$MaxConsecutiveFailures）——細節看 auto-loop-logs/$d/"
        $counts.NEEDS_ATTENTION++
        if ($MaxConsecutiveFailures -gt 0 -and $consecFail -ge $MaxConsecutiveFailures) {
            $stopBatch = $true
            $stopWhy = "連續 $consecFail 個領域失敗——疑似環境級問題（MCP／模型服務／DB），先人工查再續跑"
        }
    }
    elseif ($code -eq 3) {
        # 鎖被外部持有＝操作衝突，不是自動化損壞——訊息要分清楚
        Write-BatchLog "$tag exit 3：互斥鎖被外部持有（另一個 ps-auto-loop 在跑？）→ 停批；錯開時間重跑即可"
        $counts.MUTEX_BUSY++; $stopBatch = $true; $stopWhy = "互斥鎖被外部持有"
    }
    else {
        Write-BatchLog "$tag exit=$(if ($null -eq $code) {'（啟動失敗／崩潰）'} else {$code}) → SYSTEM ERROR，停批"
        $counts.SYSTEM_ERROR++; $stopBatch = $true; $stopWhy = "system error（exit=$code）：$d"
    }
}

# ── Summary ─────────────────────────────────────────────────
Write-BatchLog "=== Summary ==="
if ($stopWhy -ne '') { Write-BatchLog "停批原因：$stopWhy" }
foreach ($k in $counts.Keys) {
    Write-BatchLog ("{0}  {1}" -f $k.PadRight(16), $counts[$k])
}
Write-BatchLog "batch log：$batchLog"
if ($counts.SYSTEM_ERROR -gt 0 -or $counts.MUTEX_BUSY -gt 0) { exit 2 } else { exit 0 }
