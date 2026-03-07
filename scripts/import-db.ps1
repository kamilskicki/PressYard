param(
  [Parameter(Mandatory = $true)]
  [string]$InputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
& (Join-Path $PSScriptRoot "bootstrap-env.ps1") -Quiet

$resolvedInput = if ([System.IO.Path]::IsPathRooted($InputPath)) {
  [System.IO.Path]::GetFullPath($InputPath)
} else {
  [System.IO.Path]::GetFullPath((Join-Path $root $InputPath))
}

if (-not (Test-Path $resolvedInput)) {
  throw "SQL file not found: $resolvedInput"
}

Push-Location $root
try {
  Get-Content $resolvedInput | docker compose exec -T db sh -lc 'exec mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"'
}
finally {
  Pop-Location
}

Write-Host ("Database imported from {0}" -f $resolvedInput)
