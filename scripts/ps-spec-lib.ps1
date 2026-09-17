# ps-spec-lib.ps1 — Spec 引擎共用邏輯：Component＋私有需求包（pack）→ EXTRACT facts／COMPOSE 單位 → 外環派工與驗收
#                   → 確定性 render（slot 置換模板副本）→ gate；結論碼 SPEC1-<stage>-<code>[-<count>]。
# 由 ps-spec.ps1（CLI）與 scripts/tests/test-spec.ps1 dot-source。
# 前置：先 dot-source scripts/ps-knowledge-lib.ps1（讀檔／hash／canonical JSON／原子寫入／NN 解析／索引）
#       與 scripts/ps-supplemental-lib.ps1（KnowledgeNeed → 補研究 request／result／完成邊界）。
# 三層責任：本檔＋capabilities.json＝generic engine（本 repo）；.ps-private/spec/<packId>/＝私有映射（公司機）；
#           SoT＝facts＋片段收據（receipts）＋trace，spec.md 只是投影。
# 純函式庫：dot-source 無副作用、不呼叫模型、不查 DB；session 啟動由呼叫端以 -Dispatch scriptblock 注入。
# PowerShell 5.1 紀律：無三元運算子／空合併／條件成員存取／管線串接運算子；Join-Path 兩參數；-LiteralPath；Ordinal 排序；[System.IO.File]＋UTF8Encoding($false)；
#           JSON 只用 ConvertTo-PsKnJson（跨機 hash 一律 -SortKeys）／ConvertFrom-Json。
# 通用函式取自 issue17 分支 ps-contract-lib.ps1（改前綴 PsSp、逐處註明）：Get-CtSections／Get-CtTableRows／Test-CtHollow／
#           Read-CtFragment 骨架／Test-CtSelectOnly／Get-CtId／Get-CtUniqueId／New-CtGateResult。分母、renderer、-Accept 路徑全部重寫。

$script:PsSpecLibVersion = 1
$script:PsSpecSchemaVersion = 1
$script:PsSpIdRx = '^[a-z0-9][a-z0-9-]{0,31}$'
$script:PsSpReqIdRx = '^R[0-9]{2,4}$'
$script:PsSpSlotIdRx = '^S[0-9]{2,4}$'
$script:PsSpChecklistIdRx = '^C[0-9]{2,4}$'
$script:PsSpAttemptRx = '^a[0-9]{4}$'
$script:PsSpApplyOps = @('ALWAYS', 'FACT_TRUE', 'FACT_FALSE', 'ALL', 'ANY', 'NOT')
$script:PsSpCardinalities = @('ONE', 'ANY', 'ALL_DISCOVERED')
$script:PsSpRejectReasons = @('NOT_RELEVANT', 'DUPLICATE', 'NO_EVIDENCE', 'OUT_OF_SCOPE')
$script:PsSpLeakMarkers = @('"agent"', '"findings"', '"searchScope"', '"coverage"', '"dynamicRuntimeWarnings"', '"structureLines"')
$script:PsSpGradeRank = @{ AUDITED_CLEAN = 4; AUDITED_ISSUES = 3; UNAUDITED = 2; PARTIAL = 1; BLOCKED = 0 }
$script:PsSpPolicyMin = @{ AUDITED = 4; STATIC = 2; ANY = 0 }
$script:PsSpPhases = @('PLANNED', 'RUNNING', 'WAITING_KNOWLEDGE', 'WAITING_AUDIT', 'READY', 'PUBLISHED', 'BLOCKED')
$script:PsSpMaxFragmentLines = 150
$script:PsSpMaxContextFileLines = 150
$script:PsSpMaxContextTotalLines = 400
$script:PsSpMaxAttempts = 2
$script:PsSpFragmentSection = '事實'
$script:PsSpRejectSection = '未採用'
$script:PsSpRejectHeader = @('來源條目', '原因')
$script:PsSpBehaviorSection = '行為邏輯'

# ── 通用小工具（取自 ps-contract-lib.ps1）─────────────────────────

# 取自 ps-contract-lib.ps1 Get-CtSections：## 節名 → 節內文（重複節名後者覆蓋；fragment 用）
function Get-PsSpSections {
    param([string]$Text)
    $map = [ordered]@{}
    $cur = ''
    $buf = New-Object System.Text.StringBuilder
    foreach ($ln in ($Text -split "`r?`n")) {
        if ($ln -match '^##\s+(.+?)\s*$') {
            if ($cur -ne '') { $map[$cur] = $buf.ToString() }
            $cur = $Matches[1].Trim()
            $buf = New-Object System.Text.StringBuilder
            continue
        }
        if ($cur -ne '') { [void]$buf.AppendLine($ln) }
    }
    if ($cur -ne '') { $map[$cur] = $buf.ToString() }
    return $map
}

# 取自 ps-contract-lib.ps1 Get-CtTableRows：節內第一張表 → @{ Header; Rows=@(@(cells)) }
function Get-PsSpTableRows {
    param([string]$SectionText)
    $header = $null
    $rows = @()
    $inTable = $false
    foreach ($ln in ($SectionText -split "`r?`n")) {
        if ($ln -notmatch '^\s*\|') { if ($inTable) { break } else { continue } }
        if ($ln -match '^\s*\|[\s:|-]+\|?\s*$') { $inTable = $true; continue }
        $cells = @($ln.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
        if ($null -eq $header) { $header = $cells; $inTable = $true; continue }
        $rows += , $cells
    }
    return @{ Header = $header; Rows = $rows }
}

# 取自 ps-contract-lib.ps1 Test-CtHollow
function Test-PsSpHollow {
    param([string]$Body)
    $t = [regex]::Replace($Body, '(?s)<!--.*?-->', '')
    $t = [regex]::Replace($t, '(?m)^\s*[-*]?\s*<[^>]+>\s*$', '')
    $t = $t.Trim()
    if ($t -eq '') { return $true }
    if ($t -match '^[（(]\s*(無|同前|略)') { return $true }
    return $false
}

# 取自 ps-contract-lib.ps1 Test-CtSelectOnly（SQL 型證據只准 SELECT、須列數上限、無省略號）
function Test-PsSpSelectOnly {
    param([string]$Sql)
    $s = $Sql.Trim().Trim('`').Trim()
    if ($s -eq '' -or $s -eq 'NOT_APPLICABLE') { return $false }
    if ($s -notmatch '^(?i)select\s') { return $false }
    if ($s -match '(?i)\b(insert|update|delete|merge|drop|alter|create|truncate|grant|revoke|begin|declare|execute|exec)\b') { return $false }
    if ($s -match ';') { return $false }
    if ($s -match '…|\.\.\.') { return $false }
    if ($s -notmatch '(?i)fetch\s+first\s+\d+\s+rows\s+only|rownum\s*<=?\s*\d+') { return $false }
    return $true
}

# 取自 ps-contract-lib.ps1 Get-CtId／Get-CtUniqueId：stable ID（非 [A-Z0-9_#$] 消毒成 _；同鍵重複列 .2 .3）
function Get-PsSpId {
    param([string]$Prefix, [string[]]$Parts)
    $p = @($Parts | ForEach-Object { ([string]$_).Trim().ToUpperInvariant() -replace '[^A-Z0-9_#$]', '_' })
    return ($Prefix + '.' + ($p -join '.'))
}
function Get-PsSpUniqueId {
    param([string]$Base, $Seen)
    $n = 1; $id = $Base
    while ($Seen.ContainsKey($id)) { $n++; $id = $Base + '.' + $n }
    $Seen[$id] = $true
    return $id
}

# 取自 ps-contract-lib.ps1 New-CtGateResult
function New-PsSpGateResult {
    param([string]$Gate, [string]$State, [int]$Num, [int]$Den, [string]$Note)
    return [ordered]@{ gate = $Gate; state = $State; numerator = $Num; denominator = $Den; note = $Note }
}

function Read-PsSpJsonFile {
    param([string]$LiteralPath)
    $t = Read-PsKnText -LiteralPath $LiteralPath
    if ($null -eq $t) { return $null }
    try { return ($t | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

function Test-PsSpId { param([string]$Id) return ($Id -match $script:PsSpIdRx) }

function Get-PsSpPropNames {
    param($Obj)
    $names = @()
    if ($null -eq $Obj) { return , $names }
    if ($Obj -is [System.Collections.IDictionary]) { foreach ($k in $Obj.Keys) { $names += [string]$k }; return , $names }
    foreach ($p in $Obj.PSObject.Properties) { $names += $p.Name }
    return , $names
}
function Get-PsSpProp {
    param($Obj, [string]$Name)
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [System.Collections.IDictionary]) { if ($Obj.Contains($Name)) { return $Obj[$Name] }; return $null }
    $p = $Obj.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}
function Test-PsSpInt { param($V) return ($V -is [int] -or $V -is [long] -or $V -is [int16] -or $V -is [byte]) }

# ── 目錄 ─────────────────────────────────────────────────────────

function Get-PsSpDirs {
    param([string]$Root, [string]$PrivateRoot = '', [string]$RuntimeRoot = '', [string]$PackId = '', [string]$JobId = '')
    if ($PrivateRoot -eq '') { $PrivateRoot = Join-Path $Root (Join-Path '.ps-private' 'spec') }
    if ($RuntimeRoot -eq '') { $RuntimeRoot = Join-Path $Root (Join-Path '.ps-runtime' 'spec') }
    $d = @{
        Root = $Root; PrivateRoot = $PrivateRoot; RuntimeRoot = $RuntimeRoot
        Research = (Join-Path $Root (Join-Path 'docs' 'ps-research'))
        SpecGeneric = (Join-Path $Root (Join-Path '.opencode' (Join-Path 'peoplesoft' 'spec')))
        PackDir = ''; JobDir = ''; Plans = ''; Attempts = ''; Receipts = ''; Outputs = ''; JobFile = ''; CurrentFile = ''
    }
    $d.Capabilities = Join-Path $d.SpecGeneric 'capabilities.json'
    $d.GenericManifest = Join-Path $d.SpecGeneric 'generic.manifest.json'
    if ($PackId -ne '') { $d.PackDir = Join-Path $PrivateRoot $PackId }
    if ($JobId -ne '') {
        $d.JobDir = Join-Path $RuntimeRoot $JobId
        $d.Plans = Join-Path $d.JobDir 'plans'
        $d.Attempts = Join-Path $d.JobDir 'attempts'
        $d.Receipts = Join-Path $d.JobDir 'receipts'
        $d.Outputs = Join-Path $d.JobDir 'outputs'
        $d.JobFile = Join-Path $d.JobDir 'job.json'
        $d.CurrentFile = Join-Path $d.JobDir 'current.json'
    }
    return $d
}

function Get-PsSpCapabilities {
    param([string]$Root)
    $p = (Get-PsSpDirs -Root $Root).Capabilities
    $t = Read-PsKnText -LiteralPath $p
    if ($null -eq $t) { throw "找不到能力目錄 $p" }
    return ($t | ConvertFrom-Json -ErrorAction Stop)
}
function Get-PsSpFactKind {
    param($Capabilities, [string]$FactKind)
    if ($null -eq $Capabilities -or $null -eq $Capabilities.factKinds) { return $null }
    $p = $Capabilities.factKinds.PSObject.Properties[$FactKind]
    if ($null -eq $p) { return $null }
    return $p.Value
}

# ── 私有需求包驗證（PS 5.1 自製 validator；拒未知欄位）─────────────

function Get-PsSpApplicabilityRefs {
    param($App)
    $refs = @()
    if ($null -eq $App) { return , $refs }
    $op = ([string](Get-PsSpProp $App 'op')).ToUpperInvariant()
    if ($op -eq 'FACT_TRUE' -or $op -eq 'FACT_FALSE') { $f = [string](Get-PsSpProp $App 'fact'); if ($f -ne '') { $refs += $f } }
    elseif ($op -eq 'ALL' -or $op -eq 'ANY') { foreach ($a in @(Get-PsSpProp $App 'args')) { $refs += (Get-PsSpApplicabilityRefs -App $a) } }
    elseif ($op -eq 'NOT') { $refs += (Get-PsSpApplicabilityRefs -App (Get-PsSpProp $App 'arg')) }
    return , $refs
}

function Test-PsSpApplicabilitySyntax {
    param($App, [string]$Where, $FactKindProps, [int]$Depth = 0)
    $errs = @()
    if ($null -eq $App) { $errs += ('MISSING_FIELD：' + $Where + '.applicability'); return , $errs }
    if ($Depth -gt 8) { $errs += ('BAD_OP：' + $Where + ' 巢狀過深'); return , $errs }
    $allowed = @('op', 'fact', 'args', 'arg')
    foreach ($n in (Get-PsSpPropNames $App)) { if ($allowed -notcontains $n) { $errs += ('UNKNOWN_FIELD：' + $Where + '.applicability.' + $n) } }
    $op = ([string](Get-PsSpProp $App 'op')).ToUpperInvariant()
    if ($script:PsSpApplyOps -notcontains $op) { $errs += ('BAD_OP：' + $Where + ' op=' + $op); return , $errs }
    if ($op -eq 'FACT_TRUE' -or $op -eq 'FACT_FALSE') {
        $f = [string](Get-PsSpProp $App 'fact')
        $ix = $f.LastIndexOf('.')
        if ($ix -le 0 -or $ix -ge $f.Length - 1) { $errs += ('BAD_FACT_REF：' + $Where + ' ' + $f); return , $errs }
        $fk = $f.Substring(0, $ix); $prop = $f.Substring($ix + 1)
        if (-not $FactKindProps.ContainsKey($fk)) { $errs += ('BAD_FACT_REF：' + $Where + ' factKind 不在目錄：' + $fk) }
        elseif (@($FactKindProps[$fk]) -notcontains $prop) { $errs += ('BAD_FACT_REF：' + $Where + ' property 不在目錄：' + $f) }
    }
    elseif ($op -eq 'ALL' -or $op -eq 'ANY') {
        $args0 = @(Get-PsSpProp $App 'args')
        if ($args0.Count -eq 0) { $errs += ('BAD_OP：' + $Where + ' ' + $op + ' 無 args') }
        $i = 0
        foreach ($a in $args0) { $i++; $errs += (Test-PsSpApplicabilitySyntax -App $a -Where ($Where + '.args[' + $i + ']') -FactKindProps $FactKindProps -Depth ($Depth + 1)) }
    }
    elseif ($op -eq 'NOT') {
        $errs += (Test-PsSpApplicabilitySyntax -App (Get-PsSpProp $App 'arg') -Where ($Where + '.arg') -FactKindProps $FactKindProps -Depth ($Depth + 1))
    }
    return , $errs
}

# 回 @{ Ok; Errors; Pack; Template; TemplateLines; Markers; ContentHash; BindingHash; Signed; PackId; PackVersion; ReviewedVersion; Requirements }
function Test-PsSpPack {
    param([string]$PackDir, $Capabilities)
    $r = @{ Ok = $false; Errors = @(); Pack = $null; Template = $null; TemplateLines = @(); Markers = @(); ContentHash = ''; BindingHash = ''; Signed = $false; PackId = ''; PackVersion = 0; ReviewedVersion = 0; Requirements = @() }
    $pp = Join-Path $PackDir 'pack.json'
    $t = Read-PsKnText -LiteralPath $pp
    if ($null -eq $t) { $r.Errors += 'PACK_NOT_FOUND：pack.json'; return $r }
    $p = $null
    try { $p = $t | ConvertFrom-Json -ErrorAction Stop } catch { $r.Errors += 'PACK_JSON：無法解析'; return $r }
    $r.Pack = $p
    $top = @('schemaVersion', 'packId', 'packVersion', 'reviewedVersion', 'template', 'slots', 'checklist', 'requirements')
    foreach ($n in (Get-PsSpPropNames $p)) { if ($top -notcontains $n) { $r.Errors += ('UNKNOWN_FIELD：' + $n) } }
    foreach ($n in $top) { if ($null -eq (Get-PsSpProp $p $n)) { $r.Errors += ('MISSING_FIELD：' + $n) } }
    if ($r.Errors.Count -gt 0) { return $r }
    if (-not (Test-PsSpInt $p.schemaVersion) -or [int]$p.schemaVersion -ne $script:PsSpecSchemaVersion) { $r.Errors += ('VERSION：schemaVersion ' + $p.schemaVersion) }
    if (-not (Test-PsSpInt $p.packVersion) -or [int]$p.packVersion -lt 1) { $r.Errors += 'BAD_TYPE：packVersion 須為正整數' }
    if (-not (Test-PsSpInt $p.reviewedVersion) -or [int]$p.reviewedVersion -lt 0) { $r.Errors += 'BAD_TYPE：reviewedVersion 須為非負整數' }
    $r.PackId = [string]$p.packId
    if (-not (Test-PsSpId $r.PackId)) { $r.Errors += ('BAD_ID：packId ' + $r.PackId) }
    if ([string]$p.template -eq '' -or ([string]$p.template) -match '[\\/]') { $r.Errors += 'BAD_TYPE：template 須為 pack 目錄內的檔名' }
    else {
        $tt = Read-PsKnText -LiteralPath (Join-Path $PackDir ([string]$p.template))
        if ($null -eq $tt) { $r.Errors += ('TEMPLATE_MISSING：' + [string]$p.template) }
        else {
            $r.Template = $tt
            $r.TemplateLines = Get-PsKnLines -Text $tt
            foreach ($m in [regex]::Matches($tt, '\{\{slot:([^}]*)\}\}')) { if ($r.Markers -notcontains $m.Groups[1].Value) { $r.Markers += $m.Groups[1].Value } }
        }
    }
    $slots = @($p.slots | ForEach-Object { [string]$_ })
    $seenS = @{}
    foreach ($s in $slots) {
        if ($s -notmatch $script:PsSpSlotIdRx) { $r.Errors += ('BAD_ID：slot ' + $s) }
        if ($seenS.ContainsKey($s)) { $r.Errors += ('DUP_ID：slot ' + $s) } else { $seenS[$s] = $true }
        if ($null -ne $r.Template -and $r.Markers -notcontains $s) { $r.Errors += ('SLOT_NOT_IN_TEMPLATE：' + $s) }
    }
    foreach ($m in $r.Markers) { if ($slots -notcontains $m) { $r.Errors += ('MARKER_NOT_IN_SLOTS：' + $m) } }
    $cks = @($p.checklist | ForEach-Object { [string]$_ })
    $seenC = @{}
    foreach ($c in $cks) {
        if ($c -notmatch $script:PsSpChecklistIdRx) { $r.Errors += ('BAD_ID：checklist ' + $c) }
        if ($seenC.ContainsKey($c)) { $r.Errors += ('DUP_ID：checklist ' + $c) } else { $seenC[$c] = $true }
    }
    $fkProps = @{}
    $fkMode = @{}
    foreach ($fp in $Capabilities.factKinds.PSObject.Properties) { $fkProps[$fp.Name] = @($fp.Value.properties | ForEach-Object { [string]$_ }); $fkMode[$fp.Name] = [string]$fp.Value.mode }
    $ctxKeys = @{}
    if ($null -ne $Capabilities.contextKeys) { foreach ($cp in $Capabilities.contextKeys.PSObject.Properties) { $ctxKeys[$cp.Name] = $cp.Value } }
    $reqAllowed = @('id', 'slot', 'checklistRefs', 'factKind', 'required', 'applicability', 'cardinality', 'evidencePolicy', 'properties', 'context')
    $reqs = @($p.requirements)
    if ($reqs.Count -eq 0) { $r.Errors += 'MISSING_FIELD：requirements 為空' }
    $seenR = @{}
    $refC = @{}
    $byFk = @{}
    $norm = @()
    $i = 0
    foreach ($q in $reqs) {
        $i++
        $id = [string](Get-PsSpProp $q 'id')
        $where = 'requirements[' + $i + ']'
        if ($id -ne '') { $where = $id }
        foreach ($n in (Get-PsSpPropNames $q)) { if ($reqAllowed -notcontains $n) { $r.Errors += ('UNKNOWN_FIELD：' + $where + '.' + $n) } }
        foreach ($n in @('id', 'slot', 'checklistRefs', 'factKind', 'required', 'applicability', 'cardinality', 'evidencePolicy')) { if ($null -eq (Get-PsSpProp $q $n)) { $r.Errors += ('MISSING_FIELD：' + $where + '.' + $n) } }
        if ($id -notmatch $script:PsSpReqIdRx) { $r.Errors += ('BAD_ID：requirement ' + $id) }
        if ($seenR.ContainsKey($id)) { $r.Errors += ('DUP_ID：requirement ' + $id) } else { $seenR[$id] = $true }
        $slot = [string](Get-PsSpProp $q 'slot')
        if ($slots -notcontains $slot) { $r.Errors += ('SLOT_UNKNOWN：' + $where + ' slot=' + $slot) }
        $crefs = @(Get-PsSpProp $q 'checklistRefs' | ForEach-Object { [string]$_ })
        foreach ($c in $crefs) { if ($cks -notcontains $c) { $r.Errors += ('CHECKLIST_UNKNOWN：' + $where + ' ' + $c) } else { $refC[$c] = $true } }
        $fk = [string](Get-PsSpProp $q 'factKind')
        $mode = 'UNSUPPORTED'
        if ($fk -eq 'UNSUPPORTED') { }
        elseif (-not $fkProps.ContainsKey($fk)) { $r.Errors += ('FACTKIND_UNKNOWN：' + $where + ' ' + $fk) }
        else { $mode = $fkMode[$fk]; if (-not $byFk.ContainsKey($fk)) { $byFk[$fk] = @() }; $byFk[$fk] += $id }
        $req = Get-PsSpProp $q 'required'
        if ($null -ne $req -and -not ($req -is [bool])) { $r.Errors += ('REQUIRED_NOT_BOOL：' + $where) }
        $card = ([string](Get-PsSpProp $q 'cardinality')).ToUpperInvariant()
        if ($script:PsSpCardinalities -notcontains $card) { $r.Errors += ('BAD_CARDINALITY：' + $where + ' ' + $card) }
        $pol = ([string](Get-PsSpProp $q 'evidencePolicy')).ToUpperInvariant()
        if (@($Capabilities.evidencePolicies) -notcontains $pol) { $r.Errors += ('BAD_POLICY：' + $where + ' ' + $pol) }
        $props = @()
        $pv = Get-PsSpProp $q 'properties'
        if ($null -ne $pv) {
            foreach ($x in @($pv)) { $xs = [string]$x; if ($fkProps.ContainsKey($fk) -and @($fkProps[$fk]) -notcontains $xs) { $r.Errors += ('PROPERTY_UNKNOWN：' + $where + ' ' + $xs) } elseif ($props -notcontains $xs) { $props += $xs } }
        }
        elseif ($fkProps.ContainsKey($fk)) { $props = @($fkProps[$fk]) }
        $ctx = [ordered]@{}
        $cv = Get-PsSpProp $q 'context'
        if ($null -ne $cv) {
            foreach ($n in (Sort-PsKnOrdinal -Items (Get-PsSpPropNames $cv))) {
                $val = ([string](Get-PsSpProp $cv $n)).ToUpperInvariant()
                if (-not $ctxKeys.ContainsKey($n)) { $r.Errors += ('CONTEXT_UNKNOWN：' + $where + ' ' + $n); continue }
                $spec = $ctxKeys[$n]
                if ($spec -is [string]) { if ($val -notmatch [string]$Capabilities.objectNamePattern) { $r.Errors += ('CONTEXT_UNKNOWN：' + $where + ' ' + $n + ' 不符物件名文法') } }
                elseif (@($spec) -notcontains $val) { $r.Errors += ('CONTEXT_UNKNOWN：' + $where + ' ' + $n + '=' + $val) }
                $ctx[$n] = $val
            }
        }
        $app = Get-PsSpProp $q 'applicability'
        if ($null -ne $app) { $r.Errors += (Test-PsSpApplicabilitySyntax -App $app -Where $where -FactKindProps $fkProps) }
        $norm += , ([ordered]@{ id = $id; slot = $slot; checklistRefs = @($crefs); factKind = $fk; mode = $mode; required = [bool]$req; applicability = $app; cardinality = $card; evidencePolicy = $pol; properties = @($props); context = $ctx })
    }
    foreach ($c in $cks) { if (-not $refC.ContainsKey($c)) { $r.Errors += ('CHECKLIST_UNREFERENCED：' + $c) } }
    # 依賴無環（R → 產出其 applicability 所引 factKind 的 requirement；自我引用允許＝驗收後再判）
    $edges = @{}
    foreach ($q in $norm) {
        $edges[$q.id] = @()
        foreach ($ref in (Get-PsSpApplicabilityRefs -App $q.applicability)) {
            $ix = $ref.LastIndexOf('.')
            if ($ix -le 0) { continue }
            $fk = $ref.Substring(0, $ix)
            if (-not $byFk.ContainsKey($fk)) { $r.Errors += ('BAD_FACT_REF：' + $q.id + ' 引用的 ' + $fk + ' 沒有任何 requirement 產出'); continue }
            foreach ($prod in $byFk[$fk]) { if ($prod -ne $q.id -and $edges[$q.id] -notcontains $prod) { $edges[$q.id] += $prod } }
        }
    }
    $color = @{}
    $cycles = 0
    $visit = $null
    $visit = {
        param([string]$n)
        $color[$n] = 1
        foreach ($m in @($edges[$n])) {
            if (-not $color.ContainsKey($m)) { & $visit $m }
            elseif ($color[$m] -eq 1) { $script:PsSpCycleHit++ }
        }
        $color[$n] = 2
    }
    $script:PsSpCycleHit = 0
    foreach ($k in (Sort-PsKnOrdinal -Items @($edges.Keys))) { if (-not $color.ContainsKey($k)) { & $visit $k } }
    if ($script:PsSpCycleHit -gt 0) { $r.Errors += ('CYCLE：applicability 依賴有環（' + $script:PsSpCycleHit + '）') }
    $r.Requirements = @($norm)
    $r.PackVersion = 0; $r.ReviewedVersion = 0
    if (Test-PsSpInt $p.packVersion) { $r.PackVersion = [int]$p.packVersion }
    if (Test-PsSpInt $p.reviewedVersion) { $r.ReviewedVersion = [int]$p.reviewedVersion }
    $r.Signed = ($r.PackVersion -eq $r.ReviewedVersion)
    # contentHash（需求／條件／selector／證據政策）與 bindingHash（slot／模板）分開
    $content = @()
    foreach ($q in $norm) { $content += , ([ordered]@{ id = $q.id; factKind = $q.factKind; required = $q.required; applicability = $q.applicability; cardinality = $q.cardinality; evidencePolicy = $q.evidencePolicy; properties = @($q.properties); context = $q.context; checklistRefs = @($q.checklistRefs) }) }
    $r.ContentHash = Get-PsKnTextHash -Text (ConvertTo-PsKnJson -Value ([ordered]@{ checklist = @($cks); requirements = @($content) }) -SortKeys)
    $bind = @()
    foreach ($q in $norm) { $bind += , ([ordered]@{ id = $q.id; slot = $q.slot }) }
    $th = ''
    if ($null -ne $r.Template) { $th = Get-PsKnTextHash -Text $r.Template }
    $r.BindingHash = Get-PsKnTextHash -Text (ConvertTo-PsKnJson -Value ([ordered]@{ slots = @($slots); binding = @($bind); templateHash = $th }) -SortKeys)
    $r.Ok = ($r.Errors.Count -eq 0)
    return $r
}

# ── 三值 applicability ────────────────────────────────────────────

function Get-PsSpTruth {
    param($V)
    if ($null -eq $V) { return 'UNKNOWN' }
    if ($V -is [bool]) { if ($V) { return 'TRUE' } else { return 'FALSE' } }
    if (Test-PsSpInt $V) { if ([long]$V -gt 0) { return 'TRUE' } else { return 'FALSE' } }
    if ($V -is [string]) {
        $s = $V.Trim().ToUpperInvariant()
        if ($s -eq '' -or $s -eq 'UNKNOWN') { return 'UNKNOWN' }
        if ($s -eq 'FALSE' -or $s -eq 'NOT_APPLICABLE') { return 'FALSE' }
        return 'TRUE'
    }
    if ($V -is [System.Collections.IDictionary]) { if ($V.Count -gt 0) { return 'TRUE' } else { return 'FALSE' } }
    if ($V -is [System.Collections.IEnumerable]) { if (@($V).Count -gt 0) { return 'TRUE' } else { return 'FALSE' } }
    return 'TRUE'
}

# FactValues：hashtable '<factKind>.<property>' → TRUE|FALSE|UNKNOWN（缺鍵＝UNKNOWN；UNKNOWN 永不變 N/A）
function Test-PsSpApplicability {
    param($App, $FactValues)
    if ($null -eq $App) { return 'UNKNOWN' }
    $op = ([string](Get-PsSpProp $App 'op')).ToUpperInvariant()
    switch ($op) {
        'ALWAYS' { return 'TRUE' }
        'FACT_TRUE' { $f = [string](Get-PsSpProp $App 'fact'); if ($FactValues.ContainsKey($f)) { return [string]$FactValues[$f] }; return 'UNKNOWN' }
        'FACT_FALSE' {
            $f = [string](Get-PsSpProp $App 'fact')
            $v = 'UNKNOWN'
            if ($FactValues.ContainsKey($f)) { $v = [string]$FactValues[$f] }
            if ($v -eq 'TRUE') { return 'FALSE' }; if ($v -eq 'FALSE') { return 'TRUE' }; return 'UNKNOWN'
        }
        'NOT' {
            $v = Test-PsSpApplicability -App (Get-PsSpProp $App 'arg') -FactValues $FactValues
            if ($v -eq 'TRUE') { return 'FALSE' }; if ($v -eq 'FALSE') { return 'TRUE' }; return 'UNKNOWN'
        }
        'ALL' {
            $anyU = $false
            foreach ($a in @(Get-PsSpProp $App 'args')) { $v = Test-PsSpApplicability -App $a -FactValues $FactValues; if ($v -eq 'FALSE') { return 'FALSE' }; if ($v -eq 'UNKNOWN') { $anyU = $true } }
            if ($anyU) { return 'UNKNOWN' }; return 'TRUE'
        }
        'ANY' {
            $anyU = $false
            foreach ($a in @(Get-PsSpProp $App 'args')) { $v = Test-PsSpApplicability -App $a -FactValues $FactValues; if ($v -eq 'TRUE') { return 'TRUE' }; if ($v -eq 'UNKNOWN') { $anyU = $true } }
            if ($anyU) { return 'UNKNOWN' }; return 'FALSE'
        }
    }
    return 'UNKNOWN'
}

function Get-PsSpGradeRank { param([string]$Grade) if ($script:PsSpGradeRank.ContainsKey($Grade)) { return [int]$script:PsSpGradeRank[$Grade] }; return -1 }
function Test-PsSpGradeMeetsPolicy {
    param([string]$Grade, [string]$Policy)
    $min = 0
    if ($script:PsSpPolicyMin.ContainsKey($Policy)) { $min = [int]$script:PsSpPolicyMin[$Policy] }
    return ((Get-PsSpGradeRank -Grade $Grade) -ge $min)
}
function Get-PsSpMinGrade {
    param([string[]]$Grades)
    $best = ''
    $bestRank = 99
    foreach ($g in @($Grades)) { $rk = Get-PsSpGradeRank -Grade $g; if ($rk -lt $bestRank) { $bestRank = $rk; $best = $g } }
    if ($best -eq '') { return 'MISSING' }
    return $best
}

# ── 目標身分與 NN 讀取 ─────────────────────────────────────────

# 索引 nn 中主物件＝Component（不分大小寫，含續篇）；多領域 → DomainHint 或最高等級，平手＝AMBIGUOUS
# 回 @{ State=OK|NOT_FOUND|HINT_MISS|AMBIGUOUS; Domain; Files=@(檔名，主檔在前); Entries; Candidates=@(領域); Reason }
function Resolve-PsSpIdentity {
    param($Index, [string]$Component, [string]$DomainHint = '')
    $r = @{ State = 'NOT_FOUND'; Domain = ''; Files = @(); Entries = @(); Candidates = @(); Reason = '' }
    $byDom = [ordered]@{}
    foreach ($e in @($Index.nn)) {
        if (-not [string]::Equals([string]$e.primaryObject, $Component, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $d = [string]$e.domain
        if (-not $byDom.Contains($d)) { $byDom[$d] = @() }
        $byDom[$d] += , $e
    }
    $doms = Sort-PsKnOrdinal -Items @($byDom.Keys | ForEach-Object { [string]$_ })
    $r.Candidates = @($doms)
    if ($doms.Count -eq 0) { return $r }
    $pick = ''
    if ($DomainHint -ne '') {
        if ($doms -contains $DomainHint) { $pick = $DomainHint; $r.Reason = 'HINT' }
        else { $r.State = 'HINT_MISS'; return $r }
    }
    elseif ($doms.Count -eq 1) { $pick = $doms[0]; $r.Reason = 'UNIQUE' }
    else {
        $bestRank = -2; $ties = @()
        foreach ($d in $doms) {
            $rk = -1
            foreach ($e in $byDom[$d]) { $g = Get-PsSpGradeRank -Grade ([string]$e.grade); if ($g -gt $rk) { $rk = $g } }
            if ($rk -gt $bestRank) { $bestRank = $rk; $ties = @($d) } elseif ($rk -eq $bestRank) { $ties += $d }
        }
        if ($ties.Count -ne 1) { $r.State = 'AMBIGUOUS'; return $r }
        $pick = $ties[0]; $r.Reason = 'GRADE'
    }
    $r.Domain = $pick
    $r.State = 'OK'
    $main = @(); $cont = @()
    foreach ($e in $byDom[$pick]) { if ([string]$e.file -match '-\d+\.md$') { $cont += [string]$e.file } else { $main += [string]$e.file } }
    $r.Files = (Sort-PsKnOrdinal -Items $main) + (Sort-PsKnOrdinal -Items $cont)
    $r.Entries = @($byDom[$pick])
    return $r
}

# NN 讀取上下文（快取）：@{ Domain; File; Rel; Path; Text; Lines; Facts; Entry; Grade; Hash }
function Get-PsSpNnCtx {
    param([string]$Root, $Index, [string]$Domain, [string]$File, $Cache)
    $key = $Domain + '/' + $File
    if ($null -ne $Cache -and $Cache.ContainsKey($key)) { return $Cache[$key] }
    $path = Join-Path (Join-Path (Join-Path $Root (Join-Path 'docs' 'ps-research')) $Domain) $File
    $text = Read-PsKnText -LiteralPath $path
    if ($null -eq $text) { return $null }
    $ctx = @{ Domain = $Domain; File = $File; Rel = ('docs/ps-research/' + $Domain + '/' + $File); Path = $path; Text = $text; Lines = (Get-PsKnLines -Text $text); Facts = (Get-PsKnNnFacts -LiteralPath $path -Domain $Domain); Entry = $null; Grade = 'UNAUDITED'; Hash = (Get-PsKnTextHash -Text $text) }
    if ($null -ne $Index) { foreach ($e in @($Index.nn)) { if ([string]$e.domain -ceq $Domain -and [string]$e.file -ceq $File) { $ctx.Entry = $e; $ctx.Grade = [string]$e.grade; break } } }
    if ($null -eq $ctx.Entry) { $ctx.Grade = 'UNAUDITED' }
    if ($null -ne $Cache) { $Cache[$key] = $ctx }
    return $ctx
}

function Get-PsSpSectionHash {
    param([string[]]$Lines, [int]$Start, [int]$End)
    if ($Start -lt 1 -or $Start -gt $Lines.Count) { return '' }
    $e = [Math]::Min($End, $Lines.Count)
    return (Get-PsKnTextHash -Text (($Lines[($Start - 1) .. ($e - 1)]) -join "`n"))
}

# 節（含子節）：@{ name; level; start; end; hash }；找不到回 $null；Name='HEAD' 取檔頭 1..8 行
function Get-PsSpSection {
    param($Ctx, [string]$Name, [int]$Level = 2)
    if ($Name -eq 'HEAD') {
        $e = [Math]::Min(8, $Ctx.Lines.Count)
        return [ordered]@{ name = 'HEAD'; level = 0; start = 1; end = $e; hash = (Get-PsSpSectionHash -Lines $Ctx.Lines -Start 1 -End $e) }
    }
    $sec = Get-PsKnSectionRange -Sections $Ctx.Facts.sections -Name $Name -Level $Level
    if ($null -eq $sec) { return $null }
    return [ordered]@{ name = $Name; level = $Level; start = [int]$sec.start; end = [int]$sec.end; hash = (Get-PsSpSectionHash -Lines $Ctx.Lines -Start ([int]$sec.start) -End ([int]$sec.end)) }
}
function Get-PsSpSectionBody {
    param($Ctx, $Sec)
    if ($null -eq $Sec) { return '' }
    $s = [int]$Sec.start; $e = [Math]::Min([int]$Sec.end, $Ctx.Lines.Count)
    if ($s -ge $e) { return '' }
    return (($Ctx.Lines[$s .. ($e - 1)]) -join "`n")
}
function New-PsSpSourceRef {
    param($Ctx, $Sec, [string]$Role = 'TARGET')
    $sr = [ordered]@{ domain = $Ctx.Domain; file = $Ctx.File; path = $Ctx.Rel; hash = $Ctx.Hash; role = $Role; section = ''; level = 0; lines = ''; sectionHash = '' }
    if ($null -ne $Sec) { $sr.section = [string]$Sec.name; $sr.level = [int]$Sec.level; $sr.lines = ([string]$Sec.start + '-' + [string]$Sec.end); $sr.sectionHash = [string]$Sec.hash }
    return $sr
}

# 一跳 callee：相關物件角色 ∈ followRoles 且索引型別 ∈ followTypes（型別未知＝只認有 NN 檔者）；回 @( @{ Name; Role; Type; Files } )
function Get-PsSpCallees {
    param($Ctx, $Index, $Capabilities)
    $out = @()
    $roles = @($Capabilities.followRoles | ForEach-Object { [string]$_ })
    $types = @($Capabilities.followTypes | ForEach-Object { [string]$_ })
    foreach ($ro in @($Ctx.Facts.relatedObjects)) {
        $hit = $false
        foreach ($r in $roles) { if (([string]$ro.role).IndexOf($r) -ge 0) { $hit = $true; break } }
        if (-not $hit) { continue }
        $name = [string]$ro.name
        $type = ''
        $files = @()
        foreach ($o in @($Index.objects)) {
            if ([string]::Equals([string]$o.object, $name, [System.StringComparison]::OrdinalIgnoreCase) -and [string]$o.type -ne 'UNKNOWN' -and $type -eq '') { $type = ([string]$o.type).ToUpperInvariant() }
        }
        foreach ($e in @($Index.nn)) {
            if ([string]$e.domain -ceq $Ctx.Domain -and [string]::Equals([string]$e.primaryObject, $name, [System.StringComparison]::OrdinalIgnoreCase)) { $files += [string]$e.file }
        }
        if ($files.Count -eq 0) { continue }
        if ($type -ne '' -and $types -notcontains $type) { continue }
        if ($type -eq '') { $type = 'UNKNOWN' }
        $out += , (@{ Name = $name; Role = [string]$ro.role; Type = $type; Files = (Sort-PsKnOrdinal -Items $files) })
    }
    return , $out
}

function Get-PsSpDomainGateClass {
    param($Index, [string]$Domain, [string]$Object)
    $canon = $Object.ToUpperInvariant() -replace '^PS_', ''
    foreach ($d in @($Index.domains)) {
        if ([string]$d.domain -cne $Domain) { continue }
        foreach ($g in @($d.domainGate)) {
            $o = ([string]$g.object).ToUpperInvariant() -replace '^PS_', ''
            if ($o -ceq $canon) { return [string]$g.classification }
        }
    }
    return 'UNCLASSIFIED'
}
function Get-PsSpObjectType {
    param($Index, [string]$Object)
    foreach ($o in @($Index.objects)) { if ([string]::Equals([string]$o.object, $Object, [System.StringComparison]::OrdinalIgnoreCase) -and [string]$o.type -ne 'UNKNOWN') { return [string]$o.type } }
    return 'UNKNOWN'
}
function Get-PsSpWikiEntry {
    param($Index, [string]$Name)
    $cands = @($Name)
    if ($Name -match '^(?i)PS_') { $cands += ($Name.Substring(3)) } else { $cands += ('PS_' + $Name) }
    foreach ($w in @($Index.wiki)) { foreach ($c in $cands) { if ([string]::Equals([string]$w.name, $c, [System.StringComparison]::OrdinalIgnoreCase)) { return $w } } }
    return $null
}
function Get-PsSpWikiGrade {
    param($Wiki)
    if ($null -eq $Wiki) { return 'MISSING' }
    $eff = [string]$Wiki.effective
    if ($eff -eq 'verified') { return 'AUDITED_CLEAN' }
    if ($eff -eq 'draft') { return 'UNAUDITED' }
    return 'PARTIAL'
}

# 節內被引用的附錄列號（附錄 #n／E<nn>.n）→ evidenceRefs
function Get-PsSpCitedEvidence {
    param($Ctx, [string]$Body)
    $refs = @()
    $max = @($Ctx.Facts.evidence).Count
    foreach ($m in [regex]::Matches($Body, '附錄\s*#?(\d+)|\bE\d\d\.(\d+)\b')) {
        $n = 0
        if ($m.Groups[1].Value -ne '') { $n = [int]$m.Groups[1].Value } elseif ($m.Groups[2].Value -ne '') { $n = [int]$m.Groups[2].Value }
        if ($n -lt 1) { continue }
        $dup = $false
        foreach ($x in $refs) { if ([int]$x.row -eq $n) { $dup = $true } }
        if ($dup) { continue }
        $refs += , ([ordered]@{ file = $Ctx.File; row = $n; resolved = ($n -le $max) })
    }
    return , $refs
}

# 可計數條目：行為邏輯＝頂層條列；資料流＝表格列；執行方式＝非空非註解非分隔行；回 @( @{ line; kind; text } )
function Get-PsSpSectionItems {
    param($Ctx, $Sec, [string]$SectionName)
    $items = @()
    if ($null -eq $Sec) { return , $items }
    $s = [int]$Sec.start; $e = [Math]::Min([int]$Sec.end, $Ctx.Lines.Count)
    if ($SectionName -eq '資料流' -or $SectionName -eq '畫面與欄位' -or $SectionName -eq '相關物件') {
        foreach ($row in (Get-PsKnTableRows -Lines $Ctx.Lines -Start $s -End $e)) { $items += , (@{ line = [int]$row.Line; kind = $SectionName; text = $Ctx.Lines[[int]$row.Line - 1] }) }
        return , $items
    }
    for ($i = $s + 1; $i -le $e; $i++) {
        $ln = $Ctx.Lines[$i - 1]
        if ($SectionName -eq '行為邏輯' -or $SectionName -eq '未解事項') {
            if ($ln -match '^[-*]\s+\S') { $items += , (@{ line = $i; kind = $SectionName; text = $ln }) }
            continue
        }
        $t = $ln.Trim()
        if ($t -eq '' -or $t -match '^#{1,6}\s' -or $t -match '^<!--' -or $t -match '^\|[\s:|-]+\|$' -or $t -match '^<[^>]*>$') { continue }
        $items += , (@{ line = $i; kind = $SectionName; text = $ln })
    }
    return , $items
}

# ── EXTRACT facts ─────────────────────────────────────────────────

# 回 @{ Facts=@(); Needs=@( @{ Reason=MISSING|GRADE|CALLEE; Target=@{type;name}; Grade; Ctx } ) }
#   fact：{ factId, factKind, requirementIds[], subject, value, sourceRefs[], evidenceRefs[], grade }
function New-PsSpExtractFacts {
    param($Req, $Cap, $Targets, $Callees, $Index, [string]$Root, [string]$Component, $Cache)
    $r = @{ Facts = @(); Needs = @() }
    $fk = [string]$Req.factKind
    $main = $Targets[0]
    $policy = [string]$Req.evidencePolicy
    $addNeed = {
        param([string]$Reason, [string]$Type, [string]$Name, [string]$Grade, $Ctx)
        $script:PsSpNeedBuf += , (@{ Reason = $Reason; Target = @{ type = $Type; name = $Name }; Grade = $Grade; Ctx = $Ctx })
    }
    $script:PsSpNeedBuf = @()
    $facts = @()
    switch ($fk) {
        'UI.COMPONENT_IDENTITY' {
            $fn = ''; $type = ''
            foreach ($d in @($Index.domains)) { if ([string]$d.domain -ceq $main.Domain) { foreach ($fm in @($d.functionMap)) { if ([string]::Equals([string]$fm.object, $Component, [System.StringComparison]::OrdinalIgnoreCase)) { $fn = [string]$fm.function; $type = [string]$fm.type } } } }
            $head = Get-PsSpSection -Ctx $main -Name 'HEAD'
            $srs = @(New-PsSpSourceRef -Ctx $main -Sec $head)
            $ovPath = Join-Path (Join-Path (Join-Path $Root (Join-Path 'docs' 'ps-research')) $main.Domain) '00-overview.md'
            $ovHash = Get-PsKnFileHash -LiteralPath $ovPath
            if ($ovHash -ne '') { $srs += , ([ordered]@{ domain = $main.Domain; file = '00-overview.md'; path = ('docs/ps-research/' + $main.Domain + '/00-overview.md'); hash = $ovHash; role = 'OVERVIEW'; section = ''; level = 0; lines = ''; sectionHash = '' }) }
            $val = [ordered]@{ primaryObject = [string]$main.Facts.primaryObject; origin = [string]$main.Facts.origin; status = [string]$main.Facts.status; functionName = $fn; type = $type; files = @($Targets | ForEach-Object { $_.File }) }
            $facts += , ([ordered]@{ factId = ($fk + '@' + $Component); factKind = $fk; requirementIds = @($Req.id); subject = $Component; value = $val; sourceRefs = @($srs); evidenceRefs = @(); grade = $main.Grade; closure = 'SINGLE' })
        }
        'UI.NAVIGATION' {
            $entries = @(); $tm = @(); $unconfirmed = $false; $srs = @(); $grades = @(); $found = $false; $evs = @()
            foreach ($t in $Targets) {
                $fs = Get-PsSpSection -Ctx $t -Name '功能定位'
                if ($null -eq $fs) { continue }
                $found = $true
                $srs += , (New-PsSpSourceRef -Ctx $t -Sec $fs); $grades += $t.Grade
                $nav = Get-PsSpSection -Ctx $t -Name '導覽入口' -Level 3
                if ($null -ne $nav) {
                    $body = Get-PsSpSectionBody -Ctx $t -Sec $nav
                    if ($body -match '未確認') { $unconfirmed = $true }
                    foreach ($row in (Get-PsKnTableRows -Lines $t.Lines -Start ([int]$nav.start) -End ([int]$nav.end))) { $entries += , ([ordered]@{ file = $t.File; line = [int]$row.Line; cells = @($row.Cells) }) }
                    $evs += (Get-PsSpCitedEvidence -Ctx $t -Body $body)
                }
                $tms = Get-PsSpSection -Ctx $t -Name 'TechnicalMenu' -Level 3
                if ($null -ne $tms) { foreach ($ln in ((Get-PsSpSectionBody -Ctx $t -Sec $tms) -split "`n")) { $x = $ln.Trim(); if ($x -ne '' -and $x -notmatch '^<' -and $x -notmatch '^#') { $tm += $x } } }
            }
            if (-not $found) { & $addNeed 'MISSING' 'COMPONENT' $Component $main.Grade $main }
            else {
                $tmv = 'UNKNOWN'
                if ($tm.Count -gt 0) { $tmv = 'TRUE' }
                $ev = 'UNKNOWN'
                if ($entries.Count -gt 0) { $ev = 'TRUE' } elseif (-not $unconfirmed) { $ev = 'FALSE' }
                $val = [ordered]@{ entries = @($entries); entriesPresent = $ev; technicalMenu = @($tm); technicalMenuPresent = $tmv; unconfirmed = $unconfirmed }
                $facts += , ([ordered]@{ factId = ($fk + '@' + $Component); factKind = $fk; requirementIds = @($Req.id); subject = $Component; value = $val; sourceRefs = @($srs); evidenceRefs = @($evs); grade = (Get-PsSpMinGrade -Grades $grades); closure = 'ROWS' })
            }
        }
        'UI.FIELD_INVENTORY' {
            $rows = @(); $na = $false; $srs = @(); $grades = @(); $found = $false; $evs = @()
            foreach ($t in $Targets) {
                $s = Get-PsSpSection -Ctx $t -Name '畫面與欄位'
                if ($null -eq $s) { continue }
                $found = $true; $srs += , (New-PsSpSourceRef -Ctx $t -Sec $s); $grades += $t.Grade
                $body = Get-PsSpSectionBody -Ctx $t -Sec $s
                if ($body -match '（無') { $na = $true }
                foreach ($row in (Get-PsKnTableRows -Lines $t.Lines -Start ([int]$s.start) -End ([int]$s.end))) { $rows += , ([ordered]@{ file = $t.File; line = [int]$row.Line; cells = @($row.Cells) }) }
                $evs += (Get-PsSpCitedEvidence -Ctx $t -Body $body)
            }
            if (-not $found) { & $addNeed 'MISSING' 'COMPONENT' $Component $main.Grade $main }
            elseif ($rows.Count -eq 0 -and -not $na) { & $addNeed 'MISSING' 'COMPONENT' $Component $main.Grade $main }
            else {
                $fv = 'TRUE'; if ($na) { $fv = 'FALSE' }
                $val = [ordered]@{ fields = @($rows); fieldsPresent = $fv; choices = @($rows | Where-Object { $_.cells.Count -ge 4 -and [string]$_.cells[3] -ne '' }); lifecycle = @($rows | Where-Object { $_.cells.Count -ge 5 -and [string]$_.cells[4] -ne '' }); notApplicable = $na }
                $cl = 'ROWS'; if ($na) { $cl = 'NOT_APPLICABLE' }
                $facts += , ([ordered]@{ factId = ($fk + '@' + $Component); factKind = $fk; requirementIds = @($Req.id); subject = $Component; value = $val; sourceRefs = @($srs); evidenceRefs = @($evs); grade = (Get-PsSpMinGrade -Grades $grades); closure = $cl })
            }
        }
        'BEHAVIOR.RULES' {
            $rules = @(); $srs = @(); $grades = @(); $evs = @()
            foreach ($t in $Targets) {
                $s = Get-PsSpSection -Ctx $t -Name '行為邏輯'
                if ($null -eq $s) { continue }
                $srs += , (New-PsSpSourceRef -Ctx $t -Sec $s); $grades += $t.Grade
                foreach ($it in (Get-PsSpSectionItems -Ctx $t -Sec $s -SectionName '行為邏輯')) {
                    $conf = 'UNKNOWN'
                    $mc = [regex]::Match([string]$it.text, '\b(CONFIRMED|INFERRED|DYNAMIC_RUNTIME)\b')
                    if ($mc.Success) { $conf = $mc.Groups[1].Value }
                    $rules += , ([ordered]@{ file = $t.File; line = [int]$it.line; confidence = $conf; text = ([string]$it.text -replace '^[-*]\s+', '') })
                }
                $evs += (Get-PsSpCitedEvidence -Ctx $t -Body (Get-PsSpSectionBody -Ctx $t -Sec $s))
            }
            if ($rules.Count -eq 0) { & $addNeed 'MISSING' 'COMPONENT' $Component $main.Grade $main }
            else { $facts += , ([ordered]@{ factId = ($fk + '@' + $Component); factKind = $fk; requirementIds = @($Req.id); subject = $Component; value = ([ordered]@{ rules = @($rules); confidence = @($rules | ForEach-Object { $_.confidence }) }); sourceRefs = @($srs); evidenceRefs = @($evs); grade = (Get-PsSpMinGrade -Grades $grades); closure = 'ITEMS' }) }
        }
        'DATA.FLOW' {
            $tables = @(); $srs = @(); $grades = @(); $evs = @()
            foreach ($t in $Targets) {
                $s = Get-PsSpSection -Ctx $t -Name '資料流'
                if ($null -eq $s) { continue }
                $srs += , (New-PsSpSourceRef -Ctx $t -Sec $s); $grades += $t.Grade
                foreach ($df in @($t.Facts.dataFlow)) { $tables += , ([ordered]@{ file = $t.File; line = [int]$df.line; table = [string]$df.table; op = [string]$df.op; source = [string]$df.source; confidence = [string]$df.confidence }) }
                $evs += (Get-PsSpCitedEvidence -Ctx $t -Body (Get-PsSpSectionBody -Ctx $t -Sec $s))
            }
            if ($tables.Count -eq 0) { & $addNeed 'MISSING' 'COMPONENT' $Component $main.Grade $main }
            else {
                $reads = @($tables | Where-Object { $_.op -match 'READ|SELECT|LOOKUP' }); $writes = @($tables | Where-Object { $_.op -match 'WRITE|UPDATE|INSERT|DELETE|MERGE' })
                $facts += , ([ordered]@{ factId = ($fk + '@' + $Component); factKind = $fk; requirementIds = @($Req.id); subject = $Component; value = ([ordered]@{ tables = @($tables); reads = @($reads); writes = @($writes) }); sourceRefs = @($srs); evidenceRefs = @($evs); grade = (Get-PsSpMinGrade -Grades $grades); closure = 'ROWS' })
            }
        }
        'PROCESS.EXECUTION' {
            $text = @(); $srs = @(); $grades = @(); $found = $false; $cal = @(); $evs = @()
            foreach ($t in $Targets) {
                $s = Get-PsSpSection -Ctx $t -Name '執行方式'
                if ($null -eq $s) { continue }
                $body = Get-PsSpSectionBody -Ctx $t -Sec $s
                if (Test-PsSpHollow -Body $body) { continue }
                $found = $true; $srs += , (New-PsSpSourceRef -Ctx $t -Sec $s); $grades += $t.Grade
                foreach ($it in (Get-PsSpSectionItems -Ctx $t -Sec $s -SectionName '執行方式')) { $text += [string]$it.text }
                $evs += (Get-PsSpCitedEvidence -Ctx $t -Body $body)
            }
            foreach ($c in @($Callees)) {
                foreach ($cf in $c.Files) {
                    $cc = Get-PsSpNnCtx -Root $Root -Index $Index -Domain $main.Domain -File $cf -Cache $Cache
                    if ($null -eq $cc) { continue }
                    $s = Get-PsSpSection -Ctx $cc -Name '執行方式'
                    if ($null -eq $s) { continue }
                    if (-not (Test-PsSpGradeMeetsPolicy -Grade $cc.Grade -Policy $policy)) { & $addNeed 'CALLEE' 'COMPONENT' $c.Name $cc.Grade $cc; continue }
                    $srs += , (New-PsSpSourceRef -Ctx $cc -Sec $s -Role 'CALLEE'); $grades += $cc.Grade
                    $ct = @()
                    foreach ($it in (Get-PsSpSectionItems -Ctx $cc -Sec $s -SectionName '執行方式')) { $ct += [string]$it.text }
                    $cal += , ([ordered]@{ object = $c.Name; role = $c.Role; type = $c.Type; file = $cf; text = @($ct) })
                }
            }
            if (-not $found) { & $addNeed 'MISSING' 'COMPONENT' $Component $main.Grade $main }
            else {
                $all = ($text -join "`n")
                $online = 'FALSE'; if ($all -match '線上|Online|PIA|頁面') { $online = 'TRUE' }
                $batch = 'FALSE'; if ($all -match '批次|Process|排程|Run Control|AE\b|SQR' -or $cal.Count -gt 0) { $batch = 'TRUE' }
                $sched = 'FALSE'; if ($all -match '排程|Scheduler|PRCSRECUR|週期') { $sched = 'TRUE' }
                $facts += , ([ordered]@{ factId = ($fk + '@' + $Component); factKind = $fk; requirementIds = @($Req.id); subject = $Component; value = ([ordered]@{ text = @($text); online = $online; batch = $batch; schedule = $sched; callees = @($cal) }); sourceRefs = @($srs); evidenceRefs = @($evs); grade = (Get-PsSpMinGrade -Grades $grades); closure = 'PRESENT' })
            }
        }
        'SECURITY.ACCESS' {
            $text = @(); $srs = @(); $grades = @(); $found = $false; $evs = @()
            foreach ($t in $Targets) {
                $s = Get-PsSpSection -Ctx $t -Name '權限'
                if ($null -eq $s) { continue }
                $body = Get-PsSpSectionBody -Ctx $t -Sec $s
                if (Test-PsSpHollow -Body $body) { continue }
                $found = $true; $srs += , (New-PsSpSourceRef -Ctx $t -Sec $s); $grades += $t.Grade
                foreach ($it in (Get-PsSpSectionItems -Ctx $t -Sec $s -SectionName '權限')) { $text += [string]$it.text }
                $evs += (Get-PsSpCitedEvidence -Ctx $t -Body $body)
            }
            if (-not $found) { & $addNeed 'MISSING' 'COMPONENT' $Component $main.Grade $main }
            else {
                $all = ($text -join "`n")
                $pl = @(); foreach ($m in [regex]::Matches($all, '\b[A-Z][A-Z0-9_]{2,}\b')) { if ($pl -notcontains $m.Value) { $pl += $m.Value } }
                $facts += , ([ordered]@{ factId = ($fk + '@' + $Component); factKind = $fk; requirementIds = @($Req.id); subject = $Component; value = ([ordered]@{ text = @($text); permissionLists = @($pl); roles = @() }); sourceRefs = @($srs); evidenceRefs = @($evs); grade = (Get-PsSpMinGrade -Grades $grades); closure = 'PRESENT' })
            }
        }
        'RELATED.OBJECTS' {
            $objs = @(); $srs = @(); $grades = @(); $found = $false
            foreach ($t in $Targets) {
                $s = Get-PsSpSection -Ctx $t -Name '相關物件'
                if ($null -eq $s) { continue }
                $found = $true; $srs += , (New-PsSpSourceRef -Ctx $t -Sec $s); $grades += $t.Grade
                foreach ($ro in @($t.Facts.relatedObjects)) { $objs += , ([ordered]@{ file = $t.File; line = [int]$ro.line; name = [string]$ro.name; role = [string]$ro.role; type = (Get-PsSpObjectType -Index $Index -Object ([string]$ro.name)); classification = (Get-PsSpDomainGateClass -Index $Index -Domain $t.Domain -Object ([string]$ro.name)) }) }
            }
            if (-not $found -or $objs.Count -eq 0) { & $addNeed 'MISSING' 'COMPONENT' $Component $main.Grade $main }
            else { $facts += , ([ordered]@{ factId = ($fk + '@' + $Component); factKind = $fk; requirementIds = @($Req.id); subject = $Component; value = ([ordered]@{ objects = @($objs); roles = @($objs | ForEach-Object { $_.role }); classification = @($objs | ForEach-Object { $_.classification }) }); sourceRefs = @($srs); evidenceRefs = @(); grade = (Get-PsSpMinGrade -Grades $grades); closure = 'ROWS' }) }
        }
        'GAPS' {
            $items = @(); $srs = @(); $grades = @(); $found = $false
            foreach ($t in $Targets) {
                $s = Get-PsSpSection -Ctx $t -Name '未解事項'
                if ($null -eq $s) { continue }
                $found = $true; $srs += , (New-PsSpSourceRef -Ctx $t -Sec $s); $grades += $t.Grade
                foreach ($it in (Get-PsSpSectionItems -Ctx $t -Sec $s -SectionName '未解事項')) { $items += , ([ordered]@{ file = $t.File; line = [int]$it.line; text = ([string]$it.text -replace '^[-*]\s+', '') }) }
            }
            if (-not $found) { & $addNeed 'MISSING' 'COMPONENT' $Component $main.Grade $main }
            else { $facts += , ([ordered]@{ factId = ($fk + '@' + $Component); factKind = $fk; requirementIds = @($Req.id); subject = $Component; value = ([ordered]@{ items = @($items) }); sourceRefs = @($srs); evidenceRefs = @(); grade = (Get-PsSpMinGrade -Grades $grades); closure = 'ITEMS' }) }
        }
        'EVIDENCE.APPENDIX' {
            $rows = @(); $srs = @(); $grades = @(); $found = $false; $kinds = [ordered]@{ CHUNK = 0; SQL = 0; PENDING_MANUAL = 0; UNRESOLVED = 0 }
            foreach ($t in $Targets) {
                $s = Get-PsSpSection -Ctx $t -Name 'Evidence附錄'
                if ($null -eq $s) { continue }
                $found = $true; $srs += , (New-PsSpSourceRef -Ctx $t -Sec $s); $grades += $t.Grade
                foreach ($ev in @($t.Facts.evidence)) { $rows += , ([ordered]@{ file = $t.File; line = [int]$ev.line; n = [int]$ev.n; kind = [string]$ev.kind; ref = [string]$ev.ref; location = [string]$ev.location }); $kinds[[string]$ev.kind] = [int]$kinds[[string]$ev.kind] + 1 }
            }
            if (-not $found -or $rows.Count -eq 0) { & $addNeed 'MISSING' 'COMPONENT' $Component $main.Grade $main }
            else { $facts += , ([ordered]@{ factId = ($fk + '@' + $Component); factKind = $fk; requirementIds = @($Req.id); subject = $Component; value = ([ordered]@{ rows = @($rows); kinds = $kinds }); sourceRefs = @($srs); evidenceRefs = @(); grade = (Get-PsSpMinGrade -Grades $grades); closure = 'ROWS' }) }
        }
        'ENTITY.DETAIL' {
            $seen = @{}
            $wikiDir = Join-Path (Join-Path $Root (Join-Path 'docs' 'ps-research')) 'wiki'
            $want = ''
            if ($null -ne $Req.context -and $Req.context.Contains('record')) { $want = ([string]$Req.context['record']).ToUpperInvariant() }
            $anyRow = $false
            foreach ($t in $Targets) {
                $s = Get-PsSpSection -Ctx $t -Name '資料流'
                if ($null -eq $s) { continue }
                foreach ($df in @($t.Facts.dataFlow)) {
                    $rec = ([string]$df.table).ToUpperInvariant()
                    if ($want -ne '' -and $rec -ne $want -and ($rec -replace '^PS_', '') -ne ($want -replace '^PS_', '')) { continue }
                    if ($seen.ContainsKey($rec)) { continue }
                    $seen[$rec] = $true; $anyRow = $true
                    $w = Get-PsSpWikiEntry -Index $Index -Name $rec
                    if ($null -eq $w) { & $addNeed 'MISSING' 'RECORD' ($rec -replace '^PS_', '') 'MISSING' $t; continue }
                    $wg = Get-PsSpWikiGrade -Wiki $w
                    $srs = @((New-PsSpSourceRef -Ctx $t -Sec $s), ([ordered]@{ domain = 'wiki'; file = [string]$w.file; path = [string]$w.path; hash = [string]$w.hash; role = 'WIKI'; section = ''; level = 0; lines = ''; sectionHash = '' }))
                    if (-not (Test-PsSpGradeMeetsPolicy -Grade $wg -Policy $policy)) { & $addNeed 'GRADE' 'RECORD' ($rec -replace '^PS_', '') $wg $t }
                    $rels = @(); foreach ($rl in @($w.relations)) { $rels += ([string]$rl.type + ' ' + [string]$rl.target) }
                    $facts += , ([ordered]@{ factId = ($fk + '@' + $rec); factKind = $fk; requirementIds = @($Req.id); subject = $rec; value = ([ordered]@{ record = $rec; wiki = [string]$w.name; type = [string]$w.type; status = [string]$w.status; effective = [string]$w.effective; reviewed = [bool]$w.reviewed; lastVerified = [string]$w.lastVerified; observations = [int]$w.observations; relations = @($rels); line = [int]$df.line; file = $t.File }); sourceRefs = @($srs); evidenceRefs = @(); grade = $wg; closure = 'PER_RECORD' })
                }
            }
            if (-not $anyRow) { & $addNeed 'MISSING' 'COMPONENT' $Component $main.Grade $main }
        }
        default { }
    }
    # 等級低於證據政策 → GRADE need（fact 仍保留，狀態 WAITING）
    foreach ($f in $facts) {
        if ([string]$f.factKind -eq 'ENTITY.DETAIL') { continue }
        if (-not (Test-PsSpGradeMeetsPolicy -Grade ([string]$f.grade) -Policy $policy)) { & $addNeed 'GRADE' 'COMPONENT' $Component ([string]$f.grade) $main }
    }
    $r.Facts = @($facts)
    $r.Needs = @($script:PsSpNeedBuf)
    return $r
}

# ── KnowledgeNeed → 補研究協定（消費端規則）────────────────────────

function New-PsSpNeed {
    param($Req, $Cap, [string]$TargetType, [string]$TargetName, [string]$FactKind = '')
    $fk = $FactKind
    if ($fk -eq '') { $fk = [string]$Req.factKind }
    $props = @($Req.properties)
    if ($props.Count -eq 0 -and $null -ne $Cap) { $props = @($Cap.properties | ForEach-Object { [string]$_ }) }
    $ctx = [ordered]@{}
    if ($null -ne $Req.context) { foreach ($k in @($Req.context.Keys)) { $ctx[[string]$k] = [string]$Req.context[$k] } }
    return [ordered]@{ target = [ordered]@{ type = $TargetType; name = $TargetName }; context = $ctx; factKind = $fk; properties = @($props); evidencePolicy = [string]$Req.evidencePolicy; freshness = 'CURRENT' }
}

# 回 @{ State; RequestId; Outcome; Reason; Created }
#   State ∈ SUBMITTED／RESUBMITTED／WAITING_KNOWLEDGE／WAITING_AUDIT／BLOCKED_KNOWLEDGE／ROUTING_REQUIRED／INVALID／UNSUBMITTED
function Resolve-PsSpNeed {
    param([string]$Root, $Need, [string]$JobId, [string]$RequirementId, [string]$DomainHint = '', [string]$Reason = 'MISSING', [string]$CurrentHash = '', [string]$TargetFile = '', [bool]$NoSubmit = $false, $Index = $null)
    $r = @{ State = 'UNSUBMITTED'; RequestId = ''; Outcome = ''; Reason = $Reason; Created = $false }
    $cap = Get-PsSuppCapabilities -Root $Root
    $v = Test-PsSuppNeed -Need $Need -Capabilities $cap
    if (-not $v.Ok) { $r.State = 'INVALID'; return $r }
    $wk = Get-PsSuppWorkKey -Need $v.Need
    $latest = $null
    foreach ($q in (Get-PsSuppRequests -Root $Root)) { if ($q.WorkKey -ceq $wk -and ($null -eq $latest -or $q.Generation -gt $latest.Generation)) { $latest = $q } }
    $consumer = @{ kind = 'SPEC'; jobId = $JobId; requirementRef = $RequirementId }
    if ($null -eq $latest) {
        if ($NoSubmit) { return $r }
        $s = Submit-PsSupplementalRequest -Root $Root -Need $Need -Consumer $consumer -DomainHint $DomainHint
        $r.RequestId = [string]$s.requestId
        switch ([string]$s.state) {
            'CREATED' { $r.State = 'SUBMITTED'; $r.Created = $true }
            'PENDING' { $r.State = 'WAITING_KNOWLEDGE' }
            'ROUTING_REQUIRED' { $r.State = 'ROUTING_REQUIRED' }
            'INVALID' { $r.State = 'INVALID' }
            default { $r.State = 'WAITING_KNOWLEDGE'; $r.Outcome = [string]$s.state }
        }
        return $r
    }
    $r.RequestId = $latest.RequestId
    $res = Get-PsSupplementalResult -Root $Root -RequestId $latest.RequestId
    if ($null -eq $res) { $r.State = 'WAITING_KNOWLEDGE'; return $r }
    $r.Outcome = [string]$res.outcome
    if ($r.Outcome -eq 'RESOLVED' -or $r.Outcome -eq 'PARTIAL') {
        if ($Reason -eq 'GRADE' -or $Reason -eq 'CALLEE') { $r.State = 'WAITING_AUDIT'; return $r }
        # 事實仍缺：hash≠hashAfter 才重送；相同＝研究結果抽不出事實
        $hashAfter = ''
        foreach ($a in @($res.affected)) { if ($TargetFile -eq '' -or [string]$a.file -ceq $TargetFile) { $hashAfter = [string]$a.hashAfter; break } }
        if ($hashAfter -ne '' -and $CurrentHash -ne '' -and $hashAfter -ceq $CurrentHash) { $r.State = 'BLOCKED_KNOWLEDGE'; $r.Reason = 'NOT_EXTRACTABLE'; return $r }
        if ($NoSubmit) { $r.State = 'RESUBMIT_REQUIRED'; return $r }
        $s = Submit-PsSupplementalRequest -Root $Root -Need $Need -Consumer $consumer -DomainHint $DomainHint -Resubmit
        $r.RequestId = [string]$s.requestId
        if ([string]$s.state -eq 'CREATED') { $r.State = 'RESUBMITTED'; $r.Created = $true } elseif ([string]$s.state -eq 'ROUTING_REQUIRED') { $r.State = 'ROUTING_REQUIRED' } else { $r.State = 'WAITING_KNOWLEDGE' }
        return $r
    }
    if ($r.Outcome -eq 'SUPERSEDED') { $r.State = 'WAITING_KNOWLEDGE'; return $r }
    $r.State = 'BLOCKED_KNOWLEDGE'
    return $r
}

# ── COMPOSE 單位 ───────────────────────────────────────────────────

function Get-PsSpUnitKey { param([string]$UnitId) return ($UnitId -replace '[^A-Za-z0-9_.@\-一-鿿]', '-') }

# readSet 檔項：@{ domain; file; path; role; hash; sections=@(sec…) }
function Add-PsSpReadFile {
    param($ReadSet, $Ctx, [string]$Role, [string[]]$SectionNames)
    $secs = @()
    foreach ($n in $SectionNames) { $s = Get-PsSpSection -Ctx $Ctx -Name $n; if ($null -ne $s) { $secs += , $s } }
    $ev = Get-PsSpSection -Ctx $Ctx -Name 'Evidence附錄'
    if ($null -ne $ev) { $secs += , $ev }
    if ($secs.Count -eq 0) { return $ReadSet }
    $evn = @()
    foreach ($e in @($Ctx.Facts.evidence)) { $evn += [int]$e.n }
    $ReadSet += , ([ordered]@{ domain = $Ctx.Domain; file = $Ctx.File; path = $Ctx.Rel; role = $Role; hash = $Ctx.Hash; grade = $Ctx.Grade; evidence = @($evn); sections = @($secs) })
    return , $ReadSet
}

function New-PsSpUnit {
    param($Req, [string]$SubjectKey, $ReadSet, $Items, [string]$Grade)
    $uid = [string]$Req.id + '.' + $SubjectKey
    $n = 0
    $its = @()
    foreach ($it in @($Items)) { $n++; $its += , ([ordered]@{ n = $n; file = [string]$it.file; line = [int]$it.line; kind = [string]$it.kind }) }
    return [ordered]@{ unitId = $uid; unitKey = (Get-PsSpUnitKey -UnitId $uid); requirementId = [string]$Req.id; factKind = [string]$Req.factKind; subjectKey = $SubjectKey; state = 'DISPATCHABLE'; grade = $Grade; readSet = @($ReadSet); items = @($its); knowledge = $null }
}

# 回 @{ Units=@(); Needs=@() }
function New-PsSpComposeUnits {
    param($Req, $Cap, $Targets, $Callees, $Index, [string]$Root, [string]$Component, $Cache)
    $r = @{ Units = @(); Needs = @() }
    $fk = [string]$Req.factKind
    $main = $Targets[0]
    $policy = [string]$Req.evidencePolicy
    $secNames = @($Cap.sections | ForEach-Object { [string]$_ } | Where-Object { $_ -ne 'Evidence附錄' })
    switch ($fk) {
        'BEHAVIOR.VALIDATIONS' {
            $any = $false
            foreach ($t in $Targets) {
                $s = Get-PsSpSection -Ctx $t -Name '行為邏輯'
                if ($null -eq $s) { continue }
                $items = @()
                foreach ($it in (Get-PsSpSectionItems -Ctx $t -Sec $s -SectionName '行為邏輯')) { $items += , (@{ file = $t.File; line = $it.line; kind = '行為' }) }
                if ($items.Count -eq 0) { continue }
                $any = $true
                $rs = Add-PsSpReadFile -ReadSet @() -Ctx $t -Role 'TARGET' -SectionNames @('行為邏輯')
                $r.Units += , (New-PsSpUnit -Req $Req -SubjectKey ($Component + '@行為邏輯:L' + $s.start + '-' + $s.end) -ReadSet $rs -Items $items -Grade $t.Grade)
            }
            if (-not $any) { $r.Needs += , (@{ Reason = 'MISSING'; Target = @{ type = 'COMPONENT'; name = $Component }; Grade = $main.Grade; Ctx = $main }) }
        }
        { $_ -eq 'DATA.FILE_INPUT' -or $_ -eq 'DATA.FILE_OUTPUT' } {
            $rs = @(); $items = @(); $grades = @()
            foreach ($t in $Targets) {
                $names = @()
                foreach ($n in $secNames) {
                    $s = Get-PsSpSection -Ctx $t -Name $n
                    if ($null -eq $s) { continue }
                    $names += $n
                    $kind = '行為'; if ($n -eq '資料流') { $kind = '資料流' } elseif ($n -eq '執行方式') { $kind = '執行' }
                    foreach ($it in (Get-PsSpSectionItems -Ctx $t -Sec $s -SectionName $n)) { $items += , (@{ file = $t.File; line = $it.line; kind = $kind }) }
                }
                if ($names.Count -gt 0) { $rs = Add-PsSpReadFile -ReadSet $rs -Ctx $t -Role 'TARGET' -SectionNames $names; $grades += $t.Grade }
            }
            foreach ($c in @($Callees)) {
                foreach ($cf in $c.Files) {
                    $cc = Get-PsSpNnCtx -Root $Root -Index $Index -Domain $main.Domain -File $cf -Cache $Cache
                    if ($null -eq $cc) { continue }
                    if (-not (Test-PsSpGradeMeetsPolicy -Grade $cc.Grade -Policy $policy)) { $r.Needs += , (@{ Reason = 'CALLEE'; Target = @{ type = 'COMPONENT'; name = $c.Name }; Grade = $cc.Grade; Ctx = $cc }); continue }
                    $names = @()
                    foreach ($n in @('執行方式', '資料流')) {
                        $s = Get-PsSpSection -Ctx $cc -Name $n
                        if ($null -eq $s) { continue }
                        $names += $n
                        $kind = '執行'; if ($n -eq '資料流') { $kind = '資料流' }
                        foreach ($it in (Get-PsSpSectionItems -Ctx $cc -Sec $s -SectionName $n)) { $items += , (@{ file = $cc.File; line = $it.line; kind = $kind }) }
                    }
                    if ($names.Count -gt 0) { $rs = Add-PsSpReadFile -ReadSet $rs -Ctx $cc -Role 'CALLEE' -SectionNames $names; $grades += $cc.Grade }
                }
            }
            if ($rs.Count -eq 0) { $r.Needs += , (@{ Reason = 'MISSING'; Target = @{ type = 'COMPONENT'; name = $Component }; Grade = $main.Grade; Ctx = $main }) }
            else { $r.Units += , (New-PsSpUnit -Req $Req -SubjectKey $Component -ReadSet $rs -Items $items -Grade (Get-PsSpMinGrade -Grades $grades)) }
        }
        'DATA.RECORD_USAGE' {
            $want = ''
            if ($null -ne $Req.context -and $Req.context.Contains('record')) { $want = ([string]$Req.context['record']).ToUpperInvariant() }
            $recs = [ordered]@{}
            foreach ($t in $Targets) {
                foreach ($df in @($t.Facts.dataFlow)) {
                    $rec = ([string]$df.table).ToUpperInvariant()
                    if ($want -ne '' -and $rec -ne $want -and ($rec -replace '^PS_', '') -ne ($want -replace '^PS_', '')) { continue }
                    if (-not $recs.Contains($rec)) { $recs[$rec] = @() }
                    $recs[$rec] += , (@{ file = $t.File; line = [int]$df.line; kind = '資料流' })
                }
            }
            if ($recs.Count -eq 0) { $r.Needs += , (@{ Reason = 'MISSING'; Target = @{ type = 'COMPONENT'; name = $Component }; Grade = $main.Grade; Ctx = $main }); break }
            foreach ($rec in (Sort-PsKnOrdinal -Items @($recs.Keys | ForEach-Object { [string]$_ }))) {
                $items = @($recs[$rec])
                $rs = @(); $grades = @()
                $bare = $rec -replace '^PS_', ''
                foreach ($t in $Targets) {
                    $names = @()
                    if ($null -ne (Get-PsSpSection -Ctx $t -Name '資料流')) { $names += '資料流' }
                    $bs = Get-PsSpSection -Ctx $t -Name '行為邏輯'
                    if ($null -ne $bs) {
                        $hit = @()
                        foreach ($it in (Get-PsSpSectionItems -Ctx $t -Sec $bs -SectionName '行為邏輯')) { if (([string]$it.text).IndexOf($bare, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit += , (@{ file = $t.File; line = $it.line; kind = '行為' }) } }
                        if ($hit.Count -gt 0) { $names += '行為邏輯'; $items += $hit }
                    }
                    if ($names.Count -gt 0) { $rs = Add-PsSpReadFile -ReadSet $rs -Ctx $t -Role 'TARGET' -SectionNames $names; $grades += $t.Grade }
                }
                $r.Units += , (New-PsSpUnit -Req $Req -SubjectKey ($Component + '@' + $rec) -ReadSet $rs -Items $items -Grade (Get-PsSpMinGrade -Grades $grades))
            }
        }
        default { }
    }
    # 讀取集合等級低於證據政策 → GRADE need
    foreach ($u in $r.Units) { if (-not (Test-PsSpGradeMeetsPolicy -Grade ([string]$u.grade) -Policy $policy)) { $r.Needs += , (@{ Reason = 'GRADE'; Target = @{ type = 'COMPONENT'; name = $Component }; Grade = [string]$u.grade; Ctx = $main; UnitId = [string]$u.unitId }) } }
    return $r
}

# ── 規劃 ─────────────────────────────────────────────────────────

function Get-PsSpFactValues {
    param($Facts)
    $fv = @{}
    foreach ($f in @($Facts)) {
        $fk = [string]$f.factKind
        foreach ($pn in (Get-PsSpPropNames $f.value)) {
            $key = $fk + '.' + $pn
            $v = Get-PsSpTruth -V (Get-PsSpProp $f.value $pn)
            if ($fv.ContainsKey($key)) { if ($fv[$key] -ne $v) { $fv[$key] = 'UNKNOWN' } } else { $fv[$key] = $v }
        }
        # <factKind>.present：fact 存在＝TRUE（NOT_APPLICABLE closure＝FALSE）
        $pk = $fk + '.present'
        $pv = 'TRUE'; if ([string]$f.closure -eq 'NOT_APPLICABLE') { $pv = 'FALSE' }
        if (-not $fv.ContainsKey($pk)) { $fv[$pk] = $pv }
    }
    return $fv
}

# 建 plan（不寫檔）。回 @{ Plan; Summary=@{ units; facts; submitted; resubmitted; pending; waitingAudit; blocked; routing; unsupported } ; Identity }
function New-PsSpPlan {
    param([string]$Root, $Dirs, $PackV, [string]$JobId, [string]$Component, [string]$DomainHint = '', $Index, $Capabilities, [bool]$NoSubmit = $false)
    $comp = $Component.Trim().ToUpperInvariant()
    $cache = @{}
    $id = Resolve-PsSpIdentity -Index $Index -Component $comp -DomainHint $DomainHint
    $out = @{ Plan = $null; Identity = $id; Summary = @{ units = 0; facts = 0; submitted = 0; resubmitted = 0; pending = 0; waitingAudit = 0; blocked = 0; routing = 0; unsupported = 0; unknown = 0 } }
    if ($id.State -ne 'OK') { return $out }
    $targets = @()
    foreach ($f in $id.Files) { $c = Get-PsSpNnCtx -Root $Root -Index $Index -Domain $id.Domain -File $f -Cache $cache; if ($null -ne $c) { $targets += , $c } }
    if ($targets.Count -eq 0) { $out.Identity = @{ State = 'NOT_FOUND'; Domain = $id.Domain; Files = @(); Entries = @(); Candidates = @(); Reason = 'FILE_MISSING' }; return $out }
    $callees = Get-PsSpCallees -Ctx $targets[0] -Index $Index -Capabilities $Capabilities
    $plan = [ordered]@{
        schemaVersion = $script:PsSpecSchemaVersion; planHash = ''; jobId = $JobId; packId = $PackV.PackId; packVersion = $PackV.PackVersion; contentHash = $PackV.ContentHash
        component = $comp; domain = $id.Domain; identity = [ordered]@{ files = @(); reason = $id.Reason; candidates = @($id.Candidates) }
        callees = @(); requirements = @(); facts = @(); units = @(); findings = @()
    }
    foreach ($t in $targets) { $plan.identity.files += , ([ordered]@{ file = $t.File; hash = $t.Hash; grade = $t.Grade; status = [string]$t.Facts.status }) }
    foreach ($c in $callees) { $plan.callees += , ([ordered]@{ object = $c.Name; role = $c.Role; type = $c.Type; files = @($c.Files) }) }
    $factMap = [ordered]@{}
    $reqOut = @()
    $unitsOut = @()
    # 第一輪：EXTRACT facts；第二輪：applicability 與 COMPOSE
    $extract = @{}
    foreach ($q in $PackV.Requirements) {
        if ([string]$q.mode -ne 'EXTRACT') { continue }
        $cap = Get-PsSpFactKind -Capabilities $Capabilities -FactKind ([string]$q.factKind)
        $extract[$q.id] = New-PsSpExtractFacts -Req $q -Cap $cap -Targets $targets -Callees $callees -Index $Index -Root $Root -Component $comp -Cache $cache
        foreach ($f in $extract[$q.id].Facts) {
            if ($factMap.Contains([string]$f.factId)) { $ex = $factMap[[string]$f.factId]; if (@($ex.requirementIds) -notcontains $q.id) { $ex.requirementIds += $q.id } }
            else { $factMap[[string]$f.factId] = $f }
        }
    }
    $allFacts = @($factMap.Values)
    $fv = Get-PsSpFactValues -Facts $allFacts
    foreach ($q in $PackV.Requirements) {
        $cap = Get-PsSpFactKind -Capabilities $Capabilities -FactKind ([string]$q.factKind)
        $re = [ordered]@{ id = $q.id; slot = $q.slot; checklistRefs = @($q.checklistRefs); factKind = $q.factKind; mode = $q.mode; required = $q.required; cardinality = $q.cardinality; evidencePolicy = $q.evidencePolicy; applicability = $q.applicability; properties = @($q.properties); context = $q.context; applicable = 'UNKNOWN'; state = 'READY'; facts = @(); units = @(); needs = @() }
        $re.applicable = Test-PsSpApplicability -App $q.applicability -FactValues $fv
        if ($re.applicable -eq 'UNKNOWN') { $out.Summary.unknown++ }
        if ($re.applicable -eq 'FALSE') { $re.state = 'NOT_APPLICABLE'; $reqOut += , $re; continue }
        if ([string]$q.mode -eq 'UNSUPPORTED') { $re.state = 'UNSUPPORTED'; $out.Summary.unsupported++; $plan.findings += , ([ordered]@{ code = '2-06'; requirementId = $q.id; factKind = $q.factKind; mode = 'UNSUPPORTED' }); $reqOut += , $re; continue }
        $needs = @()
        if ([string]$q.mode -eq 'EXTRACT') {
            $x = $extract[$q.id]
            foreach ($f in $x.Facts) { $re.facts += [string]$f.factId }
            $needs = @($x.Needs)
        }
        else {
            $x = New-PsSpComposeUnits -Req $q -Cap $cap -Targets $targets -Callees $callees -Index $Index -Root $Root -Component $comp -Cache $cache
            foreach ($u in $x.Units) { $re.units += [string]$u.unitId; $unitsOut += , $u }
            $needs = @($x.Needs)
            if ($x.Units.Count -gt 0) { $re.state = 'PENDING' }
        }
        # KnowledgeNeed → 消費端規則（去重：同 target＋reason 只查一次）
        $seenNeed = @{}
        foreach ($nd in $needs) {
            $tt = [string]$nd.Target.type; $tn = [string]$nd.Target.name
            $fkNeed = [string]$q.factKind
            if ($tt -eq 'RECORD') { $fkNeed = 'ENTITY.DETAIL' }
            $needObj = New-PsSpNeed -Req $q -Cap $cap -TargetType $tt -TargetName $tn -FactKind $fkNeed
            $nk = $tt + ':' + $tn + ':' + [string]$nd.Reason
            if ($seenNeed.ContainsKey($nk)) { continue }
            $seenNeed[$nk] = $true
            $curHash = ''; $tf = ''
            if ($null -ne $nd.Ctx) { $curHash = [string]$nd.Ctx.Hash; $tf = [string]$nd.Ctx.File }
            $rs = Resolve-PsSpNeed -Root $Root -Need $needObj -JobId $JobId -RequirementId $q.id -DomainHint $id.Domain -Reason ([string]$nd.Reason) -CurrentHash $curHash -TargetFile $tf -NoSubmit $NoSubmit -Index $Index
            $st = [string]$rs.State
            if ($st -eq 'SUBMITTED') { $out.Summary.submitted++; $st = 'WAITING_KNOWLEDGE' }
            elseif ($st -eq 'RESUBMITTED') { $out.Summary.resubmitted++; $st = 'WAITING_KNOWLEDGE' }
            elseif ($st -eq 'UNSUBMITTED' -or $st -eq 'RESUBMIT_REQUIRED') { $st = 'WAITING_KNOWLEDGE' }
            if ($st -eq 'WAITING_KNOWLEDGE') { $out.Summary.pending++ } elseif ($st -eq 'WAITING_AUDIT') { $out.Summary.waitingAudit++ } elseif ($st -eq 'BLOCKED_KNOWLEDGE') { $out.Summary.blocked++ } elseif ($st -eq 'ROUTING_REQUIRED') { $out.Summary.routing++ }
            $unitId = ''
            if ($null -ne $nd.UnitId) { $unitId = [string]$nd.UnitId }
            $re.needs += , ([ordered]@{ requirementId = $q.id; factKind = $fkNeed; target = [ordered]@{ type = $tt; name = $tn }; reason = [string]$nd.Reason; grade = [string]$nd.Grade; state = $st; requestId = [string]$rs.RequestId; outcome = [string]$rs.Outcome; unitId = $unitId; sourceHash = $curHash })
        }
        # requirement／unit 狀態：need 決定（BLOCKED > WAITING_AUDIT > WAITING_KNOWLEDGE > ROUTING）
        $worst = ''
        foreach ($n in $re.needs) {
            $s = [string]$n.state
            $rank = 0
            if ($s -eq 'BLOCKED_KNOWLEDGE') { $rank = 4 } elseif ($s -eq 'WAITING_AUDIT') { $rank = 3 } elseif ($s -eq 'WAITING_KNOWLEDGE') { $rank = 2 } elseif ($s -eq 'ROUTING_REQUIRED' -or $s -eq 'INVALID') { $rank = 1 }
            $wr = 0
            if ($worst -eq 'BLOCKED_KNOWLEDGE') { $wr = 4 } elseif ($worst -eq 'WAITING_AUDIT') { $wr = 3 } elseif ($worst -eq 'WAITING_KNOWLEDGE') { $wr = 2 } elseif ($worst -ne '') { $wr = 1 }
            if ($rank -gt $wr) { $worst = $s }
        }
        if ($worst -ne '') {
            $re.state = $worst
            foreach ($u in $unitsOut) { if ([string]$u.requirementId -eq $q.id) { $u.state = $worst; $u.knowledge = @($re.needs)[0] } }
        }
        $reqOut += , $re
    }
    $plan.requirements = @($reqOut)
    $plan.facts = @($allFacts)
    $ukeys = @{}
    foreach ($u in $unitsOut) { $ukeys[[string]$u.unitId] = $u }
    $plan.units = @()
    foreach ($k in (Sort-PsKnOrdinal -Items @($ukeys.Keys))) { $plan.units += , $ukeys[$k] }
    $plan.planHash = Get-PsKnTextHash -Text (ConvertTo-PsKnJson -Value $plan -SortKeys)
    $out.Plan = $plan
    $out.Summary.units = $plan.units.Count
    $out.Summary.facts = $plan.facts.Count
    return $out
}

function Get-PsSpPlanRef { param($Plan) return ([string]$Plan.planHash).Substring(0, 16).ToLowerInvariant() }

# immutable：plans/<planRef>/plan.json（create-only；已存在＝重用）。回 @{ PlanRef; Created; Path }
function Write-PsSpPlan {
    param($Dirs, $Plan)
    $ref = Get-PsSpPlanRef -Plan $Plan
    $dir = Join-Path $Dirs.Plans $ref
    $p = Join-Path $dir 'plan.json'
    $obj = [ordered]@{}
    foreach ($k in $Plan.Keys) { $obj[[string]$k] = $Plan[$k] }
    $obj['createdAt'] = Get-PsKnUtcStamp
    $ok = Write-PsKnCreateOnlyText -LiteralPath $p -Text ((ConvertTo-PsKnJson -Value $obj) + "`n")
    return @{ PlanRef = $ref; Created = $ok; Path = $p }
}
function Read-PsSpPlan {
    param($Dirs, [string]$PlanRef)
    if ($PlanRef -eq '') { return $null }
    return (Read-PsSpJsonFile -LiteralPath (Join-Path (Join-Path $Dirs.Plans $PlanRef) 'plan.json'))
}
function Read-PsSpJob { param($Dirs) return (Read-PsSpJsonFile -LiteralPath $Dirs.JobFile) }
function Write-PsSpJob {
    param($Dirs, $Job)
    $o = [ordered]@{}
    foreach ($k in (Get-PsSpPropNames $Job)) { $o[[string]$k] = (Get-PsSpProp $Job $k) }
    $o['updatedAt'] = Get-PsKnUtcStamp
    return (Write-PsKnAtomicText -LiteralPath $Dirs.JobFile -Text ((ConvertTo-PsKnJson -Value $o) + "`n") -Bom $false)
}
function New-PsSpJob {
    param([string]$JobId, $PackV, [string]$Component, [string]$DomainHint)
    return [ordered]@{ schemaVersion = $script:PsSpecSchemaVersion; jobId = $JobId; packId = $PackV.PackId; packVersion = $PackV.PackVersion; contentHash = $PackV.ContentHash; bindingHash = $PackV.BindingHash; component = $Component.Trim().ToUpperInvariant(); domainHint = $DomainHint; domain = ''; currentPlanRef = ''; phase = 'PLANNED'; lastCode = ''; createdAt = (Get-PsKnUtcStamp); updatedAt = '' }
}
function Get-PsSpPhaseFromPlan {
    param($Plan)
    $has = @{}
    foreach ($q in @($Plan.requirements)) { $has[[string]$q.state] = $true }
    if ($has.ContainsKey('BLOCKED_KNOWLEDGE')) { return 'BLOCKED' }
    if ($has.ContainsKey('WAITING_AUDIT')) { return 'WAITING_AUDIT' }
    if ($has.ContainsKey('WAITING_KNOWLEDGE') -or $has.ContainsKey('ROUTING_REQUIRED')) { return 'WAITING_KNOWLEDGE' }
    return 'PLANNED'
}

# ── 指紋、拆分、收據、判定 ────────────────────────────────────────

# 指紋：單位＋part＋各節（name/level/內容 hash）＋條目（n/file/kind）的 canonical -SortKeys JSON SHA256。
# 不含檔案整體 hash 與行號：讀取節之外的改動、或只是行號漂移（前面的節長了）不使收據失效；證據參照用附錄列號（#n）而非行號，所以不怕漂移。
function Get-PsSpFingerprint {
    param([string]$UnitId, [string]$Part, $Files, $Items)
    $fs = @()
    foreach ($f in @($Files)) {
        $ss = @()
        foreach ($s in @($f.sections)) { $ss += , ([ordered]@{ name = [string]$s.name; level = [int]$s.level; hash = [string]$s.hash }) }
        $fs += , ([ordered]@{ path = [string]$f.path; sections = @($ss) })
    }
    $is = @()
    foreach ($i in @($Items)) { $is += , ([ordered]@{ n = [int]$i.n; file = [string]$i.file; kind = [string]$i.kind }) }
    return (Get-PsKnTextHash -Text (ConvertTo-PsKnJson -Value ([ordered]@{ unitId = $UnitId; part = $Part; files = @($fs); items = @($is) }) -SortKeys))
}

function Get-PsSpSplitPath { param($Dirs, [string]$PlanRef, [string]$UnitKey) return (Join-Path (Join-Path (Join-Path $Dirs.Plans $PlanRef) 'splits') ($UnitKey + '.json')) }

# 有效單位（含拆分 part）：@( @{ Unit; Part; Items; BlockedCapacity } )
function Get-PsSpEffectiveUnits {
    param($Dirs, $Plan)
    $ref = Get-PsSpPlanRef -Plan $Plan
    $out = @()
    foreach ($u in @($Plan.units)) {
        $sp = Read-PsSpJsonFile -LiteralPath (Get-PsSpSplitPath -Dirs $Dirs -PlanRef $ref -UnitKey ([string]$u.unitKey))
        if ($null -eq $sp) { $out += , (@{ Unit = $u; Part = 'p0'; Items = @($u.items); BlockedCapacity = $false }); continue }
        foreach ($p in @($sp.parts)) {
            $its = @()
            $set = @{}
            foreach ($n in @($p.items)) { $set[[int]$n] = $true }
            foreach ($i in @($u.items)) { if ($set.ContainsKey([int]$i.n)) { $its += , $i } }
            $bc = $false
            if ($null -ne $p.blockedCapacity) { $bc = [bool]$p.blockedCapacity }
            $out += , (@{ Unit = $u; Part = [string]$p.part; Items = @($its); BlockedCapacity = $bc })
        }
    }
    return , $out
}

# 容量事件：把 part 對半（≤1 條目＝不可拆 → blockedCapacity）。回 @{ Ok; Parts; Blocked }
function Write-PsSpSplit {
    param($Dirs, $Plan, $Eu)
    $ref = Get-PsSpPlanRef -Plan $Plan
    $u = $Eu.Unit
    $p = Get-PsSpSplitPath -Dirs $Dirs -PlanRef $ref -UnitKey ([string]$u.unitKey)
    $sp = Read-PsSpJsonFile -LiteralPath $p
    $parts = @()
    $maxN = 0
    if ($null -ne $sp) { foreach ($x in @($sp.parts)) { $parts += , ([ordered]@{ part = [string]$x.part; items = @($x.items | ForEach-Object { [int]$_ }); blockedCapacity = [bool]$x.blockedCapacity }); $m = [regex]::Match([string]$x.part, '^p(\d+)$'); if ($m.Success -and [int]$m.Groups[1].Value -gt $maxN) { $maxN = [int]$m.Groups[1].Value } } }
    $items = @($Eu.Items | ForEach-Object { [int]$_.n })
    $rest = @()
    foreach ($x in $parts) { if ([string]$x.part -ne [string]$Eu.Part) { $rest += , $x } }
    $blocked = $false
    if ($items.Count -le 1) {
        $blocked = $true
        $rest += , ([ordered]@{ part = [string]$Eu.Part; items = @($items); blockedCapacity = $true })
        if ([string]$Eu.Part -eq 'p0' -and $items.Count -eq 0) { $rest = @([ordered]@{ part = 'p0'; items = @(); blockedCapacity = $true }) }
    }
    else {
        $half = [int][Math]::Ceiling($items.Count / 2.0)
        $a = @($items[0 .. ($half - 1)]); $b = @($items[$half .. ($items.Count - 1)])
        $rest += , ([ordered]@{ part = ('p' + ($maxN + 1)); items = @($a); blockedCapacity = $false })
        $rest += , ([ordered]@{ part = ('p' + ($maxN + 2)); items = @($b); blockedCapacity = $false })
    }
    $obj = [ordered]@{ schemaVersion = $script:PsSpecSchemaVersion; unitId = [string]$u.unitId; parts = @($rest) }
    $ok = Write-PsKnAtomicText -LiteralPath $p -Text ((ConvertTo-PsKnJson -Value $obj) + "`n") -Bom $false
    return @{ Ok = $ok; Parts = @($rest); Blocked = $blocked }
}

function Get-PsSpReceiptName { param([string]$UnitKey, [string]$Part, [string]$Fingerprint) $k = $UnitKey; if ($Part -ne 'p0') { $k = $k + '~' + $Part }; return ($k + '.' + $Fingerprint.Substring(0, 16).ToLowerInvariant() + '.json') }

function Get-PsSpReceipts {
    param($Dirs)
    $out = @()
    if (-not [System.IO.Directory]::Exists($Dirs.Receipts)) { return , $out }
    $names = @(Get-ChildItem -LiteralPath $Dirs.Receipts -File -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    foreach ($n in (Sort-PsKnOrdinal -Items $names)) { $o = Read-PsSpJsonFile -LiteralPath (Join-Path $Dirs.Receipts $n); if ($null -ne $o) { $out += , $o } }
    return , $out
}
function Get-PsSpVerdicts {
    param($Dirs)
    $out = @()
    if (-not [System.IO.Directory]::Exists($Dirs.Attempts)) { return , $out }
    $names = @(Get-ChildItem -LiteralPath $Dirs.Attempts -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    foreach ($n in (Sort-PsKnOrdinal -Items $names)) { $o = Read-PsSpJsonFile -LiteralPath (Join-Path (Join-Path $Dirs.Attempts $n) 'verdict.json'); if ($null -ne $o) { $out += , $o } }
    return , $out
}
function Get-PsSpNextAttemptId {
    param($Dirs)
    $max = 0
    if ([System.IO.Directory]::Exists($Dirs.Attempts)) {
        foreach ($d in @(Get-ChildItem -LiteralPath $Dirs.Attempts -Directory -ErrorAction SilentlyContinue)) { $m = [regex]::Match($d.Name, '^a(\d{4})$'); if ($m.Success -and [int]$m.Groups[1].Value -gt $max) { $max = [int]$m.Groups[1].Value } }
    }
    return ('a' + ($max + 1).ToString('0000'))
}

# 現況讀取集合（依 plan 的 readSet 重讀節；節消失＝hash 空）。回 @{ Files; Fingerprint; Changed; Ctxs }
function Get-PsSpLiveInput {
    param([string]$Root, $Eu, $Index, $Cache)
    $u = $Eu.Unit
    $files = @()
    $changed = $false
    $ctxs = @{}
    foreach ($f in @($u.readSet)) {
        $c = Get-PsSpNnCtx -Root $Root -Index $Index -Domain ([string]$f.domain) -File ([string]$f.file) -Cache $Cache
        $secs = @()
        foreach ($s in @($f.sections)) {
            $live = $null
            if ($null -ne $c) { $live = Get-PsSpSection -Ctx $c -Name ([string]$s.name) -Level ([int]$s.level) }
            if ($null -eq $live) { $live = [ordered]@{ name = [string]$s.name; level = [int]$s.level; start = 0; end = 0; hash = '' } }
            if ([string]$live.hash -cne [string]$s.hash) { $changed = $true }
            $secs += , $live
        }
        $h = ''; $g = [string]$f.grade
        $ev = @()
        if ($null -ne $c) { $h = $c.Hash; $ctxs[[string]$f.file] = $c; foreach ($e in @($c.Facts.evidence)) { $ev += [int]$e.n } }
        $files += , ([ordered]@{ domain = [string]$f.domain; file = [string]$f.file; path = [string]$f.path; role = [string]$f.role; hash = $h; grade = $g; evidence = @($ev); sections = @($secs) })
    }
    $fp = Get-PsSpFingerprint -UnitId ([string]$u.unitId) -Part ([string]$Eu.Part) -Files $files -Items $Eu.Items
    return @{ Files = @($files); Fingerprint = $fp; Changed = $changed; Ctxs = $ctxs }
}
function Get-PsSpPlanFingerprint { param($Eu) return (Get-PsSpFingerprint -UnitId ([string]$Eu.Unit.unitId) -Part ([string]$Eu.Part) -Files @($Eu.Unit.readSet) -Items $Eu.Items) }

# 單位狀態（不信任 job.json）：@( @{ Eu; Fingerprint; Receipt; Attempts; State; Live } )
#   State ∈ HAS_RECEIPT／PENDING／SOURCE_CHANGED／BLOCKED／BLOCKED_CAPACITY／WAITING_KNOWLEDGE／WAITING_AUDIT／BLOCKED_KNOWLEDGE／ROUTING_REQUIRED
function Get-PsSpUnitStatus {
    param([string]$Root, $Dirs, $Plan, $Index, $Cache = $null)
    if ($null -eq $Cache) { $Cache = @{} }
    $receipts = Get-PsSpReceipts -Dirs $Dirs
    $verdicts = Get-PsSpVerdicts -Dirs $Dirs
    $out = @()
    foreach ($eu in (Get-PsSpEffectiveUnits -Dirs $Dirs -Plan $Plan)) {
        $u = $eu.Unit
        $live = Get-PsSpLiveInput -Root $Root -Eu $eu -Index $Index -Cache $Cache
        $planFp = Get-PsSpPlanFingerprint -Eu $eu
        $st = @{ Eu = $eu; Fingerprint = $live.Fingerprint; PlanFingerprint = $planFp; Receipt = $null; Attempts = 0; State = 'PENDING'; Live = $live }
        foreach ($rc in $receipts) { if ([string]$rc.unitId -ceq [string]$u.unitId -and [string]$rc.part -ceq [string]$eu.Part -and [string]$rc.inputFingerprint -ceq $live.Fingerprint) { $st.Receipt = $rc } }
        foreach ($v in $verdicts) { if ([string]$v.unitId -ceq [string]$u.unitId -and [string]$v.part -ceq [string]$eu.Part -and [string]$v.inputFingerprint -ceq $live.Fingerprint -and [bool]$v.counted) { $st.Attempts++ } }
        $us = [string]$u.state
        if ($null -ne $st.Receipt) { $st.State = 'HAS_RECEIPT' }
        elseif ($us -ne 'DISPATCHABLE') { $st.State = $us }
        elseif ($live.Changed -or $live.Fingerprint -cne $planFp) { $st.State = 'SOURCE_CHANGED' }
        elseif ($eu.BlockedCapacity) { $st.State = 'BLOCKED_CAPACITY' }
        elseif ($st.Attempts -ge $script:PsSpMaxAttempts) { $st.State = 'BLOCKED' }
        $out += , $st
    }
    return , $out
}

# ── attempt：input.json → context 切片 → manifest ─────────────────

function Get-PsSpRelPath {
    param([string]$Root, [string]$Path)
    $r = $Root.TrimEnd('\', '/')
    if ($Path.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase) -and $Path.Length -gt $r.Length) { return (($Path.Substring($r.Length).TrimStart('\', '/')) -replace '\\', '/') }
    return ($Path -replace '\\', '/')
}

# 切片：回 @( @{ File; Lines=@(); Sections=@(名) } )；Capacity＝任一檔 >150 或總 >400
function Get-PsSpContextSlices {
    param($Eu, $Live)
    $itemByKey = @{}
    foreach ($i in @($Eu.Items)) { $itemByKey[([string]$i.file + '#' + [int]$i.line)] = [int]$i.n }
    $out = @()
    $total = 0
    foreach ($f in @($Live.Files)) {
        $ctx = $Live.Ctxs[[string]$f.file]
        if ($null -eq $ctx) { continue }
        $evByLine = @{}
        foreach ($e in @($ctx.Facts.evidence)) { $evByLine[[int]$e.line] = [int]$e.n }
        $lines = @('# 片段：' + [string]$f.file + '（' + [string]$f.domain + '；證據寫「' + [string]$f.file + '#附錄列號」，列號＝Evidence 附錄各行開頭的 E 數字）')
        $evLines = @()
        $names = @()
        foreach ($s in @($f.sections)) {
            if ([int]$s.start -lt 1) { continue }
            $names += [string]$s.name
            $sName = [string]$s.name
            $sStart = [int]$s.start; $sEnd = [Math]::Min([int]$s.end, $ctx.Lines.Count)
            $isEv = ($sName -eq 'Evidence附錄')
            $lo = $sStart; $hi = $sEnd
            if (-not $isEv -and [string]$Eu.Part -ne 'p0') {
                $first = 0; $last = 0
                foreach ($i in @($Eu.Items)) { if ([string]$i.file -ceq [string]$f.file -and [int]$i.line -ge $sStart -and [int]$i.line -le $sEnd) { if ($first -eq 0 -or [int]$i.line -lt $first) { $first = [int]$i.line }; if ([int]$i.line -gt $last) { $last = [int]$i.line } } }
                if ($first -eq 0) { continue }
                $lo = $first; $hi = $last
            }
            $blk = @('', ('## ' + $sName + '（L' + $sStart + '-' + $sEnd + '）'))
            for ($n = $lo; $n -le $hi; $n++) {
                $txt = $ctx.Lines[$n - 1]
                $k = [string]$f.file + '#' + $n
                if ($itemByKey.ContainsKey($k)) { $blk += ('L' + $n + ' #' + $itemByKey[$k] + ' | ' + $txt) }
                elseif ($isEv -and $evByLine.ContainsKey($n)) { $blk += ('L' + $n + ' E' + $evByLine[$n] + ' | ' + $txt) }
                else { $blk += ('L' + $n + ' | ' + $txt) }
            }
            if ($isEv) { $evLines += $blk } else { $lines += $blk }
        }
        # 每檔 ≤150：附錄列由尾端裁掉（未列入的證據只能寫 UNRESOLVED）
        $room = $script:PsSpMaxContextFileLines - $lines.Count
        if ($room -gt 0 -and $evLines.Count -gt 0) { if ($evLines.Count -le $room) { $lines += $evLines } else { $lines += @($evLines[0 .. ($room - 1)]) } }
        $out += , (@{ File = [string]$f.file; Lines = @($lines); Sections = @($names) })
        $total += $lines.Count
    }
    $cap = ($total -gt $script:PsSpMaxContextTotalLines)
    foreach ($o in $out) { if ($o.Lines.Count -gt $script:PsSpMaxContextFileLines) { $cap = $true } }
    return @{ Slices = @($out); Total = $total; Capacity = $cap }
}

function Get-PsSpFragmentHeader { param($Cap) return ('| ' + (@($Cap.table | ForEach-Object { [string]$_ }) -join ' | ') + ' |') }
function Get-PsSpTableSep { param([int]$Cols) return ('|' + ('---|' * $Cols)) }

# 建 attempt 目錄（input.json create-only、context/*.md、manifest.md）。回 @{ AttemptId; Dir; ManifestPath; FragmentPath; InputPath; InputText; Capacity }
function New-PsSpAttempt {
    param([string]$Root, $Dirs, $Plan, $Eu, $Live, $Cap, [string]$JobId)
    $slices = Get-PsSpContextSlices -Eu $Eu -Live $Live
    $r = @{ AttemptId = ''; Dir = ''; ManifestPath = ''; FragmentPath = ''; InputPath = ''; InputText = ''; Capacity = $slices.Capacity; Total = $slices.Total }
    if ($slices.Capacity) { return $r }
    $u = $Eu.Unit
    $aid = Get-PsSpNextAttemptId -Dirs $Dirs
    $dir = Join-Path $Dirs.Attempts $aid
    [void][System.IO.Directory]::CreateDirectory((Join-Path $dir 'context'))
    $input = [ordered]@{ schemaVersion = $script:PsSpecSchemaVersion; jobId = $JobId; planRef = (Get-PsSpPlanRef -Plan $Plan); attemptId = $aid; unitId = [string]$u.unitId; part = [string]$Eu.Part; requirementId = [string]$u.requirementId; factKind = [string]$u.factKind; files = @($Live.Files); items = @($Eu.Items); fingerprint = $Live.Fingerprint }
    $inputText = (ConvertTo-PsKnJson -Value $input) + "`n"
    $ip = Join-Path $dir 'input.json'
    if (-not (Write-PsKnCreateOnlyText -LiteralPath $ip -Text $inputText)) { throw ('input.json 已存在：' + $aid) }
    $ctxRel = @()
    foreach ($s in $slices.Slices) {
        $cp = Join-Path (Join-Path $dir 'context') ([string]$s.File)
        [void](Write-PsKnAtomicText -LiteralPath $cp -Text (($s.Lines -join "`n") + "`n") -Bom $false)
        $ctxRel += , (@{ File = [string]$s.File; Rel = (Get-PsSpRelPath -Root $Root -Path $cp); Sections = @($s.Sections) })
    }
    $fp = Join-Path $dir 'fragment.md'
    $mp = Join-Path $dir 'manifest.md'
    $hdr = Get-PsSpFragmentHeader -Cap $Cap
    $cols = @($Cap.table).Count
    $sb = New-Object System.Text.StringBuilder
    $nl = "`n"
    [void]$sb.Append('# Spec 工單（job ' + $JobId + '／attempt ' + $aid + '）').Append($nl).Append($nl)
    [void]$sb.Append('需求：' + [string]$u.requirementId + '　事實類別：' + [string]$u.factKind + '（COMPOSE）　單位：' + [string]$u.unitId + '　part：' + [string]$Eu.Part).Append($nl)
    [void]$sb.Append('只讀「## 讀取範圍」列的片段檔；只寫「## 輸出」指定的一個檔。片段檔每行開頭 L<n>＝來源檔行號，#<k>＝條目號，E<n>＝Evidence 附錄列號。').Append($nl).Append($nl)
    [void]$sb.Append('## 讀取範圍').Append($nl).Append($nl)
    [void]$sb.Append('| 片段檔 | 來源檔 | 節 |').Append($nl).Append('|---|---|---|').Append($nl)
    foreach ($c in $ctxRel) { [void]$sb.Append('| ' + $c.Rel + ' | ' + $c.File + ' | ' + (($c.Sections | ForEach-Object { $_ -replace 'Evidence附錄', 'Evidence 附錄' }) -join '；') + ' |').Append($nl) }
    [void]$sb.Append($nl).Append('## 條目').Append($nl).Append($nl)
    [void]$sb.Append('每一條都要處置：寫進事實表的「來源條目」欄，或列入「## 未採用」表。').Append($nl).Append($nl)
    [void]$sb.Append('| 條目 | 來源檔 | 列 | 種類 |').Append($nl).Append('|---|---|---|---|').Append($nl)
    foreach ($i in @($Eu.Items)) { [void]$sb.Append('| ' + [int]$i.n + ' | ' + [string]$i.file + ' | ' + [int]$i.line + ' | ' + [string]$i.kind + ' |').Append($nl) }
    [void]$sb.Append($nl).Append('## 輸出').Append($nl).Append($nl)
    [void]$sb.Append('唯一可寫：' + (Get-PsSpRelPath -Root $Root -Path $fp)).Append($nl)
    [void]$sb.Append('章節：先「## 事實」再「## 未採用」，各恰一張表；章節名與表頭逐字；≤150 行；不得有三反引號圍欄、雙方括號連結、slot 標記、JSON。').Append($nl)
    [void]$sb.Append('事實表頭（逐字）：' + $hdr).Append($nl)
    [void]$sb.Append('事實分隔列：' + (Get-PsSpTableSep -Cols $cols)).Append($nl)
    [void]$sb.Append('未採用表頭（逐字）：| 來源條目 | 原因 |').Append($nl)
    [void]$sb.Append('未採用分隔列：|---|---|').Append($nl)
    [void]$sb.Append('來源條目＝條目號（多個以 ; 分隔）；證據＝「來源檔#附錄列號」（附錄列號取片段檔 Evidence 附錄各行開頭的 E 數字；多個以 ; 分隔）或 UNRESOLVED；').Append($nl)
    [void]$sb.Append('每格不得空白（無值寫 NOT_APPLICABLE）；原因 ∈ ' + ($script:PsSpRejectReasons -join '／') + '。').Append($nl)
    if ($null -ne $Cap.enums) { foreach ($ep in $Cap.enums.PSObject.Properties) { [void]$sb.Append('欄「' + $ep.Name + '」值域：' + (@($ep.Value | ForEach-Object { [string]$_ }) -join '／')).Append($nl) } }
    [void](Write-PsKnAtomicText -LiteralPath $mp -Text $sb.ToString() -Bom $false)
    $r.AttemptId = $aid; $r.Dir = $dir; $r.ManifestPath = $mp; $r.FragmentPath = $fp; $r.InputPath = $ip; $r.InputText = $inputText
    return $r
}

# ── 片段驗收（骨架取自 ps-contract-lib.ps1 Read-CtFragment：表頭逐字、enum、證據參照、≤150 行、圍欄、洩漏標記）─
# 回 @{ Ok; Errors; Reasons; Capacity; Lines; Hash; Rows; Rejected; Covered; Closure; Unresolved; Present }
function Test-PsSpFragment {
    param([string]$LiteralPath, $Items, $Files, $Cap, [string[]]$TemplateLines = @())
    $r = @{ Ok = $false; Errors = @(); Reasons = @(); Capacity = $false; Lines = 0; Hash = ''; Rows = @(); Rejected = @(); Covered = @(); Closure = 'NONE'; Unresolved = 0; Present = 'UNKNOWN' }
    $addErr = { param([string]$Code, [string]$Msg) $script:PsSpFragErr += , @($Code, $Msg) }
    $script:PsSpFragErr = @()
    if (-not [System.IO.File]::Exists($LiteralPath)) { & $addErr 'MISSING' 'fragment 檔不存在' }
    else {
        $text = Read-PsKnText -LiteralPath $LiteralPath
        if ($text.Trim() -eq '') { & $addErr 'MISSING' 'fragment 檔空白' }
        else {
            $r.Hash = Get-PsKnTextHash -Text $text
            $lines = Get-PsKnLines -Text $text
            $r.Lines = $lines.Count
            if ($lines.Count -gt $script:PsSpMaxFragmentLines) { & $addErr 'LINES_OVER' ('超過 150 行（' + $lines.Count + '）'); $r.Capacity = $true }
            if ($text -match '```') { & $addErr 'FENCE' '含三反引號圍欄' }
            if ($text -match '\[\[') { & $addErr 'WIKILINK' '含 [[' }
            if ($text -match '\{\{slot:') { & $addErr 'SLOT_MARKER' '含 {{slot: 標記' }
            $leak = 0
            foreach ($k in $script:PsSpLeakMarkers) { if ($text.Contains($k)) { $leak++ } }
            if ($leak -ge 2) { & $addErr 'JSON_LEAK' '含模型契約 JSON 洩漏'; $r.Capacity = $true }
            $tset = @{}
            foreach ($tl in @($TemplateLines)) { $x = $tl.Trim(); if ($x -eq '' -or $x -match '^#{1,6}\s' -or $x -match '^\|[\s:|-]+\|$' -or $x -match '\{\{slot:') { continue }; $tset[$x] = $true }
            $leakT = 0
            foreach ($ln in $lines) { if ($tset.ContainsKey($ln.Trim())) { $leakT++ } }
            if ($leakT -gt 0) { & $addErr 'TEMPLATE_LEAK' ('含模板副本原文行 ' + $leakT) }
            $itemSet = @{}
            foreach ($i in @($Items)) { $itemSet[[int]$i.n] = $true }
            $evOf = @{}
            foreach ($f in @($Files)) { $evOf[[string]$f.file] = @($f.evidence | ForEach-Object { [int]$_ }) }
            $checkEvidence = {
                param([string]$Cell)
                $bad = @(); $unres = 0
                foreach ($tok in ($Cell -split ';')) {
                    $x = $tok.Trim()
                    if ($x -eq '') { continue }
                    if ($x -eq 'UNRESOLVED') { $unres++; continue }
                    $m = [regex]::Match($x, '^(.+?)#(\d+)$')
                    if (-not $m.Success) { $bad += $x; continue }
                    $fn = $m.Groups[1].Value; $rowN = [int]$m.Groups[2].Value
                    $okL = $false
                    if ($evOf.ContainsKey($fn) -and @($evOf[$fn]) -contains $rowN) { $okL = $true }
                    if (-not $okL) { $bad += $x }
                }
                return @{ Bad = $bad; Unresolved = $unres }
            }
            $secs = Get-PsSpSections -Text $text
            $hdr = @($Cap.table | ForEach-Object { [string]$_ })
            $evCol = -1
            for ($i = 0; $i -lt $hdr.Count; $i++) { if ($hdr[$i] -eq '證據') { $evCol = $i }; if ($hdr[$i] -eq '來源條目') { $srcCol = $i } }
            $enumCols = @{}
            if ($null -ne $Cap.enums) { foreach ($ep in $Cap.enums.PSObject.Properties) { for ($i = 0; $i -lt $hdr.Count; $i++) { if ($hdr[$i] -eq $ep.Name) { $enumCols[$i] = @($ep.Value | ForEach-Object { [string]$_ }) } } } }
            $covered = @{}
            if (-not $secs.Contains($script:PsSpFragmentSection)) { & $addErr 'SECTION_MISSING' '缺章節「## 事實」' }
            else {
                $tb = Get-PsSpTableRows -SectionText ([string]$secs[$script:PsSpFragmentSection])
                $hdrOk = ($null -ne $tb.Header -and $tb.Header.Count -eq $hdr.Count)
                if ($hdrOk) { for ($i = 0; $i -lt $hdr.Count; $i++) { if ($tb.Header[$i] -ne $hdr[$i]) { $hdrOk = $false } } }
                if (-not $hdrOk) { & $addErr 'HEADER_MISMATCH' ('「## 事實」表頭須逐字：| ' + ($hdr -join ' | ') + ' |') }
                else {
                    $ri = 0
                    foreach ($row in $tb.Rows) {
                        $ri++
                        if ($row.Count -ne $hdr.Count) { & $addErr 'COLUMN_COUNT' ('「## 事實」第 ' + $ri + ' 列欄數 ' + $row.Count + ' ≠ ' + $hdr.Count); continue }
                        $rowItems = @(); $rowEv = @()
                        for ($i = 0; $i -lt $row.Count; $i++) { if ($row[$i] -eq '') { & $addErr 'EMPTY_CELL' ('「## 事實」第 ' + $ri + ' 列第 ' + ($i + 1) + ' 欄空值') } }
                        foreach ($tok in ($row[$srcCol] -split ';')) {
                            $x = $tok.Trim()
                            if ($x -eq '') { continue }
                            $n = 0
                            if (-not [int]::TryParse($x, [ref]$n) -or -not $itemSet.ContainsKey($n)) { & $addErr 'ITEM_UNKNOWN' ('「## 事實」第 ' + $ri + ' 列來源條目「' + $x + '」不在工單列舉'); continue }
                            $rowItems += $n; $covered[$n] = $true
                        }
                        foreach ($ci in $enumCols.Keys) { $v = $row[[int]$ci]; if ($v -ne 'NOT_APPLICABLE' -and $v -ne 'UNRESOLVED' -and @($enumCols[$ci]) -notcontains $v) { & $addErr 'ENUM' ('「## 事實」第 ' + $ri + ' 列「' + $v + '」不在值域') } }
                        if ($evCol -ge 0) {
                            $ce = & $checkEvidence $row[$evCol]
                            foreach ($b in $ce.Bad) { & $addErr 'EVIDENCE_UNKNOWN' ('「## 事實」第 ' + $ri + ' 列證據「' + $b + '」不在讀取集合') }
                            $r.Unresolved += [int]$ce.Unresolved
                            foreach ($tok in ($row[$evCol] -split ';')) { $x = $tok.Trim(); if ($x -ne '') { $rowEv += $x } }
                        }
                        $r.Rows += , ([ordered]@{ n = $ri; cells = @($row); items = @($rowItems); evidence = @($rowEv) })
                    }
                }
            }
            if (-not $secs.Contains($script:PsSpRejectSection)) { & $addErr 'SECTION_MISSING' '缺章節「## 未採用」' }
            else {
                $tb = Get-PsSpTableRows -SectionText ([string]$secs[$script:PsSpRejectSection])
                $hdrOk = ($null -ne $tb.Header -and $tb.Header.Count -eq 2 -and $tb.Header[0] -eq $script:PsSpRejectHeader[0] -and $tb.Header[1] -eq $script:PsSpRejectHeader[1])
                if (-not $hdrOk) { & $addErr 'HEADER_MISMATCH' '「## 未採用」表頭須逐字：| 來源條目 | 原因 |' }
                else {
                    $ri = 0
                    foreach ($row in $tb.Rows) {
                        $ri++
                        if ($row.Count -ne 2) { & $addErr 'COLUMN_COUNT' ('「## 未採用」第 ' + $ri + ' 列欄數 ' + $row.Count + ' ≠ 2'); continue }
                        $n = 0
                        if (-not [int]::TryParse($row[0].Trim(), [ref]$n) -or -not $itemSet.ContainsKey($n)) { & $addErr 'ITEM_UNKNOWN' ('「## 未採用」第 ' + $ri + ' 列來源條目「' + $row[0] + '」不在工單列舉'); continue }
                        if ($script:PsSpRejectReasons -notcontains $row[1].Trim()) { & $addErr 'ENUM' ('「## 未採用」第 ' + $ri + ' 列原因「' + $row[1] + '」不在值域'); continue }
                        $covered[$n] = $true
                        $r.Rejected += , ([ordered]@{ n = $n; reason = $row[1].Trim() })
                    }
                }
            }
            $missing = 0
            foreach ($i in @($Items)) { if ($covered.ContainsKey([int]$i.n)) { $r.Covered += [int]$i.n } else { $missing++ } }
            if ($missing -eq 0) { $r.Closure = 'COMPLETE' } else { $r.Closure = 'PARTIAL' }
            if ($r.Rows.Count -gt 0) { $r.Present = 'TRUE' } elseif ($r.Closure -eq 'COMPLETE') { $r.Present = 'FALSE' }
        }
    }
    foreach ($e in $script:PsSpFragErr) { if ($r.Reasons -notcontains $e[0]) { $r.Reasons += $e[0] }; $r.Errors += ($e[0] + '：' + $e[1]) }
    $r.Ok = ($r.Errors.Count -eq 0)
    return $r
}

function Write-PsSpReceipt {
    param($Dirs, $Eu, $Live, $Frag, [string]$AttemptId, [string]$PlanRef, [string]$JobId, [string]$InputText)
    $u = $Eu.Unit
    $rc = [ordered]@{
        schemaVersion = $script:PsSpecSchemaVersion; jobId = $JobId; planRef = $PlanRef; unitId = [string]$u.unitId; unitKey = [string]$u.unitKey; part = [string]$Eu.Part
        requirementId = [string]$u.requirementId; factKind = [string]$u.factKind; attemptId = $AttemptId; attemptPath = ('attempts/' + $AttemptId)
        inputFingerprint = $Live.Fingerprint; fragmentHash = $Frag.Hash; lines = $Frag.Lines; closure = $Frag.Closure; present = $Frag.Present
        rows = @($Frag.Rows); rejected = @($Frag.Rejected); covered = @($Frag.Covered); unresolvedEvidence = $Frag.Unresolved
        readSetGrade = [string]$u.grade; input = $InputText; acceptedAt = (Get-PsKnUtcStamp)
    }
    $p = Join-Path $Dirs.Receipts (Get-PsSpReceiptName -UnitKey ([string]$u.unitKey) -Part ([string]$Eu.Part) -Fingerprint $Live.Fingerprint)
    $ok = Write-PsKnCreateOnlyText -LiteralPath $p -Text ((ConvertTo-PsKnJson -Value $rc) + "`n")
    return @{ Ok = $ok; Path = $p; Existed = (-not $ok) }
}
function Write-PsSpVerdict {
    param($Dirs, [string]$AttemptId, $Verdict)
    $o = [ordered]@{}
    foreach ($k in @($Verdict.Keys)) { $o[[string]$k] = $Verdict[$k] }
    $o['attemptId'] = $AttemptId
    $o['at'] = Get-PsKnUtcStamp
    return (Write-PsKnAtomicText -LiteralPath (Join-Path (Join-Path $Dirs.Attempts $AttemptId) 'verdict.json') -Text ((ConvertTo-PsKnJson -Value $o) + "`n") -Bom $false)
}
function Write-PsSpOutcome {
    param($Dirs, [string]$AttemptId, $Outcome)
    $o = [ordered]@{}
    foreach ($k in @($Outcome.Keys)) { $o[[string]$k] = $Outcome[$k] }
    $o['at'] = Get-PsKnUtcStamp
    return (Write-PsKnAtomicText -LiteralPath (Join-Path (Join-Path $Dirs.Attempts $AttemptId) 'outcome.json') -Text ((ConvertTo-PsKnJson -Value $o) + "`n") -Bom $false)
}

# WAITING 中的 need 現在是否已有新結果（＝須重規劃）。回變動數
function Get-PsSpKnowledgeRefresh {
    param([string]$Root, $Plan, $Index)
    $n = 0
    foreach ($q in @($Plan.requirements)) {
        foreach ($nd in @($q.needs)) {
            $st = [string]$nd.state
            if ($st -ne 'WAITING_KNOWLEDGE' -and $st -ne 'WAITING_AUDIT') { continue }
            $rid = [string]$nd.requestId
            if ($rid -eq '') { continue }
            if ($st -eq 'WAITING_KNOWLEDGE') { if ($null -ne (Get-PsSupplementalResult -Root $Root -RequestId $rid)) { $n++ } }
            else { $c = Get-PsSuppCompletion -Root $Root -RequestId $rid -Index $Index; if ($c.Audited) { $n++ } }
        }
    }
    return $n
}

# ── 外環（-Run）：Dispatch scriptblock 收 @{ JobId; AttemptId; AttemptDir; ManifestPath; FragmentPath } 回 @{ TimedOut; ExitCode; FailureKind; SlotBusy }
# 回 @{ Code; Exit; Phase; Sessions; Accepted; Invalid; Blocked; Splits; SourceChanged; Pending; Waiting; Summary }
function Invoke-PsSpRun {
    param([string]$Root, $Dirs, $Plan, $PackV, $Capabilities, [string]$JobId, [int]$MaxSessions, [scriptblock]$Dispatch, [scriptblock]$Log = $null, $Index)
    function L([string]$m) { if ($null -ne $Log) { & $Log $m } }
    $r = @{ Code = ''; Exit = 0; Phase = 'RUNNING'; Sessions = 0; Accepted = 0; Invalid = 0; Blocked = 0; Splits = 0; SourceChanged = 0; Pending = 0; Waiting = 0; Replan = 0; SessionFailed = 0; SlotBusy = $false; Summary = @() }
    $ref = Get-PsSpPlanRef -Plan $Plan
    $r.Replan = Get-PsSpKnowledgeRefresh -Root $Root -Plan $Plan -Index $Index
    $cache = @{}
    $guard = 0
    while ($true) {
        $guard++
        if ($guard -gt 200) { break }
        $status = Get-PsSpUnitStatus -Root $Root -Dirs $Dirs -Plan $Plan -Index $Index -Cache $cache
        $next = $null
        $counts = @{ PENDING = 0; SOURCE_CHANGED = 0; BLOCKED = 0; BLOCKED_CAPACITY = 0; WAITING = 0; HAS_RECEIPT = 0; BLOCKED_KNOWLEDGE = 0 }
        foreach ($s in $status) {
            $st = [string]$s.State
            if ($st -eq 'PENDING') { $counts.PENDING++; if ($null -eq $next) { $next = $s } }
            elseif ($st -eq 'SOURCE_CHANGED') { $counts.SOURCE_CHANGED++ }
            elseif ($st -eq 'BLOCKED') { $counts.BLOCKED++ }
            elseif ($st -eq 'BLOCKED_CAPACITY') { $counts.BLOCKED_CAPACITY++ }
            elseif ($st -eq 'HAS_RECEIPT') { $counts.HAS_RECEIPT++ }
            elseif ($st -eq 'BLOCKED_KNOWLEDGE') { $counts.BLOCKED_KNOWLEDGE++ }
            else { $counts.WAITING++ }
        }
        $r.Pending = $counts.PENDING; $r.SourceChanged = $counts.SOURCE_CHANGED; $r.Blocked = $counts.BLOCKED + $counts.BLOCKED_CAPACITY; $r.Waiting = $counts.WAITING
        if ($counts.SOURCE_CHANGED -gt 0) { break }
        if ($null -eq $next) { break }
        if ($r.Sessions -ge $MaxSessions) { break }
        $eu = $next.Eu
        $u = $eu.Unit
        $cap = Get-PsSpFactKind -Capabilities $Capabilities -FactKind ([string]$u.factKind)
        $att = New-PsSpAttempt -Root $Root -Dirs $Dirs -Plan $Plan -Eu $eu -Live $next.Live -Cap $cap -JobId $JobId
        if ($att.Capacity) {
            $sp = Write-PsSpSplit -Dirs $Dirs -Plan $Plan -Eu $eu
            $r.Splits++
            if ($sp.Blocked) { L ('SPEC：capacity 不可拆 → BLOCKED_CAPACITY（' + [string]$u.requirementId + '）') } else { L ('SPEC：context ' + $att.Total + ' 行超限 → 拆分（' + [string]$u.requirementId + '）') }
            continue
        }
        L ('SPEC：派工 ' + $att.AttemptId + ' ' + [string]$u.requirementId + ' ' + [string]$u.factKind + ' part=' + [string]$eu.Part + ' items=' + @($eu.Items).Count)
        $r.Sessions++
        $sess = & $Dispatch @{ JobId = $JobId; AttemptId = $att.AttemptId; AttemptDir = $att.Dir; ManifestPath = $att.ManifestPath; FragmentPath = $att.FragmentPath }
        $healthy = (-not [bool]$sess.TimedOut -and -not [bool]$sess.SlotBusy -and [int]$sess.ExitCode -eq 0 -and [string]$sess.FailureKind -ne 'PROMPT_UNSAFE')
        [void](Write-PsSpOutcome -Dirs $Dirs -AttemptId $att.AttemptId -Outcome @{ timedOut = [bool]$sess.TimedOut; exitCode = [int]$sess.ExitCode; failureKind = [string]$sess.FailureKind; slotBusy = [bool]$sess.SlotBusy; healthy = $healthy })
        if ([bool]$sess.SlotBusy) { $r.SlotBusy = $true }
        # 驗收：來源快照重算
        $live2 = Get-PsSpLiveInput -Root $Root -Eu $eu -Index $Index -Cache @{}
        $fpMatch = ($live2.Fingerprint -ceq $next.Live.Fingerprint)
        $frag = Test-PsSpFragment -LiteralPath $att.FragmentPath -Items $eu.Items -Files $next.Live.Files -Cap $cap -TemplateLines $PackV.TemplateLines
        $verdict = @{ unitId = [string]$u.unitId; part = [string]$eu.Part; requirementId = [string]$u.requirementId; factKind = [string]$u.factKind; inputFingerprint = $next.Live.Fingerprint; counted = $false; code = ''; reasons = @($frag.Reasons); lines = $frag.Lines; closure = $frag.Closure; sessionHealthy = $healthy; fingerprintMatch = $fpMatch; capacity = $frag.Capacity }
        if (-not $fpMatch) {
            $verdict.code = '4-04'; $r.SourceChanged++
            L ('SPEC：來源已變（' + [string]$u.requirementId + '）→ 拒收、不記 attempt、需 -Plan 重規劃')
            [void](Write-PsSpVerdict -Dirs $Dirs -AttemptId $att.AttemptId -Verdict $verdict)
            break
        }
        if (-not $healthy) {
            $verdict.code = '3-04'; $r.SessionFailed++
            [void](Write-PsSpVerdict -Dirs $Dirs -AttemptId $att.AttemptId -Verdict $verdict)
            L ('SPEC：session 未健康結束（' + [string]$sess.FailureKind + '）→ 不記 attempt、停止本輪')
            break
        }
        if ($frag.Capacity) {
            $verdict.code = '4-05'
            $sp = Write-PsSpSplit -Dirs $Dirs -Plan $Plan -Eu $eu
            $r.Splits++
            if ($sp.Blocked) { $verdict.code = '4-06' }
            [void](Write-PsSpVerdict -Dirs $Dirs -AttemptId $att.AttemptId -Verdict $verdict)
            L ('SPEC：容量事件（' + ($frag.Reasons -join ',') + '）→ 不記 attempt、拆分 ' + [string]$u.requirementId)
            continue
        }
        if ($frag.Ok) {
            $verdict.counted = $true; $verdict.code = '4-01'
            $rc = Write-PsSpReceipt -Dirs $Dirs -Eu $eu -Live $next.Live -Frag $frag -AttemptId $att.AttemptId -PlanRef $ref -JobId $JobId -InputText $att.InputText
            [void](Write-PsSpVerdict -Dirs $Dirs -AttemptId $att.AttemptId -Verdict $verdict)
            $r.Accepted++
            L ('SPEC：驗收通過 ' + $att.AttemptId + ' closure=' + $frag.Closure + ' rows=' + @($frag.Rows).Count)
            continue
        }
        $verdict.counted = $true; $verdict.code = '4-02'
        [void](Write-PsSpVerdict -Dirs $Dirs -AttemptId $att.AttemptId -Verdict $verdict)
        $r.Invalid++
        L ('SPEC：驗收不合格 ' + $att.AttemptId + '（' + ($frag.Reasons -join ',') + '）')
    }
    # 結論
    if ($r.SourceChanged -gt 0) { $r.Code = 'SPEC1-4-04-' + $r.SourceChanged; $r.Exit = 1; $r.Phase = 'PLANNED' }
    elseif ($r.Replan -gt 0) { $r.Code = 'SPEC1-5-06-' + $r.Replan; $r.Exit = 1; $r.Phase = 'PLANNED' }
    elseif ($r.SlotBusy) { $r.Code = 'SPEC1-3-03'; $r.Exit = 1 }
    elseif ($r.SessionFailed -gt 0) { $r.Code = 'SPEC1-3-04-' + $r.SessionFailed; $r.Exit = 1 }
    elseif ($r.Blocked -gt 0 -and $r.Pending -eq 0) { $r.Code = 'SPEC1-4-03-' + $r.Blocked; $r.Exit = 1; $r.Phase = 'BLOCKED' }
    elseif ($r.Pending -gt 0) { $r.Code = 'SPEC1-3-02-' + $r.Pending; $r.Exit = 0 }
    elseif ($counts.BLOCKED_KNOWLEDGE -gt 0) { $r.Code = 'SPEC1-5-05-' + $counts.BLOCKED_KNOWLEDGE; $r.Exit = 1; $r.Phase = 'BLOCKED' }
    elseif ($r.Waiting -gt 0) {
        $ph = Get-PsSpPhaseFromPlan -Plan $Plan
        if ($ph -eq 'WAITING_AUDIT') { $r.Code = 'SPEC1-5-04-' + $r.Waiting } else { $r.Code = 'SPEC1-5-01-' + $r.Waiting }
        $r.Exit = 0; $r.Phase = $ph
    }
    else {
        $ph = Get-PsSpPhaseFromPlan -Plan $Plan
        if ($ph -eq 'PLANNED') { $r.Code = 'SPEC1-3-01-' + $counts.HAS_RECEIPT; $r.Exit = 0; $r.Phase = 'READY' }
        elseif ($ph -eq 'BLOCKED') { $r.Code = 'SPEC1-5-05-1'; $r.Exit = 1; $r.Phase = 'BLOCKED' }
        elseif ($ph -eq 'WAITING_AUDIT') { $r.Code = 'SPEC1-5-04-1'; $r.Exit = 0; $r.Phase = $ph }
        else { $r.Code = 'SPEC1-5-01-1'; $r.Exit = 0; $r.Phase = $ph }
    }
    return $r
}

# ── 評估（render 與 gate 共用）────────────────────────────────────

# 來源重驗：facts 的 sourceRefs（節 hash／檔 hash）＋各單位收據指紋。回 @{ Mismatch; Status; Facts }
function Test-PsSpSources {
    param([string]$Root, $Dirs, $Plan, $Index)
    $cache = @{}
    $mis = 0
    $factOk = @{}
    foreach ($f in @($Plan.facts)) {
        $ok = $true
        foreach ($sr in @($f.sourceRefs)) {
            $role = [string]$sr.role
            if ($role -eq 'WIKI' -or $role -eq 'OVERVIEW') {
                $p = Join-Path $Root ([string]$sr.path)
                if ((Get-PsKnFileHash -LiteralPath $p) -cne [string]$sr.hash) { $ok = $false }
                continue
            }
            $c = Get-PsSpNnCtx -Root $Root -Index $Index -Domain ([string]$sr.domain) -File ([string]$sr.file) -Cache $cache
            if ($null -eq $c) { $ok = $false; continue }
            if ([string]$sr.section -eq '') { if ($c.Hash -cne [string]$sr.hash) { $ok = $false }; continue }
            $live = Get-PsSpSection -Ctx $c -Name ([string]$sr.section) -Level ([int]$sr.level)
            if ($null -eq $live -or [string]$live.hash -cne [string]$sr.sectionHash) { $ok = $false }
        }
        $factOk[[string]$f.factId] = $ok
        if (-not $ok) { $mis++ }
    }
    $status = Get-PsSpUnitStatus -Root $Root -Dirs $Dirs -Plan $Plan -Index $Index -Cache $cache
    $receipts = Get-PsSpReceipts -Dirs $Dirs
    foreach ($s in $status) {
        if ([string]$s.State -eq 'SOURCE_CHANGED') { $mis++; continue }
        if ($null -ne $s.Receipt) { continue }
        # 有舊收據但指紋不符＝來源已變
        foreach ($rc in $receipts) { if ([string]$rc.unitId -ceq [string]$s.Eu.Unit.unitId -and [string]$rc.part -ceq [string]$s.Eu.Part) { $mis++; break } }
    }
    return @{ Mismatch = $mis; Status = @($status); Facts = $factOk }
}

# 每 requirement 一筆評估：@{ Req; Applicable; State; Facts; Units=@(@{Eu;Receipt;State}); Findings=@(@{code;…}); Closure; Rows; Fatal }
function Get-PsSpEvaluation {
    param($Plan, $PackV, $Status, $Capabilities)
    $factById = @{}
    foreach ($f in @($Plan.facts)) { $factById[[string]$f.factId] = $f }
    $fv = Get-PsSpFactValues -Facts @($Plan.facts)
    $unitsByReq = @{}
    foreach ($s in $Status) { $rid = [string]$s.Eu.Unit.requirementId; if (-not $unitsByReq.ContainsKey($rid)) { $unitsByReq[$rid] = @() }; $unitsByReq[$rid] += , $s }
    # COMPOSE present：收據 rows>0 ＝TRUE；rows=0 且 closure COMPLETE＝FALSE；否則 UNKNOWN
    foreach ($q in @($Plan.requirements)) {
        if ([string]$q.mode -ne 'COMPOSE') { continue }
        $fk = [string]$q.factKind
        $vals = @()
        $all = $true
        foreach ($s in @($unitsByReq[[string]$q.id])) { if ($null -eq $s.Receipt) { $all = $false; continue }; $vals += [string]$s.Receipt.present }
        $pv = 'UNKNOWN'
        if ($all -and $vals.Count -gt 0) { if ($vals -contains 'TRUE') { $pv = 'TRUE' } elseif ($vals -notcontains 'UNKNOWN') { $pv = 'FALSE' } }
        elseif ($vals -contains 'TRUE') { $pv = 'TRUE' }
        foreach ($pn in @('present', 'layout', 'fields', 'trigger', 'condition', 'message', 'usage')) { $k = $fk + '.' + $pn; if (-not $fv.ContainsKey($k) -or $fv[$k] -eq 'UNKNOWN') { $fv[$k] = $pv } }
    }
    $out = @()
    foreach ($q in @($Plan.requirements)) {
        $e = @{ Req = $q; Applicable = (Test-PsSpApplicability -App $q.applicability -FactValues $fv); State = [string]$q.state; Facts = @(); Units = @(); Findings = @(); Closure = 'NONE'; Rows = 0; Fatal = $false; Satisfied = $false }
        $rid = [string]$q.id; $fk = [string]$q.factKind; $mode = [string]$q.mode
        $add = { param([string]$Code, $Extra) $o = [ordered]@{ code = $Code; requirementId = $rid; factKind = $fk; mode = $mode }; foreach ($k in @($Extra.Keys)) { $o[[string]$k] = $Extra[$k] }; $script:PsSpEvalF += , $o }
        $script:PsSpEvalF = @()
        if ($e.Applicable -eq 'FALSE') { $e.State = 'NOT_APPLICABLE'; $e.Satisfied = $true; $out += , $e; continue }
        if ($e.Applicable -eq 'UNKNOWN') { & $add '7-15' @{ a = 0; c = 'UNKNOWN' } }
        if ($mode -eq 'UNSUPPORTED') { & $add '7-17' @{ a = 0; c = 'NONE' }; $e.State = 'UNSUPPORTED'; $e.Findings = @($script:PsSpEvalF); $out += , $e; continue }
        $needState = [string]$q.state
        if ($needState -eq 'WAITING_KNOWLEDGE' -or $needState -eq 'WAITING_AUDIT' -or $needState -eq 'ROUTING_REQUIRED') { & $add '7-19' @{ a = 0; c = $needState } }
        if ($needState -eq 'BLOCKED_KNOWLEDGE') { & $add '7-18' @{ a = 0; c = $needState }; $e.Fatal = $true }
        $waiting = ($needState -eq 'WAITING_KNOWLEDGE' -or $needState -eq 'WAITING_AUDIT' -or $needState -eq 'ROUTING_REQUIRED' -or $needState -eq 'BLOCKED_KNOWLEDGE')
        if ($mode -eq 'EXTRACT') {
            foreach ($fid in @($q.facts)) { if ($factById.ContainsKey($fid)) { $e.Facts += , $factById[$fid] } }
            $a = @($e.Facts).Count
            if ($a -eq 0) {
                if (-not $waiting) { & $add '7-11' @{ a = 0; c = 'NONE' }; if ([bool]$q.required) { $e.Fatal = $true } }
                $e.Closure = 'NONE'
            }
            else {
                $minG = Get-PsSpMinGrade -Grades @($e.Facts | ForEach-Object { [string]$_.grade })
                if (-not (Test-PsSpGradeMeetsPolicy -Grade $minG -Policy ([string]$q.evidencePolicy))) { & $add '7-13' @{ a = $a; c = $minG } }
                $unres = 0
                foreach ($f in $e.Facts) { foreach ($ev in @($f.evidenceRefs)) { if (-not [bool]$ev.resolved) { $unres++ } } }
                if ($unres -gt 0) { & $add '7-14' @{ a = $unres; c = 'UNRESOLVED' } }
                $cl = [string]$e.Facts[0].closure
                $e.Closure = $cl
                $rows = 0
                foreach ($f in $e.Facts) { foreach ($pn in @('fields', 'rules', 'tables', 'objects', 'items', 'rows', 'entries')) { $v = Get-PsSpProp $f.value $pn; if ($null -ne $v) { $rows += @($v).Count; break } } }
                if ($fk -eq 'ENTITY.DETAIL' -or $fk -eq 'UI.COMPONENT_IDENTITY' -or $cl -eq 'PRESENT') { $rows = $a }
                $e.Rows = $rows
                if ([string]$q.cardinality -eq 'ONE' -and $a -ne 1 -and $fk -ne 'ENTITY.DETAIL') { & $add '7-12' @{ a = $a; c = 'ONE' } }
                if ($fk -eq 'UI.NAVIGATION' -and [string]$e.Facts[0].value.unconfirmed -eq 'True') { & $add '7-21' @{ a = $rows; c = 'UNKNOWN' } }
                elseif ($cl -ne 'NOT_APPLICABLE' -and $rows -eq 0 -and $cl -ne 'PRESENT' -and $cl -ne 'SINGLE') { & $add '7-21' @{ a = 0; c = 'PARTIAL' } }
                if ($e.Findings.Count -eq 0) { }
            }
        }
        else {
            $units = @($unitsByReq[$rid])
            $e.Units = $units
            if ($units.Count -eq 0 -and -not $waiting) { & $add '7-11' @{ a = 0; c = 'NONE' }; if ([bool]$q.required) { $e.Fatal = $true } }
            $rows = 0; $allComplete = $true; $anyReceipt = $false; $unres = 0
            foreach ($s in $units) {
                $st = [string]$s.State
                if ($st -eq 'HAS_RECEIPT') { $anyReceipt = $true; $rows += @($s.Receipt.rows).Count; $unres += [int]$s.Receipt.unresolvedEvidence; if ([string]$s.Receipt.closure -ne 'COMPLETE') { $allComplete = $false; & $add '7-21' @{ a = @($s.Receipt.rows).Count; c = 'PARTIAL' } } }
                elseif ($st -eq 'BLOCKED' -or $st -eq 'BLOCKED_CAPACITY') { $allComplete = $false; & $add '7-18' @{ a = 0; c = $st }; $e.Fatal = $true }
                elseif ($st -eq 'PENDING' -or $st -eq 'SOURCE_CHANGED') { $allComplete = $false; & $add '7-11' @{ a = 0; c = $st }; if ([bool]$q.required) { $e.Fatal = $true } }
                elseif ($st -eq 'BLOCKED_KNOWLEDGE') { $allComplete = $false }
                else { $allComplete = $false; if (-not $waiting) { & $add '7-19' @{ a = 0; c = $st } } }
                if (-not (Test-PsSpGradeMeetsPolicy -Grade ([string]$s.Eu.Unit.grade) -Policy ([string]$q.evidencePolicy)) -and $st -eq 'HAS_RECEIPT') { & $add '7-13' @{ a = 1; c = [string]$s.Eu.Unit.grade } }
            }
            if ($unres -gt 0) { & $add '7-14' @{ a = $unres; c = 'UNRESOLVED' } }
            $e.Rows = $rows
            if ($units.Count -gt 0 -and $anyReceipt -and $allComplete) { $e.Closure = 'COMPLETE' } elseif ($anyReceipt) { $e.Closure = 'PARTIAL' } else { $e.Closure = 'NONE' }
            if ([string]$q.cardinality -eq 'ALL_DISCOVERED' -and $e.Closure -ne 'COMPLETE' -and $anyReceipt) { & $add '7-12' @{ a = $rows; c = $e.Closure } }
        }
        $e.Findings = @($script:PsSpEvalF)
        $fatalCodes = @('7-11', '7-18', '7-12')
        foreach ($f in $e.Findings) { if ($fatalCodes -contains [string]$f.code -and [bool]$q.required) { $e.Fatal = $true } }
        $e.Satisfied = ($e.Findings.Count -eq 0)
        $out += , $e
    }
    return , $out
}

function Get-PsSpGate {
    param($Plan, $PackV, $Evals, [string]$Generation)
    $findings = @()
    $blocked = $false
    foreach ($e in $Evals) {
        foreach ($f in @($e.Findings)) { $findings += , $f }
        $q = $e.Req
        if ([bool]$q.required -and $e.Applicable -ne 'FALSE') {
            foreach ($f in @($e.Findings)) { if ([string]$f.code -eq '7-18') { $blocked = $true } }
            if ($e.State -eq 'BLOCKED_KNOWLEDGE') { $blocked = $true }
        }
    }
    $ck = @()
    $uncovered = 0
    foreach ($c in @($PackV.Pack.checklist)) {
        $cid = [string]$c
        $cov = $false
        foreach ($e in $Evals) { if (@($e.Req.checklistRefs) -contains $cid -and ($e.Satisfied -or $e.Applicable -eq 'FALSE')) { $cov = $true } }
        if (-not $cov) { $uncovered++; $findings += , ([ordered]@{ code = '7-16'; requirementId = $cid; factKind = 'CHECKLIST'; mode = 'ANY'; a = 0; c = 'UNCOVERED' }) }
        $ck += , ([ordered]@{ id = $cid; covered = $cov })
    }
    if (-not $PackV.Signed) { $findings += , ([ordered]@{ code = '8-01'; requirementId = 'PACK'; factKind = 'MAPPING'; mode = 'ANY'; a = $PackV.ReviewedVersion; c = 'UNSIGNED' }) }
    $verdict = 'SPEC_COMPLETE'
    $nonInfo = 0
    foreach ($f in $findings) { if ([string]$f.code -ne '8-01') { $nonInfo++ } }
    if ($blocked) { $verdict = 'BLOCKED' } elseif ($nonInfo -gt 0) { $verdict = 'SPEC_PARTIAL' }
    $unknown = 0; foreach ($f in $findings) { if ([string]$f.code -eq '7-15') { $unknown++ } }
    $gate = [ordered]@{ schemaVersion = $script:PsSpecSchemaVersion; generation = $Generation; planRef = (Get-PsSpPlanRef -Plan $Plan); packVersion = $PackV.PackVersion; reviewedVersion = $PackV.ReviewedVersion; signed = $PackV.Signed; verdict = $verdict; findingCount = $nonInfo; unknownDebt = $unknown; checklistUncovered = $uncovered; requirements = @(); checklist = @($ck); findings = @($findings) }
    foreach ($e in $Evals) { $gate.requirements += , ([ordered]@{ id = [string]$e.Req.id; factKind = [string]$e.Req.factKind; mode = [string]$e.Req.mode; required = [bool]$e.Req.required; applicable = $e.Applicable; state = $e.State; closure = $e.Closure; rows = $e.Rows; findings = @($e.Findings).Count }) }
    return $gate
}

# ── 確定性 renderer（每 requirement 一個 block；slot＝其 requirements 的 block 串接）──────

function ConvertTo-PsSpCell { param([string]$V) if ($null -eq $V) { return '' }; return (($V -replace '\|', '／') -replace "[`r`n]+", ' ').Trim() }
function ConvertTo-PsSpTable {
    param([string[]]$Header, $Rows)
    $o = @('| ' + ($Header -join ' | ') + ' |', (Get-PsSpTableSep -Cols $Header.Count))
    foreach ($r in @($Rows)) { $o += ('| ' + (@($r | ForEach-Object { ConvertTo-PsSpCell ([string]$_) }) -join ' | ') + ' |') }
    return , $o
}
function ConvertTo-PsSpBlock {
    param($E, $Capabilities)
    $q = $E.Req
    $o = @('<!-- ' + [string]$q.id + ' ' + [string]$q.factKind + ' -->')
    if ($E.Applicable -eq 'FALSE') { $o += '不適用（NOT_APPLICABLE）'; return , $o }
    if ($E.Applicable -eq 'UNKNOWN') { $o += '適用性未定（UNKNOWN）' }
    if ([string]$q.mode -eq 'UNSUPPORTED') { $o += '（UNSUPPORTED）'; return , $o }
    $st = [string]$E.State
    if ($st -eq 'WAITING_KNOWLEDGE' -or $st -eq 'WAITING_AUDIT' -or $st -eq 'BLOCKED_KNOWLEDGE' -or $st -eq 'ROUTING_REQUIRED') { $o += ('（' + $st + '）') }
    if ([string]$q.mode -eq 'EXTRACT') {
        if ($E.Facts.Count -eq 0) { if ($o.Count -eq 1) { $o += '（PENDING）' }; return , $o }
        foreach ($f in $E.Facts) {
            $v = $f.value
            switch ([string]$q.factKind) {
                'UI.COMPONENT_IDENTITY' { $o += ConvertTo-PsSpTable -Header @('項目', '值') -Rows @(@('物件', [string]$v.primaryObject), @('功能', [string]$v.functionName), @('類型', [string]$v.type), @('Origin', [string]$v.origin), @('狀態', [string]$v.status)) }
                'UI.NAVIGATION' {
                    if ($v.unconfirmed) { $o += 'Portal Registry 導覽入口：未確認' }
                    if (@($v.entries).Count -gt 0) { $o += ConvertTo-PsSpTable -Header @('#', '入口') -Rows @($v.entries | ForEach-Object { , @([string]$_.line, (@($_.cells) -join ' / ')) }) }
                    if (@($v.technicalMenu).Count -gt 0) { $o += ''; $o += ('Technical Menu：' + (@($v.technicalMenu) -join '；')) }
                }
                'UI.FIELD_INVENTORY' {
                    if ($v.notApplicable) { $o += '（無畫面欄位）' }
                    else { $o += ConvertTo-PsSpTable -Header @('欄位', '顯示文字', '類型', '選項', '生命狀態') -Rows @($v.fields | ForEach-Object { $c = @($_.cells); while ($c.Count -lt 5) { $c += '' }; , @($c[0], $c[1], $c[2], $c[3], $c[4]) }) }
                }
                'BEHAVIOR.RULES' { foreach ($rl in @($v.rules)) { $o += ('- ' + (ConvertTo-PsSpCell ([string]$rl.text))) } }
                'DATA.FLOW' { $o += ConvertTo-PsSpTable -Header @('表', '操作', '來源', '信心') -Rows @($v.tables | ForEach-Object { , @([string]$_.table, [string]$_.op, [string]$_.source, [string]$_.confidence) }) }
                'PROCESS.EXECUTION' {
                    foreach ($t in @($v.text)) { $o += [string]$t }
                    foreach ($c in @($v.callees)) { $o += ''; $o += ('呼叫 ' + [string]$c.object + '（' + [string]$c.type + '，' + [string]$c.role + '）：'); foreach ($t in @($c.text)) { $o += [string]$t } }
                }
                'SECURITY.ACCESS' { foreach ($t in @($v.text)) { $o += [string]$t } }
                'RELATED.OBJECTS' { $o += ConvertTo-PsSpTable -Header @('物件', '角色', '類型', '分類') -Rows @($v.objects | ForEach-Object { , @([string]$_.name, [string]$_.role, [string]$_.type, [string]$_.classification) }) }
                'GAPS' { foreach ($it in @($v.items)) { $o += ('- ' + (ConvertTo-PsSpCell ([string]$it.text))) } }
                'EVIDENCE.APPENDIX' { $o += ConvertTo-PsSpTable -Header @('#', '位置', '種類', '機器參照') -Rows @($v.rows | ForEach-Object { , @([string]$_.n, [string]$_.location, [string]$_.kind, [string]$_.ref) }) }
                'ENTITY.DETAIL' { $o += ('- ' + [string]$v.record + '：wiki ' + [string]$v.wiki + '（' + [string]$v.type + '，' + [string]$v.effective + '；Observations ' + [string]$v.observations + '）'); foreach ($rl in @($v.relations)) { $o += ('  - ' + [string]$rl) } }
                default { $o += ('（' + [string]$q.factKind + '）') }
            }
            $o += ''
        }
        return , $o
    }
    $cap = Get-PsSpFactKind -Capabilities $Capabilities -FactKind ([string]$q.factKind)
    $hdr = @($cap.table | ForEach-Object { [string]$_ })
    $rows = @()
    $any = $false
    foreach ($s in @($E.Units)) {
        if ($null -eq $s.Receipt) { continue }
        $any = $true
        foreach ($rw in @($s.Receipt.rows)) { $rows += , @($rw.cells) }
    }
    if (-not $any) { if ($o.Count -eq 1) { $o += '（PENDING）' }; return , $o }
    if ($rows.Count -gt 0) { $o += ConvertTo-PsSpTable -Header $hdr -Rows $rows } else { $o += '（無）' }
    $o += ''
    $o += ('覆蓋：' + $E.Closure)
    return , $o
}

function ConvertTo-PsSpSpec {
    param($PackV, $Evals, $Capabilities)
    $bySlot = @{}
    foreach ($e in $Evals) {
        $slot = [string]$e.Req.slot
        if (-not $bySlot.ContainsKey($slot)) { $bySlot[$slot] = @() }
        $bySlot[$slot] += (ConvertTo-PsSpBlock -E $e -Capabilities $Capabilities)
        $bySlot[$slot] += ''
    }
    $text = $PackV.Template -replace "`r", ''
    foreach ($s in @($PackV.Pack.slots | ForEach-Object { [string]$_ })) {
        $content = ''
        if ($bySlot.ContainsKey($s)) { $content = (($bySlot[$s] -join "`n").TrimEnd()) }
        $text = $text.Replace('{{slot:' + $s + '}}', $content)
    }
    if (-not $text.EndsWith("`n")) { $text += "`n" }
    return $text
}

function ConvertTo-PsSpTrace {
    param($Plan, $PackV, $Evals, [string]$Generation)
    $o = @('# Spec trace（機械產生）', '', ('generation：' + $Generation.Substring(0, 16) + '　plan：' + (Get-PsSpPlanRef -Plan $Plan) + '　pack：' + $PackV.PackId + ' v' + $PackV.PackVersion + '（reviewed ' + $PackV.ReviewedVersion + '）　content：' + $PackV.ContentHash.Substring(0, 16) + '　binding：' + $PackV.BindingHash.Substring(0, 16)), ('component：' + [string]$Plan.component + '　domain：' + [string]$Plan.domain), '')
    foreach ($e in $Evals) {
        $q = $e.Req
        $o += ('## ' + [string]$q.id + ' ' + [string]$q.factKind + '（' + [string]$q.mode + '）')
        $o += ''
        $o += ('- slot：' + [string]$q.slot + '　checklist：' + (@($q.checklistRefs) -join '、') + '　required：' + [string]$q.required + '　cardinality：' + [string]$q.cardinality + '　policy：' + [string]$q.evidencePolicy)
        $o += ('- applicable：' + $e.Applicable + '　state：' + $e.State + '　closure：' + $e.Closure + '　rows：' + $e.Rows)
        foreach ($f in @($e.Facts)) {
            $o += ('- fact ' + [string]$f.factId + '（grade ' + [string]$f.grade + '）')
            foreach ($sr in @($f.sourceRefs)) { $h = [string]$sr.sectionHash; if ($h -eq '') { $h = [string]$sr.hash }; $o += ('  - 來源 ' + [string]$sr.path + ' ' + [string]$sr.section + ' L' + [string]$sr.lines + ' ' + $h.Substring(0, [Math]::Min(16, $h.Length)) + '（' + [string]$sr.role + '）') }
            foreach ($ev in @($f.evidenceRefs)) { $o += ('  - 證據 ' + [string]$ev.file + '#' + [string]$ev.row + ' resolved=' + [string]$ev.resolved) }
        }
        foreach ($s in @($e.Units)) {
            $line = ('- unit ' + [string]$s.Eu.Unit.unitId + ' part ' + [string]$s.Eu.Part + ' state ' + [string]$s.State + ' fp ' + ([string]$s.Fingerprint).Substring(0, 16))
            if ($null -ne $s.Receipt) { $line += ('　receipt ' + [string]$s.Receipt.attemptId + ' fragment ' + ([string]$s.Receipt.fragmentHash).Substring(0, 16) + ' closure ' + [string]$s.Receipt.closure) }
            $o += $line
            foreach ($f in @($s.Eu.Unit.readSet)) { $o += ('  - 讀取 ' + [string]$f.path + '（' + [string]$f.role + '，' + [string]$f.grade + '）：' + (@($f.sections | ForEach-Object { [string]$_.name + ' L' + $_.start + '-' + $_.end }) -join '；')) }
            if ($null -ne $s.Receipt) { foreach ($rj in @($s.Receipt.rejected)) { $o += ('  - 未採用 條目 ' + [string]$rj.n + '：' + [string]$rj.reason) } }
        }
        foreach ($nd in @($q.needs)) { $o += ('- need ' + [string]$nd.factKind + ' ' + [string]$nd.target.type + ':' + [string]$nd.target.name + ' reason ' + [string]$nd.reason + ' state ' + [string]$nd.state + ' request ' + [string]$nd.requestId) }
        foreach ($f in @($e.Findings)) { $o += ('- finding ' + [string]$f.code + ' a=' + [string]$f.a + ' c=' + [string]$f.c) }
        $o += ''
    }
    return (($o -join "`n") + "`n")
}

# -Render／-Gate：來源重驗 → 評估 → 產出（byte 相同即 parity）。回 @{ Code; Exit; Generation; Verdict; Mismatch; OutDir }
function Invoke-PsSpRender {
    param([string]$Root, $Dirs, $Plan, $PackV, $Capabilities, $Index, [bool]$GateOnly = $false)
    $r = @{ Code = ''; Exit = 0; Generation = ''; Verdict = ''; Mismatch = 0; OutDir = ''; Findings = 0 }
    $chk = Test-PsSpSources -Root $Root -Dirs $Dirs -Plan $Plan -Index $Index
    $r.Mismatch = $chk.Mismatch
    if ($chk.Mismatch -gt 0) { $r.Code = 'SPEC1-6-02-' + $chk.Mismatch; $r.Exit = 1; return $r }
    $evals = Get-PsSpEvaluation -Plan $Plan -PackV $PackV -Status $chk.Status -Capabilities $Capabilities
    $genParts = @([string]$Plan.planHash, $PackV.BindingHash, $PackV.ContentHash)
    foreach ($s in $chk.Status) { if ($null -ne $s.Receipt) { $genParts += ([string]$s.Receipt.inputFingerprint + ':' + [string]$s.Receipt.fragmentHash) } else { $genParts += ([string]$s.Fingerprint + ':' + [string]$s.State) } }
    $gen = Get-PsKnTextHash -Text (($genParts -join "`n") + "`n")
    $r.Generation = $gen
    $gate = Get-PsSpGate -Plan $Plan -PackV $PackV -Evals $evals -Generation $gen
    $r.Verdict = [string]$gate.verdict
    $r.Findings = [int]$gate.findingCount
    $outDir = Join-Path $Dirs.Outputs ($gen.Substring(0, 16).ToLowerInvariant())
    $r.OutDir = $outDir
    $gateText = (ConvertTo-PsKnJson -Value $gate) + "`n"
    if (-not (Write-PsKnAtomicText -LiteralPath (Join-Path $outDir 'gate.json') -Text $gateText -Bom $false)) { $r.Code = 'SPEC1-6-07'; $r.Exit = 1; return $r }
    if (-not $GateOnly) {
        $spec = ConvertTo-PsSpSpec -PackV $PackV -Evals $evals -Capabilities $Capabilities
        $trace = ConvertTo-PsSpTrace -Plan $Plan -PackV $PackV -Evals $evals -Generation $gen
        $ok1 = Write-PsKnAtomicText -LiteralPath (Join-Path $outDir 'spec.md') -Text $spec -Bom $false
        $ok2 = Write-PsKnAtomicText -LiteralPath (Join-Path $outDir 'trace.md') -Text $trace -Bom $false
        if (-not ($ok1 -and $ok2)) { $r.Code = 'SPEC1-6-07'; $r.Exit = 1; return $r }
        $cur = [ordered]@{ schemaVersion = $script:PsSpecSchemaVersion; generation = $gen; planRef = (Get-PsSpPlanRef -Plan $Plan); packVersion = $PackV.PackVersion; contentHash = $PackV.ContentHash; bindingHash = $PackV.BindingHash; verdict = [string]$gate.verdict; specHash = (Get-PsKnTextHash -Text $spec); traceHash = (Get-PsKnTextHash -Text $trace); gateHash = (Get-PsKnTextHash -Text $gateText) }
        if (-not (Write-PsKnAtomicText -LiteralPath $Dirs.CurrentFile -Text ((ConvertTo-PsKnJson -Value $cur) + "`n") -Bom $false)) { $r.Code = 'SPEC1-6-07'; $r.Exit = 1; return $r }
        $r.Code = 'SPEC1-6-01'; $r.Exit = 0
        return $r
    }
    $v = [string]$gate.verdict
    if ($v -eq 'BLOCKED') { $r.Code = 'SPEC1-7-03-' + $gate.findingCount; $r.Exit = 1 }
    elseif ($v -eq 'SPEC_PARTIAL') { $r.Code = 'SPEC1-7-02-' + $gate.findingCount; $r.Exit = 1 }
    elseif (-not $PackV.Signed) { $r.Code = 'SPEC1-8-01'; $r.Exit = 1 }
    else { $r.Code = 'SPEC1-7-01'; $r.Exit = 0 }
    return $r
}

# ── Doctor：stage 0 完整性、drill tuple ───────────────────────────

# generic 集合（相對 Root）：scripts/ps-spec*.ps1、.opencode/peoplesoft/spec/**（manifest 自身除外）、worker agent／command
function Get-PsSpGenericFiles {
    param([string]$Root)
    $out = @()
    $sd = Join-Path $Root 'scripts'
    if ([System.IO.Directory]::Exists($sd)) { foreach ($f in @(Get-ChildItem -LiteralPath $sd -File -Filter 'ps-spec*.ps1' -ErrorAction SilentlyContinue)) { $out += ('scripts/' + $f.Name) } }
    $gd = Join-Path $Root (Join-Path '.opencode' (Join-Path 'peoplesoft' 'spec'))
    if ([System.IO.Directory]::Exists($gd)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $gd -File -Recurse -ErrorAction SilentlyContinue)) {
            if ($f.Name -eq 'generic.manifest.json') { continue }
            if ($f.Name -match '\.(tmp|bak)-[0-9a-f]{32}$') { continue }
            $out += (Get-PsSpRelPath -Root $Root -Path $f.FullName)
        }
    }
    foreach ($p in @('.opencode/agent/ps-spec-worker.md', '.opencode/command/ps-spec-batch.md')) { if ([System.IO.File]::Exists((Join-Path $Root $p))) { $out += $p } }
    return , (Sort-PsKnOrdinal -Items $out)
}
function New-PsSpGenericManifest {
    param([string]$Root)
    $files = @()
    foreach ($rel in (Get-PsSpGenericFiles -Root $Root)) {
        $p = Join-Path $Root $rel
        $t = Read-PsKnText -LiteralPath $p
        $files += , ([ordered]@{ path = $rel; sha256 = (Get-PsKnTextHash -Text $t); lines = (Get-PsKnLines -Text $t).Count })
    }
    $m = [ordered]@{ schemaVersion = $script:PsSpecSchemaVersion; note = 'Spec generic 集合的正規化 hash（剝 BOM／CR）；ps-spec -Doctor stage 0 比對；重生：ps-spec -Doctor -WriteGenericManifest'; files = @($files) }
    $mp = (Get-PsSpDirs -Root $Root).GenericManifest
    $ok = Write-PsKnAtomicText -LiteralPath $mp -Text ((ConvertTo-PsKnJson -Value $m) + "`n") -Bom $false
    return @{ Ok = $ok; Count = $files.Count; Path = $mp }
}
# 回 @{ Ok; Missing; Modified; Extra; Count; Diff=@(路徑) ; ManifestMissing }
function Test-PsSpGenericManifest {
    param([string]$Root)
    $r = @{ Ok = $false; Missing = 0; Modified = 0; Extra = 0; Count = 0; Diff = @(); ManifestMissing = $false }
    $m = Read-PsSpJsonFile -LiteralPath (Get-PsSpDirs -Root $Root).GenericManifest
    if ($null -eq $m) { $r.ManifestMissing = $true; return $r }
    $want = @{}
    foreach ($f in @($m.files)) { $want[[string]$f.path] = [string]$f.sha256 }
    $have = @{}
    foreach ($rel in (Get-PsSpGenericFiles -Root $Root)) { $have[$rel] = Get-PsKnFileHash -LiteralPath (Join-Path $Root $rel) }
    foreach ($k in (Sort-PsKnOrdinal -Items @($want.Keys))) {
        if (-not $have.ContainsKey($k)) { $r.Missing++; $r.Diff += ('MISSING ' + $k) }
        elseif ($have[$k] -cne $want[$k]) { $r.Modified++; $r.Diff += ('MODIFIED ' + $k) }
    }
    foreach ($k in (Sort-PsKnOrdinal -Items @($have.Keys))) { if (-not $want.ContainsKey($k)) { $r.Extra++; $r.Diff += ('EXTRA ' + $k) } }
    $r.Count = $r.Missing + $r.Modified + $r.Extra
    $r.Ok = ($r.Count -eq 0)
    return $r
}

# drill tuple：D<stage>-<code> <opaque id> <factKind> <mode> k=v…（只有 opaque ID、factKind、模式、計數、封閉值）
function Get-PsSpDrill {
    param([string]$Root, $Dirs, $Plan, $Index, [string]$Code, $Gate = $null)
    $lines = @()
    $m = [regex]::Match($Code, '^(\d)-(\d\d)$')
    if (-not $m.Success) { return , $lines }
    $stage = $m.Groups[1].Value; $c = $m.Groups[2].Value
    $want = $stage + '-' + $c
    $tup = { param([string]$Id, [string]$Fk, [string]$Mode, [string]$Kv) return ('D' + $want + ' ' + $Id + ' ' + $Fk + ' ' + $Mode + ' ' + $Kv).TrimEnd() }
    switch ($stage) {
        '0' { $t = Test-PsSpGenericManifest -Root $Root; $i = 0; foreach ($d in $t.Diff) { $i++; $lines += (& $tup ('F' + $i) 'GENERIC' 'FILE' ('c=' + ($d -split ' ')[0])) } }
        '2' { if ($null -ne $Plan) { foreach ($f in @($Plan.findings)) { if ([string]$f.code -eq $want) { $lines += (& $tup ([string]$f.requirementId) ([string]$f.factKind) ([string]$f.mode) 'a=0') } } } }
        '3' { foreach ($v in (Get-PsSpVerdicts -Dirs $Dirs)) { if ([string]$v.code -eq $want) { $lines += (& $tup ([string]$v.requirementId) ([string]$v.factKind) 'COMPOSE' ([string]$v.attemptId + ' h=' + [string]$v.sessionHealthy)) } } }
        '4' { foreach ($v in (Get-PsSpVerdicts -Dirs $Dirs)) { if ([string]$v.code -eq $want) { $rs = (@($v.reasons) -join ','); if ($rs -eq '') { $rs = 'NONE' }; $lines += (& $tup ([string]$v.requirementId) ([string]$v.factKind) 'COMPOSE' ([string]$v.attemptId + ' n=' + [string]$v.lines + ' c=' + [string]$v.closure + ' r=' + $rs)) } }
            if ($c -eq '03' -and $null -ne $Plan) { foreach ($s in (Get-PsSpUnitStatus -Root $Root -Dirs $Dirs -Plan $Plan -Index $Index)) { if ([string]$s.State -eq 'BLOCKED') { $lines += (& $tup ([string]$s.Eu.Unit.requirementId) ([string]$s.Eu.Unit.factKind) 'COMPOSE' ('a=' + $s.Attempts + ' c=BLOCKED')) } } } }
        '5' {
            if ($null -ne $Plan) {
                $map = @{ '01' = 'WAITING_KNOWLEDGE'; '04' = 'WAITING_AUDIT'; '05' = 'BLOCKED_KNOWLEDGE'; '07' = 'ROUTING_REQUIRED'; '08' = 'INVALID' }
                if ($map.ContainsKey($c)) { foreach ($q in @($Plan.requirements)) { foreach ($nd in @($q.needs)) { if ([string]$nd.state -eq $map[$c]) { $lines += (& $tup ([string]$q.id) ([string]$nd.factKind) ([string]$q.mode) ('t=' + [string]$nd.target.type + ' r=' + [string]$nd.reason + ' g=' + [string]$nd.grade)) } } } }
            }
        }
        '6' { if ($null -ne $Plan) { $chk = Test-PsSpSources -Root $Root -Dirs $Dirs -Plan $Plan -Index $Index; foreach ($k in (Sort-PsKnOrdinal -Items @($chk.Facts.Keys))) { if (-not $chk.Facts[$k]) { $fk = ($k -split '@')[0]; $lines += (& $tup 'FACT' $fk 'EXTRACT' 'c=SOURCE_CHANGED') } }; foreach ($s in $chk.Status) { if ([string]$s.State -eq 'SOURCE_CHANGED') { $lines += (& $tup ([string]$s.Eu.Unit.requirementId) ([string]$s.Eu.Unit.factKind) 'COMPOSE' 'c=SOURCE_CHANGED') } } } }
        '7' { if ($null -ne $Gate) { foreach ($f in @($Gate.findings)) { if ([string]$f.code -eq $want) { $lines += (& $tup ([string]$f.requirementId) ([string]$f.factKind) ([string]$f.mode) ('a=' + [string]$f.a + ' c=' + [string]$f.c)) } } } }
        '8' { if ($null -ne $Gate) { foreach ($f in @($Gate.findings)) { if ([string]$f.code -eq $want) { $lines += (& $tup 'PACK' 'MAPPING' 'ANY' ('a=' + [string]$f.a + ' c=' + [string]$f.c)) } } } }
        default { }
    }
    return , $lines
}
