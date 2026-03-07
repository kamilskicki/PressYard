param(
  [Parameter(Mandatory = $true)]
  [string]$InputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "scripts\\import-db.ps1") @PSBoundParameters
