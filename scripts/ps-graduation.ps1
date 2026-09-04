# ps-graduation.ps1 — 畢業收據（graduation receipt）共用邏輯（issue #3）
# 由 ps-auto-loop.ps1（畢業時寫收據）與 ps-auto-all.ps1（排程時驗收據）dot-source。
# hash 計算與收據驗證只有這一份真相——禁止在別處各抄一份。
# 收據＝「某組領域檔案曾通過完整畢業門」的機械證明，不是第二份進度真相。
#
# 設計決策（對抗式驗證後）：
# - hash 範圍用「排除法」：領域目錄全部 *.md 減 log.md（營運時間軸、非知識內容）。
#   graduation.json 非 .md 天然排除（不會自我失效）；排除法讓 hash 恆為 lint
#   範圍的超集（散檔／全形數字檔名不會漏出範圍——include 清單做不到，且
#   FileSystem provider 的 -Filter 不支援 [0-9] 字元類，會靜默匹配失敗）。
# - 檔案內容先剝 BOM 與 \r 再 hash：行尾／BOM 免疫（git autocrlf、GitHub Raw
#   人工搬運不造成假失效）。
# - 檔名以 Ordinal 排序（Sort-Object 是 culture-sensitive，中文檔名跨機不定序）。
# - gateScriptHash＝本檔 hash（機械失效，不靠人記）；GateVersion 供「刻意讓
#   舊收據作廢／存活」的語意升版——**改動 ps-auto-loop 三層畢業門判定時，
#   必須手動 bump GateVersion**（門邏輯不在任何 hash 覆蓋內）。

# - 兩段式畢業（tier）：tier 1＝覆蓋畢業（可用／80 分：結構完整、無明顯錯誤，
#   容許證據品質未精修）；tier 2＝精修畢業（現行三層門）。收據記 tier，
#   驗收據時以 -RequiredTier 比對：tier 1 收據不足以放行 tier 2 的批次。
#   排程改廣度優先（所有領域先到 tier 1，再回頭做 tier 2）——單領域追求完美
#   會吃掉全部時間，其餘領域停在零；wiki 要的是「每個領域都可用」。

$script:GraduationSchemaVersion = 2
$script:GraduationGateVersion = 4   # issue #23：tier 1 門加 RESEARCH_SCOPE_OK（原始調查項／D 項未建完不得畢業）——誤發的 tier 1 收據作廢重驗（v3＝L107 分批稽核）

# 單檔正規化 hash：BOM 剝除（ReadAllText 依 BOM 解碼並丟棄）＋剝 \r 後
# 以 UTF-8 bytes 算 SHA256（大寫十六進位）
function Get-NormalizedFileHash {
    param([string]$LiteralPath)
    $text = [System.IO.File]::ReadAllText($LiteralPath)
    $text = $text.Replace("`r", "")
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text))
    }
    finally { $sha.Dispose() }
    return ([System.BitConverter]::ToString($bytes)) -replace '-', ''
}

# 領域內容聚合 hash：排除法選檔 → Ordinal 排序 → 「檔名\n檔hash\n」串接再 SHA256
function Get-DomainContentHash {
    param([string]$DomainDir)
    if (-not (Test-Path -LiteralPath $DomainDir)) { return "" }
    $names = @(Get-ChildItem -LiteralPath $DomainDir -File |
            Where-Object { $_.Extension -eq '.md' -and $_.Name -ne 'log.md' } |
            ForEach-Object { $_.Name })
    if ($names.Count -eq 0) { return "" }
    [System.Array]::Sort($names, [System.StringComparer]::Ordinal)
    $sb = New-Object System.Text.StringBuilder
    foreach ($n in $names) {
        $h = Get-NormalizedFileHash -LiteralPath (Join-Path $DomainDir $n)
        [void]$sb.Append($n).Append("`n").Append($h).Append("`n")
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sb.ToString()))
    }
    finally { $sha.Dispose() }
    return ([System.BitConverter]::ToString($bytes)) -replace '-', ''
}

# 逐檔 hash（收據診斷用，L80）：contentHash 不符時要指得出「**哪一個檔**變了」——
# 「文件已變動」沒有可行動性。選檔規則與正規化 hash **必須與 Get-DomainContentHash
# 完全相同**，兩邊漂掉會指向錯的檔（比沒有診斷更糟）。
function Get-DomainFileHashes {
    param([string]$DomainDir)
    $map = [ordered]@{}
    if (-not (Test-Path -LiteralPath $DomainDir)) { return $map }
    $names = @(Get-ChildItem -LiteralPath $DomainDir -File |
            Where-Object { $_.Extension -eq '.md' -and $_.Name -ne 'log.md' } |
            ForEach-Object { $_.Name })
    if ($names.Count -eq 0) { return $map }
    [System.Array]::Sort($names, [System.StringComparer]::Ordinal)
    foreach ($n in $names) {
        $map[$n] = Get-NormalizedFileHash -LiteralPath (Join-Path $DomainDir $n)
    }
    return $map
}

function Get-GraduationReceiptPath {
    param([string]$DomainDir)
    return (Join-Path $DomainDir "graduation.json")
}

# 驗收據：回 @{ Valid = bool; Reason = string }。
# 任何解析失敗一律 Valid=false（fail-safe → 排程器照常 RUN，絕不因壞收據停批）。
function Test-GraduationReceipt {
    param([string]$DomainDir, [string]$Domain,
        [string]$LintScriptPath, [string]$GateScriptPath,
        [int]$RequiredTier = 1)
    $rcPath = Get-GraduationReceiptPath -DomainDir $DomainDir
    if (-not (Test-Path -LiteralPath $rcPath)) {
        return @{ Valid = $false; Reason = "無收據" }
    }
    try {
        $raw = [System.IO.File]::ReadAllText($rcPath)
        $rc = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $rc) { return @{ Valid = $false; Reason = "收據空白" } }
        if ([int]$rc.schemaVersion -ne $script:GraduationSchemaVersion) {
            return @{ Valid = $false; Reason = "schemaVersion 不符（$($rc.schemaVersion)）" }
        }
        if ([int]$rc.gateVersion -ne $script:GraduationGateVersion) {
            return @{ Valid = $false; Reason = "gateVersion 不符（$($rc.gateVersion)——畢業門已改版）" }
        }
        # tier：收據等級低於本次要求＝要重跑（tier 1 收據放不了 tier 2 的行）。
        # 缺 tier 欄位視為 0（schemaVersion 已擋掉舊收據，這裡只是不信任預設）
        $rcTier = 0
        if ($null -ne $rc.tier) { $rcTier = [int]$rc.tier }
        if ($rcTier -lt $RequiredTier) {
            return @{ Valid = $false; Reason = "收據等級不足（tier $rcTier，本次要求 tier $RequiredTier）" }
        }
        if ([string]$rc.domain -cne $Domain) {
            return @{ Valid = $false; Reason = "domain 不符（$($rc.domain)）" }
        }
        if ([string]$rc.contentHash -cne (Get-DomainContentHash -DomainDir $DomainDir)) {
            # 指名哪些檔變了；舊收據沒有 files 欄位就退回舊訊息（不炸例外）
            $detail = "文件已變動"
            if ($null -ne $rc.files) {
                $now = Get-DomainFileHashes -DomainDir $DomainDir
                $was = @{}
                foreach ($p in $rc.files.PSObject.Properties) { $was[$p.Name] = [string]$p.Value }
                $changed = @()
                $added = @()
                $removed = @()
                foreach ($k in $now.Keys) {
                    if (-not $was.ContainsKey($k)) { $added += $k }
                    elseif ($was[$k] -cne [string]$now[$k]) { $changed += $k }
                }
                foreach ($k in $was.Keys) { if (-not $now.Contains($k)) { $removed += $k } }
                $bits = @()
                if ($changed.Count -gt 0) { $bits += "已修改：$($changed -join '、')" }
                if ($added.Count -gt 0) { $bits += "新增：$($added -join '、')" }
                if ($removed.Count -gt 0) { $bits += "已刪除：$($removed -join '、')" }
                if ($bits.Count -gt 0) { $detail = ($bits -join '｜') }
            }
            return @{ Valid = $false; Reason = "contentHash 不符（$detail）" }
        }
        if ([string]$rc.lintScriptHash -cne (Get-NormalizedFileHash -LiteralPath $LintScriptPath)) {
            return @{ Valid = $false; Reason = "lintScriptHash 不符（lint 已改版）" }
        }
        if ([string]$rc.gateScriptHash -cne (Get-NormalizedFileHash -LiteralPath $GateScriptPath)) {
            return @{ Valid = $false; Reason = "gateScriptHash 不符（收據邏輯已改版）" }
        }
        return @{ Valid = $true; Reason = "有效（tier $rcTier）" }
    }
    catch {
        return @{ Valid = $false; Reason = "收據損壞（$($_.Exception.Message)）" }
    }
}

# 寫收據：只准 ps-auto-loop 在三層畢業門全過後呼叫；排程器永不呼叫本函式。
# ExpectedContentHash＝畢業門通過當下的快照——寫入前重算比對，不符＝門後有
# 寫入者（TOCTOU），拒發收據。寫入後回讀重驗。回 @{ Ok = bool; Reason = string }。
function Write-GraduationReceipt {
    param([string]$DomainDir, [string]$Domain, [int]$AuditRound,
        [string]$LintScriptPath, [string]$GateScriptPath, [string]$ExpectedContentHash,
        [int]$Tier = 1)
    try {
        $nowContent = Get-DomainContentHash -DomainDir $DomainDir
        if ($nowContent -cne $ExpectedContentHash) {
            return @{ Ok = $false; Reason = "contentHash 與畢業門快照不符——門後有寫入者，拒發收據" }
        }
        $rc = [ordered]@{
            schemaVersion  = $script:GraduationSchemaVersion
            gateVersion    = $script:GraduationGateVersion
            tier           = $Tier
            domain         = $Domain
            graduatedAt    = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssK")
            auditRound     = $AuditRound
            contentHash    = $nowContent
            files          = (Get-DomainFileHashes -DomainDir $DomainDir)
            lintScriptHash = (Get-NormalizedFileHash -LiteralPath $LintScriptPath)
            gateScriptHash = (Get-NormalizedFileHash -LiteralPath $GateScriptPath)
        }
        $json = $rc | ConvertTo-Json -Depth 4
        [System.IO.File]::WriteAllText(
            (Get-GraduationReceiptPath -DomainDir $DomainDir),
            $json,
            (New-Object System.Text.UTF8Encoding($false)))
        $check = Test-GraduationReceipt -DomainDir $DomainDir -Domain $Domain `
            -LintScriptPath $LintScriptPath -GateScriptPath $GateScriptPath
        if (-not $check.Valid) {
            return @{ Ok = $false; Reason = "回讀重驗失敗：$($check.Reason)" }
        }
        return @{ Ok = $true; Reason = "收據已寫入" }
    }
    catch {
        return @{ Ok = $false; Reason = "寫入失敗（$($_.Exception.Message)）" }
    }
}
