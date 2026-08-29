# OpenTTD Blueprint

> Reproducible cross-platform OpenTTD setup for logistics, industries and transport networks.

OpenTTD Blueprint does **not** redistribute OpenTTD. It works with an
OpenTTD installation you already have (primarily Steam, on Linux or
Windows), and safely downloads/configures a curated, version-pinned set of
third-party NewGRFs and a Game Script through OpenTTD's own Online Content
system — backing up your existing configuration first, and never touching
your saves or unrelated content.

## Why Blueprint?

Setting up a "good" OpenTTD experience means hand-picking NewGRFs, getting
their load order and parameters right, and tuning a dozen gameplay
settings — then doing it again on every machine, and hoping you remember
what you picked. OpenTTD Blueprint turns that one-time research into a
versioned, reviewable, reproducible profile: clone the repo, run one
script, get the same setup every time, on Linux or Windows.

## Features

- One default profile (`logistics`) with a researched, documented NewGRF
  stack and Game Script — see `docs/MODS.md` for what and why.
- Content acquired exclusively through OpenTTD's own Online Content
  system — no scraping, no unofficial mirrors.
- `openttd.cfg` is **patched**, never replaced: every value this project
  owns lives inside marked blocks; everything else in your config is left
  byte-for-byte untouched.
- Timestamped backups before any config change, with a one-command restore.
- `--dry-run` shows exactly what would happen; `--verify` checks an
  install is correct; both make zero changes.
- Idempotent: running the installer again with nothing to do is a no-op.
- Never deletes your saves, screenshots, scenarios, or unrelated NewGRFs.

## What gets installed

For the default `logistics` profile: 9 NewGRFs (industries, trains, road
vehicles, ships, stations, landscape/trees, houses) and one Game Script —
full list, versions, licenses and rationale in `docs/MODS.md`. Nothing is
installed without you being able to read exactly what and why first
(`--dry-run`).

## Default logistics profile

> A deeper transport and logistics simulation with meaningful industrial
> chains, network planning and city growth, while remaining recognisably
> OpenTTD and avoiding excessive micromanagement.

FIRS Industries 5 for deeper industry chains, Iron Horse 4 / Road Hog /
SHARK for trains/road/ships, CHIPS Station Set 2 for industrial stations,
OpenGFX+ Landscape/Trees and ITL Houses for visual coherence, and Renewed
Village Growth as the Game Script — town growth depends on varied,
sustained cargo delivery, not passenger-service spam. See
`docs/CONFIGURATION.md` for the full gameplay-settings rationale
(CargoDist, economy, acceleration, breakdowns, map size, starting year).

## Requirements

**Linux**: Bash 5+, [`jq`](https://jqlang.org/), `tar`, `find`, `awk` — all
standard on any current desktop distro. OpenTTD via Steam (primary
target), a native `openttd` on `PATH`, or Flatpak. No `sudo`.

**Windows**: [PowerShell 7+](https://github.com/PowerShell/PowerShell)
(`pwsh`) — Windows 10/11's default Windows PowerShell 5.1 is not enough.
OpenTTD via Steam. No Administrator rights.

Full detail: `docs/LINUX.md`, `docs/WINDOWS.md`.

## Quick start

### Linux

```bash
git clone https://github.com/<you>/openttd-blueprint.git
cd openttd-blueprint
./install-linux.sh
```

### Windows

```powershell
git clone https://github.com/<you>/openttd-blueprint.git
cd openttd-blueprint
.\install-windows.ps1
```

If PowerShell blocks the script, see `docs/TROUBLESHOOTING.md` for the
safe one-off way to run it without changing your execution policy
permanently.

A first install downloads the full NewGRF/Game Script set through
OpenTTD's Online Content system — this can take several minutes (the
console content protocol has to sync a large catalog before it can select
individual packages; see `docs/RESEARCH.md` §3). Progress is printed as it
happens; re-running the installer skips anything already downloaded.

## Dry run

```bash
./install-linux.sh --dry-run      # Linux
.\install-windows.ps1 -DryRun     # Windows
```

Shows detected OpenTTD version/paths, which content is missing, and which
config sections would change — without writing anything.

## Verification

```bash
./install-linux.sh --verify       # Linux
.\install-windows.ps1 -Verify     # Windows
```

Checks the profile is fully installed and consistent; exits non-zero with
a specific `FAIL:` message per problem if not.

## Updating

Not yet implemented as an explicit command in v0.1.0 — the manifest
records exactly the content versions tested (`profiles/logistics/content-manifest.json`),
and updating those versions deliberately (a manifest change, reviewed like
any other) is how a future update would work. See `docs/SAVE_COMPATIBILITY.md`
for why this project doesn't silently chase "latest" forever.

## Backups

Created automatically before the first config change of a run, under
`~/.local/state/openttd-blueprint/backups/<timestamp>/` (Linux) or
`%LOCALAPPDATA%\OpenTTDBlueprint\backups\<timestamp>\` (Windows) — outside
both this git checkout and your live OpenTTD config. No backup is created
on a no-op re-run.

## Restore / uninstall

```bash
./uninstall-linux.sh --list       # see available backups
./uninstall-linux.sh              # restore the most recent one
```

```powershell
.\uninstall-windows.ps1 -ListBackups
.\uninstall-windows.ps1
```

This does **not** uninstall OpenTTD and does **not** delete any downloaded
content — only `openttd.cfg` is restored. See `docs/ARCHITECTURE.md`
"Additive content" for why.

## Steam compatibility

Primary target on both platforms. Native Steam (Linux/Windows) and
Flatpak OpenTTD (Linux) are auto-detected; Flatpak *Steam* itself isn't
yet — see `docs/LINUX.md`.

## Save-game compatibility

A save made with this profile should open on either platform, provided
both machines installed the same manifest version. Full detail (what
breaks compatibility, and why) in `docs/SAVE_COMPATIBILITY.md`.

## Included content

See `docs/MODS.md` for the full table (name, version, license, purpose)
and the "Deliberately excluded" section explaining what was researched
and left out on purpose (AXIS/ECS, Industrial Stations Renewal, an
aircraft set, railtype/roadtype NewGRFs, decorative objects) — and why.

## Configuration philosophy

`openttd.cfg` is never regenerated wholesale. Every value this project
owns lives inside `### BEGIN/END OPENTTD BLUEPRINT ### `-marked blocks, one
per section; everything outside those markers — your resolution, hotkeys,
network settings, anything — is left exactly as it was. Full rationale
and the alternatives considered: `docs/ARCHITECTURE.md`.

## Known incompatibilities

FIRS is a full industry-replacement set — do not additionally enable
AXIS or ECS (or any other industry replacement set) alongside it; see
`docs/MODS.md`.

## Troubleshooting

`docs/TROUBLESHOOTING.md` covers detection failures, content-download
issues, PowerShell execution policy, interrupted installs, and rollback.

## Project structure

```
openttd-blueprint/
├── install-linux.sh / install-windows.ps1     installers
├── uninstall-linux.sh / uninstall-windows.ps1  config restore
├── profiles/logistics/                         profile data (manifest, config, docs)
├── profiles/schema/                             JSON Schemas for the above
├── scripts/common/                              shared logic (Bash + PowerShell ports)
├── scripts/linux/ , scripts/windows/             platform-specific detection & content acquisition
├── tests/                                        fixture-based test suites (no real OpenTTD/network needed)
├── docs/                                         RESEARCH, ARCHITECTURE, MODS, CONFIGURATION, etc.
└── .github/workflows/                            CI (ShellCheck/PSScriptAnalyzer + tests)
```

## Development

See `CONTRIBUTING.md`. Tests run against fixtures under `tests/fixtures/`
— never against a real OpenTTD profile:

```bash
shellcheck install-linux.sh uninstall-linux.sh scripts/linux/*.sh scripts/common/*.sh
./tests/run-linux-tests.sh
```

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse
.\tests\Run-WindowsTests.ps1
```

## Contributing

See `CONTRIBUTING.md`.

## Licence

OpenTTD Blueprint's own code (installers, scripts, manifests,
documentation) is MIT-licensed — see `LICENSE`. This does **not** extend
to OpenTTD itself (GPL v2) or to any NewGRF/Game Script this project
downloads or configures, which remain under their respective authors'
licences. See `docs/MODS.md` and `THIRD_PARTY_LICENSES.md`.

## Third-party content and licences

This repository contains metadata and automation, not third-party
binaries. See `docs/MODS.md` for a full per-item license table and
`THIRD_PARTY_LICENSES.md` for licence text/links.

## Screenshots

Screenshots coming after the first validated gameplay build.

## Roadmap

**v0.2+**: `british` and `vanilla-plus` profiles, a profile selector,
controlled content-version upgrades, a `status` command.

**Later**: a `jgrpp` profile (JGR's Patch Pack), optional save-sync
guidance, a multiplayer/server profile, additional economies.

No dates promised — see `CHANGELOG.md` for what's actually shipped.
