# ps-doc-lint.ps1 — deep-research 文件的確定性格式稽核（第 1 層 lint）
# 用法：.\scripts\ps-doc-lint.ps1 -Domain 轉職
# 檢查：checklist 對帳、必要章節、confidence 標註、ChunkId UUID 格式、可疑自編 id
param(
    [Parameter(Mandatory = $true)][string]$Domain
)

$dir = Join-Path "docs/ps-research" $Domain
$violations = @()

if (-not (Test-Path $dir)) {
    Write-Error "目錄不存在：$dir"
    exit 2
}

$overviewPath = Join-Path $dir "00-overview.md"
if (-not (Test-Path $overviewPath)) {
    $violations += "缺 00-overview.md"
}
else {
    $overview = Get-Content $overviewPath -Raw -Encoding UTF8

    # 1) checklist 對帳：打勾項的目標檔必須存在；NN 檔必須被 checklist 列到
    $listed = @{}
    foreach ($m in [regex]::Matches($overview, '- \[(?<tick>[ x])\]\s+\S+.*?→\s*(?<file>\S+\.md)')) {
        $f = $m.Groups['file'].Value
        $listed[$f] = $true
        if ($m.Groups['tick'].Value -eq 'x' -and -not (Test-Path (Join-Path $dir $f))) {
            $violations += "checklist 已打勾但檔案不存在：$f"
        }
    }
    Get-ChildItem $dir -Filter "*.md" |
        Where-Object { $_.Name -match '^\d\d-' -and $_.Name -notmatch '^(00|90)-' } |
        ForEach-Object {
            if (-not $listed.ContainsKey($_.Name)) {
                $violations += "檔案未列於調查進度 checklist：$($_.Name)"
            }
        }
}

# 2) 每個 NN 檔的內容檢查
$requiredSections = @('## 功能定位', '## 行為邏輯', '## 資料流', '## 未解事項', '## Evidence 附錄')
$uuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

Get-ChildItem $dir -Filter "*.md" |
    Where-Object { $_.Name -match '^\d\d-' -and $_.Name -notmatch '^(00|90)-' } |
    ForEach-Object {
        $name = $_.Name
        $text = Get-Content $_.FullName -Raw -Encoding UTF8

        foreach ($sec in $requiredSections) {
            if ($text -notmatch [regex]::Escape($sec)) {
                $violations += "${name}：缺章節「$sec」"
            }
        }

        if ($text -notmatch 'CONFIRMED|INFERRED|DYNAMIC_RUNTIME') {
            $violations += "${name}：行為邏輯無任何 confidence 標註"
        }

        # ChunkId 必須是 UUID（非 UUID = 捏造）
        foreach ($m in [regex]::Matches($text, 'ChunkId\s*`?(?<id>[^`\s|]+)`?')) {
            $id = $m.Groups['id'].Value
            if ($id -notmatch $uuidPattern -and $id -ne '<uuid>') {
                $violations += "${name}：ChunkId 非 UUID 格式（疑似捏造）：$id"
            }
        }

        # 已知的自編 id 樣式（歷史失敗模式）
        foreach ($m in [regex]::Matches($text, '\b(SQL-[A-Z]+-\d+|CHK-[A-Z]+-\d+)\b')) {
            $violations += "${name}：出現自編 id 樣式：$($m.Value)"
        }
    }

# 輸出
if ($violations.Count -eq 0) {
    Write-Host "PASS：$Domain 全部檢查通過" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "FAIL：$($violations.Count) 項違規" -ForegroundColor Red
    $violations | ForEach-Object { Write-Host " - $_" }
    exit 1
}
