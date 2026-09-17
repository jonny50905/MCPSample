# ps-supplemental.ps1 — 補研究協定 CLI：提交 request／看狀態／看結果（Research 端執行在 ps-auto-loop -SupplementalOnly）
# 用法（公司機）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ps-supplemental.ps1 -New -Target COMPONENT:TW_XXX -FactKind DATA.FILE_INPUT -Properties present,layout,fields [-Context "operation=IMPORT"] [-EvidencePolicy AUDITED] [-Freshness CURRENT] [-DomainHint <領域>] [-ConsumerKind QA] [-Resubmit] [-GitCommit]
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ps-supplemental.ps1 -Submit -NeedFile <need.json> [-DomainHint <領域>] [-ConsumerKind SPEC -JobId <id> -RequirementRef R17] [-Resubmit] [-GitCommit]
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ps-supplemental.ps1 -Status [-Domain <領域>]
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ps-supplemental.ps1 -Result -RequestId S-…-g1
#   （執行補研究：powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ps-auto-loop.ps1 -Domain <領域> -SupplementalOnly [-GitCommit]）
# 責任：只寫 docs/ps-research/supplemental/requests/<requestId>.json（create-only）；-GitCommit 時只 commit 該檔（永不 push）。
# 不呼叫模型、不查 DB、不寫 NN／wiki／checklist、不寫 result（result 只由 auto-loop 迷你圈寫）。
# exit：0＝完成／1＝（保留）／2＝參數、驗證、路由錯誤
# 結論碼（唯一可回報給維護端的一行；其餘只在本機看）：SUPP1-<stage>-<code>[-<count>]
#   stage 1 submit：01 CREATED／02 PENDING（既有、未終局）／03 TERMINAL-<1 RESOLVED|2 PARTIAL|3 UNRESOLVED|4 OUT_OF_SCOPE|5 SUPERSEDED>／04 INVALID-<錯誤數>／05 ROUTING_REQUIRED／06 WRITE_FAILED
#   stage 2 status：01 OK-<筆數>；stage 4 result：01 FOUND-<完成層 1 RESEARCHED|2 AUDITED|3 GRADUATED|4 PROJECTED>／02 NONE／03 NOT_RESEARCHED
#   stage 3 run（auto-loop 迷你圈印）：01 DONE-<results>／02 NOTHING；stage 9 usage：01 BAD_ARGS
param(
    [switch]$New,
    [switch]$Submit,
    [switch]$Status,
    [switch]$Result,
    [string]$Target = '',
    [string]$FactKind = '',
    [string]$Properties = '',
    [string]$Context = '',
    [string]$EvidencePolicy = 'STATIC',
    [string]$Freshness = 'CURRENT',
    [string]$NeedFile = '',
    [string]$DomainHint = '',
    [string]$Domain = '',
    [string]$ConsumerKind = 'MANUAL',
    [string]$JobId = '',
    [string]$RequirementRef = '',
    [string]$RequestId = '',
    [switch]$Resubmit,
    [switch]$GitCommit,
    [string]$Root = ''
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path $PSScriptRoot -Parent }
$Root = [System.IO.Path]::GetFullPath($Root)
. (Join-Path $PSScriptRoot 'ps-knowledge-lib.ps1')
. (Join-Path $PSScriptRoot 'ps-supplemental-lib.ps1')
if ($PsKnowledgeLibVersion -ne 1 -or $PsSupplementalLibVersion -ne 1) { Write-Host "SYSTEM ERROR：lib 版本不符（knowledge=$PsKnowledgeLibVersion supplemental=$PsSupplementalLibVersion）"; exit 2 }
$dirs = Get-PsSuppDirs -Root $Root
if (-not (Test-Path -LiteralPath $dirs.Research)) { Write-Host "SYSTEM ERROR：找不到 $($dirs.Research)（-Root 給錯？）"; exit 2 }

$modes = 0
foreach ($m in @($New, $Submit, $Status, $Result)) { if ($m) { $modes++ } }
if ($modes -ne 1) { Write-Host "用法：-New … | -Submit -NeedFile <json> | -Status [-Domain] | -Result -RequestId <id>（擇一）"; Write-Host "結論代號：SUPP1-9-01"; exit 2 }

function Invoke-SuppGitCommit {
    param([string]$RelPath, [string]$Message)
    try {
        & git -C $Root add -- $RelPath 2>&1 | Out-Null
        $out = (& git -C $Root commit -m $Message -- $RelPath 2>&1 | Out-String)
        if ($LASTEXITCODE -eq 0) { Write-Host ("git：已 commit " + $RelPath) } else { Write-Host ("git commit 失敗（不中斷）：" + $out.Trim()) }
    }
    catch { Write-Host ("git 例外（不中斷）：" + $_.Exception.Message) }
}

function Write-SubmitOutcome {
    param($R)
    Write-Host ("SUPPLEMENTAL：requestId=" + $R.requestId + " state=" + $R.state + " domain=" + $R.domain + " reason=" + $R.reason)
    foreach ($e in @($R.errors)) { Write-Host ("  " + $e) }
    switch ($R.state) {
        'CREATED' {
            Write-Host ("已寫 " + $R.path)
            if ($GitCommit) { Invoke-SuppGitCommit -RelPath ('docs/ps-research/supplemental/requests/' + $R.requestId + '.json') -Message ('kb(supplemental): request ' + $R.requestId) }
            Write-Host "→ 執行：powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ps-auto-loop.ps1 -Domain <領域> -SupplementalOnly（或等 ps-auto-all 下一批）"
            Write-Host "結論代號：SUPP1-1-01"; exit 0
        }
        'PENDING' { Write-Host "→ 同 need 的 request 已存在且尚未終局；等迷你圈處理（-Status 看進度）"; Write-Host "結論代號：SUPP1-1-02"; exit 0 }
        'INVALID' { Write-Host ("結論代號：SUPP1-1-04-" + @($R.errors).Count); exit 2 }
        'ROUTING_REQUIRED' { Write-Host "→ 加 -DomainHint <領域>（該領域必須已有 00-overview.md）"; Write-Host "結論代號：SUPP1-1-05"; exit 2 }
        'WRITE_FAILED' { Write-Host "→ request 檔寫不進去（目標被別的行程開著？）；沒有任何 request 在等，稍後重新提交"; Write-Host "結論代號：SUPP1-1-06"; exit 2 }
        default {
            $idx = @('RESOLVED', 'PARTIAL', 'UNRESOLVED', 'OUT_OF_SCOPE', 'SUPERSEDED').IndexOf([string]$R.state) + 1
            if ($idx -le 0) { $idx = 0 }
            Write-Host "→ 既有結果為終局；要重跑加 -Resubmit（建新世代，舊世代由迷你圈標 SUPERSEDED）"
            Write-Host ("結論代號：SUPP1-1-03-" + $idx); exit 0
        }
    }
}

if ($New -or $Submit) {
    $need = $null
    if ($New) {
        if ($Target -eq '' -or $FactKind -eq '' -or $Properties -eq '') { Write-Host "用法：-New -Target <型別:物件名> -FactKind <碼> -Properties <a,b> …"; Write-Host "結論代號：SUPP1-9-01"; exit 2 }
        $need = ConvertTo-PsSuppNeed -Target $Target -FactKind $FactKind -Properties $Properties -Context $Context -EvidencePolicy $EvidencePolicy -Freshness $Freshness
    }
    else {
        if ($NeedFile -eq '') { Write-Host "用法：-Submit -NeedFile <need.json>"; Write-Host "結論代號：SUPP1-9-01"; exit 2 }
        $nf = $NeedFile
        if (-not [System.IO.Path]::IsPathRooted($nf)) { $nf = Join-Path $Root $nf }
        $obj = Read-PsSuppJsonFile -LiteralPath $nf
        if ($null -eq $obj) { Write-Host "SYSTEM ERROR：need 檔不存在或不是 JSON：$nf"; Write-Host "結論代號：SUPP1-9-01"; exit 2 }
        if ($null -ne $obj.need) { $obj = $obj.need }
        $need = ConvertFrom-PsSuppNeedObject -Obj $obj
    }
    $consumer = @{ kind = $ConsumerKind; jobId = $JobId; requirementRef = $RequirementRef }
    $r = Submit-PsSupplementalRequest -Root $Root -Need $need -Consumer $consumer -DomainHint $DomainHint -Resubmit:$Resubmit
    Write-SubmitOutcome -R $r
}

if ($Status) {
    $rows = Get-PsSuppStatus -Root $Root -Domain $Domain
    Write-Host ("STATUS：" + $rows.Count + " 筆" + $(if ($Domain -ne '') { "（領域 " + $Domain + "）" } else { '' }))
    foreach ($s in $rows) {
        Write-Host ("  " + $s.RequestId + "｜" + $s.Domain + "｜g" + $s.Generation + "｜" + $s.State + "｜attempts=" + $s.Attempts + "｜" + $s.FactKind + "｜" + $s.Target)
    }
    Write-Host "狀態語意：PENDING＝等迷你圈；WAITING_RESEARCH＝目標尚無 NN（迷你圈會在 checklist 寫 D 列，等研究相位建檔）；EXHAUSTED＝兩次嘗試未果（下次迷你圈發 UNRESOLVED）；SUPERSEDED_PENDING＝已被新世代取代；DOMAIN_MISSING＝request 的領域目錄已不存在（改名？）——只能重新提交"
    foreach ($rj in @($PsSuppIntakeRejected)) { Write-Host ("  intake 拒收（不列入）：" + $rj) }
    Write-Host ("結論代號：SUPP1-2-01-" + $rows.Count)
    exit 0
}

if ($Result) {
    if ($RequestId -eq '' -or $RequestId -notmatch $PsSuppRequestIdRx) { Write-Host "用法：-Result -RequestId S-<24hex>-g<n>"; Write-Host "結論代號：SUPP1-9-01"; exit 2 }
    $res = Get-PsSupplementalResult -Root $Root -RequestId $RequestId
    if ($null -eq $res) { Write-Host "RESULT：無（尚未發布；-Status 看進度）"; Write-Host "結論代號：SUPP1-4-02"; exit 0 }
    Write-Host ("RESULT：" + $RequestId + "｜outcome=" + $res.outcome + "｜disposition=" + $res.dispositionCode + "｜auditRoundAtCompletion=" + $res.auditRoundAtCompletion + "｜attempts=" + $res.attempts + "｜completedAt=" + $res.completedAt)
    foreach ($a in @($res.affected)) { Write-Host ("  受影響：" + $a.file + "｜節 " + (@($a.sections) -join '、') + "｜附錄列 " + (@($a.evidenceRows) -join '、')) }
    $c = Get-PsSuppCompletion -Root $Root -RequestId $RequestId
    Write-Host ("完成層：RESEARCHED=" + $c.Researched + " AUDITED=" + $c.Audited + " GRADUATED=" + $c.Graduated + " PROJECTED=" + $c.Projected + $(if ($c.Reason -ne '') { "（" + $c.Reason + "）" } else { '' }))
    if (-not $c.Researched) { Write-Host "結論代號：SUPP1-4-03"; exit 0 }
    $layer = 1
    if ($c.Audited) { $layer = 2 }
    if ($c.Graduated) { $layer = 3 }
    if ($c.Projected) { $layer = 4 }
    Write-Host ("結論代號：SUPP1-4-01-" + $layer)
    exit 0
}
