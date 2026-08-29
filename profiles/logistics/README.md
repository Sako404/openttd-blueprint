# Profile: logistics

The default OpenTTD Blueprint profile. A deeper transport and logistics
simulation with meaningful industrial chains, network planning and city
growth, while remaining recognisably OpenTTD.

- `profile.json` — display metadata, minimum OpenTTD version, and the
  gameplay settings this profile enforces (see schema:
  `profiles/schema/profile.schema.json`).
- `content-manifest.json` — every NewGRF/Game Script this profile installs
  or deliberately omits, with BaNaNaS content IDs, pinned versions,
  licenses and load order (schema:
  `profiles/schema/content-manifest.schema.json`).
- `openttd.cfg.block` — the literal, reviewed `key = value` lines this
  profile injects into the user's `openttd.cfg`, grouped by INI section.

See `docs/MODS.md` for what each piece of content does and why it was
chosen (or excluded), and `docs/CONFIGURATION.md` for the gameplay
reasoning behind every setting in `openttd.cfg.block`.
