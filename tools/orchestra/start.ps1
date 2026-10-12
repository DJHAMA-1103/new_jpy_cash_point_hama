[CmdletBinding()]
param(
    [ValidateRange(1024,65535)][int]$Port = 8765,
    [switch]$NoTerminals,
    [switch]$NoBrowser,
    [switch]$WorkspaceWrite,
    [ValidateSet('coordinator','ui','developer','reviewer')][string]$Role
)
$ErrorActionPreference = 'Stop'
$orchestraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$orchestraData = Join-Path $orchestraRoot '.orchestra'
$orchestraPython = (Get-Command python -ErrorAction Stop).Source
$orchestraConnection = Join-Path $orchestraData 'connection.json'
if ($Role) {
    $Host.UI.RawUI.WindowTitle = "POINT Orchestra - $Role"
    & $orchestraPython -u (Join-Path $PSScriptRoot 'terminal.py') --role $Role --connection $orchestraConnection
    exit $LASTEXITCODE
}
New-Item -ItemType Directory -Force -Path $orchestraData | Out-Null
$orchestraUrl = "http://127.0.0.1:$Port"
$orchestraReady = $false
$orchestraMode = if ($WorkspaceWrite) { 'workspace-write' } else { 'read-only' }
try {
    $orchestraHealth = Invoke-RestMethod "$orchestraUrl/api/health" -TimeoutSec 2
    if ($orchestraHealth) {
        if (-not (Test-Path -LiteralPath $orchestraConnection)) { throw 'Port is occupied but no workspace connection exists.' }
        $orchestraInfo = Get-Content -LiteralPath $orchestraConnection -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($orchestraInfo.url.TrimEnd('/') -ne $orchestraUrl) { throw 'A different port is recorded for this workspace. Stop that instance first.' }
        $orchestraState = Invoke-RestMethod "$orchestraUrl/api/state" -Headers @{'X-Orchestra-Token'=$orchestraInfo.token} -TimeoutSec 2
        if ($orchestraState.server.sandbox -ne $orchestraMode) { throw 'Server is already running in a different sandbox mode. Stop it before changing mode.' }
        $orchestraReady = $true
    }
} catch {
    if ($_.Exception.Response) { throw }
    if ($_.Exception -isnot [System.Net.WebException] -and $_.Exception -isnot [System.OperationCanceledException] -and $_.Exception.GetType().FullName -ne 'System.Net.Http.HttpRequestException') { throw }
}
if (-not $orchestraReady) {
    if (Test-Path -LiteralPath $orchestraConnection) {
        $orchestraPrevious = Get-Content -LiteralPath $orchestraConnection -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($orchestraPrevious.url -ne $orchestraUrl) {
            throw 'Connection file records another port. Stop that instance before changing the port.'
        }
    }
    $orchestraServer = Join-Path $PSScriptRoot 'server.py'
    $orchestraMode = if ($WorkspaceWrite) { 'workspace-write' } else { 'read-only' }
    $orchestraArgs = @('-u', ('"' + $orchestraServer + '"'), '--port', "$Port", '--sandbox', $orchestraMode)
    $orchestraProcess = Start-Process -FilePath $orchestraPython -ArgumentList $orchestraArgs -WorkingDirectory $orchestraRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $orchestraData 'server.stdout.log') -RedirectStandardError (Join-Path $orchestraData 'server.stderr.log') -PassThru
    for ($orchestraAttempt = 0; $orchestraAttempt -lt 60; $orchestraAttempt++) {
        $orchestraProcess.Refresh()
        if ($orchestraProcess.HasExited) { throw "Server exited. Read $orchestraData\server.stderr.log" }
        try {
            if (Test-Path -LiteralPath $orchestraConnection) {
                $orchestraInfo = Get-Content -LiteralPath $orchestraConnection -Raw -Encoding UTF8 | ConvertFrom-Json
                $null = Invoke-RestMethod "$orchestraUrl/api/state" -Headers @{'X-Orchestra-Token'=$orchestraInfo.token} -TimeoutSec 1
                $orchestraReady = $true
                break
            }
        } catch { }
        Start-Sleep -Milliseconds 250
    }
    if (-not $orchestraReady) {
        if (-not $orchestraProcess.HasExited) { Stop-Process -InputObject $orchestraProcess }
        throw "Server did not become ready. Read $orchestraData\server.stderr.log"
    }
}
if (-not $NoTerminals) {
    $orchestraWindowsFile = Join-Path $orchestraData 'terminal-pids.json'
    $orchestraWindows = @()
    if (Test-Path -LiteralPath $orchestraWindowsFile) {
        $orchestraWindows = @(Get-Content -LiteralPath $orchestraWindowsFile -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    $orchestraNextWindows = @()
    foreach ($orchestraRole in @('coordinator','ui','developer','reviewer')) {
        $orchestraExisting = $orchestraWindows | Where-Object { $_.role -eq $orchestraRole } | Select-Object -First 1
        $orchestraLive = $null
        if ($orchestraExisting) {
            $orchestraLive = Get-CimInstance Win32_Process -Filter "ProcessId = $($orchestraExisting.pid)" -ErrorAction SilentlyContinue
            if ($orchestraLive -and (($orchestraLive.CommandLine -notlike ('*' + $PSCommandPath + '*')) -or ($orchestraLive.CommandLine -notlike "*-Role $orchestraRole*"))) { $orchestraLive = $null }
        }
        if ($orchestraLive) {
            $orchestraNextWindows += $orchestraExisting
        } else {
            $orchestraArgs = @('-NoProfile', '-File', ('"' + $PSCommandPath + '"'), '-Role', $orchestraRole)
            $orchestraWindow = Start-Process powershell.exe -ArgumentList $orchestraArgs -WorkingDirectory $orchestraRoot -WindowStyle Normal -PassThru
            $orchestraNextWindows += @{role=$orchestraRole;pid=$orchestraWindow.Id}
        }
    }
    ConvertTo-Json -InputObject $orchestraNextWindows | Set-Content -LiteralPath $orchestraWindowsFile -Encoding UTF8
}
if (-not $NoBrowser) { Start-Process $orchestraUrl }
Write-Output "POINT Orchestra ready: $orchestraUrl"
Write-Output 'Four role terminals communicate through the local broker. Opening a window does not start a model task.'
