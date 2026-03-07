param(
  [string]$Service,
  [switch]$Follow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "scripts\\logs.ps1") @PSBoundParameters
