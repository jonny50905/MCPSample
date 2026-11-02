# test-bizspec.ps1 — 業務需求文件流程（ps-bizspec，BIZ1）的測試：檢查函式庫單元測試＋外環端對端（合成寫手與補查，不呼叫模型、不查 MCP）。
# 用法：pwsh -NoProfile -File scripts/tests/test-bizspec.ps1   （公司機：powershell -NoProfile -ExecutionPolicy Bypass -File …）
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repo 'scripts/ps-knowledge-lib.ps1')
. (Join-Path $repo 'scripts/ps-bizspec-lib.ps1')
$cli = Join-Path $repo 'scripts/ps-bizspec.ps1'
$script:failed = 0; $script:passed = 0
function Assert-Bz([bool]$Condition, [string]$Name, [string]$Detail = '') {
    if ($Condition) { $script:passed++; Write-Host ('PASS ' + $Name) }
    else { $script:failed++; Write-Host ('FAIL ' + $Name); if ($Detail) { Write-Host ('     ' + $Detail) } }
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
function Write-T([string]$Path, [string]$Text) { [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path)); [System.IO.File]::WriteAllText($Path, $Text, $utf8) }
$base = Join-Path ([System.IO.Path]::GetTempPath()) ('ps-bizspec-' + [guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($base)

try {
# ---------------- 規範副本與編碼 ----------------
$copies = @('.opencode/peoplesoft/bizspec/standard.md', 'claude-code/.claude/peoplesoft/bizspec/standard.md', 'docs/business-spec/standard.md')
$present = @($copies | Where-Object { [System.IO.File]::Exists((Join-Path $repo $_)) })
if ($present.Count -ge 2) {
    $ref = (Read-PsKnText -LiteralPath (Join-Path $repo $present[0])).Replace("`r", '')
    $same = $true; foreach ($c in $present) { if ((Read-PsKnText -LiteralPath (Join-Path $repo $c)).Replace("`r", '') -cne $ref) { $same = $false } }
    Assert-Bz $same ('規範：' + ($present -join '、') + ' 逐字相同')
}
foreach ($rel in @('scripts/ps-bizspec.ps1', 'scripts/ps-bizspec-lib.ps1', 'scripts/tests/test-bizspec.ps1')) {
    $b = [System.IO.File]::ReadAllBytes((Join-Path $repo $rel))
    Assert-Bz ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) ('UTF-8 BOM：' + $rel)
}

# ---------------- 函式庫：表格、位置、補查檔 ----------------
$cells = ConvertFrom-PsBzRow '| E-001 | 檔案 | a/b.md §1 | 甲 \| 乙 |'
Assert-Bz ($cells.Count -eq 4 -and $cells[3] -ceq '甲 | 乙') '表格：「\|」是儲存格內的「|」'
$tbs = Get-PsBzTables ("# x`n| a | b |`n|---|---|`n| 1 | 2 |`n`n" + '```' + "`n| c | d |`n|---|---|`n" + '```' + "`n")
Assert-Bz ($tbs.Count -eq 1 -and $tbs[0].Rows.Count -eq 1) '表格：圍欄程式碼區塊內的表格不算'
$loc = Split-PsBzLocation '`./docs/ps-research/x/01-A.md` §2.1 規則'
Assert-Bz ($null -ne $loc -and $loc.Path -ceq 'docs/ps-research/x/01-A.md') '位置：去掉反引號與 ./'
Assert-Bz ($null -ne (Split-PsBzLocation 'in/fields.csv 第 7 列')) '位置：csv 寫「第 N 列」'
Assert-Bz ($null -eq (Split-PsBzLocation '規則檔第二節')) '位置：沒有路徑 → 不合格'
$qGood = "# Q-A-001`n`n## 問題`n天數`n`n## 查詢`n- 知識層`n`n## 結果`n- 逾期期限為送出後第 7 個工作天，由系統於次日標示逾期。`n`n## 結論`n有答案：第 7 個工作天。`n"
$qc = Test-PsBzQueryFile $qGood
Assert-Bz ($qc.Ok -and $qc.Conclusion -ceq '有答案') '補查檔：四節齊、結論「有答案」'
$qc2 = Test-PsBzQueryFile "# Q`n## 問題`nx`n## 結果`n- y`n## 結論`n大概是七天`n"
Assert-Bz ((-not $qc2.Ok) -and @($qc2.Errors).Count -ge 2) '補查檔：缺「查詢」節、結論沒以三種詞開頭 → 不合格' (@($qc2.Errors) -join '；')

# ---------------- 函式庫：證據逐字比對 ----------------
$lr = Join-Path $base 'lib'
Write-T (Join-Path $lr 'in/rules.md') "# 規則`n## 2.1`n| BR-01 | 借用期間不得超過 30 天，超過時顯示「借用期間不得超過 30 天」 |`n"
Write-T (Join-Path $lr 'in/fields.csv') "畫面,標籤,技術名,必填`n借用單,用途,PURPOSE_TXT,TBD`n"
Write-T (Join-Path $lr 'out/evidence/Q-A-002.md') $qGood
Write-T (Join-Path $lr 'other/x.md') "某個不在允許位置的檔，內容夠長可以比對`n"
$ev = @{ Items = @(
        @{ Id = 'E-001'; Type = '檔案'; Location = 'in/rules.md §2.1'; Excerpt = 'BR-01 \| 借用期間不得超過 30 天'; File = '10-evidence.md'; Line = 5 },
        @{ Id = 'E-002'; Type = '檔案'; Location = 'in/fields.csv 第 1 列'; Excerpt = '借用單,用途,PURPOSE_TXT,TBD'; File = '10-evidence.md'; Line = 6 },
        @{ Id = 'E-003'; Type = '檔案'; Location = 'in/rules.md §2.1'; Excerpt = '借用期間最多不得超過 30 天'; File = '10-evidence.md'; Line = 7 },
        @{ Id = 'E-004'; Type = '檔案'; Location = 'in/rules.md §2.1'; Excerpt = '30 天'; File = '10-evidence.md'; Line = 8 },
        @{ Id = 'E-005'; Type = '檔案'; Location = 'other/x.md §1'; Excerpt = '某個不在允許位置的檔'; File = '10-evidence.md'; Line = 9 },
        @{ Id = 'E-006'; Type = '補查'; Location = 'out/evidence/Q-A-002.md §結果'; Excerpt = '逾期期限為送出後第 7 個工作天'; File = '10-evidence.md'; Line = 10 },
        @{ Id = 'E-007'; Type = '檔案'; Location = 'in/nothere.md §1'; Excerpt = '一段不存在的檔案的文字內容'; File = '10-evidence.md'; Line = 11 },
        @{ Id = 'E-008'; Type = '補查'; Location = 'out/evidence/Q-A-002.md §結果'; Excerpt = '由系統於次日標示逾期'; File = '10-evidence.md'; Line = 12 }
    ); ById = @{}; Duplicates = @(); Malformed = @() }
$ctxNoLedger = @{ Root = $lr; FileRoots = @('in/'); EvidenceRel = 'out/evidence/'; Ledger = @{} }
$f1 = Test-PsBzEvidenceItems $ev $ctxNoLedger
function Get-Codes($F, [string]$Id) { return @($F | Where-Object { ([string]$_.Detail).StartsWith($Id + '（') } | ForEach-Object { $_.Code }) }
Assert-Bz ((Get-Codes $f1 'E-001').Count -eq 0) '證據：表格列的摘錄（含 \|）逐字出現在來源 → 通過'
Assert-Bz ((Get-Codes $f1 'E-002').Count -eq 0) '證據：csv 列逐字出現 → 通過'
Assert-Bz ((Get-Codes $f1 'E-003') -contains 'BZ_EV_EXCERPT') '證據：改過一個字的摘錄 → BZ_EV_EXCERPT'
Assert-Bz ((Get-Codes $f1 'E-004') -contains 'BZ_EV_LENGTH') '證據：摘錄不到 10 字 → BZ_EV_LENGTH'
Assert-Bz ((Get-Codes $f1 'E-005') -contains 'BZ_EV_ROOT') '證據：引用允許位置以外的檔 → BZ_EV_ROOT'
Assert-Bz ((Get-Codes $f1 'E-006') -contains 'BZ_EV_QUERY') '證據：補查結果檔不在外環帳本（偽造）→ BZ_EV_QUERY'
Assert-Bz ((Get-Codes $f1 'E-007') -contains 'BZ_EV_PATH') '證據：位置所指的檔不存在 → BZ_EV_PATH'
$ctxLedger = @{ Root = $lr; FileRoots = @('in/'); EvidenceRel = 'out/evidence/'; Ledger = @{ 'out/evidence/Q-A-002.md' = (Get-PsKnTextHash -Text $qGood) } }
$f2 = Test-PsBzEvidenceItems $ev $ctxLedger
Assert-Bz ((Get-Codes $f2 'E-006').Count -eq 0 -and (Get-Codes $f2 'E-008').Count -eq 0) '證據：補查結果檔在帳本且未改、摘錄出自「結果」節 → 通過'
Write-T (Join-Path $lr 'out/evidence/Q-A-002.md') ($qGood + "多一行`n")
$f3 = Test-PsBzEvidenceItems $ev $ctxLedger
Assert-Bz ((Get-Codes $f3 'E-006') -contains 'BZ_EV_QUERY') '證據：補查結果檔在補查後被改 → BZ_EV_QUERY'

# ---------------- 外環：合成寫手與補查 ----------------
$fakeDir = Join-Path $base 'fake'
$fakeWriter = Join-Path $fakeDir 'fake-writer.ps1'
$fakeQuery = Join-Path $fakeDir 'fake-query.ps1'
[void][System.IO.Directory]::CreateDirectory($fakeDir)
[System.IO.File]::WriteAllText($fakeWriter, @'
param([string]$OrderPath, [string]$Kind, [string]$Root, [string]$OutputRoot)
$mode = [string]$env:PS_BZ_TEST_MODE
$dir = [string]$env:PS_BZ_TEST_DIR
[System.IO.File]::AppendAllText((Join-Path $dir 'calls.log'), ($Kind + "`n"))
$enc = New-Object System.Text.UTF8Encoding($false)
function W([string]$Name, [string[]]$Lines) {
    $p = Join-Path $OutputRoot $Name
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($p))
    [System.IO.File]::WriteAllText($p, (($Lines -join "`n") + "`n"), $enc)
}
$outRel = ($OutputRoot.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/')
$owner = 'Spec 產製端'; if ($mode -like '*biz*') { $owner = '業務窗口' }
function Build([bool]$Bad, [bool]$Closed, [bool]$Query) {
    $e2 = '申請人填寫示範申請單後送出，主管核准或退回。'; if ($Bad) { $e2 = '申請人填寫申請單後立即送出，主管一律核准。' }
    $rs = '待確認'; $ev3 = 'E-003'; if ($Closed) { $rs = '已確認' }; if ($Query) { $ev3 = 'E-003、E-004' }
    $as = '開放'; $ac = '—'; if ($Closed -and $Query) { $as = '已關閉'; $ac = '補查 Q-A-001（E-004）' } elseif ($Closed) { $as = '已關閉'; $ac = '業務窗口甲：第 7 個工作天' }
    W 'README.md' @('# 示範申請業務需求文件')
    foreach ($n in @('01-goals.md', '02-spec-overview.md', '05-2-screens.md', '05-3-data.md', '05-5-states.md', '05-6-permissions.md', '05-7-interfaces.md', '05-8-coverage.md', '08-spec-change.md', 'appendix.md')) { W $n @('# ' + $n) }
    W '03-reading-guide.md' @('# 3 怎麼讀 Spec', '## 3.3 範圍判讀', '| 需求鍵 | 範圍類型 | 項目 | 描述 | 證據 | 確認狀態 | 相關假設 |', '|---|---|---|---|---|---|---|', '| SCOPE-001 | 包含 | 示範申請 | 本期包含示範申請單的建立與送審 | E-001 | 已確認 | — |')
    W '05-1-flows.md' @('# 5.1 流程與業務情境', '### 申請', '#### FLOW-001 示範申請', '- 描述：申請人填單送出，主管核准或退回。', '- 證據：E-002／確認狀態：已確認／相關假設：—')
    W '05-4-rules.md' @('# 5.4 業務規則', '### 申請單', '| 需求鍵 | 描述 | 時機 | 條件 | 結果 | 結果類型 | 訊息原文 | 證據 | 確認狀態 | 相關假設 |', '|---|---|---|---|---|---|---|---|---|---|', ('| RULE-001 | 每日，若送出後超過逾期期限未處理，則標示逾期 | 每日 | 超過逾期期限 | 標示逾期 | 其他 | — | ' + $ev3 + ' | ' + $rs + ' | A-001 |'))
    W '04-requirement-index.md' @('# 4 從 Spec 整理業務需求', '## 4.3 需求索引', '| 需求鍵 | 類別 | 摘要 | 證據 | 確認狀態 | 相關假設 |', '|---|---|---|---|---|---|', '| SCOPE-001 | 範圍 | 本期包含示範申請 | E-001 | 已確認 | — |', '| FLOW-001 | 流程與業務情境 | 示範申請 | E-002 | 已確認 | — |', ('| RULE-001 | 業務規則 | 逾期標示 | ' + $ev3 + ' | ' + $rs + ' | A-001 |'), ('| ACC-001 | 驗收情境 | 逾期標示 | 衍生（見來源需求鍵） | ' + $rs + ' | A-001 |'))
    W '06-tracking.md' @('# 6 需求追蹤', '| 需求鍵 | 摘要 | 確認狀態 | 確認人／日期 | 驗收結果 | 驗收日期 | 備註 |', '|---|---|---|---|---|---|---|', '| SCOPE-001 | 本期包含示範申請 | 已確認 | — | — | — | — |')
    W '07-assumptions.md' @('# 7 缺口、矛盾與假設', '## 7.2 假設登記', '| 編號 | 類型 | 缺什麼 | 暫定做法 | 影響的需求鍵 | 該問誰 | 狀態 | 關閉依據 |', '|---|---|---|---|---|---|---|---|', ('| A-001 | 缺漏 | 逾期期限的天數（證據：E-003） | 不自動執行；由人工處理 | RULE-001 | ' + $owner + ' | ' + $as + ' | ' + $ac + ' |'))
    W '09-acceptance.md' @('# 9 業務驗收', '| 需求鍵 | 情境 | 前置條件 | 操作步驟 | 預期結果 | 來源需求鍵 | 衍生 | 證據 | 確認狀態 | 相關假設 |', '|---|---|---|---|---|---|---|---|---|---|', ('| ACC-001 | 【成立】逾期 | 已送出 | 等待 | 標示逾期 | RULE-001 | 是 | 衍生（見來源需求鍵） | ' + $rs + ' | A-001 |'))
    $evl = @('# 10 證據', '## 10.1 證據清單', '| 證據編號 | 類型 | 位置 | 原文摘錄 |', '|---|---|---|---|',
        '| E-001 | 檔案 | docs/ps-research/demo/01-demo.md §1 範圍 | 本期包含示範申請單的建立與送審（TW_DEMO_REQ）。 |',
        ('| E-002 | 檔案 | docs/ps-research/demo/01-demo.md §2 流程 | ' + $e2 + ' |'),
        '| E-003 | 檔案 | docs/ps-research/demo/01-demo.md §3 規則 | 申請單送出後超過逾期期限未處理者標示逾期，期限另定。 |')
    if ($Query) { $evl += ('| E-004 | 補查 | ' + $outRel + '/evidence/Q-A-001.md §結果 | 逾期期限為送出後第 7 個工作天，由系統於次日標示逾期。 |') }
    $evl += @('', '## 10.2 補查紀錄', '| 補查檔 | 對應假設 | 結論 | 回填的證據 |', '|---|---|---|---|')
    if ($Query) { $evl += '| evidence/Q-A-001.md | A-001 | 有答案 | E-004 |' }
    W '10-evidence.md' $evl
    W 'progress.md' @('# 進度', '- [x] 02-spec-overview.md', '- [x] 完成前自我檢查', '## 自我檢查', '自我檢查：通過；修正項：無')
}
switch ($Kind) {
    'WRITE' {
        if ($mode -eq 'stall') { if (-not [System.IO.File]::Exists((Join-Path $OutputRoot 'progress.md'))) { W 'progress.md' @('# 進度', '- [x] 02-spec-overview.md', '- [ ] 03-reading-guide.md') }; exit 0 }
        Build ($mode -like 'bad*') $false $false
        if ($mode -like 'evil*') {
            W 'evidence/Q-A-999.md' @('# 偽造的補查結果')
            $sfx = ''; if ((Split-Path (Split-Path $OutputRoot -Parent) -Leaf) -like '*-opencode') { $sfx = '-opencode' }
            $ans = Join-Path (Join-Path $Root ('.ps-private/bizspec' + $sfx)) ((Split-Path $OutputRoot -Leaf) + '/answers.md')
            [System.IO.File]::AppendAllText($ans, "| A-001 | 寫手自己代答 | 寫手 | 11/02 |`n")
        }
    }
    'FIX' { if ($mode -eq 'badalways') { exit 0 }; Build $false $false $false }
    'BACKFILL' { Build $false $true $true }
    'ANSWER' { Build $false $true $false }
}
exit 0
'@, $utf8Bom)
[System.IO.File]::WriteAllText($fakeQuery, @'
param([string]$OrderPath, [string]$Kind, [string]$Root, [string]$OutputRoot)
[System.IO.File]::AppendAllText((Join-Path ([string]$env:PS_BZ_TEST_DIR) 'calls.log'), ($Kind + "`n"))
$order = [System.IO.File]::ReadAllText($OrderPath)
$m = [regex]::Match($order, '輸出檔：(\S+?)（')
$p = Join-Path $Root $m.Groups[1].Value
[void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($p))
$t = "# Q-A-001`n`n## 問題`n逾期期限的天數`n`n## 查詢`n- 委派 ps-metadata-flow：TW_DEMO_REQ 的逾期設定`n`n## 結果`n- 逾期期限為送出後第 7 個工作天，由系統於次日標示逾期。`n`n## 結論`n有答案：逾期期限為送出後第 7 個工作天。`n"
if ([string]$env:PS_BZ_TEST_MODE -eq 'qbad') { $t = "# Q-A-001`n大概七天`n" }
[System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
exit 0
'@, $utf8Bom)

function New-BzRoot([string]$Name, [string]$Variant = 'claude', [bool]$Knowledge = $true) {
    $r = Join-Path $base $Name
    if ($Variant -eq 'claude') { $src = Join-Path $repo 'claude-code/.claude/peoplesoft/bizspec'; $dst = Join-Path $r '.claude/peoplesoft/bizspec' }
    else {
        $src = Join-Path $repo '.opencode/peoplesoft/bizspec'; $dst = Join-Path $r '.opencode/peoplesoft/bizspec'
        Write-T (Join-Path $r '.opencode/peoplesoft/sdoc/model.yaml') "model: anthropic/claude-haiku-4-5`n"
    }
    foreach ($f in @(Get-ChildItem -LiteralPath $src -File)) { Write-T (Join-Path $dst $f.Name) ([System.IO.File]::ReadAllText($f.FullName)) }
    if ($Knowledge) { Write-T (Join-Path $r 'docs/ps-research/demo/01-demo.md') "# 01 TW_DEMO_REQ 示範申請`n## 1 範圍`n- 本期包含示範申請單的建立與送審（TW_DEMO_REQ）。`n## 2 流程`n- 申請人填寫示範申請單後送出，主管核准或退回。`n## 3 規則`n- 申請單送出後超過逾期期限未處理者標示逾期，期限另定。`n" }
    return $r
}
function Invoke-Bz([string]$Root, [string]$Mode, [hashtable]$Extra = @{}) {
    $prior = @{ Mode = $env:PS_BZ_TEST_MODE; Dir = $env:PS_BZ_TEST_DIR; Cli = $env:PS_CLI }
    try {
        $env:PS_BZ_TEST_MODE = $Mode; $env:PS_BZ_TEST_DIR = $Root; $env:PS_CLI = $null
        $h = @{ Root = $Root; Components = 'TW_DEMO_REQ'; FakeWriter = $fakeWriter; FakeQuery = $fakeQuery }
        foreach ($k in $Extra.Keys) { $h[$k] = $Extra[$k] }
        $out = ((& $cli @h *>&1 | ForEach-Object { [string]$_ }) -join "`n")
        $lines = @($out -split "`n" | Where-Object { $_.Trim() -ne '' })
        return @{ Output = $out; Exit = $LASTEXITCODE; Code = $lines[-1].Trim() }
    }
    finally { $env:PS_BZ_TEST_MODE = $prior.Mode; $env:PS_BZ_TEST_DIR = $prior.Dir; $env:PS_CLI = $prior.Cli }
}
function Get-BzCalls([string]$Root) { $p = Join-Path $Root 'calls.log'; if (-not [System.IO.File]::Exists($p)) { return '' }; return (([System.IO.File]::ReadAllText($p)).Trim() -replace "`n", ',') }
$job = 'biz-' + (Get-PsKnTextHash -Text 'TW_DEMO_REQ').Substring(0, 16).ToLowerInvariant()

# 沒有來源
$r0 = New-BzRoot 'nosource' 'claude' $false
$x = Invoke-Bz $r0 'good'
Assert-Bz ($x.Code -ceq 'BIZ1-0-01' -and [System.IO.File]::Exists((Join-Path $r0 ('.ps-private/bizspec/' + $job + '/answers.md')))) '外環：知識層沒有、人工輸入是骨架 → BIZ1-0-01，建好三個輸入檔' $x.Output
# 尚未開始的 -Status
$r1 = New-BzRoot 'status'
$x = Invoke-Bz $r1 'good' @{ Status = $true }
Assert-Bz ($x.Code -ceq 'BIZ1-0-02') '外環：-Status 尚未開始 → BIZ1-0-02' $x.Output
# 完整一輪：寫作 → 檢查 → 補查 → 回填 → 檢查
$r2 = New-BzRoot 'full'
$x = Invoke-Bz $r2 'good'
Assert-Bz ($x.Code -ceq 'BIZ1-7-01' -and (Get-BzCalls $r2) -ceq 'WRITE,QUERY,BACKFILL') '外環：寫作、補查、回填後檢查全過 → BIZ1-7-01' ((Get-BzCalls $r2) + "`n" + $x.Output)
Assert-Bz ($x.Output -match '欄位統計：需求=4；證據=4；補查證據=1；開放假設=0') '外環：欄位統計行' $x.Output
$led = [System.IO.File]::ReadAllText((Join-Path $r2 ('.ps-runtime/bizspec/' + $job + '/queries.json')))
Assert-Bz ($led -match 'Q-A-001\.md' -and $led -match '有答案') '外環：補查結果記進帳本' $led
$x = Invoke-Bz $r2 'good'
Assert-Bz ($x.Code -ceq 'BIZ1-7-01' -and (Get-BzCalls $r2) -ceq 'WRITE,QUERY,BACKFILL') '外環：完成後重跑不再開 session' (Get-BzCalls $r2)
# 摘錄抄錯 → 退回修正
$r3 = New-BzRoot 'fix'
$x = Invoke-Bz $r3 'bad' @{ NoQuery = $true }
Assert-Bz ($x.Code -ceq 'BIZ1-5-01' -and (Get-BzCalls $r3) -ceq 'WRITE,FIX') '外環：摘錄對不上 → FIX 一輪後通過；-NoQuery 不補查、留開放假設 → BIZ1-5-01' ((Get-BzCalls $r3) + "`n" + $x.Output)
$cf = Join-Path $r3 ('.ps-runtime/bizspec/' + $job + '/check/c0001.md')
Assert-Bz ([System.IO.File]::Exists($cf) -and ([System.IO.File]::ReadAllText($cf)) -match 'BZ_EV_EXCERPT') '外環：檢查結果檔列出 BZ_EV_EXCERPT'
# 一直修不好 → 卡住
$r4 = New-BzRoot 'stubborn'
$x = Invoke-Bz $r4 'badalways' @{ NoQuery = $true }
Assert-Bz ($x.Code -ceq 'BIZ1-4-03' -and (Get-BzCalls $r4) -ceq 'WRITE,FIX,FIX,FIX' -and $x.Output -match '檢查：BZ_EV_EXCERPT') '外環：連續 3 輪修正仍未通過 → BIZ1-4-03，轉述檢查項' ((Get-BzCalls $r4) + "`n" + $x.Output)
$x = Invoke-Bz $r4 'good' @{ NoQuery = $true; Retry = $true }
Assert-Bz ($x.Code -ceq 'BIZ1-5-01') '外環：處理後 -Retry → 重新修正並通過' $x.Output
# 越界寫檔
$r5 = New-BzRoot 'evil'
$x = Invoke-Bz $r5 'evil' @{ NoQuery = $true }
$ansText = [System.IO.File]::ReadAllText((Join-Path $r5 ('.ps-private/bizspec/' + $job + '/answers.md')))
Assert-Bz ($x.Output -match '寫手改了不准改的檔' -and -not [System.IO.File]::Exists((Join-Path $r5 ('docs/ps-spec/' + $job + '/evidence/Q-A-999.md'))) -and $ansText -notmatch '寫手自己代答') '外環：寫手寫補查結果檔、改人工輸入檔 → 隔離與還原' $x.Output
# 業務窗口回覆
$r6 = New-BzRoot 'answer'
$x = Invoke-Bz $r6 'biz'
Assert-Bz ($x.Code -ceq 'BIZ1-5-01' -and (Get-BzCalls $r6) -ceq 'WRITE') '外環：開放假設的該問誰是業務窗口 → 不補查、BIZ1-5-01' ((Get-BzCalls $r6) + "`n" + $x.Output)
[System.IO.File]::AppendAllText((Join-Path $r6 ('.ps-private/bizspec/' + $job + '/answers.md')), "| A-001 | 逾期期限是送出後第 7 個工作天 | 業務窗口甲 | 11/03 |`n")
$x = Invoke-Bz $r6 'biz'
Assert-Bz ($x.Code -ceq 'BIZ1-7-01' -and (Get-BzCalls $r6) -ceq 'WRITE,ANSWER') '外環：answers.md 有回覆 → ANSWER 關閉假設 → BIZ1-7-01' ((Get-BzCalls $r6) + "`n" + $x.Output)
# 補查結果檔不合格
$r7 = New-BzRoot 'qbad'
$x = Invoke-Bz $r7 'qbad'
Assert-Bz ($x.Code -ceq 'BIZ1-5-01' -and (Get-BzCalls $r7) -ceq 'WRITE,QUERY,QUERY' -and $x.Output -match '補查 A-001 不合格') '外環：補查結果檔不合格 → 隔離、最多兩次、留開放假設' ((Get-BzCalls $r7) + "`n" + $x.Output)
# 寫手沒有進度
$r8 = New-BzRoot 'stall'
$x = Invoke-Bz $r8 'stall' @{ NoQuery = $true }
Assert-Bz ($x.Code -ceq 'BIZ1-4-03' -and (Get-BzCalls $r8) -ceq 'WRITE,WRITE,WRITE') '外環：寫手連續兩個 session 沒進度 → BIZ1-4-03' ((Get-BzCalls $r8) + "`n" + $x.Output)
# MaxSessions 到了 → 可續跑
$r9 = New-BzRoot 'resume'
$x = Invoke-Bz $r9 'good' @{ MaxSessions = 1 }
Assert-Bz ($x.Code -ceq 'BIZ1-3-02-1' -and (Get-BzCalls $r9) -ceq 'WRITE') '外環：-MaxSessions 1 → 一個 session 後 BIZ1-3-02-1' $x.Output
# OpenCode 版
$r10 = New-BzRoot 'oc' 'opencode'
$x = Invoke-Bz $r10 'good' @{ Cli = 'opencode' }
Assert-Bz ($x.Code -ceq 'BIZ1-7-01' -and [System.IO.File]::Exists((Join-Path $r10 ('docs/ps-spec-opencode/' + $job + '/10-evidence.md'))) -and [System.IO.Directory]::Exists((Join-Path $r10 ('.ps-private/bizspec-opencode/' + $job)))) 'OpenCode 版：輸入、產出各放 *-opencode 目錄 → BIZ1-7-01' $x.Output
# Spec 文件流程已有狀態圖 → 複製
$r11 = New-BzRoot 'copy' 'claude' $false
$doc1 = Join-Path $r11 ('.ps-private/sdoc/clone-' + $job.Substring(4) + '/status.md')
Write-T $doc1 "# 狀態圖`nflowchart LR`n  010 --> 020`n"
$x = Invoke-Bz $r11 'good' @{ MaxSessions = 1 }
$copied = Join-Path $r11 ('.ps-private/bizspec/' + $job + '/status.md')
Assert-Bz ([System.IO.File]::Exists($copied) -and ([System.IO.File]::ReadAllText($copied)) -match '010 --> 020' -and $x.Code -ceq 'BIZ1-3-02-1') '外環：Spec 文件流程同一組 Component 的狀態圖複製過來並當作來源' $x.Output
# 參數
$x = Invoke-Bz $r2 'good' @{ Components = 'TW DEMO 名稱' }
Assert-Bz ($x.Code -ceq 'BIZ1-9-01') '外環：非 ASCII 名稱 → BIZ1-9-01' $x.Output
}
finally {
    if ($env:PS_BZ_TEST_KEEP) { Write-Host ('保留測試目錄：' + $base) } else { try { Remove-Item -LiteralPath $base -Recurse -Force } catch { Write-Host ('無法刪除測試目錄：' + $base) } }
}
Write-Host ('bizspec tests: PASS=' + $script:passed + ' FAIL=' + $script:failed)
if ($script:failed -gt 0) { exit 1 }
Write-Host '全部情境 PASS'
exit 0
