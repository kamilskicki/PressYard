param(
  [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-IsWindows {
  return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
}

function Test-IsMacOS {
  return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)
}

function Join-ForwardPath([string[]]$Segments) {
  $clean = @()
  foreach ($segment in $Segments) {
    if ([string]::IsNullOrWhiteSpace($segment)) {
      continue
    }
    $clean += $segment.TrimEnd("/", "\").TrimStart("/", "\")
  }

  if ($clean.Count -eq 0) {
    return ""
  }

  $prefix = ""
  if ($Segments[0] -match "^[A-Za-z]:[\\/]*$") {
    $prefix = $Segments[0].Substring(0, 2) + "/"
    $clean = $clean[1..($clean.Count - 1)]
  }

  return $prefix + ($clean -join "/")
}

function Get-DefaultProxyConfigDir {
  if (Test-IsWindows) {
    $localAppData = if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE "AppData\\Local" }
    return Join-ForwardPath @($localAppData, "pressyard", "proxy", "dynamic")
  }

  if (Test-IsMacOS) {
    $base = if (-not [string]::IsNullOrWhiteSpace($env:HOME)) { $env:HOME } else { "~" }
    return ($base.TrimEnd("/") + "/Library/Application Support/pressyard/proxy/dynamic")
  }

  $xdgState = if (-not [string]::IsNullOrWhiteSpace($env:XDG_STATE_HOME)) { $env:XDG_STATE_HOME } else { "" }
  if (-not [string]::IsNullOrWhiteSpace($xdgState)) {
    return ($xdgState.TrimEnd("/") + "/pressyard/proxy/dynamic")
  }

  $home = if (-not [string]::IsNullOrWhiteSpace($env:HOME)) { $env:HOME } else { "~" }
  return ($home.TrimEnd("/") + "/.local/state/pressyard/proxy/dynamic")
}

function Get-OldDefaultProxyConfigDir {
  if (Test-IsWindows) {
    $localAppData = if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE "AppData\\Local" }
    return Join-ForwardPath @($localAppData, "wpdraft", "proxy", "dynamic")
  }

  if (Test-IsMacOS) {
    $base = if (-not [string]::IsNullOrWhiteSpace($env:HOME)) { $env:HOME } else { "~" }
    return ($base.TrimEnd("/") + "/Library/Application Support/wpdraft/proxy/dynamic")
  }

  $xdgState = if (-not [string]::IsNullOrWhiteSpace($env:XDG_STATE_HOME)) { $env:XDG_STATE_HOME } else { "" }
  if (-not [string]::IsNullOrWhiteSpace($xdgState)) {
    return ($xdgState.TrimEnd("/") + "/wpdraft/proxy/dynamic")
  }

  $home = if (-not [string]::IsNullOrWhiteSpace($env:HOME)) { $env:HOME } else { "~" }
  return ($home.TrimEnd("/") + "/.local/state/wpdraft/proxy/dynamic")
}

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$envPath = Join-Path $root ".env"
$examplePath = Join-Path $root ".env.example"

if (-not (Test-Path $envPath)) {
  Copy-Item $examplePath $envPath
}

$lines = Get-Content $envPath
$settings = @{}
foreach ($line in $lines) {
  if ($line -match "^\s*#" -or $line -notmatch "=") {
    continue
  }
  $parts = $line.Split("=", 2)
  $settings[$parts[0].Trim()] = $parts[1]
}

function Get-HashHex([string]$value) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($value)
    $hash = $sha.ComputeHash($bytes)
    return -join ($hash | ForEach-Object { $_.ToString("x2") })
  }
  finally {
    $sha.Dispose()
  }
}

function Test-PortAvailable([int]$port) {
  $listener = $null
  try {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
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

function Is-True([string]$value) {
  if ($null -eq $value) {
    return $false
  }
  return @("1", "true", "yes", "on") -contains $value.Trim().ToLowerInvariant()
}

function Test-ComposeProjectNameReserved([string]$projectName, [string]$currentProjectName) {
  if ([string]::IsNullOrWhiteSpace($projectName)) {
    return $true
  }

  if ($projectName -eq $currentProjectName) {
    return $false
  }

  $containerMatch = docker ps -a --filter "label=com.docker.compose.project=$projectName" --format "{{.Names}}" | Select-Object -First 1
  if ($containerMatch) {
    return $true
  }

  $networkMatch = docker network ls --filter "label=com.docker.compose.project=$projectName" --format "{{.Name}}" | Select-Object -First 1
  if ($networkMatch) {
    return $true
  }

  return $false
}

function Test-HostNameReserved([string]$hostName, [string]$configDir, [string]$currentProjectName) {
  if ([string]::IsNullOrWhiteSpace($hostName)) {
    return $true
  }

  if ([string]::IsNullOrWhiteSpace($configDir) -or -not (Test-Path $configDir)) {
    return $false
  }

  $pattern = 'Host\(`' + [Regex]::Escape($hostName) + '`\)'
  $configFiles = Get-ChildItem -Path $configDir -Filter *.yml -File -ErrorAction SilentlyContinue
  foreach ($file in $configFiles) {
    if ($file.BaseName -eq $currentProjectName) {
      continue
    }

    if (Select-String -Path $file.FullName -Pattern $pattern -Quiet) {
      return $true
    }
  }

  return $false
}

function Get-AvailableProjectName([string]$baseName, [string]$hashHex, [string]$currentProjectName) {
  if (-not (Test-ComposeProjectNameReserved -projectName $baseName -currentProjectName $currentProjectName)) {
    return $baseName
  }

  return "$baseName-$($hashHex.Substring(0, 8))"
}

function Get-AvailableHostName([string]$baseName, [string]$hashHex, [string]$configDir, [string]$currentProjectName) {
  $preferredHostName = "$baseName.localhost"
  if (-not (Test-HostNameReserved -hostName $preferredHostName -configDir $configDir -currentProjectName $currentProjectName)) {
    return $preferredHostName
  }

  return "$baseName-$($hashHex.Substring(0, 8)).localhost"
}

function Test-PortBoundByProject([int]$port, [string]$projectName) {
  if ([string]::IsNullOrWhiteSpace($projectName)) {
    return $false
  }

  $lines = docker ps --filter "label=com.docker.compose.project=$projectName" --format "{{.Ports}}"
  foreach ($line in $lines) {
    if ($line.Contains(":$port->") -or $line.Contains("]:$port->")) {
      return $true
    }
  }

  return $false
}

function Find-AvailablePort([long]$seed, [int]$minPort = 10000, [int]$maxPort = 59999) {
  if ($maxPort -le $minPort) {
    throw "Invalid port range."
  }

  $span = ($maxPort - $minPort) + 1
  $normalizedSeed = [Math]::Abs($seed)
  $candidate = $minPort + ($normalizedSeed % $span)

  for ($i = 0; $i -lt $span; $i++) {
    $probe = $candidate + $i
    if ($probe -gt $maxPort) {
      $probe = $minPort + ($probe - $maxPort - 1)
    }
    if (Test-PortAvailable $probe) {
      return $probe
    }
  }

  throw "Could not find an available host port in range $minPort-$maxPort."
}

$resolvedPath = ($root.Path).ToLowerInvariant()
$hashHex = Get-HashHex $resolvedPath
$slug = [Regex]::Replace((Split-Path $resolvedPath -Leaf), "[^a-z0-9]+", "-").Trim("-")
if ([string]::IsNullOrWhiteSpace($slug)) {
  $slug = "wp"
}

$currentProjectName = if ($settings.ContainsKey("COMPOSE_PROJECT_NAME")) { $settings["COMPOSE_PROJECT_NAME"] } else { "" }
$baseProjectName = $slug
$resolvedProjectName = Get-AvailableProjectName -baseName $baseProjectName -hashHex $hashHex -currentProjectName $currentProjectName

$autoNamespace = $true
if ($settings.ContainsKey("AUTO_NAMESPACE")) {
  $autoNamespace = Is-True $settings["AUTO_NAMESPACE"]
}
if ($autoNamespace -or -not $settings.ContainsKey("COMPOSE_PROJECT_NAME") -or [string]::IsNullOrWhiteSpace($settings["COMPOSE_PROJECT_NAME"])) {
  $settings["COMPOSE_PROJECT_NAME"] = $resolvedProjectName
}

if (-not $settings.ContainsKey("WORDPRESS_BIND_ADDRESS") -or [string]::IsNullOrWhiteSpace($settings["WORDPRESS_BIND_ADDRESS"])) {
  $settings["WORDPRESS_BIND_ADDRESS"] = "127.0.0.1"
}

if (-not $settings.ContainsKey("PROXY_PROJECT_NAME") -or [string]::IsNullOrWhiteSpace($settings["PROXY_PROJECT_NAME"])) {
  $settings["PROXY_PROJECT_NAME"] = "pressyard-proxy"
}
elseif ($settings["PROXY_PROJECT_NAME"] -eq "wpdraft-proxy") {
  $settings["PROXY_PROJECT_NAME"] = "pressyard-proxy"
}

if (-not $settings.ContainsKey("PROXY_BIND_ADDRESS") -or [string]::IsNullOrWhiteSpace($settings["PROXY_BIND_ADDRESS"])) {
  $settings["PROXY_BIND_ADDRESS"] = "127.0.0.1"
}

if (-not $settings.ContainsKey("PROXY_HTTP_PORT") -or [string]::IsNullOrWhiteSpace($settings["PROXY_HTTP_PORT"])) {
  $settings["PROXY_HTTP_PORT"] = "80"
}
elseif ($settings["PROXY_HTTP_PORT"] -eq "8088") {
  $settings["PROXY_HTTP_PORT"] = "80"
}

if (-not $settings.ContainsKey("PROXY_DASHBOARD_PORT") -or [string]::IsNullOrWhiteSpace($settings["PROXY_DASHBOARD_PORT"])) {
  $settings["PROXY_DASHBOARD_PORT"] = "8089"
}

if (-not $settings.ContainsKey("PROXY_CONFIG_DIR") -or [string]::IsNullOrWhiteSpace($settings["PROXY_CONFIG_DIR"])) {
  $settings["PROXY_CONFIG_DIR"] = Get-DefaultProxyConfigDir
}
else {
  $settings["PROXY_CONFIG_DIR"] = (($settings["PROXY_CONFIG_DIR"] -replace "\\", "/") -replace "/{2,}", "/")
  if ($settings["PROXY_CONFIG_DIR"] -eq (Get-OldDefaultProxyConfigDir) -or $settings["PROXY_CONFIG_DIR"] -match "/wpdraft/proxy/dynamic/?$") {
    $settings["PROXY_CONFIG_DIR"] = Get-DefaultProxyConfigDir
  }
}

if (-not $settings.ContainsKey("WORDPRESS_IMAGE") -or [string]::IsNullOrWhiteSpace($settings["WORDPRESS_IMAGE"])) {
  $settings["WORDPRESS_IMAGE"] = "wordpress:6.8.2-php8.2-apache"
}

if (-not $settings.ContainsKey("WORDPRESS_CLI_IMAGE") -or [string]::IsNullOrWhiteSpace($settings["WORDPRESS_CLI_IMAGE"])) {
  $settings["WORDPRESS_CLI_IMAGE"] = "wordpress:cli-php8.2"
}

if (-not $settings.ContainsKey("MARIADB_IMAGE") -or [string]::IsNullOrWhiteSpace($settings["MARIADB_IMAGE"])) {
  $settings["MARIADB_IMAGE"] = "mariadb:11.4.10"
}

if (-not $settings.ContainsKey("TRAEFIK_IMAGE") -or [string]::IsNullOrWhiteSpace($settings["TRAEFIK_IMAGE"])) {
  $settings["TRAEFIK_IMAGE"] = "traefik:v3.1"
}

if (-not $settings.ContainsKey("ADMINER_IMAGE") -or [string]::IsNullOrWhiteSpace($settings["ADMINER_IMAGE"])) {
  $settings["ADMINER_IMAGE"] = "adminer:4.8.1-standalone"
}

$autoHostname = $true
if ($settings.ContainsKey("AUTO_HOSTNAME")) {
  $autoHostname = Is-True $settings["AUTO_HOSTNAME"]
}
if ($autoHostname -or -not $settings.ContainsKey("WP_HOSTNAME") -or [string]::IsNullOrWhiteSpace($settings["WP_HOSTNAME"])) {
  $settings["WP_HOSTNAME"] = Get-AvailableHostName -baseName $slug -hashHex $hashHex -configDir $settings["PROXY_CONFIG_DIR"] -currentProjectName $settings["COMPOSE_PROJECT_NAME"]
}
$settings["HOST_RESOLUTION_MODE"] = "localhost-only"

$autoPort = $true
if ($settings.ContainsKey("AUTO_PORT")) {
  $autoPort = Is-True $settings["AUTO_PORT"]
}
if ($autoPort -or -not $settings.ContainsKey("WORDPRESS_PUBLISHED_PORT") -or [string]::IsNullOrWhiteSpace($settings["WORDPRESS_PUBLISHED_PORT"])) {
  $keepCurrentWordPressPort = $false
  if ($settings.ContainsKey("WORDPRESS_PUBLISHED_PORT")) {
    $currentWordPressPort = 0
    if ([int]::TryParse($settings["WORDPRESS_PUBLISHED_PORT"], [ref]$currentWordPressPort)) {
      if ((Test-PortAvailable $currentWordPressPort) -or (Test-PortBoundByProject -port $currentWordPressPort -projectName $settings["COMPOSE_PROJECT_NAME"])) {
        $keepCurrentWordPressPort = $true
      }
    }
  }

  if (-not $keepCurrentWordPressPort) {
    $seed = [Convert]::ToUInt32($hashHex.Substring(0, 8), 16)
    $port = Find-AvailablePort -seed $seed -minPort 10000 -maxPort 59999
    $settings["WORDPRESS_PUBLISHED_PORT"] = [string]$port
  }
}

$autoAdminerPort = $true
if ($settings.ContainsKey("AUTO_ADMINER_PORT")) {
  $autoAdminerPort = Is-True $settings["AUTO_ADMINER_PORT"]
}
if ($autoAdminerPort -or -not $settings.ContainsKey("ADMINER_PUBLISHED_PORT") -or [string]::IsNullOrWhiteSpace($settings["ADMINER_PUBLISHED_PORT"])) {
  $keepCurrentAdminerPort = $false
  if ($settings.ContainsKey("ADMINER_PUBLISHED_PORT")) {
    $currentAdminerPort = 0
    if ([int]::TryParse($settings["ADMINER_PUBLISHED_PORT"], [ref]$currentAdminerPort)) {
      if ((Test-PortAvailable $currentAdminerPort) -or (Test-PortBoundByProject -port $currentAdminerPort -projectName $settings["COMPOSE_PROJECT_NAME"])) {
        $keepCurrentAdminerPort = $true
      }
    }
  }

  if (-not $keepCurrentAdminerPort) {
    $adminerSeed = [Convert]::ToUInt32($hashHex.Substring(8, 8), 16)
    $adminerPort = Find-AvailablePort -seed $adminerSeed -minPort 10000 -maxPort 59999
    if ($adminerPort -eq [int]$settings["WORDPRESS_PUBLISHED_PORT"]) {
      $adminerPort = Find-AvailablePort -seed ($adminerSeed + 1) -minPort 10000 -maxPort 59999
    }
    $settings["ADMINER_PUBLISHED_PORT"] = [string]$adminerPort
  }
}

$proxyPort = $settings["PROXY_HTTP_PORT"]
$proxyPortSuffix = if ($proxyPort -eq "80") { "" } else { ":" + $proxyPort }
$settings["WP_URL"] = "http://$($settings["WP_HOSTNAME"])$proxyPortSuffix"
$settings["AUTO_NAMESPACE"] = if ($autoNamespace) { "true" } else { "false" }
$settings["AUTO_HOSTNAME"] = if ($autoHostname) { "true" } else { "false" }
$settings["AUTO_PORT"] = if ($autoPort) { "true" } else { "false" }
$settings["AUTO_ADMINER_PORT"] = if ($autoAdminerPort) { "true" } else { "false" }

$orderedKeys = @(
  "COMPOSE_PROJECT_NAME",
  "WORDPRESS_PUBLISHED_PORT",
  "WORDPRESS_BIND_ADDRESS",
  "WP_HOSTNAME",
  "ADMINER_PUBLISHED_PORT",
  "PROXY_PROJECT_NAME",
  "PROXY_BIND_ADDRESS",
  "PROXY_HTTP_PORT",
  "PROXY_DASHBOARD_PORT",
  "PROXY_CONFIG_DIR",
  "HOST_RESOLUTION_MODE",
  "WORDPRESS_IMAGE",
  "WORDPRESS_CLI_IMAGE",
  "MARIADB_IMAGE",
  "TRAEFIK_IMAGE",
  "ADMINER_IMAGE",
  "AUTO_NAMESPACE",
  "AUTO_HOSTNAME",
  "AUTO_PORT",
  "AUTO_ADMINER_PORT",
  "MARIADB_ROOT_PASSWORD",
  "WORDPRESS_DB_NAME",
  "WORDPRESS_DB_USER",
  "WORDPRESS_DB_PASSWORD",
  "WORDPRESS_TABLE_PREFIX",
  "WP_URL",
  "WP_SITE_TITLE",
  "WP_ADMIN_USER",
  "WP_ADMIN_PASSWORD",
  "WP_ADMIN_EMAIL",
  "WP_DEBUG"
)

$out = New-Object System.Collections.Generic.List[string]
foreach ($k in $orderedKeys) {
  if ($settings.ContainsKey($k)) {
    $out.Add("$k=$($settings[$k])")
  }
}
foreach ($k in $settings.Keys | Sort-Object) {
  if ($orderedKeys -notcontains $k -and $k -notin @("FALLBACK_HOST_SUFFIX")) {
    $out.Add("$k=$($settings[$k])")
  }
}

Set-Content -Path $envPath -Value $out -Encoding UTF8
if (-not $Quiet) {
  Write-Host "Prepared .env with COMPOSE_PROJECT_NAME=$($settings["COMPOSE_PROJECT_NAME"]), WP_URL=$($settings["WP_URL"]), and ADMINER_PUBLISHED_PORT=$($settings["ADMINER_PUBLISHED_PORT"])."
}
