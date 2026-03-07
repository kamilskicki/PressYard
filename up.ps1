param(
  [switch]$Detached,
  [switch]$WithTools,
  [switch]$WithProxy,
  [switch]$WithMail,
  [switch]$WithXdebug
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "scripts\\up.ps1") @PSBoundParameters
