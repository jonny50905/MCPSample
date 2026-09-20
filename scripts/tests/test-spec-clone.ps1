# test-spec-clone.ps1 — 合成資料測試；不查 MCP、不讀企業產物、不呼叫模型。
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repo 'scripts/ps-knowledge-lib.ps1')
. (Join-Path $repo 'scripts/ps-spec-clone-lib.ps1')
$script:failed = 0; $script:passed = 0
function Assert-Clone([bool]$Condition, [string]$Name) {
    if ($Condition) { $script:passed++; Write-Host ('PASS ' + $Name) }
    else { $script:failed++; Write-Host ('FAIL ' + $Name) }
}
function Copy-CloneValue($Value) { return ((ConvertTo-PsKnJson -Value $Value) | ConvertFrom-Json) }
$profile = Get-PsCloneProfile -Root $repo
$component = 'TW_DEMO_A'
function New-ClonePacket([string]$Topic = 'scope', [string]$Component = 'TW_DEMO_A') {
    $def = $profile.topics | Where-Object { $_.id -eq $Topic } | Select-Object -First 1
    $values = [ordered]@{}
    foreach ($field in $def.fields) { $values[$field.key] = ('合成具體值：' + $field.key) }
    $refs = @('S01')
    if ($Topic -eq 'scope') { $values.object=$Component; $values.type='COMPONENT'; $values.inclusion='CORE'; $values.usedBy='使用者直接啟動'; $values.condition='進入此功能'; $values.reason='指定的重建根'; $refs=@() }
    if ($Topic -eq 'acceptance') { $values.scenarioType='POSITIVE' }
    return [ordered]@{
        schemaVersion=1; component=$Component; topic=$Topic; coverage='COMPLETE'; summary='合成資料：已列出本頁已查得的行為。'
        items=@([ordered]@{id='S01';scopeRefs=$refs;values=$values;evidenceIds=@('E1')})
        evidence=@([ordered]@{id='E1';kind='CHUNK';locator='ChunkId 3f2a9c1e-7b4d-4e8a-9c6f-1d2e3a4b5c6d';excerpt='If DEMO_STATUS = "A" Then'})
        gaps=@();nextCursor=''
    }
}
$scope = New-ClonePacket
$scopeItems = @($scope.items)
function Check-Clone($Packet) { return (Test-PsClonePacket -Packet $Packet -Component $Packet.component -Topic $Packet.topic -Profile $profile -ScopeItems $scopeItems) }
Assert-Clone (@($profile.topics).Count -eq 10 -and $profile.topics[0].id -eq 'scope' -and $profile.topics[9].id -eq 'acceptance') '固定十個主題與順序'
foreach ($topic in $profile.topics) { $p=New-ClonePacket $topic.id; $v=Check-Clone $p; Assert-Clone $v.Ok ('合法 ' + $topic.id + ' packet') }
$scopeResult = Test-PsClonePacket -Packet $scope -Component $component -Topic scope -Profile $profile -ScopeItems @()
Assert-Clone ($scopeResult.Ok -and $scopeResult.Items.Count -eq 1) 'scope 首頁自行建立 CORE 根'
$p = Copy-CloneValue $scope; $p.component='TW_DEMO_OTHER'
Assert-Clone (-not (Test-PsClonePacket -Packet $p -Component $component -Topic scope -Profile $profile).Ok) 'Component 不符'
$p = Copy-CloneValue $scope; $p.items[0].values.object='TW_DEMO_OTHER'
Assert-Clone (-not (Test-PsClonePacket -Packet $p -Component $component -Topic scope -Profile $profile).Ok) '禁止冒入另一 CORE Component'
$p = Copy-CloneValue $scope; $p.items[0].values.inclusion='DEPENDENCY'; $p.items[0].values.usedBy='UNKNOWN'
Assert-Clone (-not (Check-Clone $p).Ok) '依賴必有實際使用關係'
$p = Copy-CloneValue $scope; $p.items[0].id='S02'; $p.items[0].values.inclusion='DEPENDENCY'; $p.items[0].values.type='RECORD'; $p.items[0].values.object='PS_DEMO_TBL'
Assert-Clone (Check-Clone $p).Ok 'scope 續頁沿用前頁根'
$p=New-ClonePacket 'ui'; $p.items[0].scopeRefs=@()
Assert-Clone (-not (Check-Clone $p).Ok) '正文必有 scopeRefs'
$p=New-ClonePacket 'ui'; $p.items[0].scopeRefs=@('MISSING')
Assert-Clone (-not (Check-Clone $p).Ok) 'scopeRefs 不得查無'
$p=New-ClonePacket 'ui'; $p.items[0].scopeRefs=@('s01')
Assert-Clone (-not (Check-Clone $p).Ok) 'scopeRefs 大小寫精確'
$excluded=Copy-CloneValue $scope.items[0]; $excluded.values.inclusion='EXCLUDED'
$p=New-ClonePacket 'ui'; $v=Test-PsClonePacket -Packet $p -Component $component -Topic ui -Profile $profile -ScopeItems @($excluded)
Assert-Clone (-not $v.Ok) 'EXCLUDED 不可進正文'
$p=New-ClonePacket 'rules'; $p.items[0].values.expression='UNKNOWN'
Assert-Clone (-not (Check-Clone $p).Ok) 'UNKNOWN 不得 COMPLETE'
$p.items[0].values.expression='UNKNOWN（未取得來源）'
Assert-Clone (-not (Check-Clone $p).Ok) 'UNKNOWN 附理由仍不得 COMPLETE'
$p.coverage='PARTIAL'; $p.gaps=@('條件式待查')
Assert-Clone (Check-Clone $p).Ok '未知資訊誠實留 PARTIAL 草稿'
$p.gaps=@(); $p.nextCursor='next-rule'
Assert-Clone (-not (Check-Clone $p).Ok) '純續頁不得掩蓋 UNKNOWN 知識缺口'
$p=New-ClonePacket 'rules'; $p.items[0].values.expression="STATUS = 'UNKNOWN'"
Assert-Clone (Check-Clone $p).Ok '技術 literal UNKNOWN 不是未知佔位符'
$p=New-ClonePacket 'rules'; $p.items[0].values.expression=''
Assert-Clone (-not (Check-Clone $p).Ok) '必要欄位不可空'
$p=New-ClonePacket 'rules'; $p.items[0].values.expression=@('值')
Assert-Clone (-not (Check-Clone $p).Ok) '必要欄位只准 string'
$p=New-ClonePacket 'rules'; $p.items[0].values.extra='不准擴充'
Assert-Clone (-not (Check-Clone $p).Ok) '固定欄位拒絕未知 key'
$p=New-ClonePacket 'rules'; $p.extra='不准擴充'
Assert-Clone (-not (Check-Clone $p).Ok) 'packet 拒絕未知 key'
$p=New-ClonePacket 'rules'; $p.items=@()
Assert-Clone (-not (Check-Clone $p).Ok) '零條目不得 COMPLETE'
$p=New-ClonePacket 'rules'; $p.gaps=@('仍有缺口')
Assert-Clone (-not (Check-Clone $p).Ok) '有缺口不得 COMPLETE'
$p=New-ClonePacket 'rules'; $p.nextCursor='p2'
Assert-Clone (-not (Check-Clone $p).Ok) '有續頁不得 COMPLETE'
$p.coverage='PARTIAL'
Assert-Clone (Check-Clone $p).Ok 'PARTIAL cursor 可以續頁'
$p.nextCursor=''
Assert-Clone (-not (Check-Clone $p).Ok) 'PARTIAL 無 cursor 須寫缺口理由'
$p=New-ClonePacket 'rules'; $p.items=@(); for($i=1;$i -le 41;$i++){ $it=Copy-CloneValue (New-ClonePacket 'rules').items[0]; $it.id='R'+$i; $p.items+=,$it }
Assert-Clone (-not (Check-Clone $p).Ok) '每頁最多 40 條目'
$p.items=$p.items[0..39]
Assert-Clone (Check-Clone $p).Ok '40 條目邊界可驗'
$p=New-ClonePacket 'rules'; $p.items+=,$p.items[0]
Assert-Clone (-not (Check-Clone $p).Ok) '重複 item ID 拒絕'
$p=New-ClonePacket 'rules'; $p.items[0].id='中文ID'
Assert-Clone (-not (Check-Clone $p).Ok) 'item ID 限 ASCII 穩定碼'
$p=New-ClonePacket 'rules'; $p.items[0].evidenceIds=@()
Assert-Clone (-not (Check-Clone $p).Ok) '每項都要證據'
$p=New-ClonePacket 'rules'; $p.items[0].evidenceIds=@('E2')
Assert-Clone (-not (Check-Clone $p).Ok) '證據 ID 必存在'
$p=New-ClonePacket 'rules'; $p.evidence+=,$p.evidence[0]
Assert-Clone (-not (Check-Clone $p).Ok) '重複 evidence ID 拒絕'
$p=New-ClonePacket 'rules'; $p.evidence[0].excerpt="一`n二`n三`n四`n五`n六"
Assert-Clone (-not (Check-Clone $p).Ok) '引文不得超過五行'
$p.evidence[0].excerpt="一`n二`n三`n四`n五"
Assert-Clone (Check-Clone $p).Ok '五行引文邊界'
$p=New-ClonePacket 'rules'; $p.evidence[0].locator='ChunkId 3f2a9c1e'
Assert-Clone (-not (Check-Clone $p).Ok) '縮寫 ChunkId 拒絕'
$p=New-ClonePacket 'rules'; $p.evidence[0].kind='NN'; $p.evidence[0].locator='docs/ps-research/測試領域/01-TW_DEMO_A.md:L12-L20'
Assert-Clone (Check-Clone $p).Ok 'NN 相對路徑與行號範圍'
foreach($bad in @('https://example.org/file.md:L1-L2','docs/ps-research/../private.md:L1-L2','docs/ps-research/測試領域/01-TW_DEMO_A.md','docs/ps-research/測試領域/01-TW_DEMO_A.md:L20-L12','D:/private.md:L1-L2')) { $p.evidence[0].locator=$bad; Assert-Clone (-not (Check-Clone $p).Ok) ('拒絕 NN locator ' + $bad) }
$p=New-ClonePacket 'rules'; $p.evidence[0].kind='SQL'; $p.evidence[0].locator='SELECT DEMO_STATUS FROM PS_DEMO_TBL WHERE ROWNUM <= 5'
Assert-Clone (Check-Clone $p).Ok 'SQL SELECT FROM'
foreach($bad in @('UPDATE PS_DEMO_TBL SET DEMO_STATUS=''A''','SELECT 1','SELECT * FROM PS_DEMO_TBL; DELETE FROM PS_DEMO_TBL','SELECT * INTO PS_DEMO_B FROM PS_DEMO_TBL','SELECT * FROM PS_DEMO_TBL FOR UPDATE')) { $p.evidence[0].locator=$bad; Assert-Clone (-not (Check-Clone $p).Ok) ('拒絕非唯讀 SQL ' + $bad) }
$p=New-ClonePacket 'states'; $p.coverage='NOT_APPLICABLE'; $p.items=@(); $p.summary='原始碼與流程均為無狀態查詢，因此沒有狀態機。'
Assert-Clone (Check-Clone $p).Ok '有證據與理由的允許 N/A'
$p.evidence=@()
Assert-Clone (-not (Check-Clone $p).Ok) 'N/A 不得缺證據'
foreach($topic in @('scope','ui','data','rules','acceptance')) { $p=New-ClonePacket $topic; $p.coverage='NOT_APPLICABLE'; $p.items=@(); Assert-Clone (-not (Check-Clone $p).Ok) ($topic + ' 不得 N/A') }
$p=New-ClonePacket 'acceptance'; $p.items[0].values.scenarioType='其他'
Assert-Clone (-not (Check-Clone $p).Ok) '驗收類型封閉'
$p=New-ClonePacket 'rules'; $p.items='not-an-array'
Assert-Clone (-not (Check-Clone $p).Ok) 'items 非陣列安全拒絕'
$p=New-ClonePacket 'rules'; $p.items=@($null)
Assert-Clone (-not (Check-Clone $p).Ok) 'null item 安全拒絕'
$v=Test-PsClonePacket -Packet 'bad' -Component $component -Topic rules -Profile $profile
Assert-Clone (-not $v.Ok) '非物件 packet 安全拒絕'

$p=New-ClonePacket 'rules'; $hash=Get-PsKnTextHash -Text (ConvertTo-PsKnJson -Value $p -SortKeys)
$review=[ordered]@{schemaVersion=1;component=$component;topic='rules';inputHash=$hash;verdict='PASS';checkedIds=@('S01');findings=@();summary='已逐項核對來源與範圍，未發現缺失。'}
$v=Test-PsCloneReview -Review $review -Packet $p -InputHash $hash
Assert-Clone ($v.Ok -and $v.Passed) 'review 完整身分／hash／覆蓋通過'
$r=Copy-CloneValue $review; $r.inputHash=('0'*64)
Assert-Clone (-not (Test-PsCloneReview -Review $r -Packet $p -InputHash $hash).Passed) '舊 review hash 拒絕'
$r=Copy-CloneValue $review; $r.topic='ui'
Assert-Clone (-not (Test-PsCloneReview -Review $r -Packet $p -InputHash $hash).Passed) 'review topic 不符'
$r=Copy-CloneValue $review; $r.checkedIds=@()
Assert-Clone (-not (Test-PsCloneReview -Review $r -Packet $p -InputHash $hash).Passed) 'review 漏驗拒絕'
$r=Copy-CloneValue $review; $r.checkedIds=@('S01','S01')
Assert-Clone (-not (Test-PsCloneReview -Review $r -Packet $p -InputHash $hash).Passed) 'review 重複 checked ID 拒絕'
$r=Copy-CloneValue $review; $r.checkedIds=@('FAKE')
Assert-Clone (-not (Test-PsCloneReview -Review $r -Packet $p -InputHash $hash).Passed) 'review 自造 checked ID 拒絕'
$r=Copy-CloneValue $review; $r.findings=@(@{itemId='S01';code='MISSING_DETAIL';detail='少了邊界'})
Assert-Clone (-not (Test-PsCloneReview -Review $r -Packet $p -InputHash $hash).Passed) 'review PASS 仍有 finding 拒絕'
$r.verdict='FAIL'; $v=Test-PsCloneReview -Review $r -Packet $p -InputHash $hash
Assert-Clone ($v.Ok -and -not $v.Passed) '合法 FAIL 不被當 PASS'
$r.findings=@(@{itemId='TOPIC';code='MISSING_BRANCH';detail='整體缺一條流程'})
Assert-Clone (Test-PsCloneReview -Review $r -Packet $p -InputHash $hash).Ok 'packet 層級 finding'
$r=Copy-CloneValue $review; $r.verdict='BLOCKED'
Assert-Clone (-not (Test-PsCloneReview -Review $r -Packet $p -InputHash $hash).Passed) 'BLOCKED 不可通過'
$r.checkedIds=@(); $r.findings=@(@{itemId='TOPIC';code='TOOL_BLOCKED';detail='工具目前不可用，未能逐筆查證'})
$v=Test-PsCloneReview -Review $r -Packet $p -InputHash $hash
Assert-Clone ($v.Ok -and -not $v.Passed) '工具阻斷可零 checkedIds 但不通過'
$r.findings[0].code='MY_CODE'
Assert-Clone (-not (Test-PsCloneReview -Review $r -Packet $p -InputHash $hash).Ok) 'finding code 封閉'
$r.findings=@()
Assert-Clone (-not (Test-PsCloneReview -Review $r -Packet $p -InputHash $hash).Ok) 'FAIL／BLOCKED 必須附原因'

$packets=@($scope,(New-ClonePacket 'rules'))
$p2=New-ClonePacket 'rules'; $p2.items[0].id='R02'; $p2.items[0].values.expression='SECOND_PAGE'; $packets+=,$p2
$s2=New-ClonePacket 'scope' 'TW_DEMO_B'; $packets+=,$s2
$u2=New-ClonePacket 'ui' 'TW_DEMO_B'; $u2.items[0].values.field='DEMO_FIELD_B'; $packets+=,$u2
$spec=ConvertTo-PsCloneSpec -Components @('TW_DEMO_A','TW_DEMO_B') -Packets $packets -Profile $profile -Status DRAFT -Gaps @('人工確認界面差異')
$trace=ConvertTo-PsCloneTrace -Components @('TW_DEMO_A','TW_DEMO_B') -Packets $packets -Profile $profile -Status DRAFT -Gaps @('人工確認界面差異')
Assert-Clone ($spec -match 'SECOND_PAGE' -and $spec -match 'DEMO_FIELD_B') '多 Component 與多頁正文完整保留'
Assert-Clone ($trace -match 'TW_DEMO_A/rules/p1/E1' -and $trace -match 'TW_DEMO_A/rules/p2/E1') '跨頁 E1 有獨立追溯命名空間'
Assert-Clone ($spec -match '未解缺口' -and $spec -match '尚無已驗收資料' -and $spec -match '人工確認界面差異') '缺 topic 與人工缺口可見'
Assert-Clone ($spec -match '不等於企業 E2E' -and $trace -match '不是企業 E2E') '結構／LLM review 與真 E2E 分開'
$again=ConvertTo-PsCloneSpec -Components @('TW_DEMO_A','TW_DEMO_B') -Packets $packets -Profile $profile -Status DRAFT -Gaps @('人工確認界面差異')
Assert-Clone ($spec -ceq $again) '相同輸入 render 位元組確定'
Assert-Clone ((ConvertTo-PsCloneCell "[x]|<script>`n下一行") -eq '&#91;x&#93;&#124;&lt;script&gt;<br>下一行') 'Markdown 格線／HTML／換行轉義'
foreach($file in @('scripts/ps-spec-clone-lib.ps1','scripts/tests/test-spec-clone.ps1')) { $bytes=[System.IO.File]::ReadAllBytes((Join-Path $repo $file)); Assert-Clone ($bytes[0]-eq239 -and $bytes[1]-eq187 -and $bytes[2]-eq191) ($file+' UTF-8 BOM') }
Write-Host ('clone tests: PASS=' + $script:passed + ' FAIL=' + $script:failed)
if ($script:failed -gt 0) { exit 1 }
exit 0
