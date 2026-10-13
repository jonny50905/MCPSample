# ps-session-lib.ps1 — headless session 啟動共用邏輯（OpenCode：`opencode run`；Claude Code：`claude -p --agent`）
# 由 ps-auto-loop.ps1（薄包裝 Invoke-Opencode）、ps-spec.ps1（-Run）、ps-spec-build.ps1、ps-supplemental 迷你圈 dot-source。
# 責任：挑 .cmd/.exe/.bat 型 shim；以 cmd.exe 啟動 CLI（rc 檔取真實結束碼、.Handle 快取、
#       逾時整樹強殺、心跳與沉默判讀、容量事件標籤）；session slot 互斥鎖 Global\MCPSample-OpencodeSession
#       ——同一台機器同一時間只跑一個 headless session（各外環各持自己的鎖：research 全域鎖／spec 逐 job 鎖，
#       但都用同一個模型服務與 oracleMCP 單通道）。前端版本由 ps-cli-lib.ps1 判定（.claude/peoplesoft 存在＝Claude Code）。
# 純函式庫：dot-source 無副作用。PowerShell 5.1 紀律：無三元／??／&&；Join-Path 兩參數；-LiteralPath。
# prompt 走 cmd.exe 命令列、放在半形雙引號裡：真正會壞的是半形雙引號（結束引號）、% （即使在引號內 cmd 也展開 %VAR%）與換行；
# > < & | ^ 在雙引號內是普通字元（不當重導向、不當中繼字元），照舊可用；中文引號「」不受限。

. (Join-Path $PSScriptRoot 'ps-cli-lib.ps1')
$script:PsSessionLibRoot = Split-Path $PSScriptRoot -Parent
$script:PsSessionLibVersion = 1
$script:PsOcSessionSlotName = 'Global\MCPSample-OpencodeSession'
# 模型端重試判讀（Claude Code 版）：最後一個成功的模型回應之後，同一個請求連續失敗幾次以上算「卡在模型端」，未達算「被拖慢」
$script:PsOcApiStuckAfter = 3

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

# 回 @{ Path; Error; Count; Exe }：Path 空＝找不到可用 shim（Error 說明）。Exe＝opencode｜claude（依前端版本）
function Get-PsOcPath {
    param([string]$Root = '')
    if ($Root -eq '') { $Root = $script:PsSessionLibRoot }
    $exe = (Get-PsCliVariant -Root $Root).Exe
    $all = @(Get-Command $exe -All -ErrorAction SilentlyContinue)
    if ($all.Count -eq 0) { return @{ Path = ''; Error = ('PATH 找不到 ' + $exe); Count = 0; Exe = $exe } }
    $p = Select-PsOcShim -Candidates $all
    if (-not $p) {
        return @{ Path = ''; Error = ('PATH 上的 ' + $exe + ' 是 ' + $all[0].Source + '（非 .cmd/.exe/.bat）——cmd.exe 會用檔案關聯開啟它而不是執行它；請確認 ' + $exe + '.cmd 或 ' + $exe + '.exe 在 PATH 上'); Count = $all.Count; Exe = $exe }
    }
    return @{ Path = $p; Error = ''; Count = $all.Count; Exe = $exe }
}

# 容量事件標籤：子代理 context 溢出通常以 exit 0 收場（task 錯誤回給 parent 當工具結果），只看 exit code 看不到；
# 不論 exit 都掃 out＋err 全文。這是標籤不是判定：無此字樣≠無溢出。
function Get-PsOcFailureKind {
    param([string]$OutFile, [string]$ErrFile)
    $pat = '(?i)context.?length|maximum context|context window|context_length_exceeded|truncating input|input (?:is )?too long|prompt is too long'
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

# Claude Code 的 stream-json 輸出 → 最後一個 result 事件的最終回覆寫進 OutFile（與 OpenCode 的 stdout 同語意：外環的
# 「stdout 回收」與尾行摘錄只看最終回覆）。回 @{ Found; IsError; Subtype; Turns }。
function Convert-PsOcClaudeStream {
    param([string]$StreamFile, [string]$OutFile)
    $r = @{ Found = $false; IsError = $false; Subtype = ''; Turns = 0 }
    if (-not $StreamFile -or -not (Test-Path -LiteralPath $StreamFile)) { return $r }
    $last = $null
    foreach ($ln in [System.IO.File]::ReadLines($StreamFile, (New-Object System.Text.UTF8Encoding($false)))) {
        $k = $ln.IndexOf('"type":"result"')
        if ($k -ge 0 -and $k -lt 40) { $last = $ln }
    }
    if ($null -eq $last) { return $r }
    $o = $null
    try { $o = $last | ConvertFrom-Json } catch { return $r }
    $r.Found = $true
    $r.IsError = [bool]$o.is_error
    $r.Subtype = [string]$o.subtype
    if ($null -ne $o.num_turns) { $r.Turns = [int]$o.num_turns }
    $txt = [string]$o.result
    try { [System.IO.File]::WriteAllText($OutFile, $txt, (New-Object System.Text.UTF8Encoding($false))) } catch { }
    return $r
}

# Claude Code 的 stream-json：模型端可重試的錯誤（5xx、429／529、沒有回應）每次重試前寫一行 system/api_retry
# （error_status＝HTTP 狀態碼，沒有回應為 null）；重試用完仍失敗時 result 帶 api_error_status。session 進行中也可讀（共用讀寫開檔）。
# 回 @{ Kind; Count; Trailing; Recovered; Progress; Statuses; ApiErrorStatus }：
#   Count＝重試事件總數；Trailing＝最後一個成功的 assistant 事件之後連續的重試數（目前這個請求已失敗幾次）；
#   Recovered＝重試之後又成功過；Progress＝成功的 assistant 事件數；Statuses＝狀態碼分布（例 504×5、無回應×1）
#   Kind：NONE｜API_RETRY_SLOW（有重試、之後仍有進展＝被拖慢）｜
#         API_RETRY_STUCK（同一個請求連續失敗達 $script:PsOcApiStuckAfter 次，或重試用完仍失敗）｜API_ERROR（沒有重試就以 API 錯誤收場）
function Get-PsOcClaudeApiRetry {
    param([string]$StreamFile)
    $r = @{ Kind = 'NONE'; Count = 0; Trailing = 0; Recovered = $false; Progress = 0; Statuses = ''; ApiErrorStatus = '' }
    if (-not $StreamFile -or -not [System.IO.File]::Exists($StreamFile)) { return $r }
    $st = [ordered]@{}
    $fs = $null
    $rd = $null
    try {
        $fs = New-Object System.IO.FileStream($StreamFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $rd = New-Object System.IO.StreamReader($fs, (New-Object System.Text.UTF8Encoding($false)))
        while ($true) {
            $ln = $rd.ReadLine()
            if ($null -eq $ln) { break }
            $k = $ln.IndexOf('"subtype":"api_retry"')
            if ($k -ge 0 -and $k -lt 80) {
                $r.Count++
                $r.Trailing++
                $s = '無回應'
                $m = [regex]::Match($ln, '"error_status":(\d+)')
                if ($m.Success) { $s = $m.Groups[1].Value }
                if ($st.Contains($s)) { $st[$s] = [int]$st[$s] + 1 } else { $st[$s] = 1 }
                continue
            }
            $k = $ln.IndexOf('"type":"assistant"')
            if ($k -ge 0 -and $k -lt 20) {
                # API 錯誤訊息（error 欄位或「API Error」文字）不算進展
                if ($ln.Contains('"error":"') -or $ln.Contains('"text":"API Error')) { continue }
                $r.Progress++
                if ($r.Trailing -gt 0) { $r.Recovered = $true }
                $r.Trailing = 0
                continue
            }
            $k = $ln.IndexOf('"type":"result"')
            if ($k -ge 0 -and $k -lt 40) {
                $m = [regex]::Match($ln, '"api_error_status":(\d+)')
                if ($m.Success) { $r.ApiErrorStatus = $m.Groups[1].Value }
            }
        }
    }
    catch { }
    finally {
        if ($null -ne $rd) { $rd.Dispose() }
        elseif ($null -ne $fs) { $fs.Dispose() }
    }
    $parts = @()
    foreach ($key in $st.Keys) { $parts += ([string]$key + '×' + [string]$st[$key]) }
    $r.Statuses = $parts -join '、'
    if ($r.ApiErrorStatus -ne '') {
        if ($r.Trailing -gt 0) { $r.Kind = 'API_RETRY_STUCK' } else { $r.Kind = 'API_ERROR' }
    }
    elseif ($r.Trailing -ge $script:PsOcApiStuckAfter) { $r.Kind = 'API_RETRY_STUCK' }
    elseif ($r.Count -gt 0) { $r.Kind = 'API_RETRY_SLOW' }
    return $r
}

# 失敗 session 的模型端判讀（Get-PsOcClaudeApiRetry 的 Kind）→ 下一步；沒有模型端事件回空字串（呼叫端沿用原本的說法）
function Get-PsOcApiHint {
    param([string[]]$Kinds, [int]$TimeoutMin, [string]$ParamName = 'TimeoutMin')
    $ks = @($Kinds)
    if ($ks -contains 'API_RETRY_STUCK') { return '卡在模型端（gateway）：同一個請求連續失敗，調高逾時多半沒用；把畫面上 SESSION 判讀行的狀態碼、次數與時間交 IT 查 gateway 逾時，恢復後同命令續跑' }
    if ($ks -contains 'API_ERROR') { return '模型 API 錯誤（沒有重試，不是逾時類）：檢查 Claude Code 登入、權限與模型名稱後同命令續跑' }
    if ($ks -contains 'API_RETRY_SLOW') { return ('被模型端重試拖慢到逾時（每個 session 上限 ' + $TimeoutMin + ' 分）：用更大的 -' + $ParamName + ' 續跑') }
    return ''
}

# OpenCode 版：模型是否在「opencode models <provider>」的清單裡（opencode run --model 只認清單裡的 <provider>/<model>）。
# 開 session 前先問，名字填錯或 provider 沒設定時不必等 session 失敗（那時 OpenCode 只回一句 Unexpected server error）。
# 回 @{ Result; Message; Count }：Result＝OK｜NOT_LISTED（provider 有、清單沒有這個模型）｜NO_PROVIDER（OpenCode 沒有這個 provider）｜
#   UNKNOWN（查不了：逾時、無法執行、沒有任何輸出；呼叫端不擋）。Windows 以 cmd.exe 檔案重導啟動（同 Invoke-PsOcSession），其他平台直接啟動。
function Test-PsOcOpencodeModel {
    param([string]$OcPath, [string]$Model, [string]$Root, [string]$LogRoot, [int]$TimeoutSec = 120)
    $r = @{ Result = 'UNKNOWN'; Message = ''; Count = 0 }
    $i = ([string]$Model).IndexOf('/')
    if ($i -le 0) { $r.Result = 'NOT_LISTED'; $r.Message = ('「' + $Model + '」不是 <provider>/<model> 的形狀'); return $r }
    $provider = $Model.Substring(0, $i)
    if ($provider -cnotmatch '^[A-Za-z0-9_][A-Za-z0-9_.@-]*$') { $r.Result = 'NOT_LISTED'; $r.Message = ('provider「' + $provider + '」含不允許的字元'); return $r }
    if (-not (Test-Path -LiteralPath $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $outFile = Join-Path $LogRoot ($stamp + '-models.out.txt')
    $errFile = Join-Path $LogRoot ($stamp + '-models.err.txt')
    $win = ([System.IO.Path]::DirectorySeparatorChar -eq [char]92)
    $p = $null
    try {
        if ($win) {
            $p = Start-Process -FilePath 'cmd.exe' -ArgumentList ('/d /s /c ""' + $OcPath + '" models ' + $provider + ' 1> "' + $outFile + '" 2> "' + $errFile + '""') -WorkingDirectory $Root -NoNewWindow -PassThru
        }
        else {
            $p = Start-Process -FilePath $OcPath -ArgumentList @('models', $provider) -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        }
        try { $null = $p.Handle } catch { }
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            if ($win) { & taskkill.exe /PID $p.Id /T /F 2>$null | Out-Null } else { try { $p.Kill() } catch { } }
            $r.Message = ('opencode models ' + $provider + ' 超過 ' + $TimeoutSec + ' 秒沒有結束')
            return $r
        }
        try { $p.WaitForExit() } catch { }
    }
    catch { $r.Message = ('opencode models 無法執行：' + $_.Exception.Message); return $r }
    $txt = ''
    foreach ($f in @($outFile, $errFile)) { if (Test-Path -LiteralPath $f) { $txt += [System.IO.File]::ReadAllText($f) + "`n" } }
    $txt = [regex]::Replace($txt, '\x1B\[[0-9;]*[A-Za-z]', '')
    $names = @()
    foreach ($ln in ($txt -split "`n")) {
        $t = $ln.Trim()
        if ($t.StartsWith($provider + '/', [System.StringComparison]::Ordinal) -and $t -cmatch '^\S+$') { $names += $t }
    }
    $r.Count = $names.Count
    if ($names -ccontains $Model) { $r.Result = 'OK'; $r.Message = ('「opencode models ' + $provider + '」有列出 ' + $Model); return $r }
    if ($txt -match '(?i)provider not found') { $r.Result = 'NO_PROVIDER'; $r.Message = ('OpenCode 沒有 provider「' + $provider + '」（opencode models ' + $provider + '：Provider not found）'); return $r }
    if ($names.Count -gt 0) { $r.Result = 'NOT_LISTED'; $r.Message = ('「opencode models ' + $provider + '」列出 ' + $names.Count + ' 個模型，沒有「' + $Model + '」'); return $r }
    $r.Message = ('opencode models ' + $provider + ' 沒有列出任何模型（輸出在 ' + $outFile + '）')
    return $r
}

# Claude Code 的權限模式（headless 預設 dontAsk：只執行 .claude/settings.json 允許清單內的工具，其餘自動拒絕、不會卡在詢問）
function Get-PsOcClaudePermissionMode {
    $pm = ([string]$env:PS_CLAUDE_PERMISSION_MODE).Trim()
    foreach ($ok in @('dontAsk', 'acceptEdits', 'default', 'auto', 'bypassPermissions')) { if ($pm -ceq $ok) { return $pm } }
    return 'dontAsk'
}

# cmd.exe 的內層命令列（不含 rc 檔那段）。回 @{ Inner; LogArgs; Agent; Prompt }。
#   OpenCode：opencode run [--model] <ExtraArgs> --title "auto-<Tag>" "<prompt>" 1> out 2> err
#   Claude Code：claude -p --agent <主代理> [--model] --permission-mode <dontAsk> --output-format stream-json --verbose "<prompt>" < NUL 1> stream 2> err
#     --command X → prompt「/X <PromptText>」、主代理取 ps-cli-lib 的指令對照（Claude Code 的指令不切換主代理）；--agent Y 原樣
function New-PsOcCommandLine {
    param([string]$Variant, [string]$OcPath, [string]$Model = '', [string]$ExtraArgs = '', [string]$PromptText,
        [string]$Tag, [string]$OutFile, [string]$ErrFile, [string]$StreamFile = '')
    if ($Variant -eq 'claude') {
        $agent = ''
        $cmdName = ''
        $mA = [regex]::Match($ExtraArgs, '--agent\s+([A-Za-z0-9_-]+)')
        if ($mA.Success) { $agent = $mA.Groups[1].Value }
        $mC = [regex]::Match($ExtraArgs, '--command\s+([A-Za-z0-9_-]+)')
        if ($mC.Success) { $cmdName = $mC.Groups[1].Value }
        $promptOut = $PromptText
        if ($cmdName -ne '') {
            $promptOut = '/' + $cmdName + ' ' + $PromptText
            if ($agent -eq '') { $agent = Get-PsCliCommandAgent -Command $cmdName }
        }
        $inner = '"' + $OcPath + '" -p '
        if ($agent -ne '') { $inner += '--agent ' + $agent + ' ' }
        if ($Model -ne '') { $inner += '--model "' + $Model + '" ' }
        $inner += '--permission-mode ' + (Get-PsOcClaudePermissionMode) + ' --output-format stream-json --verbose '
        $inner += '"' + $promptOut + '" < NUL 1> "' + $StreamFile + '" 2> "' + $ErrFile + '"'
        return @{ Inner = $inner; LogArgs = ('--agent ' + $agent + ' ｜ ' + $promptOut); Agent = $agent; Prompt = $promptOut }
    }
    $inner = '"' + $OcPath + '" run '
    if ($Model -ne '') { $inner += '--model "' + $Model + '" ' }
    if ($ExtraArgs -ne '') { $inner += $ExtraArgs + ' ' }
    $inner += '--title "auto-' + $Tag + '" '
    $inner += '"' + $PromptText + '" 1> "' + $OutFile + '" 2> "' + $ErrFile + '"'
    return @{ Inner = $inner; LogArgs = ($ExtraArgs + ' ｜ ' + $PromptText); Agent = ''; Prompt = $PromptText }
}

# 開一個新鮮 headless session（逾時整樹強殺）。回傳 @{ TimedOut; ExitCode; ErrFile; OutFile; FailureKind; SlotBusy; SlotWaitedSec; ApiKind }
#   ApiKind：Claude Code 版 stream 的模型端重試判讀（Get-PsOcClaudeApiRetry 的 Kind）；只供說明，不改變成敗判定
#   -ExtraArgs 例：'--command ps-research' 或 '--agent ps-deep-research'（OpenCode 原樣傳；Claude Code 轉成
#     --agent <該指令的主代理>＋prompt「/ps-research <PromptText>」，輸出 stream-json 落 .stream.jsonl、最終回覆抽進 OutFile）
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
        return @{ TimedOut = $false; ExitCode = -1; ErrFile = $errFile; OutFile = $outFile; FailureKind = 'PROMPT_UNSAFE'; SlotBusy = $false; SlotWaitedSec = 0; ApiKind = 'NONE' }
    }
    $slot = Enter-PsOcSessionSlot -WaitMin $SlotWaitMin -Log $Log
    if (-not $slot.Held) {
        L "SESSION($Tag) 未啟動：$($slot.Reason)（等了 $($slot.WaitedSec) 秒）——另一個 ps-auto-loop／ps-spec／補研究 session 正在用模型服務，錯開時間再跑"
        return @{ TimedOut = $true; ExitCode = -1; ErrFile = $errFile; OutFile = $outFile; FailureKind = 'SLOT_BUSY'; SlotBusy = $true; SlotWaitedSec = $slot.WaitedSec; ApiKind = 'NONE' }
    }
    try {
        # 結束碼落檔：不相信 Process 物件的 .ExitCode（-PassThru 物件在只用 WaitForExit(ms) 等待時常為 $null，
        # 而 $null -eq 0 為 false＝每個正常 session 都被判成錯誤）。改讓 cmd 把 ERRORLEVEL 寫進檔案——要可觀測的事實。
        $rcFile = Join-Path $LogRoot ('{0}-{1}.rc.txt' -f $stamp, $Tag)
        $variant = Get-PsCliVariant -Root $Root
        $streamFile = ''
        if ($variant.Name -eq 'claude') { $streamFile = Join-Path $LogRoot ('{0}-{1}.stream.jsonl' -f $stamp, $Tag) }
        $watch = @($outFile, $errFile)
        if ($streamFile -ne '') { $watch += $streamFile }
        $cl = New-PsOcCommandLine -Variant $variant.Name -OcPath $OcPath -Model $Model -ExtraArgs $ExtraArgs -PromptText $PromptText `
            -Tag $Tag -OutFile $outFile -ErrFile $errFile -StreamFile $streamFile
        $inner = $cl.Inner
        $logArgs = $cl.LogArgs
        # %^ERRORLEVEL% ＋ call：延後展開，取得的才是 CLI 的真實結束碼
        $inner += ' & call echo %^ERRORLEVEL% > "' + $rcFile + '"'
        L "SESSION($Tag) 啟動：$logArgs"
        # Claude Code 在自己的 session 內會設 CLAUDECODE；子行程繼承它會被當成巢狀 session——啟動當下拿掉、啟動後還原
        $ccSaved = $null
        if ($variant.Name -eq 'claude' -and $null -ne $env:CLAUDECODE) { $ccSaved = $env:CLAUDECODE; Remove-Item -Path Env:\CLAUDECODE -ErrorAction SilentlyContinue }
        try {
            $p = Start-Process -FilePath 'cmd.exe' -ArgumentList ('/d /s /c "' + $inner + '"') `
                -WorkingDirectory $Root -NoNewWindow -PassThru
        }
        finally {
            if ($null -ne $ccSaved) { $env:CLAUDECODE = $ccSaved }
        }
        # 必須先取用 .Handle 把行程 handle 快取住，否則 -PassThru 物件在只用 WaitForExit(ms) 等待時 .ExitCode 會是 $null
        try { $null = $p.Handle } catch { }
        $tpn = $TimeoutParamName
        if ($tpn -eq '') { if ($Tag -like 'audit*') { $tpn = 'AuditTimeoutMin' } else { $tpn = 'ResearchTimeoutMin' } }
        # 心跳：session 期間 CLI 輸出全被重導到檔案，console 會完全安靜——每 5 分鐘印一行「還活著＋已耗時」
        $sessStart = Get-Date
        $lastBeat = $sessStart
        $done = $false
        while (((Get-Date) - $sessStart).TotalMinutes -lt $TimeoutMin) {
            if ($p.WaitForExit(30000)) { $done = $true; break }
            if (((Get-Date) - $lastBeat).TotalMinutes -ge 5) {
                $mins = [int]((Get-Date) - $sessStart).TotalMinutes
                # 沉默停滯偵測（確定性、只警告不強殺）：輸出檔多久沒長大
                $lastOut = $sessStart
                foreach ($lf in $watch) {
                    if (Test-Path -LiteralPath $lf) {
                        $wt = (Get-Item -LiteralPath $lf).LastWriteTime
                        if ($wt -gt $lastOut) { $lastOut = $wt }
                    }
                }
                $silent = [int]((Get-Date) - $lastOut).TotalMinutes
                $note = ''
                if ($silent -ge 20) { $note = "；輸出已靜止 $silent 分（委派期間長時間無輸出屬常態，實測健康可達 30 分；接近逾時上限仍無輸出才需依 SOP-12 查 oracleMCP 通道）" }
                # 模型端重試（Claude Code 版）：重試事件也會讓 stream 變大，靜止時間看不出來——直接數
                $apiNote = ''
                if ($streamFile -ne '') {
                    $hb = Get-PsOcClaudeApiRetry -StreamFile $streamFile
                    if ($hb.Count -gt 0) {
                        $apiNote = "；模型端重試 $($hb.Count) 次（$($hb.Statuses)）"
                        if ($hb.Trailing -gt 0) { $apiNote += "，目前這個請求已連續失敗 $($hb.Trailing) 次" } else { $apiNote += '，之後已恢復' }
                    }
                }
                L "SESSION($Tag) 進行中…已 $mins 分（逾時上限 $TimeoutMin 分）$apiNote$note"
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
            foreach ($lf in $watch) {
                if (Test-Path -LiteralPath $lf) {
                    $wt = (Get-Item -LiteralPath $lf).LastWriteTime
                    if ($wt -gt $lastOutK) { $lastOutK = $wt }
                }
            }
            $killSilent = [int]((Get-Date) - $lastOutK).TotalMinutes
            L "SESSION($Tag) 逾時 $TimeoutMin 分，已整樹強制結束（狀態在檔案，無損）"
            if ($streamFile -ne '') { $null = Convert-PsOcClaudeStream -StreamFile $streamFile -OutFile $outFile }
            # 模型端重試先判：重試事件會讓 stream 一直變大，只看靜止時間會把「卡在模型端」誤判成「上限太短」
            $api = Get-PsOcClaudeApiRetry -StreamFile $streamFile
            $apiTxt = "模型端重試共 $($api.Count) 次（$($api.Statuses)）"
            if ($api.Kind -eq 'API_RETRY_STUCK') {
                $first = ''
                if ($api.Progress -eq 0) { $first = '；第一個請求就沒成功過＝gateway 或模型服務不通、過載' }
                L "SESSION($Tag) 判讀：強殺前同一個請求已連續失敗 $($api.Trailing) 次（$apiTxt）＝**卡在模型端（gateway）**$first——調高 -$tpn 多半沒用；把狀態碼、次數與時間交 IT 查 gateway 逾時"
            }
            elseif ($killSilent -ge 20) {
                L "SESSION($Tag) 判讀：輸出已靜止 $killSilent 分才被強殺＝**疑似卡在工具呼叫**——依 SOP-12 查 oracleMCP／模型服務通道，調高上限沒有用"
            }
            elseif ($api.Kind -eq 'API_RETRY_SLOW') {
                L "SESSION($Tag) 判讀：$apiTxt，重試後仍有進展＝**被模型端拖慢，不是卡死**——把 -$tpn 調高後重跑"
            }
            elseif ($killSilent -le 5) {
                L "SESSION($Tag) 判讀：強殺當下輸出仍在增加（靜止僅 $killSilent 分）＝**上限太短，不是卡死**——把 -$tpn 調高後重跑，不要去查 MCP 通道"
            }
            else {
                L "SESSION($Tag) 判讀：強殺當下靜止 $killSilent 分（介於兩者之間）——先看 out 檔尾端停在哪個步驟再決定調上限或查通道"
            }
            $fkT = Get-PsOcFailureKind -OutFile $outFile -ErrFile $errFile
            if ($fkT -ne 'NONE') { L "SESSION($Tag) 容量事件：$fkT（out/err 含 context 溢出字樣）——逾時前已撞 context 上限，調時間無用；見 SOP-10" }
            return @{ TimedOut = $true; ExitCode = -1; ErrFile = $errFile; OutFile = $outFile; FailureKind = $fkT; SlotBusy = $false; SlotWaitedSec = $slot.WaitedSec; ApiKind = $api.Kind }
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
        if ($streamFile -ne '') {
            $cr = Convert-PsOcClaudeStream -StreamFile $streamFile -OutFile $outFile
            if (-not $cr.Found) { L "SESSION($Tag) stream 沒有 result 事件（session 可能在啟動階段就死——看 err 檔與 $streamFile）" }
            elseif ($cr.IsError) { L "SESSION($Tag) Claude Code 回報錯誤收場：subtype=$($cr.Subtype) turns=$($cr.Turns)" }
        }
        $api = Get-PsOcClaudeApiRetry -StreamFile $streamFile
        $apiTxt = "模型端重試共 $($api.Count) 次（$($api.Statuses)）"
        if ($api.Kind -eq 'API_RETRY_STUCK') {
            $first = ''
            if ($api.Progress -eq 0) { $first = '；第一個請求就沒成功過＝gateway 或模型服務不通、過載' }
            $aes = ''
            if ($api.ApiErrorStatus -ne '') { $aes = "（api_error_status=$($api.ApiErrorStatus)）" }
            L "SESSION($Tag) 判讀：Claude Code 重試用完仍失敗$aes，同一個請求連續失敗 $($api.Trailing) 次（$apiTxt）＝**卡在模型端（gateway）**$first——把狀態碼、次數與時間交 IT 查 gateway 逾時"
        }
        elseif ($api.Kind -eq 'API_ERROR') { L "SESSION($Tag) 判讀：API 錯誤 api_error_status=$($api.ApiErrorStatus)，沒有重試＝不是逾時類——檢查 Claude Code 登入、權限與模型名稱" }
        elseif ($api.Kind -eq 'API_RETRY_SLOW') { L "SESSION($Tag) $apiTxt，重試後已恢復（被拖慢，沒有卡住）" }
        L "SESSION($Tag) 結束 exit=$code 耗時 $([int]((Get-Date) - $sessStart).TotalMinutes) 分，輸出：$outFile"
        $fk = Get-PsOcFailureKind -OutFile $outFile -ErrFile $errFile
        if ($fk -ne 'NONE') { L "SESSION($Tag) 容量事件：$fk（out/err 含 context 溢出字樣；exit=$code 不代表沒事——子代理溢出多半 exit 0）——處置見 SOP-10，不要只調 timeout" }
        return @{ TimedOut = $false; ExitCode = $code; ErrFile = $errFile; OutFile = $outFile; FailureKind = $fk; SlotBusy = $false; SlotWaitedSec = $slot.WaitedSec; ApiKind = $api.Kind }
    }
    finally {
        Exit-PsOcSessionSlot -Slot $slot
    }
}
