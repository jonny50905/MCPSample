# ps-bizspec-lib.ps1 — 業務需求文件流程（BIZ1）的解析與檢查：markdown 表格、證據章、證據逐字比對、引用、必要檔、進度、補查檔。
# 純函式、不呼叫模型；ps-bizspec.ps1 與 scripts/tests/test-bizspec.ps1 共用。PowerShell 5.1；需要先載入 ps-knowledge-lib.ps1。

$script:PsBzEvidenceHeader = @('證據編號', '類型', '位置', '原文摘錄')
$script:PsBzQueryHeader = @('補查檔', '對應假設', '結論', '回填的證據')
$script:PsBzAssumpHeader = @('編號', '類型', '缺什麼', '暫定做法', '影響的需求鍵', '該問誰', '狀態', '關閉依據')
$script:PsBzIndexHeader = @('需求鍵', '類別', '摘要', '證據', '確認狀態', '相關假設')
$script:PsBzTrackHeader = @('需求鍵', '摘要', '確認狀態', '確認人／日期', '驗收結果', '驗收日期', '備註')
$script:PsBzAnswerHeader = @('假設編號', '回覆', '回覆人代稱', '日期')
$script:PsBzRequiredFiles = @('README.md', '01-goals.md', '02-spec-overview.md', '03-reading-guide.md', '04-requirement-index.md',
    '05-1-flows.md', '05-2-screens.md', '05-3-data.md', '05-4-rules.md', '05-5-states.md', '05-6-permissions.md', '05-7-interfaces.md', '05-8-coverage.md',
    '06-tracking.md', '07-assumptions.md', '08-spec-change.md', '09-acceptance.md', '10-evidence.md', 'appendix.md', 'progress.md')
$script:PsBzQueryConclusions = @('有答案', '查無', '查詢失敗')
$script:PsBzEvidenceIdRx = New-Object System.Text.RegularExpressions.Regex('(?<![A-Za-z0-9-])E-([0-9]{3,})(?![0-9])')

# ---------------- 表格 ----------------
function ConvertFrom-PsBzRow {
    # 一列 markdown 表格 → 儲存格陣列；「\|」是儲存格內的「|」。不是表格列回 $null。
    param([string]$Line)
    $t = $Line.Trim()
    if (-not $t.StartsWith('|')) { return $null }
    $cells = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder
    $i = 1
    while ($i -lt $t.Length) {
        $ch = [string]$t[$i]
        if ($ch -eq '\' -and ($i + 1) -lt $t.Length -and [string]$t[$i + 1] -eq '|') { [void]$sb.Append('|'); $i += 2; continue }
        if ($ch -eq '|') { $cells.Add($sb.ToString().Trim()); [void]$sb.Remove(0, $sb.Length); $i++; continue }
        [void]$sb.Append($ch); $i++
    }
    if ($sb.ToString().Trim() -ne '') { $cells.Add($sb.ToString().Trim()) }
    return , $cells.ToArray()
}

function Get-PsBzTables {
    # 文字中的全部表格（圍欄程式碼區塊內的不算）。每個表格：@{ Header = 儲存格陣列; Rows = @(@{ Cells; Line }); Line = 表頭行號 }
    param([string]$Text)
    $tables = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Text) { return , $tables.ToArray() }
    $lines = Get-PsKnLines $Text
    $cur = $null; $inCode = $false
    for ($n = 0; $n -lt $lines.Count; $n++) {
        $ln = [string]$lines[$n]
        if ($ln.TrimStart().StartsWith('```')) { $inCode = -not $inCode; $cur = $null; continue }
        if ($inCode) { continue }
        $t = $ln.Trim()
        if (-not $t.StartsWith('|')) { $cur = $null; continue }
        $cells = ConvertFrom-PsBzRow $t
        if ($null -eq $cur) {
            if (($n + 1) -lt $lines.Count -and ([string]$lines[$n + 1]).Trim() -match '^\|(\s*:?-{3,}:?\s*\|)+\s*$') {
                $cur = @{ Header = $cells; Rows = (New-Object System.Collections.Generic.List[object]); Line = $n + 1 }
                $tables.Add($cur)
                $n++
            }
            continue
        }
        $cur.Rows.Add(@{ Cells = $cells; Line = $n + 1 })
    }
    return , $tables.ToArray()
}

function Test-PsBzHeader {
    param([string[]]$Header, [string[]]$Want)
    if ($null -eq $Header -or $Header.Count -ne $Want.Count) { return $false }
    for ($i = 0; $i -lt $Want.Count; $i++) { if ([string]$Header[$i] -cne [string]$Want[$i]) { return $false } }
    return $true
}

function Get-PsBzCell {
    param($Table, $Row, [string]$Name)
    $idx = [array]::IndexOf([string[]]$Table.Header, $Name)
    if ($idx -lt 0 -or $idx -ge $Row.Cells.Count) { return '' }
    return [string]$Row.Cells[$idx]
}

# ---------------- 檔案 ----------------
function Get-PsBzChapterFiles {
    # 一章的主檔與續檔（<base>.md、<base>-02.md、<base>-03.md…），依名稱排序；只回存在的檔。
    param([string]$OutDir, [string]$Base)
    $out = @()
    $main = Join-Path $OutDir ($Base + '.md')
    if ([System.IO.File]::Exists($main)) { $out += $main }
    if ([System.IO.Directory]::Exists($OutDir)) {
        $cont = @()
        foreach ($f in @(Get-ChildItem -LiteralPath $OutDir -File -Filter ($Base + '-*.md'))) {
            if ($f.Name -match ('^' + [regex]::Escape($Base) + '-[0-9]{2}\.md$')) { $cont += $f.FullName }
        }
        foreach ($c in (Sort-PsKnOrdinal -Items $cont)) { if ($null -ne $c) { $out += $c } }
    }
    return , $out
}

function Get-PsBzTextOf {
    param([string[]]$Files)
    $sb = New-Object System.Text.StringBuilder
    foreach ($f in @($Files)) { $t = Read-PsKnText -LiteralPath $f; if ($null -ne $t) { [void]$sb.Append($t); [void]$sb.Append("`n") } }
    return $sb.ToString()
}

function ConvertTo-PsBzNorm {
    # 比對用：連續空白（含全形空白）壓成一個、去頭尾空白、「\|」視為「|」
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return ([regex]::Replace($Text.Replace('\|', '|'), '\s+', ' ')).Trim()
}

function Split-PsBzLocation {
    # 「<路徑> §<章節>」或「<路徑> 第 N 列」→ @{ Path; Rest }；路徑可包反引號、可帶 ./ 開頭
    param([string]$Location)
    $t = ([string]$Location).Trim()
    $m = [regex]::Match($t, '^`?(?<p>[^\s`§]+)`?\s*(?<rest>§.*|第\s*[0-9]+\s*列.*)$')
    if (-not $m.Success) { return $null }
    $p = $m.Groups['p'].Value.Replace('\', '/')
    if ($p.StartsWith('./')) { $p = $p.Substring(2) }
    return @{ Path = $p; Rest = $m.Groups['rest'].Value.Trim() }
}

function Get-PsBzSectionLines {
    # 「## <名稱>」到下一個「## 」之間的行
    param([string]$Text, [string]$Name)
    $out = @(); $in = $false
    foreach ($ln in (Get-PsKnLines $Text)) {
        if ($ln -match '^##\s+(.+?)\s*$') { $in = ($Matches[1] -ceq $Name); continue }
        if ($in) { $out += [string]$ln }
    }
    return , $out
}

# ---------------- 證據章 ----------------
function Read-PsBzEvidence {
    # 10-evidence*.md 的 10.1 表（表頭＝證據清單）→ @{ Items = 依出現順序; ById; Duplicates; Malformed }
    param([string]$OutDir)
    $items = New-Object System.Collections.Generic.List[object]
    $byId = @{}; $dups = @(); $bad = @()
    foreach ($f in (Get-PsBzChapterFiles $OutDir '10-evidence')) {
        $text = Read-PsKnText -LiteralPath $f
        foreach ($tb in (Get-PsBzTables $text)) {
            if (-not (Test-PsBzHeader $tb.Header $script:PsBzEvidenceHeader)) { continue }
            foreach ($row in $tb.Rows) {
                $id = Get-PsBzCell $tb $row '證據編號'
                $it = @{ Id = $id; Type = (Get-PsBzCell $tb $row '類型'); Location = (Get-PsBzCell $tb $row '位置'); Excerpt = (Get-PsBzCell $tb $row '原文摘錄'); File = [System.IO.Path]::GetFileName($f); Line = $row.Line }
                if ($id -cnotmatch '^E-[0-9]{3,}$') { $bad += $it; continue }
                if ($byId.ContainsKey($id)) { $dups += $id; continue }
                $byId[$id] = $it
                $items.Add($it)
            }
        }
    }
    return @{ Items = $items.ToArray(); ById = $byId; Duplicates = $dups; Malformed = $bad }
}

function Test-PsBzEvidenceItems {
    # 每筆證據：類型、位置可解析、檔案在允許的根目錄底下且存在、摘錄長度、摘錄逐字出現在該檔同一行；補查類另驗帳本與「結果」節。
    # Ctx：@{ Root; FileRoots = @('相對路徑前綴/', …); EvidenceRel = '<輸出>/evidence/'; Ledger = @{ 相對路徑 = sha256 } }
    param($Evidence, [hashtable]$Ctx)
    $findings = New-Object System.Collections.Generic.List[object]
    $cache = @{}
    foreach ($b in @($Evidence.Malformed)) { $findings.Add(@{ Code = 'BZ_EV_FORMAT'; File = $b.File; Detail = ('第 ' + $b.Line + ' 行：證據編號要寫成 E-###（實得「' + $b.Id + '」）') }) }
    foreach ($d in @($Evidence.Duplicates | Select-Object -Unique)) { $findings.Add(@{ Code = 'BZ_EV_DUP'; File = '10-evidence.md'; Detail = ($d + ' 重複登記；一個編號只登一次') }) }
    foreach ($it in $Evidence.Items) {
        $where = $it.Id + '（' + $it.File + ' 第 ' + $it.Line + ' 行）'
        if (@('檔案', '補查') -cnotcontains $it.Type) { $findings.Add(@{ Code = 'BZ_EV_FORMAT'; File = $it.File; Detail = ($where + '：類型只能是「檔案」或「補查」') }); continue }
        $loc = Split-PsBzLocation $it.Location
        if ($null -eq $loc) { $findings.Add(@{ Code = 'BZ_EV_FORMAT'; File = $it.File; Detail = ($where + '：位置要寫「<從專案根目錄起算的路徑> §<章節>」或「<路徑> 第 N 列」') }); continue }
        $rel = $loc.Path
        if ([System.IO.Path]::IsPathRooted($rel) -or $rel.Contains('..')) { $findings.Add(@{ Code = 'BZ_EV_PATH'; File = $it.File; Detail = ($where + '：路徑要從專案根目錄起算，不用絕對路徑或 ..（實得 ' + $rel + '）') }); continue }
        $isQuery = $rel.StartsWith($Ctx.EvidenceRel, [System.StringComparison]::OrdinalIgnoreCase)
        if ($it.Type -ceq '補查' -and -not $isQuery) { $findings.Add(@{ Code = 'BZ_EV_ROOT'; File = $it.File; Detail = ($where + '：補查類證據的位置要在 ' + $Ctx.EvidenceRel + ' 底下') }); continue }
        if ($it.Type -ceq '檔案') {
            $okRoot = $false
            foreach ($fr in @($Ctx.FileRoots)) { if ($rel.StartsWith($fr, [System.StringComparison]::OrdinalIgnoreCase)) { $okRoot = $true; break } }
            if ($isQuery -or -not $okRoot) { $findings.Add(@{ Code = 'BZ_EV_ROOT'; File = $it.File; Detail = ($where + '：檔案類證據只能引用 ' + (@($Ctx.FileRoots) -join '、') + ' 底下的檔（實得 ' + $rel + '）') }); continue }
        }
        $full = Join-Path $Ctx.Root $rel
        if (-not [System.IO.File]::Exists($full)) { $findings.Add(@{ Code = 'BZ_EV_PATH'; File = $it.File; Detail = ($where + '：位置所指的檔不存在（' + $rel + '）') }); continue }
        $ex = ConvertTo-PsBzNorm $it.Excerpt
        if ($ex.Length -lt 10 -or $ex.Length -gt 150) { $findings.Add(@{ Code = 'BZ_EV_LENGTH'; File = $it.File; Detail = ($where + '：原文摘錄要 10～150 字（實得 ' + $ex.Length + ' 字）；太短就連前後文一起照抄，太長就拆成兩筆') }); continue }
        if (-not $cache.ContainsKey($rel)) { $cache[$rel] = Read-PsKnText -LiteralPath $full }
        $srcText = [string]$cache[$rel]
        $lines = @()
        if ($isQuery) {
            $key = $rel.ToLowerInvariant()
            $want = ''; foreach ($k in @($Ctx.Ledger.Keys)) { if ($k.ToLowerInvariant() -eq $key) { $want = [string]$Ctx.Ledger[$k] } }
            if ($want -eq '') { $findings.Add(@{ Code = 'BZ_EV_QUERY'; File = $it.File; Detail = ($where + '：' + $rel + ' 不是外環補查寫的檔') }); continue }
            if ((Get-PsKnTextHash -Text $srcText) -cne $want) { $findings.Add(@{ Code = 'BZ_EV_QUERY'; File = $it.File; Detail = ($where + '：' + $rel + ' 在補查後被改過') }); continue }
            $lines = Get-PsBzSectionLines $srcText '結果'
        }
        else { $lines = Get-PsKnLines $srcText }
        $hit = $false
        foreach ($ln in $lines) { if ((ConvertTo-PsBzNorm ([string]$ln)).Contains($ex)) { $hit = $true; break } }
        if (-not $hit) {
            $scope = '該檔任何一行'; if ($isQuery) { $scope = '該檔「結果」節的任何一行' }
            $findings.Add(@{ Code = 'BZ_EV_EXCERPT'; File = $it.File; Detail = ($where + '：原文摘錄不在' + $scope + '（' + $rel + '）；要從同一行逐字照抄，不改字、不跨行') })
        }
    }
    return , $findings.ToArray()
}

# ---------------- 引用 ----------------
function Get-PsBzOutputDocs {
    # 輸出資料夾第一層的 .md（不含 evidence/ 與 progress.md）
    param([string]$OutDir)
    $out = @()
    if ([System.IO.Directory]::Exists($OutDir)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $OutDir -File -Filter '*.md')) { if ($f.Name -cne 'progress.md') { $out += $f.FullName } }
    }
    return , (Sort-PsKnOrdinal -Items $out)
}

function Test-PsBzReferences {
    # 正文引用的 E-### 都要登在 10.1；10.1 每個編號至少被正文引用一次
    param([string]$OutDir, $Evidence)
    $findings = New-Object System.Collections.Generic.List[object]
    $used = @{}
    foreach ($f in (Get-PsBzOutputDocs $OutDir)) {
        $name = [System.IO.Path]::GetFileName($f)
        if ($name -like '10-evidence*') { continue }
        $text = Read-PsKnText -LiteralPath $f
        $missing = @()
        foreach ($m in $script:PsBzEvidenceIdRx.Matches([string]$text)) {
            $id = $m.Value
            $used[$id] = $true
            if (-not $Evidence.ById.ContainsKey($id) -and $missing -cnotcontains $id) { $missing += $id }
        }
        foreach ($id in $missing) { $findings.Add(@{ Code = 'BZ_REF_UNDEFINED'; File = $name; Detail = ($id + ' 沒有登在第 10 章 10.1') }) }
    }
    foreach ($it in $Evidence.Items) { if (-not $used.ContainsKey($it.Id)) { $findings.Add(@{ Code = 'BZ_REF_UNUSED'; File = $it.File; Detail = ($it.Id + ' 沒有被任何需求、假設或 3.4／7.3 引用；刪掉或補上引用') }) } }
    return , $findings.ToArray()
}

function Test-PsBzRequirementEvidence {
    # 03、05、09 的需求列與 07 的假設都要有證據編號（衍生的 ACC 寫「衍生」、OTHER 可寫「無」、假設可寫「（證據：無）」）
    param([string]$OutDir)
    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($f in (Get-PsBzOutputDocs $OutDir)) {
        $name = [System.IO.Path]::GetFileName($f)
        $text = Read-PsKnText -LiteralPath $f
        if ($name -match '^(03|05-|09)') {
            foreach ($tb in (Get-PsBzTables $text)) {
                $h = [string[]]$tb.Header
                if ($h -cnotcontains '需求鍵' -or $h -cnotcontains '證據') { continue }
                foreach ($row in $tb.Rows) {
                    $key = Get-PsBzCell $tb $row '需求鍵'
                    if ($key -cnotmatch '^[A-Z]+-[0-9]{3,}$') { continue }
                    $ev = Get-PsBzCell $tb $row '證據'
                    if ($script:PsBzEvidenceIdRx.IsMatch($ev)) { continue }
                    if ($h -ccontains '衍生' -and (Get-PsBzCell $tb $row '衍生') -ceq '是' -and $ev.Contains('衍生')) { continue }
                    if ($key.StartsWith('OTHER-') -and $ev -ceq '無') { continue }
                    $findings.Add(@{ Code = 'BZ_REQ_NO_EVIDENCE'; File = $name; Detail = ($key + '（第 ' + $row.Line + ' 行）的證據欄沒有證據編號') })
                }
            }
            if ($name -like '05-1-flows*') {
                $lines = Get-PsKnLines $text
                $key = ''; $seen = $true; $at = 0
                for ($n = 0; $n -le $lines.Count; $n++) {
                    $ln = ''; if ($n -lt $lines.Count) { $ln = [string]$lines[$n] }
                    $start = [regex]::Match($ln, '^#{2,4}\s+(FLOW-[0-9]{3,})\b')
                    if ($n -eq $lines.Count -or $start.Success -or $ln -match '^#{1,3}\s') {
                        if ($key -ne '' -and -not $seen) { $findings.Add(@{ Code = 'BZ_REQ_NO_EVIDENCE'; File = $name; Detail = ($key + '（第 ' + $at + ' 行）的「證據：」沒有證據編號') }) }
                        $key = ''; $seen = $true
                        if ($start.Success) { $key = $start.Groups[1].Value; $seen = $false; $at = $n + 1 }
                        continue
                    }
                    if ($key -ne '') {
                        $m = [regex]::Match($ln, '^\s*-\s*證據：(.*)$')
                        if ($m.Success -and $script:PsBzEvidenceIdRx.IsMatch($m.Groups[1].Value)) { $seen = $true }
                    }
                }
            }
        }
        if ($name -like '07-assumptions*') {
            foreach ($tb in (Get-PsBzTables $text)) {
                if (-not (Test-PsBzHeader $tb.Header $script:PsBzAssumpHeader)) { continue }
                foreach ($row in $tb.Rows) {
                    $id = Get-PsBzCell $tb $row '編號'
                    if ($id -cnotmatch '^A-[0-9]{3,}$') { continue }
                    $miss = Get-PsBzCell $tb $row '缺什麼'
                    $m = [regex]::Match($miss, '（證據：([^）]*)）')
                    if ($m.Success -and ($script:PsBzEvidenceIdRx.IsMatch($m.Groups[1].Value) -or $m.Groups[1].Value.Trim() -ceq '無')) { continue }
                    $findings.Add(@{ Code = 'BZ_ASSUMP_NO_EVIDENCE'; File = $name; Detail = ($id + '（第 ' + $row.Line + ' 行）的「缺什麼」句末沒有「（證據：E-###）」或「（證據：無）」') })
                }
            }
        }
    }
    return , $findings.ToArray()
}

# ---------------- 必要檔、表頭、進度 ----------------
function Get-PsBzProgress {
    param([string]$OutDir)
    $t = Read-PsKnText -LiteralPath (Join-Path $OutDir 'progress.md')
    if ($null -eq $t) { return @{ Exists = $false; Open = -1; SelfCheck = $false; Done = $false } }
    $open = 0; $self = $false
    foreach ($ln in (Get-PsKnLines $t)) {
        if ($ln -match '^\s*[-*]\s*\[\s\]') { $open++ }
        if ($ln -match '自我檢查：\s*通過') { $self = $true }
    }
    return @{ Exists = $true; Open = $open; SelfCheck = $self; Done = ($open -eq 0 -and $self) }
}

function Test-PsBzStructure {
    param([string]$OutDir)
    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($n in $script:PsBzRequiredFiles) { if (-not [System.IO.File]::Exists((Join-Path $OutDir $n))) { $findings.Add(@{ Code = 'BZ_FILE_MISSING'; File = $n; Detail = '必要的輸出檔不存在' }) } }
    $pr = Get-PsBzProgress $OutDir
    if ($pr.Exists -and $pr.Open -gt 0) { $findings.Add(@{ Code = 'BZ_PROGRESS_OPEN'; File = 'progress.md'; Detail = ('還有 ' + $pr.Open + ' 個沒打勾的項目') }) }
    if ($pr.Exists -and -not $pr.SelfCheck) { $findings.Add(@{ Code = 'BZ_SELFCHECK_MISSING'; File = 'progress.md'; Detail = '沒有「自我檢查：通過」那一行' }) }
    $want = @(@('04-requirement-index', $script:PsBzIndexHeader, '需求索引'), @('06-tracking', $script:PsBzTrackHeader, '追蹤表'), @('07-assumptions', $script:PsBzAssumpHeader, '假設'), @('10-evidence', $script:PsBzEvidenceHeader, '證據清單'))
    foreach ($w in $want) {
        $files = Get-PsBzChapterFiles $OutDir $w[0]
        if ($files.Count -eq 0) { continue }
        $found = $false
        foreach ($tb in (Get-PsBzTables (Get-PsBzTextOf $files))) { if (Test-PsBzHeader $tb.Header $w[1]) { $found = $true; break } }
        if (-not $found) { $findings.Add(@{ Code = 'BZ_HEADER_MISSING'; File = ($w[0] + '.md'); Detail = ($w[2] + '的表頭要逐字照規範：| ' + ($w[1] -join ' | ') + ' |') }) }
    }
    return , $findings.ToArray()
}

# ---------------- 假設、補查紀錄、業務回覆 ----------------
function Get-PsBzAssumptions {
    param([string]$OutDir)
    $out = @()
    $text = Get-PsBzTextOf (Get-PsBzChapterFiles $OutDir '07-assumptions')
    foreach ($tb in (Get-PsBzTables $text)) {
        if (-not (Test-PsBzHeader $tb.Header $script:PsBzAssumpHeader)) { continue }
        foreach ($row in $tb.Rows) {
            $id = Get-PsBzCell $tb $row '編號'
            if ($id -cnotmatch '^A-[0-9]{3,}$') { continue }
            $out += @{ Id = $id; Kind = (Get-PsBzCell $tb $row '類型'); Missing = (Get-PsBzCell $tb $row '缺什麼'); Provisional = (Get-PsBzCell $tb $row '暫定做法'); Keys = (Get-PsBzCell $tb $row '影響的需求鍵'); Owner = (Get-PsBzCell $tb $row '該問誰'); State = (Get-PsBzCell $tb $row '狀態') }
        }
    }
    return , $out
}

function Get-PsBzQueryRows {
    # 10.2 已列的補查檔（檔名，小寫）
    param([string]$OutDir)
    $set = @{}
    $text = Get-PsBzTextOf (Get-PsBzChapterFiles $OutDir '10-evidence')
    foreach ($tb in (Get-PsBzTables $text)) {
        if (-not (Test-PsBzHeader $tb.Header $script:PsBzQueryHeader)) { continue }
        foreach ($row in $tb.Rows) {
            $f = (Get-PsBzCell $tb $row '補查檔').Replace('`', '').Replace('\', '/')
            $name = [System.IO.Path]::GetFileName($f)
            if ($name -ne '') { $set[$name.ToLowerInvariant()] = $true }
        }
    }
    return $set
}

function Get-PsBzAnswers {
    # 業務窗口回覆（answers.md 的表）：回覆非空的列
    param([string]$Text)
    $out = @()
    foreach ($tb in (Get-PsBzTables $Text)) {
        if (-not (Test-PsBzHeader $tb.Header $script:PsBzAnswerHeader)) { continue }
        foreach ($row in $tb.Rows) {
            $id = Get-PsBzCell $tb $row '假設編號'
            $reply = Get-PsBzCell $tb $row '回覆'
            if ($id -cmatch '^A-[0-9]{3,}$' -and $reply -ne '') { $out += @{ Id = $id; Reply = $reply } }
        }
    }
    return , $out
}

function Test-PsBzQueryFile {
    # 補查結果檔：四節依序、結論節第一個非空行以「有答案／查無／查詢失敗」開頭、結果節至少一行內容
    param([string]$Text)
    $errs = @(); $conclusion = ''
    if ($null -eq $Text) { return @{ Ok = $false; Conclusion = ''; Errors = @('檔案不存在') } }
    $order = @()
    foreach ($ln in (Get-PsKnLines $Text)) { if ($ln -match '^##\s+(.+?)\s*$') { $order += $Matches[1] } }
    $want = @('問題', '查詢', '結果', '結論')
    $pos = -1
    foreach ($w in $want) {
        $i = [array]::IndexOf([string[]]$order, $w)
        if ($i -lt 0) { $errs += ('缺「## ' + $w + '」節') } elseif ($i -lt $pos) { $errs += ('「## ' + $w + '」順序不對') } else { $pos = $i }
    }
    $resLines = Get-PsBzSectionLines $Text '結果'
    $res = 0; foreach ($ln in $resLines) { if (([string]$ln).Trim() -ne '') { $res++ } }
    if ($res -eq 0) { $errs += '「結果」節沒有內容' }
    foreach ($ln in (Get-PsBzSectionLines $Text '結論')) {
        $t = ([string]$ln).Trim()
        if ($t -eq '') { continue }
        foreach ($c in $script:PsBzQueryConclusions) { if ($t.StartsWith($c)) { $conclusion = $c; break } }
        break
    }
    if ($conclusion -eq '') { $errs += '「結論」節第一行要以「有答案」「查無」或「查詢失敗」開頭' }
    return @{ Ok = ($errs.Count -eq 0); Conclusion = $conclusion; Errors = $errs }
}

# ---------------- 進度與規範段落 ----------------
function Get-PsBzCheckedItems {
    # progress.md 已打勾的項目文字（去頭尾空白）→ $true
    param([string]$OutDir)
    $set = @{}
    $t = Read-PsKnText -LiteralPath (Join-Path $OutDir 'progress.md')
    if ($null -eq $t) { return $set }
    foreach ($ln in (Get-PsKnLines $t)) {
        $m = [regex]::Match([string]$ln, '^\s*[-*]\s*\[[xX]\]\s*(.+?)\s*$')
        if ($m.Success) { $set[$m.Groups[1].Value] = $true }
    }
    return $set
}

function Test-PsBzItemChecked {
    # 某一項打勾了沒：打勾的文字以項目名稱開頭就算（容許後面加註）
    param([hashtable]$Checked, [string]$Item)
    foreach ($k in @($Checked.Keys)) { if (([string]$k).StartsWith($Item)) { return $true } }
    return $false
}

function Get-PsBzStandardRanges {
    # 規範各段的行號（1 起算、含頭尾；圍欄程式碼區塊裡的標題不算）：
    # general、ch0～ch10、appendix、selfcheck（## 層）；ch5common、ch5.1～ch5.8、ch7a（7.1～7.2）（### 層）
    param([string]$Text)
    $lines = Get-PsKnLines $Text
    $heads = New-Object System.Collections.Generic.List[object]
    $inCode = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $ln = [string]$lines[$i]
        if ($ln.TrimStart().StartsWith('```')) { $inCode = -not $inCode; continue }
        if ($inCode) { continue }
        $m = [regex]::Match($ln, '^(#{2,3})\s+(.+?)\s*$')
        if ($m.Success) { $heads.Add(@{ Level = $m.Groups[1].Value.Length; Line = $i + 1; Text = $m.Groups[2].Value }) }
    }
    $n = $lines.Count
    $r = @{}
    for ($k = 0; $k -lt $heads.Count; $k++) {
        $h = $heads[$k]; $t = [string]$h.Text; $key = ''
        if ($h.Level -eq 2) {
            if ($t -ceq '通用規則') { $key = 'general' }
            elseif ($t -match '^第\s*([0-9]+)\s*章') { $key = 'ch' + $Matches[1] }
            elseif ($t.StartsWith('附錄')) { $key = 'appendix' }
            elseif ($t.StartsWith('完成前自我檢查')) { $key = 'selfcheck' }
        }
        else {
            if ($t.StartsWith('5 章共通規則')) { $key = 'ch5common' }
            elseif ($t -match '^5\.([1-8])\s') { $key = 'ch5.' + $Matches[1] }
            elseif ($t -match '^7\.1\s') { $key = 'ch7a' }
        }
        if ($key -eq '' -or $r.ContainsKey($key)) { continue }
        $end = $n
        for ($j = $k + 1; $j -lt $heads.Count; $j++) {
            $o = $heads[$j]
            if ($key -eq 'ch7a') { if ($o.Level -le 2 -or ($o.Level -eq 3 -and ([string]$o.Text) -match '^7\.3\s')) { $end = $o.Line - 1; break } }
            elseif ($o.Level -le $h.Level) { $end = $o.Line - 1; break }
        }
        $r[$key] = @($h.Line, $end)
    }
    return $r
}

# ---------------- 全部檢查 ----------------
function Invoke-PsBzCheck {
    # 回傳 @{ Findings; Evidence; Stats }。Ctx 見 Test-PsBzEvidenceItems。
    param([string]$OutDir, [hashtable]$Ctx)
    $all = New-Object System.Collections.Generic.List[object]
    foreach ($x in (Test-PsBzStructure $OutDir)) { $all.Add($x) }
    $ev = Read-PsBzEvidence $OutDir
    foreach ($x in (Test-PsBzEvidenceItems $ev $Ctx)) { $all.Add($x) }
    foreach ($x in (Test-PsBzReferences $OutDir $ev)) { $all.Add($x) }
    foreach ($x in (Test-PsBzRequirementEvidence $OutDir)) { $all.Add($x) }
    $reqs = 0
    foreach ($tb in (Get-PsBzTables (Get-PsBzTextOf (Get-PsBzChapterFiles $OutDir '04-requirement-index')))) {
        if (Test-PsBzHeader $tb.Header $script:PsBzIndexHeader) { foreach ($row in $tb.Rows) { if ((Get-PsBzCell $tb $row '需求鍵') -cmatch '^[A-Z]+-[0-9]{3,}$') { $reqs++ } } }
    }
    $open = 0; foreach ($a in (Get-PsBzAssumptions $OutDir)) { if ($a.State -ceq '開放') { $open++ } }
    $q = 0; foreach ($it in $ev.Items) { if ($it.Type -ceq '補查') { $q++ } }
    return @{ Findings = $all.ToArray(); Evidence = $ev; Stats = @{ Requirements = $reqs; Evidence = @($ev.Items).Count; QueryEvidence = $q; OpenAssumptions = $open } }
}

function ConvertTo-PsBzFindingsMd {
    param($Findings, [string]$Title, [int]$Max = 200)
    $lines = @(('# ' + $Title), '', ('共 ' + @($Findings).Count + ' 項；只修表列的問題，不重寫其他內容。'), '', '| 代碼 | 檔案 | 說明 |', '|---|---|---|')
    $n = 0
    foreach ($f in @($Findings)) {
        if ($n -ge $Max) { $lines += ('| … | … | 其餘 ' + (@($Findings).Count - $Max) + ' 項：修完上面的再跑一次檢查 |'); break }
        $lines += ('| ' + $f.Code + ' | ' + ([string]$f.File).Replace('|', '\|') + ' | ' + ([string]$f.Detail).Replace('|', '\|') + ' |')
        $n++
    }
    return (($lines -join "`n") + "`n")
}
