[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$orchestraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$orchestraConnection = Join-Path $orchestraRoot '.orchestra\connection.json'
if (-not (Test-Path -LiteralPath $orchestraConnection)) {
    Write-Output 'No Orchestra connection file. Nothing to stop.'
    exit 0
}
$orchestraInfo = Get-Content -LiteralPath $orchestraConnection -Raw -Encoding UTF8 | ConvertFrom-Json
$orchestraUri = [Uri]$orchestraInfo.url
if ($orchestraUri.Scheme -ne 'http' -or $orchestraUri.Host -ne '127.0.0.1' -or $orchestraUri.AbsolutePath -ne '/' -or $orchestraUri.Query -or $orchestraUri.Fragment -or $orchestraUri.UserInfo) { throw 'Invalid local connection URL.' }
Invoke-RestMethod ($orchestraInfo.url.TrimEnd('/') + '/api/shutdown') -Method Post -ContentType 'application/json' -Body '{}' -Headers @{'X-Orchestra-Token'=$orchestraInfo.token} -TimeoutSec 10 | Out-Null
$orchestraServerProcess = Get-Process -Id $orchestraInfo.pid -ErrorAction SilentlyContinue
if ($orchestraServerProcess -and -not $orchestraServerProcess.WaitForExit(20000)) { throw 'Shutdown is still in progress; wait before restarting.' }
Write-Output 'Server stopped. Running tasks are cancelled; terminal views exit after disconnect. History remains saved.'
