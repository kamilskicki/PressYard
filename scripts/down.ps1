param(
  [switch]$Volumes,
  [switch]$Proxy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
& (Join-Path $PSScriptRoot "hosts-sync.ps1") -Remove -Quiet
& (Join-Path $PSScriptRoot "proxy-sync.ps1") -Remove

Push-Location $root
try {
  $args = @("--profile", "tools", "--profile", "mail", "--profile", "ops", "down", "--remove-orphans")
  if ($Volumes) {
    $args += "-v"
  }
  docker compose @args

  if ($Proxy) {
    & (Join-Path $PSScriptRoot "proxy-down.ps1")
  }
}
finally {
  Pop-Location
}
