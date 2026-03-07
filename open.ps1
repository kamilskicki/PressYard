param(
  [switch]$Adminer,
  [switch]$Direct
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "scripts\\open.ps1") @PSBoundParameters
