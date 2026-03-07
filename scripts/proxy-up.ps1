Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-EnvSettings([string]$Path) {
  $settings = @{}
  foreach ($line in Get-Content $Path) {
    if ($line -match "^\s*#" -or $line -notmatch "=") {
      continue
    }
    $parts = $line.Split("=", 2)
    $settings[$parts[0].Trim()] = $parts[1].Trim()
  }
  return $settings
}

function Test-PortAvailable([int]$Port) {
  $listener = $null
  try {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
    $listener.Start()
    return $true
  }
  catch {
    return $false
  }
  finally {
    if ($listener -ne $null) {
      $listener.Stop()
    }
  }
}

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$bootstrapScript = Join-Path $PSScriptRoot "bootstrap-env.ps1"
& $bootstrapScript -Quiet
$envPath = Join-Path $root ".env"
$settings = if (Test-Path $envPath) { Get-EnvSettings $envPath } else { @{} }

$projectName = if ($settings.ContainsKey("PROXY_PROJECT_NAME")) { $settings["PROXY_PROJECT_NAME"] } else { "pressyard-proxy" }
$httpPort = if ($settings.ContainsKey("PROXY_HTTP_PORT")) { [int]$settings["PROXY_HTTP_PORT"] } else { 80 }
$dashboardPort = if ($settings.ContainsKey("PROXY_DASHBOARD_PORT")) { [int]$settings["PROXY_DASHBOARD_PORT"] } else { 8089 }
$configDir = if ($settings.ContainsKey("PROXY_CONFIG_DIR")) { $settings["PROXY_CONFIG_DIR"] } else { Join-Path $env:LOCALAPPDATA "pressyard\\proxy\\dynamic" }

if (-not (Test-Path $configDir)) {
  New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

$projectRunning = docker ps --filter "label=com.docker.compose.project=$projectName" --format "{{.Names}}" | Select-Object -First 1
if (-not $projectRunning) {
  if (-not (Test-PortAvailable $httpPort)) {
    throw "Proxy HTTP port $httpPort is already in use. Set PROXY_HTTP_PORT in .env to a free port and rerun."
  }
  if (-not (Test-PortAvailable $dashboardPort)) {
    throw "Proxy dashboard port $dashboardPort is already in use. Set PROXY_DASHBOARD_PORT in .env to a free port and rerun."
  }
}

Push-Location $root
try {
  docker compose -f docker-compose.proxy.yml --project-name $projectName up -d --force-recreate --remove-orphans
}
finally {
  Pop-Location
}
