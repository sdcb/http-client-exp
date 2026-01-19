param(
    [string]$Url = "http://localhost:5055/ping",
    [int]$Requests = 20000,
    [int]$Parallel = 200,
    [int]$TimeoutSeconds = 5,
    [int]$CooldownSeconds = 300,
    [int]$CooldownPollSeconds = 10,
    [int]$TimeWaitThreshold = 200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$logDir = Get-Content -Path (Join-Path $root "logs/latest-run.txt")

if (-not (Test-Path -Path $logDir)) {
    throw "Log directory not found: $logDir"
}

$netstatLog = Join-Path $logDir "netstat.log"
$summaryLog = Join-Path $logDir "experiment-summary.log"
$cooldownLog = Join-Path $logDir "cooldown.log"

$serverReady = $false
for ($i = 0; $i -lt 30; $i++) {
    try {
        $response = Invoke-WebRequest -Uri $Url -TimeoutSec 2 -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            $serverReady = $true
            break
        }
    } catch {
        Start-Sleep -Seconds 1
    }
}

if (-not $serverReady) {
    throw "Server did not respond within timeout: $Url"
}

function Get-ConnCounts {
    $lines = @(netstat -an | Select-String -Pattern ":5055")
    $timeWait = @($lines | Where-Object { $_ -match "TIME_WAIT" }).Count
    $established = @($lines | Where-Object { $_ -match "ESTABLISHED" }).Count
    $closeWait = @($lines | Where-Object { $_ -match "CLOSE_WAIT" }).Count
    return [PSCustomObject]@{
        TimeWait   = $timeWait
        Established = $established
        CloseWait  = $closeWait
    }
}

function Write-ConnSample([string]$label) {
    $counts = Get-ConnCounts
    $line = "[{0}] {1} TIME_WAIT={2} ESTABLISHED={3} CLOSE_WAIT={4}" -f (Get-Date -Format o), $label, $counts.TimeWait, $counts.Established, $counts.CloseWait
    Add-Content -Path $netstatLog -Value $line
    Write-Host $line
}

function Wait-ForCooldown([string]$label, [int]$baseline) {
    $start = Get-Date
    while ($true) {
        $counts = Get-ConnCounts
        $limit = $baseline + $TimeWaitThreshold
        $line = "[{0}] {1} TIME_WAIT={2} baseline={3} limit={4}" -f (Get-Date -Format o), $label, $counts.TimeWait, $baseline, $limit
        Add-Content -Path $cooldownLog -Value $line
        Write-Host $line
        if ($counts.TimeWait -le $limit) {
            break
        }
        if (((Get-Date) - $start).TotalSeconds -ge $CooldownSeconds) {
            $timeoutLine = "[{0}] {1} cooldown timeout after {2}s" -f (Get-Date -Format o), $label, $CooldownSeconds
            Add-Content -Path $cooldownLog -Value $timeoutLine
            Write-Host $timeoutLine
            break
        }
        Start-Sleep -Seconds $CooldownPollSeconds
    }
}

function Run-Client([string]$name, [string]$filePath, [string[]]$arguments) {
    $outLog = Join-Path $logDir ("{0}.out.log" -f $name)
    $errLog = Join-Path $logDir ("{0}.err.log" -f $name)
    Write-Host "Starting client: $name"
    $proc = Start-Process -FilePath $filePath -ArgumentList $arguments -WorkingDirectory $root -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru
    $proc | Wait-Process
    $exitCode = $proc.ExitCode
    Add-Content -Path $summaryLog -Value ("[{0}] {1} ExitCode={2} OutLog={3} ErrLog={4}" -f (Get-Date -Format o), $name, $exitCode, $outLog, $errLog)
    Write-Host "Completed client: $name (ExitCode=$exitCode)"
}

$env:DOTNET_ROLL_FORWARD = "LatestMajor"

$baseline = (Get-ConnCounts).TimeWait
Write-ConnSample "before-net48"
$net48Exe = Join-Path $root "Clients/HttpLeakClient.Net48/bin/Debug/net48/HttpLeakClient.Net48.exe"
Run-Client "net48" $net48Exe @("--url", $Url, "--requests", $Requests, "--parallel", $Parallel, "--timeoutSeconds", $TimeoutSeconds)
Write-ConnSample "after-net48"
Wait-ForCooldown "cooldown-net48" $baseline

$baseline = (Get-ConnCounts).TimeWait
Write-ConnSample "before-net6"
Run-Client "net6" "dotnet" @("run", "--project", (Join-Path $root "Clients/HttpLeakClient.Net6/HttpLeakClient.Net6.csproj"), "--no-build", "--", "--url", $Url, "--requests", $Requests, "--parallel", $Parallel, "--timeoutSeconds", $TimeoutSeconds)
Write-ConnSample "after-net6"
Wait-ForCooldown "cooldown-net6" $baseline

$baseline = (Get-ConnCounts).TimeWait
Write-ConnSample "before-net8"
Run-Client "net8" "dotnet" @("run", "--project", (Join-Path $root "Clients/HttpLeakClient.Net8/HttpLeakClient.Net8.csproj"), "--no-build", "--", "--url", $Url, "--requests", $Requests, "--parallel", $Parallel, "--timeoutSeconds", $TimeoutSeconds)
Write-ConnSample "after-net8"
Wait-ForCooldown "cooldown-net8" $baseline

$baseline = (Get-ConnCounts).TimeWait
Write-ConnSample "before-net10-new"
Run-Client "net10-new" "dotnet" @("run", "--project", (Join-Path $root "Clients/HttpLeakClient.Net10/HttpLeakClient.Net10.csproj"), "--no-build", "--", "--mode", "new", "--url", $Url, "--requests", $Requests, "--parallel", $Parallel, "--timeoutSeconds", $TimeoutSeconds)
Write-ConnSample "after-net10-new"
Wait-ForCooldown "cooldown-net10-new" $baseline

$baseline = (Get-ConnCounts).TimeWait
Write-ConnSample "before-net10-static"
Run-Client "net10-static" "dotnet" @("run", "--project", (Join-Path $root "Clients/HttpLeakClient.Net10/HttpLeakClient.Net10.csproj"), "--no-build", "--", "--mode", "static", "--url", $Url, "--requests", $Requests, "--parallel", $Parallel, "--timeoutSeconds", $TimeoutSeconds)
Write-ConnSample "after-net10-static"
Wait-ForCooldown "cooldown-net10-static" $baseline

$baseline = (Get-ConnCounts).TimeWait
Write-ConnSample "before-net10-factory"
Run-Client "net10-factory" "dotnet" @("run", "--project", (Join-Path $root "Clients/HttpLeakClient.Net10/HttpLeakClient.Net10.csproj"), "--no-build", "--", "--mode", "factory", "--url", $Url, "--requests", $Requests, "--parallel", $Parallel, "--timeoutSeconds", $TimeoutSeconds)
Write-ConnSample "after-net10-factory"
Wait-ForCooldown "cooldown-net10-factory" $baseline

Write-Host "Experiment done. Logs: $logDir"
