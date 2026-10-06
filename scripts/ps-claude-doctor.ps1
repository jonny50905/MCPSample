# ps-claude-doctor.ps1 — Claude Code 版的安裝健檢（公司機；PowerShell 5.1；唯讀，不改任何設定）
# 用法：powershell -NoProfile -File .\scripts\ps-claude-doctor.ps1          ← 搬完、註冊 MCP、信任資料夾後跑
#       powershell -NoProfile -File .\scripts\ps-claude-doctor.ps1 -Live    ← 另開一個真 headless session 只做「第 0 步開線」（花極少量 token）
#       -Offline：不呼叫 claude CLI（只驗版本判定、hook、profile；維護端測試用）
# 檢查：V 版本判定（.claude/peoplesoft＋CLAUDE.md）／C claude 執行檔與版本（2.1 以上）／P powershell 在 PATH（hook 靠它）／
#       H hook 自測（connect 目標比對、skill 名委派被擋，輸出必須是合法 JSON）／F profile 的 oracle.connectionName 已回填／
#       N 四個 MCP 已註冊且連得上（claude mcp list；名字逐字相同）／-Live：T 工具被拒（多半是資料夾沒信任）、L 第 0 步 connect 沒成功。
# 資安：實際連線名、路徑只印在你螢幕上；回報維護 session 只講最後一行「結論代號」。
param(
    [switch]$Live,
    [switch]$Offline,
    [string]$Model = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'ps-cli-lib.ps1')
. (Join-Path $PSScriptRoot 'ps-session-lib.ps1')
$findings = @()
function Say([string]$Text, [string]$Color = '') {
    if ($Color -ne '') { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
}
function Add-Finding([string]$Code, [string]$Text) {
    $script:findings += $Code
    Say ('  !! ' + $Text) 'Red'
}

Say '=== ps-claude-doctor：Claude Code 版安裝健檢（唯讀） ===' 'Cyan'

Say '[檢查 V] 版本判定'
$v = Get-PsCliVariant -Root $root
if ($v.Name -ne 'claude') { Add-Finding 'V' ('外環判定為 ' + $v.Display + '（' + $v.Source + '）——.claude\peoplesoft 不在或 PS_CLI 設成 opencode') }
elseif (-not (Test-Path -LiteralPath (Join-Path $root 'CLAUDE.md'))) { Add-Finding 'V' '缺 CLAUDE.md（搬運不完整）' }
else { Say '  Claude Code 版（.claude\peoplesoft 與 CLAUDE.md 都在）' 'Green' }

Say '[檢查 P] powershell 在 PATH（hook 指令是 powershell -NoProfile -File …）'
$psCmd = @(Get-Command powershell -ErrorAction SilentlyContinue)
if ($psCmd.Count -eq 0) { Add-Finding 'P' 'PATH 找不到 powershell——Claude Code 的 hook 無法執行，guard 形同關閉' }
else { Say ('  ' + $psCmd[0].Source) 'Green' }

Say '[檢查 F] profile oracle.connectionName'
$profilePath = Get-PsCliPsPath -Root $root -Rel 'customization-profile.yaml'
$profileName = ''
if (Test-Path -LiteralPath $profilePath) {
    $pt = [System.IO.File]::ReadAllText($profilePath, [System.Text.Encoding]::UTF8)
    $m = [regex]::Match($pt, '(?m)^\s+connectionName:\s*([^#\r\n]*?)\s*(#.*)?$')
    if ($m.Success) { $profileName = $m.Groups[1].Value.Trim().Trim('"', "'") }
}
if ($profileName -eq '' -or $profileName.ToUpperInvariant() -eq 'FILL_ME') { Add-Finding 'F' ('未回填（目前＝' + $(if ($profileName -eq '') { '空' } else { $profileName }) + '）——把 OpenCode 版 profile 的值抄到 ' + $v.PsDir + '/customization-profile.yaml') }
else { Say '  已回填' 'Green' }

Say '[檢查 H] hook 自測'
$hook = Join-Path $root (Join-Path '.claude' (Join-Path 'hooks' 'ps-runtime-guard.ps1'))
function Invoke-HookProbe([string]$Json, [string]$ExeName) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ExeName
    $psi.Arguments = '-NoProfile -File "' + $hook + '" -Mode pre'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $root
    $p = [System.Diagnostics.Process]::Start($psi)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
    $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEnd()
    $null = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return @{ Out = $out; Exit = $p.ExitCode }
}
if (-not (Test-Path -LiteralPath $hook)) { Add-Finding 'H' '缺 .claude\hooks\ps-runtime-guard.ps1' }
elseif ($psCmd.Count -gt 0) {
    try {
        $probeName = 'PS_DOCTOR_PROBE_NOT_A_CONNECTION'
        $r1 = Invoke-HookProbe ('{"tool_name":"mcp__oracleMCP__connect","tool_input":{"connection_name":"' + $probeName + '"},"session_id":"doctor"}') $psCmd[0].Source
        $r2 = Invoke-HookProbe '{"tool_name":"Agent","tool_input":{"subagent_type":"ps-security-flow","prompt":"x"},"session_id":"doctor"}' $psCmd[0].Source
        $o1 = $null; $o2 = $null
        try { $o1 = $r1.Out | ConvertFrom-Json } catch { }
        try { $o2 = $r2.Out | ConvertFrom-Json } catch { }
        $d1 = ''; $d2 = ''
        if ($null -ne $o1) { $d1 = [string]$o1.hookSpecificOutput.permissionDecisionReason }
        if ($null -ne $o2) { $d2 = [string]$o2.hookSpecificOutput.permissionDecisionReason }
        $guardMode = ([string]$env:PS_ORACLE_CONNECT_GUARD).Trim().ToLowerInvariant()
        if ($guardMode -ne 'observe' -and $d1 -notmatch '^ORACLE_CONNECTION_(MISMATCH|NOT_CONFIGURED)') { Add-Finding 'H' ('connect 目標 guard 沒有擋下測試名（exit=' + $r1.Exit + '）——hook 沒執行或輸出不是 JSON') }
        elseif ($d2 -notmatch '^PS_TASK_TARGET_INVALID') { Add-Finding 'H' ('Agent 委派 guard 沒有擋下 skill 名（exit=' + $r2.Exit + '）') }
        else { Say '  connect 目標與 Agent 委派兩個 guard 都在（輸出為合法 JSON）' 'Green' }
    }
    catch { Add-Finding 'H' ('hook 自測執行失敗：' + $_.Exception.Message) }
}

if ($Offline) {
    Say '[檢查 C／N] -Offline：略過 claude CLI'
}
else {
    Say '[檢查 C] claude 執行檔與版本'
    $cli = Get-PsOcPath -Root $root
    $claudeOk = $false
    if ($cli.Path -eq '') { Add-Finding 'C' $cli.Error }
    else {
        $ver = ''
        try { $ver = ((& $cli.Path --version 2>&1 | ForEach-Object { [string]$_ }) -join ' ').Trim() } catch { $ver = '' }
        $mv = [regex]::Match($ver, '(\d+)\.(\d+)\.(\d+)')
        if (-not $mv.Success) { Add-Finding 'C' ('claude --version 讀不到版本（' + $cli.Path + '）') }
        elseif ([int]$mv.Groups[1].Value -lt 2 -or ([int]$mv.Groups[1].Value -eq 2 -and [int]$mv.Groups[2].Value -lt 1)) { Add-Finding 'C' ('Claude Code ' + $mv.Value + ' 太舊——需要 2.1 以上（--agent、dontAsk、agent hooks）') }
        else { Say ('  ' + $cli.Path + '（' + $mv.Value + '）') 'Green'; $claudeOk = $true }
    }
    Say '[檢查 N] MCP 註冊（claude mcp list；會啟動各 server 做健康檢查）'
    if ($claudeOk) {
        $saved = [Console]::OutputEncoding
        $list = ''
        try {
            [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
            Push-Location -LiteralPath $root
            try { $list = ((& $cli.Path mcp list 2>&1 | ForEach-Object { [string]$_ }) -join "`n") } finally { Pop-Location }
        }
        catch { $list = '' }
        finally { [Console]::OutputEncoding = $saved }
        foreach ($n in @('oracleMCP', 'PeoplecodeElasticSearch', 'PeoplecodeSource', 'PeoplecodeMetadata')) {
            $line = @($list -split "`n" | Where-Object { $_ -match ('^\s*' + [regex]::Escape($n) + ':') })
            if ($line.Count -eq 0) { Add-Finding 'N' ($n + '：沒有以這個名字註冊（名字要逐字相同；claude mcp add --scope user ' + $n + ' …）') }
            elseif ($line[0] -match '(?i)fail|error|✗') { Add-Finding 'N' ($n + '：已註冊但連不上——' + $line[0].Trim()) }
            else { Say ('  ' + $n + '：已註冊') 'Green' }
        }
    }
    if ($Live -and $claudeOk -and $profileName -ne '' -and $profileName.ToUpperInvariant() -ne 'FILL_ME') {
        Say '[檢查 T／L] 真 headless session：只做第 0 步開線（ps-orchestrator、dontAsk）'
        $logDir = Join-Path $root (Join-Path 'auto-loop-logs' 'ps-claude-doctor')
        $sr = Invoke-PsOcSession -OcPath $cli.Path -Root $root -LogRoot $logDir -Model $Model -ExtraArgs '--agent ps-orchestrator' `
            -PromptText '健檢：只做第 0 步開線——讀 profile 後以 profile 的連線名呼叫 mcp__oracleMCP__connect 一次，回覆一行 CONNECT_OK 或 CONNECT_FAILED 加錯誤原文，不要做其他事' `
            -TimeoutMin 10 -Tag 'doctor' -Log { param($m) Write-Host ('  ' + $m) } -SlotWaitMin 0 -TimeoutParamName 'TimeoutMin'
        $stream = @(Get-ChildItem -LiteralPath $logDir -Filter '*-doctor.stream.jsonl' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1)
        $denied = @(); $connectOk = $false
        if ($stream.Count -gt 0) {
            $ids = @{}
            foreach ($ln in [System.IO.File]::ReadLines($stream[0].FullName, (New-Object System.Text.UTF8Encoding($false)))) {
                $o = $null
                try { $o = $ln | ConvertFrom-Json } catch { continue }
                if ($o.type -eq 'assistant') { foreach ($c in @($o.message.content)) { if ($c.type -eq 'tool_use' -and $c.name -eq 'mcp__oracleMCP__connect') { $ids[[string]$c.id] = $true } } }
                if ($o.type -eq 'user') { foreach ($c in @($o.message.content)) { if ($c.type -eq 'tool_result' -and $ids.ContainsKey([string]$c.tool_use_id) -and -not [bool]$c.is_error) { $connectOk = $true } } }
                if ($o.type -eq 'result') { foreach ($d in @($o.permission_denials)) { if ($null -ne $d) { $denied += [string]$d.tool_name } } }
            }
        }
        if ($sr.TimedOut -or $sr.ExitCode -ne 0) { Add-Finding 'L' ('session 未正常結束（exit=' + $sr.ExitCode + '，逾時=' + $sr.TimedOut + '）——看 ' + $logDir + ' 的 err 檔') }
        if ($denied.Count -gt 0) { Add-Finding 'T' ('工具被拒：' + (($denied | Sort-Object -Unique) -join ', ') + '——資料夾沒信任（先互動執行一次 claude 接受信任）或 settings.json 沒搬到') }
        if (-not $connectOk) { Add-Finding 'L' '第 0 步 connect 沒有成功——看上面的 T／F／N，再看 stream 檔的 connect 回覆' }
        elseif ($denied.Count -eq 0) { Say '  connect 成功、沒有工具被拒' 'Green' }
    }
    elseif ($Live) { Say '[檢查 T／L] 略過：claude 不可用或 profile 未回填' 'Yellow' }
}

$codes = @($findings | Sort-Object -Unique)
if ($codes.Count -eq 0) { $codes = @('G') }
Say ''
Say '代號說明：V=不是 Claude Code 版（.claude\peoplesoft／CLAUDE.md 缺，或 PS_CLI=opencode）  C=claude 找不到或版本太舊'
Say '          P=powershell 不在 PATH（hook 不會執行）  H=hook 自測失敗  F=profile oracle.connectionName 未回填'
Say '          N=MCP 未註冊／名字不符／連不上  T=headless 工具被拒（多半是資料夾未信任）  L=第 0 步 connect 沒成功  G=全部正常'
Say ('結論代號：' + ($codes -join '+')) 'Cyan'
Say '（回報維護 session 只需要這一行的代號）'
if ($codes[0] -eq 'G') { exit 0 }
exit 1
