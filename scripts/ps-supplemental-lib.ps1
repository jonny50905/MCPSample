# ps-supplemental-lib.ps1 — 補研究協定（Supplemental Research）共用邏輯
# 由 ps-supplemental.ps1（CLI）、ps-auto-loop.ps1（-SupplementalOnly 迷你圈）、ps-spec-lib.ps1（規劃器消費端）dot-source。
# 前置：先 dot-source scripts/ps-knowledge-lib.ps1（讀檔／hash／canonical JSON／原子寫入／NN 解析都借它的）。
# 責任：
#   request（docs/ps-research/supplemental/requests/<requestId>.json，create-only、進內部 git）：
#     requestId＝workKey（need 的 canonical JSON SHA256）決定——同 need 的並行 Submit 落到同一檔名，Move 輸家讀贏家。
#   result（docs/ps-research/supplemental/results/<requestId>.json，create-only）：只由 Research 迷你圈末端寫。
#   manifest／收據／outcome（docs/ps-research/<領域>/supplemental-parts/，gitignore）：模型只寫收據；
#     合併由本檔確定性完成（只追加、不改寫既有句子）。
# 純函式庫：dot-source 無副作用、不呼叫模型、不查 DB。PowerShell 5.1 紀律同 ps-knowledge-lib.ps1。

$script:PsSupplementalLibVersion = 1
$script:PsSuppSchemaVersion = 1
$script:PsSuppConsumerKinds = @('SPEC', 'QA', 'MANUAL')
$script:PsSuppOutcomes = @('RESOLVED', 'PARTIAL', 'UNRESOLVED', 'OUT_OF_SCOPE', 'SUPERSEDED')
$script:PsSuppDispositions = @('RESEARCHED', 'ALREADY_COVERED', 'NO_EVIDENCE', 'WORKER_FAILED', 'CRASH', 'NOT_IN_DOMAIN', 'UNSUPPORTED', 'SUPERSEDED')
$script:PsSuppReceiptDispositions = @('RESEARCHED', 'ALREADY_COVERED', 'NO_EVIDENCE', 'NOT_IN_DOMAIN', 'UNSUPPORTED')
$script:PsSuppRequestIdRx = '^S-[0-9a-f]{24}-g\d+$'
$script:PsSuppIdRx = '^[a-z0-9][a-z0-9-]{0,31}$'
$script:PsSuppReqRefRx = '^[A-Z][A-Z0-9_]{0,15}$'
$script:PsSuppLeakMarkers = @('"agent"', '"findings"', '"searchScope"', '"coverage"', '"dynamicRuntimeWarnings"', '"structureLines"')
$script:PsSuppForbiddenWords = @('requirementRef', 'jobId', 'packId', 'consumer', '{{slot:')
$script:PsSuppTableSections = @{
    '畫面與欄位' = @{ Header = '| 欄位 | 顯示文字 | 類型 | 選項（label ↔ 儲存值） | 生命狀態 |'; Sep = '|---|---|---|---|---|'; Cells = 5; RefCell = 4 }
    '資料流'     = @{ Header = '| 表 | 操作 | 來源 | 信心 |'; Sep = '|---|---|---|---|'; Cells = 3; RefCell = 2 }
    '相關物件'   = @{ Header = '| 物件 | 角色 |'; Sep = '|---|---|'; Cells = 2; RefCell = 1 }
}
$script:PsSuppBulletSections = @('行為邏輯', '未解事項')
$script:PsSuppTextSections = @('執行方式', '權限', '功能定位')

# ── 目錄與目錄檔 ─────────────────────────────────────────────────

function Get-PsSuppDirs {
    param([string]$Root)
    $research = Join-Path $Root (Join-Path 'docs' 'ps-research')
    $supp = Join-Path $research 'supplemental'
    return @{
        Research     = $research
        Supplemental = $supp
        Requests     = (Join-Path $supp 'requests')
        Results      = (Join-Path $supp 'results')
        Capabilities = (Join-Path $Root (Join-Path '.opencode' (Join-Path 'peoplesoft' (Join-Path 'spec' 'capabilities.json'))))
    }
}

function Get-PsSuppCapabilities {
    param([string]$Root)
    $p = (Get-PsSuppDirs -Root $Root).Capabilities
    $t = Read-PsKnText -LiteralPath $p
    if ($null -eq $t) { throw "找不到能力目錄 $p（人工搬運不完整？）" }
    return ($t | ConvertFrom-Json -ErrorAction Stop)
}

function Get-PsSuppFactKind {
    param($Capabilities, [string]$FactKind)
    if ($null -eq $Capabilities -or $null -eq $Capabilities.factKinds) { return $null }
    $prop = $Capabilities.factKinds.PSObject.Properties[$FactKind]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

# ── need 解析／驗證／正規化 ──────────────────────────────────────

# CLI 參數 → need（未正規化）。Target 'COMPONENT:TW_X'；Properties 'a,b'；Context 'operation=IMPORT;mode=ANY'
function ConvertTo-PsSuppNeed {
    param([string]$Target, [string]$FactKind, [string]$Properties = '', [string]$Context = '', [string]$EvidencePolicy = 'STATIC', [string]$Freshness = 'CURRENT')
    $tt = ''; $tn = ''
    $ix = $Target.IndexOf(':')
    if ($ix -gt 0) { $tt = $Target.Substring(0, $ix).Trim(); $tn = $Target.Substring($ix + 1).Trim() } else { $tn = $Target.Trim() }
    $props = @()
    foreach ($p in ($Properties -split '[,;]')) { $x = $p.Trim(); if ($x -ne '') { $props += $x } }
    $ctx = [ordered]@{}
    foreach ($kv in ($Context -split ';')) {
        $s = $kv.Trim()
        if ($s -eq '') { continue }
        $eq = $s.IndexOf('=')
        if ($eq -le 0) { $ctx[$s] = ''; continue }
        $ctx[$s.Substring(0, $eq).Trim()] = $s.Substring($eq + 1).Trim()
    }
    return [ordered]@{
        target         = [ordered]@{ type = $tt; name = $tn }
        context        = $ctx
        factKind       = $FactKind.Trim()
        properties     = $props
        evidencePolicy = $EvidencePolicy.Trim()
        freshness      = $Freshness.Trim()
    }
}

# 從 JSON 讀回的 need（PSCustomObject）→ hashtable 形（給 Test-PsSuppNeed 重驗）
function ConvertFrom-PsSuppNeedObject {
    param($Obj)
    $n = [ordered]@{ target = [ordered]@{ type = ''; name = '' }; context = [ordered]@{}; factKind = ''; properties = @(); evidencePolicy = ''; freshness = '' }
    if ($null -eq $Obj) { return $n }
    if ($null -ne $Obj.target) { $n.target.type = [string]$Obj.target.type; $n.target.name = [string]$Obj.target.name }
    if ($null -ne $Obj.context) { foreach ($p in $Obj.context.PSObject.Properties) { $n.context[$p.Name] = [string]$p.Value } }
    $n.factKind = [string]$Obj.factKind
    if ($null -ne $Obj.properties) { $n.properties = @($Obj.properties | ForEach-Object { [string]$_ }) }
    $n.evidencePolicy = [string]$Obj.evidencePolicy
    $n.freshness = [string]$Obj.freshness
    return $n
}

# 驗證＋正規化（未知欄位拒收；名稱大寫；properties 去重 Ordinal 排序；context 鍵排序）。回 @{ Ok; Errors; Need }
function Test-PsSuppNeed {
    param($Need, $Capabilities)
    $errors = @()
    $allowedKeys = @('target', 'context', 'factKind', 'properties', 'evidencePolicy', 'freshness')
    foreach ($k in @($Need.Keys)) { if ($allowedKeys -notcontains [string]$k) { $errors += ('need 含未知欄位：' + $k) } }
    $tt = ''; $tn = ''
    if ($null -ne $Need.target) { $tt = ([string]$Need.target.type).Trim().ToUpperInvariant(); $tn = ([string]$Need.target.name).Trim().ToUpperInvariant() }
    if (@($Capabilities.targetTypes) -notcontains $tt) { $errors += ('target.type 不在值域：' + $tt) }
    $namePat = [string]$Capabilities.objectNamePattern
    if ($namePat -eq '') { $namePat = '^[A-Z0-9_][A-Z0-9_.$#-]{0,59}$' }
    if ($tn -notmatch $namePat) { $errors += ('target.name 不符物件名文法：' + $tn) }
    $fk = ([string]$Need.factKind).Trim()
    $cap = Get-PsSuppFactKind -Capabilities $Capabilities -FactKind $fk
    if ($null -eq $cap) { $errors += ('factKind 不在能力目錄：' + $fk) }
    $props = @()
    foreach ($p in @($Need.properties)) { $x = ([string]$p).Trim(); if ($x -ne '' -and $props -notcontains $x) { $props += $x } }
    if ($props.Count -eq 0) { $errors += 'properties 不得為空' }
    if ($null -ne $cap) { foreach ($p in $props) { if (@($cap.properties) -notcontains $p) { $errors += ('property 不在該 factKind 目錄：' + $p) } } }
    $props = Sort-PsKnOrdinal -Items $props
    $ctx = [ordered]@{}
    $ctxKeys = @()
    if ($null -ne $Need.context) { foreach ($k in @($Need.context.Keys)) { $ctxKeys += [string]$k } }
    foreach ($k in (Sort-PsKnOrdinal -Items $ctxKeys)) {
        $v = ([string]$Need.context[$k]).Trim()
        $spec = $null
        if ($null -ne $Capabilities.contextKeys) { $sp = $Capabilities.contextKeys.PSObject.Properties[$k]; if ($null -ne $sp) { $spec = $sp.Value } }
        if ($null -eq $spec) { $errors += ('context 鍵不在目錄：' + $k); continue }
        if ($spec -is [string]) {
            $v = $v.ToUpperInvariant()
            if ($v -notmatch $namePat) { $errors += ('context.' + $k + ' 不符物件名文法：' + $v) }
        }
        else {
            $v = $v.ToUpperInvariant()
            if (@($spec) -notcontains $v) { $errors += ('context.' + $k + ' 不在值域：' + $v) }
        }
        $ctx[$k] = $v
    }
    $ep = ([string]$Need.evidencePolicy).Trim().ToUpperInvariant()
    if (@($Capabilities.evidencePolicies) -notcontains $ep) { $errors += ('evidencePolicy 不在值域：' + $ep) }
    $fr = ([string]$Need.freshness).Trim().ToUpperInvariant()
    if (@($Capabilities.freshness) -notcontains $fr) { $errors += ('freshness 不在值域：' + $fr) }
    $norm = [ordered]@{
        target = [ordered]@{ type = $tt; name = $tn }; context = $ctx; factKind = $fk
        properties = @($props); evidencePolicy = $ep; freshness = $fr
    }
    return @{ Ok = ($errors.Count -eq 0); Errors = $errors; Need = $norm }
}

function Test-PsSuppConsumer {
    param($Consumer)
    $errors = @()
    $kind = ''; $jobId = ''; $ref = ''
    if ($null -ne $Consumer) {
        foreach ($k in @($Consumer.Keys)) { if (@('kind', 'jobId', 'requirementRef') -notcontains [string]$k) { $errors += ('consumer 含未知欄位：' + $k) } }
        $kind = ([string]$Consumer['kind']).Trim().ToUpperInvariant()
        $jobId = ([string]$Consumer['jobId']).Trim()
        $ref = ([string]$Consumer['requirementRef']).Trim()
    }
    if ($kind -eq '') { $kind = 'MANUAL' }
    if ($script:PsSuppConsumerKinds -notcontains $kind) { $errors += ('consumer.kind 不在值域：' + $kind) }
    if ($jobId -ne '' -and $jobId -notmatch $script:PsSuppIdRx) { $errors += ('consumer.jobId 不符文法（小寫英數與連字號，≤32）：' + $jobId) }
    if ($ref -ne '' -and $ref -notmatch $script:PsSuppReqRefRx) { $errors += ('consumer.requirementRef 不符文法：' + $ref) }
    if ($kind -eq 'SPEC' -and ($jobId -eq '' -or $ref -eq '')) { $errors += 'consumer.kind=SPEC 必須有 jobId 與 requirementRef' }
    return @{ Ok = ($errors.Count -eq 0); Errors = $errors; Consumer = [ordered]@{ kind = $kind; jobId = $jobId; requirementRef = $ref } }
}

function Get-PsSuppWorkKey {
    param($Need)
    $json = ConvertTo-PsKnJson -Value $Need -SortKeys
    return (Get-PsKnTextHash -Text $json)
}

function Get-PsSuppRequestId {
    param([string]$WorkKey, [int]$Generation)
    return ('S-' + $WorkKey.Substring(0, 24).ToLowerInvariant() + '-g' + $Generation)
}

# ── request／result 檔 ──────────────────────────────────────────

function Read-PsSuppJsonFile {
    param([string]$LiteralPath)
    $t = Read-PsKnText -LiteralPath $LiteralPath
    if ($null -eq $t) { return $null }
    try { return ($t | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

# 全部 request：@( @{ Path; RequestId; WorkKey; Generation; Domain; Obj } )，依 requestId Ordinal 排序。
# Research 端 intake 驗證（每次讀取都做）：檔名＝body requestId＝文法；schemaVersion；domain 是單一目錄名且非保留名；
# need 依能力目錄重驗；workKey 重算相符且與 requestId 前 24 hex 一致；generation ≥1。不符者不進清單，
# 記在 $script:PsSuppIntakeRejected（檔名：原因）供外環 log。-Capabilities 未給時自 Root 讀能力目錄；讀不到就略過 need 驗證。
function Get-PsSuppRequests {
    param([string]$Root, $Capabilities = $null)
    $d = Get-PsSuppDirs -Root $Root
    $list = @()
    $script:PsSuppIntakeRejected = @()
    if (-not [System.IO.Directory]::Exists($d.Requests)) { return , $list }
    if ($null -eq $Capabilities) { try { $Capabilities = Get-PsSuppCapabilities -Root $Root } catch { $Capabilities = $null } }
    $files = @(Get-ChildItem -LiteralPath $d.Requests -File -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^S-[0-9a-f]{24}-g\d+\.json$' })
    $names = @($files | ForEach-Object { $_.Name })
    foreach ($n in (Sort-PsKnOrdinal -Items $names)) {
        $p = Join-Path $d.Requests $n
        $o = Read-PsSuppJsonFile -LiteralPath $p
        if ($null -eq $o) { $script:PsSuppIntakeRejected += ($n + '：NOT_JSON'); continue }
        $base = $n.Substring(0, $n.Length - 5)
        $rid = [string]$o.requestId
        $dom = [string]$o.domain
        $why = ''
        $gen = 0
        if ($rid -notmatch $script:PsSuppRequestIdRx -or $rid -cne $base) { $why = 'ID_MISMATCH' }
        elseif ([string]$o.schemaVersion -ne '1') { $why = 'SCHEMA' }
        elseif ($dom -eq '' -or $dom -match '[\\/]' -or $dom.Contains('..') -or ($script:PsKnReservedNames -contains $dom)) { $why = 'DOMAIN' }
        elseif (-not [int]::TryParse([string]$o.generation, [ref]$gen) -or $gen -lt 1) { $why = 'GENERATION' }
        elseif ($null -ne $Capabilities) {
            $vn = Test-PsSuppNeed -Need (ConvertFrom-PsSuppNeedObject -Obj $o.need) -Capabilities $Capabilities
            if (-not $vn.Ok) { $why = 'NEED' }
            else {
                $wk = Get-PsSuppWorkKey -Need $vn.Need
                if ($wk -cne [string]$o.workKey -or $rid.Substring(2, 24) -cne $wk.Substring(0, 24).ToLowerInvariant()) { $why = 'WORKKEY' }
            }
        }
        if ($why -ne '') { $script:PsSuppIntakeRejected += ($n + '：' + $why); continue }
        $list += , (@{ Path = $p; RequestId = $rid; WorkKey = [string]$o.workKey; Generation = $gen; Domain = $dom; Obj = $o })
    }
    return , $list
}

function Get-PsSupplementalResult {
    param([string]$Root, [string]$RequestId)
    if ($RequestId -notmatch $script:PsSuppRequestIdRx) { return $null }
    $d = Get-PsSuppDirs -Root $Root
    return (Read-PsSuppJsonFile -LiteralPath (Join-Path $d.Results ($RequestId + '.json')))
}

function Get-PsSuppRequest {
    param([string]$Root, [string]$RequestId)
    if ($RequestId -notmatch $script:PsSuppRequestIdRx) { return $null }
    $d = Get-PsSuppDirs -Root $Root
    return (Read-PsSuppJsonFile -LiteralPath (Join-Path $d.Requests ($RequestId + '.json')))
}

# 目標物件在某領域目錄有無 NN 檔（lint 同款：^\d\d-<obj>(-\d+)?\.md$；大小寫不敏感）
function Find-PsSuppTargetNn {
    param([string]$DomainDir, [string]$TargetName)
    $hits = @()
    if (-not [System.IO.Directory]::Exists($DomainDir)) { return , $hits }
    $esc = [regex]::Escape($TargetName)
    foreach ($f in @(Get-ChildItem -LiteralPath $DomainDir -File -Filter '*.md' -ErrorAction SilentlyContinue)) {
        if ($f.Name -match ('^(?i)\d\d-' + $esc + '(-\d+)?\.md$') -and $f.Name -notmatch '^(00|90)-') { $hits += $f.Name }
    }
    return , (Sort-PsKnOrdinal -Items $hits)
}

# 路由：-DomainHint（須存在 00-overview.md）＞ 索引中以 target 為主物件的 NN 所在領域（唯一）＞ 多個候選＝Ordinal 最小
#       ＞ 零候選＝目錄掃描（索引缺時的退路）＞ 仍零＝NONE。回 @{ Domain; Reason; Candidates }
function Resolve-PsSuppDomain {
    param([string]$Root, [string]$TargetName, [string]$DomainHint = '')
    $d = Get-PsSuppDirs -Root $Root
    if ($DomainHint -ne '') {
        $ov = Join-Path (Join-Path $d.Research $DomainHint) '00-overview.md'
        if ([System.IO.File]::Exists($ov)) { return @{ Domain = $DomainHint; Reason = 'HINT'; Candidates = @($DomainHint) } }
        return @{ Domain = ''; Reason = 'BAD_HINT'; Candidates = @() }
    }
    $cands = @()
    $idx = Read-PsKnowledgeIndex -Root $Root
    if ($null -ne $idx) {
        foreach ($e in @($idx.nn)) {
            if ([string]::Equals([string]$e.primaryObject, $TargetName, [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($cands -notcontains [string]$e.domain) { $cands += [string]$e.domain }
            }
        }
    }
    $reason = 'INDEX'
    if ($cands.Count -eq 0) {
        $reason = 'SCAN'
        if ([System.IO.Directory]::Exists($d.Research)) {
            foreach ($dd in @(Get-ChildItem -LiteralPath $d.Research -Directory -ErrorAction SilentlyContinue)) {
                if ($script:PsKnReservedNames -contains $dd.Name) { continue }
                if (-not [System.IO.File]::Exists((Join-Path $dd.FullName '00-overview.md'))) { continue }
                if ((Find-PsSuppTargetNn -DomainDir $dd.FullName -TargetName $TargetName).Count -gt 0) { $cands += $dd.Name }
            }
        }
    }
    if ($cands.Count -eq 0) { return @{ Domain = ''; Reason = 'NONE'; Candidates = @() } }
    $sorted = Sort-PsKnOrdinal -Items $cands
    if ($sorted.Count -gt 1) { $reason = 'MULTI' }
    return @{ Domain = $sorted[0]; Reason = $reason; Candidates = @($sorted) }
}

function New-PsSuppRequestObject {
    param($Need, $Consumer, [string]$Domain, [string]$WorkKey, [int]$Generation, [datetime]$AsOf)
    return [ordered]@{
        schemaVersion = $script:PsSuppSchemaVersion
        requestId     = (Get-PsSuppRequestId -WorkKey $WorkKey -Generation $Generation)
        workKey       = $WorkKey
        generation    = $Generation
        createdAt     = (Get-PsKnUtcStamp -At $AsOf)
        consumer      = $Consumer
        domain        = $Domain
        need          = $Need
    }
}

# 提交：回 @{ requestId; state; domain; created; reason; errors; path }
#   state ∈ CREATED／PENDING／RESOLVED／PARTIAL／UNRESOLVED／OUT_OF_SCOPE／INVALID／ROUTING_REQUIRED
function Submit-PsSupplementalRequest {
    param([string]$Root, $Need, $Consumer = $null, [string]$DomainHint = '', [switch]$Resubmit, [datetime]$AsOf = [datetime]::UtcNow)
    $cap = Get-PsSuppCapabilities -Root $Root
    $vn = Test-PsSuppNeed -Need $Need -Capabilities $cap
    $vc = Test-PsSuppConsumer -Consumer $Consumer
    $errs = @($vn.Errors) + @($vc.Errors)
    if ($errs.Count -gt 0) { return @{ requestId = ''; state = 'INVALID'; domain = ''; created = $false; reason = 'VALIDATION'; errors = $errs; path = '' } }
    $need = $vn.Need
    $wk = Get-PsSuppWorkKey -Need $need
    $d = Get-PsSuppDirs -Root $Root
    # 既有世代
    $maxGen = 0
    $latest = $null
    foreach ($r in (Get-PsSuppRequests -Root $Root)) {
        if ($r.WorkKey -ceq $wk -and $r.Generation -gt $maxGen) { $maxGen = $r.Generation; $latest = $r }
    }
    if ($null -ne $latest) {
        $res = Get-PsSupplementalResult -Root $Root -RequestId $latest.RequestId
        if ($null -eq $res) {
            return @{ requestId = $latest.RequestId; state = 'PENDING'; domain = $latest.Domain; created = $false; reason = 'EXISTS'; errors = @(); path = $latest.Path }
        }
        if (-not $Resubmit) {
            return @{ requestId = $latest.RequestId; state = [string]$res.outcome; domain = $latest.Domain; created = $false; reason = 'TERMINAL'; errors = @(); path = $latest.Path }
        }
    }
    $gen = $maxGen + 1
    $route = Resolve-PsSuppDomain -Root $Root -TargetName $need.target.name -DomainHint $DomainHint
    if ($route.Domain -eq '') {
        $why = 'ROUTING'
        if ($route.Reason -eq 'BAD_HINT') { $why = 'BAD_HINT' }
        return @{ requestId = ''; state = 'ROUTING_REQUIRED'; domain = ''; created = $false; reason = $why; errors = @('目標物件在任何領域都沒有 NN 檔（或 -DomainHint 的領域沒有 00-overview.md）——加 -DomainHint <領域>'); path = '' }
    }
    $obj = New-PsSuppRequestObject -Need $need -Consumer $vc.Consumer -Domain $route.Domain -WorkKey $wk -Generation $gen -AsOf $AsOf
    $path = Join-Path $d.Requests ([string]$obj.requestId + '.json')
    $ok = Write-PsKnCreateOnlyText -LiteralPath $path -Text ((ConvertTo-PsKnJson -Value $obj) + "`n")
    if ($ok -eq $true) { return @{ requestId = [string]$obj.requestId; state = 'CREATED'; domain = $route.Domain; created = $true; reason = $route.Reason; errors = @(); path = $path } }
    # $false＝Move 輸家：讀贏家、回其身分；$null（或贏家檔讀不到）＝寫入延後，不能假裝有 request 在等
    $winner = $null
    if ($ok -eq $false) { $winner = Read-PsSuppJsonFile -LiteralPath $path }
    if ($null -eq $winner) {
        return @{ requestId = [string]$obj.requestId; state = 'WRITE_FAILED'; domain = $route.Domain; created = $false; reason = 'WRITE_DEFERRED'; errors = @('request 檔寫入失敗（目標被別的行程開著？）——稍後重新提交'); path = $path }
    }
    return @{ requestId = [string]$obj.requestId; state = 'PENDING'; domain = [string]$winner.domain; created = $false; reason = 'RACE_LOST'; errors = @(); path = $path }
}

# ── attempts（manifest 檔數＝attempts；outcome 缺＝crash 也算一次）───────

function Get-PsSuppPartsDir {
    param([string]$DomainDir)
    return (Join-Path $DomainDir 'supplemental-parts')
}

function Get-PsSuppAttempts {
    param([string]$DomainDir, [string]$RequestId)
    $parts = Get-PsSuppPartsDir -DomainDir $DomainDir
    $r = @{ Count = 0; Manifests = @(); Outcomes = @{}; LastN = 0; LastOutcome = $null }
    if (-not [System.IO.Directory]::Exists($parts)) { return $r }
    $esc = [regex]::Escape($RequestId)
    foreach ($f in @(Get-ChildItem -LiteralPath $parts -File -ErrorAction SilentlyContinue)) {
        $m = [regex]::Match($f.Name, ('^' + $esc + '\.a(\d+)\.manifest\.md$'))
        if ($m.Success) {
            $n = [int]$m.Groups[1].Value
            $r.Manifests += $f.Name
            if ($n -gt $r.LastN) { $r.LastN = $n }
            continue
        }
        $m = [regex]::Match($f.Name, ('^' + $esc + '\.a(\d+)\.outcome\.json$'))
        if ($m.Success) { $r.Outcomes[[int]$m.Groups[1].Value] = (Read-PsSuppJsonFile -LiteralPath $f.FullName) }
    }
    $r.Count = $r.Manifests.Count
    if ($r.LastN -gt 0 -and $r.Outcomes.ContainsKey($r.LastN)) { $r.LastOutcome = $r.Outcomes[$r.LastN] }
    return $r
}

# 待處理：domain==D、無 result、非被 supersede、attempts<MaxAttempts。回 @( @{ Request; Path; RequestId; Attempts; TargetName } )
function Get-PsSuppPending {
    param([string]$Root, [string]$Domain, [string]$DomainDir, [int]$MaxAttempts = 2, $Capabilities = $null)
    $all = Get-PsSuppRequests -Root $Root -Capabilities $Capabilities
    $maxGenByKey = @{}
    foreach ($r in $all) { if (-not $maxGenByKey.ContainsKey($r.WorkKey) -or $r.Generation -gt $maxGenByKey[$r.WorkKey]) { $maxGenByKey[$r.WorkKey] = $r.Generation } }
    $out = @()
    foreach ($r in $all) {
        if ($r.Domain -cne $Domain) { continue }
        if ($r.Generation -lt $maxGenByKey[$r.WorkKey]) { continue }
        if ($null -ne (Get-PsSupplementalResult -Root $Root -RequestId $r.RequestId)) { continue }
        $att = Get-PsSuppAttempts -DomainDir $DomainDir -RequestId $r.RequestId
        $out += , (@{ Request = $r.Obj; Path = $r.Path; RequestId = $r.RequestId; Attempts = $att.Count; TargetName = [string]$r.Obj.need.target.name; Exhausted = ($att.Count -ge $MaxAttempts) })
    }
    return , $out
}

# 被新世代取代、尚無 result 的舊 request（domain==D）：外環發 SUPERSEDED
function Get-PsSuppSuperseded {
    param([string]$Root, [string]$Domain, $Capabilities = $null)
    $all = Get-PsSuppRequests -Root $Root -Capabilities $Capabilities
    $maxGenByKey = @{}
    foreach ($r in $all) { if (-not $maxGenByKey.ContainsKey($r.WorkKey) -or $r.Generation -gt $maxGenByKey[$r.WorkKey]) { $maxGenByKey[$r.WorkKey] = $r.Generation } }
    $out = @()
    foreach ($r in $all) {
        if ($r.Domain -cne $Domain) { continue }
        if ($r.Generation -ge $maxGenByKey[$r.WorkKey]) { continue }
        if ($null -ne (Get-PsSupplementalResult -Root $Root -RequestId $r.RequestId)) { continue }
        $out += , $r
    }
    return , $out
}

# ── manifest（外環寫、模型讀；內容只來自 need＋目標 NN 節位＋一跳 callee 節位＋收據路徑）──────

function Get-PsSuppSectionOffsets {
    param($Facts, [string[]]$Names)
    $rows = @()
    foreach ($n in $Names) {
        $r = Get-PsKnSectionRange -Sections $Facts.sections -Name $n -Level 2
        if ($null -ne $r) { $rows += , (@{ Name = $n; Start = [int]$r.start; Limit = ([int]$r.end - [int]$r.start + 1) }) }
        else { $rows += , (@{ Name = $n; Start = 0; Limit = 0 }) }
    }
    return , $rows
}

# 一跳 callee：相關物件表角色含 followRoles 之一、且索引型別 ∈ followTypes、且該物件在本領域有 NN 檔
function Get-PsSuppCallees {
    param($TargetFacts, [string]$DomainDir, [string]$Domain, $Index, $Capabilities)
    $out = @()
    $roles = @($Capabilities.followRoles)
    $types = @($Capabilities.followTypes)
    # 角色以「開頭」比對（呼叫／啟動／排程／執行…）：「被呼叫」「由 X 啟動」是反向關係，不是 callee
    $roleRx = '^(' + ((@($roles | ForEach-Object { [regex]::Escape([string]$_) })) -join '|') + ')'
    foreach ($ro in @($TargetFacts.relatedObjects)) {
        $roleText = ([string]$ro.role).Trim()
        if ($roleText -notmatch $roleRx) { continue }
        $name = [string]$ro.name
        $type = ''
        if ($null -ne $Index) {
            foreach ($o in @($Index.objects)) {
                if ([string]::Equals([string]$o.object, $name, [System.StringComparison]::OrdinalIgnoreCase) -and [string]$o.type -ne 'UNKNOWN') { $type = [string]$o.type; break }
            }
        }
        if ($type -ne '' -and $types -notcontains $type) { continue }
        $files = Find-PsSuppTargetNn -DomainDir $DomainDir -TargetName $name
        if ($files.Count -eq 0) { continue }
        if ($type -eq '') {
            # 索引沒有型別：只認檔頭 Origin 存在的 NN，型別標 UNKNOWN（工單註明）
            $type = 'UNKNOWN'
        }
        $out += , (@{ Name = $name; Role = [string]$ro.role; Type = $type; Files = @($files) })
    }
    return , $out
}

function New-PsSuppManifest {
    param([string]$Root, $Request, [string]$Domain, [string]$DomainDir, [int]$AttemptNo, $Index, $Capabilities)
    $need = $Request.need
    $target = [string]$need.target.name
    $fk = [string]$need.factKind
    $cap = Get-PsSuppFactKind -Capabilities $Capabilities -FactKind $fk
    $parts = Get-PsSuppPartsDir -DomainDir $DomainDir
    if (-not [System.IO.Directory]::Exists($parts)) { [void][System.IO.Directory]::CreateDirectory($parts) }
    $rid = [string]$Request.requestId
    $manifestPath = Join-Path $parts ($rid + '.a' + $AttemptNo + '.manifest.md')
    $receiptRel = ('docs/ps-research/' + $Domain + '/supplemental-parts/' + $rid + '.a' + $AttemptNo + '.md')
    $files = Find-PsSuppTargetNn -DomainDir $DomainDir -TargetName $target
    $sections = @()
    if ($null -ne $cap) { $sections = @($cap.sections | ForEach-Object { [string]$_ }) }
    if ($sections.Count -eq 0) { $sections = @('功能定位') }
    if ($sections -notcontains 'Evidence附錄') { $sections += 'Evidence附錄' }
    $sb = New-Object System.Text.StringBuilder
    $nl = "`n"
    [void]$sb.Append('# 補研究工單 ' + $rid + '（attempt a' + $AttemptNo + '）').Append($nl).Append($nl)
    [void]$sb.Append('領域：' + $Domain).Append($nl)
    [void]$sb.Append('目標：' + [string]$need.target.type + ' ' + $target).Append($nl)
    $mode = 'EXTRACT'
    if ($null -ne $cap -and $null -ne $cap.mode) { $mode = [string]$cap.mode }
    [void]$sb.Append('事實類別：' + $fk + '（' + $mode + '）').Append($nl)
    [void]$sb.Append('要補的屬性：' + (@($need.properties) -join '、')).Append($nl)
    $ctxParts = @()
    if ($null -ne $need.context) { foreach ($p in $need.context.PSObject.Properties) { $ctxParts += ($p.Name + '=' + [string]$p.Value) } }
    if ($ctxParts.Count -eq 0) { $ctxParts = @('（無）') }
    [void]$sb.Append('情境：' + ($ctxParts -join '；')).Append($nl)
    [void]$sb.Append('證據政策：' + [string]$need.evidencePolicy + '　時效：' + [string]$need.freshness).Append($nl).Append($nl)
    [void]$sb.Append('## 讀取範圍（只准 read 下列檔的下列節；offset／limit 直接用；@缺＝該節不存在，不讀）').Append($nl).Append($nl)
    [void]$sb.Append('| 檔 | 節 | offset | limit |').Append($nl)
    [void]$sb.Append('|---|---|---|---|').Append($nl)
    $targetFiles = @()
    $calleeFiles = @()
    $targetFacts = $null
    foreach ($f in $files) {
        $facts = Get-PsKnNnFacts -LiteralPath (Join-Path $DomainDir $f) -Domain $Domain
        if ($null -eq $facts) { continue }
        if ($null -eq $targetFacts) { $targetFacts = $facts }
        $targetFiles += $f
        foreach ($row in (Get-PsSuppSectionOffsets -Facts $facts -Names $sections)) {
            $disp = $row.Name
            if ($script:PsKnSectionDisplay.ContainsKey($disp)) { $disp = $script:PsKnSectionDisplay[$disp] }
            if ($row.Start -gt 0) { [void]$sb.Append('| docs/ps-research/' + $Domain + '/' + $f + ' | ' + $disp + ' | ' + $row.Start + ' | ' + $row.Limit + ' |').Append($nl) }
            else { [void]$sb.Append('| docs/ps-research/' + $Domain + '/' + $f + ' | ' + $disp + ' | @缺 | 0 |').Append($nl) }
        }
    }
    $follow = $false
    if ($null -ne $cap -and $null -ne $cap.follow) { $follow = [bool]$cap.follow }
    if ($follow -and $null -ne $targetFacts) {
        foreach ($c in (Get-PsSuppCallees -TargetFacts $targetFacts -DomainDir $DomainDir -Domain $Domain -Index $Index -Capabilities $Capabilities)) {
            foreach ($cf in $c.Files) {
                $cfacts = Get-PsKnNnFacts -LiteralPath (Join-Path $DomainDir $cf) -Domain $Domain
                if ($null -eq $cfacts) { continue }
                $calleeFiles += $cf
                foreach ($row in (Get-PsSuppSectionOffsets -Facts $cfacts -Names @('執行方式', '資料流'))) {
                    if ($row.Start -gt 0) { [void]$sb.Append('| docs/ps-research/' + $Domain + '/' + $cf + ' | ' + $row.Name + '（callee ' + $c.Type + '，角色 ' + $c.Role + '） | ' + $row.Start + ' | ' + $row.Limit + ' |').Append($nl) }
                }
            }
        }
    }
    [void]$sb.Append($nl)
    [void]$sb.Append('## 委派鏈').Append($nl).Append($nl)
    [void]$sb.Append('依 .opencode/peoplesoft/supplemental-contract.md 的「事實類別 → 委派鏈」表；本工單類別：' + $fk + '。').Append($nl)
    [void]$sb.Append('只補「要補的屬性」列出的事實；工單沒列的不查。缺證據走既有出口（SQL 型→待人工SQL；CHUNK 型→處置 NO_EVIDENCE＋查法收據）。').Append($nl).Append($nl)
    [void]$sb.Append('## 輸出').Append($nl).Append($nl)
    [void]$sb.Append('唯一可寫：' + $receiptRel).Append($nl)
    [void]$sb.Append('格式：supplemental-contract.md 的三張表（## 處置、## 追加事實、## 追加證據）；≤150 行；不得含三反引號圍欄與 wikilink 雙中括號。').Append($nl)
    $text = $sb.ToString()
    $okM = Write-PsKnCreateOnlyText -LiteralPath $manifestPath -Text $text
    $current = Join-Path $parts 'current.manifest.md'
    $okC = $false
    if ($okM -eq $true) { $okC = Write-PsKnAtomicText -LiteralPath $current -Text $text -Bom $false }
    return @{ ManifestPath = $manifestPath; CurrentPath = $current; ReceiptPath = (Join-Path $parts ($rid + '.a' + $AttemptNo + '.md')); ReceiptRel = $receiptRel; TargetFiles = @($targetFiles); CalleeFiles = @($calleeFiles); Text = $text; Created = ($okM -eq $true); CreateDeferred = ($null -eq $okM); CurrentWritten = $okC; TargetFacts = $targetFacts }
}

function Write-PsSuppOutcome {
    param([string]$DomainDir, [string]$RequestId, [int]$AttemptNo, $Outcome)
    $parts = Get-PsSuppPartsDir -DomainDir $DomainDir
    $p = Join-Path $parts ($RequestId + '.a' + $AttemptNo + '.outcome.json')
    $o = [ordered]@{}
    foreach ($k in @($Outcome.Keys)) { $o[[string]$k] = $Outcome[$k] }
    if (-not $o.Contains('attempt')) { $o['attempt'] = $AttemptNo }
    if (-not $o.Contains('completedAt')) { $o['completedAt'] = (Get-PsKnUtcStamp) }
    [void](Write-PsKnAtomicText -LiteralPath $p -Text ((ConvertTo-PsKnJson -Value $o) + "`n") -Bom $false)
    return $p
}

# ── 收據驗收（模型唯一可寫的檔）────────────────────────────────

function Get-PsSuppTable {
    param([string[]]$Lines, $Headings, [string]$Key)
    $sec = $null
    foreach ($h in $Headings) { if ($h.Level -eq 2 -and (Get-PsKnSectionKey -Title $h.Title) -eq $Key) { $sec = $h; break } }
    if ($null -eq $sec) { return $null }
    $header = $null
    for ($i = $sec.Start; $i -lt $sec.End -and $i -lt $Lines.Count; $i++) {
        $ln = $Lines[$i]
        if ($ln -match '^\s*\|' -and $ln -notmatch '^\s*\|[\s:|-]+\|\s*$') {
            $inner = ($ln.Trim() -replace '^\|', '') -replace '\|\s*$', ''
            $header = @(); foreach ($c in ($inner -split '\|')) { $header += $c.Trim() }
            break
        }
    }
    $rows = Get-PsKnTableRows -Lines $Lines -Start $sec.Start -End $sec.End
    return @{ Header = $header; Rows = $rows; Section = $sec }
}

# 回 @{ Ok; Errors; Disposition; Method; Facts=@(@{Section;Confidence;Text;EvidenceRefs=@(int)}); Evidence=@(@{Location;Note;Ref}); Lines }
function Test-PsSuppReceipt {
    param([string]$LiteralPath, $Capabilities)
    $r = @{ Ok = $false; Errors = @(); Disposition = ''; Method = ''; Facts = @(); Evidence = @(); Lines = 0 }
    $text = Read-PsKnText -LiteralPath $LiteralPath
    if ($null -eq $text) { $r.Errors += '收據檔不存在'; return $r }
    if ($text.Trim() -eq '') { $r.Errors += '收據檔空白'; return $r }
    $lines = Get-PsKnLines -Text $text
    $r.Lines = $lines.Count
    if ($lines.Count -gt 150) { $r.Errors += ('超過 150 行（' + $lines.Count + '）') }
    if ($text -match '```') { $r.Errors += '含三反引號圍欄' }
    if ($text -match '\[\[') { $r.Errors += '含 [[ ]]（收據不得寫 wikilink；物件名用反引號或裸字）' }
    $leak = 0
    foreach ($k in $script:PsSuppLeakMarkers) { if ($text.Contains($k)) { $leak++ } }
    if ($leak -ge 2) { $r.Errors += '含模型契約 JSON 洩漏' }
    foreach ($w in $script:PsSuppForbiddenWords) { if ($text.IndexOf($w, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $r.Errors += ('含消費端識別字樣「' + $w + '」') } }
    $heads = Get-PsKnHeadings -Lines $lines
    # ## 處置
    $t1 = Get-PsSuppTable -Lines $lines -Headings $heads -Key '處置'
    if ($null -eq $t1) { $r.Errors += '缺章節「## 處置」' }
    else {
        if ($null -eq $t1.Header -or $t1.Header.Count -ne 2 -or $t1.Header[0] -ne '處置' -or $t1.Header[1] -ne '查法收據') { $r.Errors += '「## 處置」表頭須逐字為 | 處置 | 查法收據 |' }
        elseif ($t1.Rows.Count -ne 1) { $r.Errors += ('「## 處置」須恰一列（' + $t1.Rows.Count + '）') }
        else {
            $c = $t1.Rows[0].Cells
            if ($c.Count -lt 2) { $r.Errors += '「## 處置」列欄數不足' }
            else {
                $r.Disposition = $c[0].Trim().ToUpperInvariant()
                $r.Method = $c[1].Trim()
                if ($script:PsSuppReceiptDispositions -notcontains $r.Disposition) { $r.Errors += ('處置不在值域：' + $r.Disposition) }
                if ($r.Method -eq '') { $r.Errors += '查法收據空白（用什麼工具、什麼參數、查了幾頁）' }
            }
        }
    }
    # ## 追加證據（先解析，追加事實的證據# 要對它的範圍）
    $t3 = Get-PsSuppTable -Lines $lines -Headings $heads -Key '追加證據'
    if ($null -eq $t3) { $r.Errors += '缺章節「## 追加證據」' }
    else {
        if ($null -eq $t3.Header -or $t3.Header.Count -ne 3 -or $t3.Header[0] -ne '位置' -or $t3.Header[1] -ne '說明' -or $t3.Header[2] -ne '機器參照') { $r.Errors += '「## 追加證據」表頭須逐字為 | 位置 | 說明 | 機器參照 |' }
        else {
            $ri = 0
            foreach ($row in $t3.Rows) {
                $ri++
                $c = $row.Cells
                if ($c.Count -ne 3) { $r.Errors += ('「## 追加證據」第 ' + $ri + ' 列欄數 ' + $c.Count + ' ≠ 3'); continue }
                if ($c[0] -eq '' -or $c[2] -eq '') { $r.Errors += ('「## 追加證據」第 ' + $ri + ' 列位置或機器參照空白'); continue }
                $ref = $c[2]
                $okRef = $false
                if ($ref -match $script:PsKnUuidRx) { $okRef = $true }
                elseif ($ref -match '(?i)\bSELECT\b[\s\S]{0,400}?\bFROM\b') { $okRef = $true }
                elseif ($ref -match '待人工\s*SQL') { $okRef = $true }
                if (-not $okRef) { $r.Errors += ('「## 追加證據」第 ' + $ri + ' 列機器參照須為完整 36 字元 ChunkId／SELECT…FROM／待人工SQL') }
                if ($ref -match '(?<![0-9a-fA-F-])[0-9a-fA-F]{8}(?![0-9a-fA-F-])' -and $ref -notmatch $script:PsKnUuidRx -and $ref -match '(?i)chunk') { $r.Errors += ('「## 追加證據」第 ' + $ri + ' 列 ChunkId 疑似縮寫（須 36 字元）') }
                $r.Evidence += , (@{ Location = $c[0]; Note = $c[1]; Ref = $c[2]; Row = $ri })
            }
        }
    }
    # ## 追加事實
    $t2 = Get-PsSuppTable -Lines $lines -Headings $heads -Key '追加事實'
    if ($null -eq $t2) { $r.Errors += '缺章節「## 追加事實」' }
    else {
        if ($null -eq $t2.Header -or $t2.Header.Count -ne 4 -or $t2.Header[0] -ne '節' -or $t2.Header[1] -ne '信心' -or $t2.Header[2] -ne '敘述' -or $t2.Header[3] -ne '證據#') { $r.Errors += '「## 追加事實」表頭須逐字為 | 節 | 信心 | 敘述 | 證據# |' }
        else {
            $sections = @($Capabilities.nnSections | ForEach-Object { [string]$_ })
            $confs = @($Capabilities.confidence | ForEach-Object { [string]$_ })
            $ri = 0
            foreach ($row in $t2.Rows) {
                $ri++
                $c = $row.Cells
                if ($c.Count -ne 4) { $r.Errors += ('「## 追加事實」第 ' + $ri + ' 列欄數 ' + $c.Count + ' ≠ 4'); continue }
                $secKey = Get-PsKnSectionKey -Title $c[0]
                if ($sections -notcontains $secKey) { $r.Errors += ('「## 追加事實」第 ' + $ri + ' 列節名「' + $c[0] + '」不在八節'); continue }
                $conf = $c[1].Trim().ToUpperInvariant()
                if ($confs -notcontains $conf) { $r.Errors += ('「## 追加事實」第 ' + $ri + ' 列信心「' + $c[1] + '」不在三值'); continue }
                $desc = $c[2].Trim()
                if ($desc -eq '') { $r.Errors += ('「## 追加事實」第 ' + $ri + ' 列敘述空白'); continue }
                if ($script:PsSuppTableSections.ContainsKey($secKey)) {
                    $need = [int]$script:PsSuppTableSections[$secKey].Cells
                    $got = @($desc -split '｜').Count
                    if ($got -ne $need) { $r.Errors += ('「## 追加事實」第 ' + $ri + ' 列：表格節「' + $secKey + '」的敘述須以全形直線｜分成 ' + $need + ' 格（得 ' + $got + '）'); continue }
                }
                $refs = @()
                $refTxt = $c[3].Trim()
                if ($refTxt -ne '無' -and $refTxt -ne '') {
                    foreach ($tok in ($refTxt -split '[;；,、]')) {
                        $x = $tok.Trim()
                        if ($x -eq '') { continue }
                        $n = 0
                        if (-not [int]::TryParse($x, [ref]$n) -or $n -lt 1 -or $n -gt $r.Evidence.Count) { $r.Errors += ('「## 追加事實」第 ' + $ri + ' 列證據# ' + $x + ' 超出追加證據範圍（1..' + $r.Evidence.Count + '）'); continue }
                        $refs += $n
                    }
                }
                if ($conf -eq 'CONFIRMED' -and $refs.Count -eq 0) { $r.Errors += ('「## 追加事實」第 ' + $ri + ' 列 CONFIRMED 必須有證據#') }
                $r.Facts += , (@{ Section = $secKey; Confidence = $conf; Text = $desc; EvidenceRefs = @($refs); Row = $ri })
            }
        }
    }
    if ($r.Disposition -eq 'RESEARCHED' -and $r.Facts.Count -eq 0) { $r.Errors += '處置 RESEARCHED 但追加事實為空' }
    if ($r.Disposition -eq 'NOT_IN_DOMAIN' -or $r.Disposition -eq 'UNSUPPORTED') { if ($r.Facts.Count -gt 0) { $r.Errors += ('處置 ' + $r.Disposition + ' 不得追加事實') } }
    $r.Ok = ($r.Errors.Count -eq 0)
    return $r
}

# ALREADY_COVERED 只准在目標 NN 的相關節非空洞時成立
function Test-PsSuppAlreadyCovered {
    param($TargetFacts, [string]$FactKind, $Capabilities)
    if ($null -eq $TargetFacts) { return $false }
    $cap = Get-PsSuppFactKind -Capabilities $Capabilities -FactKind $FactKind
    if ($null -eq $cap) { return $false }
    $secs = @($cap.sections | ForEach-Object { [string]$_ })
    if ($secs.Count -eq 0) { return ($TargetFacts.status -eq 'COMPLETE') }
    foreach ($s in $secs) {
        switch ($s) {
            '畫面與欄位' { if ([int]$TargetFacts.fieldRows -eq 0 -and -not $TargetFacts.fieldsNotApplicable) { return $false } }
            '行為邏輯' { $bc = $TargetFacts.behaviorCounts; if (([int]$bc.CONFIRMED + [int]$bc.INFERRED + [int]$bc.DYNAMIC_RUNTIME) -eq 0) { return $false } }
            '資料流' { if (@($TargetFacts.dataFlow).Count -eq 0) { return $false } }
            '執行方式' { if ($TargetFacts.executionHollow) { return $false } }
            '權限' { if ($TargetFacts.permissionHollow) { return $false } }
            '相關物件' { if (@($TargetFacts.relatedObjects).Count -eq 0) { return $false } }
            'Evidence附錄' { if ([int]@($TargetFacts.evidence).Count -eq 0) { return $false } }
            default { }
        }
    }
    return $true
}

# ── 確定性合併（只追加；附錄編號承接；缺節在「## 未解事項」前插入）──────

function Get-PsSuppInsertAfter {
    # 節（含子節）末：最後一個非空行的索引（0 起算）；若節有 ### 子節且 $BeforeSubsections，則取第一個子節標題前的最後非空行
    param([string[]]$Lines, $Sec, [bool]$BeforeSubsections = $false)
    $endIdx = [Math]::Min([int]$Sec.End, $Lines.Count) - 1
    $startIdx = [int]$Sec.Start - 1
    if ($BeforeSubsections) {
        for ($i = $startIdx + 1; $i -le $endIdx; $i++) { if ($Lines[$i] -match '^[ \t]{0,3}###[ \t]+') { $endIdx = $i - 1; break } }
    }
    for ($i = $endIdx; $i -gt $startIdx; $i--) { if ($Lines[$i].Trim() -ne '') { return $i } }
    return $startIdx
}

function Get-PsSuppTableInsert {
    # 表格節：回 @{ After=索引; HasTable }——After＝最後一列（或分隔列）索引；無表＝節末
    param([string[]]$Lines, $Sec)
    $rows = Get-PsKnTableRows -Lines $Lines -Start $Sec.Start -End $Sec.End
    if ($rows.Count -gt 0) { return @{ After = ([int]$rows[$rows.Count - 1].Line - 1); HasTable = $true } }
    $endIdx = [Math]::Min([int]$Sec.End, $Lines.Count) - 1
    for ($i = [int]$Sec.Start; $i -le $endIdx; $i++) { if ($Lines[$i] -match '^\s*\|[\s:|-]+\|\s*$') { return @{ After = $i; HasTable = $true } } }
    return @{ After = (Get-PsSuppInsertAfter -Lines $Lines -Sec $Sec); HasTable = $false }
}

# 回 @{ Ok; Reason; BytesBefore; HashBefore; HashAfter; Sections; EvidenceRows; Changed; Path }
function Merge-PsSuppReceipt {
    param([string]$NnPath, $Receipt, [string]$RequestId)
    $res = @{ Ok = $false; Reason = ''; BytesBefore = $null; HashBefore = ''; HashAfter = ''; Sections = @(); EvidenceRows = @(); Changed = $false; Path = $NnPath }
    if (-not [System.IO.File]::Exists($NnPath)) { $res.Reason = 'NN 檔不存在'; return $res }
    $bytes = [System.IO.File]::ReadAllBytes($NnPath)
    $res.BytesBefore = $bytes
    $raw = [System.IO.File]::ReadAllText($NnPath)
    if ($raw.Length -gt 0 -and [int]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
    # BOM 以位元組判定（ReadAllText 會依 BOM 解碼並丟棄它）
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $eol = "`n"
    if ($raw.IndexOf("`r`n") -ge 0) { $eol = "`r`n" }
    $res.HashBefore = Get-PsKnTextHash -Text $raw
    $lines = Get-PsKnLines -Text $raw
    if ($Receipt.Facts.Count -eq 0 -and $Receipt.Evidence.Count -eq 0) { $res.Ok = $true; $res.Reason = 'NOTHING_TO_MERGE'; $res.HashAfter = $res.HashBefore; return $res }
    $heads = Get-PsKnHeadings -Lines $lines
    $inserts = @()   # @{ Index=插在此索引之後（-1＝檔首）; Lines=@(); Order }
    $order = 0
    # 1. Evidence 附錄：編號承接
    $evSec = Find-PsKnSection -Headings $heads -Key 'Evidence附錄'
    $maxN = 0
    $evAfter = -1
    $evHasTable = $false
    if ($null -ne $evSec) {
        foreach ($row in (Get-PsKnTableRows -Lines $lines -Start $evSec.Start -End $evSec.End)) {
            $n = 0
            if ($row.Cells.Count -gt 0 -and [int]::TryParse($row.Cells[0], [ref]$n)) { if ($n -gt $maxN) { $maxN = $n } }
            else { $maxN++ }
        }
        $ti = Get-PsSuppTableInsert -Lines $lines -Sec $evSec
        $evAfter = $ti.After
        $evHasTable = $ti.HasTable
    }
    $evLines = @()
    if (-not $evHasTable) { $evLines += ''; $evLines += '| # | 位置 | 說明 | 機器參照 |'; $evLines += '|---|---|---|---|' }
    $k = 0
    $evMap = @{}
    foreach ($e in $Receipt.Evidence) {
        $k++
        $num = $maxN + $k
        $evMap[$k] = $num
        $evLines += ('| ' + $num + ' | ' + $e.Location + ' | ' + $e.Note + ' | ' + $e.Ref + ' |')
        $res.EvidenceRows += $num
    }
    if ($Receipt.Evidence.Count -gt 0) {
        if ($null -ne $evSec) { $order++; $inserts += , (@{ Index = $evAfter; Lines = @($evLines); Order = $order }) }
        else {
            $order++
            $blk = @('', '## Evidence 附錄') + @($evLines)
            $inserts += , (@{ Index = ($lines.Count - 1); Lines = $blk; Order = $order; AtEnd = $true })
        }
    }
    # 2. 追加事實：依節分組（保留收據列序）
    $bySec = [ordered]@{}
    foreach ($f in $Receipt.Facts) { if (-not $bySec.Contains($f.Section)) { $bySec[$f.Section] = @() }; $bySec[$f.Section] += , $f }
    $gapsSec = Find-PsKnSection -Headings $heads -Key '未解事項'
    $anchorMissing = -1
    if ($null -ne $gapsSec) { $anchorMissing = [int]$gapsSec.Start - 2 }
    elseif ($null -ne $evSec) { $anchorMissing = [int]$evSec.Start - 2 }
    else { $anchorMissing = $lines.Count - 1 }
    # 錨點＝標題前最後一個非空行（插入的節塊自帶前導空行，標題前原有的空行留給下一節）
    while ($anchorMissing -gt 0 -and $lines[$anchorMissing].Trim() -eq '') { $anchorMissing-- }
    if ($anchorMissing -lt 0) { $anchorMissing = -1 }
    foreach ($secKey in $bySec.Keys) {
        $facts = $bySec[$secKey]
        $sec = Find-PsKnSection -Headings $heads -Key $secKey
        $body = @()
        $refText = { param($f) $parts = @(); foreach ($x in $f.EvidenceRefs) { if ($evMap.ContainsKey($x)) { $parts += ('#' + $evMap[$x]) } }; if ($parts.Count -gt 0) { return ('附錄 ' + ($parts -join '、')) }; return '' }
        if ($script:PsSuppTableSections.ContainsKey($secKey)) {
            $spec = $script:PsSuppTableSections[$secKey]
            foreach ($f in $facts) {
                $cells = @($f.Text -split '｜' | ForEach-Object { $_.Trim() })
                $rt = & $refText $f
                if ($rt -ne '') { $cells[[int]$spec.RefCell] = $cells[[int]$spec.RefCell] + '（' + $rt + '）' }
                if ($secKey -eq '資料流') { $cells += $f.Confidence }
                $body += ('| ' + ($cells -join ' | ') + ' |')
            }
        }
        elseif ($script:PsSuppBulletSections -contains $secKey) {
            foreach ($f in $facts) {
                $rt = & $refText $f
                $suffix = ''
                if ($rt -ne '') { $suffix = '（' + $rt + '）' }
                if ($secKey -eq '行為邏輯') { $body += ('- **' + $f.Confidence + '**：' + $f.Text + $suffix) }
                else { $body += ('- ' + $f.Text + '（' + $f.Confidence + '；補研究' + $(if ($rt -ne '') { '；' + $rt } else { '' }) + '）') }
            }
        }
        else {
            foreach ($f in $facts) {
                $rt = & $refText $f
                $meta = $f.Confidence
                if ($rt -ne '') { $meta = $meta + '；' + $rt }
                $body += ''
                $body += ($f.Text + '（' + $meta + '）')
            }
        }
        $res.Sections += $secKey
        if ($null -ne $sec) {
            if ($script:PsSuppTableSections.ContainsKey($secKey)) {
                $ti = Get-PsSuppTableInsert -Lines $lines -Sec $sec
                $blk = @()
                if (-not $ti.HasTable) { $blk += ''; $blk += $script:PsSuppTableSections[$secKey].Header; $blk += $script:PsSuppTableSections[$secKey].Sep }
                $blk += $body
                $order++; $inserts += , (@{ Index = $ti.After; Lines = $blk; Order = $order })
            }
            else {
                $after = Get-PsSuppInsertAfter -Lines $lines -Sec $sec -BeforeSubsections ($secKey -eq '功能定位')
                $order++; $inserts += , (@{ Index = $after; Lines = @($body); Order = $order })
            }
        }
        else {
            $disp = $secKey
            if ($secKey -eq '未解事項') { $disp = '未解事項（gaps）' }
            $blk = @('', ('## ' + $disp), '')
            if ($script:PsSuppTableSections.ContainsKey($secKey)) { $blk += $script:PsSuppTableSections[$secKey].Header; $blk += $script:PsSuppTableSections[$secKey].Sep }
            $bodyTrim = @($body)
            while ($bodyTrim.Count -gt 0 -and $bodyTrim[0] -eq '') { $bodyTrim = @($bodyTrim | Select-Object -Skip 1) }
            $blk += $bodyTrim
            $order++; $inserts += , (@{ Index = $anchorMissing; Lines = $blk; Order = $order })
        }
    }
    if ($inserts.Count -eq 0) { $res.Ok = $true; $res.Reason = 'NOTHING_TO_MERGE'; $res.HashAfter = $res.HashBefore; return $res }
    # 由後往前套用（同索引者：Order 大的先套，使最終順序＝Order 小的在前）
    $sorted = @($inserts | Sort-Object -Property @{ Expression = { [int]$_.Index }; Descending = $true }, @{ Expression = { [int]$_.Order }; Descending = $true })
    $work = New-Object System.Collections.Generic.List[string]
    foreach ($l in $lines) { $work.Add($l) }
    foreach ($ins in $sorted) {
        $at = [int]$ins.Index + 1
        if ($at -gt $work.Count) { $at = $work.Count }
        if ($at -lt 0) { $at = 0 }
        $work.InsertRange($at, [string[]]@($ins.Lines))
    }
    $newText = ($work.ToArray() -join $eol)
    if ($raw.EndsWith("`n") -and -not $newText.EndsWith("`n")) { $newText += $eol }
    $ok = Write-PsKnAtomicText -LiteralPath $NnPath -Text $newText -Bom $hasBom
    if (-not $ok) { $res.Reason = 'WRITE_DEFERRED'; return $res }
    $res.HashAfter = Get-PsKnTextHash -Text $newText
    $res.Changed = ($res.HashAfter -cne $res.HashBefore)
    $res.Ok = $true
    $res.Reason = 'MERGED'
    return $res
}

# 還原原 bytes：也走 tmp → Replace／Move（半路被殺不會留下 0 byte 的 NN）
function Restore-PsSuppBytes {
    param([string]$LiteralPath, [byte[]]$Bytes, [int]$Retries = 5)
    if ($null -eq $Bytes) { return $false }
    $tmp = $LiteralPath + '.tmp-' + [guid]::NewGuid().ToString('N')
    [System.IO.File]::WriteAllBytes($tmp, $Bytes)
    for ($try = 1; $try -le $Retries; $try++) {
        try {
            if ([System.IO.File]::Exists($LiteralPath)) {
                $bak = $LiteralPath + '.bak-' + [guid]::NewGuid().ToString('N')
                try { [System.IO.File]::Replace($tmp, $LiteralPath, $bak) }
                catch [System.PlatformNotSupportedException] { [System.IO.File]::Delete($LiteralPath); [System.IO.File]::Move($tmp, $LiteralPath) }
                if ([System.IO.File]::Exists($bak)) { [System.IO.File]::Delete($bak) }
            }
            else { [System.IO.File]::Move($tmp, $LiteralPath) }
            return $true
        }
        catch { Start-Sleep -Milliseconds (200 * $try) }
    }
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    return $false
}

# ── result 發布（create-only；已存在＝冪等成功）───────────────────

function New-PsSuppResult {
    param($Request, [string]$Outcome, [string]$Disposition, [int]$AuditRound, $Affected, [int]$Attempts, [datetime]$AsOf = [datetime]::UtcNow)
    if ($script:PsSuppOutcomes -notcontains $Outcome) { throw "outcome 不在值域：$Outcome" }
    if ($script:PsSuppDispositions -notcontains $Disposition) { throw "dispositionCode 不在值域：$Disposition" }
    $aff = @()
    foreach ($a in @($Affected)) {
        if ($null -eq $a) { continue }
        $aff += , ([ordered]@{ file = [string]$a.file; hashBefore = [string]$a.hashBefore; hashAfter = [string]$a.hashAfter; sections = @($a.sections); evidenceRows = @($a.evidenceRows) })
    }
    return [ordered]@{
        schemaVersion          = $script:PsSuppSchemaVersion
        requestId              = [string]$Request.requestId
        workKey                = [string]$Request.workKey
        domain                 = [string]$Request.domain
        outcome                = $Outcome
        dispositionCode        = $Disposition
        auditRoundAtCompletion = $AuditRound
        affected               = $aff
        attempts               = $Attempts
        completedAt            = (Get-PsKnUtcStamp -At $AsOf)
    }
}

# result 只由 Research 迷你圈寫；已存在＝冪等成功（但必須是同一 workKey／domain 的 result——不同就是別人寫的，回 Ok=$false 讓外環記違規）
function Publish-PsSuppResult {
    param([string]$Root, $Result)
    $d = Get-PsSuppDirs -Root $Root
    $p = Join-Path $d.Results ([string]$Result.requestId + '.json')
    if ([System.IO.File]::Exists($p)) {
        $ex = Read-PsSuppJsonFile -LiteralPath $p
        if ($null -ne $ex -and [string]$ex.workKey -ceq [string]$Result.workKey -and [string]$ex.domain -ceq [string]$Result.domain -and ($script:PsSuppOutcomes -contains [string]$ex.outcome)) { return @{ Ok = $true; Existed = $true; Path = $p } }
        return @{ Ok = $false; Existed = $true; Path = $p; Reason = 'FOREIGN_RESULT' }
    }
    $ok = Write-PsKnCreateOnlyText -LiteralPath $p -Text ((ConvertTo-PsKnJson -Value $Result) + "`n")
    if ($ok -eq $true) { return @{ Ok = $true; Existed = $false; Path = $p } }
    if ($ok -eq $false) { return @{ Ok = $true; Existed = $true; Path = $p } }
    return @{ Ok = $false; Existed = $false; Path = $p; Reason = 'WRITE_DEFERRED' }
}

# ── 消費端：完成邊界（RESEARCHED／AUDITED／GRADUATED／PROJECTED）────

# JSON 讀回的時間戳：PowerShell 7 的 ConvertFrom-Json 會把 ISO 字串轉成 DateTime、5.1 保留字串——兩種都化成 yyyy-MM-dd
function Get-PsSuppDateKey {
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return ([datetime]$Value).ToUniversalTime().ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) }
    $s = [string]$Value
    if ($s.Length -ge 10) { return $s.Substring(0, 10) }
    return $s
}

function Get-PsSuppCompletion {
    param([string]$Root, [string]$RequestId, $Index = $null)
    $res = Get-PsSupplementalResult -Root $Root -RequestId $RequestId
    $c = @{ RequestId = $RequestId; Result = $res; Researched = $false; Audited = $false; Graduated = $false; Projected = $false; Outcome = ''; Reason = '' }
    if ($null -eq $res) { $c.Reason = 'NO_RESULT'; return $c }
    $c.Outcome = [string]$res.outcome
    $c.Researched = (@('RESOLVED', 'PARTIAL') -contains $c.Outcome)
    if (-not $c.Researched) { $c.Reason = $c.Outcome; return $c }
    if ($null -eq $Index) { $Index = Read-PsKnowledgeIndex -Root $Root }
    if ($null -eq $Index) { $c.Reason = 'INDEX_MISSING'; return $c }
    $dom = [string]$res.domain
    $domRound = 0
    foreach ($d in @($Index.domains)) { if ([string]$d.domain -ceq $dom) { $domRound = [int]$d.auditRound } }
    $allClean = ($res.affected.Count -gt 0)
    $allTier = ($res.affected.Count -gt 0)
    foreach ($a in @($res.affected)) {
        $e = $null
        foreach ($n in @($Index.nn)) { if ([string]$n.domain -ceq $dom -and [string]$n.file -ceq [string]$a.file) { $e = $n; break } }
        if ($null -eq $e) { $allClean = $false; $allTier = $false; continue }
        if ([string]$e.grade -ne 'AUDITED_CLEAN') { $allClean = $false }
        if ([int]$e.receiptTier -lt 1 -or $e.receiptStale) { $allTier = $false }
    }
    $c.Audited = ($allClean -and $domRound -gt [int]$res.auditRoundAtCompletion)
    $c.Graduated = $allTier
    $req = Get-PsSuppRequest -Root $Root -RequestId $RequestId
    if ($null -ne $req) {
        $tn = [string]$req.need.target.name
        foreach ($w in @($Index.wiki)) {
            if ([string]::Equals([string]$w.name, $tn, [System.StringComparison]::OrdinalIgnoreCase)) {
                if (@('verified', 'draft') -contains [string]$w.effective -and [string]$w.lastVerified -ge (Get-PsSuppDateKey -Value $res.completedAt)) { $c.Projected = $true }
            }
        }
    }
    return $c
}

# ── wiki 標記、parts 搬移、checklist D 列 ───────────────────────

function Set-PsSuppWikiStale {
    param([string]$Root, [string]$TargetName, [string[]]$LinkedNames, [string]$RequestId, [string]$SourceLabel, [datetime]$AsOf = [datetime]::UtcNow)
    $wikiDir = Join-Path (Join-Path $Root (Join-Path 'docs' 'ps-research')) 'wiki'
    $r = @{ Stale = 0; Invalidated = 0; Files = @() }
    if (-not [System.IO.Directory]::Exists($wikiDir)) { return $r }
    $names = @($TargetName) + @($LinkedNames)
    $seen = @{}
    foreach ($n in $names) {
        if ($null -eq $n -or $n -eq '') { continue }
        $p = Join-Path $wikiDir ($n + '.md')
        if ($seen.ContainsKey($p.ToLowerInvariant())) { continue }
        $seen[$p.ToLowerInvariant()] = $true
        $raw = Read-PsKnText -LiteralPath $p
        if ($null -eq $raw) { continue }
        $eol = "`n"
        if ($raw.IndexOf("`r`n") -ge 0) { $eol = "`r`n" }
        $reviewed = ($raw -match '(?m)^reviewed:\s*true\s*$')
        $dateTxt = $AsOf.ToUniversalTime().ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        if ($reviewed) {
            $line = ('- ' + $dateTxt + ' 來源 NN 已補研究 ' + $RequestId + '（' + $SourceLabel + '）——reviewed 條目不改狀態，請人工覆核')
            if ($raw -match '(?m)^##\s*Invalidated') { $new = $raw.TrimEnd() + $eol + $line + $eol }
            else { $new = $raw.TrimEnd() + $eol + $eol + '## Invalidated（作廢紀錄——只追加，不刪除）' + $eol + $eol + $line + $eol }
            if (Write-PsKnAtomicText -LiteralPath $p -Text $new -Bom $false) { $r.Invalidated++; $r.Files += $p }
        }
        else {
            # 只改 frontmatter（第一個 --- 到第二個 ---）裡的第一個 status: 列；用 Regex 實例的 Replace(input, replacement, count)
            # （靜態 [regex]::Replace 沒有 count 參數：多給的 1 會被當成 RegexOptions.IgnoreCase）
            $fmEnd = -1
            if ($raw.StartsWith('---')) { $fmEnd = $raw.IndexOf($eol + '---', 3) }
            if ($fmEnd -lt 0) { continue }
            $fm = $raw.Substring(0, $fmEnd)
            if ($fm -match '(?m)^status:\s*stale\b') { continue }
            $rx = New-Object System.Text.RegularExpressions.Regex('(?m)^(status:\s*)\S+')
            $fmNew = $rx.Replace($fm, '${1}stale', 1)
            if ($fmNew -ceq $fm) { continue }
            $new = $fmNew + $raw.Substring($fmEnd)
            if (Write-PsKnAtomicText -LiteralPath $p -Text $new -Bom $false) { $r.Stale++; $r.Files += $p }
        }
    }
    return $r
}

function Move-PsSuppPartsDone {
    param([string]$DomainDir, [string]$LogDir, [string]$RequestId)
    $parts = Get-PsSuppPartsDir -DomainDir $DomainDir
    $dest = Join-Path $LogDir 'supplemental-done'
    if (-not [System.IO.Directory]::Exists($parts)) { return 0 }
    if (-not [System.IO.Directory]::Exists($dest)) { [void][System.IO.Directory]::CreateDirectory($dest) }
    $n = 0
    $esc = [regex]::Escape($RequestId)
    foreach ($f in @(Get-ChildItem -LiteralPath $parts -File -ErrorAction SilentlyContinue)) {
        if ($f.Name -notmatch ('^' + $esc + '\.')) { continue }
        $target = Join-Path $dest $f.Name
        if ([System.IO.File]::Exists($target)) { $target = Join-Path $dest ($f.Name + '.' + (New-PsKnRandomHex -Chars 8)) }
        try { [System.IO.File]::Move($f.FullName, $target); $n++ } catch { }
    }
    return $n
}

function Get-PsSuppChecklistRound {
    param([string]$DomainDir)
    $cl = Join-Path $DomainDir 'checklist.md'
    $t = Read-PsKnText -LiteralPath $cl
    if ($null -eq $t) { return -1 }
    $round = 0
    foreach ($m in [regex]::Matches($t, '(?m)稽核輪次[：:]\s*([0-9]+)')) { $round = [int]$m.Groups[1].Value }
    return $round
}

# 目標無 NN → 在 checklist「## 調查進度」末尾寫一列 D 列（去重：NN 檔／任何 D 列已有同物件即不寫）。回 @{ Added; Row; Reason }
function Add-PsSuppChecklistDRow {
    param([string]$DomainDir, [string]$ObjectName, [string]$RequestId)
    $cl = Join-Path $DomainDir 'checklist.md'
    $raw = [System.IO.File]::Exists($cl)
    if (-not $raw) { return @{ Added = $false; Row = ''; Reason = 'NO_CHECKLIST' } }
    $clBytes = [System.IO.File]::ReadAllBytes($cl)
    $hasBom = ($clBytes.Length -ge 3 -and $clBytes[0] -eq 0xEF -and $clBytes[1] -eq 0xBB -and $clBytes[2] -eq 0xBF)
    $rawText = [System.IO.File]::ReadAllText($cl)
    if ($rawText.Length -gt 0 -and [int]$rawText[0] -eq 0xFEFF) { $rawText = $rawText.Substring(1) }
    $canon = $ObjectName.Trim().ToLowerInvariant() -replace '^ps_', ''
    if ((Find-PsSuppTargetNn -DomainDir $DomainDir -TargetName $ObjectName).Count -gt 0) { return @{ Added = $false; Row = ''; Reason = 'NN_EXISTS' } }
    $dRow = '(?m)^\s*-\s*\[[ xX]\]\s*[Dd](\d+)-(\d+)\s[^\r\n]*?新發現\s+([^\s：:（(]+)'
    $maxSeq = @{}
    $texts = @($rawText)
    foreach ($af in @(Get-ChildItem -LiteralPath $DomainDir -Filter 'checklist-archive*.md' -File -ErrorAction SilentlyContinue)) { $t = Read-PsKnText -LiteralPath $af.FullName; if ($null -ne $t) { $texts += $t } }
    foreach ($t in $texts) {
        foreach ($m in [regex]::Matches($t, $dRow)) {
            $k = $m.Groups[3].Value.Trim().ToLowerInvariant() -replace '^ps_', ''
            if ($k -eq $canon) { return @{ Added = $false; Row = ''; Reason = 'D_EXISTS' } }
            $rnd = [int]$m.Groups[1].Value; $seq = [int]$m.Groups[2].Value
            if (-not $maxSeq.ContainsKey($rnd) -or $seq -gt $maxSeq[$rnd]) { $maxSeq[$rnd] = $seq }
        }
    }
    $round = Get-PsSuppChecklistRound -DomainDir $DomainDir
    if ($round -lt 0) { $round = 0 }
    $next = 1
    if ($maxSeq.ContainsKey($round)) { $next = $maxSeq[$round] + 1 }
    $row = ('- [ ] D' + $round + '-' + $next.ToString('00') + ' 新發現 ' + $ObjectName + '：補研究 ' + $RequestId + '（稽核）')
    $eol = "`n"
    if ($rawText.IndexOf("`r`n") -ge 0) { $eol = "`r`n" }
    $lines = @(($rawText -replace "`r", '') -split "`n")
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^##\s*調查進度') { $start = $i; break } }
    if ($start -lt 0) { $lines += ''; $lines += '## 調查進度'; $start = $lines.Count - 1 }
    $end = $lines.Count
    for ($i = $start + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^##\s') { $end = $i; break } }
    $ins = $end
    while ($ins -gt $start + 1 -and $lines[$ins - 1].Trim() -eq '') { $ins-- }
    $out = @()
    if ($ins -gt 0) { $out += $lines[0..($ins - 1)] }
    $out += $row
    if ($ins -lt $lines.Count) { $out += $lines[$ins..($lines.Count - 1)] }
    $ok = Write-PsKnAtomicText -LiteralPath $cl -Text ($out -join $eol) -Bom $hasBom
    if (-not $ok) { return @{ Added = $false; Row = $row; Reason = 'WRITE_DEFERRED' } }
    return @{ Added = $true; Row = $row; Reason = 'ADDED' }
}

# ── 狀態總覽（CLI -Status）────────────────────────────────────────

function Get-PsSuppStatus {
    param([string]$Root, [string]$Domain = '', $Capabilities = $null)
    $d = Get-PsSuppDirs -Root $Root
    $all = Get-PsSuppRequests -Root $Root -Capabilities $Capabilities
    $maxGenByKey = @{}
    foreach ($r in $all) { if (-not $maxGenByKey.ContainsKey($r.WorkKey) -or $r.Generation -gt $maxGenByKey[$r.WorkKey]) { $maxGenByKey[$r.WorkKey] = $r.Generation } }
    $out = @()
    foreach ($r in $all) {
        if ($Domain -ne '' -and $r.Domain -cne $Domain) { continue }
        $res = Get-PsSupplementalResult -Root $Root -RequestId $r.RequestId
        $state = ''
        $att = 0
        $domDir = Join-Path $d.Research $r.Domain
        if ($null -ne $res) { $state = [string]$res.outcome }
        elseif ($r.Generation -lt $maxGenByKey[$r.WorkKey]) { $state = 'SUPERSEDED_PENDING' }
        elseif (-not [System.IO.File]::Exists((Join-Path $domDir '00-overview.md'))) { $state = 'DOMAIN_MISSING' }
        else {
            $att = (Get-PsSuppAttempts -DomainDir $domDir -RequestId $r.RequestId).Count
            if ((Find-PsSuppTargetNn -DomainDir $domDir -TargetName ([string]$r.Obj.need.target.name)).Count -eq 0) { $state = 'WAITING_RESEARCH' }
            elseif ($att -ge 2) { $state = 'EXHAUSTED' }
            else { $state = 'PENDING' }
        }
        $out += , (@{ RequestId = $r.RequestId; Domain = $r.Domain; Generation = $r.Generation; State = $state; Attempts = $att; FactKind = [string]$r.Obj.need.factKind; Target = ([string]$r.Obj.need.target.type + ':' + [string]$r.Obj.need.target.name) })
    }
    return , $out
}
