param(
  [switch]$Detached,
  [switch]$WithTools,
  [switch]$WithProxy
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

Write-Host ("Install Path: {0}" -f $root.Path)

foreach ($secretName in @("MARIADB_ROOT_PASSWORD", "WORDPRESS_DB_PASSWORD", "WP_ADMIN_PASSWORD")) {
  if ($settings.ContainsKey($secretName) -and (Test-PlaceholderSecret $settings[$secretName])) {
    Write-Warning "$secretName still uses a placeholder value in .env."
  }
}

if ($WithProxy) {
  if ($WithTools) {
    & (Join-Path $PSScriptRoot "hosts-sync.ps1") -WithTools -Quiet
  }
  else {
    & (Join-Path $PSScriptRoot "hosts-sync.ps1") -Quiet
  }

  if ($WithTools) {
    & (Join-Path $PSScriptRoot "proxy-sync.ps1") -WithTools
  }
  else {
    & (Join-Path $PSScriptRoot "proxy-sync.ps1")
  }
  & (Join-Path $PSScriptRoot "proxy-up.ps1")
}

$profileArgs = @()
if ($WithTools) {
  $profileArgs += @("--profile", "tools")
}

Push-Location $root
try {
  $composeArgs = @()
  if ($Detached) {
    $composeArgs += "-d"
  }
  $composeArgs += "--remove-orphans"
  docker compose @profileArgs up @composeArgs

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

    $hostMode = if ($WithProxy) { "localhost" } else { "direct-only" }
    Write-Host ("Host Mode: {0}" -f $hostMode)
    Write-Host ("Direct URL: http://localhost:{0}" -f $wpPort)

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
  }
}
finally {
  Pop-Location
}
