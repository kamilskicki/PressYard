param(
  [switch]$WithTools,
  [switch]$WithProxy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "down.ps1") -Volumes

if ($WithTools) {
  if ($PSBoundParameters.ContainsKey("WithProxy")) {
    & (Join-Path $PSScriptRoot "up.ps1") -WithTools -WithProxy:$WithProxy
  }
  else {
    & (Join-Path $PSScriptRoot "up.ps1") -WithTools
  }
}
else {
  if ($PSBoundParameters.ContainsKey("WithProxy")) {
    & (Join-Path $PSScriptRoot "up.ps1") -WithProxy:$WithProxy
  }
  else {
    & (Join-Path $PSScriptRoot "up.ps1")
  }
}
