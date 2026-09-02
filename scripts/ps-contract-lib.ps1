# ps-contract-lib.ps1 — Legacy Contract（issue #17 Phase 1）確定性函式庫
# 由 ps-contract.ps1 dot-source；測試組 scripts/tests/test-contract.ps1 直接 dot-source。PowerShell 5.1／7 皆可。
# 職責：NN 檔確定性抽取 → 單位切分（含控制項分頁）→ manifest → fragment 解析與不變量 → 台帳收據
#       → stable ID 派發 → canonical contract（JSON）→ deterministic render（spec.md）→ verify 收據判定 → G1～G18。
# 設計備忘：docs/design/legacy-contract-phase1-decision-memo.md；教訓：applied.md L108。
# 鐵律：模型只寫固定表格 fragment（legacy-contract-fragments.md）；ID／JSON／spec／判定／驗證結果全在本檔。
# 兩個已踩過的陷阱：(1) 字典若有名為 keys 的鍵，PowerShell 的 $dict.Keys 會回該鍵的值——序列化走 GetEnumerator、
# 欄位改名 recordKeys；(2) 排序一律 Ordinal（culture 排序跨機不定序，同 ps-graduation.ps1）。

$script:ContractSchemaVersion = 1

# ── 基礎 I/O ─────────────────────────────────────────────────────────────────
function Read-CtText {
    param([string]$LiteralPath)
    $t = [System.IO.File]::ReadAllText($LiteralPath)
    if ($t.Length -gt 0 -and [int]$t[0] -eq 0xFEFF) { $t = $t.Substring(1) }
    return $t
}

function Write-CtText {
    param([string]$LiteralPath, [string]$Text, [switch]$Bom)
    $dir = Split-Path -Parent $LiteralPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($LiteralPath, $Text, (New-Object System.Text.UTF8Encoding([bool]$Bom)))
}

function Get-CtNormalizedHash {
    param([string]$Text)
    $t = $Text.Replace("`r", "")
    if ($t.Length -gt 0 -and [int]$t[0] -eq 0xFEFF) { $t = $t.Substring(1) }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($t)) } finally { $sha.Dispose() }
    return ([System.BitConverter]::ToString($bytes)) -replace '-', ''
}

function Get-CtFileHash {
    param([string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath)) { return '' }
    return (Get-CtNormalizedHash -Text (Read-CtText -LiteralPath $LiteralPath))
}

function Get-CtSqlHash {
    param([string]$Sql)
    $norm = (($Sql -replace '\s+', ' ').Trim()).ToUpperInvariant()
    return (Get-CtNormalizedHash -Text $norm).Substring(0, 12).ToLowerInvariant()
}

function Sort-CtOrdinal {
    param([string[]]$Items)
    $a = @($Items)
    if ($a.Count -le 1) { return $a }
    [System.Array]::Sort($a, [System.StringComparer]::Ordinal)
    return $a
}

function ConvertTo-CtJsonString {
    param([string]$S)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $S.ToCharArray()) {
        $c = [int]$ch
        switch ($c) {
            34 { [void]$sb.Append('\"') }
            92 { [void]$sb.Append('\\') }
            8 { [void]$sb.Append('\b') }
            12 { [void]$sb.Append('\f') }
            10 { [void]$sb.Append('\n') }
            13 { [void]$sb.Append('\r') }
            9 { [void]$sb.Append('\t') }
            default {
                if ($c -lt 32) { [void]$sb.Append('\u' + $c.ToString('x4')) } else { [void]$sb.Append($ch) }
            }
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# canonical JSON：鍵序＝插入序（[ordered]）、2 空白縮排、LF、Unicode 原樣；禁用 ConvertTo-Json（跨版本文字不一致）
function ConvertTo-CtJson {
    param($Value, [int]$Indent = 0)
    $pad = ' ' * $Indent
    $pad2 = ' ' * ($Indent + 2)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) { return ([string]$Value) }
    if ($Value -is [string]) { return (ConvertTo-CtJsonString -S $Value) }
    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Count -eq 0) { return '{}' }
        $parts = @()
        $en = $Value.GetEnumerator()
        while ($en.MoveNext()) {
            $parts += ($pad2 + (ConvertTo-CtJsonString -S ([string]$en.Key)) + ': ' + (ConvertTo-CtJson -Value $en.Value -Indent ($Indent + 2)))
        }
        return "{`n" + ($parts -join ",`n") + "`n" + $pad + '}'
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @($Value)
        if ($items.Count -eq 0) { return '[]' }
        $parts = @()
        foreach ($it in $items) { $parts += ($pad2 + (ConvertTo-CtJson -Value $it -Indent ($Indent + 2))) }
        return "[`n" + ($parts -join ",`n") + "`n" + $pad + ']'
    }
    return (ConvertTo-CtJsonString -S ([string]$Value))
}

function Read-CtJsonFile {
    param([string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath)) { return $null }
    try { return ((Read-CtText -LiteralPath $LiteralPath) | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

# customization-profile.yaml 的 oracle.currentSchema（regex 讀，不需 YAML 解析器）；FILL_ME／空＝未知
function Get-CtCurrentSchema {
    param([string]$ProfilePath)
    if (-not (Test-Path -LiteralPath $ProfilePath)) { return '' }
    $t = Read-CtText -LiteralPath $ProfilePath
    if ($t -match '(?m)^\s*currentSchema:\s*(\S+)') { $v = $Matches[1].Trim(); if ($v -eq 'FILL_ME') { return '' }; return $v }
    return ''
}

# ── 值域（單一真相：legacy-contract-vocabulary.md） ──────────────────────────────
function Get-CtVocabulary {
    param([string]$LiteralPath)
    $text = Read-CtText -LiteralPath $LiteralPath
    $vocab = @{ Version = 0; Enums = @{}; Blacklist = @() }
    if ($text -match '(?m)^vocabularyVersion:\s*(\d+)') { $vocab.Version = [int]$Matches[1] }
    $cur = ''
    foreach ($ln in ($text -split "`r?`n")) {
        if ($ln -match '^##\s+(.+?)\s*$') { $cur = $Matches[1].Trim(); if (-not $vocab.Enums.ContainsKey($cur) -and $cur -ne '自由 token 黑名單') { $vocab.Enums[$cur] = New-Object System.Collections.Generic.List[string] }; continue }
        if ($cur -eq '') { continue }
        if ($ln -notmatch '^\s*\|') { continue }
        if ($ln -match '^\s*\|[\s:|-]+\|?\s*$') { continue }
        $cells = @($ln.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
        if ($cells.Count -lt 1) { continue }
        $v = $cells[0]
        if ($v -eq '值' -or $v -eq '字樣') { continue }
        if ($cur -eq '自由 token 黑名單') { $vocab.Blacklist += $v } else { $vocab.Enums[$cur].Add($v) }
    }
    return $vocab
}

function Test-CtEnum {
    param($Vocab, [string]$EnumName, [string]$Value)
    if (-not $Vocab.Enums.ContainsKey($EnumName)) { return $false }
    return ($Vocab.Enums[$EnumName] -ccontains $Value)
}

# ── Markdown 小工具 ─────────────────────────────────────────────────────────
function Get-CtSections {
    param([string]$Text)
    $map = [ordered]@{}
    $cur = ''
    $buf = New-Object System.Text.StringBuilder
    foreach ($ln in ($Text -split "`r?`n")) {
        if ($ln -match '^##\s+(.+?)\s*$') {
            if ($cur -ne '') { $map[$cur] = $buf.ToString() }
            $cur = $Matches[1].Trim()
            $buf = New-Object System.Text.StringBuilder
            continue
        }
        if ($cur -ne '') { [void]$buf.AppendLine($ln) }
    }
    if ($cur -ne '') { $map[$cur] = $buf.ToString() }
    return $map
}

function Get-CtTableRows {
    param([string]$SectionText)
    $header = $null
    $rows = @()
    $inTable = $false
    foreach ($ln in ($SectionText -split "`r?`n")) {
        if ($ln -notmatch '^\s*\|') { if ($inTable) { break } else { continue } }
        if ($ln -match '^\s*\|[\s:|-]+\|?\s*$') { $inTable = $true; continue }
        $cells = @($ln.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
        if ($null -eq $header) { $header = $cells; $inTable = $true; continue }
        $rows += , $cells
    }
    return @{ Header = $header; Rows = $rows }
}

function Test-CtHollow {
    param([string]$Body)
    $t = [regex]::Replace($Body, '(?s)<!--.*?-->', '')
    $t = [regex]::Replace($t, '(?m)^\s*[-*]?\s*<[^>]+>\s*$', '')
    $t = $t.Trim()
    if ($t -eq '') { return $true }
    if ($t -match '^[（(]\s*(無|同前|略)') { return $true }
    return $false
}

# ── NN 檔確定性抽取（分母來源；模型不參與） ────────────────────────────────
function Get-CtNnFacts {
    param([string]$LiteralPath)
    $text = Read-CtText -LiteralPath $LiteralPath
    $name = Split-Path -Leaf $LiteralPath
    $prefix = ''
    if ($name -match '^(\d\d)-') { $prefix = $Matches[1] }
    $f = [ordered]@{
        File = $name; Prefix = $prefix; Hash = (Get-CtNormalizedHash -Text $text); Component = ''; Title = ''
        Status = 'UNRESOLVED'; Origin = 'UNKNOWN'
        FieldRows = @(); FieldsNotApplicable = $false
        BehaviorLines = @(); UiStateLineCount = 0; SaveKeywordCount = 0
        DataFlowRows = @(); PermissionDeclared = $false
        EvidenceRows = @(); Gaps = @()
    }
    if ($text -match '(?m)^#\s+(.+?)\s*$') {
        $f.Title = $Matches[1].Trim()
        if ($f.Title -match '\[\[([^\]|]+)') { $f.Component = ($Matches[1].Trim()).ToUpperInvariant() }
    }
    if ($text -match '狀態[：:]\s*(COMPLETE|PARTIAL|BLOCKED)') { $f.Status = $Matches[1] }
    if ($text -match 'Origin[：:]\s*([A-Z_]+)') { $f.Origin = $Matches[1] }
    $sec = Get-CtSections -Text $text
    foreach ($k in @($sec.Keys)) {
        $kk = $k -replace '\s', ''
        if ($kk -match '^畫面與欄位') {
            $body = [string]$sec[$k]
            if ($body -match '（無') { $f.FieldsNotApplicable = $true }
            $tb = Get-CtTableRows -SectionText $body
            foreach ($r in $tb.Rows) {
                if ($r.Count -lt 2) { continue }
                $fld = $r[0].Trim().Trim('`').ToUpperInvariant()
                if ($fld -eq '' -or $fld -match '^欄位') { continue }
                if ($fld -match '\.') { $fld = ($fld -split '\.')[-1] }
                $f.FieldRows += , ([ordered]@{ Field = $fld; Label = $r[1]; Type = $(if ($r.Count -gt 2) { $r[2] } else { '' }); Choices = $(if ($r.Count -gt 3) { $r[3] } else { '' }); Life = $(if ($r.Count -gt 4) { $r[4] } else { '' }) })
            }
        }
        elseif ($kk -match '^行為邏輯') {
            foreach ($ln in ([string]$sec[$k] -split "`r?`n")) {
                if ($ln -notmatch '^\s*[-*]\s*(.+)$') { continue }
                $line = $Matches[1]
                $conf = 'NONE'
                if ($line -match '\b(CONFIRMED|INFERRED|DYNAMIC_RUNTIME)\b') { $conf = $Matches[1] }
                $ui = ($line -match '顯示|隱藏|唯讀|必填|開放|鎖定|停用|啟用|Visible|Enabled|DisplayOnly|Required')
                $save = ($line -match '存檔|寫入|新增|更新|刪除|INSERT|UPDATE|DELETE|Save')
                if ($ui) { $f.UiStateLineCount++ }
                if ($save) { $f.SaveKeywordCount++ }
                $f.BehaviorLines += , ([ordered]@{ Text = $line; Confidence = $conf; UiState = $ui; Save = $save })
            }
        }
        elseif ($kk -match '^資料流') {
            $tb = Get-CtTableRows -SectionText ([string]$sec[$k])
            foreach ($r in $tb.Rows) {
                if ($r.Count -lt 2) { continue }
                $tbl = $r[0].Trim().Trim('`').ToUpperInvariant()
                if ($tbl -eq '' -or $tbl -match '^表') { continue }
                $rec = $tbl -replace '^PS_', ''
                $op = $r[1].Trim().ToUpperInvariant()
                $f.DataFlowRows += , ([ordered]@{ Table = $tbl; Record = $rec; Op = $op; Source = $(if ($r.Count -gt 2) { $r[2] } else { '' }); Confidence = $(if ($r.Count -gt 3) { $r[3] } else { '' }) })
            }
        }
        elseif ($kk -match '^權限') {
            $f.PermissionDeclared = (-not (Test-CtHollow -Body ([string]$sec[$k])))
        }
        elseif ($kk -match '^未解事項') {
            foreach ($ln in ([string]$sec[$k] -split "`r?`n")) { if ($ln -match '^\s*[-*]\s*(.+)$') { $f.Gaps += $Matches[1] } }
        }
        elseif ($kk -match '^Evidence') {
            $tb = Get-CtTableRows -SectionText ([string]$sec[$k])
            $n = 0
            foreach ($r in $tb.Rows) {
                if ($r.Count -lt 2) { continue }
                $n++
                # 模板：SQL 型的 SELECT 在「位置」欄、keyRows 在「機器參照」欄；CHUNK 型 UUID 在「機器參照」欄——看整列
                $whole = ($r[1..($r.Count - 1)] -join ' ')
                $kind = 'UNRESOLVED'; $id = ''; $sql = ''
                if ($whole -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $kind = 'CHUNK'; $id = $Matches[1].ToLowerInvariant() }
                elseif ($whole -match '(?i)(select\s+.+?\s+from\s+[^`|]+)') { $kind = 'SQL'; $sql = $Matches[1].Trim('`').Trim() }
                elseif ($whole -match '待人工\s*SQL') { $kind = 'PENDING_MANUAL' }
                $f.EvidenceRows += , ([ordered]@{ N = $n; Kind = $kind; ChunkId = $id; Sql = $sql; Location = $r[1]; Description = $(if ($r.Count -gt 2) { $r[2] } else { '' }) })
            }
        }
    }
    return $f
}

function Get-CtNnFiles {
    param([string]$DomainDir)
    return @(Get-ChildItem -LiteralPath $DomainDir -Filter '*.md' -File | Where-Object { $_.Name -match '^\d\d-' -and $_.Name -notmatch '^(00|90)-' } | Sort-Object Name)
}

# ── Fragment 規格（標題／表頭逐字；欄位→值域） ───────────────────────────────────
function Get-CtFragmentSpec {
    $kv = 'kv'; $tb = 'table'
    $controls = @{ Type = $tb; Header = @('頁', 'Record.Field', '顯示文字', '語系', '控制型', '選項型', '選項', '預設', '可見', '可編輯', '必填', '證據'); Enums = @{ 3 = 'languageCode'; 4 = 'controlType'; 5 = 'choiceType'; 8 = 'yesNo'; 9 = 'yesNo'; 10 = 'yesNo' }; EvidenceCol = 11; KeyCol = 1 }
    return @{
        screen = [ordered]@{
            '畫面'     = @{ Type = $kv; Keys = @('component', 'pages', 'searchRecord', 'modes', 'menuPath', 'origin', 'sourceNn'); Enums = @{ modes = 'componentMode'; origin = 'origin' }; Multi = @('pages', 'modes', 'sourceNn') }
            '控制項'   = $controls
            '狀態'     = @{ Type = $tb; Header = @('目標 Record.Field', '屬性', '條件', '觸發事件', '解析', '證據'); Enums = @{ 1 = 'stateProperty'; 3 = 'eventTrigger'; 4 = 'resolution' }; EvidenceCol = 5; KeyCol = 0 }
            '互動'     = @{ Type = $tb; Header = @('觸發事件', '條件', '效果型', '目標', '說明', '證據'); Enums = @{ 0 = 'eventTrigger'; 2 = 'effectType' }; EvidenceCol = 5 }
            '驗證'     = @{ Type = $tb; Header = @('觸發事件', '條件', '訊息型', '訊息', '證據'); Enums = @{ 0 = 'eventTrigger'; 2 = 'messageKind' }; EvidenceCol = 4 }
            '導覽'     = @{ Type = $tb; Header = @('來源', '目標', '型', '證據'); Enums = @{ 2 = 'navigationKind' }; EvidenceCol = 3 }
            '業務操作' = @{ Type = $tb; Header = @('操作鍵', '觸發', '模式', '說明', '寫入', '證據'); Enums = @{ 1 = 'eventTrigger'; 2 = 'componentMode' }; EvidenceCol = 5; OpKeyCol = 0 }
            '權限'     = @{ Type = $tb; Header = @('Permission List', 'Role', '人數', 'Search Record', '證據'); Enums = @{}; EvidenceCol = 4 }
            '查詢證據' = @{ Type = $tb; Header = @('用途', 'SQL', '關鍵列'); Enums = @{}; SqlCol = 1 }
        }
        screenpage = [ordered]@{
            '畫面'     = @{ Type = $kv; Keys = @('component', 'page', 'sourceNn'); Enums = @{}; Multi = @('sourceNn') }
            '控制項'   = $controls
        }
        entity = [ordered]@{
            '實體'     = @{ Type = $kv; Keys = @('record', 'businessMeaning', 'storageKind', 'physicalObject', 'origin', 'domainGate', 'sourceNn'); Enums = @{ storageKind = 'storageKind'; origin = 'origin'; domainGate = 'domainGate' }; Multi = @('sourceNn') }
            '欄位'     = @{ Type = $tb; Header = @('Field', 'Column', '型別', '長度', '鍵', '必填', '選項來源', '證據'); Enums = @{ 2 = 'dataType'; 5 = 'yesNo' }; MultiEnums = @{ 4 = 'keyFlag' }; EvidenceCol = 7 }
            '鍵'       = @{ Type = $kv; Keys = @('psKeys', 'businessKey', 'physicalUniqueKey', 'parentRecord', 'rowIdentity'); Enums = @{}; Multi = @('psKeys', 'businessKey', 'physicalUniqueKey') }
            '生效日'   = @{ Type = $kv; Keys = @('effdtRule', 'asOf', 'selection', 'activeOnly'); Enums = @{ effdtRule = 'effdtRule'; asOf = 'asOfSource'; selection = 'effdtSelection'; activeOnly = 'yesNo' } }
            '讀取語意' = @{ Type = $tb; Header = @('型', '內容', '證據'); Enums = @{ 0 = 'readSemanticKind' }; EvidenceCol = 2 }
            '參考查詢' = @{ Type = $tb; Header = @('用途', 'SQL', '關鍵列', '狀態'); Enums = @{ 3 = 'referenceQueryState' }; SqlCol = 1 }
            '寫入'     = @{ Type = $tb; Header = @('操作鍵', '操作', '列選擇', '變更欄位', '伴隨效果', '證據'); Enums = @{ 1 = 'persistenceOperation' }; EvidenceCol = 5; OpKeyCol = 0 }
            '存取策略' = @{ Type = $kv; Keys = @('read', 'write', 'approvalRef'); Enums = @{ read = 'accessStrategy'; write = 'accessStrategy' } }
        }
        verify = [ordered]@{
            '查詢'     = @{ Type = $tb; Header = @('單位', '樣板', 'SQL', '關鍵列', '狀態'); Enums = @{ 1 = 'verifyCheck'; 4 = 'verifyQueryState' }; SqlCol = 2 }
            '欄位'     = @{ Type = $tb; Header = @('Field', 'Column', 'DATA_TYPE', 'DATA_LENGTH'); Enums = @{}; Optional = $true }
            '物件'     = @{ Type = $tb; Header = @('檢查', '值'); Enums = @{}; Optional = $true }
        }
    }
}

function Test-CtSelectOnly {
    param([string]$Sql)
    $s = $Sql.Trim().Trim('`').Trim()
    if ($s -eq '' -or $s -eq 'NOT_APPLICABLE') { return $false }
    if ($s -notmatch '^(?i)select\s') { return $false }
    if ($s -match '(?i)\b(insert|update|delete|merge|drop|alter|create|truncate|grant|revoke|begin|declare|execute|exec)\b') { return $false }
    if ($s -match ';') { return $false }
    if ($s -match '…|\.\.\.') { return $false }
    if ($s -notmatch '(?i)fetch\s+first\s+\d+\s+rows\s+only|rownum\s*<=?\s*\d+') { return $false }
    return $true
}

function Test-CtNaturalKey {
    param([string]$Value, [switch]$RecordField)
    if ($Value -eq '') { return $false }
    if ($Value -match '[\s;|]') { return $false }
    if ($RecordField) { return ($Value -match '^[A-Z0-9_#$]+\.[A-Z0-9_#$]+$') }
    return ($Value -match '^[A-Z0-9_#$]+$')
}

function ConvertTo-CtRecordField {
    param([string]$Value)
    $v = $Value.Trim().ToUpperInvariant()
    if ($v -match '^([A-Z0-9_#$]+)\.([A-Z0-9_#$]+)$') { return @{ Record = $Matches[1]; Field = $Matches[2] } }
    return $null
}

function Split-CtMulti {
    param([string]$Value)
    if ($Value -eq '' -or $Value -eq 'NOT_APPLICABLE' -or $Value -eq 'UNRESOLVED') { return @() }
    return @($Value -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

# 解析＋不變量。$ExpectedFields：本檔控制項表應覆蓋的欄位名清單（外環依 NN 分頁決定；空＝不約束）
# 回傳 [ordered]@{ Kind; Path; File; Hash; Lines; Sections; Invalid=@(); SourceNn; Component; PageIndex; CapacityEvent }
function Read-CtFragment {
    param([string]$LiteralPath, [string]$Kind, $Vocab, $NnFactsMap, [string[]]$ExpectedFields = @())
    $spec = (Get-CtFragmentSpec)[$Kind]
    $res = [ordered]@{ Kind = $Kind; Path = $LiteralPath; File = (Split-Path -Leaf $LiteralPath); Hash = ''; Lines = 0; Sections = [ordered]@{}; Invalid = @(); SourceNn = @(); Component = ''; PageIndex = 1; CapacityEvent = $false }
    if (-not (Test-Path -LiteralPath $LiteralPath)) { $res.Invalid += 'fragment 檔不存在'; return $res }
    $text = Read-CtText -LiteralPath $LiteralPath
    if ($text.Trim() -eq '') { $res.Invalid += 'fragment 檔空白'; return $res }
    $res.Hash = Get-CtNormalizedHash -Text $text
    $res.Lines = @($text -split "`r?`n").Count
    if ($res.Lines -gt 150) { $res.Invalid += "超過 150 行（$($res.Lines)）"; $res.CapacityEvent = $true }
    if ($text -match '```') { $res.Invalid += '含三反引號圍欄' }
    $leak = 0
    foreach ($k in @('"agent"', '"findings"', '"searchScope"', '"coverage"', '"dynamicRuntimeWarnings"', '"structureLines"')) { if ($text.Contains($k)) { $leak++ } }
    if ($leak -ge 2) { $res.Invalid += '含模型契約 JSON 洩漏'; $res.CapacityEvent = $true }
    foreach ($b in $Vocab.Blacklist) { if ($text.IndexOf($b, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $res.Invalid += "含自由 token「$b」"; break } }
    $sec = Get-CtSections -Text $text
    foreach ($name in $spec.Keys) {
        $sp = $spec[$name]
        if (-not $sec.Contains($name)) { if ($sp.ContainsKey('Optional') -and $sp.Optional) { continue }; $res.Invalid += "缺章節「## $name」"; continue }
        $tb = Get-CtTableRows -SectionText ([string]$sec[$name])
        if ($null -eq $tb.Header) { $res.Invalid += "「## $name」無表格"; continue }
        if ($sp.Type -eq 'kv') {
            if ($tb.Header.Count -lt 2 -or $tb.Header[0] -ne '鍵' -or $tb.Header[1] -ne '值') { $res.Invalid += "「## $name」表頭須為 | 鍵 | 值 |"; continue }
            $kvm = [ordered]@{}
            foreach ($r in $tb.Rows) { if ($r.Count -ge 2) { $kvm[$r[0]] = $r[1] } }
            foreach ($k in $sp.Keys) {
                if (-not $kvm.Contains($k)) { $res.Invalid += "「## $name」缺鍵 $k"; continue }
                $v = [string]$kvm[$k]
                if ($v -eq '') { $res.Invalid += "「## $name」鍵 $k 空值（缺值須寫 UNRESOLVED／NOT_APPLICABLE）"; continue }
                if ($sp.Enums.ContainsKey($k)) {
                    $vals = @($v)
                    if ($sp.Multi -contains $k) { $vals = @($v -split ';' | ForEach-Object { $_.Trim() }) }
                    foreach ($x in $vals) { if (-not (Test-CtEnum -Vocab $Vocab -EnumName $sp.Enums[$k] -Value $x)) { $res.Invalid += "「## $name」$k 值「$x」不在值域 $($sp.Enums[$k])" } }
                }
            }
            $res.Sections[$name] = @{ Kv = $kvm }
        }
        else {
            $hdrOk = ($tb.Header.Count -eq $sp.Header.Count)
            if ($hdrOk) { for ($i = 0; $i -lt $sp.Header.Count; $i++) { if ($tb.Header[$i] -ne $sp.Header[$i]) { $hdrOk = $false } } }
            if (-not $hdrOk) { $res.Invalid += "「## $name」表頭與規格不符（須逐字：| $($sp.Header -join ' | ') |）"; continue }
            $rows = @()
            $ri = 0
            foreach ($r in $tb.Rows) {
                $ri++
                if ($r.Count -ne $sp.Header.Count) { $res.Invalid += "「## $name」第 $ri 列欄數 $($r.Count) ≠ $($sp.Header.Count)"; continue }
                $allNa = $true
                for ($i = 0; $i -lt $r.Count; $i++) {
                    if ($r[$i] -eq '') { $res.Invalid += "「## $name」第 $ri 列第 $($i + 1) 欄空值" }
                    if ($r[$i] -ne 'NOT_APPLICABLE') { $allNa = $false }
                }
                if ($allNa) { $rows += , @{ Cells = $r; NotApplicable = $true; Row = $ri }; continue }
                foreach ($ci in $sp.Enums.Keys) {
                    $v = $r[[int]$ci]
                    if ($v -eq 'NOT_APPLICABLE' -or $v -eq 'UNRESOLVED') { continue }
                    if (-not (Test-CtEnum -Vocab $Vocab -EnumName $sp.Enums[$ci] -Value $v)) { $res.Invalid += "「## $name」第 $ri 列「$v」不在值域 $($sp.Enums[$ci])" }
                }
                if ($sp.ContainsKey('MultiEnums')) {
                    foreach ($ci in $sp.MultiEnums.Keys) {
                        foreach ($x in @($r[[int]$ci] -split ';' | ForEach-Object { $_.Trim() })) {
                            if ($x -eq 'NOT_APPLICABLE' -or $x -eq 'UNRESOLVED') { continue }
                            if (-not (Test-CtEnum -Vocab $Vocab -EnumName $sp.MultiEnums[$ci] -Value $x)) { $res.Invalid += "「## $name」第 $ri 列「$x」不在值域 $($sp.MultiEnums[$ci])" }
                        }
                    }
                }
                if ($sp.ContainsKey('KeyCol')) {
                    $nk = $r[$sp.KeyCol]
                    if ($nk -ne 'NOT_APPLICABLE' -and $nk -ne 'UNRESOLVED' -and -not (Test-CtNaturalKey -Value $nk -RecordField)) { $res.Invalid += "「## $name」第 $ri 列自然鍵「$nk」須為 RECORD.FIELD（大寫、恰一個點、無空白）" }
                }
                if ($sp.ContainsKey('OpKeyCol')) {
                    $ok = $r[$sp.OpKeyCol]
                    if ($ok -ne 'NOT_APPLICABLE' -and $ok -notmatch '^[A-Z][A-Z0-9_]{1,30}$') { $res.Invalid += "「## $name」第 $ri 列操作鍵「$ok」不符 ^[A-Z][A-Z0-9_]{1,30}$" }
                }
                if ($sp.ContainsKey('SqlCol')) {
                    $sqlv = $r[$sp.SqlCol]
                    if ($sqlv -ne 'NOT_APPLICABLE' -and -not (Test-CtSelectOnly -Sql $sqlv)) { $res.Invalid += "「## $name」第 $ri 列 SQL 非 SELECT-only、缺列數上限或含省略號" }
                }
                if ($name -eq '參考查詢' -and ($r[3] -eq 'EXECUTED' -or $r[3] -eq 'FAILED')) { $res.Invalid += "「## 參考查詢」第 $ri 列狀態「$($r[3])」由 verify 收據決定，fragment 只准 PENDING／NOT_APPLICABLE" }
                $rows += , @{ Cells = $r; NotApplicable = $false; Row = $ri }
            }
            $res.Sections[$name] = @{ Rows = $rows }
        }
    }
    # 語意不變量
    if (($Kind -eq 'screen' -or $Kind -eq 'screenpage') -and $res.Sections.Contains('畫面')) {
        $kvm = $res.Sections['畫面'].Kv
        $comp = [string]$kvm['component']
        $res.Component = $comp.ToUpperInvariant()
        if (-not (Test-CtNaturalKey -Value $comp)) { $res.Invalid += "component「$comp」須為大寫英數底線" }
        if ($Kind -eq 'screen') { if ($res.File -ne ("screen-" + $comp + ".md")) { $res.Invalid += "檔名須為 screen-$comp.md" } }
        else {
            $pg = [string]$kvm['page']
            if ($pg -notmatch '^\d+$' -or [int]$pg -lt 2) { $res.Invalid += "page 須為 ≥2 的整數（分頁序）" } else { $res.PageIndex = [int]$pg }
            if ($res.File -ne ("screen-" + $comp + "-p" + $pg + ".md")) { $res.Invalid += "檔名須為 screen-$comp-p$pg.md" }
        }
        $res.SourceNn = @([string]$kvm['sourceNn'] -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        # 控制項分頁覆蓋（鏡射 Test-AuditPart 範圍覆蓋）：本檔須恰好覆蓋外環指定的欄位清單
        if (@($ExpectedFields).Count -gt 0 -and $res.Sections.Contains('控制項')) {
            $got = @()
            foreach ($r in $res.Sections['控制項'].Rows) {
                if ($r.NotApplicable) { continue }
                $rf = ConvertTo-CtRecordField -Value $r.Cells[1]
                if ($rf) { $got += $rf.Field }
            }
            foreach ($ef in $ExpectedFields) { if ($got -notcontains $ef) { $res.Invalid += "「## 控制項」範圍未覆蓋欄位 $ef（本檔應含 manifest 列的每一個欄位）" } }
            foreach ($g in $got) { if ($ExpectedFields -notcontains $g) { $res.Invalid += "「## 控制項」欄位 $g 不在本檔範圍（manifest 未列）" } }
        }
    }
    if ($Kind -eq 'entity' -and $res.Sections.Contains('實體')) {
        $kvm = $res.Sections['實體'].Kv
        $rec = [string]$kvm['record']
        if (-not (Test-CtNaturalKey -Value $rec)) { $res.Invalid += "record「$rec」須為大寫英數底線" }
        if ($rec -match '^PS_') { $res.Invalid += 'record 不得含 PS_ 前綴（實體表名寫 physicalObject）' }
        if ($res.File -ne ("entity-" + $rec + ".md")) { $res.Invalid += "檔名須為 entity-$rec.md" }
        $sk = [string]$kvm['storageKind']; $po = [string]$kvm['physicalObject']
        if (@('DERIVED_WORK', 'SUBRECORD', 'OTHER_LOGICAL') -contains $sk -and $po -ne 'NOT_APPLICABLE') { $res.Invalid += "storageKind=$sk 時 physicalObject 必須 NOT_APPLICABLE" }
        if (@('SQL_TABLE', 'SQL_VIEW', 'TEMP_TABLE') -contains $sk -and $po -eq 'NOT_APPLICABLE') { $res.Invalid += "storageKind=$sk 時 physicalObject 不得 NOT_APPLICABLE（未知寫 UNRESOLVED）" }
        if ($res.Sections.Contains('存取策略')) {
            $as = $res.Sections['存取策略'].Kv
            if ([string]$as['read'] -eq 'DIRECT_DB_WRITE_APPROVED' -or [string]$as['write'] -eq 'DIRECT_DB_WRITE_APPROVED') { $res.Invalid += 'DIRECT_DB_WRITE_APPROVED 不得由模型填（只能來自 approvals.md）' }
            if ([string]$as['write'] -eq 'DIRECT_DB_READ') { $res.Invalid += 'write 不得為 DIRECT_DB_READ' }
        }
        if (@('DERIVED_WORK', 'SUBRECORD', 'OTHER_LOGICAL') -contains $sk -and $res.Sections.Contains('寫入')) {
            foreach ($r in $res.Sections['寫入'].Rows) { if (-not $r.NotApplicable) { $res.Invalid += "storageKind=$sk 不得有寫入效果"; break } }
        }
        $res.SourceNn = @([string]$kvm['sourceNn'] -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }
    # 證據 ref 解析：E<nn>.<n>（nn＝來源 NN 前兩碼、n≤該檔附錄列數）；SQL:<n>（screen→查詢證據、entity→參考查詢）
    if ($Kind -ne 'verify') {
        $byPrefix = @{}
        foreach ($nn in $res.SourceNn) {
            if ($NnFactsMap.Contains($nn)) { $byPrefix[$NnFactsMap[$nn].Prefix] = @($NnFactsMap[$nn].EvidenceRows).Count } else { $res.Invalid += "sourceNn「$nn」不是本領域 NN 檔" }
        }
        $sqlMax = 0
        if ($Kind -eq 'entity' -and $res.Sections.Contains('參考查詢')) { $sqlMax = @($res.Sections['參考查詢'].Rows | Where-Object { -not $_.NotApplicable }).Count }
        if ($Kind -eq 'screen' -and $res.Sections.Contains('查詢證據')) { $sqlMax = @($res.Sections['查詢證據'].Rows | Where-Object { -not $_.NotApplicable }).Count }
        foreach ($name in $res.Sections.Keys) {
            $sp = $spec[$name]
            if ($sp.Type -ne 'table' -or -not $sp.ContainsKey('EvidenceCol')) { continue }
            foreach ($r in $res.Sections[$name].Rows) {
                if ($r.NotApplicable) { continue }
                $ev = $r.Cells[$sp.EvidenceCol]
                if ($ev -eq 'UNRESOLVED') { continue }
                foreach ($tok in @($ev -split ';' | ForEach-Object { $_.Trim() })) {
                    if ($tok -match '^E(\d\d)\.(\d+)$') {
                        $pf = $Matches[1]; $n = [int]$Matches[2]
                        if (-not $byPrefix.ContainsKey($pf)) { $res.Invalid += "「## $name」第 $($r.Row) 列證據 $tok 的 NN 前綴 $pf 不在 sourceNn" }
                        elseif ($n -lt 1 -or $n -gt $byPrefix[$pf]) { $res.Invalid += "「## $name」第 $($r.Row) 列證據 $tok 超出該 NN 附錄列數（$($byPrefix[$pf])）" }
                    }
                    elseif ($tok -match '^SQL:(\d+)$') { if ([int]$Matches[1] -lt 1 -or [int]$Matches[1] -gt $sqlMax) { $res.Invalid += "「## $name」第 $($r.Row) 列證據 $tok 超出$(if ($Kind -eq 'screen') { '查詢證據' } else { '參考查詢' })列數（$sqlMax）" } }
                    else { $res.Invalid += "「## $name」第 $($r.Row) 列證據「$tok」不是 E<nn>.<n>／SQL:<n>／UNRESOLVED" }
                }
            }
        }
    }
    return $res
}

# ── 台帳（fragment 級收據＋單位頁大小） ────────────────────────────────────────
function Get-CtLedger {
    param([string]$LiteralPath)
    $led = [ordered]@{ schemaVersion = $script:ContractSchemaVersion; fragments = [ordered]@{}; pageSizes = [ordered]@{} }
    $j = Read-CtJsonFile -LiteralPath $LiteralPath
    if ($null -eq $j) { return $led }
    if ($null -ne $j.fragments) {
        foreach ($p in $j.fragments.PSObject.Properties) {
            $e = $p.Value
            $led.fragments[$p.Name] = [ordered]@{ kind = [string]$e.kind; hash = [string]$e.hash; status = [string]$e.status; reason = [string]$e.reason; attempts = [int]$e.attempts; nnHash = [string]$e.nnHash; lines = [int]$e.lines }
        }
    }
    if ($null -ne $j.pageSizes) { foreach ($p in $j.pageSizes.PSObject.Properties) { $led.pageSizes[$p.Name] = [int]$p.Value } }
    return $led
}

function Save-CtLedger {
    param([string]$LiteralPath, $Ledger)
    $sortedF = [ordered]@{}
    foreach ($k in (Sort-CtOrdinal -Items @($Ledger.fragments.Keys))) { $sortedF[$k] = $Ledger.fragments[$k] }
    $sortedP = [ordered]@{}
    foreach ($k in (Sort-CtOrdinal -Items @($Ledger.pageSizes.Keys))) { $sortedP[$k] = $Ledger.pageSizes[$k] }
    $out = [ordered]@{ schemaVersion = $Ledger.schemaVersion; fragments = $sortedF; pageSizes = $sortedP }
    Write-CtText -LiteralPath $LiteralPath -Text (ConvertTo-CtJson -Value $out)
}

# 單位清單：每個 NN → screen 主檔（控制項第 1 頁）＋控制項分頁檔（欄位數 > 頁大小時）；資料流 distinct Record → entity
function Get-CtUnits {
    param($NnFactsMap, $Ledger, [int]$DefaultPageSize = 30)
    $units = @()
    $recs = [ordered]@{}
    foreach ($nn in (Sort-CtOrdinal -Items @($NnFactsMap.Keys))) {
        $f = $NnFactsMap[$nn]
        if ($f.Component -eq '') { continue }
        $ps = $DefaultPageSize
        if ($null -ne $Ledger -and $Ledger.pageSizes.Contains($f.Component)) { $ps = [int]$Ledger.pageSizes[$f.Component] }
        if ($ps -lt 1) { $ps = 1 }
        $fields = @($f.FieldRows | ForEach-Object { $_.Field })
        $pages = @()
        if ($fields.Count -eq 0) { $pages += , @() }
        else { for ($s = 0; $s -lt $fields.Count; $s += $ps) { $e = [Math]::Min($fields.Count - 1, $s + $ps - 1); $pages += , @($fields[$s..$e]) } }
        $k = 0
        foreach ($pg in $pages) {
            $k++
            if ($k -eq 1) { $units += , ([ordered]@{ Kind = 'screen'; Key = $f.Component; File = "screen-$($f.Component).md"; SourceNn = @($nn); NnHash = $f.Hash; PageIndex = 1; PageFields = @($pg); PageSize = $ps; PageCount = $pages.Count }) }
            else { $units += , ([ordered]@{ Kind = 'screenpage'; Key = "$($f.Component)#$k"; File = "screen-$($f.Component)-p$k.md"; SourceNn = @($nn); NnHash = $f.Hash; PageIndex = $k; PageFields = @($pg); PageSize = $ps; PageCount = $pages.Count }) }
        }
        foreach ($d in $f.DataFlowRows) {
            if ($d.Record -eq '' -or $d.Record -match '^(UNRESOLVED|NOT_APPLICABLE)$') { continue }
            if (-not $recs.Contains($d.Record)) { $recs[$d.Record] = @() }
            if ($recs[$d.Record] -notcontains $nn) { $recs[$d.Record] += $nn }
        }
    }
    foreach ($r in (Sort-CtOrdinal -Items @($recs.Keys))) {
        $hashes = @($recs[$r] | ForEach-Object { $NnFactsMap[$_].Hash })
        $units += , ([ordered]@{ Kind = 'entity'; Key = $r; File = "entity-$r.md"; SourceNn = @($recs[$r]); NnHash = (Get-CtNormalizedHash -Text ($hashes -join "`n")); PageIndex = 0; PageFields = @(); PageSize = 0; PageCount = 0 })
    }
    return $units
}

function Get-CtEvidenceTokens {
    param($NnFacts)
    if (@($NnFacts.EvidenceRows).Count -eq 0) { return '無（證據欄只能寫 UNRESOLVED）' }
    return (($NnFacts.EvidenceRows | ForEach-Object { 'E' + $NnFacts.Prefix + '.' + $_.N + '=' + $_.Kind + '（' + ($_.Description -replace '[|;]', ' ') + '）' }) -join '；')
}

function New-CtManifest {
    param([string]$Domain, $Units, $NnFactsMap, [string]$PartsDir, [int]$K)
    $ln = @()
    $ln += "# Legacy Contract 批次 manifest（外環產生，模型唯讀——不得修改；只寫「## 輸出」列的檔）"
    $ln += "領域：$Domain"
    $ln += "fragment 規則：.opencode/peoplesoft/legacy-contract-fragments.md；值域：.opencode/peoplesoft/legacy-contract-vocabulary.md"
    $ln += "證據 token 只准逐字抄下列 E<nn>.<n>（nn＝來源 NN 檔前兩碼）、本 fragment 的 SQL:<n>、或 UNRESOLVED"
    $ln += "本批單位數：$(@($Units).Count)（上限 $K）"
    $ln += ""
    $i = 0
    foreach ($u in $Units) {
        $i++
        $ln += "## 單位 $i：$($u.Kind) $($u.Key)"
        $ln += "- 輸出檔：docs/ps-research/$Domain/contract-parts/$($u.File)"
        $ln += "- 來源 NN：" + (($u.SourceNn | ForEach-Object { "docs/ps-research/$Domain/$_" }) -join '；')
        foreach ($nn in $u.SourceNn) {
            $f = $NnFactsMap[$nn]
            $ln += "- $nn 預抽事實："
            if ($u.Kind -eq 'screen') {
                $ln += "  - Component：$($f.Component)；狀態：$($f.Status)；Origin：$($f.Origin)"
                if ($f.FieldsNotApplicable) { $ln += "  - 畫面與欄位：申報不適用（控制項表寫一列全 NOT_APPLICABLE）" }
                elseif (@($f.FieldRows).Count -eq 0) { $ln += "  - 畫面與欄位：無表格列（委派 @ps-ui-flow 盤點，證據抄進「## 查詢證據」；或寫 UNRESOLVED）" }
                else {
                    $ln += "  - 控制項表**本檔只寫**第 1 頁（第 1～$(@($u.PageFields).Count) 個欄位，共 $($u.PageCount) 頁）：" + (($f.FieldRows | Where-Object { $u.PageFields -contains $_.Field } | ForEach-Object { $_.Field + '（' + $_.Label + '）' }) -join '；')
                    if ($u.PageCount -gt 1) { $ln += "  - 其餘欄位由 screen-$($f.Component)-p2.md… 分頁檔承載（另列單位）；本檔不得寫它們" }
                }
                $ln += "  - 行為邏輯：$(@($f.BehaviorLines).Count) 列（UI 狀態類 $($f.UiStateLineCount)、存檔類 $($f.SaveKeywordCount)）"
                $ln += "  - 資料流：" + $(if (@($f.DataFlowRows).Count -eq 0) { '無' } else { (($f.DataFlowRows | ForEach-Object { $_.Record + ':' + $_.Op }) -join '；') })
                $ln += "  - 權限節：$(if ($f.PermissionDeclared) { '有內容' } else { '空／缺（權限表寫 UNRESOLVED）' })"
            }
            elseif ($u.Kind -eq 'screenpage') {
                $ln += "  - 分頁檔：只寫「## 畫面」（component／page=$($u.PageIndex)／sourceNn）＋「## 控制項」；本頁欄位（每個都要有一列、不多不少）：" + (($f.FieldRows | Where-Object { $u.PageFields -contains $_.Field } | ForEach-Object { $_.Field + '（' + $_.Label + '）' }) -join '；')
            }
            else {
                $ln += "  - 資料流中本 Record 的操作：" + (($f.DataFlowRows | Where-Object { $_.Record -eq $u.Key } | ForEach-Object { $_.Op + '（' + $_.Source + '）' }) -join '；')
                $ln += "  - 欄位表只列：鍵欄位、EFFDT／EFFSEQ／EFF_STATUS、NN 畫面與欄位提到的欄位（全欄位盤點不在本批）"
            }
            $ln += "  - 可用證據：" + (Get-CtEvidenceTokens -NnFacts $f)
        }
        $ln += ""
    }
    $ln += "## 輸出"
    foreach ($u in $Units) { $ln += "- docs/ps-research/$Domain/contract-parts/$($u.File)" }
    $path = Join-Path $PartsDir 'manifest.txt'
    Write-CtText -LiteralPath $path -Text (($ln -join "`r`n") + "`r`n") -Bom
    return $path
}

# ── Stable ID ────────────────────────────────────────────────────────────────
function Get-CtId {
    param([string]$Prefix, [string[]]$Parts)
    $p = @($Parts | ForEach-Object { ([string]$_).Trim().ToUpperInvariant() -replace '[^A-Z0-9_#$]', '_' })
    return ($Prefix + '.' + ($p -join '.'))
}

function Get-CtUniqueId {
    # base＋seen 字典：同自然鍵第二列 .2、第三列 .3（列序只影響同鍵重複列）
    param([string]$Base, $Seen)
    $n = 1; $id = $Base
    while ($Seen.ContainsKey($id)) { $n++; $id = $Base + '.' + $n }
    $Seen[$id] = $true
    return $id
}

function Get-CtTargetParts {
    # 目標若為 RECORD.FIELD 拆兩段（與 CTL 一致），否則單段
    param([string]$Target)
    $rf = ConvertTo-CtRecordField -Value $Target
    if ($rf) { return @($rf.Record, $rf.Field) }
    return @($Target)
}

function Resolve-CtEvidence {
    # E<nn>.<n>／SQL:<n>／UNRESOLVED → 證據物件清單＋staticEvidence 狀態
    param([string]$Ref, $NnFactsMap, [string[]]$SourceNn, $SqlRows, [string]$SqlKind = 'RQ')
    $list = @()
    if ($Ref -eq 'UNRESOLVED' -or $Ref -eq '') { return @{ Evidence = @(); State = 'UNRESOLVED' } }
    $byPrefix = @{}
    foreach ($nn in $SourceNn) { if ($NnFactsMap.Contains($nn)) { $byPrefix[$NnFactsMap[$nn].Prefix] = $NnFactsMap[$nn] } }
    $anyFail = $false; $anyPending = $false; $anyPass = $false
    foreach ($tok in @($Ref -split ';' | ForEach-Object { $_.Trim() })) {
        if ($tok -match '^E(\d\d)\.(\d+)$') {
            $pf = $Matches[1]; $n = [int]$Matches[2]
            $row = $null; $nf = $null
            if ($byPrefix.ContainsKey($pf)) { $nf = $byPrefix[$pf]; $row = @($nf.EvidenceRows | Where-Object { $_.N -eq $n }) | Select-Object -First 1 }
            if ($null -eq $row) { $anyFail = $true; $list += , ([ordered]@{ kind = 'UNRESOLVED'; ref = $tok; note = '附錄列不存在' }); continue }
            switch ($row.Kind) {
                'CHUNK' { $anyPass = $true; $list += , ([ordered]@{ kind = 'CHUNK'; ref = $tok; chunkId = $row.ChunkId; location = $row.Location; sourceNn = $nf.File }) }
                'SQL' { $anyPass = $true; $list += , ([ordered]@{ kind = 'SQL'; ref = $tok; sql = $row.Sql; location = $row.Location; sourceNn = $nf.File }) }
                'PENDING_MANUAL' { $anyPending = $true; $list += , ([ordered]@{ kind = 'PENDING_MANUAL'; ref = $tok; location = $row.Location; sourceNn = $nf.File }) }
                default { $anyFail = $true; $list += , ([ordered]@{ kind = 'UNRESOLVED'; ref = $tok; note = '附錄機器參照無效' }) }
            }
        }
        elseif ($tok -match '^SQL:(\d+)$') {
            $n = [int]$Matches[1]
            $row = $null
            if ($null -ne $SqlRows -and $n -ge 1 -and $n -le @($SqlRows).Count) { $row = $SqlRows[$n - 1] }
            if ($null -eq $row) { $anyFail = $true; $list += , ([ordered]@{ kind = 'UNRESOLVED'; ref = $tok; note = '查詢列不存在' }); continue }
            # 形狀已過 SELECT-only＝與既有 SQL 型證據同位階（執行真值交給 oracleRead 維度）
            $anyPass = $true
            if ($SqlKind -eq 'RQ') { $list += , ([ordered]@{ kind = 'SQL'; ref = $tok; referenceQueryId = $row.id }) }
            else { $list += , ([ordered]@{ kind = 'SQL'; ref = $tok; sql = $row.sql; keyRows = $row.keyRows }) }
        }
        else { $anyFail = $true; $list += , ([ordered]@{ kind = 'UNRESOLVED'; ref = $tok; note = '格式無效' }) }
    }
    $state = 'UNRESOLVED'
    if ($anyFail) { $state = 'FAIL' } elseif ($anyPending) { $state = 'UNRESOLVED' } elseif ($anyPass) { $state = 'PASS' }
    return @{ Evidence = $list; State = $state }
}

function New-CtVerification {
    param([string]$Static = 'UNRESOLVED', [string]$Schema = 'NOT_RUN', [string]$Read = 'NOT_APPLICABLE', [string]$Ui = 'NOT_RUN', [string]$Write = 'NOT_APPLICABLE')
    return [ordered]@{ staticEvidence = $Static; oracleSchemaVerification = $Schema; oracleReadVerification = $Read; uiRuntimeVerification = $Ui; writeEffectVerification = $Write }
}

# ── approvals.md（人填）：| Record | 操作鍵 | 策略 | 核准者 | 日期 | 證據 | ─────────
function Read-CtApprovals {
    param([string]$LiteralPath)
    $out = @()
    if (-not (Test-Path -LiteralPath $LiteralPath)) { return $out }
    $tb = Get-CtTableRows -SectionText (Read-CtText -LiteralPath $LiteralPath)
    if ($null -eq $tb.Header) { return $out }
    foreach ($r in $tb.Rows) {
        if ($r.Count -lt 6) { continue }
        if ($r[0] -match '^Record') { continue }
        $out += , ([ordered]@{ record = $r[0].ToUpperInvariant(); opKey = $r[1].ToUpperInvariant(); strategy = $r[2]; approver = $r[3]; date = $r[4]; evidence = $r[5] })
    }
    return $out
}

# ── Verify 單位與收據（一單位一委派一檔：OBJ／FLD-a-b／RQ-n） ──────────────────
function Get-CtVerifyUnits {
    param($Contract, [int]$FieldPageSize = 10)
    $units = @()
    foreach ($e in $Contract.dataEntities) {
        if ([string]$e.physicalObject -eq 'NOT_APPLICABLE') { continue }
        $rec = [string]$e.record
        $units += , ([ordered]@{ Record = $rec; Kind = 'OBJ'; File = "verify-$rec-OBJ.md"; Range = @(); Fields = @(); Rq = $null })
        $flds = @($e.fields | ForEach-Object { $_ })
        if ($flds.Count -gt 0) {
            $ps = [Math]::Max(1, $FieldPageSize)
            for ($s = 0; $s -lt $flds.Count; $s += $ps) {
                $en = [Math]::Min($flds.Count - 1, $s + $ps - 1)
                $units += , ([ordered]@{ Record = $rec; Kind = 'FLD'; File = "verify-$rec-FLD-$($s + 1)-$($en + 1).md"; Range = @(($s + 1), ($en + 1)); Fields = @($flds[$s..$en]); Rq = $null })
            }
        }
        $qi = 0
        foreach ($q in $e.referenceQueries) {
            $qi++
            if ([string]$q.state -eq 'NOT_APPLICABLE') { continue }
            $units += , ([ordered]@{ Record = $rec; Kind = 'RQ'; File = "verify-$rec-RQ-$qi.md"; Range = @(); Fields = @(); Rq = $q })
        }
    }
    return $units
}

# Oracle 型別 → 契約 dataType 的可接受對映（待公司機驗證；規則 6／8）
function Test-CtTypeCompatible {
    param([string]$Contract, [string]$Oracle)
    $o = $Oracle.ToUpperInvariant()
    switch ($Contract) {
        'CHAR' { return ($o -match '^(CHAR|VARCHAR2|NCHAR|NVARCHAR2)$') }
        'VARCHAR' { return ($o -match '^(VARCHAR2|NVARCHAR2|CHAR)$') }
        'NUMBER' { return ($o -match '^(NUMBER|FLOAT|INTEGER)$') }
        'SIGNED_NUMBER' { return ($o -match '^(NUMBER|FLOAT|INTEGER)$') }
        'DATE' { return ($o -match '^(DATE|TIMESTAMP)') }
        'TIME' { return ($o -match '^(TIMESTAMP|VARCHAR2|CHAR)') }
        'DATETIME' { return ($o -match '^(TIMESTAMP|DATE)') }
        'LONG_CHAR' { return ($o -match '^(CLOB|LONG|VARCHAR2|NCLOB)$') }
        'IMAGE' { return ($o -match '^(BLOB|LONG RAW)$') }
        'IMAGE_REF' { return ($o -match '^(BLOB|VARCHAR2)$') }
        'OTHER' { return $true }
        'UNRESOLVED' { return $true }
        default { return $false }
    }
}

# 讀全部 verify 收據並逐單位判定。回傳 @{ <RECORD> = @{ Units = [ordered]@{ <File> = @{ Kind; State(PASS/FAIL/NOT_RUN); Reason; Rows; Rq } } } }
function Read-CtVerifyReceipts {
    param([string]$PartsDir, $Vocab, $Contract, [int]$FieldPageSize = 10)
    $map = @{}
    if ($null -eq $Contract) { return $map }
    $expected = @(Get-CtVerifyUnits -Contract $Contract -FieldPageSize $FieldPageSize)
    $entByRec = @{}
    foreach ($e in $Contract.dataEntities) { $entByRec[[string]$e.record] = $e }
    foreach ($u in $expected) {
        if (-not $map.ContainsKey($u.Record)) { $map[$u.Record] = @{ Units = [ordered]@{} } }
        $path = Join-Path $PartsDir $u.File
        $st = 'NOT_RUN'; $reason = '無收據'; $rowsOut = @(); $invalid = @()
        if (Test-Path -LiteralPath $path) {
            $fr = Read-CtFragment -LiteralPath $path -Kind 'verify' -Vocab $Vocab -NnFactsMap @{}
            $invalid = @($fr.Invalid)
            if ($invalid.Count -gt 0) { $reason = '收據無效：' + $invalid[0] }
            else {
                $qrows = @($fr.Sections['查詢'].Rows | Where-Object { -not $_.NotApplicable })
                $states = @($qrows | ForEach-Object { $_.Cells[4] })
                if ($qrows.Count -eq 0) { $reason = '查詢表無列' }
                elseif (@($states | Where-Object { $_ -eq 'ORACLE_MCP_DOWN' -or $_ -eq 'BLOCKED' }).Count -gt 0) { $st = 'NOT_RUN'; $reason = '通道未掛或逾時' }
                else {
                    switch ($u.Kind) {
                        'OBJ' {
                            $exists = @($qrows | Where-Object { $_.Cells[1] -eq 'OBJECT_EXISTS' })
                            if ($exists.Count -eq 0) { $reason = '缺 OBJECT_EXISTS 查詢列' }
                            elseif (@($exists | Where-Object { $_.Cells[4] -eq 'NOT_FOUND' -or $_.Cells[4] -eq 'FAILED' }).Count -gt 0) { $st = 'FAIL'; $reason = '物件查無' }
                            else {
                                $st = 'PASS'; $reason = ''
                                if ($fr.Sections.Contains('物件')) {
                                    $ot = @($fr.Sections['物件'].Rows | Where-Object { -not $_.NotApplicable -and $_.Cells[0] -eq 'OBJECT_TYPE' }) | Select-Object -First 1
                                    if ($null -ne $ot) {
                                        $sk = [string]$entByRec[$u.Record].storageKind
                                        $v = $ot.Cells[1].ToUpperInvariant()
                                        if (($sk -eq 'SQL_TABLE' -or $sk -eq 'TEMP_TABLE') -and $v -ne 'TABLE') { $st = 'FAIL'; $reason = "OBJECT_TYPE=$v 與 storageKind=$sk 不符" }
                                        if (($sk -match 'VIEW$') -and $v -ne 'VIEW') { $st = 'FAIL'; $reason = "OBJECT_TYPE=$v 與 storageKind=$sk 不符" }
                                    }
                                }
                            }
                        }
                        'FLD' {
                            if (-not $fr.Sections.Contains('欄位')) { $reason = '缺「## 欄位」表' }
                            else {
                                $frows = @($fr.Sections['欄位'].Rows | Where-Object { -not $_.NotApplicable })
                                $st = 'PASS'; $reason = ''
                                foreach ($cf in $u.Fields) {
                                    $hit = @($frows | Where-Object { $_.Cells[0].ToUpperInvariant() -eq [string]$cf.field }) | Select-Object -First 1
                                    if ($null -eq $hit) { $st = 'FAIL'; $reason = "欄位 $($cf.field) 無收據列"; break }
                                    if ($hit.Cells[1] -eq 'NOT_FOUND' -or $hit.Cells[2] -eq 'NOT_FOUND') { $st = 'FAIL'; $reason = "欄位 $($cf.field) NOT_FOUND"; break }
                                    if (-not (Test-CtTypeCompatible -Contract ([string]$cf.dataType) -Oracle $hit.Cells[2])) { $st = 'FAIL'; $reason = "欄位 $($cf.field) 型別 $($cf.dataType) 與 Oracle $($hit.Cells[2]) 不符"; break }
                                    $rowsOut += , ([ordered]@{ field = [string]$cf.field; column = $hit.Cells[1]; dataType = $hit.Cells[2]; dataLength = $hit.Cells[3] })
                                }
                            }
                        }
                        'RQ' {
                            $q = @($qrows | Where-Object { $_.Cells[1] -eq 'REFERENCE_QUERY' -and $_.Cells[0] -eq [string]$u.Rq.id }) | Select-Object -First 1
                            if ($null -eq $q) { $reason = "缺單位 $($u.Rq.id) 的 REFERENCE_QUERY 列" }
                            elseif ((Get-CtSqlHash -Sql $q.Cells[2]) -ne [string]$u.Rq.sqlHash) { $reason = 'SQL 與契約不符（hash）' }
                            elseif ($q.Cells[4] -eq 'EXECUTED') { $st = 'PASS'; $reason = ''; $rowsOut += , ([ordered]@{ keyRows = $q.Cells[3] }) }
                            else { $st = 'FAIL'; $reason = "狀態 $($q.Cells[4])" }
                        }
                    }
                }
            }
        }
        $map[$u.Record].Units[$u.File] = @{ Kind = $u.Kind; State = $st; Reason = $reason; Rows = $rowsOut; Invalid = $invalid; Rq = $u.Rq }
    }
    return $map
}

function New-CtVerifyManifest {
    param([string]$Domain, $Contract, [string]$PartsDir, [int]$FieldPageSize, $Receipts)
    $units = @(Get-CtVerifyUnits -Contract $Contract -FieldPageSize $FieldPageSize)
    $todo = @()
    foreach ($u in $units) {
        $done = $false
        if ($null -ne $Receipts -and $Receipts.ContainsKey($u.Record) -and $Receipts[$u.Record].Units.Contains($u.File)) { $done = ($Receipts[$u.Record].Units[$u.File].State -eq 'PASS') }
        if (-not $done) { $todo += , $u }
    }
    $ln = @()
    $ln += "# Oracle schema 驗證 manifest（外環產生，模型唯讀）——一個單位＝一個委派＝一個收據檔；照 cookbook §7 樣板跑 SELECT"
    $ln += "領域：$Domain"
    $ln += "收據格式：.opencode/peoplesoft/legacy-contract-fragments.md「verify 收據」；同時 ≤3 個委派；通道未掛整表狀態寫 ORACLE_MCP_DOWN；結果不由模型判定"
    $ln += "待驗單位：$($todo.Count)（共 $($units.Count)）"
    $ln += ""
    $i = 0
    $entByRec = @{}
    foreach ($e in $Contract.dataEntities) { $entByRec[[string]$e.record] = $e }
    foreach ($u in $todo) {
        $i++
        $e = $entByRec[$u.Record]
        $ln += "## 單位 $i：$($u.Kind) $($u.Record)"
        $ln += "- 輸出檔：docs/ps-research/$Domain/contract-parts/$($u.File)"
        $ln += "- physicalObject：$($e.physicalObject)（UNRESOLVED 時先以 cookbook §6 PSRECDEFN 取 SQLTABLENAME）；storageKind：$($e.storageKind)"
        switch ($u.Kind) {
            'OBJ' {
                $ln += "- 樣板：§7a OBJECT_EXISTS＋OBJECT_TYPE；§7c RECTYPE；§7d／§7e KEY_METADATA（psKeys=$(if ($e.recordKeys.psKeys.Count) { $e.recordKeys.psKeys -join ';' } else { 'UNRESOLVED' })）$(if ($e.effectiveDating.rule -ne 'NONE' -and $e.effectiveDating.rule -ne 'UNRESOLVED') { '；§7f EFFDT_SHAPE' })"
                $ln += "- 「## 物件」表填：OBJECT_TYPE=<TABLE|VIEW>、RECTYPE=<值>、SQLTABLENAME=<值>、UNIQUE_INDEX=<欄位;…>"
            }
            'FLD' {
                $ln += "- 樣板：§7b ALL_TAB_COLUMNS（一次取整表，只抄本單位欄位）；本單位欄位第 $($u.Range[0])～$($u.Range[1])：" + (($u.Fields | ForEach-Object { [string]$_.field + '(' + [string]$_.dataType + ')' }) -join '；')
                $ln += "- 「## 欄位」表每欄一列：Field｜Column｜DATA_TYPE｜DATA_LENGTH；查無寫 NOT_FOUND"
            }
            'RQ' {
                $ln += "- 樣板：§7g REFERENCE_QUERY；「## 查詢」列的「單位」欄填 $($u.Rq.id)，SQL 逐字照下列（不得改寫）："
                $ln += "  $($u.Rq.sql)"
            }
        }
        $ln += ""
    }
    $ln += "## 輸出"
    foreach ($u in $todo) { $ln += "- docs/ps-research/$Domain/contract-parts/$($u.File)" }
    if (-not (Test-Path -LiteralPath $PartsDir)) { New-Item -ItemType Directory -Path $PartsDir -Force | Out-Null }
    $path = Join-Path $PartsDir 'verify-manifest.txt'
    Write-CtText -LiteralPath $path -Text (($ln -join "`r`n") + "`r`n") -Bom
    return @{ Path = $path; Todo = $todo.Count; Total = $units.Count }
}

# ── Merge：fragments → canonical contract ─────────────────────────────────────
function Merge-CtContract {
    param([string]$Domain, $Fragments, $NnFactsMap, $Approvals, $VerifyReceipts, $Vocab, [bool]$SchemaKnown = $false)
    $screens = [ordered]@{}
    $entities = [ordered]@{}
    $unresolvedRefs = @()
    foreach ($fr in ($Fragments | Where-Object { $_.Kind -eq 'entity' } | Sort-Object { $_.File })) {
        $kvm = $fr.Sections['實體'].Kv
        $rec = ([string]$kvm['record']).ToUpperInvariant()
        $sqlRows = @()
        $qi = 0
        foreach ($r in $fr.Sections['參考查詢'].Rows) {
            if ($r.NotApplicable) { continue }
            $qi++
            $sqlRows += , ([ordered]@{ id = (Get-CtId -Prefix 'RQ' -Parts @($rec, [string]$qi)); claimDomain = 'PERSISTENCE'; purpose = $r.Cells[0]; sql = $r.Cells[1]; sqlHash = (Get-CtSqlHash -Sql $r.Cells[1]); keyRows = $r.Cells[2]; state = 'PENDING'; oracleReadVerification = 'NOT_RUN' })
        }
        $fields = @()
        foreach ($r in $fr.Sections['欄位'].Rows) {
            if ($r.NotApplicable) { continue }
            $ev = Resolve-CtEvidence -Ref $r.Cells[7] -NnFactsMap $NnFactsMap -SourceNn $fr.SourceNn -SqlRows $sqlRows -SqlKind 'RQ'
            $fields += , ([ordered]@{ id = (Get-CtId -Prefix 'FLD' -Parts @($rec, $r.Cells[0])); claimDomain = 'PERSISTENCE'; field = $r.Cells[0].ToUpperInvariant(); column = $r.Cells[1]; dataType = $r.Cells[2]; length = $r.Cells[3]; keyFlags = @(Split-CtMulti -Value $r.Cells[4]); required = $r.Cells[5]; choiceSource = $r.Cells[6]; evidence = $ev.Evidence; verification = (New-CtVerification -Static $ev.State) })
        }
        $keysKv = $fr.Sections['鍵'].Kv
        $eff = $fr.Sections['生效日'].Kv
        $reads = @(); $seenR = @{}
        foreach ($r in $fr.Sections['讀取語意'].Rows) {
            if ($r.NotApplicable) { continue }
            $ev = Resolve-CtEvidence -Ref $r.Cells[2] -NnFactsMap $NnFactsMap -SourceNn $fr.SourceNn -SqlRows $sqlRows -SqlKind 'RQ'
            $rid = Get-CtUniqueId -Base (Get-CtId -Prefix 'RDS' -Parts @($rec, $r.Cells[0])) -Seen $seenR
            $reads += , ([ordered]@{ id = $rid; claimDomain = 'PERSISTENCE'; kind = $r.Cells[0]; content = $r.Cells[1]; evidence = $ev.Evidence; verification = (New-CtVerification -Static $ev.State) })
        }
        $writes = @(); $seenW = @{}
        foreach ($r in $fr.Sections['寫入'].Rows) {
            if ($r.NotApplicable) { continue }
            $wid = Get-CtUniqueId -Base (Get-CtId -Prefix 'WRT' -Parts @($rec, $r.Cells[0], $r.Cells[1])) -Seen $seenW
            $ev = Resolve-CtEvidence -Ref $r.Cells[5] -NnFactsMap $NnFactsMap -SourceNn $fr.SourceNn -SqlRows $sqlRows -SqlKind 'RQ'
            $writes += , ([ordered]@{ id = $wid; claimDomain = 'PERSISTENCE'; opKey = $r.Cells[0].ToUpperInvariant(); operation = $r.Cells[1]; rowSelection = $r.Cells[2]; changedFields = @(Split-CtMulti -Value $r.Cells[3]); companionEffects = @(Split-CtMulti -Value $r.Cells[4]); evidence = $ev.Evidence; verification = (New-CtVerification -Static $ev.State -Write 'NOT_RUN') })
        }
        $acc = $fr.Sections['存取策略'].Kv
        $readStrategy = [string]$acc['read']; $writeStrategy = [string]$acc['write']; $approvalRef = 'NOT_APPLICABLE'
        foreach ($a in $Approvals) {
            if ($a.record -eq $rec -and $a.strategy -eq 'DIRECT_DB_WRITE_APPROVED' -and $a.approver -ne '' -and $a.date -ne '' -and $a.evidence -ne '') { $writeStrategy = 'DIRECT_DB_WRITE_APPROVED'; $approvalRef = "$($a.approver)@$($a.date)" }
        }
        # Oracle schema／read 驗證：只來自 verify 收據（外環判定），且 currentSchema 未知時一律 NOT_RUN
        $sk = [string]$kvm['storageKind']
        $schemaState = 'NOT_RUN'; $schemaNote = ''
        if (@('DERIVED_WORK', 'SUBRECORD', 'OTHER_LOGICAL') -contains $sk) { $schemaState = 'NOT_APPLICABLE' }
        elseif (-not $SchemaKnown) { $schemaNote = 'currentSchema 未回填（customization-profile.yaml）——收據一律不採信' }
        elseif ($null -ne $VerifyReceipts -and $VerifyReceipts.ContainsKey($rec)) {
            $us = $VerifyReceipts[$rec].Units
            $structural = @($us.Keys | Where-Object { $us[$_].Kind -ne 'RQ' })
            if ($structural.Count -gt 0) {
                $fails = @($structural | Where-Object { $us[$_].State -eq 'FAIL' })
                $nr = @($structural | Where-Object { $us[$_].State -eq 'NOT_RUN' })
                if ($fails.Count -gt 0) { $schemaState = 'FAIL'; $schemaNote = ($fails | ForEach-Object { $_ + '：' + $us[$_].Reason }) -join '；' }
                elseif ($nr.Count -gt 0) { $schemaState = 'NOT_RUN'; $schemaNote = ($nr | ForEach-Object { $_ + '：' + $us[$_].Reason }) -join '；' }
                else { $schemaState = 'PASS' }
            }
            foreach ($q in $sqlRows) {
                $ufile = @($us.Keys | Where-Object { $us[$_].Kind -eq 'RQ' -and $null -ne $us[$_].Rq -and [string]$us[$_].Rq.id -eq $q.id }) | Select-Object -First 1
                if ($null -ne $ufile) {
                    $r = $us[$ufile]
                    if ($r.State -eq 'PASS') { $q.state = 'EXECUTED'; $q.oracleReadVerification = 'PASS'; if ($r.Rows.Count -gt 0) { $q.keyRows = [string]$r.Rows[0].keyRows } }
                    elseif ($r.State -eq 'FAIL') { $q.state = 'FAILED'; $q.oracleReadVerification = 'FAIL' }
                }
            }
        }
        $entity = [ordered]@{
            id = (Get-CtId -Prefix 'ENT' -Parts @($rec)); claimDomain = 'PERSISTENCE'; record = $rec
            businessMeaning = [string]$kvm['businessMeaning']; storageKind = $sk; physicalObject = [string]$kvm['physicalObject']
            origin = [string]$kvm['origin']; domainGate = [string]$kvm['domainGate']; sourceNn = @($fr.SourceNn)
            fields = $fields
            recordKeys = [ordered]@{ psKeys = @(Split-CtMulti -Value ([string]$keysKv['psKeys'])); businessKey = @(Split-CtMulti -Value ([string]$keysKv['businessKey'])); physicalUniqueKey = [string]$keysKv['physicalUniqueKey']; parentRecord = [string]$keysKv['parentRecord']; rowIdentity = [string]$keysKv['rowIdentity'] }
            effectiveDating = [ordered]@{ rule = [string]$eff['effdtRule']; asOf = [string]$eff['asOf']; selection = [string]$eff['selection']; activeOnly = [string]$eff['activeOnly'] }
            readSemantics = $reads; referenceQueries = $sqlRows; writeSemantics = $writes
            accessStrategy = [ordered]@{ read = $readStrategy; write = $writeStrategy; approvalRef = $approvalRef }
            verification = (New-CtVerification -Static 'NOT_APPLICABLE' -Schema $schemaState)
            schemaNote = $schemaNote
            fragment = [ordered]@{ file = $fr.File; hash = $fr.Hash }
        }
        $entities[$rec] = $entity
    }
    # screen：主檔＋分頁檔（控制項依頁序串接後再派 ID）
    $pagesByComp = @{}
    foreach ($fr in ($Fragments | Where-Object { $_.Kind -eq 'screenpage' })) { if (-not $pagesByComp.ContainsKey($fr.Component)) { $pagesByComp[$fr.Component] = @() }; $pagesByComp[$fr.Component] += , $fr }
    foreach ($fr in ($Fragments | Where-Object { $_.Kind -eq 'screen' } | Sort-Object { $_.File })) {
        $kvm = $fr.Sections['畫面'].Kv
        $comp = ([string]$kvm['component']).ToUpperInvariant()
        $qRows = @()
        if ($fr.Sections.Contains('查詢證據')) { foreach ($r in $fr.Sections['查詢證據'].Rows) { if (-not $r.NotApplicable) { $qRows += , ([ordered]@{ purpose = $r.Cells[0]; sql = $r.Cells[1]; keyRows = $r.Cells[2] }) } } }
        $ctlRows = @()
        foreach ($r in $fr.Sections['控制項'].Rows) { if (-not $r.NotApplicable) { $ctlRows += , @{ Row = $r; Page = 1 } } }
        $pageFiles = @()
        if ($pagesByComp.ContainsKey($comp)) { foreach ($pf in ($pagesByComp[$comp] | Sort-Object { $_.PageIndex })) { $pageFiles += $pf.File; foreach ($r in $pf.Sections['控制項'].Rows) { if (-not $r.NotApplicable) { $ctlRows += , @{ Row = $r; Page = $pf.PageIndex } } } } }
        $controls = @(); $seenC = @{}
        foreach ($cr in $ctlRows) {
            $r = $cr.Row
            $rf = ConvertTo-CtRecordField -Value $r.Cells[1]
            $base = $(if ($rf) { Get-CtId -Prefix 'CTL' -Parts @($comp, $r.Cells[0], $rf.Record, $rf.Field) } else { Get-CtId -Prefix 'CTL' -Parts @($comp, $r.Cells[0], $r.Cells[1]) })
            $cid = Get-CtUniqueId -Base $base -Seen $seenC
            $choices = @()
            foreach ($c in (Split-CtMulti -Value $r.Cells[6])) { if ($c -match '^(.*)=([^=]*)$') { $choices += , ([ordered]@{ label = $Matches[1].Trim(); storedValue = $Matches[2].Trim() }) } else { $choices += , ([ordered]@{ label = $c; storedValue = 'UNRESOLVED' }) } }
            $ev = Resolve-CtEvidence -Ref $r.Cells[11] -NnFactsMap $NnFactsMap -SourceNn $fr.SourceNn -SqlRows $qRows -SqlKind 'QE'
            $controls += , ([ordered]@{ id = $cid; claimDomain = 'BEHAVIOR'; page = $r.Cells[0].ToUpperInvariant(); record = $(if ($rf) { $rf.Record } else { 'UNRESOLVED' }); field = $(if ($rf) { $rf.Field } else { $r.Cells[1] }); label = $r.Cells[2]; languageCode = $r.Cells[3]; controlType = $r.Cells[4]; choiceType = $r.Cells[5]; choices = $choices; default = $r.Cells[7]; visible = $r.Cells[8]; editable = $r.Cells[9]; required = $r.Cells[10]; fragmentPage = $cr.Page; evidence = $ev.Evidence; verification = (New-CtVerification -Static $ev.State) })
        }
        $states = @(); $seenS = @{}
        foreach ($r in $fr.Sections['狀態'].Rows) {
            if ($r.NotApplicable) { continue }
            $sid = Get-CtUniqueId -Base (Get-CtId -Prefix 'STA' -Parts (@($comp) + (Get-CtTargetParts -Target $r.Cells[0]) + @($r.Cells[1]))) -Seen $seenS
            $ev = Resolve-CtEvidence -Ref $r.Cells[5] -NnFactsMap $NnFactsMap -SourceNn $fr.SourceNn -SqlRows $qRows -SqlKind 'QE'
            $tgt = @($controls | Where-Object { ($_.record + '.' + $_.field) -eq $r.Cells[0].ToUpperInvariant() } | ForEach-Object { $_.id })
            $states += , ([ordered]@{ id = $sid; claimDomain = 'BEHAVIOR'; target = $r.Cells[0].ToUpperInvariant(); targetControlIds = $tgt; property = $r.Cells[1]; condition = $r.Cells[2]; trigger = $r.Cells[3]; resolution = $r.Cells[4]; evidence = $ev.Evidence; verification = (New-CtVerification -Static $ev.State) })
        }
        $interactions = @(); $seenI = @{}
        foreach ($r in $fr.Sections['互動'].Rows) {
            if ($r.NotApplicable) { continue }
            $iid = Get-CtUniqueId -Base (Get-CtId -Prefix 'INT' -Parts (@($comp, $r.Cells[0], $r.Cells[2]) + (Get-CtTargetParts -Target $r.Cells[3]))) -Seen $seenI
            $ev = Resolve-CtEvidence -Ref $r.Cells[5] -NnFactsMap $NnFactsMap -SourceNn $fr.SourceNn -SqlRows $qRows -SqlKind 'QE'
            $interactions += , ([ordered]@{ id = $iid; claimDomain = 'BEHAVIOR'; trigger = $r.Cells[0]; condition = $r.Cells[1]; effects = @([ordered]@{ order = 1; effectType = $r.Cells[2]; target = $r.Cells[3]; note = $r.Cells[4] }); evidence = $ev.Evidence; verification = (New-CtVerification -Static $ev.State) })
        }
        $validations = @(); $seenV = @{}
        foreach ($r in $fr.Sections['驗證'].Rows) {
            if ($r.NotApplicable) { continue }
            $vid = Get-CtUniqueId -Base (Get-CtId -Prefix 'VAL' -Parts @($comp, $r.Cells[0], $r.Cells[2], $r.Cells[3])) -Seen $seenV
            $ev = Resolve-CtEvidence -Ref $r.Cells[4] -NnFactsMap $NnFactsMap -SourceNn $fr.SourceNn -SqlRows $qRows -SqlKind 'QE'
            $validations += , ([ordered]@{ id = $vid; claimDomain = 'BEHAVIOR'; trigger = $r.Cells[0]; condition = $r.Cells[1]; messageKind = $r.Cells[2]; message = $r.Cells[3]; evidence = $ev.Evidence; verification = (New-CtVerification -Static $ev.State) })
        }
        $navs = @(); $seenN = @{}
        foreach ($r in $fr.Sections['導覽'].Rows) {
            if ($r.NotApplicable) { continue }
            $nid = Get-CtUniqueId -Base (Get-CtId -Prefix 'NAV' -Parts @($comp, $r.Cells[0], $r.Cells[1], $r.Cells[2])) -Seen $seenN
            $ev = Resolve-CtEvidence -Ref $r.Cells[3] -NnFactsMap $NnFactsMap -SourceNn $fr.SourceNn -SqlRows $qRows -SqlKind 'QE'
            $navs += , ([ordered]@{ id = $nid; claimDomain = 'BEHAVIOR'; from = $r.Cells[0]; to = $r.Cells[1]; kind = $r.Cells[2]; evidence = $ev.Evidence; verification = (New-CtVerification -Static $ev.State) })
        }
        $ops = @(); $effects = @()
        foreach ($r in $fr.Sections['業務操作'].Rows) {
            if ($r.NotApplicable) { continue }
            $opKey = $r.Cells[0].ToUpperInvariant()
            $ev = Resolve-CtEvidence -Ref $r.Cells[5] -NnFactsMap $NnFactsMap -SourceNn $fr.SourceNn -SqlRows $qRows -SqlKind 'QE'
            $effIds = @(); $seenE = @{}
            foreach ($w in (Split-CtMulti -Value $r.Cells[4])) {
                if ($w -notmatch '^([A-Z0-9_#$]+):([A-Z_]+)$') { $unresolvedRefs += "BOP $comp/$opKey 寫入「$w」格式非 RECNAME:OPERATION"; continue }
                $wrec = $Matches[1] -replace '^PS_', ''; $wop = $Matches[2]
                $eid = Get-CtUniqueId -Base (Get-CtId -Prefix 'EFF' -Parts @($comp, $opKey, $wrec, $wop)) -Seen $seenE
                $entRef = 'UNRESOLVED'; $writeRef = 'UNRESOLVED'; $wevState = 'UNRESOLVED'; $wev = @()
                if ($entities.Contains($wrec)) {
                    $entRef = $entities[$wrec].id
                    $match = @($entities[$wrec].writeSemantics | Where-Object { $_.opKey -eq $opKey -and $_.operation -eq $wop }) | Select-Object -First 1
                    if ($null -ne $match) { $writeRef = $match.id; $wevState = $match.verification.staticEvidence; $wev = $match.evidence }
                    else { $unresolvedRefs += "EFF $eid：entity-$wrec.md 寫入表無 操作鍵 $opKey／操作 $wop" }
                }
                else { $unresolvedRefs += "EFF $eid：無 entity-$wrec.md fragment" }
                $effects += , ([ordered]@{ id = $eid; claimDomain = 'PERSISTENCE'; businessOperationId = (Get-CtId -Prefix 'BOP' -Parts @($comp, $opKey)); dataEntityId = $entRef; record = $wrec; operation = $wop; writeSemanticsId = $writeRef; evidence = $wev; verification = (New-CtVerification -Static $wevState -Write 'NOT_RUN') })
                $effIds += $eid
            }
            $ops += , ([ordered]@{ id = (Get-CtId -Prefix 'BOP' -Parts @($comp, $opKey)); claimDomain = 'BEHAVIOR'; opKey = $opKey; trigger = $r.Cells[1]; mode = $r.Cells[2]; description = $r.Cells[3]; persistenceEffectIds = $effIds; noPersistence = ($r.Cells[4] -eq 'NOT_APPLICABLE'); evidence = $ev.Evidence; verification = (New-CtVerification -Static $ev.State) })
        }
        $perms = @()
        foreach ($r in $fr.Sections['權限'].Rows) {
            if ($r.NotApplicable) { continue }
            $ev = Resolve-CtEvidence -Ref $r.Cells[4] -NnFactsMap $NnFactsMap -SourceNn $fr.SourceNn -SqlRows $qRows -SqlKind 'QE'
            $perms += , ([ordered]@{ permissionList = $r.Cells[0]; role = $r.Cells[1]; userCount = $r.Cells[2]; searchRecord = $r.Cells[3]; evidence = $ev.Evidence; verification = (New-CtVerification -Static $ev.State) })
        }
        $screens[$comp] = [ordered]@{
            id = (Get-CtId -Prefix 'SCR' -Parts @($comp)); claimDomain = 'BEHAVIOR'; component = $comp
            pages = @(Split-CtMulti -Value ([string]$kvm['pages'])); searchRecord = [string]$kvm['searchRecord']; modes = @(Split-CtMulti -Value ([string]$kvm['modes'])); menuPath = [string]$kvm['menuPath']; origin = [string]$kvm['origin']; sourceNn = @($fr.SourceNn)
            controls = $controls; states = $states; interactions = $interactions; validations = $validations; navigation = $navs; businessOperations = $ops; persistenceEffects = $effects; security = $perms
            queryEvidence = $qRows
            fragment = [ordered]@{ file = $fr.File; hash = $fr.Hash; pageFiles = $pageFiles }
        }
    }
    $contract = [ordered]@{
        schemaVersion = $script:ContractSchemaVersion; vocabularyVersion = $Vocab.Version; domain = $Domain
        screens = @((Sort-CtOrdinal -Items @($screens.Keys)) | ForEach-Object { $screens[$_] })
        dataEntities = @((Sort-CtOrdinal -Items @($entities.Keys)) | ForEach-Object { $entities[$_] })
        unresolvedReferences = @(Sort-CtOrdinal -Items @($unresolvedRefs))
    }
    return $contract
}

# ── Render：canonical → developer-facing spec（18 節，順序固定） ─────────────
function ConvertTo-CtVerifText {
    param($V)
    return "static=$($V.staticEvidence) schema=$($V.oracleSchemaVerification) read=$($V.oracleReadVerification) ui=$($V.uiRuntimeVerification) write=$($V.writeEffectVerification)"
}

function ConvertTo-CtEvidenceText {
    param($Evidence)
    $parts = @()
    foreach ($e in @($Evidence)) {
        switch ([string]$e.kind) {
            'CHUNK' { $parts += "CHUNK $($e.chunkId)（$($e.sourceNn) $($e.ref)）" }
            'SQL' { if ($e.referenceQueryId) { $parts += "SQL $($e.referenceQueryId)" } elseif ($e.sourceNn) { $parts += "SQL（$($e.sourceNn) $($e.ref)）" } else { $parts += "SQL（查詢證據 $($e.ref)）" } }
            'PENDING_MANUAL' { $parts += "待人工SQL（$($e.sourceNn) $($e.ref)）" }
            default { $parts += "UNRESOLVED（$($e.ref)）" }
        }
    }
    if ($parts.Count -eq 0) { return 'UNRESOLVED' }
    return ($parts -join '；')
}

function ConvertTo-CtSpec {
    param($Contract, $Screen)
    $o = New-Object System.Collections.Generic.List[string]
    $ents = @{}
    foreach ($e in $Contract.dataEntities) { $ents[$e.record] = $e }
    $usedRecs = [ordered]@{}
    foreach ($c in $Screen.controls) { if ($c.record -ne 'UNRESOLVED') { $usedRecs[$c.record] = $true } }
    foreach ($ef in $Screen.persistenceEffects) { $usedRecs[$ef.record] = $true }
    $o.Add("# $($Screen.component) Legacy Executable Specification")
    $o.Add("")
    $o.Add("> screenId：$($Screen.id)　來源 NN：$($Screen.sourceNn -join '；')　schemaVersion：$($Contract.schemaVersion)　vocabularyVersion：$($Contract.vocabularyVersion)")
    $o.Add("> 本檔由 canonical contract 確定性產生（ps-contract.ps1 -Render），手改會被 G18 判 FAIL。")
    $o.Add("")
    $o.Add("## 功能與入口")
    $o.Add("| 鍵 | 值 |")
    $o.Add("|---|---|")
    $o.Add("| Component | $($Screen.component) |")
    $o.Add("| 選單路徑 | $($Screen.menuPath) |")
    $o.Add("| Search Record | $($Screen.searchRecord) |")
    $o.Add("| 模式 | $(if ($Screen.modes.Count) { $Screen.modes -join '；' } else { 'UNRESOLVED' }) |")
    $o.Add("| Origin | $($Screen.origin) |")
    $o.Add("")
    $o.Add("## 畫面結構")
    $o.Add("| Page | 控制項數 |")
    $o.Add("|---|---|")
    foreach ($p in $Screen.pages) { $o.Add("| $p | $(@($Screen.controls | Where-Object { $_.page -eq $p }).Count) |") }
    if ($Screen.pages.Count -eq 0) { $o.Add("| UNRESOLVED | 0 |") }
    $o.Add("")
    $o.Add("## 欄位與控制項")
    $o.Add("| controlId | Page | Record.Field | 顯示文字 | 語系 | 控制型 | 選項型 | 選項 | 預設 | 可見 | 可編輯 | 必填 | 證據 |")
    $o.Add("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    foreach ($c in $Screen.controls) {
        $ch = @($c.choices | ForEach-Object { $_.label + '=' + $_.storedValue }) -join '；'
        if ($ch -eq '') { $ch = 'NOT_APPLICABLE' }
        $o.Add("| $($c.id) | $($c.page) | $($c.record).$($c.field) | $($c.label) | $($c.languageCode) | $($c.controlType) | $($c.choiceType) | $ch | $($c.default) | $($c.visible) | $($c.editable) | $($c.required) | $(ConvertTo-CtEvidenceText $c.evidence) |")
    }
    if ($Screen.controls.Count -eq 0) { $o.Add("| （無） | | | | | | | | | | | | |") }
    $o.Add("")
    $o.Add("## 狀態與條件")
    $o.Add("| stateId | 目標 | 屬性 | 條件 | 觸發 | 解析 | 證據 |")
    $o.Add("|---|---|---|---|---|---|---|")
    foreach ($s in $Screen.states) { $o.Add("| $($s.id) | $($s.target) | $($s.property) | $($s.condition) | $($s.trigger) | $($s.resolution) | $(ConvertTo-CtEvidenceText $s.evidence) |") }
    if ($Screen.states.Count -eq 0) { $o.Add("| （無） | | | | | | |") }
    $o.Add("")
    $o.Add("## 欄位互動")
    $o.Add("| interactionId | 觸發 | 條件 | 順序 | 效果型 | 目標 | 說明 | 證據 |")
    $o.Add("|---|---|---|---|---|---|---|---|")
    foreach ($i in $Screen.interactions) { foreach ($ef in $i.effects) { $o.Add("| $($i.id) | $($i.trigger) | $($i.condition) | $($ef.order) | $($ef.effectType) | $($ef.target) | $($ef.note) | $(ConvertTo-CtEvidenceText $i.evidence) |") } }
    if ($Screen.interactions.Count -eq 0) { $o.Add("| （無） | | | | | | | |") }
    $o.Add("")
    $o.Add("## 驗證與訊息")
    $o.Add("| validationId | 觸發 | 條件 | 訊息型 | 訊息 | 證據 |")
    $o.Add("|---|---|---|---|---|---|")
    foreach ($v in $Screen.validations) { $o.Add("| $($v.id) | $($v.trigger) | $($v.condition) | $($v.messageKind) | $($v.message) | $(ConvertTo-CtEvidenceText $v.evidence) |") }
    if ($Screen.validations.Count -eq 0) { $o.Add("| （無） | | | | | |") }
    $o.Add("")
    $o.Add("## Navigation")
    $o.Add("| navigationId | 來源 | 目標 | 型 | 證據 |")
    $o.Add("|---|---|---|---|---|")
    foreach ($n in $Screen.navigation) { $o.Add("| $($n.id) | $($n.from) | $($n.to) | $($n.kind) | $(ConvertTo-CtEvidenceText $n.evidence) |") }
    if ($Screen.navigation.Count -eq 0) { $o.Add("| （無） | | | | |") }
    $o.Add("")
    $o.Add("## Business Operations")
    $o.Add("| businessOperationId | 操作鍵 | 觸發 | 模式 | 說明 | 持久化效果 | 證據 |")
    $o.Add("|---|---|---|---|---|---|---|")
    foreach ($b in $Screen.businessOperations) { $o.Add("| $($b.id) | $($b.opKey) | $($b.trigger) | $($b.mode) | $($b.description) | $(if ($b.noPersistence) { 'NOT_APPLICABLE' } elseif ($b.persistenceEffectIds.Count) { $b.persistenceEffectIds -join '；' } else { 'UNRESOLVED' }) | $(ConvertTo-CtEvidenceText $b.evidence) |") }
    if ($Screen.businessOperations.Count -eq 0) { $o.Add("| （無） | | | | | | |") }
    $o.Add("")
    $o.Add("## Data Source of Truth")
    $o.Add("Oracle DB＝Operational Data SoT；本契約＝Handover / Migration Semantics SoT。本畫面涉及的資料實體：")
    $o.Add("| dataEntityId | Record | 業務語意 | Domain Gate |")
    $o.Add("|---|---|---|---|")
    foreach ($r in $usedRecs.Keys) { if ($ents.ContainsKey($r)) { $e = $ents[$r]; $o.Add("| $($e.id) | $($e.record) | $($e.businessMeaning) | $($e.domainGate) |") } else { $o.Add("| UNRESOLVED | $r | UNRESOLVED（無 entity fragment） | UNRESOLVED |") } }
    if ($usedRecs.Count -eq 0) { $o.Add("| （無） | | | |") }
    $o.Add("")
    $o.Add("## Logical / Physical Data Mapping")
    $o.Add("| Record | storageKind | Physical Object | Origin | 欄位數 | schema 驗證 |")
    $o.Add("|---|---|---|---|---|---|")
    foreach ($r in $usedRecs.Keys) { if ($ents.ContainsKey($r)) { $e = $ents[$r]; $o.Add("| $($e.record) | $($e.storageKind) | $($e.physicalObject) | $($e.origin) | $($e.fields.Count) | $($e.verification.oracleSchemaVerification) |") } }
    $o.Add("")
    $o.Add("| fieldId | Record.Field | Column | 型別 | 長度 | 鍵 | 必填 | 選項來源 | 證據 |")
    $o.Add("|---|---|---|---|---|---|---|---|---|")
    foreach ($r in $usedRecs.Keys) { if ($ents.ContainsKey($r)) { foreach ($f in $ents[$r].fields) { $o.Add("| $($f.id) | $r.$($f.field) | $($f.column) | $($f.dataType) | $($f.length) | $(if ($f.keyFlags.Count) { $f.keyFlags -join '；' } else { 'N' }) | $($f.required) | $($f.choiceSource) | $(ConvertTo-CtEvidenceText $f.evidence) |") } } }
    $o.Add("")
    $o.Add("## Key / Effective-Date Semantics")
    $o.Add("| Record | PS Keys | Business Key | Physical Unique Key | Parent | Row Identity | effdtRule | asOf | selection | activeOnly |")
    $o.Add("|---|---|---|---|---|---|---|---|---|---|")
    foreach ($r in $usedRecs.Keys) { if ($ents.ContainsKey($r)) { $e = $ents[$r]; $o.Add("| $r | $(if ($e.recordKeys.psKeys.Count) { $e.recordKeys.psKeys -join '；' } else { 'UNRESOLVED' }) | $(if ($e.recordKeys.businessKey.Count) { $e.recordKeys.businessKey -join '；' } else { 'UNRESOLVED' }) | $($e.recordKeys.physicalUniqueKey) | $($e.recordKeys.parentRecord) | $($e.recordKeys.rowIdentity) | $($e.effectiveDating.rule) | $($e.effectiveDating.asOf) | $($e.effectiveDating.selection) | $($e.effectiveDating.activeOnly) |") } }
    $o.Add("")
    $o.Add("## Read Semantics / Reference Query")
    $o.Add("| Record | readSemanticId | 型 | 內容 | 證據 |")
    $o.Add("|---|---|---|---|---|")
    foreach ($r in $usedRecs.Keys) { if ($ents.ContainsKey($r)) { foreach ($rs in $ents[$r].readSemantics) { $o.Add("| $r | $($rs.id) | $($rs.kind) | $($rs.content) | $(ConvertTo-CtEvidenceText $rs.evidence) |") } } }
    $o.Add("")
    $o.Add("| referenceQueryId | 用途 | SQL | 關鍵列 | 狀態 | read 驗證 |")
    $o.Add("|---|---|---|---|---|---|")
    foreach ($r in $usedRecs.Keys) { if ($ents.ContainsKey($r)) { foreach ($q in $ents[$r].referenceQueries) { $o.Add("| $($q.id) | $($q.purpose) | $($q.sql) | $($q.keyRows) | $($q.state) | $($q.oracleReadVerification) |") } } }
    $o.Add("")
    $o.Add("## Write Semantics / Persistence Effects")
    $o.Add("| effectId | 業務操作 | Record | 操作 | 列選擇 | 變更欄位 | 伴隨效果 | 證據 | 驗證 |")
    $o.Add("|---|---|---|---|---|---|---|---|---|")
    foreach ($ef in $Screen.persistenceEffects) {
        $w = $null
        if ($ents.ContainsKey($ef.record)) { $w = @($ents[$ef.record].writeSemantics | Where-Object { $_.id -eq $ef.writeSemanticsId }) | Select-Object -First 1 }
        $o.Add("| $($ef.id) | $($ef.businessOperationId) | $($ef.record) | $($ef.operation) | $(if ($w) { $w.rowSelection } else { 'UNRESOLVED' }) | $(if ($w -and $w.changedFields.Count) { $w.changedFields -join '；' } else { 'UNRESOLVED' }) | $(if ($w -and $w.companionEffects.Count) { $w.companionEffects -join '；' } else { 'NOT_APPLICABLE' }) | $(ConvertTo-CtEvidenceText $ef.evidence) | $(ConvertTo-CtVerifText $ef.verification) |")
    }
    if ($Screen.persistenceEffects.Count -eq 0) { $o.Add("| （無） | | | | | | | | |") }
    $o.Add("")
    $o.Add("## Data Access Strategy")
    $o.Add("| Record | Read | Write | 核准 |")
    $o.Add("|---|---|---|---|")
    foreach ($r in $usedRecs.Keys) { if ($ents.ContainsKey($r)) { $e = $ents[$r]; $o.Add("| $r | $($e.accessStrategy.read) | $($e.accessStrategy.write) | $($e.accessStrategy.approvalRef) |") } }
    $o.Add("")
    $o.Add("## 權限差異")
    $o.Add("| Permission List | Role | 人數 | Search Record | 證據 |")
    $o.Add("|---|---|---|---|---|")
    foreach ($p in $Screen.security) { $o.Add("| $($p.permissionList) | $($p.role) | $($p.userCount) | $($p.searchRecord) | $(ConvertTo-CtEvidenceText $p.evidence) |") }
    if ($Screen.security.Count -eq 0) { $o.Add("| UNRESOLVED | UNRESOLVED | UNRESOLVED | UNRESOLVED | UNRESOLVED |") }
    $o.Add("")
    $o.Add("## Runtime / DB Verification Status")
    $o.Add("| 維度 | PASS | FAIL | NOT_RUN | NOT_APPLICABLE | UNRESOLVED |")
    $o.Add("|---|---|---|---|---|---|")
    $dims = @('staticEvidence', 'oracleSchemaVerification', 'oracleReadVerification', 'uiRuntimeVerification', 'writeEffectVerification')
    $claims = @()
    $claims += @($Screen.controls) + @($Screen.states) + @($Screen.interactions) + @($Screen.validations) + @($Screen.navigation) + @($Screen.businessOperations) + @($Screen.persistenceEffects)
    foreach ($r in $usedRecs.Keys) { if ($ents.ContainsKey($r)) { $claims += @($ents[$r]) + @($ents[$r].fields) + @($ents[$r].readSemantics) + @($ents[$r].writeSemantics) } }
    foreach ($d in $dims) {
        $cnt = @{ PASS = 0; FAIL = 0; NOT_RUN = 0; NOT_APPLICABLE = 0; UNRESOLVED = 0 }
        foreach ($c in $claims) { $v = [string]$c.verification.$d; if ($cnt.ContainsKey($v)) { $cnt[$v]++ } }
        $o.Add("| $d | $($cnt.PASS) | $($cnt.FAIL) | $($cnt.NOT_RUN) | $($cnt.NOT_APPLICABLE) | $($cnt.UNRESOLVED) |")
    }
    $o.Add("")
    $o.Add("## 未解事項")
    $unres = @()
    foreach ($c in $claims) { if ([string]$c.verification.staticEvidence -eq 'UNRESOLVED' -or [string]$c.verification.staticEvidence -eq 'FAIL') { $unres += "- $($c.id)：staticEvidence=$($c.verification.staticEvidence)" } }
    foreach ($r in $usedRecs.Keys) { if ($ents.ContainsKey($r) -and [string]$ents[$r].schemaNote -ne '') { $unres += "- $($ents[$r].id)：oracleSchema $($ents[$r].verification.oracleSchemaVerification)（$($ents[$r].schemaNote)）" } }
    foreach ($u in $Contract.unresolvedReferences) { if ($u -like "*$($Screen.component)*") { $unres += "- 引用未解析：$u" } }
    if ($unres.Count -eq 0) { $o.Add("- （無）") } else { foreach ($u in $unres) { $o.Add($u) } }
    $o.Add("")
    $o.Add("## Traceability / Evidence")
    $o.Add("| claimId | claimDomain | 證據 | 驗證 |")
    $o.Add("|---|---|---|---|")
    foreach ($c in $claims) { $o.Add("| $($c.id) | $($c.claimDomain) | $(ConvertTo-CtEvidenceText $c.evidence) | $(ConvertTo-CtVerifText $c.verification) |") }
    $o.Add("")
    return (($o -join "`r`n") + "`r`n")
}

function ConvertTo-CtSpecIndex {
    param($Contract)
    $o = @()
    $o += "# $($Contract.domain) Legacy Contract 索引"
    $o += ""
    $o += "> schemaVersion：$($Contract.schemaVersion)　vocabularyVersion：$($Contract.vocabularyVersion)　由 ps-contract.ps1 -Render 產生"
    $o += ""
    $o += "| screenId | Component | 控制項 | 狀態 | 互動 | 驗證 | 業務操作 | 效果 | spec |"
    $o += "|---|---|---|---|---|---|---|---|---|"
    foreach ($s in $Contract.screens) { $o += "| $($s.id) | $($s.component) | $($s.controls.Count) | $($s.states.Count) | $($s.interactions.Count) | $($s.validations.Count) | $($s.businessOperations.Count) | $($s.persistenceEffects.Count) | $($s.component).spec.md |" }
    $o += ""
    $o += "| dataEntityId | Record | storageKind | Physical | 欄位 | 寫入 | schema 驗證 | read | write |"
    $o += "|---|---|---|---|---|---|---|---|---|"
    foreach ($e in $Contract.dataEntities) { $o += "| $($e.id) | $($e.record) | $($e.storageKind) | $($e.physicalObject) | $($e.fields.Count) | $($e.writeSemantics.Count) | $($e.verification.oracleSchemaVerification) | $($e.accessStrategy.read) | $($e.accessStrategy.write) |" }
    $o += ""
    return (($o -join "`r`n") + "`r`n")
}

# ── Gate G1～G18 ─────────────────────────────────────────────────────────────
function New-CtGateResult {
    param([string]$Gate, [string]$State, [int]$Num, [int]$Den, [string]$Note)
    return [ordered]@{ gate = $Gate; state = $State; numerator = $Num; denominator = $Den; note = $Note }
}

function Test-CtGates {
    param($Contract, $NnFactsMap, $Ledger, $Fragments, $Vocab, [string]$SpecDir, [string]$ApprovalsPath)
    $g = @()
    $debts = @()
    $ents = @{}
    foreach ($e in $Contract.dataEntities) { $ents[$e.record] = $e }
    $screens = @{}
    foreach ($s in $Contract.screens) { $screens[$s.component] = $s }
    $nnComps = @{}
    foreach ($nn in $NnFactsMap.Keys) { $f = $NnFactsMap[$nn]; if ($f.Component -ne '') { $nnComps[$f.Component] = $f } }
    $compKeys = @(Sort-CtOrdinal -Items @($nnComps.Keys))
    # BLOCKED 單位（容量／不變量兩次未過）：分母照算、分子缺就 FAIL，理由印 BLOCKED，另出 capacity debt
    $blockedFiles = @()
    if ($null -ne $Ledger) { foreach ($k in $Ledger.fragments.Keys) { if ($Ledger.fragments[$k].status -eq 'BLOCKED') { $blockedFiles += $k; $debts += "$k｜capacity｜BLOCKED｜$($Ledger.fragments[$k].reason)" } } }
    # G1
    $ids = @{}; $dup = 0
    foreach ($s in $Contract.screens) { foreach ($c in @($s) + @($s.controls) + @($s.states) + @($s.interactions) + @($s.validations) + @($s.navigation) + @($s.businessOperations) + @($s.persistenceEffects)) { if ($ids.ContainsKey($c.id)) { $dup++ } else { $ids[$c.id] = 1 } } }
    foreach ($e in $Contract.dataEntities) { foreach ($c in @($e) + @($e.fields) + @($e.readSemantics) + @($e.writeSemantics) + @($e.referenceQueries)) { if ($ids.ContainsKey($c.id)) { $dup++ } else { $ids[$c.id] = 1 } } }
    $g1num = 0; $g1bad = @()
    foreach ($comp in $compKeys) { if ($screens.ContainsKey($comp)) { $g1num++ } else { $g1bad += $comp } }
    foreach ($comp in (Sort-CtOrdinal -Items @($screens.Keys))) { if (-not $nnComps.ContainsKey($comp)) { $g1bad += "$comp（無對應 NN）" } }
    $g1 = 'PASS'; if ($nnComps.Count -eq 0) { $g1 = 'UNRESOLVED' } elseif ($g1bad.Count -gt 0 -or $dup -gt 0) { $g1 = 'FAIL' }
    $g += New-CtGateResult 'G1' $g1 $g1num $nnComps.Count ("ID 重複 $dup；缺／多：" + ($g1bad -join '、'))
    # G2 control inventory（分母：NN 畫面與欄位列）
    $den = 0; $num = 0; $miss = @(); $naAll = $true
    foreach ($comp in $compKeys) {
        $f = $nnComps[$comp]
        if ($f.FieldsNotApplicable) { continue }
        $naAll = $false
        $ctl = @()
        if ($screens.ContainsKey($comp)) { $ctl = @($screens[$comp].controls) }
        foreach ($r in $f.FieldRows) {
            $den++
            $hit = @($ctl | Where-Object { $_.field -eq $r.Field }).Count -gt 0
            if ($hit) { $num++ } else { $blk = @($blockedFiles | Where-Object { $_ -like "screen-$comp*" }); $miss += "$comp/$($r.Field)$(if ($blk.Count) { '（BLOCKED:' + ($blk -join ',') + '）' })"; $debts += "G2｜CTL｜$comp.$($r.Field)｜FAIL" }
        }
    }
    $g2 = 'PASS'; if ($nnComps.Count -eq 0) { $g2 = 'UNRESOLVED' } elseif ($naAll) { $g2 = 'NOT_APPLICABLE' } elseif ($den -eq 0) { $g2 = 'UNRESOLVED' } elseif ($miss.Count -gt 0) { $g2 = 'FAIL' }
    $g += New-CtGateResult 'G2' $g2 $num $den ("缺控制項：" + (($miss | Select-Object -First 8) -join '、'))
    # G3 label／choice（成對：storedValue 不得 UNRESOLVED）
    $den = 0; $num = 0; $bad = @()
    foreach ($s in $Contract.screens) { foreach ($c in $s.controls) { $den++; $ok = ($c.label -ne 'UNRESOLVED' -and $c.label -ne ''); if (@('NONE', 'UNRESOLVED', 'PROMPT_TABLE', 'DYNAMIC_PROMPT', 'DYNAMIC_PEOPLECODE') -notcontains $c.choiceType) { if ($c.choices.Count -eq 0 -or @($c.choices | Where-Object { $_.storedValue -eq 'UNRESOLVED' }).Count -gt 0) { $ok = $false } }; if ($ok) { $num++ } else { $bad += $c.id; $debts += "G3｜$($c.id)｜label/choice｜UNRESOLVED" } } }
    $g3 = 'PASS'; if ($den -eq 0) { $g3 = 'NOT_APPLICABLE' } elseif ($bad.Count -gt 0) { $g3 = 'UNRESOLVED' }
    $g += New-CtGateResult 'G3' $g3 $num $den (($bad | Select-Object -First 8) -join '、')
    # G4 state（分母：NN UI 狀態關鍵詞列）
    $den = 0; $num = 0; $bad = @()
    foreach ($comp in $compKeys) { $f = $nnComps[$comp]; if ($f.UiStateLineCount -eq 0) { continue }; $den++; if ($screens.ContainsKey($comp) -and @($screens[$comp].states).Count -gt 0 -and @($screens[$comp].states | Where-Object { $_.condition -eq '' -or $_.verification.staticEvidence -eq 'FAIL' }).Count -eq 0) { $num++ } else { $bad += $comp; $debts += "G4｜SCR.$comp｜states｜FAIL" } }
    $g4 = 'PASS'; if ($den -eq 0) { $g4 = 'NOT_APPLICABLE' } elseif ($bad.Count -gt 0) { $g4 = 'FAIL' }
    $g += New-CtGateResult 'G4' $g4 $num $den ($bad -join '、')
    # G5 interaction／validation
    $den = 0; $num = 0; $bad = @()
    foreach ($comp in $compKeys) { $f = $nnComps[$comp]; if (@($f.BehaviorLines | Where-Object { $_.Confidence -ne 'NONE' }).Count -eq 0) { continue }; $den++; if ($screens.ContainsKey($comp) -and (@($screens[$comp].interactions).Count + @($screens[$comp].validations).Count) -gt 0) { $num++ } else { $bad += $comp; $debts += "G5｜SCR.$comp｜interactions｜FAIL" } }
    $g5 = 'PASS'; if ($den -eq 0) { $g5 = 'NOT_APPLICABLE' } elseif ($bad.Count -gt 0) { $g5 = 'FAIL' }
    $g += New-CtGateResult 'G5' $g5 $num $den ($bad -join '、')
    # G6 business operation
    $den = 0; $num = 0; $bad = @()
    foreach ($comp in $compKeys) { $f = $nnComps[$comp]; if (@($f.DataFlowRows).Count -eq 0 -and $f.SaveKeywordCount -eq 0) { continue }; $den++; $ok = $false; if ($screens.ContainsKey($comp)) { $ops = @($screens[$comp].businessOperations); if ($ops.Count -gt 0 -and @($ops | Where-Object { -not $_.noPersistence -and $_.persistenceEffectIds.Count -eq 0 }).Count -eq 0) { $ok = $true } }; if ($ok) { $num++ } else { $bad += $comp; $debts += "G6｜SCR.$comp｜businessOperations｜FAIL" } }
    $g6 = 'PASS'; if ($den -eq 0) { $g6 = 'NOT_APPLICABLE' } elseif ($bad.Count -gt 0) { $g6 = 'FAIL' }
    $g += New-CtGateResult 'G6' $g6 $num $den ($bad -join '、')
    # G7 entity mapping
    $recs = @{}
    foreach ($comp in $compKeys) { foreach ($d in $nnComps[$comp].DataFlowRows) { if ($d.Record -ne '') { $recs[$d.Record] = 1 } } }
    $den = $recs.Count; $num = 0; $bad = @()
    foreach ($r in (Sort-CtOrdinal -Items @($recs.Keys))) { if ($ents.ContainsKey($r)) { $num++ } else { $bad += $r; $debts += "G7｜ENT.$r｜entity｜FAIL" } }
    foreach ($s in $Contract.screens) { foreach ($ef in $s.persistenceEffects) { if ($ef.dataEntityId -eq 'UNRESOLVED') { $bad += $ef.id } } }
    $g7 = 'PASS'; if ($den -eq 0 -and $Contract.dataEntities.Count -eq 0) { $g7 = 'NOT_APPLICABLE' } elseif ($bad.Count -gt 0) { $g7 = 'FAIL' }
    $g += New-CtGateResult 'G7' $g7 $num $den (($bad | Select-Object -First 8) -join '、')
    # G8 logical↔physical
    $den = 0; $num = 0; $bad = @(); $unres = 0
    foreach ($e in $Contract.dataEntities) {
        $den++
        $sk = $e.storageKind; $po = $e.physicalObject
        $ok = (Test-CtEnum -Vocab $Vocab -EnumName 'storageKind' -Value $sk)
        if (@('DERIVED_WORK', 'SUBRECORD', 'OTHER_LOGICAL') -contains $sk -and $po -ne 'NOT_APPLICABLE') { $ok = $false }
        if (@('SQL_TABLE', 'SQL_VIEW', 'TEMP_TABLE') -contains $sk -and $po -eq 'NOT_APPLICABLE') { $ok = $false }
        if ($sk -eq 'UNRESOLVED' -or $po -eq 'UNRESOLVED') { $unres++; $debts += "G8｜$($e.id)｜storage/physical｜UNRESOLVED" }
        if ($ok) { $num++ } else { $bad += $e.id }
    }
    $g8 = 'PASS'; if ($den -eq 0) { $g8 = 'NOT_APPLICABLE' } elseif ($bad.Count -gt 0) { $g8 = 'FAIL' } elseif ($unres -gt 0) { $g8 = 'UNRESOLVED' }
    $g += New-CtGateResult 'G8' $g8 $num $den ($bad -join '、')
    # G9 keys
    $den = 0; $num = 0; $bad = @(); $unres = 0
    foreach ($e in $Contract.dataEntities) {
        if (@('DERIVED_WORK', 'SUBRECORD', 'OTHER_LOGICAL') -contains $e.storageKind) { continue }
        $den++
        if ($e.recordKeys.psKeys.Count -eq 0) { $unres++; $debts += "G9｜$($e.id)｜psKeys｜UNRESOLVED"; continue }
        $flagged = @($e.fields | Where-Object { $_.keyFlags -contains 'K' } | ForEach-Object { $_.field })
        $consistent = $true
        foreach ($k in $e.recordKeys.psKeys) { if ($flagged.Count -gt 0 -and $flagged -notcontains $k) { $consistent = $false } }
        if ($e.recordKeys.rowIdentity -eq '' -or $e.recordKeys.rowIdentity -eq 'UNRESOLVED') { $consistent = $false }
        if ($consistent) { $num++ } else { $bad += $e.id }
    }
    $g9 = 'PASS'; if ($den -eq 0) { $g9 = 'NOT_APPLICABLE' } elseif ($bad.Count -gt 0) { $g9 = 'FAIL' } elseif ($unres -gt 0) { $g9 = 'UNRESOLVED' }
    $g += New-CtGateResult 'G9' $g9 $num $den ($bad -join '、')
    # G10 effective dating
    $den = 0; $num = 0; $bad = @(); $unres = 0
    foreach ($e in $Contract.dataEntities) {
        $has = @($e.fields | Where-Object { @('EFFDT', 'EFFSEQ', 'EFF_STATUS') -contains $_.field }).Count -gt 0
        $rule = $e.effectiveDating.rule
        if ($has) { $den++; if ($rule -eq 'UNRESOLVED') { $unres++; $debts += "G10｜$($e.id)｜effdt｜UNRESOLVED" } elseif ($rule -ne 'NONE' -and $e.effectiveDating.selection -ne 'UNRESOLVED' -and $e.effectiveDating.asOf -ne 'UNRESOLVED') { $num++ } else { $bad += $e.id } }
        else { if ($rule -ne 'NONE' -and $rule -ne 'UNRESOLVED' -and $rule -ne 'CUSTOM') { $bad += "$($e.id)（無 EFFDT 欄卻標 $rule）" } }
    }
    $g10 = 'PASS'; if ($den -eq 0 -and $bad.Count -eq 0) { $g10 = 'NOT_APPLICABLE' } elseif ($bad.Count -gt 0) { $g10 = 'FAIL' } elseif ($unres -gt 0) { $g10 = 'UNRESOLVED' }
    $g += New-CtGateResult 'G10' $g10 $num $den ($bad -join '、')
    # G11 read semantics
    $den = 0; $num = 0; $bad = @()
    foreach ($e in $Contract.dataEntities) { if (@('DERIVED_WORK', 'SUBRECORD') -contains $e.storageKind) { continue }; $den++; if (@($e.readSemantics | Where-Object { $_.kind -eq 'SOURCE' }).Count -gt 0) { $num++ } else { $bad += "$($e.id)/SOURCE"; $debts += "G11｜$($e.id)｜SOURCE｜UNRESOLVED" } }
    foreach ($s in $Contract.screens) { foreach ($c in $s.controls) { if (@('PROMPT_TABLE', 'TRANSLATE_VALUE', 'DYNAMIC_PROMPT') -contains $c.choiceType) { $den++; $hit = $false; if ($ents.ContainsKey($c.record)) { $hit = @($ents[$c.record].readSemantics | Where-Object { $_.kind -eq 'LOOKUP' -and $_.content -like "*$($c.field)*" }).Count -gt 0 }; if ($hit) { $num++ } else { $bad += "$($c.id)/LOOKUP"; $debts += "G11｜$($c.id)｜LOOKUP｜UNRESOLVED" } } } }
    $g11 = 'PASS'; if ($den -eq 0) { $g11 = 'NOT_APPLICABLE' } elseif ($bad.Count -gt 0) { $g11 = 'UNRESOLVED' }
    $g += New-CtGateResult 'G11' $g11 $num $den (($bad | Select-Object -First 8) -join '、')
    # G12 write／effects
    $den = 0; $num = 0; $bad = @()
    foreach ($comp in $compKeys) {
        foreach ($d in $nnComps[$comp].DataFlowRows) {
            if (@('INSERT', 'UPDATE', 'DELETE', 'MERGE') -notcontains $d.Op) { continue }
            $den++
            $hit = $false
            if ($screens.ContainsKey($comp)) { $hit = @($screens[$comp].persistenceEffects | Where-Object { $_.record -eq $d.Record -and ($_.operation -eq $d.Op -or ($d.Op -eq 'INSERT' -and $_.operation -eq 'EFFDT_INSERT')) -and $_.writeSemanticsId -ne 'UNRESOLVED' }).Count -gt 0 }
            if ($hit) { $num++ } else { $bad += "$comp/$($d.Record):$($d.Op)"; $debts += "G12｜EFF.$comp.*.$($d.Record).$($d.Op)｜effect｜FAIL" }
        }
    }
    foreach ($e in $Contract.dataEntities) { foreach ($w in $e.writeSemantics) { if ($w.changedFields.Count -eq 0 -or $w.rowSelection -eq '' -or $w.rowSelection -eq 'UNRESOLVED') { $bad += "$($w.id)/欄位或列選擇" } } }
    $g12 = 'PASS'; if ($den -eq 0 -and $bad.Count -eq 0) { $g12 = 'NOT_APPLICABLE' } elseif ($bad.Count -gt 0) { $g12 = 'FAIL' }
    $g += New-CtGateResult 'G12' $g12 $num $den (($bad | Select-Object -First 8) -join '、')
    # G13 access strategy
    $den = 0; $num = 0; $bad = @(); $unres = 0
    $approvals = @()
    if ($ApprovalsPath) { $approvals = @(Read-CtApprovals -LiteralPath $ApprovalsPath) }
    foreach ($e in $Contract.dataEntities) {
        $den++
        $r = $e.accessStrategy.read; $w = $e.accessStrategy.write
        $ok = (Test-CtEnum -Vocab $Vocab -EnumName 'accessStrategy' -Value $r) -and (Test-CtEnum -Vocab $Vocab -EnumName 'accessStrategy' -Value $w)
        if ($w -eq 'DIRECT_DB_WRITE_APPROVED') { $ap = @($approvals | Where-Object { $_.record -eq $e.record -and $_.strategy -eq 'DIRECT_DB_WRITE_APPROVED' -and $_.approver -ne '' -and $_.date -ne '' -and $_.evidence -ne '' }); if ($ap.Count -eq 0) { $ok = $false } }
        if ($r -eq 'UNRESOLVED' -or $w -eq 'UNRESOLVED') { $unres++; $debts += "G13｜$($e.id)｜accessStrategy｜UNRESOLVED" }
        if ($ok) { $num++ } else { $bad += $e.id }
    }
    $g13 = 'PASS'; if ($den -eq 0) { $g13 = 'NOT_APPLICABLE' } elseif ($bad.Count -gt 0) { $g13 = 'FAIL' } elseif ($unres -gt 0) { $g13 = 'UNRESOLVED' }
    $g += New-CtGateResult 'G13' $g13 $num $den ($bad -join '、')
    # G14 security
    $den = 0; $num = 0; $bad = @()
    foreach ($comp in $compKeys) { if (-not $nnComps[$comp].PermissionDeclared) { continue }; $den++; if ($screens.ContainsKey($comp) -and @($screens[$comp].security | Where-Object { $_.permissionList -ne 'UNRESOLVED' }).Count -gt 0) { $num++ } else { $bad += $comp; $debts += "G14｜SCR.$comp｜security｜FAIL" } }
    $g14 = 'PASS'; if ($nnComps.Count -eq 0) { $g14 = 'UNRESOLVED' } elseif ($den -eq 0) { $g14 = 'UNRESOLVED'; foreach ($comp in $compKeys) { $debts += "G14｜SCR.$comp｜security｜UNRESOLVED（NN 無權限節）" } } elseif ($bad.Count -gt 0) { $g14 = 'FAIL' }
    $g += New-CtGateResult 'G14' $g14 $num $den ($bad -join '、')
    # G15 evidence／reference integrity
    $den = 0; $num = 0; $bad = @()
    $all = @()
    foreach ($s in $Contract.screens) { $all += @($s.controls) + @($s.states) + @($s.interactions) + @($s.validations) + @($s.navigation) + @($s.businessOperations) + @($s.persistenceEffects) }
    foreach ($e in $Contract.dataEntities) { $all += @($e.fields) + @($e.readSemantics) + @($e.writeSemantics) }
    foreach ($c in $all) { $den++; $st = [string]$c.verification.staticEvidence; if ($st -eq 'PASS' -or $st -eq 'NOT_APPLICABLE') { $num++ } elseif ($st -eq 'FAIL') { $bad += $c.id } else { $debts += "G15｜$($c.id)｜staticEvidence｜UNRESOLVED" } }
    foreach ($u in $Contract.unresolvedReferences) { $bad += $u }
    $g15 = 'PASS'; if ($den -eq 0) { $g15 = 'NOT_APPLICABLE' } elseif ($bad.Count -gt 0) { $g15 = 'FAIL' } elseif ($num -lt $den) { $g15 = 'UNRESOLVED' }
    $g += New-CtGateResult 'G15' $g15 $num $den (($bad | Select-Object -First 8) -join '、')
    # G16 Oracle schema（含 RQ 的 oracleRead debt）
    $den = 0; $num = 0; $bad = @(); $nr = 0
    foreach ($e in $Contract.dataEntities) {
        if ($e.physicalObject -eq 'NOT_APPLICABLE') { continue }
        $den++
        $st = $e.verification.oracleSchemaVerification
        if ($st -eq 'PASS') { $num++ } elseif ($st -eq 'FAIL') { $bad += "$($e.id)（$($e.schemaNote)）"; $debts += "G16｜$($e.id)｜oracleSchema｜FAIL" } else { $nr++; $debts += "G16｜$($e.id)｜oracleSchema｜NOT_RUN" }
        foreach ($q in $e.referenceQueries) { if ($q.oracleReadVerification -eq 'NOT_RUN') { $debts += "G16｜$($q.id)｜oracleRead｜NOT_RUN" } elseif ($q.oracleReadVerification -eq 'FAIL') { $bad += $q.id; $debts += "G16｜$($q.id)｜oracleRead｜FAIL" } }
    }
    $g16 = 'PASS'; if ($den -eq 0) { $g16 = 'NOT_APPLICABLE' } elseif ($bad.Count -gt 0) { $g16 = 'FAIL' } elseif ($nr -gt 0) { $g16 = 'UNRESOLVED' }
    $g += New-CtGateResult 'G16' $g16 $num $den (($bad | Select-Object -First 6) -join '、')
    # G17 schema validity（fragments 全部通過不變量）
    $den = @($Fragments).Count; $num = 0; $bad = @()
    foreach ($fr in $Fragments) { if ($fr.Invalid.Count -eq 0) { $num++ } else { $bad += "$($fr.File)：$($fr.Invalid[0])" } }
    $g17 = 'PASS'; if ($den -eq 0) { $g17 = 'UNRESOLVED' } elseif ($bad.Count -gt 0) { $g17 = 'FAIL' }
    $g += New-CtGateResult 'G17' $g17 $num $den (($bad | Select-Object -First 5) -join '、')
    # G18 renderer parity
    $den = 0; $num = 0; $bad = @()
    foreach ($s in $Contract.screens) {
        $den++
        $p = Join-Path $SpecDir ($s.component + '.spec.md')
        if (-not (Test-Path -LiteralPath $p)) { $bad += "$($s.component)（spec 不存在）"; continue }
        $fresh = ConvertTo-CtSpec -Contract $Contract -Screen $s
        if ((Get-CtNormalizedHash -Text $fresh) -eq (Get-CtFileHash -LiteralPath $p)) { $num++ } else { $bad += "$($s.component)（與重 render 不符）" }
    }
    $den++
    $ip = Join-Path $SpecDir 'index.spec.md'
    if ((Test-Path -LiteralPath $ip) -and ((Get-CtNormalizedHash -Text (ConvertTo-CtSpecIndex -Contract $Contract)) -eq (Get-CtFileHash -LiteralPath $ip))) { $num++ } else { $bad += 'index.spec.md' }
    $g18 = 'PASS'; if ($Contract.screens.Count -eq 0) { $g18 = 'NOT_APPLICABLE' } elseif ($bad.Count -gt 0) { $g18 = 'FAIL' }
    $g += New-CtGateResult 'G18' $g18 $num $den ($bad -join '、')
    # 聚合：tier 1＝結構類 gate 無 FAIL（UNRESOLVED 允許）；tier 2＝全 PASS／NOT_APPLICABLE 且無 UNRESOLVED／NOT_RUN／BLOCKED debt
    $t1Gates = @('G1', 'G2', 'G6', 'G7', 'G8', 'G12', 'G13', 'G15', 'G17', 'G18')
    $t1 = $true; $t2 = $true
    foreach ($r in $g) {
        $okState = ($r.state -eq 'PASS' -or $r.state -eq 'NOT_APPLICABLE')
        if ($t1Gates -contains $r.gate -and $r.state -eq 'FAIL') { $t1 = $false }
        if (-not $okState) { $t2 = $false }
    }
    $debtsSorted = @(Sort-CtOrdinal -Items @($debts | Select-Object -Unique))
    if (@($debtsSorted | Where-Object { $_ -like '*UNRESOLVED*' -or $_ -like '*NOT_RUN*' -or $_ -like '*BLOCKED*' }).Count -gt 0) { $t2 = $false }
    return [ordered]@{ gates = $g; debts = $debtsSorted; tier1 = $t1; tier2 = $t2 }
}
