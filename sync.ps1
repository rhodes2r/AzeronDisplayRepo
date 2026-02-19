param(
  [string]$Source = (Join-Path $PSScriptRoot 'AzeronDisplay'),
  [string]$Destination = 'Y:\AzeronDisplay',
  [switch]$Backup,
  [switch]$WhatIfSync
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Source)) {
  throw "Source path not found: $Source"
}

if ($Backup -and (Test-Path -LiteralPath $Destination)) {
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $backupPath = "${Destination}_backup_${stamp}"
  Write-Host "Creating backup: $backupPath"
  Rename-Item -LiteralPath $Destination -NewName (Split-Path -Leaf $backupPath)
}

$destParent = Split-Path -Parent $Destination
if (-not (Test-Path -LiteralPath $destParent)) {
  New-Item -ItemType Directory -Path $destParent | Out-Null
}

$roboArgs = @(
  $Source,
  $Destination,
  '/E',
  '/R:2',
  '/W:1',
  '/XD', '.claude', 'tmp',
  '/XF', '*.bak', '*.proc-working'
)

if ($WhatIfSync) {
  $roboArgs += '/L'
  Write-Host 'Running in preview mode (/L). No files will be copied.'
}

Write-Host "Syncing from $Source to $Destination"
& robocopy @roboArgs
$code = $LASTEXITCODE

# Robocopy: 0-7 are success/non-fatal statuses.
if ($code -ge 8) {
  throw "Robocopy failed with exit code $code"
}

Write-Host "Sync complete (robocopy code $code)."
