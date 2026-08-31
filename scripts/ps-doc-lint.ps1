# ps-doc-lint.ps1 — deep-research 文件的確定性格式稽核（第 1 層 lint）
# 用法：.\scripts\ps-doc-lint.ps1 -Domain 轉職
#       .\scripts\ps-doc-lint.ps1 -Domain 轉職 -StrictAudit
#       .\scripts\ps-doc-lint.ps1 -Domain 轉職 -CoverageOnly
# -CoverageOnly＝auto-loop 覆蓋畢業門（tier 1／可用 80 分）專用：只把「缺料類」
# 當違規（缺檔／空檔／缺章節／空殼章節／checklist 對帳／寫入脫軌污染），把
# 「美工類」（證據 id 格式、機器參照、confidence 標註、wiki frontmatter）降為
# 警告。**這不是新增檢查，是把既有檢查分類**——標準沒有變嚴，只是分成兩段收。
# 分類採白名單：只有明確列在 $polishPatterns 的訊息算美工，**其餘一律算缺料**
# （fail-safe：分類漏掉只會讓門更嚴，不會放水）。
# -StrictAudit＝auto-loop 畢業門專用（issue #2）：90-audit.md 的結構性問題
# （缺檔／缺模板章節／缺輪次表頭／記分卡範圍塌縮）由警告升為 FAIL。
# 手動執行不加此開關——維持警告不擋（SOP-2）。wiki 類警告任何模式都不升級
# （跨領域共用層，會讓 A 領域的畢業被 B 領域的斷鏈鎖死）。
# 檢查：checklist 對帳、必要章節、confidence 標註、ChunkId UUID 格式、可疑自編 id
param(
    [Parameter(Mandatory = $true)][string]$Domain,
    [switch]$StrictAudit,
    [switch]$CoverageOnly,
    # 標題正規化（L101／issue #10）：變體章節標題（**粗體**／#層級漂移／
    # 少內部空格／尾冒號）機械改寫成正典「## X」。只修「行內容僅有標題」
    # 且正典缺席的情況；同節多個變體＝有歧義，跳過並警告。冪等。
    [switch]$FixHeadings,
    # 唯一會寫檔的開關（循 ps-fs-doctor -FixBom 前例）：修歸檔裡的未打勾列。
    # agent 被硬規則禁止改寫 checklist-archive*.md，理由是**模型的 write 工具
    # 沒有 append、重寫大檔會撐爆**——那是工具層限制，不是語意禁令；
    # PowerShell 沒有這個限制，所以這件事只有這裡做得到。
    [switch]$FixArchive
)

# 參數消毒（L28）：-Domain 尾部空白/點會觸發 Win32 尾字元正規化不對稱——
# 「目錄」查得到（最後一段的尾空白被正規化剝掉）、其下「檔案」全查無
# （空白變成中間段、按字面查找）→ 完美的假缺檔。貼上指令最容易夾帶。
$rawDomain = $Domain
$Domain = $Domain.Trim().TrimEnd('.', ' ')
if ($Domain -cne $rawDomain) {
    Write-Host "WARN：-Domain 參數頭尾含空白/點，已自動修剪（貼上指令易夾帶，建議手打）" -ForegroundColor Yellow
}
foreach ($ch in $Domain.ToCharArray()) {
    $cp = [int]$ch
    if ($cp -lt 32 -or $cp -eq 127 -or $cp -eq 0x00A0 -or
        ($cp -ge 0x200B -and $cp -le 0x200F) -or $cp -eq 0xFEFF) {
        Write-Error "-Domain 參數含隱形字元（字元碼 $cp）——用鍵盤重新輸入，或跑 ps-fs-doctor 健檢"
        exit 2
    }
}

# 章節實質內容判定（L35）：剝掉 HTML 註解與模板佔位符後是否為空。
# 兩種「假內容」：(1) HTML 註解渲染後不可見——讀者看到的是空章節；
# (2)「同前」類省略語在**只有整檔覆寫**的工具層沒有指涉對象
# （寫入當下前一版已被自己蓋掉），是偷懶省略不是內容。
function Test-SectionHollow {
    param([string]$Body)
    $t = [regex]::Replace($Body, '(?s)<!--.*?-->', '')
    $t = [regex]::Replace($t, '(?m)^\s*[-*]?\s*<[^>]+>\s*$', '')
    $t = $t.Trim()
    if ($t -eq '') { return $true }
    if ($t -match '^[-*]?\s*(同前|同上|如前|如上|略|不變|未變|unchanged|same as before|same as above)\s*[。．.]?$') { return $true }
    return $false
}

# 覆蓋判定（L36／L76／L77）：**驗事實，不驗字面**。要驗的事實是
# 「每個 NN 檔都被這輪稽核驗到了」，不是「它被寫在哪一節、用什麼寫法」。
# 三次誤報都出在這裡：綁章節名（模型自創標題）→ 綁完整檔名（模型寫「01」）
# → 綁記分卡章節（模型把逐檔資料放明細、記分卡只留統計）。
# 所以：**違規判定掃整份報告**；記分卡那一節自己有沒有逐檔列只發警告
# （L23：資料在就不追殺，但講出來）。純命名／版面問題不得擋畢業——
# audit 每輪都會照自己的習慣重寫，擋下去就是無修復管道的活鎖。
function Test-NnMentioned {
    param([string]$Body, [string]$Name, [bool]$AllowPrefix)
    if ([string]::IsNullOrEmpty($Body)) { return 'NONE' }
    $base = [IO.Path]::GetFileNameWithoutExtension($Name)
    if ($Body -match [regex]::Escape($base)) { return 'FULL' }
    if ($AllowPrefix) {
        # 編號代稱須帶錨點——行號、日期（2026-08-01）、chunk id 裡也有兩位數：
        #   (1) 列首／清單項／第一個儲存格開頭：「01…」「- 01…」「| 01…」
        #   (2) 任一儲存格**恰為**該編號：「| 1 | 01 | 12 |」（有流水號欄）
        $p = $Name.Substring(0, 2)
        $patHead = '(?m)^[^\S\r\n]*(?:[-*][^\S\r\n]*|\|[^\S\r\n]*)?(?:\*\*)?' +
            [regex]::Escape($p) + '(?![0-9])'
        $patCell = '\|[^\S\r\n|]*(?:\*\*)?' + [regex]::Escape($p) +
            '(?:\*\*)?[^\S\r\n|]*\|'
        if (($Body -match $patHead) -or ($Body -match $patCell)) { return 'PREFIX' }
    }
    return 'NONE'
}

function Get-ScorecardCoverage {
    param([string]$AuditText, $NnNames)
    $best = @{ Covered = -1; Missing = @($NnNames); Heading = '(無章節)'
        PrefixOnly = @(); OutsideScorecard = @()
    }
    if ([string]::IsNullOrEmpty($AuditText) -or $NnNames.Count -eq 0) { return $best }
    $sections = @()
    $curHead = '(表頭前)'
    $buf = New-Object System.Text.StringBuilder
    foreach ($ln in ($AuditText -split "`r?`n")) {
        if ($ln -match '^##\s') {
            $sections += [pscustomobject]@{ Heading = $curHead; Body = $buf.ToString() }
            $curHead = $ln.Trim()
            $buf = New-Object System.Text.StringBuilder
        }
        else { [void]$buf.AppendLine($ln) }
    }
    $sections += [pscustomobject]@{ Heading = $curHead; Body = $buf.ToString() }
    # 編號代稱只在「該編號唯一對應一個檔」時才准用：NN-X.md 與續篇
    # NN-X-2.md 共用前綴，此時一個「01」證明不了兩個都列到。
    $prefixCount = @{}
    foreach ($n in $NnNames) {
        $p = $n.Substring(0, 2)
        if ($prefixCount.ContainsKey($p)) { $prefixCount[$p]++ } else { $prefixCount[$p] = 1 }
    }
    # 1) 違規判定＝整份報告有沒有提到該檔
    $miss = @()
    $prefixOnly = @()
    foreach ($n in $NnNames) {
        $ap = ($prefixCount[$n.Substring(0, 2)] -eq 1)
        $r = Test-NnMentioned -Body $AuditText -Name $n -AllowPrefix $ap
        if ($r -eq 'NONE') { $miss += $n }
        elseif ($r -eq 'PREFIX') { $prefixOnly += $n }
    }
    # 2) 記分卡那一節自己有沒有逐檔列——只發警告（版面建議，不擋門）
    $scHeading = '(無記分卡章節)'
    $outside = @()
    $cands = @($sections | Where-Object { $_.Heading -match '(記分卡|總覽|檔案清單|scorecard)' })
    if ($cands.Count -gt 0) {
        $bestSec = $null
        $bestN = -1
        foreach ($sec in $cands) {
            $c = 0
            foreach ($n in $NnNames) {
                $ap = ($prefixCount[$n.Substring(0, 2)] -eq 1)
                if ((Test-NnMentioned -Body $sec.Body -Name $n -AllowPrefix $ap) -ne 'NONE') { $c++ }
            }
            if ($c -gt $bestN) { $bestN = $c; $bestSec = $sec }
        }
        if ($null -ne $bestSec) {
            $scHeading = $bestSec.Heading
            foreach ($n in $NnNames) {
                if ($miss -contains $n) { continue }
                $ap = ($prefixCount[$n.Substring(0, 2)] -eq 1)
                if ((Test-NnMentioned -Body $bestSec.Body -Name $n -AllowPrefix $ap) -eq 'NONE') {
                    $outside += $n
                }
            }
        }
    }
    return @{ Covered = ($NnNames.Count - $miss.Count); Missing = @($miss); Heading = $scHeading
        PrefixOnly = @($prefixOnly); OutsideScorecard = @($outside)
    }
}

# 以 script 所在位置反推 repo 根目錄——任何工作目錄都能跑。
# **腳本位置是設定**（L39）：放錯資料夾＝整棵樹反推歪掉，且以前完全無聲
# ——實案：doctor 找得到 overview、lint 說缺檔，差別只在兩者跑的起點不同。
$root = Split-Path $PSScriptRoot -Parent
if ((Split-Path $PSScriptRoot -Leaf) -ne 'scripts') {
    Write-Host "WARN：本腳本不在 <repo>\scripts\ 底下（目前位置：$PSScriptRoot）——repo 根反推為 $root，可能指向錯誤的樹" -ForegroundColor Yellow
}
$researchRoot = Join-Path $root (Join-Path "docs" "ps-research")
if (-not (Test-Path -LiteralPath $researchRoot)) {
    Write-Error "找不到 $researchRoot——腳本應放在 <repo>\scripts\ 底下（目前位置：$PSScriptRoot）"
    exit 2
}
$dir = Join-Path $researchRoot $Domain
$violations = @()
$warnings = @()

if (-not (Test-Path -LiteralPath $dir)) {
    $siblings = @(Get-ChildItem -LiteralPath $researchRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Name })
    Write-Error "目錄不存在：$dir｜該 research 根下現有領域：$($siblings -join '、')"
    exit 2
}

$overviewPath = Join-Path $dir "00-overview.md"
$checklistPath = Join-Path $dir "checklist.md"
if (-not (Test-Path -LiteralPath $overviewPath)) {
    # 缺檔違規必附近似檔名收據（L24「查無必附查法收據」用回 lint 自己身上）：
    # 假缺（檔名污染/雙副檔名）與真缺（SOP-4 還原）給出可分辨的訊息
    $allInDir = @(Get-ChildItem -LiteralPath $dir -Force -File -ErrorAction SilentlyContinue)
    $near = @($allInDir | Where-Object { $_.Name -like "*overview*" })
    # 查無收據必附「查了哪裡、看到什麼」（L38）——只說「缺檔」時，人無法
    # 分辨「真缺」與「掃錯目錄」（雙胞胎資料夾／repo 副本／檔名藏隱形字元）
    $mdCount = @($allInDir | Where-Object { $_.Extension -eq '.md' }).Count
    $scanReceipt = "掃描目錄：$dir｜該目錄 $mdCount 個 .md"
    if ($near.Count -gt 0) {
        $violations += "缺 00-overview.md（但找到近似檔名：$(($near | ForEach-Object { $_.Name }) -join '、')——檔名污染？跑 ps-fs-doctor）｜$scanReceipt"
    }
    elseif ($mdCount -eq 0) {
        $violations += "缺 00-overview.md（且該目錄一個 .md 都沒有——極可能掃錯目錄：雙胞胎資料夾／repo 副本，跑 ps-fs-doctor 查代號 C）｜$scanReceipt"
    }
    else {
        $violations += "缺 00-overview.md（近似檔名掃描也無——真缺檔走 SOP-4 還原；若你看得到該檔，就是掃錯目錄或檔名藏隱形字元，跑 ps-fs-doctor）｜$scanReceipt"
    }
}

# 進度已拆檔：新格式在 checklist.md；舊格式（進度仍在 overview 內）自動相容。
# 對帳不再包在「overview 存在」分支裡（L28：一項缺檔違規不得遮蔽其餘檢查——
# 假缺 overview 曾讓「無遺失」整輪不可證）
$checklistOnly = $null
if (Test-Path -LiteralPath $checklistPath) {
    $checklistOnly = Get-Content -LiteralPath $checklistPath -Raw -Encoding UTF8
    if ($null -eq $checklistOnly) { $checklistOnly = "" }   # 空檔防護：0 byte 也要進對帳
}
elseif (Test-Path -LiteralPath $overviewPath) {
    $checklistOnly = Get-Content -LiteralPath $overviewPath -Raw -Encoding UTF8
    if ($null -eq $checklistOnly) { $checklistOnly = "" }
}
$clRound = -1
if ($null -ne $checklistOnly) {
    foreach ($m in [regex]::Matches($checklistOnly, '稽核輪次[：:]\s*([0-9]+)')) {
        $clRound = [int]$m.Groups[1].Value
    }
    # 重複表頭＝「新骨架疊在舊檔上」的腐蝕指紋（實案：56 輪吃節後檔內
    # 出現兩行稽核輪次）——輪次解析取最後一筆，重複時可能抓到錯的行
    $roundLines = @([regex]::Matches($checklistOnly, '(?m)^.*稽核輪次[：:].*$'))
    if ($roundLines.Count -gt 1) {
        $violations += "checklist.md：出現 $($roundLines.Count) 行「稽核輪次」——腐蝕指紋（新表頭疊上舊檔）；人工保留正確那一行並檢查節標題／列有無重複"
    }
}
# 00-overview 是凍結快照（L2）——歷多輪稽核後提醒讀者別當現況讀（L30）。
# L54：落後程度要從**上次換版的輪次**起算，不是從 0 起算——原本只看
# $clRound >= 3，等於做完 SOP-15 換版也永遠消不掉，是不可滿足的警告
# （L48：滅不掉的警告只會訓練人忽略警告）。標記讀不到時訊息要**明講
# 要寫哪一串字**，否則使用者標了卻不生效，只會更困惑。
if (Test-Path -LiteralPath $overviewPath) {
    $ovText = Get-Content -LiteralPath $overviewPath -Raw -Encoding UTF8
    if ($null -eq $ovText) { $ovText = "" }
    $canonical = '第 <N> 版（於稽核輪次 <R> 換版）'
    $ovRound = -1
    # 容忍全形／半形括號、有無「於」、冒號與空白差異：只要「稽核輪次<數字>…換版」
    $mv = [regex]::Match($ovText, '稽核輪次\s*[：:]?\s*([0-9]+)\s*[^0-9]{0,6}?換版')
    if ($mv.Success) { $ovRound = [int]$mv.Groups[1].Value }
    $hasVerMark = [regex]::IsMatch($ovText, '第\s*[0-9]+\s*版')
    if ($ovRound -ge 0) {
        $behind = $clRound - $ovRound
        if ($behind -ge 3) {
            $warnings += "00-overview.md：上次換版在稽核輪次 $ovRound，之後又歷 $behind 輪——導航頁可能再度失真，考慮再走一次 SOP-15 換版"
        }
    }
    elseif ($hasVerMark) {
        $warnings += "00-overview.md：偵測到版次標記但讀不到換版輪次——請把整串寫成「$canonical」（R＝換版當下的稽核輪次），否則落後程度無法機械判定"
    }
    elseif ($clRound -ge 3) {
        $warnings += "00-overview.md：凍結快照已歷 $clRound 輪稽核且無換版標記——閱讀請以 checklist／NN 檔／wiki 為準；要刷新走 SOP-15 換版，換版後在檔頭引言區寫「$canonical」本提醒才會消"
    }
}
if (Test-Path -LiteralPath $checklistPath) {
    # checklist 模板節標題必須存在——標題整個消失＝破壞性覆寫指紋
    # （row 清空可以是合法歸檔後狀態，節標題消失不是）
    $clHead = if ($null -eq $checklistOnly) { "" } else { $checklistOnly }
    foreach ($sec in @('## 調查進度', '## Gaps 彙整')) {
        if ($clHead -notmatch [regex]::Escape($sec)) {
            $violations += "checklist.md：缺節標題「$sec」（破壞性覆寫指紋——row 清空可為歸檔後合法狀態，節標題消失不是）"
        }
    }
    # Gaps 彙整實質空白（L35）：深查未回填的訊號。「真的沒有 gaps」是合法
    # 狀態但要明寫「（無）」——留註解＝渲染後看起來是空章節，人讀不到差別。
    # （調查進度不檢查：全勾歸檔後本來就該是空的）
    $gIdx = $clHead.IndexOf('## Gaps 彙整')
    if ($gIdx -ge 0) {
        $gAfter = $clHead.Substring($gIdx)
        $gNext = $gAfter.IndexOf("`n## ")
        $gBody = if ($gNext -ge 0) { $gAfter.Substring(0, $gNext) } else { $gAfter }
        $gHeadEnd = $gBody.IndexOf("`n")
        $gBody = if ($gHeadEnd -ge 0) { $gBody.Substring($gHeadEnd) } else { '' }
        if (Test-SectionHollow $gBody) {
            $warnings += "checklist.md：Gaps 彙整實質空白（僅註解／佔位符／「同前」——深查未回填；真無 gaps 請明寫「（無）」）"
        }
    }
}
if ($null -ne $checklistOnly) {
    $checklistSrc = $checklistOnly
    # 已打勾項會歸檔到 checklist-archive*.md（每輪一個分片檔）——對帳時全部合併看；
    # archive 只准收已打勾項——未勾項被搬走＝進度隱形消失（L28）
    $archiveFiles = @(Get-ChildItem -LiteralPath $dir -Filter "checklist-archive*.md" -File -ErrorAction SilentlyContinue)
    # 稽核流程標籤（L73）：任務 A／B／C 的委派切分、批次編號是 auditor 自己的
    # 流程紀錄，寫進 checklist＝製造永遠做不完的假項目。逐檔報（L74）。
    # L96 修正：D 項來源常寫「任務C 反查」——帶 A/U/D 工單編號開頭的列
    # 是合法工單，**永遠不是流程標籤**（否則合法 D 列被判「整列刪除」）
    # lookahead 內自帶 \s*——外層 \s* 回溯到任何位置，lookahead 都能吃掉
    # 剩餘空白再驗編號（否則回退零格即閃過否定斷言，D 列照樣被誤判）
    # (?i)＋task 變體（L97）：模型會用英文寫流程標籤（task C batch 1）——
    # 字樣判定必須雙語＋大小寫不敏感，否則換個語言就逃逸
    $procLabelPattern = '(?mi)^\s*-\s*\[[ x]\]\s*(?!\s*[AUD]\d+-\d+)(?=.*(?:(?:任務|task)\s*[ABC]|批次\s*\d+\s*[/／]\s*\d+))(.+?)\s*$'
    # 活頁的列文字（去掉勾選框——勾選狀態本來就會變，比對只看內容）
    $clLiveRows = @{}
    foreach ($m in [regex]::Matches($checklistOnly, '(?m)^\s*-\s*\[[ x]\]\s*(.+?)\s*$')) {
        $clLiveRows[$m.Groups[1].Value] = $true
    }
    $dupRows = @()
    foreach ($af in $archiveFiles) {
        $afText = Get-Content $af.FullName -Raw -Encoding UTF8
        if ($null -eq $afText) { $afText = "" }
        $untickedInArchive = @([regex]::Matches($afText, '(?m)^\s*-\s*\[ \]')).Count
        if ($untickedInArchive -gt 0) {
            $violations += "$($af.Name)：含 $untickedInArchive 個未打勾項——歸檔只准搬已勾項（未勾項被搬走＝調查進度隱形消失）。修法：真調查項搬回 checklist.md、稽核流程標籤整列刪除——**本項 loop 修不掉，需人工**"
        }
        # 歸檔是「搬移」不是「複製」（L73）：兩邊都留＝下輪重複計算、兩個檔一起長大
        foreach ($m in [regex]::Matches($afText, '(?m)^\s*-\s*\[[ x]\]\s*(.+?)\s*$')) {
            if ($clLiveRows.ContainsKey($m.Groups[1].Value)) {
                $dupRows += ("{0}｜{1}" -f $af.Name, $m.Groups[1].Value)
            }
        }
        # 流程標籤逐檔數（L74）：合併報一個數字，人不知道該開哪個檔改
        $afProc = @([regex]::Matches($afText, $procLabelPattern))
        if ($afProc.Count -gt 0) {
            $procSample = (@($afProc | Select-Object -First 2 | ForEach-Object { $_.Groups[1].Value }) -join '；')
            $violations += "$($af.Name)：含 $($afProc.Count) 列稽核流程標籤（如「$procSample」）——那是 auditor 的委派切分不是調查項，**整列刪除**（不要搬回 checklist，那會變成永遠做不完的假項目）"
        }
        $checklistSrc += "`n" + $afText
    }
    if ($dupRows.Count -gt 0) {
        $dupSample = (@($dupRows | Select-Object -First 3) -join '；')
        $dupMore = ""
        if ($dupRows.Count -gt 3) { $dupMore = "…等 $($dupRows.Count) 列" }
        $violations += "checklist.md 與歸檔重複 $($dupRows.Count) 列——歸檔是搬移不是複製，已寫進 archive 的列必須從 checklist.md 移除：$dupSample$dupMore"
    }
    # 活頁的流程標籤（歸檔那份在上面的迴圈裡逐檔報）
    $clProc = @([regex]::Matches($checklistOnly, $procLabelPattern))
    if ($clProc.Count -gt 0) {
        $clProcSample = (@($clProc | Select-Object -First 2 | ForEach-Object { $_.Groups[1].Value }) -join '；')
        $violations += "checklist.md：含 $($clProc.Count) 列稽核流程標籤（如「$clProcSample」）——那是 auditor 的委派切分不是調查項，**整列刪除**；回灌只准寫「A<輪次>-<序號> 補查 <NN-檔名>：FAIL x／DISPUTED y／UNVERIFIABLE z（稽核）」"
    }

    # D 項重複發現守衛（L98）：未勾 D 列的目標物件已有 NN 檔＝重複發現，
    # 放行會生出第二份同物件檔（實案：21~26 與 27~32 成對重複——D 重複列
    # ＋無「已存在」出口＋「取下一個未用編號」三者疊加）。自動類：
    # research 依 D 項規則打勾附註（已存在），不重建檔。
    foreach ($m in [regex]::Matches($checklistOnly, '(?m)^\s*-\s*\[ \]\s*[Dd]\d+-\d+[^\r\n]*?新發現\s+([^\s：:（(]+)')) {
        $obj = $m.Groups[1].Value
        $objPat = '(?i)^\d\d-' + [regex]::Escape($obj) + '(-\d+)?\.md$'
        $exist = @(Get-ChildItem -LiteralPath $dir -Filter "*.md" |
                Where-Object { $_.Name -match $objPat })
        if ($exist.Count -gt 0) {
            $violations += ("checklist.md：未勾 D 項目標「" + $obj + "」已有 NN 檔（" + $exist[0].Name + "）——重複發現，依 D 項規則打勾附註（已存在），不得重建檔")
        }
    }
    # 同物件多檔守衛（L98）：NN 檔去編號後同物件、編號卻不同＝重複建檔
    # ——知識分裂成兩份，稽核與提煉都會重工。續篇（同編號 -2）不算。
    # 擇優合併只有人做得了（比完整度與證據數）→ MANUAL_ONLY。
    $objSeen = @{}
    Get-ChildItem -LiteralPath $dir -Filter "*.md" |
        Where-Object { $_.Name -match '^\d\d-' -and $_.Name -notmatch '^(00|90)-' } |
        ForEach-Object {
            $mBase = [regex]::Match($_.Name, '^(\d\d)-(.+?)(-\d+)?\.md$')
            if (-not $mBase.Success) { return }
            $key = $mBase.Groups[2].Value.ToLowerInvariant()
            $num = $mBase.Groups[1].Value
            if (-not $objSeen.ContainsKey($key)) { $objSeen[$key] = @{} }
            $objSeen[$key][$num] = $_.Name
        }
    foreach ($k in $objSeen.Keys) {
        if (@($objSeen[$k].Keys).Count -gt 1) {
            $names = (@($objSeen[$k].Values | Sort-Object) -join '、')
            $violations += ("同物件重複建檔：" + $names + "——人工擇優（比八節完整度與證據數）留一份、刪另一份並同步 checklist 相關列——**本項 loop 修不掉，需人工**")
        }
    }

    # 1) checklist 對帳：打勾項的目標檔必須存在；NN 檔必須被 checklist 列到
    $listed = @{}
    foreach ($m in [regex]::Matches($checklistSrc, '- \[(?<tick>[ x])\]\s+\S+.*?→\s*(?<file>\S+\.md)')) {
        $f = $m.Groups['file'].Value
        $listed[$f] = $true
        if ($m.Groups['tick'].Value -eq 'x' -and -not (Test-Path -LiteralPath (Join-Path $dir $f))) {
            $violations += "checklist 已打勾但檔案不存在：$f"
        }
    }
    Get-ChildItem -LiteralPath $dir -Filter "*.md" |
        Where-Object { $_.Name -match '^\d\d-' -and $_.Name -notmatch '^(00|90)-' } |
        ForEach-Object {
            # 「列到」的事實＝檔名在 checklist＋歸檔任何一行出現——不綁列格式
            # （腐蝕/重寫會讓 → 箭頭漂掉，格式正規表示式抓不到＝假陽性）
            if ($checklistSrc.IndexOf($_.Name, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                $violations += "檔案未被 checklist（含歸檔）任何一行提及：$($_.Name)"
            }
        }
}

# 功能地圖覆蓋 diff（L31）：後續輪發現的「新大陸」會進 checklist→NN→wiki，
# 但凍結的 overview 功能地圖不會自動入圖；歸檔後 checklist 活頁也看不到。
# 機械 diff 補可見性（零新寫入路徑）——這份清單同時是 SOP-15 換版的併入清單。
if ((Test-Path -LiteralPath $overviewPath) -and $null -ne $checklistOnly) {
    $ovText = Get-Content -LiteralPath $overviewPath -Raw -Encoding UTF8
    if ($null -eq $ovText) { $ovText = "" }
    $unmapped = @()
    foreach ($m in [regex]::Matches($checklistSrc, '- \[[ x]\]\s+\S+\s+[^`\r\n]*`(?<obj>[^`\r\n]+)`[^\r\n]*?→\s*\S+\.md')) {
        $obj = $m.Groups['obj'].Value.Trim()
        if ($obj -ne '' -and $ovText.IndexOf($obj) -lt 0) { $unmapped += $obj }
    }
    $unmapped = @($unmapped | Sort-Object -Unique)
    if ($unmapped.Count -gt 0) {
        $warnings += "00-overview.md：功能地圖缺 $($unmapped.Count) 個後續發現的項目（$($unmapped -join '、')）——新發現不會自動入凍結快照，SOP-15 換版時依此清單併入"
    }
}

# 2) 每個 NN 檔的內容檢查
# 必要章節（L94，管理者兩度校正後定案＝存量實證的八節，模板順序）：
# 門檻對齊「存量 NN 檔實際整齊具備」的集合，不對齊先驗推理——
# 畫面與欄位（批次也有 Run Control 頁）與執行方式（線上／批次擇一填）
# 皆普適，01~15 全數具備。唯一不入列：## 權限——全存量缺席，成因是
# 成本（要 oracleMCP 專查）不是不適用；要補＝開明確回灌戰役，
# 不靜默翻門檻（翻了＝15 檔瞬間全違規）。
$requiredSections = @('## 相關物件', '## 功能定位', '## 畫面與欄位', '## 行為邏輯', '## 資料流', '## 執行方式', '## 未解事項', '## Evidence 附錄')
# 章節錨定（L101／issue #10 P1）：行首（容忍 ≤3 前導空白）＋字面標題——
# 內文/引文提到「## X」不再誤判為章節存在；「### X」也不再因 substring
# 巧合通過（### 的第三個 # 對不上字面「## 」後的空格）。
function Get-SectionAnchor {
    param([string]$Sec)
    return '(?m)^[ \t]{0,3}' + [regex]::Escape($Sec)
}
# 標題變體樣式（L101）：整行只有標題字樣（粗體/1~6 個 #/少內部空格/
# 尾冒號/（gaps）尾註都容忍）才算變體——內文句子提到章節名不會誤中。
$sectionLoose = @{
    '## 相關物件'      = '相關物件'
    '## 功能定位'      = '功能定位'
    '## 畫面與欄位'    = '畫面與欄位'
    '## 行為邏輯'      = '行為邏輯'
    '## 資料流'        = '資料流'
    '## 執行方式'      = '執行方式'
    '## 未解事項'      = '未解事項'
    '## Evidence 附錄' = 'Evidence[ \t]*附錄'
}
function Get-VariantLinePattern {
    param([string]$Sec)
    return '^[ \t]{0,3}(?:#{1,6}[ \t]*)?(?:\*\*)?[ \t]*' + $sectionLoose[$Sec] +
        '[ \t]*(?:（gaps）|\(gaps\))?[ \t]*(?:\*\*)?[ \t]*[:：]?[ \t]*$'
}
$uuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
$nnNames = @()
$truncatedIds = @()
$missingIds = @()   # 檔案行號型缺 chunk id——與縮寫 id 同進手術單（修法同形）
$pendingSqlRows = @()   # 明寫「待人工SQL」的列＝合法待辦出口，不算違規但要點名
$misplacedRefRows = @()  # 同列有證據、但機器參照欄放的是標籤（欄位錯放，非缺證據）
$nnText = @{}            # 檔名 → 內容（回灌工單要查「新 id 是否已套用」）
$bogusIds = @()          # 非 UUID／自編樣式的 id——不可信，須重新取證或降級移除
$failedQueryRows = @()   # 以失敗查詢當機器參照的列（SQL 型，改表名重查）
$jsonLeaks = @()         # subagent 契約 JSON 原樣洩漏（缺料類：內容可能被截斷）
$relinkOrders = @()      # [回灌]：90-audit.md 明細「處置」欄帶的機械修復指令
$rawAppendix = @()       # [附錄]（L103）：Evidence 附錄是裸 ChunkId 清單、不是模板
                         # 表格——節內逐列檢查全掛在「| 開頭的表格列」上，一列表格
                         # 都沒有＝零檢查零違規（實案：chunks GUID1,GUID2,… 整批放行）
$sectionGapByFile = @{}  # [章節]（L93）：檔名 → 缺的必要章節清單——缺章節曾是
                         # 「有偵測、無執行者」的死角（16~20 實案：lint 每輪報、
                         # 工單不出、無 session 被告知，永遠不癒）

# ── -FixHeadings（L101／issue #10）：變體標題確定性正規化 ─────────────
# LLM 寫錯結構語法 → 確定性層抓到 → **確定性層修**，不再回頭叫 LLM 修
# 語法（實案：**Evidence 附錄** 粗體標題 ×6，手術 session 看到「節明明在」
# 無所適從，61→61 卡死隊頭）。在掃描前執行：修完才掃，輸出即修復後現況。
if ($FixHeadings) {
    Write-Host "=== -FixHeadings：變體章節標題正規化 ===" -ForegroundColor Cyan
    $fhCount = 0
    Get-ChildItem -LiteralPath $dir -Filter "*.md" |
        Where-Object { $_.Name -match '^\d\d-' -and $_.Name -notmatch '^(00|90)-' } |
        ForEach-Object {
            $fhBytes = [System.IO.File]::ReadAllBytes($_.FullName)
            if ($fhBytes.Length -eq 0) { return }
            $fhBom = ($fhBytes.Length -ge 3 -and $fhBytes[0] -eq 0xEF -and $fhBytes[1] -eq 0xBB -and $fhBytes[2] -eq 0xBF)
            $fhText = [System.Text.Encoding]::UTF8.GetString($fhBytes)
            if ($fhText.Length -gt 0 -and [int]$fhText[0] -eq 0xFEFF) { $fhText = $fhText.Substring(1) }
            $fhLines = @($fhText -split "`r?`n")
            $fhChanged = $false
            foreach ($sec in $requiredSections) {
                if ($fhText -match (Get-SectionAnchor $sec)) { continue }   # 正典已在＝不動
                $vp = Get-VariantLinePattern $sec
                $hits = @()
                for ($li = 0; $li -lt $fhLines.Count; $li++) {
                    if ($fhLines[$li] -match $vp) { $hits += $li }
                }
                if ($hits.Count -eq 1) {
                    Write-Host ("  [標題正規化] " + $_.Name + "：「" + $fhLines[$hits[0]].Trim() + "」 → 「" + $sec + "」") -ForegroundColor Yellow
                    $fhLines[$hits[0]] = $sec
                    $fhChanged = $true
                    $fhCount++
                }
                elseif ($hits.Count -gt 1) {
                    Write-Host ("  [跳過] " + $_.Name + "：「" + $sec + "」有 " + $hits.Count + " 個變體候選——有歧義，留人工") -ForegroundColor DarkYellow
                }
            }
            if ($fhChanged) {
                [System.IO.File]::WriteAllText($_.FullName, ($fhLines -join "`r`n"),
                    (New-Object System.Text.UTF8Encoding($fhBom)))
            }
        }
    Write-Host "=== 正規化結束：修正 $fhCount 個標題；以下為修復後現況掃描 ===" -ForegroundColor Cyan
    Write-Host ""
}

Get-ChildItem -LiteralPath $dir -Filter "*.md" |
    Where-Object { $_.Name -match '^\d\d-' -and $_.Name -notmatch '^(00|90)-' } |
    ForEach-Object {
        $name = $_.Name
        $nnNames += $name
        # 檔名衛生：雙重編號（12-05-…）＝命名慣例侵蝕，會讓記分卡編號代稱
        # 的前綴比對變模糊。改名只能人工（改檔名＋checklist 該列），故僅警告。
        if ($name -match '^\d\d-\d\d-') {
            $warnings += "${name}：檔名雙重編號——規範是 <兩位數>-<物件或功能名>.md；擇批次空檔改名並同步 checklist 該列（人工）"
        }
        $text = Get-Content $_.FullName -Raw -Encoding UTF8
        $nnText[$name] = $text
        # 空檔防護：0 byte 檔 Get-Content -Raw 回 null，[regex]::Matches 會丟例外
        # 中斷整條掃描 pipeline（其餘檔案被靜默跳過）——強殺半寫正是這個樣子
        if ([string]::IsNullOrEmpty($text)) {
            $violations += "${name}：空檔（0 byte／無內容）——疑似寫入中斷，無法檢查"
            return
        }

        $secMissing = @()
        foreach ($sec in $requiredSections) {
            if ($text -notmatch (Get-SectionAnchor $sec)) {
                $violations += "${name}：缺章節「$sec」"
                $secMissing += $sec
            }
        }
        if ($secMissing.Count -gt 0) { $sectionGapByFile[$name] = $secMissing }

        if ($text -notmatch 'CONFIRMED|INFERRED|DYNAMIC_RUNTIME') {
            $violations += "${name}：行為邏輯無任何 confidence 標註"
        }

        # 章節空心檢查（L33）：「缺章節」只驗標題存在——空殼檔（有標題
        # 無內容）會安靜通過；行為邏輯還有 confidence 代理間接抓到，
        # 資料流完全漏網。實案：劣化 session 寫出雙空節的空殼檔。
        foreach ($sec in @('## 行為邏輯', '## 資料流')) {
            $secM = [regex]::Match($text, (Get-SectionAnchor $sec))
            $secIdx = if ($secM.Success) { $secM.Index } else { -1 }
            if ($secIdx -ge 0) {
                $after = $text.Substring($secIdx + $sec.Length)
                $nextIdx = $after.IndexOf("`n## ")
                $body = if ($nextIdx -ge 0) { $after.Substring(0, $nextIdx) } else { $after }
                if (Test-SectionHollow $body) {
                    $violations += "${name}：章節「$sec」空白（有標題無實質內容——空殼／僅註解／「同前」類省略語；git 考古或開重查工單）"
                }
            }
        }

        # ChunkId 必須是 UUID（非 UUID = 捏造）
        foreach ($m in [regex]::Matches($text, 'ChunkId\s*`?(?<id>[^`\s|]+)`?')) {
            $id = $m.Groups['id'].Value
            if ($id -notmatch '^[0-9A-Za-z]') {
                # 標點開頭＝「ChunkId」被當普通名詞寫在散文裡，非 id 引用——略過
            }
            elseif ($id -notmatch $uuidPattern -and $id -ne '<uuid>') {
                if ($id -match '^[0-9a-fA-F]{8}$') {
                    $violations += "${name}：ChunkId 遭縮寫為 8 碼（須完整 36 字元 UUID）：$id"
                    $truncatedIds += [pscustomobject]@{ File = $name; Id = $id }
                }
                else {
                    $violations += "${name}：ChunkId 非 UUID 格式（疑似捏造）：$id"
                    # L80：原本只記違規、不開工單＝有門檻沒出口（tier 2 的 lint
                    # 全綠條件過不了，而沒有任何管道會去修它）
                    $bogusIds += [pscustomobject]@{ File = $name; Id = $id }
                }
            }
        }

        # 已知的自編 id 樣式（歷史失敗模式）
        foreach ($m in [regex]::Matches($text, '\b(SQL-[A-Z]+-\d+|CHK-[A-Z]+-\d+)\b')) {
            $violations += "${name}：出現自編 id 樣式：$($m.Value)"
            $bogusIds += [pscustomobject]@{ File = $name; Id = $m.Value }
        }

        # 表格列欄位數不一致（L41）：寫入中斷的指紋——最後一列少了欄位。
        # 只在連續表格區塊內比對，警告不擋（跳脫的 | 可能造成偽陽）
        $tblLines = $text -split "`n"
        $blockStart = -1
        $blockPipes = -1
        for ($li = 0; $li -lt $tblLines.Count; $li++) {
            $isRow = $tblLines[$li] -match '^\s*\|' -and $tblLines[$li] -notmatch '^\s*\|[\s:|-]+\|?\s*$'
            if ($isRow) {
                $pipes = ([regex]::Matches($tblLines[$li], '\|')).Count
                if ($blockStart -lt 0) { $blockStart = $li; $blockPipes = $pipes }
                elseif ($pipes -ne $blockPipes) {
                    $warnings += "${name}:$($li + 1)：表格列欄位數與表頭不一致（$pipes vs $blockPipes 個分隔符——疑似寫入中斷）"
                }
            }
            elseif ($tblLines[$li].Trim() -eq '') { $blockStart = -1; $blockPipes = -1 }
        }

        # 廣域截斷偵測：不限「ChunkId」前綴——任何位置的獨立 8 碼 hex
        # （含至少一個字母、且非完整 UUID 的一部分）都視為縮寫嫌疑
        foreach ($m in [regex]::Matches($text, '(?<![0-9a-fA-F-])[0-9a-fA-F]{8}(?![0-9a-fA-F-])')) {
            $v = $m.Value
            if ($v -match '[a-fA-F]') {
                $violations += "${name}：疑似縮寫 chunk id（8 碼 hex，廣域偵測）：$v"
                $truncatedIds += [pscustomobject]@{ File = $name; Id = $v }
            }
        }

        # Evidence 義務：檔案行號型（xxx:12-24 樣式）的表格列必附
        # chunk id（UUID）或標明 SQL——兩者皆無＝MISSING_CHUNK_ID
        $evM = [regex]::Match($text, (Get-SectionAnchor '## Evidence 附錄'))
        $evIdx = if ($evM.Success) { $evM.Index } else { -1 }
        if ($evIdx -ge 0) {
            $evText = $text.Substring($evIdx)
            # 絕對行號（L41）：讓人能直接跳到該列人工確認，不必自己搜
            $evStartLine = @($text.Substring(0, $evIdx) -split "`n").Count
            # 章節存在但「內容空白」也是違規（有標題沒證據＝沒證據）。
            # L55：判定要看**可重跑的東西**，不是看有沒有出現「SQL」三個字母
            # ——舊版用 \bSQL\b 當豁免，於是整份附錄只要寫著「OracleMCP SQL」
            # 就算有證據。合格只有三種：完整 36 字元 UUID／真的 SELECT／
            # 待人工SQL（合法待辦出口）。
            $fullUuid = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
            $realSelect = '(?i)\bSELECT\b[\s\S]{0,400}?\bFROM\b'
            $pendingMark = '待人工SQL'
            if ($evText -notmatch $fullUuid -and $evText -notmatch $realSelect -and
                $evText -notmatch $pendingMark) {
                $violations += "${name}：Evidence 附錄空白（有章節標題但無任何 chunk id／SQL 證據）"
            }
            # 附錄形狀（L103）：裸 ChunkId 傾倒偵測。下方逐列檢查只看「| 開頭」
            # 的表格列——附錄若是 chunks GUID1,GUID2,… 這種清單，一列表格都沒有
            # ＝零檢查零違規，而那不是證據是遺物：無位置無說明，稽核解不了引用。
            # 判定（高置信）：節內有 UUID 卻無任何表格資料列，或存在表格外
            # 單行 ≥3 個 UUID 的傾倒列。節界＝下一個 ## 標題（附錄非末節時不越界）。
            $evNextIdx = $evText.IndexOf("`n## ")
            $evBody = if ($evNextIdx -ge 0) { $evText.Substring(0, $evNextIdx) } else { $evText }
            $evRealRows = 0
            $bareUuidN = 0
            $dumpLine = $false
            foreach ($evBLine in ($evBody -split "`n")) {
                if ($evBLine -match '^\s*\|') {
                    if ($evBLine -notmatch '^\s*\|[\s:|-]+\|?\s*$' -and
                        $evBLine -notmatch '機器參照' -and
                        $evBLine -notmatch '^\s*\|\s*(#|編號)\s*\|') { $evRealRows++ }
                }
                else {
                    $bareN = ([regex]::Matches($evBLine, $fullUuid)).Count
                    $bareUuidN += $bareN
                    if ($bareN -ge 3) { $dumpLine = $true }
                }
            }
            if (($evRealRows -eq 0 -and $bareUuidN -gt 0) -or $dumpLine) {
                $violations += "${name}：Evidence 附錄非模板表格（表格外裸 ChunkId $bareUuidN 筆）——無位置／說明，稽核不可解引用；依模板四欄表格重建"
                $rawAppendix += $name
            }
            # 檔案行號樣式（L37 收緊）：冒號前必須是**含字母的檔名 token**——
            # 舊規則「任何 冒號+數字」會把時間（23:00）、比例（1:3）當行號，
            # 派給模型「去找不存在的 chunk」的無解工單（實案：排程 SQL 證據）。
            # 豁免同時認 SELECT——SQL 型證據（查 DB 的 metadata）本就免 chunk id。
            $fileLinePattern = '[A-Za-z0-9_./\\-]*[A-Za-z][A-Za-z0-9_./\\-]*[:：][0-9]+(?:-[0-9]+)?'
            $evLineNo = $evStartLine - 1
            foreach ($line in ($evText -split "`n")) {
                $evLineNo++
                # 失敗查詢當證據（L42）：機器參照寫「schema 不存在／查無／ORA-」
                # 之類＝該證據**不可重現**，稽核重跑必然失敗。只在無 chunk id 的
                # 列上判（有 id 的列講「不存在」多半是在描述內容，不是查詢失敗）
                if ($line -match '^\|' -and $line -notmatch '^\|[\s:|-]+$' -and
                    $line -notmatch '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-' -and
                    $line -match '(schema\s*不存在|table\s+not\s+found|不存在該表|查無此表|ORA-\d|查詢失敗)') {
                    $violations += "${name}:${evLineNo}：以**失敗查詢**當機器參照（證據必須可重現）——多半是表名寫錯（PeopleTools 表禁自行加 PS_ 前綴，見 cookbook 規則 8a），改用正確表名重查後貼「SQL：<SELECT>」＋keyRows"
                    $failedQueryRows += "${name}:${evLineNo}"
                }
                # L55：改成**正面表列**——每一列證據都必須自己帶得出可重跑的東西。
                # 舊版是反面表列（「長得像 檔名:行號 且沒有 SQL 字樣」才判違規），
                # 於是兩類列完全逃過檢查：
                #   (a) 機器參照只寫「PeopleCode chunk」——沒有冒號數字，
                #       不符 fileLinePattern，整列不進判定
                #   (b) 機器參照只寫「OracleMCP SQL」——含「SQL」三字母就被豁免
                # 兩者都不是證據，是標籤：稽核重跑時什麼都跑不了。
                # 表頭列不驗（欄名不是證據）——但**不能靠「看到分隔列才開始」**：
                # 缺分隔列的表格會讓整段一列都不驗（與 L51 同型的範圍錯誤，
                # 自己的測試抓到）。改成直接認表頭欄名，缺分隔列時仍照驗
                # ——fail-safe 方向：判不出來就驗，不要略過。
                $isEvHeader = ($line -match '機器參照') -or ($line -match '^\|\s*編號\s*\|')
                if ($line -match '^\|' -and $line -notmatch '^\|[\s:|-]+$' -and -not $isEvHeader) {
                    $okUuid = ($line -match $fullUuid)
                    $okSelect = ($line -match $realSelect)
                    $okPending = ($line -match $pendingMark)
                    # 欄位錯放（管理者實測）：證據其實在「位置」欄，機器參照欄
                    # 只寫「PeopleCode chunk」這種標籤。整列有可重跑的東西＝
                    # 證據沒丟，稽核追得到——**降為警告**，不擋門也不進手術單；
                    # 但要點名，否則表格會一路歪下去。
                    if ($okUuid -or $okSelect) {
                        # 只在**四欄制**（編號｜位置｜說明｜機器參照）判錯放——
                        # 舊三欄列根本沒有機器參照欄，拿最後一欄當它會誤判
                        # （自己的回歸測試 T15 抓到）
                        $cells = @($line -split '\|' | Where-Object { $_.Trim() -ne '' })
                        if ($cells.Count -ge 4) {
                            $lastCell = $cells[$cells.Count - 1]
                            if ($lastCell -notmatch $fullUuid -and $lastCell -notmatch $realSelect -and
                                $lastCell -notmatch $pendingMark) {
                                $misplacedRefRows += "${name}:${evLineNo}"
                            }
                        }
                    }
                    if ($okPending -and -not ($okUuid -or $okSelect)) {
                        $pendingSqlRows += "${name}:${evLineNo}"
                    }
                    elseif (-not ($okUuid -or $okSelect)) {
                        $shown = $line.Trim()
                        if ($shown.Length -gt 60) { $shown = $shown.Substring(0, 60) }
                        $violations += "${name}:${evLineNo}：機器參照無效（既非 36 字元 ChunkId、也非可重跑 SELECT）——「OracleMCP SQL」「PeopleCode chunk」這類**只是標籤不是證據**，稽核重跑時跑不了；CHUNK 型補完整 id、SQL 型貼可重跑 SELECT、都不可得就寫「待人工SQL」：$shown…"
                        $ref = [regex]::Match($line, $fileLinePattern).Value
                        if ($ref -eq '') { $ref = '（無路徑線索——read 該檔該列）' }
                        $missingIds += [pscustomobject]@{ File = "${name}:${evLineNo}"; Ref = $ref }
                    }
                }
            }
        }
    }

# 2.4) subagent 回報 JSON 洩漏（L47）：主 agent 應把 subagent 的契約 JSON
# **消化成報告**，不是原樣貼進交付物。實案：90-audit.md 的「上輪回灌項覆核」
# 之後直接接模型的推理獨白＋整段 subagent JSON。與 L41 同族（寫入脫軌），
# 但簽名不同——這裡是「原料未加工就出貨」。掃 90-audit 與 NN 檔。
$rawJsonTargets = @()
if (Test-Path -LiteralPath (Join-Path $dir "90-audit.md")) { $rawJsonTargets += (Join-Path $dir "90-audit.md") }
foreach ($n in $nnNames) { $rawJsonTargets += (Join-Path $dir $n) }
foreach ($tf in $rawJsonTargets) {
    $tt = Get-Content -LiteralPath $tf -Raw -Encoding UTF8
    if ([string]::IsNullOrEmpty($tt)) { continue }
    $tname = Split-Path $tf -Leaf
    # 契約 JSON 的指紋：同時出現多個契約鍵，且以 JSON 形式（"key":）書寫
    $keyHits = 0
    foreach ($k in @('"agent"', '"searchScope"', '"deliveredFallbackUsed"', '"findings"',
            '"coverage"', '"dynamicRuntimeWarnings"', '"structureLines"', '"analyzedLines"')) {
        if ($tt.Contains($k)) { $keyHits++ }
    }
    if ($keyHits -ge 3) {
        $ln = 1
        foreach ($m in [regex]::Matches($tt, '"(agent|searchScope|findings|coverage)"\s*:')) {
            $ln = @($tt.Substring(0, $m.Index) -split "`n").Count
            break
        }
        $violations += "${tname}:${ln}：subagent 回報 JSON 原樣洩漏進文件（命中 $keyHits 個契約鍵）——契約 JSON 是**原料**，必須消化成報告文字；刪除該段並依契約內容重寫（同段常伴模型推理獨白，一併清）"
        # L80：這是**缺料類**（擋 tier 1）卻零出口——與模型內部標記洩漏同形，
        # 一併開成 [洩漏] 工單（修法一樣：看前後區塊有無截斷、刪除、補回）
        $jsonLeaks += [pscustomobject]@{ File = $tname; Line = $ln }
    }
}

# 2.5) 90-audit.md 模板符合度（每輪稽核會重寫，偏離記警告不擋；
#      -StrictAudit 時本節的結構性問題升為違規——僅限本節，wiki 類不升級）
$auditPath = Join-Path $dir "90-audit.md"
if (Test-Path -LiteralPath $auditPath) {
    $auditText = Get-Content -LiteralPath $auditPath -Raw -Encoding UTF8
    if ($null -eq $auditText) { $auditText = "" }   # 空檔＝全部章節缺（不炸例外）
    $auditSections = @('## 總覽記分卡', '## FAIL / DISPUTED / UNVERIFIABLE 明細',
        '## 上輪回灌項覆核', '## 完整性（換角度 diff）',
        '## 已回灌 checklist 的行動項', '## 系統性錯誤觀察')
    foreach ($sec in $auditSections) {
        if ($auditText -notmatch [regex]::Escape($sec)) {
            # 標題飄移只留警告（L36）——畢業門改驗「結構化全量覆蓋」的事實，
            # 綁標題字串會讓純命名問題變成無修復管道的活鎖
            $warnings += "90-audit.md：缺模板章節「$sec」（報告偏離模板；若記分卡改名，覆蓋檢查仍會驗全量）"
        }
    }
    # 契約外詞彙任何模式都只警告——散文合法引用歷史判定（如「上輪 contradicted
    # 已更正」）會誤中，升 FAIL 會製造無修復管道的畢業活鎖
    foreach ($bad in [regex]::Matches($auditText, '(?i)\b(partial[_ ]?pass|weakened|contradicted)\b')) {
        $warnings += "90-audit.md：出現契約外狀態「$($bad.Value)」（合法詞彙：PASS/FAIL/UNVERIFIABLE/VERIFIED/DISPUTED；自創詞應就近映射）"
    }
    if ($auditText -notmatch '稽核輪次') {
        $msg = "90-audit.md：表頭缺「稽核輪次」（無法判斷是否為最新一輪重驗）"
        # 同下方輪次不一致：判不出是不是本輪的報告＝綠燈不可信，tier 1 也要擋
        if ($StrictAudit -or $CoverageOnly) { $violations += $msg } else { $warnings += $msg }
    }
    # 輪次一致性（L28）：報告輪次 ≠ checklist 輪次＝報告可能是舊輪——
    # 「稽核沒跑過但看到全綠」的正解就是這個檢查
    $auditRoundNum = -1
    foreach ($m in [regex]::Matches($auditText, '稽核輪次[：:]\s*([0-9]+)')) {
        $auditRoundNum = [int]$m.Groups[1].Value
    }
    if ($clRound -ge 0 -and $auditRoundNum -ge 0 -and $auditRoundNum -ne $clRound) {
        $msg = "90-audit.md 輪次（$auditRoundNum）與 checklist 輪次（$clRound）不一致——報告可能是舊輪重驗前的殘留，綠燈不可信"
        # L73：畢業門的轉移層讀的是 checklist 的輪次＋90-audit 的 hash，
        # 「輪次遞增且 hash 變了」對一份**沒寫完**的報告照樣成立——轉移層
        # 只證明「動過」，證明不了「寫完」。這條是唯一識破的訊號，
        # 訊息自己都寫「綠燈不可信」了，就不該只在 tier 2 擋。
        if ($StrictAudit -or $CoverageOnly) { $violations += $msg } else { $warnings += $msg }
    }
    # 全量對帳（L36 結構化）：找「涵蓋最多 NN 檔」的章節當記分卡，驗是否覆蓋
    # 全部——標題叫什麼不重要，覆蓋率才是塌縮判準（自創標題不再擋畢業）
    $cover = Get-ScorecardCoverage -AuditText $auditText -NnNames $nnNames
    if ($cover.PrefixOnly.Count -gt 0) {
        $poSample = (@($cover.PrefixOnly | Select-Object -First 3) -join '、')
        $warnings += "90-audit.md：$($cover.PrefixOnly.Count) 個檔案以編號代稱（如「01」）而非完整檔名——**覆蓋算數、不擋門**，但完整檔名才讓「哪一檔沒被驗」一眼可讀：$poSample"
    }
    if ($cover.OutsideScorecard.Count -gt 0) {
        $osSample = (@($cover.OutsideScorecard | Select-Object -First 3) -join '、')
        $warnings += "90-audit.md：記分卡章節「$($cover.Heading)」沒有逐檔列出 $($cover.OutsideScorecard.Count) 個檔（逐檔資料在明細等其他章節）——**覆蓋算數、不擋門**，但記分卡逐檔一列最好讀：$osSample"
    }
    if ($nnNames.Count -gt 0 -and $cover.Missing.Count -gt 0) {
        $msg = "90-audit.md 整份報告未提及 $($cover.Missing.Count) 個檔名（提及 $($cover.Covered)/$($nnNames.Count)）——本項只量『報告有沒有提到這些檔』，不推論稽核跑了沒；成批問題寫成彙總句也會觸發。修法＝在記分卡或明細逐檔列出：$($cover.Missing -join '、')"
        # 只量「報告有沒有提到這些檔」——量不到「稽核跑了沒」，訊息不得代為
        # 推因（L69：舊訊息寫「稽核未全量重驗」，實案是稽核跑完但寫成彙總句）。
        # 掃**整份報告**不限章節（L77）：逐檔資料放記分卡或明細由模型決定，
        # 綁章節＝把版面偏好升級成畢業門，而 audit 每輪都照自己的習慣重寫
        # ＝無修復管道的活鎖。仍須擋 tier 1：真的整份都沒提到某檔，
        # 那份報告回灌不了。手動執行維持警告不擋（SOP-2）。
        if ($StrictAudit -or $CoverageOnly) { $violations += $msg } else { $warnings += $msg }
    }

    # ── 完整性節的假陰性（L81）─────────────────────────────────
    # 任務 C 是**分批委派**的，而委派會失敗（subagent 只回報「已讀取契約」
    # 就結束＝委派卡死的指紋）。模板只有一格「發現的物件：<清單，或無>」，
    # 於是「查了沒發現遺漏」與「根本沒查成」共用同一格——全部委派失敗時
    # 寫「無」，讀的人看到的是一個**假陰性的完整性宣稱**。
    # 只在 -StrictAudit（tier 2）升為違規：完整性盤點不在 tier 1 的承諾範圍
    # （tier 1＝功能查得到、文件有實質內容），提早擋只會拖慢覆蓋畢業。
    $intBody = ""
    $inInt = $false
    foreach ($ln in ($auditText -split "`r?`n")) {
        if ($ln -match '^##\s') { $inInt = ($ln -match '完整性'); continue }
        if ($inInt) { $intBody += ($ln + "`n") }
    }
    if ($intBody.Trim() -ne "" -and
        $intBody -notmatch '(?m)^.*任務\s*C\s*覆蓋.*(\d+.*\d+|全部完成|全數完成)') {
        $msg = "90-audit.md 完整性節缺「任務 C 覆蓋：完成 N／共 M 批」宣告——任務 C 分批委派且委派會失敗；沒有覆蓋率時，本節的「無」分不清『查了沒發現遺漏』與『根本沒查成』＝假陰性的完整性宣稱"
        if ($StrictAudit) { $violations += $msg } else { $warnings += $msg }
    }

    # ── 回灌工單（L79）───────────────────────────────────────────
    # 稽核已經查到答案的類型（ID_RELINK／LINE_DRIFT／STALE_DATA），答案寫在
    # 明細的「處置」欄。那是**純編輯**：不需要任何檢索，照抄即可。
    # 不套用的代價是複利：稽核是**全量重驗**，同一個失聯 id 每輪都要重做一次
    # 二次定位（Source deref → ES 結構化 → file-mode → semantic 翻頁）。
    # 只掃「明細」章節，且處置欄須符合嚴格格式；**新 id 已在該檔＝已套用，
    # 不重複開單**（否則報告沒重寫前每圈都會再開一次）。
    $detailBody = ""
    $inDetail = $false
    foreach ($ln in ($auditText -split "`r?`n")) {
        if ($ln -match '^##\s') { $inDetail = ($ln -match '明細'); continue }
        if ($inDetail) { $detailBody += ($ln + "`n") }
    }
    $relinkByFile = @{}
    $relinkPairs = @()   # (old,new) 配對——wiki 掃描用（L85：wiki sources 引用
                         # 同一批 chunk id，NN 換了新 id、wiki 還抱著死的）
    if ($detailBody -ne "") {
        foreach ($row in [regex]::Matches($detailBody, '(?m)^[^\S\r\n]*\|(?<c>.+)\|[^\S\r\n]*$')) {
            $cells = @($row.Groups['c'].Value -split '\|' | ForEach-Object { $_.Trim() })
            if ($cells.Count -lt 3) { continue }
            $fCell = $cells[0]
            $act = $cells[$cells.Count - 1]
            if ($fCell -match '^[-: ]+$' -or $fCell -eq '檔案') { continue }
            # 檔名欄可能寫完整檔名、編號（「03」）、或 wiki/<檔名>（wiki 抽驗列）
            $target = $null
            $mW = [regex]::Match($fCell, 'wiki[/\\](?<w>\S+\.md)')
            if ($mW.Success) { $target = "docs/ps-research/wiki/" + $mW.Groups['w'].Value }
            if ($null -eq $target) {
            foreach ($n in $nnNames) {
                $b = [IO.Path]::GetFileNameWithoutExtension($n)
                if ($fCell -match [regex]::Escape($b)) { $target = $n; break }
            }
            if ($null -eq $target) {
                # 編號代稱：只在該編號**唯一**對應一個檔時採用
                # （NN-X.md 與續篇 NN-X-2.md 共用前綴時無法判別，寧可不開單）
                $mNn = [regex]::Match($fCell, '(?<nn>\d\d)(?![0-9])')
                if ($mNn.Success) {
                    $cand = @($nnNames | Where-Object { $_.Substring(0, 2) -eq $mNn.Groups['nn'].Value })
                    if ($cand.Count -eq 1) { $target = $cand[0] }
                }
            }
            }
            if ($null -eq $target) { continue }
            $ord = $null
            $mR = [regex]::Match($act, '換\s*id\s*[：:]?\s*(?<old>[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s*(?:→|->|—>)\s*(?<new>[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')
            if ($mR.Success) {
                $newId = $mR.Groups['new'].Value
                # 已套用就不開單（wiki 目標不在 $nnText，就地讀檔判定）
                $tgtText = $null
                if ($nnText.ContainsKey($target)) { $tgtText = $nnText[$target] }
                elseif ($target -like 'docs/ps-research/wiki/*') {
                    $wp = Join-Path $root $target
                    if (Test-Path -LiteralPath $wp) { $tgtText = Get-Content $wp -Raw -Encoding UTF8 }
                }
                if ($tgtText -and $tgtText.IndexOf($newId, [StringComparison]::OrdinalIgnoreCase) -ge 0) { continue }
                $ord = "換 id $($mR.Groups['old'].Value) → $newId"
                $relinkPairs += , @($mR.Groups['old'].Value, $newId)
            }
            else {
                $mL = [regex]::Match($act, '更新行號\s*[：:]?\s*(?:→|->)?\s*(?<v>\S+)')
                $mS = [regex]::Match($act, '更新數值\s*[：:]?\s*(?:→|->)?\s*(?<v>\S+)')
                if ($mL.Success) { $ord = "更新行號 → $($mL.Groups['v'].Value)（原列見明細）" }
                elseif ($mS.Success) { $ord = "更新數值 → $($mS.Groups['v'].Value)（原列見明細）" }
            }
            if ($null -ne $ord) {
                if (-not $relinkByFile.ContainsKey($target)) { $relinkByFile[$target] = @() }
                $relinkByFile[$target] += $ord
            }
        }
    }
    # wiki 同步（L85）：entity 的 sources 與 NN 引用同一批 chunk——凡有
    # 「換 id」配對，wiki 檔裡還留著舊 UUID 的一律同單換掉。wiki 沒有
    # 稽核管道，這是死 id 在問答層唯一的機械修復路。
    if ($relinkPairs.Count -gt 0) {
        $wikiDir = Join-Path $researchRoot "wiki"
        if (Test-Path -LiteralPath $wikiDir) {
            foreach ($wf in @(Get-ChildItem -LiteralPath $wikiDir -Filter "*.md" -File)) {
                $wText = Get-Content $wf.FullName -Raw -Encoding UTF8
                if ([string]::IsNullOrEmpty($wText)) { continue }
                foreach ($pair in $relinkPairs) {
                    if ($wText.IndexOf($pair[0], [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $wKey = "docs/ps-research/wiki/" + $wf.Name
                        if (-not $relinkByFile.ContainsKey($wKey)) { $relinkByFile[$wKey] = @() }
                        $relinkByFile[$wKey] += "換 id $($pair[0]) → $($pair[1])"
                    }
                }
            }
        }
    }
    foreach ($f in ($relinkByFile.Keys | Sort-Object)) {
        $items = @($relinkByFile[$f])
        $relinkOrders += ("{0}｜{1}" -f $f, ($items -join '；'))
    }
}
elseif ($StrictAudit) {
    # 檔案整個不存在＝最嚴重的塌縮——非 strict 模式整節跳過（零警告）是刻意的
    # 歷史行為，但畢業門必須把「從未稽核」擋下
    $violations += "90-audit.md 不存在（StrictAudit：畢業門要求稽核報告存在）"
}

# 3) Entity Wiki 檢查（wiki/ 為跨領域共用層，存在才檢）
$wikiDir = Join-Path $root "docs/ps-research/wiki"
if (Test-Path $wikiDir) {
    $allMd = Get-ChildItem (Join-Path $root "docs/ps-research") -Recurse -Filter "*.md"
    $noteNames = @{}
    $allMd | ForEach-Object {
        $noteNames[[IO.Path]::GetFileNameWithoutExtension($_.Name)] = $true
    }
    $wikiNotes = Get-ChildItem $wikiDir -Filter "*.md" |
        Where-Object { $_.Name -ne 'index.md' }

    foreach ($n in $wikiNotes) {
        $t = Get-Content $n.FullName -Raw -Encoding UTF8
        if ([string]::IsNullOrEmpty($t)) {
            $violations += "wiki/$($n.Name)：空檔（0 byte／無內容）——疑似寫入中斷"
            continue
        }
        foreach ($key in @('aliases', 'status', 'last_verified')) {
            if ($t -notmatch "(?m)^${key}\s*:") {
                $violations += "wiki/$($n.Name)：frontmatter 缺 $key"
            }
        }
        if ($t -match '(?m)^status\s*:\s*(\S+)') {
            if ($Matches[1] -notin @('draft', 'verified', 'stale')) {
                $violations += "wiki/$($n.Name)：status 值非法：$($Matches[1])"
            }
        }
        if ($t -match '(?m)^last_verified\s*:\s*(\d{4}-\d{2}-\d{2})') {
            $d = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd', $null)
            if (((Get-Date) - $d) -gt [timespan]::FromDays(90)) {
                $warnings += "wiki/$($n.Name)：last_verified 超過 90 天（$($Matches[1])）→ 建議排入複查"
            }
        }
    }

    # 斷鏈與孤兒（[[目標]] 以「檔名（不含副檔名）」解析，跨全部領域）
    $referenced = @{}
    $domainMissing = @{}   # 本領域檔案連到、但 entity 不存在的物件（歸戶儀表 L86）
    foreach ($f in $allMd) {
        $t = Get-Content $f.FullName -Raw -Encoding UTF8
        if ([string]::IsNullOrEmpty($t)) { continue }   # 空檔已於前段記違規，斷鏈掃描跳過
        foreach ($m in [regex]::Matches($t, '\[\[([^\]|#]+)')) {
            $target = $m.Groups[1].Value.Trim()
            $referenced[$target] = $true
            if (-not $noteNames.ContainsKey($target)) {
                $warnings += "$($f.Name)：wikilink 目標不存在：[[${target}]]"
                if ($f.FullName.StartsWith($dir, [StringComparison]::OrdinalIgnoreCase)) {
                    $domainMissing[$target] = $true
                }
            }
        }
    }
    foreach ($n in $wikiNotes) {
        $entity = [IO.Path]::GetFileNameWithoutExtension($n.Name)
        if (-not $referenced.ContainsKey($entity)) {
            $warnings += "wiki/$($n.Name)：孤兒 entity（沒有任何 [[${entity}]] 入鏈）"
        }
    }
    # 歸戶儀表（L86）：auto-loop 畢業後的提煉相位以此收斂——固定輸出（0 也印）
    Write-Host "WIKI_MISSING：$($domainMissing.Count) 個本領域物件待歸戶"
}

# ── 模型內部標記洩漏：**領域內全部 .md 統一掃描**（L41／L51）─────────
# L51：原本只掃 NN 檔，於是 checklist.md／00-overview.md／90-audit.md 的
# 洩漏完全沒人看——實案：checklist 的「Gaps 彙整」節混進 <think>，而該領域
# 照樣通過 tier 1 畢業門。模型寫得到的檔就掃得到，不要挑檔。
# 洩漏常伴隨**寫入脫軌**——表格寫到一半斷掉、接著思考文字與 tool_call
# 灌進檔案、下一節才恢復。只刪標記會留下半截表格，所以訊息要求檢查
# 「該標記前後整個區塊」。
$leaks = @()
$leakPattern = '</?think(ing)?>|<\|im_(start|end)\|>|<\|endoftext\|>|</?tool_call>|<function='
if (Test-Path -LiteralPath $dir) {
    foreach ($lf in (Get-ChildItem -LiteralPath $dir -Filter "*.md" -File | Sort-Object Name)) {
        $ltext = Get-Content -LiteralPath $lf.FullName -Raw -Encoding UTF8
        if ([string]::IsNullOrEmpty($ltext)) { continue }
        foreach ($m in [regex]::Matches($ltext, $leakPattern)) {
            $lline = 1 + @($ltext.Substring(0, $m.Index) -split "`n").Count - 1
            $violations += "$($lf.Name):${lline}：模型內部標記洩漏（寫入脫軌）：$($m.Value)——檢查該行**前後整個區塊**（常見：表格斷在半路＋思考文字），刪污染並補回被截斷的內容；補不回就開重查工單"
            # 工單素材（L53）：洩漏原本只產違規、不產工單＝擋得住門卻沒有修復
            # 管道，自動迴圈必然活鎖（L43 同族）。可委派的只有 NN 檔——
            # checklist／archive 是熱檔（整檔重寫會吃掉未勾項）、00-overview 已凍結
            # （agent 零寫入）、90-audit 下輪稽核整檔重寫會自然消失。
            $delegable = ($lf.Name -match '^\d\d-' -and $lf.Name -notmatch '^(00|90)-')
            $leaks += @{ File = $lf.Name; Line = $lline; Marker = $m.Value; Delegable = $delegable }
        }
    }
}

# 宣稱環境受限卻零列走出口（L56）：真的查不到就標「待人工SQL」——那是
# 申報。只在散文裡寫「無法連線／連線限制」而一列都沒標，等於用一句話
# 免除整批舉證責任，而且事後無法分辨「真的不通」與「沒去查」。
# 實案：Gaps 寫「OracleMCP 連線限制…Unverifiable」，但管理者確認 Oracle
# 從未中斷，且全域零列標待人工SQL——30 列機器參照全是標籤。
$limitClaimPattern = '(無法連線|連線限制|無資料庫連線|連線不可用|通道(不通|中斷)|MCP\s*(不可用|無法使用))'
if ($pendingSqlRows.Count -eq 0 -and (Test-Path -LiteralPath $dir)) {
    foreach ($cf in (Get-ChildItem -LiteralPath $dir -Filter "*.md" -File | Sort-Object Name)) {
        $ctext = Get-Content -LiteralPath $cf.FullName -Raw -Encoding UTF8
        if ([string]::IsNullOrEmpty($ctext)) { continue }
        $cm = [regex]::Match($ctext, $limitClaimPattern)
        if ($cm.Success) {
            $cline = 1 + @($ctext.Substring(0, $cm.Index) -split "`n").Count - 1
            $warnings += "$($cf.Name):${cline}：宣稱環境受限（「$($cm.Value)」）但**全領域零列標『待人工SQL』**——真受限就在受影響的證據列走合法出口（那才是申報）；通道其實正常就把這句宣稱刪掉，否則無法分辨『真的不通』與『沒去查』"
            break
        }
    }
}
# 待人工SQL：合法的終止出口（L43／L53），不算違規——但要點名，否則
# 「這份文件有幾條主張還沒被機器驗過」就沒有人知道
if ($pendingSqlRows.Count -gt 0) {
    $warnings += "Evidence：$($pendingSqlRows.Count) 列標「待人工SQL」（合法待辦，非違規）——這些主張尚未經機器驗證，管理者照 SOP-2 第 4 階自跑 SQL 後回填：$($pendingSqlRows -join '、')"
}
# 欄位錯放：證據在別欄、機器參照欄放標籤——證據沒丟，只是表格不一致
if ($misplacedRefRows.Count -gt 0) {
    $warnings += "Evidence：$($misplacedRefRows.Count) 列的機器參照欄放的是標籤（如「PeopleCode chunk」「OracleMCP SQL」），真正的 ChunkId／SELECT 在同列其他欄——證據追得到故不擋，但機器參照欄應放可重跑的那一份：$($misplacedRefRows -join '、')"
}

# ── 覆蓋畢業門（tier 1）分類：美工類白名單 ──────────────────
# 分界線：**整個 Evidence／驗證層算美工，內容層算缺料**。
#   缺料＝讀者讀不到或讀到壞東西：缺檔、空檔、缺章節、空殼章節、
#         checklist 對帳不符、模型標記或契約 JSON 洩漏（疑似被截斷）。
#   美工＝內容讀得懂，但「無法逐條回溯驗證」或少了機器欄位：證據 id 格式、
#         機器參照、Evidence 附錄空白、confidence 標註、wiki frontmatter。
# 「Evidence 附錄空白」必須同列美工，否則分類失效：id 格式壞掉的檔會被判成
# 「附錄無有效證據」而同時觸發兩類，美工降級形同虛設（實案：該領域 uuid
# 問題為大宗）。代價要講明：**tier 1 只保證讀得懂、查得到、沒被截斷，
# 不保證每句話都能回溯驗證**——回溯驗證是 tier 2 精修的工作。
$polishPatterns = @(
    'Evidence 附錄空白',
    'ChunkId 遭縮寫為 8 碼',
    'ChunkId 非 UUID 格式',
    '出現自編 id 樣式',
    '疑似縮寫 chunk id',
    '當機器參照',
    '機器參照無效',
    '行為邏輯無任何 confidence 標註',
    'frontmatter 缺 ',
    'status 值非法'
)
function Test-IsPolishViolation {
    param([string]$Msg)
    foreach ($pat in $polishPatterns) {
        if ($Msg.Contains($pat)) { return $true }
    }
    return $false
}
if ($CoverageOnly) {
    $kept = @()
    $downgraded = 0
    foreach ($v in $violations) {
        if (Test-IsPolishViolation $v) { $warnings += "[美工／不擋覆蓋畢業] $v"; $downgraded++ }
        else { $kept += $v }
    }
    $violations = $kept
    Write-Host "CoverageOnly：$downgraded 項美工類違規降為警告（tier 1 只收缺料類）" -ForegroundColor Cyan
}

# 輸出
if ($warnings.Count -gt 0) {
    Write-Host "WARN：$($warnings.Count) 項警告（不擋通過）" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host " - $_" }
}
if ($violations.Count -eq 0) {
    Write-Host "PASS：$Domain 全部檢查通過" -ForegroundColor Green
    $exitCode = 0
}
else {
    Write-Host "FAIL：$($violations.Count) 項違規" -ForegroundColor Red
    $violations | ForEach-Object { Write-Host " - $_" }
    $exitCode = 1
    # 相位提示（L72）：90-audit.md 類違規只有 **audit 相位**重寫得了，research
    # 再跑幾輪也不會動到它。auto-loop 讀這個數字決定相位——否則「唯一能修它的
    # 相位被它自己擋在門外」＝活鎖（L63 同族）。畢業門仍看全部違規，標準沒放寬。
    $auditOnlyViolations = @($violations | Where-Object { $_ -like '90-audit.md*' })
    if ($auditOnlyViolations.Count -gt 0) {
        Write-Host "AUDIT_ONLY：$($auditOnlyViolations.Count) 項只有 audit 相位修得了（90-audit.md 類）——research 再跑幾輪也不會動到它" -ForegroundColor Yellow
    }
    # 沒有任何相位修得掉的（L74）：agent 被明令禁止改寫 checklist-archive*.md
    # （ps-deep-research 硬規則），所以牽涉歸檔內容的一律只能人工。
    # 白名單制——沒列到的預設「research 修得動」，讓迴圈去試（fail-safe：
    # 分類漏掉只是多跑一圈，分類過頭會讓真的能自動修的項目被判成要人工）。
    $manualPatterns = @('個未打勾項', '與歸檔重複', '稽核流程標籤', '行「稽核輪次」', '任何一行提及', '同物件重複建檔')
    $manualOnlyViolations = @($violations | Where-Object {
            $v = $_
            ($manualPatterns | Where-Object { $v.Contains($_) }).Count -gt 0
        })
    if ($manualOnlyViolations.Count -gt 0) {
        Write-Host "MANUAL_ONLY：$($manualOnlyViolations.Count) 項沒有任何相位修得掉，需人工處理（歸檔類——agent 禁止改寫 checklist-archive*.md）" -ForegroundColor Yellow
        $manualOnlyViolations | ForEach-Object { Write-Host "   · $_" -ForegroundColor Yellow }
    }
}

# 證據修復指令（縮寫 id＋機器參照無效同一張單）——放「最後」印，
# 才不會被警告牆洗出畫面。L42：工單**先判型別再給修法**，不預設「去找 chunk」
# （失敗查詢／SQL 型證據被寫成「缺 id」會逼模型去做無解的事）。
$leakDelegable = @($leaks | Where-Object { $_.Delegable })
$leakManual = @($leaks | Where-Object { -not $_.Delegable })
# tier 1（-CoverageOnly）的工單只出「缺料類」＝[洩漏] 型（寫入脫軌會讓章節
# 真的缺內容）。[欄位]／[證據] 型對應的違規訊息全在 $polishPatterns 白名單內
# ——CoverageOnly 已把它們降為警告不擋門，工單卻照出，等於 auto-loop 在 tier 1
# 燒好幾個 session 修不擋門的東西，與廣度優先（L50：tier 1 不保證回溯驗證，
# 回溯驗證是 tier 2 的工作）直接牴觸。
$polishOrderCount = $truncatedIds.Count + $missingIds.Count + $misplacedRefRows.Count +
    $bogusIds.Count + $failedQueryRows.Count
$emitPolish = (-not $CoverageOnly)
# [章節] 兩個 tier 都出（L93）：缺章節是缺料不是美工（CoverageOnly 本來就不降它）
# [附錄] 同理（L103）：裸 id 傾倒＝證據不可解引用＝缺料，不是排版
$orderTotal = $leakDelegable.Count + $relinkOrders.Count + $jsonLeaks.Count + $sectionGapByFile.Count + $rawAppendix.Count
if ($emitPolish) { $orderTotal += $polishOrderCount }
# [回灌] 兩個 tier 都出（L79）：它不需要任何檢索（答案已在明細），而每不做
# 一次，下一輪全量重驗就要對同一筆重付一次二次定位——與 [欄位]／[證據]
# 的經濟性完全不同，不套用 tier 1 的美工抑制。
if ($orderTotal -gt 0) {
    Write-Host ""
    Write-Host "=== 證據修復指令（複製整段貼給 PS-DEEP-RESEARCH；超過 7 筆請分批貼）===" -ForegroundColor Cyan
    Write-Host "以下是 lint 確認的問題清單，逐筆修復、一次一筆、一筆都不准跳："
    Write-Host "（[欄位] 型已按檔合併＝一個檔一個任務；[洩漏]／[證據] 型逐列）"
    $i = 0
    foreach ($t in $leakDelegable) {
        $i++
        Write-Host "$i. [洩漏] $($t.File):$($t.Line)：$($t.Marker)"
    }
    foreach ($t in $jsonLeaks) {
        $i++
        Write-Host "$i. [洩漏] $($t.File):$($t.Line)：subagent 契約 JSON 原樣寫進文件"
    }
    foreach ($r in $relinkOrders) {
        $i++
        $parts = $r -split '｜', 2
        Write-Host "$i. [回灌] $($parts[0])：$($parts[1])"
    }
    # [章節]（L93）：一檔一單——缺章節工單沒有這型之前，lint 每輪算出明細
    # 卻只寫進沒 session 讀的 log，違規永遠不癒
    foreach ($fn in ($sectionGapByFile.Keys | Sort-Object)) {
        $i++
        $secs = (@($sectionGapByFile[$fn]) -join '、')
        Write-Host "$i. [章節] ${fn}：缺 $secs"
    }
    # [附錄]（L103）：一檔一單；工單文字不帶筆數——筆數是狀態不是身分，
    # 帶進去會讓 auto-loop 台帳指紋失穩（attempts 歸零、BLOCKED 到不了）
    foreach ($fn in ($rawAppendix | Sort-Object)) {
        $i++
        Write-Host "$i. [附錄] ${fn}：Evidence 附錄非模板表格（裸 ChunkId 傾倒）"
    }
    # [欄位] 型按**檔**合併成一個任務：對調欄位是純編輯，一個檔一次改完最省
    # ——逐列開單會把 30 列變成 30 個任務，而 auto-loop 一圈只吃 7 筆（實案：
    # 錯放 30 餘列，逐列開單要 5 圈、每圈還先燒一個稽核 session）
    $swapByFile = @{}
    if ($emitPolish) {
    foreach ($t in $misplacedRefRows) {
        $fn = ($t -split ':')[0]
        $ln = ($t -split ':')[1]
        if (-not $swapByFile.ContainsKey($fn)) { $swapByFile[$fn] = @() }
        $swapByFile[$fn] += $ln
    }
    foreach ($fn in ($swapByFile.Keys | Sort-Object)) {
        $i++
        $lns = @($swapByFile[$fn])
        Write-Host "$i. [欄位] ${fn}：$($lns.Count) 列欄位錯放（行 $($lns -join '、')）"
    }
    foreach ($t in $truncatedIds) {
        $i++
        Write-Host "$i. [證據] $($t.File)：縮寫 id $($t.Id)"
    }
    foreach ($t in $missingIds) {
        $i++
        Write-Host "$i. [證據] $($t.File)：機器參照無效＠$($t.Ref)"
    }
    foreach ($t in $bogusIds) {
        $i++
        Write-Host "$i. [證據] $($t.File)：**不可信 id**（非 UUID／自編樣式）：$($t.Id)"
    }
    foreach ($t in $failedQueryRows) {
        $i++
        Write-Host "$i. [證據] ${t}：以失敗查詢當機器參照（SQL 型，多半表名寫錯）"
    }
    }
    Write-Host ""
    if ($sectionGapByFile.Count -gt 0) {
        Write-Host "【章節】型（檔案缺必要模板章節）——**補研究不是機械修**："
        Write-Host "  1) read 該檔，辨識主角物件；既有內容與既有證據**全部保留**"
        Write-Host "  2) 所缺章節依 function-detail 模板補寫——內容須經委派 ps-* flow"
        Write-Host "     檢索取證（Evidence 附錄要完整 36 字元 ChunkId，逐字取自工具回傳）"
        Write-Host "  3) 取證不到的節照實寫「查無＋查法收據」進未解事項，不得編造充版面"
    }
    if ($rawAppendix.Count -gt 0) {
        Write-Host "【附錄】型（Evidence 附錄是裸 id 清單、不是模板表格）——**重建表格不是排版**："
        Write-Host "  1) read 該檔＋read report-templates/function-detail-template.md 的 Evidence 附錄節"
        Write-Host "  2) 節內每個裸 ChunkId 各委派一次解引用（get_chunks_details）取 filePath＋行號"
        Write-Host "     ＋內容摘要 → 依模板四欄表格逐筆成列（欄名逐字照抄：編號、位置、說明、機器參照）"
        Write-Host "  3) 解不了的 id → 該筆移除、未解事項記一行查法收據；**禁止憑印象編位置／說明**"
        Write-Host "  4) 本文其他章節一字不動"
    }
    if ($leakDelegable.Count -gt 0) {
        Write-Host "【洩漏】型（模型內部標記寫進了交付物）——**不是刪掉標記就好**："
        Write-Host "  1) read 該檔，看標記**前後整個區塊**：表格是否斷在半路、"
        Write-Host "     章節是否缺了下半段、有沒有跟著混進推理獨白或工具呼叫文字"
        Write-Host "  2) 刪掉標記與所有非交付內容（推理獨白、契約 JSON、工具回傳原文）"
        Write-Host "  3) **補回被截斷的內容**——原本該有的表格列／段落要寫回來；"
        Write-Host "     補得回就補（證據照原有 chunk id／SQL 重取，不得憑印象重寫）"
        Write-Host "  4) 補不回＝該段內容已遺失：在該檔「未解事項」記一行"
        Write-Host "     「<章節> 因寫入脫軌遺失，待重查」，並**停止該筆**（不要編造）"
        Write-Host "  5) 只准改清單所列的檔，一個字都不要動其他檔"
        Write-Host ""
    }
    if ($relinkOrders.Count -gt 0) {
        Write-Host "【回灌】型（**最便宜：純字串替換，不要重查、不要呼叫檢索工具**）："
        Write-Host "  來源：90-audit.md 明細的「處置」欄——稽核**已經查到答案**了，照抄即可。"
        Write-Host "  換 id：read 該檔 → 找出**舊 UUID 的所有出現處** → 全部換成新 UUID"
        Write-Host "        （同一 chunk 可能被多列引用，漏換等於下輪再開一次單）"
        Write-Host "    → 驗貨：用**新 id** 呼叫 get_chunks_details 一次，"
        Write-Host "      回傳 ChunkText 必須包含該列原引文；不含＝抓錯，**禁止硬填**，"
        Write-Host "      該筆記收據跳過（下一輪稽核會重新定位）"
        Write-Host "    → 舊 UUID 在該檔找不到＝該列已被改過或已刪除：記收據跳過，不要硬塞"
        Write-Host "  更新行號／更新數值：依明細所給的新值改該列，內容一個字都不動。"
        Write-Host "  收據格式：「檔:舊值 → 新值」逐筆一行。"
        Write-Host ""
    }
    if ($emitPolish -and $misplacedRefRows.Count -gt 0) {
        Write-Host "【欄位】型（**最便宜：純編輯，不要重查、不要呼叫任何工具**）："
        Write-Host "  現象：位置欄放了完整 ChunkId 或可重跑 SELECT，機器參照欄卻只寫"
        Write-Host "        「ChunkId」「PeopleCode chunk」「OracleMCP」「SQL」這類標籤。"
        Write-Host "  修法：把**可重跑的那一份搬到機器參照欄**，位置欄改放它該放的東西："
        Write-Host "        · CHUNK 型：位置欄＝filePath:行號，機器參照欄＝完整 36 字元 ChunkId"
        Write-Host "        · SQL 型：位置欄＝表名與鍵值，機器參照欄＝SQL：SELECT … FROM …"
        Write-Host "  鐵律：**證據內容一個字都不要改**——只搬欄位。id 或 SELECT 若在搬運中"
        Write-Host "        被改短、改寫、憑印象重打，就是捏造，稽核會判 FAIL。"
        Write-Host "  同一檔內其他列若已是正確格式，照那個格式對齊即可。"
        Write-Host ""
    }
    if ($emitPolish) {
    Write-Host "【證據】型每筆**先判型別再動手（判錯型別＝白做）**："
    Write-Host " A. CHUNK 型（程式碼：PeopleCode／AE step／SQR／SQL definition）"
    Write-Host "    → read 該檔該行取得 filePath／物件名 → **委派**下列其中一個重取"
    Write-Host "      （首選依檔型；五個都有 ES＋Source，任一個都取得到 chunk）："
    Write-Host "        PeopleCode→ps-peoplecode-flow｜SQL/View→ps-sql-flow"
    Write-Host "        SQR/SQC→ps-sqr-flow｜AE→ps-ae-flow｜跨界或型別不明→ps-metadata-flow"
    Write-Host "      **禁止委派 general／explore／scout**（四個 MCP 全封＝零工具，"
    Write-Host "      交付給它必然轉圈到逾時）；**CHUNK 型禁派 ps-ui-flow**（無 ES/Source）"
    Write-Host "    → **查無不等於不存在**：首選回報查無時，改派 ps-ae-flow 或"
    Write-Host "      ps-metadata-flow（四工具全譜）再試一次；兩個管道都查無才算查無"
    Write-Host "      （搜檔 → get_file_structure → get_chunks_details）；＠後若是"
    Write-Host "      「名:數字」而該名是 AE／物件名，用 search_chunks(objectName=該名,"
    Write-Host "      componentType=ApplicationEngineProgram) 取該 step 的 chunk"
    Write-Host "    → SQR／SQC 用 search_chunks(componentType=sqr 或 sqc)＋程式名定位"
    Write-Host "      （既有的 SQR／SQC 查無結論一律重查，不得沿用）"
    Write-Host "    → 驗貨：回傳 ChunkText 必須包含該列原引文，抓錯禁止硬填"
    Write-Host "    → 用工具回傳的完整 36 字元 ChunkId 更新該列（其他一字不動）"
    Write-Host " B. SQL／metadata 型（查 DB 表：排程 PSPRCSRQST／PS_PRCSRECUR、"
    Write-Host "    頁面 PSPNLDEFN…）＝**本就免 chunk id，不要去找 chunk**"
    Write-Host "    → **委派給具 oracleMCP 權限的 subagent 執行**（只有這三個：ps-metadata-flow／"
    Write-Host "      ps-ae-flow／ps-ui-flow），照 cookbook 樣板、表名禁自行加減 PS_ 前綴"
    Write-Host "    → 你自己看不到 SQL 執行工具＝**圍堵設計不是故障**——"
    Write-Host "      **禁止因此改查 peoplecode source（DB 事實不在程式碼裡）**"
    Write-Host "    → 機器參照欄改寫成「SQL：可重跑的 SELECT」，說明欄放 keyRows"
    Write-Host "    → 原機器參照寫著 schema 不存在／查無此表／ORA- ＝失敗查詢不是證據；"
    Write-Host "      委派後仍不可得（通道忙／權限）→ 該筆輸出「舊值 → 待人工SQL」"
    Write-Host "      收據並**停止該筆**（管理者照 SOP-2 第 4 階自跑），不得換工具重試"
    Write-Host "    ※ 標「**不可信 id**」的：那個 id 本身完全不可信，**不要試圖補全它**"
    Write-Host "      ——依該列的 filePath／物件名走 A 或 B 重新取證；取不到就走 C"
    Write-Host "    ※ 標「失敗查詢」的：一律走 B（SQL／metadata 型）——表名多半寫錯，"
    Write-Host "      **禁自行加減 PS_ 前綴**（cookbook 規則 8a），改正後貼可重跑 SELECT"
    Write-Host " C. A 與 B 都取不到 → 該列移除、主張降級 INFERRED、"
    Write-Host "    未解事項記一行查法收據（查了什麼、怎麼查、結果）"
    Write-Host ""
    }
    Write-Host "全部完成後輸出收據，每筆一行：欄位型「檔:行 → 已對調（機器參照欄現為 <id 或 SELECT 前 20 字>）」；"
    Write-Host "洩漏型「檔:行 → 已清除＋補回<內容>」或"
    Write-Host "「檔:行 → 已清除，<章節>內容遺失已記未解事項」；證據型「舊值 → 新完整UUID」"
    Write-Host "或「舊值 → SQL：SELECT…」或「舊值 → 移除入 gaps」或「舊值 → 待人工SQL」。"
    Write-Host "沒有收據＝沒完成。現在從第 1 筆開始。"
    Write-Host "=== 指令結束 ===" -ForegroundColor Cyan
    Write-Host ""
}
# 抑制要講出來——無聲截斷會讀成「已經沒事了」
if ($CoverageOnly -and $polishOrderCount -gt 0) {
    Write-Host "（另有 $polishOrderCount 筆美工類工單未列出——[欄位]／[證據] 型不擋覆蓋畢業，留待 tier 2 精修）" -ForegroundColor DarkGray
    Write-Host ""
}
# 不可委派的洩漏：印在工單之外，避免被自動迴圈餵進去做無解的事（L43）
if ($leakManual.Count -gt 0) {
    Write-Host "=== 洩漏：人工處理清單（**不要**貼給模型）===" -ForegroundColor Yellow
    foreach ($t in $leakManual) {
        $why = "熱檔／凍結檔，模型整檔重寫風險高"
        if ($t.File -like 'checklist*') { $why = "checklist 類是熱檔：模型整檔重寫可能吃掉未勾項——手動刪標記最安全" }
        elseif ($t.File -like '00-*') { $why = "00-overview 已凍結（agent 零寫入）：手動刪，或併進 SOP-15 換版一起處理" }
        elseif ($t.File -like '90-*') { $why = "90-audit 下一輪稽核會整檔重寫、自然消失；要現在乾淨就手動刪該段" }
        Write-Host (" - " + $t.File + ":" + $t.Line + "：" + $t.Marker + "  → " + $why)
    }
    Write-Host "共通做法：刪標記前先看**前後整個區塊**有沒有被截斷；內容補不回就在該處明寫遺失。" -ForegroundColor Yellow
    Write-Host "=== 人工清單結束 ===" -ForegroundColor Yellow
    Write-Host ""
}

# ── -FixArchive（L82）：歸檔裡的未打勾列自動處置 ────────────────
# 歸檔契約只收已打勾項，所以未勾列一定是三種成因之一，而修法完全不同：
#   · 明示未完成（「未完成／須重派／無回應／⚠」）且是**批次類流程標籤**
#     → 從歸檔刪除，並把該事實改寫進 checklist.md 的「## Gaps 彙整」。
#       批次不是調查項，搬回「## 調查進度」會變成沒有 NN 對象的假項目；
#       但**直接刪掉會湮滅一次真實的委派失敗**，所以資訊要落到 Gaps。
#   · 明示未完成、但**不是**批次類（正常調查項／A 項）
#     → 搬回「## 調查進度」（保持未勾）——它自己說了沒做完。
#   · 純批次類、無未完成字樣 → 刪除（純噪音，下輪 audit 重做）。
#   · 其餘未勾列 → **不動**：「本來就沒做完」與「打勾在寫檔時掉了」
#     機械上分不出，誤打勾會讓真的漏掉的項目永遠消失。留 MANUAL_ONLY。
# 判定**先看內容再看外形**（L81）：含未完成字樣的批次列不是噪音，是紀錄。
if ($FixArchive) {
    Write-Host ""
    Write-Host "=== -FixArchive：歸檔未打勾列處置 ===" -ForegroundColor Cyan
    $incompletePattern = '(未完成|須重派|重派|無回應|失敗|⚠)'
    $toGaps = @()
    $toProgress = @()
    $touched = 0
    foreach ($af in $archiveFiles) {
        $afRaw = Get-Content $af.FullName -Raw -Encoding UTF8
        if ([string]::IsNullOrEmpty($afRaw)) { continue }
        $keep = @()
        $changed = $false
        foreach ($ln in ($afRaw -split "`r?`n")) {
            if ($ln -notmatch '^\s*-\s*\[ \]') { $keep += $ln; continue }
            # L96：帶 A/U/D 工單編號開頭的列是合法工單，不是批次流程標籤
            # L97：流程標籤判定雙語（模型會寫英文 task C batch）
            $isProc = (($ln -match '((任務|task)\s*[ABC]|批次\s*\d+\s*[/／]\s*\d+)') -and
                       ($ln -notmatch '^\s*-\s*\[ \]\s*[AUDaud]\d+-\d+'))
            $isIncomplete = ($ln -match $incompletePattern)
            if ($isProc -and $isIncomplete) {
                $toGaps += ($ln -replace '^\s*-\s*\[ \]\s*', '')
                Write-Host "  [刪除→Gaps] $($af.Name)：$($ln.Trim())" -ForegroundColor Yellow
                $changed = $true; continue
            }
            if ($isIncomplete) {
                $toProgress += $ln.TrimEnd()
                Write-Host "  [搬回進度] $($af.Name)：$($ln.Trim())" -ForegroundColor Yellow
                $changed = $true; continue
            }
            if ($isProc) {
                Write-Host "  [刪除] $($af.Name)：$($ln.Trim())（純批次標籤，下輪 audit 重做）" -ForegroundColor Yellow
                $changed = $true; continue
            }
            Write-Host "  [不動] $($af.Name)：$($ln.Trim())（判不出『沒做完』或『掉了勾』，留人工）" -ForegroundColor DarkGray
            $keep += $ln
        }
        if ($changed) {
            [System.IO.File]::WriteAllText($af.FullName, ($keep -join "`r`n"),
                (New-Object System.Text.UTF8Encoding($true)))
            $touched++
        }
    }
    # 補登（L91）：NN 檔未被 checklist＋歸檔任何一行提及＝歷史歸檔寫失的
    # 孤兒登記（實案：59 輪流水中某次歸檔漏寫，該列永久蒸發、無人察覺）。
    # 完整檔補已勾列、缺章節檔補未勾列（續查），下輪 audit 照常處理。
    $toRegister = @()
    if ($null -ne $checklistOnly) {
        foreach ($n in $nnNames) {
            if ($checklistSrc.IndexOf($n, [StringComparison]::OrdinalIgnoreCase) -ge 0) { continue }
            $title = [IO.Path]::GetFileNameWithoutExtension($n)
            if ($nnText.ContainsKey($n) -and $nnText[$n] -match '(?m)^#\s+(.+)$') { $title = $Matches[1].Trim() }
            $complete = $true
            if ($nnText.ContainsKey($n)) {
                foreach ($sec in $requiredSections) {
                    if ($nnText[$n] -notmatch (Get-SectionAnchor $sec)) { $complete = $false; break }
                }
            }
            $tick = if ($complete) { "x" } else { " " }
            $toRegister += ("- [$tick] " + $title + " → " + $n + "（歸檔遺失補登）")
            Write-Host "  [補登] ${n}：未被任何一行提及——補$(if ($complete) { '已勾' } else { '未勾（缺章節，續查）' })登記列" -ForegroundColor Yellow
        }
    }
    if (($toGaps.Count + $toProgress.Count + $toRegister.Count) -gt 0 -and (Test-Path -LiteralPath $checklistPath)) {
        $clRaw = Get-Content $checklistPath -Raw -Encoding UTF8
        if ($null -eq $clRaw) { $clRaw = "" }
        # 節標題消失時自建（issue #6／L93）：修復路徑不得寄生在會消失的節點上
        # ——標題被吃掉時原本只 WARN「N 列未寫入」，等於 FixArchive 也修不動
        if (($toProgress.Count + $toRegister.Count) -gt 0 -and $clRaw -notmatch '(?m)^##\s*調查進度') {
            $clRaw = $clRaw.TrimEnd() + "`r`n`r`n## 調查進度`r`n"
            Write-Host "  已重建「## 調查進度」節標題（原標題被吃掉）" -ForegroundColor Yellow
        }
        if ($toGaps.Count -gt 0 -and $clRaw -notmatch '(?m)^##\s*Gaps') {
            $clRaw = $clRaw.TrimEnd() + "`r`n`r`n## Gaps 彙整（隨深查更新）`r`n"
            Write-Host "  已重建「## Gaps 彙整」節標題（原標題被吃掉）" -ForegroundColor Yellow
        }
        $out = @()
        $doneG = $false
        $doneP = $false
        foreach ($ln in ($clRaw -split "`r?`n")) {
            $out += $ln
            if (-not $doneP -and ($toProgress.Count + $toRegister.Count) -gt 0 -and $ln -match '^##\s*調查進度') {
                foreach ($r in $toProgress) { $out += $r }
                foreach ($r in $toRegister) { $out += $r }
                $doneP = $true
            }
            if (-not $doneG -and $toGaps.Count -gt 0 -and $ln -match '^##\s*Gaps') {
                foreach ($r in $toGaps) { $out += ("- （自歸檔回收，稽核輪次 $clRound）" + $r) }
                $doneG = $true
            }
        }
        if (($toProgress.Count + $toRegister.Count) -gt 0 -and -not $doneP) { Write-Host "  WARN：找不到「## 調查進度」節，$($toProgress.Count + $toRegister.Count) 列未寫入" -ForegroundColor Red }
        if ($toGaps.Count -gt 0 -and -not $doneG) { Write-Host "  WARN：找不到「## Gaps 彙整」節，$($toGaps.Count) 列未回收" -ForegroundColor Red }
        if ($doneG -or $doneP) {
            [System.IO.File]::WriteAllText($checklistPath, ($out -join "`r`n"),
                (New-Object System.Text.UTF8Encoding($true)))
            Write-Host "  checklist.md：搬回進度 $($toProgress.Count) 列、補登 $($toRegister.Count) 列、回收進 Gaps $($toGaps.Count) 列" -ForegroundColor Green
        }
    }
    Write-Host "=== 處置結束：改動 $touched 個歸檔檔；請重跑 lint 確認 ===" -ForegroundColor Cyan
    Write-Host ""
}

exit $exitCode
