param(
  [switch]$WithTools,
  [switch]$WithMail,
  [switch]$Remove
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

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
& (Join-Path $PSScriptRoot "bootstrap-env.ps1") -Quiet

$envPath = Join-Path $root ".env"
$settings = Get-EnvSettings $envPath
$configDir = $settings["PROXY_CONFIG_DIR"]
$projectName = $settings["COMPOSE_PROJECT_NAME"]
$configPath = Join-Path $configDir "$projectName.yml"

if ($Remove) {
  if (Test-Path $configPath) {
    Remove-Item $configPath -Force
  }
  return
}

if (-not (Test-Path $configDir)) {
  New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("http:")
$lines.Add("  routers:")
$lines.Add("    $projectName-site:")
$lines.Add("      entryPoints:")
$lines.Add("        - web")
$lines.Add(('      rule: "Host(`' + $settings["WP_HOSTNAME"] + '`)"'))
$lines.Add(("      service: ""{0}-site""" -f $projectName))

if ($WithTools) {
  $lines.Add("    $projectName-adminer:")
  $lines.Add("      entryPoints:")
  $lines.Add("        - web")
  $lines.Add(('      rule: "Host(`db-' + $settings["WP_HOSTNAME"] + '`)"'))
  $lines.Add(("      service: ""{0}-adminer""" -f $projectName))
}

if ($WithMail) {
  $lines.Add("    $projectName-mailpit:")
  $lines.Add("      entryPoints:")
  $lines.Add("        - web")
  $lines.Add(('      rule: "Host(`mail-' + $settings["WP_HOSTNAME"] + '`)"'))
  $lines.Add(("      service: ""{0}-mailpit""" -f $projectName))
}

$lines.Add("  services:")
$lines.Add("    $projectName-site:")
$lines.Add("      loadBalancer:")
$lines.Add("        servers:")
$lines.Add(("          - url: ""http://host.docker.internal:{0}""" -f $settings["WORDPRESS_PUBLISHED_PORT"]))

if ($WithTools) {
  $lines.Add("    $projectName-adminer:")
  $lines.Add("      loadBalancer:")
  $lines.Add("        servers:")
  $lines.Add(("          - url: ""http://host.docker.internal:{0}""" -f $settings["ADMINER_PUBLISHED_PORT"]))
}

if ($WithMail) {
  $lines.Add("    $projectName-mailpit:")
  $lines.Add("      loadBalancer:")
  $lines.Add("        servers:")
  $lines.Add(("          - url: ""http://host.docker.internal:{0}""" -f $settings["MAILPIT_PUBLISHED_PORT"]))
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($configPath, $lines, $utf8NoBom)
