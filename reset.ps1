param(
  [switch]$WithTools,
  [switch]$WithProxy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "scripts\\reset.ps1") @PSBoundParameters
