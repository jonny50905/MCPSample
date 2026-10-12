# ps-bundle.ps1 — 搬運包：把一個版本要搬的檔收成幾份文字檔，公司機一個指令解回各檔
# 用法（公司機）：
#   每一份都另存成 UTF-8 文字檔（.txt，檔名不拘）、放進同一個資料夾，在專案資料夾執行：
#   powershell -NoProfile -File .\scripts\ps-bundle.ps1 -Bundle <資料夾> -DryRun   ← 先看會做什麼（不寫檔）
#   powershell -NoProfile -File .\scripts\ps-bundle.ps1 -Bundle <資料夾>           ← 解開
#   -Bundle 也可以給其中一份（同資料夾的其他份自動找齊）、逗號分隔的幾個檔，或舊式的單一搬運包檔。
#   第一次用：本檔要先手動搬一次（之後每次搬運包都會帶新版的本檔）。本檔必須放在 <專案>\scripts\ 底下（或給 -Root）。
# 用法（維護端，由 ps-fs-doctor -WriteManifest 呼叫）：
#   pwsh -NoProfile -File scripts/ps-bundle.ps1 -Pack -Manifest scripts/ps-transfer-manifest.claude.json -Out transfer/ps-bundle-claude.txt
#   → 寫 transfer/ps-bundle-claude-01of06.txt …（-PartKB＝每份上限 KB，預設 500；同名的舊份與舊式單一檔一併刪掉）；
#     -PartKB 0＝只寫舊式單一檔（-Out 本身）。
#
# 搬運包本體＝純文字：每個檔是「@@@PSBUNDLE-FILE|路徑|行數|sha256|bom」＋原文各行＋「@@@PSBUNDLE-END|路徑」；
#   開頭「@@@PSBUNDLE|1|版本|commit|檔數」，必刪舊檔「@@@PSBUNDLE-REMOVED|路徑」，結尾「@@@PSBUNDLE-EOF|檔數|總雜湊」。
# 分份：本體只在檔與檔之間切開；每一份是「@@@PSBUNDLE-PART|1|版本|commit|組代號|第幾份|共幾份|行數|sha256」＋本體的一段＋
#   「@@@PSBUNDLE-PART-END|組代號|第幾份|共幾份」。組代號＝本體雜湊前 16 碼，不同次打包的份不會被混用。
#   各份依序接成一個檔也能解（舊版的本檔讀不懂分份，但讀得懂接起來的檔）。
#   雜湊與 ps-fs-doctor 同一套正規化（剝 BOM、換行統一 LF、檔尾空白裁掉）——記事本另存的 CRLF／BOM 不影響；另存成 Unicode（UTF-16）也讀得懂。
# 解開前整包先驗：缺份、某一份被截斷或被改、份與份不同組、缺開頭／結尾、檔數或總雜湊不符、任一檔雜湊不符、路徑不合法 → 一個檔都不寫。
# 逐檔決定（三方比對：本機現況／上次搬入時的 manifest 記錄／搬運包）：
#   新增＝本機沒有；相同＝本機已一致；更新＝本機沒改過（＝上次 manifest 記錄）→ 覆寫；
#   保留本機＝本機改過、搬運包這次沒動它 → 不碰（例：已回填的 profile、/ps-lesson 改過的檔）；
#   衝突＝本機改過、搬運包也改了 → 本機不動，新版另存「<檔>.incoming」請人工合併；
#   本機設定檔（profile、domain map、研究佇列、教訓帳本）沒有 manifest 記錄可比時一律當衝突，不覆寫。
#   scripts/** 不在本機改（外環腳本只由維護端改）：內容不同一律更新（舊檔照樣備份），不走保留／衝突。
#   覆寫與刪除前先備份到 auto-loop-logs\ps-bundle-backup\<時間>\。manifest 最後才寫（中途中斷，重跑可接續）。
# 結論代號：G 全部完成／C 有衝突待合併（.incoming）／T 搬運包不完整（缺份、截斷、混了別次打包的份：照訊息重新複製）／
#   H 內容雜湊不符（多半是另存成非 UTF-8）／P 路徑不合法（拒絕）／W 寫入後驗證失敗。只回報代號，不貼路徑。
# PowerShell 5.1 紀律：無三元／??／&&；Join-Path 兩參數；-LiteralPath。
param(
    [string[]]$Bundle = @(),
    [switch]$DryRun,
    [string]$Root = '',
    [switch]$Pack,
    [string]$Manifest = '',
    [string]$Out = '',
    [string[]]$Extra = @(),
    [int]$PartKB = 500
)
$ErrorActionPreference = 'Stop'
$script:BdMark = '@@@PSBUNDLE'
$script:BdManifestNames = @{ opencode = 'ps-transfer-manifest.json'; claude = 'ps-transfer-manifest.claude.json' }
$script:BdPrefixes = @{ opencode = @('scripts/', '.opencode/', 'AGENTS.md'); claude = @('scripts/', '.claude/', 'CLAUDE.md') }
$script:BdProtected = '^(\.opencode|\.claude)/peoplesoft/(customization-profile\.yaml|business-domain-map\.yaml|research-domains\.txt|lessons/applied\.md|lessons/pending\.md)$'

function Get-PsBdNorm([string]$Text) {
    if ($null -eq $Text) { $Text = '' }
    if ($Text.Length -gt 0 -and [int]$Text[0] -eq 0xFEFF) { $Text = $Text.Substring(1) }
    $t = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    return (($t -replace '\s+$', '') + "`n")
}
function Get-PsBdSha([string]$Norm) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Norm)) } finally { $sha.Dispose() }
    return ((@($h | ForEach-Object { $_.ToString('x2') })) -join '')
}
function Get-PsBdLineCount([string]$Norm) { return (@($Norm -split "`n").Count - 1) }
# UTF-8（有無 BOM 都可）；記事本另存成「Unicode」（UTF-16，有 BOM）也照樣讀
function Read-PsBdText([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { return [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2) }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { return [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2) }
    return (New-Object System.Text.UTF8Encoding($false)).GetString($bytes)
}

# ── 打包（維護端）────────────────────────────────────────────────
if ($Pack) {
    if ($Root -eq '') { $Root = Split-Path $PSScriptRoot -Parent }
    if ($Manifest -eq '' -or $Out -eq '') { Write-Host '用法：-Pack -Manifest <manifest.json> -Out <搬運包.txt> [-PartKB <每份上限 KB，0＝單一檔>] [-Root <repo>] [-Extra <路徑>…]' -ForegroundColor Red; exit 2 }
    $mPath = $Manifest
    if (-not [System.IO.Path]::IsPathRooted($mPath)) { $mPath = Join-Path $Root $mPath }
    $mf = (Read-PsBdText $mPath) | ConvertFrom-Json
    $variant = 'opencode'
    if ((Split-Path $mPath -Leaf) -eq $script:BdManifestNames['claude']) { $variant = 'claude' }
    $commit = [string]$mf.commit
    $items = @()
    foreach ($f in @($mf.files)) {
        $src = [string]$f.path
        if ($null -ne $f.PSObject.Properties['repo']) { $src = [string]$f.repo }
        $items += @{ Path = [string]$f.path; Src = (Join-Path $Root $src); Bom = [bool]$f.bom }
    }
    $items += @{ Path = ('scripts/' + (Split-Path $mPath -Leaf)); Src = $mPath; Bom = $false }
    foreach ($x in $Extra) { $items += @{ Path = $x; Src = (Join-Path $Root $x); Bom = $false } }
    $nl = "`n"
    $head = New-Object System.Text.StringBuilder
    [void]$head.Append($script:BdMark + '|1|' + $variant + '|' + $commit + '|' + $items.Count).Append($nl)
    $removedCount = 0
    foreach ($r in @($mf.removed)) { if ($null -ne $r -and [string]$r.path -ne '') { [void]$head.Append($script:BdMark + '-REMOVED|' + [string]$r.path).Append($nl); $removedCount++ } }
    # 每個檔一段（檔頭＋正規化內容＋結尾），分份只在段與段之間切
    $segs = New-Object System.Collections.Generic.List[string]
    $agg = New-Object System.Text.StringBuilder
    foreach ($it in $items) {
        $norm = Get-PsBdNorm (Read-PsBdText $it.Src)
        foreach ($ln in ($norm -split "`n")) { if ($ln.StartsWith($script:BdMark)) { throw ('檔案內容有搬運包保留標記開頭的行，無法打包：' + $it.Path) } }
        $sha = Get-PsBdSha $norm
        $bomFlag = '0'
        if ($it.Bom) { $bomFlag = '1' }
        $segs.Add($script:BdMark + '-FILE|' + $it.Path + '|' + (Get-PsBdLineCount $norm) + '|' + $sha + '|' + $bomFlag + $nl + $norm + $script:BdMark + '-END|' + $it.Path + $nl)
        [void]$agg.Append($it.Path).Append("`n").Append($sha).Append("`n")
    }
    $eofLine = $script:BdMark + '-EOF|' + $items.Count + '|' + (Get-PsBdSha $agg.ToString()) + $nl
    $core = $head.ToString() + [string]::Join('', $segs.ToArray()) + $eofLine
    $oPath = $Out
    if (-not [System.IO.Path]::IsPathRooted($oPath)) { $oPath = Join-Path $Root $oPath }
    $oDir = Split-Path $oPath -Parent
    if (-not (Test-Path -LiteralPath $oDir)) { New-Item -ItemType Directory -Path $oDir -Force | Out-Null }
    $oName = Split-Path $oPath -Leaf
    $base = [System.IO.Path]::GetFileNameWithoutExtension($oName)
    $partRx = '^' + [regex]::Escape($base) + '-[0-9]{2}of[0-9]{2}\.txt$'
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $writtenNames = @()
    $title = '# PeopleSoft 知識庫分析框架——搬運包（' + $variant + ' 版；commit ' + $commit + '）'
    if ($PartKB -le 0) {
        $txt = $title + $nl + '# 整份另存成一個 UTF-8 文字檔，用 scripts\ps-bundle.ps1 -Bundle <檔> 解開（先加 -DryRun 看計畫）。不要手改本檔。' + $nl + $core
        [System.IO.File]::WriteAllText($oPath, $txt, $utf8)
        $writtenNames += $oName
        $partMsg = '單一檔'
    }
    else {
        $limit = [long]$PartKB * 1024
        $chunks = New-Object System.Collections.Generic.List[string]
        $cur = New-Object System.Text.StringBuilder
        [void]$cur.Append($head.ToString())
        $curBytes = [long]$utf8.GetByteCount($head.ToString())
        $curFiles = 0
        foreach ($s in $segs) {
            $b = [long]$utf8.GetByteCount($s)
            if ($curFiles -gt 0 -and ($curBytes + $b) -gt $limit) {
                $chunks.Add($cur.ToString())
                $cur = New-Object System.Text.StringBuilder
                $curBytes = 0
                $curFiles = 0
            }
            [void]$cur.Append($s)
            $curBytes += $b
            $curFiles++
        }
        [void]$cur.Append($eofLine)
        $chunks.Add($cur.ToString())
        $n = $chunks.Count
        if ($n -gt 99) { Write-Host ('搬運包超過 99 份——加大 -PartKB') -ForegroundColor Red; exit 2 }
        $setId = (Get-PsBdSha $core).Substring(0, 16)
        $maxKB = 0
        for ($k = 1; $k -le $n; $k++) {
            $body = $chunks[$k - 1]
            $lineCount = $body.Length - $body.Replace("`n", '').Length
            $hdr = $script:BdMark + '-PART|1|' + $variant + '|' + $commit + '|' + $setId + '|' + $k + '|' + $n + '|' + $lineCount + '|' + (Get-PsBdSha $body)
            $txt = $title + '第 ' + $k + '／' + $n + ' 份' + $nl +
                '# ' + $n + ' 份都另存成 UTF-8 文字檔（.txt，檔名不拘）放進同一個資料夾，用 scripts\ps-bundle.ps1 -Bundle <資料夾> 解開（先加 -DryRun 看計畫）。不要手改本檔。' + $nl +
                $hdr + $nl + $body + $script:BdMark + '-PART-END|' + $setId + '|' + $k + '|' + $n + $nl
            $pName = $base + '-' + $k.ToString('00') + 'of' + $n.ToString('00') + '.txt'
            [System.IO.File]::WriteAllText((Join-Path $oDir $pName), $txt, $utf8)
            $writtenNames += $pName
            $kb = [int][Math]::Ceiling($utf8.GetByteCount($txt) / 1024.0)
            if ($kb -gt $maxKB) { $maxKB = $kb }
        }
        $partMsg = '分 ' + $n + ' 份（最大一份 ' + $maxKB + ' KB；上限 ' + $PartKB + ' KB，單一檔超過上限時自成一份）'
    }
    # 同名的舊份、舊式單一檔：不在這次寫出的清單就刪掉（份數變少時不留殘份）
    foreach ($f in @(Get-ChildItem -LiteralPath $oDir -File)) {
        if (($f.Name -match $partRx -or $f.Name -eq $oName) -and $writtenNames -notcontains $f.Name) { Remove-Item -LiteralPath $f.FullName -Force }
    }
    Write-Host ('已寫入搬運包（' + $variant + '）：' + $items.Count + ' 檔、必刪舊檔 ' + $removedCount + ' 個；' + $partMsg) -ForegroundColor Green
    exit 0
}

# ── 解開（公司機）────────────────────────────────────────────────
$argList = @()
foreach ($b in $Bundle) { foreach ($s in ([string]$b).Split(',')) { $t = $s.Trim(); if ($t -ne '') { $argList += $t } } }
if ($argList.Count -eq 0) { Write-Host '用法：-Bundle <放各份的資料夾｜其中一份｜舊式單一搬運包> [-DryRun] [-Root <專案根>]' -ForegroundColor Red; exit 2 }
if ($Root -eq '') {
    if ((Split-Path $PSScriptRoot -Leaf) -ne 'scripts') { Write-Host ('本檔要放在 <專案>\scripts\ 底下執行（目前位置：' + $PSScriptRoot + '），或用 -Root 指定專案根') -ForegroundColor Red; exit 2 }
    $Root = Split-Path $PSScriptRoot -Parent
}
function Stop-Bundle([string]$Code, [string]$Text) {
    Write-Host ('  !! ' + $Text) -ForegroundColor Red
    Write-Host ('結論代號：' + $Code) -ForegroundColor Cyan
    Write-Host '（一個檔都沒寫。回報維護 session 只需要這一行的代號）'
    exit 1
}
# 讀一個來源檔：裡面的每一份（一個檔可放一份或幾份），以及它是不是舊式單一搬運包。回 @{ Parts; Classic }
function Read-PsBdSource([string]$Path) {
    $text = Read-PsBdText $Path
    if ($text.Length -gt 0 -and [int]$text[0] -eq 0xFEFF) { $text = $text.Substring(1) }
    $ls = $text.Replace("`r`n", "`n").Replace("`r", "`n") -split "`n"
    $found = New-Object System.Collections.ArrayList
    $hasHead = $false
    $i = 0
    while ($i -lt $ls.Count) {
        $ln = $ls[$i]
        if ($ln.StartsWith($script:BdMark + '|')) { $hasHead = $true }
        if (-not $ln.StartsWith($script:BdMark + '-PART|')) { $i++; continue }
        $h = $ln.Split('|')
        $p = @{ Source = $Path; Closed = $false; Lines = @(); Set = ''; Variant = ''; Commit = ''; ExpSha = '' }
        $k = 0; $n = 0; $el = -1
        if ($h.Count -ge 9 -and $h[1] -eq '1') {
            [void][int]::TryParse($h[5], [ref]$k)
            [void][int]::TryParse($h[6], [ref]$n)
            [void][int]::TryParse($h[7], [ref]$el)
            $p.Variant = $h[2]; $p.Commit = $h[3]; $p.Set = $h[4]; $p.ExpSha = $h[8]
        }
        else { $p.Bad = $true }
        $p.K = $k; $p.N = $n; $p.ExpLines = $el
        $endTag = $script:BdMark + '-PART-END|' + $p.Set + '|' + $k + '|' + $n
        $body = New-Object System.Collections.Generic.List[string]
        $j = $i + 1
        while ($j -lt $ls.Count -and $ls[$j] -cne $endTag -and -not $ls[$j].StartsWith($script:BdMark + '-PART')) { $body.Add($ls[$j]); $j++ }
        $p.Lines = $body.ToArray()
        if ($j -lt $ls.Count -and $ls[$j] -ceq $endTag) { $p.Closed = $true; $j++ }
        [void]$found.Add($p)
        $i = $j
    }
    return @{ Parts = $found.ToArray(); Classic = ($hasHead -and $found.Count -eq 0) }
}
# 一份是否完整：'' ＝通過；否則「代號|原因」
function Test-PsBdPart($P) {
    if ($P.ContainsKey('Bad')) { return 'T|標頭格式不符' }
    if (-not $P.Closed) { return 'T|沒有最後一行 @@@PSBUNDLE-PART-END（貼上被截斷）' }
    $cnt = @($P.Lines).Count
    if ($cnt -ne $P.ExpLines) { return ('T|行數不符（應 ' + $P.ExpLines + '、實得 ' + $cnt + '，貼上被截斷或多貼了）') }
    if ((Get-PsBdSha (([string]::Join("`n", [string[]]$P.Lines)) + "`n")) -ne $P.ExpSha) { return 'H|內容雜湊不符' }
    return ''
}
Write-Host '=== ps-bundle：解開搬運包 ===' -ForegroundColor Cyan

# 0) 找搬運包：給的是資料夾就讀裡面的 .txt；給的是檔案就讀它，分份不齊時再到同資料夾找同一組的其他份
$explicit = @()
$dirs = @()
foreach ($a in $argList) {
    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($a)
    if ([System.IO.Directory]::Exists($full)) { $dirs += $full }
    elseif ([System.IO.File]::Exists($full)) { $explicit += $full }
    else { Stop-Bundle 'T' ('找不到搬運包：' + $a) }
}
$parts = @()
$classic = @()
$seen = @{}
$queue = New-Object System.Collections.Generic.List[string]
foreach ($e in $explicit) { $queue.Add($e) }
foreach ($d in $dirs) { foreach ($f in @(Get-ChildItem -LiteralPath $d -File -Filter '*.txt' | Sort-Object Name)) { $queue.Add($f.FullName) } }
foreach ($src in $queue) {
    if ($seen.ContainsKey($src)) { continue }
    $seen[$src] = $true
    $rd = Read-PsBdSource $src
    foreach ($p in $rd.Parts) { $parts += $p }
    if ($rd.Classic) { $classic += $src }
}
$setId = ''
if ($parts.Count -gt 0) {
    $named = @{}
    foreach ($p in $parts) { if ($explicit -contains $p.Source -and -not $p.ContainsKey('Bad')) { $named[$p.Set] = $true } }
    if ($named.Count -gt 1) { Stop-Bundle 'T' '指名的檔案混了不同次打包的份——只給同一次打包的各份' }
    if ($named.Count -eq 1) {
        $setId = @($named.Keys)[0]
        $have = @{}
        $total = 0
        foreach ($p in $parts) { if ($p.Set -eq $setId) { $have[[int]$p.K] = $true; $total = [int]$p.N } }
        # 指名的檔不夠一整組：到同資料夾找同一組的其他份
        if ($have.Count -lt $total) {
            foreach ($e in $explicit) {
                foreach ($f in @(Get-ChildItem -LiteralPath (Split-Path $e -Parent) -File -Filter '*.txt' | Sort-Object Name)) {
                    if ($seen.ContainsKey($f.FullName)) { continue }
                    $seen[$f.FullName] = $true
                    $rd = Read-PsBdSource $f.FullName
                    foreach ($p in $rd.Parts) { if ($p.Set -eq $setId) { $parts += $p } }
                }
            }
        }
    }
    else {
        $sets = @{}
        foreach ($p in $parts) { if (-not $p.ContainsKey('Bad')) { $sets[$p.Set] = $true } }
        if ($sets.Count -gt 1) {
            Write-Host ('  !! 資料夾裡有 ' + $sets.Count + ' 組不同次打包的搬運包：') -ForegroundColor Red
            foreach ($sid in @($sets.Keys | Sort-Object)) {
                $mine = @($parts | Where-Object { $_.Set -eq $sid })
                $ks = @($mine | ForEach-Object { [int]$_.K } | Sort-Object -Unique)
                $names = @($mine | ForEach-Object { [System.IO.Path]::GetFileName($_.Source) } | Sort-Object -Unique)
                Write-Host ('     commit ' + $mine[0].Commit + '（組 ' + $sid.Substring(0, 8) + '）：第 ' + ($ks -join '、') + ' 份／共 ' + $mine[0].N + ' 份 ← ' + ($names -join '、')) -ForegroundColor Red
            }
            Stop-Bundle 'T' '只留這次要搬的那一組（或把它放進新的空資料夾）再執行'
        }
        if ($sets.Count -eq 1) { $setId = @($sets.Keys)[0] }
    }
}
if ($setId -ne '') {
    $mine = @($parts | Where-Object { $_.Set -eq $setId })
    $n = [int]$mine[0].N
    foreach ($p in $mine) { if ([int]$p.N -ne $n -or $p.Variant -ne $mine[0].Variant -or $p.Commit -ne $mine[0].Commit) { Stop-Bundle 'T' '同一組的各份標頭不一致——重新複製全部各份' } }
    if ($n -lt 1 -or $n -gt 99) { Stop-Bundle 'T' '份數不合理——重新複製全部各份' }
    $chosen = @{}
    $problems = @()
    for ($k = 1; $k -le $n; $k++) {
        $cands = @($mine | Where-Object { [int]$_.K -eq $k })
        if ($cands.Count -eq 0) { $problems += ('T|第 ' + $k + '／' + $n + ' 份：沒有找到'); continue }
        $why = ''
        foreach ($c in $cands) {
            $r = Test-PsBdPart $c
            if ($r -eq '') { $chosen[$k] = $c; break }
            if ($why -eq '') { $why = $r }
        }
        if (-not $chosen.ContainsKey($k)) { $problems += ($why.Substring(0, 1) + '|第 ' + $k + '／' + $n + ' 份（' + [System.IO.Path]::GetFileName($cands[0].Source) + '）：' + $why.Substring(2)) }
    }
    if ($problems.Count -gt 0) {
        foreach ($x in $problems) { Write-Host ('  !! ' + $x.Substring(2)) -ForegroundColor Red }
        $codes = @($problems | ForEach-Object { $_.Substring(0, 1) } | Sort-Object -Unique)
        if ($codes -contains 'T') { Write-Host '     → 沒找到或被截斷的那幾份重新複製（整份，最後一行是 @@@PSBUNDLE-PART-END）' -ForegroundColor Yellow }
        if ($codes -contains 'H') { Write-Host '     → 雜湊不符多半是另存時不是 UTF-8，或貼上時被改動；重新複製那一份' -ForegroundColor Yellow }
        Stop-Bundle ($codes -join '+') ('分份驗證失敗 ' + $problems.Count + ' 項（共 ' + $n + ' 份）')
    }
    $joined = New-Object System.Collections.Generic.List[string]
    for ($k = 1; $k -le $n; $k++) { $joined.AddRange([string[]]$chosen[$k].Lines) }
    $lines = $joined.ToArray()
    if ((Get-PsBdSha (([string]::Join("`n", $lines)) + "`n")).Substring(0, 16) -ne $setId) { Stop-Bundle 'T' '各份組不回同一個搬運包——重新複製全部各份' }
    Write-Host ('分 ' + $n + ' 份：全部到齊、逐份驗證通過')
    if ($classic.Count -gt 0) { Write-Host ('  （另有 ' + $classic.Count + ' 個舊式單一搬運包檔，已略過）') -ForegroundColor Gray }
}
else {
    if ($classic.Count -eq 0) { Stop-Bundle 'T' '找不到搬運包開頭——不是搬運包，或複製時開頭缺了' }
    if ($classic.Count -gt 1) { Stop-Bundle 'T' ('有 ' + $classic.Count + ' 個搬運包檔——只留這次要搬的那一個（或直接給那個檔）') }
    $raw = Read-PsBdText $classic[0]
    if ($raw.Length -gt 0 -and [int]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
    $lines = $raw.Replace("`r`n", "`n").Replace("`r", "`n") -split "`n"
}

# 1) 解析＋整包驗證（全部在記憶體；任何錯都不寫檔）
$i = 0
while ($i -lt $lines.Count -and -not $lines[$i].StartsWith($script:BdMark + '|')) { $i++ }
if ($i -ge $lines.Count) { Stop-Bundle 'T' '找不到搬運包開頭——不是搬運包，或複製時開頭缺了' }
$head = $lines[$i].Split('|')
if ($head.Count -lt 5 -or $head[1] -ne '1') { Stop-Bundle 'T' '搬運包格式版本不符——請改用同一個 commit 的 scripts\ps-bundle.ps1' }
$variant = $head[2]
if (-not $script:BdPrefixes.ContainsKey($variant)) { Stop-Bundle 'T' ('不認得的版本：' + $variant) }
$commit = $head[3]
$expectCount = 0
[void][int]::TryParse($head[4], [ref]$expectCount)
$i++
$removed = @()
$files = @()
$eof = $null
$bad = @()
while ($i -lt $lines.Count) {
    $ln = $lines[$i]
    if ($ln.StartsWith($script:BdMark + '-REMOVED|')) { $removed += $ln.Substring(($script:BdMark + '-REMOVED|').Length); $i++; continue }
    if ($ln.StartsWith($script:BdMark + '-EOF|')) { $eof = $ln.Split('|'); break }
    if ($ln.StartsWith($script:BdMark + '-FILE|')) {
        $h = $ln.Split('|')
        if ($h.Count -lt 5) { Stop-Bundle 'T' ('檔頭格式壞了（第 ' + ($i + 1) + ' 行）') }
        $path = $h[1]
        $endTag = $script:BdMark + '-END|' + $path
        $j = $i + 1
        $body = New-Object System.Collections.Generic.List[string]
        while ($j -lt $lines.Count -and $lines[$j] -ne $endTag) {
            if ($lines[$j].StartsWith($script:BdMark)) { break }
            $body.Add($lines[$j]); $j++
        }
        if ($j -ge $lines.Count -or $lines[$j] -ne $endTag) { Stop-Bundle 'T' ('檔案區塊沒有結尾標記：' + $path + '——貼上被截斷或被改過，重新複製整份搬運包') }
        $norm = Get-PsBdNorm ([string]::Join("`n", $body.ToArray()))
        $files += @{ Path = $path; Lines = [int]$h[2]; Sha = $h[3]; Bom = ($h[4] -eq '1'); Norm = $norm; ActualSha = (Get-PsBdSha $norm); ActualLines = (Get-PsBdLineCount $norm) }
        $i = $j + 1
        continue
    }
    $i++
}
if ($null -eq $eof) { Stop-Bundle 'T' '找不到搬運包結尾——複製時後段被截斷，重新複製整份' }
$agg = New-Object System.Text.StringBuilder
foreach ($f in $files) { [void]$agg.Append($f.Path).Append("`n").Append($f.Sha).Append("`n") }
if ($files.Count -ne $expectCount -or [string]$eof[1] -ne [string]$files.Count -or [string]$eof[2] -ne (Get-PsBdSha $agg.ToString())) { Stop-Bundle 'T' ('檔數或總雜湊不符（開頭 ' + $expectCount + '、實得 ' + $files.Count + '）——搬運包不完整或被改過') }
foreach ($f in $files) {
    $p = $f.Path
    $okPath = ($p -match '^[A-Za-z0-9_.][A-Za-z0-9_./-]*$') -and ($p -notmatch '(^|/)\.\.?(/|$)') -and ($p -notmatch '//')
    $okPrefix = $false
    foreach ($pre in $script:BdPrefixes[$variant]) { if ($p -ceq $pre -or ($pre.EndsWith('/') -and $p.StartsWith($pre))) { $okPrefix = $true } }
    if (-not ($okPath -and $okPrefix)) { $bad += ('P|' + $p) }
    elseif ($f.ActualSha -ne $f.Sha -or $f.ActualLines -ne $f.Lines) { $bad += ('H|' + $p) }
}
foreach ($r in $removed) {
    $okR = ($r -match '^[A-Za-z0-9_.][A-Za-z0-9_./-]*$') -and ($r -notmatch '(^|/)\.\.?(/|$)') -and ($r -notmatch '//')
    $okPrefix = $false
    foreach ($pre in $script:BdPrefixes[$variant]) { if ($r -ceq $pre -or ($pre.EndsWith('/') -and $r.StartsWith($pre))) { $okPrefix = $true } }
    if (-not ($okR -and $okPrefix)) { $bad += ('P|' + $r) }
}
if ($bad.Count -gt 0) {
    $codes = @($bad | ForEach-Object { $_.Split('|')[0] } | Sort-Object -Unique)
    foreach ($b in $bad) {
        $kind = '內容雜湊不符'
        if ($b.StartsWith('P|')) { $kind = '路徑不合法（拒絕）' }
        Write-Host ('  !! ' + $kind + '：' + $b.Substring(2)) -ForegroundColor Red
    }
    if ($codes -contains 'H') { Write-Host '     → 多半是另存時不是 UTF-8（記事本選「UTF-8」），或貼上時被改動；重新複製整份再試' -ForegroundColor Yellow }
    Stop-Bundle ($codes -join '+') ('驗證失敗 ' + $bad.Count + ' 項')
}
Write-Host ('搬運包：' + $variant + ' 版、commit ' + $commit + '、' + $files.Count + ' 檔、必刪舊檔 ' + $removed.Count + ' 個（整包驗證通過）')

# 2) 三方比對：本機現況／上次 manifest 記錄（基準）／搬運包
$base = @{}
$other = 'opencode'
if ($variant -eq 'opencode') { $other = 'claude' }
foreach ($v in @($variant, $other)) {
    $mp = Join-Path $Root (Join-Path 'scripts' $script:BdManifestNames[$v])
    if (-not (Test-Path -LiteralPath $mp)) { continue }
    $old = $null
    try { $old = (Read-PsBdText $mp) | ConvertFrom-Json } catch { continue }
    foreach ($e in @($old.files)) {
        $k = [string]$e.path
        if ($base.ContainsKey($k)) { continue }
        if ($v -ne $variant -and -not $k.StartsWith('scripts/')) { continue }
        $base[$k] = [string]$e.sha256
    }
}
$myManifest = 'scripts/' + $script:BdManifestNames[$variant]
$plan = @()
foreach ($f in $files) {
    $full = Join-Path $Root $f.Path
    $act = ''
    if (-not [System.IO.File]::Exists($full)) { $act = 'NEW' }
    else {
        $localSha = Get-PsBdSha (Get-PsBdNorm (Read-PsBdText $full))
        if ($localSha -eq $f.Sha) { $act = 'SAME' }
        elseif ($f.Path -eq $myManifest -or $f.Path.StartsWith('scripts/')) { $act = 'UPDATE' }
        elseif ($base.ContainsKey($f.Path)) {
            if ($localSha -eq $base[$f.Path]) { $act = 'UPDATE' }
            elseif ($f.Sha -eq $base[$f.Path]) { $act = 'KEEP' }
            else { $act = 'CONFLICT' }
        }
        elseif ($f.Path -match $script:BdProtected) { $act = 'CONFLICT' }
        else { $act = 'UPDATE' }
    }
    $plan += @{ F = $f; Act = $act; Full = $full }
}
$dels = @()
foreach ($r in $removed) { $rf = Join-Path $Root $r; if ([System.IO.File]::Exists($rf)) { $dels += @{ Path = $r; Full = $rf } } }
$label = @{ NEW = '新增'; UPDATE = '更新'; SAME = '相同'; KEEP = '保留本機'; CONFLICT = '衝突' }
foreach ($a in @('NEW', 'UPDATE', 'KEEP', 'CONFLICT')) {
    foreach ($x in @($plan | Where-Object { $_.Act -eq $a })) {
        $color = 'Gray'
        if ($a -eq 'CONFLICT') { $color = 'Yellow' }
        Write-Host ('  ' + $label[$a] + '：' + $x.F.Path) -ForegroundColor $color
    }
}
foreach ($d in $dels) { Write-Host ('  刪除（舊檔）：' + $d.Path) }
$count = @{}
foreach ($a in @('NEW', 'UPDATE', 'SAME', 'KEEP', 'CONFLICT')) { $count[$a] = @($plan | Where-Object { $_.Act -eq $a }).Count }
$summary = '新增 ' + $count.NEW + '／更新 ' + $count.UPDATE + '／相同 ' + $count.SAME + '／保留本機 ' + $count.KEEP + '／衝突 ' + $count.CONFLICT + '／刪除 ' + $dels.Count
if ($DryRun) {
    Write-Host ('計畫（-DryRun，沒有寫任何檔）：' + $summary) -ForegroundColor Cyan
    exit 0
}

# 3) 執行：備份 → 寫入（manifest 最後）→ 逐檔回讀驗證
$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture)
$backupRoot = Join-Path $Root (Join-Path 'auto-loop-logs' (Join-Path 'ps-bundle-backup' $stamp))
function Backup-PsBdFile([string]$Rel, [string]$Full) {
    $dst = Join-Path $backupRoot $Rel
    $dd = Split-Path $dst -Parent
    if (-not (Test-Path -LiteralPath $dd)) { New-Item -ItemType Directory -Path $dd -Force | Out-Null }
    Copy-Item -LiteralPath $Full -Destination $dst -Force
}
function Write-PsBdFile([string]$Full, [string]$Norm, [bool]$Bom) {
    $dir = Split-Path $Full -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $text = $Norm.Replace("`n", "`r`n")
    $tmp = $Full + '.bundle-tmp'
    [System.IO.File]::WriteAllText($tmp, $text, (New-Object System.Text.UTF8Encoding($Bom)))
    if ([System.IO.File]::Exists($Full)) { [System.IO.File]::Delete($Full) }
    [System.IO.File]::Move($tmp, $Full)
}
$writeBad = @()
$ordered = @($plan | Where-Object { $_.F.Path -ne $myManifest }) + @($plan | Where-Object { $_.F.Path -eq $myManifest })
foreach ($x in $ordered) {
    $f = $x.F
    if ($x.Act -eq 'SAME' -or $x.Act -eq 'KEEP') { continue }
    if ($x.Act -eq 'CONFLICT') { Write-PsBdFile ($x.Full + '.incoming') $f.Norm $f.Bom; continue }
    if ($x.Act -eq 'UPDATE') { Backup-PsBdFile $f.Path $x.Full }
    Write-PsBdFile $x.Full $f.Norm $f.Bom
    $chk = Get-PsBdSha (Get-PsBdNorm (Read-PsBdText $x.Full))
    if ($chk -ne $f.Sha) { $writeBad += $f.Path }
}
foreach ($d in $dels) {
    Backup-PsBdFile $d.Path $d.Full
    Remove-Item -LiteralPath $d.Full -Force
}
Write-Host ('完成：' + $summary) -ForegroundColor Green
if (($count.UPDATE + $dels.Count) -gt 0) { Write-Host ('  被覆寫／刪除的舊檔已備份：' + $backupRoot) }
if ($count.CONFLICT -gt 0) { Write-Host '  衝突檔：本機版本沒動，新版另存為「<檔>.incoming」——人工比對合併後刪掉 .incoming' -ForegroundColor Yellow }
if ($count.KEEP -gt 0) { Write-Host '  保留本機：這些檔你本機改過、這次搬運包沒動它們，原樣保留（ps-fs-doctor 會把它們列為版本不符，屬正常）' }
foreach ($w in $writeBad) { Write-Host ('  !! 寫入後驗證失敗：' + $w) -ForegroundColor Red }
$codes = @()
if ($writeBad.Count -gt 0) { $codes += 'W' }
if ($count.CONFLICT -gt 0) { $codes += 'C' }
if ($codes.Count -eq 0) { $codes = @('G') }
Write-Host '下一步：powershell -NoProfile -File .\scripts\ps-fs-doctor.ps1（Claude Code 版另跑 scripts\ps-claude-doctor.ps1）'
Write-Host ('結論代號：' + ($codes -join '+')) -ForegroundColor Cyan
Write-Host '（回報維護 session 只需要這一行的代號）'
if ($writeBad.Count -gt 0) { exit 1 }
exit 0
