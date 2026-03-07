param(
  [switch]$Volumes,
  [switch]$Proxy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "scripts\\down.ps1") @PSBoundParameters
