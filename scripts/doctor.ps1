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

function Test-IsAdmin {
  if (-not (Test-IsWindows)) {
    return ([System.Environment]::UserName -eq "root")
  }

  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-HostsPath {
  if (Test-IsWindows) {
    return Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
  }

  return "/etc/hosts"
}

function Write-Check([string]$Label, [string]$Status, [string]$Detail) {
  Write-Host ("[{0}] {1}: {2}" -f $Status, $Label, $Detail)
}

function Test-PlaceholderSecret([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $true
  }

  return $Value -match "^change-this-"
}

function Is-True([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $false
  }

  return @("1", "true", "yes", "on") -contains $Value.Trim().ToLowerInvariant()
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
& (Join-Path $PSScriptRoot "bootstrap-env.ps1") -Quiet
$settings = Get-EnvSettings (Join-Path $root ".env")

$dockerVersion = docker version --format "{{.Server.Version}}" 2>$null
if ([string]::IsNullOrWhiteSpace($dockerVersion)) {
  Write-Check "Docker" "WARN" "Docker daemon unavailable. Start Docker Desktop or Docker Engine."
}
else {
  Write-Check "Docker" "OK" ("Server {0}" -f $dockerVersion)
}

$composeVersion = docker compose version 2>$null
if ($LASTEXITCODE -eq 0) {
  Write-Check "Compose" "OK" $composeVersion
}
else {
  Write-Check "Compose" "WARN" "Docker Compose plugin unavailable."
}

$projectName = $settings["COMPOSE_PROJECT_NAME"]
$siteUrl = $settings["WP_URL"]
$hostMode = if ($settings.ContainsKey("HOST_RESOLUTION_MODE")) { $settings["HOST_RESOLUTION_MODE"] } else { "unknown" }
$proxyProjectName = $settings["PROXY_PROJECT_NAME"]
$proxyPort = [int]$settings["PROXY_HTTP_PORT"]
$xdebugEnabled = Is-True $settings["ENABLE_XDEBUG"]
$mailpitEnabled = Is-True $settings["ENABLE_MAILPIT"]

Write-Check "Project" "OK" $projectName
Write-Check "Install Path" "OK" $root.Path
Write-Check "Site URL" "OK" $siteUrl
Write-Check "Host Mode" "OK" $hostMode
Write-Check "Mailpit" "OK" ($(if ($mailpitEnabled) { "enabled in .env" } else { "disabled in .env" }))
Write-Check "Xdebug" "OK" ($(if ($xdebugEnabled) { "enabled in .env" } else { "disabled in .env" }))

if ($hostMode -eq "localhost-only") {
  $isAdmin = Test-IsAdmin
  $adminDetail = if ($isAdmin) { "terminal can manage hosts-file entries" } else { "run PowerShell as Administrator for clean .localhost URLs" }
  Write-Check "Privileges" ($(if ($isAdmin) { "OK" } else { "WARN" })) $adminDetail

  $hostsPath = Get-HostsPath
  if (Test-Path $hostsPath) {
    $hostsContent = Get-Content $hostsPath -Raw
    $hostPresent = $hostsContent -match ("(^|\s){0}(\s|$)" -f [Regex]::Escape($settings["WP_HOSTNAME"]))
    Write-Check "Hosts Entry" ($(if ($hostPresent) { "OK" } else { "WARN" })) ($(if ($hostPresent) { "$($settings["WP_HOSTNAME"]) mapped in $hostsPath" } else { "missing $($settings["WP_HOSTNAME"]) in $hostsPath" }))

    if ($mailpitEnabled) {
      $mailHost = "mail-$($settings["WP_HOSTNAME"])"
      $mailPresent = $hostsContent -match ("(^|\s){0}(\s|$)" -f [Regex]::Escape($mailHost))
      Write-Check "Mailpit Host" ($(if ($mailPresent) { "OK" } else { "WARN" })) ($(if ($mailPresent) { "$mailHost mapped in $hostsPath" } else { "missing $mailHost in $hostsPath" }))
    }
  }
  else {
    Write-Check "Hosts Entry" "WARN" ("hosts file not found at {0}" -f $hostsPath)
  }
}

$proxyRunning = docker ps --filter "label=com.docker.compose.project=$proxyProjectName" --format "{{.Names}}" 2>$null
$proxyConfigPath = Join-Path $settings["PROXY_CONFIG_DIR"] ("{0}.yml" -f $projectName)
if (-not (Test-PortAvailable $proxyPort)) {
  if (-not [string]::IsNullOrWhiteSpace(($proxyRunning | Select-Object -First 1))) {
    Write-Check "Proxy Port" "OK" ("port {0} owned by {1}" -f $proxyPort, (($proxyRunning | Select-Object -First 1)))
  }
  else {
    Write-Check "Proxy Port" "WARN" ("port {0} is busy and not owned by the shared proxy" -f $proxyPort)
  }
}
else {
  Write-Check "Proxy Port" "OK" ("port {0} is free" -f $proxyPort)
}

if (Test-Path $proxyConfigPath) {
  Write-Check "Proxy Route" "OK" ("found {0}" -f $proxyConfigPath)
}
else {
  Write-Check "Proxy Route" "WARN" ("missing {0}" -f $proxyConfigPath)
}

foreach ($secretName in @("MARIADB_ROOT_PASSWORD", "WORDPRESS_DB_PASSWORD", "WP_ADMIN_PASSWORD")) {
  $placeholder = Test-PlaceholderSecret $settings[$secretName]
  $detail = if ($placeholder) { "placeholder value still set" } else { "customized" }
  Write-Check $secretName ($(if ($placeholder) { "WARN" } else { "OK" })) $detail
}

$packagesPath = Join-Path $root "packages"
$packageCount = @(Get-ChildItem $packagesPath -Filter *.zip -File -ErrorAction SilentlyContinue).Count
Write-Check "Packages" "OK" ("{0} ZIP package(s) in {1}" -f $packageCount, $packagesPath)

$running = docker ps --filter "label=com.docker.compose.project=$projectName" --format "{{.Names}}" 2>$null
$runningList = @($running | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($runningList.Count -gt 0) {
  Write-Check "Containers" "OK" ($runningList -join ", ")
  Write-Host ""
  Write-Host "Ready:"
  Write-Host ("  .\open.ps1           -> {0}" -f $settings["WP_URL"])
  if ($mailpitEnabled) {
    Write-Host ("  .\open.ps1 -Mailpit  -> http://mail-{0}" -f $settings["WP_HOSTNAME"])
  }
}
else {
  Write-Check "Containers" "WARN" "Project is not running."
  Write-Host ""
  Write-Host "Next step:"
  if ($hostMode -eq "localhost-only" -and -not (Test-IsAdmin)) {
    Write-Host "  Start PowerShell as Administrator, then run .\up.ps1"
  }
  else {
    $nextArgs = New-Object System.Collections.Generic.List[string]
    $nextArgs.Add(".\up.ps1")
    if (Is-True $settings["ENABLE_MAILPIT"]) {
      $nextArgs.Add("-WithMail")
    }
    if (Is-True $settings["ENABLE_XDEBUG"]) {
      $nextArgs.Add("-WithXdebug")
    }
    Write-Host ("  {0}" -f ($nextArgs -join " "))
  }
}
