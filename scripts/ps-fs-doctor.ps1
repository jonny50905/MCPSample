# ps-fs-doctor.ps1 — 檔案系統健檢：搬運完整性／隱形字元／雙胞胎資料夾／假缺檔（唯讀）
# 情境：lint 報「缺 00-overview.md」但 Explorer 看得到檔案——Windows 上這種
# 「看得到、程式找不到」幾乎都是隱形字元（FEFF/零寬空格）或雙副檔名。
# 用法：powershell -File .\scripts\ps-fs-doctor.ps1                     ← 搬完檔跑這個（檢查 M/D/S）
#       powershell -File .\scripts\ps-fs-doctor.ps1 -Domain <領域>      ← 加驗領域目錄（領域名手打，不要貼上）
#       加 -FixBom 會順手修 scripts\*.ps1 的「內文開頭 FEFF」（雙 BOM 病），其餘一律唯讀。
#       -WriteManifest 是**維護 session 專用**（重生搬運基準）——公司機不要跑，
#       跑了＝拿本地現況蓋掉基準，檢查 M 失去意義。
# 資安設計：實際路徑/檔名只印在你螢幕上；回報維護 session 只需要講最後一行的
# 「結論代號」（可複選，例：A+D），不需要貼任何輸出。
# 注意：若跑本腳本也出現「'#' 不是 cmdlet…」紅字＝本腳本自己也被雙 BOM 污染
# （搬運鏈通病），該紅字只影響第 1 行註解、不影響診斷結果。
param(
    [string]$Domain = "",
    [switch]$FixBom,
    [switch]$WriteManifest
)

$root = Split-Path $PSScriptRoot -Parent
$researchRoot = Join-Path $root (Join-Path "docs" "ps-research")
$dir = Join-Path $researchRoot $Domain
$findings = @()

function Get-CharCodes([string]$s) {
    return (($s.ToCharArray() | ForEach-Object { [int]$_ }) -join ',')
}
function Test-HasInvisible([string]$s) {
    foreach ($ch in $s.ToCharArray()) {
        $cp = [int]$ch
        if ($cp -lt 32 -or $cp -eq 127 -or $cp -eq 0x00A0 -or
            ($cp -ge 0x200B -and $cp -le 0x200F) -or $cp -eq 0xFEFF) { return $true }
    }
    return $false
}

# ── 搬運 manifest（檢查 M）——維護 session 每批 push 前重生、公司機只讀。
# 雜湊對「正規化內容」計算：剝 BOM、換行統一 LF、檔尾空白裁掉——
# GitHub Raw 複製到 Windows 另存造成的行尾／BOM 差異不誤報，
# 內容差一個字就會報。範圍＝scripts＋.opencode 全樹（框架的全部）。
$manifestPath = Join-Path $root (Join-Path "scripts" "ps-transfer-manifest.json")

function Get-NormalizedInfo([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($text.Length -gt 0 -and [int]$text[0] -eq 0xFEFF) { $text = $text.Substring(1) }
    $text = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    $text = ($text -replace '\s+$', '') + "`n"
    $lines = @($text -split "`n").Count - 1
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = ((@($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text)) | ForEach-Object { $_.ToString('x2') })) -join '')
    $sha.Dispose()
    return @{ Lines = $lines; Sha = $hash; Bom = $hasBom }
}

function Get-TransferFiles {
    $list = @()
    $sDir = Join-Path $root "scripts"
    if (Test-Path -LiteralPath $sDir) {
        $list += @(Get-ChildItem -LiteralPath $sDir -File -Recurse |
                Where-Object { $_.Name -ne 'ps-transfer-manifest.json' })
    }
    $ocDir = Join-Path $root ".opencode"
    if (Test-Path -LiteralPath $ocDir) {
        $list += @(Get-ChildItem -LiteralPath $ocDir -File -Recurse)
    }
    return $list
}

function Get-RelPath([string]$Full) {
    $p = $Full.Substring($root.Length).TrimStart('\', '/')
    return ($p -replace '\\', '/')
}

if ($WriteManifest) {
    $entries = @()
    foreach ($f in (Get-TransferFiles | Sort-Object FullName)) {
        $n = Get-NormalizedInfo $f.FullName
        $entries += [pscustomobject]@{
            path   = (Get-RelPath $f.FullName)
            lines  = $n.Lines
            sha256 = $n.Sha
            bom    = [bool]($f.Extension -eq '.ps1' -and $n.Bom)
        }
    }
    $commit = "unknown"
    try {
        $g = (& git -C $root rev-parse --short HEAD 2>$null | Out-String).Trim()
        if ($g) { $commit = $g }
    }
    catch { }
    $doc = [pscustomobject]@{
        note   = "維護 session 每批 push 前重生；公司機只讀不寫。搬運清單必含本檔。"
        commit = $commit
        files  = $entries
    }
    [System.IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $doc -Depth 4),
        (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("已寫入 manifest：" + $entries.Count + " 檔（commit " + $commit + "）") -ForegroundColor Green
    exit 0
}

Write-Host "=== ps-fs-doctor：檔案系統健檢（唯讀） ===" -ForegroundColor Cyan

# M) 搬運完整性——漏搬／版本不符／搬壞／BOM 缺，逐檔點名
Write-Host "[檢查 M] 搬運完整性（scripts＋.opencode 全樹對照 manifest）"
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Write-Host "  !! 找不到 scripts\ps-transfer-manifest.json——manifest 本身也在搬運清單內，先搬它再重跑" -ForegroundColor Red
    $findings += 'M'
}
else {
    $mf = $null
    try { $mf = (Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { }
    if ($null -eq $mf -or $null -eq $mf.files) {
        Write-Host "  !! manifest 解析失敗——該檔搬壞了，重新複製整檔" -ForegroundColor Red
        $findings += 'M'
    }
    else {
        $mMissing = 0; $mMismatch = 0; $mBomBad = 0; $mExtra = 0
        $known = @{}
        foreach ($e in @($mf.files)) {
            $known[[string]$e.path] = $true
            $full = Join-Path $root ([string]$e.path)
            if (-not [System.IO.File]::Exists($full)) {
                Write-Host ("  !! 漏搬：" + $e.path + "（應為 " + $e.lines + " 行）") -ForegroundColor Red
                $mMissing++; continue
            }
            $n = Get-NormalizedInfo $full
            if ($n.Sha -ne [string]$e.sha256) {
                $hint = ""
                if ([int]$e.lines -eq $n.Lines) { $hint = "——行數同、內容異（多半是搬到舊版）" }
                Write-Host ("  !! 版本不符/搬壞：" + $e.path + "（基準 " + $e.lines + " 行，現況 " + $n.Lines + " 行" + $hint + "）") -ForegroundColor Red
                $mMismatch++
            }
            if ([bool]$e.bom -and -not $n.Bom) {
                Write-Host ("  !! BOM 缺失：" + $e.path + "（.ps1 要存 UTF-8 with BOM）") -ForegroundColor Red
                $mBomBad++
            }
        }
        foreach ($f in (Get-TransferFiles)) {
            $rp = Get-RelPath $f.FullName
            if (-not $known.ContainsKey($rp)) {
                Write-Host ("  ?? 未列管的多出檔：" + $rp + "（舊檔未刪或誤放——建議清掉）") -ForegroundColor Yellow
                $mExtra++
            }
        }
        if (($mMissing + $mMismatch + $mBomBad) -gt 0) {
            $findings += 'M'
            Write-Host ("  小結：漏搬 " + $mMissing + "／版本不符 " + $mMismatch + "／BOM 缺 " + $mBomBad + "（基準 commit " + $mf.commit + "）") -ForegroundColor Red
        }
        else {
            Write-Host ("  全部 " + @($mf.files).Count + " 檔與基準一致（commit " + $mf.commit + "）") -ForegroundColor Green
        }
        if ($mExtra -gt 0) { $findings += 'X' }
    }
}

# F) 這次輸入的 -Domain 參數本身（未指定＝只做搬運與腳本健檢，跳過領域類）
if ($Domain -eq "") {
    Write-Host "[檢查 F/A/B] 未指定 -Domain——跳過領域檢查（加 -Domain <領域> 可加驗）"
}
else {
    Write-Host ("[檢查 F] -Domain 參數字元碼：[" + (Get-CharCodes $Domain) + "]")
    if (Test-HasInvisible $Domain) {
        Write-Host "  !! 參數本身含隱形字元——這次輸入就被污染了；用鍵盤手打重跑" -ForegroundColor Red
        $findings += 'F'
    }
    else { Write-Host "  參數乾淨" -ForegroundColor Green }
}

# C) 領域資料夾雙胞胎／資料夾名異常
Write-Host "[檢查 C] docs\ps-research 底下的資料夾名"
if (Test-Path -LiteralPath $researchRoot) {
    $groups = @{}
    foreach ($d0 in (Get-ChildItem -LiteralPath $researchRoot -Directory -Force)) {
        if (Test-HasInvisible $d0.Name) {
            Write-Host ("  !! 資料夾名含隱形字元：" + $d0.Name + "  [" + (Get-CharCodes $d0.Name) + "]") -ForegroundColor Red
            $findings += 'C'
        }
        $stripped = ""
        foreach ($ch in $d0.Name.ToCharArray()) {
            if (-not (Test-HasInvisible ([string]$ch))) { $stripped += $ch }
        }
        $key = $stripped.ToLowerInvariant()
        if (-not $groups.ContainsKey($key)) { $groups[$key] = @() }
        $groups[$key] += $d0.Name
    }
    foreach ($k in $groups.Keys) {
        if ($groups[$k].Count -gt 1) {
            Write-Host ("  !! 雙胞胎資料夾（去隱形字元後同名）：" + ($groups[$k] -join "  |  ")) -ForegroundColor Red
            $findings += 'C'
        }
    }
    if (-not ($findings -contains 'C')) { Write-Host "  無雙胞胎、名稱皆乾淨" -ForegroundColor Green }
}
else {
    Write-Host "  !! docs\ps-research 不存在——root 解析可能不對（腳本要放在 repo 的 scripts\ 底下跑）" -ForegroundColor Red
    $findings += 'E'
}

# A/B/E) 00-overview.md 與領域內全部檔名
if ($Domain -ne "") {
Write-Host "[檢查 A/B] 領域目錄與 00-overview.md"
if (-not (Test-Path -LiteralPath $dir)) {
    Write-Host "  !! 領域目錄不存在（-LiteralPath 精確比對）——參數與實際資料夾名對不上（配合檢查 C/F 判讀）" -ForegroundColor Red
    $findings += 'E'
}
else {
    if ([System.IO.File]::Exists((Join-Path $dir "00-overview.md"))) {
        Write-Host "  00-overview.md 精確檔名存在 → lint 的『缺』是假缺" -ForegroundColor Green
        $findings += 'A'
    }
    else {
        $cands = @(Get-ChildItem -LiteralPath $dir -Force -File | Where-Object { $_.Name -like "*overview*" })
        if ($cands.Count -gt 0) {
            foreach ($c in $cands) {
                Write-Host ("  !! 找到變體檔名：" + $c.Name + "  [" + (Get-CharCodes $c.Name) + "]") -ForegroundColor Red
            }
            $findings += 'B'
        }
        else {
            Write-Host "  !! 00-overview 連變體都找不到——真缺檔（走 SOP-4 內部 git 還原）" -ForegroundColor Red
            $findings += 'E'
        }
    }
    foreach ($f in (Get-ChildItem -LiteralPath $dir -Force -File)) {
        if (Test-HasInvisible $f.Name) {
            Write-Host ("  !! 檔名含隱形字元：" + $f.Name + "  [" + (Get-CharCodes $f.Name) + "]") -ForegroundColor Red
            $findings += 'B'
        }
    }
}
}

# D) 內文 FEFF 掃描（scripts\*.ps1 全部＋領域內 *.md）——BOM 之外內文不該有 FEFF
Write-Host "[檢查 D] 內文 FEFF（雙 BOM 病）掃描"
$scanFiles = @()
$scanFiles += @(Get-ChildItem -LiteralPath (Join-Path $root "scripts") -Filter "*.ps1" -File)
if ($Domain -ne "" -and (Test-Path -LiteralPath $dir)) {
    $scanFiles += @(Get-ChildItem -LiteralPath $dir -Filter "*.md" -File)
}
$dFound = $false
foreach ($f in $scanFiles) {
    $t = [System.IO.File]::ReadAllText($f.FullName)   # 檔頭正規 BOM 會被剝掉，剝完仍見 FEFF＝內文污染
    $ix = $t.IndexOf([char]0xFEFF)
    if ($ix -ge 0) {
        $dFound = $true
        Write-Host ("  !! 內文含 FEFF：" + $f.Name + "（位置 " + $ix + "）") -ForegroundColor Red
        if ($f.Extension -eq '.ps1' -and $ix -eq 0) {
            Write-Host "     ↑ 雙 BOM：症狀依檔案結構而異——檔首是註解→執行期「'#' 不是 cmdlet」；" -ForegroundColor Yellow
            Write-Host "       檔首註解後接 param()→**解析期 InvalidLeftHandSide**（param 不再是第一個語句）。加 -FixBom 修" -ForegroundColor Yellow
        }
        $findings += 'D'
        if ($FixBom -and $f.Extension -eq '.ps1' -and $ix -eq 0) {
            [System.IO.File]::WriteAllText($f.FullName, $t.TrimStart([char]0xFEFF),
                (New-Object System.Text.UTF8Encoding($true)))
            Write-Host ("     已修復（去內文開頭 FEFF、重存單一 BOM）：" + $f.Name) -ForegroundColor Yellow
        }
    }
}
if (-not $dFound) { Write-Host "  全部乾淨" -ForegroundColor Green }

# S) 腳本語法與行數（搬運完整性）——貼上被截斷／中文字串壞掉會在這裡現形
Write-Host "[檢查 S] scripts\*.ps1 語法解析與行數（搬運完整性）"
$sBad = $false
foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $root "scripts") -Filter "*.ps1" -File)) {
    $lineCount = @([System.IO.File]::ReadAllLines($f.FullName)).Count
    $errs = $null
    $toks = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$toks, [ref]$errs)
    if ($errs.Count -gt 0) {
        $sBad = $true
        $findings += 'S'
        Write-Host ("  !! " + $f.Name + "（" + $lineCount + " 行）解析失敗 " + $errs.Count + " 項：") -ForegroundColor Red
        foreach ($e in ($errs | Select-Object -First 3)) {
            Write-Host ("     行 " + $e.Extent.StartLineNumber + " 欄 " + $e.Extent.StartColumnNumber + "：" + $e.Message)
        }
        Write-Host "     → 搬運不完整／貼上被截斷或中文字串壞掉：重新從 GitHub Raw 複製整檔（存 UTF-8 with BOM）" -ForegroundColor Yellow
    }
    else {
        Write-Host ("  OK  " + $f.Name + "（" + $lineCount + " 行——對照維護 session 給的搬運清單行數）")
    }
}
if (-not $sBad) { Write-Host "  全部可解析" -ForegroundColor Green }

# 結論
$codes = @($findings | Sort-Object -Unique)
if ($codes.Count -eq 0) { $codes = @('G') }
Write-Host ""
Write-Host "代號說明：A=00-overview 其實存在（假缺：當時 lint 的 -Domain 輸入被污染，手打參數重跑）"
Write-Host "          B=檔名異常（變體/隱形字元，照上面列的檔改名）  C=資料夾雙胞胎/資料夾名異常"
Write-Host "          D=內文 FEFF 污染（.ps1 可加 -FixBom 自動修）  E=真缺檔或路徑對不上（SOP-4）"
Write-Host "          F=這次輸入的參數含隱形字元  S=腳本語法解析失敗（搬運不完整，重新複製整檔）"
Write-Host "          M=搬運不完整（漏搬/版本不符/搬壞/BOM 缺——照檢查 M 列的檔逐一重搬）"
Write-Host "          X=多出未列管檔（舊檔未刪或誤放，建議清掉）"
Write-Host "          G=全部正常（另有原因，回報後續查）"
Write-Host ("結論代號：" + ($codes -join '+')) -ForegroundColor Cyan
Write-Host "（回報維護 session 只需要這一行的代號，其他內容不用貼出來）"
