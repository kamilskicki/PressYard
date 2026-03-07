param(
  [switch]$Adminer,
  [switch]$Mailpit,
  [switch]$Direct
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "scripts\\open.ps1") @PSBoundParameters
