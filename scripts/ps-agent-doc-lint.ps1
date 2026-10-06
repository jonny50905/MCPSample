# ps-agent-doc-lint.ps1 — 模型讀的檔只留規則（唯讀檢查）
# 範圍：.opencode/agent、skills、command、peoplesoft/*.md（SOP／README／test-scenarios 除外）、report-templates、peoplesoft/spec/*.md；
#       Claude Code 版同一組（.claude/agents、skills、commands、peoplesoft/…）＋CLAUDE.md（維護端在 claude-code/ 子樹）。
# 阻擋：issue 編號、日期、變更敘述詞（審查發現／已廢止／舊版／暫時解／追記／同日／根因未明）。
#       這些是給人看的歷史，只能放 lessons/applied.md、SOP.md、HANDOFF.md、commit 訊息。
# 警告：教訓編號 L<nn>（既有慣例，先只計數不擋）。
# 用法：pwsh -NoProfile -File scripts\ps-agent-doc-lint.ps1 [-Root <repo>]；exit 1＝有阻擋項。
#       ps-fs-doctor -WriteManifest 會先跑本檢查，不過就不重生 manifest。
param([string]$Root = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
$globs = @('.opencode/agent/*.md', '.opencode/skills/*/SKILL.md', '.opencode/command/*.md',
           '.opencode/peoplesoft/*.md', '.opencode/peoplesoft/report-templates/*.md', '.opencode/peoplesoft/spec/*.md')
# Claude Code 版：維護端在 claude-code/ 子樹、公司機部署在根目錄的 .claude（含 CLAUDE.md——它只放執行期規則）。
# 根目錄 .claude 只有在 .claude/peoplesoft 存在時才是框架（維護端根目錄的 .claude 是維護工具，不掃）
$pres = @('claude-code/')
if ([System.IO.Directory]::Exists((Join-Path $Root (Join-Path '.claude' 'peoplesoft')))) { $pres += '' }
foreach ($pre in $pres) {
    $globs += @(($pre + '.claude/agents/*.md'), ($pre + '.claude/skills/*/SKILL.md'), ($pre + '.claude/commands/*.md'),
        ($pre + '.claude/peoplesoft/*.md'), ($pre + '.claude/peoplesoft/report-templates/*.md'), ($pre + '.claude/peoplesoft/spec/*.md'),
        ($pre + 'CLAUDE.md'))
}
$exclude = @('SOP.md', 'README.md', 'test-scenarios.md')
$block = @(
    @{ Kind = 'issue 編號'; Rx = '(?i)issue\s*#\d+' },
    @{ Kind = 'Case 編號'; Rx = '#\d+\s*Case\s*\d' },
    @{ Kind = '日期';      Rx = '(?<!\d)20\d\d-\d\d(?:-\d\d)?(?!\d)' },
    @{ Kind = '變更敘述';  Rx = '審查發現|對抗審查|已廢止|舊版|暫時解|追記|同日|根因未明' }
)
$warnRx = '(?<![A-Za-z0-9])L\d{2,3}(?![A-Za-z0-9])'
$files = @()
foreach ($g in $globs) {
    $files += @(Get-ChildItem -Path (Join-Path $Root $g) -File -ErrorAction SilentlyContinue |
            Where-Object { $exclude -notcontains $_.Name })
}
$hits = 0; $warn = 0
foreach ($f in ($files | Sort-Object FullName -Unique)) {
    $rel = $f.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
    $text = [System.IO.File]::ReadAllText($f.FullName)
    if ($text.Length -gt 0 -and [int]$text[0] -eq 0xFEFF) { $text = $text.Substring(1) }
    $lines = $text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $ln = $lines[$i]
        foreach ($b in $block) {
            if ($ln -match $b.Rx) {
                $hits++
                Write-Host ("  " + $rel + ":" + ($i + 1) + " [" + $b.Kind + "] " + $ln.Trim())
            }
        }
        $warn += @([regex]::Matches($ln, $warnRx)).Count
    }
}
Write-Host ("agent 檔檢查：阻擋 " + $hits + " 項；教訓編號 L<nn>：" + $warn + " 處（既有慣例，先只計數）")
if ($hits -gt 0) {
    Write-Host "  出處／日期／變更敘述不進模型讀的檔——搬去 lessons/applied.md、SOP.md、HANDOFF.md 或 commit 訊息。" -ForegroundColor Red
    exit 1
}
exit 0
