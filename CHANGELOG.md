# Changelog

All notable changes to OpenTTD Blueprint are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-08-31

### Changed

- **Licence: MIT → GNU AGPL-3.0-or-later** for OpenTTD Blueprint's own
  code, manifests and documentation. Releases up to and including 0.1.0
  remain MIT; those grants are not revoked. The change applies from this
  release onward.
- `LICENSE` now carries the official AGPL text verbatim. The scope note
  that previously lived appended to the MIT text moved to `NOTICE`, which
  keeps the licence file detectable and the boundary explicit.

### Added

- `NOTICE` — copyright, official upstream, and the explicit statement that
  the AGPL covers this project's own work only and does not relicense
  OpenTTD or any third-party content Blueprint causes to be downloaded.
- `AUTHORS`.
- README: a project status and affiliation section stating plainly that
  OpenTTD Blueprint is an independent project, not an official OpenTTD
  project, and not affiliated with or endorsed by it.
- `CONTRIBUTING.md`: contribution licensing under AGPL (no CLA, no DCO),
  a rule that no third-party content or private machine data belongs in
  the repository, both-platform test guidance, and the upstream link.

### Note

No functional change to the installers in this release — it establishes the
project's open-source and governance baseline.

## [0.1.0] - 2026-08-29

### Added

- Initial public release of OpenTTD Blueprint.
- `logistics` default profile: content manifest, gameplay configuration
  template, and NewGRF parameter/order documentation.
- `install-linux.sh` and `install-windows.ps1` with `--dry-run`/`-DryRun`
  and `--verify`/`-Verify` modes, timestamped config backups, and
  idempotent re-runs.
- `uninstall-linux.sh` and `uninstall-windows.ps1` for config restore.
- Optional AI opponent (`--with-ai` / `-WithAI`, off by default): pins
  RailwAI to a company slot via `[ai_players]`/`max_no_competitors`,
  selected after comparing it against AdmiralAI/CivilAI/SimpleAI.
- Content manifest schema and profile resolution.
- Automated fixture tests for manifest parsing, config generation and
  installer safety behaviour.
- GitHub Actions CI for Linux (ShellCheck + tests) and Windows
  (PSScriptAnalyzer + tests).
- Documentation: README, RESEARCH, MODS, CONFIGURATION, ARCHITECTURE,
  TROUBLESHOOTING, SAVE_COMPATIBILITY.

### Fixed

- NewGRFs downloaded via the content system were left packed inside their
  `content_download/newgrf/*.tar`, where OpenTTD's plain-filename `[newgrf]`
  resolution cannot find them; the installer now extracts each `.grf` into
  a loose file under `newgrf/`.
- Multi-word `[game_scripts]`/`[ai_players]` keys (e.g. `Renewed Village
  Growth`) were silently truncated at the first space by OpenTTD's ini
  parser; such keys are now quoted.
- `economy.inflation = true` conflicts with the required Iron Horse NewGRF
  (fatal error on load); `inflation` now stays at the engine default
  (`false`). See `docs/RESEARCH.md` §5 "Stability check" for how all three
  were found — a live `openttd -D -x` run against the installed config,
  not just the installer's own dry-run/verify/idempotency checks.
