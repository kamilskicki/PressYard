param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$WpArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($WpArgs.Count -eq 0) {
  throw "Pass WP-CLI arguments, for example: .\scripts\wp.ps1 plugin list"
}

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
& (Join-Path $PSScriptRoot "bootstrap-env.ps1") -Quiet

Push-Location $root
try {
  docker compose --profile ops run --rm --no-deps wp-cli @WpArgs
}
finally {
  Pop-Location
}
