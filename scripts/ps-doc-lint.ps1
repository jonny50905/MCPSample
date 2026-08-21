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
    [switch]$CoverageOnly
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

# 記分卡定位（L36）：**以結構找表，不綁章節名**——模型會自創標題
# （實例：「本輪已完成檔案總覽」取代「總覽記分卡」，資料完整只是換了格子）。
# 畢業門要驗的是「全量覆蓋」這個事實，不是標題字串；標題飄移留警告即可
# （L23：資料在就不追殺），否則純命名問題＝無修復管道的畢業活鎖。
# 候選章節優先取標題含記分卡類關鍵字者；都沒有才退回「排除明細類」全表掃描。
function Get-ScorecardCoverage {
    param([string]$AuditText, $NnNames)
    $best = @{ Covered = -1; Missing = @($NnNames); Heading = '(無章節)' }
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
    $cands = @($sections | Where-Object { $_.Heading -match '(記分卡|總覽|檔案清單|scorecard)' })
    if ($cands.Count -eq 0) {
        $cands = @($sections | Where-Object { $_.Heading -notmatch '(明細|回灌|系統性|完整性|覆核)' })
    }
    if ($cands.Count -eq 0) { $cands = $sections }
    foreach ($sec in $cands) {
        $miss = @($NnNames | Where-Object {
                $sec.Body -notmatch [regex]::Escape([IO.Path]::GetFileNameWithoutExtension($_))
            })
        $cov = $NnNames.Count - $miss.Count
        if ($cov -gt $best.Covered) {
            $best = @{ Covered = $cov; Missing = $miss; Heading = $sec.Heading }
        }
    }
    return $best
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
    foreach ($af in $archiveFiles) {
        $afText = Get-Content $af.FullName -Raw -Encoding UTF8
        if ($null -eq $afText) { $afText = "" }
        $untickedInArchive = @([regex]::Matches($afText, '(?m)^\s*-\s*\[ \]')).Count
        if ($untickedInArchive -gt 0) {
            $violations += "$($af.Name)：含 $untickedInArchive 個未打勾項——歸檔只准搬已勾項（未勾項被搬走＝調查進度隱形消失）"
        }
        $checklistSrc += "`n" + $afText
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
            if (-not $listed.ContainsKey($_.Name)) {
                $violations += "檔案未列於調查進度 checklist：$($_.Name)"
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
$requiredSections = @('## 功能定位', '## 行為邏輯', '## 資料流', '## 未解事項', '## Evidence 附錄')
$uuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
$nnNames = @()
$truncatedIds = @()
$missingIds = @()   # 檔案行號型缺 chunk id——與縮寫 id 同進手術單（修法同形）
$pendingSqlRows = @()   # 明寫「待人工SQL」的列＝合法待辦出口，不算違規但要點名
$misplacedRefRows = @()  # 同列有證據、但機器參照欄放的是標籤（欄位錯放，非缺證據）

Get-ChildItem -LiteralPath $dir -Filter "*.md" |
    Where-Object { $_.Name -match '^\d\d-' -and $_.Name -notmatch '^(00|90)-' } |
    ForEach-Object {
        $name = $_.Name
        $nnNames += $name
        $text = Get-Content $_.FullName -Raw -Encoding UTF8
        # 空檔防護：0 byte 檔 Get-Content -Raw 回 null，[regex]::Matches 會丟例外
        # 中斷整條掃描 pipeline（其餘檔案被靜默跳過）——強殺半寫正是這個樣子
        if ([string]::IsNullOrEmpty($text)) {
            $violations += "${name}：空檔（0 byte／無內容）——疑似寫入中斷，無法檢查"
            return
        }

        foreach ($sec in $requiredSections) {
            if ($text -notmatch [regex]::Escape($sec)) {
                $violations += "${name}：缺章節「$sec」"
            }
        }

        if ($text -notmatch 'CONFIRMED|INFERRED|DYNAMIC_RUNTIME') {
            $violations += "${name}：行為邏輯無任何 confidence 標註"
        }

        # 章節空心檢查（L33）：「缺章節」只驗標題存在——空殼檔（有標題
        # 無內容）會安靜通過；行為邏輯還有 confidence 代理間接抓到，
        # 資料流完全漏網。實案：劣化 session 寫出雙空節的空殼檔。
        foreach ($sec in @('## 行為邏輯', '## 資料流')) {
            $secIdx = $text.IndexOf($sec)
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
                }
            }
        }

        # 已知的自編 id 樣式（歷史失敗模式）
        foreach ($m in [regex]::Matches($text, '\b(SQL-[A-Z]+-\d+|CHK-[A-Z]+-\d+)\b')) {
            $violations += "${name}：出現自編 id 樣式：$($m.Value)"
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
        $evIdx = $text.IndexOf('## Evidence 附錄')
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
        if ($StrictAudit) { $violations += $msg } else { $warnings += $msg }
    }
    # 輪次一致性（L28）：報告輪次 ≠ checklist 輪次＝報告可能是舊輪——
    # 「稽核沒跑過但看到全綠」的正解就是這個檢查
    $auditRoundNum = -1
    foreach ($m in [regex]::Matches($auditText, '稽核輪次[：:]\s*([0-9]+)')) {
        $auditRoundNum = [int]$m.Groups[1].Value
    }
    if ($clRound -ge 0 -and $auditRoundNum -ge 0 -and $auditRoundNum -ne $clRound) {
        $msg = "90-audit.md 輪次（$auditRoundNum）與 checklist 輪次（$clRound）不一致——報告可能是舊輪重驗前的殘留，綠燈不可信"
        if ($StrictAudit) { $violations += $msg } else { $warnings += $msg }
    }
    # 全量對帳（L36 結構化）：找「涵蓋最多 NN 檔」的章節當記分卡，驗是否覆蓋
    # 全部——標題叫什麼不重要，覆蓋率才是塌縮判準（自創標題不再擋畢業）
    $cover = Get-ScorecardCoverage -AuditText $auditText -NnNames $nnNames
    if ($nnNames.Count -gt 0 -and $cover.Missing.Count -gt 0) {
        $msg = "90-audit.md：記分卡未涵蓋 $($cover.Missing.Count) 個檔案（最佳章節「$($cover.Heading)」覆蓋 $($cover.Covered)/$($nnNames.Count)；範圍塌縮跡象——稽核未全量重驗）：$($cover.Missing -join '、')"
        # 塌縮＝稽核沒跑完，屬「有沒有做完」不是「證據精不精修」——tier 1 門
        # （CoverageOnly）必須看得見，否則只驗兩檔的稽核也能拿覆蓋畢業。
        # 手動執行（無開關）仍維持警告不擋（SOP-2）。
        if ($StrictAudit -or $CoverageOnly) { $violations += $msg } else { $warnings += $msg }
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
    foreach ($f in $allMd) {
        $t = Get-Content $f.FullName -Raw -Encoding UTF8
        if ([string]::IsNullOrEmpty($t)) { continue }   # 空檔已於前段記違規，斷鏈掃描跳過
        foreach ($m in [regex]::Matches($t, '\[\[([^\]|#]+)')) {
            $target = $m.Groups[1].Value.Trim()
            $referenced[$target] = $true
            if (-not $noteNames.ContainsKey($target)) {
                $warnings += "$($f.Name)：wikilink 目標不存在：[[${target}]]"
            }
        }
    }
    foreach ($n in $wikiNotes) {
        $entity = [IO.Path]::GetFileNameWithoutExtension($n.Name)
        if (-not $referenced.ContainsKey($entity)) {
            $warnings += "wiki/$($n.Name)：孤兒 entity（沒有任何 [[${entity}]] 入鏈）"
        }
    }
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
}

# 證據修復指令（縮寫 id＋機器參照無效同一張單）——放「最後」印，
# 才不會被警告牆洗出畫面。L42：工單**先判型別再給修法**，不預設「去找 chunk」
# （失敗查詢／SQL 型證據被寫成「缺 id」會逼模型去做無解的事）。
$leakDelegable = @($leaks | Where-Object { $_.Delegable })
$leakManual = @($leaks | Where-Object { -not $_.Delegable })
if (($truncatedIds.Count + $missingIds.Count + $leakDelegable.Count + $misplacedRefRows.Count) -gt 0) {
    Write-Host ""
    Write-Host "=== 證據修復指令（複製整段貼給 PS-DEEP-RESEARCH；超過 7 筆請分批貼）===" -ForegroundColor Cyan
    Write-Host "以下是 lint 確認的問題清單，逐筆修復、一次一筆、一筆都不准跳："
    Write-Host "（[欄位] 型已按檔合併＝一個檔一個任務；[洩漏]／[證據] 型逐列）"
    $i = 0
    foreach ($t in $leakDelegable) {
        $i++
        Write-Host "$i. [洩漏] $($t.File):$($t.Line)：$($t.Marker)"
    }
    # [欄位] 型按**檔**合併成一個任務：對調欄位是純編輯，一個檔一次改完最省
    # ——逐列開單會把 30 列變成 30 個任務，而 auto-loop 一圈只吃 7 筆（實案：
    # 錯放 30 餘列，逐列開單要 5 圈、每圈還先燒一個稽核 session）
    $swapByFile = @{}
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
    Write-Host ""
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
    if ($misplacedRefRows.Count -gt 0) {
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
    Write-Host " C. A 與 B 都取不到 → 該列移除、主張降級 INFERRED、"
    Write-Host "    未解事項記一行查法收據（查了什麼、怎麼查、結果）"
    Write-Host ""
    Write-Host "全部完成後輸出收據，每筆一行：欄位型「檔:行 → 已對調（機器參照欄現為 <id 或 SELECT 前 20 字>）」；"
    Write-Host "洩漏型「檔:行 → 已清除＋補回<內容>」或"
    Write-Host "「檔:行 → 已清除，<章節>內容遺失已記未解事項」；證據型「舊值 → 新完整UUID」"
    Write-Host "或「舊值 → SQL：SELECT…」或「舊值 → 移除入 gaps」或「舊值 → 待人工SQL」。"
    Write-Host "沒有收據＝沒完成。現在從第 1 筆開始。"
    Write-Host "=== 指令結束 ===" -ForegroundColor Cyan
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

exit $exitCode
