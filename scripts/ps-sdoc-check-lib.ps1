# ps-sdoc-check-lib.ps1 — Spec 文件流程的 L2（參照與一致性）與 L3（覆蓋）檢核，另有 S07 推測用語警告。
# 輸入是 Build-PsSdModel 的結果（Items：前綴 → 項目清單；ById：ID → 項目）。每筆結果 @{ Doc; Layer（L2／L3／W）; Code; Message }。
# 欄位是 NOT_APPLICABLE 或 UNRESOLVED 時，依賴它的檢核略過（UNRESOLVED 已經是 90 的問題）。
# 依賴：ps-sdoc-schema-lib.ps1、ps-sdoc-status-lib.ps1、ps-sdoc-lib.ps1。

$script:PsSdCheckLibVersion = '1'
$script:PsSdSpeculativeRx = [regex]'推測|猜測|應該是|大概|似乎|或許|假設|估計'

function Add-PsSdViolation {
    param($List, [string]$Doc, [string]$Layer, [string]$Code, [string]$Message)
    $List.Add(@{ Doc = $Doc; Layer = $Layer; Code = $Code; Message = $Message })
}

function Get-PsSdField {
    # 取欄位值；不存在回 $null（以 return , 保留陣列）。
    param($Item, [string]$Name)
    if ($null -eq $Item -or -not ($Item -is [System.Collections.IDictionary]) -or -not $Item.Contains($Name)) { return $null }
    return , $Item[$Name]
}

function Test-PsSdIsList {
    param($V)
    return ($null -ne $V -and $V -is [System.Collections.IList] -and -not ($V -is [string]))
}

function Get-PsSdCodesOf {
    # 運算元（state／const）代表的狀態碼集合。
    param($Operands, $ById)
    $out = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($o in $Operands) {
        if ($o -is [System.Collections.IDictionary]) {
            if ($o.Contains('state') -and $ById.ContainsKey([string]$o['state'])) { [void]$out.Add([string]$ById[[string]$o['state']]['code']) }
            elseif ($o.Contains('const')) { [void]$out.Add([string]$o['const']) }
        }
    }
    return , $out
}

function Get-PsSdBindingEntity {
    param($State, $ById)
    if ($null -eq $State -or -not $State.Contains('binding')) { return $null }
    $b = [string]$State['binding']
    if (-not $ById.ContainsKey($b)) { return $null }
    return [string]$ById[$b]['entity']
}

function Test-PsSdFinalPred {
    param($P, [string]$Bind, $Finals, $ById)
    if (-not ($P -is [System.Collections.IDictionary]) -or -not $P.Contains('left')) { return $false }
    $l = $P['left']
    if (-not ($l -is [System.Collections.IDictionary]) -or $l.Count -ne 1 -or -not $l.Contains('fld') -or [string]$l['fld'] -cne $Bind) { return $false }
    $op = [string]$P['op']
    $got = $null
    if ($op -ceq 'EQ') { $got = Get-PsSdCodesOf @($P['right']) $ById }
    elseif ($op -ceq 'IN') { $got = Get-PsSdCodesOf @($P['right']) $ById }
    else { return $false }
    if ($got.Count -ne $Finals.Count) { return $false }
    foreach ($x in $Finals) { if (-not $got.Contains($x)) { return $false } }
    return $true
}

function Get-PsSdLeftAct {
    param($C)
    if ($C -is [System.Collections.IDictionary] -and $C.Contains('left') -and $C['left'] -is [System.Collections.IDictionary] -and $C['left'].Contains('act')) { return [string]$C['left']['act'] }
    return $null
}

# ---------------- L2 ----------------
function Invoke-PsSdL2Checks {
    param($Model, $Registry)
    $v = [System.Collections.Generic.List[object]]::new()
    $items = $Model.Items; $byId = $Model.ById
    $idKeys = Get-PsSdIdKeyMap $Registry
    # R01／R03／R04：參照存在、只往上游、不引用 EXCLUDED 物件
    foreach ($p in $script:PsSdPrefixInfo.Keys) {
        $sdoc = $script:PsSdPrefixInfo[$p].Doc
        foreach ($it in $items[$p]) {
            $iid = [string]$it['id']
            $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($ref in (Get-PsSdItemRefs $it)) {
                if (-not $seen.Add($ref)) { continue }
                if (-not $byId.ContainsKey($ref)) {
                    if ($idKeys.ContainsKey($ref)) { Add-PsSdViolation $v $sdoc 'L2' 'R01' ($iid + ' 參照尚待研究（PENDING）的 ' + $ref) }
                    else { Add-PsSdViolation $v $sdoc 'L2' 'R01' ($iid + ' 參照不存在的 ' + $ref) }
                    continue
                }
                $tdoc = Get-PsSdDocOfId $ref
                if ($tdoc -cne $sdoc -and -not ((Get-PsSdRankOfId $ref) -lt $script:PsSdPrefixInfo[$p].Rank)) { Add-PsSdViolation $v $sdoc 'L2' 'R03' ($iid + ' 往下游參照 ' + $ref) }
                if ($ref.StartsWith('OBJ-') -and [string]$byId[$ref]['inclusion'] -ceq 'EXCLUDED' -and @('01-overview', '90-questions', '19-decision-log') -notcontains $sdoc) {
                    Add-PsSdViolation $v $sdoc 'L2' 'R04' ($iid + ' 參照 EXCLUDED 物件 ' + $ref)
                }
            }
        }
    }
    # R04：不建置欄位名不出現在 07、90、19 以外的正文
    $xf = [System.Collections.Generic.List[object]]::new()
    foreach ($x in $items['XF']) {
        $ent = $null; if ($byId.ContainsKey([string]$x['entity'])) { $ent = $byId[[string]$x['entity']] }
        $rec = ''; if ($null -ne $ent) { $rec = [string]$ent['key'] }
        foreach ($f in @($x['fields'])) { $xf.Add(@{ Rec = $rec; Field = [string]$f; Rx = [regex]('(?<![A-Z0-9_])' + [regex]::Escape([string]$f) + '(?![A-Z0-9_])') }) }
    }
    if ($xf.Count -gt 0) {
        foreach ($p in $script:PsSdPrefixInfo.Keys) {
            $sdoc = $script:PsSdPrefixInfo[$p].Doc
            if (@('07-database', '90-questions', '19-decision-log') -contains $sdoc) { continue }
            foreach ($it in $items[$p]) {
                $hit = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                foreach ($s in (Get-PsSdStringsOf $it)) { foreach ($z in $xf) { if ($z.Rx.IsMatch($s) -and $hit.Add($z.Rec + '.' + $z.Field)) { Add-PsSdViolation $v $sdoc 'L2' 'R04' ([string]$it['id'] + ' 正文寫到不建置欄位 ' + $z.Rec + '.' + $z.Field) } } }
            }
        }
    }
    # R06：轉移寫入狀態欄位＝目標狀態碼；經判斷節點的轉移必有守衛
    foreach ($t in $items['TRN']) {
        $to = $null; if ($byId.ContainsKey([string]$t['to'])) { $to = $byId[[string]$t['to']] }
        $w = Get-PsSdField $t 'writes'
        if ($null -ne $to -and (Test-PsSdIsList $w) -and $to.Contains('binding')) {
            $ok = $false
            foreach ($a in $w) {
                if ($a -is [System.Collections.IDictionary] -and [string]$a['field'] -ceq [string]$to['binding'] -and $a['value'] -is [System.Collections.IDictionary] -and [string]$a['value']['const'] -ceq [string]$to['code']) { $ok = $true }
            }
            if (-not $ok) { Add-PsSdViolation $v '04-workflow' 'L2' 'R06' ([string]$t['id'] + ' 未寫入狀態欄位＝' + $to['code']) }
        }
        $g = Get-PsSdField $t 'guard'
        if ($t.Contains('via') -and @($t['via']).Count -gt 0 -and $g -is [System.Collections.IDictionary] -and $g.Contains('na')) { Add-PsSdViolation $v '04-workflow' 'L2' 'R06' ([string]$t['id'] + ' 經判斷節點收合但 guard 為 NA') }
    }
    # R07：狀態碼屬於綁定欄位的值域、顯示文字一致、狀態欄位值域只列圖上代碼
    foreach ($s in $items['STATE']) {
        if (-not $s.Contains('binding') -or -not $s.Contains('code') -or -not $byId.ContainsKey([string]$s['binding'])) { continue }
        $f = $byId[[string]$s['binding']]
        $vd = Get-PsSdField $f 'valueDomain'
        if (-not ($vd -is [System.Collections.IDictionary]) -or -not $vd.Contains('xlat')) { continue }
        $xl = New-PsSdMap; foreach ($e in @($vd['xlat'])) { $xl[[string]$e['stored']] = [string]$e['label'] }
        if (-not $xl.ContainsKey([string]$s['code'])) { Add-PsSdViolation $v '04-workflow' 'L2' 'R07' ([string]$s['id'] + ' 狀態碼 ' + $s['code'] + ' 不在 ' + $f['key'] + ' 值域') }
        elseif ($s['domainLabel'] -is [string] -and [string]$s['domainLabel'] -cne $xl[[string]$s['code']]) { Add-PsSdViolation $v '04-workflow' 'L2' 'R07' ([string]$s['id'] + ' 顯示文字與值域不符') }
    }
    foreach ($f in $items['FLD']) {
        $codes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $bound = $false
        foreach ($s in $items['STATE']) { if ($s.Contains('binding') -and [string]$s['binding'] -ceq [string]$f['id']) { $bound = $true; [void]$codes.Add([string]$s['code']) } }
        $vd = Get-PsSdField $f 'valueDomain'
        if ($bound -and $vd -is [System.Collections.IDictionary] -and $vd.Contains('xlat')) {
            $extra = @(); foreach ($e in @($vd['xlat'])) { if (-not $codes.Contains([string]$e['stored'])) { $extra += [string]$e['stored'] } }
            if ($extra.Count -gt 0) { Add-PsSdViolation $v '07-database' 'L2' 'R07' ([string]$f['id'] + ' 狀態欄位值域含圖外代碼 ' + ((Get-PsSdSortedIds $extra) -join '、')) }
        }
    }
    # R05：元件選項的儲存值屬於欄位值域
    foreach ($u in $items['UI']) {
        $opts = Get-PsSdField $u 'options'
        if (-not (Test-PsSdIsList $opts) -or $opts.Count -eq 0) { continue }
        $b = Get-PsSdField $u 'binding'
        if (-not ($b -is [System.Collections.IDictionary]) -or -not $b.Contains('fld') -or -not $byId.ContainsKey([string]$b['fld'])) { continue }
        $vd = Get-PsSdField $byId[[string]$b['fld']] 'valueDomain'
        if (-not ($vd -is [System.Collections.IDictionary]) -or -not $vd.Contains('xlat')) { continue }
        $xl = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal); foreach ($e in @($vd['xlat'])) { [void]$xl.Add([string]$e['stored']) }
        $bad = @(); foreach ($o in $opts) { if (-not $xl.Contains([string]$o['stored'])) { $bad += [string]$o['stored'] } }
        if ($bad.Count -gt 0) { Add-PsSdViolation $v '05-ui' 'L2' 'R05' ([string]$u['id'] + ' 選項儲存值不在值域 ' + ($bad -join '、')) }
    }
    # R08：衍生概念對每個有效日實體都有有效日規則
    foreach ($d in $items['DRV']) {
        $res = Get-PsSdField $d 'resolution'
        if (-not ($res -is [System.Collections.IDictionary])) { continue }
        $cov = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($e in @($res['effectiveDating'])) { if ($e -is [System.Collections.IDictionary]) { [void]$cov.Add([string]$e['entity']) } }
        foreach ($src in @($res['sources'])) {
            if (-not $byId.ContainsKey([string]$src)) { continue }
            $ed = Get-PsSdField $byId[[string]$src] 'effectiveDating'
            if ($ed -is [System.Collections.IDictionary] -and [string]$ed['kind'] -cne 'NONE' -and -not $cov.Contains([string]$src)) { Add-PsSdViolation $v '07-database' 'L2' 'R08' ([string]$d['id'] + ' 來源 ' + $src + ' 有有效日但沒有有效日規則') }
        }
    }
    # R09：功能入口與其轉移的觸發物件一致
    foreach ($fr in $items['FR']) {
        $entry = Get-PsSdField $fr 'entry'
        if (-not ($entry -is [System.Collections.IDictionary])) { continue }
        foreach ($t in @($fr['realizes'])) {
            if (-not $byId.ContainsKey([string]$t)) { continue }
            $trig = Get-PsSdField $byId[[string]$t] 'trigger'
            if ($trig -is [System.Collections.IDictionary] -and $trig.Contains('object') -and [string]$trig['object'] -cne [string]$entry['object']) { Add-PsSdViolation $v '02-functional-requirements' 'L2' 'R09' ([string]$fr['id'] + ' 入口與 ' + $t + ' 觸發物件不同') }
        }
    }
    # R10：規則的觸發元件屬於規則適用的功能
    foreach ($b in $items['BR']) {
        $trig = Get-PsSdField $b 'trigger'
        if (-not ($trig -is [System.Collections.IDictionary]) -or -not $trig.Contains('control')) { continue }
        $c = [string]$trig['control']
        if (-not $byId.ContainsKey($c)) { continue }
        $hit = $false; foreach ($x in @($byId[$c]['usedBy'])) { if (@($b['appliesTo']) -ccontains [string]$x) { $hit = $true } }
        if (-not $hit) { Add-PsSdViolation $v '09-business-logic' 'L2' 'R10' ([string]$b['id'] + ' 觸發元件不屬於適用功能') }
    }
    # R11：操作的轉移屬於其功能實現的轉移
    foreach ($o in $items['OP']) {
        $eff = Get-PsSdField $o 'effects'
        if (-not ($eff -is [System.Collections.IDictionary]) -or -not $eff.Contains('transitions') -or -not $byId.ContainsKey([string]$o['fr'])) { continue }
        $real = @($byId[[string]$o['fr']]['realizes'])
        $miss = @(); foreach ($t in @($eff['transitions'])) { if ($real -cnotcontains [string]$t) { $miss += [string]$t } }
        if ($miss.Count -gt 0) { Add-PsSdViolation $v '08-api' 'L2' 'R11' ([string]$o['id'] + ' 轉移不屬於其功能 ' + ((Get-PsSdSortedIds $miss) -join '、')) }
    }
    # R12：轉移操作者條件中的角色，對觸發物件有權限設定
    $permPairs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($pm in $items['PERM']) { [void]$permPairs.Add([string]$pm['principal'] + '|' + [string]$pm['resource']) }
    foreach ($t in $items['TRN']) {
        $trig = Get-PsSdField $t 'trigger'
        if (-not ($trig -is [System.Collections.IDictionary]) -or -not $trig.Contains('object')) { continue }
        $obj = [string]$trig['object']
        $holder = New-PsSdObject; $holder['a'] = Get-PsSdField $t 'actor'
        $roles = Get-PsSdSortedIds (@((Get-PsSdItemRefs $holder) | Where-Object { $_.StartsWith('ROLE-') }))
        foreach ($ro in $roles) { if (-not $permPairs.Contains($ro + '|' + $obj)) { Add-PsSdViolation $v '04-workflow' 'L2' 'R12' ([string]$t['id'] + ' 操作者角色 ' + $ro + ' 對 ' + $obj + ' 沒有權限設定') } }
    }
    foreach ($x in (Invoke-PsSdR13 $Model)) { $v.Add($x) }
    foreach ($x in (Invoke-PsSdR14 $Model)) { $v.Add($x) }
    return , $v.ToArray()
}

function Invoke-PsSdR13 {
    # 守門轉移與狀態活動。
    param($Model)
    $v = [System.Collections.Generic.List[object]]::new()
    $items = $Model.Items; $byId = $Model.ById
    $gateActs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($a in $items['ACT']) { if ([string]$a['enforcement'] -ceq 'SYSTEM_GATE') { [void]$gateActs.Add([string]$a['id']) } }
    foreach ($p in $script:PsSdPrefixInfo.Keys) {
        foreach ($it in $items[$p]) {
            foreach ($c in (Get-PsSdConds $it)) {
                $act = Get-PsSdLeftAct $c
                if ($null -ne $act -and -not $gateActs.Contains($act)) { Add-PsSdViolation $v $script:PsSdPrefixInfo[$p].Doc 'L2' 'R13' ([string]$it['id'] + ' 以 ' + $c['op'] + ' 引用的 ' + $act + ' 不是 SYSTEM_GATE 活動') }
            }
        }
    }
    foreach ($a in $items['ACT']) {
        $rb = Get-PsSdField $a 'realizedBy'
        if (-not (Test-PsSdIsList $rb)) { continue }
        foreach ($t in $rb) { if ($byId.ContainsKey([string]$t) -and [string]$byId[[string]$t]['from'] -cne [string]$a['state']) { Add-PsSdViolation $v '04-workflow' 'L2' 'R13' ([string]$a['id'] + ' 的完成轉移 ' + $t + ' 不是從活動所在狀態出發') } }
    }
    $checkRows = {
        param([string]$Owner, $Cond, [string]$TargetEnt)
        foreach ($c in (Get-PsSdConds $Cond)) {
            if (-not $c.Contains('rows')) { continue }
            $rid = [string]$c['rows']
            $par = $null; if ($byId.ContainsKey($rid)) { $par = Get-PsSdField $byId[$rid] 'parent' }
            if (-not ($par -is [System.Collections.IDictionary]) -or [string]$par['entity'] -cne $TargetEnt) { Add-PsSdViolation $v '04-workflow' 'L2' 'R13' ($Owner + ' 的逐列條件 ' + $rid + ' 沒有以 parent 連到被判斷的實體 ' + $TargetEnt) }
        }
    }
    foreach ($t in $items['TRN']) {
        $g = Get-PsSdField $t 'guard'
        if ([string]$t['from'] -cne 'INITIAL' -and (Test-PsSdIsCond $g) -and $byId.ContainsKey([string]$t['from'])) {
            $ent = Get-PsSdBindingEntity $byId[[string]$t['from']] $byId
            if ($ent) { & $checkRows ([string]$t['id']) $g $ent }
        }
    }
    foreach ($a in $items['ACT']) {
        $cmp = Get-PsSdField $a 'completion'
        if ((Test-PsSdIsCond $cmp) -and $byId.ContainsKey([string]$a['state'])) {
            $ent = Get-PsSdBindingEntity $byId[[string]$a['state']] $byId
            if ($ent) { & $checkRows ([string]$a['id']) $cmp $ent }
        }
    }
    foreach ($t in $items['TRN']) {
        if ([string](Get-PsSdField $t 'exitMode') -cne 'ON_COMPLETION') { continue }
        $fs = $null; if ([string]$t['from'] -cne 'INITIAL' -and $byId.ContainsKey([string]$t['from'])) { $fs = $byId[[string]$t['from']] }
        $regs = Get-PsSdField $fs 'regions'
        if ($null -eq $fs -or -not (Test-PsSdIsList $regs) -or $regs.Count -eq 0) { Add-PsSdViolation $v '04-workflow' 'L2' 'R13' ([string]$t['id'] + ' 是 ON_COMPLETION，但起點沒有子業務'); continue }
        $g = Get-PsSdField $t 'guard'
        if (-not (Test-PsSdIsCond $g)) { continue }
        $cs = Get-PsSdConj $g
        foreach ($reg in $regs) {
            $finals = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($x in @($reg['finalStates'])) { if ($byId.ContainsKey([string]$x)) { [void]$finals.Add([string]$byId[[string]$x]['code']) } }
            $member = $null
            foreach ($s in $items['STATE']) { if ([string]$s['entityKey'] -ceq [string]$reg['entityKey'] -and $s.Contains('binding')) { $member = $s; break } }
            $bind = $null; $bent = $null
            if ($null -ne $member) { $bind = [string]$member['binding']; if ($byId.ContainsKey($bind)) { $bent = [string]$byId[$bind]['entity'] } }
            $ok = $false
            foreach ($c in $cs) {
                if ($c -is [System.Collections.IDictionary] -and $c.Contains('rows') -and [string]$c['rows'] -ceq $bent -and [string]$c['quantifier'] -ceq 'ALL') {
                    foreach ($p2 in (Get-PsSdConj $c['where'])) { if (Test-PsSdFinalPred $p2 $bind $finals $byId) { $ok = $true } }
                } elseif ((Test-PsSdFinalPred $c $bind $finals $byId) -and $bent -ceq (Get-PsSdBindingEntity $fs $byId)) { $ok = $true }
            }
            if (-not $ok) {
                $fl = [System.Collections.Generic.List[string]]::new($finals); $fl.Sort([System.StringComparer]::Ordinal)
                Add-PsSdViolation $v '04-workflow' 'L2' 'R13' ([string]$t['id'] + ' 的守衛沒有要求子業務 ' + $reg['entityKey'] + ' 的資料全部到終點 ' + ($fl -join '、'))
            }
        }
        foreach ($a in $items['ACT']) {
            if ([string]$a['state'] -ceq [string]$t['from'] -and [string]$a['enforcement'] -ceq 'SYSTEM_GATE') {
                $hit = $false
                foreach ($c in $cs) { if ((Get-PsSdLeftAct $c) -ceq [string]$a['id'] -and [string]$c['op'] -ceq 'DONE' -and $c['left'].Count -eq 1) { $hit = $true } }
                if (-not $hit) { Add-PsSdViolation $v '04-workflow' 'L2' 'R13' ([string]$t['id'] + ' 的守衛沒有要求守門活動 ' + $a['id'] + ' 完成') }
            }
        }
    }
    return , $v.ToArray()
}

function Invoke-PsSdR14 {
    # 原生未使用分支：本體條件不比對已證明不會出現的值；範圍外情境的證明不指向範圍內物件；09 的處置與 90 的證明互相對應。
    param($Model)
    $v = [System.Collections.Generic.List[object]]::new()
    $items = $Model.Items; $byId = $Model.ById
    $fldByKey = New-PsSdMap; foreach ($f in $items['FLD']) { $fldByKey[[string]$f['key']] = [string]$f['id'] }
    $overridden = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($d in $items['DEC']) { if ([string]$d['effect'] -ceq 'ADD_SCOPE') { foreach ($q in @($d['resolves'])) { [void]$overridden.Add([string]$q) } } }
    $qs = @(); foreach ($q in $items['Q']) { if ([string]$q['category'] -ceq 'NATIVE_UNUSED_BRANCH' -and -not $overridden.Contains([string]$q['id'])) { $qs += , $q } }
    $inScope = @(); foreach ($o in $items['OBJ']) { if ([string]$o['inclusion'] -cne 'EXCLUDED' -and @('COMPONENT', 'PAGE', 'SECONDARY_PAGE') -contains [string]$o['objectType']) { $inScope += [string]$o['objectName'] } }
    foreach ($q in $qs) {
        $pf = Get-PsSdField $q 'proof'
        if (-not ($pf -is [System.Collections.IDictionary])) { continue }
        if (@('DATA_VALUE_ABSENT', 'CONFIG_VALUE') -contains [string]$pf['kind']) {
            if (-not $fldByKey.ContainsKey([string]$pf['field'])) { continue }
            $fid = $fldByKey[[string]$pf['field']]
            $absent = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal); foreach ($x in @($pf['absentValues'])) { [void]$absent.Add([string]$x) }
            foreach ($p in $script:PsSdPrefixInfo.Keys) {
                if ($p -ceq 'AI' -or $script:PsSdPrefixInfo[$p].Rank -gt 9) { continue }
                foreach ($it in $items[$p]) {
                    foreach ($c in (Get-PsSdConds $it)) {
                        $l = $c['left']
                        if (-not ($l -is [System.Collections.IDictionary]) -or $l.Count -ne 1 -or [string]$l['fld'] -cne $fid) { continue }
                        $r = $c['right']
                        $vals = @(); if (Test-PsSdIsList $r) { $vals = @($r) } elseif ($null -ne $r) { $vals = @($r) }
                        $hit = @(); foreach ($x in $vals) { if ($x -is [System.Collections.IDictionary] -and $x.Contains('const') -and $absent.Contains([string]$x['const'])) { $hit += [string]$x['const'] } }
                        if ($hit.Count -gt 0) { Add-PsSdViolation $v $script:PsSdPrefixInfo[$p].Doc 'L2' 'R14' ([string]$it['id'] + ' 的條件比對 ' + $pf['field'] + '＝' + ((Get-PsSdSortedIds $hit) -join '、') + '，但 ' + $q['id'] + ' 已證明這個值不會出現') }
                    }
                }
            }
        } else {
            foreach ($nm in (Get-PsSdSortedIds $inScope)) {
                if ([regex]::IsMatch([string]$pf['context'], '(?<![A-Za-z0-9_])' + [regex]::Escape($nm) + '(?![A-Za-z0-9_])')) { Add-PsSdViolation $v '90-questions' 'L2' 'R14' ([string]$q['id'] + ' 以範圍外情境證明，但 ' + $nm + ' 在範圍內') }
            }
        }
    }
    $native = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($d in $Model.ProgramDispositions) { if (@($d['kinds']) -ccontains 'NATIVE_UNUSED_BRANCH' -and $byId.ContainsKey([string]$d['program'])) { [void]$native.Add([string]$byId[[string]$d['program']]['objectName']) } }
    $locs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($q in $qs) { $ob = Get-PsSdField $q 'observed'; if ($ob -is [System.Collections.IDictionary] -and $ob.Contains('location')) { [void]$locs.Add([string]$ob['location']) } }
    foreach ($l in (Get-PsSdSortedIds @($locs))) { if (-not $native.Contains($l)) { Add-PsSdViolation $v '09-business-logic' 'L2' 'R14' ($l + ' 有原生未使用分支的證明，但程式處置沒有標 NATIVE_UNUSED_BRANCH') } }
    foreach ($l in (Get-PsSdSortedIds @($native))) { if (-not $locs.Contains($l)) { Add-PsSdViolation $v '09-business-logic' 'L2' 'R14' ($l + ' 標了 NATIVE_UNUSED_BRANCH，但 90 沒有對應的證明') } }
    return , $v.ToArray()
}

# ---------------- L3 ----------------
function Invoke-PsSdC01 {
    # 04 與採用的解讀一致；STATUS 文字逐行恰好處置一次；04 記下的解讀摘要與這次比對相同。
    param($Model, $Built, [string]$StatusRef, $Summary, $RecordedSummary)
    $v = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $Built) { return , $v.ToArray() }
    $items = $Model.Items; $byId = $Model.ById
    $ents = $Built.Entities; $comps = $Built.Composites
    $sid = New-PsSdMap
    foreach ($s in $items['STATE']) { if ($s.Contains('code')) { $sid[[string]$s['entityKey'] + '|' + [string]$s['code']] = [string]$s['id'] } }
    $codeOf = {
        param([string]$Ref)
        if ($Ref -ceq 'INITIAL') { return '*' }
        if ($byId.ContainsKey($Ref)) { return [string]$byId[$Ref]['code'] }
        return '?'
    }
    $allE = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($p in @('STATE', 'TRN', 'FLOW')) { foreach ($x in $items[$p]) { [void]$allE.Add([string]$x['entityKey']) } }
    foreach ($e in (Get-PsSdSortedIds @($allE))) { if (-not $ents.ContainsKey($e)) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ('狀態實體 ' + $e + ' 不在採用的解讀裡') } }
    foreach ($ek in (Get-PsSdSortedKeys $ents)) {
        $pr = $ents[$ek]
        $mine = @(); foreach ($s in $items['STATE']) { if ([string]$s['entityKey'] -ceq $ek -and $s.Contains('code')) { $mine += , $s } }
        $got = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal); foreach ($s in $mine) { [void]$got.Add([string]$s['code']) }
        $more = @(); foreach ($c in $got) { if (-not $pr.Codes.Contains($c)) { $more += $c } }
        $less = @(); foreach ($c in $pr.Codes) { if (-not $got.Contains($c)) { $less += $c } }
        if ($more.Count -gt 0 -or $less.Count -gt 0) {
            $msg = @(); if ($more.Count -gt 0) { $msg += ('多 ' + ((Get-PsSdSortedIds $more) -join '、')) }; if ($less.Count -gt 0) { $msg += ('少 ' + ((Get-PsSdSortedIds $less) -join '、')) }
            Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ($ek + ' 的 STATE 與解讀的狀態碼不符：' + ($msg -join '；'))
        }
        $pairs = New-PsSdMap
        foreach ($t in $items['TRN']) { if ([string]$t['entityKey'] -ceq $ek) { $pairs[(& $codeOf ([string]$t['from'])) + '>' + (& $codeOf ([string]$t['to']))] = $t } }
        $more = @(); foreach ($k in $pairs.Keys) { if (-not $pr.Pairs.Contains($k)) { $more += $k } }
        $less = @(); foreach ($k in $pr.Pairs) { if (-not $pairs.ContainsKey($k)) { $less += $k } }
        if ($more.Count -gt 0 -or $less.Count -gt 0) {
            $msg = @(); if ($more.Count -gt 0) { $msg += ('多 ' + ((Get-PsSdSortedIds $more) -join '、')) }; if ($less.Count -gt 0) { $msg += ('少 ' + ((Get-PsSdSortedIds $less) -join '、')) }
            Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ($ek + ' 的 TRN 與解讀的轉移不符：' + ($msg -join '；'))
        }
        foreach ($k in (Get-PsSdSortedKeys $pairs)) {
            $t = $pairs[$k]
            $via = @(); if ($t.Contains('via')) { $via = @($t['via']) }
            $want = @(); if ($pr.Via.ContainsKey($k)) { $want = @($pr.Via[$k]) }
            if (($via -join [char]0) -cne ($want -join [char]0)) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ([string]$t['id'] + ' via 與解讀不符') }
            $labs = @(); if ($t.Contains('diagramLabels')) { $labs = @($t['diagramLabels']) }
            $wl = @(); if ($pr.Labels.ContainsKey($k)) { $wl = @($pr.Labels[$k]) }
            if (($labs -join [char]0) -cne ($wl -join [char]0)) {
                $show = '沒有線上文字'; if ($wl.Count -gt 0) { $show = $wl -join '、' }
                Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ([string]$t['id'] + ' 的線上文字與解讀不符（解讀：' + $show + '）')
            }
        }
        foreach ($s in $mine) {
            if ([bool]$s['isFinal'] -ne $pr.Finals.Contains([string]$s['code'])) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ([string]$s['id'] + ' 終點標記與解讀不符') }
            if ([bool]$s['isInitialTarget'] -ne $pr.Initials.Contains([string]$s['code'])) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ([string]$s['id'] + ' 新建標記與解讀不符') }
        }
        $mineF = New-PsSdMap; foreach ($f in $items['FLOW']) { if ([string]$f['entityKey'] -ceq $ek) { $mineF[[string]$f['scenarioType']] = $f } }
        $diff = @(); foreach ($k in $mineF.Keys) { if (-not $pr.Scenarios.ContainsKey($k)) { $diff += $k } }; foreach ($k in $pr.Scenarios.Keys) { if (-not $mineF.ContainsKey($k)) { $diff += $k } }
        if ($diff.Count -gt 0) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ($ek + ' 的 FLOW 與情境類型不符：' + ((Get-PsSdSortedIds $diff) -join '、')) }
        foreach ($lab in (Get-PsSdSortedKeys $pr.Scenarios)) {
            if (-not $mineF.ContainsKey($lab)) { continue }
            $steps = Get-PsSdField $mineF[$lab] 'steps'
            if (-not (Test-PsSdIsList $steps)) { continue }
            $gp = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($st in $steps) { $tid = [string]$st['transition']; if ($byId.ContainsKey($tid)) { [void]$gp.Add((& $codeOf ([string]$byId[$tid]['from'])) + '>' + (& $codeOf ([string]$byId[$tid]['to']))) } }
            $same = ($gp.Count -eq $pr.Scenarios[$lab].Count); foreach ($x in $pr.Scenarios[$lab]) { if (-not $gp.Contains($x)) { $same = $false } }
            if (-not $same) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ('FLOW「' + $lab + '」步驟與解讀的情境不符') }
        }
    }
    # 主業務狀態裡的子業務
    $compIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($ck in $comps.Keys) {
        $ci = $comps[$ck]
        $k2 = $ci.Entity + '|' + $ci.Code
        if (-not $sid.ContainsKey($k2)) { continue }
        $csId = $sid[$k2]; [void]$compIds.Add($csId)
        $cs = $byId[$csId]
        $regs = @(); if ($cs.Contains('regions')) { $regs = @($cs['regions']) }
        $re = @(); foreach ($r in $regs) { $re += [string]$r['entityKey'] }
        if ([string]$cs['stateKind'] -cne 'COMPOSITE' -or ($re -join [char]0) -cne (@($ci.Regions) -join [char]0)) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ($csId + ' 的子業務與解讀不符（解讀：' + (@($ci.Regions) -join '、') + '）'); continue }
        foreach ($r in $regs) {
            $want = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            if ($ents.ContainsKey([string]$r['entityKey'])) { foreach ($x in $ents[[string]$r['entityKey']].Finals) { [void]$want.Add($x) } }
            $got = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($x in @($r['finalStates'])) { if ($byId.ContainsKey([string]$x)) { [void]$got.Add([string]$byId[[string]$x]['code']) } }
            if (-not $got.SetEquals($want)) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ($csId + ' 的子業務 ' + $r['entityKey'] + ' 的終點與解讀不符') }
            foreach ($s in $items['STATE']) { if ([string]$s['entityKey'] -ceq [string]$r['entityKey'] -and [string](Get-PsSdField $s 'parent') -cne $csId) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ([string]$s['id'] + ' 屬於 ' + $csId + ' 裡的子業務，但 parent 沒有指向它') } }
        }
        foreach ($t in $items['TRN']) { if ([string]$t['entityKey'] -ceq $ci.Entity -and [string]$t['from'] -ceq $csId -and [string](Get-PsSdField $t 'exitMode') -ceq 'NORMAL') { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ([string]$t['id'] + ' 從有子業務的 ' + $csId + ' 離開，exitMode 不得為 NORMAL') } }
    }
    foreach ($s in $items['STATE']) { if ($s.Contains('regions') -and @($s['regions']).Count -gt 0 -and -not $compIds.Contains([string]$s['id'])) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ([string]$s['id'] + ' 宣稱有子業務，但解讀裡沒有') } }
    foreach ($t in $items['TRN']) { $em = [string](Get-PsSdField $t 'exitMode'); if (@('ON_COMPLETION', 'INTERRUPT') -ccontains $em -and -not $compIds.Contains([string]$t['from'])) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ([string]$t['id'] + ' 的 exitMode 是 ' + $em + '，但起點沒有子業務') } }
    # STATUS 文字
    $byLoc = New-PsSdMap
    foreach ($d in $Model.StatusTexts) { $l = [string]$d['locator']; if (-not $byLoc.ContainsKey($l)) { $byLoc[$l] = [System.Collections.Generic.List[object]]::new() }; $byLoc[$l].Add($d) }
    foreach ($l in (Get-PsSdSortedKeys $byLoc)) { if ($byLoc[$l].Count -gt 1) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ('STATUS 文字 ' + $l + ' 重複處置') } }
    $enum = New-PsSdMap
    foreach ($t in $Built.Texts) { $enum[$StatusRef + '#L' + $t.Line] = $t }
    foreach ($t in $Built.Texts) {
        $loc = $StatusRef + '#L' + $t.Line
        if (-not $byLoc.ContainsKey($loc)) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ('STATUS 文字 ' + $loc + '「' + $t.Text + '」沒有處置'); continue }
        $d = $byLoc[$loc][0]
        if ([string]$d['text'] -cne $t.Text) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ($loc + ' 的處置文字與原文不同') }
        foreach ($iid in @($d['items'])) {
            if ($null -eq $iid) { continue }
            if (-not $byId.ContainsKey([string]$iid)) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ($loc + ' 的處置指向不存在的 ' + $iid) }
            elseif (([string]$iid).StartsWith('ACT-') -and $t.Kind -eq 'text' -and $t.Code) {
                $want = $null; if ($sid.ContainsKey([string]$t.EntityKey + '|' + [string]$t.Code)) { $want = $sid[[string]$t.EntityKey + '|' + [string]$t.Code] }
                if ([string]$byId[[string]$iid]['state'] -cne [string]$want) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ($iid + ' 的所在狀態與 ' + $loc + ' 描述的狀態不符') }
            }
        }
    }
    foreach ($l in (Get-PsSdSortedKeys $byLoc)) { if (-not $enum.ContainsKey($l)) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ($l + ' 不是 STATUS 檔的說明文字或狀態描述') } }
    foreach ($a in $items['ACT']) {
        $entries = @(); foreach ($d in $Model.StatusTexts) { if (@($d['items']) -ccontains [string]$a['id']) { $entries += , $d } }
        if ($entries.Count -eq 0) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ([string]$a['id'] + ' 沒有對應的 STATUS 文字'); continue }
        $hit = $false; foreach ($d in $entries) { if (([string]$d['text']).Contains([string]$a['behavior'])) { $hit = $true } }
        if (-not $hit) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' ([string]$a['id'] + ' 的 behavior 不是對應那一行的原文') }
    }
    if ($null -ne $RecordedSummary -and -not (Test-PsSdSameNode $RecordedSummary $Summary)) { Add-PsSdViolation $v '04-workflow' 'L3' 'C01' '04 記下的狀態圖解讀摘要與這次比對的結果不同' }
    return , $v.ToArray()
}

function Test-PsSdHasCompare {
    param($Cond)
    foreach ($c in (Get-PsSdConds $Cond)) { if (@('GT', 'GE', 'LT', 'LE', 'BETWEEN') -ccontains [string]$c['op']) { return $true } }
    return $false
}

function Invoke-PsSdL3Checks {
    param($Model, $Built, [string]$StatusRef, $Summary)
    $v = [System.Collections.Generic.List[object]]::new()
    $items = $Model.Items; $byId = $Model.ById
    foreach ($x in (Invoke-PsSdC01 $Model $Built $StatusRef $Summary $null)) { $v.Add($x) }
    $frOfTrn = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($fr in $items['FR']) { foreach ($t in @($fr['realizes'])) { if ($null -ne $t) { [void]$frOfTrn.Add([string]$t) } } }
    $ifPerf = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($i in $items['IF']) { foreach ($t in @($i['performs'])) { if ($null -ne $t) { [void]$ifPerf.Add([string]$t) } } }
    # C02
    foreach ($t in $items['TRN']) {
        $trig = Get-PsSdField $t 'trigger'
        $auto = $false
        if ($trig -is [System.Collections.IDictionary]) {
            if ([string]$trig['kind'] -ceq 'COMPLETION') { $auto = $true }
            if ([string]$trig['kind'] -ceq 'SYSTEM_EVENT' -and $trig.Contains('evaluatedAfter') -and @($trig['evaluatedAfter']).Count -gt 0) { $auto = $true }
        }
        if (-not $frOfTrn.Contains([string]$t['id']) -and -not $ifPerf.Contains([string]$t['id']) -and -not $auto) { Add-PsSdViolation $v '02-functional-requirements' 'L3' 'C02' ([string]$t['id'] + ' 沒有功能實現') }
        if ((Get-PsSdField $t 'implementedAt') -is [System.Collections.IDictionary]) { Add-PsSdViolation $v '04-workflow' 'L3' 'C02' ([string]$t['id'] + ' 找不到實作') }
    }
    $performed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($fr in $items['FR']) { foreach ($a in @($fr['performs'])) { if ($null -ne $a) { [void]$performed.Add([string]$a) } } }
    foreach ($a in $items['ACT']) { if ([string]$a['enforcement'] -ceq 'SYSTEM_GATE' -and -not $performed.Contains([string]$a['id'])) { Add-PsSdViolation $v '02-functional-requirements' 'L3' 'C02' ([string]$a['id'] + ' 是守門活動，但沒有功能讓操作者完成它') } }
    # 不建置欄位
    $xfNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($x in $items['XF']) { if ($byId.ContainsKey([string]$x['entity'])) { $rec = [string]$byId[[string]$x['entity']]['key']; foreach ($f in @($x['fields'])) { [void]$xfNames.Add($rec + '.' + [string]$f) } } }
    # C03：頁面欄位都有 UI 元件
    $ctrlKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($u in $items['UI']) { if ([string]$u['uiKind'] -ceq 'CONTROL') { [void]$ctrlKeys.Add([string]$u['key']) } }
    foreach ($pg in $Model.Pages) {
        foreach ($f in $pg.Fields) {
            if ($xfNames.Contains([string]$f)) { continue }
            $k = $pg.Component + '.' + $pg.Page + '.' + $f
            if (-not $ctrlKeys.Contains($k)) { Add-PsSdViolation $v '05-ui' 'L3' 'C03' ('頁面欄位 ' + $pg.Component + '.' + $pg.Page + '.' + $f + ' 沒有 UI 項目') }
        }
    }
    # C04：Record 欄位都有 FLD
    $fldKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($f in $items['FLD']) { [void]$fldKeys.Add([string]$f['key']) }
    foreach ($rc in $Model.Records) {
        foreach ($fn in $rc.Fields) {
            $k = $rc.Record + '.' + $fn
            if ($xfNames.Contains($k)) { continue }
            if (-not $fldKeys.Contains($k)) { Add-PsSdViolation $v '07-database' 'L3' 'C04' ($k + ' 沒有 FLD 項目') }
        }
    }
    # C05：核心 PeopleCode 程式每支恰一筆處置
    $disp = New-PsSdMap
    foreach ($d in $Model.ProgramDispositions) { $k = [string]$d['program']; if ($disp.ContainsKey($k)) { $disp[$k]++ } else { $disp[$k] = 1 } }
    foreach ($o in $items['OBJ']) {
        if ([string]$o['objectType'] -cne 'PEOPLECODE' -or [string]$o['inclusion'] -ceq 'EXCLUDED') { continue }
        $n = 0; if ($disp.ContainsKey([string]$o['id'])) { $n = $disp[[string]$o['id']] }
        if ($n -ne 1) { Add-PsSdViolation $v '09-business-logic' 'L3' 'C05' ([string]$o['id'] + ' 處置筆數 ' + $n) }
    }
    # C06：Record 的排除欄數與 XF 一致
    foreach ($o in $items['OBJ']) {
        $fu = Get-PsSdField $o 'fieldUsage'
        if (-not ($fu -is [System.Collections.IDictionary]) -or -not $fu.Contains('excluded')) { continue }
        $ent = $null; foreach ($e in $items['ENT']) { if ([string]$e['record'] -ceq [string]$o['id']) { $ent = $e; break } }
        $n = 0
        if ($null -ne $ent) { foreach ($x in $items['XF']) { if ([string]$x['entity'] -ceq [string]$ent['id']) { $n += @($x['fields']).Count } } }
        if ($n -ne [int]$fu['excluded']['count']) { Add-PsSdViolation $v '01-overview' 'L3' 'C06' ([string]$o['id'] + ' 排除欄數 ' + $fu['excluded']['count'] + ' 與 XF ' + $n + ' 不符') }
    }
    # C07：測試覆蓋
    $tcs = $items['TC']
    $covered = {
        param([string]$Kind, [string]$Iid, [string]$WantType)
        foreach ($t in $tcs) {
            $cv = Get-PsSdField $t 'covers'
            if (-not ($cv -is [System.Collections.IDictionary]) -or -not $cv.Contains($Kind)) { continue }
            if (@($cv[$Kind]) -ccontains $Iid -and ($WantType -eq '' -or [string]$t['scenarioType'] -ceq $WantType)) { return $true }
        }
        return $false
    }
    foreach ($fr in $items['FR']) {
        $ok = $false; foreach ($t in $tcs) { if ([string]$t['fr'] -ceq [string]$fr['id'] -and [string]$t['scenarioType'] -ceq 'POSITIVE') { $ok = $true } }
        if (-not $ok) { Add-PsSdViolation $v '14-testing' 'L3' 'C07' ([string]$fr['id'] + ' 沒有正例') }
    }
    foreach ($b in $items['BR']) {
        $act = Get-PsSdField $b 'action'
        if ($act -is [System.Collections.IDictionary] -and [string]$act['kind'] -ceq 'REJECT' -and -not (& $covered 'rules' ([string]$b['id']) 'NEGATIVE')) { Add-PsSdViolation $v '14-testing' 'L3' 'C07' ([string]$b['id'] + ' 沒有反例') }
        if ((Test-PsSdHasCompare (Get-PsSdField $b 'condition')) -and -not (& $covered 'rules' ([string]$b['id']) 'BOUNDARY')) { Add-PsSdViolation $v '14-testing' 'L3' 'C07' ([string]$b['id'] + ' 條件含比較運算但沒有邊界案例') }
    }
    foreach ($t in $items['TRN']) {
        $tk = [string]$t['key']; $short = $tk.Substring($tk.IndexOf(':') + 1)
        if (-not (& $covered 'transitions' ([string]$t['id']) '')) { Add-PsSdViolation $v '14-testing' 'L3' 'C07' ([string]$t['id'] + '（' + $short + '）沒有測試案例') }
        if ((Test-PsSdHasCompare (Get-PsSdField $t 'guard')) -and -not (& $covered 'transitions' ([string]$t['id']) 'BOUNDARY')) { Add-PsSdViolation $v '14-testing' 'L3' 'C07' ([string]$t['id'] + ' 守衛含比較運算但沒有邊界案例') }
    }
    foreach ($f in $items['FLOW']) { if (-not (& $covered 'flows' ([string]$f['id']) '')) { Add-PsSdViolation $v '14-testing' 'L3' 'C07' ([string]$f['id'] + ' 沒有端到端案例') } }
    foreach ($t in $items['TRN']) {
        if ([string](Get-PsSdField $t 'exitMode') -cne 'ON_COMPLETION') { continue }
        foreach ($typ in @('POSITIVE', 'NEGATIVE')) { if (-not (& $covered 'transitions' ([string]$t['id']) $typ)) { Add-PsSdViolation $v '14-testing' 'L3' 'C07' ([string]$t['id'] + ' 是守門轉移，缺 ' + $typ + ' 案例') } }
        $we = $false; foreach ($c in (Get-PsSdConds (Get-PsSdField $t 'guard'))) { if ($c.Contains('whenEmpty')) { $we = $true } }
        if ($we -and -not (& $covered 'transitions' ([string]$t['id']) 'BOUNDARY')) { Add-PsSdViolation $v '14-testing' 'L3' 'C07' ([string]$t['id'] + ' 的逐列條件有 whenEmpty，缺「沒有任何一列」的 BOUNDARY 案例') }
    }
    foreach ($a in $items['ACT']) { if ([string]$a['enforcement'] -ceq 'SYSTEM_GATE' -and -not (& $covered 'activities' ([string]$a['id']) '')) { Add-PsSdViolation $v '14-testing' 'L3' 'C07' ([string]$a['id'] + ' 是守門活動，沒有測試案例') } }
    # C08：每個 FR 有操作契約；操作的檢核清單包含所有會在該操作觸發的拒絕型規則
    foreach ($fr in $items['FR']) {
        $ok = $false; foreach ($o in $items['OP']) { if ([string]$o['fr'] -ceq [string]$fr['id']) { $ok = $true } }
        if (-not $ok) { Add-PsSdViolation $v '08-api' 'L3' 'C08' ([string]$fr['id'] + ' 沒有操作契約') }
    }
    foreach ($o in $items['OP']) {
        $eff = Get-PsSdField $o 'effects'
        $trs = @(); if ($eff -is [System.Collections.IDictionary] -and $eff.Contains('transitions')) { $trs = @($eff['transitions']) }
        $vals = Get-PsSdField $o 'validations'; $vals = @($vals)
        foreach ($b in $items['BR']) {
            $act = Get-PsSdField $b 'action'
            if (-not ($act -is [System.Collections.IDictionary]) -or [string]$act['kind'] -cne 'REJECT') { continue }
            $trig = Get-PsSdField $b 'trigger'
            if (-not ($trig -is [System.Collections.IDictionary])) { continue }
            $need = $false
            foreach ($x in @($trig['transitions'])) { if ($null -ne $x -and $trs -ccontains [string]$x) { $need = $true } }
            if ([string]$trig['event'] -ceq 'SAVE_EDIT' -and @($b['appliesTo']) -ccontains [string]$o['fr'] -and @('CREATE', 'UPDATE', 'TRANSITION') -ccontains [string]$o['opKind']) { $need = $true }
            if ($need -and $vals -cnotcontains [string]$b['id']) { Add-PsSdViolation $v '08-api' 'L3' 'C08' ([string]$o['id'] + ' 漏列檢核 ' + $b['id']) }
        }
    }
    # C09：未解的 BLOCKING 問題
    foreach ($q in $items['Q']) {
        if ([string]$q['status'] -cne 'OPEN' -or [string]$q['severity'] -cne 'BLOCKING') { continue }
        $aff = @($q['affects'])
        if ($aff.Count -eq 0) { Add-PsSdViolation $v '90-questions' 'L3' 'C09' ([string]$q['id'] + ' 未解（BLOCKING）') }
        foreach ($a in $aff) { if ($null -ne $a) { $d = Get-PsSdDocOfId ([string]$a); if ($d) { Add-PsSdViolation $v $d 'L3' 'C09' ([string]$q['id'] + ' 未解（BLOCKING）影響 ' + $a) } } }
    }
    # C10：每個 FR 恰一個切片；每個工作有完成條件
    foreach ($fr in $items['FR']) {
        $n = 0; foreach ($t in $items['TASK']) { if ([string]$t['fr'] -ceq [string]$fr['id']) { $n++ } }
        if ($n -ne 1) { Add-PsSdViolation $v '17-tasks' 'L3' 'C10' ([string]$fr['id'] + ' 的工作項數 ' + $n) }
    }
    foreach ($t in $items['TASK']) {
        $ok = $false; foreach ($d in $items['DOD']) { if ([string](Get-PsSdField $d 'task') -ceq [string]$t['id']) { $ok = $true } }
        if (-not $ok) { Add-PsSdViolation $v '18-definition-of-done' 'L3' 'C10' ([string]$t['id'] + ' 沒有完成條件') }
    }
    return , $v.ToArray()
}

function Get-PsSdSpeculationWarnings {
    # S07：CONFIRMED 項目的文字出現推測用語（警告，不擋；交 L4 覆核或改開問題）。
    param($Model)
    $v = [System.Collections.Generic.List[object]]::new()
    foreach ($p in $script:PsSdPrefixInfo.Keys) {
        if (@('AI', 'TASK', 'DOD', 'Q', 'DEC') -ccontains $p) { continue }
        foreach ($it in $Model.Items[$p]) {
            if ([string]$it['certainty'] -cne 'CONFIRMED') { continue }
            foreach ($s in (Get-PsSdStringsOf $it)) {
                $m = $script:PsSdSpeculativeRx.Match($s)
                if ($m.Success) { Add-PsSdViolation $v $script:PsSdPrefixInfo[$p].Doc 'W' 'S07' ([string]$it['id'] + ' CONFIRMED 項目出現推測用語「' + $m.Value + '」（警告，交覆核）'); break }
            }
        }
    }
    return , $v.ToArray()
}
