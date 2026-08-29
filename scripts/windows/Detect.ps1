# Read-only detection of the local OpenTTD installation on Windows.
# Nothing in this file writes to disk. See docs/WINDOWS.md for the
# directory layout this assumes, and docs/RESEARCH.md for how it was
# verified (Linux-side; the Windows directory layout itself is per
# OpenTTD's own documented behaviour, not independently re-verified on a
# real Windows machine for this project — see docs/WINDOWS.md).

function Get-SteamLibraryPaths {
    [CmdletBinding()]
    param()

    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Steam'),
        (Join-Path $env:ProgramFiles 'Steam')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'steamapps')) }

    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($lib in $candidates) { $result.Add($lib) }

    foreach ($lib in $candidates) {
        $vdf = Join-Path $lib 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            $content = Get-Content -LiteralPath $vdf -Raw
            $vdfMatches = [regex]::Matches($content, '"path"\s+"([^"]+)"')
            foreach ($m in $vdfMatches) {
                # VDF escapes backslashes as \\
                $result.Add(($m.Groups[1].Value -replace '\\\\', '\'))
            }
        }
    }

    return $result | Select-Object -Unique
}

function Find-OpenttdExecutable {
    [CmdletBinding()]
    param()

    foreach ($lib in (Get-SteamLibraryPaths)) {
        $exe = Join-Path $lib 'steamapps\common\OpenTTD\openttd.exe'
        if (Test-Path -LiteralPath $exe) { return $exe }
    }

    $onPath = Get-Command 'openttd.exe' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    return $null
}

function Get-OpenttdVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Executable
    )
    $output = & $Executable -h 2>&1 | Select-Object -First 1
    if ($output -match '^OpenTTD\s+([0-9][0-9A-Za-z\.\-]*)') {
        return $Matches[1]
    }
    return $null
}

function Get-OpenttdConfigDataDir {
    <#
    .SYNOPSIS
    Windows keeps config and data together in one directory (unlike
    Linux's XDG split) — see docs/RESEARCH.md §2 / docs/WINDOWS.md.
    #>
    [CmdletBinding()]
    param()
    return (Join-Path $env:USERPROFILE 'Documents\OpenTTD')
}

function Get-DetectedState {
    [CmdletBinding()]
    param()

    $exe = Find-OpenttdExecutable
    $version = $null
    if ($exe) { $version = Get-OpenttdVersion -Executable $exe }
    $dir = Get-OpenttdConfigDataDir
    $configFile = Join-Path $dir 'openttd.cfg'

    return [ordered]@{
        executable    = $exe
        version       = $version
        config_dir    = $dir
        config_file   = $configFile
        config_exists = (Test-Path -LiteralPath $configFile)
        data_dir      = $dir
    }
}
