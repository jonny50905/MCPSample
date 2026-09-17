# ps-session-lib.ps1 — opencode headless session 啟動共用邏輯
# 由 ps-auto-loop.ps1（薄包裝 Invoke-Opencode）、ps-spec.ps1（-Run）、ps-supplemental 迷你圈 dot-source。
# 責任：挑 .cmd/.exe/.bat 型 shim；以 cmd.exe 啟動 `opencode run`（rc 檔取真實結束碼、.Handle 快取、
#       逾時整樹強殺、心跳與沉默判讀、容量事件標籤）；session slot 互斥鎖 Global\MCPSample-OpencodeSession
#       ——同一台機器同一時間只跑一個 headless session（各外環各持自己的鎖：research 全域鎖／spec 逐 job 鎖，
#       但都用同一個模型服務與 oracleMCP 單通道）。
# 純函式庫：dot-source 無副作用。PowerShell 5.1 紀律：無三元／??／&&；Join-Path 兩參數；-LiteralPath。
# prompt 走 cmd.exe 命令列、放在半形雙引號裡：真正會壞的是半形雙引號（結束引號）、% （即使在引號內 cmd 也展開 %VAR%）與換行；
# > < & | ^ 在雙引號內是普通字元（不當重導向、不當中繼字元），照舊可用；中文引號「」不受限。

$script:PsSessionLibVersion = 1
$script:PsOcSessionSlotName = 'Global\MCPSample-OpencodeSession'

# npm 同時裝 opencode / opencode.cmd / opencode.ps1；Get-Command 會優先回 .ps1——把 .ps1 丟給 cmd.exe
# 不會執行，Windows 會用檔案關聯開啟它（記事本）並阻塞，關掉後 cmd 回 exit 0，外環誤判 session 正常結束。
function Select-PsOcShim {
    param($Candidates)
    foreach ($ext in @('.cmd', '.exe', '.bat')) {
        foreach ($c in @($Candidates)) {
            if ($c.Source -and $c.Source.ToLowerInvariant().EndsWith($ext)) { return $c.Source }
        }
    }
    return $null
}

# 回 @{ Path; Error; Count }：Path 空＝找不到可用 shim（Error 說明）
function Get-PsOcPath {
    $all = @(Get-Command opencode -All -ErrorAction SilentlyContinue)
    if ($all.Count -eq 0) { return @{ Path = ''; Error = 'PATH 找不到 opencode'; Count = 0 } }
    $p = Select-PsOcShim -Candidates $all
    if (-not $p) {
        return @{ Path = ''; Error = ('PATH 上的 opencode 是 ' + $all[0].Source + '（非 .cmd/.exe/.bat）——cmd.exe 會用檔案關聯開啟它而不是執行它；請確認 npm 的 opencode.cmd 在 PATH 上'); Count = $all.Count }
    }
    return @{ Path = $p; Error = ''; Count = $all.Count }
}

# 容量事件標籤：子代理 context 溢出通常以 exit 0 收場（task 錯誤回給 parent 當工具結果），只看 exit code 看不到；
# 不論 exit 都掃 out＋err 全文。這是標籤不是判定：無此字樣≠無溢出。
function Get-PsOcFailureKind {
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

# prompt 是否能安全放進 cmd.exe 命令列的雙引號引數：只擋真的會壞的三種——半形雙引號、%（cmd 在引號內也展開 %VAR%）、換行。
# > < & | ^ 在雙引號內是普通字元（手術 prompt 就含「A > B > C」），不擋。
function Test-PsOcPromptSafe {
    param([string]$PromptText)
    if ($null -eq $PromptText -or $PromptText -eq '') { return $false }
    if ($PromptText -match '[\r\n"%]') { return $false }
    return $true
}

# 取 session slot（有界等待；前任行程死亡＝AbandonedMutexException＝視為取得）。
# 回 @{ Held; Mutex; WaitedSec; Reason }；Held=$false 時呼叫端自行決定（外環一律不啟動 session）。
function Enter-PsOcSessionSlot {
    param([int]$WaitMin = 0, [scriptblock]$Log = $null)
    $slot = @{ Held = $false; Mutex = $null; WaitedSec = 0; Reason = '' }
    $m = $null
    try { $m = New-Object System.Threading.Mutex($false, $script:PsOcSessionSlotName) }
    catch { $slot.Reason = ('session slot 互斥鎖無法建立：' + $_.Exception.Message); return $slot }
    $held = $false
    try { $held = $m.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $held = $true }
    $started = Get-Date
    if (-not $held -and $WaitMin -gt 0) {
        if ($null -ne $Log) { & $Log ('session slot 被占用（另一個 headless session 正在跑：ps-auto-loop／ps-spec -Run／補研究迷你圈）——最多等 ' + $WaitMin + ' 分，取得後逾時才起算') }
        $lastBeat = Get-Date
        while (-not $held -and ((Get-Date) - $started).TotalMinutes -lt $WaitMin) {
            try { $held = $m.WaitOne(30000) } catch [System.Threading.AbandonedMutexException] { $held = $true }
            if (-not $held -and $null -ne $Log -and ((Get-Date) - $lastBeat).TotalMinutes -ge 5) {
                & $Log ('session slot 仍被占用…已等 ' + [int]((Get-Date) - $started).TotalMinutes + ' 分（上限 ' + $WaitMin + ' 分）')
                $lastBeat = Get-Date
            }
        }
    }
    $slot.WaitedSec = [int]((Get-Date) - $started).TotalSeconds
    if (-not $held) {
        try { $m.Dispose() } catch { }
        $slot.Reason = 'session slot 被占用'
        return $slot
    }
    $slot.Held = $true
    $slot.Mutex = $m
    return $slot
}

function Exit-PsOcSessionSlot {
    param($Slot)
    if ($null -eq $Slot -or -not $Slot.Held -or $null -eq $Slot.Mutex) { return }
    try { $Slot.Mutex.ReleaseMutex() } catch { }
    try { $Slot.Mutex.Dispose() } catch { }
    $Slot.Held = $false
    $Slot.Mutex = $null
}

# 開一個新鮮 opencode session（逾時整樹強殺）。回傳 @{ TimedOut; ExitCode; ErrFile; OutFile; FailureKind; SlotBusy; SlotWaitedSec }
#   -ExtraArgs 例：'--command ps-research' 或 '--agent ps-deep-research'
#   -SlotWaitMin：取不到 session slot 最多等幾分（0＝不等）；等不到＝不啟動，回 SlotBusy=$true、TimedOut=$true、FailureKind=SLOT_BUSY
#   -Log：一行一則的記錄函式（外環傳 ${function:Write-Log}）；未給＝Write-Host
#   逾時從取得 slot 起算（等待 slot 的時間不吃 session 的 TimeoutMin）
function Invoke-PsOcSession {
    param(
        [string]$OcPath, [string]$Root, [string]$LogRoot, [string]$Model = '',
        [string]$ExtraArgs = '', [string]$PromptText, [int]$TimeoutMin, [string]$Tag,
        [scriptblock]$Log = $null, [int]$SlotWaitMin = 0, [string]$TimeoutParamName = ''
    )
    function L([string]$m) { if ($null -ne $Log) { & $Log $m } else { Write-Host $m } }
    if (-not (Test-Path -LiteralPath $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outFile = Join-Path $LogRoot ('{0}-{1}.out.txt' -f $stamp, $Tag)
    $errFile = Join-Path $LogRoot ('{0}-{1}.err.txt' -f $stamp, $Tag)
    if (-not (Test-PsOcPromptSafe -PromptText $PromptText)) {
        L "SESSION($Tag) 拒啟動：prompt 含換行、半形雙引號或 %（cmd 在雙引號內也會展開 %VAR%）——外環組 prompt 的錯，不是模型"
        return @{ TimedOut = $false; ExitCode = -1; ErrFile = $errFile; OutFile = $outFile; FailureKind = 'PROMPT_UNSAFE'; SlotBusy = $false; SlotWaitedSec = 0 }
    }
    $slot = Enter-PsOcSessionSlot -WaitMin $SlotWaitMin -Log $Log
    if (-not $slot.Held) {
        L "SESSION($Tag) 未啟動：$($slot.Reason)（等了 $($slot.WaitedSec) 秒）——另一個 ps-auto-loop／ps-spec／補研究 session 正在用模型服務，錯開時間再跑"
        return @{ TimedOut = $true; ExitCode = -1; ErrFile = $errFile; OutFile = $outFile; FailureKind = 'SLOT_BUSY'; SlotBusy = $true; SlotWaitedSec = $slot.WaitedSec }
    }
    try {
        # 結束碼落檔：不相信 Process 物件的 .ExitCode（-PassThru 物件在只用 WaitForExit(ms) 等待時常為 $null，
        # 而 $null -eq 0 為 false＝每個正常 session 都被判成錯誤）。改讓 cmd 把 ERRORLEVEL 寫進檔案——要可觀測的事實。
        $rcFile = Join-Path $LogRoot ('{0}-{1}.rc.txt' -f $stamp, $Tag)
        $inner = '"' + $OcPath + '" run '
        if ($Model -ne '') { $inner += '--model "' + $Model + '" ' }
        if ($ExtraArgs -ne '') { $inner += $ExtraArgs + ' ' }
        $inner += '--title "auto-' + $Tag + '" '
        $inner += '"' + $PromptText + '" 1> "' + $outFile + '" 2> "' + $errFile + '"'
        # %^ERRORLEVEL% ＋ call：延後展開，取得的才是 opencode 的真實結束碼
        $inner += ' & call echo %^ERRORLEVEL% > "' + $rcFile + '"'
        L "SESSION($Tag) 啟動：$ExtraArgs ｜ $PromptText"
        $p = Start-Process -FilePath 'cmd.exe' -ArgumentList ('/d /s /c "' + $inner + '"') `
            -WorkingDirectory $Root -NoNewWindow -PassThru
        # 必須先取用 .Handle 把行程 handle 快取住，否則 -PassThru 物件在只用 WaitForExit(ms) 等待時 .ExitCode 會是 $null
        try { $null = $p.Handle } catch { }
        $tpn = $TimeoutParamName
        if ($tpn -eq '') { if ($Tag -like 'audit*') { $tpn = 'AuditTimeoutMin' } else { $tpn = 'ResearchTimeoutMin' } }
        # 心跳：session 期間 opencode 輸出全被重導到檔案，console 會完全安靜——每 5 分鐘印一行「還活著＋已耗時」
        $sessStart = Get-Date
        $lastBeat = $sessStart
        $done = $false
        while (((Get-Date) - $sessStart).TotalMinutes -lt $TimeoutMin) {
            if ($p.WaitForExit(30000)) { $done = $true; break }
            if (((Get-Date) - $lastBeat).TotalMinutes -ge 5) {
                $mins = [int]((Get-Date) - $sessStart).TotalMinutes
                # 沉默停滯偵測（確定性、只警告不強殺）：輸出檔多久沒長大
                $lastOut = $sessStart
                foreach ($lf in @($outFile, $errFile)) {
                    if (Test-Path -LiteralPath $lf) {
                        $wt = (Get-Item -LiteralPath $lf).LastWriteTime
                        if ($wt -gt $lastOut) { $lastOut = $wt }
                    }
                }
                $silent = [int]((Get-Date) - $lastOut).TotalMinutes
                $note = ''
                if ($silent -ge 20) { $note = "；輸出已靜止 $silent 分（委派期間長時間無輸出屬常態，實測健康可達 30 分；接近逾時上限仍無輸出才需依 SOP-12 查 oracleMCP 通道）" }
                L "SESSION($Tag) 進行中…已 $mins 分（逾時上限 $TimeoutMin 分）$note"
                $lastBeat = Get-Date
            }
        }
        if (-not $done) { $done = $p.WaitForExit(1000) }
        if ($done) {
            try { $p.WaitForExit() } catch { }
            try { $p.Refresh() } catch { }
        }
        if (-not $done) {
            & taskkill.exe /PID $p.Id /T /F 2>$null | Out-Null
            # 強殺當下就下判讀：「卡死 vs 跑得久」的處置完全相反（一個查通道、一個調上限）
            $lastOutK = $sessStart
            foreach ($lf in @($outFile, $errFile)) {
                if (Test-Path -LiteralPath $lf) {
                    $wt = (Get-Item -LiteralPath $lf).LastWriteTime
                    if ($wt -gt $lastOutK) { $lastOutK = $wt }
                }
            }
            $killSilent = [int]((Get-Date) - $lastOutK).TotalMinutes
            L "SESSION($Tag) 逾時 $TimeoutMin 分，已整樹強制結束（狀態在檔案，無損）"
            if ($killSilent -le 5) {
                L "SESSION($Tag) 判讀：強殺當下輸出仍在增加（靜止僅 $killSilent 分）＝**上限太短，不是卡死**——把 -$tpn 調高後重跑，不要去查 MCP 通道"
            }
            elseif ($killSilent -ge 20) {
                L "SESSION($Tag) 判讀：輸出已靜止 $killSilent 分才被強殺＝**疑似卡在工具呼叫**——依 SOP-12 查 oracleMCP／模型服務通道，調高上限沒有用"
            }
            else {
                L "SESSION($Tag) 判讀：強殺當下靜止 $killSilent 分（介於兩者之間）——先看 out 檔尾端停在哪個步驟再決定調上限或查通道"
            }
            $fkT = Get-PsOcFailureKind -OutFile $outFile -ErrFile $errFile
            if ($fkT -ne 'NONE') { L "SESSION($Tag) 容量事件：$fkT（out/err 含 context 溢出字樣）——逾時前已撞 context 上限，調時間無用；見 SOP-10" }
            return @{ TimedOut = $true; ExitCode = -1; ErrFile = $errFile; OutFile = $outFile; FailureKind = $fkT; SlotBusy = $false; SlotWaitedSec = $slot.WaitedSec }
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
            # 仍讀不到＝環境層面拿不到結束碼；視為 0（正常）並大聲記錄——反向（視為錯誤）已實證會把健康的 run 誤停
            L "SESSION($Tag) 警告：ExitCode 讀不到，視為 0（正常結束）——若後續行為異常請回報此行"
            $code = 0
        }
        L "SESSION($Tag) 結束 exit=$code 耗時 $([int]((Get-Date) - $sessStart).TotalMinutes) 分，輸出：$outFile"
        $fk = Get-PsOcFailureKind -OutFile $outFile -ErrFile $errFile
        if ($fk -ne 'NONE') { L "SESSION($Tag) 容量事件：$fk（out/err 含 context 溢出字樣；exit=$code 不代表沒事——子代理溢出多半 exit 0）——處置見 SOP-10，不要只調 timeout" }
        return @{ TimedOut = $false; ExitCode = $code; ErrFile = $errFile; OutFile = $outFile; FailureKind = $fk; SlotBusy = $false; SlotWaitedSec = $slot.WaitedSec }
    }
    finally {
        Exit-PsOcSessionSlot -Slot $slot
    }
}
