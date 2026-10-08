# ps-sdoc-status-lib.ps1 — 第 0 階段：STATUS 檔的三份狀態圖解讀（設計 §8.2、§8.3）。
# 外環不解讀 Mermaid：只認得 Mermaid 區塊的範圍與每一行的行號。
#   1. 檢查每份解讀：Mermaid 區塊內每一個非空行恰好交代一次、引用的行在圖內、轉移起訖與子業務的實體存在。
#   2. 以引用的行對齊三份的實體（Jaccard ≥ 0.5；代號取多數讀者用的那個）。
#   3. 拆成事實（STATE、FINAL、REGION、TRN、LABEL、SCENARIO、TEXT、CONFLICT）比對：三份都有的直接採用；
#      其餘第 2 輪逐項問三位讀者（YES／NO／UNSURE），過半採用或否定，仍無多數交人。名稱與 via 取多數讀者的寫法。
#   4. 採用的事實＝04 的分母（Get-PsSdBuiltModel）；04 外殼的 statusReading 由 Get-PsSdStatusReadingSummary 產生。
# 讀者的解讀以 ConvertTo-PsSdNode 轉成 Hashtable 後傳入。依賴 ps-sdoc-schema-lib.ps1。

$script:PsSdStatusLibVersion = '1'

function ConvertTo-PsSdLines {
    # 行號從 1 起算；CRLF／CR 一律視為換行，行號與 LF 版相同。
    param([string]$Text)
    if ($null -eq $Text) { $Text = '' }
    if ($Text.Length -gt 0 -and [int][char]$Text[0] -eq 0xFEFF) { $Text = $Text.Substring(1) }
    $t = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    return , $t.Split([char]10)
}

function Get-PsSdStatusFingerprint {
    # STATUS 檔的指紋：去 BOM、CR 後的 UTF-8 SHA-256（小寫）。
    param([string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $t = $Text.Replace("`r", '')
    if ($t.Length -gt 0 -and [int][char]$t[0] -eq 0xFEFF) { $t = $t.Substring(1) }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($t)) } finally { $sha.Dispose() }
    return ([System.BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
}

function Get-PsSdMermaidLines {
    # Mermaid 區塊內（不含 ``` 那兩行）每一個非空行：SortedDictionary[行號 → 去頭尾空白的文字]。
    param([string]$Text)
    $out = [System.Collections.Generic.SortedDictionary[int, string]]::new()
    $inside = $false
    $lines = ConvertTo-PsSdLines $Text
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $t = $lines[$i].Trim()
        if (-not $inside -and $t.StartsWith('```mermaid')) { $inside = $true; continue }
        if ($inside -and $t.StartsWith('```')) { $inside = $false; continue }
        if ($inside -and $t.Length -gt 0) { $out[$i + 1] = $t }
    }
    return , $out
}

function Get-PsSdProseLines {
    # STATUS 檔圖外的每一行說明：程式碼區塊、標題、空行、表格表頭與分隔線、水平線除外。去掉引言符號與清單符號。
    param([string]$Text)
    $lines = ConvertTo-PsSdLines $Text
    $skip = [System.Collections.Generic.HashSet[int]]::new()
    $start = 0
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $t = $lines[$i].Trim()
        if ($start -eq 0 -and $t.StartsWith('```')) { $start = $i + 1; continue }
        if ($start -ne 0 -and $t.StartsWith('```')) { for ($k = $start; $k -le $i + 1; $k++) { [void]$skip.Add($k) }; $start = 0 }
    }
    if ($start -ne 0) { for ($k = $start; $k -le $lines.Length; $k++) { [void]$skip.Add($k) } }
    $sep = '^\|?\s*:?-{3,}'
    $out = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $ln = $i + 1
        if ($skip.Contains($ln)) { continue }
        $t = $lines[$i].Trim()
        if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
        if ([regex]::IsMatch($t, $sep) -or [regex]::IsMatch($t, '^(-{3,}|\*{3,}|_{3,})$')) { continue }
        if ($t.StartsWith('|') -and $i + 1 -lt $lines.Length -and [regex]::IsMatch($lines[$i + 1].Trim(), $sep)) { continue }
        $clean = [regex]::Replace($t, '^>\s*', '')
        $clean = [regex]::Replace($clean, '^([-*+]|[0-9]+[.)])\s+', '')
        $out.Add(@{ Line = $ln; Kind = 'prose'; Text = $clean; EntityKey = $null; Code = $null })
    }
    return , $out.ToArray()
}

# ---------------- 每份解讀的檢查 ----------------
function Test-PsSdReading {
    # 回傳 @{ Code; Message } 陣列：BAD_CODE、DUPLICATE、BAD_REF、NO_LINES、CITE_OUTSIDE、LINE_TWICE、LINE_UNACCOUNTED。
    param([string]$Text, $Reading)
    $lines = Get-PsSdMermaidLines $Text
    $out = [System.Collections.Generic.List[object]]::new()
    $use = @{}
    $cited = [System.Collections.Generic.HashSet[int]]::new()
    $keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $ents = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($s in @($Reading['states'])) {
        $e = [string]$s['entity']; $c = [string]$s['code']
        if (-not [regex]::IsMatch($c, '^[0-9]{3}$')) { $out.Add(@{ Code = 'BAD_CODE'; Message = ($e + ' 的狀態碼 ' + $c + ' 不是三位數字') }) }
        if (-not $keys.Add($e + [char]0 + $c)) { $out.Add(@{ Code = 'DUPLICATE'; Message = ($e + ' ' + $c + ' 重複') }) }
        [void]$ents.Add($e)
        foreach ($ln in @($s['lines'])) { [void]$cited.Add([int]$ln) }
        foreach ($g in @($s['regions'])) { foreach ($ln in @($g['lines'])) { [void]$cited.Add([int]$ln) } }
    }
    foreach ($s in @($Reading['states'])) {
        foreach ($g in @($s['regions'])) {
            if (-not $ents.Contains([string]$g['entity'])) { $out.Add(@{ Code = 'BAD_REF'; Message = ([string]$s['entity'] + ' ' + [string]$s['code'] + ' 的子業務 ' + [string]$g['entity'] + ' 沒有任何狀態') }) }
        }
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($t in @($Reading['transitions'])) {
        $e = [string]$t['entity']; $a = [string]$t['from']; $b = [string]$t['to']
        $name = '轉移 ' + $e + ' ' + $a + '>' + $b
        if (-not $seen.Add($e + [char]0 + $a + [char]0 + $b)) { $out.Add(@{ Code = 'DUPLICATE'; Message = ($name + ' 重複') }) }
        foreach ($c in @($a, $b)) {
            if ($c -ne '*' -and -not $keys.Contains($e + [char]0 + $c)) { $out.Add(@{ Code = 'BAD_REF'; Message = ($name + ' 的 ' + $c + ' 不是這個實體的狀態') }) }
        }
        if (@($t['lines']).Count -eq 0) { $out.Add(@{ Code = 'NO_LINES'; Message = ($name + ' 沒有引用任何一行') }) }
        foreach ($ln in @($t['lines'])) { [void]$cited.Add([int]$ln) }
    }
    foreach ($o in @($Reading['otherLines'])) {
        foreach ($ln in @($o['lines'])) { $n = [int]$ln; if ($use.ContainsKey($n)) { $use[$n]++ } else { $use[$n] = 1 } }
    }
    $citedSorted = [System.Collections.Generic.List[int]]::new($cited); $citedSorted.Sort()
    foreach ($ln in $citedSorted) {
        if (-not $lines.ContainsKey($ln)) { $out.Add(@{ Code = 'CITE_OUTSIDE'; Message = ('第 ' + $ln + ' 行不在 Mermaid 區塊內，卻被引用') }) }
        if ($use.ContainsKey($ln)) { $out.Add(@{ Code = 'LINE_TWICE'; Message = ('第 ' + $ln + ' 行既被引用，又列在其他行') }) }
    }
    $useSorted = [System.Collections.Generic.List[int]]::new(); foreach ($k in $use.Keys) { $useSorted.Add([int]$k) }; $useSorted.Sort()
    foreach ($ln in $useSorted) {
        if (-not $lines.ContainsKey($ln)) { $out.Add(@{ Code = 'CITE_OUTSIDE'; Message = ('第 ' + $ln + ' 行不在 Mermaid 區塊內，卻列在其他行') }) }
        if ($use[$ln] -gt 1) { $out.Add(@{ Code = 'LINE_TWICE'; Message = ('第 ' + $ln + ' 行在其他行列了 ' + $use[$ln] + ' 次') }) }
    }
    foreach ($ln in $lines.Keys) {
        if (-not $cited.Contains($ln) -and -not $use.ContainsKey($ln)) { $out.Add(@{ Code = 'LINE_UNACCOUNTED'; Message = ('第 ' + $ln + ' 行沒有交代：' + $lines[$ln]) }) }
    }
    return , $out.ToArray()
}

# ---------------- 對齊、事實、比對 ----------------
function Get-PsSdEntityLines {
    # 實體 → 引用的行（HashSet[int]）。
    param($Reading)
    $out = New-PsSdMap
    foreach ($s in @($Reading['states'])) {
        $e = [string]$s['entity']
        if (-not $out.ContainsKey($e)) { $out[$e] = [System.Collections.Generic.HashSet[int]]::new() }
        foreach ($ln in @($s['lines'])) { [void]$out[$e].Add([int]$ln) }
    }
    foreach ($t in @($Reading['transitions'])) {
        $e = [string]$t['entity']
        if (-not $out.ContainsKey($e)) { $out[$e] = [System.Collections.Generic.HashSet[int]]::new() }
        foreach ($ln in @($t['lines'])) { [void]$out[$e].Add([int]$ln) }
    }
    return $out
}

function Get-PsSdSortedKeys {
    param($Map)
    $keys = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $Map.Keys) { $keys.Add([string]$k) }
    $keys.Sort([System.StringComparer]::Ordinal)
    return , $keys.ToArray()
}

function Get-PsSdAlignment {
    # 回傳每份解讀的對照表（讀者用的代號 → 共同代號）。共同代號取多數讀者用的那個（同票取字元碼最小）。
    param([object[]]$Readings)
    $lineSets = @()
    foreach ($r in $Readings) { $lineSets += , (Get-PsSdEntityLines $r) }
    $clusters = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $Readings.Length; $i++) {
        $mine = $lineSets[$i]
        foreach ($key in (Get-PsSdSortedKeys $mine)) {
            $ls = $mine[$key]
            $best = $null; $score = 0.0
            foreach ($c in $clusters) {
                if ($c.Members.ContainsKey($i)) { continue }
                $other = $lineSets[$c.FirstReader][$c.FirstKey]
                $inter = 0
                foreach ($x in $ls) { if ($other.Contains($x)) { $inter++ } }
                $union = $ls.Count + $other.Count - $inter
                $jac = 0.0
                if ($union -gt 0) { $jac = [double]$inter / [double]$union }
                if ($jac -gt $score) { $best = $c; $score = $jac }
            }
            if ($null -ne $best -and $score -ge 0.5) { $best.Members[$i] = $key }
            else {
                $m = @{}; $m[$i] = $key
                $clusters.Add(@{ Members = $m; FirstReader = $i; FirstKey = $key })
            }
        }
    }
    $maps = @()
    for ($i = 0; $i -lt $Readings.Length; $i++) { $maps += , (New-PsSdMap) }
    foreach ($c in $clusters) {
        $votes = New-PsSdMap
        foreach ($k in $c.Members.Values) { if ($votes.ContainsKey($k)) { $votes[$k]++ } else { $votes[$k] = 1 } }
        $top = 0
        foreach ($n in $votes.Values) { if ($n -gt $top) { $top = $n } }
        $canon = $null
        foreach ($k in (Get-PsSdSortedKeys $votes)) { if ($votes[$k] -eq $top) { $canon = $k; break } }
        foreach ($i in $c.Members.Keys) { $maps[$i][$c.Members[$i]] = $canon }
    }
    return , $maps
}

function ConvertTo-PsSdFactPart {
    # 與原型相同的排序字串：整數照十進位、null 寫 None、行號 tuple 寫 (a, b)。
    param($V)
    if ($null -eq $V) { return 'None' }
    if ($V -is [object[]]) {
        $parts = @(); foreach ($x in $V) { $parts += [string]$x }
        if ($parts.Count -eq 1) { return ('(' + $parts[0] + ',)') }
        return ('(' + ($parts -join ', ') + ')')
    }
    return [string]$V
}

function New-PsSdFact {
    param([object[]]$Parts)
    $strs = @(); foreach ($p in $Parts) { $strs += (ConvertTo-PsSdFactPart $p) }
    return @{ Kind = [string]$Parts[0]; Parts = $Parts; Key = ($strs -join [string][char]0) }
}

function Get-PsSdReadingFacts {
    # 拆成可比的事實與各事實引用的行；名稱、via 另外回傳（取多數讀者的寫法，不單獨表決）。
    param($Reading, $KeyMap)
    $facts = New-PsSdMap; $cite = New-PsSdMap; $names = New-PsSdMap; $via = New-PsSdMap
    $add = {
        param($Fact, $Lines)
        if (-not $facts.ContainsKey($Fact.Key)) { $facts[$Fact.Key] = $Fact; $cite[$Fact.Key] = [System.Collections.Generic.HashSet[int]]::new() }
        foreach ($ln in @($Lines)) { if ($null -ne $ln) { [void]$cite[$Fact.Key].Add([int]$ln) } }
    }
    foreach ($s in @($Reading['states'])) {
        $e = $KeyMap[[string]$s['entity']]; $c = [string]$s['code']
        & $add (New-PsSdFact @('STATE', $e, $c)) $s['lines']
        $names[$e + [char]0 + $c] = [string]$s['name']
        if ($s['final'] -eq $true) { & $add (New-PsSdFact @('FINAL', $e, $c)) $s['lines'] }
        foreach ($g in @($s['regions'])) { & $add (New-PsSdFact @('REGION', $e, $c, $KeyMap[[string]$g['entity']])) $g['lines'] }
    }
    foreach ($t in @($Reading['transitions'])) {
        $e = $KeyMap[[string]$t['entity']]; $a = [string]$t['from']; $b = [string]$t['to']
        & $add (New-PsSdFact @('TRN', $e, $a, $b)) $t['lines']
        $vv = @(); foreach ($x in @($t['via'])) { if ($null -ne $x) { $vv += [string]$x } }
        $via[$e + [char]0 + $a + [char]0 + $b] = $vv
        foreach ($lab in @($t['labels'])) { if ($null -ne $lab) { & $add (New-PsSdFact @('LABEL', $e, $a, $b, [string]$lab)) $t['lines'] } }
        if ($null -ne $t['scenario'] -and [string]$t['scenario'] -ne '') { & $add (New-PsSdFact @('SCENARIO', $e, $a, $b, [string]$t['scenario'])) $t['lines'] }
    }
    foreach ($o in @($Reading['otherLines'])) {
        if ([string]$o['disposition'] -ne 'TEXT') { continue }
        $e = $null
        if ($o.ContainsKey('entity')) { $e = [string]$o['entity']; if ($KeyMap.ContainsKey($e)) { $e = $KeyMap[$e] } }
        $c = $null
        if ($o.ContainsKey('code')) { $c = [string]$o['code'] }
        foreach ($ln in @($o['lines'])) { & $add (New-PsSdFact @('TEXT', [int]$ln, $e, $c)) @([int]$ln) }
    }
    foreach ($cf in @($Reading['conflicts'])) {
        if ($null -eq $cf) { continue }
        $ls = [System.Collections.Generic.List[int]]::new(); foreach ($x in @($cf['lines'])) { $ls.Add([int]$x) }; $ls.Sort()
        $arr = New-Object object[] $ls.Count
        for ($k = 0; $k -lt $ls.Count; $k++) { $arr[$k] = $ls[$k] }
        & $add (New-PsSdFact @('CONFLICT', $arr)) $cf['lines']
    }
    return @{ Facts = $facts; Cite = $cite; Names = $names; Via = $via }
}

function Get-PsSdFactText {
    param($Fact)
    $p = $Fact.Parts
    $tr = {
        param($a, $b)
        $x = $a; if ($a -eq '*') { $x = '新建' }
        return ($x + '→' + $b)
    }
    switch ($Fact.Kind) {
        'STATE' { return ('狀態 ' + $p[1] + ' ' + $p[2]) }
        'FINAL' { return ($p[1] + ' 的 ' + $p[2] + ' 是終點') }
        'REGION' { return ($p[1] + ' 的 ' + $p[2] + ' 裡進行子業務 ' + $p[3]) }
        'TRN' { return ('轉移 ' + $p[1] + ' ' + (& $tr $p[2] $p[3])) }
        'LABEL' { return ($p[1] + ' ' + (& $tr $p[2] $p[3]) + ' 的線上文字「' + $p[4] + '」') }
        'SCENARIO' { return ($p[1] + ' ' + (& $tr $p[2] $p[3]) + ' 屬於情境「' + $p[4] + '」') }
        'TEXT' {
            if ($null -ne $p[2] -and $null -ne $p[3]) { return ('第 ' + $p[1] + ' 行是 ' + $p[2] + ' ' + $p[3] + ' 的業務文字') }
            if ($null -ne $p[2]) { return ('第 ' + $p[1] + ' 行是 ' + $p[2] + ' 的業務文字') }
            return ('第 ' + $p[1] + ' 行是業務文字')
        }
    }
    $ls = @(); foreach ($x in $p[1]) { $ls += [string]$x }
    return ('第 ' + ($ls -join '、') + ' 行互相矛盾')
}

function Get-PsSdMajority {
    # 各讀者的對照表合併：同一鍵取多數讀者的寫法（同票取讀者順序在前的）。值是字串或字串陣列。
    param([object[]]$Maps)
    $vals = New-PsSdMap
    $order = [System.Collections.Generic.List[string]]::new()
    foreach ($m in $Maps) {
        foreach ($k in (Get-PsSdSortedKeys $m)) {
            if (-not $vals.ContainsKey($k)) { $vals[$k] = [System.Collections.Generic.List[object]]::new(); $order.Add($k) }
            $vals[$k].Add($m[$k])
        }
    }
    $out = New-PsSdMap
    foreach ($k in $order) {
        $vs = $vals[$k]
        $counts = New-PsSdMap
        foreach ($v in $vs) { $ck = ConvertTo-PsSdCanonical $v; if ($counts.ContainsKey($ck)) { $counts[$ck]++ } else { $counts[$ck] = 1 } }
        $top = 0; foreach ($n in $counts.Values) { if ($n -gt $top) { $top = $n } }
        foreach ($v in $vs) { if ($counts[(ConvertTo-PsSdCanonical $v)] -eq $top) { $out[$k] = $v; break } }
    }
    return $out
}

function Compare-PsSdReadings {
    # $Readings：三份第 1 輪解讀（Hashtable）。$Round2：$null，或 Hashtable「讀者序|事實鍵」→ YES／NO／UNSURE。
    param([string]$Text, [object[]]$Readings, $Round2)
    $n = $Readings.Length
    $maps = Get-PsSdAlignment $Readings
    $per = @()
    for ($i = 0; $i -lt $n; $i++) { $per += , (Get-PsSdReadingFacts $Readings[$i] $maps[$i]) }
    $all = New-PsSdMap; $cite = New-PsSdMap
    foreach ($p in $per) {
        foreach ($k in $p.Facts.Keys) {
            if (-not $all.ContainsKey($k)) { $all[$k] = $p.Facts[$k]; $cite[$k] = [System.Collections.Generic.HashSet[int]]::new() }
            $cite[$k].UnionWith($p.Cite[$k])
        }
    }
    $accepted = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $contested = [System.Collections.Generic.List[object]]::new()
    $unresolved = [System.Collections.Generic.List[object]]::new()
    foreach ($k in (Get-PsSdSortedKeys $all)) {
        $have = 0
        foreach ($p in $per) { if ($p.Facts.ContainsKey($k)) { $have++ } }
        if ($have -eq $n) { [void]$accepted.Add($k); continue }
        $yes = 0; $no = 0; $unsure = 0
        if ($null -ne $Round2) {
            for ($i = 0; $i -lt $n; $i++) {
                $ak = [string]$i + '|' + $k
                $ans = ''
                if ($Round2.ContainsKey($ak)) { $ans = [string]$Round2[$ak] }
                if ($ans -eq 'YES') { $yes++ } elseif ($ans -eq 'NO') { $no++ } elseif ($ans -eq 'UNSURE') { $unsure++ }
            }
        }
        $result = 'UNRESOLVED'
        if ($yes * 2 -gt $n) { $result = 'ACCEPTED' } elseif ($no * 2 -gt $n) { $result = 'REJECTED' }
        if ($result -eq 'ACCEPTED') { [void]$accepted.Add($k) }
        if ($result -eq 'UNRESOLVED') { $unresolved.Add($all[$k]) }
        $ls = [System.Collections.Generic.List[int]]::new($cite[$k]); $ls.Sort()
        $r2 = [string]$yes + ':' + [string]$no
        if ($unsure -gt 0) { $r2 += ':' + [string]$unsure }
        $contested.Add(@{ Key = $k; Fact = $all[$k]; Lines = $ls.ToArray(); Round1 = ([string]$have + ':' + [string]($n - $have)); Round2 = $r2; Result = $result })
    }
    $nameMaps = @(); $viaMaps = @()
    foreach ($p in $per) { $nameMaps += , $p.Names; $viaMaps += , $p.Via }
    $mermaid = Get-PsSdMermaidLines $Text
    return @{
        Maps = $maps; Facts = $all; Accepted = $accepted; Contested = $contested.ToArray(); Unresolved = $unresolved.ToArray(); Cite = $cite
        Names = (Get-PsSdMajority $nameMaps); Via = (Get-PsSdMajority $viaMaps)
        MermaidLines = $mermaid.Count; FactCount = $all.Count; Unanimous = ($all.Count - $contested.Count); Readers = $n
    }
}

function Get-PsSdRound2Questions {
    # 第 2 輪工單：不一致的事實逐項附引用的行（行號與原文）。題號 F01…。
    param([string]$Text, $Result)
    $lines = ConvertTo-PsSdLines $Text
    $out = [System.Collections.Generic.List[object]]::new()
    $i = 0
    foreach ($c in $Result.Contested) {
        $i++
        $cited = [System.Collections.Generic.List[object]]::new()
        foreach ($ln in $c.Lines) { $tx = ''; if ($ln -ge 1 -and $ln -le $lines.Length) { $tx = $lines[$ln - 1].Trim() }; $cited.Add([ordered]@{ line = $ln; text = $tx }) }
        $out.Add([ordered]@{ id = ('F' + $i.ToString('00', [System.Globalization.CultureInfo]::InvariantCulture)); fact = (Get-PsSdFactText $c.Fact); lines = $cited.ToArray(); factKey = $c.Key })
    }
    return , $out.ToArray()
}

# ---------------- 採用的事實 → 04 的分母 ----------------
function Get-PsSdBuiltModel {
    # 回傳 @{ Entities; Composites; Texts; Names }：
    #   Entities[實體] = @{ Codes; Pairs（'起>迄'，新建寫 *）; Via[pair]; Labels[pair]（依原文首次出現的行排序）; Finals; Initials; Scenarios[情境]=pairs; Main }
    #   Composites['實體|狀態碼'] = @{ Entity; Code; Regions（子業務實體，依圖上順序）; Exits }
    #   Texts：圖外每一行說明＋多數讀者列為業務文字的圖內行，依行號排序（@{ Line; Kind; Text; EntityKey; Code }）
    param([string]$Text, $Result)
    $lines = ConvertTo-PsSdLines $Text
    $acc = [System.Collections.Generic.List[object]]::new()
    foreach ($k in (Get-PsSdSortedKeys $Result.Facts)) { if ($Result.Accepted.Contains($k)) { $acc.Add($Result.Facts[$k]) } }
    $first = New-PsSdMap
    for ($i = 0; $i -lt $lines.Length; $i++) {
        foreach ($f in $acc) {
            if ($f.Kind -eq 'LABEL' -and -not $first.ContainsKey($f.Parts[4]) -and $lines[$i].Contains([string]$f.Parts[4])) { $first[$f.Parts[4]] = $i + 1 }
        }
    }
    $ents = New-PsSdMap
    $getE = {
        param($e)
        if (-not $ents.ContainsKey($e)) {
            $ents[$e] = @{
                Codes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                Pairs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                Via = (New-PsSdMap); Labels = (New-PsSdMap)
                Finals = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                Initials = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                Scenarios = (New-PsSdMap); Main = $true
            }
        }
        return $ents[$e]
    }
    $subs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $regions = New-PsSdMap
    foreach ($f in $acc) {
        $p = $f.Parts
        switch ($f.Kind) {
            'STATE' { [void](& $getE $p[1]).Codes.Add($p[2]) }
            'FINAL' { [void](& $getE $p[1]).Finals.Add($p[2]) }
            'TRN' {
                $ent = & $getE $p[1]
                $pair = $p[2] + '>' + $p[3]
                [void]$ent.Pairs.Add($pair)
                if ($p[2] -eq '*') { [void]$ent.Initials.Add($p[3]) }
                $vk = $p[1] + [char]0 + $p[2] + [char]0 + $p[3]
                if ($Result.Via.ContainsKey($vk) -and @($Result.Via[$vk]).Count -gt 0) { $ent.Via[$pair] = @($Result.Via[$vk]) }
            }
            'REGION' {
                [void]$subs.Add($p[3])
                $rk = $p[1] + '|' + $p[2]
                if (-not $regions.ContainsKey($rk)) { $regions[$rk] = [System.Collections.Generic.List[object]]::new() }
                $min = [int]::MaxValue; foreach ($x in $Result.Cite[$f.Key]) { if ($x -lt $min) { $min = $x } }
                $regions[$rk].Add(@{ Line = $min; Entity = $p[3] })
            }
        }
    }
    foreach ($f in $acc) {
        $p = $f.Parts
        if ($f.Kind -eq 'LABEL') {
            $ent = & $getE $p[1]; $pair = $p[2] + '>' + $p[3]
            if (-not $ent.Labels.ContainsKey($pair)) { $ent.Labels[$pair] = [System.Collections.Generic.List[string]]::new() }
            $ent.Labels[$pair].Add($p[4])
        }
        if ($f.Kind -eq 'SCENARIO') {
            $ent = & $getE $p[1]; $pair = $p[2] + '>' + $p[3]
            if (-not $ent.Scenarios.ContainsKey($p[4])) { $ent.Scenarios[$p[4]] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal) }
            [void]$ent.Scenarios[$p[4]].Add($pair)
        }
    }
    foreach ($e in @($ents.Keys)) {
        $ent = $ents[$e]
        $ent.Main = -not $subs.Contains($e)
        foreach ($pair in @($ent.Labels.Keys)) {
            $keyed = [System.Collections.Generic.List[string]]::new()
            foreach ($t in $ent.Labels[$pair]) { $fl = 0; if ($first.ContainsKey($t)) { $fl = $first[$t] }; $keyed.Add($fl.ToString('D8', [System.Globalization.CultureInfo]::InvariantCulture) + [char]0 + $t) }
            $keyed.Sort([System.StringComparer]::Ordinal)
            $labs = @(); foreach ($x in $keyed) { $labs += $x.Substring(9) }
            $ent.Labels[$pair] = $labs
        }
    }
    $comps = [ordered]@{}
    foreach ($rk in (Get-PsSdSortedKeys $regions)) {
        $parts = $rk.Split('|')
        $e = $parts[0]; $code = $parts[1]
        $keyed = [System.Collections.Generic.List[string]]::new()
        foreach ($g in $regions[$rk]) { $keyed.Add(([int]$g.Line).ToString('D8', [System.Globalization.CultureInfo]::InvariantCulture) + [char]0 + $g.Entity) }
        $keyed.Sort([System.StringComparer]::Ordinal)
        $regEnts = @(); foreach ($x in $keyed) { $regEnts += $x.Substring(9) }
        $exits = [System.Collections.Generic.List[string]]::new()
        if ($ents.ContainsKey($e)) { foreach ($pair in $ents[$e].Pairs) { $ab = $pair.Split('>'); if ($ab[0] -eq $code) { $exits.Add($ab[1]) } } }
        $exits.Sort([System.StringComparer]::Ordinal)
        $comps[$rk] = @{ Entity = $e; Code = $code; Regions = $regEnts; Exits = $exits.ToArray() }
    }
    $texts = [System.Collections.Generic.List[object]]::new()
    foreach ($t in (Get-PsSdProseLines $Text)) { $texts.Add($t) }
    foreach ($f in $acc) {
        if ($f.Kind -ne 'TEXT') { continue }
        $ln = [int]$f.Parts[1]
        $tx = ''; if ($ln -ge 1 -and $ln -le $lines.Length) { $tx = $lines[$ln - 1].Trim() }
        $texts.Add(@{ Line = $ln; Kind = 'text'; Text = $tx; EntityKey = $f.Parts[2]; Code = $f.Parts[3] })
    }
    $textsSorted = @($texts | Sort-Object -Property @{ Expression = { $_.Line } })
    return @{ Entities = $ents; Composites = $comps; Texts = $textsSorted; Names = $Result.Names }
}

function Get-PsSdStatusReadingSummary {
    # 04 外殼的 statusReading（schema 欄位順序）。
    param($Result, [string]$StatusRef, [string]$Fingerprint)
    $contested = [System.Collections.Generic.List[object]]::new()
    foreach ($c in $Result.Contested) {
        $locs = @(); foreach ($ln in $c.Lines) { $locs += ($StatusRef + '#L' + $ln) }
        $contested.Add([ordered]@{ fact = (Get-PsSdFactText $c.Fact); lines = $locs; round1 = $c.Round1; round2 = $c.Round2; result = $c.Result })
    }
    $rounds = 1
    if ($Result.Contested.Length -gt 0) { $rounds = 2 }
    return [ordered]@{
        readers = $Result.Readers; rounds = $rounds; mermaidLines = $Result.MermaidLines; facts = $Result.FactCount
        unanimous = $Result.Unanimous; contested = $contested.ToArray(); unresolved = $Result.Unresolved.Length; fingerprint = $Fingerprint
    }
}

function Get-PsSdConflictFacts {
    # 多數讀者列出的圖與圖矛盾（採用的 CONFLICT 事實）：每項開 STATUS_SELF_CONFLICT。
    param($Result)
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($k in (Get-PsSdSortedKeys $Result.Facts)) {
        $f = $Result.Facts[$k]
        if ($f.Kind -eq 'CONFLICT' -and $Result.Accepted.Contains($k)) { $out.Add($f) }
    }
    return , $out.ToArray()
}
