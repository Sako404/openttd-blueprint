# Security Policy

OpenTTD Blueprint is a configuration/installer project, not a network
service, so its attack surface is small. Still, a few rules matter:

## Reporting a problem

Open a GitHub issue. Do not include:

- credentials, tokens, or passwords of any kind
- Steam account details
- full machine paths that reveal personal information

If the issue is sensitive (e.g. a script that could damage a user's
configuration or data), say so in the issue title and a maintainer will
follow up privately if needed.

## What this project does and does not do with your system

- The installers never require or store Steam credentials, GitHub
  credentials, or any other secret.
- The installers never require Administrator (Windows) or root/sudo
  (Linux) privileges. If a future change would need elevated privileges,
  that will be called out explicitly and remain optional.
- Content is only ever acquired through the mechanisms documented in
  `docs/RESEARCH.md` and `docs/ARCHITECTURE.md` — OpenTTD's own Online
  Content system or other documented official sources. No arbitrary
  binaries are fetched from unofficial mirrors.

## Before you run the scripts

`install-linux.sh` and `install-windows.ps1` are plain shell/PowerShell
scripts. As with any script you download from the internet, read it before
running it. Both are designed to be short enough to review in a few
minutes, and both support a `--dry-run` / `-DryRun` mode that makes no
changes so you can see exactly what would happen first.

## Supported versions

Only the latest tagged release is supported. Older tags are kept for
reference but not maintained.
