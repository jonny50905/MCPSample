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
#   SUM KF=失敗工單種類分布 RT=全部狀態碼分布 CACHE=C0（從沒命中）/C1（部分）/C2（都有） MAXM/MAXO=最大輸入／輸出 P0=第一個請求就失敗的 session 數 AFTEROK=session 失敗但產出照收的 attempt 數
#   ENVNOW 跑本腳本的視窗目前設了哪些覆寫變數：D=PS_SESSION_CLAUDE_ENV_DEFAULTS K=PS_SESSION_CLAUDE_ENV_SKIP I=PS_SDOC_RESEARCH_PAGE_ITEMS L=PS_SDOC_READING_PART_LINES
#          T=MAX_THINKING_TOKENS R=CLAUDE_CODE_MAX_RETRIES A=PS_SESSION_API_ABORT_AFTER N=CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK
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

$roots = @()
if ($Cli -eq '' -or $Cli -eq 'claude') { $roots += , @{ Dir = (Join-Path $Root '.ps-runtime/sdoc'); Logs = (Join-Path $Root '.ps-runtime/sdoc-logs'); Cli = 'claude' } }
if ($Cli -eq '' -or $Cli -eq 'opencode') { $roots += , @{ Dir = (Join-Path $Root '.ps-runtime/sdoc-opencode'); Logs = (Join-Path $Root '.ps-runtime/sdoc-opencode-logs'); Cli = 'opencode' } }

# 版本：新版 scripts 有環境預設與每頁上限
$v = 'O'
$libTxt = Get-DgText (Join-Path $PSScriptRoot 'ps-session-lib.ps1') 400000
$sdlTxt = Get-DgText (Join-Path $PSScriptRoot 'ps-sdoc-lib.ps1') 400000
if ($libTxt.Contains('PsOcClaudeEnvCommon') -and $sdlTxt.Contains('PsSdResearchPageItems')) { $v = 'N' }
$envNow = @()
foreach ($pair in @(@('D', 'PS_SESSION_CLAUDE_ENV_DEFAULTS'), @('K', 'PS_SESSION_CLAUDE_ENV_SKIP'), @('I', 'PS_SDOC_RESEARCH_PAGE_ITEMS'), @('L', 'PS_SDOC_READING_PART_LINES'), @('T', 'MAX_THINKING_TOKENS'), @('R', 'CLAUDE_CODE_MAX_RETRIES'), @('A', 'PS_SESSION_API_ABORT_AFTER'), @('N', 'CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK'))) {
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
                Findings = (Get-DgFindings $oc.findings); SessionFindings = ''; Parts = 0; Cap = ''; Api = $null; Model = '-'; Err = 'E0'; Dur = '' }
            if ($null -ne $oc.PSObject.Properties['sessionFindings']) { $row.SessionFindings = Get-DgFindings $oc.sessionFindings }
            if ($null -ne $inp.PSObject.Properties['outputParts']) { $row.Parts = @($inp.outputParts).Count }
            if ($null -ne $inp.PSObject.Properties['pageItemCap']) { $row.Cap = [string]$inp.pageItemCap }
            if ([System.IO.Directory]::Exists($r.Logs)) {
                $sf = @(Get-ChildItem -LiteralPath $r.Logs -File -Filter ('*-' + $jid + '-' + $ad.Name + '.stream.jsonl') | Sort-Object Name | Select-Object -Last 1)
                $ef = @(Get-ChildItem -LiteralPath $r.Logs -File -Filter ('*-' + $jid + '-' + $ad.Name + '.err.txt') | Sort-Object Name | Select-Object -Last 1)
                if ($sf.Count -gt 0) {
                    $row.Api = Get-PsOcClaudeApiRetry -StreamFile $sf[0].FullName
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
Write-Host ('DIAG v1 | V=' + $v + ' | JOBS=' + $jobs + ' | ATT=' + $rows.Count + ' | SF=' + $failed.Count + ' | AFTEROK=' + $afterOk.Count + ' | ENVNOW=' + $envTxt)
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
exit 0
