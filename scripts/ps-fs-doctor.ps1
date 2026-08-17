# ps-fs-doctor.ps1 — 檔案系統健檢：隱形字元／雙胞胎資料夾／假缺檔診斷（唯讀）
# 情境：lint 報「缺 00-overview.md」但 Explorer 看得到檔案——Windows 上這種
# 「看得到、程式找不到」幾乎都是隱形字元（FEFF/零寬空格）或雙副檔名。
# 用法：powershell -File .\scripts\ps-fs-doctor.ps1 -Domain <領域>（領域名用手打，不要貼上）
#       加 -FixBom 會順手修 scripts\*.ps1 的「內文開頭 FEFF」（雙 BOM 病），其餘一律唯讀。
# 資安設計：實際路徑/檔名只印在你螢幕上；回報維護 session 只需要講最後一行的
# 「結論代號」（可複選，例：A+D），不需要貼任何輸出。
# 注意：若跑本腳本也出現「'#' 不是 cmdlet…」紅字＝本腳本自己也被雙 BOM 污染
# （搬運鏈通病），該紅字只影響第 1 行註解、不影響診斷結果。
param(
    [Parameter(Mandatory = $true)][string]$Domain,
    [switch]$FixBom
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

Write-Host "=== ps-fs-doctor：檔案系統健檢（唯讀） ===" -ForegroundColor Cyan

# F) 這次輸入的 -Domain 參數本身
Write-Host ("[檢查 F] -Domain 參數字元碼：[" + (Get-CharCodes $Domain) + "]")
if (Test-HasInvisible $Domain) {
    Write-Host "  !! 參數本身含隱形字元——這次輸入就被污染了；用鍵盤手打重跑" -ForegroundColor Red
    $findings += 'F'
}
else { Write-Host "  參數乾淨" -ForegroundColor Green }

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

# D) 內文 FEFF 掃描（scripts\*.ps1 全部＋領域內 *.md）——BOM 之外內文不該有 FEFF
Write-Host "[檢查 D] 內文 FEFF（雙 BOM 病）掃描"
$scanFiles = @()
$scanFiles += @(Get-ChildItem -LiteralPath (Join-Path $root "scripts") -Filter "*.ps1" -File)
if (Test-Path -LiteralPath $dir) {
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

# 結論
$codes = @($findings | Sort-Object -Unique)
if ($codes.Count -eq 0) { $codes = @('G') }
Write-Host ""
Write-Host "代號說明：A=00-overview 其實存在（假缺：當時 lint 的 -Domain 輸入被污染，手打參數重跑）"
Write-Host "          B=檔名異常（變體/隱形字元，照上面列的檔改名）  C=資料夾雙胞胎/資料夾名異常"
Write-Host "          D=內文 FEFF 污染（.ps1 可加 -FixBom 自動修）  E=真缺檔或路徑對不上（SOP-4）"
Write-Host "          F=這次輸入的參數含隱形字元  G=全部正常（另有原因，回報後續查）"
Write-Host ("結論代號：" + ($codes -join '+')) -ForegroundColor Cyan
Write-Host "（回報維護 session 只需要這一行的代號，其他內容不用貼出來）"
