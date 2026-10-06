# ps-runtime-guard.ps1 — Claude Code hook：無狀態 guard，沒有派工閘門、沒有 READY／todo 狀態機
#
# -Mode pre（.claude/settings.json 的 PreToolUse，matcher：mcp__oracleMCP__connect|Agent|Task）
#   (1) Oracle connect 目標：本次 connection_name 必須等於 profile oracle.connectionName。
#       未填／FILL_ME → ORACLE_CONNECTION_NOT_CONFIGURED；不一致或沒帶 → ORACLE_CONNECTION_MISMATCH；工具不執行、不改參數。
#       env PS_ORACLE_CONNECT_GUARD=observe 或 profile oracle.connectGuard: observe → 只記錄不擋（enforce 為預設）。
#   (2) Agent 委派目標：skill 名、主代理專用名（ps-orchestrator／ps-deep-research／ps-spec-worker／ps-clone-worker）一律擋；
#       呼叫者是 ps-* 主代理（hook 輸入的 agent_type）時更嚴：只准 .claude/agents 裡可當子代理的 ps-* agent——內建或不存在的代理、
#       沒帶 subagent_type（＝內建 general-purpose）也擋。一般 session（沒有 --agent，agent_type 空）可用內建代理做維護／排錯。
#       擋＝PS_TASK_TARGET_INVALID（訊息指出該派誰）。
# -Mode post（PostToolUse，matcher：Agent|Task）
#   (3) 子代理報告的 suggestedNext[].agent 是 skill 名或不是可委派的 agent → 以 additionalContext 附一段
#       「[ps-runtime-guard] …」註記（報告本文不動）。
# -Mode path -PathProfile <spec-worker|clone-worker|spec-author>（worker agent 的 frontmatter hooks）
#   (4) 讀寫路徑白名單與 Bash 命令形狀；不在白名單 → PS_PATH_DENIED。hook 自己出錯也擋（fail-closed）。
#
# 擋＝stdout 印 PreToolUse 的 permissionDecision=deny JSON（理由文字就是模型看到的工具錯誤）；放行＝不印、exit 0。
# 輸出 JSON 全部 \u 轉義成 ASCII（PS 5.1 主控台碼頁不影響）；stdin 以位元組讀入再 UTF-8 解碼。
# 決策紀錄：<專案>/auto-loop-logs/ps-runtime-guard/hook-<yyyyMMdd>.jsonl（只記工具名、代理名、決策與錯誤碼；不記 SQL、prompt、連線字串）。
# PowerShell 5.1 紀律：無三元／??／&&；Join-Path 兩參數；-LiteralPath。
param(
    [string]$Mode = 'pre',
    [string]$PathProfile = ''
)

$ErrorActionPreference = 'Stop'
$script:GuardRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:ClaudeDir = Join-Path $script:GuardRoot '.claude'
$script:CodeTarget = 'PS_TASK_TARGET_INVALID'
$script:MainOnly = @('ps-orchestrator', 'ps-deep-research', 'ps-spec-worker', 'ps-clone-worker')
$script:SkillCarrier = @{ 'ps-security-flow' = 'ps-metadata-flow'; 'ps-data-lineage' = 'ps-metadata-flow'; 'ps-process-flow' = 'ps-metadata-flow' }
$script:SkillPrimaryOnly = @('ps-business-discovery', 'ps-business-explain', 'ps-impact-analysis')

function ConvertTo-PsGuardJsonString {
    param([string]$Text)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    if ($null -ne $Text) {
        foreach ($ch in $Text.ToCharArray()) {
            $c = [int]$ch
            if ($ch -eq '"') { [void]$sb.Append('\"') }
            elseif ($ch -eq '\') { [void]$sb.Append('\\') }
            elseif ($c -lt 32 -or $c -gt 126) { [void]$sb.Append('\u' + $c.ToString('x4')) }
            else { [void]$sb.Append($ch) }
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Write-PsGuardDeny {
    param([string]$Reason)
    [Console]::Out.Write('{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":' + (ConvertTo-PsGuardJsonString -Text $Reason) + '}}')
}

function Write-PsGuardPostNote {
    param([string]$Note)
    [Console]::Out.Write('{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":' + (ConvertTo-PsGuardJsonString -Text $Note) + '}}')
}

function Write-PsGuardLog {
    param([string]$Tool, [string]$Agent, [string]$Decision, [string]$Code, [string]$Session)
    try {
        $dir = Join-Path $script:GuardRoot (Join-Path 'auto-loop-logs' 'ps-runtime-guard')
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $file = Join-Path $dir ('hook-' + (Get-Date).ToString('yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture) + '.jsonl')
        $line = '{"ts":' + (ConvertTo-PsGuardJsonString -Text ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture))) +
            ',"mode":' + (ConvertTo-PsGuardJsonString -Text $Mode) + ',"profile":' + (ConvertTo-PsGuardJsonString -Text $PathProfile) +
            ',"tool":' + (ConvertTo-PsGuardJsonString -Text $Tool) + ',"agent":' + (ConvertTo-PsGuardJsonString -Text $Agent) +
            ',"decision":' + (ConvertTo-PsGuardJsonString -Text $Decision) + ',"code":' + (ConvertTo-PsGuardJsonString -Text $Code) +
            ',"session":' + (ConvertTo-PsGuardJsonString -Text $Session) + '}'
        [System.IO.File]::AppendAllText($file, $line + "`n", (New-Object System.Text.UTF8Encoding($false)))
    }
    catch { }
}

function Read-PsGuardInput {
    $stdin = [Console]::OpenStandardInput()
    $ms = New-Object System.IO.MemoryStream
    $stdin.CopyTo($ms)
    $raw = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
    if ($raw.Length -gt 0 -and [int]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
    if ($raw.Trim() -eq '') { return $null }
    return ($raw | ConvertFrom-Json)
}

function Get-PsGuardProp {
    param($Obj, [string]$Name)
    if ($null -eq $Obj) { return $null }
    $p = $Obj.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

# profile 的 oracle: 區塊 → @{ key = value }（只需支援「  key: value」與 # 註解）
function Read-PsGuardProfileOracle {
    $out = @{}
    $p = Join-Path $script:ClaudeDir (Join-Path 'peoplesoft' 'customization-profile.yaml')
    if (-not (Test-Path -LiteralPath $p)) { return $out }
    $text = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
    if ($text.Length -gt 0 -and [int]$text[0] -eq 0xFEFF) { $text = $text.Substring(1) }
    $inOracle = $false
    foreach ($ln in ($text -split "`r?`n")) {
        if ($ln -match '^oracle:\s*(#.*)?$') { $inOracle = $true; continue }
        if (-not $inOracle) { continue }
        if ($ln.Trim() -eq '' -or $ln.Trim().StartsWith('#')) { continue }
        if ($ln -notmatch '^\s') { break }
        $m = [regex]::Match($ln, '^\s+([A-Za-z_][A-Za-z0-9_]*):\s*([^#]*?)\s*(#.*)?$')
        if ($m.Success) { $out[$m.Groups[1].Value] = ($m.Groups[2].Value -replace '^["'']|["'']$', '') }
    }
    return $out
}

function Get-PsGuardConnectMode {
    param($Oracle)
    $e = ([string]$env:PS_ORACLE_CONNECT_GUARD).Trim().ToLowerInvariant()
    if ($e -eq 'enforce' -or $e -eq 'observe') { return $e }
    $v = ([string]$Oracle['connectGuard']).Trim().ToLowerInvariant()
    if ($v -eq 'enforce' -or $v -eq 'observe') { return $v }
    return 'enforce'
}

function Get-PsGuardConnectProblem {
    param([string]$ProfileName, [string]$Target)
    $tail = '模型：不要猜、不要從 list_connections 的清單挑名字（清單把名稱和連線字串黏在一起）；本題不派會查 DB 的委派，' +
        '向使用者回報「Oracle 連線未設定／連線名不一致（profile oracle.connectionName＝<值>）」，其餘部分照常作答。這不是 oracleMCP 掛載故障，不要重新連線 MCP。'
    if ($ProfileName -eq '' -or $ProfileName.ToUpperInvariant() -eq 'FILL_ME') {
        $shown = $ProfileName
        if ($shown -eq '') { $shown = '空' }
        return @{ Code = 'ORACLE_CONNECTION_NOT_CONFIGURED'; Message = ('ORACLE_CONNECTION_NOT_CONFIGURED：本次 mcp__oracleMCP__connect 未執行（被 Oracle 連線目標 guard 擋下，不是權限問題）。profile oracle.connectionName 未填（目前＝' + $shown + '）——請管理者在 .claude/peoplesoft/customization-profile.yaml 回填 SQLcl 已儲存連線名（實際連得上的那個名字）。' + $tail) }
    }
    if ($Target -eq '') {
        return @{ Code = 'ORACLE_CONNECTION_MISMATCH'; Message = ('ORACLE_CONNECTION_MISMATCH：本次 mcp__oracleMCP__connect 未執行（被 Oracle 連線目標 guard 擋下，不是權限問題）。呼叫沒有帶 connection_name；只准連 profile oracle.connectionName 指定的「' + $ProfileName + '」——用 connection_name＝「' + $ProfileName + '」重新呼叫。') }
    }
    if ($Target -cne $ProfileName) {
        return @{ Code = 'ORACLE_CONNECTION_MISMATCH'; Message = ('ORACLE_CONNECTION_MISMATCH：本次 mcp__oracleMCP__connect 未執行（被 Oracle 連線目標 guard 擋下，不是權限問題）。connect 目標「' + $Target + '」≠ profile oracle.connectionName「' + $ProfileName + '」。只准連 profile 指定的連線：用 connection_name＝「' + $ProfileName + '」原樣重新呼叫 connect。' + $tail) }
    }
    return $null
}

function Get-PsGuardAgentNames {
    $names = @{}
    $d = Join-Path $script:ClaudeDir 'agents'
    if (Test-Path -LiteralPath $d) {
        foreach ($f in @(Get-ChildItem -LiteralPath $d -File -Filter '*.md')) { $names[$f.BaseName] = $true }
    }
    return $names
}

function Get-PsGuardSkillNames {
    $names = @{}
    $d = Join-Path $script:ClaudeDir 'skills'
    if (Test-Path -LiteralPath $d) {
        foreach ($dir in @(Get-ChildItem -LiteralPath $d -Directory)) {
            if (Test-Path -LiteralPath (Join-Path $dir.FullName 'SKILL.md')) { $names[$dir.Name] = $true }
        }
    }
    return $names
}

function Get-PsGuardDelegatable {
    $agents = Get-PsGuardAgentNames
    $out = @()
    foreach ($k in @($agents.Keys | Sort-Object)) { if ($script:MainOnly -notcontains $k) { $out += $k } }
    return $out
}

# 委派目標檢查：回 $null＝可執行；否則 @{ Code; Kind; Carrier; Message }
function Get-PsGuardTargetProblem {
    param([string]$Target, [bool]$Strict = $true)
    $agents = Get-PsGuardAgentNames
    $skills = Get-PsGuardSkillNames
    $list = (Get-PsGuardDelegatable) -join '／'
    $tail = '這是路由錯誤，不是 Oracle 掛載或 DB 連線問題：不要 connect、不要重新連線 MCP、不要當成 Oracle 掛載故障回報，用正確的 subagent_type 重新委派即可。'
    if ($Target -eq '') {
        if (-not $Strict) { return $null }
        return @{ Code = $script:CodeTarget; Kind = 'missing'; Carrier = ''; Message = ($script:CodeTarget + '：本次 Agent 委派未執行——沒有指定 subagent_type（會落到內建 general-purpose，查不到 PeopleSoft）。可委派的 agent：' + $list + '。' + $tail) }
    }
    if ($agents.ContainsKey($Target)) {
        if ($script:MainOnly -contains $Target) {
            return @{ Code = $script:CodeTarget; Kind = 'main'; Carrier = ''; Message = ($script:CodeTarget + '：本次 Agent 委派未執行——「' + $Target + '」是主代理（以 claude --agent ' + $Target + ' 啟動），不能當子代理委派。可委派的 agent：' + $list + '。' + $tail) }
        }
        return $null
    }
    if ($skills.ContainsKey($Target)) {
        $where = '.claude/skills/' + $Target + '/SKILL.md'
        $carrier = ''
        if ($script:SkillCarrier.ContainsKey($Target)) {
            $carrier = $script:SkillCarrier[$Target]
            $next = '請改派承載 agent「' + $carrier + '」（subagent_type=' + $carrier + '），並在 prompt 指定「讀取 ' + $where + '，依 oracle-query-cookbook.md 對應章節查證，回傳既定 JSON 報告」。'
        }
        elseif ($script:SkillPrimaryOnly -contains $Target) {
            $next = '這個 skill 由主代理自己 Read ' + $where + ' 後遵守，不委派；需要檢索時依委派表拆成 ps-* 子代理的 Agent 委派。'
        }
        else {
            $next = '請依主代理的委派表選擇對應的 ps-* agent，並在 prompt 指定讀取 ' + $where + '。'
        }
        return @{ Code = $script:CodeTarget; Kind = 'skill'; Carrier = $carrier; Message = ($script:CodeTarget + '：本次 Agent 委派未執行——「' + $Target + '」是 skill（' + $where + '），不是可委派的 agent。' + $next + $tail) }
    }
    if (-not $Strict) { return $null }
    return @{ Code = $script:CodeTarget; Kind = 'unknown'; Carrier = ''; Message = ($script:CodeTarget + '：本次 Agent 委派未執行——「' + $Target + '」不是本專案的 ps-* 子代理（內建代理與其他代理查不到 PeopleSoft）。可委派的 agent：' + $list + '。' + $tail) }
}

# Agent 工具回傳 → 全部字串串起來（格式因版本而異：字串、content 陣列或物件）
function Get-PsGuardAllText {
    param($Obj, [int]$Depth = 0)
    if ($null -eq $Obj -or $Depth -gt 8) { return '' }
    if ($Obj -is [string]) { return $Obj }
    $sb = New-Object System.Text.StringBuilder
    if ($Obj -is [System.Collections.IEnumerable]) {
        foreach ($x in $Obj) { [void]$sb.Append((Get-PsGuardAllText -Obj $x -Depth ($Depth + 1))).Append("`n") }
        return $sb.ToString()
    }
    foreach ($p in @($Obj.PSObject.Properties)) {
        if ($p.MemberType -ne 'NoteProperty') { continue }
        [void]$sb.Append((Get-PsGuardAllText -Obj $p.Value -Depth ($Depth + 1))).Append("`n")
    }
    return $sb.ToString()
}

function Get-PsGuardSuggestedNotes {
    param([string]$Text)
    $notes = @()
    $agents = Get-PsGuardAgentNames
    $skills = Get-PsGuardSkillNames
    $seen = @{}
    foreach ($m in [regex]::Matches($Text, '"suggestedNext"\s*:\s*\[([\s\S]*?)\]')) {
        foreach ($a in [regex]::Matches($m.Groups[1].Value, '"agent"\s*:\s*"([^"]*)"')) {
            $name = $a.Groups[1].Value.Trim()
            if ($name -eq '' -or $seen.ContainsKey($name)) { continue }
            $seen[$name] = $true
            if ($agents.ContainsKey($name) -and $script:MainOnly -notcontains $name) { continue }
            if ($skills.ContainsKey($name) -and -not $agents.ContainsKey($name)) {
                if ($script:SkillCarrier.ContainsKey($name)) {
                    $c = $script:SkillCarrier[$name]
                    $notes += ('「' + $name + '」是 skill、不是 agent：改派 ' + $c + '（subagent_type=' + $c + '），並在 prompt 指定讀取 .claude/skills/' + $name + '/SKILL.md；不要用 subagent_type=' + $name)
                }
                else { $notes += ('「' + $name + '」是 skill、不是 agent：主代理自讀該 SKILL.md，不委派；不要用 subagent_type=' + $name) }
            }
            else { $notes += ('「' + $name + '」不是可委派的子代理；依主代理的委派表改派') }
        }
    }
    return $notes
}

# 路徑 → 專案根相對路徑（/ 分隔、小寫）；在專案根外回 $null
function Get-PsGuardRelPath {
    param([string]$PathText, [string]$Cwd)
    if ($null -eq $PathText -or $PathText.Trim() -eq '') { $PathText = '.' }
    $base = $Cwd
    if ($null -eq $base -or $base -eq '') { $base = $script:GuardRoot }
    $full = $PathText
    if (-not [System.IO.Path]::IsPathRooted($full)) { $full = Join-Path $base $full }
    $full = [System.IO.Path]::GetFullPath($full)
    $root = [System.IO.Path]::GetFullPath($script:GuardRoot).TrimEnd('\', '/')
    $fl = ($full -replace '\\', '/').ToLowerInvariant()
    $rl = ($root -replace '\\', '/').ToLowerInvariant()
    if ($fl -eq $rl) { return '' }
    if (-not $fl.StartsWith($rl + '/')) { return $null }
    return $fl.Substring($rl.Length + 1)
}

function Test-PsGuardPathAllowed {
    param([string]$Rel, [string[]]$Patterns, [bool]$AllowDirPrefix)
    if ($null -eq $Rel) { return $false }
    foreach ($p in $Patterns) {
        $pl = $p.ToLowerInvariant()
        if ($Rel -like $pl) { return $true }
        if ($AllowDirPrefix -and $Rel -ne '' -and (($Rel + '/x') -like $pl)) { return $true }
    }
    return $false
}

function Get-PsGuardPathPolicy {
    param([string]$Name)
    switch ($Name) {
        'spec-worker' {
            return @{ Read = @('.ps-runtime/spec/*/attempts/*', '.claude/peoplesoft/spec/*'); Write = @('.ps-runtime/spec/*/attempts/*/fragment.md'); Shell = $false }
        }
        'clone-worker' {
            return @{ Read = @('.ps-runtime/clone-spec/*/attempts/*', '.ps-runtime/clone-spec/*/revisions/*', '.ps-runtime/clone-spec/*/receipts/*', '.claude/peoplesoft/*', 'docs/ps-research/*'); Write = @('.ps-runtime/clone-spec/*/attempts/*/packet.json', '.ps-runtime/clone-spec/*/attempts/*/review.json'); Shell = $false }
        }
        'spec-author' {
            return @{ Read = @('docs/ps-spec/*', '.ps-runtime/clone-spec/*/job.json', '.claude/peoplesoft/spec/clone-contract.md'); Write = @(); Shell = $true }
        }
    }
    return $null
}

function Invoke-PsGuardPre {
    param($In)
    $tool = [string](Get-PsGuardProp $In 'tool_name')
    $ti = Get-PsGuardProp $In 'tool_input'
    $agent = [string](Get-PsGuardProp $In 'agent_type')
    $session = [string](Get-PsGuardProp $In 'session_id')
    if ($tool -eq 'mcp__oracleMCP__connect') {
        $oracle = Read-PsGuardProfileOracle
        $profileName = ([string]$oracle['connectionName']).Trim()
        $target = ''
        foreach ($k in @('connection_name', 'connectionName', 'name', 'connection')) {
            $v = Get-PsGuardProp $ti $k
            if ($v -is [string] -and $v.Trim() -ne '') { $target = $v.Trim(); break }
        }
        $prob = Get-PsGuardConnectProblem -ProfileName $profileName -Target $target
        if ($null -eq $prob) { Write-PsGuardLog -Tool $tool -Agent $agent -Decision 'allow' -Code '' -Session $session; return }
        if ((Get-PsGuardConnectMode -Oracle $oracle) -eq 'observe') { Write-PsGuardLog -Tool $tool -Agent $agent -Decision 'observe' -Code $prob.Code -Session $session; return }
        Write-PsGuardLog -Tool $tool -Agent $agent -Decision 'deny' -Code $prob.Code -Session $session
        Write-PsGuardDeny -Reason $prob.Message
        return
    }
    if ($tool -eq 'Agent' -or $tool -eq 'Task') {
        $target = ([string](Get-PsGuardProp $ti 'subagent_type')).Trim()
        # ps-* 主代理（--agent 啟動，hook 輸入帶 agent_type）走嚴格白名單；一般 session 只擋 skill 名與主代理專用名
        $prob = Get-PsGuardTargetProblem -Target $target -Strict ($agent.StartsWith('ps-'))
        if ($null -eq $prob) { Write-PsGuardLog -Tool $tool -Agent $agent -Decision 'allow' -Code $target -Session $session; return }
        Write-PsGuardLog -Tool $tool -Agent $agent -Decision 'deny' -Code ($prob.Code + ':' + $prob.Kind) -Session $session
        Write-PsGuardDeny -Reason $prob.Message
    }
}

function Invoke-PsGuardPost {
    param($In)
    $tool = [string](Get-PsGuardProp $In 'tool_name')
    if ($tool -ne 'Agent' -and $tool -ne 'Task') { return }
    $text = Get-PsGuardAllText -Obj (Get-PsGuardProp $In 'tool_response')
    $notes = @(Get-PsGuardSuggestedNotes -Text $text)
    if ($notes.Count -eq 0) { return }
    Write-PsGuardLog -Tool $tool -Agent ([string](Get-PsGuardProp $In 'agent_type')) -Decision 'note' -Code 'SUGGESTED_NEXT_INVALID' -Session ([string](Get-PsGuardProp $In 'session_id'))
    Write-PsGuardPostNote -Note ("[ps-runtime-guard] 報告的 suggestedNext 含無效委派目標（不轉發、不算 Oracle 掛載或 DB 連線問題）：`n- " + ($notes -join "`n- "))
}

function Invoke-PsGuardPath {
    param($In)
    $tool = [string](Get-PsGuardProp $In 'tool_name')
    $ti = Get-PsGuardProp $In 'tool_input'
    $cwd = [string](Get-PsGuardProp $In 'cwd')
    $agent = [string](Get-PsGuardProp $In 'agent_type')
    $session = [string](Get-PsGuardProp $In 'session_id')
    $policy = Get-PsGuardPathPolicy -Name $PathProfile
    if ($null -eq $policy) { Write-PsGuardDeny -Reason ('PS_PATH_DENIED：未知的路徑設定「' + $PathProfile + '」——agent 檔的 hook 設定錯誤，請管理者修正。'); return }
    $deny = ''
    if (@('Read', 'Grep', 'Glob') -contains $tool) {
        $p = [string](Get-PsGuardProp $ti 'file_path')
        if ($tool -ne 'Read') { $p = [string](Get-PsGuardProp $ti 'path') }
        $rel = Get-PsGuardRelPath -PathText $p -Cwd $cwd
        if (-not (Test-PsGuardPathAllowed -Rel $rel -Patterns $policy.Read -AllowDirPrefix ($tool -ne 'Read'))) {
            $deny = 'PS_PATH_DENIED：本代理只准讀工單範圍（' + ($policy.Read -join '、') + '）；不要讀其他檔、不要掃描別的工作。'
        }
    }
    elseif (@('Write', 'Edit', 'MultiEdit', 'NotebookEdit') -contains $tool) {
        $p = [string](Get-PsGuardProp $ti 'file_path')
        if ($p -eq '') { $p = [string](Get-PsGuardProp $ti 'notebook_path') }
        $rel = Get-PsGuardRelPath -PathText $p -Cwd $cwd
        if ($p -eq '' -or -not (Test-PsGuardPathAllowed -Rel $rel -Patterns $policy.Write -AllowDirPrefix $false)) {
            $w = '（無）'
            if ($policy.Write.Count -gt 0) { $w = ($policy.Write -join '、') }
            $deny = 'PS_PATH_DENIED：本代理只准寫工單指定的那一個產物（' + $w + '）；其他檔一律不寫。'
        }
    }
    elseif (@('Bash', 'PowerShell') -contains $tool) {
        $cmd = ([string](Get-PsGuardProp $ti 'command')).Trim()
        $ok = $false
        # 參數只准三種詞：-開關、單引號包住的 Component 清單（英數 _ . $ # - , 空白）、數字——沒有串接、重導向、未加引號的變數
        if ($policy.Shell -and $cmd -match "^powershell(\.exe)? -NoProfile -File scripts[\\/]ps-spec-build\.ps1((\s+-[A-Za-z]+)|(\s+'[A-Za-z0-9_.`$#, -]+')|(\s+[0-9]+))*\s*$") { $ok = $true }
        if (-not $ok) { $deny = 'PS_PATH_DENIED：本代理只准執行「powershell -NoProfile -File scripts/ps-spec-build.ps1 <參數>」這一種命令，不得串接其他命令、重導向或變數。' }
    }
    if ($deny -ne '') {
        Write-PsGuardLog -Tool $tool -Agent $agent -Decision 'deny' -Code 'PS_PATH_DENIED' -Session $session
        Write-PsGuardDeny -Reason $deny
    }
}

try {
    $in = Read-PsGuardInput
    if ($null -eq $in) { exit 0 }
    if ($Mode -eq 'post') { Invoke-PsGuardPost -In $in }
    elseif ($Mode -eq 'path') { Invoke-PsGuardPath -In $in }
    else { Invoke-PsGuardPre -In $in }
    exit 0
}
catch {
    if ($Mode -eq 'path') {
        Write-PsGuardDeny -Reason ('PS_PATH_DENIED：路徑 guard 執行失敗（' + $_.Exception.Message + '），為安全起見不放行；請管理者檢查 .claude/hooks/ps-runtime-guard.ps1。')
        exit 0
    }
    Write-PsGuardLog -Tool '' -Agent '' -Decision 'error' -Code ([string]$_.Exception.Message) -Session ''
    exit 0
}
