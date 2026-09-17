# scripts/tests/test-ps51-static.ps1 — PowerShell 5.1 語法紀律的靜態守衛（AST 走訪 scripts/**/*.ps1）
# 用法：pwsh -NoProfile -File scripts/tests/test-ps51-static.ps1   （在 PowerShell 7 跑：5.1 連解析都會炸的語法在 7 才看得到）
# 阻擋（exit 1）：三元 ?:、??、??=、?.、&&／|| 管線鏈、ForEach-Object -Parallel、ConvertFrom-Json -AsHashtable／-Depth、
#   -Encoding utf8NoBOM／utf8BOM／ansi、三段以上 Join-Path（含 -AdditionalChildPath）、Split-Path -LeafBase、Test-Json、
#   [IO.File]::Move 三參數、[IO.Path]::GetRelativePath、解析錯誤、缺 UTF-8 BOM（5.1 無 BOM 會把中文誤解析）、
#   @(函式 …) 直接包住以 `return , $arr` 回傳的函式（空陣列時 Count 會是 1；要先指派再 @()）。
# 警告（只計數）：Get-Date -Format（永遠依目前文化，民國曆環境 yyyy 會變 115；改用 .ToString('<fmt>', InvariantCulture)）、
#   DateTime.ToString('<日期格式>') 未給文化參數、Get-Content 未指定 -Encoding UTF8。
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ErrorActionPreference = 'Stop'
# 遺留腳本（前一個專案、與本框架無關，README「腳本」表標為遺留）不在守衛範圍
$legacy = @('test-mcp-tools-list.ps1', 'test-elasticsearch-mcp-tools-list.ps1')
$files = @(Get-ChildItem -Path (Join-Path $repoRoot 'scripts') -Filter '*.ps1' -Recurse -File | Where-Object { $legacy -notcontains $_.Name } | Sort-Object FullName)
$problems = @()
$warnings = @()
$pathParams = @('Path', 'ChildPath', 'AdditionalChildPath')
# 前置掃描：哪些函式以 return , $arr 回傳（呼叫端不得直接 @(函式 …)）
$commaReturnFns = @{}
foreach ($f in $files) {
    $t0 = $null; $e0 = $null
    $ast0 = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$t0, [ref]$e0)
    if ($e0.Count -gt 0) { continue }
    foreach ($fd in $ast0.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        $hasComma = $false
        foreach ($rs in $fd.Body.FindAll({ param($x) $x -is [System.Management.Automation.Language.ReturnStatementAst] }, $true)) {
            if ($null -ne $rs.Pipeline -and $rs.Pipeline.Extent.Text -match '^\s*,') { $hasComma = $true; break }
        }
        if ($hasComma) { $commaReturnFns[$fd.Name] = $true }
    }
}
foreach ($f in $files) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) { $problems += "${rel}: 缺 UTF-8 BOM（PS 5.1 會把中文字串當語法錯誤）" }
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errs)
    if ($errs.Count -gt 0) { foreach ($e in $errs) { $problems += "${rel}:$($e.Extent.StartLineNumber) 解析錯誤：$($e.Message)" }; continue }
    foreach ($n in $ast.FindAll({ $true }, $true)) {
        $tn = $n.GetType().Name
        $ln = $n.Extent.StartLineNumber
        if ($tn -eq 'TernaryExpressionAst') { $problems += "${rel}:$ln 三元運算子 ?:（5.1 不支援）" }
        elseif ($tn -eq 'PipelineChainAst') { $problems += "${rel}:$ln 管線鏈 &&／||（5.1 不支援）" }
        elseif ($tn -eq 'BinaryExpressionAst' -and ([string]$n.Operator) -match 'QuestionQuestion|Coalesce') { $problems += "${rel}:$ln ?? 運算子（5.1 不支援）" }
        elseif ($tn -eq 'AssignmentStatementAst' -and ([string]$n.Operator) -match 'QuestionQuestion') { $problems += "${rel}:$ln ??=（5.1 不支援）" }
        elseif ($tn -eq 'MemberExpressionAst' -and $n.NullConditional) { $problems += "${rel}:$ln ?. 成員存取（5.1 不支援）" }
        elseif ($tn -eq 'ArrayExpressionAst') {
            $stmts = @($n.SubExpression.Statements)
            if ($stmts.Count -eq 1 -and $stmts[0] -is [System.Management.Automation.Language.PipelineAst]) {
                $pes = @($stmts[0].PipelineElements)
                if ($pes.Count -eq 1 -and $pes[0] -is [System.Management.Automation.Language.CommandAst]) {
                    $cn = [string]$pes[0].GetCommandName()
                    if ($cn -ne '' -and $commaReturnFns.ContainsKey($cn)) { $problems += "${rel}:$ln @($cn …) 直接包住 return , 陣列 的函式（空陣列時 Count=1）；改成先指派再 @(變數)" }
                }
            }
        }
        elseif ($tn -eq 'InvokeMemberExpressionAst') {
            $member = [string]$n.Member.Extent.Text
            $target = [string]$n.Expression.Extent.Text
            $argc = 0
            if ($null -ne $n.Arguments) { $argc = $n.Arguments.Count }
            if ($member -eq 'Move' -and $target -match '(?i)\bFile\]$' -and $argc -ge 3) { $problems += "${rel}:$ln [IO.File]::Move 三參數（overwrite 旗標是 .NET Core 才有）" }
            if ($member -eq 'GetRelativePath' -and $target -match '(?i)\bPath\]$') { $problems += "${rel}:$ln [IO.Path]::GetRelativePath（.NET Framework 沒有）" }
            if ($member -eq 'ToString' -and $argc -eq 1) {
                $a0 = $n.Arguments[0]
                if ($a0 -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $a0.Value -match '(yyyy|MM|dd|HH|mm|ss)') { $warnings += "${rel}:$ln .ToString('<日期格式>') 未給文化參數（第二參數加 [System.Globalization.CultureInfo]::InvariantCulture）" }
            }
        }
        elseif ($tn -eq 'CommandAst') {
            $name = [string]$n.GetCommandName()
            if ($name -eq '') { continue }
            $paramNames = @()
            $positional = 0
            $els = @($n.CommandElements)
            $skipNext = $false
            for ($i = 1; $i -lt $els.Count; $i++) {
                $e = $els[$i]
                if ($skipNext) { $skipNext = $false; continue }
                if ($e -is [System.Management.Automation.Language.CommandParameterAst]) {
                    $paramNames += $e.ParameterName
                    if ($null -eq $e.Argument -and $name -eq 'Join-Path' -and ($pathParams | Where-Object { $_ -like ($e.ParameterName + '*') })) { $skipNext = $true }
                    continue
                }
                $positional++
            }
            switch ($name) {
                'ForEach-Object' { if ($paramNames -contains 'Parallel') { $problems += "${rel}:$ln ForEach-Object -Parallel（5.1 不支援）" } }
                'ConvertFrom-Json' { foreach ($p in $paramNames) { if ('AsHashtable' -like ($p + '*') -or 'Depth' -like ($p + '*')) { $problems += "${rel}:$ln ConvertFrom-Json -$p（5.1 不支援）" } } }
                'Join-Path' {
                    $named = @($paramNames | Where-Object { 'AdditionalChildPath' -like ($_ + '*') })
                    if ($named.Count -gt 0) { $problems += "${rel}:$ln Join-Path -AdditionalChildPath（5.1 不支援）" }
                    $pathCount = $positional + @($paramNames | Where-Object { $p = $_; ($pathParams | Where-Object { $_ -like ($p + '*') }).Count -gt 0 }).Count
                    if ($pathCount -ge 3) { $problems += "${rel}:$ln Join-Path 三段以上（5.1 只收兩段；請巢狀）" }
                }
                'Split-Path' { if (@($paramNames | Where-Object { $_.Length -gt 4 -and 'LeafBase' -like ($_ + '*') }).Count -gt 0) { $problems += "${rel}:$ln Split-Path -LeafBase（5.1 不支援；-Leaf 是另一個參數）" } }
                'Test-Json' { $problems += "${rel}:$ln Test-Json（5.1 沒有）" }
                'Get-Date' { if (@($paramNames | Where-Object { $_.Length -ge 1 -and 'Format' -like ($_ + '*') }).Count -gt 0) { $warnings += "${rel}:$ln Get-Date -Format 永遠依目前文化（無法指定）；改用 (Get-Date).ToUniversalTime().ToString('<fmt>', [System.Globalization.CultureInfo]::InvariantCulture)" } }
                'Get-Content' { if ($paramNames -notcontains 'Encoding' -and $n.Extent.Text -notmatch '-Raw\s*-Encoding|-Encoding') { $warnings += "${rel}:$ln Get-Content 未指定 -Encoding UTF8" } }
                default { }
            }
            for ($i = 1; $i -lt $els.Count - 1; $i++) {
                $e = $els[$i]
                if ($e -is [System.Management.Automation.Language.CommandParameterAst] -and 'Encoding' -like ($e.ParameterName + '*') -and $e.ParameterName.Length -ge 3) {
                    $v = [string]$els[$i + 1].Extent.Text
                    if ($v -match '(?i)utf8NoBOM|utf8BOM|^ansi$|^oem$') { $problems += "${rel}:$ln -Encoding $v（5.1 只有 UTF8／Unicode／ASCII 等舊名）" }
                }
            }
        }
    }
}
Write-Host ("PS 5.1 靜態守衛：掃 " + $files.Count + " 個 .ps1；阻擋 " + $problems.Count + " 項；警告 " + $warnings.Count + " 項")
foreach ($p in $problems) { Write-Host ("  BLOCK " + $p) -ForegroundColor Red }
if ($env:PS51_STATIC_VERBOSE) { foreach ($w in $warnings) { Write-Host ("  warn  " + $w) -ForegroundColor Yellow } }
if ($problems.Count -gt 0) { Write-Host "共 $($problems.Count) 個 FAIL" -ForegroundColor Red; exit 1 }
Write-Host "全部情境 PASS" -ForegroundColor Green
exit 0
