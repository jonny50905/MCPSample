# ps-knowledge.ps1 — 知識索引 CLI（issue #33）：重建／檢查／查詢 docs/ps-research/knowledge/
# 用法（公司機）：powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ps-knowledge.ps1 -Rebuild
#                powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ps-knowledge.ps1 -Check
#                powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ps-knowledge.ps1 -Find TW_XXX
#                powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ps-knowledge.ps1 -Slice docs\ps-research\<領域>\03-X.md -Section 資料流
# 責任：只讀 docs/ps-research/**、auto-loop-logs/<領域>/audit-r*.done.json；只寫 docs/ps-research/knowledge/{index.json,index.md,objects.md}（原子替換；本機快取，gitignore）。
# 不呼叫模型、不查 DB、不動任何 NN／wiki／checklist。何時跑：內部 git pull 之後、/ps-correct 之後、懷疑索引過時時；
# ps-auto-loop 在 safe point 自動發布，正常批次不必手跑。
# exit：0＝完成（-Check：CURRENT）／1＝-Check STALE／2＝參數或環境錯（含 -Check MISSING）
param(
    [switch]$Rebuild,
    [switch]$Check,
    [string]$Find = '',
    [string]$Slice = '',
    [string]$Section = '',
    [string]$Root = '',
    [string]$LogRoot = ''
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path $PSScriptRoot -Parent }
$Root = [System.IO.Path]::GetFullPath($Root)
. (Join-Path $PSScriptRoot 'ps-knowledge-lib.ps1')
if ($PsKnowledgeLibVersion -ne 1) { Write-Host "SYSTEM ERROR：ps-knowledge-lib.ps1 版本不符（$PsKnowledgeLibVersion）"; exit 2 }
$researchRoot = Join-Path $Root (Join-Path 'docs' 'ps-research')
if (-not (Test-Path -LiteralPath $researchRoot)) { Write-Host "SYSTEM ERROR：找不到 $researchRoot（-Root 給錯？）"; exit 2 }
if ($LogRoot -eq '') { $LogRoot = Join-Path $Root 'auto-loop-logs' }

$modes = 0
if ($Rebuild) { $modes++ }
if ($Check) { $modes++ }
if ($Find -ne '') { $modes++ }
if ($Slice -ne '') { $modes++ }
if ($modes -ne 1) { Write-Host "用法：-Rebuild | -Check | -Find <詞> | -Slice <NN 路徑> -Section <節名>（擇一）"; Write-Host "結論代號：KNOW1-9-01"; exit 2 }

# 結論碼（唯一可回報給維護端的一行；上面的內容只在本機看）：KNOW1-<stage>-<code>[-<count>]
#   stage 1 rebuild：01 OK／02 PUBLISH_DEFERRED；stage 2 check：01 CURRENT／02 STALE-<變動檔數>／03 MISSING；
#   stage 3 find：01 HIT-<筆數>／02 NONE；stage 4 slice：01 OK／02 NOT_FOUND；stage 9 usage：01 BAD_ARGS
if ($Rebuild) {
    $r = Publish-PsKnowledgeIndex -Root $Root -LogRoot $LogRoot
    Write-Host ("KNOWLEDGE：generation=" + $r.generation.Substring(0, 16) + " domains=" + $r.domains + " nn=" + $r.nn + " objects=" + $r.objects + " wiki=" + $r.wiki)
    if (-not $r.published) { Write-Host "PUBLISH_DEFERRED：目標被其他行程開著；舊索引保留，稍後再跑 -Rebuild"; Write-Host "結論代號：KNOW1-1-02"; exit 1 }
    Write-Host ("已寫 " + $r.dir + " 的 index.json／index.md／objects.md")
    Write-Host "結論代號：KNOW1-1-01"
    exit 0
}
if ($Check) {
    $c = Test-PsKnowledgeIndex -Root $Root -LogRoot $LogRoot
    Write-Host ("KNOWLEDGE_CHECK：" + $c.State)
    if ($c.State -eq 'CURRENT') { Write-Host "結論代號：KNOW1-2-01"; exit 0 }
    if ($c.State -eq 'STALE') {
        $n = 0
        if ($null -ne $c.Changed) { $n = @($c.Changed).Count }
        $doctor = Join-Path $LogRoot 'knowledge-doctor.txt'
        try {
            if (-not (Test-Path -LiteralPath $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }
            [System.IO.File]::WriteAllText($doctor, ("[" + (Get-PsKnUtcStamp) + "] " + $c.Reason + "`n"), (New-Object System.Text.UTF8Encoding($false)))
            Write-Host ("變動檔名寫在 " + $doctor + "（本機看；不要貼出）")
        }
        catch { }
        Write-Host "→ 跑 -Rebuild 重建（索引過時只影響定位與等級顯示，內容永遠讀原檔）"
        Write-Host ("結論代號：KNOW1-2-02-" + $n)
        exit 1
    }
    Write-Host "→ 跑 -Rebuild 建立索引"; Write-Host "結論代號：KNOW1-2-03"; exit 2
}
if ($Find -ne '') {
    $idx = Read-PsKnowledgeIndex -Root $Root
    if ($null -eq $idx) { Write-Host "KNOWLEDGE_CHECK：MISSING｜索引不存在，先 -Rebuild"; Write-Host "結論代號：KNOW1-2-03"; exit 2 }
    $h = Find-PsKnowledge -Index $idx -Term $Find
    Write-Host ("FIND：" + $Find + "｜nn=" + $h.nn.Count + " objects=" + $h.objects.Count + " wiki=" + $h.wiki.Count)
    foreach ($e in $h.nn) {
        $secs = @()
        foreach ($sec in @($e.sections)) { $secs += ([string]$sec.name + '@' + $sec.start + '/' + ([int]$sec.end - [int]$sec.start + 1)) }
        Write-Host ("  NN：" + $e.path + "｜" + $e.grade + "｜狀態 " + $e.status + "｜稽核輪次 " + $e.auditRound + "｜" + ($secs -join ';'))
    }
    foreach ($o in $h.objects) { Write-Host ("  物件：" + $o.object + "｜" + $o.type + "｜" + $o.domain + "/" + $o.file + "｜" + $o.role + "｜" + $o.grade) }
    foreach ($w in $h.wiki) { Write-Host ("  wiki：" + $w.path + "｜" + $w.status + "／" + $w.effective + "｜reviewed=" + $w.reviewed + "｜aliases=" + (@($w.aliases) -join '、')) }
    $total = $h.nn.Count + $h.objects.Count + $h.wiki.Count
    if ($total -gt 0) { Write-Host ("結論代號：KNOW1-3-01-" + $total) } else { Write-Host "結論代號：KNOW1-3-02" }
    exit 0
}
if ($Slice -ne '') {
    if ($Section -eq '') { Write-Host "用法：-Slice <NN 路徑> -Section <節名>"; Write-Host "結論代號：KNOW1-9-01"; exit 2 }
    $p = $Slice
    if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $Root $p }
    $s = Get-PsKnowledgeSlice -LiteralPath $p -Section $Section
    if ($null -eq $s) { Write-Host ("SLICE：找不到節「" + $Section + "」或檔案不存在：" + $p); Write-Host "結論代號：KNOW1-4-02"; exit 2 }
    Write-Host ("SLICE：" + $p + "｜" + $Section + "｜" + $s.Start + "-" + $s.End)
    foreach ($l in $s.Lines) { Write-Host $l }
    Write-Host "結論代號：KNOW1-4-01"
    exit 0
}
