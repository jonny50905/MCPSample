# ps-sdoc-render-lib.ps1 — Spec 文件流程的渲染：canonical → 00-index.md 與每種文件一份 Markdown。
# 04 由 STATE／TRN／FLOW 重新產生狀態圖與情境圖；每個項目前有錨點 <a id="ID"></a>（L5 讀者以「檔名#ID」引用）；
# 每個項目附「被引用」（外環反查）。輸出逐位元可重現（LF、固定順序）。依賴 ps-sdoc-lib.ps1。

$script:PsSdRenderLibVersion = '1'
$script:PsSdCtxText = @{ 'CURRENT_USER_OPRID' = '目前使用者帳號'; 'CURRENT_USER_EMPLID' = '目前使用者員工編號'; 'CURRENT_DATE' = '系統日期'
    'CURRENT_DATETIME' = '系統時間'; 'CURRENT_MODE' = '目前模式'; 'CURRENT_ACTION' = '目前動作' }
$script:PsSdOpText = @{ 'EQ' = '＝'; 'NE' = '≠'; 'GT' = '＞'; 'GE' = '≥'; 'LT' = '＜'; 'LE' = '≤'; 'IN' = '屬於'; 'NOT_IN' = '不屬於'; 'BETWEEN' = '介於'; 'HAS_ROLE' = '具有角色' }
$script:PsSdUnaryText = @{ 'IS_BLANK' = '為空白（字元欄為 NULL 或單一空白）'; 'IS_NOT_BLANK' = '不為空白'; 'EXISTS' = '查得到'
    'NOT_EXISTS' = '查不到（結果為空）'; 'CHANGED' = '本次有變更'; 'DONE' = '已完成'; 'NOT_DONE' = '尚未完成' }
$script:PsSdBasisText = @{ 'AUTHORITATIVE_DOC' = '狀態權威文件'; 'CODE' = '程式'; 'DATA' = '資料'; 'METADATA' = 'metadata'; 'KNOWLEDGE' = '既有研究'
    'PROJECT_INPUT' = '專案輸入'; 'HUMAN_DECISION' = '人工決策'; 'DERIVED' = '推導'; 'COMPUTED' = '外環計算'; 'TEMPLATE' = '框架模板' }
$script:PsSdSectionTitle = @{ 'GOAL' = '專案目標'; 'RESP' = '決策責任'; 'OBJ' = '範圍（舊系統物件）'; 'AI' = '條款'; 'ENT' = '資料實體'; 'FLD' = '資料欄位'
    'DRV' = '衍生概念（查找規則）'; 'XF' = '不建置的原生欄位'; 'ROLE' = '角色'; 'PERM' = '權限'; 'STATE' = '狀態'; 'TRN' = '狀態轉移'; 'FLOW' = '情境流程'
    'ACT' = '狀態活動'; 'IF' = '介面與批次'; 'FR' = '功能需求'; 'UI' = '畫面與元件'; 'MSG' = '訊息'; 'BR' = '業務規則'; 'OP' = '操作契約'; 'TC' = '測試案例'
    'TASK' = '工作項'; 'DOD' = '完成條件'; 'Q' = '問題'; 'DEC' = '決策' }
$script:PsSdNl = @{ 'kind' = '種類'; 'object' = '物件'; 'action' = '動作'; 'event' = '事件'; 'transitions' = '轉移'; 'modes' = '模式'; 'control' = '元件'
    'message' = '訊息'; 'assignments' = '指派'; 'interface' = '介面'; 'sources' = '來源實體'; 'joins' = '串接'; 'filter' = '篩選'; 'effectiveDating' = '有效日規則'
    'pick' = '取值欄位'; 'tieBreak' = '同值處理'; 'result' = '結果'; 'fallback' = '替代'; 'note' = '說明'; 'rule' = '規則'; 'orderBy' = '排序'; 'entity' = '實體'
    'keyField' = '鍵欄位'; 'asOf' = '基準日'; 'effStatusActiveOnly' = '只取有效狀態'; 'currentRow' = '目前有效列'; 'boundary' = '交易邊界'; 'writeOrder' = '寫入順序'
    'onFailure' = '失敗時'; 'concurrency' = '併發'; 'idempotency' = '重複執行'; 'strategy' = '策略'; 'legacyBehavior' = '原系統行為'; 'repeatable' = '可重複'
    'behavior' = '行為'; 'writes' = '寫入'; 'interfaces' = '介面'; 'events' = '事件鏈'; 'name' = '名稱'; 'field' = '欄位'; 'drv' = '衍生概念'; 'required' = '必填'
    'seq' = '序'; 'transition' = '轉移'; 'description' = '說明'; 'state' = '狀態'; 'actor' = '操作者'; 'data' = '資料'; 'synthetic' = '合成資料'; 'rules' = '規則'
    'flows' = '情境'; 'controls' = '元件'; 'operations' = '操作'; 'resultState' = '結果狀態'; 'noDataChange' = '資料不變'; 'value' = '值'; 'visible' = '顯示'
    'editable' = '可編輯'; 'label' = '文字'; 'stored' = '儲存值'; 'key' = '代號'; 'scrollLevel' = '層級'; 'repeating' = '可重複列'; 'parentRegion' = '上層區塊'
    'excluded' = '排除'; 'count' = '欄數'; 'noneExcludable' = '無可排除'; 'checkedOn' = '查詢日'; 'undetermined' = '判不了'; 'code' = '代碼'; 'a' = '查法 a'
    'b' = '查法 b'; 'c' = '查法 c'; 'xlat' = '值清單'; 'prompt' = '查找來源'; 'range' = '範圍'; 'free' = '自由輸入'; 'derived' = '衍生'; 'active' = '有效'
    'dataPresence' = '資料'; 'target' = '目標'; 'layout' = '版面'; 'encoding' = '編碼'; 'fields' = '欄位'; 'length' = '長度'; 'format' = '格式'; 'source' = '來源'
    'from' = '起'; 'to' = '迄'; 'location' = '位置'; 'entityKey' = '狀態實體'; 'option' = '選項'; 'consequence' = '結果'; 'statement' = '敘述'; 'refs' = '參照'
    'evidenceRequired' = '需要的證據'; 'entities' = '實體'; 'derivations' = '衍生概念'; 'roles' = '角色'; 'tests' = '測試'; 'effect' = '效果'; 'inputs' = '輸入'
    'left' = '左'; 'right' = '右'; 'operation' = '操作'; 'definitionOnlyCount' = '只計數的定義值'; 'definitionOnlyCodes' = '定義值'; 'finalStates' = '終點狀態'
    'evaluatedAfter' = '在這些之後檢查'; 'activities' = '活動'; 'branchCondition' = '分支條件原文'; 'absentValues' = '不會出現的值'; 'context' = '情境'
    'composite' = '複合狀態'; 'index' = '區塊序' }

function New-PsSdRenderContext {
    param($Model, $Envelopes, $SchemaReg)
    $rev = New-PsSdMap
    foreach ($id in $Model.ById.Keys) {
        foreach ($r in (Get-PsSdItemRefs $Model.ById[$id])) {
            if (-not $rev.ContainsKey($r)) { $rev[$r] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal) }
            [void]$rev[$r].Add([string]$id)
        }
    }
    foreach ($pd in $Model.ProgramDispositions) {
        foreach ($x in @($pd['items'])) {
            if ($null -eq $x) { continue }
            if (-not $rev.ContainsKey([string]$x)) { $rev[[string]$x] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal) }
            [void]$rev[[string]$x].Add([string]$pd['program'])
        }
    }
    $desc = New-PsSdMap
    if ($null -ne $SchemaReg) {
        foreach ($p in $script:PsSdPrefixInfo.Keys) {
            $m = New-PsSdMap
            $def = (Resolve-PsSdRef $SchemaReg '' (Get-PsSdItemSchemaRoot $p)).Schema
            foreach ($part in $def['allOf']) {
                if ($part -is [System.Collections.IDictionary] -and $part.Contains('properties')) {
                    foreach ($k in $part['properties'].Keys) { $pv = $part['properties'][$k]; if ($pv -is [System.Collections.IDictionary] -and $pv.Contains('description')) { $m[[string]$k] = [string]$pv['description'] } }
                }
            }
            $desc[$p] = $m
        }
    }
    return @{ Model = $Model; ById = $Model.ById; Reverse = $rev; Docs = $Envelopes; Desc = $desc }
}

function Get-PsSdLabel {
    param($Rc, [string]$Id)
    if (-not $Rc.ById.ContainsKey($Id)) { return $Id }
    $p = Get-PsSdIdPrefix $Id
    $it = $Rc.ById[$Id]
    switch ($p) {
        'OBJ' { return [string]$it['objectName'] }
        'TRN' { $k = [string]$it['key']; $k = $k.Substring($k.IndexOf(':') + 1); return $k.Replace('*', '新建').Replace('>', '→') }
        'FLOW' { return [string]$it['scenarioType'] }
        'UI' {
            if ($it.Contains('title') -and $it['title'] -is [string]) { return [string]$it['title'] }
            if ($it.Contains('label') -and $it['label'] -is [string]) { return [string]$it['label'] }
            $k = [string]$it['key']; return $k.Substring($k.LastIndexOf('.') + 1)
        }
        'RESP' { return [string]$it['area'] }
        'AI' { return [string]$it['category'] }
        'DEC' { return [string]$it['title'] }
    }
    if (@('ENT', 'FLD', 'XF', 'PERM', 'DOD', 'Q', 'MSG') -ccontains $p) { return [string]$it['key'] }
    foreach ($k in @('name', 'title')) { if ($it.Contains($k) -and $it[$k] -is [string]) { return [string]$it[$k] } }
    return [string]$it['key']
}

function Get-PsSdLink {
    param($Rc, [string]$Id)
    if ($Id -ceq 'INITIAL') { return '（新建）' }
    if (-not $Rc.ById.ContainsKey($Id)) { return $Id }
    return ($Id + '（' + (Get-PsSdLabel $Rc $Id) + '）')
}

function ConvertTo-PsSdOperandText {
    param($Rc, $O)
    if ($O.Contains('fld')) { return (Get-PsSdLink $Rc ([string]$O['fld'])) }
    if ($O.Contains('drv')) { return ('〈' + (Get-PsSdLabel $Rc ([string]$O['drv'])) + '〉（' + $O['drv'] + '）') }
    if ($O.Contains('state')) {
        $sidv = [string]$O['state']
        if ($Rc.ById.ContainsKey($sidv)) {
            $it = $Rc.ById[$sidv]; $nm = [string]$it['name']; $sp = $nm.IndexOf(' '); if ($sp -ge 0) { $nm = $nm.Substring($sp + 1) }
            return ("'" + $it['code'] + "'（" + $sidv + ' ' + $nm + '）')
        }
        return $sidv
    }
    if ($O.Contains('role')) { return (Get-PsSdLink $Rc ([string]$O['role'])) }
    if ($O.Contains('act')) { return ('活動 ' + (Get-PsSdLink $Rc ([string]$O['act']))) }
    if ($O.Contains('const')) { if ([string]$O['type'] -ceq 'NUMBER') { return [string]$O['const'] }; return ("'" + $O['const'] + "'") }
    if ($O.Contains('ctx')) { $c = [string]$O['ctx']; if ($script:PsSdCtxText.ContainsKey($c)) { return $script:PsSdCtxText[$c] }; return $c }
    if ($O.Contains('param')) { return ('參數 ' + $O['param']) }
    return (ConvertTo-PsSdCanonical $O)
}

function ConvertTo-PsSdCondText {
    param($Rc, $C)
    if ($C -is [string]) { if ($C -ceq 'ALWAYS') { return '無條件' }; return $C }
    if ($C.Contains('all')) { $parts = @(); foreach ($x in $C['all']) { $parts += ('（' + (ConvertTo-PsSdCondText $Rc $x) + '）') }; return ($parts -join '且') }
    if ($C.Contains('any')) { $parts = @(); foreach ($x in $C['any']) { $parts += ('（' + (ConvertTo-PsSdCondText $Rc $x) + '）') }; return ($parts -join '或') }
    if ($C.Contains('not') -and -not $C.Contains('left')) { return ('非（' + (ConvertTo-PsSdCondText $Rc $C['not']) + '）') }
    if ($C.Contains('rows')) {
        $ent = Get-PsSdLink $Rc ([string]$C['rows']); $w = ConvertTo-PsSdCondText $Rc $C['where']
        $q = [string]$C['quantifier']
        if ($q -ceq 'ALL') { $t = $ent + ' 中對應這一筆的每一列都符合（' + $w + '）' }
        elseif ($q -ceq 'ANY') { $t = $ent + ' 中對應這一筆的至少一列符合（' + $w + '）' }
        elseif ($q -ceq 'NONE') { $t = $ent + ' 中對應這一筆的列沒有任何一列符合（' + $w + '）' }
        else {
            $cnt = $C['count']; $op = [string]$cnt['op']; $ot = $op; if ($script:PsSdOpText.ContainsKey($op)) { $ot = $script:PsSdOpText[$op] }
            $t = $ent + ' 中對應這一筆、且符合（' + $w + '）的列數 ' + $ot + ' ' + $cnt['value']
        }
        if ($C.Contains('whenEmpty')) { if ([string]$C['whenEmpty'] -ceq 'MET') { $t += '；沒有任何對應的列時視為成立' } else { $t += '；沒有任何對應的列時視為不成立' } }
        return $t
    }
    if (-not $C.Contains('left')) { return (ConvertTo-PsSdCanonical $C) }
    $left = ConvertTo-PsSdOperandText $Rc $C['left']
    $op = [string]$C['op']
    if ($script:PsSdUnaryText.ContainsKey($op)) { return ($left + ' ' + $script:PsSdUnaryText[$op]) }
    $ot = $op; if ($script:PsSdOpText.ContainsKey($op)) { $ot = $script:PsSdOpText[$op] }
    $r = $C['right']
    if ($r -is [System.Collections.IList] -and -not ($r -is [string])) {
        $parts = @(); foreach ($x in $r) { $parts += (ConvertTo-PsSdOperandText $Rc $x) }
        if ($op -ceq 'BETWEEN') { return ($left + ' 介於 ' + ($parts -join ' 與 ')) }
        return ($left + ' ' + $ot + ' {' + ($parts -join '、') + '}')
    }
    if ($null -eq $r) { return ($left + ' ' + $ot) }
    return ($left + ' ' + $ot + ' ' + (ConvertTo-PsSdOperandText $Rc $r))
}

function Test-PsSdIsCondValue {
    param($V)
    if ($V -is [string]) { return ($V -ceq 'ALWAYS') }
    if (-not ($V -is [System.Collections.IDictionary])) { return $false }
    if ($V.Contains('all') -or $V.Contains('any')) { return $true }
    if ($V.Contains('not') -and $V.Count -eq 1) { return $true }
    if ($V.Contains('left') -and $V.Contains('op')) { return $true }
    if ($V.Contains('rows') -and $V.Contains('quantifier') -and $V.Contains('where')) { return $true }
    return $false
}

function Test-PsSdIsOperandValue {
    param($V)
    if (-not ($V -is [System.Collections.IDictionary])) { return $false }
    $kinds = @('fld', 'drv', 'state', 'role', 'act', 'const', 'ctx', 'param')
    $n = 0
    foreach ($k in $V.Keys) { if ($kinds -ccontains [string]$k) { $n++ } elseif ([string]$k -cne 'type') { return $false } }
    return ($n -eq 1)
}

function ConvertTo-PsSdValueText {
    # 能寫成一行就回傳文字，否則回 $null。
    param($Rc, $V)
    if ($V -is [bool]) { if ($V) { return '是' }; return '否' }
    if (Test-PsSdIsNumber $V) { return [string]$V }
    if ($V -is [string]) {
        if ($script:PsSdRefRx.IsMatch($V)) { return (Get-PsSdLink $Rc $V) }
        if ($V -ceq 'INITIAL') { return '（新建）' }
        if ($V -ceq 'ALWAYS') { return '一律（無條件）' }
        if ($V -ceq 'NEVER') { return '永不' }
        return $V
    }
    if ($V -is [System.Collections.IDictionary]) {
        if ($V.Contains('na') -and ($V.Count -eq 1 -or ($V.Count -eq 2 -and $V.Contains('evidence')))) { return ('不適用：' + $V['na']) }
        if ($V.Count -eq 1 -and $V.Contains('unresolved')) { return ('未解：' + (Get-PsSdLink $Rc ([string]$V['unresolved']))) }
        if (Test-PsSdIsCondValue $V) { return (ConvertTo-PsSdCondText $Rc $V) }
        if (Test-PsSdIsOperandValue $V) { return (ConvertTo-PsSdOperandText $Rc $V) }
        $okKeys = $true; foreach ($k in $V.Keys) { if (@('field', 'value', 'when', 'note') -cnotcontains [string]$k) { $okKeys = $false } }
        if ($okKeys -and $V.Contains('field') -and $V.Contains('value')) {
            if ($V['value'] -is [System.Collections.IDictionary]) { $t = (Get-PsSdLink $Rc ([string]$V['field'])) + ' ← ' + (ConvertTo-PsSdOperandText $Rc $V['value']) }
            else { $t = (Get-PsSdLink $Rc ([string]$V['field'])) + " ＝ '" + $V['value'] + "'" }
            if ($V.Contains('when')) { $t += '（當 ' + (ConvertTo-PsSdCondText $Rc $V['when']) + '）' }
            if ($V.Contains('note')) { $t += '（' + $V['note'] + '）' }
            return $t
        }
        return $null
    }
    if ($V -is [System.Collections.IList]) {
        $parts = @()
        foreach ($x in $V) { $t = ConvertTo-PsSdValueText $Rc $x; if ($null -eq $t) { return $null }; $parts += $t }
        if ($parts.Count -eq 0) { return '（無）' }
        $joined = $parts -join '、'
        if ($joined.Length -le 160 -or $parts.Count -eq 1) { return $joined }
        return $null
    }
    if ($null -eq $V) { return '（無）' }
    return [string]$V
}

function ConvertTo-PsSdBullets {
    param($Rc, $V, [int]$Indent)
    $pad = '  ' * $Indent
    $out = [System.Collections.Generic.List[string]]::new()
    if ($V -is [System.Collections.IDictionary]) {
        foreach ($k in $V.Keys) {
            $nm = [string]$k; if ($script:PsSdNl.ContainsKey($nm)) { $nm = $script:PsSdNl[$nm] }
            $t = ConvertTo-PsSdValueText $Rc $V[$k]
            if ($null -ne $t) { $out.Add($pad + '- ' + $nm + '：' + $t) }
            else { $out.Add($pad + '- ' + $nm + '：'); foreach ($l in (ConvertTo-PsSdBullets $Rc $V[$k] ($Indent + 1))) { $out.Add($l) } }
        }
    } elseif ($V -is [System.Collections.IList]) {
        $i = 0
        foreach ($x in $V) {
            $i++
            $t = ConvertTo-PsSdValueText $Rc $x
            if ($null -ne $t) { $out.Add($pad + '- ' + $t); continue }
            if ($x -is [System.Collections.IDictionary]) {
                $all = $true; $parts = @()
                foreach ($k in $x.Keys) { $tv = ConvertTo-PsSdValueText $Rc $x[$k]; if ($null -eq $tv) { $all = $false; break }; $nm = [string]$k; if ($script:PsSdNl.ContainsKey($nm)) { $nm = $script:PsSdNl[$nm] }; $parts += ($nm + '：' + $tv) }
                if ($all) { $out.Add($pad + '- ' + ($parts -join '；')); continue }
            }
            $out.Add($pad + '- 第 ' + $i + ' 筆')
            foreach ($l in (ConvertTo-PsSdBullets $Rc $x ($Indent + 1))) { $out.Add($l) }
        }
    }
    return , $out.ToArray()
}

function ConvertTo-PsSdItemMarkdown {
    param($Rc, $It)
    $id = [string]$It['id']; $p = Get-PsSdIdPrefix $id
    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add('<a id="' + $id + '"></a>')
    $out.Add('')
    $out.Add('### ' + $id + '　' + (Get-PsSdLabel $Rc $id))
    $out.Add('')
    $out.Add('- 自然鍵：`' + $It['key'] + '`')
    $skip = @('id', 'key', 'lifecycle', 'basis', 'certainty', 'evidence', 'derivedFrom', 'component', 'inference')
    $desc = $null; if ($Rc.Desc.ContainsKey($p)) { $desc = $Rc.Desc[$p] }
    foreach ($k in $It.Keys) {
        $kn = [string]$k
        if ($skip -ccontains $kn) { continue }
        $d = $kn; if ($null -ne $desc -and $desc.ContainsKey($kn)) { $d = $desc[$kn] }
        $t = ConvertTo-PsSdValueText $Rc $It[$k]
        if ($null -ne $t) { $out.Add('- ' + $d + '：' + $t) }
        else { $out.Add('- ' + $d + '：'); foreach ($l in (ConvertTo-PsSdBullets $Rc $It[$k] 1)) { $out.Add($l) } }
    }
    if ($It.Contains('component')) { $out.Add('- Component：' + $It['component']) }
    $src = [string]$It['basis']; if ($script:PsSdBasisText.ContainsKey($src)) { $src = $script:PsSdBasisText[$src] }
    if ([string]$It['certainty'] -ceq 'INFERRED') { $src += '（推論：' + $It['inference'] + '）' }
    if ($It.Contains('derivedFrom') -and @($It['derivedFrom']).Count -gt 0) { $src += '；推導自 ' + (@($It['derivedFrom']) -join '、') }
    if (@($It['evidence']).Count -gt 0) { $src += '；證據 ' + (@($It['evidence']) -join '、') }
    $out.Add('- 來源：' + $src)
    if ($Rc.Reverse.ContainsKey($id)) {
        $keyed = [System.Collections.Generic.List[string]]::new()
        foreach ($x in $Rc.Reverse[$id]) { $px = Get-PsSdIdPrefix $x; $rank = 99; if ($script:PsSdPrefixInfo.Contains($px)) { $rank = $script:PsSdPrefixInfo[$px].Rank }; $keyed.Add($rank.ToString('D2', [System.Globalization.CultureInfo]::InvariantCulture) + [char]0 + $x) }
        $keyed.Sort([System.StringComparer]::Ordinal)
        $groups = [ordered]@{}
        foreach ($kx in $keyed) { $x = $kx.Substring(3); $px = Get-PsSdIdPrefix $x; if (-not $groups.Contains($px)) { $groups[$px] = [System.Collections.Generic.List[string]]::new() }; $groups[$px].Add($x) }
        $gs = @(); foreach ($g in $groups.Keys) { $gs += ($groups[$g] -join '、') }
        $out.Add('- 被引用（外環反查）：' + ($gs -join '；'))
    } else { $out.Add('- 被引用（外環反查）：尚無') }
    $out.Add('')
    return , $out.ToArray()
}

function ConvertTo-PsSdMermaidSafe {
    # Mermaid 標籤裡會破壞語法的字元換成全形或空白。
    param([string]$Text)
    $t = $Text.Replace('"', '＂').Replace(';', '；').Replace('#', '＃').Replace('{', '｛').Replace('}', '｝').Replace('|', '｜').Replace('<', '〈').Replace('>', '〉').Replace('`', '｀')
    $t = $t.Replace("`r", ' ').Replace("`n", ' ')
    return $t
}

function Get-PsSdMermaidState {
    param($Rc, $Items)
    $states = @(); $trns = @()
    foreach ($i in $Items) { $id = [string]$i['id']; if ($id.StartsWith('STATE-')) { $states += , $i } elseif ($id.StartsWith('TRN-')) { $trns += , $i } }
    $regionOf = New-PsSdMap
    foreach ($s in $states) { if ($s.Contains('regions')) { $n = 0; foreach ($r in $s['regions']) { $n++; $regionOf[[string]$r['entityKey']] = @([string]$s['code'], $n) } } }
    $sid = New-PsSdMap
    foreach ($s in $states) {
        $e = [string]$s['entityKey']; $code = [string]$s['code']
        if ($regionOf.ContainsKey($e)) { $sid[[string]$s['id']] = 'R' + $regionOf[$e][0] + '_' + $regionOf[$e][1] + '_' + $code } else { $sid[[string]$s['id']] = 'S' + $code }
    }
    $edges = {
        param($Ts, [string]$Pad)
        $o = [System.Collections.Generic.List[string]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($t in $Ts) {
            $a = '[*]'; if ([string]$t['from'] -cne 'INITIAL') { $a = $sid[[string]$t['from']] }
            $b = $sid[[string]$t['to']]
            if ($t.Contains('via') -and @($t['via']).Count -gt 0) {
                $v = [regex]::Replace([string]@($t['via'])[0], '[^A-Za-z0-9_]', '_')
                if ($seen.Add($a + '|' + $v)) { $o.Add($Pad + $a + ' --> ' + $v) }
                $g = ''
                if ((Test-PsSdIsCondValue $t['guard']) -and -not ($t['guard'] -is [string])) { $g = ConvertTo-PsSdCondText $Rc $t['guard']; $g = [regex]::Replace($g, '（[A-Z0-9_$#@]+\.', '（') }
                $lab = ([string]$t['id'] + ' ' + $g).Trim()
                $o.Add($Pad + $v + ' --> ' + $b + ' : ' + (ConvertTo-PsSdMermaidSafe $lab))
            } else {
                $lab = [string]$t['id']
                if ($t.Contains('diagramLabels') -and @($t['diagramLabels']).Count -gt 0) { $lab += ' ' + (@($t['diagramLabels']) -join '／') }
                $em = [string]$t['exitMode']
                if ($em -ceq 'ON_COMPLETION') { $lab += '（守門）' } elseif ($em -ceq 'INTERRUPT') { $lab += '（中斷子業務）' }
                $o.Add($Pad + $a + ' --> ' + $b + ' : ' + (ConvertTo-PsSdMermaidSafe $lab))
            }
        }
        return , $o.ToArray()
    }
    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add('```mermaid'); $out.Add('stateDiagram-v2')
    $main = @(); foreach ($s in $states) { if (-not $regionOf.ContainsKey([string]$s['entityKey'])) { $main += , $s } }
    foreach ($s in $main) {
        $nm = ConvertTo-PsSdMermaidSafe ([string]$s['name'])
        if (-not $s.Contains('regions') -or @($s['regions']).Count -eq 0) { $out.Add('    state "' + $nm + '" as ' + $sid[[string]$s['id']]); continue }
        $out.Add('    state "' + $nm + '" as ' + $sid[[string]$s['id']] + ' {')
        $i = 0
        foreach ($r in $s['regions']) {
            if ($i -gt 0) { $out.Add('        --') }
            $i++
            $ek = [string]$r['entityKey']
            foreach ($x in $states) { if ([string]$x['entityKey'] -ceq $ek) { $out.Add('        state "' + (ConvertTo-PsSdMermaidSafe ([string]$x['name'])) + '" as ' + $sid[[string]$x['id']]) } }
            $sub = @(); foreach ($t in $trns) { if ([string]$t['entityKey'] -ceq $ek) { $sub += , $t } }
            foreach ($l in (& $edges $sub '        ')) { $out.Add($l) }
            foreach ($x in $states) { if ([string]$x['entityKey'] -ceq $ek -and $x['isFinal'] -eq $true) { $out.Add('        ' + $sid[[string]$x['id']] + ' --> [*]') } }
        }
        $out.Add('    }')
    }
    $vias = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($t in $trns) { if ($t.Contains('via')) { foreach ($v in @($t['via'])) { [void]$vias.Add([regex]::Replace([string]$v, '[^A-Za-z0-9_]', '_')) } } }
    foreach ($v in $vias) { $out.Add('    state ' + $v + ' <<choice>>') }
    $mt = @(); foreach ($t in $trns) { if (-not $regionOf.ContainsKey([string]$t['entityKey'])) { $mt += , $t } }
    foreach ($l in (& $edges $mt '    ')) { $out.Add($l) }
    foreach ($s in $main) { if ($s['isFinal'] -eq $true) { $out.Add('    ' + $sid[[string]$s['id']] + ' --> [*]') } }
    $out.Add('```')
    return , $out.ToArray()
}

function Get-PsSdMermaidFlow {
    param($Rc, $Items)
    $states = @(); $flows = @()
    foreach ($i in $Items) { $id = [string]$i['id']; if ($id.StartsWith('STATE-')) { $states += , $i } elseif ($id.StartsWith('FLOW-')) { $flows += , $i } }
    $regionOf = New-PsSdMap
    foreach ($s in $states) { if ($s.Contains('regions')) { $n = 0; foreach ($r in $s['regions']) { $n++; $regionOf[[string]$r['entityKey']] = @([string]$s['code'], $n) } } }
    $sid = New-PsSdMap
    foreach ($s in $states) {
        $e = [string]$s['entityKey']; $code = [string]$s['code']
        if ($regionOf.ContainsKey($e)) { $sid[[string]$s['id']] = 'R' + $regionOf[$e][0] + '_' + $regionOf[$e][1] + '_' + $code } else { $sid[[string]$s['id']] = 'N' + $code }
    }
    $startId = { param([string]$EntKey); if ($regionOf.ContainsKey($EntKey)) { return ('S' + $regionOf[$EntKey][0] + '_' + $regionOf[$EntKey][1]) }; return 'START' }
    $edges = {
        param([string]$EntKey, [string]$Pad)
        $o = [System.Collections.Generic.List[string]]::new()
        foreach ($f in $flows) {
            if ([string]$f['entityKey'] -cne $EntKey -or -not ($f['steps'] -is [System.Collections.IList])) { continue }
            foreach ($st in $f['steps']) {
                $tid = [string]$st['transition']
                if (-not $Rc.ById.ContainsKey($tid)) { continue }
                $t = $Rc.ById[$tid]
                $a = & $startId $EntKey; if ([string]$t['from'] -cne 'INITIAL') { $a = $sid[[string]$t['from']] }
                $o.Add($Pad + $a + ' -->|' + (ConvertTo-PsSdMermaidSafe ([string]$f['scenarioType'])) + '｜' + $tid + '| ' + $sid[[string]$t['to']])
            }
        }
        return , $o.ToArray()
    }
    $flowEnts = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($f in $flows) { [void]$flowEnts.Add([string]$f['entityKey']) }
    $mainEnts = [System.Collections.Generic.List[string]]::new()
    foreach ($s in $states) { $e = [string]$s['entityKey']; if (-not $regionOf.ContainsKey($e) -and $flowEnts.Contains($e) -and -not $mainEnts.Contains($e)) { $mainEnts.Add($e) } }
    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add('```mermaid'); $out.Add('flowchart TD')
    foreach ($s in $states) {
        if (-not $mainEnts.Contains([string]$s['entityKey']) -or -not $s.Contains('regions') -or @($s['regions']).Count -eq 0) { continue }
        $out.Add('    subgraph ' + $sid[[string]$s['id']] + ' [' + (ConvertTo-PsSdMermaidSafe ([string]$s['name'])) + ']')
        $i = 0
        foreach ($r in $s['regions']) {
            $i++
            $ek = [string]$r['entityKey']
            $out.Add('        subgraph G' + $s['code'] + '_' + $i + ' [' + $ek + ']')
            if ($flowEnts.Contains($ek)) { $out.Add('            ' + (& $startId $ek) + '((新建))') }
            foreach ($x in $states) { if ([string]$x['entityKey'] -ceq $ek) { $out.Add('            ' + $sid[[string]$x['id']] + '["' + (ConvertTo-PsSdMermaidSafe ([string]$x['name'])) + '"]') } }
            foreach ($l in (& $edges $ek '            ')) { $out.Add($l) }
            $out.Add('        end')
        }
        $out.Add('    end')
    }
    $out.Add('    START((新建))')
    foreach ($s in $states) { if ($mainEnts.Contains([string]$s['entityKey']) -and (-not $s.Contains('regions') -or @($s['regions']).Count -eq 0)) { $out.Add('    ' + $sid[[string]$s['id']] + '["' + (ConvertTo-PsSdMermaidSafe ([string]$s['name'])) + '"]') } }
    foreach ($ek in $mainEnts) { foreach ($l in (& $edges $ek '    ')) { $out.Add($l) } }
    $out.Add('```')
    return , $out.ToArray()
}

function ConvertTo-PsSdCell {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return $Text.Replace("`r", '').Replace("`n", '<br>').Replace('|', '\|')
}

function ConvertTo-PsSdDocMarkdown {
    param($Rc, [string]$Doc)
    $d = $Rc.Docs[$Doc]
    $out = [System.Collections.Generic.List[string]]::new()
    $gate = @(); foreach ($k in $d['gate'].Keys) { $gate += ([string]$k + ' ' + $d['gate'][$k]) }
    $deps = @(); foreach ($x in @($d['dependsOn'])) { if ($null -ne $x) { $deps += ([string]$x).Substring(0, 2) } }
    $depText = '無'; if ($deps.Count -gt 0) { $depText = $deps -join '、' }
    $oq = @(); foreach ($q in @($d['openQuestions'])) { if ($null -ne $q) { $oq += (Get-PsSdLink $Rc ([string]$q)) } }
    $oqText = '無'; if ($oq.Count -gt 0) { $oqText = $oq -join '、' }
    $out.Add('# ' + $d['title']); $out.Add('')
    $out.Add('> `' + $d['docId'] + '`｜版本 ' + $d['revision'] + '｜狀態 **' + $d['status'] + '**｜' + ($gate -join ' · '))
    $out.Add('> 依賴文件：' + $depText + '｜未解問題：' + $oqText)
    $out.Add('> ' + $d['summary'])
    if ($d.Contains('approval')) { $out.Add('> 已核准：' + $d['approval']['approvedBy'] + '，' + $d['approval']['approvedOn'] + '（docHash ' + ([string]$d['approval']['docHash']).Substring(0, 12) + '）') }
    $out.Add('> 本檔由 canonical JSON 以程式產生，請勿手改；修改走研究重跑或 19 的決策。')
    $out.Add('')
    $items = @($d['items'])
    if ($Doc -eq '01-overview') {
        $out.Add('## 範圍摘要'); $out.Add(''); $out.Add('| 分類 | 物件 |'); $out.Add('|---|---|')
        foreach ($inc in @('CORE', 'DEPENDENCY', 'EXCLUDED')) {
            $objs = @(); foreach ($o in $items) { if (([string]$o['id']).StartsWith('OBJ-') -and [string]$o['inclusion'] -ceq $inc) { $objs += ([string]$o['id'] + ' ' + $o['objectName']) } }
            $out.Add('| ' + $inc + ' | ' + (ConvertTo-PsSdCell ($objs -join '、')) + ' |')
        }
        $out.Add(''); $out.Add('專案輸入檔：' + $d['projectInputStatus'] + '。不建置的原生欄位見 07。'); $out.Add('')
    }
    if ($Doc -eq '04-workflow') {
        $out.Add('## 狀態圖（由 STATE／TRN 重新產生）'); $out.Add('')
        foreach ($l in (Get-PsSdMermaidState $Rc $items)) { $out.Add($l) }
        $out.Add(''); $out.Add('## 情境流程圖（由 FLOW 重新產生）'); $out.Add('')
        foreach ($l in (Get-PsSdMermaidFlow $Rc $items)) { $out.Add($l) }
        $out.Add('')
        $sr = $d['statusReading']
        $out.Add('## 狀態圖解讀'); $out.Add('')
        $line = [string]$sr['readers'] + ' 位讀者各自讀 STATUS 檔（Mermaid 區塊共 ' + $sr['mermaidLines'] + ' 行，每一行都有交代），拆成 ' + $sr['facts'] + ' 項事實比對：三份一致 ' + $sr['unanimous'] + ' 項'
        if (@($sr['contested']).Count -eq 0) { $line += '。' } else { $line += '；不一致 ' + @($sr['contested']).Count + ' 項，第 2 輪逐項重讀後表決：' }
        $out.Add($line); $out.Add('')
        if (@($sr['contested']).Count -gt 0) {
            $out.Add('| 事實 | 引用的行 | 第 1 輪（有：沒有） | 第 2 輪（同意：不同意） | 結果 |'); $out.Add('|---|---|---|---|---|')
            foreach ($c in $sr['contested']) {
                $ls = @(); foreach ($x in $c['lines']) { $ls += ([string]$x).Substring(([string]$x).IndexOf('#') + 1) }
                $out.Add('| ' + (ConvertTo-PsSdCell ([string]$c['fact'])) + ' | ' + ($ls -join '、') + ' | ' + $c['round1'] + ' | ' + $c['round2'] + ' | ' + $c['result'] + ' |')
            }
            $out.Add('')
        }
        if ([int]$sr['unresolved'] -gt 0) { $out.Add('第 2 輪仍無多數 ' + $sr['unresolved'] + ' 項，已在 90 開 STATUS_READING_CONFLICT 交人裁決。'); $out.Add('') }
        $out.Add('## STATUS 文字的處置'); $out.Add('')
        $out.Add('STATUS 檔圖外的每一行說明，以及讀者列為業務文字的圖內行，都要處置：寫進了哪些項目，或為什麼沒有規格內容。'); $out.Add('')
        $out.Add('| 位置 | 原文 | 處置 | 寫進的項目或理由 |'); $out.Add('|---|---|---|---|')
        foreach ($x in @($d['statusTexts'])) {
            if ($null -eq $x) { continue }
            $what = @(); if ($x.Contains('items')) { foreach ($a in $x['items']) { $what += (Get-PsSdLink $Rc ([string]$a)) } }
            $w = $what -join '、'
            if ($x.Contains('note')) { if ($w) { $w += '；' }; $w += [string]$x['note'] }
            $out.Add('| ' + $x['locator'] + ' | ' + (ConvertTo-PsSdCell ([string]$x['text'])) + ' | ' + $x['disposition'] + ' | ' + (ConvertTo-PsSdCell $w) + ' |')
        }
        $out.Add('')
    }
    if ($Doc -eq '07-database') {
        $out.Add('## 不建置的原生欄位（摘要）'); $out.Add(''); $out.Add('| ID | Record | 欄位 | 資料剖析 |'); $out.Add('|---|---|---|---|')
        foreach ($x in $items) { if (([string]$x['id']).StartsWith('XF-')) { $out.Add('| ' + $x['id'] + ' | ' + $x['key'] + ' | ' + (@($x['fields']) -join '、') + ' | ' + (ConvertTo-PsSdCell ([string]$x['dataCheck'])) + ' |') } }
        $out.Add(''); $out.Add('重建時這些欄位不建資料欄、不上畫面、不寫規則。'); $out.Add('')
    }
    if ($Doc -eq '09-business-logic') {
        $out.Add('## PeopleCode 程式處置（覆蓋率分母）'); $out.Add(''); $out.Add('| 程式 | 處置 | 對應項目 |'); $out.Add('|---|---|---|')
        foreach ($pd in @($d['programDispositions'])) {
            if ($null -eq $pd) { continue }
            $its = @($pd['items']) -join '、'; if (-not $its) { $its = '—' }
            $note = ''; if ($pd.Contains('note')) { $note = '；' + $pd['note'] }
            $out.Add('| ' + (Get-PsSdLink $Rc ([string]$pd['program'])) + ' | ' + (@($pd['kinds']) -join '、') + ' | ' + (ConvertTo-PsSdCell ($its + $note)) + ' |')
        }
        $out.Add('')
    }
    if ($Doc -eq '17-tasks') {
        $out.Add('## 建議順序'); $out.Add(''); $out.Add('| 順序 | 工作 | 依賴 |'); $out.Add('|---|---|---|')
        $keyed = [System.Collections.Generic.List[string]]::new(); $tm = New-PsSdMap
        foreach ($t in $items) { $k = ([int]$t['order']).ToString('D6', [System.Globalization.CultureInfo]::InvariantCulture) + [char]0 + [string]$t['id']; $keyed.Add($k); $tm[$k] = $t }
        $keyed.Sort([System.StringComparer]::Ordinal)
        foreach ($k in $keyed) { $t = $tm[$k]; $dp = @($t['dependsOn']) -join '、'; if (-not $dp) { $dp = '—' }; $out.Add('| ' + $t['order'] + ' | ' + $t['id'] + ' ' + (ConvertTo-PsSdCell ([string]$t['name'])) + ' | ' + $dp + ' |') }
        $out.Add('')
    }
    if ($Doc -eq '90-questions') {
        $s = $d['suppressed']
        $codes = @(); foreach ($x in @($s['definitionOnlyCodes'])) { if ($null -ne $x) { $codes += ([string]$x['entityKey'] + '=' + $x['code']) } }
        $out.Add('只存在於值域定義、沒有資料也沒有核心程式使用的狀態碼：' + $s['definitionOnlyCount'] + ' 個（' + ($codes -join '、') + '），只計數、不列題。'); $out.Add('')
    }
    foreach ($p in $script:PsSdDocPrefixes[$Doc]) {
        $out.Add('## ' + $script:PsSdSectionTitle[$p] + '（' + $p + '）'); $out.Add('')
        $mine = @(); foreach ($it in $items) { if (([string]$it['id']).StartsWith($p + '-')) { $mine += , $it } }
        if ($mine.Count -eq 0) { $out.Add('（無）'); $out.Add(''); continue }
        foreach ($it in $mine) { foreach ($l in (ConvertTo-PsSdItemMarkdown $Rc $it)) { $out.Add($l) } }
    }
    return (([string]::Join("`n", $out.ToArray())).TrimEnd() + "`n")
}

function ConvertTo-PsSdIndexMarkdown {
    # $Info：JobId、Revision、Phase、Components、Violations（@{Doc;Layer;Code;Message}）、Warnings、Problems（輸入問題）、DocHashes（文件 → docHash）
    param($Rc, $Info)
    $out = [System.Collections.Generic.List[string]]::new()
    $comps = @($Info.Components) -join '、'
    $out.Add('# 00 索引'); $out.Add('')
    $out.Add('> `' + $Info.JobId + '`｜版本 ' + $Info.Revision + '｜整體狀態 **' + $Info.Phase + '**｜Component：' + $comps)
    $out.Add('> 本檔由外環產生，是閱讀入口；規格內容以各文件為準。'); $out.Add('')
    foreach ($l in @('## 閱讀順序', '', '1. 16 AI 實作指引（怎麼讀、什麼不能做）', '2. 01 專案概覽 → 04 流程與狀態機 → 02 功能需求',
            '3. 07 資料設計 → 03 角色與權限 → 05 畫面與互動 → 09 業務邏輯 → 06 系統架構 → 08 操作契約', '4. 14 測試與驗收 → 17 工作拆解 → 18 完成定義',
            '5. 19 決策紀錄、90 問題清單（實作前確認沒有影響自己工作的未解問題）', '', '## 文件與檢核', '',
            '| 文件 | 狀態 | L1 | L2 | L3 | L4 | L5 | docHash 前 12 碼 | 摘要 |', '|---|---|---|---|---|---|---|---|---|')) { $out.Add($l) }
    foreach ($doc in $script:PsSdDocOrder) {
        if (-not $Rc.Docs.ContainsKey($doc)) { continue }
        $d = $Rc.Docs[$doc]; $g = $d['gate']
        $h = ''; if ($null -ne $Info.DocHashes -and $Info.DocHashes.ContainsKey($doc)) { $h = ([string]$Info.DocHashes[$doc]).Substring(0, 12) }
        $out.Add('| [' + $d['title'] + '](' + $doc + '.md) | ' + $d['status'] + ' | ' + $g['L1'] + ' | ' + $g['L2'] + ' | ' + $g['L3'] + ' | ' + $g['L4'] + ' | ' + $g['L5'] + ' | `' + $h + '` | ' + (ConvertTo-PsSdCell ([string]$d['summary'])) + ' |')
    }
    $out.Add(''); $out.Add('## 未通過的檢核'); $out.Add('')
    $groups = [ordered]@{}
    foreach ($v in @($Info.Violations)) { if ($null -eq $v) { continue }; $k = $v.Doc + '/' + $v.Layer; if (-not $groups.Contains($k)) { $groups[$k] = [System.Collections.Generic.List[string]]::new() }; $groups[$k].Add($v.Code + ' ' + $v.Message) }
    if ($groups.Count -eq 0) { $out.Add('- 無') } else { foreach ($k in $groups.Keys) { $out.Add('- ' + $k + '：' + ($groups[$k] -join '；')) } }
    if (@($Info.Warnings).Count -gt 0) { $out.Add(''); $out.Add('## 警告（不擋，交覆核）'); $out.Add(''); foreach ($w in $Info.Warnings) { $out.Add('- ' + $w.Code + ' ' + $w.Message) } }
    if (@($Info.Problems).Count -gt 0) { $out.Add(''); $out.Add('## 輸入檔與收據的問題'); $out.Add(''); foreach ($p in $Info.Problems) { $out.Add('- ' + $p) } }
    if ($null -ne $Info.L5) {
        $out.Add(''); $out.Add('## 乾淨讀者（L5）'); $out.Add('')
        $out.Add('- 三位只看本組文件的讀者回答外環由規格出的題目，多數決比對標準答案；第 1 輪沒讀懂的項目交原研究單元改寫後由新讀者重問一次。')
        $out.Add('- 可出題的文件：' + ((@($Info.L5.Eligible) | ForEach-Object { $script:PsSdDocTitles[[string]$_] }) -join '、'))
        $out.Add('- 題目 ' + $Info.L5.Asked + '；通過 ' + $Info.L5.Passed + '；兩輪仍沒讀懂 ' + $Info.L5.Failed + '（90 的 READER_* 問題）')
    }
    $out.Add(''); $out.Add('## ID 前綴對照'); $out.Add(''); $out.Add('| 前綴 | 項目 | 定義所在 |'); $out.Add('|---|---|---|')
    foreach ($p in $script:PsSdPrefixInfo.Keys) { $pi = $script:PsSdPrefixInfo[$p]; $out.Add('| `' + $p + '` | ' + $pi.Name + ' | [' + $script:PsSdDocTitles[$pi.Doc] + '](' + $pi.Doc + '.md) |') }
    $out.Add(''); $out.Add('## 追溯矩陣（以功能為列，外環反查產生）'); $out.Add('')
    $out.Add('| 功能 | 轉移 | 情境 | 元件 | 規則 | 操作 | 測試 | 工作 |'); $out.Add('|---|---|---|---|---|---|---|---|')
    $flows = @(); foreach ($it in $Rc.Model.Items['FLOW']) { $flows += , $it }
    foreach ($fr in $Rc.Model.Items['FR']) {
        $frid = [string]$fr['id']
        $trn = Get-PsSdSortedIds @($fr['realizes'])
        $fl = @(); foreach ($f in $flows) { if ($f['steps'] -is [System.Collections.IList]) { foreach ($s in $f['steps']) { if ($trn -ccontains [string]$s['transition']) { $fl += [string]$f['id'] } } } }
        $fl = Get-PsSdSortedIds $fl
        $rv = @(); if ($Rc.Reverse.ContainsKey($frid)) { $rv = @($Rc.Reverse[$frid]) }
        $ui = @(); $br = @(); $op = @(); $tc = @(); $tk = @()
        foreach ($x in $rv) {
            if ($x.StartsWith('UI-') -and [string]$Rc.ById[$x]['uiKind'] -ceq 'CONTROL') { $ui += $x } elseif ($x.StartsWith('BR-')) { $br += $x } elseif ($x.StartsWith('OP-')) { $op += $x } elseif ($x.StartsWith('TC-')) { $tc += $x } elseif ($x.StartsWith('TASK-')) { $tk += $x }
        }
        $cells = @(); foreach ($grp in @($trn, $fl, (Get-PsSdSortedIds $ui), (Get-PsSdSortedIds $br), (Get-PsSdSortedIds $op), (Get-PsSdSortedIds $tc), (Get-PsSdSortedIds $tk))) { $j = @($grp) -join '、'; if (-not $j) { $j = '—' }; $cells += $j }
        $out.Add('| ' + $frid + ' ' + (ConvertTo-PsSdCell ([string]$fr['name'])) + ' | ' + ($cells -join ' | ') + ' |')
    }
    $qs = @(); foreach ($q in $Rc.Model.Items['Q']) { $qs += , $q }
    $cnt = { param([scriptblock]$Pred); $n = 0; foreach ($q in $qs) { if (& $Pred $q) { $n++ } }; return $n }
    $out.Add(''); $out.Add('## 問題摘要'); $out.Add('')
    $out.Add('- BLOCKING 未解：' + (& $cnt { param($q) [string]$q['severity'] -ceq 'BLOCKING' -and [string]$q['status'] -ceq 'OPEN' }))
    $out.Add('- 資訊類未解：' + (& $cnt { param($q) [string]$q['severity'] -ceq 'INFO' -and [string]$q['status'] -ceq 'OPEN' }) + '（圖外 HIGH ' + (& $cnt { param($q) [string]$q['grade'] -ceq 'HIGH' -and [string]$q['status'] -ceq 'OPEN' }) + '、LOW ' + (& $cnt { param($q) [string]$q['grade'] -ceq 'LOW' -and [string]$q['status'] -ceq 'OPEN' }) + '；原生未使用分支 ' + (& $cnt { param($q) [string]$q['category'] -ceq 'NATIVE_UNUSED_BRANCH' -and [string]$q['status'] -ceq 'OPEN' }) + '）')
    $out.Add('- 已回答：' + (& $cnt { param($q) [string]$q['status'] -ceq 'ANSWERED' }) + '；已撤回：' + (& $cnt { param($q) [string]$q['status'] -ceq 'WITHDRAWN' }) + '；接受為缺口：' + (& $cnt { param($q) [string]$q['status'] -ceq 'ACCEPTED_AS_GAP' }))
    $out.Add('- 只計數的定義值：' + $Rc.Model.Suppressed['definitionOnlyCount'])
    $out.Add('')
    $out.Add((Get-PsSdFieldStatsLine $Rc.Model))
    $out.Add('')
    return ([string]::Join("`n", $out.ToArray()))
}

function Get-PsSdFieldStatsLine {
    # 「欄位統計」一行：範圍內 Record、已判定、判不了（依代碼）、不建置欄位。
    param($Model)
    $objs = @(); foreach ($o in $Model.Items['OBJ']) { if ([string]$o['objectType'] -ceq 'RECORD' -and [string]$o['inclusion'] -cne 'EXCLUDED') { $objs += , $o } }
    $und = New-PsSdMap; $undN = 0
    foreach ($o in $objs) { $fu = $null; if ($o.Contains('fieldUsage')) { $fu = $o['fieldUsage'] }; if ($fu -is [System.Collections.IDictionary] -and $fu.Contains('undetermined')) { $c = [string]$fu['undetermined']['code']; if ($und.ContainsKey($c)) { $und[$c]++ } else { $und[$c] = 1 }; $undN++ } }
    $xfN = 0; foreach ($x in $Model.Items['XF']) { $xfN += @($x['fields']).Count }
    $line = '欄位統計：範圍內 Record ' + $objs.Count + '；已判定 ' + ($objs.Count - $undN) + '；判不了 ' + $undN
    if ($undN -gt 0) { $parts = @(); foreach ($k in (Get-PsSdSortedKeys $und)) { $parts += ($k + ' ' + $und[$k]) }; $line += '（' + ($parts -join '、') + '）' }
    $line += '；不建置欄位 ' + $xfN + '（' + $Model.Items['XF'].Count + ' 個 Record）'
    return $line
}

function ConvertTo-PsSdMarkdownSet {
    # 回傳 OrderedDictionary：檔名 → 內容（00-index.md 與 15 份）。$Info 見 ConvertTo-PsSdIndexMarkdown；另可帶 SchemaReg（欄位說明取自 schema）。
    param($Model, $Envelopes, $Info)
    $sreg = $null; if ($Info.ContainsKey('SchemaReg')) { $sreg = $Info.SchemaReg }
    $rc = New-PsSdRenderContext $Model $Envelopes $sreg
    $ii = @{ JobId = $Info.JobId; Revision = $Info.Revision; Phase = $Info.Phase; Components = $Info.Components; Violations = $Info.Violations; Warnings = $Info.Warnings; Problems = $Info.Problems; DocHashes = $Info.DocHashes; L5 = $Info.L5 }
    if ($null -eq $ii.Components) { $ii.Components = @($Envelopes['01-overview']['components']) }
    $set = [ordered]@{}
    $set['00-index.md'] = ConvertTo-PsSdIndexMarkdown $rc $ii
    foreach ($doc in $script:PsSdDocOrder) { if ($Envelopes.ContainsKey($doc)) { $set[$doc + '.md'] = ConvertTo-PsSdDocMarkdown $rc $doc } }
    return $set
}
