# Save-game compatibility

OpenTTD Blueprint installs a *profile* (config + content). It does not
manage, convert, or synchronise save games in v0.1.0 (brief §43, §52).
This document exists so a save you create is one you can reliably reopen
later or on the other platform.

## What has to match for a save to load

- **Every NewGRF and Game Script referenced in the save must be present**
  on the machine loading it. OpenTTD tracks each by its internal grfid and
  can often substitute a newer compatible version of the same GRF, but a
  *missing* NewGRF blocks loading outright (you'll get an explicit "missing
  NewGRF" error, not silent corruption).
- **OpenTTD engine version**: generally forward-compatible (a newer
  OpenTTD opens an older save) but not reliably backward-compatible (an
  older OpenTTD may refuse a save made by a newer one). Keep both machines
  on the same or a newer OpenTTD release than the one the save was
  created with.
- **Game Script state**: Renewed Village Growth stores its own per-town
  state inside the save. Upgrading the script mid-save is generally safe
  (its versions are written to read older saved state); downgrading to an
  older script version after saving with a newer one is not supported.

## Practical guidance for this project

- Because both `install-linux.sh` and `install-windows.ps1` consume the
  same `profiles/logistics/content-manifest.json` with pinned versions, a
  save made on one platform should open cleanly on the other **provided
  both ran the same manifest version** (check
  `blueprint-state.json`'s `manifest_version` field on each machine).
- If you update the profile (a manifest version bump) after already
  playing a save, keep the old NewGRF versions available until you've
  either finished that save or deliberately migrated it — OpenTTD Blueprint
  does not delete previously-installed content on an update, precisely so
  older saves keep working (brief §53).
- `--verify` checks that the *currently selected* content matches the
  installed profile version; it does not inspect any specific save file.
  There is no save-scanning "will this save still load" command in
  v0.1.0.

## If a save complains about a missing NewGRF

See `docs/TROUBLESHOOTING.md` — in short: re-run the installer for the
profile version that save was created with (not necessarily the latest),
since the required content is additive and never removed by a later
install.
