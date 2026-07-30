# ps-doc-lint.ps1 — deep-research 文件的確定性格式稽核（第 1 層 lint）
# 用法：.\scripts\ps-doc-lint.ps1 -Domain 轉職
# 檢查：checklist 對帳、必要章節、confidence 標註、ChunkId UUID 格式、可疑自編 id
param(
    [Parameter(Mandatory = $true)][string]$Domain
)

# 以 script 所在位置反推 repo 根目錄——任何工作目錄都能跑
$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path $root (Join-Path "docs/ps-research" $Domain)
$violations = @()
$warnings = @()

if (-not (Test-Path $dir)) {
    Write-Error "目錄不存在：$dir"
    exit 2
}

$overviewPath = Join-Path $dir "00-overview.md"
$checklistPath = Join-Path $dir "checklist.md"
if (-not (Test-Path $overviewPath)) {
    $violations += "缺 00-overview.md"
}
else {
    # 進度已拆檔：新格式在 checklist.md；舊格式（進度仍在 overview 內）自動相容
    $checklistSrc = if (Test-Path $checklistPath) {
        Get-Content $checklistPath -Raw -Encoding UTF8
    }
    else {
        Get-Content $overviewPath -Raw -Encoding UTF8
    }

    # 1) checklist 對帳：打勾項的目標檔必須存在；NN 檔必須被 checklist 列到
    $listed = @{}
    foreach ($m in [regex]::Matches($checklistSrc, '- \[(?<tick>[ x])\]\s+\S+.*?→\s*(?<file>\S+\.md)')) {
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
$nnNames = @()

Get-ChildItem $dir -Filter "*.md" |
    Where-Object { $_.Name -match '^\d\d-' -and $_.Name -notmatch '^(00|90)-' } |
    ForEach-Object {
        $name = $_.Name
        $nnNames += $name
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
                if ($id -match '^[0-9a-fA-F]{8}$') {
                    $violations += "${name}：ChunkId 遭縮寫為 8 碼（須完整 36 字元 UUID）：$id"
                }
                else {
                    $violations += "${name}：ChunkId 非 UUID 格式（疑似捏造）：$id"
                }
            }
        }

        # 已知的自編 id 樣式（歷史失敗模式）
        foreach ($m in [regex]::Matches($text, '\b(SQL-[A-Z]+-\d+|CHK-[A-Z]+-\d+)\b')) {
            $violations += "${name}：出現自編 id 樣式：$($m.Value)"
        }
    }

# 2.5) 90-audit.md 模板符合度（每輪稽核會重寫，偏離記警告不擋）
$auditPath = Join-Path $dir "90-audit.md"
if (Test-Path $auditPath) {
    $auditText = Get-Content $auditPath -Raw -Encoding UTF8
    $auditSections = @('## 總覽記分卡', '## FAIL / DISPUTED / UNVERIFIABLE 明細',
        '## 上輪回灌項覆核', '## 完整性（換角度 diff）',
        '## 已回灌 checklist 的行動項', '## 系統性錯誤觀察')
    foreach ($sec in $auditSections) {
        if ($auditText -notmatch [regex]::Escape($sec)) {
            $warnings += "90-audit.md：缺模板章節「$sec」（報告偏離模板，對帳會失準）"
        }
    }
    foreach ($bad in [regex]::Matches($auditText, '(?i)\b(partial[_ ]?pass|weakened|contradicted)\b')) {
        $warnings += "90-audit.md：出現契約外狀態「$($bad.Value)」（合法詞彙：PASS/FAIL/UNVERIFIABLE/VERIFIED/DISPUTED；自創詞應就近映射）"
    }
    if ($auditText -notmatch '稽核輪次') {
        $warnings += "90-audit.md：表頭缺「稽核輪次」（無法判斷是否為最新一輪重驗）"
    }
    # 全量對帳：每個 NN 檔都必須出現在稽核報告內文（記分卡一檔一列）
    $missingRows = @($nnNames | Where-Object { $auditText -notmatch [regex]::Escape($_) })
    if ($missingRows.Count -gt 0) {
        $warnings += "90-audit.md：記分卡缺 $($missingRows.Count) 個檔案列（範圍塌縮跡象——稽核未全量重驗）：$($missingRows -join '、')"
    }
}

# 3) Entity Wiki 檢查（wiki/ 為跨領域共用層，存在才檢）
$wikiDir = Join-Path $root "docs/ps-research/wiki"
if (Test-Path $wikiDir) {
    $allMd = Get-ChildItem (Join-Path $root "docs/ps-research") -Recurse -Filter "*.md"
    $noteNames = @{}
    $allMd | ForEach-Object {
        $noteNames[[IO.Path]::GetFileNameWithoutExtension($_.Name)] = $true
    }
    $wikiNotes = Get-ChildItem $wikiDir -Filter "*.md" |
        Where-Object { $_.Name -ne 'index.md' }

    foreach ($n in $wikiNotes) {
        $t = Get-Content $n.FullName -Raw -Encoding UTF8
        foreach ($key in @('aliases', 'status', 'last_verified')) {
            if ($t -notmatch "(?m)^${key}\s*:") {
                $violations += "wiki/$($n.Name)：frontmatter 缺 $key"
            }
        }
        if ($t -match '(?m)^status\s*:\s*(\S+)') {
            if ($Matches[1] -notin @('draft', 'verified', 'stale')) {
                $violations += "wiki/$($n.Name)：status 值非法：$($Matches[1])"
            }
        }
        if ($t -match '(?m)^last_verified\s*:\s*(\d{4}-\d{2}-\d{2})') {
            $d = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd', $null)
            if (((Get-Date) - $d) -gt [timespan]::FromDays(90)) {
                $warnings += "wiki/$($n.Name)：last_verified 超過 90 天（$($Matches[1])）→ 建議排入複查"
            }
        }
    }

    # 斷鏈與孤兒（[[目標]] 以「檔名（不含副檔名）」解析，跨全部領域）
    $referenced = @{}
    foreach ($f in $allMd) {
        $t = Get-Content $f.FullName -Raw -Encoding UTF8
        foreach ($m in [regex]::Matches($t, '\[\[([^\]|#]+)')) {
            $target = $m.Groups[1].Value.Trim()
            $referenced[$target] = $true
            if (-not $noteNames.ContainsKey($target)) {
                $warnings += "$($f.Name)：wikilink 目標不存在：[[${target}]]"
            }
        }
    }
    foreach ($n in $wikiNotes) {
        $entity = [IO.Path]::GetFileNameWithoutExtension($n.Name)
        if (-not $referenced.ContainsKey($entity)) {
            $warnings += "wiki/$($n.Name)：孤兒 entity（沒有任何 [[${entity}]] 入鏈）"
        }
    }
}

# 輸出
if ($warnings.Count -gt 0) {
    Write-Host "WARN：$($warnings.Count) 項警告（不擋通過）" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host " - $_" }
}
if ($violations.Count -eq 0) {
    Write-Host "PASS：$Domain 全部檢查通過" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "FAIL：$($violations.Count) 項違規" -ForegroundColor Red
    $violations | ForEach-Object { Write-Host " - $_" }
    exit 1
}
