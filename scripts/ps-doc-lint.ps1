# ps-doc-lint.ps1 — deep-research 文件的確定性格式稽核（第 1 層 lint）
# 用法：.\scripts\ps-doc-lint.ps1 -Domain 轉職
#       .\scripts\ps-doc-lint.ps1 -Domain 轉職 -StrictAudit
# -StrictAudit＝auto-loop 畢業門專用（issue #2）：90-audit.md 的結構性問題
# （缺檔／缺模板章節／缺輪次表頭／記分卡範圍塌縮）由警告升為 FAIL。
# 手動執行不加此開關——維持警告不擋（SOP-2）。wiki 類警告任何模式都不升級
# （跨領域共用層，會讓 A 領域的畢業被 B 領域的斷鏈鎖死）。
# 檢查：checklist 對帳、必要章節、confidence 標註、ChunkId UUID 格式、可疑自編 id
param(
    [Parameter(Mandatory = $true)][string]$Domain,
    [switch]$StrictAudit
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

# 以 script 所在位置反推 repo 根目錄——任何工作目錄都能跑
$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path $root (Join-Path "docs/ps-research" $Domain)
$violations = @()
$warnings = @()

if (-not (Test-Path $dir)) {
    Write-Error "目錄不存在：$dir"
    exit 2
}

$overviewPath = Join-Path $dir "00-overview.md"
$checklistPath = Join-Path $dir "checklist.md"
if (-not (Test-Path $overviewPath)) {
    # 缺檔違規必附近似檔名收據（L24「查無必附查法收據」用回 lint 自己身上）：
    # 假缺（檔名污染/雙副檔名）與真缺（SOP-4 還原）給出可分辨的訊息
    $near = @(Get-ChildItem -LiteralPath $dir -Force -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*overview*" })
    if ($near.Count -gt 0) {
        $violations += "缺 00-overview.md（但找到近似檔名：$(($near | ForEach-Object { $_.Name }) -join '、')——檔名污染？跑 ps-fs-doctor）"
    }
    else {
        $violations += "缺 00-overview.md（近似檔名掃描也無——真缺檔，走 SOP-4 還原）"
    }
}

# 進度已拆檔：新格式在 checklist.md；舊格式（進度仍在 overview 內）自動相容。
# 對帳不再包在「overview 存在」分支裡（L28：一項缺檔違規不得遮蔽其餘檢查——
# 假缺 overview 曾讓「無遺失」整輪不可證）
$checklistOnly = $null
if (Test-Path $checklistPath) {
    $checklistOnly = Get-Content $checklistPath -Raw -Encoding UTF8
    if ($null -eq $checklistOnly) { $checklistOnly = "" }   # 空檔防護：0 byte 也要進對帳
}
elseif (Test-Path $overviewPath) {
    $checklistOnly = Get-Content $overviewPath -Raw -Encoding UTF8
    if ($null -eq $checklistOnly) { $checklistOnly = "" }
}
$clRound = -1
if ($null -ne $checklistOnly) {
    foreach ($m in [regex]::Matches($checklistOnly, '稽核輪次[：:]\s*([0-9]+)')) {
        $clRound = [int]$m.Groups[1].Value
    }
}
if (Test-Path $checklistPath) {
    # checklist 模板節標題必須存在——標題整個消失＝破壞性覆寫指紋
    # （row 清空可以是合法歸檔後狀態，節標題消失不是）
    $clHead = if ($null -eq $checklistOnly) { "" } else { $checklistOnly }
    foreach ($sec in @('## 調查進度', '## Gaps 彙整')) {
        if ($clHead -notmatch [regex]::Escape($sec)) {
            $violations += "checklist.md：缺節標題「$sec」（破壞性覆寫指紋——row 清空可為歸檔後合法狀態，節標題消失不是）"
        }
    }
}
if ($null -ne $checklistOnly) {
    $checklistSrc = $checklistOnly
    # 已打勾項會歸檔到 checklist-archive*.md（每輪一個分片檔）——對帳時全部合併看；
    # archive 只准收已打勾項——未勾項被搬走＝進度隱形消失（L28）
    $archiveFiles = @(Get-ChildItem -Path $dir -Filter "checklist-archive*.md" -File -ErrorAction SilentlyContinue)
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
        if ($m.Groups['tick'].Value -eq 'x' -and -not (Test-Path (Join-Path $dir $f))) {
            $violations += "checklist 已打勾但檔案不存在：$f"
        }
    }
    Get-ChildItem $dir -Filter "*.md" |
        Where-Object { $_.Name -match '^\d\d-' -and $_.Name -notmatch '^(00|90)-' } |
        ForEach-Object {
            if (-not $listed.ContainsKey($_.Name)) {
                $violations += "檔案未列於調查進度 checklist：$($_.Name)"
            }
        }
}

# 2) 每個 NN 檔的內容檢查
$requiredSections = @('## 功能定位', '## 行為邏輯', '## 資料流', '## 未解事項', '## Evidence 附錄')
$uuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
$nnNames = @()
$truncatedIds = @()

Get-ChildItem $dir -Filter "*.md" |
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

        # 模型內部標記洩漏（chat template 未對齊時會漏進輸出）
        foreach ($m in [regex]::Matches($text, '</?think(ing)?>|<\|im_(start|end)\|>')) {
            $violations += "${name}：模型內部標記洩漏（污染）：$($m.Value)"
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
            # 章節存在但「內容空白」也是違規（有標題沒證據＝沒證據）
            if ($evText -notmatch '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-' -and
                $evText -notmatch '(?i)\bSQL\b') {
                $violations += "${name}：Evidence 附錄空白（有章節標題但無任何 chunk id／SQL 證據）"
            }
            foreach ($line in ($evText -split "`n")) {
                if ($line -match '^\|' -and $line -notmatch '^\|[\s:|-]+$' -and
                    $line -match '[:：]\d+' -and
                    $line -notmatch '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-' -and
                    $line -notmatch '(?i)\bSQL\b') {
                    $violations += "${name}：Evidence 列為檔案行號型但缺 chunk id：$($line.Trim().Substring(0, [Math]::Min(60, $line.Trim().Length)))…"
                }
            }
        }
    }

# 2.5) 90-audit.md 模板符合度（每輪稽核會重寫，偏離記警告不擋；
#      -StrictAudit 時本節的結構性問題升為違規——僅限本節，wiki 類不升級）
$auditPath = Join-Path $dir "90-audit.md"
if (Test-Path $auditPath) {
    $auditText = Get-Content $auditPath -Raw -Encoding UTF8
    if ($null -eq $auditText) { $auditText = "" }   # 空檔＝全部章節缺（不炸例外）
    $auditSections = @('## 總覽記分卡', '## FAIL / DISPUTED / UNVERIFIABLE 明細',
        '## 上輪回灌項覆核', '## 完整性（換角度 diff）',
        '## 已回灌 checklist 的行動項', '## 系統性錯誤觀察')
    foreach ($sec in $auditSections) {
        if ($auditText -notmatch [regex]::Escape($sec)) {
            $msg = "90-audit.md：缺模板章節「$sec」（報告偏離模板，對帳會失準）"
            if ($StrictAudit) { $violations += $msg } else { $warnings += $msg }
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
    # 全量對帳：每個 NN 檔都必須出現在稽核報告內文（記分卡一檔一列）
    $missingRows = @($nnNames | Where-Object { $auditText -notmatch [regex]::Escape($_) })
    if ($missingRows.Count -gt 0) {
        $warnings += "90-audit.md：記分卡缺 $($missingRows.Count) 個檔案列（範圍塌縮跡象——稽核未全量重驗）：$($missingRows -join '、')"
    }
    if ($StrictAudit) {
        # 畢業門版全量對帳：只認「## 總覽記分卡」章節內的列——檔名出現在
        # FAIL 明細／回灌節不算覆蓋（防塌縮漏判）；檔名接受含/不含 .md（防誤殺）
        $scIdx = $auditText.IndexOf('## 總覽記分卡')
        if ($scIdx -ge 0) {
            $scText = $auditText.Substring($scIdx)
            $nextIdx = $scText.IndexOf("`n## ", 1)
            if ($nextIdx -gt 0) { $scText = $scText.Substring(0, $nextIdx) }
            $scMissing = @($nnNames | Where-Object {
                    $scText -notmatch [regex]::Escape([IO.Path]::GetFileNameWithoutExtension($_))
                })
            if ($scMissing.Count -gt 0) {
                $violations += "90-audit.md：總覽記分卡章節內缺 $($scMissing.Count) 個檔案列（StrictAudit——記分卡＝本輪全量重驗）：$($scMissing -join '、')"
            }
        }
        # 缺「## 總覽記分卡」章節本身已在上方升為違規，不重複記
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

# 縮寫 id 的手術式修復指令——放「最後」印，才不會被警告牆洗出畫面
if ($truncatedIds.Count -gt 0) {
    Write-Host ""
    Write-Host "=== 手術式修復指令（複製整段貼給 PS-DEEP-RESEARCH；超過 7 筆請分批貼）===" -ForegroundColor Cyan
    Write-Host "以下是 lint 確認的縮寫 ChunkId 清單，逐筆修復、一次一筆、一筆都不准跳："
    $i = 0
    foreach ($t in $truncatedIds) {
        $i++
        Write-Host "$i. $($t.File)：$($t.Id)"
    }
    Write-Host "每筆固定流程：read 該檔找到該筆 evidence 的 filePath 與行號"
    Write-Host "→ 委派對應 flow subagent 用 filePath 重取該段"
    Write-Host "（搜檔 → get_file_structure → get_chunks_details）"
    Write-Host "→ 用「工具回傳的完整 ChunkId」更新該筆（僅改該 id，其他一字不動）。"
    Write-Host "全部完成後輸出收據：每筆一行「舊8碼 → 新完整UUID」對照表。"
    Write-Host "沒有收據＝沒完成。現在從第 1 筆開始。"
    Write-Host "=== 指令結束 ===" -ForegroundColor Cyan
    Write-Host ""
}

exit $exitCode
