# Timestamped config backups. PowerShell port of scripts/common/backup.sh.
# See docs/ARCHITECTURE.md "Backup strategy".

function New-ConfigBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfigFile,
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ProfileName,
        [Parameter(Mandatory)][string]$OpenttdVersion,
        [Parameter(Mandatory)][string]$BlueprintVersion
    )

    $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd_HHmmss')
    $dest = Join-Path $BackupRoot $stamp
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -LiteralPath $ConfigFile -Destination (Join-Path $dest 'openttd.cfg')

    $metadata = [ordered]@{
        date_utc          = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        openttd_version   = $OpenttdVersion
        source_path       = $ConfigFile
        profile           = $ProfileName
        blueprint_version = $BlueprintVersion
    }
    $metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dest 'metadata.json') -Encoding UTF8

    return $dest
}

function Get-LatestBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot
    )
    if (-not (Test-Path -LiteralPath $BackupRoot)) { return $null }
    $dirs = Get-ChildItem -LiteralPath $BackupRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
    if ($dirs.Count -eq 0) { return $null }
    return $dirs[0].FullName
}
