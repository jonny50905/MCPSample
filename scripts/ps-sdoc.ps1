# ps-sdoc.ps1 — Spec 文件流程（Claude Code 版）的單一入口：00-index＋14 份文件＋90 問題清單。
# 第 0 階段三位讀者解讀 STATUS 檔（不一致的逐項第 2 輪多數決）→ 研究單元依序（每頁研究與獨立覆核分開 session）→ 外環組裝、檢核、渲染。
# 模型只寫研究包、解讀、覆核；ID、canonical、檢核、Markdown 都由本腳本確定性產生。PowerShell 5.1；公司機資料只留本機。
# 輸入 .ps-private/sdoc/<job>/；執行狀態 .ps-runtime/sdoc/<job>/；產出 docs/ps-spec/<job>/。最後一行一律是結論碼（DOC1-…）。
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Components,
    [string]$Root = '',
    [switch]$Status,
    [ValidateRange(1, 100)][int]$MaxSessions = 4,
    [ValidateRange(1, 180)][int]$TimeoutMin = 30,
    [string]$Model = '',
    [switch]$Refresh,
    [switch]$Retry,
    [string]$FakeWorker = ''
)
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'ps-knowledge-lib.ps1')
    . (Join-Path $PSScriptRoot 'ps-session-lib.ps1')
    foreach ($lib in @('ps-sdoc-schema-lib', 'ps-sdoc-status-lib', 'ps-sdoc-lib', 'ps-sdoc-check-lib', 'ps-sdoc-render-lib', 'ps-sdoc-reader-lib')) { . (Join-Path $PSScriptRoot ($lib + '.ps1')) }
}
catch { Write-Host ('共用腳本載入失敗，請核對搬運清單與 UTF-8 BOM：' + $_.Exception.Message); Write-Host 'DOC1-9-02'; exit 2 }

$script:SdSkeletonMark = '<!-- SDOC:SKELETON -->'

# ---------------- 檔案 ----------------
function Read-SdNode([string]$Path) {
    if (-not [System.IO.File]::Exists($Path)) { return $null }
    try { $n = ConvertTo-PsSdNode (Read-PsSdJsonFile $Path); return , $n }
    catch { throw ('JSON 損壞，保留現場：' + $Path) }
}
function Write-SdJson([string]$Path, $Value, [switch]$Create) {
    $text = ConvertTo-PsSdJsonText $Value
    if ($Create) {
        $ok = Write-PsKnCreateOnlyText -LiteralPath $Path -Text $text
        if ($null -eq $ok) { throw 'SDOC_WRITE_DEFERRED' }
        if (-not $ok -and (Read-PsKnText -LiteralPath $Path) -cne $text) { throw ('不可覆寫既有紀錄：' + $Path) }
    }
    elseif (-not (Write-PsKnAtomicText -LiteralPath $Path -Text $text)) { throw 'SDOC_WRITE_DEFERRED' }
}
function Write-SdText([string]$Path, [string]$Text) {
    if (-not (Write-PsKnAtomicText -LiteralPath $Path -Text $Text)) { throw 'SDOC_WRITE_DEFERRED' }
}
function Get-SdFiles([string]$Dir) {
    $out = New-Object System.Collections.Generic.List[string]
    if ([System.IO.Directory]::Exists($Dir)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $Dir -File -Recurse -Force)) {
            if (($f.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw '不支援 reparse point 的工作目錄。' }
            $out.Add($f.FullName)
        }
    }
    return , $out.ToArray()
}
function Get-SdNumber([string]$Dir, [string]$Pattern) {
    $n = 0
    if ([System.IO.Directory]::Exists($Dir)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Force)) { $m = [regex]::Match($f.Name, $Pattern); if ($m.Success) { $n = [Math]::Max($n, [int]$m.Groups[1].Value) } }
    }
    return $n
}
function Get-SdText([string]$Path) {
    if (-not [System.IO.File]::Exists($Path)) { return $null }
    return (Read-PsKnText -LiteralPath $Path)
}
function Get-SdHash($Value) { return (Get-PsSdTextHash (ConvertTo-PsKnJson -Value $Value -SortKeys)) }
function Get-SdRel([string]$Path) { return ($Path.Substring($J.Root.Length).TrimStart('\', '/') -replace '\\', '/') }

# ---------------- 輸入檔骨架 ----------------
function Initialize-SdInputs {
    # 缺檔就建骨架（不覆寫既有檔）。回傳 STATUS 檔是否已提供。
    $dir = $J.InputRoot
    [void][System.IO.Directory]::CreateDirectory($dir)
    $files = [ordered]@{
        'status.md' = @($script:SdSkeletonMark, '# STATUS 狀態流程（請以實際內容取代本檔）', '',
            '把這組 Component 的狀態圖全部貼在這個檔案：Mermaid flowchart 與 stateDiagram-v2 都可以，畫法不限；',
            '節點寫狀態碼（三位數字，含前導 0，例如 010、020）。子業務可以獨立畫，也可以合在大圖上。',
            '圖下方的說明區域寫各階段誰該做什麼（可省略）。', '',
            '貼好後刪掉第一行的 SDOC:SKELETON 標記，再執行同一個命令。') -join "`n"
        'project.md' = @($script:SdSkeletonMark, '# 專案輸入（選填；不填時 01 的目標以 NOT_PROVIDED 呈現）', '', '## 目標', '',
            '| 目標 | 成功標準 |', '|---|---|', '', '## 決策責任', '',
            '範圍只能填 SPEC_APPROVAL、QUESTION_RESOLUTION、BUSINESS_RULE_OWNER、DATA_OWNER、OTHER；只寫職稱或單位類別，不寫人名。', '',
            '| 範圍 | 職稱或單位類別 |', '|---|---|', '', '填好後刪掉第一行的 SDOC:SKELETON 標記。') -join "`n"
        'decisions.md' = @('# 人工裁決', '', '問題 ID 以 90-questions.md 為準；效果只能填 NO_CHANGE、DROP、ADD_SCOPE、ACCEPT_GAP、AMEND_INPUT；日期寫 YYYY-MM-DD。', '',
            '| 問題 ID | 決定 | 理由 | 效果 | 決定者類別 | 日期 |', '|---|---|---|---|---|---|') -join "`n"
        'approvals.md' = @('# 人工核准', '', 'docHash 前 12 碼取自 00-index.md 的「文件與檢核」表；文件內容改了，舊的核准就不再成立。', '',
            '| 文件 | 版本 | docHash 前 12 碼 | 核准者類別 | 日期 |', '|---|---|---|---|---|') -join "`n"
    }
    foreach ($name in $files.Keys) {
        $p = Join-Path $dir $name
        if (-not [System.IO.File]::Exists($p)) { [void](Write-PsKnCreateOnlyText -LiteralPath $p -Text ($files[$name] + "`n")) }
    }
    $st = Get-SdText (Join-Path $dir 'status.md')
    return ($null -ne $st -and -not $st.Contains($script:SdSkeletonMark) -and (Get-PsSdMermaidLines $st).Count -gt 0)
}

# ---------------- 研究來源指紋（變了就開新版本） ----------------
function Get-SdSource {
    # STATUS 檔、ADD_SCOPE 裁決、schema。專案輸入、其他裁決、核准檔不換版本（只重新組裝）。
    $map = [ordered]@{}
    $map['status.md'] = Get-PsSdStatusFingerprint (Get-SdText (Join-Path $J.InputRoot 'status.md'))
    $dec = ConvertFrom-PsSdDecisions (Get-SdText (Join-Path $J.InputRoot 'decisions.md')) 'decisions.md'
    $add = @(); foreach ($r in $dec.Rows) { if ($r.Effect -eq 'ADD_SCOPE') { $add += $r.QId } }
    $map['decisions.md#ADD_SCOPE'] = ((Sort-PsKnOrdinal -Items $add) -join ',')
    foreach ($d in @($J.SchemaDir, $J.RuntimeSchemaDir)) {
        $files = Get-SdFiles $d
        foreach ($f in (Sort-PsKnOrdinal -Items $files)) { $map[(Get-SdRel $f)] = Get-PsKnFileHash -LiteralPath $f }
    }
    return @{ Hash = (Get-SdHash $map); Files = $map }
}
function Get-SdKnowledgeFingerprint {
    # 只顯示：docs/ps-research 有變時提示可 -Refresh（不自動換版本）。
    $research = Join-Path $J.Root 'docs/ps-research'
    $map = [ordered]@{}
    foreach ($f in (Sort-PsKnOrdinal -Items (Get-SdFiles $research))) {
        $rel = $f.Substring($research.Length).TrimStart('\', '/') -replace '\\', '/'
        if ($rel -match '^(knowledge|supplemental)/') { continue }
        if ($f.EndsWith('.md', [StringComparison]::OrdinalIgnoreCase)) { $map[$rel] = Get-PsKnFileHash -LiteralPath $f }
    }
    return (Get-SdHash $map)
}

# ---------------- 帳本與收據 ----------------
function Get-SdLedger {
    # attempt 寫完 outcome.json 就不再變：同一個行程內快取，不重讀
    $rows = New-Object System.Collections.Generic.List[object]
    if ([System.IO.Directory]::Exists($J.AttemptRoot)) {
        foreach ($d in @(Get-ChildItem -LiteralPath $J.AttemptRoot -Directory | Sort-Object Name)) {
            if ($d.Name -notmatch '^a[0-9]{4,8}$') { continue }
            if ($J.LedgerCache.ContainsKey($d.Name)) { $c = $J.LedgerCache[$d.Name]; if ($null -ne $c) { $rows.Add($c) }; continue }
            $inp = Read-SdNode (Join-Path $d.FullName 'input.json')
            if ($null -eq $inp -or [string]$inp['revision'] -cne $J.Revision['id']) { if ($null -ne $inp) { $J.LedgerCache[$d.Name] = $null }; continue }
            $row = @{ Id = $d.Name; Dir = $d.FullName; Input = $inp; Outcome = (Read-SdNode (Join-Path $d.FullName 'outcome.json')) }
            if ($null -ne $row.Outcome) { $J.LedgerCache[$d.Name] = $row }
            $rows.Add($row)
        }
    }
    return , $rows.ToArray()
}
function Get-SdReceipts {
    # 本版本的收據（依研究單元順序、主題、頁排序）；完整性不符就停。
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($p in (Get-SdFiles $J.ReceiptRoot)) {
        if (-not $p.EndsWith('.json')) { continue }
        # 收據建立後不再變：同一個行程內快取
        if (-not $J.ReceiptCache.ContainsKey($p)) { $J.ReceiptCache[$p] = Read-SdNode $p }
        $rc = $J.ReceiptCache[$p]
        if ($null -eq $rc -or [string]$rc['revision'] -cne $J.Revision['id']) { continue }
        if ((Get-SdHash $rc['packet']) -cne [string]$rc['packetHash'] -or [string]$rc['review']['verdict'] -cne 'PASS') { throw ('收據失去完整性：' + (Get-SdRel $p)) }
        if ([string]$rc['researchAttempt'] -ceq [string]$rc['reviewAttempt']) { throw ('收據沒有獨立的研究與覆核：' + (Get-SdRel $p)) }
        $ui = Get-PsSdUnitIndex ([string]$rc['unit'])
        $sk = $ui.ToString('D2', [System.Globalization.CultureInfo]::InvariantCulture) + [char]0 + [string]$rc['subject'] + [char]0 + ([int]$rc['page']).ToString('D4', [System.Globalization.CultureInfo]::InvariantCulture)
        $aq = @(); foreach ($x in @($rc['amendQuestions'])) { if ($null -ne $x) { $aq += [string]$x } }
        $rows.Add(@{ Path = $p; Receipt = $rc; Packet = $rc['packet']; Ref = ([string]$rc['unit'] + '/' + [string]$rc['subject'] + '/p' + [string]$rc['page']); Sort = $sk
                Amend = ([string]$rc['cursor']).StartsWith('L5-AMEND'); AmendQuestions = $aq })
    }
    $keys = New-Object System.Collections.Generic.List[string]; $map = @{}
    foreach ($r in $rows) { $keys.Add($r.Sort); $map[$r.Sort] = $r }
    $keys.Sort([System.StringComparer]::Ordinal)
    $out = @(); foreach ($k in $keys) { $out += , $map[$k] }
    return , $out
}
function Get-SdRowsFor([object[]]$Ledger, [string]$Key) {
    $out = @(); foreach ($e in $Ledger) { if ([string]$e.Input['workKey'] -ceq $Key) { $out += , $e } }
    return , $out
}
function Get-SdSlotState([object[]]$Rows) {
    # 同一個工作鍵：本預算的計次失敗數、最後的發現、最後一次接受的 attempt、可覆核的候選。
    $invalid = 0; $findings = @(); $accepted = $null; $candidate = $null; $rejected = @{}
    foreach ($e in $Rows) {
        $o = $e.Outcome
        if ($null -eq $o) { continue }
        if ([int]$e.Input['budget'] -eq $J.Budget -and $o['counted'] -eq $true) { $invalid++ }
        if ($o['counted'] -eq $true -and @($o['findings']).Count -gt 0) { $findings = @($o['findings']) }
        if ([string]$o['status'] -ceq 'ACCEPTED') { $accepted = $e }
        if (@('REVIEW_FAIL', 'REVIEW_BLOCKED') -contains [string]$o['status']) { $rejected[[string]$e.Input['candidateId']] = $true }
    }
    foreach ($e in $Rows) { if ($null -ne $e.Outcome -and [string]$e.Outcome['status'] -ceq 'CANDIDATE' -and -not $rejected.ContainsKey($e.Id)) { $candidate = $e } }
    return @{ Invalid = $invalid; Findings = $findings; Accepted = $accepted; Candidate = $candidate }
}

# ---------------- 第 0 階段 ----------------
function Get-SdStage0([object[]]$Ledger) {
    $text = Get-SdText (Join-Path $J.InputRoot 'status.md')
    $fp = Get-PsSdStatusFingerprint $text
    $work = @(); $gaps = @(); $readings = @()
    foreach ($r in @('R1', 'R2', 'R3')) {
        $key = 'stage0/read/' + $r
        $s = Get-SdSlotState (Get-SdRowsFor $Ledger $key)
        if ($null -ne $s.Accepted) { $readings += , (Read-SdNode (Join-Path $s.Accepted.Dir 'output.json')); continue }
        if ($s.Invalid -ge 2) { $gaps += ('第 0 階段讀者 ' + $r + ' 的解讀本預算已兩次不合格：' + (@($s.Findings | Select-Object -First 3) -join '；')); continue }
        $work += , @{ Kind = 'STATUS_READ'; Reader = $r; Key = $key; Findings = $s.Findings; Unit = 'stage0'; Subject = $r; Page = 1 }
    }
    if ($readings.Count -lt 3) {
        $st = 'READ'; if ($work.Count -eq 0) { $st = 'BLOCKED' }
        return @{ State = $st; Work = $work; Gaps = $gaps; Text = $text; Fingerprint = $fp }
    }
    $res = Compare-PsSdReadings $text $readings $null
    $questions = @()
    if ($res.Contested.Length -gt 0) {
        $questions = Get-PsSdRound2Questions $text $res
        $answers = @{}; $have = 0
        for ($i = 0; $i -lt 3; $i++) {
            $r = 'R' + ($i + 1)
            $key = 'stage0/round2/' + $r
            $s = Get-SdSlotState (Get-SdRowsFor $Ledger $key)
            if ($null -ne $s.Accepted) {
                $ans = Read-SdNode (Join-Path $s.Accepted.Dir 'output.json')
                $byQ = @{}; foreach ($a in @($ans['answers'])) { $byQ[[string]$a['id']] = [string]$a['answer'] }
                foreach ($q in $questions) { $answers[[string]$i + '|' + $q.factKey] = $byQ[[string]$q.id] }
                $have++
                continue
            }
            if ($s.Invalid -ge 2) { $gaps += ('第 0 階段讀者 ' + $r + ' 的第 2 輪回答本預算已兩次不合格：' + (@($s.Findings | Select-Object -First 3) -join '；')); continue }
            $work += , @{ Kind = 'STATUS_ROUND2'; Reader = $r; Key = $key; Findings = $s.Findings; Unit = 'stage0'; Subject = $r; Page = 2; Questions = $questions }
        }
        if ($have -lt 3) {
            $st = 'ROUND2'; if ($work.Count -eq 0) { $st = 'BLOCKED' }
            return @{ State = $st; Work = $work; Gaps = $gaps; Text = $text; Fingerprint = $fp; Questions = $questions }
        }
        $res = Compare-PsSdReadings $text $readings $answers
    }
    $built = Get-PsSdBuiltModel $text $res
    $sk = Get-PsSdWorkflowSkeleton $built
    $summary = Get-PsSdStatusReadingSummary $res 'status.md' $fp
    $wait = ($res.Unresolved.Length -gt 0 -or (Get-PsSdConflictFacts $res).Length -gt 0)
    $st = 'DONE'; if ($wait) { $st = 'WAIT' }
    return @{ State = $st; Work = @(); Gaps = $gaps; Text = $text; Fingerprint = $fp; Result = $res; Built = $built; Skeleton = $sk; Summary = $summary; Questions = $questions }
}

# ---------------- 研究單元 ----------------
function Get-SdSubjects($Unit, $Stage0) {
    if ($Unit.Per -eq 'component') { return , @($J.Names) }
    if ($Unit.Per -eq 'job') { return , @('JOB') }
    $ents = @(); foreach ($e in (Get-PsSdSortedKeys $Stage0.Built.Entities)) { $ents += $e }
    return , $ents
}
function Get-SdResolved($Receipt) {
    # 收集模式的解析結果（同一個行程內快取）。
    $ck = [string]$Receipt.Receipt['packetHash'] + '|' + $J.RegistryStamp
    if ($J.ResolveCache.ContainsKey($ck)) { return $J.ResolveCache[$ck] }
    $ctx = New-PsSdResolveContext $J.SchemaReg $J.Registry $J.Skeleton 'status.md' $J.Built 'Collect'
    $res = Resolve-PsSdPacket $ctx $Receipt.Packet
    $J.ResolveCache[$ck] = $res
    return $res
}
function Get-SdCoverage([object[]]$Receipts) {
    # 已產出的項目鍵、EVIDENCE_GAP 問題鍵、已處置的 STATUS 行、已處置的程式；以及上游需求。
    $items = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $gapKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $lines = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $programs = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $requests = New-Object System.Collections.Generic.List[object]
    foreach ($r in $Receipts) {
        $p = $r.Packet
        foreach ($it in @($p['items'])) { if ($null -ne $it) { [void]$items.Add([string]$it['type'] + '/' + [string]$it['key']) } }
        foreach ($q in @($p['questions'])) { if ($null -ne $q -and [string]$q['category'] -ceq 'EVIDENCE_GAP') { [void]$gapKeys.Add([string]$q['key']) } }
        foreach ($st in @($p['statusTexts'])) { if ($null -ne $st) { [void]$lines.Add('L' + [string]$st['line']) } }
        foreach ($pd in @($p['programDispositions'])) { if ($null -ne $pd) { [void]$programs.Add([string]$pd['program']) } }
        foreach ($rq in @($p['requests'])) { if ($null -ne $rq) { $requests.Add(@{ Type = [string]$rq['type']; Key = [string]$rq['key']; Subject = [string]$p['subject']; Unit = [string]$p['unit'] }) } }
    }
    return @{ Items = $items; GapKeys = $gapKeys; Lines = $lines; Programs = $programs; Requests = $requests }
}
function Get-SdRequired($Unit, [string]$Subject, $Stage0, [object[]]$Receipts) {
    # 本主題必須處置的分母鍵（ITEM：型別/自然鍵；L<n>：STATUS 行；PROGRAM/<物件鍵>）。
    $req = New-Object System.Collections.Generic.List[string]
    if ($Unit.Id -eq 'workflow') { foreach ($k in @($Stage0.Skeleton.Entities[$Subject])) { $req.Add($k) } }
    elseif ($Unit.Id -eq 'texts') { foreach ($t in $Stage0.Built.Texts) { $req.Add('L' + $t.Line) } }
    elseif (@('ui', 'data', 'rules') -contains $Unit.Id) {
        $xf = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
        foreach ($r in $Receipts) {
            if ([string]$r.Receipt['unit'] -cne 'scope') { continue }
            foreach ($it in @($r.Packet['items'])) { if ($null -ne $it -and [string]$it['type'] -ceq 'XF') { foreach ($f in @($it['fields'])) { [void]$xf.Add([string]$it['key'] + '.' + [string]$f) } } }
        }
        foreach ($r in $Receipts) {
            if ([string]$r.Receipt['unit'] -cne 'scope' -or [string]$r.Receipt['subject'] -cne $Subject) { continue }
            $p = $r.Packet
            if ($Unit.Id -eq 'ui' -and $p.Contains('denominators')) { foreach ($pg in @($p['denominators']['pages'])) { foreach ($f in @($pg['fields'])) { if (-not $xf.Contains([string]$f)) { $req.Add('UI/' + $Subject + '.' + [string]$pg['page'] + '.' + [string]$f) } } } }
            if ($Unit.Id -eq 'data' -and $p.Contains('denominators')) { foreach ($rc in @($p['denominators']['records'])) { foreach ($f in @($rc['fields'])) { $k = [string]$rc['record'] + '.' + [string]$f; if (-not $xf.Contains($k)) { $req.Add('FLD/' + $k) } } } }
            if ($Unit.Id -eq 'rules') { foreach ($it in @($p['items'])) { if ($null -ne $it -and [string]$it['type'] -ceq 'OBJ' -and [string]$it['objectType'] -ceq 'PEOPLECODE' -and [string]$it['inclusion'] -cne 'EXCLUDED') { $req.Add('PROGRAM/' + [string]$it['key']) } } }
        }
    }
    $uniq = New-Object System.Collections.Generic.List[string]; $seen = @{}
    foreach ($k in $req) { if (-not $seen.ContainsKey($k)) { $seen[$k] = $true; $uniq.Add($k) } }
    return , $uniq.ToArray()
}
function Test-SdCovered([string]$Req, $Cov, $Registry) {
    if ($Req -match '^L\d+$') { return $Cov.Lines.Contains($Req) }
    if ($Req.StartsWith('PROGRAM/')) {
        $k = $Req.Substring(8)
        if ($Cov.Programs.Contains('@OBJ/' + $k)) { return $true }
        $id = Get-PsSdRegisteredId $Registry 'OBJ' $k
        if ($null -ne $id -and $Cov.Programs.Contains($id)) { return $true }
        return $Cov.GapKeys.Contains($Req)
    }
    return ($Cov.Items.Contains($Req) -or $Cov.GapKeys.Contains($Req))
}
function Get-SdWrittenKeys([object[]]$Receipts) {
    # 已驗收收據寫過的項目（型別/自然鍵）：全 job 同一個自然鍵只寫一次。
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($r in $Receipts) { foreach ($it in @($r.Packet['items'])) { if ($null -ne $it) { [void]$set.Add([string]$it['type'] + '/' + [string]$it['key']) } } }
    return , $set
}
function Get-SdDuplicateKeys($Packet, $Written) {
    $out = @()
    if ($null -eq $Packet) { return , $out }
    foreach ($it in @($Packet['items'])) { if ($null -ne $it) { $k = [string]$it['type'] + '/' + [string]$it['key']; if ($Written.Contains($k)) { $out += $k } } }
    return , $out
}
function Get-SdPending([object[]]$Receipts) {
    # 上游需求還沒被產出（也沒有同鍵的 EVIDENCE_GAP）：@{ '單元|主題' = List[型別/鍵] }
    $cov = Get-SdCoverage $Receipts
    $out = @{}
    foreach ($rq in $cov.Requests) {
        $k = $rq.Type + '/' + $rq.Key
        if ($cov.Items.Contains($k) -or $cov.GapKeys.Contains($k)) { continue }
        $homeUnit = $script:PsSdRequestUnit[$rq.Type]
        if ($null -eq $homeUnit) { continue }
        $subj = $rq.Subject; if ($J.Names -cnotcontains $subj) { $subj = $J.Names[0] }
        $slot = $homeUnit + '|' + $subj
        if (-not $out.ContainsKey($slot)) { $out[$slot] = New-Object System.Collections.Generic.List[string] }
        if (-not $out[$slot].Contains($k)) { $out[$slot].Add($k) }
    }
    return $out
}
function Get-SdPageState($Unit, [string]$Subject, [object[]]$Receipts, [object[]]$Ledger, $Pending, $Stage0, $Amend) {
    # $Amend：L5 要本主題改寫的項目（@{ ItemKeys; Questions; Findings; Cursor }），沒有就 $null。
    $mine = @(); foreach ($r in $Receipts) { if ([string]$r.Receipt['unit'] -ceq $Unit.Id -and [string]$r.Receipt['subject'] -ceq $Subject) { $mine += , $r } }
    $page = 1; $cursor = ''; $mainDone = $false
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($r in $mine) {
        $rc = $r.Receipt
        if ([int]$rc['page'] -ne $page) { throw ('頁次不連續：' + $r.Ref) }
        if ($mainDone) { $cr = [string]$rc['cursor']; if ($cr -cne 'REQUESTS' -and -not $cr.StartsWith('L5-AMEND')) { throw ('頁次不連續：' + $r.Ref) }; $page++; continue }
        if ([string]$rc['cursor'] -cne $cursor) { throw ('頁次不連續：' + $r.Ref) }
        if ([string]$r.Packet['coverage'] -ceq 'COMPLETE') { $mainDone = $true; $page++; $cursor = 'REQUESTS'; continue }
        $next = [string]$r.Packet['nextCursor']
        if ($next -eq '' -or $seen.Contains($next) -or $page -ge 30) { return @{ State = 'BLOCKED'; Findings = @('續頁游標重複、空白或已達 30 頁；請縮小範圍後 -Refresh。') } }
        [void]$seen.Add($next); $cursor = $next; $page++
    }
    $requested = @(); $amendKeys = @(); $amendQs = @(); $l5Find = @()
    $slot = $Unit.Id + '|' + $Subject
    if ($mainDone) {
        if ($Pending.ContainsKey($slot)) { $requested = @($Pending[$slot]); $cursor = 'REQUESTS' }
        elseif ($null -ne $Amend) { $amendKeys = @($Amend.ItemKeys); $requested = $amendKeys; $amendQs = @($Amend.Questions); $l5Find = @($Amend.Findings); $cursor = [string]$Amend.Cursor }
        else { return @{ State = 'DONE'; Findings = @() } }
    }
    # 分母以全部已驗收收據判斷：別的 Component 已寫的共用欄位不必重寫
    $required = Get-SdRequired $Unit $Subject $Stage0 $Receipts
    $cov = Get-SdCoverage $Receipts
    $remaining = @(); foreach ($k in $required) { if (-not (Test-SdCovered $k $cov $J.Registry)) { $remaining += $k } }
    $key = $Unit.Id + '/' + $Subject + '/' + $page
    $s = Get-SdSlotState (Get-SdRowsFor $Ledger $key)
    $base = @{ Unit = $Unit.Id; Subject = $Subject; Page = $page; Cursor = $cursor; Key = $key; Findings = $s.Findings; Required = $remaining; Requested = $requested; Candidate = $s.Candidate
        Amend = $amendKeys; AmendQuestions = $amendQs; L5Findings = $l5Find }
    if ($s.Invalid -ge 2) { $base.State = 'BLOCKED'; $base.Findings = @($s.Findings) + '本頁本次預算已兩次未通過；修正原因後加 -Retry（保留既有收據）。'; return $base }
    if ($null -ne $s.Candidate) {
        # 候選產生後，別的主題先驗收了同一個自然鍵：候選作廢重研究（不計次）
        $written = Get-SdWrittenKeys $Receipts
        $dup = @(); foreach ($k in (Get-SdDuplicateKeys (Read-SdNode (Join-Path $s.Candidate.Dir 'candidate.json')) $written)) { if ($amendKeys -cnotcontains $k) { $dup += $k } }
        if ($dup.Count -eq 0) { $base.State = 'REVIEW'; $base.Kind = 'REVIEW'; return $base }
        $base.Candidate = $null
        $base.Findings = @('前一份研究包寫了別頁已驗收的項目：' + (@($dup | Select-Object -First 8) -join '、') + '；改為參照，不要重寫。') + @($s.Findings)
    }
    $base.State = 'RESEARCH'; $base.Kind = 'RESEARCH'
    return $base
}
function Get-SdResearchWork($Receipts, [object[]]$Ledger, $Pending, $S0, $Amend) {
    # 研究單元依序（前一單元全部完成才排下一單元）。回傳 @{ Work; Gaps; Done }。
    $work = @(); $gaps = @(); $done = $true
    foreach ($u in $script:PsSdUnits) {
        $unitDone = $true
        foreach ($subj in (Get-SdSubjects $u $S0)) {
            $am = $null; $slot = $u.Id + '|' + $subj; if ($Amend.ContainsKey($slot)) { $am = $Amend[$slot] }
            $ps = Get-SdPageState $u $subj $Receipts $Ledger $Pending $S0 $am
            if ($ps.State -eq 'DONE') { continue }
            $unitDone = $false
            if ($ps.State -eq 'BLOCKED') { $gaps += ($u.Id + ' / ' + $subj + '：' + (@($ps.Findings | Select-Object -First 3) -join '；')); continue }
            $work += , $ps
        }
        if (-not $unitDone) { $done = $false; break }
    }
    return @{ Work = $work; Gaps = $gaps; Done = $done }
}
function Get-SdState {
    $ledger = Get-SdLedger
    $receipts = @()
    $work = @(); $gaps = @(); $phase = 'RUNNABLE'; $l5 = $null
    $s0 = Get-SdStage0 $ledger
    $gaps += @($s0.Gaps)
    if ($s0.State -eq 'READ' -or $s0.State -eq 'ROUND2') { $work += @($s0.Work) }
    elseif ($s0.State -eq 'BLOCKED') { $phase = 'BLOCKED' }
    elseif ($s0.State -eq 'WAIT') { $phase = 'WAIT_STATUS' }
    else {
        $J.Skeleton = $s0.Skeleton; $J.Built = $s0.Built
        $receipts = Get-SdReceipts
        $pending = Get-SdPending $receipts
        $rw = Get-SdResearchWork $receipts $ledger $pending $s0 @{}
        $work += @($rw.Work); $gaps += @($rw.Gaps)
        if (-not $rw.Done) { if ($work.Count -eq 0) { $phase = 'BLOCKED' } }
        else {
            # 研究完成：L5 乾淨讀者（第 1 輪沒讀懂的項目先交原研究單元改寫，再由新讀者重問）
            $l5 = Get-SdL5State $s0 $receipts $ledger
            $blocked = (@($l5.Gaps).Count -gt 0)
            $gaps += @($l5.Gaps)
            if ($l5.Amend.Count -gt 0) {
                $aw = Get-SdResearchWork $receipts $ledger $pending $s0 $l5.Amend
                $work += @($aw.Work); $gaps += @($aw.Gaps); if (@($aw.Gaps).Count -gt 0) { $blocked = $true }
            }
            $work += @($l5.Work)
            if ($work.Count -gt 0) { $phase = 'RUNNABLE' } elseif ($blocked) { $phase = 'BLOCKED' } else { $phase = 'RESEARCH_DONE' }
        }
    }
    $used = 0; foreach ($e in $ledger) { if ([int]$e.Input['budget'] -eq $J.Budget -and ($null -eq $e.Outcome -or [string]$e.Outcome['status'] -cne 'SLOT_BUSY')) { $used++ } }
    $limit = [Math]::Min(6000, 300 + 80 * $J.Names.Count * $script:PsSdUnits.Length)
    if ($used -ge $limit -and $work.Count -gt 0) { $gaps += '本次總派工預算已達上限；檢查缺口後加 -Retry 開新預算。'; $work = @(); $phase = 'BLOCKED' }
    return @{ Ledger = $ledger; Receipts = $receipts; Stage0 = $s0; Work = $work; Gaps = $gaps; Phase = $phase; Used = $used; Limit = $limit; L5 = $l5 }
}

# ---------------- L5 乾淨讀者 ----------------
function ConvertTo-SdAns($A) {
    $ids = @(); foreach ($x in @($A['ids'])) { if ($null -ne $x) { $ids += [string]$x } }
    return @{ Class = [string]$A['class']; Ids = $ids; Kind = [string]$A['kind']; Text = [string]$A['text']; Reason = [string]$A['reason'] }
}
function Get-SdBatchId([int]$Round, [object[]]$Questions) {
    $ids = @(); foreach ($q in $Questions) { $ids += [string]$q['id'] }
    $sorted = Sort-PsKnOrdinal -Items $ids
    return ('b' + (Get-PsSdTextHash ([string]$Round + "`n" + (@($sorted) -join "`n"))).Substring(0, 12))
}
function Get-SdReaderFinal($Batch, [string]$Reader, [object[]]$Ledger) {
    # 一位讀者在一個批次的最後答案：@{ State（DONE／WORK／BLOCKED）; Answers（題目 ID → 歸類後的答案）; Work; Findings }
    $base = 'l5/' + $Batch.Round + '/' + $Batch.Id + '/' + $Reader
    $mk = { param($WorkKey, $AskList, [bool]$IsRetry, $Notes) return @{ Kind = 'READER'; Key = $WorkKey; Reader = $Reader; Round = $Batch.Round; Batch = $Batch.Id; Questions = @($AskList); Retry = $IsRetry; Findings = @($Notes); Unit = 'l5'; Subject = $Batch.Id; Page = $Batch.Round } }
    $s1 = Get-SdSlotState (Get-SdRowsFor $Ledger $base)
    if ($null -eq $s1.Accepted) {
        if ($s1.Invalid -ge 2) { return @{ State = 'BLOCKED'; Findings = $s1.Findings } }
        return @{ State = 'WORK'; Work = (& $mk $base $Batch.Questions $false $s1.Findings) }
    }
    $answers = @{}
    foreach ($a in @($s1.Accepted.Outcome['answers'])) { if ($null -ne $a) { $answers[[string]$a['id']] = ConvertTo-SdAns $a } }
    $inv = @(); foreach ($q in $Batch.Questions) { $id = [string]$q['id']; if ($answers.ContainsKey($id) -and $answers[$id].Class -ceq 'INV') { $inv += $id } }
    if ($inv.Count -eq 0) { return @{ State = 'DONE'; Answers = $answers } }
    $s2 = Get-SdSlotState (Get-SdRowsFor $Ledger ($base + '/retry'))
    if ($null -ne $s2.Accepted) { foreach ($a in @($s2.Accepted.Outcome['answers'])) { if ($null -ne $a) { $answers[[string]$a['id']] = ConvertTo-SdAns $a } }; return @{ State = 'DONE'; Answers = $answers } }
    if ($s2.Invalid -ge 2) { return @{ State = 'DONE'; Answers = $answers } }
    # 答案沒有出處：同一輪重問該讀者一次
    $qs = @(); foreach ($q in $Batch.Questions) { if ($inv -ccontains [string]$q['id']) { $qs += , $q } }
    $fs = @(); foreach ($id in $inv) { $fs += ($id + '：' + $answers[$id].Reason) }
    return @{ State = 'WORK'; Work = (& $mk ($base + '/retry') $qs $true (@($s2.Findings) + $fs)) }
}
function Get-SdL5Short([string]$Text, [int]$Max) {
    $t = ($Text -replace '\s+', ' ').Trim()
    if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max) + '…' }
    return $t
}
function Get-SdL5Summary($V) {
    $sum = @()
    foreach ($x in $V.Votes) {
        $t = Get-SdL5Short $x.Ans.Text 120
        if ($x.Vote -ceq 'NIS') { $t = '文件沒寫' }
        elseif ($x.Vote -ceq 'INV') { $t = '答案沒有出處（' + $x.Ans.Reason + '）' }
        elseif (@($x.Ans.Ids).Count -gt 0) { $t = $t + '〔' + (@($x.Ans.Ids) -join '、') + '〕' }
        $sum += ($x.Reader + '：' + $t)
    }
    return ($sum -join '；')
}
function New-SdReaderQuestion($Q, $V) {
    $cat = Get-PsSdL5Category $V.Verdict
    $text = '乾淨讀者兩輪都沒有一致讀懂：' + [string]$Q['prompt'] + '（' + $V.Verdict + '）。讀者答案：' + (Get-SdL5Summary $V) + '。請把這個項目寫清楚，或在 decisions.md 裁決。'
    return @{ Key = ($cat + ':' + [string]$Q['item'] + ':' + [string]$Q['q']); Category = $cat; Question = $text; Affects = @([string]$Q['item']); RaisedBy = 'READER'; Status = 'OPEN'; Evidence = @() }
}
function Get-SdL5State($S0, [object[]]$Receipts, [object[]]$Ledger) {
    # 回傳 @{ Work; Gaps; Amend（'單元|主題' → @{ ItemKeys; Questions; Findings; Cursor }）; Docs（文件 → PASS／NOT_RUN）; Extra（READER 問題）; 計數 }
    $res = @{ Work = @(); Gaps = @(); Amend = @{}; Docs = @{}; Extra = @(); Asked = 0; Passed = 0; Failed = 0; Eligible = @() }
    foreach ($d in $script:PsSdDocOrder) { $res.Docs[$d] = 'NOT_RUN' }
    # 出題的基礎（組裝、可出題的文件、題目）只隨收據與人工輸入改變：同一個行程內快取
    $sig = New-Object System.Text.StringBuilder
    foreach ($r in $Receipts) { [void]$sig.Append([string]$r.Receipt['packetHash']).Append('|') }
    foreach ($n in @('project.md', 'decisions.md')) { [void]$sig.Append((Get-PsSdStatusFingerprint (Get-SdText (Join-Path $J.InputRoot $n)))).Append('|') }
    $ck = Get-PsSdTextHash $sig.ToString()
    if ($null -ne $J.L5Cache -and $J.L5Cache.Key -ceq $ck) { $model = $J.L5Cache.Model; $eligible = $J.L5Cache.Eligible; $questions = $J.L5Cache.Questions }
    else {
        [void](Update-PsSdRegistry $J.SchemaReg $J.Registry $J.Skeleton @($Receipts) @())
        $st = @{ Receipts = @($Receipts); Stage0 = $S0 }
        $model = Build-SdModel $st @()
        $gates = (Get-SdDocGates $model $st $null $null).Gates
        $eligible = @()
        foreach ($d in $script:PsSdDocOrder) {
            $g = $gates[$d]
            if ([string]$g['L5'] -ceq 'NOT_APPLICABLE') { continue }
            $ok = $true; foreach ($l in @('L1', 'L2', 'L3', 'L4')) { if (@('PASS', 'NOT_APPLICABLE') -cnotcontains [string]$g[$l]) { $ok = $false } }
            if ($ok) { $eligible += $d }
        }
        $questions = Get-PsSdL5Questions $model $eligible
        $J.L5Cache = @{ Key = $ck; Model = $model; Eligible = $eligible; Questions = $questions }
    }
    $res.Eligible = $eligible
    $res.Asked = @($questions).Count
    # 批次：由各批次第一個讀者工單定義題目與標準答案
    $batches = New-Object System.Collections.Generic.List[object]; $seenB = @{}
    foreach ($e in $Ledger) {
        if ([string]$e.Input['kind'] -cne 'READER' -or $e.Input['retry'] -eq $true) { continue }
        $bk = [string]$e.Input['round'] + '|' + [string]$e.Input['batch']
        if ($seenB.ContainsKey($bk)) { continue }
        $seenB[$bk] = $true
        $batches.Add(@{ Round = [int]$e.Input['round']; Id = [string]$e.Input['batch']; Questions = @($e.Input['questions']) })
    }
    $verdicts = @{}; $open = @{}
    foreach ($b in $batches) {
        foreach ($q in $b.Questions) { $open[[string]$b.Round + '|' + [string]$q['id']] = $true }
        $finals = @{}; $busy = $false
        foreach ($r in @('R1', 'R2', 'R3')) {
            $f = Get-SdReaderFinal $b $r $Ledger
            if ($f.State -eq 'BLOCKED') { $res.Gaps += ('L5 讀者 ' + $r + '（第 ' + $b.Round + ' 輪 ' + $b.Id + '）本預算兩次不合格：' + (@($f.Findings | Select-Object -First 2) -join '；')); $busy = $true; continue }
            if ($f.State -eq 'WORK') { $res.Work += , $f.Work; $busy = $true; continue }
            $finals[$r] = $f.Answers
        }
        if ($busy) { continue }
        # 文字題交判定 session
        $judge = @{}; $needJudge = @()
        foreach ($q in $b.Questions) {
            if ([string]$q['mode'] -cne 'TEXT') { continue }
            $any = $false; foreach ($r in @('R1', 'R2', 'R3')) { $a = $finals[$r][[string]$q['id']]; if ($null -ne $a -and $a.Class -ceq 'ANS') { $any = $true } }
            if ($any) { $needJudge += , $q }
        }
        if ($needJudge.Count -gt 0) {
            $jk = 'l5/' + $b.Round + '/' + $b.Id + '/judge'
            $sj = Get-SdSlotState (Get-SdRowsFor $Ledger $jk)
            if ($null -eq $sj.Accepted) {
                if ($sj.Invalid -ge 2) { $res.Gaps += ('L5 判定（第 ' + $b.Round + ' 輪 ' + $b.Id + '）本預算兩次不合格：' + (@($sj.Findings | Select-Object -First 2) -join '；')); continue }
                $items = @()
                foreach ($q in $needJudge) {
                    $o = New-PsSdObject; $o['id'] = [string]$q['id']; $o['question'] = [string]$q['prompt']; $o['standard'] = [string]$q['text']
                    $ans = @(); foreach ($r in @('R1', 'R2', 'R3')) { $a = $finals[$r][[string]$q['id']]; if ($null -ne $a -and $a.Class -ceq 'ANS') { $x = New-PsSdObject; $x['reader'] = $r; $x['text'] = $a.Text; $ans += , $x } }
                    $o['answers'] = $ans; $items += , $o
                }
                $res.Work += , @{ Kind = 'JUDGE'; Key = $jk; Round = $b.Round; Batch = $b.Id; Items = $items; Findings = @($sj.Findings); Unit = 'l5'; Subject = $b.Id; Page = $b.Round }
                continue
            }
            foreach ($v in @($sj.Accepted.Outcome['verdicts'])) { if ($null -ne $v) { $judge[[string]$v['id'] + '|' + [string]$v['reader']] = [string]$v['verdict'] } }
        }
        foreach ($q in $b.Questions) {
            $id = [string]$q['id']
            $votes = @()
            foreach ($r in @('R1', 'R2', 'R3')) {
                $a = $finals[$r][$id]
                if ($null -eq $a) { $a = @{ Class = 'INV'; Ids = @(); Kind = ''; Text = ''; Reason = '沒有回答' } }
                $votes += , @{ Reader = $r; Vote = (Get-PsSdL5Vote $q $a ([string]$judge[$id + '|' + $r])); Ans = $a }
            }
            $verdicts[[string]$b.Round + '|' + $id] = @{ Verdict = (Get-PsSdL5Verdict $q $votes); Votes = $votes }
            $open.Remove([string]$b.Round + '|' + $id)
        }
    }
    # 每題：第 1 輪 → 原研究單元改寫 → 第 2 輪（仍不一致就開 READER 問題）
    $amended = @{}; foreach ($r in $Receipts) { foreach ($x in @($r.AmendQuestions)) { $amended[[string]$x] = $true } }
    $need1 = @(); $need2 = @(); $failed1 = @(); $final = @{}
    foreach ($q in $questions) {
        $id = [string]$q['id']
        $v1 = $verdicts['1|' + $id]
        if ($null -eq $v1) { if (-not $open.ContainsKey('1|' + $id)) { $need1 += , $q }; continue }
        if ($v1.Verdict -ceq 'CONSISTENT') { $final[$id] = 'PASS'; continue }
        if (-not $amended.ContainsKey($id)) { $failed1 += , @{ Q = $q; V = $v1 }; continue }
        $v2 = $verdicts['2|' + $id]
        if ($null -eq $v2) { if (-not $open.ContainsKey('2|' + $id)) { $need2 += , $q }; continue }
        if ($v2.Verdict -ceq 'CONSISTENT') { $final[$id] = 'PASS' } else { $final[$id] = 'FAIL'; $res.Extra += , (New-SdReaderQuestion $q $v2) }
    }
    foreach ($pair in @(@(1, $need1), @(2, $need2))) {
        if (@($pair[1]).Count -eq 0) { continue }
        foreach ($g in (Get-PsSdL5Groups $model @($pair[1]))) {
            $bid = Get-SdBatchId $pair[0] $g
            $res.Work += , @{ Kind = 'READER'; Key = ('l5/' + $pair[0] + '/' + $bid + '/R1'); Reader = 'R1'; Round = $pair[0]; Batch = $bid; Questions = @($g); Retry = $false; Findings = @(); Unit = 'l5'; Subject = $bid; Page = $pair[0] }
        }
    }
    # 第 1 輪全部問完才交改寫：同一主題的問題一次改完
    $round1Busy = ($need1.Count -gt 0); foreach ($k in @($open.Keys)) { if (([string]$k).StartsWith('1|')) { $round1Busy = $true } }
    if (-not $round1Busy -and $failed1.Count -gt 0) {
        $idKeys = Get-PsSdIdKeyMap $J.Registry
        foreach ($f in $failed1) {
            $item = [string]$f.Q['item']
            if (-not $model.ItemReceipt.ContainsKey($item) -or -not $idKeys.ContainsKey($item)) { continue }
            $parts = ([string]$model.ItemReceipt[$item]).Split('/')
            $slot = $parts[0] + '|' + $parts[1]
            if (-not $res.Amend.ContainsKey($slot)) { $res.Amend[$slot] = @{ ItemKeys = (New-Object System.Collections.Generic.List[string]); Questions = (New-Object System.Collections.Generic.List[string]); Findings = (New-Object System.Collections.Generic.List[string]); Cursor = '' } }
            $am = $res.Amend[$slot]
            $tk = [string]$idKeys[$item].Prefix + '/' + [string]$idKeys[$item].Key
            if (-not $am.ItemKeys.Contains($tk)) { $am.ItemKeys.Add($tk) }
            $am.Questions.Add([string]$f.Q['id'])
            $am.Findings.Add(([string]$f.Q['prompt'] + ' → ' + $f.V.Verdict + '。讀者答案：' + (Get-SdL5Summary $f.V)))
        }
        foreach ($slot in @($res.Amend.Keys)) {
            $n = 1; foreach ($r in $Receipts) { if ($r.Amend -and ([string]$r.Receipt['unit'] + '|' + [string]$r.Receipt['subject']) -ceq $slot) { $n++ } }
            $res.Amend[$slot].Cursor = 'L5-AMEND-' + $n
        }
    }
    $pendingDocs = @{}
    foreach ($q in $questions) { $id = [string]$q['id']; if (-not $final.ContainsKey($id)) { $pendingDocs[[string]$q['doc']] = $true } elseif ($final[$id] -eq 'PASS') { $res.Passed++ } else { $res.Failed++ } }
    foreach ($d in $eligible) { if (-not $pendingDocs.ContainsKey($d)) { $res.Docs[$d] = 'PASS' } }
    return $res
}

# ---------------- 工單附件：欄位說明（由 schema 產生） ----------------
function Get-SdSchemaBrief($Node) {
    if ($Node -is [bool]) { return '任意' }
    if (-not ($Node -is [System.Collections.IDictionary])) { return '' }
    if ($Node.Contains('$ref')) {
        $name = ([string]$Node['$ref']).Substring(([string]$Node['$ref']).LastIndexOf('/') + 1)
        $map = @{ 'text' = '文字（不得是填充字）'; 'rawText' = '原文'; 'notApplicable' = 'NA：{"na":"理由","evidence":["E1"]}'; 'unresolved' = 'UNRESOLVED：{"unresolved":"缺口說明"}'
            'condition' = '條件式'; 'dataCondition' = '資料條件式（只准 fld／drv／const／ctx／param）'; 'operand' = '運算元'; 'dataOperand' = '資料運算元'; 'date' = '日期 YYYY-MM-DD'
            'slug' = '大寫代號'; 'componentName' = 'Component 原名'; 'psName' = 'PeopleSoft 原名'; 'evRef' = '證據 E<n>'; 'assignment' = '指派 {"field":…,"value":…}'; 'refSpec' = '任一規格項目的參照' }
        if ($map.ContainsKey($name)) { return $map[$name] }
        if ($name.StartsWith('ref')) { $p = $name.Substring(3); return ('參照 ' + $p + '（ID 或 @' + $p + '/自然鍵）') }
        return $name
    }
    if ($Node.Contains('enum')) { return ('值域：' + ((@($Node['enum']) | ForEach-Object { [string]$_ }) -join '／')) }
    if ($Node.Contains('const')) { return ('固定 ' + (ConvertTo-PsSdCanonical $Node['const'])) }
    foreach ($k in @('anyOf', 'oneOf')) {
        if ($Node.Contains($k)) { $parts = @(); foreach ($b in $Node[$k]) { $parts += (Get-SdSchemaBrief $b) }; return ($parts -join '｜') }
    }
    $t = [string]$Node['type']
    if ($t -eq 'array') { $s = '陣列〈' + (Get-SdSchemaBrief $Node['items']) + '〉'; if ($Node.Contains('minItems')) { $s += '（至少 ' + $Node['minItems'] + ' 項）' }; return $s }
    if ($t -eq 'object') {
        if ($Node.Contains('properties')) { $ps = @(); foreach ($k in @($Node['properties'].get_Keys())) { $ps += [string]$k }; return ('物件｛' + ($ps -join '、') + '｝') }
        return '物件'
    }
    if ($t -eq 'string' -and $Node.Contains('pattern')) { return ('字串（格式 ' + $Node['pattern'] + '）') }
    if ($t) { return $t }
    return ''
}
function Get-SdFieldGuide([string[]]$Prefixes) {
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add('# 欄位說明（由 schema 產生；與 schema 不一致時以 schema 為準）'); $out.Add('')
    $out.Add('每個項目寫成 {"type":"<前綴>","key":"<自然鍵>", …欄位}。id、lifecycle 由外環產生，不要寫。'); $out.Add('')
    $base = (Resolve-PsSdRef $J.SchemaReg '' 'urn:ps-spec:schema:common#/$defs/itemBase').Schema
    foreach ($p in $Prefixes) {
        $def = (Resolve-PsSdRef $J.SchemaReg '' (Get-PsSdItemSchemaRoot $p)).Schema
        $req = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
        foreach ($x in @($base['required'])) { [void]$req.Add([string]$x) }
        # 欄位名另存清單：schema 有名為 keys 的欄位（ENT），不能靠字典的 .Keys 列舉
        $props = New-PsSdMap; $names = New-Object System.Collections.Generic.List[string]
        foreach ($k in @($base['properties'].get_Keys())) { if (-not $props.ContainsKey([string]$k)) { $names.Add([string]$k) }; $props[[string]$k] = $base['properties'][$k] }
        foreach ($part in $def['allOf']) { if ($part -is [System.Collections.IDictionary]) { if ($part.Contains('properties')) { foreach ($k in @($part['properties'].get_Keys())) { if (-not $props.ContainsKey([string]$k)) { $names.Add([string]$k) }; $props[[string]$k] = $part['properties'][$k] } }; if ($part.Contains('required')) { foreach ($x in @($part['required'])) { [void]$req.Add([string]$x) } } } }
        $out.Add('## ' + $p + ' ' + $script:PsSdPrefixInfo[$p].Name + '（' + $script:PsSdPrefixInfo[$p].Doc + '）'); $out.Add('')
        $out.Add('| 欄位 | 必填 | 型別／值域 | 說明 |'); $out.Add('|---|---|---|---|')
        foreach ($k in $names) {
            if (@('id', 'lifecycle') -ccontains $k) { continue }
            $sk = ''; if ($script:PsSdSkeletonFields.ContainsKey($p) -and $script:PsSdSkeletonFields[$p] -ccontains $k) { $sk = '（外環由狀態圖解讀帶入，不要寫）' }
            $n = $props[$k]; $d = ''; if ($n -is [System.Collections.IDictionary] -and $n.Contains('description')) { $d = [string]$n['description'] }
            $r = ''; if ($req.Contains($k)) { $r = '✓' }
            $out.Add('| `' + $k + '` | ' + $r + ' | ' + (ConvertTo-PsSdCell (Get-SdSchemaBrief $n)) + ' | ' + (ConvertTo-PsSdCell ($d + $sk)) + ' |')
        }
        $out.Add('')
    }
    return (($out.ToArray() -join "`n") + "`n")
}

# ---------------- 圍欄 ----------------
# 只圍執行狀態與產出；人工輸入目錄不還原（session 期間人改 STATUS 檔或 ADD_SCOPE 裁決由來源指紋判 SOURCE_CHANGED）。
function Get-SdFence {
    $map = @{}
    foreach ($dir in @($J.JobRoot, $J.OutputRoot)) { foreach ($p in (Get-SdFiles $dir)) { $map[$p] = [System.IO.File]::ReadAllBytes($p) } }
    return , $map
}
function Restore-SdFence($Snapshot, [string]$Allowed) {
    $violations = @()
    foreach ($p in $Snapshot.Keys) {
        $now = $null; if ([System.IO.File]::Exists($p)) { $now = [System.IO.File]::ReadAllBytes($p) }
        if ($null -ne $now -and [Convert]::ToBase64String($now) -ceq [Convert]::ToBase64String($Snapshot[$p])) { continue }
        $bytes = $Snapshot[$p]
        $txt = [Text.Encoding]::UTF8.GetString($bytes)
        $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)
        if ($bom) { $txt = $txt.Substring(1) }
        if (-not (Write-PsKnAtomicText -LiteralPath $p -Text $txt -Bom $bom)) { throw 'SDOC_WRITE_DEFERRED' }
        $violations += (Get-SdRel $p)
    }
    foreach ($dir in @($J.JobRoot, $J.OutputRoot)) {
        foreach ($p in (Get-SdFiles $dir)) {
            if ($Snapshot.ContainsKey($p) -or $p -ceq $Allowed) { continue }
            $q = Join-Path (Join-Path $J.RuntimeRoot 'quarantine') ([guid]::NewGuid().ToString('N') + '-' + [System.IO.Path]::GetFileName($p))
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($q))
            [System.IO.File]::Move($p, $q)
            $violations += (Get-SdRel $p)
        }
    }
    return , $violations
}

# ---------------- 輸出驗收 ----------------
function Test-SdReadingOutput($Out, [string]$Reader, [string]$Fp, [string]$Text) {
    $errs = @()
    if ($null -eq $Out) { return , @('output.json 不存在或不是合法 JSON') }
    foreach ($e in (Test-PsSdSchema $J.SchemaReg 'urn:ps-spec:schema:status-reading' $Out)) { $errs += $e }
    if ($errs.Count -gt 0) { return , $errs }
    if ([string]$Out['jobId'] -cne $J.JobId) { $errs += ('jobId 應為 ' + $J.JobId) }
    if ([string]$Out['reader'] -cne $Reader) { $errs += ('reader 應為 ' + $Reader) }
    if ([string]$Out['source']['ref'] -cne 'status.md') { $errs += 'source.ref 應為 status.md' }
    if ([string]$Out['source']['fingerprint'] -cne $Fp) { $errs += 'source.fingerprint 與工單的 STATUS 指紋不同（檔案改了就要重讀）' }
    foreach ($p in (Test-PsSdReading $Text $Out)) { $errs += ($p.Code + '：' + $p.Message) }
    return , $errs
}
function Test-SdRound2Output($Out, [string]$Reader, [string]$Fp, [object[]]$Questions) {
    $errs = @()
    if ($null -eq $Out) { return , @('output.json 不存在或不是合法 JSON') }
    foreach ($e in (Test-PsSdSchema $J.SchemaReg 'urn:ps-sdoc:schema:status-round2' $Out)) { $errs += $e }
    if ($errs.Count -gt 0) { return , $errs }
    if ([string]$Out['jobId'] -cne $J.JobId -or [string]$Out['reader'] -cne $Reader) { $errs += 'jobId／reader 與工單不符' }
    if ([string]$Out['source']['fingerprint'] -cne $Fp) { $errs += 'source.fingerprint 與工單的 STATUS 指紋不同' }
    $want = @(); foreach ($q in $Questions) { $want += [string]$q.id }
    $got = @(); foreach ($a in @($Out['answers'])) { $got += [string]$a['id'] }
    if (((Sort-PsKnOrdinal -Items $want) -join ',') -cne ((Sort-PsKnOrdinal -Items $got) -join ',')) { $errs += ('answers 要逐題回答 ' + ($want -join '、') + ' 各一次') }
    return , $errs
}
function Test-SdResearchOutput($Out, $Work, $State, [string]$Aid, [string]$InputHash) {
    $errs = @()
    if ($null -eq $Out) { return , @('output.json 不存在或不是合法 JSON') }
    foreach ($e in (Test-PsSdSchema $J.SchemaReg 'urn:ps-sdoc:schema:research-packet' $Out)) { $errs += $e }
    if ($errs.Count -gt 0) { return , @($errs | Select-Object -First 30) }
    foreach ($pair in @(@('jobId', $J.JobId), @('attemptId', $Aid), @('unit', $Work.Unit), @('subject', $Work.Subject), @('inputHash', $InputHash))) {
        if ([string]$Out[$pair[0]] -cne [string]$pair[1]) { $errs += ($pair[0] + ' 應為 ' + $pair[1]) }
    }
    if ([int]$Out['page'] -ne [int]$Work.Page) { $errs += ('page 應為 ' + $Work.Page) }
    $unit = Get-PsSdUnit $Work.Unit
    $extraPage = ([string]$Work.Cursor -ceq 'REQUESTS' -or ([string]$Work.Cursor).StartsWith('L5-AMEND'))
    foreach ($x in @('denominators', 'statusTexts', 'programDispositions', 'definitionOnlyCodes')) {
        if ($Out.Contains($x) -and $unit.Extras -notcontains $x) { $errs += ($Work.Unit + ' 單元不能寫 ' + $x) }
        elseif ($Out.Contains($x) -and $extraPage) { $errs += ('上游需求頁與改寫頁不寫 ' + $x + '（第一輪已處置）') }
    }
    if ($extraPage -and [string]$Out['coverage'] -cne 'COMPLETE') { $errs += '上游需求頁與改寫頁要一頁寫完（COMPLETE）' }
    if ([string]$Out['nextCursor'] -ne '' -and [string]$Out['nextCursor'] -ceq [string]$Work.Cursor) { $errs += 'nextCursor 沒有前進' }
    $ctx = New-PsSdResolveContext $J.SchemaReg $J.Registry $J.Skeleton 'status.md' $J.Built 'Check'
    $res = Resolve-PsSdPacket $ctx $Out
    foreach ($e in $res.Errors) { $errs += $e }
    # 全 job 同一個自然鍵只寫一次（跨頁、跨主題）
    $written = Get-SdWrittenKeys $State.Receipts
    foreach ($k in (Get-SdDuplicateKeys $Out $written)) { if (@($Work.Amend) -ccontains $k) { continue }; $errs += ($k + '：別頁已寫過（可引用清單上有），改為參照，不要重寫') }
    # COMPLETE：分母鍵、上游需求、前頁與本頁引用的同單元後寫項目都要處置
    if ([string]$Out['coverage'] -ceq 'COMPLETE') {
        $rcpt = @{ Receipt = (New-PsSdOrderedFrom @('unit', $Work.Unit, 'subject', $Work.Subject)); Packet = $Out }
        $cov = Get-SdCoverage @($rcpt)
        $miss = @(); foreach ($k in @($Work.Required) + @($Work.Requested)) { if (-not (Test-SdCovered $k $cov $J.Registry)) { $miss += $k } }
        if ($miss.Count -gt 0) { $errs += ('COMPLETE 前要處置的鍵還有 ' + $miss.Count + ' 個沒寫成項目、也沒開同鍵的 EVIDENCE_GAP：' + (@($miss | Select-Object -First 12) -join '、')) }
        $fw = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
        foreach ($k in @($res.Forward)) { [void]$fw.Add([string]$k) }
        foreach ($r in $State.Receipts) { if ([string]$r.Receipt['unit'] -ceq $Work.Unit -and [string]$r.Receipt['subject'] -ceq $Work.Subject) { foreach ($k in @((Get-SdResolved $r).Forward)) { [void]$fw.Add([string]$k) } } }
        $owed = @(); foreach ($k in $fw) { if (-not $cov.Items.Contains($k)) { $owed += $k } }
        if ($owed.Count -gt 0) { $owedSorted = Sort-PsKnOrdinal -Items $owed; $errs += ('引用了本單元還沒寫的項目，COMPLETE 前要寫出：' + (@($owedSorted | Select-Object -First 12) -join '、')) }
    }
    return , @($errs | Select-Object -First 40)
}
function Test-SdReviewOutput($Out, $Work, $Packet, [string]$Aid, [string]$InputHash) {
    $res = @{ Errors = @(); Passed = $false; Verdict = ''; Findings = @() }
    if ($null -eq $Out) { $res.Errors = @('output.json 不存在或不是合法 JSON'); return $res }
    $errs = @(); foreach ($e in (Test-PsSdSchema $J.SchemaReg 'urn:ps-sdoc:schema:review' $Out)) { $errs += $e }
    if ($errs.Count -gt 0) { $res.Errors = $errs; return $res }
    foreach ($pair in @(@('jobId', $J.JobId), @('attemptId', $Aid), @('unit', $Work.Unit), @('subject', $Work.Subject), @('inputHash', $InputHash))) {
        if ([string]$Out[$pair[0]] -cne [string]$pair[1]) { $errs += ($pair[0] + ' 應為 ' + $pair[1]) }
    }
    if ([int]$Out['page'] -ne [int]$Work.Page) { $errs += ('page 應為 ' + $Work.Page) }
    $keys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($it in @($Packet['items'])) { [void]$keys.Add([string]$it['type'] + '/' + [string]$it['key']) }
    foreach ($k in @($Out['checkedKeys'])) { if (-not $keys.Contains([string]$k)) { $errs += ('checkedKeys 有本包沒有的 ' + $k) } }
    $v = [string]$Out['verdict']
    if ($v -ceq 'PASS') {
        if (@($Out['checkedKeys']).Count -ne $keys.Count) { $errs += 'PASS 要逐項核對本包每個項目（checkedKeys 要列全部「型別/自然鍵」）' }
        if (@($Out['findings']).Count -gt 0) { $errs += 'PASS 不得有 findings' }
    } elseif (@($Out['findings']).Count -eq 0) { $errs += ($v + ' 要寫 findings') }
    foreach ($f in @($Out['findings'])) { if ([string]$f['key'] -cne 'TOPIC' -and -not $keys.Contains([string]$f['key'])) { $errs += ('findings 的 key 要是本包的「型別/自然鍵」或 TOPIC：' + $f['key']) } }
    $res.Errors = $errs; $res.Verdict = $v; $res.Passed = ($errs.Count -eq 0 -and $v -ceq 'PASS')
    $fs = @(); foreach ($f in @($Out['findings'])) { $fs += ([string]$f['code'] + ' ' + [string]$f['key'] + '：' + [string]$f['detail']) }
    $res.Findings = $fs
    return $res
}

function Test-SdReaderOutput($Out, $Work, [string]$Aid, [string]$InputHash, $Docs) {
    # 讀者答案：結構與題目對齊有錯就整份退回（計次）；逐題驗引用，沒有出處的答案記為無效（同一輪重問一次）。
    $res = @{ Errors = @(); Answers = @(); Invalid = @() }
    if ($null -eq $Out) { $res.Errors = @('output.json 不存在或不是合法 JSON'); return $res }
    $errs = @(); foreach ($e in (Test-PsSdSchema $J.SchemaReg 'urn:ps-sdoc:schema:l5-answers' $Out)) { $errs += $e }
    if ($errs.Count -gt 0) { $res.Errors = @($errs | Select-Object -First 20); return $res }
    foreach ($pair in @(@('jobId', $J.JobId), @('attemptId', $Aid), @('reader', $Work.Reader), @('batch', $Work.Batch), @('inputHash', $InputHash))) { if ([string]$Out[$pair[0]] -cne [string]$pair[1]) { $errs += ($pair[0] + ' 應為 ' + $pair[1]) } }
    if ([int]$Out['round'] -ne [int]$Work.Round) { $errs += ('round 應為 ' + $Work.Round) }
    $byId = @{}; foreach ($a in @($Out['answers'])) { if ($null -eq $a) { continue }; $id = [string]$a['id']; if ($byId.ContainsKey($id)) { $errs += ($id + ' 回答了兩次') } else { $byId[$id] = $a } }
    $want = @(); foreach ($q in $Work.Questions) { $want += [string]$q['id'] }
    foreach ($id in $want) { if (-not $byId.ContainsKey($id)) { $errs += ($id + ' 沒有回答') } }
    foreach ($id in @($byId.Keys)) { if ($want -cnotcontains $id) { $errs += ($id + ' 不是本工單的題目') } }
    if ($errs.Count -gt 0) { $res.Errors = @($errs | Select-Object -First 30); return $res }
    $sections = Get-PsSdMdSections $Docs
    $answers = @(); $inv = @()
    foreach ($q in $Work.Questions) {
        $id = [string]$q['id']
        $c = Test-PsSdL5Answer $byId[$id] $q $sections
        $o = New-PsSdObject; $o['id'] = $id; $o['class'] = $c.Class; $o['ids'] = @($c.Ids); $o['kind'] = $c.Kind; $o['text'] = $c.Text; $o['reason'] = $c.Reason
        $answers += , $o
        if ($c.Class -ceq 'INV') { $inv += $id }
    }
    $res.Answers = $answers; $res.Invalid = $inv
    return $res
}
function Test-SdJudgeOutput($Out, $Work, [string]$Aid, [string]$InputHash) {
    $res = @{ Errors = @(); Verdicts = @() }
    if ($null -eq $Out) { $res.Errors = @('output.json 不存在或不是合法 JSON'); return $res }
    $errs = @(); foreach ($e in (Test-PsSdSchema $J.SchemaReg 'urn:ps-sdoc:schema:l5-judge' $Out)) { $errs += $e }
    if ($errs.Count -gt 0) { $res.Errors = @($errs | Select-Object -First 20); return $res }
    foreach ($pair in @(@('jobId', $J.JobId), @('attemptId', $Aid), @('batch', $Work.Batch), @('inputHash', $InputHash))) { if ([string]$Out[$pair[0]] -cne [string]$pair[1]) { $errs += ($pair[0] + ' 應為 ' + $pair[1]) } }
    if ([int]$Out['round'] -ne [int]$Work.Round) { $errs += ('round 應為 ' + $Work.Round) }
    $want = @{}; foreach ($it in $Work.Items) { foreach ($a in @($it['answers'])) { $want[[string]$it['id'] + '|' + [string]$a['reader']] = $true } }
    $got = @{}
    foreach ($v in @($Out['verdicts'])) {
        if ($null -eq $v) { continue }
        $k = [string]$v['id'] + '|' + [string]$v['reader']
        if (-not $want.ContainsKey($k)) { $errs += ($k + ' 不是本工單要判定的答案') } elseif ($got.ContainsKey($k)) { $errs += ($k + ' 判定了兩次') } else { $got[$k] = $true }
    }
    foreach ($k in @($want.Keys)) { if (-not $got.ContainsKey($k)) { $errs += ($k + ' 沒有判定') } }
    $res.Errors = @($errs | Select-Object -First 30)
    if ($errs.Count -eq 0) { $res.Verdicts = @($Out['verdicts']) }
    return $res
}

# ---------------- 組裝、工作中文件、發布 ----------------
function Build-SdModel($State, [object[]]$Extra) {
    $ai = Read-SdNode (Join-Path $J.SdocDir 'ai-instructions.json')
    if ($null -eq $ai) { throw '缺少 .claude/peoplesoft/sdoc/ai-instructions.json（搬運不完整）。' }
    $xq = @(); foreach ($x in @($Extra)) { if ($null -ne $x) { $xq += , $x } }
    return (Build-PsSdModel @{ SchemaReg = $J.SchemaReg; Registry = $J.Registry; Skeleton = $J.Skeleton; Built = $J.Built; StageResult = $State.Stage0.Result
            StatusRef = 'status.md'; Receipts = @($State.Receipts); ProjectText = (Get-SdText (Join-Path $J.InputRoot 'project.md')); ProjectRef = 'project.md'
            DecisionsText = (Get-SdText (Join-Path $J.InputRoot 'decisions.md')); DecisionsRef = 'decisions.md'; AiTemplate = @($ai['clauses']); ExtraQuestions = $xq })
}
function Get-SdDocGates($Model, $State, $UnitsDone, $L5Docs) {
    # 每份文件的 L1～L5。$UnitsDone 為 $null＝研究單元都已完成；$L5Docs 為 $null＝L5 維持 NOT_RUN。
    $l2 = Invoke-PsSdL2Checks $Model $J.Registry
    $l3 = Invoke-PsSdL3Checks $Model $J.Built 'status.md' $State.Stage0.Summary
    $viol = @{}; foreach ($x in @($l2) + @($l3)) { $viol[$x.Doc + '/' + $x.Layer] = $true }
    $meta = Get-SdMeta $State
    $gates = @{}; $l1Errors = @()
    foreach ($d in $script:PsSdDocOrder) {
        $g = New-PsSdGate $d
        $e0 = New-PsSdEnvelope $Model $d $g $meta $null
        $se = Test-PsSdSchema $J.SchemaReg ('urn:ps-spec:schema:' + $d) $e0
        if (@($se).Count -gt 0) { $g['L1'] = 'FAIL'; foreach ($x in @($se | Select-Object -First 5)) { $l1Errors += @{ Doc = $d; Layer = 'L1'; Code = 'S01'; Message = $x } } } else { $g['L1'] = 'PASS' }
        $g['L2'] = 'PASS'; if ($viol.ContainsKey($d + '/L2')) { $g['L2'] = 'FAIL' }
        if ($g['L3'] -ne 'NOT_APPLICABLE') { $g['L3'] = 'PASS'; if ($viol.ContainsKey($d + '/L3')) { $g['L3'] = 'FAIL' } }
        if ($g['L4'] -ne 'NOT_APPLICABLE') { if ($null -eq $UnitsDone -or $UnitsDone[$d]) { $g['L4'] = 'PASS' } else { $g['L4'] = 'NOT_RUN' } }
        if ($g['L5'] -ne 'NOT_APPLICABLE' -and $null -ne $L5Docs -and $L5Docs.ContainsKey($d)) { $g['L5'] = [string]$L5Docs[$d] }
        $gates[$d] = $g
    }
    return @{ Gates = $gates; L1Errors = $l1Errors; L2 = $l2; L3 = $l3; Meta = $meta }
}
function Save-SdRegistry { Write-SdJson $J.RegistryPath $J.Registry; $J.RegistryStamp = Get-SdHash $J.Registry }
function Get-SdMeta($State) {
    return @{ JobId = $J.JobId; Revision = $J.Revision['id']; Components = @($J.Names); FrameworkFp = (Get-PsSdFrameworkFingerprint $J.SchemaReg); StatusRef = 'status.md'; StatusFp = $State.Stage0.Fingerprint
        ProjectRef = 'project.md'; ProjectFp = (Get-PsSdStatusFingerprint (Get-SdText (Join-Path $J.InputRoot 'project.md'))); DecisionsRef = 'decisions.md'
        DecisionsFp = (Get-PsSdStatusFingerprint (Get-SdText (Join-Path $J.InputRoot 'decisions.md'))); StatusReading = $State.Stage0.Summary }
}
function Update-SdWorkingSet($State) {
    # 工作中文件：已驗收內容的組裝與渲染＋可引用清單（工單指向這裡）。不跑檢核。
    [void](Update-PsSdRegistry $J.SchemaReg $J.Registry $J.Skeleton @($State.Receipts) @())
    $model = Build-SdModel $State @()
    Save-SdRegistry
    $meta = Get-SdMeta $State
    $envs = @{}
    foreach ($d in $script:PsSdDocOrder) { $envs[$d] = New-PsSdEnvelope $model $d (New-PsSdGate $d) $meta $null }
    $set = ConvertTo-PsSdMarkdownSet $model $envs @{ JobId = $J.JobId; Revision = $J.Revision['id']; Phase = 'IN_PROGRESS'; Components = @($J.Names); Violations = @(); Warnings = @(); Problems = @($model.Problems); DocHashes = @{}; SchemaReg = $J.SchemaReg }
    $mdDir = Join-Path $J.WorkDir 'md'
    foreach ($name in $set.Keys) { Write-SdText (Join-Path $mdDir $name) $set[$name] }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# 可引用清單（' + $J.Revision['id'] + '）'); $lines.Add('')
    $lines.Add('參照寫 ID（例：FLD-007）或「@前綴/自然鍵」。「尚待研究」表示已派號、還沒有內容（上游需求）。'); $lines.Add('')
    $idKeys = Get-PsSdIdKeyMap $J.Registry
    foreach ($p in $script:PsSdPrefixInfo.Keys) {
        if (@('TASK', 'DOD', 'DEC', 'AI') -contains $p) { continue }
        $rows = New-Object System.Collections.Generic.List[string]
        $ids = New-Object System.Collections.Generic.List[string]
        foreach ($id in $idKeys.Keys) { if ($idKeys[$id].Prefix -ceq $p) { $ids.Add([string]$id) } }
        $sorted = Get-PsSdSortedById @($ids | ForEach-Object { $o = New-PsSdObject; $o['id'] = $_; $o })
        foreach ($o in $sorted) {
            $id = [string]$o['id']; $label = '尚待研究'
            if ($model.ById.ContainsKey($id)) { $rc = New-PsSdRenderContext $model @{} $null; $label = Get-PsSdLabel $rc $id }
            $rows.Add('| ' + $id + ' | `' + $idKeys[$id].Key + '` | ' + (ConvertTo-PsSdCell $label) + ' |')
        }
        if ($rows.Count -eq 0) { continue }
        $lines.Add('## ' + $p + ' ' + $script:PsSdPrefixInfo[$p].Name); $lines.Add(''); $lines.Add('| ID | 自然鍵 | 名稱 |'); $lines.Add('|---|---|---|')
        foreach ($r in $rows) { $lines.Add($r) }
        $lines.Add('')
    }
    Write-SdText (Join-Path $J.WorkDir 'citeable.md') (($lines.ToArray() -join "`n") + "`n")
    return $model
}
function Get-SdDocUnitsDone($State) {
    # 每份文件的研究單元是否都完成（L4：已驗收內容都經過獨立覆核；單元沒做完記 NOT_RUN）。
    $done = @{}
    foreach ($d in $script:PsSdDocOrder) { $done[$d] = $true }
    if ($State.Phase -eq 'RESEARCH_DONE') { return $done }
    foreach ($d in $script:PsSdDocOrder) {
        foreach ($u in $script:PsSdUnits) {
            $hit = $false; foreach ($p in $u.Types) { if ($script:PsSdPrefixInfo[$p].Doc -eq $d) { $hit = $true } }
            if (-not $hit) { continue }
            foreach ($w in $State.Work) { if ($w.Unit -eq $u.Id) { $done[$d] = $false } }
            if ($State.Phase -ne 'RUNNABLE' -and $State.Phase -ne 'RESEARCH_DONE') { $done[$d] = $false }
        }
    }
    return $done
}
function Publish-Sd($State) {
    $extra = @(); $l5Docs = $null
    if ($null -ne $State.L5) { $extra = @($State.L5.Extra); $l5Docs = $State.L5.Docs }
    $model = Build-SdModel $State $extra
    Save-SdRegistry
    $gg = Get-SdDocGates $model $State (Get-SdDocUnitsDone $State) $l5Docs
    $l2 = $gg.L2; $l3 = $gg.L3; $l1Errors = $gg.L1Errors; $meta = $gg.Meta
    $warn = Get-PsSdSpeculationWarnings $model
    $appr = ConvertFrom-PsSdApprovals (Get-SdText (Join-Path $J.InputRoot 'approvals.md')) 'approvals.md'
    $problems = @($model.Problems) + @($appr.Problems)
    $envs = @{}; $hashes = @{}
    foreach ($d in $script:PsSdDocOrder) {
        $g = $gg.Gates[$d]
        $env = New-PsSdEnvelope $model $d $g $meta $null
        $h = Get-PsSdDocHash $env
        $approval = $null
        foreach ($r in $appr.Rows) {
            if ($r.Doc -eq $d -and $h.StartsWith($r.HashPrefix)) { $approval = New-PsSdOrderedFrom @('approvedBy', $r.ApprovedBy, 'approvedOn', $r.Date, 'docHash', $h) }
        }
        if ($null -ne $approval) { $env = New-PsSdEnvelope $model $d $g $meta $approval }
        $envs[$d] = $env; $hashes[$d] = $h
    }
    $phase = $State.Phase
    if ($phase -eq 'RESEARCH_DONE') {
        $phase = 'APPROVED'
        foreach ($d in $script:PsSdDocOrder) { if ([string]$envs[$d]['status'] -cne 'approved') { $phase = 'REVIEW_READY' } }
        if ($phase -ne 'APPROVED') { foreach ($d in $script:PsSdDocOrder) { if (@('in_review', 'approved') -cnotcontains [string]$envs[$d]['status']) { $phase = 'DRAFT' } } }
    }
    $allViol = @($l1Errors) + @($l2) + @($l3)
    $l5Info = $null; if ($null -ne $State.L5) { $l5Info = @{ Eligible = @($State.L5.Eligible); Asked = $State.L5.Asked; Passed = $State.L5.Passed; Failed = $State.L5.Failed } }
    $set = ConvertTo-PsSdMarkdownSet $model $envs @{ JobId = $J.JobId; Revision = $J.Revision['id']; Phase = $phase; Components = @($J.Names); Violations = $allViol; Warnings = @($warn); Problems = $problems; DocHashes = $hashes; SchemaReg = $J.SchemaReg; L5 = $l5Info }
    $files = [ordered]@{}
    foreach ($name in $set.Keys) { $files[$name] = $set[$name] }
    foreach ($d in $script:PsSdDocOrder) { $files['canonical/' + $d + '.json'] = ConvertTo-PsSdJsonText $envs[$d] }
    $files['canonical/evidence.json'] = ConvertTo-PsSdJsonText (Get-PsSdEvidenceDoc $model $J.JobId $J.Revision['id'])
    $docs = [ordered]@{}
    foreach ($d in $script:PsSdDocOrder) { $docs[$d] = New-PsSdOrderedFrom @('status', [string]$envs[$d]['status'], 'gate', $envs[$d]['gate'], 'summary', [string]$envs[$d]['summary'], 'docHash', $hashes[$d]) }
    $vl = @(); foreach ($x in $allViol) { $vl += ($x.Doc + '/' + $x.Layer + ' ' + $x.Code + ' ' + $x.Message) }
    $wl = @(); foreach ($x in $warn) { $wl += ($x.Doc + ' ' + $x.Code + ' ' + $x.Message) }
    $gate = New-PsSdOrderedFrom @('schemaVersion', 1, 'jobId', $J.JobId, 'revision', $J.Revision['id'], 'phase', $phase, 'components', @($J.Names), 'docs', $docs, 'violations', $vl, 'warnings', $wl, 'problems', @($problems), 'assurance', '結構驗證、獨立 session 的證據覆核與確定性檢核；不是企業環境 E2E，也不保證重建無差異。')
    $files['gate.json'] = ConvertTo-PsSdJsonText $gate
    $all = New-Object System.Text.StringBuilder
    foreach ($k in $files.Keys) { [void]$all.Append($k + "`n" + $files[$k] + "`n") }
    $generation = (Get-PsSdTextHash $all.ToString()).Substring(0, 24)
    $dir = Join-Path (Join-Path $J.OutputRoot 'generated') $generation
    foreach ($k in $files.Keys) {
        $path = Join-Path $dir $k
        $ok = Write-PsKnCreateOnlyText -LiteralPath $path -Text $files[$k]
        if ($null -eq $ok) { throw 'SDOC_WRITE_DEFERRED' }
        if (-not $ok -and (Read-PsKnText -LiteralPath $path) -cne $files[$k]) { throw ('既有 generated 檔案已被修改；保留人工內容，不覆寫：' + (Get-SdRel $path)) }
    }
    if ((Get-SdSource).Hash -cne $J.Revision['sourceHash']) { throw 'SDOC_SOURCE_CHANGED' }
    $rel = 'generated/' + $generation
    $readme = @('# Spec 文件（本機入口）', '', ('整體狀態：**' + $phase + '**'), '', ('- [00 索引（從這裡開始）](' + $rel + '/00-index.md)'), ('- [90 問題清單](' + $rel + '/90-questions.md)'), ('- [品質狀態 gate.json](' + $rel + '/gate.json)'), '',
        ('人工輸入在 `' + (Get-SdRel $J.InputRoot) + '/`：status.md（狀態圖）、project.md（目標）、decisions.md（裁決 90 的問題）、approvals.md（核准）。'),
        'generated 是可重建投影，請勿在其中人工修稿；修改走研究重跑或 decisions.md。',
        'REVIEW_READY 代表五層檢核通過，不代表企業 E2E 或可無差異重建；approved 只能由人寫進 approvals.md。', '',
        '在 PowerShell 繼續：', ('`' + $J.NextCommand + '`'), '', '重新研究：同命令加 -Refresh；修正失敗原因後重試：同命令加 -Retry。') -join "`n"
    Write-SdText (Join-Path $J.OutputRoot 'README.md') ($readme + "`n")
    Write-SdJson (Join-Path $J.OutputRoot 'current.json') (New-PsSdOrderedFrom @('schemaVersion', 1, 'generation', $generation, 'revision', $J.Revision['id'], 'phase', $phase, 'index', ($rel + '/00-index.md'), 'gate', ($rel + '/gate.json')))
    return @{ Phase = $phase; Generation = $generation; Model = $model; Violations = $allViol; Problems = $problems }
}

# ---------------- 派工 ----------------
function Get-SdSkeletonForEntity([string]$Entity) {
    $out = @()
    foreach ($tk in @($J.Skeleton.Entities[$Entity])) {
        $i = $tk.IndexOf('/'); $p = $tk.Substring(0, $i); $k = $tk.Substring($i + 1)
        $o = New-PsSdObject
        $o['type'] = $p; $o['id'] = Get-PsSdRegisteredId $J.Registry $p $k; $o['key'] = $k
        $sk = $J.Skeleton[$p][$k]
        foreach ($f in $sk.Keys) { $o[[string]$f] = Copy-PsSdNode $sk[$f] }
        foreach ($f in @('parent', 'from', 'to')) { if ($o.Contains($f) -and ([string]$o[$f]).StartsWith('@STATE/')) { $o[$f] = Get-PsSdRegisteredId $J.Registry 'STATE' ([string]$o[$f]).Substring(7) } }
        if ($o.Contains('regions')) { foreach ($r in $o['regions']) { $fs = @(); foreach ($x in @($r['finalStates'])) { $fs += (Get-PsSdRegisteredId $J.Registry 'STATE' ([string]$x).Substring(7)) }; $r['finalStates'] = $fs } }
        $out += , $o
    }
    return , $out
}
function Invoke-SdAttempt($Work, $State) {
    $n = 1 + (Get-SdNumber $J.AttemptRoot '^a([0-9]{4,8})$')
    $aid = 'a' + $n.ToString('0000', [System.Globalization.CultureInfo]::InvariantCulture)
    $ad = Join-Path $J.AttemptRoot $aid
    [void][System.IO.Directory]::CreateDirectory($ad)
    $kind = $Work.Kind
    # 讀者與判定都在 inbox 隔離：看不到其他讀者、研究包或標準答案
    $isolated = @('STATUS_READ', 'STATUS_ROUND2', 'READER', 'JUDGE') -contains $kind
    $agent = 'ps-sdoc-worker'
    if ($kind -like 'STATUS_*') { $agent = 'ps-status-reader' } elseif ($kind -eq 'READER') { $agent = 'ps-spec-reader' } elseif ($kind -eq 'JUDGE') { $agent = 'ps-spec-judge' }
    $box = $ad
    if ($isolated) {
        $box = $J.InboxDir
        if ([System.IO.Directory]::Exists($box)) { foreach ($f in (Get-SdFiles $box)) { [System.IO.File]::Delete($f) } }
        [void][System.IO.Directory]::CreateDirectory($box)
    }
    $outPath = Join-Path $box 'output.json'
    $packet = $null; $candidateId = ''; $candidateHash = ''
    if ($kind -eq 'REVIEW') {
        $candidateId = $Work.Candidate.Id
        $packet = Read-SdNode (Join-Path $Work.Candidate.Dir 'candidate.json')
        $candidateHash = Get-SdHash $packet
        if ($candidateHash -cne [string]$Work.Candidate.Outcome['packetHash']) { throw '候選快照 hash 不符，停止而不沿用。' }
    }
    $inp = New-PsSdObject
    foreach ($kv in @(@('schemaVersion', 1), @('jobId', $J.JobId), @('attemptId', $aid), @('revision', $J.Revision['id']), @('budget', $J.Budget), @('workKey', $Work.Key), @('kind', $kind),
            @('unit', $Work.Unit), @('subject', $Work.Subject), @('page', [int]$Work.Page), @('components', @($J.Names)), @('statusPath', (Get-SdRel (Join-Path $J.InputRoot 'status.md'))))) { $inp[$kv[0]] = $kv[1] }
    $docs = $null
    if ($kind -eq 'READER') {
        $inp['reader'] = $Work.Reader; $inp['round'] = [int]$Work.Round; $inp['batch'] = $Work.Batch; $inp['retry'] = [bool]$Work.Retry
        $inp['perspective'] = $script:PsSdL5Perspectives[$Work.Reader]
        $inp['questions'] = @($Work.Questions)
        $inp['docsDir'] = Get-SdRel (Join-Path $box 'docs')
        # 文件快照：讀者只看這一份，引用也以這一份驗
        $docs = New-PsSdMap
        foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $J.WorkDir 'md') -Filter '*.md' -File)) { $docs[$f.Name] = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8) }
    }
    elseif ($kind -eq 'JUDGE') { $inp['round'] = [int]$Work.Round; $inp['batch'] = $Work.Batch; $inp['items'] = @($Work.Items) }
    elseif ($isolated) {
        $inp['reader'] = $Work.Reader
        $inp['statusRef'] = 'status.md'
        $inp['statusFingerprint'] = $State.Stage0.Fingerprint
        if ($kind -eq 'STATUS_ROUND2') { $qs = @(); foreach ($q in $Work.Questions) { $o = New-PsSdObject; $o['id'] = $q.id; $o['fact'] = $q.fact; $o['lines'] = $q.lines; $qs += , $o }; $inp['questions'] = $qs }
    } else {
        $inp['cursor'] = [string]$Work.Cursor
        $inp['requiredKeys'] = @($Work.Required)
        $inp['requestedKeys'] = @($Work.Requested)
        $inp['workDir'] = Get-SdRel $J.WorkDir
        $inp['citeablePath'] = Get-SdRel (Join-Path $J.WorkDir 'citeable.md')
        $inp['fieldGuidePath'] = Get-SdRel (Join-Path $ad 'fields.md')
        if ($Work.Unit -eq 'workflow') { $inp['skeletonPath'] = Get-SdRel (Join-Path $ad 'skeleton.json') }
        if ($kind -eq 'REVIEW') { $inp['candidateId'] = $candidateId; $inp['candidateHash'] = $candidateHash; $inp['packet'] = $packet }
        if (@($Work.Amend).Count -gt 0) { $inp['amendKeys'] = @($Work.Amend); $inp['amendQuestions'] = @($Work.AmendQuestions); $inp['readerFindings'] = @($Work.L5Findings) }
    }
    $inp['previousFindings'] = @($Work.Findings)
    $inp['outputPath'] = Get-SdRel $outPath
    $inp['inputHash'] = ''
    $inp['inputHash'] = Get-SdHash $inp
    Write-SdJson (Join-Path $ad 'input.json') $inp -Create
    $unitTitle = '第 0 階段：狀態圖解讀'
    if ($kind -eq 'READER' -or $kind -eq 'JUDGE') { $unitTitle = 'L5 乾淨讀者（第 ' + $Work.Round + ' 輪）' }
    elseif (-not $isolated) { $unitTitle = $Work.Unit + '（' + (Get-PsSdUnit $Work.Unit).Title + '）' }
    $m = New-Object System.Collections.Generic.List[string]
    $m.Add('# Spec 文件工單'); $m.Add('')
    foreach ($l in @(('- Job：' + $J.JobId), ('- Attempt：' + $aid), ('- 種類：' + $kind), ('- 研究單元：' + $unitTitle + '；主題：' + $Work.Subject + '；第 ' + $Work.Page + ' 頁'), ('- 工單：' + (Get-SdRel (Join-Path $box 'input.json')) + '（inputHash ' + $inp['inputHash'] + '）'), ('- 輸出：' + (Get-SdRel $outPath) + '（只准寫這一個檔）'), ('- STATUS 檔：' + $inp['statusPath']))) { $m.Add($l) }
    if ($kind -eq 'READER') {
        $m.Add('- 規則：.claude/peoplesoft/sdoc/reader-contract.md')
        $m.Add('- 你的視角：' + $inp['perspective'])
        $m.Add('- 文件：' + $inp['docsDir'] + '/（只看這些 Markdown；從 00-index.md 開始）')
        $m.Add('- 題目：input.json 的 questions，共 ' + @($Work.Questions).Count + ' 題；每題都要回答')
        if ($Work.Retry) { $m.Add('- 重問：這些題目上次的答案沒有出處（引用不存在，或引用的段落裡找不到答案的 ID），重新作答') }
    }
    elseif ($kind -eq 'JUDGE') {
        $m.Add('- 規則：.claude/peoplesoft/sdoc/judge-contract.md')
        $m.Add('- 題目、標準答案與讀者答案：input.json 的 items，共 ' + @($Work.Items).Count + ' 題')
    }
    elseif ($isolated) {
        $m.Add('- 規則：.claude/peoplesoft/sdoc/status-reading-contract.md')
        if ($kind -eq 'STATUS_ROUND2') { $m.Add('- 第 2 輪：逐題回答工單 questions 的每一項（YES／NO／UNSURE）') }
    } else {
        $m.Add('- 規則：.claude/peoplesoft/sdoc/research-contract.md（通用規則＋「' + $Work.Unit + '」一節）'); if ($kind -eq 'REVIEW') { $m.Add('- 覆核：.claude/peoplesoft/sdoc/review-contract.md；被覆核的研究包在工單的 packet') }
        $m.Add('- 欄位說明：' + $inp['fieldGuidePath']); $m.Add('- 可引用清單：' + $inp['citeablePath']); $m.Add('- 目前已驗收的文件：' + $inp['workDir'] + '/md/'); $m.Add('- 知識索引：docs/ps-research/knowledge/index.md')
        $ex = Join-Path $J.SdocDir ('examples/' + $Work.Unit + '.json')
        if ([System.IO.File]::Exists($ex)) { $m.Add('- 範例（合成資料，只看格式；jobId、attemptId、inputHash 照本工單，參照的項目不一定在範例裡）：' + (Get-SdRel $ex)) }
        if ($Work.Unit -eq 'workflow') { $m.Add('- 骨架（狀態圖解讀採用的狀態、轉移、情境，含 ID）：' + $inp['skeletonPath']) }
        if ([string]$Work.Cursor -ne '') { $m.Add('- 游標：' + $Work.Cursor) }
        $hReq = '## 必須處置的分母鍵（COMPLETE 前要全部寫成項目，或開同鍵的 EVIDENCE_GAP 問題）'; $hAsk = '## 上游需求（本頁要產出這些項目，或開同鍵的 EVIDENCE_GAP 問題）'
        if ($kind -eq 'REVIEW') { $hReq = '## 本頁研究前尚未處置的分母鍵（研究包若標 COMPLETE，外環已確認每個鍵都有項目或 EVIDENCE_GAP；覆核看處置是否有證據）'; $hAsk = '## 本頁要處理的上游需求' }
        if (@($Work.Required).Count -gt 0) { $m.Add(''); $m.Add($hReq); $m.Add(''); foreach ($k in $Work.Required) { $m.Add('- `' + $k + '`') } }
        if (@($Work.Amend).Count -gt 0) {
            $hAsk = '## 要改寫的項目（同一個自然鍵寫完整的新版本，取代先前的內容）'
            if ($kind -eq 'REVIEW') { $hAsk = '## 本頁改寫的項目（取代先前的內容；覆核改寫後是否讀得懂、證據是否支持）' }
        }
        if (@($Work.Requested).Count -gt 0) { $m.Add(''); $m.Add($hAsk); $m.Add(''); foreach ($k in $Work.Requested) { $m.Add('- `' + $k + '`') } }
        if (@($Work.L5Findings).Count -gt 0) { $m.Add(''); $m.Add('## 乾淨讀者沒有一致讀懂的地方（只看渲染後文件作答；改寫要讓這些題目答得出來，不要只換說法）'); $m.Add(''); foreach ($f in @($Work.L5Findings)) { $m.Add('- ' + $f) } }
    }
    if (@($Work.Findings).Count -gt 0) { $m.Add(''); $m.Add('## 前次未通過的原因（先修正這些）'); $m.Add(''); foreach ($f in @($Work.Findings | Select-Object -First 30)) { $m.Add('- ' + $f) } }
    $manifest = ($m.ToArray() -join "`n") + "`n"
    Write-SdText (Join-Path $ad 'manifest.md') $manifest
    if ($isolated) {
        $boxInp = $inp
        if ($kind -eq 'READER') {
            # 讀者的工單不含標準答案
            $boxInp = New-PsSdObject; foreach ($k in @($inp.get_Keys())) { $boxInp[[string]$k] = $inp[$k] }
            $qs = @(); foreach ($q in $Work.Questions) { $o = New-PsSdObject; foreach ($k in @('id', 'item', 'q', 'prompt', 'mode', 'ask')) { $o[$k] = $q[$k] }; $qs += , $o }
            $boxInp['questions'] = $qs
            foreach ($name in @($docs.get_Keys())) { Write-SdText (Join-Path (Join-Path $box 'docs') $name) $docs[$name] }
        }
        Write-SdText (Join-Path $box 'manifest.md') $manifest; Write-SdText (Join-Path $box 'input.json') (ConvertTo-PsSdJsonText $boxInp)
    }
    else {
        Write-SdText (Join-Path $ad 'fields.md') (Get-SdFieldGuide (Get-PsSdUnit $Work.Unit).Types)
        if ($Work.Unit -eq 'workflow') { Write-SdText (Join-Path $ad 'skeleton.json') (ConvertTo-PsSdJsonText (Get-SdSkeletonForEntity $Work.Subject)) }
    }
    $fence = Get-SdFence
    Write-Host ('派工 ' + $aid + '：' + $kind + ' ' + $Work.Unit + ' / ' + $Work.Subject + ' / 第 ' + $Work.Page + ' 頁')
    $sr = $null
    try {
        if ($FakeWorker -ne '') {
            $global:LASTEXITCODE = 0
            $null = (& $FakeWorker -AttemptDir $ad -InputPath (Join-Path $box 'input.json') -OutputPath $outPath -Kind $kind -Root $J.Root *>&1 | ForEach-Object { [string]$_ })
            $sr = @{ ExitCode = [int]$LASTEXITCODE; TimedOut = $false; SlotBusy = $false; FailureKind = 'NONE' }
        }
        else { $sr = Invoke-PsOcSession -OcPath $J.OcPath -Root $J.Root -LogRoot (Join-Path $J.Root '.ps-runtime/sdoc-logs') -Model $Model -ExtraArgs ('--agent ' + $agent) -PromptText ($J.JobId + '/' + $aid) -TimeoutMin $TimeoutMin -Tag ($J.JobId + '-' + $aid) -Log { param($msg) Write-Host $msg } -SlotWaitMin 0 -TimeoutParamName 'TimeoutMin' }
    }
    catch { $sr = @{ ExitCode = -1; TimedOut = $false; SlotBusy = $false; FailureKind = 'DISPATCH_ERROR' }; Write-Host ('session 未完成：' + $_.Exception.Message) }
    $violations = Restore-SdFence $fence $outPath
    $outText = $null
    if ([System.IO.File]::Exists($outPath)) { $outText = [System.IO.File]::ReadAllText($outPath, [System.Text.Encoding]::UTF8) }
    if ($isolated) {
        if ($null -ne $outText) { Write-SdText (Join-Path $ad 'output.json') $outText }
        foreach ($f in (Get-SdFiles $box)) { [System.IO.File]::Delete($f) }
    }
    $outcome = New-PsSdOrderedFrom @('status', '', 'counted', $false, 'findings', @(), 'packetHash', '', 'at', (Get-PsKnUtcStamp))
    $accepted = $false
    if ((Get-SdSource).Hash -cne $J.Revision['sourceHash']) { $outcome['status'] = 'SOURCE_CHANGED' }
    elseif ([bool]$sr.SlotBusy) { $outcome['status'] = 'SLOT_BUSY' }
    elseif ($violations.Count -gt 0) { $outcome['status'] = 'INVALID'; $outcome['counted'] = $true; $outcome['findings'] = @('改了不准改的檔案，已還原／隔離：' + (@($violations | Select-Object -First 5) -join '、')) }
    elseif ([bool]$sr.TimedOut -or [int]$sr.ExitCode -ne 0 -or (@('', 'NONE') -notcontains [string]$sr.FailureKind)) { $outcome['status'] = 'SESSION_FAILED'; $outcome['findings'] = @([string]$sr.FailureKind) }
    else {
        $out = $null
        if ($null -ne $outText) { try { $out = ConvertTo-PsSdNode (ConvertFrom-PsSdJson $outText) } catch { $out = $null } }
        if ($kind -eq 'STATUS_READ') {
            $e = Test-SdReadingOutput $out $Work.Reader $State.Stage0.Fingerprint $State.Stage0.Text
            if ($e.Count -gt 0) { $outcome['status'] = 'INVALID'; $outcome['counted'] = $true; $outcome['findings'] = @($e | Select-Object -First 30) } else { $outcome['status'] = 'ACCEPTED' }
        }
        elseif ($kind -eq 'STATUS_ROUND2') {
            $e = Test-SdRound2Output $out $Work.Reader $State.Stage0.Fingerprint $Work.Questions
            if ($e.Count -gt 0) { $outcome['status'] = 'INVALID'; $outcome['counted'] = $true; $outcome['findings'] = @($e | Select-Object -First 30) } else { $outcome['status'] = 'ACCEPTED' }
        }
        elseif ($kind -eq 'READER') {
            $v = Test-SdReaderOutput $out $Work $aid ([string]$inp['inputHash']) $docs
            if (@($v.Errors).Count -gt 0) { $outcome['status'] = 'INVALID'; $outcome['counted'] = $true; $outcome['findings'] = @($v.Errors) }
            else { $outcome['status'] = 'ACCEPTED'; $outcome['answers'] = @($v.Answers); $outcome['invalidIds'] = @($v.Invalid); $outcome['findings'] = @() }
        }
        elseif ($kind -eq 'JUDGE') {
            $v = Test-SdJudgeOutput $out $Work $aid ([string]$inp['inputHash'])
            if (@($v.Errors).Count -gt 0) { $outcome['status'] = 'INVALID'; $outcome['counted'] = $true; $outcome['findings'] = @($v.Errors) }
            else { $outcome['status'] = 'ACCEPTED'; $outcome['verdicts'] = @($v.Verdicts) }
        }
        elseif ($kind -eq 'RESEARCH') {
            $e = Test-SdResearchOutput $out $Work $State $aid ([string]$inp['inputHash'])
            if ($e.Count -gt 0) { $outcome['status'] = 'INVALID'; $outcome['counted'] = $true; $outcome['findings'] = @($e) }
            else { Write-SdJson (Join-Path $ad 'candidate.json') $out -Create; $outcome['status'] = 'CANDIDATE'; $outcome['packetHash'] = Get-SdHash $out }
        }
        else {
            $v = Test-SdReviewOutput $out $Work $packet $aid ([string]$inp['inputHash'])
            if ($v.Errors.Count -gt 0) { $outcome['status'] = 'INVALID'; $outcome['counted'] = $true; $outcome['findings'] = @($v.Errors | Select-Object -First 30) }
            elseif (-not $v.Passed) { $outcome['status'] = 'REVIEW_FAIL'; if ($v.Verdict -ceq 'BLOCKED') { $outcome['status'] = 'REVIEW_BLOCKED' }; $outcome['counted'] = $true; $outcome['findings'] = @($v.Findings) }
            else {
                $rc = New-PsSdOrderedFrom @('schemaVersion', 1, 'revision', $J.Revision['id'], 'unit', $Work.Unit, 'subject', $Work.Subject, 'page', [int]$Work.Page, 'cursor', [string]$Work.Cursor, 'packet', $packet, 'packetHash', $candidateHash, 'review', $out, 'researchAttempt', $candidateId, 'reviewAttempt', $aid, 'acceptedAt', (Get-PsKnUtcStamp))
                if (@($Work.AmendQuestions).Count -gt 0) { $rc['amendQuestions'] = @($Work.AmendQuestions) }
                $rk = (Get-PsSdTextHash $Work.Key).Substring(0, 24)
                Write-SdJson (Join-Path $J.ReceiptRoot ($rk + '.json')) $rc -Create
                $outcome['status'] = 'ACCEPTED'; $accepted = $true
            }
        }
    }
    Write-SdJson (Join-Path $ad 'outcome.json') $outcome -Create
    Write-Host ('本次結果：' + $outcome['status'])
    foreach ($f in @($outcome['findings'] | Select-Object -First 8)) { Write-Host ('  ' + $f) }
    return @{ Status = [string]$outcome['status']; Receipt = $accepted }
}

# ---------------- 主程式 ----------------
$exitCode = 0; $code = 'DOC1-9-02'; $mutex = $null; $held = $false
$J = @{ ResolveCache = @{}; RegistryStamp = ''; LedgerCache = @{}; ReceiptCache = @{}; L5Cache = $null }
try {
    if ($Root -eq '') { $Root = Split-Path $PSScriptRoot -Parent }
    $Root = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if (-not [System.IO.Directory]::Exists($Root) -or -not (Test-PsOcPromptSafe -PromptText $Root) -or ($Model -ne '' -and (-not (Test-PsOcPromptSafe -PromptText $Model) -or $Model -cnotmatch '^[A-Za-z0-9_][A-Za-z0-9_.:/-]*$'))) { throw 'SDOC_ARGUMENT_INVALID' }
    if (($Status -and ($Refresh -or $Retry)) -or ($Refresh -and $Retry)) { throw 'SDOC_ARGUMENT_INVALID' }
    $set = @{}
    $componentText = $Components.Trim()
    if ($componentText.Length -ge 2 -and $componentText.StartsWith("'") -and $componentText.EndsWith("'")) { $componentText = $componentText.Substring(1, $componentText.Length - 2) }
    foreach ($name in @($componentText -split '[,\s]+' | Where-Object { $_ -ne '' })) {
        if ($name -match '[^\x00-\x7F]') { throw 'SDOC_ARGUMENT_INVALID' }
        $upper = $name.ToUpperInvariant()
        if ($upper -cnotmatch '^[A-Z0-9_][A-Z0-9_.$#-]{0,59}$') { throw 'SDOC_ARGUMENT_INVALID' }
        $set[$upper] = $true
    }
    if ($set.Count -eq 0) { throw 'SDOC_ARGUMENT_INVALID' }
    $cli = Get-PsCliVariant -Root $Root
    if ($cli.Name -ne 'claude') { throw 'SDOC_VARIANT' }
    $J.Root = $Root
    $J.Names = Sort-PsKnOrdinal -Items @($set.Keys)
    $J.JobId = 'clone-' + (Get-PsKnTextHash -Text ($J.Names -join "`n")).Substring(0, 16).ToLowerInvariant()
    $J.SdocDir = Join-Path $Root ($cli.PsDir + '/sdoc')
    $J.SchemaDir = Join-Path $J.SdocDir 'schemas'
    $J.RuntimeSchemaDir = Join-Path $J.SdocDir 'schemas-runtime'
    $J.InputRoot = Join-Path (Join-Path $Root '.ps-private/sdoc') $J.JobId
    $J.RuntimeRoot = Join-Path $Root '.ps-runtime/sdoc'
    $J.JobRoot = Join-Path $J.RuntimeRoot $J.JobId
    $J.AttemptRoot = Join-Path $J.JobRoot 'attempts'
    $J.InboxDir = Join-Path $J.JobRoot 'inbox'
    $J.RegistryPath = Join-Path $J.JobRoot 'registry.json'
    $J.OutputRoot = Join-Path (Join-Path $Root 'docs/ps-spec') $J.JobId
    $revisionRoot = Join-Path $J.JobRoot 'revisions'
    $J.NextCommand = "powershell -NoProfile -File '" + $PSCommandPath.Replace("'", "''") + "' -Root '" + $Root.Replace("'", "''") + "' -Components '" + ($J.Names -join ',') + "'"
    if ($Model -ne '') { $J.NextCommand += " -Model '" + $Model + "'" }
    $rootLockId = (Get-PsKnTextHash -Text $Root.ToUpperInvariant()).Substring(0, 16)
    $mutex = New-Object System.Threading.Mutex($false, ('Global\MCPSample-SpecDocs-' + $rootLockId + '-' + $J.JobId))
    try { $held = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $held = $true }
    if (-not $held) { Write-Host '同一組 Component 的文件工作正在執行；稍後用相同命令繼續。'; $code = 'DOC1-0-03'; $exitCode = 3 }
    else {
        $ready = $false
        if ($Status) { $st0 = Get-SdText (Join-Path $J.InputRoot 'status.md'); $ready = ($null -ne $st0 -and -not $st0.Contains($script:SdSkeletonMark) -and (Get-PsSdMermaidLines $st0).Count -gt 0) }
        else { $ready = Initialize-SdInputs }
        if (-not $ready) {
            Write-Host ('等待 STATUS 檔：請把這組 Component 的狀態圖（Mermaid）放進 ' + (Get-SdRel (Join-Path $J.InputRoot 'status.md')) + '，並刪掉第一行的 SDOC:SKELETON 標記。')
            Write-Host ('同一目錄另有 project.md（目標，選填）、decisions.md（裁決）、approvals.md（核准）。放好後用相同命令繼續：')
            Write-Host $J.NextCommand
            $code = 'DOC1-0-01'
        }
        else {
            $J.SchemaReg = Read-PsSdSchemaDir @($J.SchemaDir, $J.RuntimeSchemaDir)
            $source = Get-SdSource
            $rn = Get-SdNumber $revisionRoot '^r([0-9]{4,8})\.json$'
            $J.Revision = $null
            if ($rn -gt 0) { $J.Revision = Read-SdNode (Join-Path $revisionRoot ('r' + $rn.ToString('0000') + '.json')) }
            if ($Status -and $null -eq $J.Revision) { Write-Host '尚未開始。下一步：'; Write-Host $J.NextCommand; $code = 'DOC1-0-02' }
            elseif ($Status -and [string]$J.Revision['sourceHash'] -cne $source.Hash) { Write-Host '狀態：STALE。STATUS 檔、ADD_SCOPE 裁決或 schema 改了；用相同命令建立新版本。'; Write-Host $J.NextCommand; $code = 'DOC1-4-04'; $exitCode = 1 }
            else {
                if ($null -eq $J.Revision -or $Refresh -or [string]$J.Revision['sourceHash'] -cne $source.Hash) {
                    $rn++
                    $J.Revision = New-PsSdOrderedFrom @('schemaVersion', 1, 'id', ('r' + $rn.ToString('0000')), 'sourceHash', $source.Hash, 'sourceFiles', $source.Files, 'knowledge', (Get-SdKnowledgeFingerprint), 'components', @($J.Names), 'createdAt', (Get-PsKnUtcStamp))
                    Write-SdJson (Join-Path $revisionRoot ([string]$J.Revision['id'] + '.json')) $J.Revision -Create
                    Write-Host ('開始新研究版本 ' + $J.Revision['id'] + '；舊版本與文件保留。')
                }
                $J.ReceiptRoot = Join-Path (Join-Path $J.JobRoot 'receipts') ([string]$J.Revision['id'])
                $J.WorkDir = Join-Path (Join-Path $J.JobRoot 'work') ([string]$J.Revision['id'])
                $budgetRoot = Join-Path (Join-Path $J.JobRoot 'budgets') ([string]$J.Revision['id'])
                $J.Budget = Get-SdNumber $budgetRoot '^b([0-9]{4,8})\.json$'
                if ($J.Budget -eq 0 -or $Retry) {
                    $J.Budget++
                    if (-not $Status) { Write-SdJson (Join-Path $budgetRoot ('b' + $J.Budget.ToString('0000') + '.json')) (New-PsSdOrderedFrom @('revision', [string]$J.Revision['id'], 'budget', $J.Budget, 'createdAt', (Get-PsKnUtcStamp), 'explicitRetry', [bool]$Retry)) -Create }
                }
                $J.Registry = Read-PsSdIdRegistry $J.RegistryPath
                $J.RegistryStamp = Get-SdHash $J.Registry
                $state = Get-SdState
                $stopReason = ''; $sessions = 0; $published = $null
                if (-not $Status) {
                    if ($FakeWorker -eq '') { $oc = Get-PsOcPath -Root $Root; $J.OcPath = [string]$oc.Path; if ($J.OcPath -eq '' -and $state.Work.Count -gt 0) { throw ('無法啟動 ' + $oc.Exe + '：' + $oc.Error) } }
                    elseif (-not [System.IO.File]::Exists($FakeWorker)) { throw 'FakeWorker 不存在。' }
                    $failedSubjects = @{}
                    while ($sessions -lt $MaxSessions -and $state.Work.Count -gt 0) {
                        if ($state.Stage0.State -eq 'DONE' -and -not [System.IO.File]::Exists((Join-Path $J.WorkDir 'citeable.md'))) { [void](Update-SdWorkingSet $state) }
                        # 先覆核已有的候選，再開新研究：候選越早驗收，別的主題越早看得到
                        $work = $null
                        foreach ($w in $state.Work) { if ($w.Kind -eq 'REVIEW' -and -not $failedSubjects.ContainsKey($w.Unit + '|' + $w.Subject)) { $work = $w; break } }
                        if ($null -eq $work) { foreach ($w in $state.Work) { if (-not $failedSubjects.ContainsKey($w.Unit + '|' + $w.Subject)) { $work = $w; break } } }
                        if ($null -eq $work) { break }
                        if ((Get-SdSource).Hash -cne [string]$J.Revision['sourceHash']) { $stopReason = 'SOURCE_CHANGED'; break }
                        $r = Invoke-SdAttempt $work $state
                        if ($r.Status -ne 'SLOT_BUSY') { $sessions++ }
                        if (@('SOURCE_CHANGED', 'SLOT_BUSY') -contains $r.Status) { $stopReason = $r.Status; break }
                        if ($r.Status -eq 'SESSION_FAILED') { $stopReason = $r.Status; $failedSubjects[$work.Unit + '|' + $work.Subject] = $true }
                        $state = Get-SdState
                        if ($r.Receipt -or ($work.Kind -like 'STATUS_*' -and $state.Stage0.State -eq 'DONE')) { [void](Update-SdWorkingSet $state) }
                    }
                    $state = Get-SdState
                    if ($stopReason -eq 'SOURCE_CHANGED') { $state.Phase = 'STALE'; $state.Gaps += '來源在 session 期間改變；本次不發布。用相同命令建立新版本。' }
                    elseif ($state.Stage0.State -eq 'DONE' -or $state.Stage0.State -eq 'WAIT') {
                        if ($state.Stage0.State -eq 'WAIT') { $J.Built = $state.Stage0.Built; $J.Skeleton = $state.Stage0.Skeleton; [void](Update-PsSdRegistry $J.SchemaReg $J.Registry $J.Skeleton @() @()) }
                        $published = Publish-Sd $state
                    }
                    Write-SdJson (Join-Path $J.JobRoot 'job.json') (New-PsSdOrderedFrom @('schemaVersion', 1, 'jobId', $J.JobId, 'components', @($J.Names), 'revision', [string]$J.Revision['id'], 'budget', $J.Budget, 'phase', $state.Phase, 'updatedAt', (Get-PsKnUtcStamp)))
                }
                $phase = $state.Phase
                if ($null -ne $published) { $phase = $published.Phase }
                elseif ($phase -eq 'RESEARCH_DONE') { $cur = Read-SdNode (Join-Path $J.OutputRoot 'current.json'); $phase = 'DRAFT'; if ($null -ne $cur) { $phase = [string]$cur['phase'] } }
                $receiptCount = @($state.Receipts).Count
                Write-Host ('狀態：' + $phase + '；本輪 session=' + $sessions + '；已驗收頁=' + $receiptCount + '；待處理=' + $state.Work.Count + '；本預算已用 ' + $state.Used + '／' + $state.Limit)
                if ($null -ne $published) { Write-Host (Get-PsSdFieldStatsLine $published.Model) }
                if ($null -ne $state.L5) { Write-Host ('乾淨讀者（L5）：題目 ' + $state.L5.Asked + '；通過 ' + $state.L5.Passed + '；兩輪仍沒讀懂 ' + $state.L5.Failed) }
                Write-Host ('入口：' + (Join-Path $J.OutputRoot 'README.md'))
                if ($null -ne $J.Revision -and $J.Revision.Contains('knowledge') -and [string]$J.Revision['knowledge'] -cne (Get-SdKnowledgeFingerprint)) { Write-Host '提醒：本版本開始後 docs/ps-research 有更新；要以新知識重查請加 -Refresh。' }
                foreach ($g in $state.Gaps) { Write-Host ('缺口：' + $g) }
                if ($phase -eq 'APPROVED') { Write-Host '全部文件已核准。'; $code = 'DOC1-7-02' }
                elseif ($phase -eq 'REVIEW_READY') { Write-Host '五層檢核全過，可人工審閱與核准（approvals.md）。這不是企業 E2E。'; $code = 'DOC1-7-01' }
                elseif ($phase -eq 'DRAFT') { Write-Host '研究已完成，但仍有檢核未過或 BLOCKING 問題：見 00-index 的「未通過的檢核」與 90 問題清單；裁決寫進 decisions.md 後用相同命令重新組裝。'; Write-Host $J.NextCommand; $code = 'DOC1-5-01' }
                elseif ($phase -eq 'WAIT_STATUS') { Write-Host '三位讀者對 STATUS 檔有仍無多數的解讀或圖與圖矛盾：見 90 問題清單（STATUS_READING_CONFLICT／STATUS_SELF_CONFLICT）。改好 status.md 後用相同命令重跑。'; $code = 'DOC1-4-01'; $exitCode = 1 }
                elseif ($phase -eq 'BLOCKED') { Write-Host '下一步：檢查缺口與 attempts 的 outcome，修正原因後同命令加 -Retry；範圍或來源重做用 -Refresh。'; Write-Host ($J.NextCommand + ' -Retry'); $code = 'DOC1-4-03'; $exitCode = 1 }
                elseif ($phase -eq 'STALE') { Write-Host '下一步：來源已變，用相同命令建立新版本。'; Write-Host $J.NextCommand; $code = 'DOC1-4-04'; $exitCode = 1 }
                else { Write-Host '下一步：用相同命令繼續：'; Write-Host $J.NextCommand; $code = 'DOC1-3-02-' + $state.Work.Count }
                if ($stopReason -eq 'SLOT_BUSY') { Write-Host '模型服務被其他 session 使用，未消耗失敗次數；稍後重跑。'; $code = 'DOC1-3-03'; $exitCode = 1 }
                if ($stopReason -eq 'SESSION_FAILED') { Write-Host 'session 失敗，未消耗失敗次數；檢查 Claude Code／MCP 後重跑。'; $code = 'DOC1-3-04'; $exitCode = 1 }
            }
        }
    }
}
catch {
    $exitCode = 1
    $msg = $_.Exception.Message
    if ($msg -eq 'SDOC_WRITE_DEFERRED') { Write-Host '寫入暫時失敗，未假裝完成；解除檔案占用後用相同命令繼續。'; $code = 'DOC1-3-07' }
    elseif ($msg -eq 'SDOC_SOURCE_CHANGED') { Write-Host '來源在發布前改變，未換 current；用相同命令重建。'; $code = 'DOC1-4-04' }
    elseif ($msg -eq 'SDOC_ARGUMENT_INVALID') { Write-Host '參數錯誤：Components 只收 exact ASCII 物件名（逗號或空白分隔）；Status／Refresh／Retry 不可混用，Model／Root 不可含命令列控制字元。'; $code = 'DOC1-9-01'; $exitCode = 2 }
    elseif ($msg -eq 'SDOC_VARIANT') { Write-Host '這個流程只有 Claude Code 版（.claude/peoplesoft 不存在）。'; $code = 'DOC1-9-01'; $exitCode = 2 }
    else { Write-Host ('無法繼續：' + $msg); if ($env:PS_SDOC_TRACE) { Write-Host $_.ScriptStackTrace }; $code = 'DOC1-9-02'; $exitCode = 2 }
}
finally { if ($held -and $null -ne $mutex) { $mutex.ReleaseMutex() }; if ($null -ne $mutex) { $mutex.Dispose() } }
Write-Host $code
exit $exitCode
