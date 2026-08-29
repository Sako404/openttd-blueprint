# Troubleshooting

## "OpenTTD was not found"

The installer checks Steam library folders (native only in v0.1.0 — see
`docs/LINUX.md` "Steam Deck / Flatpak Steam"), Flatpak, and `PATH`. If
OpenTTD is installed somewhere else, either add it to `PATH` or open an
issue describing your setup.

## "OpenTTD was found, but version X.Y is too old"

The `logistics` profile requires OpenTTD ≥ the version in
`profiles/logistics/profile.json`'s `openttd_min_version`. Update OpenTTD
through Steam (or your package manager) and re-run.

## Config directory not detected / wrong path

Override `XDG_CONFIG_HOME`/`XDG_DATA_HOME` before running the installer if
your OpenTTD uses a non-standard location (e.g. Flatpak Steam — see
`docs/LINUX.md`). `--dry-run` always shows the exact paths it resolved
before anything changes, so check that first.

## Content downloader fails / times out

`install-linux.sh` drives OpenTTD's own Online Content system headlessly
(see `docs/RESEARCH.md` §3 and `docs/ARCHITECTURE.md` "Download
mechanism") — this needs a working internet connection to
`content.openttd.org`. If it fails:

- Check general internet connectivity.
- Re-run the installer — it's idempotent and skips content that's already
  present, so a re-run only retries what's actually missing.
- If a specific package consistently fails, check its BaNaNaS page
  (linked from `profiles/logistics/content-manifest.json`'s
  `project_url` field) to confirm it's still available — content is
  occasionally pulled by its author.

## A downloaded version doesn't match the manifest's pinned version

OpenTTD's console content protocol doesn't expose a documented way to
select an exact historical version non-interactively (see
`docs/RESEARCH.md` §3) — the installer resolves each package to whatever
version the content server currently lists first for that content ID,
which is normally the current/recommended one. `--verify` checks that
required content is *present*, not that its version exactly matches the
manifest. If you need the precise historical version (e.g. to open an old
save), install it manually via OpenTTD's in-game Online Content browser.

## "NewGRF unavailable" / missing NewGRF when loading a save

The save references a NewGRF that isn't installed, or a different version
of one that is. See `docs/SAVE_COMPATIBILITY.md`. Re-running the installer
never removes previously-installed content, so if the save was made with
an older Blueprint version, re-installing the current profile won't have
removed what that save needs — the issue is more likely that the content
was never installed on this machine at all, or was manually removed.

## Missing Game Script after install

Run `./install-linux.sh --verify` — it checks for the `[game_scripts]`
managed block specifically. If content download succeeded but the script
still isn't listed, `build_gamescript_line` couldn't match the downloaded
script's registered name via `openttd -h`'s "List of Game Scripts:"
listing; this can happen if the script's author changed its internal
short name. Open an issue with your `openttd -h` output.

## A NewGRF fatal-errors on startup ("not compatible with OpenTTD Inflation" or similar)

Some NewGRFs hard-refuse to load under specific engine settings — this is
the NewGRF's own author-authored check, not an installer bug. The
`logistics` profile hit exactly this with Iron Horse and `economy.inflation`
(see `docs/RESEARCH.md` §5 "Stability check" and `docs/CONFIGURATION.md`),
and now ships with the conflicting setting left at the engine default. If
you've since changed `inflation` (or another economy setting) back on
manually and a required NewGRF stops loading, that manual change is the
cause — check `content-manifest.json`'s `incompatibilities` field for the
item, and OpenTTD's own startup log for the exact NewGRF error text.

## Occasional stutters / brief freezes during play

Most likely cause: CargoDist (Link Graph). The `logistics` profile
deliberately turns `linkgraph.distribution_pax`/`distribution_mail` to
Symmetric and `distribution_armoured`/`distribution_default` to Asymmetric
(engine default is Manual for all four — see `docs/RESEARCH.md` §6). Under
Manual, the engine never runs the link-graph solver at all; under
Symmetric/Asymmetric it does, on a schedule controlled by two settings the
profile leaves at their engine defaults (verified against
`src/table/settings/linkgraph_settings.ini`, `OpenTTD/OpenTTD` on GitHub):

- `linkgraph.recalc_interval` — default `8`: recalculate the graph every 8
  in-game days.
- `linkgraph.recalc_time` — default `32`: spread that recalculation over
  32 in-game days in a background thread.
- `linkgraph.accuracy` — default `16` (range 2-64): higher is more precise
  and more expensive.

The recalculation itself runs off the main thread, but on a busy network —
FIRS's industry chains and Iron Horse's large vehicle roster both push the
graph size up — the periodic sync back to the main thread can still be
felt as a brief stutter, roughly every 8 in-game days. This was observed
live on 2026-08-29: a direct CPU comparison at the main menu between
vanilla OpenTTD (no content) and the same machine with the `logistics`
profile loaded showed ~15-20% CPU vanilla vs. ~36-47% with the profile,
even before any player-built network existed — confirming the added
content itself (not a general OpenTTD/hardware issue) drives the extra
load that the link-graph recalculation then periodically spends.

This is a deliberate profile trade-off (CargoDist is central to
"logistics"), not an installer bug. If the stutters are disruptive, no
reinstall is needed — adjust it in-game: **Settings → Advanced Settings →
Environment → Cargo Distribution**. Lowering `accuracy` makes each
recalculation cheaper; raising `recalc_interval` makes it happen less
often. Both trade routing precision for smoothness.

## Windows: "running scripts is disabled on this system"

PowerShell's default execution policy blocks unsigned local scripts. Don't
permanently lower your execution policy — instead, run the installer for
just this one invocation:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1
```

## Installer interrupted mid-way

Safe to just re-run. The config-patching step only ever writes a fully
computed replacement file in one atomic move (see
`docs/ARCHITECTURE.md` "Config ownership"), and content download is
resumable/idempotent — re-running skips anything already present and
retries anything missing.

## Rolling back

```bash
./uninstall-linux.sh --list      # see available backups
./uninstall-linux.sh             # restore the most recent one
```

See `docs/SAVE_COMPATIBILITY.md` before removing content a save still
depends on — `uninstall-linux.sh` only ever restores `openttd.cfg`, never
deletes downloaded content, so this is safe to run even if you're unsure.

## Verification failures

`./install-linux.sh --verify` prints one `FAIL:` line per problem found
(missing content, missing config block, wrong profile) and exits non-zero.
Each message names exactly what's missing — re-running `install-linux.sh`
(not `--verify`) fixes most of them, since it's idempotent.
