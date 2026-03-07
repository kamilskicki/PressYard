param(
  [switch]$WithTools,
  [switch]$WithMail,
  [switch]$Remove,
  [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-EnvSettings([string]$Path) {
  $settings = @{}
  foreach ($line in Get-Content $Path) {
    if ($line -match "^\s*#" -or $line -notmatch "=") {
      continue
    }
    $parts = $line.Split("=", 2)
    $settings[$parts[0].Trim()] = $parts[1].Trim()
  }
  return $settings
}

function Test-IsWindows {
  return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
}

function Get-HostsPath {
  if (Test-IsWindows) {
    return Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
  }

  return "/etc/hosts"
}

function Test-HostsWritable([string]$Path) {
  $stream = $null
  try {
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
    return $true
  }
  catch {
    return $false
  }
  finally {
    if ($stream -ne $null) {
      $stream.Dispose()
    }
  }
}

function Remove-ManagedBlock([string[]]$Lines, [string]$BeginMarker, [string]$EndMarker) {
  $result = New-Object System.Collections.Generic.List[string]
  $skip = $false

  foreach ($line in $Lines) {
    if ($line -eq $BeginMarker) {
      $skip = $true
      continue
    }

    if ($skip) {
      if ($line -eq $EndMarker) {
        $skip = $false
      }
      continue
    }

    $result.Add($line)
  }

  return ,$result
}

function Get-EntryLines([string]$HostName, [switch]$WithTools, [switch]$WithMail) {
  $entries = New-Object System.Collections.Generic.List[string]
  $entries.Add(("127.0.0.1 {0}" -f $HostName))
  if ($WithTools) {
    $entries.Add(("127.0.0.1 db-{0}" -f $HostName))
  }
  if ($WithMail) {
    $entries.Add(("127.0.0.1 mail-{0}" -f $HostName))
  }
  return ,$entries
}

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
& (Join-Path $PSScriptRoot "bootstrap-env.ps1") -Quiet
$settings = Get-EnvSettings (Join-Path $root ".env")

$projectName = $settings["COMPOSE_PROJECT_NAME"]
$hostName = $settings["WP_HOSTNAME"]
$hostsPath = Get-HostsPath
$beginMarker = "# BEGIN PRESSYARD $projectName"
$endMarker = "# END PRESSYARD $projectName"
$legacyBeginMarker = "# BEGIN WPDRAFT $projectName"
$legacyEndMarker = "# END WPDRAFT $projectName"
$shouldManageHosts = $hostName -like "*.localhost"

if (-not (Test-Path $hostsPath)) {
  if ($Remove) {
    Write-Warning "Hosts file not found at $hostsPath."
    return
  }
  throw "Hosts file not found at $hostsPath."
  return
}

if (-not (Test-HostsWritable -Path $hostsPath)) {
  if ($Remove) {
    Write-Warning ("Cannot update {0}. Run PowerShell with elevated privileges if you want automatic .localhost hostnames." -f $hostsPath)
    return
  }
  throw "Cannot update $hostsPath. Run PowerShell with elevated privileges and rerun .\up.ps1 for clean .localhost URLs."
}

$currentContent = Get-Content -Path $hostsPath -Raw
$lineEnding = if ($currentContent.Contains("`r`n")) { "`r`n" } else { "`n" }
$lines = if ([string]::IsNullOrEmpty($currentContent)) { @() } else { [System.Text.RegularExpressions.Regex]::Split($currentContent, "\r?\n") }
$cleanLines = New-Object System.Collections.Generic.List[string]
foreach ($line in (Remove-ManagedBlock -Lines $lines -BeginMarker $legacyBeginMarker -EndMarker $legacyEndMarker)) {
  $cleanLines.Add($line)
}

$normalizedLines = New-Object System.Collections.Generic.List[string]
foreach ($line in (Remove-ManagedBlock -Lines $cleanLines.ToArray() -BeginMarker $beginMarker -EndMarker $endMarker)) {
  $normalizedLines.Add($line)
}
$cleanLines = $normalizedLines

if (-not $Remove) {
  if (-not $shouldManageHosts) {
    throw "WP_HOSTNAME must end in .localhost for managed hostnames."
  }

  if ($cleanLines.Count -gt 0 -and $cleanLines[$cleanLines.Count - 1] -ne "") {
    $cleanLines.Add("")
  }

  $cleanLines.Add($beginMarker)
  foreach ($entry in Get-EntryLines -HostName $hostName -WithTools:$WithTools -WithMail:$WithMail) {
    $cleanLines.Add($entry)
  }
  $cleanLines.Add($endMarker)
}

$newContent = (($cleanLines.ToArray()) -join $lineEnding).TrimEnd("`r", "`n")
if (-not [string]::IsNullOrEmpty($newContent)) {
  $newContent += $lineEnding
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($hostsPath, $newContent, $utf8NoBom)

if (-not $Quiet) {
  if ($Remove) {
    Write-Host ("Removed managed hosts entry for {0}." -f $hostName)
  }
  else {
    Write-Host ("Mapped {0} to 127.0.0.1 in {1}." -f $hostName, $hostsPath)
  }
}
