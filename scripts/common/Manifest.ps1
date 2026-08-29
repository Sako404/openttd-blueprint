# Load and lightly validate profile.json / content-manifest.json.
# PowerShell port of scripts/common/manifest.sh — see that file's header
# comment for why this isn't full JSON-Schema validation.

function Test-ContentManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    try {
        $manifest = $raw | ConvertFrom-Json
    } catch {
        throw "Test-ContentManifest: not valid JSON: $Path"
    }

    if ($manifest.schema_version -ne 1) {
        throw "Test-ContentManifest: schema_version must be 1"
    }
    if ([string]::IsNullOrEmpty($manifest.profile)) {
        throw "Test-ContentManifest: missing profile"
    }

    $bad = @()
    foreach ($item in $manifest.content) {
        $problem = $false
        if (-not $item.name) { $problem = $true }
        if ($item.type -ne 'newgrf' -and $item.type -ne 'game_script' -and $item.type -ne 'ai') { $problem = $true }
        if ($null -eq $item.required) { $problem = $true }
        if ($item.source -ne 'bananas' -and $item.source -ne 'none') { $problem = $true }
        if ($item.version_policy -ne 'pinned') { $problem = $true }
        if (-not $item.purpose) { $problem = $true }
        if (-not $item.license) { $problem = $true }
        if ($item.source -eq 'bananas' -and (-not $item.content_id -or -not $item.version)) { $problem = $true }
        if ($item.source -eq 'none' -and -not $item.omitted_reason) { $problem = $true }
        if ($problem) { $bad += $(if ($item.name) { $item.name } else { '<unnamed>' }) }
    }

    if ($bad.Count -gt 0) {
        throw "Test-ContentManifest: invalid content entries in ${Path}: $($bad -join ', ')"
    }

    return $manifest
}

function Test-Profile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    try {
        $profileData = $raw | ConvertFrom-Json
    } catch {
        throw "Test-Profile: not valid JSON: $Path"
    }

    $missing = @()
    if ($profileData.schema_version -ne 1) { $missing += 'schema_version' }
    if ([string]::IsNullOrEmpty($profileData.name)) { $missing += 'name' }
    if ([string]::IsNullOrEmpty($profileData.display_name)) { $missing += 'display_name' }
    if ([string]::IsNullOrEmpty($profileData.blueprint_version)) { $missing += 'blueprint_version' }
    if ([string]::IsNullOrEmpty($profileData.openttd_min_version)) { $missing += 'openttd_min_version' }
    if ($null -eq $profileData.gameplay.starting_year) { $missing += 'gameplay.starting_year' }
    if ($null -eq $profileData.gameplay.map_size.x -or $null -eq $profileData.gameplay.map_size.y) { $missing += 'gameplay.map_size' }

    if ($missing.Count -gt 0) {
        throw "Test-Profile: missing required field(s) in ${Path}: $($missing -join ', ')"
    }

    return $profileData
}

function Get-RequiredContent {
    <#
    .SYNOPSIS
    Returns required, bananas-sourced content items from a parsed manifest,
    optionally filtered by Type, sorted by their `order` field. Pass
    -IncludeAi to also include optional `ai`-type items (opt-in via
    -WithAI on install-windows.ps1 — off by default).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Manifest,
        [string]$Type,
        [switch]$IncludeAi
    )
    $items = $Manifest.content | Where-Object {
        ($_.required -eq $true -or ($IncludeAi -and $_.type -eq 'ai')) -and $_.source -eq 'bananas' -and (-not $Type -or $_.type -eq $Type)
    }
    return @($items | Sort-Object order)
}
