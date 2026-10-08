# ps-sdoc-lib.ps1 — Spec 文件流程（Claude Code 版）的核心：常數、項目工具、ID registry、研究包驗收與合成、canonical 組裝、計算文件。
# 依賴（呼叫端先載入）：ps-knowledge-lib.ps1（JSON 輸出、hash、原子寫入）、ps-sdoc-schema-lib.ps1、ps-sdoc-status-lib.ps1。
# 記憶體形狀：JSON 物件一律是區分大小寫、保留順序的 OrderedDictionary（New-PsSdObject）；陣列是 object[]。
# 研究包的參照：既有 ID（FLD-007）或 '@前綴/自然鍵'；證據：E1…（外環換成 EV-xxxx）；{"unresolved":"缺口說明"}（外環開 EVIDENCE_GAP 問題）。
# PS 5.1 相容。

$script:PsSdLibVersion = '1'

# ---------------- 常數 ----------------
$script:PsSdPrefixInfo = [ordered]@{
    'GOAL' = @{ Doc = '01-overview'; Rank = 0; Name = '專案目標'; Label = '目標' }
    'RESP' = @{ Doc = '01-overview'; Rank = 0; Name = '決策責任'; Label = '決策責任' }
    'OBJ' = @{ Doc = '01-overview'; Rank = 0; Name = '舊系統物件'; Label = '物件' }
    'AI' = @{ Doc = '16-ai-instructions'; Rank = 0; Name = 'AI 指引條款'; Label = '條款' }
    'ENT' = @{ Doc = '07-database'; Rank = 1; Name = '資料實體'; Label = '實體' }
    'FLD' = @{ Doc = '07-database'; Rank = 1; Name = '資料欄位'; Label = '欄位' }
    'DRV' = @{ Doc = '07-database'; Rank = 1; Name = '衍生概念'; Label = '衍生概念' }
    'XF' = @{ Doc = '07-database'; Rank = 1; Name = '不建置原生欄位'; Label = '不建置欄位組' }
    'ROLE' = @{ Doc = '03-roles-permissions'; Rank = 2; Name = '角色'; Label = '角色' }
    'PERM' = @{ Doc = '03-roles-permissions'; Rank = 2; Name = '權限'; Label = '權限' }
    'STATE' = @{ Doc = '04-workflow'; Rank = 3; Name = '狀態'; Label = '狀態' }
    'TRN' = @{ Doc = '04-workflow'; Rank = 3; Name = '狀態轉移'; Label = '轉移' }
    'FLOW' = @{ Doc = '04-workflow'; Rank = 3; Name = '情境流程'; Label = '情境' }
    'ACT' = @{ Doc = '04-workflow'; Rank = 3; Name = '狀態活動'; Label = '活動' }
    'IF' = @{ Doc = '06-architecture'; Rank = 4; Name = '介面／批次'; Label = '介面' }
    'FR' = @{ Doc = '02-functional-requirements'; Rank = 5; Name = '功能需求'; Label = '功能' }
    'UI' = @{ Doc = '05-ui'; Rank = 6; Name = '畫面／元件'; Label = '畫面元件' }
    'MSG' = @{ Doc = '09-business-logic'; Rank = 7; Name = '訊息'; Label = '訊息' }
    'BR' = @{ Doc = '09-business-logic'; Rank = 7; Name = '業務規則'; Label = '規則' }
    'OP' = @{ Doc = '08-api'; Rank = 8; Name = '操作契約'; Label = '操作' }
    'TC' = @{ Doc = '14-testing'; Rank = 9; Name = '測試案例'; Label = '測試案例' }
    'TASK' = @{ Doc = '17-tasks'; Rank = 10; Name = '工作項'; Label = '工作項' }
    'DOD' = @{ Doc = '18-definition-of-done'; Rank = 11; Name = '完成條件'; Label = '完成條件' }
    'Q' = @{ Doc = '90-questions'; Rank = 12; Name = '問題'; Label = '問題' }
    'DEC' = @{ Doc = '19-decision-log'; Rank = 13; Name = '決策'; Label = '決策' }
}
$script:PsSdDocOrder = @('01-overview', '02-functional-requirements', '03-roles-permissions', '04-workflow', '05-ui', '06-architecture',
    '07-database', '08-api', '09-business-logic', '14-testing', '16-ai-instructions', '17-tasks', '18-definition-of-done',
    '19-decision-log', '90-questions')
$script:PsSdDocTitles = @{
    '01-overview' = '01 專案概覽'; '02-functional-requirements' = '02 功能需求'; '03-roles-permissions' = '03 角色與權限'
    '04-workflow' = '04 流程與狀態機'; '05-ui' = '05 畫面與互動'; '06-architecture' = '06 系統架構（技術中立）'
    '07-database' = '07 資料設計'; '08-api' = '08 操作契約（API）'; '09-business-logic' = '09 業務邏輯'
    '14-testing' = '14 測試與驗收'; '16-ai-instructions' = '16 AI 實作指引'; '17-tasks' = '17 工作拆解與相依'
    '18-definition-of-done' = '18 完成定義'; '19-decision-log' = '19 決策紀錄'; '90-questions' = '90 問題清單'
}
$script:PsSdDocPrefixes = @{
    '01-overview' = @('GOAL', 'RESP', 'OBJ'); '02-functional-requirements' = @('FR'); '03-roles-permissions' = @('ROLE', 'PERM')
    '04-workflow' = @('STATE', 'TRN', 'FLOW', 'ACT'); '05-ui' = @('UI'); '06-architecture' = @('IF')
    '07-database' = @('ENT', 'FLD', 'DRV', 'XF'); '08-api' = @('OP'); '09-business-logic' = @('MSG', 'BR'); '14-testing' = @('TC')
    '16-ai-instructions' = @('AI'); '17-tasks' = @('TASK'); '18-definition-of-done' = @('DOD'); '19-decision-log' = @('DEC')
    '90-questions' = @('Q')
}
$script:PsSdRefRx = [regex]'^(GOAL|RESP|OBJ|AI|ENT|FLD|DRV|XF|ROLE|PERM|STATE|TRN|FLOW|ACT|IF|FR|UI|MSG|BR|OP|TC|TASK|DOD|Q|DEC)-\d{3,}$'
$script:PsSdKeyRefRx = [regex]'^@(GOAL|RESP|OBJ|ENT|FLD|DRV|XF|ROLE|PERM|STATE|TRN|FLOW|ACT|IF|FR|UI|MSG|BR|OP|TC)/(\S(.*\S)?)$'
# 研究單位（依序）。Per：component＝每個 Component 一個主題；job＝全 job 一個；entity＝每個狀態實體一個。
$script:PsSdUnits = @(
    @{ Id = 'scope'; Title = '範圍'; Per = 'component'; Types = @('OBJ', 'XF'); Extras = @('denominators') }
    @{ Id = 'data'; Title = '資料'; Per = 'component'; Types = @('ENT', 'FLD', 'DRV'); Extras = @() }
    @{ Id = 'security'; Title = '權限'; Per = 'component'; Types = @('ROLE', 'PERM'); Extras = @() }
    @{ Id = 'texts'; Title = '說明區域與狀態活動'; Per = 'job'; Types = @('ACT'); Extras = @('statusTexts') }
    @{ Id = 'workflow'; Title = '流程'; Per = 'entity'; Types = @('STATE', 'TRN', 'FLOW'); Extras = @('definitionOnlyCodes') }
    @{ Id = 'interfaces'; Title = '介面'; Per = 'component'; Types = @('IF'); Extras = @() }
    @{ Id = 'functions'; Title = '功能'; Per = 'component'; Types = @('FR'); Extras = @() }
    @{ Id = 'ui'; Title = '畫面'; Per = 'component'; Types = @('UI'); Extras = @() }
    @{ Id = 'rules'; Title = '規則'; Per = 'component'; Types = @('MSG', 'BR'); Extras = @('programDispositions') }
    @{ Id = 'operations'; Title = '操作'; Per = 'component'; Types = @('OP'); Extras = @() }
    @{ Id = 'testing'; Title = '測試'; Per = 'component'; Types = @('TC'); Extras = @() }
)
# 研究包可以提出的上游需求（型別 → 研究單位）
$script:PsSdRequestUnit = @{ 'OBJ' = 'scope'; 'ENT' = 'data'; 'FLD' = 'data'; 'DRV' = 'data'; 'ROLE' = 'security'; 'IF' = 'interfaces'; 'MSG' = 'rules' }
# 工作流程骨架欄位（由第 0 階段帶入，研究包不得寫）
$script:PsSdSkeletonFields = @{
    'STATE' = @('entityKey', 'stateKind', 'code', 'name', 'parent', 'regions', 'isInitialTarget', 'isFinal')
    'TRN' = @('entityKey', 'from', 'to', 'via', 'diagramLabels')
    'FLOW' = @('entityKey', 'scenarioType')
}
$script:PsSdResearchQuestionCategories = @('OFF_DIAGRAM_STATE', 'OFF_DIAGRAM_TRANSITION', 'NATIVE_UNUSED_BRANCH', 'DIAGRAM_EDGE_UNIMPLEMENTED',
    'DIAGRAM_CODE_CONFLICT', 'SCOPE_CANDIDATE', 'EVIDENCE_GAP')
$script:PsSdInfoCategories = @('OFF_DIAGRAM_STATE', 'OFF_DIAGRAM_TRANSITION', 'NATIVE_UNUSED_BRANCH', 'INPUT_MISSING')

function Get-PsSdUnit {
    param([string]$Id)
    foreach ($u in $script:PsSdUnits) { if ($u.Id -eq $Id) { return $u } }
    return $null
}

function Get-PsSdUnitIndex {
    param([string]$Id)
    for ($i = 0; $i -lt $script:PsSdUnits.Length; $i++) { if ($script:PsSdUnits[$i].Id -eq $Id) { return $i } }
    return -1
}

function Get-PsSdIdPrefix {
    param([string]$Id)
    $i = $Id.IndexOf('-')
    if ($i -lt 0) { return '' }
    return $Id.Substring(0, $i)
}

function Get-PsSdDocOfId {
    param([string]$Id)
    $p = Get-PsSdIdPrefix $Id
    if (-not $script:PsSdPrefixInfo.Contains($p)) { return '' }
    return $script:PsSdPrefixInfo[$p].Doc
}

function Get-PsSdRankOfId {
    param([string]$Id)
    $p = Get-PsSdIdPrefix $Id
    if (-not $script:PsSdPrefixInfo.Contains($p)) { return 99 }
    return $script:PsSdPrefixInfo[$p].Rank
}

# ---------------- 項目工具 ----------------
function Get-PsSdItemRefs {
    # 項目裡所有 ID 參照（不含最上層的 id），依出現順序，可重複。
    param($Item)
    $out = [System.Collections.Generic.List[string]]::new()
    $stack = [System.Collections.Generic.Stack[object]]::new()
    if ($Item -is [System.Collections.IDictionary]) {
        $keys = @($Item.Keys)
        for ($i = $keys.Length - 1; $i -ge 0; $i--) { if ([string]$keys[$i] -cne 'id') { $stack.Push($Item[$keys[$i]]) } }
    } else { $stack.Push($Item) }
    while ($stack.Count -gt 0) {
        $v = $stack.Pop()
        if ($v -is [string]) { if ($script:PsSdRefRx.IsMatch($v)) { $out.Add($v) }; continue }
        if ($v -is [System.Collections.IDictionary]) {
            $keys = @($v.Keys)
            for ($i = $keys.Length - 1; $i -ge 0; $i--) { $stack.Push($v[$keys[$i]]) }
            continue
        }
        if ($v -is [System.Collections.IList]) { for ($i = $v.Count - 1; $i -ge 0; $i--) { $stack.Push($v[$i]) } }
    }
    return , $out.ToArray()
}

function Get-PsSdStringsOf {
    param($Value)
    $out = [System.Collections.Generic.List[string]]::new()
    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push($Value)
    while ($stack.Count -gt 0) {
        $v = $stack.Pop()
        if ($v -is [string]) { $out.Add($v); continue }
        if ($v -is [System.Collections.IDictionary]) { $keys = @($v.Keys); for ($i = $keys.Length - 1; $i -ge 0; $i--) { $stack.Push($v[$keys[$i]]) }; continue }
        if ($v -is [System.Collections.IList]) { for ($i = $v.Count - 1; $i -ge 0; $i--) { $stack.Push($v[$i]) } }
    }
    return , $out.ToArray()
}

function Get-PsSdConds {
    # 結構內所有單一條件（有 left＋op 的 predicate 與 rows），依出現順序。
    param($Value)
    $out = [System.Collections.Generic.List[object]]::new()
    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push($Value)
    while ($stack.Count -gt 0) {
        $v = $stack.Pop()
        if ($v -is [System.Collections.IDictionary]) {
            if (($v.Contains('left') -and $v.Contains('op')) -or $v.Contains('rows')) { $out.Add($v) }
            $keys = @($v.Keys); for ($i = $keys.Length - 1; $i -ge 0; $i--) { $stack.Push($v[$keys[$i]]) }
            continue
        }
        if ($v -is [System.Collections.IList] -and -not ($v -is [string])) { for ($i = $v.Count - 1; $i -ge 0; $i--) { $stack.Push($v[$i]) } }
    }
    return , $out.ToArray()
}

function Get-PsSdConj {
    # 最上層以 all 串起的各項（巢狀 all 展開）。
    param($Cond)
    $out = [System.Collections.Generic.List[object]]::new()
    if ($Cond -is [System.Collections.IDictionary] -and $Cond.Contains('all')) {
        foreach ($x in $Cond['all']) { $sub = Get-PsSdConj $x; foreach ($y in $sub) { $out.Add($y) } }
    } else { $out.Add($Cond) }
    return , $out.ToArray()
}

function Test-PsSdIsCond {
    param($Cond)
    if ($Cond -is [string]) { return ($Cond -ceq 'ALWAYS') }
    if ($Cond -is [System.Collections.IDictionary]) { return (-not $Cond.Contains('na') -and -not $Cond.Contains('unresolved')) }
    return $false
}

function Test-PsSdSameNode {
    param($A, $B)
    return ((ConvertTo-PsSdCanonical $A) -ceq (ConvertTo-PsSdCanonical $B))
}

function Copy-PsSdNode {
    param($Value)
    $c = ConvertTo-PsSdNode $Value
    return , $c
}

function New-PsSdOrderedFrom {
    # 以 ($鍵, $值) 成對的陣列建物件：New-PsSdOrderedFrom @('a', 1, 'b', 2)
    param([object[]]$Pairs)
    $o = New-PsSdObject
    for ($i = 0; $i -lt $Pairs.Length; $i += 2) { $o[[string]$Pairs[$i]] = $Pairs[$i + 1] }
    return , $o
}

function Get-PsSdTextHash {
    # 小寫 SHA-256（與 Get-PsKnTextHash 相同的正規化：去 CR、去 BOM）。
    param([string]$Text)
    return (Get-PsKnTextHash $Text).ToLowerInvariant()
}

function ConvertTo-PsSdJsonText {
    # canonical JSON：保留物件鍵順序、2 空格縮排、LF、結尾換行。
    param($Value)
    return ((ConvertTo-PsKnJson -Value $Value) + "`n")
}

function Read-PsSdJsonNode {
    param([string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return $null }
    $n = ConvertTo-PsSdNode (Read-PsSdJsonFile $Path)
    return , $n
}

# ---------------- schema 導出的欄位順序 ----------------
function Get-PsSdItemSchemaRoot {
    param([string]$Prefix)
    return ('urn:ps-spec:schema:' + $script:PsSdPrefixInfo[$Prefix].Doc + '#/$defs/' + $Prefix)
}

function Get-PsSdItemPropertyOrder {
    # 項目鍵的輸出順序：itemBase 的欄位，再接型別自己的欄位（schema 宣告順序）。
    param($SchemaReg, [string]$Prefix)
    $ck = 'order|' + $Prefix
    if ($SchemaReg.RefCache.ContainsKey($ck)) { return $SchemaReg.RefCache[$ck] }
    $order = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $base = (Resolve-PsSdRef $SchemaReg '' 'urn:ps-spec:schema:common#/$defs/itemBase').Schema
    foreach ($k in $base['properties'].Keys) { if ($seen.Add([string]$k)) { $order.Add([string]$k) } }
    $def = (Resolve-PsSdRef $SchemaReg '' (Get-PsSdItemSchemaRoot $Prefix)).Schema
    foreach ($part in $def['allOf']) {
        if ($part -is [System.Collections.IDictionary] -and $part.Contains('properties')) {
            foreach ($k in $part['properties'].Keys) { if ($seen.Add([string]$k)) { $order.Add([string]$k) } }
        }
    }
    $arr = $order.ToArray()
    $SchemaReg.RefCache[$ck] = $arr
    return , $arr
}

function ConvertTo-PsSdOrderedItem {
    # 依 schema 欄位順序重排項目的鍵（未宣告的鍵照原順序接在後面，交給 schema 擋）。
    param($SchemaReg, $Item, [string]$Prefix)
    $order = Get-PsSdItemPropertyOrder $SchemaReg $Prefix
    $o = New-PsSdObject
    foreach ($k in $order) { if ($Item.Contains($k)) { $o[$k] = $Item[$k] } }
    foreach ($k in @($Item.Keys)) { if (-not $o.Contains([string]$k)) { $o[[string]$k] = $Item[$k] } }
    return , $o
}

# ---------------- ID registry（每個 job 一份；ID 穩定、作廢不重用） ----------------
function New-PsSdIdRegistry {
    $r = New-PsSdObject
    $r['schemaVersion'] = 1
    $r['prefixes'] = New-PsSdObject
    return , $r
}

function Read-PsSdIdRegistry {
    param([string]$Path)
    $n = Read-PsSdJsonNode $Path
    if ($null -eq $n) { $n = New-PsSdIdRegistry }
    return , $n
}

function Get-PsSdRegisteredId {
    param($Registry, [string]$Prefix, [string]$Key)
    $ps = $Registry['prefixes']
    if (-not $ps.Contains($Prefix)) { return $null }
    $keys = $ps[$Prefix]['keys']
    if ($keys.Contains($Key)) { return [string]$keys[$Key] }
    return $null
}

function Register-PsSdKeys {
    # 新出現的自然鍵依字元碼順序排序後給號；已有 ID 的鍵不變。回傳新派發的 (鍵, ID) 對照（OrderedDictionary）。
    param($Registry, [string]$Prefix, [string[]]$Keys)
    $ps = $Registry['prefixes']
    if (-not $ps.Contains($Prefix)) { $p = New-PsSdObject; $p['next'] = 1; $p['keys'] = New-PsSdObject; $ps[$Prefix] = $p }
    $entry = $ps[$Prefix]
    $new = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($k in $Keys) { if ($null -ne $k -and -not $entry['keys'].Contains($k) -and $seen.Add($k)) { $new.Add($k) } }
    $new.Sort([System.StringComparer]::Ordinal)
    $assigned = New-PsSdObject
    foreach ($k in $new) {
        $n = [int]$entry['next']
        $digits = 3
        if ($Prefix -ceq 'DEC') { $digits = 3 }
        $id = $Prefix + '-' + $n.ToString(('D' + $digits), [System.Globalization.CultureInfo]::InvariantCulture)
        $entry['keys'][$k] = $id
        $entry['next'] = $n + 1
        $assigned[$k] = $id
    }
    return , $assigned
}

function Get-PsSdIdKeyMap {
    # ID → @{ Prefix; Key }（全部前綴）。
    param($Registry)
    $out = New-PsSdMap
    foreach ($p in $Registry['prefixes'].Keys) {
        $keys = $Registry['prefixes'][$p]['keys']
        foreach ($k in $keys.Keys) { $out[[string]$keys[$k]] = @{ Prefix = [string]$p; Key = [string]$k } }
    }
    return $out
}

# ---------------- 證據 ----------------
$script:PsSdEvidenceKinds = @('CHUNK', 'SQL', 'NN', 'WIKI', 'STATUS_DOC', 'PROJECT_INPUT', 'METADATA_RECEIPT', 'HUMAN_DECISION')

function Test-PsSdSqlLocator {
    # 只准單一 SELECT／WITH，不得含 DML／DDL、INTO 或分號串接。
    param([string]$Sql)
    $s = $Sql.Trim()
    if (-not [regex]::IsMatch($s, '^(?i)(SELECT|WITH)\b')) { return $false }
    if ([regex]::IsMatch($s, ';\s*\S')) { return $false }
    if ([regex]::IsMatch($s, '(?i)\b(INSERT|UPDATE|DELETE|MERGE|DROP|ALTER|CREATE|TRUNCATE|GRANT|REVOKE|EXECUTE|EXEC|INTO)\b')) { return $false }
    return $true
}

function Get-PsSdEvidenceSignature {
    param($Ev)
    return ([string]$Ev['kind'] + [char]0 + [string]$Ev['locator'] + [char]0 + [string]$Ev['excerpt'])
}

# ---------------- 04 骨架（第 0 階段採用的事實） ----------------
function Get-PsSdWorkflowSkeleton {
    # 回傳 @{ STATE; TRN; FLOW }：各為 OrderedDictionary（自然鍵 → 骨架欄位），另有 Entities（實體 → 該實體的鍵清單）。
    # 狀態參照先寫成 '@STATE/<鍵>'，合成時換成 ID。
    param($Built)
    $sk = @{ STATE = (New-PsSdObject); TRN = (New-PsSdObject); FLOW = (New-PsSdObject); Entities = (New-PsSdMap) }
    $parentOf = New-PsSdMap
    foreach ($ck in $Built.Composites.Keys) {
        $c = $Built.Composites[$ck]
        foreach ($sub in $c.Regions) { if (-not $parentOf.ContainsKey($sub)) { $parentOf[$sub] = '@STATE/' + $c.Entity + ':' + $c.Code } }
    }
    foreach ($e in (Get-PsSdSortedKeys $Built.Entities)) {
        $ent = $Built.Entities[$e]
        $mine = [System.Collections.Generic.List[string]]::new()
        $codes = [System.Collections.Generic.List[string]]::new($ent.Codes); $codes.Sort([System.StringComparer]::Ordinal)
        foreach ($code in $codes) {
            $key = $e + ':' + $code
            $it = New-PsSdObject
            $it['entityKey'] = $e
            $ck = $e + '|' + $code
            if ($Built.Composites.Contains($ck)) { $it['stateKind'] = 'COMPOSITE' } else { $it['stateKind'] = 'SIMPLE' }
            $it['code'] = $code
            $nk = $e + [char]0 + $code
            $name = $code
            if ($Built.Names.ContainsKey($nk)) { $name = [string]$Built.Names[$nk] }
            $it['name'] = $name
            if ($parentOf.ContainsKey($e)) { $it['parent'] = $parentOf[$e] }
            if ($Built.Composites.Contains($ck)) {
                $regs = [System.Collections.Generic.List[object]]::new()
                foreach ($sub in $Built.Composites[$ck].Regions) {
                    $fin = @()
                    if ($Built.Entities.ContainsKey($sub)) {
                        $fl = [System.Collections.Generic.List[string]]::new($Built.Entities[$sub].Finals); $fl.Sort([System.StringComparer]::Ordinal)
                        foreach ($f in $fl) { $fin += ('@STATE/' + $sub + ':' + $f) }
                    }
                    $r = New-PsSdObject; $r['entityKey'] = $sub; $r['finalStates'] = $fin
                    $regs.Add($r)
                }
                $it['regions'] = $regs.ToArray()
            }
            $it['isInitialTarget'] = $ent.Initials.Contains($code)
            $it['isFinal'] = $ent.Finals.Contains($code)
            $sk.STATE[$key] = $it
            $mine.Add('STATE/' + $key)
        }
        $pairs = [System.Collections.Generic.List[string]]::new($ent.Pairs); $pairs.Sort([System.StringComparer]::Ordinal)
        foreach ($pair in $pairs) {
            $ab = $pair.Split('>')
            $key = $e + ':' + $pair
            $it = New-PsSdObject
            $it['entityKey'] = $e
            if ($ab[0] -eq '*') { $it['from'] = 'INITIAL' } else { $it['from'] = '@STATE/' + $e + ':' + $ab[0] }
            $it['to'] = '@STATE/' + $e + ':' + $ab[1]
            if ($ent.Via.ContainsKey($pair)) { $it['via'] = @($ent.Via[$pair]) }
            if ($ent.Labels.ContainsKey($pair) -and @($ent.Labels[$pair]).Count -gt 0) { $it['diagramLabels'] = @($ent.Labels[$pair]) }
            $sk.TRN[$key] = $it
            $mine.Add('TRN/' + $key)
        }
        foreach ($scen in (Get-PsSdSortedKeys $ent.Scenarios)) {
            $key = $e + ':' + $scen
            $it = New-PsSdObject
            $it['entityKey'] = $e
            $it['scenarioType'] = $scen
            $sk.FLOW[$key] = $it
            $mine.Add('FLOW/' + $key)
        }
        $sk.Entities[$e] = $mine.ToArray()
    }
    return $sk
}

# ---------------- 研究包：參照解析與合成 ----------------
function New-PsSdResolveContext {
    # $Mode：Check（驗收一頁：未派號的新鍵給暫定 ID，並以 schema 驗每個項目）／Collect（同 Check 但不驗，只為收集要派號的鍵）／Build（組裝：一律用 registry 的 ID）。
    param($SchemaReg, $Registry, $Skeleton, [string]$StatusRef, $Built, [string]$Mode)
    return @{
        SchemaReg = $SchemaReg; Registry = $Registry; Skeleton = $Skeleton; StatusRef = $StatusRef; Built = $Built; Mode = $Mode
        IdKeys = (Get-PsSdIdKeyMap $Registry)
        Evidence = [System.Collections.Generic.List[object]]::new(); EvidenceBySig = (New-PsSdMap)
        Temp = 900000
    }
}

function Get-PsSdQKeyPart {
    param([string]$Text)
    return ([regex]::Replace($Text.Trim(), '\s+', '_'))
}

function Add-PsSdEvidence {
    # 依內容去重；Check 模式給暫定 ID。回傳 EV ID。
    param($Ctx, $Ev)
    $sig = Get-PsSdEvidenceSignature $Ev
    if ($Ctx.EvidenceBySig.ContainsKey($sig)) { return $Ctx.EvidenceBySig[$sig] }
    $n = $Ctx.Evidence.Count + 1
    if ($Ctx.Mode -ne 'Build') { $n += 9000 }
    $id = 'EV-' + $n.ToString('D4', [System.Globalization.CultureInfo]::InvariantCulture)
    $o = New-PsSdObject
    $o['id'] = $id
    foreach ($k in @('kind', 'locator', 'excerpt', 'capturedOn')) { if ($Ev.Contains($k)) { $o[$k] = $Ev[$k] } }
    $Ctx.Evidence.Add($o)
    $Ctx.EvidenceBySig[$sig] = $id
    return $id
}

function Resolve-PsSdKeyRef {
    # '@前綴/鍵' 或既有 ID → ID；找不到回 $null。
    param($Ctx, $Local, [string]$Value)
    $m = $script:PsSdKeyRefRx.Match($Value)
    if ($m.Success) {
        $p = $m.Groups[1].Value; $k = $m.Groups[2].Value
        $lk = $p + '/' + $k
        if ($Local.ContainsKey($lk)) { return $Local[$lk] }
        $id = Get-PsSdRegisteredId $Ctx.Registry $p $k
        return $id
    }
    if ($script:PsSdRefRx.IsMatch($Value)) {
        if ($Ctx.IdKeys.ContainsKey($Value)) { return $Value }
        return $null
    }
    return $null
}

function Resolve-PsSdStateRef {
    # 參照 → ID：本包、registry、本包的暫定 ID；Check／Collect 模式下，同單元型別的未知鍵視為後頁才寫的項目（給暫定 ID、記進 Forward，
    # 單元寫完 COMPLETE 前要出現）。找不到回 $null。
    param($Ctx, $State, [string]$Value)
    $id = Resolve-PsSdKeyRef $Ctx $State.Local $Value
    if ($null -ne $id) { return $id }
    if ($State.LocalIds.Contains($Value)) { return $Value }
    if ($Ctx.Mode -eq 'Build') { return $null }
    $m = $script:PsSdKeyRefRx.Match($Value)
    if (-not $m.Success -or @($State.UnitTypes) -notcontains $m.Groups[1].Value) { return $null }
    $lk = $m.Groups[1].Value + '/' + $m.Groups[2].Value
    $Ctx.Temp++
    $id = $m.Groups[1].Value + '-' + $Ctx.Temp
    $State.Local[$lk] = $id
    [void]$State.LocalIds.Add($id)
    $State.Forward.Add($lk)
    return $id
}

function Resolve-PsSdValue {
    # 深走一個值，換掉參照、證據與缺口；錯誤寫進 $State.Errors。
    param($Ctx, $State, $Value, [string]$ParentKey, [string]$Path)
    if ($Value -is [string]) {
        if ($Value.Length -gt 1 -and $Value[0] -eq '@') {
            $id = Resolve-PsSdStateRef $Ctx $State $Value
            if ($null -eq $id) { $State.Errors.Add($State.Where + ' ' + $Path + '：參照不存在的 ' + $Value); return $Value }
            return $id
        }
        if ($ParentKey -ceq 'evidence' -and [regex]::IsMatch($Value, '^E[1-9][0-9]*$')) {
            if ($State.LocalEv.ContainsKey($Value)) { return $State.LocalEv[$Value] }
            $State.Errors.Add($State.Where + ' ' + $Path + '：證據 ' + $Value + ' 不在本包的 evidence')
            return $Value
        }
        if ($script:PsSdRefRx.IsMatch($Value) -and -not $Ctx.IdKeys.ContainsKey($Value) -and -not $State.LocalIds.Contains($Value)) {
            $State.Errors.Add($State.Where + ' ' + $Path + '：參照不存在的 ' + $Value)
        }
        return $Value
    }
    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Count -eq 1 -and $Value.Contains('unresolved') -and $Value['unresolved'] -is [string] -and -not [regex]::IsMatch([string]$Value['unresolved'], '^Q-\d{3,}$')) {
            $qkey = 'EVIDENCE_GAP:' + (Get-PsSdQKeyPart ($State.ItemKey + '#' + $Path))
            $qid = Get-PsSdRegisteredId $Ctx.Registry 'Q' $qkey
            if ($null -eq $qid) {
                if ($Ctx.Mode -ne 'Build') { $Ctx.Temp++; $qid = 'Q-' + $Ctx.Temp } else { $State.Errors.Add($State.Where + ' ' + $Path + '：缺口問題尚未派號'); $qid = 'Q-999' }
            }
            $State.Gaps.Add(@{ Key = $qkey; Id = $qid; Text = [string]$Value['unresolved']; ItemId = $State.ItemId; Evidence = $State.ItemEvidence })
            $o = New-PsSdObject; $o['unresolved'] = $qid
            return , $o
        }
        $o = New-PsSdObject
        foreach ($k in @($Value.Keys)) {
            $cp = [string]$k
            if ($Path) { $cp = $Path + '.' + $k }
            $o[[string]$k] = Resolve-PsSdValue $Ctx $State $Value[$k] ([string]$k) $cp
        }
        return , $o
    }
    if ($Value -is [System.Collections.IList]) {
        $arr = New-Object object[] $Value.Count
        for ($i = 0; $i -lt $Value.Count; $i++) { $arr[$i] = Resolve-PsSdValue $Ctx $State $Value[$i] $ParentKey ($Path + '[' + $i + ']') }
        return , $arr
    }
    return $Value
}

function Resolve-PsSdPacket {
    # 研究包 → 合成後的 canonical 項目。回傳 @{ Errors; Items（@{Prefix;Key;Id;Item}）; Questions（@{Key;Id;Item}）; Gaps; Requests; Implicit; Extras; Forward（同單元後頁才寫的鍵） }。
    # Check 模式另以各文件 schema 驗證每個合成後的項目與問題。
    param($Ctx, $Packet)
    $errs = [System.Collections.Generic.List[string]]::new()
    $unitId = [string]$Packet['unit']
    $unit = Get-PsSdUnit $unitId
    $unitTypes = @(); if ($null -ne $unit) { $unitTypes = @($unit.Types) }
    $state = @{ Errors = $errs; Local = (New-PsSdMap); LocalEv = (New-PsSdMap); LocalIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        Gaps = [System.Collections.Generic.List[object]]::new(); Where = ''; ItemKey = ''; ItemId = ''; ItemEvidence = @(); UnitTypes = $unitTypes; Forward = [System.Collections.Generic.List[string]]::new() }
    # 證據
    foreach ($ev in @($Packet['evidence'])) {
        if ($null -eq $ev) { continue }
        $lid = [string]$ev['id']
        if ($state.LocalEv.ContainsKey($lid)) { $errs.Add('evidence：' + $lid + ' 重複'); continue }
        if ([string]$ev['kind'] -ceq 'SQL' -and -not (Test-PsSdSqlLocator ([string]$ev['locator']))) { $errs.Add('evidence ' + $lid + '：SQL 只准單一 SELECT／WITH，不得含 DML、INTO 或分號串接') }
        $state.LocalEv[$lid] = Add-PsSdEvidence $Ctx $ev
    }
    # 本包項目與需求的 ID
    $seenKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($it in @($Packet['items'])) {
        if ($null -eq $it) { continue }
        $p = [string]$it['type']; $k = [string]$it['key']
        if ($null -ne $unit -and $unit.Types -notcontains $p) { $errs.Add($p + '/' + $k + '：' + $unitId + ' 單元不能寫 ' + $p); continue }
        if (-not $seenKeys.Add($p + '/' + $k)) { $errs.Add($p + '/' + $k + '：同一包重複'); continue }
        $id = Get-PsSdRegisteredId $Ctx.Registry $p $k
        if ($null -eq $id) {
            if ($Ctx.Mode -ne 'Build') { $Ctx.Temp++; $id = $p + '-' + $Ctx.Temp } else { $errs.Add($p + '/' + $k + '：尚未派號') }
        }
        $state.Local[$p + '/' + $k] = $id
        if ($null -ne $id) { [void]$state.LocalIds.Add($id) }
    }
    $requests = [System.Collections.Generic.List[object]]::new()
    foreach ($rq in @($Packet['requests'])) {
        if ($null -eq $rq) { continue }
        $p = [string]$rq['type']; $k = [string]$rq['key']
        $id = Get-PsSdRegisteredId $Ctx.Registry $p $k
        if ($null -eq $id) {
            if ($Ctx.Mode -ne 'Build') { $Ctx.Temp++; $id = $p + '-' + $Ctx.Temp } else { $errs.Add('requests ' + $p + '/' + $k + '：尚未派號') }
        }
        if (-not $state.Local.ContainsKey($p + '/' + $k)) { $state.Local[$p + '/' + $k] = $id }
        if ($null -ne $id) { [void]$state.LocalIds.Add($id) }
        $requests.Add(@{ Type = $p; Key = $k; Reason = [string]$rq['reason']; Id = $id })
    }
    # 範圍單元：XF 指向本包 RECORD 的 ENT（資料單元稍後研究），視為上游需求
    $implicit = [System.Collections.Generic.List[object]]::new()
    if ($unitId -eq 'scope') {
        foreach ($it in @($Packet['items'])) {
            if ($null -eq $it -or [string]$it['type'] -cne 'OBJ' -or [string]$it['objectType'] -cne 'RECORD' -or [string]$it['inclusion'] -ceq 'EXCLUDED') { continue }
            $rk = 'ENT/' + [string]$it['objectName']
            if ($state.Local.ContainsKey($rk)) { continue }
            $id = Get-PsSdRegisteredId $Ctx.Registry 'ENT' ([string]$it['objectName'])
            if ($null -eq $id -and $Ctx.Mode -ne 'Build') { $Ctx.Temp++; $id = 'ENT-' + $Ctx.Temp }
            if ($null -ne $id) { $state.Local[$rk] = $id; [void]$state.LocalIds.Add($id) }
            $implicit.Add(@{ Type = 'ENT'; Key = [string]$it['objectName'] })
        }
    }
    # 項目
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($it in @($Packet['items'])) {
        if ($null -eq $it) { continue }
        $p = [string]$it['type']; $k = [string]$it['key']
        if (-not $state.Local.ContainsKey($p + '/' + $k)) { continue }
        $id = $state.Local[$p + '/' + $k]
        $state.Where = $p + '/' + $k; $state.ItemKey = $k; $state.ItemId = $id
        $state.ItemEvidence = @()
        $body = New-PsSdObject
        foreach ($f in @($it.Keys)) {
            $fn = [string]$f
            if ($fn -ceq 'type') { continue }
            if ($fn -ceq 'id' -or $fn -ceq 'lifecycle') { $errs.Add($state.Where + '：研究包不得寫 ' + $fn + '（外環產生）'); continue }
            if ($script:PsSdSkeletonFields.ContainsKey($p) -and $script:PsSdSkeletonFields[$p] -ccontains $fn) { $errs.Add($state.Where + '：研究包不得寫 ' + $fn + '（取自狀態圖解讀）'); continue }
            $body[$fn] = $it[$f]
        }
        if ($body.Contains('evidence')) {
            $evs = @(); foreach ($x in @($body['evidence'])) { if ($state.LocalEv.ContainsKey([string]$x)) { $evs += $state.LocalEv[[string]$x] } }
            $state.ItemEvidence = $evs
        }
        $resolved = Resolve-PsSdValue $Ctx $state $body '' ''
        $merged = New-PsSdObject
        $merged['id'] = $id
        $merged['key'] = $k
        $merged['lifecycle'] = 'ACTIVE'
        foreach ($f in @($resolved.Keys)) { if ([string]$f -cne 'key') { $merged[[string]$f] = $resolved[$f] } }
        if ($script:PsSdSkeletonFields.ContainsKey($p)) {
            $sk = $null
            if ($null -ne $Ctx.Skeleton -and $Ctx.Skeleton[$p].Contains($k)) { $sk = $Ctx.Skeleton[$p][$k] }
            if ($null -eq $sk) { $errs.Add($state.Where + '：不是狀態圖解讀採用的' + $script:PsSdPrefixInfo[$p].Name + '（研究只能補細節，不能增減）'); continue }
            if ($unitId -eq 'workflow' -and [string]$sk['entityKey'] -cne [string]$Packet['subject']) { $errs.Add($state.Where + '：不屬於本單元的狀態實體 ' + $Packet['subject']) }
            $skState = @{ Errors = $errs; Local = (New-PsSdMap); LocalEv = (New-PsSdMap); LocalIds = $state.LocalIds; Gaps = $state.Gaps; Where = $state.Where; ItemKey = $k; ItemId = $id; ItemEvidence = @(); UnitTypes = @(); Forward = $state.Forward }
            $skr = Resolve-PsSdValue $Ctx $skState $sk '' ''
            foreach ($f in @($skr.Keys)) { $merged[[string]$f] = $skr[$f] }
        }
        $ordered = ConvertTo-PsSdOrderedItem $Ctx.SchemaReg $merged $p
        if ($Ctx.Mode -eq 'Check') {
            $ie = Test-PsSdSchema $Ctx.SchemaReg (Get-PsSdItemSchemaRoot $p) $ordered
            foreach ($e in @($ie)) { $errs.Add($state.Where + ' ' + $e) }
        }
        $items.Add(@{ Prefix = $p; Key = $k; Id = $id; Item = $ordered })
    }
    # 問題
    $questions = [System.Collections.Generic.List[object]]::new()
    foreach ($q in @($Packet['questions'])) {
        if ($null -eq $q) { continue }
        $cat = [string]$q['category']
        $qkey = $cat + ':' + [string]$q['key']
        $state.Where = 'Q/' + $qkey; $state.ItemKey = $qkey
        $qid = Get-PsSdRegisteredId $Ctx.Registry 'Q' $qkey
        if ($null -eq $qid) { if ($Ctx.Mode -ne 'Build') { $Ctx.Temp++; $qid = 'Q-' + $Ctx.Temp } else { $errs.Add($state.Where + '：尚未派號'); continue } }
        $state.ItemId = $qid
        $o = New-PsSdObject
        $o['id'] = $qid; $o['key'] = $qkey; $o['lifecycle'] = 'ACTIVE'; $o['basis'] = 'COMPUTED'; $o['certainty'] = 'CONFIRMED'
        $evs = @(); foreach ($x in @($q['evidence'])) { if ($null -ne $x) { if ($state.LocalEv.ContainsKey([string]$x)) { $evs += $state.LocalEv[[string]$x] } else { $errs.Add($state.Where + '：證據 ' + $x + ' 不在本包的 evidence') } } }
        $o['evidence'] = $evs
        $o['category'] = $cat
        if ($script:PsSdInfoCategories -contains $cat) { $o['severity'] = 'INFO' } else { $o['severity'] = 'BLOCKING' }
        if ($q.Contains('grade')) { $o['grade'] = $q['grade'] }
        $o['question'] = $q['question']
        $aff = @()
        foreach ($a in @($q['affects'])) {
            if ($null -eq $a) { continue }
            $aid = Resolve-PsSdStateRef $Ctx $state ([string]$a)
            if ($null -eq $aid) { $errs.Add($state.Where + ' affects：參照不存在的 ' + $a) } else { $aff += $aid }
        }
        $o['affects'] = $aff
        if ($q.Contains('observed')) { $o['observed'] = Resolve-PsSdValue $Ctx $state $q['observed'] 'observed' 'observed' }
        if ($q.Contains('proof')) { $o['proof'] = Resolve-PsSdValue $Ctx $state $q['proof'] 'proof' 'proof' }
        $o['raisedBy'] = 'RESEARCH'
        $o['status'] = 'OPEN'
        if ($q.Contains('proposedAnswer')) { $o['proposedAnswer'] = $q['proposedAnswer'] }
        if ($Ctx.Mode -eq 'Check') {
            $qe = Test-PsSdSchema $Ctx.SchemaReg 'urn:ps-spec:schema:90-questions#/$defs/Q' $o
            foreach ($e in @($qe)) { $errs.Add($state.Where + ' ' + $e) }
        }
        $questions.Add(@{ Key = $qkey; Id = $qid; Item = $o })
    }
    # 單元附加資料
    $extras = @{}
    if ($Packet.Contains('statusTexts')) {
        $rows = [System.Collections.Generic.List[object]]::new()
        $texts = New-PsSdMap
        if ($null -ne $Ctx.Built) { foreach ($t in $Ctx.Built.Texts) { $texts[[string]$t.Line] = $t } }
        foreach ($st in @($Packet['statusTexts'])) {
            if ($null -eq $st) { continue }
            $ln = [int]$st['line']
            $state.Where = 'statusTexts 第 ' + $ln + ' 行'; $state.ItemKey = 'L' + $ln
            if (-not $texts.ContainsKey([string]$ln)) { $errs.Add($state.Where + '：不是 STATUS 檔的說明文字或讀者列為業務文字的行'); continue }
            $o = New-PsSdObject
            $o['locator'] = $Ctx.StatusRef + '#L' + $ln
            $o['text'] = $texts[[string]$ln].Text
            $o['disposition'] = $st['disposition']
            if ($st.Contains('items')) {
                $ids = @()
                foreach ($x in @($st['items'])) { $rid = Resolve-PsSdStateRef $Ctx $state ([string]$x); if ($null -eq $rid) { $errs.Add($state.Where + '：參照不存在的 ' + $x) } else { $ids += $rid } }
                $o['items'] = $ids
            }
            if ($st.Contains('note')) { $o['note'] = $st['note'] }
            $rows.Add($o)
        }
        $extras['statusTexts'] = $rows.ToArray()
    }
    if ($Packet.Contains('programDispositions')) {
        $rows = [System.Collections.Generic.List[object]]::new()
        foreach ($pd in @($Packet['programDispositions'])) {
            if ($null -eq $pd) { continue }
            $state.Where = 'programDispositions ' + $pd['program']; $state.ItemKey = [string]$pd['program']
            $o = New-PsSdObject
            $pid0 = Resolve-PsSdStateRef $Ctx $state ([string]$pd['program'])
            if ($null -eq $pid0) { $errs.Add($state.Where + '：參照不存在的程式') ; continue }
            $o['program'] = $pid0
            $o['kinds'] = $pd['kinds']
            $ids = @()
            foreach ($x in @($pd['items'])) { if ($null -eq $x) { continue }; $rid = Resolve-PsSdStateRef $Ctx $state ([string]$x); if ($null -eq $rid) { $errs.Add($state.Where + '：參照不存在的 ' + $x) } else { $ids += $rid } }
            $o['items'] = $ids
            if ($pd.Contains('note')) { $o['note'] = $pd['note'] }
            $rows.Add($o)
        }
        $extras['programDispositions'] = $rows.ToArray()
    }
    if ($Packet.Contains('denominators')) {
        $d = $Packet['denominators']
        $pages = [System.Collections.Generic.List[object]]::new()
        foreach ($pg in @($d['pages'])) { if ($null -eq $pg) { continue }; $pages.Add(@{ Component = [string]$Packet['subject']; Page = [string]$pg['page']; Fields = @($pg['fields']) }) }
        $recs = [System.Collections.Generic.List[object]]::new()
        foreach ($rc in @($d['records'])) { if ($null -eq $rc) { continue }; $recs.Add(@{ Record = [string]$rc['record']; Fields = @($rc['fields']) }) }
        foreach ($grp in @(@($d['pages']) + @($d['records']))) { if ($null -eq $grp) { continue }; foreach ($x in @($grp['evidence'])) { if (-not $state.LocalEv.ContainsKey([string]$x)) { $errs.Add('denominators：證據 ' + $x + ' 不在本包的 evidence') } } }
        $extras['denominators'] = @{ Pages = $pages.ToArray(); Records = $recs.ToArray() }
    }
    if ($Packet.Contains('definitionOnlyCodes')) {
        $rows = [System.Collections.Generic.List[object]]::new()
        foreach ($dc in @($Packet['definitionOnlyCodes'])) { if ($null -eq $dc) { continue }; $o = New-PsSdObject; $o['entityKey'] = [string]$Packet['subject']; $o['code'] = [string]$dc['code']; $rows.Add($o) }
        $extras['definitionOnlyCodes'] = $rows.ToArray()
    }
    return @{ Errors = $errs; Items = $items.ToArray(); Questions = $questions.ToArray(); Gaps = $state.Gaps.ToArray(); Requests = $requests.ToArray(); Implicit = $implicit.ToArray(); Extras = $extras; Forward = $state.Forward.ToArray() }
}

# ---------------- 派號：骨架與收據 ----------------
function Update-PsSdRegistry {
    # 為第 0 階段骨架與目前全部收據（依單元順序）中尚未派號的自然鍵派號。$Receipts：@{ Packet } 陣列（已排序）。
    param($SchemaReg, $Registry, $Skeleton, [object[]]$Receipts, [object[]]$ExtraKeys)
    $want = New-PsSdMap
    $add = {
        param([string]$Pfx, [string]$Ky)
        if (-not $want.ContainsKey($Pfx)) { $want[$Pfx] = [System.Collections.Generic.List[string]]::new() }
        $want[$Pfx].Add($Ky)
    }
    if ($null -ne $Skeleton) {
        foreach ($p in @('STATE', 'TRN', 'FLOW')) { foreach ($k in $Skeleton[$p].Keys) { & $add $p ([string]$k) } }
    }
    foreach ($ek in @($ExtraKeys)) { if ($null -ne $ek) { & $add $ek.Prefix $ek.Key } }
    $ctx = New-PsSdResolveContext $SchemaReg $Registry $Skeleton '' $null 'Collect'
    foreach ($r in @($Receipts)) {
        if ($null -eq $r) { continue }
        $res = Resolve-PsSdPacket $ctx $r.Packet
        foreach ($it in $res.Items) { & $add $it.Prefix $it.Key }
        foreach ($rq in $res.Requests) { & $add $rq.Type $rq.Key }
        foreach ($im in $res.Implicit) { & $add $im.Type $im.Key }
        foreach ($q in $res.Questions) { & $add 'Q' $q.Key }
        foreach ($g in $res.Gaps) { & $add 'Q' $g.Key }
    }
    $n = 0
    foreach ($p in $script:PsSdPrefixInfo.Keys) {
        if (-not $want.ContainsKey($p)) { continue }
        $assigned = Register-PsSdKeys $Registry $p $want[$p].ToArray()
        $n += $assigned.Count
    }
    return $n
}

# ---------------- 組裝：收據 → 項目 ----------------
function Build-PsSdResearchModel {
    # 回傳 @{ Items（前綴 → List）; ById; Questions; Gaps; Requests; StatusTexts; ProgramDispositions; Denominators; DefinitionOnlyCodes; Evidence; Errors; ItemReceipt（ID → 收據參照） }
    param($SchemaReg, $Registry, $Skeleton, [string]$StatusRef, $Built, [object[]]$Receipts)
    $ctx = New-PsSdResolveContext $SchemaReg $Registry $Skeleton $StatusRef $Built 'Build'
    $items = New-PsSdMap
    foreach ($p in $script:PsSdPrefixInfo.Keys) { $items[$p] = [System.Collections.Generic.List[object]]::new() }
    $byId = New-PsSdMap
    $itemReceipt = New-PsSdMap
    $questions = [System.Collections.Generic.List[object]]::new()
    $gaps = [System.Collections.Generic.List[object]]::new()
    $requests = [System.Collections.Generic.List[object]]::new()
    $statusTexts = [System.Collections.Generic.List[object]]::new()
    $programs = [System.Collections.Generic.List[object]]::new()
    $pages = [System.Collections.Generic.List[object]]::new()
    $records = [System.Collections.Generic.List[object]]::new()
    $defOnly = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($r in @($Receipts)) {
        if ($null -eq $r) { continue }
        $res = Resolve-PsSdPacket $ctx $r.Packet
        foreach ($e in $res.Errors) { $errors.Add([string]$r.Ref + '：' + $e) }
        foreach ($it in $res.Items) {
            if ($byId.ContainsKey($it.Id)) { $errors.Add([string]$r.Ref + '：' + $it.Prefix + '/' + $it.Key + ' 已在其他收據出現，略過'); continue }
            $items[$it.Prefix].Add($it.Item)
            $byId[$it.Id] = $it.Item
            $itemReceipt[$it.Id] = $r.Ref
        }
        foreach ($q in $res.Questions) { $questions.Add(@{ Key = $q.Key; Id = $q.Id; Item = $q.Item; Ref = $r.Ref }) }
        foreach ($g in $res.Gaps) { $gaps.Add($g) }
        foreach ($rq in $res.Requests) { $requests.Add(@{ Type = $rq.Type; Key = $rq.Key; Reason = $rq.Reason; Id = $rq.Id; Unit = [string]$r.Packet['unit']; Subject = [string]$r.Packet['subject'] }) }
        if ($res.Extras.ContainsKey('statusTexts')) { foreach ($x in $res.Extras['statusTexts']) { $statusTexts.Add($x) } }
        if ($res.Extras.ContainsKey('programDispositions')) { foreach ($x in $res.Extras['programDispositions']) { $programs.Add($x) } }
        if ($res.Extras.ContainsKey('denominators')) {
            foreach ($x in $res.Extras['denominators'].Pages) { $pages.Add($x) }
            foreach ($x in $res.Extras['denominators'].Records) { $records.Add($x) }
        }
        if ($res.Extras.ContainsKey('definitionOnlyCodes')) { foreach ($x in $res.Extras['definitionOnlyCodes']) { $defOnly.Add($x) } }
    }
    # 每個前綴依 ID 排序
    foreach ($p in @($items.Keys)) {
        $lst = $items[$p]
        if ($lst.Count -lt 2) { continue }
        $keyed = [System.Collections.Generic.List[string]]::new()
        $map = New-PsSdMap
        foreach ($it in $lst) { $num = [int](([string]$it['id']).Substring($p.Length + 1)); $sk = $num.ToString('D8', [System.Globalization.CultureInfo]::InvariantCulture); $keyed.Add($sk); $map[$sk] = $it }
        $keyed.Sort([System.StringComparer]::Ordinal)
        $sorted = [System.Collections.Generic.List[object]]::new()
        foreach ($sk in $keyed) { $sorted.Add($map[$sk]) }
        $items[$p] = $sorted
    }
    return @{ Items = $items; ById = $byId; ItemReceipt = $itemReceipt; Questions = $questions; Gaps = $gaps; Requests = $requests
        StatusTexts = $statusTexts.ToArray(); ProgramDispositions = $programs.ToArray(); Pages = $pages.ToArray(); Records = $records.ToArray()
        DefinitionOnlyCodes = $defOnly.ToArray(); Evidence = $ctx.Evidence; EvidenceCtx = $ctx; Errors = $errors }
}

# ---------------- 人工輸入檔（Markdown 表格） ----------------
function Get-PsSdMarkdownTables {
    # 回傳 @{ Heading; Header（欄名陣列）; Rows（@{ Line; Cells; Text }） } 陣列。表格以 | 開頭、第二行是分隔線。
    param([string]$Text)
    $lines = ConvertTo-PsSdLines $Text
    $out = [System.Collections.Generic.List[object]]::new()
    $heading = ''
    $i = 0
    while ($i -lt $lines.Length) {
        $t = $lines[$i].Trim()
        $hm = [regex]::Match($t, '^#{1,6}\s+(.*?)\s*#*$')
        if ($hm.Success) { $heading = $hm.Groups[1].Value; $i++; continue }
        if ($t.StartsWith('|') -and $i + 1 -lt $lines.Length -and [regex]::IsMatch($lines[$i + 1].Trim(), '^\|?\s*:?-{3,}')) {
            $header = Split-PsSdTableRow $t
            $rows = [System.Collections.Generic.List[object]]::new()
            $j = $i + 2
            while ($j -lt $lines.Length -and $lines[$j].Trim().StartsWith('|')) {
                $rows.Add(@{ Line = $j + 1; Cells = (Split-PsSdTableRow $lines[$j].Trim()); Text = $lines[$j].Trim() })
                $j++
            }
            $out.Add(@{ Heading = $heading; Header = $header; Rows = $rows.ToArray() })
            $i = $j
            continue
        }
        $i++
    }
    return , $out.ToArray()
}

function Split-PsSdTableRow {
    param([string]$Row)
    $r = $Row.Trim()
    if ($r.StartsWith('|')) { $r = $r.Substring(1) }
    if ($r.EndsWith('|') -and -not $r.EndsWith('\|')) { $r = $r.Substring(0, $r.Length - 1) }
    $cells = [System.Collections.Generic.List[string]]::new()
    $sb = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $r.Length; $i++) {
        $ch = $r[$i]
        if ($ch -eq '\' -and $i + 1 -lt $r.Length -and $r[$i + 1] -eq '|') { [void]$sb.Append('|'); $i++; continue }
        if ($ch -eq '|') { $cells.Add($sb.ToString().Trim()); [void]$sb.Clear(); continue }
        [void]$sb.Append($ch)
    }
    $cells.Add($sb.ToString().Trim())
    return , $cells.ToArray()
}

function ConvertFrom-PsSdProjectInput {
    # project.md：「目標」表（目標｜成功標準）與「決策責任」表（範圍｜職稱或單位類別）。
    param([string]$Text, [string]$Ref)
    $res = @{ Provided = $false; Goals = [System.Collections.Generic.List[object]]::new(); Resps = [System.Collections.Generic.List[object]]::new(); Problems = [System.Collections.Generic.List[string]]::new() }
    if ($null -eq $Text -or $Text.Contains('<!-- SDOC:SKELETON -->')) { return $res }
    foreach ($tb in (Get-PsSdMarkdownTables $Text)) {
        $h0 = ''; if ($tb.Header.Length -gt 0) { $h0 = $tb.Header[0] }
        if ($tb.Heading -like '*目標*' -or $h0 -eq '目標') {
            foreach ($row in $tb.Rows) {
                if ($row.Cells.Length -lt 2 -or $row.Cells[0] -eq '') { continue }
                $crit = @(); foreach ($c in [regex]::Split($row.Cells[1], '；|;|<br\s*/?>')) { $c2 = $c.Trim(); if ($c2) { $crit += $c2 } }
                if ($crit.Count -eq 0) { $res.Problems.Add($Ref + '#L' + $row.Line + '：目標沒有成功標準'); continue }
                $res.Goals.Add(@{ Statement = $row.Cells[0]; Criteria = $crit; Line = $row.Line; Text = $row.Text })
            }
        } elseif ($tb.Heading -like '*決策責任*' -or $h0 -eq '範圍') {
            foreach ($row in $tb.Rows) {
                if ($row.Cells.Length -lt 2 -or $row.Cells[0] -eq '') { continue }
                $area = $row.Cells[0].Trim().ToUpperInvariant()
                if (@('SPEC_APPROVAL', 'QUESTION_RESOLUTION', 'BUSINESS_RULE_OWNER', 'DATA_OWNER', 'OTHER') -notcontains $area) { $res.Problems.Add($Ref + '#L' + $row.Line + '：範圍 ' + $row.Cells[0] + ' 不在值域'); continue }
                $res.Resps.Add(@{ Area = $area; Holder = $row.Cells[1]; Line = $row.Line; Text = $row.Text })
            }
        }
    }
    $res.Provided = ($res.Goals.Count -gt 0)
    return $res
}

function ConvertFrom-PsSdDecisions {
    # decisions.md：問題 ID｜決定｜理由｜效果｜決定者類別｜日期。
    param([string]$Text, [string]$Ref)
    $res = @{ Rows = [System.Collections.Generic.List[object]]::new(); Problems = [System.Collections.Generic.List[string]]::new() }
    if ($null -eq $Text) { return $res }
    foreach ($tb in (Get-PsSdMarkdownTables $Text)) {
        if ($tb.Header.Length -lt 6 -or $tb.Header[0] -notlike '*問題*') { continue }
        foreach ($row in $tb.Rows) {
            $c = $row.Cells
            if ($c.Length -lt 6 -or ($c[0] -eq '' -and $c[1] -eq '')) { continue }
            $where = $Ref + '#L' + $row.Line
            $qid = $c[0].Trim().ToUpperInvariant()
            $eff = $c[3].Trim().ToUpperInvariant()
            if (-not [regex]::IsMatch($qid, '^Q-\d{3,}$')) { $res.Problems.Add($where + '：問題 ID 格式不對（例：Q-003）'); continue }
            if (@('NO_CHANGE', 'DROP', 'ADD_SCOPE', 'ACCEPT_GAP', 'AMEND_INPUT') -notcontains $eff) { $res.Problems.Add($where + '：效果要是 NO_CHANGE／DROP／ADD_SCOPE／ACCEPT_GAP／AMEND_INPUT'); continue }
            if (-not [regex]::IsMatch($c[5].Trim(), '^\d{4}-\d{2}-\d{2}$')) { $res.Problems.Add($where + '：日期格式要是 YYYY-MM-DD'); continue }
            if ($c[1].Trim() -eq '' -or $c[2].Trim() -eq '' -or $c[4].Trim() -eq '') { $res.Problems.Add($where + '：決定、理由、決定者類別都要填'); continue }
            $res.Rows.Add(@{ QId = $qid; Decision = $c[1].Trim(); Rationale = $c[2].Trim(); Effect = $eff; DecidedBy = $c[4].Trim(); DecidedOn = $c[5].Trim(); Line = $row.Line; Text = $row.Text })
        }
    }
    return $res
}

function ConvertFrom-PsSdApprovals {
    # approvals.md：文件｜版本｜docHash 前 12 碼｜核准者類別｜日期。
    param([string]$Text, [string]$Ref)
    $res = @{ Rows = [System.Collections.Generic.List[object]]::new(); Problems = [System.Collections.Generic.List[string]]::new() }
    if ($null -eq $Text) { return $res }
    foreach ($tb in (Get-PsSdMarkdownTables $Text)) {
        if ($tb.Header.Length -lt 5 -or $tb.Header[0] -notlike '*文件*') { continue }
        foreach ($row in $tb.Rows) {
            $c = $row.Cells
            if ($c.Length -lt 5 -or $c[0] -eq '') { continue }
            $where = $Ref + '#L' + $row.Line
            $doc = $c[0].Trim()
            $m = [regex]::Match($doc, '^(\d{2})')
            if (-not $m.Success) { $res.Problems.Add($where + '：文件要寫編號（例：04 或 04-workflow）'); continue }
            $dt = ''
            foreach ($d in $script:PsSdDocOrder) { if ($d.StartsWith($m.Groups[1].Value + '-')) { $dt = $d } }
            if ($dt -eq '') { $res.Problems.Add($where + '：沒有 ' + $doc + ' 這份文件'); continue }
            $hp = $c[2].Trim().ToLowerInvariant()
            if (-not [regex]::IsMatch($hp, '^[0-9a-f]{12}$')) { $res.Problems.Add($where + '：docHash 前 12 碼要是 12 個 0-9a-f'); continue }
            if (-not [regex]::IsMatch($c[4].Trim(), '^\d{4}-\d{2}-\d{2}$')) { $res.Problems.Add($where + '：日期格式要是 YYYY-MM-DD'); continue }
            $res.Rows.Add(@{ Doc = $dt; Revision = $c[1].Trim(); HashPrefix = $hp; ApprovedBy = $c[3].Trim(); Date = $c[4].Trim(); Line = $row.Line })
        }
    }
    return $res
}

# ---------------- 計算項目 ----------------
function New-PsSdComputedItem {
    param([string]$Id, [string]$Key, [string]$Basis, [object[]]$Evidence)
    $o = New-PsSdObject
    $o['id'] = $Id; $o['key'] = $Key; $o['lifecycle'] = 'ACTIVE'; $o['basis'] = $Basis; $o['certainty'] = 'CONFIRMED'
    if ($null -eq $Evidence) { $Evidence = @() }
    $o['evidence'] = @($Evidence)
    return , $o
}

function Get-PsSdSortedIds {
    param($Ids)
    $l = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($x in $Ids) { if ($null -ne $x -and $seen.Add([string]$x)) { $l.Add([string]$x) } }
    $l.Sort([System.StringComparer]::Ordinal)
    return , $l.ToArray()
}

function Get-PsSdTaskItems {
    # 17：一個基礎工作＋每個 FR 一個垂直切片。順序依各 FR 最早轉移在狀態圖上的廣度優先層級；前置工作是到達起點狀態的那條轉移所屬的 FR。
    param($Registry, $Items, $ById)
    $trns = New-PsSdMap
    foreach ($t in $Items['TRN']) { $trns[[string]$t['id']] = $t }
    $trnSorted = [System.Collections.Generic.List[object]]::new()
    $tk = [System.Collections.Generic.List[string]]::new(); $tmap = New-PsSdMap
    foreach ($t in $Items['TRN']) { $tk.Add([string]$t['key']); $tmap[[string]$t['key']] = $t }
    $tk.Sort([System.StringComparer]::Ordinal)
    foreach ($k in $tk) { $trnSorted.Add($tmap[$k]) }
    $level = New-PsSdMap; $level['INITIAL'] = 0
    $firstReach = New-PsSdMap
    $frontier = [System.Collections.Generic.List[string]]::new(); $frontier.Add('INITIAL')
    while ($frontier.Count -gt 0) {
        $nxt = [System.Collections.Generic.List[string]]::new()
        foreach ($s in $frontier) {
            foreach ($t in $trnSorted) {
                if ([string]$t['from'] -ceq $s -and -not $level.ContainsKey([string]$t['to'])) {
                    $level[[string]$t['to']] = $level[$s] + 1
                    $firstReach[[string]$t['to']] = [string]$t['id']
                    $nxt.Add([string]$t['to'])
                }
            }
        }
        $frontier = $nxt
    }
    $trnLevel = {
        param([string]$TrnId)
        if (-not $trns.ContainsKey($TrnId)) { return 999 }
        $f = [string]$trns[$TrnId]['from']
        if ($level.ContainsKey($f)) { return [int]$level[$f] }
        return 999
    }
    $frOfTrn = New-PsSdMap
    foreach ($fr in $Items['FR']) { foreach ($t in @($fr['realizes'])) { if ($null -eq $t) { continue }; if (-not $frOfTrn.ContainsKey([string]$t)) { $frOfTrn[[string]$t] = [System.Collections.Generic.List[string]]::new() }; $frOfTrn[[string]$t].Add([string]$fr['id']) } }
    $members = {
        param($FrItem)
        $fid = [string]$FrItem['id']
        $m = New-PsSdObject
        $tr = @(); foreach ($x in @($FrItem['realizes'])) { if ($null -ne $x) { $tr += [string]$x } }
        $ctl = @(); foreach ($u in $Items['UI']) { if ([string]$u['uiKind'] -ceq 'CONTROL' -and @($u['usedBy']) -ccontains $fid) { $ctl += [string]$u['id'] } }
        $rul = @(); foreach ($b in $Items['BR']) { if (@($b['appliesTo']) -ccontains $fid) { $rul += [string]$b['id'] } }
        $ops = @(); foreach ($o in $Items['OP']) { if ([string]$o['fr'] -ceq $fid) { $ops += [string]$o['id'] } }
        $tst = @(); foreach ($t in $Items['TC']) { if ([string]$t['fr'] -ceq $fid) { $tst += [string]$t['id'] } }
        $acts = @()
        $perf = @(); if ($FrItem.Contains('performs')) { $perf = @($FrItem['performs']) }
        foreach ($a in $Items['ACT']) {
            $hit = $perf -ccontains [string]$a['id']
            if (-not $hit -and $a.Contains('realizedBy')) { foreach ($x in @($a['realizedBy'])) { if ($tr -ccontains [string]$x) { $hit = $true } } }
            if ($hit) { $acts += [string]$a['id'] }
        }
        $touched = [System.Collections.Generic.List[string]]::new()
        foreach ($iid in @($tr + $ctl + $rul + $ops)) { if ($ById.ContainsKey($iid)) { foreach ($x in (Get-PsSdItemRefs $ById[$iid])) { $touched.Add($x) } } }
        $flds = @(); $drvs = @(); $roles = @()
        foreach ($x in $touched) { if ($x.StartsWith('FLD-')) { $flds += $x } elseif ($x.StartsWith('DRV-')) { $drvs += $x } elseif ($x.StartsWith('ROLE-')) { $roles += $x } }
        $m['fields'] = Get-PsSdSortedIds $flds
        $m['derivations'] = Get-PsSdSortedIds $drvs
        $m['roles'] = Get-PsSdSortedIds $roles
        $m['transitions'] = $tr
        if ($acts.Count -gt 0) { $m['activities'] = $acts }
        $m['controls'] = $ctl
        $m['rules'] = $rul
        $m['operations'] = $ops
        $m['tests'] = $tst
        return , $m
    }
    $found = @{ Key = 'FOUNDATION:DATA_AND_SECURITY'; Kind = 'FOUNDATION'; Fr = $null }
    $slices = [System.Collections.Generic.List[object]]::new()
    foreach ($fr in $Items['FR']) {
        $lv = 999
        foreach ($t in @($fr['realizes'])) { if ($null -ne $t) { $l1 = & $trnLevel ([string]$t); if ($l1 -lt $lv) { $lv = $l1 } } }
        $slices.Add(@{ Level = $lv; Key = [string]$fr['key']; Fr = $fr })
    }
    $sk = [System.Collections.Generic.List[string]]::new(); $smap = New-PsSdMap
    foreach ($s in $slices) { $k2 = ([int]$s.Level).ToString('D4', [System.Globalization.CultureInfo]::InvariantCulture) + [char]0 + $s.Key; $sk.Add($k2); $smap[$k2] = $s }
    $sk.Sort([System.StringComparer]::Ordinal)
    $keys = @($found.Key); foreach ($k2 in $sk) { $keys += ('SLICE:' + $smap[$k2].Key) }
    $assigned = Register-PsSdKeys $Registry 'TASK' $keys
    $foundId = Get-PsSdRegisteredId $Registry 'TASK' $found.Key
    $taskByFr = New-PsSdMap
    foreach ($k2 in $sk) { $s = $smap[$k2]; $taskByFr[[string]$s.Fr['id']] = Get-PsSdRegisteredId $Registry 'TASK' ('SLICE:' + $s.Key) }
    $out = [System.Collections.Generic.List[object]]::new()
    $f = New-PsSdComputedItem $foundId $found.Key 'COMPUTED' @()
    $f['taskKind'] = 'FOUNDATION'
    $na = New-PsSdObject; $na['na'] = '基礎工作，不對應單一功能'
    $f['fr'] = $na
    $f['name'] = '資料結構、衍生概念與角色權限'
    $f['order'] = 1
    $f['dependsOn'] = @()
    $fm = New-PsSdObject
    $fm['entities'] = @($Items['ENT'] | ForEach-Object { [string]$_['id'] })
    $fm['fields'] = @($Items['FLD'] | ForEach-Object { [string]$_['id'] })
    $fm['derivations'] = @($Items['DRV'] | ForEach-Object { [string]$_['id'] })
    $fm['roles'] = @($Items['ROLE'] | ForEach-Object { [string]$_['id'] })
    $f['members'] = $fm
    $f['deliverables'] = @('DATA_STRUCTURE', 'SECURITY')
    $out.Add($f)
    $n = 0
    foreach ($k2 in $sk) {
        $s = $smap[$k2]; $fr = $s.Fr; $n++
        $tid = $taskByFr[[string]$fr['id']]
        $t = New-PsSdComputedItem $tid ('SLICE:' + $s.Key) 'COMPUTED' @()
        $t['taskKind'] = 'SLICE'
        $t['fr'] = [string]$fr['id']
        $t['name'] = $fr['name']
        $t['order'] = $n + 1
        $deps = @($foundId)
        $real = @(); foreach ($x in @($fr['realizes'])) { if ($null -ne $x) { $real += [string]$x } }
        if ($real.Count -gt 0) {
            $rk = [System.Collections.Generic.List[string]]::new(); $rmap = New-PsSdMap
            foreach ($x in $real) { $kk = ([int](& $trnLevel $x)).ToString('D4', [System.Globalization.CultureInfo]::InvariantCulture) + [char]0 + [string]$trns[$x]['key']; $rk.Add($kk); $rmap[$kk] = $x }
            $rk.Sort([System.StringComparer]::Ordinal)
            $first = $rmap[$rk[0]]
            $src = [string]$trns[$first]['from']
            if ($src -cne 'INITIAL' -and $firstReach.ContainsKey($src)) {
                $pred = $firstReach[$src]
                if ($frOfTrn.ContainsKey($pred)) { foreach ($fid in $frOfTrn[$pred]) { if ($fid -cne [string]$fr['id'] -and $taskByFr.ContainsKey($fid) -and $deps -cnotcontains $taskByFr[$fid]) { $deps += $taskByFr[$fid] } } }
            }
        }
        $t['dependsOn'] = $deps
        $t['members'] = & $members $fr
        $t['deliverables'] = @('OPERATIONS', 'SCREENS', 'RULES', 'TESTS')
        $out.Add($t)
    }
    # 依 ID 排序
    $ik = [System.Collections.Generic.List[string]]::new(); $imap = New-PsSdMap
    foreach ($t in $out) { $ik.Add([string]$t['id']); $imap[[string]$t['id']] = $t }
    $ik.Sort([System.StringComparer]::Ordinal)
    $res = @(); foreach ($k in $ik) { $res += , $imap[$k] }
    return , $res
}

function Get-PsSdDodItems {
    # 18：全域條件（模板）＋每個工作的完成條件（由工作成員反查）。
    param($Registry, $Items, $ById, [object[]]$Tasks)
    $crit = {
        param([string]$Kind, [string]$Statement, $Refs, [string]$Ev)
        $c = New-PsSdObject; $c['kind'] = $Kind; $c['statement'] = $Statement; $c['refs'] = @($Refs); $c['evidenceRequired'] = $Ev
        return , $c
    }
    $defs = [System.Collections.Generic.List[object]]::new()
    $bind = @(); foreach ($s in $Items['STATE']) { if ($s.Contains('binding')) { $bind += [string]$s['binding'] } }
    $xfs = @(); foreach ($x in $Items['XF']) { $xfs += [string]$x['id'] }
    $g = @()
    $g += , (& $crit 'STORED_VALUES_PRESERVED' '狀態碼與選項儲存值與 07 的值域完全相同。' (Get-PsSdSortedIds $bind) 'TEST_REPORT')
    $g += , (& $crit 'NO_EXCLUDED_FIELDS' '07「不建置的原生欄位」沒有出現在資料結構、畫面與規則。' $xfs 'CODE_REFERENCE')
    $g += , (& $crit 'BLANK_SEMANTICS_PRESERVED' '空白、0 與 NULL 的比較照共同定義實作。' @() 'TEST_REPORT')
    $g += , (& $crit 'TRACE_IDS_RECORDED' '程式與測試都標註實作的 ID。' @() 'CODE_REFERENCE')
    $g += , (& $crit 'OPEN_QUESTIONS_CLOSED' '影響本工作項目的 BLOCKING 問題都已在 19 有決策。' @() 'REVIEW_RECORD')
    $defs.Add(@{ Key = 'GLOBAL:BASELINE'; Scope = 'GLOBAL'; Basis = 'TEMPLATE'; Task = $null; Criteria = $g })
    foreach ($t in $Tasks) {
        $m = $t['members']
        $cs = @()
        if ([string]$t['taskKind'] -ceq 'FOUNDATION') {
            $cs += , (& $crit 'STORED_VALUES_PRESERVED' '實體、欄位、值域與衍生概念照 07 建立。' (@($m['entities']) + @($m['derivations'])) 'CODE_REFERENCE')
            $perms = @(); foreach ($p in $Items['PERM']) { $perms += [string]$p['id'] }
            $cs += , (& $crit 'RULES_IMPLEMENTED' '角色與資料範圍照 03 建立。' $perms 'TEST_REPORT')
        } else {
            if (@($m['tests']).Count -gt 0) { $cs += , (& $crit 'TESTS_PASS' '本工作的測試案例全數通過。' $m['tests'] 'TEST_REPORT') }
            $acts = @(); if ($m.Contains('activities')) { $acts = @($m['activities']) }
            $st = '本工作的轉移、規則與操作都已實作。'
            if ($acts.Count -gt 0) { $st = '本工作的轉移、活動、規則與操作都已實作。' }
            $cs += , (& $crit 'RULES_IMPLEMENTED' $st (@($m['transitions']) + $acts + @($m['rules']) + @($m['operations'])) 'CODE_REFERENCE')
            $msgs = @()
            foreach ($iid in @(@($m['rules']) + @($m['operations']))) { if ($ById.ContainsKey([string]$iid)) { foreach ($x in (Get-PsSdItemRefs $ById[[string]$iid])) { if ($x.StartsWith('MSG-')) { $msgs += $x } } } }
            $msgs = Get-PsSdSortedIds $msgs
            if ($msgs.Count -gt 0) { $cs += , (& $crit 'MESSAGES_PRESERVED' '訊息原文與觸發條件與 09 一致。' $msgs 'TEST_REPORT') }
        }
        $defs.Add(@{ Key = ('TASK:' + [string]$t['key']); Scope = 'TASK'; Basis = 'COMPUTED'; Task = [string]$t['id']; Criteria = $cs })
    }
    $keys = @(); foreach ($d in $defs) { $keys += $d.Key }
    [void](Register-PsSdKeys $Registry 'DOD' $keys)
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($d in $defs) {
        $o = New-PsSdComputedItem (Get-PsSdRegisteredId $Registry 'DOD' $d.Key) $d.Key $d.Basis @()
        $o['scope'] = $d.Scope
        if ($null -ne $d.Task) { $o['task'] = $d.Task }
        $o['criteria'] = @($d.Criteria)
        $out.Add($o)
    }
    $ik = [System.Collections.Generic.List[string]]::new(); $imap = New-PsSdMap
    foreach ($t in $out) { $ik.Add([string]$t['id']); $imap[[string]$t['id']] = $t }
    $ik.Sort([System.StringComparer]::Ordinal)
    $res = @(); foreach ($k in $ik) { $res += , $imap[$k] }
    return , $res
}

function Get-PsSdStage0Questions {
    # 第 0 階段：第 2 輪仍無多數的事實 → STATUS_READING_CONFLICT；多數讀者列出的圖與圖矛盾 → STATUS_SELF_CONFLICT。回傳 @{ Key; Category; Question } 陣列。
    param($Result, [string]$StatusRef)
    $out = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $Result) { return , $out.ToArray() }
    foreach ($f in $Result.Unresolved) {
        $locs = @(); $ls = [System.Collections.Generic.List[int]]::new($Result.Cite[$f.Key]); $ls.Sort(); foreach ($x in $ls) { $locs += ('第 ' + $x + ' 行') }
        $parts = @(); foreach ($x in $f.Parts) { $parts += (ConvertTo-PsSdFactPart $x) }
        $out.Add(@{ Key = ('STATUS_READING_CONFLICT:' + (Get-PsSdQKeyPart ($parts -join ':'))); Category = 'STATUS_READING_CONFLICT'
            Question = ('三位讀者對「' + (Get-PsSdFactText $f) + '」第 2 輪仍沒有過半的同意或否定（' + ($locs -join '、') + '）。請把 STATUS 檔這幾行改清楚（裁決效果 AMEND_INPUT）後重跑。') })
    }
    foreach ($f in (Get-PsSdConflictFacts $Result)) {
        $ls = @(); foreach ($x in $f.Parts[1]) { $ls += [string]$x }
        $out.Add(@{ Key = ('STATUS_SELF_CONFLICT:L' + ($ls -join '_L')); Category = 'STATUS_SELF_CONFLICT'
            Question = ('多數讀者認為 STATUS 檔第 ' + ($ls -join '、') + ' 行的圖互相矛盾，又看不出是摘要。請把圖改一致（裁決效果 AMEND_INPUT）後重跑。') })
    }
    return , $out.ToArray()
}

function Build-PsSdModel {
    # 全部項目：研究收據＋專案輸入＋模板＋裁決＋問題彙整＋17／18。
    # $In：SchemaReg、Registry、Skeleton、Built、StageResult、StatusRef、Receipts、ProjectText、ProjectRef、DecisionsText、DecisionsRef、AiTemplate（@{key;category;clause} 陣列）、ExtraQuestions（L5 等，@{Key;Category;Question;Affects;RaisedBy;Status} 陣列）
    param($In)
    $reg = $In.Registry
    $m = Build-PsSdResearchModel $In.SchemaReg $reg $In.Skeleton $In.StatusRef $In.Built $In.Receipts
    $items = $m.Items; $byId = $m.ById; $ctx = $m.EvidenceCtx
    $problems = [System.Collections.Generic.List[string]]::new()
    foreach ($e in $m.Errors) { $problems.Add($e) }
    # 01：專案輸入
    $proj = ConvertFrom-PsSdProjectInput $In.ProjectText $In.ProjectRef
    foreach ($e in $proj.Problems) { $problems.Add($e) }
    $gkeys = @(); for ($i = 0; $i -lt $proj.Goals.Count; $i++) { $gkeys += ('GOAL:' + ($i + 1).ToString('D2', [System.Globalization.CultureInfo]::InvariantCulture)) }
    [void](Register-PsSdKeys $reg 'GOAL' $gkeys)
    for ($i = 0; $i -lt $proj.Goals.Count; $i++) {
        $g = $proj.Goals[$i]
        $ev = New-PsSdObject; $ev['kind'] = 'PROJECT_INPUT'; $ev['locator'] = $In.ProjectRef + '#L' + $g.Line; $ev['excerpt'] = $g.Text
        $o = New-PsSdComputedItem (Get-PsSdRegisteredId $reg 'GOAL' $gkeys[$i]) $gkeys[$i] 'PROJECT_INPUT' @((Add-PsSdEvidence $ctx $ev))
        $nm = $g.Statement; if ($nm.Length -gt 40) { $nm = $nm.Substring(0, 40) + '…' }
        $o['name'] = $nm; $o['statement'] = $g.Statement; $o['successCriteria'] = @($g.Criteria)
        $items['GOAL'].Add($o); $byId[[string]$o['id']] = $o
    }
    $rkeys = @(); foreach ($r in $proj.Resps) { $rkeys += ('RESP:' + $r.Area) }
    [void](Register-PsSdKeys $reg 'RESP' $rkeys)
    $respSorted = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $proj.Resps) {
        $ev = New-PsSdObject; $ev['kind'] = 'PROJECT_INPUT'; $ev['locator'] = $In.ProjectRef + '#L' + $r.Line; $ev['excerpt'] = $r.Text
        $o = New-PsSdComputedItem (Get-PsSdRegisteredId $reg 'RESP' ('RESP:' + $r.Area)) ('RESP:' + $r.Area) 'PROJECT_INPUT' @((Add-PsSdEvidence $ctx $ev))
        $o['area'] = $r.Area; $o['holder'] = $r.Holder
        $respSorted.Add($o)
    }
    foreach ($o in (Get-PsSdSortedById $respSorted)) { $items['RESP'].Add($o); $byId[[string]$o['id']] = $o }
    # 16：模板條款
    $akeys = @(); foreach ($a in @($In.AiTemplate)) { $akeys += [string]$a['key'] }
    [void](Register-PsSdKeys $reg 'AI' $akeys)
    $aiList = [System.Collections.Generic.List[object]]::new()
    foreach ($a in @($In.AiTemplate)) {
        $o = New-PsSdComputedItem (Get-PsSdRegisteredId $reg 'AI' ([string]$a['key'])) ([string]$a['key']) 'TEMPLATE' @()
        $o['category'] = $a['category']; $o['clause'] = $a['clause']
        $aiList.Add($o)
    }
    foreach ($o in (Get-PsSdSortedById $aiList)) { $items['AI'].Add($o); $byId[[string]$o['id']] = $o }
    # 90：問題彙整（研究、缺口、第 0 階段、輸入、讀者）
    $qdefs = [System.Collections.Generic.List[object]]::new()
    foreach ($q in $m.Questions) { $qdefs.Add(@{ Key = $q.Key; Item = $q.Item }) }
    foreach ($g in $m.Gaps) {
        $affects = @(); if ($g.ItemId -and $script:PsSdRefRx.IsMatch([string]$g.ItemId) -and -not ([string]$g.ItemId).StartsWith('Q-')) { $affects += [string]$g.ItemId }
        $qdefs.Add(@{ Key = $g.Key; Category = 'EVIDENCE_GAP'; Question = $g.Text; Affects = $affects; RaisedBy = 'RESEARCH'; Evidence = @($g.Evidence) })
    }
    foreach ($s0 in (Get-PsSdStage0Questions $In.StageResult $In.StatusRef)) { $qdefs.Add(@{ Key = $s0.Key; Category = $s0.Category; Question = $s0.Question; Affects = @(); RaisedBy = 'STATUS_READING'; Evidence = @() }) }
    if (-not $proj.Provided) {
        $qdefs.Add(@{ Key = 'INPUT_MISSING:PROJECT_GOALS'; Category = 'INPUT_MISSING'; Question = ('專案輸入檔 ' + $In.ProjectRef + ' 沒有提供目標與成功標準；01 的目標欄以 NOT_PROVIDED 呈現。需要時補上後重跑。'); Affects = @(); RaisedBy = 'GATE'; Evidence = @() })
    }
    foreach ($xq in @($In.ExtraQuestions)) { if ($null -ne $xq) { $qdefs.Add($xq) } }
    $qkeys = @(); foreach ($d in $qdefs) { $qkeys += $d.Key }
    [void](Register-PsSdKeys $reg 'Q' $qkeys)
    $qList = [System.Collections.Generic.List[object]]::new()
    $qSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($d in $qdefs) {
        if (-not $qSeen.Add($d.Key)) { continue }
        if ($d.ContainsKey('Item')) { $qList.Add($d.Item); continue }
        $o = New-PsSdComputedItem (Get-PsSdRegisteredId $reg 'Q' $d.Key) $d.Key 'COMPUTED' @($d.Evidence)
        $o['category'] = $d.Category
        if ($script:PsSdInfoCategories -contains $d.Category) { $o['severity'] = 'INFO' } else { $o['severity'] = 'BLOCKING' }
        $o['question'] = $d.Question
        $o['affects'] = @($d.Affects)
        $o['raisedBy'] = $d.RaisedBy
        $st = 'OPEN'; if ($d.ContainsKey('Status') -and $d.Status) { $st = $d.Status }
        $o['status'] = $st
        $qList.Add($o)
    }
    $qById = New-PsSdMap
    foreach ($q in $qList) { $qById[[string]$q['id']] = $q }
    # 19：裁決
    $dec = ConvertFrom-PsSdDecisions $In.DecisionsText $In.DecisionsRef
    foreach ($e in $dec.Problems) { $problems.Add($e) }
    $dkeys = @(); for ($i = 0; $i -lt $dec.Rows.Count; $i++) { $dkeys += ('DEC:' + ($i + 1).ToString('D4', [System.Globalization.CultureInfo]::InvariantCulture)) }
    [void](Register-PsSdKeys $reg 'DEC' $dkeys)
    for ($i = 0; $i -lt $dec.Rows.Count; $i++) {
        $r = $dec.Rows[$i]
        if (-not $qById.ContainsKey($r.QId)) { $problems.Add($In.DecisionsRef + '#L' + $r.Line + '：本版沒有 ' + $r.QId + '（問題 ID 以 90 為準）'); continue }
        $q = $qById[$r.QId]
        $ev = New-PsSdObject; $ev['kind'] = 'HUMAN_DECISION'; $ev['locator'] = $In.DecisionsRef + '#L' + $r.Line; $ev['excerpt'] = $r.Text
        $o = New-PsSdComputedItem (Get-PsSdRegisteredId $reg 'DEC' $dkeys[$i]) $dkeys[$i] 'HUMAN_DECISION' @((Add-PsSdEvidence $ctx $ev))
        $o['title'] = $r.Decision
        $o['context'] = ($r.QId + '：' + [string]$q['question'])
        $o['decision'] = $r.Decision
        $o['rationale'] = $r.Rationale
        $o['decidedBy'] = $r.DecidedBy
        $o['decidedOn'] = $r.DecidedOn
        $o['status'] = 'ACCEPTED'
        $o['resolves'] = @($r.QId)
        $o['affects'] = @($q['affects'])
        $o['effect'] = $r.Effect
        $items['DEC'].Add($o); $byId[[string]$o['id']] = $o
        if ($r.Effect -eq 'ACCEPT_GAP') { $q['status'] = 'ACCEPTED_AS_GAP' } else { $q['status'] = 'ANSWERED' }
    }
    foreach ($o in (Get-PsSdSortedById $qList)) { $items['Q'].Add($o); $byId[[string]$o['id']] = $o }
    # 17／18
    $tasks = Get-PsSdTaskItems $reg $items $byId
    foreach ($t in $tasks) { $items['TASK'].Add($t); $byId[[string]$t['id']] = $t }
    $dods = Get-PsSdDodItems $reg $items $byId $tasks
    foreach ($d in $dods) { $items['DOD'].Add($d); $byId[[string]$d['id']] = $d }
    # 90 外殼：只計數的定義值
    $sup = New-PsSdObject
    $codes = [System.Collections.Generic.List[object]]::new()
    $seenC = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($c in $m.DefinitionOnlyCodes) { if ($seenC.Add([string]$c['entityKey'] + ':' + [string]$c['code'])) { $codes.Add($c) } }
    $sup['definitionOnlyCount'] = $codes.Count
    $sup['definitionOnlyCodes'] = $codes.ToArray()
    return @{
        Items = $items; ById = $byId; ItemReceipt = $m.ItemReceipt; Evidence = $ctx.Evidence; Problems = $problems
        ProjectProvided = $proj.Provided; StatusTexts = $m.StatusTexts; ProgramDispositions = $m.ProgramDispositions
        Pages = $m.Pages; Records = $m.Records; Suppressed = $sup; Requests = $m.Requests
    }
}

function Get-PsSdSortedById {
    param($List)
    $ik = [System.Collections.Generic.List[string]]::new(); $imap = New-PsSdMap
    foreach ($t in $List) {
        $id = [string]$t['id']; $p = Get-PsSdIdPrefix $id
        $num = [int]$id.Substring($p.Length + 1)
        $k = $p + [char]0 + $num.ToString('D8', [System.Globalization.CultureInfo]::InvariantCulture)
        $ik.Add($k); $imap[$k] = $t
    }
    $ik.Sort([System.StringComparer]::Ordinal)
    $res = @(); foreach ($k in $ik) { $res += , $imap[$k] }
    return , $res
}

# ---------------- 文件外殼 ----------------
function Get-PsSdDocItems {
    param($Model, [string]$Doc)
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($p in $script:PsSdDocPrefixes[$Doc]) { foreach ($it in $Model.Items[$p]) { $out.Add($it) } }
    return , $out.ToArray()
}

function Get-PsSdFrameworkFingerprint {
    param($SchemaReg)
    $ids = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $SchemaReg.Schemas.Keys) { if (([string]$k).StartsWith('urn:ps-spec:schema:')) { $ids.Add([string]$k) } }
    $ids.Sort([System.StringComparer]::Ordinal)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($k in $ids) { [void]$sb.Append((ConvertTo-PsSdCanonical $SchemaReg.Schemas[$k])) }
    return (Get-PsSdTextHash $sb.ToString())
}

function New-PsSdEnvelope {
    # $Meta：JobId、Revision、Components、FrameworkFp、StatusRef、StatusFp、ProjectRef、ProjectFp、DecisionsRef、DecisionsFp、StatusReading
    param($Model, [string]$Doc, $Gate, $Meta, $Approval)
    $items = Get-PsSdDocItems $Model $Doc
    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($it in $items) { [void]$ids.Add([string]$it['id']) }
    $extra = New-PsSdObject
    switch ($Doc) {
        '01-overview' { if ($Model.ProjectProvided) { $extra['projectInputStatus'] = 'PROVIDED' } else { $extra['projectInputStatus'] = 'NOT_PROVIDED' } }
        '04-workflow' { $extra['statusReading'] = $Meta.StatusReading; $extra['statusTexts'] = @($Model.StatusTexts) }
        '09-business-logic' { $extra['programDispositions'] = @($Model.ProgramDispositions) }
        '90-questions' { $extra['suppressed'] = $Model.Suppressed }
    }
    $deps = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($it in $items) { foreach ($r in (Get-PsSdItemRefs $it)) { $d = Get-PsSdDocOfId $r; if ($d -and $d -cne $Doc) { [void]$deps.Add($d) } } }
    foreach ($s in (Get-PsSdStringsOf $extra)) { if ($script:PsSdRefRx.IsMatch($s)) { $d = Get-PsSdDocOfId $s; if ($d -and $d -cne $Doc) { [void]$deps.Add($d) } } }
    $depList = @(); foreach ($d in $script:PsSdDocOrder) { if ($deps.Contains($d)) { $depList += $d } }
    $evKind = New-PsSdMap
    foreach ($e in $Model.Evidence) { $evKind[[string]$e['id']] = [string]$e['kind'] }
    $kinds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $research = [System.Collections.Generic.List[string]]::new()
    foreach ($it in $items) {
        foreach ($e in @($it['evidence'])) {
            if ($null -eq $e -or -not $evKind.ContainsKey([string]$e)) { continue }
            $k = $evKind[[string]$e]; [void]$kinds.Add($k)
            if (@('CHUNK', 'SQL', 'METADATA_RECEIPT', 'NN', 'WIKI') -contains $k) { $research.Add([string]$e) }
        }
    }
    $sources = [System.Collections.Generic.List[object]]::new()
    $sources.Add((New-PsSdOrderedFrom @('kind', 'FRAMEWORK', 'ref', 'schemas/1.0', 'fingerprint', $Meta.FrameworkFp)))
    if ($kinds.Contains('STATUS_DOC') -or $Doc -eq '04-workflow') { $sources.Add((New-PsSdOrderedFrom @('kind', 'STATUS_DOC', 'ref', $Meta.StatusRef, 'fingerprint', $Meta.StatusFp))) }
    if ($kinds.Contains('PROJECT_INPUT')) { $sources.Add((New-PsSdOrderedFrom @('kind', 'PROJECT_INPUT', 'ref', $Meta.ProjectRef, 'fingerprint', $Meta.ProjectFp))) }
    if ($kinds.Contains('HUMAN_DECISION')) { $sources.Add((New-PsSdOrderedFrom @('kind', 'HUMAN_DECISION', 'ref', $Meta.DecisionsRef, 'fingerprint', $Meta.DecisionsFp))) }
    if ($research.Count -gt 0) {
        $rs = Get-PsSdSortedIds $research
        $sigs = @(); foreach ($e in $Model.Evidence) { if ($rs -ccontains [string]$e['id']) { $sigs += (Get-PsSdEvidenceSignature $e) } }
        $sources.Add((New-PsSdOrderedFrom @('kind', 'RESEARCH_RECEIPT', 'ref', ('receipts/' + $Doc), 'fingerprint', (Get-PsSdTextHash ($sigs -join "`n")))))
    }
    $openq = @()
    foreach ($q in $Model.Items['Q']) {
        if ([string]$q['status'] -cne 'OPEN') { continue }
        $hit = $false; foreach ($a in @($q['affects'])) { if ($ids.Contains([string]$a)) { $hit = $true } }
        if ($hit) { $openq += [string]$q['id'] }
    }
    $openq = Get-PsSdSortedIds $openq
    $counts = New-PsSdMap
    foreach ($it in $items) { $p = Get-PsSdIdPrefix ([string]$it['id']); if ($counts.ContainsKey($p)) { $counts[$p]++ } else { $counts[$p] = 1 } }
    $parts = @(); foreach ($p in $script:PsSdDocPrefixes[$Doc]) { if ($counts.ContainsKey($p)) { $parts += ($script:PsSdPrefixInfo[$p].Label + ' ' + $counts[$p]) } }
    $summary = '無項目'; if ($parts.Count -gt 0) { $summary = $parts -join '、' }
    if ($Doc -eq '90-questions') {
        $st = New-PsSdMap; $blk = 0
        foreach ($q in $items) { $s = [string]$q['status']; if ($st.ContainsKey($s)) { $st[$s]++ } else { $st[$s] = 1 }; if ($s -ceq 'OPEN' -and [string]$q['severity'] -ceq 'BLOCKING') { $blk++ } }
        $sp = @(); foreach ($k in @('OPEN', 'ANSWERED', 'WITHDRAWN', 'ACCEPTED_AS_GAP')) { if ($st.ContainsKey($k)) { $sp += ($k + ' ' + $st[$k]) } }
        if ($sp.Count -gt 0) { $summary += '（' + ($sp -join '、') + '）' }
        $summary += '；未解 BLOCKING ' + $blk + '；只計數的定義值 ' + $Model.Suppressed['definitionOnlyCount']
    } elseif ($Doc -ne '19-decision-log' -and $Doc -ne '16-ai-instructions') {
        $summary += '；未解問題 ' + $openq.Count
    }
    $applicable = @(); foreach ($k in @('L1', 'L2', 'L3', 'L4', 'L5')) { if ([string]$Gate[$k] -cne 'NOT_APPLICABLE') { $applicable += $k } }
    $status = 'in_review'
    foreach ($k in $applicable) { if ([string]$Gate[$k] -cne 'PASS') { $status = 'draft' } }
    if ($status -eq 'in_review' -and $null -ne $Approval) { $status = 'approved' }
    $env = New-PsSdObject
    $env['schemaVersion'] = '1.0'
    $env['docType'] = $Doc
    $env['docId'] = $Meta.JobId + '/' + $Doc.Substring(0, 2)
    $env['jobId'] = $Meta.JobId
    $env['revision'] = $Meta.Revision
    $env['status'] = $status
    $env['title'] = $script:PsSdDocTitles[$Doc]
    $env['summary'] = $summary
    $env['components'] = @($Meta.Components)
    $env['dependsOn'] = $depList
    $env['sources'] = $sources.ToArray()
    $env['gate'] = $Gate
    $env['openQuestions'] = $openq
    if ($null -ne $Approval -and $status -eq 'approved') { $env['approval'] = $Approval }
    foreach ($k in @($extra.Keys)) { $env[[string]$k] = $extra[$k] }
    $env['items'] = $items
    return , $env
}

function Get-PsSdDocHash {
    # canonical 文件正規化後的 sha256：不含 status、gate、approval、revision；鍵逐層依字元碼排序。
    param($Envelope)
    $o = New-PsSdObject
    foreach ($k in @($Envelope.Keys)) { if (@('status', 'gate', 'approval', 'revision') -cnotcontains [string]$k) { $o[[string]$k] = $Envelope[$k] } }
    return (Get-PsSdTextHash (ConvertTo-PsKnJson -Value $o -SortKeys))
}

function New-PsSdGate {
    param([string]$Doc)
    $g = New-PsSdObject
    foreach ($k in @('L1', 'L2', 'L3', 'L4', 'L5')) { $g[$k] = 'NOT_RUN' }
    if (@('16-ai-instructions', '19-decision-log', '90-questions') -contains $Doc) { $g['L3'] = 'NOT_APPLICABLE' }
    if (@('16-ai-instructions', '17-tasks', '18-definition-of-done', '19-decision-log', '90-questions') -contains $Doc) { $g['L4'] = 'NOT_APPLICABLE' }
    if (@('02-functional-requirements', '03-roles-permissions', '04-workflow', '05-ui', '06-architecture', '07-database', '08-api', '09-business-logic') -notcontains $Doc) { $g['L5'] = 'NOT_APPLICABLE' }
    return , $g
}

function Get-PsSdEvidenceDoc {
    param($Model, [string]$JobId, [string]$Revision)
    $o = New-PsSdObject
    $o['schemaVersion'] = '1.0'; $o['jobId'] = $JobId; $o['revision'] = $Revision; $o['items'] = $Model.Evidence.ToArray()
    return , $o
}
