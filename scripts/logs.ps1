param(
  [string]$Service,
  [switch]$Follow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")

Push-Location $root
try {
  $args = @()
  if ($Follow) {
    $args += "-f"
  }
  if (-not [string]::IsNullOrWhiteSpace($Service)) {
    $args += $Service
  }
  docker compose logs @args
}
finally {
  Pop-Location
}
