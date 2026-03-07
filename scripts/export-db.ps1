param(
  [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
& (Join-Path $PSScriptRoot "bootstrap-env.ps1") -Quiet

$backupDir = Join-Path $root "backups"
if (-not (Test-Path $backupDir)) {
  New-Item -ItemType Directory -Path $backupDir | Out-Null
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutputPath = Join-Path $backupDir "db-$stamp.sql"
}

$resolvedOutput = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
  [System.IO.Path]::GetFullPath($OutputPath)
} else {
  [System.IO.Path]::GetFullPath((Join-Path $root $OutputPath))
}

Push-Location $root
try {
  docker compose exec -T db sh -lc 'exec mariadb-dump -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"' |
    Out-File -FilePath $resolvedOutput -Encoding utf8
}
finally {
  Pop-Location
}

Write-Host ("Database exported to {0}" -f $resolvedOutput)
