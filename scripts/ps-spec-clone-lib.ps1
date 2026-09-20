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
function Get-PsCloneProfile {
    param([string]$Root)
    $path = Join-Path $Root '.opencode/peoplesoft/spec/clone-profile.json'
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
    foreach ($ev in $evs) {
        $e = Test-PsCloneShape $ev @('id','kind','locator','excerpt') 'evidence'; $r.Errors += $e
        if (-not (Test-PsCloneObject $ev)) { continue }
        if ($ev.id -isnot [string] -or $ev.id -cnotmatch '^E[1-9][0-9]*$' -or -not $eids.Add([string]$ev.id)) { $r.Errors += 'EVIDENCE_ID_INVALID_OR_DUPLICATE' }
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
            $scopeMap[$id] = $item
        }
        else {
            if (@($refs).Count -eq 0) { $r.Errors += ('SCOPE_REFS_REQUIRED:' + $id) }
            foreach ($sid in @($refs)) {
                if ($sid -isnot [string] -or -not $scopeMap.ContainsKey([string]$sid)) { $r.Errors += ('SCOPE_REF_UNKNOWN:' + $id); continue }
                if (@('CORE','DEPENDENCY') -cnotcontains [string]$scopeMap[[string]$sid].values.inclusion) { $r.Errors += ('SCOPE_REF_EXCLUDED:' + $id) }
            }
            if ($Topic -eq 'acceptance' -and @('POSITIVE','NEGATIVE','BOUNDARY') -cnotcontains [string]$item.values.scenarioType) { $r.Errors += ('SCENARIO_TYPE_INVALID:' + $id) }
        }
    }
    if ($Topic -eq 'scope') {
        $rootFound = $false
        foreach ($s in $scopeMap.Values) { if ([string]$s.values.inclusion -ceq 'CORE' -and [string]$s.values.type -ceq 'COMPONENT' -and [string]$s.values.object -ceq $Component) { $rootFound = $true } }
        if (-not $rootFound) { $r.Errors += 'CORE_COMPONENT_REQUIRED' }
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
    [void]$o.Add('| Component | 範圍 ID | 物件 | 型別 | 分類 | 使用關係／條件 | 理由 |')
    [void]$o.Add('|---|---|---|---|---|---|---|')
    foreach ($component in $Components) {
        foreach ($packet in @($Packets | Where-Object { $_.component -ceq $component -and $_.topic -ceq 'scope' })) {
            foreach ($item in $packet.items) { $v = $item.values; [void]$o.Add('| ' + ((@($component,$item.id,$v.object,$v.type,$v.inclusion,($v.usedBy + '；' + $v.condition),$v.reason) | ForEach-Object { ConvertTo-PsCloneCell $_ }) -join ' | ') + ' |') }
        }
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
