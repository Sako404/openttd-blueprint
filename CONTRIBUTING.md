# Contributing to OpenTTD Blueprint

Thanks for considering a contribution. This project favours reproducibility,
safety and simplicity over feature count — see `docs/ARCHITECTURE.md` for the
philosophy behind the current design.

## Before you start

- For anything beyond a small fix, open an issue first to discuss the
  approach. This especially applies to adding new content to the default
  `logistics` profile or adding a new profile.
- Keep the Linux and Windows installers behaviourally equivalent. Logic
  that decides *what* to install belongs in the shared profile/manifest
  data, not duplicated per-platform.

## Adding or changing content in a profile

1. Verify the content against a primary source (BaNaNaS listing, author's
   own repository, or OpenTTD documentation) — not a forum post.
2. Update `profiles/<profile>/content-manifest.json` with the exact content
   ID, version, license and source.
3. Document the choice (and any rejected alternatives) in
   `docs/MODS.md`.
4. If it changes gameplay behaviour, document the reasoning in
   `docs/CONFIGURATION.md`.

## Code style

- **Bash**: must pass `shellcheck` with no unresolved warnings. Use
  `set -euo pipefail`, quote variables, keep functions small.
- **PowerShell**: must pass `PSScriptAnalyzer` with no unresolved warnings.
  Prefer built-in cmdlets over shelling out.
- No unnecessary new dependencies (see `docs/ARCHITECTURE.md` for the
  project's dependency-minimisation stance).

## Tests

Run the test suite in `tests/` before submitting a change — `tests/run-linux-tests.sh`
on Linux, `tests/Run-WindowsTests.ps1` on Windows. Both platforms are
supported, so a change to shared behaviour should be verified on both.
Any change to installer behaviour should come with a fixture-based test, not
manual verification only.

The tests deliberately never touch a real OpenTTD installation and never use
the network — they run against `tests/fixtures/` and a throwaway temp
directory. Keep it that way; a test that needs the live content server is a
manual check, not a test.

## Commit style

Small, logical commits. Conventional-commit-style prefixes are appreciated
(`feat:`, `fix:`, `docs:`, `test:`, `ci:`, `chore:`) but not mandatory.

## Reporting bugs

Open a GitHub issue with:

- OS and OpenTTD version
- exact command run (including flags)
- full output
- whether `--dry-run` reproduces the same detection results

Do not include personal file paths or credentials in bug reports.

## What must not go into the repository

- **No third-party content.** No NewGRFs, Game Scripts, AIs, basesets,
  graphics, sound or music, and no OpenTTD binaries. Blueprint references
  content by ID and lets OpenTTD fetch it; the repository stays metadata
  and automation.
- **No private or local-machine data.** No real home directories, machine
  names, Steam account paths, tokens or credentials. Use generic
  placeholders in examples — `C:\Users\me`, `~/.local/share/…`.

## Licensing

OpenTTD Blueprint's own code and documentation are licensed under
**AGPL-3.0-or-later** (see `LICENSE` and `NOTICE`). By submitting a
contribution you agree it is licensed under those same terms.

There is no CLA and no DCO sign-off requirement.

That licence covers this project's work only. It does not apply to OpenTTD
or to any third-party content Blueprint causes to be downloaded — those keep
their own licences. See `THIRD_PARTY_LICENSES.md`.

## Upstream

Official upstream: <https://github.com/Sako404/openttd-blueprint>
