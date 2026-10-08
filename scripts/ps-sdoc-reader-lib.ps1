# ps-sdoc-reader-lib.ps1 — Spec 文件流程的 L5 乾淨讀者：由 canonical 確定性出題、驗證讀者的引用、比對答案、多數決。
# 讀者只看渲染出的 Markdown；標準答案只留在外環。題目的比對方式：IDS（ID 集合）、ORDERED（有序 ID）、KIND（代碼＋ID 集合）、TEXT（交判定 session）。
# 依賴（呼叫端先載入）：ps-sdoc-schema-lib.ps1、ps-sdoc-lib.ps1。PS 5.1 相容。

$script:PsSdReaderLibVersion = '1'
# 讀者答案不比對的前綴（外環計算的文件）
$script:PsSdL5ComputedPrefixes = @('Q', 'DEC', 'TASK', 'DOD', 'AI')
# 三位讀者的視角
$script:PsSdL5Perspectives = [ordered]@{
    'R1' = '後端實作者：你要據此寫出資料表、交易與商業邏輯'
    'R2' = '畫面實作者：你要據此寫出畫面、元件的顯示與可編輯條件與操作流程'
    'R3' = '測試設計者：你要據此寫出驗收測試的前置資料、步驟與預期結果'
}
# 題目定義：題號 → @{ Prefix; Mode; Text（題目）; Ask（ids／kind 要填什麼） }
$script:PsSdL5QDefs = [ordered]@{
    'T1' = @{ Prefix = 'TRN'; Mode = 'IDS'; Text = '誰能觸發這個轉移？資格怎麼判定、資料從哪裡來？'; Ask = 'ids 列出判定操作者資格用到的所有項目 ID（角色、衍生概念、欄位、狀態、活動）；沒有限制就空陣列' }
    'T2' = @{ Prefix = 'TRN'; Mode = 'KIND'; Text = '由哪個畫面或程序、哪個動作觸發？'; Ask = 'kind 填觸發種類（USER_ACTION／BATCH／SYSTEM_EVENT／INTERFACE／COMPLETION）；ids 列出觸發所在的物件 ID' }
    'T3' = @{ Prefix = 'TRN'; Mode = 'IDS'; Text = '這個轉移的條件逐項是什麼？'; Ask = 'ids 列出轉移條件裡出現的所有項目 ID；沒有條件就空陣列' }
    'T4' = @{ Prefix = 'TRN'; Mode = 'IDS'; Text = '轉移後哪些欄位變成什麼值？'; Ask = 'ids 列出被寫入的欄位 ID，以及寫入值裡出現的項目 ID' }
    'T5' = @{ Prefix = 'TRN'; Mode = 'IDS'; Text = '哪些規則會擋下這個轉移？擋下時顯示什麼訊息？'; Ask = 'ids 列出會擋下它的規則 ID 與這些規則的訊息 ID；沒有就空陣列' }
    'T6' = @{ Prefix = 'TRN'; Mode = 'TEXT'; Text = '重複觸發或兩人同時操作時會怎樣？'; Ask = 'text 寫行為' }
    'T7' = @{ Prefix = 'TRN'; Mode = 'KIND'; Text = '什麼時候能離開這個狀態？每個子業務要到哪個狀態、一筆子資料都沒有時算不算成立、還要等哪個活動？'; Ask = 'kind 填「一筆子資料都沒有時」的判定（MET／NOT_MET；有多個逐列條件時以逗號依字母序串接）；ids 列出逐列條件的子實體、條件裡的項目與要完成的活動 ID' }
    'T8' = @{ Prefix = 'TRN'; Mode = 'KIND'; Text = '誰觸發、什麼時候觸發？自動轉移的話，系統在哪些動作之後檢查？'; Ask = 'kind 填觸發種類；ids 列出系統在其之後檢查的轉移或活動 ID（沒有就空陣列）' }
    'D1' = @{ Prefix = 'DRV'; Mode = 'IDS'; Text = '怎麼找出這個人或這個值？從哪些資料、取哪一欄？'; Ask = 'ids 列出查找用到的實體、欄位、衍生概念 ID' }
    'D2' = @{ Prefix = 'DRV'; Mode = 'KIND'; Text = '有效日怎麼取？'; Ask = 'kind 填有效日規則（例 CURRENT_ROW；多個以逗號依字母序串接；不涉及有效日填 NONE）；ids 列出套用有效日規則的實體與基準欄位 ID' }
    'D3' = @{ Prefix = 'DRV'; Mode = 'TEXT'; Text = '查不到或查到多筆時怎樣？'; Ask = 'text 寫行為' }
    'B1' = @{ Prefix = 'BR'; Mode = 'KIND'; Text = '這條規則何時觸發？'; Ask = 'kind 填觸發事件代碼（例 SAVE_EDIT、FIELD_CHANGE）；ids 列出觸發的畫面元件與轉移 ID' }
    'B2' = @{ Prefix = 'BR'; Mode = 'IDS'; Text = '條件逐項是什麼？資料從哪裡來？'; Ask = 'ids 列出條件裡出現的所有項目 ID' }
    'B3' = @{ Prefix = 'BR'; Mode = 'KIND'; Text = '結果是什麼（拒絕、警告或設值）？訊息原文是什麼？'; Ask = 'kind 填結果種類（REJECT／WARN／SET_VALUE／CLEAR_VALUE／INVOKE_INTERFACE／NOTIFY）；ids 列出訊息、被設值的欄位、介面 ID' }
    'B4' = @{ Prefix = 'BR'; Mode = 'TEXT'; Text = '空白、0、NULL、日期邊界怎麼算？'; Ask = 'text 寫邊界的處理' }
    'F1' = @{ Prefix = 'FR'; Mode = 'IDS'; Text = '誰、從哪個入口、在什麼狀態下可以做這個功能？'; Ask = 'ids 列出操作者（角色、衍生概念）、入口物件、前置條件裡的項目 ID' }
    'F2' = @{ Prefix = 'FR'; Mode = 'IDS'; Text = '做完後狀態怎麼變？'; Ask = 'ids 列出這個功能實現的轉移 ID' }
    'W1' = @{ Prefix = 'FLOW'; Mode = 'ORDERED'; Text = '這個情境的步驟順序是什麼？'; Ask = 'ids 依步驟順序列出轉移 ID' }
    'O1' = @{ Prefix = 'OP'; Mode = 'IDS'; Text = '這個操作的輸入、輸出是什麼？依序套用哪些檢核？'; Ask = 'ids 列出輸入、輸出用到的欄位與衍生概念 ID，以及套用的檢核規則 ID' }
    'O2' = @{ Prefix = 'OP'; Mode = 'TEXT'; Text = '失敗時留下什麼？併發怎麼處理？'; Ask = 'text 寫交易邊界、失敗後的殘留狀態與併發處理' }
    'U1' = @{ Prefix = 'UI'; Mode = 'IDS'; Text = '這個元件什麼時候看得到、什麼時候能改？'; Ask = 'ids 列出顯示條件與可編輯條件裡出現的所有項目 ID' }
    'P1' = @{ Prefix = 'PERM'; Mode = 'IDS'; Text = '這個權限看得到哪些資料列？'; Ask = 'ids 列出資料範圍條件裡出現的所有項目 ID' }
    'I1' = @{ Prefix = 'IF'; Mode = 'TEXT'; Text = '這個介面何時觸發？失敗與重送時怎樣？'; Ask = 'text 寫觸發時機、錯誤處理與重送行為' }
    'A1' = @{ Prefix = 'ACT'; Mode = 'KIND'; Text = '這個階段誰要做什麼？系統怎麼知道做完了？沒做完會擋住哪個轉移？'; Ask = 'kind 填落實方式（BY_TRANSITION／SYSTEM_GATE／EXPECTED_ONLY）；ids 列出負責人（角色、衍生概念）、完成條件裡的項目，以及沒做完會被擋住的轉移 ID' }
}

function Test-PsSdL5Answerable {
    # 欄位缺或是 UNRESOLVED（已是 90 的問題）就不出題。
    param($V)
    if ($null -eq $V) { return $false }
    if ($V -is [System.Collections.IDictionary] -and $V.Contains('unresolved')) { return $false }
    return $true
}

function Get-PsSdL5Refs {
    # 節點裡的規格項目 ID（去重、依出現順序；不含題目項目自己與外環計算的前綴）。
    param($Node, [string]$Own)
    $out = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Node) { return , $out.ToArray() }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $refs = Get-PsSdItemRefs $Node
    foreach ($r in $refs) {
        if ($r -ceq $Own -or $script:PsSdL5ComputedPrefixes -ccontains (Get-PsSdIdPrefix $r)) { continue }
        if ($seen.Add($r)) { $out.Add($r) }
    }
    return , $out.ToArray()
}

function Get-PsSdL5Text {
    # 標準答案的文字：字串原樣；NA 寫「不適用：理由」；物件與陣列串接其中的文字。
    param($V)
    if ($null -eq $V) { return '' }
    if ($V -is [string]) { return $V }
    if ($V -is [System.Collections.IDictionary] -and $V.Contains('na')) { return ('不適用：' + [string]$V['na']) }
    $parts = Get-PsSdStringsOf $V
    $keep = @(); foreach ($p in $parts) { if (-not $script:PsSdRefRx.IsMatch($p) -and $p -notmatch '^EV-\d+$') { $keep += $p } }
    return ($keep -join '；')
}

function Get-PsSdL5Label {
    param($Item)
    $id = [string]$Item['id']
    $name = ''
    foreach ($k in @('name', 'label', 'title')) { if ($Item.Contains($k) -and $Item[$k] -is [string]) { $name = [string]$Item[$k]; break } }
    if ($name -eq '') { $name = [string]$Item['key'] }
    return ($id + '（' + $name + '）')
}

function Get-PsSdL5Questions {
    # 由組裝結果出題。$Docs：可以出題的文件（L1～L4 都通過）。回傳物件陣列（鍵 id、item、q、doc、prompt、mode、ask、ids、kind、text；
    # 與工單 JSON 同形，一律以索引取值），依項目 ID 與題號排序。
    param($Model, [string[]]$Docs)
    $out = [System.Collections.Generic.List[object]]::new()
    $docOk = @{}; foreach ($d in $Docs) { $docOk[$d] = $true }
    $add = {
        param($Target, [string]$Code, $RefIds, [string]$KindValue, [string]$TextValue)
        $def = $script:PsSdL5QDefs[$Code]
        $o = New-PsSdObject
        $o['id'] = [string]$Target['id'] + '/' + $Code; $o['item'] = [string]$Target['id']; $o['q'] = $Code; $o['doc'] = $script:PsSdPrefixInfo[$def.Prefix].Doc
        $o['prompt'] = (Get-PsSdL5Label $Target) + '：' + $def.Text; $o['mode'] = $def.Mode; $o['ask'] = $def.Ask
        $expIds = @(); foreach ($x in @($RefIds)) { if ($null -ne $x) { $expIds += [string]$x } }
        $o['ids'] = $expIds; $o['kind'] = $KindValue; $o['text'] = $TextValue
        $out.Add($o)
    }
    $items = $Model.Items
    # 反查：轉移 → 會擋下它的規則（規則觸發點指向該轉移，或該轉移所屬操作的檢核清單）；活動 → 等它完成的守門轉移
    $blockers = @{}
    foreach ($br in $items['BR']) {
        if ([string]$br['action']['kind'] -cne 'REJECT') { continue }
        foreach ($t in @($br['trigger']['transitions'])) { if ($null -ne $t) { if (-not $blockers.ContainsKey([string]$t)) { $blockers[[string]$t] = [System.Collections.Generic.List[string]]::new() }; $blockers[[string]$t].Add([string]$br['id']) } }
    }
    foreach ($op in $items['OP']) {
        $trs = @(); if ($op['effects'] -is [System.Collections.IDictionary]) { $trs = @($op['effects']['transitions']) }
        foreach ($t in $trs) {
            if ($null -eq $t) { continue }
            foreach ($v in @($op['validations'])) {
                if ($null -eq $v -or -not $Model.ById.Contains([string]$v)) { continue }
                if ([string]$Model.ById[[string]$v]['action']['kind'] -cne 'REJECT') { continue }
                if (-not $blockers.ContainsKey([string]$t)) { $blockers[[string]$t] = [System.Collections.Generic.List[string]]::new() }
                $blockers[[string]$t].Add([string]$v)
            }
        }
    }
    $gated = @{}
    foreach ($trn in $items['TRN']) {
        foreach ($c in (Get-PsSdConds $trn['guard'])) {
            if ($c -is [System.Collections.IDictionary] -and $c.Contains('left') -and $c['left'] -is [System.Collections.IDictionary] -and $c['left'].Contains('act') -and [string]$c['op'] -ceq 'DONE') {
                $a = [string]$c['left']['act']
                if (-not $gated.ContainsKey($a)) { $gated[$a] = [System.Collections.Generic.List[string]]::new() }
                $gated[$a].Add([string]$trn['id'])
            }
        }
    }
    if ($docOk.ContainsKey('04-workflow')) {
        foreach ($t in $items['TRN']) {
            $id = [string]$t['id']
            if (Test-PsSdL5Answerable $t['actor']) { & $add $t 'T1' (Get-PsSdL5Refs $t['actor'] $id) '' '' }
            if (Test-PsSdL5Answerable $t['trigger']) { & $add $t 'T2' (Get-PsSdL5Refs $t['trigger']['object'] $id) ([string]$t['trigger']['kind']) '' }
            if (Test-PsSdL5Answerable $t['guard']) { & $add $t 'T3' (Get-PsSdL5Refs $t['guard'] $id) '' '' }
            if (Test-PsSdL5Answerable $t['writes']) { & $add $t 'T4' (Get-PsSdL5Refs $t['writes'] $id) '' '' }
            $bl = @(); if ($blockers.ContainsKey($id)) { foreach ($b in $blockers[$id]) { $bl += $b; $msg = $Model.ById[$b]['action']['message']; if ($null -ne $msg) { $bl += [string]$msg } } }
            & $add $t 'T5' (Get-PsSdL5Refs $bl $id) '' ''
            if (Test-PsSdL5Answerable $t['reentry']) {
                $txt = Get-PsSdL5Text $t['reentry']
                foreach ($op in $items['OP']) { if ($op['effects'] -is [System.Collections.IDictionary] -and @($op['effects']['transitions']) -ccontains $id -and $op['transaction'] -is [System.Collections.IDictionary] -and $op['transaction'].Contains('concurrency')) { $txt += '；' + (Get-PsSdL5Text $op['transaction']['concurrency']) } }
                & $add $t 'T6' @() '' $txt
            }
            if ([string]$t['exitMode'] -ceq 'ON_COMPLETION' -and (Test-PsSdL5Answerable $t['guard'])) {
                $we = [System.Collections.Generic.List[string]]::new(); $gids = @()
                foreach ($c in (Get-PsSdConds $t['guard'])) {
                    if ($c -is [System.Collections.IDictionary] -and $c.Contains('rows')) { if ($c.Contains('whenEmpty') -and -not $we.Contains([string]$c['whenEmpty'])) { $we.Add([string]$c['whenEmpty']) }; $rowRefs = Get-PsSdL5Refs $c $id; $gids += $rowRefs }
                    elseif ($c -is [System.Collections.IDictionary] -and $c.Contains('left') -and $c['left'] -is [System.Collections.IDictionary] -and $c['left'].Contains('act')) { $gids += [string]$c['left']['act'] }
                }
                $we.Sort([System.StringComparer]::Ordinal)
                & $add $t 'T7' (Get-PsSdL5Refs $gids $id) ($we.ToArray() -join ',') ''
                if (Test-PsSdL5Answerable $t['trigger']) { & $add $t 'T8' (Get-PsSdL5Refs $t['trigger']['evaluatedAfter'] $id) ([string]$t['trigger']['kind']) '' }
            }
        }
        foreach ($f in $items['FLOW']) {
            $steps = [System.Collections.Generic.List[object]]::new(); foreach ($s in @($f['steps'])) { if ($null -ne $s) { $steps.Add($s) } }
            $ord = @(); foreach ($s in ($steps | Sort-Object { [int]$_['seq'] })) { $ord += [string]$s['transition'] }
            & $add $f 'W1' $ord '' ''
        }
        foreach ($a in $items['ACT']) {
            $id = [string]$a['id']
            if (-not (Test-PsSdL5Answerable $a['enforcement'])) { continue }
            $actRefs = Get-PsSdL5Refs @($a['actors'], $a['completion']) $id
            $allRefs = @($actRefs); if ($gated.ContainsKey($id)) { $allRefs += @($gated[$id]) }
            & $add $a 'A1' (Get-PsSdL5Refs $allRefs $id) ([string]$a['enforcement']) ''
        }
    }
    if ($docOk.ContainsKey('07-database')) {
        foreach ($d in $items['DRV']) {
            $id = [string]$d['id']
            & $add $d 'D1' (Get-PsSdL5Refs @($d['resolution'], $d['inputs']) $id) '' ''
            $rules = [System.Collections.Generic.List[string]]::new(); $ed = $null
            if ($d['resolution'] -is [System.Collections.IDictionary] -and $d['resolution'].Contains('effectiveDating')) { $ed = $d['resolution']['effectiveDating']; foreach ($e in @($ed)) { if ($null -ne $e -and -not $rules.Contains([string]$e['rule'])) { $rules.Add([string]$e['rule']) } } }
            $rules.Sort([System.StringComparer]::Ordinal)
            $edKind = 'NONE'; if ($rules.Count -gt 0) { $edKind = $rules.ToArray() -join ',' }
            & $add $d 'D2' (Get-PsSdL5Refs $ed $id) $edKind ''
            & $add $d 'D3' @() '' ((Get-PsSdL5Text $d['whenNotFound']) + '；' + (Get-PsSdL5Text $d['whenMultiple']))
        }
    }
    if ($docOk.ContainsKey('09-business-logic')) {
        foreach ($b in $items['BR']) {
            $id = [string]$b['id']
            & $add $b 'B1' (Get-PsSdL5Refs @($b['trigger']['control'], $b['trigger']['transitions']) $id) ([string]$b['trigger']['event']) ''
            if (Test-PsSdL5Answerable $b['condition']) { & $add $b 'B2' (Get-PsSdL5Refs $b['condition'] $id) '' '' }
            & $add $b 'B3' (Get-PsSdL5Refs $b['action'] $id) ([string]$b['action']['kind']) ''
            if (Test-PsSdL5Answerable $b['boundaries']) { & $add $b 'B4' @() '' (Get-PsSdL5Text $b['boundaries']) }
        }
    }
    if ($docOk.ContainsKey('02-functional-requirements')) {
        foreach ($f in $items['FR']) {
            $id = [string]$f['id']
            & $add $f 'F1' (Get-PsSdL5Refs @($f['actors'], $f['entry'], $f['preconditions']) $id) '' ''
            if ([string]$f['frKind'] -ceq 'TRANSITION') { & $add $f 'F2' (Get-PsSdL5Refs $f['realizes'] $id) '' '' }
        }
    }
    if ($docOk.ContainsKey('08-api')) {
        foreach ($o in $items['OP']) {
            $id = [string]$o['id']
            & $add $o 'O1' (Get-PsSdL5Refs @($o['inputs'], $o['outputs'], $o['validations']) $id) '' ''
            if (Test-PsSdL5Answerable $o['transaction']) { & $add $o 'O2' @() '' (Get-PsSdL5Text $o['transaction']) }
        }
    }
    if ($docOk.ContainsKey('05-ui')) {
        foreach ($u in $items['UI']) {
            if ([string]$u['uiKind'] -cne 'CONTROL') { continue }
            $vis = $u['visibility']; $edt = $u['editability']
            if (-not ($vis -is [System.Collections.IDictionary]) -and -not ($edt -is [System.Collections.IDictionary])) { continue }
            & $add $u 'U1' (Get-PsSdL5Refs @($vis, $edt) ([string]$u['id'])) '' ''
        }
    }
    if ($docOk.ContainsKey('03-roles-permissions')) {
        foreach ($p in $items['PERM']) { if ($p['dataScope'] -is [System.Collections.IDictionary]) { & $add $p 'P1' (Get-PsSdL5Refs $p['dataScope'] ([string]$p['id'])) '' '' } }
    }
    if ($docOk.ContainsKey('06-architecture')) {
        foreach ($f in $items['IF']) {
            $txt = @((Get-PsSdL5Text $f['trigger']), (Get-PsSdL5Text $f['errorHandling']), (Get-PsSdL5Text $f['idempotency']), (Get-PsSdL5Text $f['retry'])) -join '；'
            & $add $f 'I1' @() '' $txt
        }
    }
    # 依項目 ID（前綴內依編號）與題號排序
    $keyed = [System.Collections.Generic.List[string]]::new(); $map = @{}
    foreach ($qq in $out) {
        $itemId = [string]$qq['item']
        $p = Get-PsSdIdPrefix $itemId
        $n = [int]$itemId.Substring($p.Length + 1)
        $sk = $p + [char]0 + $n.ToString('D8', [System.Globalization.CultureInfo]::InvariantCulture) + [char]0 + [string]$qq['q']
        $keyed.Add($sk); $map[$sk] = $qq
    }
    $keyed.Sort([System.StringComparer]::Ordinal)
    $sorted = @(); foreach ($k in $keyed) { $sorted += , $map[$k] }
    return , $sorted
}

function Get-PsSdL5Groups {
    # 依功能切片分組（一個 FR 與它的轉移、情境、規則、操作、畫面元件、活動一組），其餘一組；每組最多 $Size 題。回傳題目陣列的陣列。
    param($Model, [object[]]$Questions, [int]$Size = 20)
    $byItem = @{}
    foreach ($q in $Questions) { $it = [string]$q['item']; if (-not $byItem.ContainsKey($it)) { $byItem[$it] = [System.Collections.Generic.List[object]]::new() }; $byItem[$it].Add($q) }
    $taken = @{}
    $groups = [System.Collections.Generic.List[object]]::new()
    $take = {
        param($List, [string]$Id)
        if ($taken.ContainsKey($Id) -or -not $byItem.ContainsKey($Id)) { return }
        $taken[$Id] = $true
        foreach ($q in $byItem[$Id]) { $List.Add($q) }
    }
    $items = $Model.Items
    foreach ($fr in $items['FR']) {
        $g = [System.Collections.Generic.List[object]]::new()
        $fid = [string]$fr['id']
        & $take $g $fid
        $trs = @(); foreach ($t in @($fr['realizes'])) { if ($null -ne $t) { $trs += [string]$t } }
        foreach ($t in $trs) { & $take $g $t }
        foreach ($f in $items['FLOW']) { foreach ($s in @($f['steps'])) { if ($null -ne $s -and $trs -ccontains [string]$s['transition']) { & $take $g ([string]$f['id']) } } }
        foreach ($a in $items['ACT']) { $hit = $false; foreach ($t in @($a['realizedBy'])) { if ($trs -ccontains [string]$t) { $hit = $true } }; foreach ($x in @($fr['performs'])) { if ([string]$x -ceq [string]$a['id']) { $hit = $true } }; if ($hit) { & $take $g ([string]$a['id']) } }
        foreach ($b in $items['BR']) { if (@($b['appliesTo']) -ccontains $fid) { & $take $g ([string]$b['id']) } }
        foreach ($o in $items['OP']) { if ([string]$o['fr'] -ceq $fid) { & $take $g ([string]$o['id']) } }
        foreach ($u in $items['UI']) { if (@($u['usedBy']) -ccontains $fid) { & $take $g ([string]$u['id']) } }
        if ($g.Count -gt 0) { $groups.Add($g) }
    }
    $rest = [System.Collections.Generic.List[object]]::new()
    foreach ($q in $Questions) { if (-not $taken.ContainsKey([string]$q['item'])) { $rest.Add($q) } }
    if ($rest.Count -gt 0) { $groups.Add($rest) }
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($g in $groups) {
        for ($i = 0; $i -lt $g.Count; $i += $Size) {
            $chunk = @(); for ($j = $i; $j -lt [Math]::Min($i + $Size, $g.Count); $j++) { $chunk += , $g[$j] }
            $out.Add($chunk)
        }
    }
    return , $out.ToArray()
}

function Get-PsSdMdSections {
    # 渲染文件的段落：'<檔名>#<ID>' → 從該 ID 的錨點到下一個錨點或下一個二級標題的文字。
    param($Files)
    $map = New-PsSdMap
    foreach ($name in @($Files.get_Keys())) {
        $text = [string]$Files[$name]
        $ms = [regex]::Matches($text, '<a id="([A-Z]+-\d{3,})"></a>')
        for ($i = 0; $i -lt $ms.Count; $i++) {
            $start = $ms[$i].Index
            $end = $text.Length
            if ($i + 1 -lt $ms.Count) { $end = $ms[$i + 1].Index }
            $h = $text.IndexOf("`n## ", $start, [System.StringComparison]::Ordinal)
            if ($h -ge 0 -and $h -lt $end) { $end = $h }
            $map[[string]$name + '#' + $ms[$i].Groups[1].Value] = $text.Substring($start, $end - $start)
        }
    }
    return , $map
}

function Test-PsSdL5IdIn {
    param([string]$Id, [string]$Text)
    return [regex]::IsMatch($Text, '(?<![A-Za-z0-9-])' + [regex]::Escape($Id) + '(?![0-9])')
}

function Test-PsSdL5Answer {
    # 讀者的一個答案 → @{ Class（ANS／NIS／INV）; Ids; Kind; Text; Reason }。引用必須存在、答案裡的每個 ID 都要出現在引用的段落裡。
    param($Answer, $Question, $Sections)
    $res = @{ Class = 'INV'; Ids = @(); Kind = ''; Text = ''; Reason = '' }
    $status = [string]$Answer['status']
    $res.Text = [string]$Answer['text']
    if ($status -ceq 'NOT_IN_SPEC') { $res.Class = 'NIS'; return $res }
    # ID 一律大寫比對；引用正規化成「小寫檔名#大寫 ID」（容許前面帶路徑）
    $ids = [System.Collections.Generic.List[string]]::new(); $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($x in @($Answer['ids'])) { if ($null -eq $x) { continue }; $s = ([string]$x).Trim().ToUpperInvariant(); if ($s -eq '' -or $s -ceq [string]$Question['item'] -or $script:PsSdL5ComputedPrefixes -ccontains (Get-PsSdIdPrefix $s)) { continue }; if ($seen.Add($s)) { $ids.Add($s) } }
    $res.Ids = $ids.ToArray()
    $kinds = [System.Collections.Generic.List[string]]::new()
    foreach ($part in ([string]$Answer['kind']).Split(',')) { $t = $part.Trim().ToUpperInvariant(); if ($t -ne '' -and -not $kinds.Contains($t)) { $kinds.Add($t) } }
    $kinds.Sort([System.StringComparer]::Ordinal)
    $res.Kind = $kinds.ToArray() -join ','
    $cited = [System.Text.StringBuilder]::new()
    $cits = @(); foreach ($c in @($Answer['citations'])) { if ($null -ne $c -and ([string]$c).Trim() -ne '') { $cits += ([string]$c).Trim() } }
    if ($cits.Count -eq 0) { $res.Reason = '沒有引用'; return $res }
    foreach ($c in $cits) {
        $k = $c -replace '\\', '/'
        $h = $k.IndexOf('#')
        if ($h -gt 0) { $file = $k.Substring(0, $h); $file = $file.Substring($file.LastIndexOf('/') + 1); $k = $file.ToLowerInvariant() + '#' + $k.Substring($h + 1).Trim().ToUpperInvariant() }
        if (-not $Sections.ContainsKey($k)) { $res.Reason = ('引用的段落不存在：' + $c); return $res }
        [void]$cited.Append($Sections[$k]).Append("`n")
    }
    $all = $cited.ToString()
    foreach ($id in $res.Ids) { if (-not (Test-PsSdL5IdIn $id $all)) { $res.Reason = ('引用的段落裡沒有 ' + $id); return $res } }
    $res.Class = 'ANS'
    return $res
}

function Get-PsSdL5Vote {
    # 一位讀者對一題的票：MATCH／MISMATCH／NIS／INV；文字題看判定（缺判定回 PENDING）。
    param($Question, $Ans, [string]$Judge)
    if ($Ans.Class -ceq 'INV') { return 'INV' }
    if ($Ans.Class -ceq 'NIS') { return 'NIS' }
    $mode = [string]$Question['mode']
    if ($mode -ceq 'TEXT') { if ($Judge -ceq 'MATCH' -or $Judge -ceq 'MISMATCH') { return $Judge }; return 'PENDING' }
    $exp = @($Question['ids'] | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
    if ($mode -ceq 'ORDERED') { if ((@($Ans.Ids) -join '|') -ceq ($exp -join '|')) { return 'MATCH' }; return 'MISMATCH' }
    $a = Sort-PsKnOrdinal -Items @($Ans.Ids); $b = Sort-PsKnOrdinal -Items $exp
    $same = ((@($a) -join '|') -ceq (@($b) -join '|'))
    if ($mode -ceq 'KIND' -and $Ans.Kind -cne [string]$Question['kind']) { $same = $false }
    if ($same) { return 'MATCH' }
    return 'MISMATCH'
}

function Get-PsSdL5Verdict {
    # 三票 → CONSISTENT／UNDERSPECIFIED／CONTRADICTS_SOURCE／DIVERGENT。$Answers：三位讀者的 @{ Vote; Ans }。
    param($Question, [object[]]$Answers)
    $n = @{ 'MATCH' = 0; 'MISMATCH' = 0; 'NIS' = 0; 'INV' = 0 }
    foreach ($a in $Answers) { if ($n.ContainsKey($a.Vote)) { $n[$a.Vote]++ } }
    if ($n['MATCH'] -ge 2) { return 'CONSISTENT' }
    if ($n['NIS'] -ge 2) { return 'UNDERSPECIFIED' }
    $sig = {
        param($Vote)
        $sortedIds = Sort-PsKnOrdinal -Items @($Vote.Ans.Ids)
        return ([string]$Vote.Ans.Kind + [char]0 + (@($sortedIds) -join '|'))
    }
    $inv = @{}; $mis = @{}
    foreach ($a in $Answers) {
        if ($a.Vote -ceq 'INV' -and @($a.Ans.Ids).Count -gt 0) { $s = & $sig $a; if ($inv.ContainsKey($s)) { $inv[$s]++ } else { $inv[$s] = 1 } }
        if ($a.Vote -ceq 'MISMATCH' -and [string]$Question['mode'] -cne 'TEXT') { $s = & $sig $a; if ($mis.ContainsKey($s)) { $mis[$s]++ } else { $mis[$s] = 1 } }
    }
    foreach ($k in @($inv.Keys)) { if ($inv[$k] -ge 2) { return 'UNDERSPECIFIED' } }
    foreach ($k in @($mis.Keys)) { if ($mis[$k] -ge 2) { return 'CONTRADICTS_SOURCE' } }
    return 'DIVERGENT'
}

function Get-PsSdL5Category {
    param([string]$Verdict)
    switch ($Verdict) {
        'UNDERSPECIFIED' { return 'READER_UNDERSPECIFIED' }
        'CONTRADICTS_SOURCE' { return 'READER_CONTRADICTION' }
    }
    return 'READER_DIVERGENT'
}
