# Linux notes

Primary target: CachyOS / Arch-based systems, but nothing here is
Arch-specific — `install-linux.sh` only assumes Bash, coreutils, `jq`,
`tar`, `find`, and `awk`, all standard on essentially any Linux desktop.

## Requirements

- Bash 5+ (standard on any current distro)
- `jq` — install via your package manager if missing, e.g.
  `sudo pacman -S jq` (Arch/CachyOS), `sudo apt install jq` (Debian/Ubuntu).
  The installer detects a missing `jq` and tells you, rather than
  installing it for you (brief §27: "do not silently install system
  packages").
- OpenTTD itself, installed via Steam (primary target) or otherwise
  reachable as `openttd` on `PATH`, or as a Flatpak (`org.openttd.OpenTTD`).

## Detected paths

- Steam library: every `steamapps` root under `~/.local/share/Steam`,
  `~/.steam/steam`, `~/.steam/root`, plus any extra libraries listed in
  `steamapps/libraryfolders.vdf`.
- Executable: `<steam-library>/steamapps/common/OpenTTD/openttd`, or a
  Flatpak (`flatpak run org.openttd.OpenTTD`), or whatever `openttd`
  resolves to on `PATH`.
- Config: `${XDG_CONFIG_HOME:-~/.config}/openttd/openttd.cfg` (native), or
  `~/.var/app/org.openttd.OpenTTD/config/openttd/openttd.cfg` (Flatpak).
- Data (NewGRF/AI/GameScript/saves): `${XDG_DATA_HOME:-~/.local/share}/openttd/`
  (native) or the equivalent `~/.var/app/...` path (Flatpak).
- Backups: `${XDG_STATE_HOME:-~/.local/state}/openttd-blueprint/backups/`
  — deliberately outside both the git checkout and the live OpenTTD
  config/data directories.

## Running

```bash
git clone https://github.com/<you>/openttd-blueprint.git
cd openttd-blueprint
./install-linux.sh --dry-run   # see what would happen, no changes
./install-linux.sh             # install
./install-linux.sh --verify    # confirm it's installed correctly
```

No `sudo` is required or used at any point.

## Steam Deck / Flatpak Steam

Flatpak Steam runs OpenTTD inside its own sandbox with a different data
root (`~/.var/app/com.valvesoftware.Steam/...`). This isn't autodetected
in v0.1.0 — `steam_library_paths()` only checks native Steam locations.
If you're on Flatpak Steam specifically (not a Flatpak OpenTTD — those
*are* detected), point the installer at the right paths manually by
exporting `XDG_CONFIG_HOME`/`XDG_DATA_HOME` before running it, or open an
issue if this is common enough to warrant native detection.
