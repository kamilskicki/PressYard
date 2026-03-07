param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$WpArgs
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

function Is-True([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $false
  }

  return @("1", "true", "yes", "on") -contains $Value.Trim().ToLowerInvariant()
}

if ($WpArgs.Count -eq 0) {
  throw "Pass WP-CLI arguments, for example: .\scripts\wp.ps1 plugin list"
}

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
& (Join-Path $PSScriptRoot "bootstrap-env.ps1") -Quiet
$settings = Get-EnvSettings (Join-Path $root ".env")
$projectName = $settings["COMPOSE_PROJECT_NAME"]
$mailpitRunning = docker ps --filter "label=com.docker.compose.project=$projectName" --filter "label=com.docker.compose.service=mailpit" --format "{{.Names}}" | Select-Object -First 1

$previousEnableMailpit = $env:ENABLE_MAILPIT
if ((Is-True $settings["ENABLE_MAILPIT"]) -or -not [string]::IsNullOrWhiteSpace($mailpitRunning)) {
  $env:ENABLE_MAILPIT = "true"
}

Push-Location $root
try {
  docker compose --profile ops run --rm --no-deps wp-cli @WpArgs
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
