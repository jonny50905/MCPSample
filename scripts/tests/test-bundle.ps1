# scripts/tests/test-bundle.ps1 — 搬運包（ps-bundle.ps1 打包／解開）的功能測試（維護端；PowerShell 7 或 5.1）
# 範圍（臨時目錄，結束自刪）：repo 的搬運包各份是最新（與現況重新打包逐字相同、每份不超過上限、舊式單一檔已不在）；
#   全新安裝（各份以 CRLF＋BOM、任意檔名、打亂順序另存在同一資料夾，其中一份存成 UTF-16）→ fs-doctor G；只給其中一份＝同資料夾自動找齊；
#   各份接成一個檔也能解；重跑全相同；三方比對（本機改過＋上游沒動＝保留本機、本機沒改＋上游改＝更新並備份、兩邊都改＝.incoming、
#   設定檔無基準＝.incoming）；scripts 本機改過一律更新；必刪舊檔移到備份；
#   整包驗證（截斷＝T、內容被改＝H、路徑跳出或不屬於該版＝P、缺份＝T、某一份截斷＝T、某一份被改＝H、資料夾混了兩組＝T）時一個檔都不寫；
#   舊式單一檔照樣能解；OpenCode 版含 AGENTS.md。
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ErrorActionPreference = 'Stop'
$bundleScript = Join-Path $repoRoot 'scripts/ps-bundle.ps1'
$failCount = 0
function Assert([bool]$Cond, [string]$Name) {
    if ($Cond) { Write-Host "  PASS：$Name" }
    else { Write-Host "  FAIL：$Name" -ForegroundColor Red; $script:failCount++ }
}
function Get-Norm([string]$Text) {
    if ($Text.Length -gt 0 -and [int]$Text[0] -eq 0xFEFF) { $Text = $Text.Substring(1) }
    $t = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    return (($t -replace '\s+$', '') + "`n")
}
function Get-Sha([string]$Norm) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Norm)) } finally { $sha.Dispose() }
    return ((@($h | ForEach-Object { $_.ToString('x2') })) -join '')
}
function Read-Text([string]$Path) { return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) }
function Write-Text([string]$Path, [string]$Text, [bool]$Bom = $false) {
    $d = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($Bom)))
}
function Invoke-Unpack([string]$Target, [string]$BundlePath, [switch]$DryRun) {
    $h = @{ Bundle = $BundlePath }
    if ($DryRun) { $h['DryRun'] = $true }
    $o = ((& (Join-Path $Target 'scripts/ps-bundle.ps1') @h *>&1 | ForEach-Object { [string]$_ }) -join "`n")
    $script:lastExit = $LASTEXITCODE
    return $o
}
function Get-Code([string]$Out) {
    $m = [regex]::Matches($Out, '結論代號：(\S+)')
    if ($m.Count -eq 0) { return '' }
    return $m[$m.Count - 1].Groups[1].Value
}
function New-Target {
    $t = Join-Path $work ('t-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path (Join-Path $t 'scripts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $t 'docs/ps-research') -Force | Out-Null
    Copy-Item -LiteralPath $bundleScript -Destination (Join-Path $t 'scripts/ps-bundle.ps1')
    return $t
}
function Get-FileCount([string]$Dir) { return @(Get-ChildItem -LiteralPath $Dir -Recurse -File -Force).Count }
# 某個資料夾裡某一版的各份（依份序）
function Get-PartPaths([string]$Dir, [string]$Variant) {
    $rx = '^ps-bundle-' + $Variant + '-[0-9]{2}of[0-9]{2}\.txt$'
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -File | Sort-Object Name)) { if ($f.Name -match $rx) { $list.Add($f.FullName) } }
    return , $list.ToArray()
}
# 模擬公司機另存：各份改成任意檔名（倒序編號）、CRLF＋BOM；-Utf16 時第 1 份存成 Unicode；-Skip 的份不放
function New-PartsFolder([string[]]$Parts, [string]$Name, [switch]$Utf16, [int[]]$Skip = @()) {
    $dir = Join-Path $work $Name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    for ($k = 1; $k -le $Parts.Count; $k++) {
        if ($Skip -contains $k) { continue }
        $txt = (Get-Norm (Read-Text $Parts[$k - 1])).Replace("`n", "`r`n")
        $dst = Join-Path $dir ('第' + (100 - $k) + '份.txt')
        if ($Utf16 -and $k -eq 1) { [System.IO.File]::WriteAllText($dst, $txt, [System.Text.Encoding]::Unicode) }
        else { Write-Text $dst $txt $true }
    }
    return $dir
}
# 手工組搬運包（驗證失敗類情境用）：files＝@(@{Path;Text})
function New-RawBundle([string]$Variant, $Files, [string[]]$Removed = @()) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('@@@PSBUNDLE|1|' + $Variant + '|test|' + @($Files).Count + "`n")
    foreach ($r in $Removed) { [void]$sb.Append('@@@PSBUNDLE-REMOVED|' + $r + "`n") }
    $agg = New-Object System.Text.StringBuilder
    foreach ($f in $Files) {
        $n = Get-Norm $f.Text
        $sha = Get-Sha $n
        [void]$sb.Append('@@@PSBUNDLE-FILE|' + $f.Path + '|' + (@($n -split "`n").Count - 1) + '|' + $sha + "|0`n").Append($n).Append('@@@PSBUNDLE-END|' + $f.Path + "`n")
        [void]$agg.Append($f.Path).Append("`n").Append($sha).Append("`n")
    }
    [void]$sb.Append('@@@PSBUNDLE-EOF|' + @($Files).Count + '|' + (Get-Sha $agg.ToString()) + "`n")
    return $sb.ToString()
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('bundle-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
    Write-Host "1：repo 的搬運包各份是最新"
    $transferDir = Join-Path $repoRoot 'transfer'
    foreach ($v in @('opencode', 'claude')) {
        $mName = 'ps-transfer-manifest.json'
        $extra = @('AGENTS.md')
        if ($v -eq 'claude') { $mName = 'ps-transfer-manifest.claude.json'; $extra = @() }
        $freshDir = Join-Path $work ('fresh-' + $v)
        New-Item -ItemType Directory -Path $freshDir -Force | Out-Null
        $null = & $bundleScript -Pack -Manifest (Join-Path $repoRoot ('scripts/' + $mName)) -Out (Join-Path $freshDir ('ps-bundle-' + $v + '.txt')) -Root $repoRoot -Extra $extra *>&1
        $fresh = Get-PartPaths $freshDir $v
        $committed = Get-PartPaths $transferDir $v
        $same = ($fresh.Count -ge 2 -and $fresh.Count -eq $committed.Count)
        if ($same) {
            for ($i = 0; $i -lt $fresh.Count; $i++) {
                if ([System.IO.Path]::GetFileName($fresh[$i]) -cne [System.IO.Path]::GetFileName($committed[$i]) -or (Get-Norm (Read-Text $fresh[$i])) -cne (Get-Norm (Read-Text $committed[$i]))) { $same = $false }
            }
        }
        Assert $same ("transfer/ps-bundle-" + $v + "-NNofMM.txt 各份與現況重新打包逐字相同（過期就跑 ps-fs-doctor -WriteManifest）")
        Assert (-not (Test-Path -LiteralPath (Join-Path $transferDir ('ps-bundle-' + $v + '.txt')))) ("舊式單一檔 transfer/ps-bundle-" + $v + ".txt 已不在")
        $sizeOk = $true
        foreach ($c in $committed) {
            $len = (Get-Item -LiteralPath $c).Length
            $nf = ([regex]::Matches((Read-Text $c), '(?m)^@@@PSBUNDLE-FILE\|')).Count
            if ($len -gt (500 * 1024 + 2048) -and $nf -gt 1) { $sizeOk = $false }
        }
        Assert $sizeOk ("每一份不超過 500 KB（只有單一檔本身超過上限時才例外）：" + $v)
    }

    Write-Host "2：全新安裝（Claude Code 版；各份任意檔名、倒序、CRLF＋BOM 另存在同一資料夾，第 1 份存成 UTF-16）"
    $cp = Get-PartPaths $transferDir 'claude'
    $in = New-PartsFolder $cp 'in-claude' -Utf16
    $classicDir = Join-Path $work 'classic'
    New-Item -ItemType Directory -Path $classicDir -Force | Out-Null
    $classic = Join-Path $classicDir 'ps-bundle-claude.txt'
    $null = & $bundleScript -Pack -Manifest (Join-Path $repoRoot 'scripts/ps-transfer-manifest.claude.json') -Out $classic -Root $repoRoot -PartKB 0 *>&1
    Copy-Item -LiteralPath $classic -Destination (Join-Path $in 'old-single.txt')
    $t = New-Target
    $o = Invoke-Unpack $t $in -DryRun
    Assert ($o -match '計畫（-DryRun' -and -not (Test-Path -LiteralPath (Join-Path $t 'CLAUDE.md'))) "-DryRun 只列計畫、不寫檔"
    $o = Invoke-Unpack $t $in
    Assert ((Get-Code $o) -eq 'G' -and $script:lastExit -eq 0 -and $o -match ('分 ' + $cp.Count + ' 份：全部到齊') -and (Test-Path -LiteralPath (Join-Path $t 'CLAUDE.md')) -and (Test-Path -LiteralPath (Join-Path $t 'scripts/ps-transfer-manifest.claude.json'))) "給資料夾：各份到齊、G、CLAUDE.md 與 manifest 都寫出"
    Assert ($o -match '另有 1 個舊式單一搬運包檔，已略過') "資料夾裡的舊式單一檔被略過（不混用）"
    $hb = [System.IO.File]::ReadAllBytes((Join-Path $t '.claude/hooks/ps-runtime-guard.ps1'))
    $mb = [System.IO.File]::ReadAllBytes((Join-Path $t '.claude/settings.json'))
    Assert ($hb[0] -eq 0xEF -and $hb[1] -eq 0xBB -and $mb[0] -ne 0xEF) ".ps1 寫成 UTF-8 with BOM、其他檔無 BOM"
    $fsd = ((& (Join-Path $t 'scripts/ps-fs-doctor.ps1') *>&1 | ForEach-Object { [string]$_ }) -join "`n")
    Assert ($fsd -match 'Claude Code 版' -and $fsd -match '結論代號：G') "解開後 ps-fs-doctor：Claude Code 版、G"
    $o = Invoke-Unpack $t $in
    Assert ((Get-Code $o) -eq 'G' -and $o -match '新增 0／更新 0／相同 \d+／保留本機 0／衝突 0／刪除 0') "重跑：全部相同"
    $one = Join-Path $in '第97份.txt'
    $o = Invoke-Unpack $t $one
    Assert ((Get-Code $o) -eq 'G' -and $o -match ('分 ' + $cp.Count + ' 份：全部到齊') -and $o -match '相同 \d+／保留本機 0') "只給其中一份：同資料夾的其他份自動找齊"
    $catSb = New-Object System.Text.StringBuilder
    foreach ($p in $cp) { [void]$catSb.Append((Get-Norm (Read-Text $p))) }
    $catDir = Join-Path $work 'cat'
    $cat = Join-Path $catDir 'all-in-one.txt'
    Write-Text $cat $catSb.ToString()
    $o = Invoke-Unpack $t $cat
    Assert ((Get-Code $o) -eq 'G' -and $o -match ('分 ' + $cp.Count + ' 份：全部到齊')) "各份依序接成一個檔也能解"

    Write-Host "3：三方比對"
    $agentA = Join-Path $t '.claude/agents/ps-ui-flow.md'
    $agentB = Join-Path $t '.claude/agents/ps-sql-flow.md'
    $prof = Join-Path $t '.claude/peoplesoft/customization-profile.yaml'
    Write-Text $agentA ((Read-Text $agentA) + "`n本機教訓新增一行`n")
    Write-Text $prof ((Read-Text $prof) -replace '(?m)^  connectionName: FILL_ME', '  connectionName: HR_DEV')
    $scr = Join-Path $t 'scripts/ps-cli-lib.ps1'
    Write-Text $scr ((Read-Text $scr) + "`n# 本機亂改`n") $true
    $o = Invoke-Unpack $t $in
    Assert ((Read-Text $scr) -notmatch '本機亂改') "scripts 本機改過 → 一律更新回維護端版本（舊檔備份）"
    Assert ((Get-Code $o) -eq 'G' -and $o -match '保留本機 2' -and (Read-Text $agentA) -match '本機教訓新增一行' -and (Read-Text $prof) -match 'connectionName: HR_DEV') "本機改過、搬運包沒動 → 保留本機（agent 與已回填的 profile 都不被蓋）"
    # 上游：改 A（本機也改過）、B（本機沒改）、profile（本機改過）
    $srcRoot = Join-Path $work 'src'
    foreach ($d in @('scripts', 'claude-code')) { Copy-Item -LiteralPath (Join-Path $repoRoot $d) -Destination (Join-Path $srcRoot $d) -Recurse }
    foreach ($rel in @('claude-code/.claude/agents/ps-ui-flow.md', 'claude-code/.claude/agents/ps-sql-flow.md', 'claude-code/.claude/peoplesoft/customization-profile.yaml')) {
        $p = Join-Path $srcRoot $rel
        Write-Text $p ((Read-Text $p) + "`n# 上游新增`n")
    }
    $mfp = Join-Path $srcRoot 'scripts/ps-transfer-manifest.claude.json'
    $mfj = Read-Text $mfp
    Write-Text (Join-Path $srcRoot 'claude-code/.claude/agents/ps-legacy-old.md') 'x'
    Write-Text $mfp ($mfj -replace '"removed":\s*\[\s*\]', '"removed": [ { "path": ".claude/agents/ps-legacy-old.md", "note": "test" } ]')
    $v2Dir = Join-Path $work 'v2'
    New-Item -ItemType Directory -Path $v2Dir -Force | Out-Null
    $null = & $bundleScript -Pack -Manifest $mfp -Out (Join-Path $v2Dir 'ps-bundle-claude.txt') -Root $srcRoot *>&1
    Write-Text (Join-Path $t '.claude/agents/ps-legacy-old.md') 'old'
    $o = Invoke-Unpack $t $v2Dir
    Assert ((Get-Code $o) -eq 'C' -and $script:lastExit -eq 0) "兩邊都改 → 結論 C（有衝突待合併）"
    Assert ((Read-Text $agentB) -match '# 上游新增') "本機沒改、上游改 → 更新"
    Assert ((Read-Text $agentA) -match '本機教訓新增一行' -and (Read-Text $agentA) -notmatch '# 上游新增' -and (Test-Path -LiteralPath ($agentA + '.incoming')) -and (Read-Text ($agentA + '.incoming')) -match '# 上游新增') "兩邊都改 → 本機不動、新版另存 .incoming"
    Assert ((Read-Text $prof) -match 'connectionName: HR_DEV' -and (Test-Path -LiteralPath ($prof + '.incoming'))) "profile 兩邊都改 → 回填值保留、新版 .incoming"
    Assert (-not (Test-Path -LiteralPath (Join-Path $t '.claude/agents/ps-legacy-old.md'))) "必刪舊檔已移除"
    $bk = @(Get-ChildItem -LiteralPath (Join-Path $t 'auto-loop-logs/ps-bundle-backup') -Recurse -File -Force | ForEach-Object { $_.Name })
    Assert ($bk -contains 'ps-sql-flow.md' -and $bk -contains 'ps-legacy-old.md') "被覆寫與刪除的舊檔都在備份目錄"

    Write-Host "4：整包驗證失敗時一個檔都不寫"
    $t2 = New-Target
    $all = Get-Norm (Read-Text $classic)
    $cut = Join-Path $work 'cut.txt'
    Write-Text $cut ($all.Substring(0, [int]($all.Length * 0.6)))
    $o = Invoke-Unpack $t2 $cut
    Assert ((Get-Code $o) -eq 'T' -and $script:lastExit -ne 0 -and (Get-FileCount $t2) -eq 1) "舊式單一檔截斷 → T、沒寫任何檔"
    $ix = $all.IndexOf('connectionName: FILL_ME')
    $bad = Join-Path $work 'bad.txt'
    Write-Text $bad ($all.Substring(0, $ix) + 'connectionName: FILL_ME?' + $all.Substring($ix + 'connectionName: FILL_ME'.Length))
    $o = Invoke-Unpack $t2 $bad
    Assert ((Get-Code $o) -eq 'H' -and (Get-FileCount $t2) -eq 1) "舊式單一檔內容被改 → H、沒寫任何檔"
    $trav = Join-Path $work 'trav.txt'
    Write-Text $trav (New-RawBundle 'claude' @(@{ Path = 'scripts/ok.txt'; Text = 'ok' }, @{ Path = 'scripts/../../evil.txt'; Text = 'x' }))
    $o = Invoke-Unpack $t2 $trav
    Assert ((Get-Code $o) -eq 'P' -and -not (Test-Path -LiteralPath (Join-Path $t2 'scripts/ok.txt'))) "路徑跳出專案 → P、整包不寫"
    $wrong = Join-Path $work 'wrong.txt'
    Write-Text $wrong (New-RawBundle 'claude' @(@{ Path = '.opencode/agent/x.md'; Text = 'x' }))
    $o = Invoke-Unpack $t2 $wrong
    Assert ((Get-Code $o) -eq 'P') "Claude Code 版搬運包裡出現 .opencode 路徑 → P"
    $rmBad = Join-Path $work 'rmbad.txt'
    Write-Text $rmBad (New-RawBundle 'claude' @(@{ Path = 'scripts/ok.txt'; Text = 'ok' }) @('docs/ps-research/x.md'))
    $o = Invoke-Unpack $t2 $rmBad
    Assert ((Get-Code $o) -eq 'P') "必刪清單不屬於該版的範圍（研究產出）→ P"
    $n = $cp.Count
    $miss = New-PartsFolder $cp 'miss' -Skip @(3)
    $o = Invoke-Unpack $t2 $miss
    Assert ((Get-Code $o) -eq 'T' -and $o -match ('第 3／' + $n + ' 份：沒有找到') -and (Get-FileCount $t2) -eq 1) "缺第 3 份 → T、指出缺哪一份、沒寫任何檔"
    $trunc = New-PartsFolder $cp 'trunc'
    $p2 = Join-Path $trunc '第98份.txt'
    $p2t = Read-Text $p2
    Write-Text $p2 ($p2t.Substring(0, [int]($p2t.Length * 0.7))) $true
    $o = Invoke-Unpack $t2 $trunc
    Assert ((Get-Code $o) -eq 'T' -and $o -match ('第 2／' + $n + ' 份（第98份\.txt）') -and (Get-FileCount $t2) -eq 1) "第 2 份貼上被截斷 → T、指出哪一份與檔名、沒寫任何檔"
    $mod = New-PartsFolder $cp 'mod'
    $p4 = Join-Path $mod '第96份.txt'
    $p4t = Read-Text $p4
    $mid = $p4t.IndexOf('PowerShell')
    Write-Text $p4 ($p4t.Substring(0, $mid) + 'P0werShell' + $p4t.Substring($mid + 10)) $true
    $o = Invoke-Unpack $t2 $mod
    Assert ((Get-Code $o) -eq 'H' -and $o -match ('第 4／' + $n + ' 份') -and (Get-FileCount $t2) -eq 1) "第 4 份內容被改 → H、沒寫任何檔"
    $two = New-PartsFolder $cp 'two'
    foreach ($f in (Get-PartPaths $v2Dir 'claude')) { Copy-Item -LiteralPath $f -Destination (Join-Path $two ('v2-' + [System.IO.Path]::GetFileName($f))) }
    $o = Invoke-Unpack $t2 $two
    Assert ((Get-Code $o) -eq 'T' -and $o -match '資料夾裡有 2 組不同次打包的搬運包' -and (Get-FileCount $t2) -eq 1) "資料夾混了兩次打包的份 → T、列出各組、沒寫任何檔"
    $o = Invoke-Unpack $t2 (Join-Path $two '第99份.txt')
    Assert ((Get-Code $o) -eq 'G') "同一個資料夾，指名其中一份 → 只取那一組（另一組不混用）"

    Write-Host "5：設定檔沒有基準時不覆寫（舊式單一檔照樣能解）"
    $t3 = New-Target
    Write-Text (Join-Path $t3 '.claude/peoplesoft/research-domains.txt') "本機領域`n"
    $o = Invoke-Unpack $t3 $classic
    Assert ((Get-Code $o) -eq 'C' -and (Read-Text (Join-Path $t3 '.claude/peoplesoft/research-domains.txt')) -match '本機領域' -and (Test-Path -LiteralPath (Join-Path $t3 '.claude/peoplesoft/research-domains.txt.incoming'))) "沒有 manifest 記錄的本機研究佇列 → 衝突、不覆寫"

    Write-Host "6：OpenCode 版全新安裝"
    $t4 = New-Target
    $inO = New-PartsFolder (Get-PartPaths $transferDir 'opencode') 'in-opencode'
    $o = Invoke-Unpack $t4 $inO
    $fsd4 = ((& (Join-Path $t4 'scripts/ps-fs-doctor.ps1') *>&1 | ForEach-Object { [string]$_ }) -join "`n")
    Assert ((Get-Code $o) -eq 'G' -and (Test-Path -LiteralPath (Join-Path $t4 'AGENTS.md')) -and -not (Test-Path -LiteralPath (Join-Path $t4 '.claude')) -and $fsd4 -match 'OpenCode 版' -and $fsd4 -match '結論代號：G') "OpenCode 版：含 AGENTS.md、不含 .claude、fs-doctor G"
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ""
if ($failCount -gt 0) { Write-Host "共 $failCount 個 FAIL" -ForegroundColor Red; exit 1 }
Write-Host "全部情境 PASS" -ForegroundColor Green
exit 0
