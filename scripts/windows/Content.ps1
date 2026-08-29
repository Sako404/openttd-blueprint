# Content acquisition and [newgrf]/[game_scripts] block generation for
# Windows. PowerShell port of scripts/linux/content.sh — see that file's
# header and docs/RESEARCH.md §3/§5 for why this drives OpenTTD's own
# console `content` commands, and why filenames/script names are resolved
# from OpenTTD's own output instead of guessed. Uses the `tar.exe` built
# into Windows 10 (1803+)/11 to list a downloaded content archive's
# contents, exactly as the Linux side uses `tar -tf`.

function Get-ByteSwappedHex {
    <#
    .SYNOPSIS
    Returns the same 4 bytes of an 8-hex-char content ID in reverse order.
    BaNaNaS's own package-page URLs and the downloaded tar's filename
    always use one canonical byte order, but the console's own `content
    state` listing was observed, live, to report at least Game Script and
    AI content in the *opposite* byte order for the same package (NewGRF
    entries matched directly, un-swapped, in every case observed). Callers
    try both forms when matching a content_state row. See docs/RESEARCH.md §3.
    #>
    param([Parameter(Mandatory)][string]$Hex)
    return $Hex.Substring(6, 2) + $Hex.Substring(4, 2) + $Hex.Substring(2, 2) + $Hex.Substring(0, 2)
}

function Get-ContentTarPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DataDir,
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][string]$ContentId
    )
    $dir = Join-Path $DataDir "content_download\$Type"
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    $match = Get-ChildItem -LiteralPath $dir -Filter "$ContentId-*.tar" -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($match) { return $match.FullName }
    return $null
}

function Test-ContentPresent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DataDir,
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][string]$ContentId
    )
    return [bool](Get-ContentTarPath -DataDir $DataDir -Type $Type -ContentId $ContentId)
}

function Wait-LogIdle {
    <#
    .SYNOPSIS
    Polls a growing log file once a second, returning once its size has
    been unchanged for 3 consecutive polls (and at least MinSeconds have
    passed), or once MaxSeconds have elapsed. See scripts/linux/content.sh
    _wait_log_idle for why: there's no documented "operation complete"
    marker for content update/download reliable enough to grep for.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogFile,
        [Parameter(Mandatory)][int]$MinSeconds,
        [Parameter(Mandatory)][int]$MaxSeconds
    )
    $elapsed = 0
    $lastSize = -1
    $stable = 0
    while ($elapsed -lt $MaxSeconds) {
        Start-Sleep -Seconds 1
        $elapsed++
        $size = if (Test-Path -LiteralPath $LogFile) { (Get-Item -LiteralPath $LogFile).Length } else { 0 }
        if ($size -eq $lastSize) { $stable++ } else { $stable = 0 }
        $lastSize = $size
        if ($elapsed -ge $MinSeconds -and $stable -ge 3) { return }
    }
}

function Invoke-ContentDownload {
    <#
    .SYNOPSIS
    Drives a headless dedicated-server session through the console `content`
    command family for every required, not-yet-present bananas-sourced item.
    Returns $true if every required item is present on disk afterwards.

    .NOTES
    Resolves each package by content_id to *a* currently-listed version, not
    provably the exact version pinned in the manifest — see
    scripts/linux/content.sh download_required_content and
    docs/RESEARCH.md §3 for why.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$LogFile,
        [Parameter(Mandatory)][string]$DataDir,
        [switch]$WithAi
    )

    Set-Content -LiteralPath $LogFile -Value @() -Encoding UTF8
    $writer = [System.IO.StreamWriter]::new($LogFile, $true)
    $writer.AutoFlush = $true

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Executable
    $psi.Arguments = '-D -x'
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action {
        if ($EventArgs.Data) { $Event.MessageData.WriteLine($EventArgs.Data) }
    } -MessageData $writer | Out-Null
    Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action {
        if ($EventArgs.Data) { $Event.MessageData.WriteLine($EventArgs.Data) }
    } -MessageData $writer | Out-Null

    $proc.Start() | Out-Null
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()

    try {
        # The console/network-content subsystem isn't immediately ready when
        # the dedicated server starts — a command sent too early is silently
        # dropped ("Command 'content' not found."), verified empirically on
        # the Linux side (scripts/linux/content.sh). A short fixed delay
        # before the first command avoids the race.
        Start-Sleep -Seconds 2
        $proc.StandardInput.WriteLine('content update')
        # `content update` is a silent background fetch of the server's
        # full catalog (observed: tens of thousands of items) with no
        # documented completion signal — wait a fixed, empirically-generous
        # duration rather than idle-polling (verified on the Linux side:
        # `content state` issued once this has settled returns complete,
        # correct results).
        Start-Sleep -Seconds 60

        # `content state <filter>` narrows the listing to just matching
        # names instead of dumping the entire catalog — verified
        # empirically (Linux side) to be far faster and more reliable: an
        # *unfiltered* `content state` was observed to sometimes leave the
        # dedicated server too busy digesting its own multi-thousand-line
        # output to reliably process the commands that followed. One
        # filtered call per required item avoids that entirely.
        #
        # Phase 1: resolve every item's numeric ID first, *without*
        # selecting anything yet. Phase 2 below issues every `content
        # select` back-to-back, immediately before `content download`. This
        # split exists because interleaving select with further content
        # state calls was observed (Linux side live run) to silently lose
        # most selections -- only 4 of 9 correctly-resolved items actually
        # got downloaded, no error at all. The server's numeric IDs are
        # apparently not guaranteed stable across separate content state
        # calls in the same session.
        $required = Get-RequiredContent -Manifest $Manifest -IncludeAi:$WithAi
        $selectedIds = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $required) {
            $type = if ($item.type -eq 'game_script') { 'game' } else { $item.type }
            if (Test-ContentPresent -DataDir $DataDir -Type $type -ContentId $item.content_id) { continue }
            $startLine = (Get-Content -LiteralPath $LogFile -Encoding UTF8 | Measure-Object -Line).Lines
            # The console splits an unquoted argument on whitespace — an
            # unquoted multi-word filter was observed (Linux side testing)
            # to effectively match on just one generic word, returning
            # dozens of unrelated packages instead of one. Quoting the
            # whole filter gives an exact-substring match instead.
            $proc.StandardInput.WriteLine("content state `"$($item.name)`"")
            # Round-trip time for a single filtered query varies a lot in
            # practice (verified on the Linux side) — idle-detection per
            # item adapts instead of wasting time on fast items or
            # truncating slow ones.
            Wait-LogIdle -LogFile $LogFile -MinSeconds 10 -MaxSeconds 40
            $newLines = Get-Content -LiteralPath $LogFile -Encoding UTF8 | Select-Object -Skip $startLine
            $swappedId = Get-ByteSwappedHex -Hex $item.content_id
            $pattern = ",\s*(" + [regex]::Escape($item.content_id) + "|" + [regex]::Escape($swappedId) + ")\s*,"
            $row = $newLines | Where-Object { $_ -imatch $pattern } | Select-Object -First 1
            if ($row -and ($row -match '^(\d+),')) {
                $selectedIds.Add($Matches[1])
            } else {
                Write-Warning "content_id $($item.content_id) not found via 'content state $($item.name)' — server may not have it"
            }
        }

        # Phase 2: select everything, then download. A short pause after
        # each select (no intervening content state query) was necessary:
        # sending all selects with zero delay was *also* observed (Linux
        # side live run) to lose every single one -- the console apparently
        # needs a brief moment to register each selection.
        foreach ($id in $selectedIds) {
            $proc.StandardInput.WriteLine("content select $id")
            Start-Sleep -Seconds 2
        }
        Start-Sleep -Seconds 3

        $proc.StandardInput.WriteLine('content download')
        Wait-LogIdle -LogFile $LogFile -MinSeconds 5 -MaxSeconds 150
        $proc.StandardInput.WriteLine('quit')
        # A dedicated server (-D) is designed to run indefinitely and does
        # not reliably exit on "quit" (verified empirically on the Linux
        # side) — poll briefly for natural exit, then force-terminate
        # rather than risk hanging forever.
        $proc.WaitForExit(30000) | Out-Null
    } finally {
        if (-not $proc.HasExited) { $proc.Kill() }
        Get-EventSubscriber | Where-Object { $_.SourceObject -eq $proc } | Unregister-Event
        $writer.Close()
    }

    $missing = 0
    foreach ($item in (Get-RequiredContent -Manifest $Manifest -IncludeAi:$WithAi)) {
        $type = if ($item.type -eq 'game_script') { 'game' } else { $item.type }
        if (-not (Test-ContentPresent -DataDir $DataDir -Type $type -ContentId $item.content_id)) {
            # Not Write-Error: callers run under $ErrorActionPreference =
            # 'Stop', where the first Write-Error would abort this loop
            # before the remaining items are even checked.
            Write-Warning "MISSING after download: $($item.name) ($type $($item.content_id))"
            $missing++
        }
    }
    return ($missing -eq 0)
}

function Resolve-NewgrfFilename {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DataDir,
        [Parameter(Mandatory)][string]$ContentId
    )
    $tarPath = Get-ContentTarPath -DataDir $DataDir -Type 'newgrf' -ContentId $ContentId
    if (-not $tarPath) { return $null }
    $entries = & tar -tf $tarPath
    $grf = $entries | Where-Object { $_ -imatch '\.grf$' } | Select-Object -First 1
    if (-not $grf) { return $null }
    return (Split-Path -Leaf $grf)
}

function Resolve-RegisteredName {
    <#
    .SYNOPSIS
    Shared by Resolve-GameScriptName/Resolve-AiName: prints the registered
    short name OpenTTD uses for downloaded content, found by fuzzy-matching
    a manifest item's display name against a named section of `openttd -h`
    output (e.g. "List of Game Scripts:", "List of AIs:").
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$Heading,
        [Parameter(Mandatory)][string]$DisplayName
    )
    $needle = $DisplayName -replace ' ', ''
    $output = & $Executable -h 2>&1
    $inSection = $false
    foreach ($line in $output) {
        if ($line -eq $Heading) { $inSection = $true; continue }
        if ($inSection -and $line -match '^List of ') { break }
        if ($inSection -and $line.Trim()) {
            $token = ($line -split ' \(v')[0]
            if ($token.StartsWith($needle) -or $needle.StartsWith($token)) {
                return $token
            }
        }
    }
    return $null
}

function Resolve-GameScriptName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$DisplayName
    )
    return Resolve-RegisteredName -Executable $Executable -Heading 'List of Game Scripts:' -DisplayName $DisplayName
}

function Resolve-AiName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$DisplayName
    )
    return Resolve-RegisteredName -Executable $Executable -Heading 'List of AIs:' -DisplayName $DisplayName
}

function Build-NewgrfLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DataDir,
        [Parameter(Mandatory)]$Manifest
    )
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($item in (Get-RequiredContent -Manifest $Manifest -Type 'newgrf')) {
        $filename = Resolve-NewgrfFilename -DataDir $DataDir -ContentId $item.content_id
        if (-not $filename) {
            throw "Build-NewgrfLines: could not resolve filename for content $($item.content_id)"
        }
        if ($item.parameters) {
            $lines.Add("$filename = $($item.parameters)")
        } else {
            $lines.Add("$filename =")
        }
    }
    return $lines.ToArray()
}

function Build-GameScriptLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)]$Manifest
    )
    $gs = Get-RequiredContent -Manifest $Manifest -Type 'game_script' | Select-Object -First 1
    if (-not $gs) { return @() }
    $scriptName = Resolve-GameScriptName -Executable $Executable -DisplayName $gs.name
    if (-not $scriptName) {
        throw "Build-GameScriptLine: could not resolve registered name for '$($gs.name)'"
    }
    return @("$scriptName =")
}

function Build-AiPlayersLines {
    <#
    .SYNOPSIS
    Prints the "[ai_players]" lines that pin the manifest's optional AI
    opponent to a company slot, or an empty array if none is present. Only
    call this when the user opted in (-WithAI) — see
    scripts/linux/content.sh build_ai_players_lines for the source-verified
    slot-ordering rationale (slot 0 = human/"none", slot 1 = the AI).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)]$Manifest
    )
    $ai = $Manifest.content | Where-Object { $_.type -eq 'ai' -and $_.source -eq 'bananas' } | Select-Object -First 1
    if (-not $ai) { return @() }
    $aiName = Resolve-AiName -Executable $Executable -DisplayName $ai.name
    if (-not $aiName) {
        throw "Build-AiPlayersLines: could not resolve registered name for '$($ai.name)'"
    }
    return @('none =', "$aiName =")
}
