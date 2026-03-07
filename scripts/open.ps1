param(
  [switch]$Adminer,
  [switch]$Direct
)

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

function Open-Url([string]$Url) {
  if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
    Start-Process $Url | Out-Null
    return
  }

  if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
    & open $Url
    return
  }

  & xdg-open $Url
}

function Format-ProxyUrl([string]$HostName, [string]$Port) {
  if ($Port -eq "80") {
    return "http://$HostName"
  }

  return "http://{0}:{1}" -f $HostName, $Port
}

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
& (Join-Path $PSScriptRoot "bootstrap-env.ps1") -Quiet
$settings = Get-EnvSettings (Join-Path $root ".env")

  if ($Adminer) {
  if ($Direct) {
    $url = "http://127.0.0.1:{0}" -f $settings["ADMINER_PUBLISHED_PORT"]
  }
  else {
    $url = Format-ProxyUrl -HostName ("db-{0}" -f $settings["WP_HOSTNAME"]) -Port $settings["PROXY_HTTP_PORT"]
  }
}
else {
  if ($Direct) {
    $url = "http://localhost:{0}" -f $settings["WORDPRESS_PUBLISHED_PORT"]
  }
  else {
    $url = $settings["WP_URL"]
  }
}

Open-Url $url
Write-Host $url
