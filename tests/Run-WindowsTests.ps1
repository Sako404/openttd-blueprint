# Fixture-based tests for the Windows-side shared library, mirroring
# tests/run-linux-tests.sh (see that file for why these two must stay in
# sync). No Pester dependency — a small hand-rolled runner, consistent
# with docs/ARCHITECTURE.md "Dependency minimisation". Never touches a
# real OpenTTD installation or the network.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BpRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Fixtures = Join-Path $BpRoot 'tests\fixtures'

. (Join-Path $BpRoot 'scripts\common\Manifest.ps1')
. (Join-Path $BpRoot 'scripts\common\IniBlock.ps1')
. (Join-Path $BpRoot 'scripts\common\Backup.ps1')
. (Join-Path $BpRoot 'scripts\common\State.ps1')

$script:Pass = 0
$script:Fail = 0

function Assert-Eq {
    param($Description, $Expected, $Actual)
    if ($Expected -eq $Actual) {
        $script:Pass++
        Write-Host "  ok - $Description"
    } else {
        $script:Fail++
        Write-Host "  FAIL - $Description (expected: [$Expected], got: [$Actual])"
    }
}

function Assert-Success {
    param($Description, [scriptblock]$Block)
    try {
        & $Block | Out-Null
        $script:Pass++
        Write-Host "  ok - $Description"
    } catch {
        $script:Fail++
        Write-Host "  FAIL - $Description ($($_.Exception.Message))"
    }
}

function Assert-Failure {
    param($Description, [scriptblock]$Block)
    try {
        & $Block | Out-Null
        $script:Fail++
        Write-Host "  FAIL - $Description (expected failure, succeeded)"
    } catch {
        $script:Pass++
        Write-Host "  ok - $Description"
    }
}

$WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

try {
    Write-Host '== manifest validation =='
    Assert-Success 'valid manifest passes Test-ContentManifest' { Test-ContentManifest -Path (Join-Path $Fixtures 'valid-manifest.json') }
    Assert-Failure 'invalid manifest fails Test-ContentManifest' { Test-ContentManifest -Path (Join-Path $Fixtures 'invalid-manifest.json') }
    Assert-Success 'valid profile passes Test-Profile' { Test-Profile -Path (Join-Path $Fixtures 'valid-profile.json') }
    Assert-Failure 'invalid profile fails Test-Profile' { Test-Profile -Path (Join-Path $Fixtures 'invalid-profile.json') }

    Write-Host '== Get-RequiredContent =='
    $manifest = Test-ContentManifest -Path (Join-Path $Fixtures 'valid-manifest.json')
    $required = Get-RequiredContent -Manifest $manifest
    Assert-Eq 'lists only required bananas-sourced items' 1 $required.Count
    Assert-Eq 'correct item name' 'Example NewGRF' $required[0].name

    Write-Host '== Set-IniBlock: fresh insert =='
    $cfg = Join-Path $WorkDir 'openttd.cfg'
    Copy-Item -LiteralPath (Join-Path $Fixtures 'sample-openttd.cfg') -Destination $cfg
    $blockLines = @('distribution_pax = 2', 'distribution_mail = 2')
    Set-IniBlock -Path $cfg -Section 'linkgraph' -MarkerId 'profile: test, section: linkgraph' -BlockLines $blockLines
    $extracted = Get-IniBlock -Path $cfg -MarkerId 'profile: test, section: linkgraph'
    Assert-Eq 'block content matches after fresh insert' ($blockLines -join "`n") ($extracted -join "`n")
    Assert-Success 'pre-existing key in same section survives' { Select-String -LiteralPath $cfg -Pattern 'recalc_time = 4' -SimpleMatch }
    Assert-Success 'unrelated section untouched' { Select-String -LiteralPath $cfg -Pattern 'server_name = My Server' -SimpleMatch }

    Write-Host '== Set-IniBlock: idempotent re-patch =='
    $before = Get-Content -LiteralPath $cfg -Raw
    Set-IniBlock -Path $cfg -Section 'linkgraph' -MarkerId 'profile: test, section: linkgraph' -BlockLines $blockLines
    $after = Get-Content -LiteralPath $cfg -Raw
    Assert-Eq 're-running with identical block produces byte-identical file' $before $after

    Write-Host '== Set-IniBlock: update existing block =='
    Set-IniBlock -Path $cfg -Section 'linkgraph' -MarkerId 'profile: test, section: linkgraph' -BlockLines @('distribution_pax = 1')
    $extracted2 = Get-IniBlock -Path $cfg -MarkerId 'profile: test, section: linkgraph'
    Assert-Eq 'block content updates in place' 'distribution_pax = 1' ($extracted2 -join "`n")
    $markerCount = (Select-String -LiteralPath $cfg -Pattern 'BEGIN OPENTTD BLUEPRINT \(profile: test, section: linkgraph\)' | Measure-Object).Count
    Assert-Eq 'no duplicate marker blocks after repeated patch' 1 $markerCount

    Write-Host '== Set-IniBlock: unknown user NewGRF content preserved =='
    Assert-Success 'unrelated NewGRF entries survive untouched' { Select-String -LiteralPath $cfg -Pattern 'some-old-pack.grf = 1 2 3' -SimpleMatch }

    Write-Host '== Set-IniBlock: missing section is an error, not silent =='
    Assert-Failure 'patching a nonexistent section fails loudly' { Set-IniBlock -Path $cfg -Section 'does_not_exist' -MarkerId 'profile: test, section: nope' -BlockLines $blockLines }

    Write-Host '== Split-IniSections =='
    $splitDir = Join-Path $WorkDir 'split'
    $blockFile = Join-Path $WorkDir 'blockfile.cfg'
    @('[difficulty]', 'number_towns = 2', '', '[economy]', 'inflation = true') | Set-Content -LiteralPath $blockFile
    Split-IniSections -SourcePath $blockFile -OutDir $splitDir
    Assert-Success 'difficulty.body created' { Test-Path -LiteralPath (Join-Path $splitDir 'difficulty.body') }
    Assert-Success 'economy.body created' { Test-Path -LiteralPath (Join-Path $splitDir 'economy.body') }

    Write-Host '== backup creation =='
    $backupRoot = Join-Path $WorkDir 'backups'
    $backupDir = New-ConfigBackup -ConfigFile $cfg -BackupRoot $backupRoot -ProfileName 'test' -OpenttdVersion '15.3' -BlueprintVersion '0.1.0'
    Assert-Success 'backup directory created' { Test-Path -LiteralPath $backupDir -PathType Container }
    Assert-Success 'backup contains openttd.cfg' { Test-Path -LiteralPath (Join-Path $backupDir 'openttd.cfg') }
    Assert-Success 'backup contains metadata.json' { Test-Path -LiteralPath (Join-Path $backupDir 'metadata.json') }
    $meta = Get-Content -LiteralPath (Join-Path $backupDir 'metadata.json') -Raw | ConvertFrom-Json
    Assert-Eq 'backup metadata records profile name' 'test' $meta.profile

    Write-Host '== state read/write =='
    $stateFile = Join-Path $WorkDir 'blueprint-state.json'
    Write-BlueprintState -StateFile $stateFile -BlueprintVersion '0.1.0' -ProfileName 'test' -ManifestVersion '0.1.0' `
        -BackupDir $backupDir -PreexistingContent @('Preexisting Thing') -AddedContent @('Added Thing')
    Assert-Success 'state file is valid JSON' { Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json }
    $profileField = Read-BlueprintStateField -StateFile $stateFile -FieldName 'profile'
    Assert-Eq 'state records profile' 'test' $profileField

    Write-Host '== paths with spaces =='
    $spaceDir = Join-Path $WorkDir 'dir with spaces'
    New-Item -ItemType Directory -Force -Path $spaceDir | Out-Null
    $spaceCfg = Join-Path $spaceDir 'openttd.cfg'
    Copy-Item -LiteralPath (Join-Path $Fixtures 'sample-openttd.cfg') -Destination $spaceCfg
    Assert-Success 'Set-IniBlock works with spaces in path' { Set-IniBlock -Path $spaceCfg -Section 'linkgraph' -MarkerId 'profile: test, section: linkgraph' -BlockLines $blockLines }

    Write-Host '== -IncludeAi manifest filtering (logistics profile) =='
    $logisticsManifest = Test-ContentManifest -Path (Join-Path $BpRoot 'profiles\logistics\content-manifest.json')
    $withoutAi = Get-RequiredContent -Manifest $logisticsManifest
    $withAi = Get-RequiredContent -Manifest $logisticsManifest -IncludeAi
    Assert-Success 'RailwAI excluded by default (no -IncludeAi)' { if (($withoutAi | Where-Object { $_.name -eq 'RailwAI' })) { throw 'RailwAI should not be present' } }
    Assert-Success 'RailwAI included with -IncludeAi' { if (-not ($withAi | Where-Object { $_.name -eq 'RailwAI' })) { throw 'RailwAI should be present' } }
    Assert-Eq '-IncludeAi adds exactly one item to the selection' ($withoutAi.Count + 1) $withAi.Count

} finally {
    Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host '=========================================='
Write-Host "PASS: $script:Pass  FAIL: $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
