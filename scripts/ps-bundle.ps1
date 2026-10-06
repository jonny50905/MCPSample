# ps-bundle.ps1 — 搬運包：把一個版本要搬的檔全部收進一個文字檔，公司機一個指令解回各檔
# 用法（公司機）：
#   powershell -NoProfile -File .\scripts\ps-bundle.ps1 -Bundle <搬運包.txt> -DryRun   ← 先看會做什麼（不寫檔）
#   powershell -NoProfile -File .\scripts\ps-bundle.ps1 -Bundle <搬運包.txt>           ← 解開
#   第一次用：本檔要先手動搬一次（之後每次搬運包都會帶新版的本檔）。本檔必須放在 <專案>\scripts\ 底下（或給 -Root）。
# 用法（維護端，由 ps-fs-doctor -WriteManifest 呼叫）：
#   pwsh -NoProfile -File scripts/ps-bundle.ps1 -Pack -Manifest scripts/ps-transfer-manifest.claude.json -Out transfer/ps-bundle-claude.txt
#
# 搬運包＝純文字：每個檔是「@@@PSBUNDLE-FILE|路徑|行數|sha256|bom」＋原文各行＋「@@@PSBUNDLE-END|路徑」；
#   開頭「@@@PSBUNDLE|1|版本|commit|檔數」，必刪舊檔「@@@PSBUNDLE-REMOVED|路徑」，結尾「@@@PSBUNDLE-EOF|檔數|總雜湊」。
#   雜湊與 ps-fs-doctor 同一套正規化（剝 BOM、換行統一 LF、檔尾空白裁掉）——記事本另存的 CRLF／BOM 不影響。
# 解開前整包先驗：缺開頭／結尾（貼上被截斷）、檔數或總雜湊不符、任一檔雜湊不符、路徑不合法 → 一個檔都不寫。
# 逐檔決定（三方比對：本機現況／上次搬入時的 manifest 記錄／搬運包）：
#   新增＝本機沒有；相同＝本機已一致；更新＝本機沒改過（＝上次 manifest 記錄）→ 覆寫；
#   保留本機＝本機改過、搬運包這次沒動它 → 不碰（例：已回填的 profile、/ps-lesson 改過的檔）；
#   衝突＝本機改過、搬運包也改了 → 本機不動，新版另存「<檔>.incoming」請人工合併；
#   本機設定檔（profile、domain map、研究佇列、教訓帳本）沒有 manifest 記錄可比時一律當衝突，不覆寫。
#   scripts/** 不在本機改（外環腳本只由維護端改）：內容不同一律更新（舊檔照樣備份），不走保留／衝突。
#   覆寫與刪除前先備份到 auto-loop-logs\ps-bundle-backup\<時間>\。manifest 最後才寫（中途中斷，重跑可接續）。
# 結論代號：G 全部完成／C 有衝突待合併（.incoming）／T 搬運包不完整（重新複製整檔）／H 內容雜湊不符（多半是另存成非 UTF-8）／
#   P 路徑不合法（拒絕）／W 寫入後驗證失敗。只回報代號，不貼路徑。
# PowerShell 5.1 紀律：無三元／??／&&；Join-Path 兩參數；-LiteralPath。
param(
    [string]$Bundle = '',
    [switch]$DryRun,
    [string]$Root = '',
    [switch]$Pack,
    [string]$Manifest = '',
    [string]$Out = '',
    [string[]]$Extra = @()
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
function Read-PsBdText([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return (New-Object System.Text.UTF8Encoding($false)).GetString($bytes)
}

# ── 打包（維護端）────────────────────────────────────────────────
if ($Pack) {
    if ($Root -eq '') { $Root = Split-Path $PSScriptRoot -Parent }
    if ($Manifest -eq '' -or $Out -eq '') { Write-Host '用法：-Pack -Manifest <manifest.json> -Out <搬運包.txt> [-Root <repo>] [-Extra <路徑>…]' -ForegroundColor Red; exit 2 }
    $mPath = $Manifest
    if (-not [System.IO.Path]::IsPathRooted($mPath)) { $mPath = Join-Path $Root $mPath }
    $mf = (Read-PsBdText $mPath) | ConvertFrom-Json
    $variant = 'opencode'
    if ((Split-Path $mPath -Leaf) -eq $script:BdManifestNames['claude']) { $variant = 'claude' }
    $items = @()
    foreach ($f in @($mf.files)) {
        $src = [string]$f.path
        if ($null -ne $f.PSObject.Properties['repo']) { $src = [string]$f.repo }
        $items += @{ Path = [string]$f.path; Src = (Join-Path $Root $src); Bom = [bool]$f.bom }
    }
    $items += @{ Path = ('scripts/' + (Split-Path $mPath -Leaf)); Src = $mPath; Bom = $false }
    foreach ($x in $Extra) { $items += @{ Path = $x; Src = (Join-Path $Root $x); Bom = $false } }
    $sb = New-Object System.Text.StringBuilder
    $nl = "`n"
    [void]$sb.Append('# PeopleSoft 知識庫分析框架——搬運包（' + $variant + ' 版；commit ' + [string]$mf.commit + '）').Append($nl)
    [void]$sb.Append('# 整份另存成一個 UTF-8 文字檔，用 scripts\ps-bundle.ps1 -Bundle <檔> 解開（先加 -DryRun 看計畫）。不要手改本檔。').Append($nl)
    [void]$sb.Append($script:BdMark + '|1|' + $variant + '|' + [string]$mf.commit + '|' + $items.Count).Append($nl)
    foreach ($r in @($mf.removed)) { if ($null -ne $r -and [string]$r.path -ne '') { [void]$sb.Append($script:BdMark + '-REMOVED|' + [string]$r.path).Append($nl) } }
    $agg = New-Object System.Text.StringBuilder
    foreach ($it in $items) {
        $norm = Get-PsBdNorm (Read-PsBdText $it.Src)
        foreach ($ln in ($norm -split "`n")) { if ($ln.StartsWith($script:BdMark)) { throw ('檔案內容有搬運包保留標記開頭的行，無法打包：' + $it.Path) } }
        $sha = Get-PsBdSha $norm
        $bomFlag = '0'
        if ($it.Bom) { $bomFlag = '1' }
        [void]$sb.Append($script:BdMark + '-FILE|' + $it.Path + '|' + (Get-PsBdLineCount $norm) + '|' + $sha + '|' + $bomFlag).Append($nl)
        [void]$sb.Append($norm)
        [void]$sb.Append($script:BdMark + '-END|' + $it.Path).Append($nl)
        [void]$agg.Append($it.Path).Append("`n").Append($sha).Append("`n")
    }
    [void]$sb.Append($script:BdMark + '-EOF|' + $items.Count + '|' + (Get-PsBdSha $agg.ToString())).Append($nl)
    $oPath = $Out
    if (-not [System.IO.Path]::IsPathRooted($oPath)) { $oPath = Join-Path $Root $oPath }
    $oDir = Split-Path $oPath -Parent
    if (-not (Test-Path -LiteralPath $oDir)) { New-Item -ItemType Directory -Path $oDir -Force | Out-Null }
    [System.IO.File]::WriteAllText($oPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ('已寫入搬運包（' + $variant + '）：' + $items.Count + ' 檔、必刪舊檔 ' + @($mf.removed | Where-Object { $null -ne $_ }).Count + ' 個') -ForegroundColor Green
    exit 0
}

# ── 解開（公司機）────────────────────────────────────────────────
if ($Bundle -eq '') { Write-Host '用法：-Bundle <搬運包.txt> [-DryRun] [-Root <專案根>]' -ForegroundColor Red; exit 2 }
if ($Root -eq '') {
    if ((Split-Path $PSScriptRoot -Leaf) -ne 'scripts') { Write-Host ('本檔要放在 <專案>\scripts\ 底下執行（目前位置：' + $PSScriptRoot + '），或用 -Root 指定專案根') -ForegroundColor Red; exit 2 }
    $Root = Split-Path $PSScriptRoot -Parent
}
$findings = @()
function Stop-Bundle([string]$Code, [string]$Text) {
    Write-Host ('  !! ' + $Text) -ForegroundColor Red
    Write-Host ('結論代號：' + $Code) -ForegroundColor Cyan
    Write-Host '（一個檔都沒寫。回報維護 session 只需要這一行的代號）'
    exit 1
}
if (-not (Test-Path -LiteralPath $Bundle)) { Stop-Bundle 'T' ('找不到搬運包：' + $Bundle) }
Write-Host '=== ps-bundle：解開搬運包 ===' -ForegroundColor Cyan
$raw = Read-PsBdText $Bundle
if ($raw.Length -gt 0 -and [int]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
$lines = $raw.Replace("`r`n", "`n").Replace("`r", "`n") -split "`n"

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
