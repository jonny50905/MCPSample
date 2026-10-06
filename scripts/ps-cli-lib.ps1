# ps-cli-lib.ps1 — 前端版本描述：同一套外環同時服務 OpenCode 版（.opencode）與 Claude Code 版（.claude）
# 判定（確定性）：env PS_CLI＝claude｜opencode 優先；否則 <Root>/.claude/peoplesoft 存在＝claude，其餘＝opencode。
#   維護端 repo 根目錄只有 .opencode/peoplesoft（Claude Code 版的原始檔在 claude-code/ 子樹，部署時去掉前綴）→ opencode。
#   公司機同一資料夾兩版並存時 claude 優先；要跑 OpenCode 版外環先設 $env:PS_CLI='opencode'。
# 純函式庫：dot-source 無副作用。PowerShell 5.1 紀律：無三元／??／&&；Join-Path 兩參數；-LiteralPath。

$script:PsCliLibVersion = 1

# 指令 → 主代理：Claude Code 的指令不切換主代理，外環以 --agent 帶（OpenCode 版由指令 frontmatter 的 agent 決定）
$script:PsCliCommandAgent = @{
    'ps-research'    = 'ps-deep-research'
    'ps-audit'       = 'ps-deep-research'
    'ps-audit-batch' = 'ps-deep-research'
    'ps-supplement'  = 'ps-deep-research'
    'ps-lesson'      = 'ps-deep-research'
    'ps-correct'     = 'ps-deep-research'
    'ps-spec'        = 'ps-spec-author'
    'ps-spec-batch'  = 'ps-spec-worker'
    'ps-clone-batch' = 'ps-clone-worker'
}

function Get-PsCliVariant {
    param([string]$Root)
    $name = ''
    $source = 'detect'
    $e = ([string]$env:PS_CLI).Trim().ToLowerInvariant()
    if ($e -eq 'claude' -or $e -eq 'opencode') { $name = $e; $source = 'env' }
    if ($name -eq '') {
        $name = 'opencode'
        if ($Root -and [System.IO.Directory]::Exists((Join-Path $Root (Join-Path '.claude' 'peoplesoft')))) { $name = 'claude' }
    }
    if ($name -eq 'claude') {
        return @{
            Name = 'claude'; Display = 'Claude Code'; Source = $source; Exe = 'claude'
            FwDir = '.claude'; AgentDir = '.claude/agents'; CommandDir = '.claude/commands'; SkillDir = '.claude/skills'
            PsDir = '.claude/peoplesoft'; Manifest = 'ps-transfer-manifest.claude.json'; InstructionFile = 'CLAUDE.md'
        }
    }
    return @{
        Name = 'opencode'; Display = 'OpenCode'; Source = $source; Exe = 'opencode'
        FwDir = '.opencode'; AgentDir = '.opencode/agent'; CommandDir = '.opencode/command'; SkillDir = '.opencode/skills'
        PsDir = '.opencode/peoplesoft'; Manifest = 'ps-transfer-manifest.json'; InstructionFile = 'AGENTS.md'
    }
}

# <Root> 底下的框架檔絕對路徑；Rel 以 / 分隔（例 'spec/capabilities.json'）
function Get-PsCliPsPath {
    param([string]$Root, [string]$Rel = '')
    $v = Get-PsCliVariant -Root $Root
    $p = Join-Path $Root $v.PsDir
    if ($Rel -ne '') { $p = Join-Path $p $Rel }
    return $p
}

function Get-PsCliCommandAgent {
    param([string]$Command)
    if ($script:PsCliCommandAgent.ContainsKey($Command)) { return [string]$script:PsCliCommandAgent[$Command] }
    return ''
}
