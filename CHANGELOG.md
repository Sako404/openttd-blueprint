# Changelog

All notable changes to OpenTTD Blueprint are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-08-29

### Added

- Initial public release of OpenTTD Blueprint.
- `logistics` default profile: content manifest, gameplay configuration
  template, and NewGRF parameter/order documentation.
- `install-linux.sh` and `install-windows.ps1` with `--dry-run`/`-DryRun`
  and `--verify`/`-Verify` modes, timestamped config backups, and
  idempotent re-runs.
- `uninstall-linux.sh` and `uninstall-windows.ps1` for config restore.
- Content manifest schema and profile resolution.
- Automated fixture tests for manifest parsing, config generation and
  installer safety behaviour.
- GitHub Actions CI for Linux (ShellCheck + tests) and Windows
  (PSScriptAnalyzer + tests).
- Documentation: README, RESEARCH, MODS, CONFIGURATION, ARCHITECTURE,
  TROUBLESHOOTING, SAVE_COMPATIBILITY.
