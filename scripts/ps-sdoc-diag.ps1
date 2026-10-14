# ps-sdoc-diag.ps1 — Spec 文件流程的診斷報告：只印代號與數字（不印路徑、物件名、jobId、hash），可以用唸的回報給維護端。
# 用法：powershell -NoProfile -File scripts\ps-sdoc-diag.ps1 [-Last 12] [-Cli claude|opencode]
#   讀 .ps-runtime\sdoc[-opencode]\<job>\attempts\aNNNN\{input.json,outcome.json} 與 .ps-runtime\sdoc[-opencode]-logs\*-<job>-aNNNN.{stream.jsonl,err.txt}，
#   每個 attempt 一行、最後一行 SUM 彙總；Claude Code 版另以 ps-session-lib 的 Get-PsOcClaudeApiRetry 算每個 session 的模型端數據。
# 代號：
#   V   N＝新版 scripts（有環境預設與每頁上限）、O＝舊版
#   K   工單種類 R=STATUS_READ 2=STATUS_ROUND2 S=RESEARCH V=REVIEW L=READER J=JUDGE
#   U   研究單元 S0=stage0 SC=scope DA=data SE=security TX=texts WF=workflow IF=interfaces FN=functions UI=ui RU=rules OP=operations TE=testing L5=乾淨讀者
#   S   outcome 狀態 OK=ACCEPTED CA=CANDIDATE IN=INVALID SF=SESSION_FAILED RF=REVIEW_FAIL RB=REVIEW_BLOCKED SB=SLOT_BUSY SC=SOURCE_CHANGED
#   F   findings／sessionFindings T=TIMED_OUT Xn=EXIT_n A=API_ABORTED W=API_RETRY_SLOW K=API_RETRY_STUCK E=API_ERROR C=CONTEXT_OVERFLOW -=NONE ?=其他（驗收錯誤）
#   Q   成功請求數  P   成功的 assistant 事件數（0＝第一個請求就沒成功過）  C   快取命中次數／成功請求數
#   M   主代理最大輸入（k token）  L   主代理最後一次輸入（k token）  O   單次最多輸出（token）
#   RT  模型端重試的狀態碼分布（504x6、NRx2＝無回應）  AE  result 的 api_error_status
#   ERR err 檔分類 E0=空或沒有 E504=含 504 ECONN=連線中斷／重置 E400=含 400 EOTH=其他
#   MD  模型家族 S45/S46/S5/S55=Sonnet 4.5/4.6/5/5.5 O=Opus H=Haiku X=看不出  PT=解讀分段數  CAP=本頁上限  DUR=session 分鐘（檔名時間到 stream 最後寫入）
#   TH  含 thinking 區塊的 assistant 事件數（0＝這個 session 沒開 thinking）  UZ=最後一個成功回應的 usage 數值欄（欄名:值；全 0＝gateway 沒回 usage）
#   LT/LR 卡住的那個請求之前最後一個工具呼叫的名稱／其結果的位元組數（Read 大結果＝卡在輸入側；Write＝卡在寫完之後）  RU=result 事件的 usage 總計 in/cc/cr/out
#   F 另有 INVALID 的驗收錯誤代號 NJ=不是合法 JSON NW=少寫一段 FP=指紋不同 OV=超過每頁上限 SC=schema／欄位錯 LN=逐行交代錯 ?=其他
#   SUM KF=失敗工單種類分布 RT=全部狀態碼分布 CACHE=C0（從沒命中）/C1（部分）/C2（都有） MAXM/MAXO=最大輸入／輸出 P0=第一個請求就失敗的 session 數 AFTEROK=session 失敗但產出照收的 attempt 數
#   ENVNOW 跑本腳本的視窗目前設了哪些覆寫變數：D=PS_SESSION_CLAUDE_ENV_DEFAULTS K=PS_SESSION_CLAUDE_ENV_SKIP I=PS_SDOC_RESEARCH_PAGE_ITEMS L=PS_SDOC_READING_PART_LINES
#          T=MAX_THINKING_TOKENS R=CLAUDE_CODE_MAX_RETRIES A=PS_SESSION_API_ABORT_AFTER N=CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK E=CLAUDE_CODE_EFFORT_LEVEL
#   SUM2（只要回報這一行）：版本 模型家族 種類-findings 狀態碼 TH LT G NEXT——以最近一個失敗的 attempt 為準；G~秒＝估的 gateway 逾時（session 分鐘扣掉成功請求後除以重試數）
#   NEXT 腳本判斷的下一步：0=先解新搬運包 1=設 CLAUDE_CODE_EFFORT_LEVEL=low（adaptive 模型關不掉 thinking，只能壓低）
#        2=縮每次回應（讀者 PS_SDOC_READING_PART_LINES=20；研究 PS_SDOC_RESEARCH_PAGE_ITEMS=4） 3=縮輸入（CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1）
#        4=gateway 不吃 effort（RT 有 400）：拿掉 CLAUDE_CODE_EFFORT_LEVEL 5=改走 OpenCode 版（-Cli opencode） 6=沒有失敗、不用改
param([string]$Root = '', [ValidateRange(1, 500)][int]$Last = 12, [ValidateSet('', 'claude', 'opencode')][string]$Cli = '')
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path $PSScriptRoot -Parent }
. (Join-Path $PSScriptRoot 'ps-session-lib.ps1')

function Get-DgText([string]$Path, [int]$MaxBytes = 65536) {
    if (-not [System.IO.File]::Exists($Path)) { return '' }
    $fs = $null
    try {
        $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $n = [int][Math]::Min([long]$MaxBytes, $fs.Length)
        $buf = New-Object byte[] $n
        $read = $fs.Read($buf, 0, $n)
        return [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
    }
    catch { return '' }
    finally { if ($null -ne $fs) { $fs.Dispose() } }
}
function Get-DgJson([string]$Path) {
    if (-not [System.IO.File]::Exists($Path)) { return $null }
    try { return ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json) } catch { return $null }
}
function Get-DgKind([string]$K) {
    switch ($K) { 'STATUS_READ' { return 'R' } 'STATUS_ROUND2' { return '2' } 'RESEARCH' { return 'S' } 'REVIEW' { return 'V' } 'READER' { return 'L' } 'JUDGE' { return 'J' } }
    return '?'
}
function Get-DgUnit([string]$U) {
    $map = @{ 'stage0' = 'S0'; 'scope' = 'SC'; 'data' = 'DA'; 'security' = 'SE'; 'texts' = 'TX'; 'workflow' = 'WF'; 'interfaces' = 'IF'; 'functions' = 'FN'; 'ui' = 'UI'; 'rules' = 'RU'; 'operations' = 'OP'; 'testing' = 'TE'; 'l5' = 'L5' }
    if ($map.ContainsKey($U)) { return [string]$map[$U] }
    if ($U -eq '') { return '-' }
    return '?'
}
function Get-DgStatus([string]$S) {
    $map = @{ 'ACCEPTED' = 'OK'; 'CANDIDATE' = 'CA'; 'INVALID' = 'IN'; 'SESSION_FAILED' = 'SF'; 'REVIEW_FAIL' = 'RF'; 'REVIEW_BLOCKED' = 'RB'; 'SLOT_BUSY' = 'SB'; 'SOURCE_CHANGED' = 'SC' }
    if ($map.ContainsKey($S)) { return [string]$map[$S] }
    return '?'
}
function Get-DgFindings($List) {
    $out = @()
    foreach ($f in @($List)) {
        $t = [string]$f
        if ($t -eq 'TIMED_OUT') { $out += 'T' }
        elseif ($t -match '^EXIT_(-?\d+)$') { $out += ('X' + $Matches[1]) }
        elseif ($t -eq 'API_ABORTED') { $out += 'A' }
        elseif ($t -eq 'API_RETRY_SLOW') { $out += 'W' }
        elseif ($t -eq 'API_RETRY_STUCK') { $out += 'K' }
        elseif ($t -eq 'API_ERROR') { $out += 'E' }
        elseif ($t -eq 'CONTEXT_OVERFLOW') { $out += 'C' }
        elseif ($t -eq 'NONE' -or $t -eq '') { $out += '-' }
        elseif ($t.Contains('不是合法 JSON')) { $out += 'NJ' }
        elseif ($t.Contains('沒有寫')) { $out += 'NW' }
        elseif ($t.Contains('指紋')) { $out += 'FP' }
        elseif ($t.Contains('超過上限')) { $out += 'OV' }
        elseif ($t.Contains('schema') -or $t.Contains('應為') -or $t.Contains('欄位')) { $out += 'SC' }
        elseif ($t.Contains('交代')) { $out += 'LN' }
        else { $out += '?' }
    }
    if ($out.Count -eq 0) { return '-' }
    return (($out | Select-Object -Unique) -join ',')
}
function Get-DgModel([string]$Head) {
    $m = [regex]::Match($Head, '"model":"([^"]*)"')
    if (-not $m.Success) { return 'X' }
    $id = $m.Groups[1].Value.ToLowerInvariant()
    if ($id -match 'sonnet-?5-?5|sonnet-5\.5') { return 'S55' }
    if ($id -match 'sonnet-?5(?![\d.])|sonnet-5-') { return 'S5' }
    if ($id -match 'sonnet-?4-?6') { return 'S46' }
    if ($id -match 'sonnet-?4-?5') { return 'S45' }
    if ($id -match 'sonnet') { return 'S?' }
    if ($id -match 'opus') { return 'O' }
    if ($id -match 'haiku') { return 'H' }
    return 'X'
}
function Get-DgErrClass([string]$Err) {
    if ($Err.Trim() -eq '') { return 'E0' }
    if ($Err -match '\b504\b|Gateway Time-?out') { return 'E504' }
    if ($Err -match '(?i)connection (lost|reset)|ECONNRESET|socket hang up|fetch failed|terminated|stalled') { return 'ECONN' }
    if ($Err -match '\b400\b') { return 'E400' }
    return 'EOTH'
}
function Format-DgK([int]$N) { return ([string][int][Math]::Round($N / 1000.0) + 'k') }
# stream 的補充數據：thinking 區塊數、最後一個成功回應的 usage 欄位、卡住請求之前的最後一個工具與結果大小、result 的 usage 總計
function Get-DgStreamExtra([string]$Path) {
    $r = @{ Think = 0; Usage = ''; LastTool = ''; LastResultLen = 0; ResultUsage = '' }
    if (-not [System.IO.File]::Exists($Path)) { return $r }
    $ord = [System.StringComparison]::Ordinal
    $tool = ''; $resLen = 0; $frozen = $false; $afterProgress = $false
    $fs = $null; $rd = $null
    try {
        $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $rd = New-Object System.IO.StreamReader($fs, (New-Object System.Text.UTF8Encoding($false)))
        while ($true) {
            $ln = $rd.ReadLine()
            if ($null -eq $ln) { break }
            if ($ln.IndexOf('"subtype":"api_retry"', $ord) -ge 0 -and $ln.IndexOf('"subtype":"api_retry"', $ord) -lt 80) {
                # 一串重試的第一個：凍結「卡住的請求之前」的工具與結果大小（之後恢復又失敗會重新凍結）
                if ($afterProgress) { $r.LastTool = $tool; $r.LastResultLen = $resLen; $afterProgress = $false }
                continue
            }
            $k = $ln.IndexOf('"type":"assistant"', $ord)
            if ($k -ge 0 -and $k -lt 20) {
                if ($ln.IndexOf('"text":"API Error', $ord) -ge 0) { continue }
                $afterProgress = $true
                if ($ln.IndexOf('"type":"thinking"', $ord) -ge 0) { $r.Think++ }
                $m = [regex]::Match($ln, '"type":"tool_use","id":"[^"]*","name":"([^"]+)"')
                if ($m.Success) { $tool = $m.Groups[1].Value }
                $u = $ln.LastIndexOf('"usage":{', $ord)
                if ($u -ge 0) {
                    $win = $ln.Substring($u + 9, [Math]::Min(400, $ln.Length - $u - 9))
                    $pairs = @()
                    foreach ($pm in [regex]::Matches($win, '"([a-z0-9_]+)":(\d+)')) { if ($pairs.Count -lt 8) { $pairs += ($pm.Groups[1].Value.Replace('_input_tokens', '').Replace('_tokens', '') + ':' + $pm.Groups[2].Value) } }
                    if ($pairs.Count -gt 0) { $r.Usage = ($pairs -join ',') }
                }
                continue
            }
            $k = $ln.IndexOf('"type":"user"', $ord)
            if ($k -ge 0 -and $k -lt 20) { if ($ln.IndexOf('"tool_result"', $ord) -ge 0) { $resLen = $ln.Length } ; continue }
            $k = $ln.IndexOf('"type":"result"', $ord)
            if ($k -ge 0 -and $k -lt 40) {
                $u = $ln.IndexOf('"usage":{', $ord)
                if ($u -ge 0) {
                    $uf = Get-PsOcUsageFields ($ln.Substring($u, [Math]::Min(600, $ln.Length - $u)))
                    if ($null -ne $uf) { $r.ResultUsage = ([string]([int]$uf.Context - [int]$uf.CacheRead) + '/' + [int]$uf.CacheRead + '/' + [int]$uf.Output) }
                }
            }
        }
    }
    catch { }
    finally { if ($null -ne $rd) { $rd.Dispose() } elseif ($null -ne $fs) { $fs.Dispose() } }
    return $r
}

$roots = @()
if ($Cli -eq '' -or $Cli -eq 'claude') { $roots += , @{ Dir = (Join-Path $Root '.ps-runtime/sdoc'); Logs = (Join-Path $Root '.ps-runtime/sdoc-logs'); Cli = 'claude' } }
if ($Cli -eq '' -or $Cli -eq 'opencode') { $roots += , @{ Dir = (Join-Path $Root '.ps-runtime/sdoc-opencode'); Logs = (Join-Path $Root '.ps-runtime/sdoc-opencode-logs'); Cli = 'opencode' } }

# 版本：新版 scripts 有環境預設與每頁上限
$v = 'O'
$libTxt = Get-DgText (Join-Path $PSScriptRoot 'ps-session-lib.ps1') 400000
$sdlTxt = Get-DgText (Join-Path $PSScriptRoot 'ps-sdoc-lib.ps1') 400000
if ($libTxt.Contains('PsOcClaudeEnvCommon') -and $sdlTxt.Contains('PsSdResearchPageItems')) { $v = 'N' }
$envNow = @()
foreach ($pair in @(@('D', 'PS_SESSION_CLAUDE_ENV_DEFAULTS'), @('K', 'PS_SESSION_CLAUDE_ENV_SKIP'), @('I', 'PS_SDOC_RESEARCH_PAGE_ITEMS'), @('L', 'PS_SDOC_READING_PART_LINES'), @('T', 'MAX_THINKING_TOKENS'), @('R', 'CLAUDE_CODE_MAX_RETRIES'), @('A', 'PS_SESSION_API_ABORT_AFTER'), @('N', 'CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK'), @('E', 'CLAUDE_CODE_EFFORT_LEVEL'))) {
    $val = [string][System.Environment]::GetEnvironmentVariable($pair[1])
    if ($val -ne '') { $envNow += ($pair[0] + '=' + $val) }
}
$envTxt = '-'
if ($envNow.Count -gt 0) { $envTxt = ($envNow -join ',') }

$rows = @()
$jobs = 0
foreach ($r in $roots) {
    if (-not [System.IO.Directory]::Exists($r.Dir)) { continue }
    foreach ($jd in @(Get-ChildItem -LiteralPath $r.Dir -Directory | Sort-Object Name)) {
        $att = Join-Path $jd.FullName 'attempts'
        if (-not [System.IO.Directory]::Exists($att)) { continue }
        $jobs++
        $jid = $jd.Name
        foreach ($ad in @(Get-ChildItem -LiteralPath $att -Directory | Where-Object { $_.Name -match '^a\d{4,8}$' } | Sort-Object Name)) {
            $oc = Get-DgJson (Join-Path $ad.FullName 'outcome.json')
            $inp = Get-DgJson (Join-Path $ad.FullName 'input.json')
            if ($null -eq $oc -or $null -eq $inp) { continue }
            $row = @{ Job = $jobs; Aid = $ad.Name; Cli = $r.Cli; Kind = (Get-DgKind ([string]$inp.kind)); Unit = (Get-DgUnit ([string]$inp.unit)); Status = (Get-DgStatus ([string]$oc.status))
                Findings = (Get-DgFindings $oc.findings); SessionFindings = ''; Parts = 0; Cap = ''; Api = $null; Model = '-'; Err = 'E0'; Dur = ''; Extra = $null }
            if ($null -ne $oc.PSObject.Properties['sessionFindings']) { $row.SessionFindings = Get-DgFindings $oc.sessionFindings }
            if ($null -ne $inp.PSObject.Properties['outputParts']) { $row.Parts = @($inp.outputParts).Count }
            if ($null -ne $inp.PSObject.Properties['pageItemCap']) { $row.Cap = [string]$inp.pageItemCap }
            if ([System.IO.Directory]::Exists($r.Logs)) {
                $sf = @(Get-ChildItem -LiteralPath $r.Logs -File -Filter ('*-' + $jid + '-' + $ad.Name + '.stream.jsonl') | Sort-Object Name | Select-Object -Last 1)
                $ef = @(Get-ChildItem -LiteralPath $r.Logs -File -Filter ('*-' + $jid + '-' + $ad.Name + '.err.txt') | Sort-Object Name | Select-Object -Last 1)
                if ($sf.Count -gt 0) {
                    $row.Api = Get-PsOcClaudeApiRetry -StreamFile $sf[0].FullName
                    $row.Extra = Get-DgStreamExtra $sf[0].FullName
                    $row.Model = Get-DgModel (Get-DgText $sf[0].FullName 200000)
                    $m = [regex]::Match($sf[0].Name, '^(\d{8})-(\d{6})-')
                    if ($m.Success) {
                        $t0 = $null
                        try { $t0 = [datetime]::ParseExact($m.Groups[1].Value + $m.Groups[2].Value, 'yyyyMMddHHmmss', [System.Globalization.CultureInfo]::InvariantCulture) } catch { $t0 = $null }
                        if ($null -ne $t0) { $row.Dur = [string][int]([Math]::Max(0, ($sf[0].LastWriteTime - $t0).TotalMinutes)) }
                    }
                }
                if ($ef.Count -gt 0) { $row.Err = Get-DgErrClass (Get-DgText $ef[0].FullName 65536) }
            }
            $rows += , $row
        }
    }
}

$failed = @($rows | Where-Object { $_.Status -eq 'SF' })
$afterOk = @($rows | Where-Object { $_.SessionFindings -ne '' })
Write-Host ('DIAG v2 | V=' + $v + ' | JOBS=' + $jobs + ' | ATT=' + $rows.Count + ' | SF=' + $failed.Count + ' | AFTEROK=' + $afterOk.Count + ' | ENVNOW=' + $envTxt)
$show = @($rows | Select-Object -Last $Last)
$kf = @{}; $rt = @{}; $maxM = 0; $maxO = 0; $p0 = 0; $cacheHit = 0; $cacheReq = 0; $models = @{}
foreach ($row in $rows) {
    if ($row.Status -eq 'SF') { $k = $row.Kind; if ($kf.ContainsKey($k)) { $kf[$k] = [int]$kf[$k] + 1 } else { $kf[$k] = 1 } }
    $a = $row.Api
    if ($null -ne $a) {
        if ([int]$a.MaxContextMain -gt $maxM) { $maxM = [int]$a.MaxContextMain }
        if ([int]$a.MaxOutput -gt $maxO) { $maxO = [int]$a.MaxOutput }
        if ([int]$a.Progress -eq 0 -and $row.Status -eq 'SF') { $p0++ }
        $cacheHit += [int]$a.CacheRequests; $cacheReq += [int]$a.Requests
        foreach ($part in ([string]$a.Statuses -split '、')) { $pm = [regex]::Match($part, '^(.+)×(\d+)$'); if ($pm.Success) { $code = $pm.Groups[1].Value; if ($code -eq '無回應') { $code = 'NR' }; if ($rt.ContainsKey($code)) { $rt[$code] = [int]$rt[$code] + [int]$pm.Groups[2].Value } else { $rt[$code] = [int]$pm.Groups[2].Value } } }
        if ($row.Model -ne '-') { $models[$row.Model] = $true }
    }
}
foreach ($row in $show) {
    $line = 'J' + $row.Job + ' A' + $row.Aid.Substring(1) + ' K=' + $row.Kind + ' U=' + $row.Unit + ' S=' + $row.Status + ' F=' + $row.Findings
    if ($row.SessionFindings -ne '') { $line += ' SF=' + $row.SessionFindings }
    $a = $row.Api
    if ($null -ne $a) {
        $sts = [string]$a.Statuses; if ($sts -eq '') { $sts = '-' } else { $sts = $sts.Replace('無回應', 'NR').Replace('×', 'x').Replace('、', ',') }
        $line += ' Q=' + [int]$a.Requests + ' P=' + [int]$a.Progress + ' C=' + [int]$a.CacheRequests + '/' + [int]$a.Requests + ' M=' + (Format-DgK ([int]$a.MaxContextMain)) + ' L=' + (Format-DgK ([int]$a.LastContextMain)) + ' O=' + [int]$a.MaxOutput + ' RT=' + $sts
        if ([string]$a.ApiErrorStatus -ne '') { $line += ' AE=' + [string]$a.ApiErrorStatus }
        if ([int]$a.MaxContextSub -gt 0) { $line += ' MS=' + (Format-DgK ([int]$a.MaxContextSub)) }
        $x = $row.Extra
        if ($null -ne $x) {
            $line += ' TH=' + [int]$x.Think
            if ([string]$x.LastTool -ne '' -or [int]$x.LastResultLen -gt 0) { $lt = [string]$x.LastTool; if ($lt -eq '') { $lt = '-' }; $line += ' LT=' + $lt + ' LR=' + [int]$x.LastResultLen }
            if ([string]$x.Usage -ne '') { $line += ' UZ=' + [string]$x.Usage }
            if ([string]$x.ResultUsage -ne '') { $line += ' RU=' + [string]$x.ResultUsage }
        }
    }
    $line += ' ERR=' + $row.Err + ' MD=' + $row.Model
    if ($row.Parts -gt 0) { $line += ' PT=' + $row.Parts }
    if ($row.Cap -ne '') { $line += ' CAP=' + $row.Cap }
    if ($row.Dur -ne '') { $line += ' DUR=' + $row.Dur }
    Write-Host $line
}
$kfTxt = '-'; if ($kf.Count -gt 0) { $kfTxt = (@($kf.Keys | Sort-Object | ForEach-Object { $_ + ':' + $kf[$_] }) -join ',') }
$rtTxt = '-'; if ($rt.Count -gt 0) { $rtTxt = (@($rt.Keys | Sort-Object | ForEach-Object { $_ + ':' + $rt[$_] }) -join ',') }
$cache = '-'
if ($cacheReq -gt 0) { if ($cacheHit -eq 0) { $cache = 'C0' } elseif ($cacheHit -lt $cacheReq) { $cache = 'C1' } else { $cache = 'C2' } }
# 模型家族彙總：看得出家族的 session 存在時不列 X（合成或看不出 id 的 session）
$mdKeys = @($models.Keys | Sort-Object)
if ($mdKeys.Count -gt 1) { $mdKeys = @($mdKeys | Where-Object { $_ -ne 'X' }) }
$mdTxt = '-'; if ($mdKeys.Count -gt 0) { $mdTxt = ($mdKeys -join ',') }
Write-Host ('SUM | KF=' + $kfTxt + ' | RT=' + $rtTxt + ' | CACHE=' + $cache + ' | MAXM=' + (Format-DgK $maxM) + ' | MAXO=' + $maxO + ' | P0=' + $p0 + ' | MD=' + $mdTxt + ' | AFTEROK=' + $afterOk.Count)

# ---------------- SUM2：一行就夠的回報，與腳本自己判斷的下一步 ----------------
$focus = $null
foreach ($row in $rows) { if ($row.Status -eq 'SF' -and $null -ne $row.Api) { $focus = $row } }
if ($null -eq $focus) { foreach ($row in $rows) { if ($row.Status -eq 'SF') { $focus = $row } } }
$next = 6; $why = '最近沒有 session 失敗；照常續跑'
$sum2 = 'SUM2 ' + $v + ' ' + $mdTxt + ' -'
if ($v -eq 'O') { $next = 0; $why = '跑的是舊版 scripts：先解新搬運包再跑' }
elseif ($null -ne $focus) {
    $a = $focus.Api; $x = $focus.Extra
    $rtF = '-'; $th = 0; $ltTxt = '-'; $gTxt = '-'; $p0f = $false; $has400 = $false
    if ($null -ne $a) {
        $rtF = [string]$a.Statuses; if ($rtF -eq '') { $rtF = '-' } else { $rtF = $rtF.Replace('無回應', 'NR').Replace('×', 'x').Replace('、', ',') }
        if ($rtF -match '(^|,)400x') { $has400 = $true }
        if ([int]$a.Progress -eq 0) { $p0f = $true }
        if ([int]$a.Count -ge 3 -and $focus.Dur -ne '') {
            $g = [int](([int]$focus.Dur * 60 - [int]$a.Requests * 30) / [int]$a.Count)
            if ($g -gt 0) { $gTxt = 'G~' + [string]([int][Math]::Round($g / 10.0) * 10) }
        }
    }
    if ($null -ne $x) {
        $th = [int]$x.Think
        $lt = [string]$x.LastTool
        if ($lt -ne '' -or [int]$x.LastResultLen -gt 0) {
            $code = 'M'
            if ($lt -eq 'Read') { $code = 'R' } elseif ($lt -eq 'Write') { $code = 'W' } elseif ($lt -eq '') { $code = '-' }
            $ltTxt = $code + (Format-DgK ([int]$x.LastResultLen))
        }
    }
    $focusMd = $focus.Model; if ($focusMd -eq '-' -or $focusMd -eq 'X') { $focusMd = $mdTxt }
    $sum2 = 'SUM2 ' + $v + ' ' + $focusMd + ' ' + $focus.Kind + '-' + $focus.Findings + ' ' + $rtF + ' TH' + $th + ' LT=' + $ltTxt + ' ' + $gTxt
    $adaptive = ($focusMd -match '^S(46|5|55)$' -or $focusMd -eq 'O')
    if ($has400) { $next = 4; $why = 'gateway 不吃 effort 參數（狀態碼有 400）：拿掉 CLAUDE_CODE_EFFORT_LEVEL（Remove-Item Env:CLAUDE_CODE_EFFORT_LEVEL）' }
    elseif ($p0f) { $next = 5; $why = '第一個請求就沒成功過：這條線本身過不了，改走 OpenCode 版（scripts\ps-sdoc.ps1 -Cli opencode）' }
    elseif ($th -gt 0 -and $adaptive -and ([string]$env:CLAUDE_CODE_EFFORT_LEVEL).Trim() -eq '') { $next = 1; $why = 'thinking 開著（TH>0）而這個模型關不掉：$env:CLAUDE_CODE_EFFORT_LEVEL = ''low'' 後重跑' }
    elseif ($ltTxt.StartsWith('R') -and [int]$x.LastResultLen -ge 40000) { $next = 3; $why = '卡在讀完大檔之後的請求（輸入側）：$env:CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT = ''1'' 後重跑' }
    elseif ($focus.Kind -eq 'S' -or $focus.Kind -eq 'V') { $next = 2; $why = '縮每次回應：$env:PS_SDOC_RESEARCH_PAGE_ITEMS = ''4'' 後重跑' }
    elseif ($focus.Kind -eq 'R' -or $focus.Kind -eq '2') { $next = 2; $why = '縮每次回應：$env:PS_SDOC_READING_PART_LINES = ''20'' 後重跑' }
    else { $next = 5; $why = '槓桿都試過仍卡：改走 OpenCode 版（scripts\ps-sdoc.ps1 -Cli opencode）' }
}
Write-Host ($sum2 + ' NEXT=' + $next)
Write-Host ('NEXT' + $next + '：' + $why)
exit 0
