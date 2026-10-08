# ps-sdoc-schema-lib.ps1 — JSON Schema（2020-12 子集）驗證器：Spec 文件流程的 canonical 文件、研究包、狀態圖解讀都用它驗。
# 支援：type、enum、const、properties、required、additionalProperties、unevaluatedProperties、items、minItems、maxItems、
#       uniqueItems、contains、pattern、minLength、maxLength、minimum、maximum、minProperties、allOf、anyOf、oneOf、not、
#       if／then／else、$ref（同檔 #/... 與跨檔 urn:...#/...）、$defs。其他關鍵字忽略。
# 值：ConvertFrom-Json 的結果（PSCustomObject／object[]）或 IDictionary／IList；驗證前先轉成區分大小寫的 Hashtable 與 object[]。
# pattern 用 .NET regex；結尾的 $ 視為字串結尾（\z），結尾多一個換行也算不符。
# 用法：$reg = Read-PsSdSchemaDir <目錄>；$errs = Test-PsSdSchema $reg 'urn:ps-spec:schema:04-workflow' $doc
#       回傳錯誤字串陣列（空＝通過）；呼叫端先指派再 @($errs)。
# PS 5.1 相容：不用三元運算子、??、類別、-AsHashtable。

$script:PsSdSchemaLibVersion = '1'

function New-PsSdMap {
    # 區分大小寫的 Hashtable（JSON 的鍵區分大小寫）。
    return [hashtable]::new([System.StringComparer]::Ordinal)
}

function ConvertFrom-PsSdJson {
    # 與 repo 其他腳本相同用 ConvertFrom-Json（PS 5.1 字串保留原樣；PS 7 只有完整 ISO 時間戳會變 DateTime，canonical 文件只用日期）。
    param([string]$Text)
    if ($Text.Length -gt 0 -and [int][char]$Text[0] -eq 0xFEFF) { $Text = $Text.Substring(1) }
    return (ConvertFrom-Json -InputObject $Text)
}

function Read-PsSdJsonFile {
    param([string]$Path)
    return (ConvertFrom-PsSdJson ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)))
}

function Test-PsSdIsNumber {
    param($V)
    if ($null -eq $V -or $V -is [bool] -or $V -is [string]) { return $false }
    return ($V -is [int] -or $V -is [long] -or $V -is [double] -or $V -is [decimal] -or $V -is [single] -or $V -is [int16] -or $V -is [byte])
}

function Test-PsSdIsInteger {
    param($V)
    if (-not (Test-PsSdIsNumber $V)) { return $false }
    if ($V -is [int] -or $V -is [long] -or $V -is [int16] -or $V -is [byte]) { return $true }
    return ([double]$V -eq [math]::Floor([double]$V))
}

function ConvertTo-PsSdNode {
    # 轉成驗證用的形狀：物件→區分大小寫的 Hashtable，陣列→object[]；以 return , 值 回傳（陣列原樣保留）。
    param($V)
    if ($null -eq $V) { return $null }
    if ($V -is [string] -or $V -is [bool]) { return $V }
    if ($V -is [System.Collections.IDictionary]) {
        $h = New-PsSdMap
        foreach ($k in @($V.Keys)) { $h[[string]$k] = ConvertTo-PsSdNode $V[$k] }
        return $h
    }
    if ($V -is [System.Management.Automation.PSCustomObject]) {
        $h = New-PsSdMap
        foreach ($p in $V.PSObject.Properties) { $h[$p.Name] = ConvertTo-PsSdNode $p.Value }
        return $h
    }
    if ($V -is [System.Collections.IList]) {
        $n = $V.Count
        $arr = New-Object object[] $n
        for ($i = 0; $i -lt $n; $i++) { $arr[$i] = ConvertTo-PsSdNode $V[$i] }
        return , $arr
    }
    return $V
}

function New-PsSdSchemaRegistry {
    param([object[]]$Schemas)
    $map = New-PsSdMap
    foreach ($s in $Schemas) {
        $c = ConvertTo-PsSdNode $s
        if (-not ($c -is [hashtable]) -or -not $c.ContainsKey('$id')) { throw 'SCHEMA_ID_MISSING' }
        $map[[string]$c['$id']] = $c
    }
    return @{ Schemas = $map; RefCache = (New-PsSdMap); Regex = (New-PsSdMap) }
}

function Read-PsSdSchemaDir {
    param([string]$Dir)
    $list = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Filter '*.json' -File | Sort-Object Name)) {
        [void]$list.Add((Read-PsSdJsonFile $f.FullName))
    }
    return (New-PsSdSchemaRegistry $list.ToArray())
}

function ConvertTo-PsSdCanonical {
    # 比較用的正規字串（物件鍵依字元碼排序）。
    param($V)
    if ($null -eq $V) { return 'null' }
    if ($V -is [bool]) { if ($V) { return 'true' }; return 'false' }
    if ($V -is [string]) { return ('"' + $V.Replace('\', '\\').Replace('"', '\"') + '"') }
    if (Test-PsSdIsNumber $V) { return ([double]$V).ToString('R', [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($V -is [System.Collections.IDictionary]) {
        $names = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $V.Keys) { $names.Add([string]$k) }
        $names.Sort([System.StringComparer]::Ordinal)
        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($n in $names) { $parts.Add((ConvertTo-PsSdCanonical $n) + ':' + (ConvertTo-PsSdCanonical $V[$n])) }
        return ('{' + [string]::Join(',', $parts) + '}')
    }
    if ($V -is [System.Management.Automation.PSCustomObject]) { return (ConvertTo-PsSdCanonical (ConvertTo-PsSdNode $V)) }
    if ($V -is [System.Collections.IList]) {
        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($x in $V) { $parts.Add((ConvertTo-PsSdCanonical $x)) }
        return ('[' + [string]::Join(',', $parts) + ']')
    }
    return ('"' + [string]$V + '"')
}

function Get-PsSdTypeName {
    param($V)
    if ($null -eq $V) { return 'null' }
    if ($V -is [bool]) { return 'boolean' }
    if ($V -is [string]) { return 'string' }
    if (Test-PsSdIsInteger $V) { return 'integer' }
    if (Test-PsSdIsNumber $V) { return 'number' }
    if ($V -is [hashtable]) { return 'object' }
    if ($V -is [object[]]) { return 'array' }
    return 'unknown'
}

function Test-PsSdType {
    param($V, [string]$T)
    switch ($T) {
        'string' { return ($V -is [string]) }
        'object' { return ($V -is [hashtable]) }
        'array' { return ($V -is [object[]]) }
        'integer' { return (Test-PsSdIsInteger $V) }
        'number' { return (Test-PsSdIsNumber $V) }
        'boolean' { return ($V -is [bool]) }
        'null' { return ($null -eq $V) }
    }
    return $false
}

function Resolve-PsSdRef {
    param($Reg, [string]$BaseId, [string]$Ref)
    $ck = $BaseId + '|' + $Ref
    if ($Reg.RefCache.ContainsKey($ck)) { return $Reg.RefCache[$ck] }
    $doc = $BaseId; $frag = ''
    $hash = $Ref.IndexOf('#')
    if ($hash -lt 0) { $doc = $Ref }
    elseif ($hash -eq 0) { $frag = $Ref.Substring(1) }
    else { $doc = $Ref.Substring(0, $hash); $frag = $Ref.Substring($hash + 1) }
    if (-not $Reg.Schemas.ContainsKey($doc)) { throw ('SCHEMA_REF_UNKNOWN:' + $Ref) }
    $node = $Reg.Schemas[$doc]
    if ($frag) {
        foreach ($raw in $frag.TrimStart('/').Split('/')) {
            $tok = $raw.Replace('~1', '/').Replace('~0', '~')
            if (-not ($node -is [hashtable]) -or -not $node.ContainsKey($tok)) { throw ('SCHEMA_REF_UNKNOWN:' + $Ref) }
            $node = $node[$tok]
        }
    }
    $r = @{ Schema = $node; BaseId = $doc }
    $Reg.RefCache[$ck] = $r
    return $r
}

function Get-PsSdRegex {
    param($Reg, [string]$Pattern)
    if ($Reg.Regex.ContainsKey($Pattern)) { return $Reg.Regex[$Pattern] }
    $p = $Pattern
    if ($p.EndsWith('$') -and -not $p.EndsWith('\$')) { $p = $p.Substring(0, $p.Length - 1) + '\z' }
    $rx = [regex]::new($p)
    $Reg.Regex[$Pattern] = $rx
    return $rx
}

function Test-PsSdSchema {
    # 回傳錯誤字串陣列（空＝通過）。$Root 是 schema 的 $id（或 $id#/$defs/X）。
    param($Registry, [string]$Root, $Value)
    $r = Resolve-PsSdRef $Registry '' $Root
    $node = ConvertTo-PsSdNode $Value
    $res = Invoke-PsSdValidate $Registry $r.Schema $node '' $r.BaseId
    return , $res.Errors.ToArray()
}

function Format-PsSdShort {
    param([string]$S)
    if ($S.Length -gt 60) { return ($S.Substring(0, 57) + '…') }
    return $S
}

function Invoke-PsSdValidate {
    param($Reg, $S, $V, [string]$Path, [string]$Base)
    $errs = [System.Collections.Generic.List[string]]::new()
    $isObj = $V -is [hashtable]
    $ev = $null
    if ($isObj) { $ev = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal) }
    $res = @{ Errors = $errs; Evaluated = $ev }
    if ($S -is [bool]) {
        if (-not $S) { $w = $Path; if (-not $w) { $w = '（根）' }; $errs.Add($w + '：不允許出現') }
        return $res
    }
    if (-not ($S -is [hashtable])) { return $res }
    $where = $Path
    if (-not $where) { $where = '（根）' }

    if ($S.ContainsKey('$ref')) {
        $t = Resolve-PsSdRef $Reg $Base ([string]$S['$ref'])
        $sub = Invoke-PsSdValidate $Reg $t.Schema $V $Path $t.BaseId
        if ($sub.Errors.Count -gt 0) { $errs.AddRange($sub.Errors) } elseif ($isObj) { $ev.UnionWith($sub.Evaluated) }
    }
    if ($S.ContainsKey('type')) {
        $tv = $S['type']
        $ok = $false
        if ($tv -is [string]) { $ok = Test-PsSdType $V $tv }
        else { foreach ($t1 in $tv) { if (Test-PsSdType $V ([string]$t1)) { $ok = $true; break } } }
        if (-not $ok) {
            $tn = $tv
            if (-not ($tv -is [string])) { $tn = [string]::Join('／', [string[]]@($tv)) }
            $errs.Add($where + '：型別應為 ' + $tn + '，實際是 ' + (Get-PsSdTypeName $V))
            return $res
        }
    }
    if ($S.ContainsKey('const')) {
        $c = $S['const']
        $same = $false
        if ($c -is [string] -and $V -is [string]) { $same = ($c -ceq $V) }
        else { $same = ((ConvertTo-PsSdCanonical $c) -ceq (ConvertTo-PsSdCanonical $V)) }
        if (-not $same) { $errs.Add($where + '：必須是 ' + (ConvertTo-PsSdCanonical $c)) }
    }
    if ($S.ContainsKey('enum')) {
        $hit = $false
        $cv = $null
        foreach ($x in $S['enum']) {
            if ($x -is [string] -and $V -is [string]) { if ($x -ceq $V) { $hit = $true; break } }
            else {
                if ($null -eq $cv) { $cv = ConvertTo-PsSdCanonical $V }
                if ((ConvertTo-PsSdCanonical $x) -ceq $cv) { $hit = $true; break }
            }
        }
        if (-not $hit) {
            $shown = [System.Collections.Generic.List[string]]::new()
            foreach ($x in $S['enum']) { $shown.Add([string]$x) }
            $errs.Add($where + '：' + (Format-PsSdShort (ConvertTo-PsSdCanonical $V)) + ' 不在值域（' + [string]::Join('／', $shown) + '）')
        }
    }
    if ($V -is [string]) {
        if ($S.ContainsKey('pattern')) {
            $rx = Get-PsSdRegex $Reg ([string]$S['pattern'])
            if (-not $rx.IsMatch($V)) { $errs.Add($where + '：格式不符（' + [string]$S['pattern'] + '）：' + (Format-PsSdShort $V)) }
        }
        if ($S.ContainsKey('minLength') -and $V.Length -lt [int]$S['minLength']) { $errs.Add($where + '：長度至少 ' + $S['minLength']) }
        if ($S.ContainsKey('maxLength') -and $V.Length -gt [int]$S['maxLength']) { $errs.Add($where + '：長度最多 ' + $S['maxLength']) }
    }
    elseif ($V -is [int] -or $V -is [long] -or $V -is [double] -or $V -is [decimal] -or $V -is [single] -or $V -is [int16] -or $V -is [byte]) {
        if ($S.ContainsKey('minimum') -and [double]$V -lt [double]$S['minimum']) { $errs.Add($where + '：不得小於 ' + $S['minimum']) }
        if ($S.ContainsKey('maximum') -and [double]$V -gt [double]$S['maximum']) { $errs.Add($where + '：不得大於 ' + $S['maximum']) }
    }
    elseif ($V -is [object[]]) {
        $n = $V.Length
        if ($S.ContainsKey('minItems') -and $n -lt [int]$S['minItems']) { $errs.Add($where + '：至少 ' + $S['minItems'] + ' 項') }
        if ($S.ContainsKey('maxItems') -and $n -gt [int]$S['maxItems']) { $errs.Add($where + '：最多 ' + $S['maxItems'] + ' 項') }
        if ($S.ContainsKey('uniqueItems') -and $S['uniqueItems'] -eq $true) {
            $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($x in $V) {
                $cx = ConvertTo-PsSdCanonical $x
                if (-not $seen.Add($cx)) { $errs.Add($where + '：項目重複：' + (Format-PsSdShort $cx)); break }
            }
        }
        if ($S.ContainsKey('items')) {
            $is = $S['items']
            for ($i = 0; $i -lt $n; $i++) {
                $sub = Invoke-PsSdValidate $Reg $is $V[$i] ($Path + '[' + $i + ']') $Base
                if ($sub.Errors.Count -gt 0) { $errs.AddRange($sub.Errors) }
            }
        }
        if ($S.ContainsKey('contains')) {
            $found = $false
            foreach ($x in $V) { $sub = Invoke-PsSdValidate $Reg $S['contains'] $x $Path $Base; if ($sub.Errors.Count -eq 0) { $found = $true; break } }
            if (-not $found) { $errs.Add($where + '：至少要有一項符合規定的形狀') }
        }
    }
    elseif ($isObj) {
        if ($S.ContainsKey('minProperties') -and $V.Count -lt [int]$S['minProperties']) { $errs.Add($where + '：至少要有 ' + $S['minProperties'] + ' 個欄位') }
        if ($S.ContainsKey('required')) {
            foreach ($rq in $S['required']) { if (-not $V.ContainsKey([string]$rq)) { $errs.Add($where + '：缺必填欄位 ' + $rq) } }
        }
        $props = $null
        if ($S.ContainsKey('properties')) { $props = $S['properties'] }
        $names = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $V.Keys) { $names.Add([string]$k) }
        $names.Sort([System.StringComparer]::Ordinal)
        if ($null -ne $props) {
            foreach ($nm in $names) {
                if ($props.ContainsKey($nm)) {
                    [void]$ev.Add($nm)
                    $cp = $nm
                    if ($Path) { $cp = $Path + '.' + $nm }
                    $sub = Invoke-PsSdValidate $Reg $props[$nm] $V[$nm] $cp $Base
                    if ($sub.Errors.Count -gt 0) { $errs.AddRange($sub.Errors) }
                }
            }
        }
        if ($S.ContainsKey('additionalProperties')) {
            $ap = $S['additionalProperties']
            foreach ($nm in $names) {
                if ($null -ne $props -and $props.ContainsKey($nm)) { continue }
                [void]$ev.Add($nm)
                if ($ap -is [bool]) {
                    if (-not $ap) { $errs.Add($where + '：不允許的欄位 ' + $nm) }
                } else {
                    $cp = $nm
                    if ($Path) { $cp = $Path + '.' + $nm }
                    $sub = Invoke-PsSdValidate $Reg $ap $V[$nm] $cp $Base
                    if ($sub.Errors.Count -gt 0) { $errs.AddRange($sub.Errors) }
                }
            }
        }
    }

    if ($S.ContainsKey('allOf')) {
        foreach ($s0 in $S['allOf']) {
            $sub = Invoke-PsSdValidate $Reg $s0 $V $Path $Base
            if ($sub.Errors.Count -gt 0) { $errs.AddRange($sub.Errors) } elseif ($isObj) { $ev.UnionWith($sub.Evaluated) }
        }
    }
    if ($S.ContainsKey('anyOf')) {
        $results = [System.Collections.Generic.List[object]]::new()
        $okAny = $false
        foreach ($b in $S['anyOf']) {
            $sub = Invoke-PsSdValidate $Reg $b $V $Path $Base
            $results.Add($sub)
            if ($sub.Errors.Count -eq 0) { $okAny = $true; if ($isObj) { $ev.UnionWith($sub.Evaluated) } }
        }
        if (-not $okAny) { $errs.Add((Format-PsSdAlternatives $where $results)) }
    }
    if ($S.ContainsKey('oneOf')) {
        $results = [System.Collections.Generic.List[object]]::new()
        $valid = [System.Collections.Generic.List[object]]::new()
        foreach ($b in $S['oneOf']) {
            $sub = Invoke-PsSdValidate $Reg $b $V $Path $Base
            $results.Add($sub)
            if ($sub.Errors.Count -eq 0) { $valid.Add($sub) }
        }
        if ($valid.Count -eq 1) { if ($isObj) { $ev.UnionWith($valid[0].Evaluated) } }
        elseif ($valid.Count -eq 0) { $errs.Add((Format-PsSdAlternatives $where $results)) }
        else { $errs.Add($where + '：同時符合 ' + $valid.Count + ' 種寫法，只能符合一種') }
    }
    if ($S.ContainsKey('not')) {
        $sub = Invoke-PsSdValidate $Reg $S['not'] $V $Path $Base
        if ($sub.Errors.Count -eq 0) { $errs.Add($where + '：' + (Format-PsSdNot $S['not'] $V)) }
    }
    if ($S.ContainsKey('if')) {
        $ifr = Invoke-PsSdValidate $Reg $S['if'] $V $Path $Base
        $branch = $null
        if ($ifr.Errors.Count -eq 0) {
            if ($isObj) { $ev.UnionWith($ifr.Evaluated) }
            if ($S.ContainsKey('then')) { $branch = $S['then'] }
        } elseif ($S.ContainsKey('else')) { $branch = $S['else'] }
        if ($null -ne $branch) {
            $sub = Invoke-PsSdValidate $Reg $branch $V $Path $Base
            if ($sub.Errors.Count -gt 0) { $errs.AddRange($sub.Errors) } elseif ($isObj) { $ev.UnionWith($sub.Evaluated) }
        }
    }
    if ($isObj -and $S.ContainsKey('unevaluatedProperties')) {
        $up = $S['unevaluatedProperties']
        $names2 = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $V.Keys) { $names2.Add([string]$k) }
        $names2.Sort([System.StringComparer]::Ordinal)
        foreach ($nm in $names2) {
            if ($ev.Contains($nm)) { continue }
            if ($up -is [bool]) {
                if (-not $up) { $errs.Add($where + '：不允許的欄位 ' + $nm) }
            } else {
                $cp = $nm
                if ($Path) { $cp = $Path + '.' + $nm }
                $sub = Invoke-PsSdValidate $Reg $up $V[$nm] $cp $Base
                if ($sub.Errors.Count -gt 0) { $errs.AddRange($sub.Errors) }
            }
            [void]$ev.Add($nm)
        }
    }
    return $res
}

function Format-PsSdNot {
    param($NotSchema, $Value)
    if ($NotSchema -is [hashtable]) {
        if ($NotSchema.ContainsKey('required')) { return ('不得同時出現 ' + [string]::Join('、', [string[]]@($NotSchema['required']))) }
        if ($NotSchema.ContainsKey('anyOf')) {
            $names = [System.Collections.Generic.List[string]]::new()
            foreach ($b in $NotSchema['anyOf']) { if ($b -is [hashtable] -and $b.ContainsKey('required')) { foreach ($x in $b['required']) { $names.Add([string]$x) } } }
            if ($names.Count -gt 0) { return ('不得出現 ' + [string]::Join('／', $names)) }
        }
    }
    if ($Value -is [string]) { return ('命中禁用的寫法：' + (Format-PsSdShort $Value)) }
    return '命中禁止的形狀'
}

function Format-PsSdAlternatives {
    # anyOf／oneOf 全部不符時，回報最接近的那一種寫法的錯誤（錯誤最少、且不是一開始型別或固定值就不符的分支）。
    param([string]$Where, $Results)
    $best = $null; $bestScore = [int]::MaxValue
    $head0 = $Where + '：'
    foreach ($r in $Results) {
        $score = $r.Errors.Count
        if ($r.Errors.Count -gt 0) {
            $e0 = [string]$r.Errors[0]
            if ($e0.StartsWith($head0) -and $e0.Contains('：型別應為 ')) { $score += 1000 }
            elseif ($e0.StartsWith($head0) -and $e0.Contains('：必須是 ')) { $score += 500 }
        }
        if ($score -lt $bestScore) { $best = $r; $bestScore = $score }
    }
    $head = $Where + '：不符合任何一種允許的寫法'
    if ($null -eq $best -or $best.Errors.Count -eq 0) { return $head }
    $n = [math]::Min(3, $best.Errors.Count)
    $shown = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $n; $i++) { $shown.Add([string]$best.Errors[$i]) }
    return ($head + '；最接近的寫法：' + [string]::Join('；', $shown))
}
