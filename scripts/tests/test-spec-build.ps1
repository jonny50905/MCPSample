# test-spec-build.ps1 — 真 PS5.1 CLI＋合成 worker；不查企業資料／MCP，不執行模型。
$ErrorActionPreference = 'Stop'
$testRepo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $testRepo 'scripts/ps-knowledge-lib.ps1')
$testBase = Join-Path ([System.IO.Path]::GetTempPath()) ('ps-clone-build-' + [guid]::NewGuid().ToString('N'))
# 凍結這次待測 production bytes，避免並行維護同一 checkout 被誤判成 fixture 的來源改變。
$testTools = Join-Path $testBase 'framework'
[void][System.IO.Directory]::CreateDirectory($testTools)
foreach($name in @('ps-spec-build.ps1','ps-spec-clone-lib.ps1','ps-knowledge-lib.ps1','ps-session-lib.ps1')){Copy-Item -LiteralPath (Join-Path (Join-Path $testRepo 'scripts') $name) -Destination (Join-Path $testTools $name)}
$testCli = Join-Path $testTools 'ps-spec-build.ps1'
$script:testPass = 0; $script:testFail = 0
function Assert-Build([bool]$Condition, [string]$Name) {
    if ($Condition) { $script:testPass++; Write-Host ('PASS ' + $Name) }
    else { $script:testFail++; Write-Host ('FAIL ' + $Name) }
}
function Write-BuildFixture([string]$Path, [string]$Text, [bool]$Bom = $false) {
    if (-not (Write-PsKnAtomicText -LiteralPath $Path -Text $Text -Bom $Bom)) { throw 'TEST_WRITE_FAILED' }
}
function Read-BuildJson([string]$Path) { return ((Read-PsKnText -LiteralPath $Path) | ConvertFrom-Json) }
function New-BuildRoot([string]$Name) {
    $dir = Join-Path $testBase $Name
    foreach ($p in @('.opencode/peoplesoft/spec/clone-profile.json','.opencode/peoplesoft/spec/clone-contract.md','.opencode/peoplesoft/customization-profile.yaml','.opencode/peoplesoft/business-domain-map.yaml','.opencode/agent/ps-clone-worker.md','.opencode/command/ps-clone-batch.md')) {
        $dst = Join-Path $dir $p
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($dst))
        Copy-Item -LiteralPath (Join-Path $testRepo $p) -Destination $dst
    }
    return $dir
}
function Invoke-Build([string]$Root, [string]$Components = 'TW_DEMO_A', [int]$Sessions = 4, [string]$Mode = 'valid', [switch]$Status, [switch]$Retry, [switch]$Refresh) {
    $prior = $env:PS_CLONE_TEST_MODE
    try {
        $env:PS_CLONE_TEST_MODE = $Mode
        $h = @{Root=$Root;Components=$Components;MaxSessions=$Sessions;FakeWorker=$script:testWorker}
        if($Status){$h.Status=$true}; if($Retry){$h.Retry=$true}; if($Refresh){$h.Refresh=$true}
        $out = ((& $testCli @h *>&1 | ForEach-Object { [string]$_ }) -join "`n")
        $lines = @($out -split "`n" | Where-Object { $_.Trim() -ne '' })
        return @{Output=$out;Exit=$LASTEXITCODE;Code=$lines[-1].Trim()}
    }
    finally { $env:PS_CLONE_TEST_MODE = $prior }
}
function Get-BuildJob([string]$Root) {
    $dirs=@(Get-ChildItem -LiteralPath (Join-Path $Root '.ps-runtime/clone-spec') -Directory | Where-Object { $_.Name -like 'clone-*' })
    if($dirs.Count -ne 1){throw 'TEST_EXPECT_ONE_JOB'}
    return $dirs[0].FullName
}
function Get-BuildRecords([string]$Job, [string]$Kind) {
    $out=@(); $dir=Join-Path $Job $Kind
    if(Test-Path -LiteralPath $dir){foreach($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -Recurse)){if($Kind -eq 'attempts' -and $f.Name -ne 'input.json'){continue};$out+=,(Read-BuildJson $f.FullName)}}
    return , $out
}
function Get-BuildSnapshot([string]$Root) {
    $map=[ordered]@{}
    foreach($f in @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force | Sort-Object FullName)){ $map[$f.FullName]=@((Get-PsKnFileHash -LiteralPath $f.FullName),$f.LastWriteTimeUtc.Ticks) }
    return (ConvertTo-PsKnJson -Value $map -SortKeys)
}
$script:testWorker = Join-Path $testBase 'fake-worker.ps1'
$workerText = @'
param([string]$AttemptDir,[string]$ManifestPath,[string]$OutputPath,[string]$Kind)
$ErrorActionPreference='Stop'
$inp=[System.IO.File]::ReadAllText((Join-Path $AttemptDir 'input.json')) | ConvertFrom-Json
$manifest=[System.IO.File]::ReadAllText($ManifestPath)
$profilePath=[regex]::Match($manifest,'(?m)^ProfilePath: (.+)\r?$').Groups[1].Value.Trim()
$profile=[System.IO.File]::ReadAllText($profilePath) | ConvertFrom-Json
$topic=$profile.topics | Where-Object { $_.id -ceq $inp.topic } | Select-Object -First 1
$mode=$env:PS_CLONE_TEST_MODE
if($Kind -eq 'RESEARCH'){
    $values=[ordered]@{}
    foreach($field in $topic.fields){$values[$field.key]='合成明確行為：'+$field.key}
    $refs=@('S01');$id=$inp.topic+'-1'
    if($inp.topic -eq 'scope'){$id='S01';$refs=@();$values.object=$inp.component;$values.type='COMPONENT';$values.inclusion='CORE';$values.usedBy='使用者啟動';$values.condition='進入指定功能';$values.reason='使用者指定核心'}
    $items=@([ordered]@{id=$id;scopeRefs=$refs;values=$values;evidenceIds=@('E1')})
    if($inp.topic -eq 'scope' -and $mode -eq 'scope-noise'){$x=$items[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json;$x.id='S02';$x.values.object='TW_DEMO_UNUSED';$x.values.inclusion='EXCLUDED';$items+=,$x}
    if($inp.topic -eq 'flows' -and $mode -eq 'scope-noise'){$items[0].scopeRefs=@('S02')}
    if($inp.topic -eq 'acceptance'){
        $items=@();$n=0
        foreach($kindValue in @('POSITIVE','NEGATIVE','BOUNDARY')){$n++;$v=[ordered]@{};foreach($k in $values.Keys){$v[$k]=$values[$k]};$v.scenarioType=$kindValue;$items+=,[ordered]@{id=('A0'+$n);scopeRefs=@('S01');values=$v;evidenceIds=@('E1')}}
    }
    $value=[ordered]@{schemaVersion=1;component=$inp.component;topic=$inp.topic;coverage='COMPLETE';summary='本合成主題的具體行為。';items=$items;evidence=@([ordered]@{id='E1';kind='CHUNK';locator='3f2a9c1e-7b4d-4e8a-9c6f-1d2e3a4b5c6d';excerpt='If DEMO_STATUS = "A" Then'});gaps=@();nextCursor=''}
    if($mode -eq 'partial' -and $inp.topic -eq 'scope'){$value.coverage='PARTIAL';$value.gaps=@('仍缺核心欄位證據')}
    if(@('paged','repeat-cursor','late-na') -contains $mode -and $inp.topic -eq 'flows'){
        $value.items[0].id='flows-'+$inp.page
        $value.items[0].values.scenario='FLOW_PAGE_'+$inp.page
        $value.evidence[0].excerpt='FLOW_SOURCE_PAGE_'+$inp.page
        if([int]$inp.page -eq 1 -or $mode -eq 'repeat-cursor'){$value.coverage='PARTIAL';$value.nextCursor='FLOW_SECOND_BRANCH'}
        if($mode -eq 'late-na' -and [int]$inp.page -gt 1){$value.coverage='NOT_APPLICABLE';$value.items=@();$value.nextCursor='';$value.summary='合成理由：這個主題不適用。'}
    }
    if($mode -eq 'hidden-unknown' -and $inp.topic -eq 'flows'){$value.coverage='PARTIAL';$value.nextCursor='FLOW_SECOND_BRANCH';$value.items[0].values.branches='UNKNOWN'}
    if($mode -eq 'forge-receipt'){
        $job=Split-Path (Split-Path $AttemptDir -Parent) -Parent
        $f=Join-Path (Join-Path (Join-Path $job 'receipts') $inp.revision) 'forged.json'
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($f))
        [System.IO.File]::WriteAllText($f,'{"schemaVersion":1,"forged":true}',(New-Object System.Text.UTF8Encoding($false)))
    }
    if($mode -eq 'mutate-input'){[System.IO.File]::WriteAllText((Join-Path $AttemptDir 'input.json'),'{}',(New-Object System.Text.UTF8Encoding($false)))}
}
else{
    $value=[ordered]@{schemaVersion=1;component=$inp.component;topic=$inp.topic;inputHash=$inp.inputHash;verdict='PASS';checkedIds=@($inp.packet.items | ForEach-Object {$_.id});findings=@();summary='已獨立核對所有合成項目與完整性。'}
    if($mode -eq 'bad-hash'){$value.inputHash=('0'*64)}
    if($mode -eq 'missing-checks'){$value.checkedIds=@()}
    if($mode -eq 'review-fail'){$value.verdict='FAIL';$value.findings=@(@{itemId='TOPIC';code='MISSING_BRANCH';detail='缺少反向分支'})}
}
$text=ConvertTo-Json -InputObject $value -Depth 30
[System.IO.File]::WriteAllText($OutputPath,$text,(New-Object System.Text.UTF8Encoding($false)))
exit 0
'@
Write-BuildFixture $script:testWorker $workerText $true

# 相同輸入一鍵續跑；scope 在每個 Component 內先於其他主題。
$rMulti=New-BuildRoot 'multi'
if(-not [string]::IsNullOrWhiteSpace($env:ComSpec) -and [System.IO.File]::Exists($env:ComSpec)){
    $rCmd=New-BuildRoot 'cmd-quotes'
    # 這一例刻意測實際 cmd.exe 邊界，子 PS 明帶執行原則；其餘 CLI 均同行程呼叫。
    $cmdLine='powershell.exe -NoProfile -ExecutionPolicy Bypass -File "'+$testCli+'" -Root "'+$rCmd+'" -Components ''TW_DEMO_A,TW_DEMO_B'' -Status'
    $cmdOutput=((& $env:ComSpec /d /s /c $cmdLine 2>&1 | ForEach-Object {[string]$_}) -join "`n")
    Assert-Build ($LASTEXITCODE -eq 0 -and $cmdOutput -match 'CLONE1-0-02') '真 cmd.exe 傳 Components 單引號不會拒絕正常入口'
}
$quoted=Invoke-Build $rMulti "'TW_DEMO_A,TW_DEMO_B'" 1 valid -Status
Assert-Build ($quoted.Code -eq 'CLONE1-0-02' -and $quoted.Exit -eq 0) 'cmd 原樣傳來的最外單引號可解析'
$badQuote=Invoke-Build $rMulti "TW_DEMO_'A,TW_DEMO_B" 1 valid -Status
Assert-Build ($badQuote.Code -eq 'CLONE1-9-01' -and $badQuote.Exit -eq 2) '物件名內嵌單引號仍拒絕'
if(-not [string]::IsNullOrWhiteSpace($env:ComSpec) -and [System.IO.File]::Exists($env:ComSpec)){
    $rOther=New-BuildRoot 'other-root'
    $lockHelper=Join-Path $testBase 'hold-job-lock.ps1';$lockReady=Join-Path $testBase 'lock.ready';$lockRelease=Join-Path $testBase 'lock.release'
    $lockText=@'
param([string]$Name,[string]$Ready,[string]$Release)
$m=New-Object System.Threading.Mutex($false,$Name);$held=$false
try{
    $held=$m.WaitOne(3000);if(-not $held){exit 2}
    [System.IO.File]::WriteAllText($Ready,'ready')
    $watch=[System.Diagnostics.Stopwatch]::StartNew()
    while(-not [System.IO.File]::Exists($Release) -and $watch.Elapsed.TotalSeconds -lt 40){Start-Sleep -Milliseconds 100}
}
finally{if($held){$m.ReleaseMutex()};$m.Dispose()}
'@
    Write-BuildFixture $lockHelper $lockText $true
    $lockRootHash=(Get-PsKnTextHash -Text $rMulti.ToUpperInvariant()).Substring(0,16)
    $lockJobId='clone-'+(Get-PsKnTextHash -Text "TW_DEMO_A`nTW_DEMO_B").Substring(0,16).ToLowerInvariant()
    $lockName='Global\MCPSample-CloneSpec-'+$lockRootHash+'-'+$lockJobId
    $lockArgs='-NoProfile -ExecutionPolicy Bypass -File "'+$lockHelper+'" -Name "'+$lockName+'" -Ready "'+$lockReady+'" -Release "'+$lockRelease+'"'
    $lockProcess=Start-Process -FilePath 'powershell.exe' -ArgumentList $lockArgs -WindowStyle Hidden -PassThru
    try{
        for($i=0;$i -lt 100 -and -not [System.IO.File]::Exists($lockReady);$i++){Start-Sleep -Milliseconds 100}
        if(-not [System.IO.File]::Exists($lockReady)){throw 'TEST_LOCK_HELPER_NOT_READY'}
        $sameRoot=Invoke-Build $rMulti 'TW_DEMO_A,TW_DEMO_B' 1 valid -Status
        $otherRoot=Invoke-Build $rOther 'TW_DEMO_A,TW_DEMO_B' 1 valid -Status
        Assert-Build ($sameRoot.Code -eq 'CLONE1-0-03' -and $sameRoot.Exit -eq 3) '獨立進程持鎖時，同 Root 同 Components 仍互斥'
        Assert-Build ($otherRoot.Code -eq 'CLONE1-0-02' -and $otherRoot.Exit -eq 0) '不同 Root 的同 Components 不互相阻擋'
    }
    finally{
        Write-BuildFixture $lockRelease 'release'
        if(-not $lockProcess.WaitForExit(3000)){$lockProcess.Kill()}
        $lockProcess.Dispose()
    }
}
$first=Invoke-Build $rMulti 'tw_demo_b,TW_DEMO_A,TW_DEMO_A' 1
$job=Get-BuildJob $rMulti
$attempts=Get-BuildRecords $job 'attempts';$receipts=Get-BuildRecords $job 'receipts'
Assert-Build ($attempts.Count -eq 1 -and $receipts.Count -eq 0 -and $attempts[0].kind -eq 'RESEARCH') '一個研究 session 不得自行驗收'
Assert-Build ($first.Code -match '^CLONE1-3-02-' -and $first.Output -match '文件：') '預算停下提供文件入口與續跑狀態'
$before=Get-BuildSnapshot $rMulti
$st=Invoke-Build $rMulti 'TW_DEMO_A,TW_DEMO_B' 40 -Status
$after=Get-BuildSnapshot $rMulti
Assert-Build ($before -ceq $after -and $st.Output -match 'session=0') 'Status 無寫入／無派工'
$next=Invoke-Build $rMulti 'TW_DEMO_A TW_DEMO_B' 39
if($next.Code -ne 'CLONE1-7-01'){Write-Host $next.Output}
$attempts=Get-BuildRecords $job 'attempts';$receipts=Get-BuildRecords $job 'receipts'
Assert-Build ($next.Code -eq 'CLONE1-7-01' -and $attempts.Count -eq 40 -and $receipts.Count -eq 20) '多 Component 去重／同 job 續跑：40 sessions、20 accepted topics'
foreach($comp in @('TW_DEMO_A','TW_DEMO_B')){
    $a=@($attempts | Where-Object {$_.component -ceq $comp} | Sort-Object attemptId)
    $r=@($receipts | Where-Object {$_.component -ceq $comp})
    Assert-Build ($a.Count -eq 20 -and $r.Count -eq 10 -and $a[0].topic -eq 'scope' -and $a[0].kind -eq 'RESEARCH' -and $a[1].topic -eq 'scope' -and $a[1].kind -eq 'AUDIT') ($comp+' 各10主題且scope-first獨立覆核')
}
$independent=@($receipts | Where-Object {$_.researchAttempt -ceq $_.reviewAttempt}).Count
Assert-Build ($independent -eq 0) '所有收據都有不同研究／覆核 attempt'
$lastAudit=@($attempts | Where-Object {$_.kind -eq 'AUDIT'} | Sort-Object attemptId)[-1]
$visibleComponents=@{}
foreach($path in @($lastAudit.acceptedPacketPaths)){$priorReceipt=Read-BuildJson $path;$visibleComponents[[string]$priorReceipt.component]=$true}
Assert-Build (@($lastAudit.components).Count -eq 2 -and $visibleComponents.ContainsKey('TW_DEMO_A') -and $visibleComponents.ContainsKey('TW_DEMO_B')) '覆核工單可見整份 Component 集合及跨功能已接受內容'
$outRoot=Join-Path (Join-Path $rMulti 'docs/ps-spec') ([System.IO.Path]::GetFileName($job))
$pointer=Read-BuildJson (Join-Path $outRoot 'current.json')
$oldSpec=[string]$pointer.specPath
Assert-Build ((Read-PsKnText -LiteralPath $oldSpec) -match 'TW_DEMO_A' -and (Read-PsKnText -LiteralPath $oldSpec) -match 'TW_DEMO_B') '產物包含全部 Component'
$before=Get-BuildSnapshot $rMulti
$done=Invoke-Build $rMulti 'TW_DEMO_B,TW_DEMO_A' 4
$again=Get-BuildRecords $job 'attempts'
Assert-Build ($done.Code -eq 'CLONE1-7-01' -and $again.Count -eq 40) '完成後重跑不重派'
Write-BuildFixture $oldSpec ((Read-PsKnText -LiteralPath $oldSpec)+"`n人工修訂必保留`n")
$edited=Read-PsKnText -LiteralPath $oldSpec
$conflict=Invoke-Build $rMulti 'TW_DEMO_A,TW_DEMO_B' 4
Assert-Build ($conflict.Exit -ne 0 -and (Read-PsKnText -LiteralPath $oldSpec) -ceq $edited -and $conflict.Output -match '不覆寫') '人工修改 generated 時拒絕覆寫且內容保留'

# 真正的續頁：第一頁不是缺知識，第二頁完成同一主題，兩頁均需獨立覆核。
$rPaged=New-BuildRoot 'paged'
$paged=Invoke-Build $rPaged 'TW_DEMO_A' 22 paged
if($paged.Code -ne 'CLONE1-7-01'){Write-Host $paged.Output}
$j=Get-BuildJob $rPaged;$pagedReceipts=Get-BuildRecords $j 'receipts';$pagedAttempts=Get-BuildRecords $j 'attempts'
$flowPages=@($pagedReceipts | Where-Object {$_.topic -eq 'flows'} | Sort-Object page)
Assert-Build ($paged.Code -eq 'CLONE1-7-01' -and $pagedReceipts.Count -eq 11 -and $pagedAttempts.Count -eq 22 -and $flowPages.Count -eq 2 -and $flowPages[0].packet.coverage -eq 'PARTIAL' -and $flowPages[1].packet.coverage -eq 'COMPLETE') '純續頁 PARTIAL→COMPLETE 共11頁／22sessions，可達 READY'
$ptr=Read-BuildJson (Join-Path (Join-Path (Join-Path $rPaged 'docs/ps-spec') ([System.IO.Path]::GetFileName($j))) 'current.json')
$pagedSpec=Read-PsKnText -LiteralPath $ptr.specPath;$pagedTrace=Read-PsKnText -LiteralPath $ptr.tracePath;$pagedGate=Read-BuildJson $ptr.gatePath
$specFirst=$pagedSpec.IndexOf('FLOW_PAGE_1',[System.StringComparison]::Ordinal);$specSecond=$pagedSpec.IndexOf('FLOW_PAGE_2',[System.StringComparison]::Ordinal)
$traceFirst=$pagedTrace.IndexOf('TW_DEMO_A/flows/p1/E1',[System.StringComparison]::Ordinal);$traceSecond=$pagedTrace.IndexOf('TW_DEMO_A/flows/p2/E1',[System.StringComparison]::Ordinal)
Assert-Build ($specFirst -ge 0 -and $specSecond -gt $specFirst -and $traceFirst -ge 0 -and $traceSecond -gt $traceFirst -and $pagedTrace -match 'FLOW_SOURCE_PAGE_1' -and $pagedTrace -match 'FLOW_SOURCE_PAGE_2') '多頁正文與trace完整按頁序輸出，重名E1不混頁'
Assert-Build (@($pagedGate.gaps).Count -eq 0 -and $pagedSpec -notmatch '尚未閉合') '純續頁收尾沒有幽靈缺口'
$rCursor=New-BuildRoot 'repeat-cursor'
$cursor=Invoke-Build $rCursor 'TW_DEMO_A' 6 repeat-cursor
$j=Get-BuildJob $rCursor;$cursorReceipts=Get-BuildRecords $j 'receipts'
$cursorFlows=@($cursorReceipts | Where-Object {$_.topic -eq 'flows'})
Assert-Build ($cursor.Code -ne 'CLONE1-7-01' -and $cursor.Output -match 'nextCursor 沒有前進' -and $cursorFlows.Count -eq 1) '重複 cursor 拒收第二頁且不得 READY'
$rLateNa=New-BuildRoot 'late-na'
$lateNa=Invoke-Build $rLateNa 'TW_DEMO_A' 6 late-na
$j=Get-BuildJob $rLateNa;$naReceipts=Get-BuildRecords $j 'receipts'
$naFlowPages=@($naReceipts | Where-Object {$_.topic -eq 'flows'})
Assert-Build ($lateNa.Code -ne 'CLONE1-7-01' -and $naFlowPages.Count -eq 1 -and $naFlowPages[0].page -eq 1) '已有內容的主題不可用第二頁 N/A 撤銷適用性'
$rHidden=New-BuildRoot 'hidden-unknown'
$hidden=Invoke-Build $rHidden 'TW_DEMO_A' 4 hidden-unknown
$j=Get-BuildJob $rHidden;$hiddenReceipts=Get-BuildRecords $j 'receipts'
Assert-Build ($hidden.Code -ne 'CLONE1-7-01' -and $hidden.Output -match 'UNRESOLVED_GAP_REQUIRED' -and @($hiddenReceipts | Where-Object {$_.topic -eq 'flows'}).Count -eq 0) 'UNKNOWN 不得藏在純續頁以後頁 COMPLETE 消債'

# 新來源不是舊收據續簽；Status stale 不寫新 revision。
$rSource=New-BuildRoot 'source'
$null=Invoke-Build $rSource 'TW_DEMO_A' 2
$sourceJob=Get-BuildJob $rSource
$oldReceipts=Get-BuildRecords $sourceJob 'receipts'
$changed=Join-Path $rSource '.opencode/peoplesoft/customization-profile.yaml'
Write-BuildFixture $changed ((Read-PsKnText -LiteralPath $changed)+"`n# synthetic source change`n")
$before=Get-BuildSnapshot $rSource
$stale=Invoke-Build $rSource 'TW_DEMO_A' 4 -Status
Assert-Build ($stale.Code -eq 'CLONE1-4-04' -and (Get-BuildSnapshot $rSource) -ceq $before) 'Status 檢知 stale 但不建立新版本'
$new=Invoke-Build $rSource 'TW_DEMO_A' 1
$revs=@(Get-ChildItem -LiteralPath (Join-Path $sourceJob 'revisions') -File)
$sourceReceipts=Get-BuildRecords $sourceJob 'receipts'
Assert-Build ($revs.Count -eq 2 -and $oldReceipts.Count -eq 1 -and $sourceReceipts.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $sourceJob 'receipts/r0001'))) '來源變更新 revision，保留舊收據而不沿用'

foreach($mode in @('bad-hash','missing-checks','review-fail')){
    $r=New-BuildRoot $mode
    $result=Invoke-Build $r 'TW_DEMO_A' 6 $mode
    $j=Get-BuildJob $r;$rc=Get-BuildRecords $j 'receipts'
    Assert-Build ($result.Code -eq 'CLONE1-4-03' -and $rc.Count -eq 0) ($mode+' 不得進已接受正文')
    if($mode -eq 'bad-hash'){
        $retry=Invoke-Build $r 'TW_DEMO_A' 1 valid -Retry
        $rc=Get-BuildRecords $j 'receipts'
        Assert-Build ($rc.Count -eq 1 -and $retry.Code -match '^CLONE1-3-02-') '顯式 Retry 可以重驗保留候選，不假清舊失敗'
    }
}
$rPartial=New-BuildRoot 'partial'
$partial=Invoke-Build $rPartial 'TW_DEMO_A' 4 partial
$j=Get-BuildJob $rPartial;$rc=Get-BuildRecords $j 'receipts'
$partialCandidates=@(Get-ChildItem -LiteralPath (Join-Path $j 'attempts') -Filter 'candidate.json' -File -Recurse)
Assert-Build ($partial.Code -eq 'CLONE1-4-03' -and $partialCandidates.Count -gt 0 -and (Read-BuildJson $partialCandidates[0].FullName).coverage -eq 'PARTIAL') 'PARTIAL 無 cursor 保留誠實候選但不 READY'
$rNoise=New-BuildRoot 'scope-noise'
$noise=Invoke-Build $rNoise 'TW_DEMO_A' 4 scope-noise
$j=Get-BuildJob $rNoise;$rc=Get-BuildRecords $j 'receipts'
Assert-Build ($noise.Output -match 'SCOPE_REF_EXCLUDED' -and @($rc | Where-Object {$_.topic -eq 'flows'}).Count -eq 0) 'EXCLUDED 雜訊不得污染核心正文'
foreach($mode in @('forge-receipt','mutate-input')){
    $r=New-BuildRoot $mode
    $result=Invoke-Build $r 'TW_DEMO_A' 2 $mode
    $j=Get-BuildJob $r;$rc=Get-BuildRecords $j 'receipts'
    Assert-Build ($result.Code -eq 'CLONE1-4-03' -and $rc.Count -eq 0 -and $result.Output -match '非授權') ($mode+' 圍欄阻擋且不驗收')
    if($mode -eq 'forge-receipt'){$q=Join-Path $r '.ps-runtime/clone-spec/quarantine';Assert-Build ((Test-Path -LiteralPath $q) -and @(Get-ChildItem -LiteralPath $q -File).Count -gt 0) '偽造收據隔離保留現場'}
    else{$inputs=Get-BuildRecords $j 'attempts';Assert-Build ($inputs.Count -eq 2 -and $inputs[0].component -eq 'TW_DEMO_A') '被改工單從圍欄原樣還原'}
}
Write-Host ('build tests: PASS=' + $script:testPass + ' FAIL=' + $script:testFail)
Write-Host ('合成測試現場保留（可供本機排查）：' + $testBase)
if($script:testFail -gt 0){exit 1}
exit 0
