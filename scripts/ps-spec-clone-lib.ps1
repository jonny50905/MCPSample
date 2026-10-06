# ps-spec-clone-lib.ps1 — 核心重建規格的封閉資料契約、結構驗證與確定性 Markdown。
# 先 dot-source ps-knowledge-lib.ps1；本檔不查 DB、不叫模型、不寫研究文件。
$script:PsCloneLibVersion = 1

function Get-PsCloneProp {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { if ($Object.Contains($Name)) { return , $Object[$Name] }; return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return , $p.Value
}
function Get-PsCloneKeys {
    param($Object)
    if ($null -eq $Object) { return , @() }
    if ($Object -is [System.Collections.IDictionary]) { return , @($Object.Keys | ForEach-Object { [string]$_ }) }
    return , @($Object.PSObject.Properties.Name)
}
function Test-PsCloneObject { param($Value) return ($Value -is [System.Collections.IDictionary] -or $Value -is [System.Management.Automation.PSCustomObject]) }
function Test-PsCloneArray { param($Value) return ($Value -is [System.Array] -or $Value -is [System.Collections.IList]) }
function Test-PsCloneText { param($Value) return ($Value -is [string] -and -not [string]::IsNullOrWhiteSpace($Value)) }
function Test-PsCloneUnknown {
    param([string]$Text)
    return ($Text -match '(?i)^\s*(?:UNKNOWN|UNRESOLVED|TODO|TBD|NOT_VERIFIED)(?![A-Za-z0-9_])|^\s*(?:待查|待補|待確認|未知|未確認|查無)(?:$|[\s:：（(])|^\s*(?:N/A|[-?])\s*$')
}
function Test-PsCloneLocator {
    param([string]$Kind, [string]$Locator)
    if ($Locator -match '(?i)https?://|file://') { return $false }
    if ($Kind -ceq 'CHUNK') { return ($Locator -match '(?i)(?<![0-9a-f])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![0-9a-f])') }
    if ($Kind -ceq 'NN') {
        if ($Locator -match '(^|/)\.{1,2}(/|$)') { return $false }
        $m = [regex]::Match($Locator, '^docs/ps-research/[^\r\n<>:]+\.md(?::|#)L?([1-9][0-9]*)-L?([1-9][0-9]*)$')
        if (-not $m.Success) { return $false }
        $start = 0L; $end = 0L
        return ([long]::TryParse($m.Groups[1].Value, [ref]$start) -and [long]::TryParse($m.Groups[2].Value, [ref]$end) -and $end -ge $start -and $Locator -notmatch '\\')
    }
    if ($Kind -ceq 'SQL') {
        # 只驗可讀 SQL 的外形；不執行，也不宣稱查詢結果已被核對。
        $sql = [regex]::Replace($Locator, "'(?:''|[^'])*'", "''")
        $sql = [regex]::Replace($sql, '(?s)/\*.*?\*/', ' ')
        $sql = [regex]::Replace($sql, '(?m)--[^\r\n]*', ' ')
        if ($sql -notmatch '(?is)^\s*SELECT\b' -or $sql -notmatch '(?i)\bFROM\b') { return $false }
        if ($sql -match '(?i)\b(?:INSERT|UPDATE|DELETE|MERGE|ALTER|DROP|CREATE|TRUNCATE|EXEC|EXECUTE|GRANT|REVOKE|INTO)\b') { return $false }
        return ($sql.Trim().TrimEnd(';') -notmatch ';')
    }
    return $false
}
function Test-PsCloneShape {
    param($Object, [string[]]$Keys, [string]$Where)
    $errs = @()
    if (-not (Test-PsCloneObject $Object)) { return , @($Where + ':OBJECT_REQUIRED') }
    $actual = Get-PsCloneKeys $Object
    foreach ($k in $Keys) { if ($actual -cnotcontains $k) { $errs += ($Where + ':MISSING_' + $k) } }
    foreach ($k in $actual) { if ($Keys -cnotcontains $k) { $errs += ($Where + ':UNKNOWN_' + $k) } }
    return , $errs
}
function ConvertFrom-PsCloneFieldExclusion {
    # scope 原生欄位排除項的 object：<RECORD>：<FIELD>、<FIELD>…（原名大寫）。回傳 @{ Ok; Record; Fields }。
    param([string]$Object)
    $r = @{ Ok = $false; Record = ''; Fields = @() }
    $m = [regex]::Match([string]$Object, '^\s*([^：:]+?)\s*[：:]\s*(.+?)\s*$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $m.Success) { return $r }
    $record = $m.Groups[1].Value
    if ($record -cnotmatch '^[A-Z0-9_][A-Z0-9_$#-]{0,59}$') { return $r }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $fields = @()
    foreach ($f in ($m.Groups[2].Value -split '[、,，;；\s]+')) {
        if ($f -eq '') { continue }
        if ($f -cnotmatch '^[A-Z0-9_][A-Z0-9_$#]{0,59}$') { return $r }
        if ($seen.Add($f)) { $fields += $f }
    }
    if ($fields.Count -eq 0) { return $r }
    $r.Ok = $true; $r.Record = $record; $r.Fields = $fields
    return $r
}
# Record 的「原生欄位判定」三種結論；判不了只准下列原因代碼。
$script:PsCloneFieldUsageCodes = @('NO_TABLE', 'EMPTY_TABLE', 'NOT_PROD', 'TIMEOUT', 'QUERY_FAILED', 'CHECK_INCOMPLETE')
function ConvertFrom-PsCloneFieldUsage {
    # 排除 <n> 欄（<FIELD 項 ID>）／無可排除（查詢日 YYYY-MM-DD）／判不了：<代碼>。回傳 @{ Kind; Count; Ref; Code }，Kind 空字串＝格式不符。
    param([string]$Text)
    $r = @{ Kind = ''; Count = 0; Ref = ''; Code = '' }
    $m = [regex]::Match([string]$Text, '^\s*排除\s*([0-9]{1,4})\s*欄\s*[（(]\s*([A-Za-z][A-Za-z0-9_.-]{0,79})\s*[）)]')
    if ($m.Success) { $r.Kind = 'EXCLUDE'; $r.Count = [int]$m.Groups[1].Value; $r.Ref = $m.Groups[2].Value; return $r }
    $m = [regex]::Match([string]$Text, '^\s*無可排除\s*[（(]\s*查詢日\s*[:：]?\s*([0-9]{4}-[0-9]{2}-[0-9]{2})\s*[）)]')
    if ($m.Success) {
        $d = [datetime]::MinValue
        if ([datetime]::TryParseExact($m.Groups[1].Value, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { $r.Kind = 'NONE' }
        return $r
    }
    $m = [regex]::Match([string]$Text, '^\s*判不了\s*[：:]\s*([A-Z_]+)(?![A-Za-z0-9_])')
    if ($m.Success -and $script:PsCloneFieldUsageCodes -ccontains $m.Groups[1].Value) { $r.Kind = 'UNDETERMINED'; $r.Code = $m.Groups[1].Value }
    return $r
}
function Get-PsCloneRecordKey {
    # Record 名比對鍵：開頭識別字、大寫、去掉 PS_ 實體表前綴。
    param([string]$Name)
    $m = [regex]::Match([string]$Name, '^\s*([A-Za-z0-9_$#-]+)')
    if (-not $m.Success) { return '' }
    $k = $m.Groups[1].Value.ToUpperInvariant()
    if ($k.StartsWith('PS_')) { $k = $k.Substring(3) }
    return $k
}
function Test-PsCloneRecordItem {
    # 範圍內（CORE／DEPENDENCY）的 Record：每筆都要有原生欄位判定。
    param($Item)
    if (-not (Test-PsCloneObject $Item)) { return $false }
    $v = Get-PsCloneProp $Item 'values'
    return ([string](Get-PsCloneProp $v 'type') -ceq 'RECORD' -and @('CORE', 'DEPENDENCY') -ccontains [string](Get-PsCloneProp $v 'inclusion'))
}
function Test-PsCloneFieldExclusionItem {
    param($Item)
    if (-not (Test-PsCloneObject $Item)) { return $false }
    $v = Get-PsCloneProp $Item 'values'
    return ([string](Get-PsCloneProp $v 'type') -ceq 'FIELD' -and [string](Get-PsCloneProp $v 'inclusion') -ceq 'EXCLUDED')
}
function Get-PsCloneExcludedFieldKeys {
    # 已核定 scope 的原生欄位排除項 → 'RECORD.FIELD' 集合（Ordinal）。
    param($ScopeItems)
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($s in @($ScopeItems)) {
        if (-not (Test-PsCloneFieldExclusionItem $s)) { continue }
        $x = ConvertFrom-PsCloneFieldExclusion ([string]$s.values.object)
        if (-not $x.Ok) { continue }
        foreach ($f in $x.Fields) { [void]$set.Add($x.Record + '.' + $f) }
    }
    return , $set
}
function Find-PsCloneExcludedMentions {
    # 正文 values 指到已排除欄位的 'RECORD.FIELD'：任一欄的 Record.Field（含 PS_ 實體表前綴）；
    # data 類同時有 record 與 field 欄時，另比對 record 欄的 Record 與 field 欄的欄位名。
    param($Values, $Excluded)
    $hits = New-Object 'System.Collections.Generic.List[string]'
    if ($null -eq $Excluded -or $Excluded.Count -eq 0 -or -not (Test-PsCloneObject $Values)) { return , $hits.ToArray() }
    $keys = Get-PsCloneKeys $Values
    foreach ($key in $keys) {
        $text = Get-PsCloneProp $Values $key
        if ($text -isnot [string]) { continue }
        foreach ($m in [regex]::Matches($text, '(?<![A-Za-z0-9_$#])([A-Za-z0-9_$#]+)\.([A-Za-z0-9_$#]+)(?![A-Za-z0-9_$#])')) {
            $rec = $m.Groups[1].Value.ToUpperInvariant(); $fld = $m.Groups[2].Value.ToUpperInvariant(); $hit = ''
            if ($Excluded.Contains($rec + '.' + $fld)) { $hit = $rec + '.' + $fld }
            elseif ($rec.StartsWith('PS_') -and $Excluded.Contains($rec.Substring(3) + '.' + $fld)) { $hit = $rec.Substring(3) + '.' + $fld }
            if ($hit -ne '' -and -not $hits.Contains($hit)) { $hits.Add($hit) }
        }
    }
    $record = Get-PsCloneProp $Values 'record'; $field = Get-PsCloneProp $Values 'field'
    if ($record -is [string] -and $field -is [string]) {
        $rm = [regex]::Match($record, '^\s*([A-Za-z0-9_$#]+)')
        if ($rm.Success) {
            $rec = $rm.Groups[1].Value.ToUpperInvariant()
            $recs = @($rec); if ($rec.StartsWith('PS_')) { $recs += $rec.Substring(3) }
            foreach ($tok in [regex]::Matches($field, '[A-Za-z0-9_$#]+')) {
                foreach ($candidate in $recs) {
                    $k = $candidate + '.' + $tok.Value.ToUpperInvariant()
                    if ($Excluded.Contains($k) -and -not $hits.Contains($k)) { $hits.Add($k) }
                }
            }
        }
    }
    return , $hits.ToArray()
}
function Get-PsCloneFieldExclusionPlan {
    # 不建置欄位：各 Component scope 的排除項，扣掉其他 Component 正文仍引用者（跨 Component 須建置）。
    param([string[]]$Components, $Packets)
    $rows = New-Object 'System.Collections.Generic.List[object]'
    $conflicts = New-Object 'System.Collections.Generic.List[string]'
    $fieldKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $recordKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($component in $Components) {
        $scopeItems = @()
        foreach ($p in @($Packets)) { if ($null -ne $p -and $p.component -ceq $component -and $p.topic -ceq 'scope') { $scopeItems += @($p.items) } }
        $excluded = Get-PsCloneExcludedFieldKeys $scopeItems
        if ($excluded.Count -eq 0) { continue }
        $usedElsewhere = @{}
        foreach ($p in @($Packets)) {
            if ($null -eq $p -or $p.component -ceq $component -or $p.topic -ceq 'scope') { continue }
            foreach ($item in @($p.items)) {
                if (-not (Test-PsCloneObject $item)) { continue }
                $hits = Find-PsCloneExcludedMentions $item.values $excluded
                foreach ($h in $hits) {
                    if (-not $usedElsewhere.ContainsKey($h)) { $usedElsewhere[$h] = New-Object 'System.Collections.Generic.List[string]' }
                    if (-not $usedElsewhere[$h].Contains([string]$p.component)) { $usedElsewhere[$h].Add([string]$p.component) }
                }
            }
        }
        foreach ($s in $scopeItems) {
            if (-not (Test-PsCloneFieldExclusionItem $s)) { continue }
            $x = ConvertFrom-PsCloneFieldExclusion ([string]$s.values.object)
            if (-not $x.Ok) { continue }
            $kept = @()
            foreach ($f in $x.Fields) {
                $k = $x.Record + '.' + $f
                if ($usedElsewhere.ContainsKey($k)) { $conflicts.Add($k + '（' + $component + ' 判定無用；' + ($usedElsewhere[$k].ToArray() -join '、') + ' 正文引用）') }
                else { $kept += $f; [void]$fieldKeys.Add($k) }
            }
            if ($kept.Count -eq 0) { continue }
            [void]$recordKeys.Add($x.Record)
            $rows.Add(@{ Component = $component; Id = [string]$s.id; Record = $x.Record; Fields = $kept; Condition = [string]$s.values.condition; UsedBy = [string]$s.values.usedBy })
        }
    }
    return @{ Rows = $rows.ToArray(); Conflicts = $conflicts.ToArray(); RecordCount = $recordKeys.Count; FieldCount = $fieldKeys.Count }
}
function Get-PsCloneRecordCoverage {
    # 範圍內 Record 的原生欄位判定覆蓋：已判定（排除／無可排除）、判不了（依原因代碼）。
    param($Packets)
    $total = 0; $checked = 0; $undetermined = 0; $byCode = @{}
    foreach ($p in @($Packets)) {
        if ($null -eq $p -or $p.topic -cne 'scope') { continue }
        foreach ($item in @($p.items)) {
            if (-not (Test-PsCloneRecordItem $item)) { continue }
            $total++
            $u = ConvertFrom-PsCloneFieldUsage ([string](Get-PsCloneProp $item.values 'fieldUsage'))
            if ($u.Kind -eq 'EXCLUDE' -or $u.Kind -eq 'NONE') { $checked++ }
            elseif ($u.Kind -eq 'UNDETERMINED') { $undetermined++; if (-not $byCode.ContainsKey($u.Code)) { $byCode[$u.Code] = 0 }; $byCode[$u.Code]++ }
        }
    }
    $ordered = [ordered]@{}
    $codes = Sort-PsKnOrdinal -Items @($byCode.Keys)
    foreach ($c in $codes) { $ordered[$c] = [int]$byCode[$c] }
    return @{ Total = $total; Checked = $checked; Undetermined = $undetermined; ByCode = $ordered }
}
function Format-PsCloneUndeterminedCodes {
    param($ByCode)
    $parts = @()
    foreach ($k in $ByCode.Keys) { $parts += ([string]$k + ' ' + [string]$ByCode[$k]) }
    return ($parts -join '、')
}
function Get-PsCloneFieldStats {
    # 只有計數與封閉代碼，可對維護端回報；不含物件名。
    param([string[]]$Components, $Packets)
    $plan = Get-PsCloneFieldExclusionPlan -Components $Components -Packets $Packets
    $cov = Get-PsCloneRecordCoverage -Packets $Packets
    $ui = 0; $data = 0
    foreach ($p in @($Packets)) {
        if ($null -eq $p) { continue }
        if ($p.topic -ceq 'ui') { $ui += @($p.items).Count }
        elseif ($p.topic -ceq 'data') { $data += @($p.items).Count }
    }
    return [ordered]@{ scopeRecords = [int]$cov.Total; checkedRecords = [int]$cov.Checked; undeterminedRecords = [int]$cov.Undetermined; undeterminedByCode = $cov.ByCode; excludedRecords = [int]$plan.RecordCount; excludedFields = [int]$plan.FieldCount; crossComponentKept = [int]@($plan.Conflicts).Count; uiItems = [int]$ui; dataItems = [int]$data }
}
function Get-PsCloneProfile {
    param([string]$Root)
    $path = Get-PsCliPsPath -Root $Root -Rel 'spec/clone-profile.json'
    $text = Read-PsKnText -LiteralPath $path
    if ($null -eq $text) { throw 'CLONE_PROFILE_MISSING' }
    $p = $text | ConvertFrom-Json -ErrorAction Stop
    if ($p.schemaVersion -ne 1 -or $p.maxItemsPerPage -ne 40 -or @($p.topics).Count -ne 10) { throw 'CLONE_PROFILE_INVALID' }
    $expected = @('scope','flows','ui','data','rules','states','transactions','interfaces','security','acceptance')
    for ($i = 0; $i -lt $expected.Count; $i++) {
        $t = $p.topics[$i]
        if ($t.id -cne $expected[$i] -or @($t.fields).Count -eq 0) { throw 'CLONE_PROFILE_INVALID' }
        $seen = @{}
        foreach ($f in $t.fields) { if ($f.key -notmatch '^[A-Za-z][A-Za-z0-9]*$' -or $seen.ContainsKey($f.key) -or -not (Test-PsCloneText $f.label)) { throw 'CLONE_PROFILE_INVALID' }; $seen[$f.key] = $true }
    }
    return $p
}
function Test-PsClonePacket {
    param($Packet, [string]$Component, [string]$Topic, $Profile, $ScopeItems = @())
    $r = @{ Ok = $false; Errors = @(); Packet = $Packet; Items = @() }
    $errs = Test-PsCloneShape $Packet @('schemaVersion','component','topic','coverage','summary','items','evidence','gaps','nextCursor') 'packet'
    $r.Errors += $errs
    if (-not (Test-PsCloneObject $Packet)) { return $r }
    $def = $null
    foreach ($t in $Profile.topics) { if ($t.id -ceq $Topic) { $def = $t; break } }
    if ($null -eq $def) { $r.Errors += 'TOPIC_UNKNOWN'; return $r }
    if ($Packet.schemaVersion -isnot [int] -and $Packet.schemaVersion -isnot [long]) { $r.Errors += 'SCHEMA_VERSION' }
    elseif ($Packet.schemaVersion -ne 1) { $r.Errors += 'SCHEMA_VERSION' }
    if ($Packet.component -isnot [string] -or $Packet.component -cne $Component) { $r.Errors += 'COMPONENT_MISMATCH' }
    if ($Packet.topic -isnot [string] -or $Packet.topic -cne $Topic) { $r.Errors += 'TOPIC_MISMATCH' }
    $coverage = [string]$Packet.coverage
    if (@('COMPLETE','PARTIAL','NOT_APPLICABLE') -cnotcontains $coverage) { $r.Errors += 'COVERAGE_INVALID' }
    if (-not (Test-PsCloneText $Packet.summary) -or $Packet.summary -notmatch '[\u3400-\u9fff]') { $r.Errors += 'SUMMARY_REQUIRED_ZH' }
    if ($Packet.nextCursor -isnot [string] -or ([string]$Packet.nextCursor).Length -gt 240 -or [string]$Packet.nextCursor -match '[\r\n\x00]') { $r.Errors += 'CURSOR_INVALID' }
    if ($coverage -ne 'PARTIAL' -and [string]$Packet.nextCursor -ne '') { $r.Errors += 'CURSOR_REQUIRES_PARTIAL' }
    foreach ($key in @('items','evidence','gaps')) { $value = Get-PsCloneProp $Packet $key; if (-not (Test-PsCloneArray $value)) { $r.Errors += ('ARRAY_REQUIRED_' + $key) } }
    $items = Get-PsCloneProp $Packet 'items'; $evs = Get-PsCloneProp $Packet 'evidence'; $gaps = Get-PsCloneProp $Packet 'gaps'
    $items = @($items); $evs = @($evs); $gaps = @($gaps)
    $r.Items = $items
    if ($items.Count -gt 40) { $r.Errors += 'PAGE_ITEM_LIMIT' }
    if ($coverage -eq 'COMPLETE' -and $items.Count -eq 0) { $r.Errors += 'EMPTY_COMPLETE' }
    foreach ($gap in $gaps) { if (-not (Test-PsCloneText $gap)) { $r.Errors += 'GAP_INVALID' } }
    if ($coverage -eq 'COMPLETE' -and $gaps.Count -gt 0) { $r.Errors += 'COMPLETE_HAS_GAPS' }
    if ($coverage -eq 'PARTIAL' -and $gaps.Count -eq 0 -and [string]$Packet.nextCursor -eq '') { $r.Errors += 'PARTIAL_REASON_REQUIRED' }
    if ($coverage -eq 'NOT_APPLICABLE') {
        if (-not $def.allowNotApplicable -or @('scope','ui','data','rules','acceptance') -contains $Topic) { $r.Errors += 'NOT_APPLICABLE_FORBIDDEN' }
        if ($items.Count -gt 0 -or $gaps.Count -gt 0) { $r.Errors += 'NOT_APPLICABLE_HAS_ITEMS_OR_GAPS' }
        if ($evs.Count -eq 0) { $r.Errors += 'NOT_APPLICABLE_EVIDENCE_REQUIRED' }
        if (Test-PsCloneUnknown ([string]$Packet.summary)) { $r.Errors += 'NOT_APPLICABLE_REASON_REQUIRED' }
    }
    $eids = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $evMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
    foreach ($ev in $evs) {
        $e = Test-PsCloneShape $ev @('id','kind','locator','excerpt') 'evidence'; $r.Errors += $e
        if (-not (Test-PsCloneObject $ev)) { continue }
        if ($ev.id -isnot [string] -or $ev.id -cnotmatch '^E[1-9][0-9]*$' -or -not $eids.Add([string]$ev.id)) { $r.Errors += 'EVIDENCE_ID_INVALID_OR_DUPLICATE' }
        elseif (-not $evMap.ContainsKey([string]$ev.id)) { $evMap[[string]$ev.id] = $ev }
        if (@('CHUNK','SQL','NN') -cnotcontains [string]$ev.kind) { $r.Errors += 'EVIDENCE_KIND_INVALID' }
        if (-not (Test-PsCloneText $ev.locator) -or (Test-PsCloneUnknown ([string]$ev.locator))) { $r.Errors += 'EVIDENCE_LOCATOR_REQUIRED' }
        elseif (-not (Test-PsCloneLocator -Kind ([string]$ev.kind) -Locator ([string]$ev.locator))) { $r.Errors += 'EVIDENCE_LOCATOR_INVALID' }
        if (-not (Test-PsCloneText $ev.excerpt) -or (Test-PsCloneUnknown ([string]$ev.excerpt))) { $r.Errors += 'EVIDENCE_EXCERPT_REQUIRED' }
        elseif (@(([string]$ev.excerpt -replace "`r", '') -split "`n").Count -gt 5) { $r.Errors += 'EVIDENCE_EXCERPT_TOO_LONG' }
    }
    $scopeMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
    foreach ($s in @($ScopeItems)) { if ($null -ne $s -and (Test-PsCloneText $s.id)) { $scopeMap[[string]$s.id] = $s } }
    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $fieldKeys = @($def.fields | ForEach-Object { [string]$_.key })
    $excludedKeys = $null
    if ($Topic -ne 'scope') { $excludedKeys = Get-PsCloneExcludedFieldKeys $ScopeItems }
    $pageFieldItems = @{}; $pageExcludeRefs = @()
    foreach ($item in $items) {
        $e = Test-PsCloneShape $item @('id','scopeRefs','values','evidenceIds') 'item'; $r.Errors += $e
        if (-not (Test-PsCloneObject $item)) { continue }
        $id = [string]$item.id
        if ($item.id -isnot [string] -or $id -cnotmatch '^[A-Za-z][A-Za-z0-9_.-]{0,79}$' -or -not $ids.Add($id)) { $r.Errors += 'ITEM_ID_INVALID_OR_DUPLICATE' }
        $e = Test-PsCloneShape $item.values $fieldKeys ('values.' + $id); $r.Errors += $e
        foreach ($key in $fieldKeys) {
            $v = Get-PsCloneProp $item.values $key
            if (-not (Test-PsCloneText $v)) { $r.Errors += ('VALUE_REQUIRED:' + $id + '.' + $key) }
            elseif ($coverage -eq 'COMPLETE' -and (Test-PsCloneUnknown $v)) { $r.Errors += ('UNRESOLVED_COMPLETE:' + $id + '.' + $key) }
            elseif ($coverage -eq 'PARTIAL' -and $gaps.Count -eq 0 -and (Test-PsCloneUnknown $v)) { $r.Errors += ('UNRESOLVED_GAP_REQUIRED:' + $id + '.' + $key) }
        }
        $refs = Get-PsCloneProp $item 'scopeRefs'; $eRefs = Get-PsCloneProp $item 'evidenceIds'
        if (-not (Test-PsCloneArray $refs)) { $r.Errors += ('SCOPE_REFS_ARRAY:' + $id) }
        if (-not (Test-PsCloneArray $eRefs) -or @($eRefs).Count -eq 0) { $r.Errors += ('EVIDENCE_REFS_REQUIRED:' + $id) }
        foreach ($eid in @($eRefs)) { if ($eid -isnot [string] -or -not $eids.Contains([string]$eid)) { $r.Errors += ('EVIDENCE_REF_UNKNOWN:' + $id) } }
        if ($Topic -eq 'scope') {
            if (@($refs).Count -ne 0) { $r.Errors += ('SCOPE_ROOT_REFS_MUST_BE_EMPTY:' + $id) }
            $v = $item.values
            if (@('CORE','DEPENDENCY','EXCLUDED') -cnotcontains [string]$v.inclusion) { $r.Errors += ('INCLUSION_INVALID:' + $id) }
            if ([string]$v.inclusion -eq 'CORE' -and [string]$v.type -eq 'COMPONENT' -and [string]$v.object -cne $Component) { $r.Errors += ('FOREIGN_CORE_COMPONENT:' + $id) }
            if ([string]$v.inclusion -eq 'DEPENDENCY') { foreach ($k in @('usedBy','condition','reason')) { $value = Get-PsCloneProp $v $k; if (-not (Test-PsCloneText $value) -or (Test-PsCloneUnknown $value)) { $r.Errors += ('DEPENDENCY_RELATION_REQUIRED:' + $id + '.' + $k) } } }
            if ([string]$v.type -ieq 'FIELD' -and [string]$v.type -cne 'FIELD') { $r.Errors += ('FIELD_TYPE_CASE:' + $id) }
            if ([string]$v.type -ieq 'RECORD' -and [string]$v.type -cne 'RECORD') { $r.Errors += ('RECORD_TYPE_CASE:' + $id) }
            if (Test-PsCloneRecordItem $item) {
                # 每個範圍內 Record 都要有判定結論；「沒查」只能寫成判不了＋原因代碼，統計看得到。
                $u = ConvertFrom-PsCloneFieldUsage ([string](Get-PsCloneProp $v 'fieldUsage'))
                if ($u.Kind -eq '') { $r.Errors += ('FIELD_USAGE_REQUIRED:' + $id) }
                elseif ($u.Kind -eq 'EXCLUDE') { $pageExcludeRefs += , @{ Id = $id; Ref = $u.Ref; Count = $u.Count; Key = (Get-PsCloneRecordKey ([string]$v.object)) } }
                elseif ($u.Kind -eq 'NONE') {
                    $hasProfile = $false
                    foreach ($eid in @($eRefs)) {
                        if ($eid -isnot [string] -or -not $evMap.ContainsKey([string]$eid)) { continue }
                        $ev = $evMap[[string]$eid]
                        if ([string]$ev.kind -ceq 'SQL' -and [string]$ev.locator -match '(?i)\bALL_TAB_COLUMNS\b|\b(?:COUNT|SUM)\s*\(') { $hasProfile = $true }
                    }
                    if (-not $hasProfile) { $r.Errors += ('FIELD_USAGE_EVIDENCE_REQUIRED:' + $id) }
                }
            }
            if ([string]$v.type -ceq 'FIELD') {
                # 原生欄位只記判定無用者；保留的欄位不逐欄列進 scope。
                if ([string]$v.inclusion -cne 'EXCLUDED') { $r.Errors += ('FIELD_SCOPE_EXCLUDED_ONLY:' + $id) }
                $fx = ConvertFrom-PsCloneFieldExclusion ([string]$v.object)
                if (-not $fx.Ok) { $r.Errors += ('FIELD_EXCLUSION_OBJECT_INVALID:' + $id) }
                elseif ([string]$v.inclusion -ceq 'EXCLUDED') { $pageFieldItems[$id] = @{ Key = (Get-PsCloneRecordKey $fx.Record); Count = @($fx.Fields).Count } }
                $dm = [regex]::Match([string]$v.condition, '^\s*非預設\s*0\s*筆\s*[（(]\s*全表非空\s*[，,、]\s*查詢日\s*[:：]?\s*([0-9]{4}-[0-9]{2}-[0-9]{2})\s*[）)]')
                $queryDate = [datetime]::MinValue
                if (-not $dm.Success -or -not [datetime]::TryParseExact($dm.Groups[1].Value, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$queryDate)) { $r.Errors += ('FIELD_EXCLUSION_CONDITION_INVALID:' + $id) }
                foreach ($mark in @('a', 'b', 'c')) { if ([string]$v.usedBy -notmatch ('(?:^|[；;，,、\s])' + $mark + '\s*[：:]')) { $r.Errors += ('FIELD_EXCLUSION_CHECKS_REQUIRED:' + $id + '.' + $mark) } }
                $hasData = $false; $hasXref = $false
                foreach ($eid in @($eRefs)) {
                    if ($eid -isnot [string] -or -not $evMap.ContainsKey([string]$eid)) { continue }
                    $ev = $evMap[[string]$eid]
                    if ([string]$ev.kind -cne 'SQL') { continue }
                    if ([string]$ev.locator -match '(?i)\bPSPCMNAME\b') { $hasXref = $true }
                    elseif ([string]$ev.locator -match '(?i)\b(?:COUNT|SUM)\s*\(') { $hasData = $true }
                }
                if (-not $hasData) { $r.Errors += ('FIELD_EXCLUSION_DATA_SQL_REQUIRED:' + $id) }
                if (-not $hasXref) { $r.Errors += ('FIELD_EXCLUSION_XREF_SQL_REQUIRED:' + $id) }
            }
            $scopeMap[$id] = $item
        }
        else {
            if (@($refs).Count -eq 0) { $r.Errors += ('SCOPE_REFS_REQUIRED:' + $id) }
            foreach ($sid in @($refs)) {
                if ($sid -isnot [string] -or -not $scopeMap.ContainsKey([string]$sid)) { $r.Errors += ('SCOPE_REF_UNKNOWN:' + $id); continue }
                if (@('CORE','DEPENDENCY') -cnotcontains [string]$scopeMap[[string]$sid].values.inclusion) { $r.Errors += ('SCOPE_REF_EXCLUDED:' + $id) }
            }
            $mentions = Find-PsCloneExcludedMentions $item.values $excludedKeys
            foreach ($hit in $mentions) { $r.Errors += ('FIELD_EXCLUDED_IN_BODY:' + $id + ':' + $hit) }
            if ($Topic -eq 'acceptance' -and @('POSITIVE','NEGATIVE','BOUNDARY') -cnotcontains [string]$item.values.scenarioType) { $r.Errors += ('SCENARIO_TYPE_INVALID:' + $id) }
        }
    }
    if ($Topic -eq 'scope') {
        $rootFound = $false
        foreach ($s in $scopeMap.Values) { if ([string]$s.values.inclusion -ceq 'CORE' -and [string]$s.values.type -ceq 'COMPONENT' -and [string]$s.values.object -ceq $Component) { $rootFound = $true } }
        if (-not $rootFound) { $r.Errors += 'CORE_COMPONENT_REQUIRED' }
        # 「排除 n 欄（ID）」要指到同一頁、同一 Record、欄數相符的 FIELD 項；FIELD 項也必須有 Record 項指到它。
        $referenced = @{}
        foreach ($ref in $pageExcludeRefs) {
            $target = $null
            if ($pageFieldItems.ContainsKey($ref.Ref)) { $target = $pageFieldItems[$ref.Ref] }
            if ($null -eq $target -or $target.Key -cne $ref.Key -or $target.Count -ne $ref.Count) { $r.Errors += ('FIELD_USAGE_REF_INVALID:' + $ref.Id) }
            else { $referenced[$ref.Ref] = $true }
        }
        $fieldIds = Sort-PsKnOrdinal -Items @($pageFieldItems.Keys)
        foreach ($fid in $fieldIds) { if (-not $referenced.ContainsKey($fid)) { $r.Errors += ('FIELD_EXCLUSION_ORPHAN:' + $fid) } }
    }
    $r.Ok = ($r.Errors.Count -eq 0)
    return $r
}

function Test-PsCloneReview {
    param($Review, $Packet, [string]$InputHash)
    $r = @{ Ok = $false; Errors = @(); Passed = $false }
    $e = Test-PsCloneShape $Review @('schemaVersion','component','topic','inputHash','verdict','checkedIds','findings','summary') 'review'; $r.Errors += $e
    if (-not (Test-PsCloneObject $Review)) { return $r }
    if (($Review.schemaVersion -isnot [int] -and $Review.schemaVersion -isnot [long]) -or $Review.schemaVersion -ne 1) { $r.Errors += 'SCHEMA_VERSION' }
    if ($Review.component -cne $Packet.component -or $Review.topic -cne $Packet.topic) { $r.Errors += 'REVIEW_IDENTITY_MISMATCH' }
    if ($InputHash -notmatch '^[A-Fa-f0-9]{64}$' -or $Review.inputHash -isnot [string] -or $Review.inputHash -cne $InputHash) { $r.Errors += 'REVIEW_HASH_MISMATCH' }
    if (@('PASS','FAIL','BLOCKED') -cnotcontains [string]$Review.verdict) { $r.Errors += 'REVIEW_VERDICT_INVALID' }
    if (-not (Test-PsCloneText $Review.summary) -or $Review.summary -notmatch '[\u3400-\u9fff]') { $r.Errors += 'REVIEW_SUMMARY_REQUIRED_ZH' }
    $checked = Get-PsCloneProp $Review 'checkedIds'; $findings = Get-PsCloneProp $Review 'findings'; $items = Get-PsCloneProp $Packet 'items'
    if (-not (Test-PsCloneArray $checked)) { $r.Errors += 'REVIEW_CHECKED_ARRAY' }
    if (-not (Test-PsCloneArray $findings)) { $r.Errors += 'REVIEW_FINDINGS_ARRAY' }
    $expected = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($item in @($items)) { [void]$expected.Add([string]$item.id) }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($id in @($checked)) { if ($id -isnot [string] -or -not $expected.Contains([string]$id) -or -not $seen.Add([string]$id)) { $r.Errors += 'REVIEW_CHECKED_UNKNOWN_OR_DUPLICATE' } }
    if ([string]$Review.verdict -ceq 'PASS' -and -not $seen.SetEquals($expected)) { $r.Errors += 'REVIEW_CHECKED_INCOMPLETE' }
    foreach ($finding in @($findings)) {
        $e = Test-PsCloneShape $finding @('itemId','code','detail') 'finding'; $r.Errors += $e
        if (-not (Test-PsCloneObject $finding)) { continue }
        if (-not (Test-PsCloneText $finding.itemId) -or ([string]$finding.itemId -cne 'TOPIC' -and -not $expected.Contains([string]$finding.itemId))) { $r.Errors += 'REVIEW_FINDING_ITEM_UNKNOWN' }
        if (@('MISSING_DETAIL','MISSING_BRANCH','EVIDENCE_MISMATCH','SCOPE_NOISE','CONTRADICTION','LANGUAGE','TOOL_BLOCKED') -cnotcontains [string]$finding.code) { $r.Errors += 'REVIEW_FINDING_CODE_INVALID' }
        if (-not (Test-PsCloneText $finding.detail)) { $r.Errors += 'REVIEW_FINDING_DETAIL_REQUIRED' }
    }
    if ([string]$Review.verdict -ceq 'PASS' -and @($findings).Count -gt 0) { $r.Errors += 'REVIEW_PASS_HAS_FINDINGS' }
    if (@('FAIL','BLOCKED') -ccontains [string]$Review.verdict -and @($findings).Count -eq 0) { $r.Errors += 'REVIEW_FAILURE_REASON_REQUIRED' }
    $r.Ok = ($r.Errors.Count -eq 0)
    $r.Passed = ($r.Ok -and [string]$Review.verdict -ceq 'PASS' -and @($findings).Count -eq 0)
    return $r
}

function ConvertTo-PsCloneCell {
    param($Value)
    return ([string]$Value).Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('|','&#124;').Replace("`r",'').Replace("`n",'<br>').Replace('[','&#91;').Replace(']','&#93;')
}
function Add-PsCloneGapLines {
    param($Lines, [string[]]$Components, $Packets, $Profile, $Gaps)
    foreach ($gap in @($Gaps)) { if (-not [string]::IsNullOrWhiteSpace([string]$gap)) { [void]$Lines.Add('- ' + (ConvertTo-PsCloneCell $gap)) } }
    foreach ($component in $Components) {
        foreach ($topic in $Profile.topics) {
            $pages = @($Packets | Where-Object { $_.component -ceq $component -and $_.topic -ceq $topic.id })
            if ($pages.Count -eq 0) { [void]$Lines.Add('- ' + $component + '／' + $topic.title + '：尚無已驗收資料。'); continue }
            foreach ($page in $pages) {
                foreach ($g in @($page.gaps)) { [void]$Lines.Add('- ' + $component + '／' + $topic.title + '：' + (ConvertTo-PsCloneCell $g)) }
            }
            $last = $pages[$pages.Count - 1]
            if ($last.coverage -eq 'PARTIAL') { [void]$Lines.Add('- ' + $component + '／' + $topic.title + '：尚未閉合，需續頁或補查。') }
        }
    }
}
function ConvertTo-PsCloneSpec {
    param([string[]]$Components, $Packets, $Profile, [string]$Status, $Gaps = @())
    $o = New-Object 'System.Collections.Generic.List[string]'
    [void]$o.Add('# 核心功能重建規格')
    [void]$o.Add('')
    [void]$o.Add('狀態：' + (ConvertTo-PsCloneCell $Status))
    [void]$o.Add('指定 Component：' + (($Components | ForEach-Object { ConvertTo-PsCloneCell $_ }) -join '、'))
    [void]$o.Add('')
    [void]$o.Add('本文件供核心功能重建與人工覆核；結構驗證及獨立 LLM 覆核不等於企業 E2E 測試，也不機械證明業務語意完整。驗收情境為待執行設計。技術名稱與值保留原文。')
    [void]$o.Add('')
    [void]$o.Add('## 跨 Component 範圍與依賴')
    [void]$o.Add('')
    foreach ($component in $Components) {
        foreach ($packet in @($Packets | Where-Object { $_.component -ceq $component -and $_.topic -ceq 'scope' })) { [void]$o.Add('- ' + (ConvertTo-PsCloneCell $component) + '：' + (ConvertTo-PsCloneCell $packet.summary)) }
    }
    [void]$o.Add('')
    [void]$o.Add('| Component | 範圍 ID | 物件 | 型別 | 分類 | 使用關係／條件 | 理由 | 原生欄位判定 |')
    [void]$o.Add('|---|---|---|---|---|---|---|---|')
    foreach ($component in $Components) {
        foreach ($packet in @($Packets | Where-Object { $_.component -ceq $component -and $_.topic -ceq 'scope' })) {
            foreach ($item in $packet.items) {
                if (Test-PsCloneFieldExclusionItem $item) { continue }
                $v = $item.values; [void]$o.Add('| ' + ((@($component,$item.id,$v.object,$v.type,$v.inclusion,($v.usedBy + '；' + $v.condition),$v.reason,(Get-PsCloneProp $v 'fieldUsage')) | ForEach-Object { ConvertTo-PsCloneCell $_ }) -join ' | ') + ' |')
            }
        }
    }
    [void]$o.Add(''); [void]$o.Add('## 不建置的原生欄位'); [void]$o.Add('')
    $cov = Get-PsCloneRecordCoverage -Packets $Packets
    $covLine = '範圍內 Record 的原生欄位判定：已判定 ' + $cov.Checked + '／' + $cov.Total + '；判不了 ' + $cov.Undetermined
    if ($cov.Undetermined -gt 0) { $covLine += '（' + (Format-PsCloneUndeterminedCodes $cov.ByCode) + '）' }
    [void]$o.Add($covLine + '。判不了的 Record 欄位全部保留在正文，未經篩選。'); [void]$o.Add('')
    $plan = Get-PsCloneFieldExclusionPlan -Components $Components -Packets $Packets
    if (@($plan.Rows).Count -eq 0) { [void]$o.Add('無判定無用的原生欄位；判不了的欄位一律保留在各章節正文。') }
    else {
        [void]$o.Add('下列欄位在 PROD 全表沒有非預設值，且該 Component 核心路徑程式沒有指名引用，判定業務未使用：重建時不建資料欄、不上畫面、不寫規則。未列出的欄位以各章節正文為準。')
        [void]$o.Add('')
        [void]$o.Add('| Component | 範圍 ID | Record | 欄位 | 資料剖析 | 程式面查法 |')
        [void]$o.Add('|---|---|---|---|---|---|')
        foreach ($row in $plan.Rows) { [void]$o.Add('| ' + ((@($row.Component, $row.Id, $row.Record, ($row.Fields -join '、'), $row.Condition, $row.UsedBy) | ForEach-Object { ConvertTo-PsCloneCell $_ }) -join ' | ') + ' |') }
        [void]$o.Add('')
        [void]$o.Add('合計：' + $plan.RecordCount + ' 個 Record、' + $plan.FieldCount + ' 個欄位。')
    }
    if (@($plan.Conflicts).Count -gt 0) {
        [void]$o.Add('')
        [void]$o.Add('以下欄位雖被某 Component 判定無用，但其他 Component 正文有引用，整體重建須建置：')
        foreach ($c in $plan.Conflicts) { [void]$o.Add('- ' + (ConvertTo-PsCloneCell $c)) }
    }
    foreach ($topic in $Profile.topics) {
        if ($topic.id -eq 'scope') { continue }
        [void]$o.Add(''); [void]$o.Add('## ' + $topic.title)
        foreach ($component in $Components) {
            [void]$o.Add(''); [void]$o.Add('### ' + (ConvertTo-PsCloneCell $component)); [void]$o.Add('')
            $pages = @($Packets | Where-Object { $_.component -ceq $component -and $_.topic -ceq $topic.id })
            if ($pages.Count -eq 0) { [void]$o.Add('待補：尚無已驗收資料。'); continue }
            $pageNo = 0
            foreach ($packet in $pages) {
                $pageNo++
                [void]$o.Add((ConvertTo-PsCloneCell $packet.summary) + '（' + $packet.coverage + '）'); [void]$o.Add('')
                foreach ($item in $packet.items) {
                    [void]$o.Add('#### ' + (ConvertTo-PsCloneCell $item.id)); [void]$o.Add('')
                    foreach ($field in $topic.fields) { $value = Get-PsCloneProp $item.values $field.key; [void]$o.Add('- ' + $field.label + '：' + (ConvertTo-PsCloneCell $value)) }
                    [void]$o.Add('- 範圍參照：' + (($item.scopeRefs | ForEach-Object { ConvertTo-PsCloneCell $_ }) -join '、'))
                    [void]$o.Add('- 證據索引：' + $component + '/' + $topic.id + '/p' + $pageNo + '/' + ($item.evidenceIds -join '、')); [void]$o.Add('')
                }
            }
        }
    }
    [void]$o.Add('## 未解缺口與交付限制'); [void]$o.Add('')
    Add-PsCloneGapLines -Lines $o -Components $Components -Packets $Packets -Profile $Profile -Gaps $Gaps
    [void]$o.Add(''); [void]$o.Add('未列缺口不等於已執行端到端測試；仍須內部人員核對範圍、來源與驗收結果。')
    return (($o -join "`n") + "`n")
}
function ConvertTo-PsCloneTrace {
    param([string[]]$Components, $Packets, $Profile, [string]$Status, $Gaps = @())
    $o = New-Object 'System.Collections.Generic.List[string]'
    [void]$o.Add('# 核心重建規格追溯表'); [void]$o.Add(''); [void]$o.Add('狀態：' + (ConvertTo-PsCloneCell $Status))
    [void]$o.Add(''); [void]$o.Add('結構驗證與獨立 LLM 覆核不是企業 E2E。以下是來源定位，不證明引用內容已在真實環境重新執行。')
    foreach ($component in $Components) {
        foreach ($topic in $Profile.topics) {
            $pages = @($Packets | Where-Object { $_.component -ceq $component -and $_.topic -ceq $topic.id }); $pageNo = 0
            foreach ($packet in $pages) {
                $pageNo++; $prefix = $component + '/' + $topic.id + '/p' + $pageNo
                [void]$o.Add(''); [void]$o.Add('## ' + $prefix); [void]$o.Add(''); [void]$o.Add('覆蓋：' + $packet.coverage)
                [void]$o.Add(''); [void]$o.Add('| 項目 | 範圍參照 | 證據 ID |'); [void]$o.Add('|---|---|---|')
                foreach ($item in $packet.items) { [void]$o.Add('| ' + (ConvertTo-PsCloneCell $item.id) + ' | ' + (ConvertTo-PsCloneCell ($item.scopeRefs -join '、')) + ' | ' + (ConvertTo-PsCloneCell ($item.evidenceIds -join '、')) + ' |') }
                foreach ($ev in $packet.evidence) { [void]$o.Add(''); [void]$o.Add('### ' + $prefix + '/' + $ev.id); [void]$o.Add(''); [void]$o.Add('- 類型：' + $ev.kind); [void]$o.Add('- 定位：' + (ConvertTo-PsCloneCell $ev.locator)); [void]$o.Add('- 引文：' + (ConvertTo-PsCloneCell $ev.excerpt)) }
            }
        }
    }
    [void]$o.Add(''); [void]$o.Add('## 未解缺口'); [void]$o.Add('')
    Add-PsCloneGapLines -Lines $o -Components $Components -Packets $Packets -Profile $Profile -Gaps $Gaps
    return (($o -join "`n") + "`n")
}
