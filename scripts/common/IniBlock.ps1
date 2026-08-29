# Idempotent marked-block patching for OpenTTD's INI-style openttd.cfg.
# PowerShell port of scripts/common/ini_block.sh — the two MUST stay
# behaviourally identical (same marker text, same "leave everything outside
# the markers untouched" contract). See docs/ARCHITECTURE.md "Config
# ownership" and "Linux/Windows abstraction".

function Set-IniBlock {
    <#
    .SYNOPSIS
    Injects or updates a marked block of lines inside one [Section] of an
    OpenTTD-style INI file, leaving everything else byte-for-byte untouched.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$MarkerId,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$BlockLines
    )

    $begin = "### BEGIN OPENTTD BLUEPRINT ($MarkerId) ###"
    $end = "### END OPENTTD BLUEPRINT ($MarkerId) ###"
    $sectionHeader = "[$Section]"

    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    if (-not ($lines | Where-Object { $_ -ceq $sectionHeader })) {
        throw "Set-IniBlock: section [$Section] not found in $Path"
    }

    $output = [System.Collections.Generic.List[string]]::new()
    $inSection = $false
    $inBlock = $false
    $emitted = $false

    foreach ($line in $lines) {
        $isHeader = $line -cmatch '^\[[^\]]*\]$'

        if ($isHeader -and ($line -ceq $sectionHeader)) {
            $inSection = $true
            $output.Add($line)
            continue
        }

        if ($isHeader -and $inSection -and -not ($line -ceq $sectionHeader)) {
            if (-not $emitted) {
                $output.Add($begin)
                foreach ($l in $BlockLines) { $output.Add($l) }
                $output.Add($end)
                $emitted = $true
            }
            $inSection = $false
            $output.Add($line)
            continue
        }

        if ($inSection -and ($line -ceq $begin)) {
            $inBlock = $true
            $output.Add($begin)
            foreach ($l in $BlockLines) { $output.Add($l) }
            $output.Add($end)
            $emitted = $true
            continue
        }

        if ($inSection -and $inBlock -and ($line -ceq $end)) {
            $inBlock = $false
            continue
        }

        if ($inBlock) { continue }

        $output.Add($line)
    }

    if ($inSection -and -not $emitted) {
        $output.Add($begin)
        foreach ($l in $BlockLines) { $output.Add($l) }
        $output.Add($end)
    }

    Set-Content -LiteralPath $Path -Value $output -Encoding UTF8
}

function Get-IniBlock {
    <#
    .SYNOPSIS
    Returns the current content of a marked block (without markers), or an
    empty array if the block isn't present.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$MarkerId
    )

    $begin = "### BEGIN OPENTTD BLUEPRINT ($MarkerId) ###"
    $end = "### END OPENTTD BLUEPRINT ($MarkerId) ###"

    if (-not (Test-Path -LiteralPath $Path)) { return @() }

    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    $result = [System.Collections.Generic.List[string]]::new()
    $inBlock = $false
    foreach ($line in $lines) {
        if ($line -ceq $begin) { $inBlock = $true; continue }
        if ($line -ceq $end) { $inBlock = $false; continue }
        if ($inBlock) { $result.Add($line) }
    }
    return $result.ToArray()
}

function Split-IniSections {
    <#
    .SYNOPSIS
    Splits a file containing one or more "[section]" groups into
    "<OutDir>/<section>.body" files (body only, no header). Lines before
    the first section header are ignored.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$OutDir
    )

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $lines = @(Get-Content -LiteralPath $SourcePath -Encoding UTF8)
    $currentSection = $null
    $buffers = @{}

    foreach ($line in $lines) {
        if ($line -cmatch '^\[([^\]]*)\]$') {
            $currentSection = $Matches[1]
            if (-not $buffers.ContainsKey($currentSection)) {
                $buffers[$currentSection] = [System.Collections.Generic.List[string]]::new()
            }
            continue
        }
        if ($null -ne $currentSection) {
            $buffers[$currentSection].Add($line)
        }
    }

    foreach ($section in $buffers.Keys) {
        $outFile = Join-Path $OutDir "$section.body"
        Set-Content -LiteralPath $outFile -Value $buffers[$section] -Encoding UTF8
    }
}
