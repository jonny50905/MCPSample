# ps-knowledge-lib.ps1 — 知識索引（Knowledge Index）共用邏輯（issue #33）
# 由 ps-knowledge.ps1（CLI）、ps-auto-loop.ps1（safe point 發布）、ps-spec-lib.ps1（規劃器）、
# ps-supplemental-lib.ps1（路由）dot-source。純函式庫：dot-source 不產生任何副作用、不呼叫模型、不查 DB。
#
# 責任：把 docs/ps-research/<領域>/（NN／00-overview／90-audit／checklist／graduation.json）、
#       auto-loop-logs/<領域>/audit-r<N>.done.json 與 docs/ps-research/wiki/*.md 確定性解析成
#       docs/ps-research/knowledge/index.json（腳本讀）＋ index.md（模型 grep／read 用；不含 [[ ]]）。
# 索引只記「定位」（檔、節的起訖行號）與「品質旗標」（等級／有效性），內容永遠讀原檔；
# 索引是可重建的投影，不是第二份真相。
#
# PowerShell 5.1 紀律：無三元／??／&&；Join-Path 兩參數；-LiteralPath；Ordinal 排序；
# 檔案讀寫走 [System.IO.File]；JSON 輸出用本檔的 canonical 序列化（不用 ConvertTo-Json：5.1 會把 < > ' 逃逸成 \u 且 Depth 預設 2）。

$script:PsKnowledgeLibVersion = 1
$script:PsKnowledgeSchemaVersion = 1

# ── 基礎：讀檔、hash、排序 ───────────────────────────────────────

# 讀文字（BOM 自動剝除）；回傳 $null 表示檔案不存在
function Read-PsKnText {
    param([string]$LiteralPath)
    if (-not [System.IO.File]::Exists($LiteralPath)) { return $null }
    $t = [System.IO.File]::ReadAllText($LiteralPath)
    if ($t.Length -gt 0 -and [int]$t[0] -eq 0xFEFF) { $t = $t.Substring(1) }
    return $t
}

# 逐行（行號 1 起算＝OpenCode read 工具顯示的行號；\r 剝掉、行數不變）
function Get-PsKnLines {
    param([string]$Text)
    if ($null -eq $Text) { return , @() }
    return , @(($Text -replace "`r", '') -split "`n")
}

# 正規化 hash：剝 BOM 與 \r 後 UTF-8 bytes SHA256（大寫 hex）——與 ps-graduation.ps1 Get-NormalizedFileHash 相同規則
function Get-PsKnTextHash {
    param([string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $t = $Text.Replace("`r", '')
    if ($t.Length -gt 0 -and [int]$t[0] -eq 0xFEFF) { $t = $t.Substring(1) }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($t)) }
    finally { $sha.Dispose() }
    return ([System.BitConverter]::ToString($bytes)) -replace '-', ''
}

function Get-PsKnFileHash {
    param([string]$LiteralPath)
    $t = Read-PsKnText -LiteralPath $LiteralPath
    if ($null -eq $t) { return '' }
    return Get-PsKnTextHash -Text $t
}

function Sort-PsKnOrdinal {
    param([string[]]$Items)
    $arr = @($Items)
    if ($arr.Count -le 1) { return , $arr }
    [System.Array]::Sort($arr, [System.StringComparer]::Ordinal)
    return , $arr
}

# 時間戳一律 InvariantCulture（zh-TW 若設民國曆，yyyy 會變 115；時間分隔符也會隨文化變）
function Get-PsKnUtcStamp {
    param([datetime]$At = [datetime]::UtcNow)
    return $At.ToUniversalTime().ToString("yyyy-MM-dd'T'HH':'mm':'ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
}
function Get-PsKnDateKey {
    param([datetime]$At = [datetime]::UtcNow)
    return $At.ToUniversalTime().ToString('yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture)
}
# 12 hex 隨機（crypto RNG：GUID 位元組；不用 System.Random——.NET Framework 以 TickCount 播種，同毫秒會撞）
function New-PsKnRandomHex {
    param([int]$Chars = 12)
    $sb = New-Object System.Text.StringBuilder
    while ($sb.Length -lt $Chars) {
        foreach ($b in [guid]::NewGuid().ToByteArray()) { [void]$sb.Append($b.ToString('x2')) }
    }
    return $sb.ToString().Substring(0, $Chars)
}

# ── canonical JSON（insertion order、LF、2 空格、非 ASCII 原樣；-SortKeys 時逐層 Ordinal 排序鍵，供 workKey 等跨機 hash）────────

function ConvertTo-PsKnJsonString {
    param([string]$Value)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $Value.ToCharArray()) {
        $code = [int]$ch
        if ($code -eq 34) { [void]$sb.Append('\"') }
        elseif ($code -eq 92) { [void]$sb.Append('\\') }
        elseif ($code -eq 8) { [void]$sb.Append('\b') }
        elseif ($code -eq 12) { [void]$sb.Append('\f') }
        elseif ($code -eq 10) { [void]$sb.Append('\n') }
        elseif ($code -eq 13) { [void]$sb.Append('\r') }
        elseif ($code -eq 9) { [void]$sb.Append('\t') }
        elseif ($code -lt 32 -or $code -eq 0x2028 -or $code -eq 0x2029) { [void]$sb.Append('\u').Append($code.ToString('x4')) }
        else { [void]$sb.Append($ch) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function ConvertTo-PsKnJson {
    param($Value, [int]$Indent = 0, [switch]$SortKeys)
    $pad = ' ' * $Indent
    $pad2 = ' ' * ($Indent + 2)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or $Value -is [byte]) {
        return ([System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture))
    }
    if ($Value -is [double] -or $Value -is [single]) { return ([double]$Value).ToString('R', [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [decimal]) { return ([decimal]$Value).ToString([System.Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [string]) { return (ConvertTo-PsKnJsonString -Value $Value) }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @()
        foreach ($k in $Value.Keys) { $keys += [string]$k }
        if ($keys.Count -eq 0) { return '{}' }
        if ($SortKeys) { $keys = Sort-PsKnOrdinal -Items $keys }
        $parts = @()
        foreach ($k in $keys) {
            $parts += ($pad2 + (ConvertTo-PsKnJsonString -Value $k) + ': ' + (ConvertTo-PsKnJson -Value $Value[$k] -Indent ($Indent + 2) -SortKeys:$SortKeys))
        }
        return ('{' + "`n" + ($parts -join (',' + "`n")) + "`n" + $pad + '}')
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $od = [ordered]@{}
        foreach ($p in $Value.PSObject.Properties) { $od[$p.Name] = $p.Value }
        return (ConvertTo-PsKnJson -Value $od -Indent $Indent -SortKeys:$SortKeys)
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @()
        foreach ($it in $Value) { $items += , $it }
        if ($items.Count -eq 0) { return '[]' }
        $parts = @()
        foreach ($it in $items) { $parts += ($pad2 + (ConvertTo-PsKnJson -Value $it -Indent ($Indent + 2) -SortKeys:$SortKeys)) }
        return ('[' + "`n" + ($parts -join (',' + "`n")) + "`n" + $pad + ']')
    }
    return (ConvertTo-PsKnJsonString -Value ([string]$Value))
}

# ── 原子寫入 ────────────────────────────────────────────────────

# mutable 目標：寫 tmp → 目標存在則 Replace、否則 Move（同 volume）；Windows 上目標被別的行程開著會 sharing violation → 重試 5 次（200ms 退避），
# 仍失敗＝保留舊版、刪 tmp、回 $false（呼叫端記 PUBLISH_DEFERRED）。成功回 $true；回讀失敗拋錯。
function Write-PsKnAtomicText {
    param([string]$LiteralPath, [string]$Text, [bool]$Bom = $false, [int]$Retries = 5)
    $dir = [System.IO.Path]::GetDirectoryName($LiteralPath)
    if (-not [System.IO.Directory]::Exists($dir)) { [void][System.IO.Directory]::CreateDirectory($dir) }
    $tmp = $LiteralPath + '.tmp-' + [guid]::NewGuid().ToString('N')
    [System.IO.File]::WriteAllText($tmp, $Text, (New-Object System.Text.UTF8Encoding($Bom)))
    $ok = $false
    $lastErr = ''
    for ($try = 1; $try -le $Retries; $try++) {
        try {
            if ([System.IO.File]::Exists($LiteralPath)) {
                # Replace 需要真實的備份檔名（$null 在 PS 會變成空字串）；備份完成即刪
                $bak = $LiteralPath + '.bak-' + [guid]::NewGuid().ToString('N')
                try {
                    [System.IO.File]::Replace($tmp, $LiteralPath, $bak)
                }
                catch [System.PlatformNotSupportedException] {
                    [System.IO.File]::Delete($LiteralPath)
                    [System.IO.File]::Move($tmp, $LiteralPath)
                }
                if ([System.IO.File]::Exists($bak)) { [System.IO.File]::Delete($bak) }
            }
            else {
                [System.IO.File]::Move($tmp, $LiteralPath)
            }
            $ok = $true
            break
        }
        catch {
            $lastErr = $_.Exception.Message
            Start-Sleep -Milliseconds (200 * $try)
        }
    }
    if (-not $ok) {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        Write-Host ("PUBLISH_DEFERRED：" + $LiteralPath + "（" + $lastErr + "）")
        return $false
    }
    $back = Read-PsKnText -LiteralPath $LiteralPath
    if ($null -eq $back) { throw "寫入後回讀失敗：$LiteralPath" }
    return $true
}

# create-only 目標：tmp → Move；目標已存在 → 回 $false（不覆寫、不拋）
function Write-PsKnCreateOnlyText {
    param([string]$LiteralPath, [string]$Text)
    $dir = [System.IO.Path]::GetDirectoryName($LiteralPath)
    if (-not [System.IO.Directory]::Exists($dir)) { [void][System.IO.Directory]::CreateDirectory($dir) }
    if ([System.IO.File]::Exists($LiteralPath)) { return $false }
    $tmp = $LiteralPath + '.tmp-' + [guid]::NewGuid().ToString('N')
    [System.IO.File]::WriteAllText($tmp, $Text, (New-Object System.Text.UTF8Encoding($false)))
    try {
        [System.IO.File]::Move($tmp, $LiteralPath)
        return $true
    }
    catch [System.IO.IOException] {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        return $false
    }
}

# 清掉半寫殘留（crash 時留下的 *.tmp-<guid>／*.bak-<guid>）；只清超過 MinAgeMinutes 的，避免掃到別的行程正在寫的 tmp
function Remove-PsKnTempFiles {
    param([string]$Directory, [int]$MinAgeMinutes = 10)
    if (-not [System.IO.Directory]::Exists($Directory)) { return 0 }
    $n = 0
    $cut = [datetime]::UtcNow.AddMinutes(-1 * $MinAgeMinutes)
    foreach ($f in @(Get-ChildItem -LiteralPath $Directory -File -Force -ErrorAction SilentlyContinue)) {
        if ($f.Name -match '\.(tmp|bak)-[0-9a-f]{32}$' -and $f.LastWriteTimeUtc -lt $cut) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue; $n++ }
    }
    return $n
}

# ── Markdown 結構解析 ───────────────────────────────────────────

# 標題清單：Level（2／3）、Title（去掉 # 與尾空白）、Start（標題行號）、End（同級或更高級下一標題的前一行；最後＝總行數）
function Get-PsKnHeadings {
    param([string[]]$Lines)
    $list = @()
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $m = [regex]::Match($Lines[$i], '^[ \t]{0,3}(#{2,3})[ \t]+(.+?)[ \t]*$')
        if ($m.Success) {
            $list += , ([ordered]@{ Level = $m.Groups[1].Value.Length; Title = $m.Groups[2].Value; Start = ($i + 1); End = $Lines.Count })
        }
    }
    for ($j = 0; $j -lt $list.Count; $j++) {
        for ($k = $j + 1; $k -lt $list.Count; $k++) {
            if ($list[$k].Level -le $list[$j].Level) { $list[$j].End = $list[$k].Start - 1; break }
        }
    }
    return , $list
}

# 節標題正規化鍵：去空白、去（gaps）、去「Evidence 附錄」的空白差異
function Get-PsKnSectionKey {
    param([string]$Title)
    $t = $Title -replace '\*\*', ''
    $t = $t -replace '（[^）]*）', ''
    $t = $t -replace '\([^)]*\)', ''
    $t = $t -replace '[：:]\s*$', ''
    $t = $t -replace '\s+', ''
    return $t
}

# 取指定 ## 節（含其 ### 子節）的 Start／End；找不到回 $null
function Find-PsKnSection {
    param($Headings, [string]$Key, [int]$Level = 2)
    foreach ($h in $Headings) {
        if ($h.Level -eq $Level -and (Get-PsKnSectionKey -Title $h.Title) -eq $Key) { return $h }
    }
    return $null
}

# 表格列（跳過表頭與分隔列；cell Trim、保留空 cell）。回傳 @( @{ Line=行號; Cells=@(...) } )
function Get-PsKnTableRows {
    param([string[]]$Lines, [int]$Start, [int]$End)
    $rows = @()
    $seenHeader = $false
    for ($i = $Start; $i -le $End -and $i -le $Lines.Count; $i++) {
        $ln = $Lines[$i - 1]
        if ($ln -notmatch '^\s*\|') { continue }
        if ($ln -match '^\s*\|[\s:|-]+\|\s*$') { $seenHeader = $true; continue }
        $inner = $ln.Trim()
        $inner = $inner -replace '^\|', ''
        $inner = $inner -replace '\|\s*$', ''
        $cells = @()
        foreach ($c in ($inner -split '\|')) { $cells += $c.Trim() }
        if (-not $seenHeader) {
            # 分隔列之前的第一列是表頭；沒有分隔列的殘缺表也把第一列當表頭
            $seenHeader = $true
            continue
        }
        $rows += , ([ordered]@{ Line = $i; Cells = $cells })
    }
    return , $rows
}

# 節是否空洞：去 HTML 註解、<占位>、「同前／略／unchanged」後無內容（同 ps-doc-lint Test-SectionHollow）
function Test-PsKnHollow {
    param([string[]]$Lines, [int]$Start, [int]$End)
    if ($Start -lt 1 -or $Start -gt $End) { return $true }
    $body = ($Lines[($Start) .. ([Math]::Min($End, $Lines.Count) - 1)]) -join "`n"
    if ($Start -ge $Lines.Count) { return $true }
    $body = [regex]::Replace($body, '<!--.*?-->', '', 'Singleline')
    $keep = @()
    foreach ($l in ($body -split "`n")) {
        $t = $l.Trim()
        if ($t -eq '') { continue }
        if ($t -match '^<[^>]*>$') { continue }
        if ($t -match '^(同前|同上|如前|如上|略|不變|未變|unchanged|same as before|same as above)[。.]?$') { continue }
        $keep += $t
    }
    return ($keep.Count -eq 0)
}

function Get-PsKnWikilinks {
    param([string]$Text)
    $set = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Text) { return , @() }
    foreach ($m in [regex]::Matches($Text, '\[\[([^\]|#]+)')) {
        $v = $m.Groups[1].Value.Trim()
        if ($v -ne '' -and -not $set.Contains($v)) { $set.Add($v) }
    }
    return , @($set.ToArray())
}

$script:PsKnUuidRx = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
$script:PsKnNnSections = @('相關物件', '功能定位', '畫面與欄位', '行為邏輯', '資料流', '執行方式', '權限', '未解事項', 'Evidence附錄')
$script:PsKnSectionDisplay = @{ '相關物件' = '相關物件'; '功能定位' = '功能定位'; '畫面與欄位' = '畫面與欄位'; '行為邏輯' = '行為邏輯'; '資料流' = '資料流'; '執行方式' = '執行方式'; '權限' = '權限'; '未解事項' = '未解事項'; 'Evidence附錄' = 'Evidence' }

# 從 sections 陣列取第一個符合（名稱鍵＋層級）的範圍；找不到回 $null
function Get-PsKnSectionRange {
    param($Sections, [string]$Name, [int]$Level = 2)
    foreach ($sec in @($Sections)) {
        if ([int]$sec.level -eq $Level -and [string]$sec.name -eq $Name) { return $sec }
    }
    return $null
}

# ── NN 檔解析 ───────────────────────────────────────────────────

function Test-PsKnIsNnFile {
    param([string]$Name)
    return ($Name -match '^\d\d-' -and $Name -notmatch '^(00|90)-' -and $Name -match '\.md$')
}

function Get-PsKnNnFacts {
    param([string]$LiteralPath, [string]$Domain)
    $text = Read-PsKnText -LiteralPath $LiteralPath
    if ($null -eq $text) { return $null }
    $lines = Get-PsKnLines -Text $text
    $name = [System.IO.Path]::GetFileName($LiteralPath)
    $f = [ordered]@{
        domain = $Domain; file = $name; title = ''; primaryObject = ''; status = 'UNKNOWN'; origin = ''
        lineCount = $lines.Count; hash = (Get-PsKnTextHash -Text $text)
        sections = @(); missingSections = @(); duplicateSections = 0
        relatedObjects = @(); fieldRows = 0; fieldsNotApplicable = $false
        behaviorCounts = [ordered]@{ CONFIRMED = 0; INFERRED = 0; DYNAMIC_RUNTIME = 0 }
        dataFlow = @(); executionHollow = $true; permissionHollow = $true; gaps = 0
        evidence = @(); evidenceKinds = [ordered]@{ CHUNK = 0; SQL = 0; PENDING_MANUAL = 0; UNRESOLVED = 0 }
        links = @()
    }
    # 標題與檔頭
    for ($i = 0; $i -lt [Math]::Min(5, $lines.Count); $i++) {
        $m = [regex]::Match($lines[$i], '^#\s+(.+?)\s*$')
        if ($m.Success) {
            $f.title = $m.Groups[1].Value
            $mm = [regex]::Match($f.title, '\[\[([^\]|#]+)\]\]')
            if ($mm.Success) { $f.primaryObject = $mm.Groups[1].Value.Trim() }
            break
        }
    }
    $head = ($lines[0 .. ([Math]::Min(8, $lines.Count) - 1)]) -join "`n"
    $ms = [regex]::Match($head, '狀態[：:]\s*(COMPLETE|PARTIAL|BLOCKED)')
    if ($ms.Success) { $f.status = $ms.Groups[1].Value }
    $mo = [regex]::Match($head, 'Origin[：:]\s*([A-Z_]+)')
    if ($mo.Success) { $f.origin = $mo.Groups[1].Value }
    if ($f.primaryObject -eq '') {
        # 標題沒有 [[ ]]：退而取檔名的物件段（12-TW_X.md → TW_X；續篇 -2 剝掉）
        $base = $name -replace '\.md$', ''
        $base = $base -replace '^\d\d-', ''
        $base = $base -replace '-\d+$', ''
        $f.primaryObject = $base
    }
    $heads = Get-PsKnHeadings -Lines $lines
    $seenKeys = @{}
    foreach ($h in $heads) {
        $key = Get-PsKnSectionKey -Title $h.Title
        $dupKey = ([string]$h.Level + ':' + $key.ToLowerInvariant())
        if ($seenKeys.ContainsKey($dupKey)) { $f.duplicateSections++ } else { $seenKeys[$dupKey] = $true }
        $f.sections += , ([ordered]@{ level = $h.Level; name = $key; start = $h.Start; end = $h.End })
    }
    foreach ($s in $script:PsKnNnSections) { if ($null -eq (Get-PsKnSectionRange -Sections $f.sections -Name $s -Level 2)) { $f.missingSections += $s } }
    # 相關物件
    $sec = Find-PsKnSection -Headings $heads -Key '相關物件'
    if ($null -ne $sec) {
        foreach ($r in (Get-PsKnTableRows -Lines $lines -Start $sec.Start -End $sec.End)) {
            if ($r.Cells.Count -lt 1) { continue }
            $obj = $r.Cells[0]
            $mm = [regex]::Match($obj, '\[\[([^\]|#]+)\]\]')
            if ($mm.Success) { $obj = $mm.Groups[1].Value.Trim() } else { $obj = ($obj -replace '`', '').Trim() }
            if ($obj -eq '' -or $obj -match '^<.*>$') { continue }
            $role = ''
            if ($r.Cells.Count -ge 2) { $role = $r.Cells[1] }
            $f.relatedObjects += , ([ordered]@{ name = $obj; role = $role; line = $r.Line })
        }
    }
    # 畫面與欄位
    $sec = Find-PsKnSection -Headings $heads -Key '畫面與欄位'
    if ($null -ne $sec) {
        $rows = Get-PsKnTableRows -Lines $lines -Start $sec.Start -End $sec.End
        $f.fieldRows = $rows.Count
        $body = ($lines[($sec.Start) .. ([Math]::Min($sec.End, $lines.Count) - 1)]) -join "`n"
        if ($body -match '（無') { $f.fieldsNotApplicable = $true }
    }
    # 行為邏輯
    $sec = Find-PsKnSection -Headings $heads -Key '行為邏輯'
    if ($null -ne $sec) {
        $body = ($lines[($sec.Start) .. ([Math]::Min($sec.End, $lines.Count) - 1)]) -join "`n"
        foreach ($k in @('CONFIRMED', 'INFERRED', 'DYNAMIC_RUNTIME')) {
            $f.behaviorCounts[$k] = ([regex]::Matches($body, ('\b' + $k + '\b'))).Count
        }
    }
    # 資料流
    $sec = Find-PsKnSection -Headings $heads -Key '資料流'
    if ($null -ne $sec) {
        foreach ($r in (Get-PsKnTableRows -Lines $lines -Start $sec.Start -End $sec.End)) {
            if ($r.Cells.Count -lt 2) { continue }
            $tbl = ($r.Cells[0] -replace '`', '').Trim()
            $tbl = $tbl -replace '\[\[|\]\]', ''
            if ($tbl -eq '' -or $tbl -match '^<.*>$') { continue }
            $op = $r.Cells[1].ToUpperInvariant()
            $src = ''; $conf = ''
            if ($r.Cells.Count -ge 3) { $src = $r.Cells[2] }
            if ($r.Cells.Count -ge 4) { $conf = $r.Cells[3].ToUpperInvariant() }
            $f.dataFlow += , ([ordered]@{ table = $tbl; op = $op; source = $src; confidence = $conf; line = $r.Line })
        }
    }
    $sec = Find-PsKnSection -Headings $heads -Key '執行方式'
    if ($null -ne $sec) { $f.executionHollow = (Test-PsKnHollow -Lines $lines -Start $sec.Start -End $sec.End) }
    $sec = Find-PsKnSection -Headings $heads -Key '權限'
    if ($null -ne $sec) { $f.permissionHollow = (Test-PsKnHollow -Lines $lines -Start $sec.Start -End $sec.End) }
    $sec = Find-PsKnSection -Headings $heads -Key '未解事項'
    if ($null -ne $sec) {
        $n = 0
        for ($i = $sec.Start; $i -lt $sec.End; $i++) { if ($lines[$i] -match '^\s*[-*]\s+\S') { $n++ } }
        $f.gaps = $n
    }
    # Evidence 附錄
    $sec = Find-PsKnSection -Headings $heads -Key 'Evidence附錄'
    if ($null -ne $sec) {
        foreach ($r in (Get-PsKnTableRows -Lines $lines -Start $sec.Start -End $sec.End)) {
            if ($r.Cells.Count -lt 2) { continue }
            $joined = ($r.Cells -join ' | ')
            $kind = 'UNRESOLVED'
            $ref = ''
            $mu = [regex]::Match($joined, $script:PsKnUuidRx)
            if ($mu.Success) { $kind = 'CHUNK'; $ref = $mu.Value }
            elseif ($joined -match '(?i)\bSELECT\b[\s\S]{0,400}?\bFROM\b') { $kind = 'SQL' }
            elseif ($joined -match '待人工\s*SQL') { $kind = 'PENDING_MANUAL' }
            $num = 0
            [void][int]::TryParse($r.Cells[0], [ref]$num)
            if ($num -eq 0) { $num = $f.evidence.Count + 1 }
            $loc = ''
            if ($r.Cells.Count -ge 2) { $loc = $r.Cells[1] }
            $f.evidence += , ([ordered]@{ n = $num; line = $r.Line; kind = $kind; ref = $ref; location = $loc })
            $f.evidenceKinds[$kind] = [int]$f.evidenceKinds[$kind] + 1
        }
    }
    $f.links = Get-PsKnWikilinks -Text $text
    return $f
}

# ── 00-overview／90-audit／checklist／收據 ───────────────────────

function Get-PsKnOverviewFacts {
    param([string]$LiteralPath)
    $text = Read-PsKnText -LiteralPath $LiteralPath
    $o = [ordered]@{ exists = ($null -ne $text); hash = ''; functionMap = @() }
    if ($null -eq $text) { return $o }
    $o.hash = Get-PsKnTextHash -Text $text
    $lines = Get-PsKnLines -Text $text
    $heads = Get-PsKnHeadings -Lines $lines
    $sec = Find-PsKnSection -Headings $heads -Key '功能地圖'
    if ($null -ne $sec) {
        foreach ($r in (Get-PsKnTableRows -Lines $lines -Start $sec.Start -End $sec.End)) {
            if ($r.Cells.Count -lt 3) { continue }
            $obj = $r.Cells[2]
            $mm = [regex]::Match($obj, '\[\[([^\]|#]+)\]\]')
            if ($mm.Success) { $obj = $mm.Groups[1].Value.Trim() } else { $obj = ($obj -replace '`', '').Trim() }
            if ($obj -eq '' -or $obj -match '^<.*>$') { continue }
            $type = ''; $origin = ''; $fn = ''
            if ($r.Cells.Count -ge 2) { $fn = $r.Cells[1] }
            if ($r.Cells.Count -ge 4) { $type = $r.Cells[3] }
            if ($r.Cells.Count -ge 5) { $origin = $r.Cells[4] }
            $o.functionMap += , ([ordered]@{ object = $obj; function = $fn; type = $type; origin = $origin })
        }
    }
    return $o
}

function Get-PsKnAuditFacts {
    param([string]$LiteralPath)
    $text = Read-PsKnText -LiteralPath $LiteralPath
    $a = [ordered]@{ exists = ($null -ne $text); hash = ''; round = 0; scorecard = [ordered]@{}; details = @(); failedRefs = @(); domainGate = @() }
    if ($null -eq $text) { return $a }
    $a.hash = Get-PsKnTextHash -Text $text
    $lines = Get-PsKnLines -Text $text
    $mr = [regex]::Matches($text, '稽核輪次[：:]\s*(\d+)')
    if ($mr.Count -gt 0) { $a.round = [int]$mr[$mr.Count - 1].Groups[1].Value }
    $heads = Get-PsKnHeadings -Lines $lines
    foreach ($h in $heads) {
        if ($h.Level -ne 2) { continue }
        $t = $h.Title
        if ($t -match '記分卡|總覽' -and $t -notmatch '明細') {
            foreach ($r in (Get-PsKnTableRows -Lines $lines -Start $h.Start -End $h.End)) {
                if ($r.Cells.Count -lt 7) { continue }
                $file = ($r.Cells[0] -replace '\*\*', '').Trim()
                if ($file -eq '' -or $file -match '合計') { continue }
                $nums = @()
                for ($c = 1; $c -le 5; $c++) { $v = 0; [void][int]::TryParse(($r.Cells[$c] -replace '\*\*', '').Trim(), [ref]$v); $nums += $v }
                $light = $r.Cells[$r.Cells.Count - 1]
                $lightCode = 'UNKNOWN'
                if ($light -match '⛔|未稽核') { $lightCode = 'NOT_AUDITED' }
                elseif ($light -match '🔴') { $lightCode = 'RED' }
                elseif ($light -match '🟡') { $lightCode = 'YELLOW' }
                elseif ($light -match '🟢') { $lightCode = 'GREEN' }
                if ($r.Cells[1] -match '未稽核') { $lightCode = 'NOT_AUDITED' }
                $a.scorecard[$file] = [ordered]@{ pass = $nums[0]; fail = $nums[1]; unverifiable = $nums[2]; verified = $nums[3]; disputed = $nums[4]; light = $lightCode }
            }
        }
        elseif ($t -match '完整性') {
            # Domain Gate 候選表：| 候選物件 | 型別 | 經由表 | 方向 | origin | 分類 | 理由 |
            foreach ($r in (Get-PsKnTableRows -Lines $lines -Start $h.Start -End $h.End)) {
                if ($r.Cells.Count -lt 6) { continue }
                $obj = ($r.Cells[0] -replace '\[\[|\]\]|`', '').Trim()
                if ($obj -eq '' -or $obj -match '^<.*>$') { continue }
                $cls = $r.Cells[5].Trim().ToUpperInvariant()
                if ($cls -notmatch '^(DOMAIN_ROOT|DEPENDENCY|OUT_OF_SCOPE)') { continue }
                $reason = ''
                if ($r.Cells.Count -ge 7) { $reason = $r.Cells[6] }
                $a.domainGate += , ([ordered]@{ object = $obj; type = $r.Cells[1]; viaTable = $r.Cells[2]; direction = $r.Cells[3]; origin = $r.Cells[4]; classification = ([regex]::Match($cls, '^(DOMAIN_ROOT|DEPENDENCY|OUT_OF_SCOPE)').Value); reason = $reason; line = $r.Line })
            }
        }
        elseif ($t -match '明細') {
            foreach ($r in (Get-PsKnTableRows -Lines $lines -Start $h.Start -End $h.End)) {
                if ($r.Cells.Count -lt 4) { continue }
                $file = $r.Cells[0].Trim()
                $type = $r.Cells[1]
                $content = $r.Cells[2]
                $cls = 'OTHER'
                if ($type -match 'FAIL') { $cls = 'FAIL' }
                elseif ($type -match 'DISPUTED') { $cls = 'DISPUTED' }
                elseif ($type -match 'UNVERIFIABLE') { $cls = 'UNVERIFIABLE' }
                $a.details += , ([ordered]@{ file = $file; type = $type; verdict = $cls; content = $content; line = $r.Line })
                if ($cls -eq 'FAIL') {
                    foreach ($mu in [regex]::Matches($content, $script:PsKnUuidRx)) {
                        $u = $mu.Value.ToLowerInvariant()
                        if ($a.failedRefs -notcontains $u) { $a.failedRefs += $u }
                    }
                }
            }
        }
    }
    return $a
}

# 未勾的 A／U 補強列 → 每個 NN 檔的待補數；未勾 D 列數；未勾調查項數
function Get-PsKnChecklistFacts {
    param([string]$LiteralPath)
    $text = Read-PsKnText -LiteralPath $LiteralPath
    $c = [ordered]@{ exists = ($null -ne $text); hash = ''; round = 0; pendingRepairs = [ordered]@{}; pendingD = 0; pendingPlain = 0 }
    if ($null -eq $text) { return $c }
    $c.hash = Get-PsKnTextHash -Text $text
    $mr = [regex]::Matches($text, '稽核輪次[：:]\s*(\d+)')
    if ($mr.Count -gt 0) { $c.round = [int]$mr[0].Groups[1].Value }
    foreach ($m in [regex]::Matches($text, '(?m)^\s*-\s*\[ \]\s*(.+?)\s*$')) {
        $body = $m.Groups[1].Value
        if ($body -match '^[Dd]\d+-\d+\b') { $c.pendingD++; continue }
        if ($body -match '^[AUau]\d+-\d+\b') {
            $mf = [regex]::Match($body, '\d\d-[^\s（）()：:]+\.md')
            if ($mf.Success) {
                $k = $mf.Value
                if ($c.pendingRepairs.Contains($k)) { $c.pendingRepairs[$k] = [int]$c.pendingRepairs[$k] + 1 } else { $c.pendingRepairs[$k] = 1 }
            }
            continue
        }
        if ($body -match '(?i)(?:任務|task)\s*[ABC]\b|批次\s*\d+\s*[/／]\s*\d+') { continue }
        if ($body -match '\d\d-[^\s（）()：:]+\.md') { $c.pendingPlain++ }
    }
    return $c
}

function Get-PsKnReceiptFacts {
    param([string]$DomainDir)
    $p = Join-Path $DomainDir 'graduation.json'
    $r = [ordered]@{ exists = $false; tier = 0; gateVersion = 0; files = [ordered]@{}; hash = '' }
    $text = Read-PsKnText -LiteralPath $p
    if ($null -eq $text) { return $r }
    $r.hash = Get-PsKnTextHash -Text $text
    try {
        $j = $text | ConvertFrom-Json -ErrorAction Stop
        $r.exists = $true
        if ($null -ne $j.tier) { $r.tier = [int]$j.tier }
        if ($null -ne $j.gateVersion) { $r.gateVersion = [int]$j.gateVersion }
        if ($null -ne $j.files) { foreach ($pp in $j.files.PSObject.Properties) { $r.files[$pp.Name] = [string]$pp.Value } }
    }
    catch { $r.exists = $false }
    return $r
}

# 稽核時各檔 hash：先讀領域目錄的 audit-done.json（稽核合併時外環另存；進內部 git → 各機可判），
# 沒有再退到 auto-loop-logs/<領域>/audit-r<N>.done.json（單機）取 N 最大者；files[].hash
function Get-PsKnAuditDoneFacts {
    param([string]$LogDir, [string]$DomainDir = '')
    $d = [ordered]@{ exists = $false; round = 0; files = [ordered]@{}; hash = ''; source = '' }
    $best = $null; $bestN = -1
    if ($DomainDir -ne '' -and [System.IO.File]::Exists((Join-Path $DomainDir 'audit-done.json'))) {
        $best = Join-Path $DomainDir 'audit-done.json'
        $d.source = 'domain'
    }
    elseif ([System.IO.Directory]::Exists($LogDir)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $LogDir -File -ErrorAction SilentlyContinue)) {
            $m = [regex]::Match($f.Name, '^audit-r(\d+)\.done\.json$')
            if ($m.Success) { $n = [int]$m.Groups[1].Value; if ($n -gt $bestN) { $bestN = $n; $best = $f.FullName } }
        }
        if ($null -ne $best) { $d.source = 'logs' }
    }
    if ($null -eq $best) { return $d }
    $text = Read-PsKnText -LiteralPath $best
    if ($null -eq $text) { return $d }
    $d.hash = Get-PsKnTextHash -Text $text
    try {
        $j = $text | ConvertFrom-Json -ErrorAction Stop
        $d.exists = $true; $d.round = $bestN
        if ($null -ne $j.round) { $d.round = [int]$j.round }
        if ($null -ne $j.files) {
            foreach ($pp in $j.files.PSObject.Properties) {
                $h = ''
                if ($null -ne $pp.Value -and $null -ne $pp.Value.hash) { $h = [string]$pp.Value.hash }
                $d.files[$pp.Name] = $h
            }
        }
    }
    catch { $d.exists = $false }
    return $d
}

# ── wiki entity 解析 ─────────────────────────────────────────────

function Get-PsKnYamlList {
    param([string]$Raw, [string[]]$Lines, [int]$Index)
    # 支援 [a, b] 與後續縮排 "- x" 兩種
    $out = @()
    $v = $Raw.Trim()
    if ($v -match '^\[(.*)\]$') {
        foreach ($p in ($Matches[1] -split ',')) { $t = $p.Trim().Trim('"').Trim("'"); if ($t -ne '') { $out += $t } }
        return , $out
    }
    if ($v -ne '') { $out += $v.Trim('"').Trim("'"); return , $out }
    for ($i = $Index + 1; $i -lt $Lines.Count; $i++) {
        $m = [regex]::Match($Lines[$i], '^\s+-\s*(.+?)\s*$')
        if ($m.Success) { $out += $m.Groups[1].Value.Trim('"').Trim("'") } else { break }
    }
    return , $out
}

function Get-PsKnWikiFacts {
    param([string]$LiteralPath)
    $text = Read-PsKnText -LiteralPath $LiteralPath
    if ($null -eq $text) { return $null }
    $lines = Get-PsKnLines -Text $text
    $name = [System.IO.Path]::GetFileNameWithoutExtension($LiteralPath)
    $w = [ordered]@{
        name = $name; file = [System.IO.Path]::GetFileName($LiteralPath); hash = (Get-PsKnTextHash -Text $text)
        aliases = @(); type = 'UNKNOWN'; origin = ''; status = 'UNKNOWN'; confidence = ''; lastVerified = ''; sources = @(); reviewed = $false
        observations = 0; relations = @(); invalidated = 0; links = @(); lineCount = $lines.Count
    }
    # frontmatter
    if ($lines.Count -gt 2 -and $lines[0].Trim() -eq '---') {
        $endIdx = -1
        for ($i = 1; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq '---') { $endIdx = $i; break } }
        if ($endIdx -gt 0) {
            for ($i = 1; $i -lt $endIdx; $i++) {
                $m = [regex]::Match($lines[$i], '^([A-Za-z_]+)\s*:\s*(.*?)\s*(?:#.*)?$')
                if (-not $m.Success) { continue }
                $k = $m.Groups[1].Value; $v = $m.Groups[2].Value
                switch ($k) {
                    'aliases' { $w.aliases = Get-PsKnYamlList -Raw $v -Lines $lines -Index $i }
                    'sources' { $w.sources = Get-PsKnYamlList -Raw $v -Lines $lines -Index $i }
                    'type' { if ($v -ne '') { $w.type = $v.ToUpperInvariant() } }
                    'origin' { $w.origin = $v }
                    'status' { $w.status = $v.ToLowerInvariant() }
                    'confidence' { $w.confidence = $v }
                    'last_verified' { $w.lastVerified = $v }
                    'reviewed' { $w.reviewed = ($v -match '^(?i)true$') }
                }
            }
        }
    }
    $heads = Get-PsKnHeadings -Lines $lines
    foreach ($h in $heads) {
        if ($h.Level -ne 2) { continue }
        $k = Get-PsKnSectionKey -Title $h.Title
        if ($k -match '^Observations') {
            for ($i = $h.Start; $i -lt $h.End; $i++) { if ($lines[$i] -match '^\s*-\s+\S') { $w.observations++ } }
        }
        elseif ($k -match '^Relations') {
            for ($i = $h.Start; $i -lt $h.End; $i++) {
                $m = [regex]::Match($lines[$i], '^\s*-\s*([A-Za-z_]+)\s+\[\[([^\]|#]+)')
                if ($m.Success) { $w.relations += , ([ordered]@{ type = $m.Groups[1].Value; target = $m.Groups[2].Value.Trim() }) }
            }
        }
        elseif ($k -match '^Invalidated') {
            for ($i = $h.Start; $i -lt $h.End; $i++) { if ($lines[$i] -match '^\s*-\s+\S') { $w.invalidated++ } }
        }
    }
    $w.links = Get-PsKnWikilinks -Text $text
    return $w
}

# ── 等級與有效性 ────────────────────────────────────────────────

function Get-PsKnNnGrade {
    param($Nn, $Audit, $Checklist, $AuditDone)
    $g = [ordered]@{ grade = 'UNAUDITED'; auditRound = 0; light = 'NONE'; fail = 0; disputed = 0; unverifiable = 0; pendingRepairs = 0; hashSinceAudit = 'unknown' }
    if ($null -ne $Audit -and $Audit.exists) { $g.auditRound = $Audit.round }
    if ($null -ne $Checklist -and $Checklist.pendingRepairs.Contains($Nn.file)) { $g.pendingRepairs = [int]$Checklist.pendingRepairs[$Nn.file] }
    if ($null -ne $AuditDone -and $AuditDone.exists -and $AuditDone.files.Contains($Nn.file)) {
        $h = [string]$AuditDone.files[$Nn.file]
        if ($h -ne '') { if ($h -ceq $Nn.hash) { $g.hashSinceAudit = 'same' } else { $g.hashSinceAudit = 'changed' } }
    }
    if ($Nn.status -eq 'BLOCKED') { $g.grade = 'BLOCKED' }
    elseif ($Nn.status -eq 'PARTIAL') { $g.grade = 'PARTIAL' }
    $row = $null
    if ($null -ne $Audit -and $Audit.exists -and $Audit.scorecard.Contains($Nn.file)) { $row = $Audit.scorecard[$Nn.file] }
    if ($null -ne $row) {
        $g.light = $row.light; $g.fail = $row.fail; $g.disputed = $row.disputed; $g.unverifiable = $row.unverifiable
    }
    if ($g.grade -eq 'UNAUDITED') {
        if ($null -eq $row -or $row.light -eq 'NOT_AUDITED') { $g.grade = 'UNAUDITED' }
        elseif ($row.fail -eq 0 -and $row.disputed -eq 0 -and $g.pendingRepairs -eq 0 -and $g.hashSinceAudit -ne 'changed') { $g.grade = 'AUDITED_CLEAN' }
        else { $g.grade = 'AUDITED_ISSUES' }
    }
    return $g
}

function Get-PsKnWikiEffective {
    param($Wiki, [string[]]$FailedRefs, [datetime]$AsOf)
    if ($Wiki.status -eq 'stale') { return 'stale' }
    foreach ($s in $Wiki.sources) {
        $mu = [regex]::Match([string]$s, $script:PsKnUuidRx)
        if ($mu.Success -and ($FailedRefs -contains $mu.Value.ToLowerInvariant())) { return 'STALE_BY_SOURCE' }
    }
    if ($Wiki.lastVerified -match '^\d{4}-\d{2}-\d{2}$') {
        $dt = [datetime]::MinValue
        if ([datetime]::TryParseExact($Wiki.lastVerified, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$dt)) {
            if (($AsOf - $dt).TotalDays -gt 90) { return 'EXPIRED' }
        }
    }
    if ($Wiki.status -eq 'verified' -or $Wiki.status -eq 'draft') { return $Wiki.status }
    return 'UNKNOWN'
}

# ── 建索引 ───────────────────────────────────────────────────────

$script:PsKnReservedNames = @('wiki', 'knowledge', 'supplemental', 'spec')

function Get-PsKnDomainDirs {
    param([string]$ResearchRoot)
    $out = @()
    if (-not [System.IO.Directory]::Exists($ResearchRoot)) { return , $out }
    foreach ($d in @(Get-ChildItem -LiteralPath $ResearchRoot -Directory -ErrorAction SilentlyContinue)) {
        if ($script:PsKnReservedNames -contains $d.Name.ToLowerInvariant()) { continue }
        if ($d.Name -match '^zz-.*-fixture$') { continue }
        $out += $d.FullName
    }
    $names = @()
    foreach ($p in $out) { $names += $p }
    $names = Sort-PsKnOrdinal -Items $names
    return , $names
}

function Build-PsKnowledgeIndex {
    param([string]$Root, [string]$LogRoot = '', [datetime]$AsOf = (Get-Date))
    $researchRoot = Join-Path $Root (Join-Path 'docs' 'ps-research')
    if ($LogRoot -eq '') { $LogRoot = Join-Path $Root 'auto-loop-logs' }
    $inputs = @()   # "相對路徑`n hash" 供世代 hash
    $idx = [ordered]@{
        schemaVersion = $script:PsKnowledgeSchemaVersion; generation = ''; builtAt = $AsOf.ToString('yyyy-MM-ddTHH:mm:ssK')
        domains = @(); nn = @(); objects = @(); wiki = @()
    }
    $wikiDir = Join-Path $researchRoot 'wiki'
    $wikiByName = [ordered]@{}
    $allFailedRefs = @()
    $auditByDomain = [ordered]@{}
    $nnList = @()
    foreach ($dd in (Get-PsKnDomainDirs -ResearchRoot $researchRoot)) {
        $domain = [System.IO.Path]::GetFileName($dd)
        $ov = Get-PsKnOverviewFacts -LiteralPath (Join-Path $dd '00-overview.md')
        $au = Get-PsKnAuditFacts -LiteralPath (Join-Path $dd '90-audit.md')
        $cl = Get-PsKnChecklistFacts -LiteralPath (Join-Path $dd 'checklist.md')
        $rc = Get-PsKnReceiptFacts -DomainDir $dd
        $done = Get-PsKnAuditDoneFacts -LogDir (Join-Path $LogRoot $domain) -DomainDir $dd
        $auditByDomain[$domain] = $au
        foreach ($u in $au.failedRefs) { if ($allFailedRefs -notcontains $u) { $allFailedRefs += $u } }
        if ($ov.exists) { $inputs += ($domain + '/00-overview.md' + "`n" + $ov.hash) }
        if ($au.exists) { $inputs += ($domain + '/90-audit.md' + "`n" + $au.hash) }
        if ($cl.exists) { $inputs += ($domain + '/checklist.md' + "`n" + $cl.hash) }
        if ($rc.exists) { $inputs += ($domain + '/graduation.json' + "`n" + $rc.hash) }
        if ($done.exists) { $inputs += ($domain + '/audit-done.json' + "`n" + $done.hash) }
        $files = @()
        foreach ($f in @(Get-ChildItem -LiteralPath $dd -File -ErrorAction SilentlyContinue)) { if (Test-PsKnIsNnFile -Name $f.Name) { $files += $f.Name } }
        $files = Sort-PsKnOrdinal -Items $files
        $nnCount = 0
        foreach ($name in $files) {
            $nn = Get-PsKnNnFacts -LiteralPath (Join-Path $dd $name) -Domain $domain
            if ($null -eq $nn) { continue }
            $nnCount++
            $inputs += ($domain + '/' + $name + "`n" + $nn.hash)
            $gr = Get-PsKnNnGrade -Nn $nn -Audit $au -Checklist $cl -AuditDone $done
            $tier = 0; $receiptStale = $true
            if ($rc.exists -and $rc.files.Contains($name)) { if ([string]$rc.files[$name] -ceq $nn.hash) { $tier = $rc.tier; $receiptStale = $false } }
            $entry = [ordered]@{
                domain = $domain; file = $name; path = ('docs/ps-research/' + $domain + '/' + $name)
                primaryObject = $nn.primaryObject; title = $nn.title; status = $nn.status; origin = $nn.origin
                grade = $gr.grade; auditRound = $gr.auditRound; light = $gr.light; fail = $gr.fail; disputed = $gr.disputed; unverifiable = $gr.unverifiable
                pendingRepairs = $gr.pendingRepairs; hashSinceAudit = $gr.hashSinceAudit; receiptTier = $tier; receiptStale = $receiptStale
                lineCount = $nn.lineCount; hash = $nn.hash
                sections = @($nn.sections); missingSections = @($nn.missingSections); duplicateSections = $nn.duplicateSections
                relatedObjects = @($nn.relatedObjects); fieldRows = $nn.fieldRows; fieldsNotApplicable = $nn.fieldsNotApplicable
                behaviorCounts = $nn.behaviorCounts; dataFlow = @($nn.dataFlow); executionHollow = $nn.executionHollow; permissionHollow = $nn.permissionHollow
                gaps = $nn.gaps; evidenceCount = $nn.evidence.Count; evidenceKinds = $nn.evidenceKinds; links = @($nn.links)
            }
            $nnList += , $entry
        }
        $idx.domains += , ([ordered]@{
                domain = $domain; nnCount = $nnCount; overview = $ov.exists; auditRound = $au.round; auditExists = $au.exists
                checklistRound = $cl.round; pendingRepairs = $cl.pendingRepairs.Count; pendingD = $cl.pendingD; pendingPlain = $cl.pendingPlain
                receiptTier = $rc.tier; receiptExists = $rc.exists; functionMap = @($ov.functionMap); domainGate = @($au.domainGate); auditDoneSource = $done.source
            })
    }
    $idx.nn = @($nnList)
    # wiki
    $wikiList = @()
    if ([System.IO.Directory]::Exists($wikiDir)) {
        $wf = @()
        foreach ($f in @(Get-ChildItem -LiteralPath $wikiDir -File -ErrorAction SilentlyContinue)) { if ($f.Extension -eq '.md' -and $f.Name -ne 'index.md') { $wf += $f.Name } }
        foreach ($name in (Sort-PsKnOrdinal -Items $wf)) {
            $w = Get-PsKnWikiFacts -LiteralPath (Join-Path $wikiDir $name)
            if ($null -eq $w) { continue }
            $inputs += ('wiki/' + $name + "`n" + $w.hash)
            $w.effective = Get-PsKnWikiEffective -Wiki $w -FailedRefs $allFailedRefs -AsOf $AsOf
            $w.referencedBy = @()
            foreach ($e in $nnList) { if ($e.links -contains $w.name) { $w.referencedBy += ($e.domain + '/' + $e.file) } }
            $w.path = ('docs/ps-research/wiki/' + $name)
            $wikiByName[$w.name] = $w
            $wikiList += , $w
        }
    }
    $idx.wiki = @($wikiList)
    # objects：(物件, NN) 一列；類型：wiki → 功能地圖 → UNKNOWN
    $typeByObject = @{}
    foreach ($d in $idx.domains) { foreach ($fm in $d.functionMap) { if ($fm.type -ne '' -and -not $typeByObject.ContainsKey($fm.object)) { $typeByObject[$fm.object] = $fm.type } } }
    $objs = @()
    foreach ($e in $nnList) {
        $seen = @{}
        $cands = @()
        $cands += , @($e.primaryObject, '主物件', 1)
        foreach ($ro in $e.relatedObjects) { $cands += , @($ro.name, $ro.role, $ro.line) }
        foreach ($l in $e.links) { $cands += , @($l, '連結', 0) }
        foreach ($c in $cands) {
            $n = [string]$c[0]
            if ($n -eq '' -or $seen.ContainsKey($n)) { continue }
            $seen[$n] = $true
            $t = 'UNKNOWN'
            if ($wikiByName.Contains($n)) { $t = $wikiByName[$n].type } elseif ($typeByObject.ContainsKey($n)) { $t = $typeByObject[$n] }
            $objs += , ([ordered]@{ object = $n; type = $t; domain = $e.domain; file = $e.file; role = [string]$c[1]; grade = $e.grade; line = [int]$c[2] })
        }
    }
    $idx.objects = @($objs)
    # 世代 hash：所有輸入（路徑＋hash）Ordinal 排序後 SHA256
    $sorted = Sort-PsKnOrdinal -Items $inputs
    $idx.generation = Get-PsKnTextHash -Text (($sorted -join "`n") + "`n")
    $idx.inputCount = $inputs.Count
    return $idx
}

# ── index.md（模型讀）────────────────────────────────────────────

function ConvertTo-PsKnCell {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    $v = $Value -replace '\|', '／'
    $v = $v -replace '\[\[', '⟦'
    $v = $v -replace '\]\]', '⟧'
    $v = $v -replace "[`r`n]+", ' '
    return $v.Trim()
}

function Get-PsKnLightText {
    param($E)
    if ($E.auditRound -le 0 -or $E.light -eq 'NONE') { return '無' }
    $mark = switch ($E.light) { 'GREEN' { '🟢' } 'YELLOW' { '🟡' } 'RED' { '🔴' } 'NOT_AUDITED' { '⛔' } default { '?' } }
    return ('第' + $E.auditRound + '輪' + $mark)
}

function ConvertTo-PsKnowledgeIndexMd {
    param($Index)
    $sb = New-Object System.Text.StringBuilder
    $nl = "`n"
    [void]$sb.Append('# 知識索引（機械產生，勿手改）').Append($nl).Append($nl)
    [void]$sb.Append('generation：' + $Index.generation.Substring(0, 16) + '　建置：' + $Index.builtAt + '　領域 ' + $Index.domains.Count + '　NN ' + $Index.nn.Count + '　wiki ' + $Index.wiki.Count + '　schema ' + $Index.schemaVersion).Append($nl).Append($nl)
    [void]$sb.Append('用法（讀取契約：.opencode/peoplesoft/knowledge-retrieval-contract.md）：grep（pattern=物件名或 alias，path=docs/ps-research/knowledge，include=index.md）取列；').Append($nl)
    [void]$sb.Append('NN 列的「節」欄＝節名@offset/limit（read 該 NN 檔時直接用 offset 與 limit；@缺＝該節不存在）；片段第一行必須是該節標題，否則以 grep 重新定位；').Append($nl)
    [void]$sb.Append('等級：AUDITED_CLEAN（可直接引用）／AUDITED_ISSUES／UNAUDITED／PARTIAL／BLOCKED（只當線索，關鍵結論要現查）。物件彙總表在同目錄 objects.md。重建：powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ps-knowledge.ps1 -Rebuild').Append($nl).Append($nl)
    [void]$sb.Append('## 領域').Append($nl).Append($nl)
    [void]$sb.Append('| 領域 | NN 數 | 稽核輪次 | 待補 | 未建 NN | tier（本機） |').Append($nl)
    [void]$sb.Append('|---|---|---|---|---|---|').Append($nl)
    foreach ($d in $Index.domains) {
        $tierTxt = '無'
        if ($d.receiptExists) { $tierTxt = [string]$d.receiptTier }
        [void]$sb.Append('| ' + (ConvertTo-PsKnCell $d.domain) + ' | ' + $d.nnCount + ' | ' + $d.auditRound + ' | ' + $d.pendingRepairs + ' | ' + ($d.pendingPlain + $d.pendingD) + ' | ' + $tierTxt + ' |').Append($nl)
    }
    [void]$sb.Append($nl).Append('## Wiki').Append($nl).Append($nl)
    [void]$sb.Append('| 物件 | 類型 | 狀態 | 有效性 | 人工 | last_verified | 來源數 | 引用NN | aliases |').Append($nl)
    [void]$sb.Append('|---|---|---|---|---|---|---|---|---|').Append($nl)
    foreach ($w in $Index.wiki) {
        $rev = '否'
        if ($w.reviewed) { $rev = '是' }
        [void]$sb.Append('| ' + (ConvertTo-PsKnCell $w.name) + ' | ' + (ConvertTo-PsKnCell $w.type) + ' | ' + $w.status + ' | ' + $w.effective + ' | ' + $rev + ' | ' + (ConvertTo-PsKnCell $w.lastVerified) + ' | ' + $w.sources.Count + ' | ' + $w.referencedBy.Count + ' | ' + (ConvertTo-PsKnCell ($w.aliases -join '、')) + ' |').Append($nl)
    }
    [void]$sb.Append($nl).Append('## NN').Append($nl).Append($nl)
    [void]$sb.Append('| 領域 | 檔 | 主物件 | 等級 | 狀態 | 稽核 | 節（名@offset/limit） | 證據 | 缺口 | 待補 | hash |').Append($nl)
    [void]$sb.Append('|---|---|---|---|---|---|---|---|---|---|---|').Append($nl)
    foreach ($e in $Index.nn) {
        $secParts = @()
        $shown = @{}
        foreach ($k in $script:PsKnNnSections) {
            $disp = $k
            if ($script:PsKnSectionDisplay.ContainsKey($k)) { $disp = $script:PsKnSectionDisplay[$k] }
            $r = Get-PsKnSectionRange -Sections $e.sections -Name $k -Level 2
            if ($null -ne $r) { $secParts += ($disp + '@' + $r.start + '/' + ([int]$r.end - [int]$r.start + 1)); $shown['2:' + $k] = $true }
            else { $secParts += ($disp + '@缺') }
        }
        foreach ($sec in @($e.sections)) {
            $kk = ([string]$sec.level + ':' + [string]$sec.name)
            if ($shown.ContainsKey($kk)) { continue }
            $shown[$kk] = $true
            $secParts += ([string]$sec.name + '@' + $sec.start + '/' + ([int]$sec.end - [int]$sec.start + 1))
        }
        if ([int]$e.duplicateSections -gt 0) { $secParts += ('重複標題×' + $e.duplicateSections) }
        $h8 = ''
        if ($e.hash.Length -ge 8) { $h8 = $e.hash.Substring(0, 8) }
        $obj = $e.primaryObject
        if ($e.file -match '-\d+\.md$') { $obj = $obj + '（續篇）' }
        [void]$sb.Append('| ' + (ConvertTo-PsKnCell $e.domain) + ' | ' + (ConvertTo-PsKnCell $e.file) + ' | ' + (ConvertTo-PsKnCell $obj) + ' | ' + $e.grade + ' | ' + $e.status + ' | ' + (Get-PsKnLightText $e) + ' | ' + (ConvertTo-PsKnCell ($secParts -join ';')) + ' | ' + $e.evidenceCount + ' | ' + $e.gaps + ' | ' + $e.pendingRepairs + ' | ' + $h8 + ' |').Append($nl)
    }
    return $sb.ToString()
}

# objects.md（模型讀）：物件彙總表，一物件一列——與 index.md 分檔，hub 物件不會吃掉 grep 的 100 筆上限
function ConvertTo-PsKnowledgeObjectsMd {
    param($Index)
    $sb = New-Object System.Text.StringBuilder
    $nl = "`n"
    [void]$sb.Append('# 物件索引（機械產生，勿手改）').Append($nl).Append($nl)
    [void]$sb.Append('generation：' + $Index.generation.Substring(0, 16) + '　物件 ' + $Index.objects.Count + '　用法：grep（pattern=\| <物件名> \|，path=docs/ps-research/knowledge，include=objects.md）；找到檔名後回 index.md 的 NN 列取節 offset/limit').Append($nl).Append($nl)
    [void]$sb.Append('## 物件').Append($nl).Append($nl)
    [void]$sb.Append('| 物件 | 類型 | 主物件於 | 引用NN數 | 引用於（角色；最多 10） |').Append($nl)
    [void]$sb.Append('|---|---|---|---|---|').Append($nl)
    $agg = [ordered]@{}
    foreach ($o in $Index.objects) {
        if (-not $agg.Contains($o.object)) { $agg[$o.object] = [ordered]@{ type = $o.type; primary = @(); refs = @() } }
        $a = $agg[$o.object]
        if ($a.type -eq 'UNKNOWN' -and $o.type -ne 'UNKNOWN') { $a.type = $o.type }
        if ($o.role -eq '主物件') { $a.primary += ($o.domain + '/' + $o.file) } else { $a.refs += ($o.domain + '/' + $o.file + '（' + $o.role + '）') }
    }
    $names = @()
    foreach ($k in $agg.Keys) { $names += [string]$k }
    foreach ($n in (Sort-PsKnOrdinal -Items $names)) {
        $a = $agg[$n]
        $refShown = @($a.refs)
        $more = ''
        if ($refShown.Count -gt 10) { $more = '、+' + ($refShown.Count - 10); $refShown = @($refShown[0 .. 9]) }
        [void]$sb.Append('| ' + (ConvertTo-PsKnCell $n) + ' | ' + (ConvertTo-PsKnCell $a.type) + ' | ' + (ConvertTo-PsKnCell ($a.primary -join '、')) + ' | ' + $a.refs.Count + ' | ' + (ConvertTo-PsKnCell (($refShown -join '、') + $more)) + ' |').Append($nl)
    }
    return $sb.ToString()
}

# ── 發布、檢查、查詢 ─────────────────────────────────────────────

function Get-PsKnowledgeDir {
    param([string]$Root)
    return (Join-Path $Root (Join-Path 'docs' (Join-Path 'ps-research' 'knowledge')))
}

function Publish-PsKnowledgeIndex {
    param([string]$Root, [string]$LogRoot = '', [datetime]$AsOf = (Get-Date))
    $idx = Build-PsKnowledgeIndex -Root $Root -LogRoot $LogRoot -AsOf $AsOf
    $dir = Get-PsKnowledgeDir -Root $Root
    [void](Remove-PsKnTempFiles -Directory $dir)
    $json = ConvertTo-PsKnJson -Value $idx
    $md = ConvertTo-PsKnowledgeIndexMd -Index $idx
    $om = ConvertTo-PsKnowledgeObjectsMd -Index $idx
    $ok1 = Write-PsKnAtomicText -LiteralPath (Join-Path $dir 'index.json') -Text ($json + "`n") -Bom $false
    $ok2 = Write-PsKnAtomicText -LiteralPath (Join-Path $dir 'index.md') -Text $md -Bom $false
    $ok3 = Write-PsKnAtomicText -LiteralPath (Join-Path $dir 'objects.md') -Text $om -Bom $false
    return [ordered]@{ generation = $idx.generation; domains = $idx.domains.Count; nn = $idx.nn.Count; wiki = $idx.wiki.Count; objects = $idx.objects.Count; dir = $dir; published = ($ok1 -and $ok2 -and $ok3) }
}

function Read-PsKnowledgeIndex {
    param([string]$Root)
    $p = Join-Path (Get-PsKnowledgeDir -Root $Root) 'index.json'
    $text = Read-PsKnText -LiteralPath $p
    if ($null -eq $text) { return $null }
    try { return ($text | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

# 回 @{ State = CURRENT|STALE|MISSING; Reason; DiskGeneration; LiveGeneration }
function Test-PsKnowledgeIndex {
    param([string]$Root, [string]$LogRoot = '')
    $disk = Read-PsKnowledgeIndex -Root $Root
    $mdPath = Join-Path (Get-PsKnowledgeDir -Root $Root) 'index.md'
    $omPath = Join-Path (Get-PsKnowledgeDir -Root $Root) 'objects.md'
    if ($null -eq $disk -or -not [System.IO.File]::Exists($mdPath) -or -not [System.IO.File]::Exists($omPath)) { return @{ State = 'MISSING'; Reason = '索引不存在或無法解析'; DiskGeneration = ''; LiveGeneration = '' } }
    $live = Build-PsKnowledgeIndex -Root $Root -LogRoot $LogRoot
    $dg = [string]$disk.generation
    if ($dg -ceq $live.generation) { return @{ State = 'CURRENT'; Reason = '世代一致'; DiskGeneration = $dg; LiveGeneration = $live.generation } }
    # 指出哪些檔變了（比對 nn／wiki hash）
    $changed = @()
    $was = @{}
    foreach ($e in @($disk.nn)) { $was[[string]$e.domain + '/' + [string]$e.file] = [string]$e.hash }
    foreach ($e in @($disk.wiki)) { $was['wiki/' + [string]$e.file] = [string]$e.hash }
    $now = @{}
    foreach ($e in $live.nn) { $now[$e.domain + '/' + $e.file] = $e.hash }
    foreach ($e in $live.wiki) { $now['wiki/' + $e.file] = $e.hash }
    foreach ($k in $now.Keys) { if (-not $was.ContainsKey($k)) { $changed += ('新增：' + $k) } elseif ($was[$k] -cne $now[$k]) { $changed += ('已修改：' + $k) } }
    foreach ($k in $was.Keys) { if (-not $now.ContainsKey($k)) { $changed += ('已刪除：' + $k) } }
    $reason = '世代不符'
    if ($changed.Count -gt 0) { $reason = '世代不符（' + (($changed | Sort-Object) -join '、') + '）' } else { $reason = '世代不符（稽核／checklist／收據等非 NN 輸入變動）' }
    return @{ State = 'STALE'; Reason = $reason; DiskGeneration = $dg; LiveGeneration = $live.generation; Changed = $changed }
}

# 依詞比對物件名／alias／功能名／檔名（OrdinalIgnoreCase 子字串）
function Find-PsKnowledge {
    param($Index, [string]$Term)
    $hits = [ordered]@{ nn = @(); wiki = @(); objects = @() }
    if ($null -eq $Index -or $Term -eq '') { return $hits }
    $cmp = [System.StringComparison]::OrdinalIgnoreCase
    foreach ($e in @($Index.nn)) {
        if (([string]$e.primaryObject).IndexOf($Term, $cmp) -ge 0 -or ([string]$e.title).IndexOf($Term, $cmp) -ge 0 -or ([string]$e.file).IndexOf($Term, $cmp) -ge 0) { $hits.nn += , $e }
    }
    foreach ($o in @($Index.objects)) { if (([string]$o.object).IndexOf($Term, $cmp) -ge 0) { $hits.objects += , $o } }
    foreach ($w in @($Index.wiki)) {
        $match = (([string]$w.name).IndexOf($Term, $cmp) -ge 0)
        if (-not $match) { foreach ($a in @($w.aliases)) { if (([string]$a).IndexOf($Term, $cmp) -ge 0) { $match = $true; break } } }
        if ($match) { $hits.wiki += , $w }
    }
    return $hits
}

# 讀某 NN 的某節（含子節）原文；回 @{ Start; End; Lines }；找不到回 $null
function Get-PsKnowledgeSlice {
    param([string]$LiteralPath, [string]$Section)
    $text = Read-PsKnText -LiteralPath $LiteralPath
    if ($null -eq $text) { return $null }
    $lines = Get-PsKnLines -Text $text
    $heads = Get-PsKnHeadings -Lines $lines
    $key = Get-PsKnSectionKey -Title $Section
    $sec = Find-PsKnSection -Headings $heads -Key $key
    if ($null -eq $sec) { $sec = Find-PsKnSection -Headings $heads -Key $key -Level 3 }
    if ($null -eq $sec) { return $null }
    return @{ Start = $sec.Start; End = $sec.End; Lines = @($lines[($sec.Start - 1) .. ($sec.End - 1)]) }
}
