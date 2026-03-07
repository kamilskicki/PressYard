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

function Test-IsWindows {
  return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
}

function Get-HostsPath {
  if (Test-IsWindows) {
    return Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
  }

  return "/etc/hosts"
}

function Write-Check([string]$Label, [bool]$Ok, [string]$Detail) {
  $status = if ($Ok) { "OK" } else { "WARN" }
  Write-Host ("[{0}] {1}: {2}" -f $status, $Label, $Detail)
}

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
& (Join-Path $PSScriptRoot "bootstrap-env.ps1") -Quiet
$settings = Get-EnvSettings (Join-Path $root ".env")

$dockerVersion = docker version --format "{{.Server.Version}}" 2>$null
Write-Check "Docker" (-not [string]::IsNullOrWhiteSpace($dockerVersion)) ("Server {0}" -f $dockerVersion)

$composeVersion = docker compose version 2>$null
Write-Check "Compose" ($LASTEXITCODE -eq 0) $composeVersion

$siteUrl = $settings["WP_URL"]
$projectName = $settings["COMPOSE_PROJECT_NAME"]
Write-Check "Project" $true $projectName
Write-Check "Site URL" $true $siteUrl
$hostMode = if ($settings.ContainsKey("HOST_RESOLUTION_MODE")) { $settings["HOST_RESOLUTION_MODE"] } else { "unknown" }
Write-Check "Host Mode" $true $hostMode

if ($hostMode -eq "localhost-only") {
  $hostsPath = Get-HostsPath
  if (Test-Path $hostsPath) {
    $hostsContent = Get-Content $hostsPath -Raw
    $hostPresent = $hostsContent -match ("(^|\s){0}(\s|$)" -f [Regex]::Escape($settings["WP_HOSTNAME"]))
    $hostsDetail = if ($hostPresent) { "$($settings["WP_HOSTNAME"]) mapped in $hostsPath" } else { "missing $($settings["WP_HOSTNAME"]) in $hostsPath" }
    Write-Check "Hosts Entry" $hostPresent $hostsDetail
  }
  else {
    Write-Check "Hosts Entry" $false ("hosts file not found at {0}" -f $hostsPath)
  }
}

foreach ($secretName in @("MARIADB_ROOT_PASSWORD", "WORDPRESS_DB_PASSWORD", "WP_ADMIN_PASSWORD")) {
  $placeholder = $settings[$secretName] -match "^change-this-"
  $detail = if ($placeholder) { "placeholder value still set" } else { "customized" }
  Write-Check $secretName (-not $placeholder) $detail
}

$running = docker ps --filter "label=com.docker.compose.project=$projectName" --format "{{.Names}}" 2>$null
Write-Check "Containers" (-not [string]::IsNullOrWhiteSpace(($running | Select-Object -First 1))) ((@($running) -join ", "))
