# scripts/tests/test-supplemental.ps1 — 補研究協定（ps-supplemental-lib／ps-supplemental CLI）的功能測試
# 用法：pwsh -NoProfile -File scripts/tests/test-supplemental.ps1   （PowerShell 7 或 5.1 皆可；不需 opencode）
# 範圍：合成 fixtures（臨時目錄，結束自刪；無公司資料）：need 驗證負例、workKey／requestId 確定性、同 need 並行提交只一檔、
#       路由三態（hint／索引／掃描／多候選／零候選）、-Resubmit 世代與 SUPERSEDED、工單內容（節位、callee、無 consumer／[[）、
#       收據驗收負例、確定性合併（條列／表格／文字節、附錄編號承接、缺節插入、CRLF＋BOM 保留、冪等）、還原、
#       attempts 由工單檔推導、目標無 NN → checklist D 列、result create-only 冪等、wiki stale／reviewed 標記、
#       完成邊界（RESEARCHED／AUDITED）、CLI exit 與結論碼形狀。
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ErrorActionPreference = 'Stop'
. (Join-Path $repoRoot 'scripts/ps-knowledge-lib.ps1')
. (Join-Path $repoRoot 'scripts/ps-supplemental-lib.ps1')
$cli = Join-Path $repoRoot 'scripts/ps-supplemental.ps1'

$failCount = 0
function Assert([bool]$Cond, [string]$Name) {
    if ($Cond) { Write-Host "  PASS：$Name" }
    else { Write-Host "  FAIL：$Name" -ForegroundColor Red; $script:failCount++ }
}
function Write-Utf8([string]$Path, [string[]]$Lines, [bool]$Bom, [string]$Eol = "`n") {
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, ($Lines -join $Eol), (New-Object System.Text.UTF8Encoding($Bom)))
}
function Invoke-Cli([string[]]$CliArgs) {
    # 同行程呼叫（& script）：exit 碼進 $LASTEXITCODE、Write-Host 走 information stream 以 [string] 取字；
    # 不開子行程＝不受公司機執行原則（ExecutionPolicy）與主控台編碼影響，也不會被 Out-String 折行
    # 陣列 splat 對 script 一律走位置繫結、不辨識 '-Name'（與外部程序命令列剖析不同）；
    # 先轉成雜湊表再 splat，讓 -New 等 switch／具名參數正確繫結到 CLI 的 param()
    $h = @{}
    $i = 0
    while ($i -lt $CliArgs.Count) {
        $name = $CliArgs[$i] -replace '^-', ''
        if (($i + 1) -lt $CliArgs.Count -and $CliArgs[$i + 1] -notmatch '^-') {
            $h[$name] = $CliArgs[$i + 1]; $i += 2
        } else {
            $h[$name] = $true; $i += 1
        }
    }
    $out = @(& $cli @h -Root $root *>&1 | ForEach-Object { [string]$_ })
    $last = ''
    if ($out.Count -gt 0) { $last = [string]$out[$out.Count - 1] }
    return @{ Exit = $LASTEXITCODE; Lines = @($out); Last = $last }
}
function Test-CodeShape([string]$Line, [string]$Family) {
    $code = $Line -replace '^結論代號：', ''
    if ($code -notmatch ('^' + $Family + '1-\d-\d\d(-\d+)?$')) { return $false }
    if ($code -match '/|\.md|TW_|[\u4e00-\u9fff]') { return $false }
    return $true
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('supp-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$research = Join-Path $root 'docs/ps-research'
$domA = Join-Path $research '職缺測試'
$wiki = Join-Path $research 'wiki'
$logs = Join-Path $root 'auto-loop-logs'
New-Item -ItemType Directory -Path (Join-Path $root '.opencode/peoplesoft/spec') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot '.opencode/peoplesoft/spec/capabilities.json') -Destination (Join-Path $root '.opencode/peoplesoft/spec/capabilities.json')
$uuid1 = '3f2a9c1e-7b4d-4e8a-9c6f-1d2e3a4b5c6d'
$uuid2 = '9b2f5c1e-4a3d-4f0a-8f21-7e5d0c9a1b2c'
$cap = Get-PsSuppCapabilities -Root $root

function New-NnLines([string]$Num, [string]$Obj, [string[]]$Related, [bool]$DropPermission = $false) {
    $l = @(
        "# $Num 功能$Obj（[[$Obj]]）",
        '',
        '> 所屬總覽：[00-overview.md](00-overview.md)　狀態：COMPLETE',
        '> Origin：CUSTOM_PREFIX　搜尋政策：CUSTOM_FIRST　Delivered fallback：未使用',
        '',
        '## 相關物件',
        '',
        '| 物件 | 角色 |',
        '|---|---|',
        "| [[$Obj]] | 主 Component |"
    )
    $l += $Related
    $l += @(
        '',
        '## 功能定位',
        '',
        '誰在用、業務目的。',
        '',
        '### 導覽入口',
        '',
        'Portal Registry 導覽入口：未確認（navigation metadata 尚未查證）',
        '',
        '### Technical Menu',
        '',
        'MENU_A / USE / ITEM_A',
        '',
        '## 畫面與欄位',
        '',
        '| 欄位 | 顯示文字 | 類型 | 選項（label ↔ 儲存值） | 生命狀態 |',
        '|---|---|---|---|---|',
        '| DEMO_STATUS | 狀態 | Translate | 免役=E / 服役中=S | E：使用中（資料 3 筆） |',
        '',
        '## 行為邏輯',
        '',
        '- **CONFIRMED**：選 E 時開放原因並帶入日期（`a.pcode:12`）',
        '- **INFERRED**：核准後回寫',
        '',
        '## 資料流',
        '',
        '| 表 | 操作 | 來源 | 信心 |',
        '|---|---|---|---|',
        '| PS_DEMO_TBL | UPDATE | 存檔 PeopleCode | CONFIRMED |',
        '',
        '## 執行方式',
        '',
        '線上操作。'
    )
    if (-not $DropPermission) { $l += @('', '## 權限', '', '<!-- 無 -->') }
    $l += @(
        '',
        '## 未解事項（gaps）',
        '',
        '- 缺一',
        '',
        '## Evidence 附錄',
        '',
        '| # | 位置 | 說明 | 機器參照 |',
        '|---|---|---|---|',
        "| 1 | ``a.pcode:12-24`` | E 分支 | ChunkId ``$uuid1`` |",
        '| 2 | SQL：`SELECT X FROM PSXLATITEM` | 選項 | keyRows：E=免役 |',
        '| 3 | `PS_PRCSRECUR` | 排程 | 待人工SQL |'
    )
    return , $l
}
function Write-Fixture {
    Write-Utf8 (Join-Path $domA '01-TW_DEMO_A.md') (New-NnLines '01' 'TW_DEMO_A' @('| [[PS_DEMO_TBL]] | 讀取來源 |', '| [[TWSQR_DEMO]] | 排程執行 |') $true) $false
    Write-Utf8 (Join-Path $domA '02-TWSQR_DEMO.md') (New-NnLines '02' 'TWSQR_DEMO' @('| `PS_DEMO_STG` | 寫入目標 |')) $false
    Write-Utf8 (Join-Path $domA '00-overview.md') @('# 職缺測試 業務總覽', '', '## 功能地圖', '', '| # | 功能 | Component / 物件 | 類型 | Origin | 一句話說明 |', '|---|---|---|---|---|---|', '| 01 | 功能甲 | [[TW_DEMO_A]] | 線上頁面 | CUSTOM_PREFIX | 說明 |', '| 02 | 批次乙 | [[TWSQR_DEMO]] | 批次 | CUSTOM_PREFIX | 說明 |') $false
    Write-Utf8 (Join-Path $domA 'checklist.md') @('# 職缺測試 調查進度', '', '稽核輪次：2', '', '## 調查進度', '', '- [x] 01 功能甲 `TW_DEMO_A` → 01-TW_DEMO_A.md', '- [x] 02 批次乙 `TWSQR_DEMO` → 02-TWSQR_DEMO.md', '- [ ] 03 功能丙 `TW_DEMO_C` → 03-TW_DEMO_C.md', '', '## Gaps 彙整（隨深查更新）', '', '- x') $true "`r`n"
    Write-Utf8 (Join-Path $domA 'checklist-archive-r1.md') @('# 歸檔 r1', '', '- [x] D1-03 新發現 TW_DEMO_OLD：任務C（稽核）') $false
    Write-Utf8 (Join-Path $wiki 'TW_DEMO_A.md') @('---', 'aliases: [功能甲]', 'type: COMPONENT', 'origin: CUSTOM_PREFIX', 'status: draft', 'confidence: 0.6', 'last_verified: 2026-09-01', "sources: [$uuid1]", 'reviewed: false', '---', '# TW_DEMO_A', '', '## Observations', '', '- [結構] 事實一', '', '## Relations', '', '- part_of [[職缺測試]]') $false
    Write-Utf8 (Join-Path $wiki 'PS_DEMO_TBL.md') @('---', 'aliases: [示範表]', 'type: RECORD', 'origin: CUSTOM_PREFIX', 'status: verified', 'confidence: 0.9', 'last_verified: 2026-09-10', "sources: [$uuid2]", 'reviewed: true', '---', '# PS_DEMO_TBL', '', '## Observations', '', '- [結構] x', '', '## Invalidated（作廢紀錄——只追加，不刪除）', '', '- 舊事實') $false
    Write-Utf8 (Join-Path $wiki 'TWSQR_DEMO.md') @('---', 'aliases: []', 'type: SQR', 'origin: CUSTOM_PREFIX', 'status: draft', 'confidence: 0.5', 'last_verified: 2026-09-01', 'sources: []', 'reviewed: false', '---', '# TWSQR_DEMO', '', '## Observations', '', '- [排程] 每日') $false
    Write-Utf8 (Join-Path $wiki 'index.md') @('# Entity Wiki 索引', '', '- [[TW_DEMO_A]]') $false
}
Write-Fixture
$null = Publish-PsKnowledgeIndex -Root $root -LogRoot $logs
$index = Read-PsKnowledgeIndex -Root $root

# ── 情境 1：need 驗證與正規化、workKey 確定性 ─────────────────────
Write-Host "情境 1：need 驗證負例、正規化、workKey／requestId 確定性"
$bad = ConvertTo-PsSuppNeed -Target 'WIDGET:tw x' -FactKind 'NOPE' -Properties '' -Context 'foo=1;operation=BOGUS' -EvidencePolicy 'X' -Freshness 'Y'
$vb = Test-PsSuppNeed -Need $bad -Capabilities $cap
Assert ((-not $vb.Ok) -and $vb.Errors.Count -eq 8) "負例：型別／物件名文法／factKind／properties 空／未知 context 鍵／context 值域／evidencePolicy／freshness 各一條（共 8）"
$bad2 = ConvertTo-PsSuppNeed -Target 'COMPONENT:TW_DEMO_A' -FactKind 'DATA.FILE_INPUT' -Properties 'present,nope' -EvidencePolicy 'AUDITED'
$vb2 = Test-PsSuppNeed -Need $bad2 -Capabilities $cap
Assert ((-not $vb2.Ok) -and $vb2.Errors.Count -eq 1 -and $vb2.Errors[0] -match 'nope') "負例：property 不在該 factKind 目錄"
$bad3 = [ordered]@{ target = [ordered]@{ type = 'COMPONENT'; name = 'TW_DEMO_A' }; context = [ordered]@{}; factKind = 'DATA.FLOW'; properties = @('reads'); evidencePolicy = 'ANY'; freshness = 'CURRENT'; extra = 1 }
Assert (-not (Test-PsSuppNeed -Need $bad3 -Capabilities $cap).Ok) "負例：未知欄位拒收"
$n1 = ConvertTo-PsSuppNeed -Target 'component:tw_demo_a' -FactKind 'DATA.FILE_INPUT' -Properties 'layout,present,present' -Context 'operation=import' -EvidencePolicy 'audited' -Freshness 'current'
$v1 = Test-PsSuppNeed -Need $n1 -Capabilities $cap
Assert ($v1.Ok -and $v1.Need.target.name -eq 'TW_DEMO_A' -and (@($v1.Need.properties) -join ',') -eq 'layout,present' -and $v1.Need.context['operation'] -eq 'IMPORT') "正規化：大寫、properties 去重 Ordinal 排序、context 值大寫"
$n2 = ConvertTo-PsSuppNeed -Target 'COMPONENT:TW_DEMO_A' -FactKind 'DATA.FILE_INPUT' -Properties 'present,layout' -Context 'operation=IMPORT' -EvidencePolicy 'AUDITED' -Freshness 'CURRENT'
$wk1 = Get-PsSuppWorkKey -Need $v1.Need
$wk2 = Get-PsSuppWorkKey -Need (Test-PsSuppNeed -Need $n2 -Capabilities $cap).Need
Assert ($wk1 -ceq $wk2 -and $wk1 -match '^[0-9A-F]{64}$') "workKey：同 need 不同寫法 → 同一 SHA256"
$rid1 = Get-PsSuppRequestId -WorkKey $wk1 -Generation 1
Assert ($rid1 -match $PsSuppRequestIdRx -and $rid1 -eq ('S-' + $wk1.Substring(0, 24).ToLowerInvariant() + '-g1')) "requestId 文法 ^S-[0-9a-f]{24}-g\d+$"
$vc = Test-PsSuppConsumer -Consumer @{ kind = 'SPEC'; jobId = 'demo-job'; requirementRef = '' }
Assert ((-not $vc.Ok) -and $vc.Errors[0] -match 'SPEC') "consumer：SPEC 缺 requirementRef → 拒"
Assert ((Test-PsSuppConsumer -Consumer @{ kind = 'spec'; jobId = 'Bad_Job'; requirementRef = 'R17' }).Errors.Count -eq 1) "consumer：jobId 大寫底線不符文法"
Assert ((Test-PsSuppConsumer -Consumer $null).Ok -and (Test-PsSuppConsumer -Consumer $null).Consumer.kind -eq 'MANUAL') "consumer：省略＝MANUAL"

# ── 情境 2：提交、去重、並行、路由 ────────────────────────────────
Write-Host "情境 2：Submit（CREATED／PENDING／RACE）、路由（INDEX／HINT／BAD_HINT／NONE／MULTI）"
$s1 = Submit-PsSupplementalRequest -Root $root -Need $n1 -Consumer @{ kind = 'QA' }
Assert ($s1.state -eq 'CREATED' -and $s1.created -and $s1.domain -eq '職缺測試' -and $s1.reason -eq 'INDEX' -and (Test-Path -LiteralPath $s1.path)) "第一次提交 → CREATED、路由 INDEX（主物件所在領域）"
$reqObj = Read-PsSuppJsonFile -LiteralPath $s1.path
Assert ($reqObj.schemaVersion -eq 1 -and $reqObj.requestId -eq $rid1 -and $reqObj.generation -eq 1 -and $reqObj.consumer.kind -eq 'QA' -and $reqObj.need.target.name -eq 'TW_DEMO_A' -and $reqObj.workKey -ceq $wk1) "request 檔：schemaVersion／requestId／generation／consumer／need／workKey"
$rawReq = Read-PsKnText -LiteralPath $s1.path
Assert ($rawReq -notmatch '\r' -and $rawReq.EndsWith("`n") -and $rawReq -match '"createdAt": "\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ"') "request 檔：LF、UTC 時間戳"
$s2 = Submit-PsSupplementalRequest -Root $root -Need $n2 -Consumer @{ kind = 'MANUAL' }
Assert ($s2.state -eq 'PENDING' -and -not $s2.created -and $s2.requestId -eq $rid1 -and $s2.reason -eq 'EXISTS') "同 need 再提交 → PENDING、同 requestId、不建檔"
Assert ($s2.state -eq 'PENDING' -and (Submit-PsSupplementalRequest -Root $root -Need $n2 -Resubmit).state -eq 'PENDING') "-Resubmit 但既有尚未終局 → 仍 PENDING（不建新世代）"
# 並行：4 個行程對同一 need 提交（不同 factKind 情境避免與上面撞）
$jobs = @()
for ($i = 0; $i -lt 4; $i++) {
    $jobs += Start-Job -ScriptBlock {
        param($RepoRoot, $Root)
        . (Join-Path $RepoRoot 'scripts/ps-knowledge-lib.ps1')
        . (Join-Path $RepoRoot 'scripts/ps-supplemental-lib.ps1')
        $n = ConvertTo-PsSuppNeed -Target 'COMPONENT:TW_DEMO_A' -FactKind 'SECURITY.ACCESS' -Properties 'roles' -EvidencePolicy 'ANY'
        $r = Submit-PsSupplementalRequest -Root $Root -Need $n
        return ($r.requestId + '|' + $r.state + '|' + $r.reason)
    } -ArgumentList $repoRoot, $root
}
$jr = @($jobs | Wait-Job -Timeout 120 | Receive-Job)
$jobs | Remove-Job -Force -ErrorAction SilentlyContinue
$ids = @($jr | ForEach-Object { ([string]$_ -split '\|')[0] } | Sort-Object -Unique)
$createdN = @($jr | Where-Object { ([string]$_ -split '\|')[1] -eq 'CREATED' }).Count
$reqFiles = @(Get-ChildItem -LiteralPath (Join-Path $research 'supplemental/requests') -Filter '*.json')
Assert ($jr.Count -eq 4 -and $ids.Count -eq 1 -and $createdN -eq 1 -and $reqFiles.Count -eq 2) "並行 4 次同 need 提交：只一個 CREATED、其餘 PENDING、requestId 相同、檔案只多一個"
$sec = Submit-PsSupplementalRequest -Root $root -Need (ConvertTo-PsSuppNeed -Target 'COMPONENT:TW_DEMO_A' -FactKind 'SECURITY.ACCESS' -Properties 'roles' -EvidencePolicy 'ANY')
$ridSec = $sec.requestId
# 路由
$r1 = Resolve-PsSuppDomain -Root $root -TargetName 'TW_DEMO_A' -DomainHint 'nope'
Assert ($r1.Domain -eq '' -and $r1.Reason -eq 'BAD_HINT') "路由：-DomainHint 的領域沒有 00-overview → BAD_HINT"
$r2 = Resolve-PsSuppDomain -Root $root -TargetName 'TW_NOWHERE'
Assert ($r2.Domain -eq '' -and $r2.Reason -eq 'NONE') "路由：任何領域都沒 NN → NONE"
$s3 = Submit-PsSupplementalRequest -Root $root -Need (ConvertTo-PsSuppNeed -Target 'COMPONENT:TW_NOWHERE' -FactKind 'DATA.FLOW' -Properties 'reads')
Assert ($s3.state -eq 'ROUTING_REQUIRED' -and $s3.requestId -eq '' -and $reqFiles.Count -eq @(Get-ChildItem -LiteralPath (Join-Path $research 'supplemental/requests') -Filter '*.json').Count) "零候選且無 hint → ROUTING_REQUIRED、不建檔"
$s4 = Submit-PsSupplementalRequest -Root $root -Need (ConvertTo-PsSuppNeed -Target 'COMPONENT:TW_NOWHERE' -FactKind 'DATA.FLOW' -Properties 'reads') -DomainHint '職缺測試'
Assert ($s4.state -eq 'CREATED' -and $s4.domain -eq '職缺測試' -and $s4.reason -eq 'HINT') "零候選但有 hint → CREATED（WAITING_RESEARCH 候選）"
$ridNowhere = $s4.requestId
Write-Utf8 (Join-Path (Join-Path $research 'aa-b') '01-TW_DEMO_A.md') (New-NnLines '01' 'TW_DEMO_A' @()) $false
Write-Utf8 (Join-Path (Join-Path $research 'aa-b') '00-overview.md') @('# aa-b 總覽', '', '## 功能地圖', '', '| # | 功能 | Component / 物件 | 類型 | Origin | 一句話說明 |', '|---|---|---|---|---|---|') $false
$null = Publish-PsKnowledgeIndex -Root $root -LogRoot $logs
$r3 = Resolve-PsSuppDomain -Root $root -TargetName 'TW_DEMO_A'
Assert ($r3.Reason -eq 'MULTI' -and $r3.Domain -eq 'aa-b' -and $r3.Candidates.Count -eq 2) "路由：兩領域都有主物件 NN → MULTI、取 Ordinal 最小"
Remove-Item -LiteralPath (Join-Path $research 'aa-b') -Recurse -Force
Remove-Item -LiteralPath (Join-Path $research 'knowledge') -Recurse -Force
$r4 = Resolve-PsSuppDomain -Root $root -TargetName 'TW_DEMO_A'
Assert ($r4.Reason -eq 'SCAN' -and $r4.Domain -eq '職缺測試') "路由：索引不存在 → 目錄掃描退路"
$null = Publish-PsKnowledgeIndex -Root $root -LogRoot $logs
$index = Read-PsKnowledgeIndex -Root $root

# ── 情境 3：工單 ──────────────────────────────────────────────────
Write-Host "情境 3：工單（節位／callee 一跳／無消費端識別／create-only）"
$req1 = Get-PsSuppRequest -Root $root -RequestId $rid1
$mf = New-PsSuppManifest -Root $root -Request $req1 -Domain '職缺測試' -DomainDir $domA -AttemptNo 1 -Index $index -Capabilities $cap
$mfText = Read-PsKnText -LiteralPath $mf.ManifestPath
$facts1 = Get-PsKnNnFacts -LiteralPath (Join-Path $domA '01-TW_DEMO_A.md') -Domain '職缺測試'
$bh = Get-PsKnSectionRange -Sections $facts1.sections -Name '行為邏輯'
Assert ($mf.Created -and (Test-Path -LiteralPath $mf.CurrentPath) -and ((Read-PsKnText -LiteralPath $mf.CurrentPath) -ceq $mfText)) "工單檔＋current.manifest.md 內容相同"
Assert ($mfText -match ('\| docs/ps-research/職缺測試/01-TW_DEMO_A\.md \| 行為邏輯 \| ' + $bh.start + ' \| ' + ([int]$bh.end - [int]$bh.start + 1) + ' \|')) "工單：目標 NN 的節 offset／limit 與解析一致"
Assert ($mfText -match '\| docs/ps-research/職缺測試/01-TW_DEMO_A\.md \| 資料流 \|' -and $mfText -match '\| docs/ps-research/職缺測試/01-TW_DEMO_A\.md \| 執行方式 \|' -and $mfText -match '\| docs/ps-research/職缺測試/01-TW_DEMO_A\.md \| Evidence 附錄 \|' -and $mfText -notmatch '\| Evidence附錄 \|') "工單：DATA.FILE_INPUT 的三節＋Evidence 附錄都列（節名用實際標題名，worker 才對得上）"
Assert ($mfText -match '02-TWSQR_DEMO\.md \| 執行方式（callee SQR，角色 排程執行） \|' -and $mf.CalleeFiles.Count -eq 1) "工單：follow 一跳 callee（角色排程、索引型別 SQR）的執行方式／資料流節"
Assert ($mfText -notmatch '\[\[' -and $mfText -notmatch 'consumer' -and $mfText -notmatch 'requirementRef' -and $mfText -notmatch 'jobId' -and $mfText -match 'operation=IMPORT' -and $mfText -match '要補的屬性：layout、present') "工單：不含 [[／consumer／requirementRef／jobId；含情境與屬性"
Assert ($mfText -match ('唯一可寫：docs/ps-research/職缺測試/supplemental-parts/' + [regex]::Escape($rid1) + '\.a1\.md')) "工單：唯一可寫的收據路徑"
$mfDup = New-PsSuppManifest -Root $root -Request $req1 -Domain '職缺測試' -DomainDir $domA -AttemptNo 1 -Index $index -Capabilities $cap
Assert (-not $mfDup.Created) "工單：同 attempt 再建 → create-only 拒絕"
$reqSec = Get-PsSuppRequest -Root $root -RequestId $ridSec
$mfSec = New-PsSuppManifest -Root $root -Request $reqSec -Domain '職缺測試' -DomainDir $domA -AttemptNo 1 -Index $index -Capabilities $cap
Assert ((Read-PsKnText -LiteralPath $mfSec.ManifestPath) -match '\| 權限 \| @缺 \| 0 \|' -and $mfSec.CalleeFiles.Count -eq 0) "工單：目標缺「權限」節寫 @缺；SECURITY.ACCESS 不 follow"

# ── 情境 4：收據驗收負例 ──────────────────────────────────────────
Write-Host "情境 4：收據驗收（缺表／處置／證據#／[[／洩漏／識別字樣／分格／CONFIRMED 無證據／行數／圍欄）"
$partsDir = Join-Path $domA 'supplemental-parts'
function New-ReceiptLines([string]$Disp, [string[]]$Facts, [string[]]$Evidence) {
    $l = @('## 處置', '| 處置 | 查法收據 |', '|---|---|', "| $Disp | ps-peoplecode-flow 搜 3 chunk |", '', '## 追加事實', '| 節 | 信心 | 敘述 | 證據# |', '|---|---|---|---|')
    $l += $Facts
    $l += @('', '## 追加證據', '| 位置 | 說明 | 機器參照 |', '|---|---|---|')
    $l += $Evidence
    return , $l
}
$ev2 = @("| ``a.pcode:40-58`` | File 讀取 | ChunkId ``$uuid2`` |", '| `sqr/x.sqr:1` | INSERT | SELECT 1 FROM DUAL |')
$rc = Join-Path $partsDir 'rc.md'
Write-Utf8 $rc (New-ReceiptLines 'RESEARCHED' @('| 行為邏輯 | CONFIRMED | 匯入時逐列讀取 CSV | 1 |') $ev2) $false
$ok = Test-PsSuppReceipt -LiteralPath $rc -Capabilities $cap
Assert ($ok.Ok -and $ok.Disposition -eq 'RESEARCHED' -and $ok.Facts.Count -eq 1 -and $ok.Evidence.Count -eq 2 -and $ok.Facts[0].EvidenceRefs[0] -eq 1) "合格收據：三表齊、處置、事實、證據"
Write-Utf8 $rc @('## 處置', '| 處置 | 查法收據 |', '|---|---|', '| RESEARCHED | x |', '', '## 追加證據', '| 位置 | 說明 | 機器參照 |', '|---|---|---|') $false
$t = Test-PsSuppReceipt -LiteralPath $rc -Capabilities $cap
Assert ((-not $t.Ok) -and ($t.Errors -join ';') -match '缺章節「## 追加事實」') "負例：缺追加事實表"
Write-Utf8 $rc (New-ReceiptLines 'DONE' @() @()) $false
Assert (($t = Test-PsSuppReceipt -LiteralPath $rc -Capabilities $cap) -and (-not $t.Ok) -and ($t.Errors -join ';') -match '處置不在值域') "負例：處置不在值域"
Write-Utf8 $rc (New-ReceiptLines 'RESEARCHED' @('| 行為邏輯 | CONFIRMED | x | 3 |') $ev2) $false
Assert ((($t = Test-PsSuppReceipt -LiteralPath $rc -Capabilities $cap).Errors -join ';') -match '證據# 3 超出') "負例：證據# 越界"
Write-Utf8 $rc (New-ReceiptLines 'RESEARCHED' @('| 行為邏輯 | CONFIRMED | 讀 [[PS_X]] | 1 |') $ev2) $false
Assert ((($t = Test-PsSuppReceipt -LiteralPath $rc -Capabilities $cap).Errors -join ';') -match '\[\[') "負例：含 [[ ]]"
Write-Utf8 $rc ((New-ReceiptLines 'RESEARCHED' @('| 行為邏輯 | CONFIRMED | x | 1 |') $ev2) + @('', '{"agent":"x","findings":[]}')) $false
Assert ((($t = Test-PsSuppReceipt -LiteralPath $rc -Capabilities $cap).Errors -join ';') -match '洩漏') "負例：模型契約 JSON 洩漏"
Write-Utf8 $rc (New-ReceiptLines 'RESEARCHED' @('| 行為邏輯 | CONFIRMED | 依 requirementRef R17 | 1 |') $ev2) $false
Assert ((($t = Test-PsSuppReceipt -LiteralPath $rc -Capabilities $cap).Errors -join ';') -match 'requirementRef') "負例：含消費端識別字樣"
Write-Utf8 $rc (New-ReceiptLines 'RESEARCHED' @('| 資料流 | CONFIRMED | PS_X｜INSERT | 1 |') $ev2) $false
Assert ((($t = Test-PsSuppReceipt -LiteralPath $rc -Capabilities $cap).Errors -join ';') -match '分成 3 格（得 2）') "負例：表格節分格數不符"
Write-Utf8 $rc (New-ReceiptLines 'RESEARCHED' @('| 行為邏輯 | CONFIRMED | x | 無 |') $ev2) $false
Assert ((($t = Test-PsSuppReceipt -LiteralPath $rc -Capabilities $cap).Errors -join ';') -match 'CONFIRMED 必須有證據#') "負例：CONFIRMED 無證據#"
Write-Utf8 $rc (New-ReceiptLines 'RESEARCHED' @('| 行為邏輯 | MAYBE | x | 1 |', '| 摘要 | CONFIRMED | x | 1 |') $ev2) $false
$t = Test-PsSuppReceipt -LiteralPath $rc -Capabilities $cap
Assert ((-not $t.Ok) -and ($t.Errors -join ';') -match '信心「MAYBE」不在三值' -and ($t.Errors -join ';') -match '節名「摘要」不在八節') "負例：信心值域、節名八節"
Write-Utf8 $rc (New-ReceiptLines 'RESEARCHED' @() $ev2) $false
Assert ((($t = Test-PsSuppReceipt -LiteralPath $rc -Capabilities $cap).Errors -join ';') -match 'RESEARCHED 但追加事實為空') "負例：RESEARCHED 無事實"
Write-Utf8 $rc (New-ReceiptLines 'RESEARCHED' @('| 行為邏輯 | CONFIRMED | x | 1 |') @('| a | b | ChunkId 3f2a9c1e |')) $false
Assert ((($t = Test-PsSuppReceipt -LiteralPath $rc -Capabilities $cap).Errors -join ';') -match '機器參照須為') "負例：ChunkId 縮寫不是合法機器參照"
$long = New-ReceiptLines 'NO_EVIDENCE' @() @()
while ($long.Count -le 151) { $long += '' }
Write-Utf8 $rc ($long + @('```')) $false
$t = Test-PsSuppReceipt -LiteralPath $rc -Capabilities $cap
Assert ((-not $t.Ok) -and ($t.Errors -join ';') -match '超過 150 行' -and ($t.Errors -join ';') -match '圍欄') "負例：>150 行、三反引號圍欄"
Write-Utf8 $rc (New-ReceiptLines 'NOT_IN_DOMAIN' @('| 行為邏輯 | CONFIRMED | x | 1 |') $ev2) $false
Assert ((($t = Test-PsSuppReceipt -LiteralPath $rc -Capabilities $cap).Errors -join ';') -match 'NOT_IN_DOMAIN 不得追加事實') "負例：NOT_IN_DOMAIN 帶事實"
Write-Utf8 $rc (New-ReceiptLines 'NO_EVIDENCE' @('| 未解事項 | INFERRED | 查無檔案讀取邏輯 | 無 |') @('| `PS_X` | 排程 | 待人工SQL |')) $false
$t = Test-PsSuppReceipt -LiteralPath $rc -Capabilities $cap
Assert ($t.Ok -and $t.Disposition -eq 'NO_EVIDENCE') "NO_EVIDENCE：可帶未解事項與待人工SQL 證據列"
Remove-Item -LiteralPath $rc -Force

# ── 情境 5：確定性合併 ────────────────────────────────────────────
Write-Host "情境 5：確定性合併（條列／表格／文字節、附錄編號承接、缺節插入、CRLF＋BOM、冪等、還原）"
$factLines = @(
    '| 行為邏輯 | CONFIRMED | 匯入時逐列讀取 CSV | 1 |',
    '| 資料流 | CONFIRMED | PS_DEMO_STG｜INSERT｜SQR TWSQR_DEMO | 2 |',
    '| 畫面與欄位 | INFERRED | FILE_NAME｜檔名｜Edit｜｜使用中 | 無 |',
    '| 執行方式 | DYNAMIC_RUNTIME | 批次由 Run Control 觸發 | 無 |',
    '| 未解事項 | INFERRED | 檔案編碼未指定 | 無 |',
    '| 權限 | CONFIRMED | PL_DEMO 授權 | 1 |',
    '| 相關物件 | CONFIRMED | PS_DEMO_STG｜寫入目標 | 2 |'
)
$rcGood = Join-Path $partsDir ($rid1 + '.a1.md')
Write-Utf8 $rcGood (New-ReceiptLines 'RESEARCHED' $factLines $ev2) $false
$recv = Test-PsSuppReceipt -LiteralPath $rcGood -Capabilities $cap
Assert ($recv.Ok -and $recv.Facts.Count -eq 7) "合併用收據合格（7 條事實、2 列證據）"
$nnPath = Join-Path $domA '01-TW_DEMO_A.md'
$copyLf = Join-Path $root 'copy-lf.md'
Copy-Item -LiteralPath $nnPath -Destination $copyLf
$mg = Merge-PsSuppReceipt -NnPath $nnPath -Receipt $recv -RequestId $rid1
$merged = Read-PsKnText -LiteralPath $nnPath
$mLines = Get-PsKnLines -Text $merged
Assert ($mg.Ok -and $mg.Changed -and $mg.HashBefore -cne $mg.HashAfter -and $mg.EvidenceRows.Count -eq 2 -and $mg.EvidenceRows[0] -eq 4 -and $mg.EvidenceRows[1] -eq 5) "合併：hash 改變、附錄新列編號承接 4、5"
$iB = [array]::IndexOf($mLines, '- **INFERRED**：核准後回寫')
Assert ($iB -ge 0 -and $mLines[$iB + 1] -eq '- **CONFIRMED**：匯入時逐列讀取 CSV（附錄 #4）' -and $mLines[$iB + 2] -eq '') "條列節：追加在最後一條之後、附錄參照換成新編號"
$iD = [array]::IndexOf($mLines, '| PS_DEMO_TBL | UPDATE | 存檔 PeopleCode | CONFIRMED |')
Assert ($iD -ge 0 -and $mLines[$iD + 1] -eq '| PS_DEMO_STG | INSERT | SQR TWSQR_DEMO（附錄 #5） | CONFIRMED |') "表格節（資料流）：表末追加列、信心欄補上"
$iF = [array]::IndexOf($mLines, '| DEMO_STATUS | 狀態 | Translate | 免役=E / 服役中=S | E：使用中（資料 3 筆） |')
Assert ($iF -ge 0 -and $mLines[$iF + 1] -eq '| FILE_NAME | 檔名 | Edit |  | 使用中 |') "表格節（畫面與欄位）：五格（含空格）"
$iR = [array]::IndexOf($mLines, '| [[TWSQR_DEMO]] | 排程執行 |')
Assert ($iR -ge 0 -and $mLines[$iR + 1] -eq '| PS_DEMO_STG | 寫入目標（附錄 #5） |') "表格節（相關物件）：兩格、無 [[（不進 WIKI_MISSING）"
$iX = [array]::IndexOf($mLines, '線上操作。')
Assert ($iX -ge 0 -and $mLines[$iX + 1] -eq '' -and $mLines[$iX + 2] -eq '批次由 Run Control 觸發（DYNAMIC_RUNTIME）') "文字節（執行方式）：節末追加段落"
$iG = [array]::IndexOf($mLines, '- 缺一')
Assert ($iG -ge 0 -and $mLines[$iG + 1] -eq '- 檔案編碼未指定（INFERRED；補研究）') "條列節（未解事項）：追加並標補研究"
$iP = [array]::IndexOf($mLines, '## 權限')
$iGap = [array]::IndexOf($mLines, '## 未解事項（gaps）')
Assert ($iP -gt 0 -and $iP -lt $iGap -and $mLines[$iP - 1] -eq '' -and $mLines[$iP + 1] -eq '' -and $mLines[$iP + 2] -eq 'PL_DEMO 授權（CONFIRMED；附錄 #4）' -and $mLines[$iP + 3] -eq '' -and $mLines[$iP + 4] -eq '## 未解事項（gaps）') "缺節：在「## 未解事項」前插入「## 權限」＋段落，前後各留一個空行"
$iE = [array]::IndexOf($mLines, '| 3 | `PS_PRCSRECUR` | 排程 | 待人工SQL |')
Assert ($iE -ge 0 -and $mLines[$iE + 1] -eq "| 4 | ``a.pcode:40-58`` | File 讀取 | ChunkId ``$uuid2`` |" -and $mLines[$iE + 2] -eq '| 5 | `sqr/x.sqr:1` | INSERT | SELECT 1 FROM DUAL |') "附錄：新列緊接最後一列、編號 4、5"
$fAfter = Get-PsKnNnFacts -LiteralPath $nnPath -Domain '職缺測試'
Assert ($fAfter.missingSections.Count -eq 0 -and $fAfter.duplicateSections -eq 0 -and -not $fAfter.permissionHollow -and $fAfter.evidence.Count -eq 5 -and $fAfter.dataFlow.Count -eq 2 -and $fAfter.fieldRows -eq 2) "合併後 NN 仍可解析：九節齊、無重複、權限非空洞、附錄 5 列"
# 冪等（同收據對同原檔再合併一次 → 內容相同）
$mg2 = Merge-PsSuppReceipt -NnPath $copyLf -Receipt $recv -RequestId $rid1
Assert ($mg2.HashAfter -ceq $mg.HashAfter) "確定性：同收據對同原檔再合併 → 相同 hash"
# CRLF＋BOM 保留
$copyCrlf = Join-Path $root 'copy-crlf.md'
[System.IO.File]::WriteAllText($copyCrlf, ((Get-PsKnLines -Text (Read-PsKnText -LiteralPath $copyLf)) -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
$origCrlf = Read-PsKnText -LiteralPath $copyCrlf
Write-Utf8 $copyCrlf (New-NnLines '01' 'TW_DEMO_A' @('| [[PS_DEMO_TBL]] | 讀取來源 |', '| [[TWSQR_DEMO]] | 排程執行 |') $true) $true "`r`n"
$mg3 = Merge-PsSuppReceipt -NnPath $copyCrlf -Receipt $recv -RequestId $rid1
$bytes3 = [System.IO.File]::ReadAllBytes($copyCrlf)
$text3 = [System.IO.File]::ReadAllText($copyCrlf)
Assert ($bytes3[0] -eq 0xEF -and $bytes3[1] -eq 0xBB -and $text3 -match "`r`n" -and $text3 -notmatch "(?<!`r)`n" -and $mg3.HashAfter -ceq $mg.HashAfter) "CRLF＋BOM 原檔：合併後仍 CRLF＋BOM，正規化 hash 與 LF 版相同"
# 合併痕跡在不在（外環判斷「已合併但 result 沒發布」的那次合併有沒有被回捲，用它取代 hash 相等）
Assert ((Test-PsSuppMergePresent -NnPath $nnPath -Receipt $recv -Capabilities $cap) -and (Test-PsSuppMergePresent -NnPath $nnPath -ReceiptPath $rcGood -Capabilities $cap)) "合併痕跡：合併後機器參照與事實敘述都在 → present（收據物件／收據路徑兩種呼叫法皆可）"
$nnTouched = Read-PsKnText -LiteralPath $nnPath
Assert (Test-PsSuppMergePresent -NnText ($nnTouched + "`n- **INFERRED**：同 run 下一張 request 又追加的一條`n") -Receipt $recv -Capabilities $cap) "合併痕跡：檔案之後又被別張 request 合併過（hash 已不同）→ 內容仍在，present"
Assert (-not (Test-PsSuppMergePresent -NnPath $nnPath -ReceiptPath (Join-Path $root 'no-such-receipt.md') -Capabilities $cap)) "合併痕跡：收據檔不在＝無法證明 → absent"
# 還原
Assert ((Restore-PsSuppBytes -LiteralPath $nnPath -Bytes $mg.BytesBefore) -and ((Get-PsKnFileHash -LiteralPath $nnPath) -ceq $mg.HashBefore)) "還原：BytesBefore 寫回 → hash 回到合併前"
Assert (-not (Test-PsSuppMergePresent -NnPath $nnPath -Receipt $recv -Capabilities $cap)) "合併痕跡：合併被還原（回捲）→ absent，外環據此當成沒合併過、照常重派"
$mgAgain = Merge-PsSuppReceipt -NnPath $nnPath -Receipt $recv -RequestId $rid1
Assert ($mgAgain.HashAfter -ceq $mg.HashAfter) "還原後再合併 → 同一結果（合併只依原檔與收據）"
$empty = @{ Facts = @(); Evidence = @() }
Assert ((Merge-PsSuppReceipt -NnPath $nnPath -Receipt $empty -RequestId $rid1).Reason -eq 'NOTHING_TO_MERGE') "空收據 → NOTHING_TO_MERGE、不改檔"
# 附錄不存在的 NN：在檔尾建節
$noEv = Join-Path $root 'no-ev.md'
Write-Utf8 $noEv @('# 09 x（[[TW_DEMO_X]]）', '', '## 行為邏輯', '', '- **CONFIRMED**：a', '', '## 未解事項（gaps）', '', '- b') $false
$mg4 = Merge-PsSuppReceipt -NnPath $noEv -Receipt $recv -RequestId $rid1
$t4 = Get-PsKnLines -Text (Read-PsKnText -LiteralPath $noEv)
Assert ($mg4.Ok -and $mg4.EvidenceRows[0] -eq 1 -and ([array]::IndexOf($t4, '## Evidence 附錄') -gt [array]::IndexOf($t4, '## 未解事項（gaps）')) -and (@($t4 | Where-Object { $_ -match '^## ' }).Count -eq 8)) "無附錄／缺多節的 NN：附錄建在檔尾（編號從 1）、五個缺節在未解事項前建立（共 8 個 ## 節）"
Assert ((Test-PsSuppAlreadyCovered -TargetFacts $fAfter -FactKind 'DATA.FILE_INPUT' -Capabilities $cap) -and -not (Test-PsSuppAlreadyCovered -TargetFacts $facts1 -FactKind 'SECURITY.ACCESS' -Capabilities $cap)) "ALREADY_COVERED 判定：相關節非空洞才成立（原檔無權限節 → 不成立）"

# ── 情境 6：attempts、D 列、result、wiki 標記、搬移 ────────────────
Write-Host "情境 6：attempts 推導、目標無 NN → D 列、result create-only、wiki stale／reviewed、parts 搬移"
$att = Get-PsSuppAttempts -DomainDir $domA -RequestId $rid1
Assert ($att.Count -eq 1 -and $att.LastN -eq 1 -and $null -eq $att.LastOutcome) "attempts＝工單檔數（1）；outcome 缺＝crash 語意（LastOutcome null）"
$null = Write-PsSuppOutcome -DomainDir $domA -RequestId $rid1 -AttemptNo 1 -Outcome @{ timedOut = $false; exitCode = 0; failureKind = 'NONE'; receiptValid = $true; disposition = 'RESEARCHED'; merged = $true }
$att = Get-PsSuppAttempts -DomainDir $domA -RequestId $rid1
Assert ($null -ne $att.LastOutcome -and $att.LastOutcome.disposition -eq 'RESEARCHED' -and $att.LastOutcome.attempt -eq 1 -and ([string]$att.LastOutcome.completedAt) -ne '') "outcome 檔：attempt 與 completedAt 自動補"
$pend = Get-PsSuppPending -Root $root -Domain '職缺測試' -DomainDir $domA
$pendIds = @($pend | ForEach-Object { $_.RequestId })
Assert ($pend.Count -eq 3 -and ($pendIds -contains $rid1) -and ($pendIds -contains $ridSec) -and ($pendIds -contains $ridNowhere) -and (@($pend | Where-Object { $_.RequestId -eq $rid1 })[0].Attempts -eq 1)) "pending：三張（含 WAITING_RESEARCH 候選）、attempts 帶出"
$d1 = Add-PsSuppChecklistDRow -DomainDir $domA -ObjectName 'TW_NOWHERE' -RequestId $ridNowhere
$clText = Read-PsKnText -LiteralPath (Join-Path $domA 'checklist.md')
Assert ($d1.Added -and $d1.Row -eq ('- [ ] D2-01 新發現 TW_NOWHERE：補研究 ' + $ridNowhere + '（稽核）') -and $clText -match "`r`n" -and ([System.IO.File]::ReadAllBytes((Join-Path $domA 'checklist.md'))[0] -eq 0xEF)) "D 列：輪次 2、序號 01、插在調查進度末；checklist 的 CRLF＋BOM 保留"
$clLines = Get-PsKnLines -Text $clText
$iRow = [array]::IndexOf($clLines, $d1.Row)
Assert ($iRow -gt 0 -and $clLines[$iRow - 1] -match 'TW_DEMO_C' -and $clLines[$iRow + 1] -eq '' -and $clLines[$iRow + 2] -match '^## Gaps') "D 列位置：最後一個調查項之後、Gaps 節之前"
Assert ((Add-PsSuppChecklistDRow -DomainDir $domA -ObjectName 'tw_nowhere' -RequestId $ridNowhere).Reason -eq 'D_EXISTS' -and (Add-PsSuppChecklistDRow -DomainDir $domA -ObjectName 'TW_DEMO_A' -RequestId $ridNowhere).Reason -eq 'NN_EXISTS' -and (Add-PsSuppChecklistDRow -DomainDir $domA -ObjectName 'TW_DEMO_OLD' -RequestId $ridNowhere).Reason -eq 'D_EXISTS') "D 列去重：同物件（大小寫）／已有 NN／歸檔 D 列 → 不寫"
$d2 = Add-PsSuppChecklistDRow -DomainDir $domA -ObjectName 'TW_ANOTHER' -RequestId $ridNowhere
Assert ($d2.Row -match '^- \[ \] D2-02 ') "D 列序號承接同輪最大序號"
$st = Get-PsSuppStatus -Root $root -Domain '職缺測試'
$stMap = @{}
foreach ($s in $st) { $stMap[$s.RequestId] = $s.State }
Assert ($stMap[$rid1] -eq 'PENDING' -and $stMap[$ridNowhere] -eq 'WAITING_RESEARCH' -and $stMap[$ridSec] -eq 'PENDING') "狀態：PENDING／WAITING_RESEARCH"
$affected = @(@{ file = '01-TW_DEMO_A.md'; hashBefore = $mg.HashBefore; hashAfter = $mg.HashAfter; sections = @($mg.Sections); evidenceRows = @($mg.EvidenceRows) })
$res1 = New-PsSuppResult -Request $req1 -Outcome 'RESOLVED' -Disposition 'RESEARCHED' -AuditRound 2 -Affected $affected -Attempts 1
$p1 = Publish-PsSuppResult -Root $root -Result $res1
$p2 = Publish-PsSuppResult -Root $root -Result $res1
Assert ($p1.Ok -and -not $p1.Existed -and $p2.Ok -and $p2.Existed -and (Test-Path -LiteralPath $p1.Path)) "result：create-only；再發布＝冪等成功"
$resRead = Get-PsSupplementalResult -Root $root -RequestId $rid1
Assert ($resRead.outcome -eq 'RESOLVED' -and $resRead.dispositionCode -eq 'RESEARCHED' -and $resRead.affected[0].hashAfter -ceq $mg.HashAfter -and $resRead.affected[0].evidenceRows.Count -eq 2 -and $resRead.auditRoundAtCompletion -eq 2) "result 檔：outcome／disposition／affected／auditRound"
$threw = $false
try { $null = New-PsSuppResult -Request $req1 -Outcome 'DONE' -Disposition 'RESEARCHED' -AuditRound 1 -Affected @() -Attempts 1 } catch { $threw = $true }
Assert ($threw) "result：outcome 不在值域 → 拋錯（不寫）"
Assert ((Get-PsSuppPending -Root $root -Domain '職缺測試' -DomainDir $domA).Count -eq 2) "有 result 的 request 不再 pending"
$sTerm = Submit-PsSupplementalRequest -Root $root -Need $n1
Assert ($sTerm.state -eq 'RESOLVED' -and $sTerm.reason -eq 'TERMINAL' -and -not $sTerm.created) "終局後同 need 再提交 → 回 outcome、不建檔"
$sRe = Submit-PsSupplementalRequest -Root $root -Need $n1 -Resubmit
Assert ($sRe.state -eq 'CREATED' -and $sRe.requestId -eq (Get-PsSuppRequestId -WorkKey $wk1 -Generation 2)) "-Resubmit：建 g2"
$sup = Get-PsSuppSuperseded -Root $root -Domain '職缺測試'
Assert ($sup.Count -eq 0) "g1 已有 result → 不算 superseded"
$sRe3 = Submit-PsSupplementalRequest -Root $root -Need $n1 -Resubmit
Assert ($sRe3.state -eq 'PENDING' -and $sRe3.requestId -eq $sRe.requestId) "g2 未終局時再 -Resubmit → PENDING（不建 g3）"
$ws = Set-PsSuppWikiStale -Root $root -TargetName 'TW_DEMO_A' -LinkedNames @('PS_DEMO_TBL', 'TWSQR_DEMO', 'NOPE') -RequestId $rid1 -SourceLabel '職缺測試/01-TW_DEMO_A.md'
$wikiA = Read-PsKnText -LiteralPath (Join-Path $wiki 'TW_DEMO_A.md')
$wikiT = Read-PsKnText -LiteralPath (Join-Path $wiki 'PS_DEMO_TBL.md')
$wikiS = Read-PsKnText -LiteralPath (Join-Path $wiki 'TWSQR_DEMO.md')
Assert ($ws.Stale -eq 2 -and $ws.Invalidated -eq 1 -and $wikiA -match '(?m)^status: stale$' -and $wikiS -match '(?m)^status: stale$' -and $wikiT -match '(?m)^status: verified$' -and $wikiT -match ('來源 NN 已補研究 ' + [regex]::Escape($rid1)) -and $wikiT -match '(?m)^## Invalidated') "wiki：非 reviewed → stale；reviewed → 狀態不動、Invalidated 追加一行；不存在的名字略過"
$ws2 = Set-PsSuppWikiStale -Root $root -TargetName 'TW_DEMO_A' -LinkedNames @() -RequestId $rid1 -SourceLabel 'x'
Assert ($ws2.Stale -eq 0) "wiki：已 stale 不重複改"
$moved = Move-PsSuppPartsDone -DomainDir $domA -LogDir (Join-Path $logs '職缺測試') -RequestId $rid1
Assert ($moved -eq 3 -and (Test-Path -LiteralPath (Join-Path (Join-Path $logs '職缺測試') ('supplemental-done/' + $rid1 + '.a1.manifest.md'))) -and -not (Test-Path -LiteralPath $mf.ManifestPath)) "parts 搬移：manifest／收據／outcome 三檔搬到 auto-loop-logs/<領域>/supplemental-done/"

# ── 情境 7：完成邊界 ──────────────────────────────────────────────
Write-Host "情境 7：完成邊界（RESEARCHED → AUDITED：稽核輪次遞增＋AUDITED_CLEAN＋audit-done.json）"
$null = Publish-PsKnowledgeIndex -Root $root -LogRoot $logs
$c0 = Get-PsSuppCompletion -Root $root -RequestId $rid1
Assert ($c0.Researched -and -not $c0.Audited -and -not $c0.Graduated) "尚未稽核：RESEARCHED=true、AUDITED=false"
$hNow = Get-PsKnFileHash -LiteralPath $nnPath
Write-Utf8 (Join-Path $domA '90-audit.md') @('# 職缺測試 稽核報告（90-audit）', '', '> 稽核輪次：3', '', '## 總覽記分卡', '', '| 檔案 | 證據 PASS | FAIL | UNVERIFIABLE | Claim VERIFIED | DISPUTED | 燈號 |', '|---|---|---|---|---|---|---|', '| 01-TW_DEMO_A.md | 5 | 0 | 0 | 2 | 0 | 🟢 |', '| 02-TWSQR_DEMO.md | 3 | 0 | 0 | 1 | 0 | 🟢 |', '', '## FAIL / DISPUTED / UNVERIFIABLE 明細', '', '| 檔案 | 類型 | 內容 | 原因 | 處置 |', '|---|---|---|---|---|', '', '## 完整性（換角度 diff）', '', '- 任務 C 覆蓋：全部完成') $false
$clRaw = Read-PsKnText -LiteralPath (Join-Path $domA 'checklist.md')
[System.IO.File]::WriteAllText((Join-Path $domA 'checklist.md'), ($clRaw -replace '稽核輪次：2', '稽核輪次：3'), (New-Object System.Text.UTF8Encoding($true)))
[System.IO.File]::WriteAllText((Join-Path $domA 'audit-done.json'), ('{"round":3,"files":{"01-TW_DEMO_A.md":{"hash":"' + $hNow + '"},"02-TWSQR_DEMO.md":{"hash":"' + (Get-PsKnFileHash -LiteralPath (Join-Path $domA '02-TWSQR_DEMO.md')) + '"}}}'), (New-Object System.Text.UTF8Encoding($false)))
$null = Publish-PsKnowledgeIndex -Root $root -LogRoot $logs
$idx2 = Read-PsKnowledgeIndex -Root $root
$e1 = @($idx2.nn | Where-Object { $_.file -eq '01-TW_DEMO_A.md' })[0]
Assert ($e1.grade -eq 'AUDITED_CLEAN' -and $e1.auditRound -eq 3) "索引：合併後的 NN 經第 3 輪稽核 → AUDITED_CLEAN（audit-done.json 判稽核後未改）"
$c1 = Get-PsSuppCompletion -Root $root -RequestId $rid1
Assert ($c1.Researched -and $c1.Audited -and -not $c1.Graduated -and -not $c1.Projected) "AUDITED：affected 全 AUDITED_CLEAN 且 auditRound 3 > auditRoundAtCompletion 2；GRADUATED／PROJECTED 仍 false"
Assert ((Get-PsSuppCompletion -Root $root -RequestId $ridSec).Reason -eq 'NO_RESULT') "無 result → NO_RESULT"

# ── 情境 8：CLI ───────────────────────────────────────────────────
Write-Host "情境 8：CLI exit 與結論碼形狀"
$c = Invoke-Cli @('-New', '-Target', 'COMPONENT:TW_DEMO_A', '-FactKind', 'UI.NAVIGATION', '-Properties', 'entries')
Assert ($c.Exit -eq 0 -and $c.Last -eq '結論代號：SUPP1-1-01' -and (($c.Lines -join "`n") -match 'state=CREATED')) "-New 合法 → exit 0、SUPP1-1-01"
$c = Invoke-Cli @('-New', '-Target', 'COMPONENT:TW_DEMO_A', '-FactKind', 'UI.NAVIGATION', '-Properties', 'entries')
Assert ($c.Exit -eq 0 -and $c.Last -eq '結論代號：SUPP1-1-02') "-New 重複 → SUPP1-1-02（PENDING）"
$c = Invoke-Cli @('-New', '-Target', 'WIDGET:x y', '-FactKind', 'NOPE', '-Properties', 'a')
Assert ($c.Exit -eq 2 -and $c.Last -match '^結論代號：SUPP1-1-04-\d+$') "-New 驗證失敗 → exit 2、SUPP1-1-04-<n>"
$c = Invoke-Cli @('-New', '-Target', 'COMPONENT:TW_NOWHERE2', '-FactKind', 'DATA.FLOW', '-Properties', 'reads')
Assert ($c.Exit -eq 2 -and $c.Last -eq '結論代號：SUPP1-1-05') "-New 零候選 → SUPP1-1-05"
$c = Invoke-Cli @('-New', '-Target', 'COMPONENT:TW_DEMO_A', '-FactKind', 'DATA.FILE_INPUT', '-Properties', 'present,layout', '-Context', 'operation=IMPORT', '-EvidencePolicy', 'AUDITED')
Assert ($c.Exit -eq 0 -and $c.Last -eq '結論代號：SUPP1-1-02') "-New 對已有 g2（未終局）的 need → PENDING"
$needJson = Join-Path $root 'need.json'
[System.IO.File]::WriteAllText($needJson, '{"target":{"type":"COMPONENT","name":"TW_DEMO_A"},"context":{},"factKind":"BEHAVIOR.RULES","properties":["rules"],"evidencePolicy":"STATIC","freshness":"CURRENT"}', (New-Object System.Text.UTF8Encoding($false)))
$c = Invoke-Cli @('-Submit', '-NeedFile', $needJson, '-ConsumerKind', 'SPEC', '-JobId', 'demo-job', '-RequirementRef', 'R05')
Assert ($c.Exit -eq 0 -and $c.Last -eq '結論代號：SUPP1-1-01') "-Submit -NeedFile（SPEC 消費者）→ CREATED"
$c = Invoke-Cli @('-Submit', '-NeedFile', $needJson, '-ConsumerKind', 'SPEC')
Assert ($c.Exit -eq 2 -and $c.Last -match '^結論代號：SUPP1-1-04-') "-Submit SPEC 缺 jobId／requirementRef → INVALID"
$c = Invoke-Cli @('-Status', '-Domain', '職缺測試')
Assert ($c.Exit -eq 0 -and $c.Last -match '^結論代號：SUPP1-2-01-\d+$') "-Status → SUPP1-2-01-<n>"
$c = Invoke-Cli @('-Result', '-RequestId', $rid1)
Assert ($c.Exit -eq 0 -and $c.Last -eq '結論代號：SUPP1-4-01-2' -and (($c.Lines -join "`n") -match 'AUDITED=True')) "-Result 有結果 → 完成層 2（AUDITED）"
$c = Invoke-Cli @('-Result', '-RequestId', $ridSec)
Assert ($c.Exit -eq 0 -and $c.Last -eq '結論代號：SUPP1-4-02') "-Result 無結果 → SUPP1-4-02"
$c = Invoke-Cli @('-Status', '-New')
Assert ($c.Exit -eq 2 -and $c.Last -eq '結論代號：SUPP1-9-01') "動詞衝突 → SUPP1-9-01"
foreach ($code in @('結論代號：SUPP1-1-01', '結論代號：SUPP1-1-04-8', '結論代號：SUPP1-2-01-12', '結論代號：SUPP1-4-01-2')) { Assert (Test-CodeShape $code 'SUPP') "結論碼形狀：$code" }
Assert (-not (Test-CodeShape '結論代號：SUPP1-1-01-TW_X' 'SUPP') -and -not (Test-CodeShape '結論代號：SUPP1-1-01-職缺' 'SUPP')) "結論碼形狀：含物件名／CJK 不合格"
$allOut = @()
foreach ($a in @(@('-Status'), @('-Result', '-RequestId', $rid1))) { $allOut += (Invoke-Cli $a).Lines }
Assert (@($allOut | Where-Object { $_ -match '^結論代號：' }).Count -eq 2) "每個動詞恰一行結論代號"

# ── 情境 9：intake 拒收／callee 反向角色／wiki 內文 status 不動／領域目錄消失 ─────
Write-Host "情境 9：intake 驗證拒收（ID_MISMATCH／WORKKEY）、callee 角色開頭比對、wiki 只改 frontmatter、領域目錄消失 → DOMAIN_MISSING"
$dirs = Get-PsSuppDirs -Root $root
$badId = 'S-' + ('a' * 24) + '-g1'
Write-Utf8 (Join-Path $dirs.Requests ($badId + '.json')) @('{"schemaVersion":"1","requestId":"S-' + ('b' * 24) + '-g1","workKey":"x","generation":1,"domain":"職缺測試","need":{}}') $false
$raw1 = Read-PsKnText -LiteralPath (Join-Path $dirs.Requests ($rid1 + '.json'))
$fakeId = 'S-' + ('c' * 24) + '-g1'
Write-Utf8 (Join-Path $dirs.Requests ($fakeId + '.json')) @(($raw1 -replace [regex]::Escape($rid1), $fakeId)) $false
$acceptedRaw = Get-PsSuppRequests -Root $root -Capabilities $cap
$accepted = @($acceptedRaw)
$ids = @($accepted | ForEach-Object { $_.RequestId })
$rejTxt = ($PsSuppIntakeRejected -join ';')
Assert (($ids -contains $rid1) -and ($ids -notcontains $badId) -and ($ids -notcontains $fakeId) -and $rejTxt -match ([regex]::Escape($badId) + '\.json：ID_MISMATCH') -and $rejTxt -match ([regex]::Escape($fakeId) + '\.json：WORKKEY')) "intake：requestId 與檔名不符 → ID_MISMATCH；requestId 與 workKey 對不上 → WORKKEY；兩者都不進清單、合法的照常"
# 單檔版的同一把尺（迷你圈圍籬拿它判斷「session 期間新增的 request 是不是別的行程正常提交的」）
$schemaId = 'S-' + ('d' * 24) + '-g1'
Write-Utf8 (Join-Path $dirs.Requests ($schemaId + '.json')) @((($raw1 -replace [regex]::Escape($rid1), $schemaId) -replace '("schemaVersion"\s*:\s*)1', '${1}2')) $false
$vGood = Test-PsSuppRequestFile -LiteralPath (Join-Path $dirs.Requests ($rid1 + '.json')) -Capabilities $cap
$vBadId = Test-PsSuppRequestFile -LiteralPath (Join-Path $dirs.Requests ($badId + '.json')) -Capabilities $cap
$vFake = Test-PsSuppRequestFile -LiteralPath (Join-Path $dirs.Requests ($fakeId + '.json')) -Capabilities $cap
$vSchema = Test-PsSuppRequestFile -LiteralPath (Join-Path $dirs.Requests ($schemaId + '.json')) -Capabilities $cap
$vName = Test-PsSuppRequestFile -LiteralPath (Join-Path $dirs.Requests 'not-a-request.json') -Capabilities $cap
Assert ($vGood.Ok -and $vGood.RequestId -ceq $rid1 -and $vGood.Generation -eq 1 -and (-not $vBadId.Ok) -and $vBadId.Reason -eq 'ID_MISMATCH' -and (-not $vFake.Ok) -and $vFake.Reason -eq 'WORKKEY' -and (-not $vSchema.Ok) -and $vSchema.Reason -eq 'SCHEMA' -and (-not $vName.Ok) -and $vName.Reason -eq 'NAME') "Test-PsSuppRequestFile：合格／ID_MISMATCH／WORKKEY／SCHEMA／檔名文法不符——intake 與圍籬共用"
$resOk = Join-Path $dirs.Results ($rid1 + '.json')
$vResGood = Test-PsSuppResultFile -LiteralPath $resOk
$badRes = 'S-' + ('e' * 24) + '-g1'
Write-Utf8 (Join-Path $dirs.Results ($badRes + '.json')) @('{"schemaVersion":1,"requestId":"' + $badRes + '","outcome":"DONE"}') $false
$vResBad = Test-PsSuppResultFile -LiteralPath (Join-Path $dirs.Results ($badRes + '.json'))
Assert ($vResGood.Ok -and (-not $vResBad.Ok) -and $vResBad.Reason -eq 'OUTCOME') "Test-PsSuppResultFile：合格 result 過、outcome 不在值域 → OUTCOME"
Remove-Item -LiteralPath (Join-Path $dirs.Results ($badRes + '.json')) -Force
Remove-Item -LiteralPath (Join-Path $dirs.Requests ($schemaId + '.json')) -Force
Remove-Item -LiteralPath (Join-Path $dirs.Requests ($badId + '.json')) -Force
Remove-Item -LiteralPath (Join-Path $dirs.Requests ($fakeId + '.json')) -Force
$factsRev = @{ relatedObjects = @(@{ name = 'TWSQR_DEMO'; role = '被呼叫（由排程執行的反向關係）' }) }
$cRevRaw = Get-PsSuppCallees -TargetFacts $factsRev -DomainDir $domA -Domain '職缺測試' -Index $index -Capabilities $cap
$cRev = @($cRevRaw)
$factsFwd = @{ relatedObjects = @(@{ name = 'TWSQR_DEMO'; role = '排程執行' }) }
$cFwdRaw = Get-PsSuppCallees -TargetFacts $factsFwd -DomainDir $domA -Domain '職缺測試' -Index $index -Capabilities $cap
$cFwd = @($cFwdRaw)
Assert ($cRev.Count -eq 0 -and $cFwd.Count -eq 1 -and $cFwd[0].Name -eq 'TWSQR_DEMO') "callee：角色以開頭比對——「被呼叫」不是 callee、「排程執行」是"
Write-Utf8 (Join-Path $wiki 'TW_DEMO_B.md') @('---', 'name: TW_DEMO_B', 'type: COMPONENT', 'status: verified', 'sources:', '  - 職缺測試/01-TW_DEMO_A.md', '---', '', '# TW_DEMO_B', '', 'status: verified（內文說明文字，不是 frontmatter）', '', '| 欄位 | 值 |', '|---|---|', '| status | verified |', '') $false
$wsB = Set-PsSuppWikiStale -Root $root -TargetName 'TW_DEMO_B' -LinkedNames @() -RequestId $rid1 -SourceLabel 'x'
$wikiB = Read-PsKnText -LiteralPath (Join-Path $wiki 'TW_DEMO_B.md')
Assert ($wsB.Stale -eq 1 -and $wikiB -match '(?m)^status: stale$' -and $wikiB -match '(?m)^status: verified（內文' -and $wikiB -match '\| status \| verified \|' -and ([regex]::Matches($wikiB, '(?m)^status: stale')).Count -eq 1) "wiki：只改 frontmatter 的第一個 status:；內文的 status: 字樣一個都不動"
$domGone = Join-Path $research 'zz-gone'
Write-Utf8 (Join-Path $domGone '00-overview.md') @('# zz-gone 總覽', '') $false
$sGone = Submit-PsSupplementalRequest -Root $root -Need (ConvertTo-PsSuppNeed -Target 'COMPONENT:TW_DEMO_C' -FactKind 'UI.NAVIGATION' -Properties 'entries') -DomainHint 'zz-gone'
Remove-Item -LiteralPath $domGone -Recurse -Force
$stGoneRaw = Get-PsSuppStatus -Root $root -Domain 'zz-gone' -Capabilities $cap
$stGone = @($stGoneRaw)
Assert ($sGone.state -eq 'CREATED' -and $stGone.Count -eq 1 -and $stGone[0].State -eq 'DOMAIN_MISSING') "status：領域目錄不見（改名／刪除）→ DOMAIN_MISSING（不是 WAITING_RESEARCH）"
$emptyRcpt = Join-Path $root 'empty-receipt.md'
Write-Utf8 $emptyRcpt @('## 處置', '| 處置 | 查法收據 |', '|---|---|', '| NO_EVIDENCE | ps-peoplecode-flow 搜 TW_DEMO_A 全部事件 2 頁無 File 物件 |', '', '## 追加事實', '| 節 | 信心 | 敘述 | 證據# |', '|---|---|---|---|', '', '## 追加證據', '| 位置 | 說明 | 機器參照 |', '|---|---|---|', '') $false
$vEmpty = Test-PsSuppReceipt -LiteralPath $emptyRcpt -Capabilities $cap
Assert ($vEmpty.Ok -and $vEmpty.Disposition -eq 'NO_EVIDENCE' -and $vEmpty.Facts.Count -eq 0 -and $vEmpty.Evidence.Count -eq 0) "收據：查無時兩張空表（只有表頭與分隔列）合格（契約的空表規則）"

Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
if ($failCount -gt 0) { Write-Host "共 $failCount 個 FAIL" -ForegroundColor Red; exit 1 }
Write-Host "全部情境 PASS" -ForegroundColor Green
