# sdoc-test-fixtures.ps1 — 測試用：把設計範例的 canonical 文件拆回研究包（模擬各研究單位已驗收的收據）。
# 只給 scripts/tests/test-sdoc*.ps1 dot-source；合成資料，不含公司內容。

function Get-SdTestPaths {
    # 維護端 repo：Claude Code 版在 claude-code/ 子樹；部署版面（公司機、搬運包演練）在根目錄 .claude/。
    # 設計範例（預期結果）只在維護端 repo 的 docs/design，不在搬運包；HasDesign=$false 時整支測試略過。
    param([string]$Repo)
    $sd = Join-Path $Repo 'claude-code/.claude/peoplesoft/sdoc'
    if (-not [System.IO.Directory]::Exists($sd)) { $sd = Join-Path $Repo '.claude/peoplesoft/sdoc' }
    $design = Join-Path $Repo 'docs/design/spec-schema-framework'
    return @{ SdocDir = $sd; Design = $design; HasDesign = [System.IO.Directory]::Exists((Join-Path $design 'examples')) }
}

function ConvertTo-SdPacketValue {
    # canonical 的值 → 研究包的寫法：ID → '@前綴/自然鍵'；EV-xxxx → 本包的 E<n>（同時把證據加進本包）。
    param($Value, $IdToKey, $EvById, $State, [string]$ParentKey)
    if ($Value -is [string]) {
        if ($ParentKey -ceq 'evidence' -and $Value.StartsWith('EV-')) {
            if (-not $State.EvLocal.ContainsKey($Value)) {
                $n = $State.EvLocal.Count + 1
                $lid = 'E' + $n
                $State.EvLocal[$Value] = $lid
                $src = $EvById[$Value]
                $e = New-PsSdObject
                $e['id'] = $lid
                foreach ($k in @('kind', 'locator', 'excerpt', 'capturedOn')) { if ($src.Contains($k)) { $e[$k] = $src[$k] } }
                $State.Evidence.Add($e)
            }
            return $State.EvLocal[$Value]
        }
        if ($script:PsSdRefRx.IsMatch($Value) -and $IdToKey.ContainsKey($Value)) {
            $p = Get-PsSdIdPrefix $Value
            return ('@' + $p + '/' + $IdToKey[$Value])
        }
        return $Value
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $o = New-PsSdObject
        foreach ($k in @($Value.Keys)) { $o[[string]$k] = ConvertTo-SdPacketValue $Value[$k] $IdToKey $EvById $State ([string]$k) }
        return , $o
    }
    if ($Value -is [System.Collections.IList]) {
        $arr = New-Object object[] $Value.Count
        for ($i = 0; $i -lt $Value.Count; $i++) { $arr[$i] = ConvertTo-SdPacketValue $Value[$i] $IdToKey $EvById $State $ParentKey }
        return , $arr
    }
    return $Value
}

function New-SdPacket {
    param([string]$JobId, [string]$Unit, [string]$Subject, [int]$Page)
    $p = New-PsSdObject
    $p['schemaVersion'] = '1.0'; $p['jobId'] = $JobId; $p['attemptId'] = 'a0001'; $p['unit'] = $Unit; $p['subject'] = $Subject; $p['page'] = $Page
    $p['inputHash'] = ('0' * 64); $p['coverage'] = 'COMPLETE'; $p['summary'] = '合成資料：由設計範例拆回的研究包。'
    $p['items'] = @(); $p['evidence'] = @(); $p['questions'] = @(); $p['requests'] = @(); $p['nextCursor'] = ''
    return @{ Packet = $p; State = @{ EvLocal = (New-PsSdMap); Evidence = [System.Collections.Generic.List[object]]::new() }; Items = [System.Collections.Generic.List[object]]::new(); Questions = [System.Collections.Generic.List[object]]::new() }
}

function Add-SdPacketItem {
    param($Pk, $Item, $IdToKey, $EvById)
    $p = Get-PsSdIdPrefix ([string]$Item['id'])
    $o = New-PsSdObject
    $o['type'] = $p
    $o['key'] = $Item['key']
    $skip = @('id', 'key', 'lifecycle')
    if ($script:PsSdSkeletonFields.ContainsKey($p)) { $skip += $script:PsSdSkeletonFields[$p] }
    foreach ($k in @($Item.Keys)) {
        if ($skip -ccontains [string]$k) { continue }
        $o[[string]$k] = ConvertTo-SdPacketValue $Item[$k] $IdToKey $EvById $Pk.State ([string]$k)
    }
    $Pk.Items.Add($o)
}

function Add-SdPacketQuestion {
    param($Pk, $Q, $IdToKey, $EvById)
    $o = New-PsSdObject
    $cat = [string]$Q['category']
    $o['category'] = $cat
    $o['key'] = ([string]$Q['key']).Substring($cat.Length + 1)
    $o['question'] = $Q['question']
    $o['affects'] = ConvertTo-SdPacketValue $Q['affects'] $IdToKey $EvById $Pk.State 'affects'
    foreach ($k in @('grade', 'observed', 'proof', 'proposedAnswer')) { if ($Q.Contains($k)) { $o[$k] = ConvertTo-SdPacketValue $Q[$k] $IdToKey $EvById $Pk.State $k } }
    $o['evidence'] = ConvertTo-SdPacketValue $Q['evidence'] $IdToKey $EvById $Pk.State 'evidence'
    $Pk.Questions.Add($o)
}

function Complete-SdPacket {
    param($Pk)
    $Pk.Packet['items'] = $Pk.Items.ToArray()
    $Pk.Packet['questions'] = $Pk.Questions.ToArray()
    $Pk.Packet['evidence'] = $Pk.State.Evidence.ToArray()
    return , $Pk.Packet
}

function Get-SdExampleReceipts {
    # 回傳 @{ Receipts; ExtraQuestions; Docs; IdToKey; EvById }。$Pages／$Records：分母（範例 canonical 沒有，測試另給）。
    # $UiPerComponent：畫面項目依鍵的 Component 前綴分包（外環逐 Component 檢查畫面分母時用）。
    param([string]$Dir, [string]$JobId, [string]$StatusRef, $Pages, $Records, [switch]$UiPerComponent)
    $docs = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $Dir 'canonical') -Filter '*.json' -File)) {
        $docs[[System.IO.Path]::GetFileNameWithoutExtension($f.Name)] = ConvertTo-PsSdNode (Read-PsSdJsonFile $f.FullName)
    }
    $idToKey = New-PsSdMap; $byPrefix = New-PsSdMap
    foreach ($d in $docs.Keys) {
        if ($d -eq 'evidence') { continue }
        foreach ($it in $docs[$d]['items']) {
            $idToKey[[string]$it['id']] = [string]$it['key']
            $p = Get-PsSdIdPrefix ([string]$it['id'])
            if (-not $byPrefix.ContainsKey($p)) { $byPrefix[$p] = [System.Collections.Generic.List[object]]::new() }
            $byPrefix[$p].Add($it)
        }
    }
    $evById = New-PsSdMap
    foreach ($e in $docs['evidence']['items']) { $evById[[string]$e['id']] = $e }
    $comps = @($docs['01-overview']['components'])
    $subject = [string]$comps[0]
    $receipts = [System.Collections.Generic.List[object]]::new()
    $mk = {
        param([string]$Unit, [string]$Subj, [string[]]$Prefixes)
        $pk = New-SdPacket $JobId $Unit $Subj 1
        foreach ($p in $Prefixes) { if ($byPrefix.ContainsKey($p)) { foreach ($it in $byPrefix[$p]) { Add-SdPacketItem $pk $it $idToKey $evById } } }
        return $pk
    }
    # 範圍：每個 Component 一包；物件放第一包；分母（範例 canonical 沒有，測試另給）依 Component 分包
    foreach ($comp in $comps) {
        $pk = New-SdPacket $JobId 'scope' ([string]$comp) 1
        if ([string]$comp -ceq $subject) { foreach ($p in @('OBJ', 'XF')) { if ($byPrefix.ContainsKey($p)) { foreach ($it in $byPrefix[$p]) { Add-SdPacketItem $pk $it $idToKey $evById } } } }
        $myPages = @(); foreach ($pg in @($Pages)) { if ($null -ne $pg -and [string]$pg.Component -ceq [string]$comp) { $myPages += , $pg } }
        $myRecs = @(); if ([string]$comp -ceq $subject) { foreach ($rc in @($Records)) { if ($null -ne $rc) { $myRecs += , $rc } } }
        if ($myPages.Count -gt 0 -or $myRecs.Count -gt 0) {
            $ev = New-PsSdObject; $ev['id'] = 'E' + ($pk.State.Evidence.Count + 1); $ev['kind'] = 'SQL'
            $ev['locator'] = 'SELECT PNLNAME, FIELDNUM, RECNAME, FIELDNAME FROM PSPNLFIELD WHERE PNLNAME LIKE ''TW_DEMO%'''
            $ev['excerpt'] = '合成：頁面與 Record 欄位清單'
            $pk.State.Evidence.Add($ev)
            $den = New-PsSdObject
            $pl = @(); foreach ($pg in $myPages) { $o = New-PsSdObject; $o['page'] = $pg.Page; $o['fields'] = @($pg.Fields); $o['evidence'] = @($ev['id']); $pl += , $o }
            $rl = @(); foreach ($rc in $myRecs) { $o = New-PsSdObject; $o['record'] = $rc.Record; $o['fields'] = @($rc.Fields); $o['evidence'] = @($ev['id']); $rl += , $o }
            $den['pages'] = $pl; $den['records'] = $rl
            $pk.Packet['denominators'] = $den
        }
        $receipts.Add(@{ Ref = 'scope/' + $comp + '/p1'; Packet = (Complete-SdPacket $pk) })
    }
    $receipts.Add(@{ Ref = 'data/' + $subject + '/p1'; Packet = (Complete-SdPacket (& $mk 'data' $subject @('ENT', 'FLD', 'DRV'))) })
    $receipts.Add(@{ Ref = 'security/' + $subject + '/p1'; Packet = (Complete-SdPacket (& $mk 'security' $subject @('ROLE', 'PERM'))) })
    # 說明區域與活動
    $pk = & $mk 'texts' $subject @('ACT')
    $st = @()
    foreach ($t in @($docs['04-workflow']['statusTexts'])) {
        $o = New-PsSdObject
        $o['line'] = [int](([string]$t['locator']) -replace '^.*#L', '')
        $o['disposition'] = $t['disposition']
        if ($t.Contains('items')) { $o['items'] = ConvertTo-SdPacketValue $t['items'] $idToKey $evById $pk.State 'items' }
        if ($t.Contains('note')) { $o['note'] = $t['note'] }
        $st += , $o
    }
    $pk.Packet['statusTexts'] = $st
    $receipts.Add(@{ Ref = 'texts/' + $subject + '/p1'; Packet = (Complete-SdPacket $pk) })
    # 流程：每個狀態實體一包；圖外問題放進該實體
    $ents = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @('STATE', 'TRN', 'FLOW')) { if ($byPrefix.ContainsKey($p)) { foreach ($it in $byPrefix[$p]) { if (-not $ents.Contains([string]$it['entityKey'])) { $ents.Add([string]$it['entityKey']) } } } }
    $ents.Sort([System.StringComparer]::Ordinal)
    foreach ($e in $ents) {
        $pk = New-SdPacket $JobId 'workflow' $e 1
        foreach ($p in @('STATE', 'TRN', 'FLOW')) { if ($byPrefix.ContainsKey($p)) { foreach ($it in $byPrefix[$p]) { if ([string]$it['entityKey'] -ceq $e) { Add-SdPacketItem $pk $it $idToKey $evById } } } }
        if ($byPrefix.ContainsKey('Q')) {
            foreach ($q in $byPrefix['Q']) {
                if (@('OFF_DIAGRAM_STATE', 'OFF_DIAGRAM_TRANSITION') -contains [string]$q['category'] -and [string]$q['observed']['entityKey'] -ceq $e) { Add-SdPacketQuestion $pk $q $idToKey $evById }
            }
        }
        if ($docs.ContainsKey('90-questions')) {
            $codes = @(); foreach ($c in @($docs['90-questions']['suppressed']['definitionOnlyCodes'])) { if ([string]$c['entityKey'] -ceq $e) { $o = New-PsSdObject; $o['code'] = $c['code']; $codes += , $o } }
            if ($codes.Count -gt 0) { $pk.Packet['definitionOnlyCodes'] = $codes }
        }
        $receipts.Add(@{ Ref = 'workflow/' + $e + '/p1'; Packet = (Complete-SdPacket $pk) })
    }
    $plain = @(@('interfaces', @('IF')), @('functions', @('FR')))
    if (-not $UiPerComponent) { $plain += , @('ui', @('UI')) }
    foreach ($u in $plain) {
        $receipts.Add(@{ Ref = $u[0] + '/' + $subject + '/p1'; Packet = (Complete-SdPacket (& $mk $u[0] $subject $u[1])) })
    }
    if ($UiPerComponent) {
        foreach ($comp in $comps) {
            $pk = New-SdPacket $JobId 'ui' ([string]$comp) 1
            if ($byPrefix.ContainsKey('UI')) { foreach ($it in $byPrefix['UI']) { if (([string]$it['key']).StartsWith([string]$comp + '.')) { Add-SdPacketItem $pk $it $idToKey $evById } } }
            $receipts.Add(@{ Ref = 'ui/' + $comp + '/p1'; Packet = (Complete-SdPacket $pk) })
        }
    }
    $pk = & $mk 'rules' $subject @('MSG', 'BR')
    if ($docs.ContainsKey('09-business-logic')) {
        $pd = @()
        foreach ($d in @($docs['09-business-logic']['programDispositions'])) { $pd += , (ConvertTo-SdPacketValue $d $idToKey $evById $pk.State '') }
        $pk.Packet['programDispositions'] = $pd
    }
    if ($byPrefix.ContainsKey('Q')) { foreach ($q in $byPrefix['Q']) { if ([string]$q['category'] -ceq 'NATIVE_UNUSED_BRANCH') { Add-SdPacketQuestion $pk $q $idToKey $evById } } }
    $receipts.Add(@{ Ref = 'rules/' + $subject + '/p1'; Packet = (Complete-SdPacket $pk) })
    $receipts.Add(@{ Ref = 'operations/' + $subject + '/p1'; Packet = (Complete-SdPacket (& $mk 'operations' $subject @('OP'))) })
    $receipts.Add(@{ Ref = 'testing/' + $subject + '/p1'; Packet = (Complete-SdPacket (& $mk 'testing' $subject @('TC'))) })
    # 讀者提出的問題（L5）
    $extra = [System.Collections.Generic.List[object]]::new()
    if ($byPrefix.ContainsKey('Q')) {
        foreach ($q in $byPrefix['Q']) {
            if (-not ([string]$q['category']).StartsWith('READER_')) { continue }
            $aff = @(); foreach ($a in @($q['affects'])) { $aff += [string]$a }
            $extra.Add(@{ Key = [string]$q['key']; Category = [string]$q['category']; Question = [string]$q['question']; Affects = $aff; RaisedBy = 'READER'; Status = [string]$q['status']; Evidence = @() })
        }
    }
    return @{ Receipts = $receipts.ToArray(); ExtraQuestions = $extra.ToArray(); Docs = $docs; IdToKey = $idToKey; EvById = $evById; Components = $comps }
}

function ConvertTo-SdComparable {
    # 比對用：證據 ID 換成證據內容。
    param($Value, $EvSig, [string]$ParentKey)
    if ($Value -is [string]) {
        if ($ParentKey -ceq 'evidence' -and $EvSig.ContainsKey($Value)) { return $EvSig[$Value] }
        return $Value
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $o = New-PsSdObject
        foreach ($k in @($Value.Keys)) { $o[[string]$k] = ConvertTo-SdComparable $Value[$k] $EvSig ([string]$k) }
        return , $o
    }
    if ($Value -is [System.Collections.IList]) {
        $arr = New-Object object[] $Value.Count
        for ($i = 0; $i -lt $Value.Count; $i++) { $arr[$i] = ConvertTo-SdComparable $Value[$i] $EvSig $ParentKey }
        if ($ParentKey -ceq 'evidence') { $l = [System.Collections.Generic.List[string]]::new(); foreach ($x in $arr) { $l.Add([string]$x) }; $l.Sort([System.StringComparer]::Ordinal); return , $l.ToArray() }
        return , $arr
    }
    return $Value
}
