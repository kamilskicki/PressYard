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

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$envPath = Join-Path $root ".env"
$projectName = "pressyard-proxy"

if (Test-Path $envPath) {
  $settings = Get-EnvSettings $envPath
  if ($settings.ContainsKey("PROXY_PROJECT_NAME") -and -not [string]::IsNullOrWhiteSpace($settings["PROXY_PROJECT_NAME"])) {
    $projectName = $settings["PROXY_PROJECT_NAME"]
  }
}

Push-Location $root
try {
  docker compose -f docker-compose.proxy.yml --project-name $projectName down --remove-orphans
}
finally {
  Pop-Location
}
