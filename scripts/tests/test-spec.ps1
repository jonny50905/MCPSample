# scripts/tests/test-spec.ps1 — Spec 引擎（ps-spec-lib／ps-spec CLI）的功能測試
# 用法：pwsh -NoProfile -File scripts/tests/test-spec.ps1   （PowerShell 7 或 5.1 皆可）
# 範圍：合成 fixtures（臨時目錄，結束自刪；無公司資料；物件名一律 TW_DEMO_*／PS_DEMO_*）：
#       pack 驗證負例、兩套 pack 對同一合成 NN 產不同 spec、EXTRACT facts、COMPOSE manifest／context／條目列舉、
#       假 worker（合格／不合格／超長／含模板行／來源改變）、input.json 快照與來源改變拒收（不記 attempt）、receipt 鍵含指紋、
#       re-plan 重用收據、WAITING_KNOWLEDGE／WAITING_AUDIT 不重送、render parity、render 前來源重驗、gate 覆蓋與 UNKNOWN debt、
#       drill tuple 形狀、doctor stage 0、jobId 文法、結論碼形狀。
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ErrorActionPreference = 'Stop'
. (Join-Path $repoRoot 'scripts/ps-knowledge-lib.ps1')
. (Join-Path $repoRoot 'scripts/ps-supplemental-lib.ps1')
. (Join-Path $repoRoot 'scripts/ps-session-lib.ps1')
. (Join-Path $repoRoot 'scripts/ps-spec-lib.ps1')
$cli = Join-Path $repoRoot 'scripts/ps-spec.ps1'

$failCount = 0
function Assert([bool]$Cond, [string]$Name) {
    if ($Cond) { Write-Host "  PASS：$Name" }
    else { Write-Host "  FAIL：$Name" -ForegroundColor Red; $script:failCount++ }
}
function Write-Utf8([string]$Path, [string[]]$Lines, [bool]$Bom = $false, [string]$Eol = "`n") {
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, ($Lines -join $Eol) + $Eol, (New-Object System.Text.UTF8Encoding($Bom)))
}
$codeRx = '^SPEC1-\d-\d\d(-\d+)?$'
$script:lastOut = ''
# 每次 CLI：回最後一行（結論碼）；並驗形狀（不含 /、.md、TW_、CJK）
function Invoke-Cli {
    param([hashtable]$Named)
    $h = @{}
    foreach ($k in $script:commonH.Keys) { $h[$k] = $script:commonH[$k] }
    foreach ($k in $Named.Keys) { $h[$k] = $Named[$k] }
    $o = (& $cli @h *>&1 | Out-String)
    $script:lastOut = $o
    if ($env:PS_SPEC_TEST_DEBUG -eq '1') { Write-Host $o }
    $script:lastExit = $LASTEXITCODE
    $lines = @(($o -replace "`r", '') -split "`n" | Where-Object { $_.Trim() -ne '' })
    $last = ''
    if ($lines.Count -gt 0) { $last = $lines[$lines.Count - 1].Trim() }
    $shapeOk = ($last -match $codeRx -and $last -notmatch '/|\.md|TW_|[\u4e00-\u9fff]')
    if (-not $shapeOk) { Write-Host "  FAIL：結論碼形狀（$last）" -ForegroundColor Red; $script:failCount++ }
    return $last
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('spec-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$research = Join-Path $root 'docs/ps-research'
$domA = Join-Path $research '測試領域'
$wiki = Join-Path $research 'wiki'
$priv = Join-Path $root 'private'
$rt = Join-Path $root 'runtime'
$logs = Join-Path $root 'logs'
$examples = Join-Path $repoRoot '.opencode/peoplesoft/spec/examples'
New-Item -ItemType Directory -Path (Join-Path $root '.opencode/peoplesoft/spec') -Force | Out-Null
New-Item -ItemType Directory -Path $priv -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot '.opencode/peoplesoft/spec/capabilities.json') -Destination (Join-Path $root '.opencode/peoplesoft/spec/capabilities.json')
Copy-Item -LiteralPath (Join-Path $examples 'pack-a') -Destination (Join-Path $priv 'pack-a') -Recurse
Copy-Item -LiteralPath (Join-Path $examples 'pack-b') -Destination (Join-Path $priv 'pack-b') -Recurse
$uuid1 = '3f2a9c1e-7b4d-4e8a-9c6f-1d2e3a4b5c6d'
$uuid2 = '9b2f5c1e-4a3d-4f0a-8f21-7e5d0c9a1b2c'

function New-DemoNn([string]$Num, [string]$Obj, [string]$Status, [string[]]$Behavior, [bool]$WithCallee = $true) {
    $l = @(
        "# $Num 示範功能（[[$Obj]]）",
        '',
        "> 所屬總覽：[00-overview.md](00-overview.md)　狀態：$Status",
        '> Origin：CUSTOM_PREFIX　搜尋政策：CUSTOM_FIRST　Delivered fallback：未使用',
        '',
        '## 相關物件',
        '',
        '| 物件 | 角色 |',
        '|---|---|',
        "| [[$Obj]] | 主 Component |",
        '| [[PS_DEMO_TBL]] | 寫入目標 |',
        '| [[PS_JOB]] | 讀取來源 |'
    )
    if ($WithCallee) { $l += '| [[TW_DEMO_IMP]] | 呼叫（匯入 AE） |' }
    $l += @(
        '',
        '## 功能定位',
        '',
        '示範用維護頁面：維護示範資料表。',
        '',
        '### 導覽入口',
        '',
        '| # | Portal | 入口型 | CREF 物件名 | 導覽入口 | 可見性 | 語系／來源 | 證據 |',
        '|---|---|---|---|---|---|---|---|',
        '| 1 | EMPLOYEE | PORTAL_REGISTRY | TW_DEMO_CREF | 示範 > 維護 > 示範資料 | REGISTRY_DEFINED | ZHT／LANG | 附錄 #2 |',
        '',
        '### Technical Menu',
        '',
        'TW_DEMO_MENU / USE / TW_DEMO_ITEM',
        '',
        '## 畫面與欄位',
        '',
        '| 欄位 | 顯示文字 | 類型 | 選項（label ↔ 儲存值） | 生命狀態 |',
        '|---|---|---|---|---|',
        '| DEMO_STATUS | 示範狀態 | Translate | 啟用=A / 停用=I | A：使用中 |',
        '| EFFDT | 生效日 | Date |  |  |',
        '',
        '## 行為邏輯',
        ''
    )
    $l += $Behavior
    $l += @(
        '',
        '## 資料流',
        '',
        '| 表 | 操作 | 來源 | 信心 |',
        '|---|---|---|---|',
        '| PS_DEMO_TBL | UPDATE | 存檔 PeopleCode | CONFIRMED |',
        '| PS_JOB | READ | 查詢 | INFERRED |',
        '',
        '## 執行方式',
        '',
        '線上操作；匯入由 TW_DEMO_IMP 批次執行（Process Scheduler）。',
        '',
        '## 權限',
        '',
        'TW_DEMO_PL（Permission List）。',
        '',
        '## 未解事項（gaps）',
        '',
        '- 示範缺口一',
        '',
        '## Evidence 附錄',
        '',
        '| # | 位置 | 說明 | 機器參照 |',
        '|---|---|---|---|',
        "| 1 | ``TW_DEMO_A.SaveEdit:12-24`` | 狀態檢核 | ChunkId ``$uuid1`` |",
        '| 2 | SQL：`SELECT PORTAL_OBJNAME FROM PSPRSMDEFN WHERE ROWNUM <= 5` | 入口 | keyRows：TW_DEMO_CREF |',
        "| 3 | ``TW_DEMO_A.SavePostChange:5-9`` | 回寫 | ChunkId ``$uuid2`` |"
    )
    return , $l
}
$behA = @(
    '- **CONFIRMED**：DEMO_STATUS 為 A 時必須填 EFFDT，否則顯示錯誤訊息（附錄 #1）',
    '- **CONFIRMED**：存檔後回寫 PS_DEMO_TBL 的 DEMO_STATUS（附錄 #3）',
    '- **INFERRED**：匯入檔以逗號分隔，欄位 EMPLID、DEMO_STATUS、EFFDT'
)
Write-Utf8 (Join-Path $domA '03-TW_DEMO_A.md') (New-DemoNn '03' 'TW_DEMO_A' 'COMPLETE' $behA)
Write-Utf8 (Join-Path $domA '04-TW_DEMO_IMP.md') @(
    '# 04 示範匯入（[[TW_DEMO_IMP]]）', '', '> 所屬總覽：[00-overview.md](00-overview.md)　狀態：COMPLETE', '> Origin：CUSTOM_PREFIX　搜尋政策：CUSTOM_FIRST　Delivered fallback：未使用', '',
    '## 相關物件', '', '| 物件 | 角色 |', '|---|---|', '| [[TW_DEMO_IMP]] | 主 AE |', '| [[PS_DEMO_TBL]] | 寫入目標 |', '',
    '## 功能定位', '', '示範匯入批次。', '',
    '## 畫面與欄位', '', '（無——AE，無使用者畫面）', '',
    '## 行為邏輯', '', '- **CONFIRMED**：逐列讀入 CSV 寫入 PS_DEMO_TBL（附錄 #1）', '',
    '## 資料流', '', '| 表 | 操作 | 來源 | 信心 |', '|---|---|---|---|', '| PS_DEMO_TBL | INSERT | AE Step | CONFIRMED |', '',
    '## 執行方式', '', '批次：Process Scheduler 排程 TW_DEMO_IMP，Run Control 頁 TW_DEMO_RC；輸入檔 demo_in.csv。', '',
    '## 權限', '', '<!-- 無 -->', '',
    '## 未解事項（gaps）', '', '- 無', '',
    '## Evidence 附錄', '', '| # | 位置 | 說明 | 機器參照 |', '|---|---|---|---|', "| 1 | ``TW_DEMO_IMP.MAIN.Step01`` | 讀檔 | ChunkId ``$uuid2`` |")
Write-Utf8 (Join-Path $domA '05-TW_DEMO_B.md') (New-DemoNn '05' 'TW_DEMO_B' 'COMPLETE' @('- **INFERRED**：示範 B 的行為') $false)
Write-Utf8 (Join-Path $domA '00-overview.md') @('# 測試領域 業務總覽', '', '## 功能地圖', '', '| # | 功能 | Component / 物件 | 類型 | Origin | 一句話說明 |', '|---|---|---|---|---|---|', '| 03 | 示範功能 | [[TW_DEMO_A]] | 線上頁面 | CUSTOM_PREFIX | 說明 |', '| 04 | 示範匯入 | [[TW_DEMO_IMP]] | AE | CUSTOM_PREFIX | 說明 |', '| 05 | 示範乙 | [[TW_DEMO_B]] | 線上頁面 | CUSTOM_PREFIX | 說明 |')
Write-Utf8 (Join-Path $domA '90-audit.md') @('# 測試領域 稽核報告（90-audit）', '', '> 稽核輪次：4　稽核日期：X', '', '## 總覽記分卡', '', '| 檔案 | 證據 PASS | FAIL | UNVERIFIABLE | Claim VERIFIED | DISPUTED | 燈號 |', '|---|---|---|---|---|---|---|', '| 03-TW_DEMO_A.md | 3 | 0 | 0 | 2 | 0 | 🟢 |', '| 04-TW_DEMO_IMP.md | 1 | 0 | 0 | 1 | 0 | 🟢 |', '| 05-TW_DEMO_B.md | 未稽核 | | | | | ⛔ |', '', '## FAIL / DISPUTED / UNVERIFIABLE 明細', '', '| 檔案 | 類型 | 內容 | 原因 | 處置 |', '|---|---|---|---|---|', '', '## 完整性（換角度 diff）', '', '| 候選物件 | 型別 | 經由表 | 方向 | origin | 分類 | 理由 |', '|---|---|---|---|---|---|---|', '| PS_JOB | RECORD | PS_JOB | 讀 | DELIVERED | DEPENDENCY | 共用表 |')
Write-Utf8 (Join-Path $domA 'checklist.md') @('# 測試領域 調查進度', '', '稽核輪次：4', '', '## 調查進度', '', '- [x] 03 示範功能 `TW_DEMO_A` → 03-TW_DEMO_A.md', '- [x] 04 示範匯入 `TW_DEMO_IMP` → 04-TW_DEMO_IMP.md', '- [x] 05 示範乙 `TW_DEMO_B` → 05-TW_DEMO_B.md')
Write-Utf8 (Join-Path $wiki 'PS_DEMO_TBL.md') @('---', 'aliases: [示範資料表]', 'type: RECORD', 'origin: CUSTOM_PREFIX', 'status: verified', 'confidence: high', 'last_verified: 2099-01-01', "sources: [$uuid1]", 'reviewed: false', '---', '', '# PS_DEMO_TBL', '', '## Observations', '', '- 示範資料表，鍵 EMPLID＋EFFDT', '- DEMO_STATUS 為 A／I', '', '## Relations', '', '- written_by [[TW_DEMO_A]]')
function Write-AuditDone {
    $done = [ordered]@{ round = 4; files = [ordered]@{} }
    foreach ($f in @('03-TW_DEMO_A.md', '04-TW_DEMO_IMP.md')) { $done.files[$f] = [ordered]@{ hash = (Get-PsKnFileHash -LiteralPath (Join-Path $domA $f)); status = 'DONE' } }
    [System.IO.File]::WriteAllText((Join-Path $domA 'audit-done.json'), (ConvertTo-PsKnJson -Value $done), (New-Object System.Text.UTF8Encoding($false)))
}
Write-AuditDone

# 假 worker：讀 manifest 的條目表與表頭，依 PS_SPEC_FAKE_MODE 寫 fragment
$fake = Join-Path $root 'fake-worker.ps1'
Write-Utf8 $fake @(
    'param([string]$AttemptDir, [string]$ManifestPath, [string]$FragmentPath)',
    '$mode = $env:PS_SPEC_FAKE_MODE',
    'if ($mode -eq "") { $mode = "valid" }',
    '$m = [System.IO.File]::ReadAllText($ManifestPath)',
    '$items = @()',
    'foreach ($mm in [regex]::Matches($m, "(?m)^\| (\d+) \| ([^|]+?) \| (\d+) \| ([^|]+?) \|$")) { $items += , @([int]$mm.Groups[1].Value, $mm.Groups[2].Value, [int]$mm.Groups[3].Value) }',
    '$hdr = [regex]::Match($m, "(?m)^事實表頭（逐字）：(.+)$").Groups[1].Value.Trim()',
    '$cols = @($hdr.Trim("|") -split "\|").Count',
    '$sep = "|" + ("---|" * $cols)',
    '$rows = @()',
    'foreach ($it in $items) { $c = @([string]$it[0]); for ($i = 1; $i -lt $cols - 1; $i++) { if ($hdr -match "用途" -and $i -eq 2) { $c += "WRITE" } else { $c += ("示範值" + $i) } }; $c += ($it[1] + "#1"); $rows += ("| " + ($c -join " | ") + " |") }',
    'if ($mode -eq "missing") { exit 0 }',
    'if ($mode -eq "mutate") { $nn = $env:PS_SPEC_FAKE_NN; $t = [System.IO.File]::ReadAllText($nn); $t = $t.Replace("- **INFERRED**：匯入檔", "- **CONFIRMED**：新增條目`n- **INFERRED**：匯入檔"); [System.IO.File]::WriteAllText($nn, $t, (New-Object System.Text.UTF8Encoding($false))) }',
    '$out = @("## 事實", $hdr, $sep)',
    'if ($mode -eq "invalid") { $out += ("| 99 | x | x | x | nofile#1 |") } elseif ($mode -eq "partial") { $out += $rows[0] } else { $out += $rows }',
    '$out += @("", "## 未採用", "| 來源條目 | 原因 |", "|---|---|")',
    'if ($mode -eq "template") { $out += "本模板為合成範例：公司機複製本目錄為 .ps-private/spec/<packId>/ 後，只改標記位置與文字，不改 generic 檔。" }',
    'if ($mode -eq "long") { for ($i = 0; $i -lt 200; $i++) { $out += "" } }',
    '[System.IO.File]::WriteAllText($FragmentPath, ($out -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))',
    'exit 0')
$env:PS_SPEC_FAKE_MODE = 'valid'
$env:PS_SPEC_FAKE_NN = (Join-Path $domA '03-TW_DEMO_A.md')
$script:commonH = @{ Root = $root; PrivateRoot = $priv; RuntimeRoot = $rt; LogRoot = $logs }
$caps = Get-PsSpCapabilities -Root $root

# ── 情境 1：pack 驗證（正例與負例）────────────────────────────
Write-Host "情境 1：pack 驗證"
$va = Test-PsSpPack -PackDir (Join-Path $priv 'pack-a') -Capabilities $caps
Assert ($va.Ok -and $va.Signed -and $va.Requirements.Count -eq 11 -and $va.Markers.Count -eq 7) "pack-a 合法：11 requirements、7 個模板標記、已簽核"
$vb = Test-PsSpPack -PackDir (Join-Path $priv 'pack-b') -Capabilities $caps
Assert ($vb.Ok -and $vb.Requirements.Count -eq 9 -and $va.ContentHash -cne $vb.ContentHash -and $va.BindingHash -cne $vb.BindingHash) "pack-b 合法（含 UNSUPPORTED、ALL／NOT 條件、context.record）；content／binding hash 與 A 不同"
function New-BadPack([string]$Name, [scriptblock]$Mutate, [string]$Template = '') {
    $d = Join-Path $priv $Name
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    $p = (Read-PsKnText -LiteralPath (Join-Path $priv 'pack-a/pack.json')) | ConvertFrom-Json
    $p.packId = $Name
    & $Mutate $p
    [System.IO.File]::WriteAllText((Join-Path $d 'pack.json'), (ConvertTo-PsKnJson -Value $p), (New-Object System.Text.UTF8Encoding($false)))
    if ($Template -eq '') { $Template = Read-PsKnText -LiteralPath (Join-Path $priv 'pack-a/template-bound.md') }
    [System.IO.File]::WriteAllText((Join-Path $d 'template-bound.md'), $Template, (New-Object System.Text.UTF8Encoding($false)))
    return (Test-PsSpPack -PackDir $d -Capabilities $caps)
}
$r = New-BadPack 'bad-unknown' { param($p) $p | Add-Member -NotePropertyName 'extra' -NotePropertyValue 1 }
Assert ((-not $r.Ok) -and ($r.Errors -join ';') -match 'UNKNOWN_FIELD：extra') "負例：未知欄位拒收"
$r = New-BadPack 'bad-dup' { param($p) $p.requirements[1].id = 'R01' }
Assert ((-not $r.Ok) -and ($r.Errors -join ';') -match 'DUP_ID：requirement R01') "負例：requirement id 重複"
$r = New-BadPack 'bad-ck' { param($p) $p.checklist += 'C99' }
Assert ((-not $r.Ok) -and ($r.Errors -join ';') -match 'CHECKLIST_UNREFERENCED：C99') "負例：checklist id 未被任何 requirement 引用"
$r = New-BadPack 'bad-slot' { param($p) $p.slots += 'S99' }
Assert ((-not $r.Ok) -and ($r.Errors -join ';') -match 'SLOT_NOT_IN_TEMPLATE：S99') "負例：slot 不在模板"
$r = New-BadPack 'bad-marker' { param($p) } ((Read-PsKnText -LiteralPath (Join-Path $priv 'pack-a/template-bound.md')) + "`n{{slot:S42}}`n")
Assert ((-not $r.Ok) -and ($r.Errors -join ';') -match 'MARKER_NOT_IN_SLOTS：S42') "負例：模板標記不在 slots"
$r = New-BadPack 'bad-fk' { param($p) $p.requirements[0].factKind = 'UI.NOPE' }
Assert ((-not $r.Ok) -and ($r.Errors -join ';') -match 'FACTKIND_UNKNOWN') "負例：factKind 不在目錄"
$r = New-BadPack 'bad-prop' { param($p) $p.requirements[0] | Add-Member -NotePropertyName 'properties' -NotePropertyValue @('nope') }
Assert ((-not $r.Ok) -and ($r.Errors -join ';') -match 'PROPERTY_UNKNOWN') "負例：property 不在目錄"
$r = New-BadPack 'bad-cycle' { param($p) $p.requirements[0].applicability = ([pscustomobject]@{ op = 'FACT_TRUE'; fact = 'UI.NAVIGATION.entries' }); $p.requirements[1].applicability = ([pscustomobject]@{ op = 'FACT_TRUE'; fact = 'UI.COMPONENT_IDENTITY.origin' }) }
Assert ((-not $r.Ok) -and ($r.Errors -join ';') -match 'CYCLE') "負例：applicability 依賴成環（R01↔R02）"
$r = New-BadPack 'bad-req' { param($p) $p.requirements[0].required = 'yes' }
Assert ((-not $r.Ok) -and ($r.Errors -join ';') -match 'REQUIRED_NOT_BOOL') "負例：required 非 bool"
$r = New-BadPack 'bad-op' { param($p) $p.requirements[0].applicability = ([pscustomobject]@{ op = 'MAYBE' }) }
Assert ((-not $r.Ok) -and ($r.Errors -join ';') -match 'BAD_OP') "負例：applicability op 不在值域"
$r = New-BadPack 'bad-ref' { param($p) $p.requirements[0].applicability = ([pscustomobject]@{ op = 'FACT_TRUE'; fact = 'GAPS.items' }) }
Assert ((-not $r.Ok) -and ($r.Errors -join ';') -match 'BAD_FACT_REF') "負例：引用的 factKind 沒有 requirement 產出"
$r = New-BadPack 'unsigned' { param($p) $p.reviewedVersion = 0 }
Assert ($r.Ok -and -not $r.Signed) "reviewedVersion ≠ packVersion：結構合法但未簽核"
$c = Invoke-Cli @{ ValidatePack = $true; Pack = 'unsigned' }
Assert ($c -eq 'SPEC1-8-01' -and $script:lastExit -eq 1) "CLI -ValidatePack 未簽核 → SPEC1-8-01 exit 1"
$c = Invoke-Cli @{ ValidatePack = $true; Pack = 'pack-a' }
Assert ($c -eq 'SPEC1-1-01' -and $script:lastExit -eq 0) "CLI -ValidatePack pack-a → SPEC1-1-01"
$c = Invoke-Cli @{ ValidatePack = $true; Pack = 'bad-dup' }
Assert ($c -match '^SPEC1-1-03-\d+$' -and $script:lastExit -eq 1) "CLI -ValidatePack 負例 → SPEC1-1-03-<n>"
$c = Invoke-Cli @{ ValidatePack = $true; Pack = 'nope' }
Assert ($c -eq 'SPEC1-1-02' -and $script:lastExit -eq 2) "CLI -ValidatePack 不存在 → SPEC1-1-02 exit 2"
$c = Invoke-Cli @{ Plan = $true; JobId = 'Bad_ID'; Component = 'TW_DEMO_A'; Pack = 'pack-a' }
Assert ($c -eq 'SPEC1-9-05' -and $script:lastExit -eq 2) "jobId 文法：大寫／底線 → SPEC1-9-05 exit 2"
$c = Invoke-Cli @{ Plan = $true; JobId = 'j1' }
Assert ($c -eq 'SPEC1-9-01' -and $script:lastExit -eq 2) "缺 -Component／-Pack → SPEC1-9-01"
$c = Invoke-Cli @{}
Assert ($c -eq 'SPEC1-9-01' -and $script:lastExit -eq 2) "無模式 → SPEC1-9-01"

# ── 情境 2：-Plan（身分、EXTRACT facts、COMPOSE units、applicability 三值）──
Write-Host "情境 2：規劃（EXTRACT facts／COMPOSE units／三值 applicability）"
$c = Invoke-Cli @{ Plan = $true; JobId = 'job-a'; Component = 'tw_demo_a'; Pack = 'pack-a' }
Assert ($c -match '^SPEC1-2-01-\d+$' -and $script:lastExit -eq 0) "-Plan pack-a → SPEC1-2-01-<units>（Component 大小寫不敏感）"
$dirsA = Get-PsSpDirs -Root $root -PrivateRoot $priv -RuntimeRoot $rt -PackId 'pack-a' -JobId 'job-a'
$jobA = Read-PsSpJob -Dirs $dirsA
$planA = Read-PsSpPlan -Dirs $dirsA -PlanRef ([string]$jobA.currentPlanRef)
Assert ($null -ne $planA -and [string]$planA.domain -eq '測試領域' -and [string]$planA.component -eq 'TW_DEMO_A' -and @($planA.identity.files).Count -eq 1) "plan.json：領域唯一、Component 正規化、主檔 1"
Assert ([System.IO.File]::Exists((Join-Path (Join-Path $dirsA.Plans ([string]$jobA.currentPlanRef)) 'plan.json')) -and [string]$jobA.phase -eq 'PLANNED') "plans/<planHash>/plan.json 存在；job.phase=PLANNED"
$factsA = @{}
foreach ($f in @($planA.facts)) { $factsA[[string]$f.factKind] = $f }
Assert ($factsA.ContainsKey('UI.COMPONENT_IDENTITY') -and [string]$factsA['UI.COMPONENT_IDENTITY'].value.origin -eq 'CUSTOM_PREFIX' -and [string]$factsA['UI.COMPONENT_IDENTITY'].value.functionName -eq '示範功能' -and [string]$factsA['UI.COMPONENT_IDENTITY'].grade -eq 'AUDITED_CLEAN') "EXTRACT UI.COMPONENT_IDENTITY：Origin／功能名（00-overview）／等級 AUDITED_CLEAN"
Assert ($factsA.ContainsKey('UI.FIELD_INVENTORY') -and @($factsA['UI.FIELD_INVENTORY'].value.fields).Count -eq 2 -and [string]$factsA['UI.FIELD_INVENTORY'].closure -eq 'ROWS') "EXTRACT UI.FIELD_INVENTORY：2 列"
Assert ($factsA.ContainsKey('BEHAVIOR.RULES') -and @($factsA['BEHAVIOR.RULES'].value.rules).Count -eq 3 -and @($factsA['BEHAVIOR.RULES'].evidenceRefs).Count -eq 2 -and [bool]$factsA['BEHAVIOR.RULES'].evidenceRefs[0].resolved) "EXTRACT BEHAVIOR.RULES：3 條、引用附錄 #1／#3 可解"
Assert ($factsA.ContainsKey('DATA.FLOW') -and @($factsA['DATA.FLOW'].value.tables).Count -eq 2 -and @($factsA['DATA.FLOW'].value.writes).Count -eq 1) "EXTRACT DATA.FLOW：2 表、1 寫入"
Assert ($factsA.ContainsKey('PROCESS.EXECUTION') -and @($factsA['PROCESS.EXECUTION'].value.callees).Count -eq 1 -and [string]$factsA['PROCESS.EXECUTION'].value.callees[0].object -eq 'TW_DEMO_IMP' -and (@($factsA['PROCESS.EXECUTION'].sourceRefs | Where-Object { $_.role -eq 'CALLEE' })).Count -eq 1) "EXTRACT PROCESS.EXECUTION：follow 一跳 callee（AE）進 sourceRefs"
Assert ($factsA.ContainsKey('RELATED.OBJECTS') -and (@($factsA['RELATED.OBJECTS'].value.objects | Where-Object { $_.name -eq 'PS_JOB' })[0].classification -eq 'DEPENDENCY') -and (@($factsA['RELATED.OBJECTS'].value.objects | Where-Object { $_.name -eq 'PS_DEMO_TBL' })[0].classification -eq 'UNCLASSIFIED')) "EXTRACT RELATED.OBJECTS：domainGate 分類照抄（DEPENDENCY／UNCLASSIFIED）"
Assert ($factsA.ContainsKey('UI.NAVIGATION') -and @($factsA['UI.NAVIGATION'].value.entries).Count -eq 1 -and @($factsA['UI.NAVIGATION'].value.technicalMenu).Count -eq 1) "EXTRACT UI.NAVIGATION：導覽入口表 1 列＋Technical Menu"
$reqA = @{}
foreach ($q in @($planA.requirements)) { $reqA[[string]$q.id] = $q }
Assert ([string]$reqA['R20'].applicable -eq 'TRUE' -and [string]$reqA['R17'].applicable -eq 'UNKNOWN' -and [string]$reqA['R18'].applicable -eq 'TRUE') "applicability：FACT_TRUE 對 EXTRACT 事實＝TRUE；自我引用 COMPOSE 事實＝UNKNOWN（不變 N/A）"
$unitsA = @($planA.units)
$uk = @($unitsA | ForEach-Object { [string]$_.unitId })
Assert ($unitsA.Count -eq 4 -and ($uk -contains 'R17.TW_DEMO_A') -and ($uk -contains 'R18.TW_DEMO_A@PS_DEMO_TBL') -and ($uk -contains 'R18.TW_DEMO_A@PS_JOB') -and (@($uk | Where-Object { $_ -match '^R20\.TW_DEMO_A@行為邏輯:L\d+-\d+$' })).Count -eq 1) "COMPOSE units：subjectKey 文法（<C>／<C>@<Record>／<C>@行為邏輯:L<a>-<b>）"
$u17 = @($unitsA | Where-Object { $_.unitId -eq 'R17.TW_DEMO_A' })[0]
Assert (@($u17.readSet).Count -eq 2 -and (@($u17.readSet | Where-Object { $_.role -eq 'CALLEE' })).Count -eq 1 -and @($u17.items).Count -eq 8) "DATA.FILE_INPUT unit：讀取集合含 callee 節；條目＝行為 3＋資料流 2＋執行 1＋callee 執行 1＋callee 資料流 1"
Assert ((@($u17.readSet[0].sections | Where-Object { $_.name -eq 'Evidence附錄' })).Count -eq 1 -and [string]$u17.readSet[0].sections[0].hash -match '^[0-9A-F]{64}$') "讀取集合：每檔含 Evidence 附錄；每節內容 hash"
$c = Invoke-Cli @{ Plan = $true; JobId = 'job-a'; Component = 'TW_DEMO_A'; Pack = 'pack-a' }
Assert ($c -match '^SPEC1-2-02-\d+$') "同輸入再 -Plan → planHash 相同 → SPEC1-2-02（重用）"
$c = Invoke-Cli @{ Plan = $true; JobId = 'job-x'; Component = 'TW_NOPE'; Pack = 'pack-a' }
Assert ($c -eq 'SPEC1-2-03' -and $script:lastExit -eq 1) "Component 無 NN 且無 DomainHint → SPEC1-2-03"

# ── 情境 3：-Run（假 worker：manifest／context／驗收／收據）────────
Write-Host "情境 3：外環派工與驗收（假 worker）"
$env:PS_SPEC_FAKE_MODE = 'valid'
$c = Invoke-Cli @{ Run = $true; JobId = 'job-a'; MaxSessions = '1'; FakeWorker = $fake }
Assert ($c -match '^SPEC1-3-02-\d+$' -and $script:lastExit -eq 0) "-Run MaxSessions=1 → 一個 session、仍有 pending → SPEC1-3-02-<n>"
$a1 = Join-Path $dirsA.Attempts 'a0001'
Assert ([System.IO.File]::Exists((Join-Path $a1 'input.json')) -and [System.IO.File]::Exists((Join-Path $a1 'manifest.md')) -and [System.IO.File]::Exists((Join-Path $a1 'fragment.md')) -and [System.IO.File]::Exists((Join-Path $a1 'verdict.json')) -and [System.IO.File]::Exists((Join-Path $a1 'outcome.json'))) "attempt a0001：input.json／manifest.md／context／fragment.md／verdict／outcome"
$man = Read-PsKnText -LiteralPath (Join-Path $a1 'manifest.md')
Assert ($man -match '(?m)^\| 1 \| 03-TW_DEMO_A\.md \| \d+ \| 行為 \|$' -and $man -match '事實表頭（逐字）：\| 來源條目 \|' -and $man -notmatch '\{\{slot:' -and $man -notmatch '\[\[') "manifest：條目表（檔／列／種類）、逐字表頭、無模板標記與 wikilink"
$ctxFiles = @(Get-ChildItem -LiteralPath (Join-Path $a1 'context') -File)
$ctx1 = Read-PsKnText -LiteralPath $ctxFiles[0].FullName
Assert ($ctxFiles.Count -ge 1 -and $ctx1 -match '(?m)^L\d+ #1 \| - \*\*CONFIRMED\*\*' -and $ctx1 -match '(?m)^L\d+ E1 \| \| 1 \|' -and (Get-PsKnLines -Text $ctx1).Count -le 150) "context 切片：每行 L<行號> [#條目|E附錄列號] | 原文；≤150 行"
$v1 = Read-PsSpJsonFile -LiteralPath (Join-Path $a1 'verdict.json')
Assert ([string]$v1.code -eq '4-01' -and [bool]$v1.counted -and [string]$v1.closure -eq 'COMPLETE') "verdict：4-01、計入 attempt、closure COMPLETE（外環算）"
$rcs = @(Get-ChildItem -LiteralPath $dirsA.Receipts -File)
Assert ($rcs.Count -eq 1 -and $rcs[0].Name -match '^R17\.TW_DEMO_A\.[0-9a-f]{16}\.json$') "receipt 檔名含 inputFingerprint 前 16 hex"
$rc1 = Read-PsSpJsonFile -LiteralPath $rcs[0].FullName
Assert ([string]$rc1.inputFingerprint -match '^[0-9A-F]{64}$' -and [string]$rc1.fragmentHash -match '^[0-9A-F]{64}$' -and ([string]$rc1.input) -match '"fingerprint"' -and [string]$rc1.attemptPath -eq 'attempts/a0001') "receipt：inputFingerprint／fragmentHash／input.json 全文／attempt 相對路徑"
$env:PS_SPEC_FAKE_MODE = 'valid'
$c = Invoke-Cli @{ Run = $true; JobId = 'job-a'; MaxSessions = '9'; FakeWorker = $fake }
Assert ($c -match '^SPEC1-3-01-4$' -and $script:lastExit -eq 0) "-Run 派完剩餘單位 → SPEC1-3-01-4（全部有收據）READY"
$jobA = Read-PsSpJob -Dirs $dirsA
Assert ([string]$jobA.phase -eq 'READY') "job.phase=READY"
$c = Invoke-Cli @{ Run = $true; JobId = 'job-a'; FakeWorker = $fake }
Assert ($c -eq 'SPEC1-3-01-4' -and @(Get-ChildItem -LiteralPath $dirsA.Attempts -Directory).Count -eq 4) "再 -Run＝no-op（不新增 attempt）"

# ── 情境 4：render／gate／parity／來源重驗 ─────────────────────────
Write-Host "情境 4：render parity、gate、來源重驗"
$c = Invoke-Cli @{ Render = $true; JobId = 'job-a' }
Assert ($c -eq 'SPEC1-6-01' -and $script:lastExit -eq 0 -and ($script:lastOut.Trim() -eq 'SPEC1-6-01')) "-Render → SPEC1-6-01，且只印結論碼"
$curA = Read-PsSpJsonFile -LiteralPath $dirsA.CurrentFile
$outA = Join-Path $dirsA.Outputs (([string]$curA.generation).Substring(0, 16).ToLowerInvariant())
$spec1 = [System.IO.File]::ReadAllBytes((Join-Path $outA 'spec.md'))
$trace1 = [System.IO.File]::ReadAllBytes((Join-Path $outA 'trace.md'))
$gate1 = [System.IO.File]::ReadAllBytes((Join-Path $outA 'gate.json'))
$c = Invoke-Cli @{ Render = $true; JobId = 'job-a' }
$spec2 = [System.IO.File]::ReadAllBytes((Join-Path $outA 'spec.md'))
$trace2 = [System.IO.File]::ReadAllBytes((Join-Path $outA 'trace.md'))
$gate2 = [System.IO.File]::ReadAllBytes((Join-Path $outA 'gate.json'))
Assert ($c -eq 'SPEC1-6-01' -and [System.Linq.Enumerable]::SequenceEqual($spec1, $spec2) -and [System.Linq.Enumerable]::SequenceEqual($trace1, $trace2) -and [System.Linq.Enumerable]::SequenceEqual($gate1, $gate2)) "render parity：重 render spec.md／trace.md／gate.json byte 相同"
$specText = [System.Text.Encoding]::UTF8.GetString($spec1)
Assert ($specText -notmatch '\{\{slot:' -and $specText -match '## 1\. 功能識別' -and $specText -match '\| 物件 \| TW_DEMO_A \|' -and $specText -match '\| DEMO_STATUS \|' -and $specText -match '(?m)^\| 來源條目 \| 觸發 \|') "spec.md：標記全部置換、模板章節保留、EXTRACT 表與 COMPOSE 表都在"
$c = Invoke-Cli @{ Gate = $true; JobId = 'job-a' }
Assert ($c -eq 'SPEC1-7-01' -and $script:lastExit -eq 0 -and ($script:lastOut.Trim() -eq 'SPEC1-7-01')) "-Gate → SPEC_COMPLETE（SPEC1-7-01；只印結論碼）"
$g = Read-PsSpJsonFile -LiteralPath (Join-Path $outA 'gate.json')
Assert ([string]$g.verdict -eq 'SPEC_COMPLETE' -and [int]$g.unknownDebt -eq 0 -and (@($g.checklist | Where-Object { -not $_.covered })).Count -eq 0 -and [bool]$g.signed) "gate.json：verdict／UNKNOWN debt 0／checklist 全覆蓋／signed"
# 來源改變 → render 前重驗
$nnA = Join-Path $domA '03-TW_DEMO_A.md'
$orig = [System.IO.File]::ReadAllBytes($nnA)
$t = [System.IO.File]::ReadAllText($nnA)
[System.IO.File]::WriteAllText($nnA, $t.Replace('| EFFDT | 生效日 | Date |  |  |', '| EFFDT | 生效日 | Date |  |  |' + "`n" + '| DEMO_NOTE | 備註 | Char |  |  |'), (New-Object System.Text.UTF8Encoding($false)))
$c = Invoke-Cli @{ Render = $true; JobId = 'job-a' }
$curA2 = Read-PsSpJsonFile -LiteralPath $dirsA.CurrentFile
Assert ($c -match '^SPEC1-6-02-\d+$' -and $script:lastExit -eq 1 -and [string]$curA2.generation -eq [string]$curA.generation) "來源改變 → -Render SPEC1-6-02 SOURCE_CHANGED、current.json 不換"
$c = Invoke-Cli @{ Run = $true; JobId = 'job-a'; FakeWorker = $fake }
Assert ($c -eq 'SPEC1-3-01-4' -and $script:lastExit -eq 0) "畫面與欄位改變不在任何 COMPOSE 讀取集合 → -Run 收據全部仍有效（指紋只看讀取節內容）"
$c = Invoke-Cli @{ Doctor = $true; JobId = 'job-a'; Drill = '6-02' }
$tuples = @(($script:lastOut -replace "`r", '') -split "`n" | Where-Object { $_ -match '^D6-02 ' })
Assert ($tuples.Count -ge 1 -and (@($tuples | Where-Object { $_ -notmatch '^D\d-\d\d( [A-Za-z0-9_.@:=~-]+)+$' -or $_ -match '/|\.md|TW_|[\u4e00-\u9fff]' })).Count -eq 0) "drill 6-02：tuple 只有 opaque id／factKind／模式／封閉值（無路徑、物件名、CJK）"
[System.IO.File]::WriteAllBytes($nnA, $orig)
Write-AuditDone
$c = Invoke-Cli @{ Render = $true; JobId = 'job-a' }
Assert ($c -eq 'SPEC1-6-01') "來源還原 → -Render 恢復"

# ── 情境 5：假 worker 負例（不合格→計 attempt→BLOCKED；超長→拆分不計；含模板行；來源改變不計；缺檔）──
Write-Host "情境 5：驗收負例、attempts 計數、容量事件、來源快照"
$c = Invoke-Cli @{ Plan = $true; JobId = 'job-n'; Component = 'TW_DEMO_A'; Pack = 'pack-a' }
$dirsN = Get-PsSpDirs -Root $root -PrivateRoot $priv -RuntimeRoot $rt -PackId 'pack-a' -JobId 'job-n'
$env:PS_SPEC_FAKE_MODE = 'invalid'
$c = Invoke-Cli @{ Run = $true; JobId = 'job-n'; MaxSessions = 1; FakeWorker = $fake }
$vN1 = Read-PsSpJsonFile -LiteralPath (Join-Path (Join-Path $dirsN.Attempts 'a0001') 'verdict.json')
Assert ($c -match '^SPEC1-3-02-' -and [string]$vN1.code -eq '4-02' -and [bool]$vN1.counted -and (@($vN1.reasons) -contains 'ITEM_UNKNOWN') -and (@($vN1.reasons) -contains 'EVIDENCE_UNKNOWN')) "不合格片段（來源條目不在列舉、證據不在讀取集合）→ 4-02、計入 attempt"
Assert (-not [System.IO.Directory]::Exists($dirsN.Receipts) -or @(Get-ChildItem -LiteralPath $dirsN.Receipts -File).Count -eq 0) "不合格 → 無收據"
$c = Invoke-Cli @{ Run = $true; JobId = 'job-n'; MaxSessions = 1; FakeWorker = $fake }
$vN2 = Read-PsSpJsonFile -LiteralPath (Join-Path (Join-Path $dirsN.Attempts 'a0002') 'verdict.json')
Assert ([string]$vN2.unitId -eq [string]$vN1.unitId -and [bool]$vN2.counted) "第二次仍不合格（同單位）→ 計入第 2 次 attempt"
$c = Invoke-Cli @{ Run = $true; JobId = 'job-n'; MaxSessions = 1; FakeWorker = $fake }
$vN3 = Read-PsSpJsonFile -LiteralPath (Join-Path (Join-Path $dirsN.Attempts 'a0003') 'verdict.json')
Assert ([string]$vN3.unitId -ne [string]$vN1.unitId) "attempts≥2 → 該單位 BLOCKED、外環改派下一單位"
$env:PS_SPEC_FAKE_MODE = 'long'
$c = Invoke-Cli @{ Run = $true; JobId = 'job-n'; MaxSessions = 1; FakeWorker = $fake }
$vN4 = Read-PsSpJsonFile -LiteralPath (Join-Path (Join-Path $dirsN.Attempts 'a0004') 'verdict.json')
$splitDir = Join-Path (Join-Path $dirsN.Plans ([string](Read-PsSpJob -Dirs $dirsN).currentPlanRef)) 'splits'
$splits = @(Get-ChildItem -LiteralPath $splitDir -File -ErrorAction SilentlyContinue)
Assert ([string]$vN4.code -eq '4-05' -and -not [bool]$vN4.counted -and $splits.Count -eq 1) "＞150 行＝容量事件：不記 attempt、寫 splits/<unit>.json"
$sp = Read-PsSpJsonFile -LiteralPath $splits[0].FullName
Assert (@($sp.parts).Count -eq 2 -and (@($sp.parts[0].items).Count + @($sp.parts[1].items).Count) -eq @(@($vN4.unitId) | ForEach-Object { 0 })[0] + (@((Read-PsSpPlan -Dirs $dirsN -PlanRef ([string](Read-PsSpJob -Dirs $dirsN).currentPlanRef)).units | Where-Object { $_.unitId -eq [string]$vN4.unitId })[0].items).Count) "拆分：兩個 part、條目對半且總數不變"
$env:PS_SPEC_FAKE_MODE = 'valid'
$c = Invoke-Cli @{ Run = $true; JobId = 'job-n'; MaxSessions = 2; FakeWorker = $fake }
$rcsN = @(Get-ChildItem -LiteralPath $dirsN.Receipts -File | Where-Object { $_.Name -match '~p[12]\.' })
Assert ($rcsN.Count -eq 2) "拆分後兩個 part 各自派工、收據鍵含 ~p<n>"
$env:PS_SPEC_FAKE_MODE = 'template'
$c = Invoke-Cli @{ Run = $true; JobId = 'job-n'; MaxSessions = 1; FakeWorker = $fake }
$last = @(Get-ChildItem -LiteralPath $dirsN.Attempts -Directory | Sort-Object Name)[-1]
$vT = Read-PsSpJsonFile -LiteralPath (Join-Path $last.FullName 'verdict.json')
Assert ([string]$vT.code -eq '4-02' -and (@($vT.reasons) -contains 'TEMPLATE_LEAK')) "片段含模板副本原文行 → TEMPLATE_LEAK 不合格"
$env:PS_SPEC_FAKE_MODE = 'missing'
$c = Invoke-Cli @{ Run = $true; JobId = 'job-n'; MaxSessions = 1; FakeWorker = $fake }
$last = @(Get-ChildItem -LiteralPath $dirsN.Attempts -Directory | Sort-Object Name)[-1]
$vM = Read-PsSpJsonFile -LiteralPath (Join-Path $last.FullName 'verdict.json')
Assert ([string]$vM.code -eq '4-02' -and (@($vM.reasons) -contains 'MISSING') -and [bool]$vM.counted) "worker 健康結束但沒寫片段 → MISSING、計入 attempt"
$env:PS_SPEC_FAKE_MODE = 'valid'
$c = Invoke-Cli @{ Run = $true; JobId = 'job-n'; MaxSessions = 9; FakeWorker = $fake }
Assert ($c -match '^SPEC1-4-03-2$' -and $script:lastExit -eq 1 -and [string](Read-PsSpJob -Dirs $dirsN).phase -eq 'BLOCKED') "其餘單位完成後：仍有 2 個 BLOCKED 單位 → SPEC1-4-03-2、phase BLOCKED"
$c = Invoke-Cli @{ Doctor = $true; JobId = 'job-n'; Drill = '4-03' }
Assert ($c -eq 'SPEC1-0-05-2' -and $script:lastOut -match '(?m)^D4-03 R17 DATA\.FILE_INPUT COMPOSE a=2 c=BLOCKED$' -and $script:lastOut -match '(?m)^D4-03 R18 DATA\.RECORD_USAGE COMPOSE a=2 c=BLOCKED$') "drill 4-03：兩筆 tuple（a=2 c=BLOCKED；只有 opaque id／factKind／模式／計數）"
$c = Invoke-Cli @{ Doctor = $true; JobId = 'job-n'; Drill = '4-02' }
$tup4 = @(($script:lastOut -replace "`r", '') -split "`n" | Where-Object { $_ -match '^D4-02 ' })
Assert ($tup4.Count -eq 5 -and (@($tup4 | Where-Object { $_ -notmatch '^D4-02 R\d+ [A-Z_.]+ COMPOSE a\d{4} n=\d+ c=[A-Z]+ r=[A-Z_,]+$' })).Count -eq 0) "drill 4-02：五筆不合格 tuple（attemptId／行數／closure／原因碼）"
$c = Invoke-Cli @{ Gate = $true; JobId = 'job-n' }
Assert ($c -match '^SPEC1-7-03-\d+$' -and $script:lastExit -eq 1) "gate：required 單位 BLOCKED → verdict BLOCKED（SPEC1-7-03-<n>）"
# 來源在 session 期間改變 → 拒收、不記 attempt
$c = Invoke-Cli @{ Plan = $true; JobId = 'job-m'; Component = 'TW_DEMO_A'; Pack = 'pack-a' }
$dirsM = Get-PsSpDirs -Root $root -PrivateRoot $priv -RuntimeRoot $rt -PackId 'pack-a' -JobId 'job-m'
$env:PS_SPEC_FAKE_MODE = 'mutate'
$c = Invoke-Cli @{ Run = $true; JobId = 'job-m'; MaxSessions = 1; FakeWorker = $fake }
$vMu = Read-PsSpJsonFile -LiteralPath (Join-Path (Join-Path $dirsM.Attempts 'a0001') 'verdict.json')
$inMu = Read-PsSpJsonFile -LiteralPath (Join-Path (Join-Path $dirsM.Attempts 'a0001') 'input.json')
Assert ($c -eq 'SPEC1-4-04-1' -and $script:lastExit -eq 1 -and [string]$vMu.code -eq '4-04' -and -not [bool]$vMu.counted -and -not [bool]$vMu.fingerprintMatch) "session 期間來源改變 → input.json 指紋不符 → 拒收、不記 attempt、SPEC1-4-04"
Assert ([string]$inMu.fingerprint -match '^[0-9A-F]{64}$' -and @($inMu.files).Count -ge 1 -and [string]$inMu.files[0].hash -match '^[0-9A-F]{64}$' -and [string]$inMu.files[0].sections[0].hash -match '^[0-9A-F]{64}$') "input.json：每檔 hash＋每節內容 hash＋指紋（派工前 create-only）"
Assert ((Write-PsKnCreateOnlyText -LiteralPath (Join-Path (Join-Path $dirsM.Attempts 'a0001') 'input.json') -Text 'x') -eq $false) "input.json create-only（不可覆寫）"
$env:PS_SPEC_FAKE_MODE = 'valid'
[System.IO.File]::WriteAllBytes($nnA, $orig)
Write-AuditDone
# ── 情境 6：re-plan 重用收據 ─────────────────────────────────────
Write-Host "情境 6：來源改變後 re-plan，未受影響單位的收據重用"
$c = Invoke-Cli @{ Run = $true; JobId = 'job-a'; MaxSessions = 9; FakeWorker = $fake }
Assert ($c -eq 'SPEC1-3-01-4') "job-a 現況（來源已還原後）：4 收據齊全"
$t = [System.IO.File]::ReadAllText($nnA)
[System.IO.File]::WriteAllText($nnA, $t.Replace('| PS_JOB | READ | 查詢 | INFERRED |', '| PS_JOB | READ | 查詢 | INFERRED |' + "`n" + '| PS_DEMO_LOG | INSERT | 存檔 PeopleCode | CONFIRMED |'), (New-Object System.Text.UTF8Encoding($false)))
Write-AuditDone
$c = Invoke-Cli @{ Run = $true; JobId = 'job-a'; FakeWorker = $fake }
Assert ($c -match '^SPEC1-4-04-') "資料流改變（新增一列）→ -Run 要求重規劃"
$before = @(Get-ChildItem -LiteralPath $dirsA.Attempts -Directory).Count
$c = Invoke-Cli @{ Plan = $true; JobId = 'job-a'; Component = 'TW_DEMO_A'; Pack = 'pack-a' }
$jobA2 = Read-PsSpJob -Dirs $dirsA
Assert ($c -match '^SPEC1-2-01-5$' -and [string]$jobA2.currentPlanRef -ne [string]$jobA.currentPlanRef) "re-plan → 新 planHash、單位 5（多一個 Record）"
$c = Invoke-Cli @{ Run = $true; JobId = 'job-a'; MaxSessions = 9; FakeWorker = $fake }
$after = @(Get-ChildItem -LiteralPath $dirsA.Attempts -Directory).Count
Assert ($c -eq 'SPEC1-3-01-5' -and ($after - $before) -eq 4) "re-plan 後只派受影響單位（行為邏輯單位不變→收據重用；資料流相關 4 單位重派）"
$c = Invoke-Cli @{ Render = $true; JobId = 'job-a' }
$c2 = Invoke-Cli @{ Gate = $true; JobId = 'job-a' }
Assert ($c -eq 'SPEC1-6-01' -and $c2 -eq 'SPEC1-7-01') "re-plan 後 render／gate 恢復 SPEC_COMPLETE"
# ── 情境 7：KnowledgeNeed（WAITING_KNOWLEDGE／WAITING_AUDIT 不重送；hash≠hashAfter 才 -Resubmit）──
Write-Host "情境 7：KnowledgeNeed 消費端規則"
$reqDir = Join-Path $research 'supplemental/requests'
$resDir = Join-Path $research 'supplemental/results'
$c = Invoke-Cli @{ Plan = $true; JobId = 'job-b'; Component = 'TW_DEMO_B'; Pack = 'pack-a' }
$dirsB = Get-PsSpDirs -Root $root -PrivateRoot $priv -RuntimeRoot $rt -PackId 'pack-a' -JobId 'job-b'
$jobB = Read-PsSpJob -Dirs $dirsB
$planB = Read-PsSpPlan -Dirs $dirsB -PlanRef ([string]$jobB.currentPlanRef)
$reqFiles = @(Get-ChildItem -LiteralPath $reqDir -File -ErrorAction SilentlyContinue)
$r01 = @($planB.requirements | Where-Object { $_.id -eq 'R01' })[0]
Assert ($c -match '^SPEC1-2-01-' -and [string]$jobB.phase -eq 'WAITING_KNOWLEDGE' -and $reqFiles.Count -ge 1 -and [string]$r01.state -eq 'WAITING_KNOWLEDGE' -and [string]$r01.needs[0].reason -eq 'GRADE' -and [string]$r01.needs[0].requestId -match '^S-[0-9a-f]{24}-g1$') "TW_DEMO_B UNAUDITED＋R01 policy AUDITED → GRADE need → Submit（consumer SPEC）→ WAITING_KNOWLEDGE"
$reqObj = Read-PsSpJsonFile -LiteralPath (Join-Path $reqDir ([string]$r01.needs[0].requestId + '.json'))
Assert ([string]$reqObj.consumer.kind -eq 'SPEC' -and [string]$reqObj.consumer.jobId -eq 'job-b' -and [string]$reqObj.consumer.requirementRef -eq 'R01' -and [string]$reqObj.need.factKind -eq 'UI.COMPONENT_IDENTITY') "request：consumer=SPEC／jobId／requirementRef；need.factKind"
$nReq = $reqFiles.Count
$c = Invoke-Cli @{ Plan = $true; JobId = 'job-b'; Component = 'TW_DEMO_B'; Pack = 'pack-a' }
Assert (@(Get-ChildItem -LiteralPath $reqDir -File).Count -eq $nReq) "再 -Plan：既有 pending request 不重送"
$c = Invoke-Cli @{ Run = $true; JobId = 'job-b'; MaxSessions = 9; FakeWorker = $fake }
Assert ($c -match '^SPEC1-5-01-\d+$' -and $script:lastExit -eq 0 -and $script:lastOut -match 'WAITING_KNOWLEDGE n=') "-Run：可派單位派完後進 WAITING_KNOWLEDGE（釋放鎖、exit 0）"
$c = Invoke-Cli @{ Run = $true; JobId = 'job-b'; MaxSessions = 9; FakeWorker = $fake }
Assert ($c -match '^SPEC1-5-01-\d+$') "等待中重跑 -Run＝無新 result 即 no-op"
# 假 result：RESOLVED、hashAfter＝現況 → 等級仍 UNAUDITED → WAITING_AUDIT、不重送
$rid = [string]$r01.needs[0].requestId
$hashB = Get-PsKnFileHash -LiteralPath (Join-Path $domA '05-TW_DEMO_B.md')
$resObj = [ordered]@{ schemaVersion = 1; requestId = $rid; workKey = [string]$reqObj.workKey; domain = '測試領域'; outcome = 'RESOLVED'; dispositionCode = 'RESEARCHED'; auditRoundAtCompletion = 4; affected = @([ordered]@{ file = '05-TW_DEMO_B.md'; hashBefore = $hashB; hashAfter = $hashB; sections = @('功能定位'); evidenceRows = @(4) }); attempts = 1; completedAt = '2099-01-01T00:00:00Z' }
New-Item -ItemType Directory -Path $resDir -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $resDir ($rid + '.json')), (ConvertTo-PsKnJson -Value $resObj), (New-Object System.Text.UTF8Encoding($false)))
$c = Invoke-Cli @{ Run = $true; JobId = 'job-b'; MaxSessions = 9; FakeWorker = $fake }
Assert ($c -match '^SPEC1-5-06-\d+$' -and $script:lastExit -eq 1) "result 出現 → -Run 回報 REPLAN_REQUIRED（SPEC1-5-06）"
$c = Invoke-Cli @{ Plan = $true; JobId = 'job-b'; Component = 'TW_DEMO_B'; Pack = 'pack-a' }
$jobB = Read-PsSpJob -Dirs $dirsB
$planB = Read-PsSpPlan -Dirs $dirsB -PlanRef ([string]$jobB.currentPlanRef)
$r01 = @($planB.requirements | Where-Object { $_.id -eq 'R01' })[0]
Assert ([string]$jobB.phase -eq 'WAITING_AUDIT' -and [string]$r01.state -eq 'WAITING_AUDIT' -and @(Get-ChildItem -LiteralPath $reqDir -File).Count -eq $nReq) "RESOLVED 但等級低於 evidencePolicy → WAITING_AUDIT（SPEC1-5-04）、不重送"
$c = Invoke-Cli @{ Run = $true; JobId = 'job-b'; MaxSessions = 9; FakeWorker = $fake }
Assert ($c -match '^SPEC1-5-04-\d+$' -and $script:lastExit -eq 0) "-Run 在 WAITING_AUDIT：SPEC1-5-04"
$compB = Get-PsSuppCompletion -Root $root -RequestId $rid
Assert ($compB.Researched -and -not $compB.Audited) "完成邊界：RESEARCHED 但未 AUDITED（等級 UNAUDITED）"
# 事實仍缺且 hash≠hashAfter → -Resubmit（generation 2）；缺節 fact：TW_DEMO_B 的 UI.NAVIGATION 用 pack-c（缺 功能定位 節）
$packC = Join-Path $priv 'pack-c'
New-Item -ItemType Directory -Path $packC -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $packC 'pack.json'), '{ "schemaVersion": 1, "packId": "pack-c", "packVersion": 1, "reviewedVersion": 1, "template": "t.md", "slots": ["S01"], "checklist": ["C01"], "requirements": [ { "id": "R01", "slot": "S01", "checklistRefs": ["C01"], "factKind": "SECURITY.ACCESS", "required": true, "applicability": { "op": "ALWAYS" }, "cardinality": "ANY", "evidencePolicy": "ANY" } ] }', (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $packC 't.md'), "# T`n`n{{slot:S01}}`n", (New-Object System.Text.UTF8Encoding($false)))
$nnB = Join-Path $domA '05-TW_DEMO_B.md'
$tB = [System.IO.File]::ReadAllText($nnB)
[System.IO.File]::WriteAllText($nnB, $tB.Replace('TW_DEMO_PL（Permission List）。', '<!-- 無 -->'), (New-Object System.Text.UTF8Encoding($false)))
$c = Invoke-Cli @{ Plan = $true; JobId = 'job-c'; Component = 'TW_DEMO_B'; Pack = 'pack-c' }
$dirsC = Get-PsSpDirs -Root $root -PrivateRoot $priv -RuntimeRoot $rt -PackId 'pack-c' -JobId 'job-c'
$planC = Read-PsSpPlan -Dirs $dirsC -PlanRef ([string](Read-PsSpJob -Dirs $dirsC).currentPlanRef)
$needC = @($planC.requirements)[0].needs[0]
Assert ([string]$needC.reason -eq 'MISSING' -and [string]$needC.state -eq 'WAITING_KNOWLEDGE' -and [string]$needC.requestId -match '-g1$') "權限節空洞 → MISSING need → 新 request g1"
$ridC = [string]$needC.requestId
$reqC = Read-PsSpJsonFile -LiteralPath (Join-Path $reqDir ($ridC + '.json'))
$resC = [ordered]@{ schemaVersion = 1; requestId = $ridC; workKey = [string]$reqC.workKey; domain = '測試領域'; outcome = 'PARTIAL'; dispositionCode = 'RESEARCHED'; auditRoundAtCompletion = 4; affected = @([ordered]@{ file = '05-TW_DEMO_B.md'; hashBefore = 'X'; hashAfter = 'DEADBEEF'; sections = @('權限'); evidenceRows = @() }); attempts = 1; completedAt = '2099-01-01T00:00:00Z' }
[System.IO.File]::WriteAllText((Join-Path $resDir ($ridC + '.json')), (ConvertTo-PsKnJson -Value $resC), (New-Object System.Text.UTF8Encoding($false)))
$c = Invoke-Cli @{ Plan = $true; JobId = 'job-c'; Component = 'TW_DEMO_B'; Pack = 'pack-c' }
$planC = Read-PsSpPlan -Dirs $dirsC -PlanRef ([string](Read-PsSpJob -Dirs $dirsC).currentPlanRef)
$needC = @($planC.requirements)[0].needs[0]
Assert ([string]$needC.requestId -match '-g2$' -and [System.IO.File]::Exists((Join-Path $reqDir ($ridC -replace '-g1$', '-g2.json')))) "result 存在但 hash≠hashAfter 且事實仍缺 → -Resubmit（generation 2）"
$resC2 = [ordered]@{ schemaVersion = 1; requestId = ($ridC -replace '-g1$', '-g2'); workKey = [string]$reqC.workKey; domain = '測試領域'; outcome = 'UNRESOLVED'; dispositionCode = 'NO_EVIDENCE'; auditRoundAtCompletion = 4; affected = @(); attempts = 2; completedAt = '2099-01-02T00:00:00Z' }
[System.IO.File]::WriteAllText((Join-Path $resDir (($ridC -replace '-g1$', '-g2') + '.json')), (ConvertTo-PsKnJson -Value $resC2), (New-Object System.Text.UTF8Encoding($false)))
$c = Invoke-Cli @{ Plan = $true; JobId = 'job-c'; Component = 'TW_DEMO_B'; Pack = 'pack-c' }
$c2 = Invoke-Cli @{ Run = $true; JobId = 'job-c'; FakeWorker = $fake }
Assert ($c2 -match '^SPEC1-5-05-\d+$' -and $script:lastExit -eq 1 -and [string](Read-PsSpJob -Dirs $dirsC).phase -eq 'BLOCKED') "UNRESOLVED → BLOCKED_KNOWLEDGE（SPEC1-5-05）"
$c = Invoke-Cli @{ Render = $true; JobId = 'job-c' }
$c2 = Invoke-Cli @{ Gate = $true; JobId = 'job-c' }
Assert ($c -eq 'SPEC1-6-01' -and $c2 -match '^SPEC1-7-03-') "BLOCKED_KNOWLEDGE 的 required requirement → gate BLOCKED"
[System.IO.File]::WriteAllText($nnB, $tB, (New-Object System.Text.UTF8Encoding($false)))
# ── 情境 8：pack-b 對同一 NN 產不同 spec；UNKNOWN debt；drill 7-xx ──
Write-Host "情境 8：兩套 pack 不同 spec、UNKNOWN debt、gate drill"
$c = Invoke-Cli @{ Plan = $true; JobId = 'job-p'; Component = 'TW_DEMO_A'; Pack = 'pack-b' }
$dirsP = Get-PsSpDirs -Root $root -PrivateRoot $priv -RuntimeRoot $rt -PackId 'pack-b' -JobId 'job-p'
$planP = Read-PsSpPlan -Dirs $dirsP -PlanRef ([string](Read-PsSpJob -Dirs $dirsP).currentPlanRef)
$rP = @{}
foreach ($q in @($planP.requirements)) { $rP[[string]$q.id] = $q }
Assert ($c -match '^SPEC1-2-01-2$' -and [string]$rP['R09'].applicable -eq 'TRUE' -and [string]$rP['R19'].state -eq 'UNSUPPORTED' -and [string]$rP['R16'].applicable -eq 'UNKNOWN' -and @($planP.units | Where-Object { $_.unitId -eq 'R09.TW_DEMO_A@PS_DEMO_TBL' }).Count -eq 1) "pack-b：ALL／NOT 條件＝TRUE；UNSUPPORTED；context.record 只出一個 RECORD_USAGE 單位；DATA.FILE_OUTPUT 自我引用＝UNKNOWN"
$f07 = @($planP.facts | Where-Object { $_.factKind -eq 'ENTITY.DETAIL' })
Assert ($f07.Count -eq 1 -and [string]$f07[0].subject -eq 'PS_DEMO_TBL' -and [string]$f07[0].grade -eq 'AUDITED_CLEAN' -and [int]$f07[0].value.observations -eq 2 -and (@($rP['R07'].needs | Where-Object { $_.target.type -eq 'RECORD' -and $_.target.name -eq 'JOB' })).Count -eq 1) "ENTITY.DETAIL：PS_DEMO_TBL 有 wiki（verified→AUDITED_CLEAN、2 Observations）；PS_JOB 無 wiki → RECORD need"
$c = Invoke-Cli @{ Render = $true; JobId = 'job-p' }
$c2 = Invoke-Cli @{ Gate = $true; JobId = 'job-p' }
$curP = Read-PsSpJsonFile -LiteralPath $dirsP.CurrentFile
$outP = Join-Path $dirsP.Outputs (([string]$curP.generation).Substring(0, 16).ToLowerInvariant())
$gP = Read-PsSpJsonFile -LiteralPath (Join-Path $outP 'gate.json')
Assert ($c -eq 'SPEC1-6-01' -and $c2 -match '^SPEC1-7-02-\d+$' -and [int]$gP.unknownDebt -ge 1 -and (@($gP.findings | Where-Object { $_.code -eq '7-15' -and $_.requirementId -eq 'R16' })).Count -eq 1 -and (@($gP.findings | Where-Object { $_.code -eq '7-17' })).Count -eq 1 -and (@($gP.findings | Where-Object { $_.code -eq '7-11' -and $_.requirementId -eq 'R09' })).Count -eq 1) "未派工前 gate：UNKNOWN debt（7-15）、UNSUPPORTED（7-17）、required 單位缺（7-11）→ SPEC_PARTIAL"
$c = Invoke-Cli @{ Doctor = $true; JobId = 'job-p'; Drill = '7-15' }
Assert ($c -eq 'SPEC1-0-05-1' -and $script:lastOut -match '(?m)^D7-15 R16 DATA\.FILE_OUTPUT COMPOSE a=0 c=UNKNOWN$') "drill 7-15：固定 tuple「D7-15 R16 DATA.FILE_OUTPUT COMPOSE a=0 c=UNKNOWN」"
$c = Invoke-Cli @{ Doctor = $true; JobId = 'job-p'; Drill = '7-16' }
Assert ($c -match '^SPEC1-0-05-\d+$' -and $script:lastOut -match '(?m)^D7-16 C0\d CHECKLIST ANY a=0 c=UNCOVERED$') "drill 7-16：checklist 覆蓋缺口 tuple"
$env:PS_SPEC_FAKE_MODE = 'valid'
$c = Invoke-Cli @{ Run = $true; JobId = 'job-p'; MaxSessions = 9; FakeWorker = $fake }
$c = Invoke-Cli @{ Render = $true; JobId = 'job-p' }
$c2 = Invoke-Cli @{ Gate = $true; JobId = 'job-p' }
$curP = Read-PsSpJsonFile -LiteralPath $dirsP.CurrentFile
$outP = Join-Path $dirsP.Outputs (([string]$curP.generation).Substring(0, 16).ToLowerInvariant())
$specB = Read-PsKnText -LiteralPath (Join-Path $outP 'spec.md')
$specA = Read-PsKnText -LiteralPath (Join-Path $outA 'spec.md')
Assert ($c -eq 'SPEC1-6-01' -and $c2 -match '^SPEC1-7-02-\d+$' -and $specB -match '## 甲、物件與依賴' -and $specB -notmatch '## 1\. 功能識別' -and $specA -notmatch '## 甲、' -and ($specA -cne $specB) -and $specB -match 'PS_DEMO_TBL：wiki PS_DEMO_TBL' -and $specB -match '（UNSUPPORTED）') "兩套 pack 對同一 NN：spec.md 章節與內容不同（B 含 ENTITY.DETAIL、UNSUPPORTED；派工後仍 PARTIAL＝UNSUPPORTED＋RECORD need）"
$gP = Read-PsSpJsonFile -LiteralPath (Join-Path $outP 'gate.json')
Assert ([string]$gP.verdict -eq 'SPEC_PARTIAL' -and [int]$gP.unknownDebt -eq 0 -and (@($gP.findings | Where-Object { $_.code -eq '7-19' })).Count -ge 1) "派工後：DATA.FILE_OUTPUT present 由片段決定（UNKNOWN debt 歸零）；PS_JOB wiki 缺 → WAITING（7-19）"
$traceB = Read-PsKnText -LiteralPath (Join-Path $outP 'trace.md')
Assert ($traceB -match '(?m)^- fact ENTITY\.DETAIL@PS_DEMO_TBL（grade AUDITED_CLEAN）' -and $traceB -match '來源 docs/ps-research/wiki/PS_DEMO_TBL\.md' -and $traceB -match 'receipt a\d{4} fragment [0-9A-F]{16}') "trace.md：requirement → facts → 來源檔 hash／一跳 wiki／收據"
# ── 情境 9：doctor stage 0（generic manifest）─────────────────────
Write-Host "情境 9：doctor stage 0"
$groot = Join-Path $root 'generic'
foreach ($rel in @('scripts/ps-spec-lib.ps1', 'scripts/ps-spec.ps1', '.opencode/agent/ps-spec-worker.md', '.opencode/command/ps-spec-batch.md', '.opencode/peoplesoft/spec/capabilities.json', '.opencode/peoplesoft/spec/support-codes.md', '.opencode/peoplesoft/spec/examples/pack-a/pack.json')) {
    $src = Join-Path $repoRoot $rel
    if (-not [System.IO.File]::Exists($src)) { continue }
    $dst = Join-Path $groot $rel
    New-Item -ItemType Directory -Path (Split-Path $dst -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $src -Destination $dst
}
$c = Invoke-Cli @{ Doctor = $true; Root = $groot }
Assert ($c -eq 'SPEC1-0-02' -and $script:lastExit -eq 1) "無 generic.manifest.json → SPEC1-0-02"
$c = Invoke-Cli @{ Doctor = $true; Root = $groot; WriteGenericManifest = $true }
$gm = Read-PsSpJsonFile -LiteralPath (Join-Path $groot '.opencode/peoplesoft/spec/generic.manifest.json')
Assert ($c -eq 'SPEC1-0-04' -and @($gm.files).Count -ge 6 -and (@($gm.files | Where-Object { $_.path -eq 'scripts/ps-spec-lib.ps1' })).Count -eq 1 -and (@($gm.files | Where-Object { $_.path -eq '.opencode/peoplesoft/spec/generic.manifest.json' })).Count -eq 0) "-WriteGenericManifest：列 scripts/ps-spec*.ps1、spec/**、agent、command；不含自身"
$c = Invoke-Cli @{ Doctor = $true; Root = $groot }
Assert ($c -eq 'SPEC1-0-03' -and $script:lastExit -eq 0) "manifest 一致 → SPEC1-0-03"
Add-Content -LiteralPath (Join-Path $groot 'scripts/ps-spec.ps1') -Value '# tampered' -Encoding UTF8
$c = Invoke-Cli @{ Doctor = $true; Root = $groot }
Assert ($c -eq 'SPEC1-0-01-1' -and $script:lastExit -eq 1) "generic 檔被改 → SPEC1-0-01-1（GENERIC_MODIFIED）"
$c = Invoke-Cli @{ Doctor = $true; Root = $groot; Drill = '0-01' }
Assert ($script:lastOut -match '(?m)^D0-01 F1 GENERIC FILE c=MODIFIED$') "drill 0-01：tuple 只有序號與封閉值（不印檔名）"
Set-Content -LiteralPath (Join-Path $groot 'scripts/ps-spec.ps1') -Value ([System.IO.File]::ReadAllText((Join-Path $repoRoot 'scripts/ps-spec.ps1'))) -NoNewline -Encoding UTF8
Add-Content -LiteralPath (Join-Path $groot 'scripts/ps-spec.ps1') -Value "`r`n" -Encoding UTF8
$c = Invoke-Cli @{ Doctor = $true; Root = $groot }
Assert ($c -eq 'SPEC1-0-01-1' -or $c -eq 'SPEC1-0-03') "CRLF／BOM 差異不算修改（正規化 hash）"
$c = Invoke-Cli @{ Doctor = $true; Root = $repoRoot }
Assert ($c -eq 'SPEC1-0-03' -and $script:lastExit -eq 0) "本 repo 的 generic.manifest.json 與現況一致（維護端改 generic 檔後須重生）"
# ── 情境 10：lib 層：三值邏輯、closure、SelectOnly ───────────────
Write-Host "情境 10：三值 applicability／closure／工具函式"
$fv = @{ 'A.x' = 'TRUE'; 'A.y' = 'FALSE'; 'A.z' = 'UNKNOWN' }
$tt = @(
    @{ App = @{ op = 'ALWAYS' }; Want = 'TRUE' },
    @{ App = @{ op = 'FACT_TRUE'; fact = 'A.z' }; Want = 'UNKNOWN' },
    @{ App = @{ op = 'FACT_FALSE'; fact = 'A.y' }; Want = 'TRUE' },
    @{ App = @{ op = 'FACT_TRUE'; fact = 'A.nope' }; Want = 'UNKNOWN' },
    @{ App = @{ op = 'ALL'; args = @(@{ op = 'FACT_TRUE'; fact = 'A.x' }, @{ op = 'FACT_TRUE'; fact = 'A.z' }) }; Want = 'UNKNOWN' },
    @{ App = @{ op = 'ALL'; args = @(@{ op = 'FACT_TRUE'; fact = 'A.y' }, @{ op = 'FACT_TRUE'; fact = 'A.z' }) }; Want = 'FALSE' },
    @{ App = @{ op = 'ANY'; args = @(@{ op = 'FACT_TRUE'; fact = 'A.y' }, @{ op = 'FACT_TRUE'; fact = 'A.z' }) }; Want = 'UNKNOWN' },
    @{ App = @{ op = 'ANY'; args = @(@{ op = 'FACT_TRUE'; fact = 'A.x' }, @{ op = 'FACT_TRUE'; fact = 'A.z' }) }; Want = 'TRUE' },
    @{ App = @{ op = 'NOT'; arg = @{ op = 'FACT_TRUE'; fact = 'A.z' } }; Want = 'UNKNOWN' }
)
$okT = $true
foreach ($t in $tt) { if ((Test-PsSpApplicability -App $t.App -FactValues $fv) -ne $t.Want) { $okT = $false } }
Assert $okT "三值真值表：ALL／ANY／NOT／FACT_*；UNKNOWN 不吸收成 FALSE"
Assert ((Test-PsSpSelectOnly -Sql 'SELECT A FROM T WHERE ROWNUM <= 5') -and -not (Test-PsSpSelectOnly -Sql 'SELECT A FROM T') -and -not (Test-PsSpSelectOnly -Sql 'DELETE FROM T WHERE ROWNUM <= 1')) "Test-PsSpSelectOnly（取自 #17 通用函式）"
$seen = @{}
Assert ((Get-PsSpUniqueId -Base 'X.A' -Seen $seen) -eq 'X.A' -and (Get-PsSpUniqueId -Base 'X.A' -Seen $seen) -eq 'X.A.2' -and (Get-PsSpId -Prefix 'CTL' -Parts @('tw x', 'f-1')) -eq 'CTL.TW_X.F_1') "Get-PsSpId／Get-PsSpUniqueId（取自 #17 通用函式）"
$env:PS_SPEC_FAKE_MODE = 'partial'
$c = Invoke-Cli @{ Plan = $true; JobId = 'job-q'; Component = 'TW_DEMO_A'; Pack = 'pack-a' }
$c = Invoke-Cli @{ Run = $true; JobId = 'job-q'; MaxSessions = 9; FakeWorker = $fake }
$dirsQ = Get-PsSpDirs -Root $root -PrivateRoot $priv -RuntimeRoot $rt -PackId 'pack-a' -JobId 'job-q'
$rcQ = @(Get-PsSpReceipts -Dirs $dirsQ)
$c = Invoke-Cli @{ Render = $true; JobId = 'job-q' }
$c2 = Invoke-Cli @{ Gate = $true; JobId = 'job-q' }
$curQ = Read-PsSpJsonFile -LiteralPath $dirsQ.CurrentFile
$gQ = Read-PsSpJsonFile -LiteralPath (Join-Path (Join-Path $dirsQ.Outputs (([string]$curQ.generation).Substring(0, 16).ToLowerInvariant())) 'gate.json')
Assert ((@($rcQ | Where-Object { $_.closure -eq 'PARTIAL' })).Count -ge 1 -and $c2 -match '^SPEC1-7-02-' -and (@($gQ.findings | Where-Object { $_.code -eq '7-21' -and $_.c -eq 'PARTIAL' })).Count -ge 1 -and (@($gQ.findings | Where-Object { $_.code -eq '7-12' -and $_.requirementId -eq 'R20' })).Count -eq 1) "片段只覆蓋部分條目 → 收據 closure PARTIAL（外環算）；ALL_DISCOVERED 需求 → 7-12；coverage tuple 7-21 c=PARTIAL"
$c = Invoke-Cli @{ Doctor = $true; JobId = 'job-q'; Drill = '7-21' }
Assert ($script:lastOut -match '(?m)^D7-21 R20 BEHAVIOR\.VALIDATIONS COMPOSE a=1 c=PARTIAL$') "drill 7-21 tuple 形狀：D7-21 R20 BEHAVIOR.VALIDATIONS COMPOSE a=1 c=PARTIAL"
$env:PS_SPEC_FAKE_MODE = 'valid'

Remove-Item -Recurse -Force $root
Write-Host ""
if ($failCount -gt 0) { Write-Host "共 $failCount 個 FAIL" -ForegroundColor Red; exit 1 }
Write-Host "全部情境 PASS" -ForegroundColor Green
