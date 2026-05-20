$ErrorActionPreference = 'Stop'

$serverDll = "$PSScriptRoot\..\src\HanshinChat.Mcp.Server\bin\Debug\net8.0\HanshinChat.Mcp.Server.dll"
if (-not (Test-Path $serverDll)) {
    Write-Error "Built dll not found: $serverDll. Run dotnet build first."
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'dotnet'
$psi.Arguments = "`"$serverDll`""
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.WorkingDirectory = (Resolve-Path "$PSScriptRoot\..\src\HanshinChat.Mcp.Server\bin\Debug\net8.0").Path

$proc = [System.Diagnostics.Process]::Start($psi)

$init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"1.0"}}}'
$initialized = '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}'
$listTools = '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'

$proc.StandardInput.WriteLine($init)
$proc.StandardInput.WriteLine($initialized)
$proc.StandardInput.WriteLine($listTools)
$proc.StandardInput.Flush()

$received = @()
$deadline = (Get-Date).AddSeconds(10)
while ((Get-Date) -lt $deadline -and $received.Count -lt 2) {
    if (-not $proc.StandardOutput.EndOfStream) {
        $line = $proc.StandardOutput.ReadLine()
        if ($line) {
            $received += $line
            Write-Host "RECV: $line"
        }
    } else {
        Start-Sleep -Milliseconds 100
    }
}

$proc.StandardInput.Close()
if (-not $proc.HasExited) { $proc.Kill() }
$proc.WaitForExit(2000) | Out-Null

if ($received.Count -lt 2) {
    Write-Host "stderr:"
    Write-Host $proc.StandardError.ReadToEnd()
    Write-Error "Did not receive expected responses (got $($received.Count))."
}

$toolsResp = $received | Where-Object { $_ -match '"id":2' } | Select-Object -First 1
if (-not $toolsResp) { Write-Error 'No tools/list response.' }

$parsed = $toolsResp | ConvertFrom-Json
$names = $parsed.result.tools | ForEach-Object { $_.name }
Write-Host ""
Write-Host "Tool count: $($names.Count)"
$names | Sort-Object | ForEach-Object { Write-Host "  - $_" }
