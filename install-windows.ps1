<#
.SYNOPSIS
OpenTTD Blueprint — Windows installer.

.DESCRIPTION
See docs/ARCHITECTURE.md for the full design (config ownership,
transactional install order, idempotency) and docs/WINDOWS.md for
platform-specific notes.

.PARAMETER DryRun
Show what would happen; make no changes.

.PARAMETER Verify
Check that the profile is installed and consistent; make no changes.

.PARAMETER Profile
Profile name (default: logistics).

.EXAMPLE
.\install-windows.ps1 -DryRun
.\install-windows.ps1
.\install-windows.ps1 -Verify
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Verify,
    [string]$Profile = 'logistics'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BpVersion = '0.1.0'
$BpRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

. (Join-Path $BpRoot 'scripts\common\Manifest.ps1')
. (Join-Path $BpRoot 'scripts\common\IniBlock.ps1')
. (Join-Path $BpRoot 'scripts\common\Backup.ps1')
. (Join-Path $BpRoot 'scripts\common\State.ps1')
. (Join-Path $BpRoot 'scripts\windows\Detect.ps1')
. (Join-Path $BpRoot 'scripts\windows\Content.ps1')

$ProfileDir = Join-Path $BpRoot "profiles\$Profile"
$ManifestFile = Join-Path $ProfileDir 'content-manifest.json'
$ProfileFile = Join-Path $ProfileDir 'profile.json'
$CfgBlockFile = Join-Path $ProfileDir 'openttd.cfg.block'

if (-not (Test-Path -LiteralPath $ProfileDir)) {
    Write-Error "ERROR: unknown profile '$Profile' (no such directory: $ProfileDir)"
    exit 1
}

if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
    Write-Error "ERROR: 'tar' was not found on PATH (built into Windows 10 1803+ / 11)."
    exit 1
}

Write-Host "OpenTTD Blueprint v$BpVersion"
Write-Host "Profile: $Profile"
Write-Host ''

$manifest = Test-ContentManifest -Path $ManifestFile
$profileData = Test-Profile -Path $ProfileFile

$detected = Get-DetectedState
$exe = $detected.executable
$version = $detected.version
$configDir = $detected.config_dir
$configFile = $detected.config_file
$configExists = $detected.config_exists
$dataDir = $detected.data_dir

Write-Host 'Detected:'
Write-Host "  OpenTTD executable : $(if ($exe) { $exe } else { 'not found' })"
Write-Host "  OpenTTD version    : $(if ($version) { $version } else { 'unknown' })"
Write-Host "  Config file        : $configFile $(if ($configExists) { '(exists)' } else { '(will be created)' })"
Write-Host "  Data directory     : $dataDir"
Write-Host ''

if (-not $exe) {
    Write-Error 'ERROR: OpenTTD was not found (checked Steam libraries, PATH). See docs/TROUBLESHOOTING.md.'
    exit 1
}

$minVersion = $profileData.openttd_min_version
if ($version -and ([version]($version -replace '[^\d\.].*$', '') -lt [version]$minVersion)) {
    Write-Error "ERROR: OpenTTD was found, but version $version is too old for the $Profile profile.`n       Required: OpenTTD >= $minVersion`n       Detected: $version"
    exit 1
}

$BackupRoot = Join-Path $env:LOCALAPPDATA 'OpenTTDBlueprint\backups'
$StateFile = Join-Path $configDir 'blueprint-state.json'

function Initialize-ConfigSkeleton {
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    if (-not (Test-Path -LiteralPath $configFile)) {
        @('[difficulty]', '', '[economy]', '', '[vehicle]', '', '[linkgraph]', '', '[game_creation]', '', '[newgrf]', '', '[game_scripts]') |
            Set-Content -LiteralPath $configFile -Encoding UTF8
    }
    $existing = Get-Content -LiteralPath $configFile -Encoding UTF8
    foreach ($section in @('difficulty', 'economy', 'vehicle', 'linkgraph', 'game_creation', 'newgrf', 'game_scripts')) {
        if (-not ($existing -ccontains "[$section]")) {
            Add-Content -LiteralPath $configFile -Value @('', "[$section]") -Encoding UTF8
            $existing = Get-Content -LiteralPath $configFile -Encoding UTF8
        }
    }
}

function Get-PatchedConfig {
    param([string]$SourcePath, [string]$OutPath)
    Copy-Item -LiteralPath $SourcePath -Destination $OutPath -Force

    $splitDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    Split-IniSections -SourcePath $CfgBlockFile -OutDir $splitDir
    foreach ($section in @('difficulty', 'economy', 'vehicle', 'linkgraph', 'game_creation')) {
        $bodyFile = Join-Path $splitDir "$section.body"
        if (-not (Test-Path -LiteralPath $bodyFile)) { continue }
        $blockLines = @(Get-Content -LiteralPath $bodyFile -Encoding UTF8)
        Set-IniBlock -Path $OutPath -Section $section -MarkerId "profile: $Profile, section: $section" -BlockLines $blockLines
    }
    Remove-Item -Recurse -Force $splitDir

    $newgrfLines = Build-NewgrfLines -DataDir $dataDir -Manifest $manifest
    Set-IniBlock -Path $OutPath -Section 'newgrf' -MarkerId "profile: $Profile, section: newgrf" -BlockLines $newgrfLines

    $gsLine = Build-GameScriptLine -Executable $exe -Manifest $manifest
    if ($gsLine.Count -gt 0) {
        Set-IniBlock -Path $OutPath -Section 'game_scripts' -MarkerId "profile: $Profile, section: game_scripts" -BlockLines $gsLine
    }
}

$requiredItems = Get-RequiredContent -Manifest $manifest
$preexisting = [System.Collections.Generic.List[string]]::new()
$missingItems = [System.Collections.Generic.List[string]]::new()
foreach ($item in $requiredItems) {
    $type = if ($item.type -eq 'game_script') { 'game' } else { $item.type }
    if (Test-ContentPresent -DataDir $dataDir -Type $type -ContentId $item.content_id) {
        $preexisting.Add($item.name)
    } else {
        $missingItems.Add($item.name)
        Write-Host "  content missing: $($item.name)"
    }
}

if ($DryRun) {
    Write-Host '--- DRY RUN: no changes will be made ---'
    Write-Host ''
    if ($missingItems.Count -gt 0) {
        Write-Host "$($missingItems.Count) required content item(s) would be downloaded (see list above)."
    } else {
        Write-Host 'All required content already present.'
    }
    Write-Host ''
    if ($configExists) {
        $splitDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        Split-IniSections -SourcePath $CfgBlockFile -OutDir $splitDir
        $tmpCheck = [System.IO.Path]::GetTempFileName()
        Copy-Item -LiteralPath $configFile -Destination $tmpCheck -Force
        $changed = $false
        foreach ($section in @('difficulty', 'economy', 'vehicle', 'linkgraph', 'game_creation')) {
            $bodyFile = Join-Path $splitDir "$section.body"
            if (-not (Test-Path -LiteralPath $bodyFile)) { continue }
            $before = (Get-IniBlock -Path $configFile -MarkerId "profile: $Profile, section: $section") -join "`n"
            $blockLines = @(Get-Content -LiteralPath $bodyFile -Encoding UTF8)
            Set-IniBlock -Path $tmpCheck -Section $section -MarkerId "profile: $Profile, section: $section" -BlockLines $blockLines
            $after = (Get-IniBlock -Path $tmpCheck -MarkerId "profile: $Profile, section: $section") -join "`n"
            if ($before -ne $after) {
                Write-Host "  [$section] would be added/updated"
                $changed = $true
            }
        }
        if (-not $changed) { Write-Host '  gameplay settings already up to date' }
        Remove-Item -Recurse -Force $splitDir
        Remove-Item -Force $tmpCheck
    } else {
        Write-Host '  openttd.cfg does not exist yet -- would be created with all profile sections.'
    }
    Write-Host ''
    Write-Host "Backup would be created under: $BackupRoot\<timestamp>\ (only if config actually changes)"
    exit 0
}

if ($Verify) {
    $fail = $false
    if (-not (Test-Path -LiteralPath $StateFile)) {
        Write-Error "FAIL: no blueprint-state.json at $StateFile -- profile not installed."
        exit 1
    }
    $installedProfile = Read-BlueprintStateField -StateFile $StateFile -FieldName 'profile'
    if ($installedProfile -ne $Profile) {
        Write-Host "FAIL: installed profile is '$installedProfile', not '$Profile'." -ForegroundColor Red
        $fail = $true
    }
    foreach ($item in $requiredItems) {
        $type = if ($item.type -eq 'game_script') { 'game' } else { $item.type }
        if (-not (Test-ContentPresent -DataDir $dataDir -Type $type -ContentId $item.content_id)) {
            Write-Host "FAIL: required content missing: $($item.name)" -ForegroundColor Red
            $fail = $true
        }
    }
    foreach ($section in @('difficulty', 'economy', 'vehicle', 'linkgraph', 'game_creation', 'newgrf')) {
        if ((Get-IniBlock -Path $configFile -MarkerId "profile: $Profile, section: $section").Count -eq 0) {
            Write-Host "FAIL: no OpenTTD Blueprint block found in [$section] of $configFile" -ForegroundColor Red
            $fail = $true
        }
    }
    if (-not $fail) {
        Write-Host "OK: profile '$Profile' is installed and consistent."
        exit 0
    } else {
        exit 1
    }
}

# --- real install from here ---

Initialize-ConfigSkeleton

if ($missingItems.Count -gt 0) {
    Write-Host "Downloading $($missingItems.Count) required content item(s) via OpenTTD's Online Content system..."
    $logFile = [System.IO.Path]::GetTempFileName()
    $ok = Invoke-ContentDownload -Executable $exe -Manifest $manifest -LogFile $logFile -DataDir $dataDir
    if (-not $ok) {
        Write-Error 'ERROR: content download did not complete. Log:'
        Get-Content -LiteralPath $logFile | Write-Error
        exit 1
    }
    Remove-Item -Force $logFile
    Write-Host 'Content download complete.'
} else {
    Write-Host 'All required content already present -- skipping download.'
}

$patched = [System.IO.Path]::GetTempFileName()
Get-PatchedConfig -SourcePath $configFile -OutPath $patched

$currentBytes = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8
$patchedBytes = Get-Content -LiteralPath $patched -Raw -Encoding UTF8
if ($currentBytes -ceq $patchedBytes) {
    Write-Host 'Configuration already up to date -- no changes needed.'
    $backupDir = ''
} else {
    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    $backupDir = New-ConfigBackup -ConfigFile $configFile -BackupRoot $BackupRoot -ProfileName $Profile `
        -OpenttdVersion $(if ($version) { $version } else { 'unknown' }) -BlueprintVersion $BpVersion
    Write-Host "Backed up existing config to: $backupDir"
    Copy-Item -LiteralPath $patched -Destination $configFile -Force
    Write-Host "Applied $Profile profile configuration."
}
Remove-Item -Force $patched -ErrorAction SilentlyContinue

Write-BlueprintState -StateFile $StateFile -BlueprintVersion $BpVersion -ProfileName $Profile `
    -ManifestVersion $profileData.blueprint_version -BackupDir $(if ($backupDir) { $backupDir } else { 'none' }) `
    -PreexistingContent $preexisting.ToArray() -AddedContent $missingItems.ToArray()
Write-Host "Wrote state: $StateFile"

Write-Host ''
Write-Host 'Install complete. Run ''.\install-windows.ps1 -Verify'' to confirm.'
