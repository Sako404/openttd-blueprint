# Read/write blueprint-state.json. PowerShell port of scripts/common/state.sh.
# See docs/ARCHITECTURE.md "Ownership metadata".

function Write-BlueprintState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StateFile,
        [Parameter(Mandatory)][string]$BlueprintVersion,
        [Parameter(Mandatory)][string]$ProfileName,
        [Parameter(Mandatory)][string]$ManifestVersion,
        [Parameter(Mandatory)][string]$BackupDir,
        [Parameter(Mandatory)][string[]]$PreexistingContent,
        [Parameter(Mandatory)][string[]]$AddedContent
    )

    $state = [ordered]@{
        blueprint_version                = $BlueprintVersion
        profile                          = $ProfileName
        manifest_version                 = $ManifestVersion
        installed_at                     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        config_backup                    = $BackupDir
        content_detected_before_install  = @($PreexistingContent)
        content_added_by_install         = @($AddedContent)
    }
    $state | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

function Read-BlueprintStateField {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StateFile,
        [Parameter(Mandatory)][string]$FieldName
    )
    if (-not (Test-Path -LiteralPath $StateFile)) { return $null }
    $json = Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    return $json.$FieldName
}
