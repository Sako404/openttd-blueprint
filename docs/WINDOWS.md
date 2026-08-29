# Windows notes

**Windows support is implemented and covered by PowerShell-side automated
tests and CI (`windows-latest`), but has not been physically run on a real
Windows machine or against a real Steam OpenTTD install** — this project
was developed on Linux. See `docs/RESEARCH.md`/the project's final report
for exactly what was and wasn't validated. If you run it on real Windows,
feedback (or a PR fixing what's wrong) is very welcome.

## Requirements

- PowerShell 7+ (`pwsh`). Windows 10/11 ship Windows PowerShell 5.1 by
  default, which is not the same thing — install PowerShell 7 from the
  Microsoft Store or [github.com/PowerShell/PowerShell](https://github.com/PowerShell/PowerShell)
  if `pwsh -v` doesn't work.
- OpenTTD via Steam (primary target).

## Detected paths (per OpenTTD's own documented directory structure)

Unlike Linux, Windows does **not** split config and data across separate
directories — both live together under:

```
%USERPROFILE%\Documents\OpenTTD\
```

containing `openttd.cfg` directly (not in a subfolder), plus
`newgrf\`, `ai\`, `game\`, `save\`, `scenario\`, `content_download\`, etc.
as siblings — the same set of subdirectories as Linux's data directory,
just merged into one root instead of split via XDG.

Steam's own install location (where the `OpenTTD.exe` binary lives, e.g.
`C:\Program Files (x86)\Steam\steamapps\common\OpenTTD\`) is a **different
directory** from the config/data directory above — `install-windows.ps1`
does not confuse the two (brief §28: "do not confuse the Steam
installation directory with user configuration directory").

Steam libraries on a non-C drive are supported: the installer enumerates
`libraryfolders.vdf` the same way the Linux installer does, not just the
default `C:\Program Files (x86)\Steam` path.

Backups live under `%LOCALAPPDATA%\OpenTTDBlueprint\backups\`.

## Running

```powershell
git clone https://github.com/<you>/openttd-blueprint.git
cd openttd-blueprint
.\install-windows.ps1 -DryRun   # see what would happen, no changes
.\install-windows.ps1           # install
.\install-windows.ps1 -Verify   # confirm it's installed correctly
```

If PowerShell blocks the script from running at all, see
`docs/TROUBLESHOOTING.md` — use `-ExecutionPolicy Bypass` for a single
invocation rather than permanently changing your execution policy.

No Administrator privileges are required or used.
