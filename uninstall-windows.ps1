<#
.SYNOPSIS
OpenTTD Blueprint — Windows uninstaller.

.DESCRIPTION
This does NOT uninstall OpenTTD, and does NOT delete downloaded NewGRF/
Game Script content. Its only job is restoring openttd.cfg to how it was
before OpenTTD Blueprint touched it. See docs/ARCHITECTURE.md "Additive
content".

.PARAMETER ListBackups
List available backups, newest first, then exit.

.PARAMETER RestoreDir
Restore a specific backup directory instead of the most recent one.

.PARAMETER ProfileName
Profile name (default: logistics). Accepts -Profile as an alias.

.EXAMPLE
.\uninstall-windows.ps1 -ListBackups
.\uninstall-windows.ps1
.\uninstall-windows.ps1 -RestoreDir 'C:\Users\me\AppData\Local\OpenTTDBlueprint\backups\2026-08-29_170000'
#>
[CmdletBinding()]
param(
    [switch]$ListBackups,
    [string]$RestoreDir,
    # Named ProfileName (not Profile) to avoid shadowing PowerShell's own
    # automatic $PROFILE variable — -Profile kept working via the alias.
    [Alias('Profile')]
    [string]$ProfileName = 'logistics'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BpRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $BpRoot 'scripts\common\Backup.ps1')
. (Join-Path $BpRoot 'scripts\windows\Detect.ps1')

$detected = Get-DetectedState
$configDir = $detected.config_dir
$configFile = $detected.config_file
$BackupRoot = Join-Path $env:LOCALAPPDATA 'OpenTTDBlueprint\backups'
$StateFile = Join-Path $configDir 'blueprint-state.json'

if ($ListBackups) {
    Write-Host "Backups under ${BackupRoot}:"
    if (-not (Test-Path -LiteralPath $BackupRoot)) {
        Write-Host '  (none found)'
        exit 0
    }
    $dirs = Get-ChildItem -LiteralPath $BackupRoot -Directory | Sort-Object Name -Descending
    if ($dirs.Count -eq 0) {
        Write-Host '  (none found)'
        exit 0
    }
    foreach ($dir in $dirs) {
        $metaFile = Join-Path $dir.FullName 'metadata.json'
        $profileName = 'unknown'
        $date = 'unknown'
        if (Test-Path -LiteralPath $metaFile) {
            $meta = Get-Content -LiteralPath $metaFile -Raw | ConvertFrom-Json
            $profileName = $meta.profile
            $date = $meta.date_utc
        }
        Write-Host "  $($dir.FullName)  (profile: $profileName, date: $date)"
    }
    exit 0
}

$targetDir = if ($RestoreDir) { $RestoreDir } else { Get-LatestBackup -BackupRoot $BackupRoot }

if (-not $targetDir -or -not (Test-Path -LiteralPath $targetDir)) {
    Write-Error "ERROR: no backup found to restore (looked under $BackupRoot). Run with -ListBackups to see available backups."
    exit 1
}

$backupCfg = Join-Path $targetDir 'openttd.cfg'
if (-not (Test-Path -LiteralPath $backupCfg)) {
    Write-Error "ERROR: $targetDir does not contain an openttd.cfg backup."
    exit 1
}

Write-Host "Restoring $configFile from $backupCfg"
Copy-Item -LiteralPath $backupCfg -Destination $configFile -Force

if (Test-Path -LiteralPath $StateFile) {
    Remove-Item -Force $StateFile
    Write-Host "Removed $StateFile (profile '$ProfileName' is no longer marked installed)."
}

Write-Host 'Restore complete. Downloaded content under the OpenTTD data directory was left untouched.'
