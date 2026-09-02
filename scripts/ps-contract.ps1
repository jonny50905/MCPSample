# ps-contract.ps1 — Legacy Contract（issue #17 Phase 1）確定性外環 CLI
# 用法：.\scripts\ps-contract.ps1 -Domain 兵役 -Plan            # 抽 NN 事實、切單位（控制項依 -ControlPageSize 分頁）、寫 contract-parts/manifest.txt
#       .\scripts\ps-contract.ps1 -Domain 兵役 -All             # Accept → Merge → Render → Gate
#       .\scripts\ps-contract.ps1 -Domain 兵役 -Gate -Tier 2    # 只跑 gate（tier 2＝零 UNRESOLVED／NOT_RUN／BLOCKED debt）
#       .\scripts\ps-contract.ps1 -Domain 兵役 -VerifyPlan      # 寫 contract-parts/verify-manifest.txt（Oracle schema 驗證工單；currentSchema 未回填即拒產）
# 產物全部在 docs/ps-research/<領域>/contract-parts/ 與 contract/（子目錄：不進 lint 八節門檻、不進畢業 contentHash）。
# 模型側只寫 contract-parts/*.md（固定表格，見 .opencode/peoplesoft/legacy-contract-fragments.md）；
# ID／JSON／spec／判定／驗證結果全在本腳本與 ps-contract-lib.ps1。設計：docs/design/legacy-contract-phase1-decision-memo.md。
# 容量事件（同分批稽核 L107）：fragment >150 行或洩漏 → 該 Component 控制項頁大小對半（最小 10）、該 Component 全部 screen 檔重排；
# 不變量兩次未過（hash 有變）→ BLOCKED，-Plan 不再排入、-Gate 出 capacity debt。
# exit：0＝本次動作全過（-Gate：所選 tier 通過）／1＝有 INVALID／FAIL／未達 tier／2＝環境或參數錯誤
param(
    [Parameter(Mandatory = $true)][string]$Domain,
    [switch]$Plan,
    [switch]$Accept,
    [switch]$Merge,
    [switch]$Render,
    [switch]$Gate,
    [switch]$All,
    [switch]$VerifyPlan,
    [ValidateSet(1, 2)][int]$Tier = 1,
    [int]$BatchSize = 4,
    # 控制項表每檔欄位數上限（NN 畫面與欄位列數 > 此值即分頁成 screen-<COMP>-p<k>.md）；容量事件對半、最小 10
    [int]$ControlPageSize = 30,
    # Oracle 驗證 FLD 單位每委派欄位數
    [int]$VerifyFieldPageSize = 10,
    # 覆寫 customization-profile.yaml 的 oracle.currentSchema（測試用；空＝讀 profile）
    [string]$CurrentSchema = "",
    # 測試用：覆寫 repo 根（預設由 $PSScriptRoot 反推）
    [string]$Root = ""
)

# -Domain 消毒（同 ps-doc-lint L28）
$rawDomain = $Domain
$Domain = $Domain.Trim().TrimEnd('.', ' ')
if ($Domain -cne $rawDomain) { Write-Host "WARN：-Domain 參數頭尾含空白/點，已自動修剪" -ForegroundColor Yellow }
foreach ($ch in $Domain.ToCharArray()) {
    $cp = [int]$ch
    if ($cp -lt 32 -or $cp -eq 127 -or $cp -eq 0x00A0 -or ($cp -ge 0x200B -and $cp -le 0x200F) -or $cp -eq 0xFEFF) {
        Write-Error "-Domain 參數含隱形字元（字元碼 $cp）"; exit 2
    }
}

if ($Root -eq "") { $Root = Split-Path -Parent $PSScriptRoot }
$libPath = Join-Path $PSScriptRoot 'ps-contract-lib.ps1'
if (-not (Test-Path -LiteralPath $libPath)) { Write-Error "找不到 $libPath"; exit 2 }
. $libPath

$vocabPath = Join-Path $Root (Join-Path '.opencode' (Join-Path 'peoplesoft' 'legacy-contract-vocabulary.md'))
$profilePath = Join-Path $Root (Join-Path '.opencode' (Join-Path 'peoplesoft' 'customization-profile.yaml'))
if (-not (Test-Path -LiteralPath $vocabPath)) { Write-Error "找不到值域檔 $vocabPath"; exit 2 }
$dir = Join-Path $Root (Join-Path 'docs' (Join-Path 'ps-research' $Domain))
if (-not (Test-Path -LiteralPath $dir)) { Write-Error "領域目錄不存在：$dir"; exit 2 }
$partsDir = Join-Path $dir 'contract-parts'
$ctDir = Join-Path $dir 'contract'
$specDir = Join-Path $ctDir 'spec'
$ledgerPath = Join-Path $ctDir 'contract-ledger.json'
$contractPath = Join-Path $ctDir 'legacy-contract.json'
$gatePath = Join-Path $ctDir 'contract-gate.json'
$receiptPath = Join-Path $ctDir 'contract-receipt.json'
$approvalsPath = Join-Path $ctDir 'approvals.md'

if ($All) { $Accept = $true; $Merge = $true; $Render = $true; $Gate = $true }
if (-not ($Plan -or $Accept -or $Merge -or $Render -or $Gate -or $VerifyPlan)) { Write-Error "請指定 -Plan／-Accept／-Merge／-Render／-Gate／-All／-VerifyPlan 之一"; exit 2 }

$vocab = Get-CtVocabulary -LiteralPath $vocabPath
$nnFacts = @{}
foreach ($f in (Get-CtNnFiles -DomainDir $dir)) { $nnFacts[$f.Name] = Get-CtNnFacts -LiteralPath $f.FullName }
$schema = $CurrentSchema
if ($schema -eq "") { $schema = Get-CtCurrentSchema -ProfilePath $profilePath }
$schemaKnown = ($schema -ne "")
Write-Host "=== ps-contract：領域=$Domain NN=$($nnFacts.Count) 檔 vocabulary v$($vocab.Version) schema v$script:ContractSchemaVersion currentSchema=$(if ($schemaKnown) { '已設' } else { '未回填（verify 收據不採信）' }) ===" -ForegroundColor Cyan
$exitCode = 0
$ledger = Get-CtLedger -LiteralPath $ledgerPath
if (-not (Test-Path -LiteralPath $ctDir)) { New-Item -ItemType Directory -Path $ctDir -Force | Out-Null }
$units = @(Get-CtUnits -NnFactsMap $nnFacts -Ledger $ledger -DefaultPageSize $ControlPageSize)
$unitByFile = @{}
foreach ($u in $units) { $unitByFile[$u.File] = $u }

# ── -Plan：決定本批單位（無收據、NN 已變、或 INVALID 待重寫；BLOCKED 靠邊），寫 manifest ──
if ($Plan) {
    $pending = @()
    foreach ($u in $units) {
        $e = $null
        if ($ledger.fragments.Contains($u.File)) { $e = $ledger.fragments[$u.File] }
        $need = $true
        if ($null -ne $e) {
            if ($e.status -eq 'DONE' -and $e.nnHash -eq $u.NnHash) { $need = $false }
            if ($e.status -eq 'BLOCKED') { $need = $false; Write-Host "PLAN：$($u.File) BLOCKED（$($e.reason)）——出路＝拆 NN 續篇縮小單檔、或人工修好後刪 ledger 該項重排" -ForegroundColor Yellow }
        }
        if ($need) { $pending += , $u }
    }
    $batch = @($pending | Select-Object -First $BatchSize)
    if (-not (Test-Path -LiteralPath $partsDir)) { New-Item -ItemType Directory -Path $partsDir -Force | Out-Null }
    $mp = New-CtManifest -Domain $Domain -Units $batch -NnFactsMap $nnFacts -PartsDir $partsDir -K $BatchSize
    Write-Host "PLAN：單位 $($units.Count)（screen $(@($units | Where-Object { $_.Kind -eq 'screen' }).Count)／分頁 $(@($units | Where-Object { $_.Kind -eq 'screenpage' }).Count)／entity $(@($units | Where-Object { $_.Kind -eq 'entity' }).Count)）待寫 $($pending.Count) 本批 $($batch.Count) → $mp"
    foreach ($u in $batch) { Write-Host "PLAN_UNIT：$($u.Kind)｜$($u.Key)｜$($u.File)｜來源 $($u.SourceNn -join ';')$(if ($u.Kind -ne 'entity') { '｜控制項 ' + @($u.PageFields).Count + ' 欄（頁大小 ' + $u.PageSize + '）' })" }
    if ($batch.Count -eq 0) { Write-Host "PLAN：無待寫單位（全部有收據或 BLOCKED）" -ForegroundColor Green }
}

# ── -Accept：解析 fragment、驗不變量（含分頁覆蓋）、容量事件、寫收據 ────────────
$fragments = @()
if ($Accept -or $Merge -or $Render -or $Gate -or $VerifyPlan) {
    if (Test-Path -LiteralPath $partsDir) {
        foreach ($f in (Get-ChildItem -LiteralPath $partsDir -Filter '*.md' -File | Where-Object { $_.Name -match '^(screen|entity)-' } | Sort-Object Name)) {
            $kind = 'entity'
            if ($f.Name -match '^screen-.+-p\d+\.md$') { $kind = 'screenpage' } elseif ($f.Name -like 'screen-*') { $kind = 'screen' }
            $expected = @()
            if ($unitByFile.ContainsKey($f.Name)) { $expected = @($unitByFile[$f.Name].PageFields) }
            $fr = Read-CtFragment -LiteralPath $f.FullName -Kind $kind -Vocab $vocab -NnFactsMap $nnFacts -ExpectedFields $expected
            if (-not $unitByFile.ContainsKey($f.Name)) { $fr.Invalid += '不在單位清單內（NN 檔無此 Component／Record，或分頁已重切）' }
            $fragments += , $fr
        }
    }
    if ($Accept) {
        $done = 0; $invalid = 0; $blocked = 0
        $capacityComps = @{}
        foreach ($fr in $fragments) {
            $prev = $null
            if ($ledger.fragments.Contains($fr.File)) { $prev = $ledger.fragments[$fr.File] }
            $attempts = 0
            if ($null -ne $prev) { $attempts = [int]$prev.attempts }
            $nnHash = ''
            if ($unitByFile.ContainsKey($fr.File)) { $nnHash = $unitByFile[$fr.File].NnHash }
            $status = 'DONE'; $reason = ''
            if ($fr.Invalid.Count -gt 0) {
                $status = 'INVALID'; $reason = ($fr.Invalid | Select-Object -First 3) -join '；'
                if ($fr.CapacityEvent -and $fr.Component -ne '') {
                    # 容量事件：不記 attempts（不是內容錯），頁大小對半重切
                    $capacityComps[$fr.Component] = $true
                }
                elseif ($null -eq $prev -or $prev.hash -ne $fr.Hash) { $attempts++ }
                if ($attempts -ge 2) { $status = 'BLOCKED'; $blocked++ }
                $invalid++
                Write-Host "ACCEPT：$($fr.File) $status（attempts=$attempts$(if ($fr.CapacityEvent) { '，容量事件' })）——$reason" -ForegroundColor Red
                foreach ($iv in $fr.Invalid) { Write-Host "  !! $iv" -ForegroundColor Red }
            }
            else { $done++; $attempts = 0; Write-Host "ACCEPT：$($fr.File) DONE（$($fr.Lines) 行）" -ForegroundColor Green }
            $ledger.fragments[$fr.File] = [ordered]@{ kind = $fr.Kind; hash = $fr.Hash; status = $status; reason = $reason; attempts = $attempts; nnHash = $nnHash; lines = $fr.Lines }
        }
        foreach ($comp in $capacityComps.Keys) {
            $cur = $ControlPageSize
            if ($ledger.pageSizes.Contains($comp)) { $cur = [int]$ledger.pageSizes[$comp] }
            $new = [Math]::Max(10, [int][Math]::Floor($cur / 2))
            if ($new -lt $cur) {
                $ledger.pageSizes[$comp] = $new
                foreach ($k in @($ledger.fragments.Keys)) { if ($k -like "screen-$comp.md" -or $k -like "screen-$comp-p*.md") { $ledger.fragments[$k].status = 'PENDING'; $ledger.fragments[$k].reason = '容量事件重切' } }
                Write-Host "ACCEPT：容量事件——$comp 控制項頁大小 $cur → $new，該 Component 全部 screen 檔重排（-Plan 會重切分頁）" -ForegroundColor Yellow
            }
            else {
                foreach ($k in @($ledger.fragments.Keys)) { if ($k -like "screen-$comp.md" -or $k -like "screen-$comp-p*.md") { if ($ledger.fragments[$k].status -eq 'INVALID') { $ledger.fragments[$k].status = 'BLOCKED'; $ledger.fragments[$k].reason = '頁大小已到最小仍超容量'; $blocked++ } } }
                Write-Host "ACCEPT：$comp 頁大小已 $cur（最小）仍超容量——BLOCKED；出路＝拆 NN 續篇縮小單檔" -ForegroundColor Red
            }
        }
        Save-CtLedger -LiteralPath $ledgerPath -Ledger $ledger
        Write-Host "ACCEPT_SUMMARY：DONE=$done INVALID=$invalid BLOCKED=$blocked → $ledgerPath"
        if ($invalid -gt 0) { $exitCode = 1 }
    }
}

# ── -Merge：收據 DONE 的 fragment → canonical JSON（verify 收據只在 currentSchema 已知時採信） ──
$contract = $null
$accepted = @($fragments | Where-Object { $_.Invalid.Count -eq 0 })
if ($Merge) {
    $approvals = @(Read-CtApprovals -LiteralPath $approvalsPath)
    # 先做一次不含收據的 merge 取得實體與 RQ（verify 單位由 canonical 決定），再讀收據蓋章
    $draft = Merge-CtContract -Domain $Domain -Fragments $accepted -NnFactsMap $nnFacts -Approvals $approvals -VerifyReceipts @{} -Vocab $vocab -SchemaKnown $false
    $verify = @{}
    if ($schemaKnown) { $verify = Read-CtVerifyReceipts -PartsDir $partsDir -Vocab $vocab -Contract $draft -FieldPageSize $VerifyFieldPageSize }
    foreach ($rec in $verify.Keys) { foreach ($uf in $verify[$rec].Units.Keys) { $u = $verify[$rec].Units[$uf]; if ($u.Invalid.Count -gt 0) { Write-Host "VERIFY：$uf 收據無效——$($u.Invalid[0])" -ForegroundColor Yellow } elseif ($u.State -ne 'PASS' -and $u.Reason -ne '無收據') { Write-Host "VERIFY：$uf $($u.State)——$($u.Reason)" -ForegroundColor $(if ($u.State -eq 'FAIL') { 'Red' } else { 'Yellow' }) } } }
    $contract = Merge-CtContract -Domain $Domain -Fragments $accepted -NnFactsMap $nnFacts -Approvals $approvals -VerifyReceipts $verify -Vocab $vocab -SchemaKnown $schemaKnown
    Write-CtText -LiteralPath $contractPath -Text (ConvertTo-CtJson -Value $contract)
    Write-Host "MERGE：screens=$($contract.screens.Count) entities=$($contract.dataEntities.Count) 未解析引用=$($contract.unresolvedReferences.Count) → $contractPath"
    foreach ($u in $contract.unresolvedReferences) { Write-Host "  ?? $u" -ForegroundColor Yellow }
    # Render／Gate 一律吃「磁碟上的 JSON」（單一真相）——記憶體物件與反序列化物件的形狀差異
    # 不得影響 render 結果，否則 G18 parity 會在下一次獨立 -Gate 時假 FAIL
    $contract = Read-CtJsonFile -LiteralPath $contractPath
    if ($null -eq $contract) { Write-Error "寫入後無法回讀 $contractPath"; exit 2 }
}
elseif ($Render -or $Gate -or $VerifyPlan) {
    $contract = Read-CtJsonFile -LiteralPath $contractPath
    if ($null -eq $contract) { Write-Error "找不到或無法解析 $contractPath（先跑 -Merge）"; exit 2 }
}

# ── -Render：spec/*.spec.md ────────────────────────────────────────────────
if ($Render) {
    if (-not (Test-Path -LiteralPath $specDir)) { New-Item -ItemType Directory -Path $specDir -Force | Out-Null }
    foreach ($s in $contract.screens) {
        $p = Join-Path $specDir ($s.component + '.spec.md')
        Write-CtText -LiteralPath $p -Text (ConvertTo-CtSpec -Contract $contract -Screen $s) -Bom
    }
    Write-CtText -LiteralPath (Join-Path $specDir 'index.spec.md') -Text (ConvertTo-CtSpecIndex -Contract $contract) -Bom
    foreach ($f in (Get-ChildItem -LiteralPath $specDir -Filter '*.spec.md' -File)) {
        $comp = $f.Name -replace '\.spec\.md$', ''
        if ($comp -ne 'index' -and @($contract.screens | Where-Object { $_.component -eq $comp }).Count -eq 0) { Remove-Item -LiteralPath $f.FullName -Force }
    }
    Write-Host "RENDER：$($contract.screens.Count) 個 spec＋index → $specDir"
}

# ── -VerifyPlan：Oracle schema 驗證工單（一單位一委派） ───────────────────────
if ($VerifyPlan) {
    if (-not $schemaKnown) {
        Write-Host "VERIFY_PLAN：currentSchema=FILL_ME，不產工單——先回填 .opencode/peoplesoft/customization-profile.yaml 的 oracle.currentSchema（或以 -CurrentSchema 覆寫）" -ForegroundColor Red
        exit 2
    }
    $verify = Read-CtVerifyReceipts -PartsDir $partsDir -Vocab $vocab -Contract $contract -FieldPageSize $VerifyFieldPageSize
    $vm = New-CtVerifyManifest -Domain $Domain -Contract $contract -PartsDir $partsDir -FieldPageSize $VerifyFieldPageSize -Receipts $verify
    Write-Host "VERIFY_PLAN：待驗 $($vm.Todo)／共 $($vm.Total) 單位 → $($vm.Path)"
}

# ── -Gate：G1～G18＋收據 ───────────────────────────────────────────────────
if ($Gate) {
    # 獨立 -Gate 吃的是磁碟 JSON：若 contract-parts 已比 JSON 新（hash 不同或現在驗不過），只警告不改判定——重合併請用 -All
    if (-not $Merge) {
        $stale = @()
        $fragByFile = @{}
        foreach ($fr in $fragments) { $fragByFile[$fr.File] = $fr }
        foreach ($o in (@($contract.screens) + @($contract.dataEntities))) {
            $ff = $o.fragment.file
            if (-not $fragByFile.ContainsKey($ff)) { $stale += "$ff（檔已不存在）"; continue }
            if ($fragByFile[$ff].Hash -ne $o.fragment.hash) { $stale += "$ff（hash 已變）" } elseif ($fragByFile[$ff].Invalid.Count -gt 0) { $stale += "$ff（現驗 INVALID）" }
        }
        if ($stale.Count -gt 0) { Write-Host "GATE_WARN：legacy-contract.json 早於 contract-parts（$($stale -join '、')）——本次判定以磁碟 JSON 為準，重合併請用 -All" -ForegroundColor Yellow }
    }
    $res = Test-CtGates -Contract $contract -NnFactsMap $nnFacts -Ledger $ledger -Fragments $fragments -Vocab $vocab -SpecDir $specDir -ApprovalsPath $approvalsPath
    foreach ($r in $res.gates) {
        $color = 'Green'
        if ($r.state -eq 'FAIL') { $color = 'Red' } elseif ($r.state -eq 'UNRESOLVED') { $color = 'Yellow' } elseif ($r.state -eq 'NOT_APPLICABLE') { $color = 'DarkGray' }
        Write-Host ("GATE：{0}={1}｜{2}/{3}｜{4}" -f $r.gate, $r.state, $r.numerator, $r.denominator, $r.note) -ForegroundColor $color
    }
    foreach ($d in $res.debts) { Write-Host "DEBT：$d" -ForegroundColor DarkYellow }
    Write-Host "GATE_SUMMARY：tier1=$($res.tier1) tier2=$($res.tier2) debts=$($res.debts.Count)"
    $gateDoc = [ordered]@{ schemaVersion = $script:ContractSchemaVersion; domain = $Domain; tier1 = $res.tier1; tier2 = $res.tier2; gates = $res.gates; debts = $res.debts }
    Write-CtText -LiteralPath $gatePath -Text (ConvertTo-CtJson -Value $gateDoc)
    $receipt = [ordered]@{
        schemaVersion = $script:ContractSchemaVersion; vocabularyVersion = $vocab.Version; domain = $Domain
        gatedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK'); tier1 = $res.tier1; tier2 = $res.tier2
        contractHash = (Get-CtFileHash -LiteralPath $contractPath); vocabularyHash = (Get-CtFileHash -LiteralPath $vocabPath)
        libHash = (Get-CtFileHash -LiteralPath $libPath); cliHash = (Get-CtFileHash -LiteralPath $PSCommandPath)
    }
    Write-CtText -LiteralPath $receiptPath -Text (ConvertTo-CtJson -Value $receipt)
    $pass = $res.tier1
    if ($Tier -eq 2) { $pass = $res.tier2 }
    if ($pass) { Write-Host "PASS：contract tier $Tier" -ForegroundColor Green } else { Write-Host "FAIL：contract tier $Tier 未達" -ForegroundColor Red; $exitCode = 1 }
}

exit $exitCode
