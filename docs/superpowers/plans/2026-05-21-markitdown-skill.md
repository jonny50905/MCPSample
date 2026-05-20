# markitdown Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a project-level Claude Code skill at `.claude/skills/markitdown/SKILL.md` that converts AIP-labeled Office files (Word/Excel/PowerPoint) to Markdown via Office COM + Microsoft markitdown CLI.

**Architecture:** Single `SKILL.md` file containing decision tables and inline PowerShell snippets for Claude to adapt. Workflow: validate prereqs → first-run discovery to populate `config.json` (AIP label GUIDs + downgrade policy) → for each source file, Office COM opens it, downgrades label per policy, `SaveAs2` to a mirrored `.tmp\` path, then `markitdown <tmp> -o <final>`. Batch mode reuses one COM instance per Office app across all files of that extension.

**Tech Stack:** Markdown (SKILL.md content), Windows PowerShell 7+, Microsoft markitdown CLI (`pip install 'markitdown[all]'`), Office COM (`Word.Application` / `Excel.Application` / `PowerPoint.Application`), Microsoft 365 `SensitivityLabel` API.

**Spec:** [docs/superpowers/specs/2026-05-21-markitdown-skill-design.md](../specs/2026-05-21-markitdown-skill-design.md)

**Repo state note:** This project is **not currently a git repo** (per environment scan). Plan replaces git commits with "save & continue" checkpoints. If user later runs `git init`, all artifacts created by this plan will be tracked except `.claude/skills/markitdown/config.json` (excluded via Task 1).

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `D:\TMP\MCPDemo\.claude\skills\markitdown\` | Create dir | Skill folder |
| `D:\TMP\MCPDemo\.claude\skills\markitdown\SKILL.md` | Create | Sole artifact Claude reads at trigger time |
| `D:\TMP\MCPDemo\.claude\skills\markitdown\config.json` | Created at first-run (NOT in this plan) | Tenant-specific label GUIDs + policy |
| `D:\TMP\MCPDemo\.gitignore` | Modify | Add `config.json` exclusion |

User-provided verification samples (NOT created by this plan, needed for Task 10 smoke test):
- One `.docx` labeled `C-internal`
- One `.xlsx` labeled `C-external`
- One `.pptx` labeled `B` (or any tier that should be policy-forbidden)
- One file with a label NOT yet enumerated (to verify `unknown-source-label` path)

---

### Task 1: Skill directory + .gitignore exclusion

**Files:**
- Create: `D:\TMP\MCPDemo\.claude\skills\markitdown\` (directory)
- Modify: `D:\TMP\MCPDemo\.gitignore`

- [ ] **Step 1: Create skill directory**

Run:
```powershell
New-Item -ItemType Directory -Force "D:\TMP\MCPDemo\.claude\skills\markitdown" | Out-Null
Test-Path "D:\TMP\MCPDemo\.claude\skills\markitdown"
```
Expected: `True`

- [ ] **Step 2: Read existing `.gitignore`**

Use Read tool on `D:\TMP\MCPDemo\.gitignore` to know current contents.

- [ ] **Step 3: Append exclusion for config.json**

Use Edit tool to append (no replacement — pure append). Add these three lines to the end:

```
# markitdown skill — tenant-specific AIP label GUIDs
.claude/skills/markitdown/config.json
.claude/skills/markitdown/.tmp/
```

- [ ] **Step 4: Verify the gitignore update**

Run:
```powershell
Get-Content "D:\TMP\MCPDemo\.gitignore" -Tail 3
```
Expected output contains the three lines from Step 3.

- [ ] **Step 5: Save & continue**

(No git in repo. Move on.)

---

### Task 2: SKILL.md skeleton — frontmatter + decision table

**Files:**
- Create: `D:\TMP\MCPDemo\.claude\skills\markitdown\SKILL.md`

- [ ] **Step 1: Write the file with frontmatter and section 1**

Use Write tool to create the file with exactly this content (don't append later sections yet — they come in subsequent tasks):

````markdown
---
name: markitdown
description: Use when the user wants to convert Office documents (.xlsx / .xls / .docx / .doc / .pptx) to Markdown, or to read these documents' content as Markdown. Covers single-file conversion and batch conversion of all Office files under a folder (recursive). Source files are assumed to carry AIP sensitivity labels; the skill drives Office COM to produce unprotected copies before invoking markitdown. Outputs to D:\MarkItDownOutPut\ mirroring source relative folder structure.
---

# Office → Markdown (markitdown CLI + AIP-aware)

把 Office 檔案（Word / Excel / PowerPoint）轉成 Markdown。**所有來源檔可能帶 AIP sensitivity label**，本 skill 用 Office COM 先解密為無保護副本，再呼叫 `markitdown` CLI 完成轉換。

## 何時用這個 skill

| 使用者說 | 是否觸發 |
|---|---|
| 「把 D:\Reports\Q1.xlsx 轉成 markdown」 | ✅ |
| 「D:\Reports\ 底下所有 Excel/Word 都轉成 markdown」 | ✅ 批次 |
| 「讀一下這份 .docx 的內容」 | ✅ 轉完後 Read 輸出檔回覆 |
| 「把 PDF 轉成 markdown」 | ❌ 不在本 skill 範圍 |
| 「寫一份 markdown 報告」 | ❌ 沒有 Office 來源檔 |

## 支援的副檔名

| 副檔名 | 對應 COM app |
|---|---|
| `.xlsx`, `.xls` | `Excel.Application` |
| `.docx`, `.doc` | `Word.Application` |
| `.pptx` | `PowerPoint.Application` |

範圍外（PDF / HTML / 圖片 / 音訊等）不處理 — 若使用者要求，請改用其他工具。
````

- [ ] **Step 2: Verify file written correctly**

Run:
```powershell
Get-Content "D:\TMP\MCPDemo\.claude\skills\markitdown\SKILL.md" -TotalCount 5
```
Expected: first line `---`, second line `name: markitdown`, third line starts with `description: Use when`.

- [ ] **Step 3: Save & continue**

---

### Task 3: Prerequisites section + prereq PowerShell helper

**Files:**
- Modify: `D:\TMP\MCPDemo\.claude\skills\markitdown\SKILL.md` (append)

- [ ] **Step 1: Append "前置條件" section**

Use Edit tool to append to the end of SKILL.md (after Task 2's content):

````markdown

## 前置條件（每次轉換前驗證一次）

三項都過才能繼續，任一失敗即中止並回報。

1. **markitdown CLI 已安裝** — `markitdown --version` 成功
2. **Office desktop 可用** — Word COM `New-Object -ComObject Word.Application` 不拋例外
3. **config.json 存在** — `.claude/skills/markitdown/config.json` 已由探索模式產生

把以下 PowerShell 給使用者跑（或 Claude 自行用 Bash/PowerShell 工具呼叫）：

```powershell
function Test-MarkitdownPrereqs {
    # 1. markitdown CLI
    $null = & markitdown --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "markitdown CLI 未安裝。請執行: pip install 'markitdown[all]'"
    }

    # 2. Office COM (用 Word 探測)
    try {
        $probe = New-Object -ComObject Word.Application
        $probe.Quit()
        [void][System.Runtime.Interopservices.Marshal]::ReleaseComObject($probe)
    } catch {
        throw "Office desktop (Word) 未安裝或非 COM 可用版本: $_"
    }

    # 3. config.json
    $cfgPath = "D:\TMP\MCPDemo\.claude\skills\markitdown\config.json"
    if (-not (Test-Path $cfgPath)) {
        Write-Warning "config.json 不存在 — 請先跑「探索模式」(見下方段落)"
        return $null
    }
    return Get-Content $cfgPath -Raw | ConvertFrom-Json
}
```
````

- [ ] **Step 2: Verify section appended**

Run:
```powershell
Select-String -Path "D:\TMP\MCPDemo\.claude\skills\markitdown\SKILL.md" -Pattern "Test-MarkitdownPrereqs" -SimpleMatch
```
Expected: one match line.

- [ ] **Step 3: Save & continue**

---

### Task 4: Output rules section

**Files:**
- Modify: `D:\TMP\MCPDemo\.claude\skills\markitdown\SKILL.md` (append)

- [ ] **Step 1: Append "輸出規則" section**

Use Edit tool to append:

````markdown

## 輸出規則

| 模式 | 輸出位置 |
|---|---|
| 單檔 | `D:\MarkItDownOutPut\<basename>.md` |
| 批次（指定 `$SourceRoot`） | `D:\MarkItDownOutPut\<rel-path>\<basename>.md`（鏡像來源相對路徑） |

範例：
- 來源 `D:\Reports\Q1\Sales\jan.xlsx`，`$SourceRoot = D:\Reports`
- 輸出 = `D:\MarkItDownOutPut\Q1\Sales\jan.md`

**規則：**
- 輸出根 `D:\MarkItDownOutPut\` 不存在時自動建立。
- 同名輸出檔**直接覆寫**（一致、可重跑；要保留舊版請使用者自備份）。

### 中繼檔（COM 解密產物）

- 中繼根：`D:\MarkItDownOutPut\.tmp\`
- 命名：鏡像來源相對路徑，basename 加 `.unprotected` 中綴
  - 例：來源 `D:\Reports\Q1\Sales\jan.xlsx` → 中繼 `D:\MarkItDownOutPut\.tmp\Q1\Sales\jan.unprotected.xlsx`
- 轉換成功即刪除；失敗保留供 debug。
````

- [ ] **Step 2: Verify**

Run:
```powershell
Select-String -Path "D:\TMP\MCPDemo\.claude\skills\markitdown\SKILL.md" -Pattern "MarkItDownOutPut\\\.tmp" -SimpleMatch
```
Expected: at least one match.

- [ ] **Step 3: Save & continue**

---

### Task 5: AIP label policy + config.json schema documentation

**Files:**
- Modify: `D:\TMP\MCPDemo\.claude\skills\markitdown\SKILL.md` (append)

- [ ] **Step 1: Append "AIP Label 政策" section**

Use Edit tool to append:

````markdown

## AIP Label 政策（核心）

來源檔可能標為不同 tier（如 `A` / `B` / `C-internal` / `C-external`）。markitdown 無法讀取加密檔，所以 skill 必須先把 label 降到 **`unprotected_target`**（預設 `C-external`），再 `SaveAs2` 為無保護副本。

降階規則由 `config.json` 的 `allowed_downgrades` 控制 — 不在白名單的降階一律 fail（記入失敗清單），**不嘗試繞過**。

### `config.json` schema

```json
{
  "labels": {
    "A":          { "id": "<guid>", "name": "<display>" },
    "B":          { "id": "<guid>", "name": "<display>" },
    "C-internal": { "id": "<guid>", "name": "<display>" },
    "C-external": { "id": "<guid>", "name": "<display>" }
  },
  "unprotected_target": "C-external",
  "allowed_downgrades": [
    { "from": "C-internal", "to": "C-external" }
  ]
}
```

> `config.json` 已加入 `.gitignore`，不入版控（label GUID 屬租戶隱私）。

### Justification 文字

`SetLabel` 第二參數固定為：
`"Convert to Markdown via markitdown skill"`

每次降階都會在 M365 audit log 留一筆紀錄。
````

- [ ] **Step 2: Verify section appended**

Run:
```powershell
Select-String -Path "D:\TMP\MCPDemo\.claude\skills\markitdown\SKILL.md" -Pattern "allowed_downgrades" -SimpleMatch | Measure-Object | Select-Object -ExpandProperty Count
```
Expected: ≥ 2 (一次出現在說明、一次出現在 JSON 範例).

- [ ] **Step 3: Save & continue**

---

### Task 6: Discovery mode (first-run setup) section

**Files:**
- Modify: `D:\TMP\MCPDemo\.claude\skills\markitdown\SKILL.md` (append)

- [ ] **Step 1: Append "探索模式" section**

Use Edit tool to append:

````markdown

## 探索模式（first-run setup）

`config.json` 不存在時，Claude 必須先帶使用者跑探索模式，把 label GUID 蒐齊。

**互動腳本**（Claude 透過 PowerShell 工具呼叫，逐欄問使用者）：

```powershell
function Start-MarkitdownDiscovery {
    $cfgPath = "D:\TMP\MCPDemo\.claude\skills\markitdown\config.json"
    if (Test-Path $cfgPath) {
        Write-Warning "config.json 已存在: $cfgPath。如要重做請先備份/移除。"
        return
    }

    $config = [ordered]@{
        labels             = [ordered]@{}
        unprotected_target = $null
        allowed_downgrades = @()
    }

    $word = New-Object -ComObject Word.Application
    $word.Visible       = $false
    $word.DisplayAlerts = 0

    Write-Host "請逐 tier 提供一份 sample .docx（Enter 跳過）"
    foreach ($tier in @('A', 'B', 'C-internal', 'C-external')) {
        $path = Read-Host "Sample for tier '$tier'"
        if (-not $path) { continue }
        if (-not (Test-Path $path)) { Write-Warning "找不到 $path"; continue }
        try {
            $doc = $word.Documents.OpenNoRepairDialog($path, $false, $true)
            $lbl = $doc.SensitivityLabel.GetLabel()
            $config.labels[$tier] = [ordered]@{
                id   = $lbl.LabelId
                name = $lbl.LabelName
            }
            Write-Host "  ✓ $tier = $($lbl.LabelName) [$($lbl.LabelId)]"
            $doc.Close($false)
        } catch {
            Write-Warning "讀 $path label 失敗: $_"
        }
    }

    $word.Quit()
    [void][System.Runtime.Interopservices.Marshal]::ReleaseComObject($word)

    $tgt = Read-Host "unprotected_target tier 名稱（預設 C-external）"
    if (-not $tgt) { $tgt = 'C-external' }
    $config.unprotected_target = $tgt

    Write-Host "輸入 allowed_downgrades，每行 'from->to'，空行結束："
    while ($true) {
        $line = Read-Host "  >"
        if (-not $line) { break }
        $parts = $line -split '\s*->\s*'
        if ($parts.Length -ne 2) { Write-Warning "格式錯誤，略過"; continue }
        $config.allowed_downgrades += [ordered]@{ from = $parts[0]; to = $parts[1] }
    }

    $config | ConvertTo-Json -Depth 4 | Set-Content $cfgPath -Encoding UTF8
    Write-Host "`n寫入: $cfgPath"
    Write-Host "提醒：請拿一份 unprotected_target tier 的 sample 跑一次轉換，確認真的可解密。"
}
```

**驗證步驟**（探索完後立即執行，不通過就提示換 tier）：

```powershell
# 取一份標為 unprotected_target 的 sample，端到端跑一次
Convert-OfficeFile -SourcePath "<sample.docx>" `
                   -OutputPath "D:\MarkItDownOutPut\__verify.md" `
                   -TmpPath    "D:\MarkItDownOutPut\.tmp\__verify.unprotected.docx" `
                   -Config     (Get-Content (Join-Path $env:USERPROFILE 'placeholder') -Raw | ConvertFrom-Json)
# 預期：D:\MarkItDownOutPut\__verify.md 內容非空。若 markitdown 失敗 → unprotected_target 仍有加密，
# 請改設更低 tier 重來。
```

> `Convert-OfficeFile` 的定義在下節「用法 A：單檔」。
````

- [ ] **Step 2: Verify**

Run:
```powershell
Select-String -Path "D:\TMP\MCPDemo\.claude\skills\markitdown\SKILL.md" -Pattern "Start-MarkitdownDiscovery" -SimpleMatch
```
Expected: at least one match.

- [ ] **Step 3: Save & continue**

---

### Task 7: Single-file conversion section (用法 A) + Convert-OfficeFile function

**Files:**
- Modify: `D:\TMP\MCPDemo\.claude\skills\markitdown\SKILL.md` (append)

- [ ] **Step 1: Append "用法 A：單檔" section with full PowerShell**

Use Edit tool to append:

````markdown

## 用法 A：單檔

```powershell
function Convert-OfficeFile {
    param(
        [Parameter(Mandatory)] [string] $SourcePath,
        [Parameter(Mandatory)] [string] $OutputPath,
        [Parameter(Mandatory)] [string] $TmpPath,
        [Parameter(Mandatory)] [psobject] $Config,
        [psobject] $ComApp,        # 若已啟動可傳入；否則本函式自己起停
        [string]   $ComType        # 'Word' | 'Excel' | 'PowerPoint'；不傳則依副檔名推
    )

    $ext = ([IO.Path]::GetExtension($SourcePath)).ToLower()
    if (-not $ComType) {
        $ComType = switch ($ext) {
            '.doc'  { 'Word' }       '.docx' { 'Word' }
            '.xls'  { 'Excel' }      '.xlsx' { 'Excel' }
            '.pptx' { 'PowerPoint' }
            default { throw "不支援的副檔名: $ext" }
        }
    }

    $ownApp = $false
    if (-not $ComApp) {
        $progId = "$ComType.Application"
        $ComApp = New-Object -ComObject $progId
        $ComApp.Visible       = $false
        try { $ComApp.DisplayAlerts = 0 } catch {}
        $ownApp = $true
    }

    $justification = "Convert to Markdown via markitdown skill"

    try {
        # --- Open (ReadOnly=true) ---
        $doc = switch ($ComType) {
            'Word'       { $ComApp.Documents.OpenNoRepairDialog($SourcePath, $false, $true) }
            'Excel'      { $ComApp.Workbooks.Open($SourcePath, 0, $true) }
            'PowerPoint' { $ComApp.Presentations.Open($SourcePath, $true, $false, $false) }
        }

        # --- Read current label ---
        $sourceLabelId = $doc.SensitivityLabel.GetLabel().LabelId
        $sourceTier = $null
        foreach ($p in $Config.labels.PSObject.Properties) {
            if ($p.Value.id -eq $sourceLabelId) { $sourceTier = $p.Name; break }
        }
        if (-not $sourceTier) {
            throw [PSCustomObject]@{ Reason='unknown-source-label'; Detail=$sourceLabelId }
        }

        $target = $Config.unprotected_target

        # --- Apply downgrade if needed ---
        if ($sourceTier -ne $target) {
            $allowed = $false
            foreach ($d in $Config.allowed_downgrades) {
                if ($d.from -eq $sourceTier -and $d.to -eq $target) { $allowed = $true; break }
            }
            if (-not $allowed) {
                throw [PSCustomObject]@{ Reason='policy-forbidden'; Detail="$sourceTier -> $target" }
            }
            try {
                $doc.SensitivityLabel.SetLabel($Config.labels.$target.id, $justification)
            } catch {
                throw [PSCustomObject]@{ Reason='no-downgrade-rights'; Detail=$_.Exception.Message }
            }
        }

        # --- SaveAs2 to .tmp\ ---
        New-Item -ItemType Directory -Force (Split-Path $TmpPath) | Out-Null
        switch ($ComType) {
            'Word' {
                # 16 = wdFormatDocumentDefault (.docx), 0 = wdFormatDocument (.doc)
                $fmt = if ($ext -eq '.doc') { 0 } else { 16 }
                $doc.SaveAs2($TmpPath, $fmt)
                $doc.Close($false)
            }
            'Excel' {
                # 51 = xlOpenXMLWorkbook (.xlsx), 56 = xlExcel8 (.xls)
                $fmt = if ($ext -eq '.xls') { 56 } else { 51 }
                $doc.SaveAs($TmpPath, $fmt)
                $doc.Close($false)
            }
            'PowerPoint' {
                # 24 = ppSaveAsOpenXMLPresentation (.pptx)
                $doc.SaveAs($TmpPath, 24)
                $doc.Close()
            }
        }

        # --- markitdown ---
        New-Item -ItemType Directory -Force (Split-Path $OutputPath) | Out-Null
        $mdOut = & markitdown $TmpPath -o $OutputPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw [PSCustomObject]@{ Reason='markitdown-failed'; Detail=($mdOut -join "`n") }
        }

        # --- Cleanup tmp on success ---
        Remove-Item $TmpPath -Force -ErrorAction SilentlyContinue
    }
    finally {
        if ($ownApp) {
            try { $ComApp.Quit() } catch {}
            [void][System.Runtime.Interopservices.Marshal]::ReleaseComObject($ComApp)
        }
    }
}
```

**單檔典型呼叫：**

```powershell
$config = Test-MarkitdownPrereqs                                        # 含 config.json 讀取
if (-not $config) { throw "請先跑探索模式" }

$src    = "D:\Reports\Q1.xlsx"
$base   = [IO.Path]::GetFileNameWithoutExtension($src)
$out    = "D:\MarkItDownOutPut\$base.md"
$tmp    = "D:\MarkItDownOutPut\.tmp\$base.unprotected$([IO.Path]::GetExtension($src))"

Convert-OfficeFile -SourcePath $src -OutputPath $out -TmpPath $tmp -Config $config
Write-Host "完成 → $out"
```

若使用者意圖是「讀內容」（如「讀一下這份 .docx 的內容」），Claude 應在轉完後用 Read 工具讀 `$out`，再摘要回覆。
````

- [ ] **Step 2: Verify section appended**

Run:
```powershell
Select-String -Path "D:\TMP\MCPDemo\.claude\skills\markitdown\SKILL.md" -Pattern "function Convert-OfficeFile" -SimpleMatch
```
Expected: one match.

- [ ] **Step 3: Save & continue**

---

### Task 8: Batch conversion section (用法 B) + Convert-OfficeFolder function

**Files:**
- Modify: `D:\TMP\MCPDemo\.claude\skills\markitdown\SKILL.md` (append)

- [ ] **Step 1: Append "用法 B：批次" section**

Use Edit tool to append:

````markdown

## 用法 B：批次（資料夾遞迴）

```powershell
function Convert-OfficeFolder {
    param(
        [Parameter(Mandatory)] [string]   $SourceRoot,
        [Parameter(Mandatory)] [psobject] $Config,
        [string] $OutputRoot = "D:\MarkItDownOutPut",
        [string] $TmpRoot    = "D:\MarkItDownOutPut\.tmp"
    )

    $exts = @('.xlsx', '.xls', '.docx', '.doc', '.pptx')

    # 蒐集 + 過濾 ~$ 暫存
    $allFiles = Get-ChildItem -LiteralPath $SourceRoot -Recurse -File |
        Where-Object {
            $exts -contains $_.Extension.ToLower() -and
            -not $_.Name.StartsWith('~$')
        }

    if (-not $allFiles) {
        Write-Host "在 $SourceRoot 下找不到任何支援的 Office 檔。"
        return
    }

    # 依副檔名分桶 (Word / Excel / PowerPoint)
    $buckets = @{
        Word       = @()
        Excel      = @()
        PowerPoint = @()
    }
    foreach ($f in $allFiles) {
        switch ($f.Extension.ToLower()) {
            '.doc'  { $buckets.Word       += $f }
            '.docx' { $buckets.Word       += $f }
            '.xls'  { $buckets.Excel      += $f }
            '.xlsx' { $buckets.Excel      += $f }
            '.pptx' { $buckets.PowerPoint += $f }
        }
    }

    $successes = @()
    $failures  = @()

    foreach ($comType in 'Word', 'Excel', 'PowerPoint') {
        $bucket = $buckets[$comType]
        if (-not $bucket) { continue }

        Write-Host "`n=== 處理 $comType 檔 ($($bucket.Count) 個) ==="
        $app = New-Object -ComObject "$comType.Application"
        $app.Visible       = $false
        try { $app.DisplayAlerts = 0 } catch {}

        try {
            foreach ($file in $bucket) {
                $rel       = $file.FullName.Substring($SourceRoot.TrimEnd('\').Length).TrimStart('\')
                $relNoExt  = [IO.Path]::ChangeExtension($rel, $null).TrimEnd('.')
                $outPath   = Join-Path $OutputRoot ($relNoExt + '.md')
                $tmpPath   = Join-Path $TmpRoot    ($relNoExt + '.unprotected' + $file.Extension)

                Write-Host "→ $($file.FullName)"
                try {
                    Convert-OfficeFile -SourcePath $file.FullName `
                                       -OutputPath $outPath `
                                       -TmpPath    $tmpPath `
                                       -Config     $Config `
                                       -ComApp     $app `
                                       -ComType    $comType
                    $successes += $file.FullName
                } catch {
                    $reason = if ($_.TargetObject -and $_.TargetObject.Reason) {
                        $_.TargetObject.Reason
                    } else { 'unexpected' }
                    $detail = if ($_.TargetObject -and $_.TargetObject.Detail) {
                        $_.TargetObject.Detail
                    } else { $_.Exception.Message }
                    $failures += [pscustomobject]@{
                        File   = $file.FullName
                        Reason = $reason
                        Detail = $detail
                    }
                    Write-Warning "  [$reason] $detail"
                }
            }
        }
        finally {
            try { $app.Quit() } catch {}
            [void][System.Runtime.Interopservices.Marshal]::ReleaseComObject($app)
        }
    }

    # 結尾彙整
    Write-Host "`n=== markitdown 轉換結果 ==="
    Write-Host "成功: $($successes.Count) 檔，輸出在 $OutputRoot"
    Write-Host "失敗: $($failures.Count) 檔"

    if ($failures.Count -gt 0) {
        $failures | Group-Object Reason | ForEach-Object {
            Write-Host "`n[$($_.Name)]"
            $_.Group | ForEach-Object {
                Write-Host "  $($_.File)"
                Write-Host "    → $($_.Detail)"
            }
        }
    }

    return [pscustomobject]@{
        Successes = $successes
        Failures  = $failures
    }
}
```

**批次典型呼叫：**

```powershell
$config = Test-MarkitdownPrereqs
if (-not $config) { throw "請先跑探索模式" }

Convert-OfficeFolder -SourceRoot "D:\Reports" -Config $config
```

> 批次模式整批只啟動三個 COM app（每種 Office 一個），避免每檔啟停 Office 的數量級慢速。
````

- [ ] **Step 2: Verify**

Run:
```powershell
Select-String -Path "D:\TMP\MCPDemo\.claude\skills\markitdown\SKILL.md" -Pattern "function Convert-OfficeFolder" -SimpleMatch
```
Expected: one match.

- [ ] **Step 3: Save & continue**

---

### Task 9: Failure types table + skip rules + common errors section

**Files:**
- Modify: `D:\TMP\MCPDemo\.claude\skills\markitdown\SKILL.md` (append)

- [ ] **Step 1: Append "失敗類型與處理" section**

Use Edit tool to append:

````markdown

## 跳過規則

- 檔名以 `~$` 開頭（Office 鎖檔暫存）：批次模式自動略過，**不列入失敗清單**。

## 失敗類型與處理

| Reason | 何時發生 | 建議下一步 |
|---|---|---|
| `policy-forbidden` | 來源 tier → `unprotected_target` 不在 `allowed_downgrades` | 此檔暫時跳過；若實際需要轉，請走人工降階流程或修改 `config.json`（需與資安團隊確認） |
| `unknown-source-label` | 來源檔 `LabelId` 不在 `config.json` 內 | 重跑探索模式，把該 tier 加進來再試 |
| `no-downgrade-rights` | `SetLabel` COM 呼叫被拒（沒有降階權限） | 確認帳號對該檔有 Owner / Co-Author 權限；或聯絡資安釋出降階能力 |
| `office-not-installed` | 前置檢查失敗 | 安裝 Office desktop（Click-to-Run 受限版不行） |
| `markitdown-failed` | COM 解密成功但 markitdown 解析失敗 | 通常是壞檔 / 舊版 binary `.doc` 異常 / 巨型 Excel 公式錯誤；中繼檔保留在 `.tmp\`，可手動診斷 |
| `target-still-encrypted` | SaveAs2 後 markitdown 仍打不開（`unprotected_target` 設錯） | 改設更低 tier 重跑探索 |
| `file-corrupt-or-locked` | COM `Open` 階段就失敗 | 確認檔案沒在 Office 中開啟、沒被防毒鎖、不是 0 byte |

## 常見錯誤排查

- **`SetLabel` 一直丟 COM exception**：通常是租戶政策不允許程式碼降階，或目前 Office 帳號沒登入 Azure AD。先在 Word UI 手動降階一次成功，再跑 skill。
- **中繼檔留在 `.tmp\`**：表示該檔失敗。`.tmp\` 已加入 `.gitignore`，不必擔心入版。
- **大量 audit log**：批次轉幾百份檔會在 M365 audit log 留同等數量降階紀錄。**大量批次前請先知會 IT**。
````

- [ ] **Step 2: Verify**

Run:
```powershell
Select-String -Path "D:\TMP\MCPDemo\.claude\skills\markitdown\SKILL.md" -Pattern "target-still-encrypted" -SimpleMatch
```
Expected: one match.

- [ ] **Step 3: Save & continue**

---

### Task 10: End-to-end smoke test

**Files:** None (verification only)

**Pre-requisite:** User has prepared sample files described in plan header — at minimum:
- `sample-cint.docx` labeled `C-internal`
- `sample-cext.xlsx` labeled `C-external`
- `sample-b.pptx` labeled `B` (or whichever tier you have that is NOT in `allowed_downgrades`)

If samples are unavailable, mark Task 10 as deferred and notify the user.

- [ ] **Step 1: Verify Claude Code sees the skill**

Restart Claude Code (or `/reload`). Type `/help` and confirm the skills list now contains `markitdown`. Alternatively:

```powershell
Get-ChildItem "D:\TMP\MCPDemo\.claude\skills\markitdown\" | Format-Table Name, Length
```
Expected: `SKILL.md` present, size > 5KB.

- [ ] **Step 2: Run prereq check (expect "config.json 不存在" warning)**

In Claude Code, say: "驗證 markitdown skill 前置條件"

Expected: skill triggers, runs `Test-MarkitdownPrereqs`. markitdown CLI ✓, Word COM ✓, config.json ❌ (warning). No exception.

- [ ] **Step 3: Run discovery mode with sample files**

In Claude Code, say: "請跑 markitdown 探索模式" and provide paths to your sample files when prompted.

Expected: `config.json` written. Inspect:

```powershell
Get-Content "D:\TMP\MCPDemo\.claude\skills\markitdown\config.json" -Raw
```
Should contain `labels`, `unprotected_target`, `allowed_downgrades`.

- [ ] **Step 4: Single-file conversion — C-internal sample**

In Claude Code, say: "把 <絕對路徑>\sample-cint.docx 轉成 markdown"

Expected:
- `D:\MarkItDownOutPut\sample-cint.md` exists
- 內容非空（有原文件文字、表格用 markdown 表格呈現）
- `D:\MarkItDownOutPut\.tmp\sample-cint.unprotected.docx` 已被刪除

- [ ] **Step 5: Single-file conversion — C-external sample (no SetLabel path)**

In Claude Code, say: "把 <絕對路徑>\sample-cext.xlsx 轉成 markdown"

Expected:
- 不觸發 `SetLabel`（已在 target tier），但仍 SaveAs2 為中繼檔
- `D:\MarkItDownOutPut\sample-cext.md` 內容非空

- [ ] **Step 6: Policy-forbidden — B-tier sample**

In Claude Code, say: "把 <絕對路徑>\sample-b.pptx 轉成 markdown"

Expected:
- 失敗，`reason = policy-forbidden`
- 沒有輸出檔
- 訊息明確列出 `B -> C-external 不在 allowed_downgrades`

- [ ] **Step 7: Batch conversion — folder containing all three samples**

Put all三個 sample 放進 `D:\smoke-test\`（其中一個放子資料夾 `D:\smoke-test\sub\`，測鏡像）。

In Claude Code, say: "把 D:\smoke-test\ 底下所有 Office 檔轉成 markdown"

Expected：
- 成功：兩份（C-internal、C-external）
- 失敗：一份（B，reason=policy-forbidden）
- 結尾彙整有 `[policy-forbidden]` 區塊
- 鏡像：`D:\MarkItDownOutPut\sub\<basename>.md` 路徑正確
- `~$` 鎖檔（若存在）被略過、不在失敗清單

- [ ] **Step 8: Save & deliver**

把 smoke test 結果（成功檔數、失敗檔數、輸出路徑樣本）整理成一段短訊息回給使用者。Skill 完成。

---

## Self-Review Notes

**1. Spec coverage check:**
- §1.1 Skill location (project-level, no Junction) → Task 1
- §1.2 Extensions supported → Task 2 table + Task 7 dispatch logic
- §1.3 Description → Task 2 frontmatter
- §1.4 Decision table → Task 2
- §2 Prerequisites → Task 3
- §3.1–3.4 Output rules incl. mirrored .tmp → Task 4 + Task 8 path math
- §4 Single-file flow → Task 7
- §5 Batch flow with COM bucketing + failure list → Task 8
- §6.1 Discovery → Task 6
- §6.2 config.json schema → Task 5
- §6.3 Per-file decision (with explicit justification string) → Task 7 `Convert-OfficeFile`
- §6.4 Failure types → Task 9 (also `target-still-encrypted`)
- §6.5 Audit log warning → Task 9 common errors
- §7 SKILL.md structure → Tasks 2–9 build it in order
- §8 Out-of-scope → Task 2 description + decision table excludes them
- §9 Risks → covered in Task 9 common errors and finally blocks (COM cleanup)
- §10 Task slices → this plan

**2. Naming consistency:**
- `Test-MarkitdownPrereqs` used in Tasks 3, 6, 7, 8 (consistent)
- `Convert-OfficeFile` used in Tasks 6 (validation reference), 7 (definition), 8 (call) — consistent signature
- `Convert-OfficeFolder` defined in Task 8 only
- `Start-MarkitdownDiscovery` defined in Task 6
- Config field names match spec §6.2 exactly (`labels`, `unprotected_target`, `allowed_downgrades`)

**3. No placeholders remain:**
- Every PowerShell function has full body
- No "TBD" / "implement later" / "similar to" — code repeated where needed
- One literal placeholder (`<sample.docx>`) only in the verification example in Task 6, and one (`<絕對路徑>`) in Task 10 smoke test — these are intentional user-input markers, not plan failures.
