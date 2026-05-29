param(
  [string]$Action = "status"
)

$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$HostName = "127.0.0.1"
$Port = if ($env:SERVER_PORT) { [int]$env:SERVER_PORT } else { 4173 }
$PidFile = Join-Path $Root ".webserver.pid"
$LogFile = Join-Path $Root ".webserver.log"
$ErrorLogFile = Join-Path $Root ".webserver.error.log"
$Url = "http://${HostName}:$Port/"

function Get-ManagedProcess {
  if (-not (Test-Path -LiteralPath $PidFile)) {
    return $null
  }

  $raw = Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($raw -notmatch "^\d+$") {
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    return $null
  }

  $process = Get-Process -Id ([int]$raw) -ErrorAction SilentlyContinue
  if (-not $process) {
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
  }
  return $process
}

function Get-PortListener {
  Get-NetTCPConnection -LocalAddress $HostName -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    Select-Object -First 1
}

function Get-PythonLaunch {
  $python = Get-Command python -ErrorAction SilentlyContinue
  if ($python) {
    return @{
      File = $python.Source
      Args = @("-m", "http.server", [string]$Port, "--bind", $HostName)
    }
  }

  $py = Get-Command py -ErrorAction SilentlyContinue
  if ($py) {
    return @{
      File = $py.Source
      Args = @("-3", "-m", "http.server", [string]$Port, "--bind", $HostName)
    }
  }

  throw "Python was not found on PATH. Install Python or add it to PATH."
}

function Quote-CmdArg {
  param([string]$Value)

  if ($Value -match '[\s"]') {
    return '"' + ($Value -replace '"', '\"') + '"'
  }
  return $Value
}

function Start-WebServer {
  $managed = Get-ManagedProcess
  if ($managed) {
    Write-Host "Server already running at $Url (PID $($managed.Id))"
    return
  }

  $listener = Get-PortListener
  if ($listener) {
    throw "Port $Port is already in use by unmanaged PID $($listener.OwningProcess). Stop that process or set SERVER_PORT before starting."
  }

  $python = Get-PythonLaunch
  $argString = (($python.Args | ForEach-Object { Quote-CmdArg $_ }) -join " ")
  $command = 'cd /d "{0}" && "{1}" {2} 1>> "{3}" 2>> "{4}"' -f $Root, $python.File, $argString, $LogFile, $ErrorLogFile

  $launcher = Start-Process `
    -FilePath $env:ComSpec `
    -ArgumentList @("/d", "/c", $command) `
    -WindowStyle Hidden `
    -PassThru

  $deadline = (Get-Date).AddSeconds(8)
  do {
    Start-Sleep -Milliseconds 200
    $listener = Get-PortListener
    if ($listener) {
      Set-Content -LiteralPath $PidFile -Value $listener.OwningProcess -Encoding ascii
      Write-Host "Server running at $Url (PID $($listener.OwningProcess))"
      return
    }
  } while ((Get-Date) -lt $deadline)

  if ($launcher -and (Get-Process -Id $launcher.Id -ErrorAction SilentlyContinue)) {
    Stop-Process -Id $launcher.Id -Force -ErrorAction SilentlyContinue
  }

  throw "Server did not start listening on $Url within 8 seconds. See $ErrorLogFile."
}

function Stop-WebServer {
  $managed = Get-ManagedProcess
  if (-not $managed) {
    Write-Host "No managed server is running."
    return
  }

  Stop-Process -Id $managed.Id -Force
  Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
  Write-Host "Stopped server PID $($managed.Id)."
}

function Show-WebServerStatus {
  $managed = Get-ManagedProcess
  if ($managed) {
    Write-Host "Managed server running at $Url (PID $($managed.Id))"
    return
  }

  $listener = Get-PortListener
  if ($listener) {
    Write-Host "Port $Port is in use by unmanaged PID $($listener.OwningProcess)."
    return
  }

  Write-Host "Server is stopped. Run webserver.cmd start to launch $Url"
}

switch ($Action.ToLowerInvariant()) {
  "start" {
    Start-WebServer
  }
  "stop" {
    Stop-WebServer
  }
  "reset" {
    Stop-WebServer
    Start-WebServer
  }
  "restart" {
    Stop-WebServer
    Start-WebServer
  }
  "status" {
    Show-WebServerStatus
  }
  "help" {
    Write-Host "Usage:"
    Write-Host "  webserver.cmd start"
    Write-Host "  webserver.cmd stop"
    Write-Host "  webserver.cmd status"
    Write-Host "  webserver.cmd reset"
    Write-Host ""
    Write-Host "Defaults:"
    Write-Host "  URL:  $Url"
    Write-Host "  Port: $Port (override with: set SERVER_PORT=5000)"
    Write-Host ""
    Write-Host "Runtime file:"
    Write-Host "  .webserver.pid"
    Write-Host "  .webserver.log"
    Write-Host "  .webserver.error.log"
  }
  "-h" {
    & $PSCommandPath help
  }
  "/?" {
    & $PSCommandPath help
  }
  default {
    throw "Unknown command '$Action'. Run webserver.cmd help."
  }
}
