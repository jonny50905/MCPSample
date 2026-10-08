# scripts/tests/test-claude-variant.ps1 — Claude Code 版（repo 的 claude-code/ 子樹）一致性、hook 與外環版本層測試（維護端專用）
# 用法：pwsh -NoProfile -File scripts/tests/test-claude-variant.ps1                      ← 驗證（exit 1＝有 FAIL）
#       pwsh -NoProfile -File scripts/tests/test-claude-variant.ps1 -WriteGenericManifest ← 重生 claude-code/.claude/peoplesoft/spec/generic.manifest.json
#       （generic 集合含 scripts/ps-spec*.ps1：改了 Spec 引擎或 Claude Code 版的 spec／worker 檔都要重生；之後再跑 ps-fs-doctor -WriteManifest）
# 範圍：合成「公司機部署」臨時目錄（scripts＋claude-code/* 去前綴，結束自刪）：
#   A 兩版對照（agent／command／skill／契約一一對應、資料檔逐字相同、profile 鍵值相同）、不得殘留另一版字樣、frontmatter 形狀、
#     settings.json、路徑與 MCP 工具名可解析；
#   B hook（connect 目標、Agent 委派目標、suggestedNext 註記、worker 路徑白名單、Bash 命令形狀）；
#   C 外環版本層（版本判定、Claude Code 命令列、stream-json 抽最終回覆、搬運 manifest 與 generic manifest 是最新、知識索引用法行、能力目錄路徑）。
param([switch]$WriteGenericManifest)
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ErrorActionPreference = 'Stop'
$cc = Join-Path $repoRoot 'claude-code'
$oc = Join-Path $repoRoot '.opencode'
$pwshExe = (Get-Process -Id $PID).Path

$failCount = 0
function Assert([bool]$Cond, [string]$Name) {
    if ($Cond) { Write-Host "  PASS：$Name" }
    else { Write-Host "  FAIL：$Name" -ForegroundColor Red; $script:failCount++ }
}
function Read-Norm([string]$Path) {
    $t = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if ($t.Length -gt 0 -and [int]$t[0] -eq 0xFEFF) { $t = $t.Substring(1) }
    return (($t -replace "`r", '') -replace '\s+$', '')
}
function Get-RelUnder([string]$Base, [string]$Full) {
    return (($Full.Substring($Base.Length).TrimStart('\', '/')) -replace '\\', '/')
}
function Get-NameSet([string]$Dir, [string]$Filter, [switch]$Dirs) {
    $h = @{}
    if (-not (Test-Path -LiteralPath $Dir)) { return $h }
    if ($Dirs) { foreach ($d in @(Get-ChildItem -LiteralPath $Dir -Directory)) { $h[$d.Name] = $true } }
    else { foreach ($f in @(Get-ChildItem -LiteralPath $Dir -File -Filter $Filter)) { $h[$f.BaseName] = $true } }
    return $h
}
function Get-Frontmatter([string]$Path) {
    $lines = @((Read-Norm $Path) -split "`n")
    $fm = @()
    if ($lines.Count -gt 0 -and $lines[0] -eq '---') {
        for ($i = 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -eq '---') { break }; $fm += $lines[$i] }
    }
    return ($fm -join "`n")
}

# ── 部署模擬：<tmp>/scripts＝repo scripts；<tmp>/{.claude,CLAUDE.md}＝claude-code/ 去前綴（README.md 不部署）
function New-DeployRoot {
    $d = Join-Path ([System.IO.Path]::GetTempPath()) ('claude-deploy-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts') -Destination (Join-Path $d 'scripts') -Recurse
    Copy-Item -LiteralPath (Join-Path $cc '.claude') -Destination (Join-Path $d '.claude') -Recurse
    Copy-Item -LiteralPath (Join-Path $cc 'CLAUDE.md') -Destination (Join-Path $d 'CLAUDE.md')
    New-Item -ItemType Directory -Path (Join-Path $d (Join-Path 'docs' (Join-Path 'ps-research' 'wiki'))) -Force | Out-Null
    return $d
}

if ($WriteGenericManifest) {
    $dep = New-DeployRoot
    try {
        $o = ((& (Join-Path $dep 'scripts/ps-spec.ps1') -Doctor -WriteGenericManifest -Root $dep *>&1 | ForEach-Object { [string]$_ }) -join "`n")
        $src = Join-Path $dep '.claude/peoplesoft/spec/generic.manifest.json'
        if (-not (Test-Path -LiteralPath $src)) { Write-Host $o; Write-Host '重生失敗：部署模擬目錄沒有產生 generic.manifest.json' -ForegroundColor Red; exit 1 }
        Copy-Item -LiteralPath $src -Destination (Join-Path $cc '.claude/peoplesoft/spec/generic.manifest.json') -Force
        Write-Host '已重生 claude-code/.claude/peoplesoft/spec/generic.manifest.json（接著跑 ps-fs-doctor -WriteManifest）' -ForegroundColor Green
        exit 0
    }
    finally { Remove-Item -LiteralPath $dep -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "A：兩版對照與檔案衛生"
# claude-code/README.md 是給人看的對照說明（不部署），其餘部署檔不得出現另一版字樣
$ccAll = @(Get-ChildItem -LiteralPath $cc -File -Recurse -Force | Where-Object { (Get-RelUnder $cc $_.FullName) -ne 'README.md' })
$leak = @($ccAll | Where-Object { (Read-Norm $_.FullName) -match '(?i)opencode' } | ForEach-Object { Get-RelUnder $cc $_.FullName })
Assert ($leak.Count -eq 0) ("claude-code/ 的部署檔不含另一版字樣（opencode）" + $(if ($leak.Count -gt 0) { '：' + ($leak -join ', ') } else { '' }))

$excludedAgents = @('explore', 'general', 'scout', 'ps-audit-orchestrator')
# Spec 文件流程（scripts/ps-sdoc.ps1）只有 Claude Code 版：它的 worker／讀者 agent 沒有 OpenCode 對應檔
$claudeOnlyAgents = @('ps-status-reader', 'ps-sdoc-worker')
$ocAgents = Get-NameSet (Join-Path $oc 'agent') '*.md'
$ccAgents = Get-NameSet (Join-Path $cc '.claude/agents') '*.md'
$missA = @($ocAgents.Keys | Where-Object { $excludedAgents -notcontains $_ -and -not $ccAgents.ContainsKey($_) })
$extraA = @($ccAgents.Keys | Where-Object { -not $ocAgents.ContainsKey($_) -and $claudeOnlyAgents -notcontains $_ })
Assert ($missA.Count -eq 0 -and $extraA.Count -eq 0) ("agent 一一對應（OpenCode 內建覆寫 explore／general／scout、備用 ps-audit-orchestrator、Claude Code 獨有的 Spec 文件 agent 除外）" + $(if ($missA.Count + $extraA.Count -gt 0) { '：缺 ' + ($missA -join ',') + '／多 ' + ($extraA -join ',') } else { '' }))
$coBad = @($claudeOnlyAgents | Where-Object { -not $ccAgents.ContainsKey($_) -or $ocAgents.ContainsKey($_) })
Assert ($coBad.Count -eq 0) ("Claude Code 獨有的 Spec 文件 agent 存在、且 OpenCode 版沒有同名檔" + $(if ($coBad.Count -gt 0) { '：' + ($coBad -join ',') } else { '' }))
$ocCmds = Get-NameSet (Join-Path $oc 'command') '*.md'
$ccCmds = Get-NameSet (Join-Path $cc '.claude/commands') '*.md'
$d1 = @($ocCmds.Keys | Where-Object { -not $ccCmds.ContainsKey($_) }) + @($ccCmds.Keys | Where-Object { -not $ocCmds.ContainsKey($_) })
Assert ($d1.Count -eq 0) ("指令一一對應" + $(if ($d1.Count -gt 0) { '：' + ($d1 -join ',') } else { '' }))
$ocSk = Get-NameSet (Join-Path $oc 'skills') '' -Dirs
$ccSk = Get-NameSet (Join-Path $cc '.claude/skills') '' -Dirs
$d2 = @($ocSk.Keys | Where-Object { -not $ccSk.ContainsKey($_) }) + @($ccSk.Keys | Where-Object { -not $ocSk.ContainsKey($_) })
Assert ($d2.Count -eq 0) ("skill 一一對應" + $(if ($d2.Count -gt 0) { '：' + ($d2 -join ',') } else { '' }))
$contractMiss = @()
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $oc 'peoplesoft') -File -Filter '*.md')) {
    if (@('SOP.md', 'README.md', 'test-scenarios.md') -contains $f.Name) { continue }
    if (-not (Test-Path -LiteralPath (Join-Path $cc ('.claude/peoplesoft/' + $f.Name)))) { $contractMiss += $f.Name }
}
foreach ($sub in @('report-templates', 'spec')) {
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $oc ('peoplesoft/' + $sub)) -File -Recurse)) {
        $rel = Get-RelUnder (Join-Path $oc 'peoplesoft') $f.FullName
        if (-not (Test-Path -LiteralPath (Join-Path $cc ('.claude/peoplesoft/' + $rel)))) { $contractMiss += $rel }
    }
}
Assert ($contractMiss.Count -eq 0) ("契約／模板／spec 檔一一對應（SOP.md、README.md、test-scenarios.md 為人讀文件，不部署）" + $(if ($contractMiss.Count -gt 0) { '：缺 ' + ($contractMiss -join ',') } else { '' }))

$dataDiff = @()
$dataFiles = @('business-domain-map.yaml', 'research-domains.txt')
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $oc 'peoplesoft/spec') -File -Recurse)) {
    if ($f.Extension -eq '.md' -or $f.Name -eq 'generic.manifest.json') { continue }
    $dataFiles += ('spec/' + (Get-RelUnder (Join-Path $oc 'peoplesoft/spec') $f.FullName))
}
foreach ($rel in $dataFiles) {
    $a = Join-Path $oc ('peoplesoft/' + $rel)
    $b = Join-Path $cc ('.claude/peoplesoft/' + $rel)
    if (-not (Test-Path -LiteralPath $b) -or (Read-Norm $a) -cne (Read-Norm $b)) { $dataDiff += $rel }
}
Assert ($dataDiff.Count -eq 0) ("資料檔兩版逐字相同（domain map、研究佇列、spec 的 JSON 與範例 pack）" + $(if ($dataDiff.Count -gt 0) { '：' + ($dataDiff -join ',') } else { '' }))
function Get-YamlKeyLines([string]$Path) {
    $out = @()
    foreach ($ln in @((Read-Norm $Path) -split "`n")) {
        $t = ($ln -replace '\s+#.*$', '') -replace '\s+$', ''
        if ($t.Trim() -eq '' -or $t.TrimStart().StartsWith('#')) { continue }
        $out += $t
    }
    return ($out -join "`n")
}
Assert ((Get-YamlKeyLines (Join-Path $oc 'peoplesoft/customization-profile.yaml')) -ceq (Get-YamlKeyLines (Join-Path $cc '.claude/peoplesoft/customization-profile.yaml'))) "customization-profile.yaml 去註解後鍵值逐行相同（公司機可把已回填的值原樣抄過去）"

$subagents = @('ps-ui-flow', 'ps-peoplecode-flow', 'ps-sql-flow', 'ps-sqr-flow', 'ps-ae-flow', 'ps-metadata-flow', 'ps-auditor')
$dbMain = @('ps-orchestrator', 'ps-deep-research', 'ps-clone-worker', 'ps-sdoc-worker')
$pathProfiles = @{ 'ps-spec-worker' = 'spec-worker'; 'ps-clone-worker' = 'clone-worker'; 'ps-spec-author' = 'spec-author'; 'ps-status-reader' = 'status-reader'; 'ps-sdoc-worker' = 'sdoc-worker' }
$fmBad = @()
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $cc '.claude/agents') -File -Filter '*.md')) {
    $fm = Get-Frontmatter $f.FullName
    $n = $f.BaseName
    $tools = ''
    if ($fm -match '(?m)^tools:\s*(.+)$') { $tools = $Matches[1] }
    $toolList = @($tools -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    if ($fm -notmatch ('(?m)^name:\s*' + [regex]::Escape($n) + '\s*$')) { $fmBad += ($n + ':name') }
    if ($fm -notmatch '(?m)^description:\s*\S') { $fmBad += ($n + ':description') }
    if ($fm -notmatch '(?m)^model:\s*inherit\s*$') { $fmBad += ($n + ':model') }
    if ($toolList.Count -eq 0) { $fmBad += ($n + ':tools') }
    if ($subagents -contains $n) {
        if ($toolList -contains 'Agent' -or $toolList -contains 'Task') { $fmBad += ($n + ':子代理不得再委派') }
        if (@($toolList | Where-Object { $_ -match '^mcp__oracleMCP__(connect|list_connections|disconnect|sqlcl_run)$' }).Count -gt 0) { $fmBad += ($n + ':子代理不開連線工具') }
    }
    if ($dbMain -contains $n -and $toolList -notcontains 'mcp__oracleMCP__connect') { $fmBad += ($n + ':主代理要能 connect') }
    if (@($toolList | Where-Object { $_ -match '^mcp__oracleMCP__(disconnect|sqlcl_run)$' }).Count -gt 0) { $fmBad += ($n + ':disconnect／sqlcl_run 不開') }
    if ($pathProfiles.ContainsKey($n)) {
        if ($fm -notmatch ('-Mode path -PathProfile ' + $pathProfiles[$n] + '"')) { $fmBad += ($n + ':路徑 hook') }
    }
    elseif ($fm -match '(?m)^hooks:') { $fmBad += ($n + ':非 worker 不掛路徑 hook') }
}
Assert ($fmBad.Count -eq 0) ("agent frontmatter 形狀（name＝檔名、model inherit、tools 白名單、子代理不委派不連線、worker 掛路徑 hook）" + $(if ($fmBad.Count -gt 0) { '：' + ($fmBad -join '，') } else { '' }))

. (Join-Path $repoRoot 'scripts/ps-cli-lib.ps1')
$cmdBad = @()
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $cc '.claude/commands') -File -Filter '*.md')) {
    $t = Read-Norm $f.FullName
    $fm = Get-Frontmatter $f.FullName
    if ($fm -notmatch '(?m)^disable-model-invocation:\s*true\s*$') { $cmdBad += ($f.BaseName + ':disable-model-invocation') }
    if ($fm -notmatch '(?m)^description:\s*\S') { $cmdBad += ($f.BaseName + ':description') }
    if ($fm -match '(?m)^(agent|subtask):') { $cmdBad += ($f.BaseName + ':不得有 agent／subtask 鍵') }
    $ag = Get-PsCliCommandAgent -Command $f.BaseName
    if ($ag -eq '') { $cmdBad += ($f.BaseName + ':ps-cli-lib 沒有主代理對照') }
    elseif ($t -notmatch ('claude --agent ' + [regex]::Escape($ag))) { $cmdBad += ($f.BaseName + ':前提段沒寫 claude --agent ' + $ag) }
    if ($t -notmatch '\$ARGUMENTS') { $cmdBad += ($f.BaseName + ':$ARGUMENTS') }
}
Assert ($cmdBad.Count -eq 0) ("指令形狀（禁止模型自行觸發、前提段的主代理＝外環對照表、帶 `$ARGUMENTS）" + $(if ($cmdBad.Count -gt 0) { '：' + ($cmdBad -join '，') } else { '' }))

$settings = $null
try { $settings = [System.IO.File]::ReadAllText((Join-Path $cc '.claude/settings.json')) | ConvertFrom-Json } catch { }
Assert ($null -ne $settings) "settings.json 可解析"
if ($null -ne $settings) {
    $allow = @($settings.permissions.allow)
    $deny = @($settings.permissions.deny)
    $preCmd = [string]$settings.hooks.PreToolUse[0].hooks[0].command
    $postCmd = [string]$settings.hooks.PostToolUse[0].hooks[0].command
    Assert ([string]$settings.model -eq 'sonnet' -and $null -eq $settings.PSObject.Properties['agent']) "settings：模型 sonnet、不設預設主代理（直接 claude＝一般 session，可做維護排錯）"
    Assert ($allow -contains 'mcp__oracleMCP__connect' -and $allow -contains 'mcp__oracleMCP__sql_run' -and $allow -contains 'Edit(./docs/ps-research/**)' -and $deny -contains 'mcp__oracleMCP__sqlcl_run' -and $allow -notcontains 'mcp__oracleMCP__disconnect') "settings：headless 需要的工具在允許清單、sqlcl_run 拒絕、disconnect 不預先允許"
    Assert ($preCmd -match '\.claude/hooks/ps-runtime-guard\.ps1 -Mode pre$' -and [string]$settings.hooks.PreToolUse[0].matcher -match 'mcp__oracleMCP__connect' -and [string]$settings.hooks.PreToolUse[0].matcher -match 'Agent') "settings：PreToolUse hook 掛 connect 與 Agent"
    Assert ($postCmd -match '-Mode post$') "settings：PostToolUse hook 掛 Agent 回傳"
    Assert ([string]$settings.env.BASH_MAX_TIMEOUT_MS -eq '7200000') "settings：Bash 上限 2 小時（ps-spec-author 的 ps-sdoc 長跑）"
    Assert ($allow -contains 'Bash(powershell -NoProfile -File scripts/ps-sdoc.ps1 *)' -and $allow -contains 'PowerShell(powershell -NoProfile -File scripts/ps-sdoc.ps1 *)' -and $allow -contains 'Edit(./.ps-runtime/sdoc/**)') "settings：ps-spec-author 可跑 ps-sdoc、headless worker 可寫 .ps-runtime/sdoc"
}
$hookPath = Join-Path $cc '.claude/hooks/ps-runtime-guard.ps1'
$hb = [System.IO.File]::ReadAllBytes($hookPath)
Assert ($hb.Length -ge 3 -and $hb[0] -eq 0xEF -and $hb[1] -eq 0xBB -and $hb[2] -eq 0xBF) "hook 腳本 UTF-8 with BOM"

$modelFiles = @(Get-ChildItem -LiteralPath (Join-Path $cc '.claude') -File -Recurse -Include '*.md') + @(Get-Item -LiteralPath (Join-Path $cc 'CLAUDE.md'))
$badRef = @()
$knownTools = @('mcp__oracleMCP__list_connections', 'mcp__oracleMCP__connect', 'mcp__oracleMCP__disconnect', 'mcp__oracleMCP__sql_run', 'mcp__oracleMCP__sqlcl_run',
    'mcp__PeoplecodeElasticSearch__search_chunks', 'mcp__PeoplecodeSource__get_chunks_details', 'mcp__PeoplecodeSource__get_file_structure',
    'mcp__PeoplecodeMetadata__find_field_usage', 'mcp__PeoplecodeMetadata__search_component_metadata', 'mcp__PeoplecodeMetadata__get_ae_sql_metadata')
$badTool = @()
foreach ($f in $modelFiles) {
    $t = Read-Norm $f.FullName
    foreach ($m in [regex]::Matches($t, '(?<![A-Za-z0-9_/-])\.claude/[A-Za-z0-9_./-]*[A-Za-z0-9_]')) {
        $p = $m.Value
        if ($p -match '\*|<') { continue }
        if ($p -eq '.claude/agents/ps-security-flow.md') { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $cc $p))) { $badRef += ((Get-RelUnder $cc $f.FullName) + '→' + $p) }
    }
    foreach ($m in [regex]::Matches($t, 'mcp__[A-Za-z]+__[A-Za-z_]+')) {
        if ($knownTools -notcontains $m.Value) { $badTool += ((Get-RelUnder $cc $f.FullName) + '→' + $m.Value) }
    }
}
# oracleMCP 工具實名是底線拼法 sql_run／sqlcl_run／list_connections（舊錯名與連字號拼法不得回流，同 test-auto-loop 情境 31）
$wrongPat = ('run_' + 'sql') + '|' + ('list' + '-connections') + '|' + ('run' + '-sql') + '|' + ('sql' + '-run') + '|' + ('sqlcl' + '-run')
$wrongName = @($ccAll | Where-Object { (Read-Norm $_.FullName) -match $wrongPat } | ForEach-Object { Get-RelUnder $cc $_.FullName })
Assert ($wrongName.Count -eq 0) ("oracleMCP 工具名一律底線實名（無舊錯名、無連字號拼法）" + $(if ($wrongName.Count -gt 0) { '：' + ($wrongName -join ', ') } else { '' }))
$badRef = @($badRef | Sort-Object -Unique)
$badTool = @($badTool | Sort-Object -Unique)
Assert (-not (Test-Path -LiteralPath (Join-Path $cc '.claude/agents/ps-security-flow.md'))) "不新增 .claude/agents/ps-security-flow.md（skill 不以同名 agent 接受誤派；SKILL.md 明寫它不存在）"
Assert ($badRef.Count -eq 0) ("模型檔引用的 .claude/ 路徑都存在" + $(if ($badRef.Count -gt 0) { '：' + ($badRef -join '，') } else { '' }))
Assert ($badTool.Count -eq 0) ("模型檔的 MCP 工具全名都在已知清單（mcp__<註冊名>__<工具>）" + $(if ($badTool.Count -gt 0) { '：' + ($badTool -join '，') } else { '' }))
$lint = ((& (Join-Path $repoRoot 'scripts/ps-agent-doc-lint.ps1') -Root $repoRoot *>&1 | ForEach-Object { [string]$_ }) -join "`n")
Assert ($LASTEXITCODE -eq 0 -and $lint -notmatch 'claude-code/.*\[(issue 編號|日期|變更敘述|Case 編號)\]') "agent-doc-lint 涵蓋 claude-code 樹且無阻擋項"

$dep = New-DeployRoot
try {
    Write-Host "B：hook（部署模擬目錄）"
    $hook = Join-Path $dep '.claude/hooks/ps-runtime-guard.ps1'
    function Invoke-Hook([string]$Json, [string[]]$HookArgs = @()) {
        $o = ($Json | & $pwshExe -NoProfile -File $hook @HookArgs 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
        $script:hookExit = $LASTEXITCODE
        $script:hookObj = $null
        if ($o.Trim() -ne '') { try { $script:hookObj = $o | ConvertFrom-Json } catch { } }
        return $o
    }
    function Get-Deny { if ($null -eq $script:hookObj) { return '' }; return [string]$script:hookObj.hookSpecificOutput.permissionDecisionReason }
    $connect = '{"tool_name":"mcp__oracleMCP__connect","tool_input":{"connection_name":"HR_UAT"},"agent_type":"ps-orchestrator","session_id":"t"}'
    $null = Invoke-Hook $connect
    Assert ((Get-Deny) -like 'ORACLE_CONNECTION_NOT_CONFIGURED*' -and $script:hookExit -eq 0) "connect：profile FILL_ME → ORACLE_CONNECTION_NOT_CONFIGURED（deny JSON、exit 0）"
    $pf = Join-Path $dep '.claude/peoplesoft/customization-profile.yaml'
    [System.IO.File]::WriteAllText($pf, ([System.IO.File]::ReadAllText($pf) -replace '(?m)^  connectionName: FILL_ME', '  connectionName: HR_DEV'), (New-Object System.Text.UTF8Encoding($false)))
    $null = Invoke-Hook $connect
    Assert ((Get-Deny) -like 'ORACLE_CONNECTION_MISMATCH*HR_DEV*') "connect：目標≠profile → ORACLE_CONNECTION_MISMATCH（訊息帶 profile 值）"
    $o = Invoke-Hook ($connect -replace 'HR_UAT', 'HR_DEV')
    Assert ($o.Trim() -eq '' -and $script:hookExit -eq 0) "connect：目標＝profile → 放行（無輸出）"
    $null = Invoke-Hook '{"tool_name":"mcp__oracleMCP__connect","tool_input":{},"session_id":"t"}'
    Assert ((Get-Deny) -like 'ORACLE_CONNECTION_MISMATCH*') "connect：沒帶 connection_name → MISMATCH"
    $env:PS_ORACLE_CONNECT_GUARD = 'observe'
    $o = Invoke-Hook $connect
    Remove-Item -Path Env:\PS_ORACLE_CONNECT_GUARD -ErrorAction SilentlyContinue
    Assert ($o.Trim() -eq '') "connect：PS_ORACLE_CONNECT_GUARD=observe → 只記錄不擋"
    $null = Invoke-Hook '{"tool_name":"Agent","tool_input":{"subagent_type":"ps-security-flow","prompt":"x"}}'
    Assert ((Get-Deny) -like 'PS_TASK_TARGET_INVALID*ps-metadata-flow*') "Agent：skill 名 ps-security-flow → PS_TASK_TARGET_INVALID 並指出承載 ps-metadata-flow（一般 session 也擋）"
    $o = Invoke-Hook '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","prompt":"x"}}'
    $o2 = Invoke-Hook '{"tool_name":"Agent","tool_input":{"prompt":"x"}}'
    Assert ($o.Trim() -eq '' -and $o2.Trim() -eq '') "Agent：一般 session（沒有 agent_type）可用內建 Explore／general-purpose 做維護排錯"
    $null = Invoke-Hook '{"tool_name":"Agent","tool_input":{"subagent_type":"ps-deep-research","prompt":"x"}}'
    Assert ((Get-Deny) -like 'PS_TASK_TARGET_INVALID*主代理*') "Agent：一般 session 委派主代理專用名 → 照樣擋"
    $null = Invoke-Hook '{"tool_name":"Agent","tool_input":{"subagent_type":"ps-business-explain","prompt":"x"}}'
    Assert ((Get-Deny) -like 'PS_TASK_TARGET_INVALID*自己 Read*') "Agent：主代理自讀的 skill → 擋、說明不委派"
    $null = Invoke-Hook '{"tool_name":"Agent","tool_input":{"subagent_type":"ps-deep-research","prompt":"x"},"agent_type":"ps-orchestrator"}'
    Assert ((Get-Deny) -like 'PS_TASK_TARGET_INVALID*主代理*') "Agent：主代理專用名 → 擋"
    $null = Invoke-Hook '{"tool_name":"Task","tool_input":{"subagent_type":"general-purpose","prompt":"x"},"agent_type":"ps-orchestrator"}'
    Assert ((Get-Deny) -like 'PS_TASK_TARGET_INVALID*ps-ui-flow*') "Agent（舊名 Task）：ps-* 主代理委派內建 general-purpose → 擋、列出可委派清單"
    $null = Invoke-Hook '{"tool_name":"Agent","tool_input":{"prompt":"x"},"agent_type":"ps-deep-research"}'
    Assert ((Get-Deny) -like 'PS_TASK_TARGET_INVALID*subagent_type*') "Agent：ps-* 主代理沒帶 subagent_type → 擋"
    $o1 = Invoke-Hook '{"tool_name":"Agent","tool_input":{"subagent_type":"ps-ui-flow","prompt":"x"}}'
    $o2 = Invoke-Hook '{"tool_name":"Agent","tool_input":{"subagent_type":"ps-spec-author","prompt":"x"}}'
    Assert ($o1.Trim() -eq '' -and $o2.Trim() -eq '') "Agent：ps-ui-flow／ps-spec-author → 放行"
    $null = Invoke-Hook '{"tool_name":"Agent","tool_input":{"subagent_type":"ps-sdoc-worker","prompt":"x"}}'
    $d1 = Get-Deny
    $null = Invoke-Hook '{"tool_name":"Agent","tool_input":{"subagent_type":"ps-status-reader","prompt":"x"},"agent_type":"ps-orchestrator"}'
    Assert ($d1 -like 'PS_TASK_TARGET_INVALID*主代理*' -and (Get-Deny) -like 'PS_TASK_TARGET_INVALID*主代理*') "Agent：Spec 文件的 worker／讀者只由外環 headless 啟動，不能委派"
    $null = Invoke-Hook '{"tool_name":"Agent","tool_response":{"content":[{"type":"text","text":"{\"status\":\"COMPLETE\",\"suggestedNext\":[{\"agent\":\"ps-data-lineage\",\"task\":\"x\"},{\"agent\":\"ps-sqr-flow\"},{\"agent\":\"nobody\"}]}"}]}}' @('-Mode', 'post')
    $note = ''
    if ($null -ne $script:hookObj) { $note = [string]$script:hookObj.hookSpecificOutput.additionalContext }
    Assert ($note -like '`[ps-runtime-guard`]*ps-data-lineage*ps-metadata-flow*nobody*' -and $note -notmatch 'ps-sqr-flow') "post：suggestedNext 的 skill 名與未知名附註記、合法目標不提"
    $o = Invoke-Hook '{"tool_name":"Agent","tool_response":"{\"status\":\"COMPLETE\",\"suggestedNext\":[{\"agent\":\"ps-ui-flow\"}]}"}' @('-Mode', 'post')
    Assert ($o.Trim() -eq '') "post：全部合法 → 無輸出"
    function Test-PathHook([string]$PathProfileName, [string]$Tool, [string]$Key, [string]$Value) {
        $v = $Value -replace '\\', '\\\\'
        $j = '{"tool_name":"' + $Tool + '","tool_input":{"' + $Key + '":"' + $v + '"},"cwd":"' + ($dep -replace '\\', '\\\\') + '"}'
        $o = Invoke-Hook $j @('-Mode', 'path', '-PathProfile', $PathProfileName)
        return ($o.Trim() -eq '')
    }
    $att = Join-Path $dep '.ps-runtime/spec/job-1/attempts/a0001'
    Assert (Test-PathHook 'spec-worker' 'Read' 'file_path' (Join-Path $att 'manifest.md')) "path spec-worker：讀工單 → 放行"
    Assert (Test-PathHook 'spec-worker' 'Read' 'file_path' '.claude/peoplesoft/spec/clone-contract.md') "path spec-worker：讀 spec 契約（相對路徑）→ 放行"
    Assert (-not (Test-PathHook 'spec-worker' 'Read' 'file_path' (Join-Path $dep 'docs/ps-research/wiki/X.md'))) "path spec-worker：讀 wiki → 擋"
    Assert (Test-PathHook 'spec-worker' 'Write' 'file_path' (Join-Path $att 'fragment.md')) "path spec-worker：寫 fragment.md → 放行"
    Assert (-not (Test-PathHook 'spec-worker' 'Write' 'file_path' (Join-Path $att 'manifest.md'))) "path spec-worker：寫工單 → 擋"
    Assert (-not (Test-PathHook 'spec-worker' 'Read' 'file_path' ($att + '/../../../../../CLAUDE.md'))) "path spec-worker：.. 跳出工單範圍 → 擋"
    Assert (-not (Test-PathHook 'spec-worker' 'Bash' 'command' 'dir')) "path spec-worker：Bash → 擋"
    Assert (Test-PathHook 'clone-worker' 'Grep' 'path' 'docs/ps-research') "path clone-worker：Grep 研究目錄 → 放行"
    Assert (Test-PathHook 'clone-worker' 'Write' 'file_path' (Join-Path $dep '.ps-runtime/clone-spec/clone-0123456789abcdef/attempts/a1/packet.json')) "path clone-worker：寫 packet.json → 放行"
    Assert (-not (Test-PathHook 'clone-worker' 'Write' 'file_path' (Join-Path $dep 'docs/ps-research/x/01-A.md'))) "path clone-worker：寫 NN → 擋"
    Assert (Test-PathHook 'spec-author' 'Bash' 'command' "powershell -NoProfile -File scripts/ps-sdoc.ps1 -Components 'TW_A,TW_B' -MaxSessions 4") "path spec-author：ps-sdoc 命令 → 放行"
    Assert (-not (Test-PathHook 'spec-author' 'Bash' 'command' "powershell -NoProfile -File scripts/ps-sdoc.ps1 -Components 'TW_A'; del x")) "path spec-author：串接命令 → 擋"
    Assert (Test-PathHook 'spec-author' 'Bash' 'command' "powershell -NoProfile -File scripts/ps-sdoc.ps1 -Components 'TW_A`$X,TW#B' -Status") "path spec-author：Component 名含 `$／#（單引號內）→ 放行"
    Assert (-not (Test-PathHook 'spec-author' 'Bash' 'command' "powershell -NoProfile -File scripts/ps-sdoc.ps1 -Components `$(whoami)")) "path spec-author：未加引號的變數／子命令 → 擋"
    Assert (-not (Test-PathHook 'spec-author' 'Bash' 'command' "powershell -NoProfile -File scripts/ps-sdoc.ps1 -Components 'TW_A' > out.txt")) "path spec-author：重導向 → 擋"
    Assert (-not (Test-PathHook 'spec-author' 'Bash' 'command' "powershell -NoProfile -File scripts/ps-spec-build.ps1 -Components 'TW_A'")) "path spec-author：舊的 ps-spec-build 命令 → 擋（Claude Code 版的 /ps-spec 只走 ps-sdoc）"
    Assert (-not (Test-PathHook 'spec-author' 'PowerShell' 'command' 'Remove-Item x')) "path spec-author：其他命令 → 擋"
    Assert (-not (Test-PathHook 'spec-author' 'Write' 'file_path' (Join-Path $dep 'docs/ps-spec/x.md'))) "path spec-author：任何寫檔 → 擋"
    Assert (-not (Test-PathHook 'spec-author' 'Write' 'file_path' (Join-Path $dep '.ps-private/sdoc/clone-0123456789abcdef/approvals.md'))) "path spec-author：不代寫人工輸入檔（核准、裁決）→ 擋"
    Assert (Test-PathHook 'spec-author' 'Read' 'file_path' (Join-Path $dep 'docs/ps-spec/TW_A/spec.md')) "path spec-author：讀 Spec 產物 → 放行"
    Assert (Test-PathHook 'spec-author' 'Read' 'file_path' (Join-Path $dep '.ps-private/sdoc/clone-0123456789abcdef/decisions.md')) "path spec-author：讀人工輸入檔（說明怎麼填）→ 放行"
    $sj = Join-Path $dep '.ps-runtime/sdoc/clone-0123456789abcdef'
    Assert (Test-PathHook 'status-reader' 'Read' 'file_path' (Join-Path $sj 'inbox/manifest.md')) "path status-reader：讀 inbox 工單 → 放行"
    Assert (Test-PathHook 'status-reader' 'Read' 'file_path' (Join-Path $dep '.ps-private/sdoc/clone-0123456789abcdef/status.md')) "path status-reader：讀 STATUS 檔 → 放行"
    Assert (Test-PathHook 'status-reader' 'Read' 'file_path' '.claude/peoplesoft/sdoc/status-reading-contract.md') "path status-reader：讀解讀契約 → 放行"
    Assert (-not (Test-PathHook 'status-reader' 'Read' 'file_path' (Join-Path $sj 'attempts/a0001/output.json'))) "path status-reader：讀其他讀者的解讀 → 擋（三位讀者互相隔離）"
    Assert (-not (Test-PathHook 'status-reader' 'Read' 'file_path' (Join-Path $dep 'docs/ps-research/wiki/X.md'))) "path status-reader：讀研究知識 → 擋（只看 STATUS 檔）"
    Assert (Test-PathHook 'status-reader' 'Write' 'file_path' (Join-Path $sj 'inbox/output.json')) "path status-reader：寫 inbox/output.json → 放行"
    Assert (-not (Test-PathHook 'status-reader' 'Write' 'file_path' (Join-Path $sj 'attempts/a0001/output.json'))) "path status-reader：寫 attempt 目錄 → 擋"
    Assert (Test-PathHook 'sdoc-worker' 'Read' 'file_path' (Join-Path $sj 'attempts/a0004/manifest.md')) "path sdoc-worker：讀工單 → 放行"
    Assert (Test-PathHook 'sdoc-worker' 'Read' 'file_path' (Join-Path $sj 'work/r0001/citeable.md')) "path sdoc-worker：讀可引用清單 → 放行"
    Assert (Test-PathHook 'sdoc-worker' 'Grep' 'path' 'docs/ps-research') "path sdoc-worker：Grep 研究目錄 → 放行"
    Assert (Test-PathHook 'sdoc-worker' 'Read' 'file_path' '.claude/peoplesoft/sdoc/examples/data.json') "path sdoc-worker：讀研究包範例 → 放行"
    Assert (-not (Test-PathHook 'sdoc-worker' 'Read' 'file_path' (Join-Path $dep '.ps-private/sdoc/clone-0123456789abcdef/decisions.md'))) "path sdoc-worker：讀人工裁決檔 → 擋"
    Assert (Test-PathHook 'sdoc-worker' 'Write' 'file_path' (Join-Path $sj 'attempts/a0004/output.json')) "path sdoc-worker：寫 output.json → 放行"
    Assert (-not (Test-PathHook 'sdoc-worker' 'Write' 'file_path' (Join-Path $sj 'receipts/r0001/x.json'))) "path sdoc-worker：寫收據 → 擋"
    Assert (-not (Test-PathHook 'sdoc-worker' 'Write' 'file_path' (Join-Path $sj 'attempts/a0004/candidate.json'))) "path sdoc-worker：寫候選快照 → 擋"
    Assert (-not (Test-PathHook 'sdoc-worker' 'Bash' 'command' 'dir')) "path sdoc-worker：Bash → 擋"
    Assert (-not (Test-PathHook 'no-such' 'Read' 'file_path' (Join-Path $att 'manifest.md'))) "path：未知設定 → 擋（hook 設定錯不放行）"

    Write-Host "C：外環版本層（部署模擬目錄）"
    . (Join-Path $dep 'scripts/ps-knowledge-lib.ps1')
    . (Join-Path $dep 'scripts/ps-session-lib.ps1')
    . (Join-Path $dep 'scripts/ps-supplemental-lib.ps1')
    $v = Get-PsCliVariant -Root $dep
    Assert ($v.Name -eq 'claude' -and $v.PsDir -eq '.claude/peoplesoft' -and $v.Exe -eq 'claude' -and $v.Manifest -eq 'ps-transfer-manifest.claude.json') "版本判定：.claude/peoplesoft 存在＝Claude Code"
    Assert ((Get-PsCliVariant -Root $repoRoot).Name -eq 'opencode') "版本判定：維護端 repo 根＝OpenCode（Claude Code 版在 claude-code/ 子樹）"
    $env:PS_CLI = 'opencode'
    $vo = Get-PsCliVariant -Root $dep
    Remove-Item -Path Env:\PS_CLI -ErrorAction SilentlyContinue
    Assert ($vo.Name -eq 'opencode' -and $vo.Source -eq 'env') "版本判定：PS_CLI 環境變數優先"
    $cl = New-PsOcCommandLine -Variant 'claude' -OcPath 'C:\bin\claude.exe' -ExtraArgs '--command ps-research' -PromptText '轉職' -Tag 't' -OutFile 'o.txt' -ErrFile 'e.txt' -StreamFile 's.jsonl'
    Assert ($cl.Agent -eq 'ps-deep-research' -and $cl.Prompt -eq '/ps-research 轉職' -and $cl.Inner -like '"C:\bin\claude.exe" -p --agent ps-deep-research --permission-mode dontAsk --output-format stream-json --verbose "/ps-research 轉職" < NUL 1> "s.jsonl" 2> "e.txt"') "命令列：--command ps-research → claude -p --agent ps-deep-research「/ps-research <領域>」（dontAsk、stream-json）"
    $cl2 = New-PsOcCommandLine -Variant 'claude' -OcPath 'claude.cmd' -Model 'sonnet' -ExtraArgs '--command ps-spec-batch' -PromptText 'job-a0001' -Tag 't' -OutFile 'o' -ErrFile 'e' -StreamFile 's'
    Assert ($cl2.Agent -eq 'ps-spec-worker' -and $cl2.Inner -match '--model "sonnet"') "命令列：ps-spec-batch → ps-spec-worker；-Model 透傳"
    Assert ((New-PsOcCommandLine -Variant 'claude' -OcPath 'claude.cmd' -ExtraArgs '--command ps-clone-batch' -PromptText 'x' -Tag 't' -OutFile 'o' -ErrFile 'e' -StreamFile 's').Agent -eq 'ps-clone-worker') "命令列：ps-clone-batch → ps-clone-worker"
    $cl3 = New-PsOcCommandLine -Variant 'claude' -OcPath 'claude.cmd' -ExtraArgs '--agent ps-deep-research' -PromptText '手術工單' -Tag 't' -OutFile 'o' -ErrFile 'e' -StreamFile 's'
    Assert ($cl3.Agent -eq 'ps-deep-research' -and $cl3.Prompt -eq '手術工單') "命令列：--agent 原樣、prompt 不加指令"
    $env:PS_CLAUDE_PERMISSION_MODE = 'acceptEdits'
    $cl4 = New-PsOcCommandLine -Variant 'claude' -OcPath 'claude.cmd' -ExtraArgs '--agent ps-deep-research' -PromptText 'x' -Tag 't' -OutFile 'o' -ErrFile 'e' -StreamFile 's'
    $env:PS_CLAUDE_PERMISSION_MODE = 'rm -rf'
    $cl5 = New-PsOcCommandLine -Variant 'claude' -OcPath 'claude.cmd' -ExtraArgs '--agent ps-deep-research' -PromptText 'x' -Tag 't' -OutFile 'o' -ErrFile 'e' -StreamFile 's'
    Remove-Item -Path Env:\PS_CLAUDE_PERMISSION_MODE -ErrorAction SilentlyContinue
    Assert ($cl4.Inner -match '--permission-mode acceptEdits' -and $cl5.Inner -match '--permission-mode dontAsk ') "命令列：PS_CLAUDE_PERMISSION_MODE 只接受已知值，其餘回 dontAsk"
    $clo = New-PsOcCommandLine -Variant 'opencode' -OcPath 'opencode.cmd' -ExtraArgs '--command ps-research' -PromptText '轉職' -Tag 'r1' -OutFile 'o.txt' -ErrFile 'e.txt'
    Assert ($clo.Inner -eq '"opencode.cmd" run --command ps-research --title "auto-r1" "轉職" 1> "o.txt" 2> "e.txt"') "命令列：OpenCode 版形狀不變"
    $sf = Join-Path $dep 's.jsonl'
    $of = Join-Path $dep 'o.txt'
    [System.IO.File]::WriteAllText($sf, ('{"type":"system","subtype":"init"}' + "`n" + '{"type":"assistant","message":{"content":[{"type":"text","text":"中途"}]}}' + "`n" + '{"type":"result","subtype":"success","is_error":false,"num_turns":7,"result":"## 記分卡\n| 檔案 |\n已寫 docs/x.md"}' + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    $r = Convert-PsOcClaudeStream -StreamFile $sf -OutFile $of
    Assert ($r.Found -and -not $r.IsError -and $r.Turns -eq 7 -and ([System.IO.File]::ReadAllText($of)) -ceq ("## 記分卡`n| 檔案 |`n已寫 docs/x.md")) "stream-json：最後一個 result 事件的最終回覆抽進 OutFile（stdout 回收語意不變）"
    [System.IO.File]::WriteAllText($sf, ('{"type":"result","subtype":"error_during_execution","is_error":true,"num_turns":2,"result":"Prompt is too long"}' + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    $r = Convert-PsOcClaudeStream -StreamFile $sf -OutFile $of
    Assert ($r.Found -and $r.IsError -and (Get-PsOcFailureKind -OutFile $of -ErrFile '') -eq 'CONTEXT_OVERFLOW') "stream-json：錯誤收場與 context 溢出字樣（Prompt is too long）可辨識"
    [System.IO.File]::WriteAllText($sf, '{"type":"system","subtype":"init"}', (New-Object System.Text.UTF8Encoding($false)))
    Assert (-not (Convert-PsOcClaudeStream -StreamFile $sf -OutFile (Join-Path $dep 'none.txt')).Found) "stream-json：沒有 result 事件 → Found=false"
    Assert ((Get-PsSuppDirs -Root $dep).Capabilities -like '*.claude*peoplesoft*spec*capabilities.json' -and (Test-Path -LiteralPath (Get-PsSuppDirs -Root $dep).Capabilities)) "補研究：能力目錄取 .claude/peoplesoft/spec"
    $pub = Publish-PsKnowledgeIndex -Root $dep
    $imd = [System.IO.File]::ReadAllText((Join-Path $dep 'docs/ps-research/knowledge/index.md'))
    $omd = [System.IO.File]::ReadAllText((Join-Path $dep 'docs/ps-research/knowledge/objects.md'))
    Assert ($pub.published -and $imd -match '\.claude/peoplesoft/knowledge-retrieval-contract\.md' -and $imd -match 'path=docs/ps-research/knowledge/index\.md，output_mode=content' -and $omd -match 'path=docs/ps-research/knowledge/objects\.md' -and $imd -notmatch '(?i)opencode') "知識索引：用法行是 Claude Code 的 Grep／Read 形狀與 .claude 契約路徑"
    # B 段把 profile 的 connectionName 改成測試值——先還原再驗搬運完整性
    Copy-Item -LiteralPath (Join-Path $cc '.claude/peoplesoft/customization-profile.yaml') -Destination $pf -Force
    $fsd = ((& (Join-Path $dep 'scripts/ps-fs-doctor.ps1') *>&1 | ForEach-Object { [string]$_ }) -join "`n")
    Assert ($fsd -match '檢查 M\] 搬運完整性（Claude Code 版' -and $fsd -match '結論代號：G') "fs-doctor：部署模擬目錄對 Claude Code 版 manifest 全部一致（scripts/ps-transfer-manifest.claude.json 是最新）"
    Remove-Item -LiteralPath (Join-Path $dep '.claude/agents/ps-ui-flow.md') -Force
    [System.IO.File]::WriteAllText((Join-Path $dep '.claude/hooks/old-guard.ps1'), '#', (New-Object System.Text.UTF8Encoding($true)))
    $fsd2 = ((& (Join-Path $dep 'scripts/ps-fs-doctor.ps1') -ShowExtras *>&1 | ForEach-Object { [string]$_ }) -join "`n")
    Assert ($fsd2 -match '漏搬：\.claude/agents/ps-ui-flow\.md' -and $fsd2 -match '未列管的多出檔：\.claude/hooks/old-guard\.ps1' -and $fsd2 -match '結論代號：.*M') "fs-doctor：漏搬 agent 與多出檔點名（M／X）"
    Copy-Item -LiteralPath (Join-Path $cc '.claude/agents/ps-ui-flow.md') -Destination (Join-Path $dep '.claude/agents/ps-ui-flow.md')
    Remove-Item -LiteralPath (Join-Path $dep '.claude/hooks/old-guard.ps1') -Force
    # ps-claude-doctor -Offline：hook 以 powershell 名稱執行——維護端 PATH 只有 pwsh 時，臨時放一個同名連結
    $shim = Join-Path $dep '.shim'
    New-Item -ItemType Directory -Path $shim -Force | Out-Null
    $savedPath = $env:PATH
    if (@(Get-Command powershell -ErrorAction SilentlyContinue).Count -eq 0) {
        $shimTarget = Join-Path $shim 'powershell'
        if ($IsWindows) { $shimTarget = $shimTarget + '.exe' }
        New-Item -ItemType SymbolicLink -Path $shimTarget -Target $pwshExe | Out-Null
        $env:PATH = $shim + [System.IO.Path]::PathSeparator + $env:PATH
    }
    try {
        $doc1 = ((& (Join-Path $dep 'scripts/ps-claude-doctor.ps1') -Offline *>&1 | ForEach-Object { [string]$_ }) -join "`n")
        Assert ($doc1 -match '結論代號：F$' -or $doc1 -match '結論代號：F\s') "ps-claude-doctor -Offline：profile 未回填 → 只報 F（版本判定、powershell、hook 自測都過）"
        [System.IO.File]::WriteAllText($pf, ([System.IO.File]::ReadAllText($pf) -replace '(?m)^  connectionName: FILL_ME', '  connectionName: HR_DEV'), (New-Object System.Text.UTF8Encoding($false)))
        $doc2 = ((& (Join-Path $dep 'scripts/ps-claude-doctor.ps1') -Offline *>&1 | ForEach-Object { [string]$_ }) -join "`n")
        Assert ($doc2 -match '結論代號：G') "ps-claude-doctor -Offline：回填後 → G"
        Copy-Item -LiteralPath (Join-Path $cc '.claude/peoplesoft/customization-profile.yaml') -Destination $pf -Force
    }
    finally { $env:PATH = $savedPath }
    $sd = ((& (Join-Path $dep 'scripts/ps-spec.ps1') -Doctor -Root $dep *>&1 | ForEach-Object { [string]$_ }) -join "`n")
    $sdLines = @(($sd -replace "`r", '') -split "`n" | Where-Object { $_.Trim() -ne '' })
    $sdLast = ''
    if ($sdLines.Count -gt 0) { $sdLast = $sdLines[$sdLines.Count - 1].Trim() }
    Assert ($sdLast -eq 'SPEC1-0-03') ("ps-spec -Doctor：Claude Code 版 generic.manifest.json 是最新（SPEC1-0-03；實得 " + $sdLast + "；過期就跑本測試 -WriteGenericManifest）")
}
finally {
    Remove-Item -LiteralPath $dep -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
if ($failCount -gt 0) { Write-Host "共 $failCount 個 FAIL" -ForegroundColor Red; exit 1 }
Write-Host "全部情境 PASS" -ForegroundColor Green
exit 0
