param(
  [switch]$Detached,
  [switch]$WithTools,
  [switch]$WithProxy,
  [switch]$WithMail,
  [switch]$WithXdebug
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $PSBoundParameters.ContainsKey("Detached")) {
  $Detached = $true
}

if (-not $PSBoundParameters.ContainsKey("WithProxy")) {
  $WithProxy = $true
}

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

function Wait-HttpReady([string]$Url, [hashtable]$Headers = @{}, [int]$Attempts = 45, [int]$DelaySeconds = 2) {
  for ($i = 0; $i -lt $Attempts; $i++) {
    try {
      $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -Headers $Headers -TimeoutSec 5
      if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
        return $true
      }
    }
    catch {
      $response = $null
      if ($_.Exception.PSObject.Properties.Name -contains "Response") {
        $response = $_.Exception.Response
      }
      if ($response -and $response.StatusCode.value__ -ge 200 -and $response.StatusCode.value__ -lt 400) {
        return $true
      }
    }
    Start-Sleep -Seconds $DelaySeconds
  }

  return $false
}

function Format-ProxyUrl([string]$HostName, [string]$Port) {
  if ($Port -eq "80") {
    return "http://$HostName"
  }

  return "http://{0}:{1}" -f $HostName, $Port
}

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$bootstrapScript = Join-Path $PSScriptRoot "bootstrap-env.ps1"
& $bootstrapScript -Quiet

$envPath = Join-Path $root ".env"
$settings = Get-EnvSettings $envPath

if (-not $PSBoundParameters.ContainsKey("WithMail")) {
  $WithMail = $settings.ContainsKey("ENABLE_MAILPIT") -and (Is-True $settings["ENABLE_MAILPIT"])
}

if (-not $PSBoundParameters.ContainsKey("WithXdebug")) {
  $WithXdebug = $settings.ContainsKey("ENABLE_XDEBUG") -and (Is-True $settings["ENABLE_XDEBUG"])
}

Write-Host ("Install Path: {0}" -f $root.Path)

foreach ($secretName in @("MARIADB_ROOT_PASSWORD", "WORDPRESS_DB_PASSWORD", "WP_ADMIN_PASSWORD")) {
  if ($settings.ContainsKey($secretName) -and (Test-PlaceholderSecret $settings[$secretName])) {
    Write-Warning "$secretName still uses a placeholder value in .env."
  }
}

if ($WithProxy) {
  & (Join-Path $PSScriptRoot "hosts-sync.ps1") -WithTools:$WithTools -WithMail:$WithMail -Quiet
  & (Join-Path $PSScriptRoot "proxy-sync.ps1") -WithTools:$WithTools -WithMail:$WithMail
  & (Join-Path $PSScriptRoot "proxy-up.ps1")
}

$composeFileArgs = @("-f", "docker-compose.yml")
if ($WithXdebug) {
  $composeFileArgs += @("-f", "docker-compose.xdebug.yml")
}

$profileArgs = @()
if ($WithTools) {
  $profileArgs += @("--profile", "tools")
}
if ($WithMail) {
  $profileArgs += @("--profile", "mail")
}

Push-Location $root
try {
  $previousEnableMailpit = $env:ENABLE_MAILPIT
  if ($WithMail) {
    $env:ENABLE_MAILPIT = "true"
  }

  $composeArgs = @()
  if ($Detached) {
    $composeArgs += "-d"
  }
  $composeArgs += "--remove-orphans"
  docker compose @composeFileArgs @profileArgs up @composeArgs

  if ($Detached) {
    $hostName = $settings["WP_HOSTNAME"]
    $wpUrl = $settings["WP_URL"]
    $wpPort = $settings["WORDPRESS_PUBLISHED_PORT"]
    $directUrl = "http://127.0.0.1:{0}" -f $wpPort
    [void](Wait-HttpReady -Url $directUrl -Attempts 35)

    if ($WithProxy) {
      [void](Wait-HttpReady -Url $wpUrl -Attempts 10)
    }

    if ($WithTools -and $settings.ContainsKey("ADMINER_PUBLISHED_PORT")) {
      $adminerDirectUrl = "http://127.0.0.1:{0}" -f $settings["ADMINER_PUBLISHED_PORT"]
      [void](Wait-HttpReady -Url $adminerDirectUrl -Attempts 10)
      if ($WithProxy) {
        $adminerProxyUrl = Format-ProxyUrl -HostName ("db-{0}" -f $hostName) -Port $settings["PROXY_HTTP_PORT"]
        [void](Wait-HttpReady -Url $adminerProxyUrl -Attempts 10)
      }
    }

    if ($WithMail -and $settings.ContainsKey("MAILPIT_PUBLISHED_PORT")) {
      $mailpitDirectUrl = "http://127.0.0.1:{0}" -f $settings["MAILPIT_PUBLISHED_PORT"]
      [void](Wait-HttpReady -Url $mailpitDirectUrl -Attempts 10)
      if ($WithProxy) {
        $mailpitProxyUrl = Format-ProxyUrl -HostName ("mail-{0}" -f $hostName) -Port $settings["PROXY_HTTP_PORT"]
        [void](Wait-HttpReady -Url $mailpitProxyUrl -Attempts 10)
      }
    }

    $hostMode = if ($WithProxy) { "localhost" } else { "direct-only" }
    Write-Host ("Host Mode: {0}" -f $hostMode)
    Write-Host ("Direct URL: http://localhost:{0}" -f $wpPort)
    Write-Host ("Xdebug: {0}" -f ($(if ($WithXdebug) { "enabled" } else { "disabled" })))

    if ($WithProxy) {
      Write-Host ("Proxy URL: " + $wpUrl)
    }

    if ($WithTools -and $settings.ContainsKey("ADMINER_PUBLISHED_PORT")) {
      $bindHost = if ($settings.ContainsKey("WORDPRESS_BIND_ADDRESS")) { $settings["WORDPRESS_BIND_ADDRESS"] } else { "127.0.0.1" }
      Write-Host ("Adminer URL: http://{0}:{1}" -f $bindHost, $settings["ADMINER_PUBLISHED_PORT"])
      if ($WithProxy) {
        Write-Host ("Adminer Proxy URL: " + (Format-ProxyUrl -HostName ("db-{0}" -f $hostName) -Port $settings["PROXY_HTTP_PORT"]))
      }
    }

    if ($WithMail -and $settings.ContainsKey("MAILPIT_PUBLISHED_PORT")) {
      $bindHost = if ($settings.ContainsKey("WORDPRESS_BIND_ADDRESS")) { $settings["WORDPRESS_BIND_ADDRESS"] } else { "127.0.0.1" }
      Write-Host ("Mailpit URL: http://{0}:{1}" -f $bindHost, $settings["MAILPIT_PUBLISHED_PORT"])
      if ($WithProxy) {
        Write-Host ("Mailpit Proxy URL: " + (Format-ProxyUrl -HostName ("mail-{0}" -f $hostName) -Port $settings["PROXY_HTTP_PORT"]))
      }
    }
  }
}
finally {
  if ($null -eq $previousEnableMailpit) {
    Remove-Item Env:ENABLE_MAILPIT -ErrorAction SilentlyContinue
  }
  else {
    $env:ENABLE_MAILPIT = $previousEnableMailpit
  }
  Pop-Location
}
