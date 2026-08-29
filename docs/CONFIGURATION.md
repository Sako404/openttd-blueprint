# Gameplay configuration — the `logistics` profile

Every value here is written verbatim from
`profiles/logistics/openttd.cfg.block`; this document explains the
intended gameplay consequence of each, and where a value differs from
OpenTTD's own current engine default, says so. Exact key names and how
they were verified (against OpenTTD's own settings tables, not guessed):
`docs/RESEARCH.md` §7.

## Starting year: 1950

Chosen for a stack spanning Iron Horse 4's 1860–2020 vehicle range: 1950
sits comfortably inside it, giving a mix of early-diesel/late-steam
starting equipment with plenty of runway to reach modern trains without
starting so early that the first several decades are spent waiting for
useful vehicles.

## Map size: 1024×1024

Large enough for intercity rail corridors, dedicated freight lines,
multiple industry clusters and future network expansion without forcing
cramped, everything-touches-everything layouts. Stored in `openttd.cfg` as
`map_x = 10` / `map_y = 10` — these keys hold the *bit exponent*, not the
tile count (`2^10 = 1024`); a literal `1024` in these keys would set an
absurdly large map.

## Town count & industry density: moderate (both at engine default)

`number_towns = 2` and `industry_density = 4` both match OpenTTD's own
"Normal" default — pinned explicitly here for reproducibility rather than
left implicit, not because the profile wants anything unusual. FIRS's
industry chains are already more numerous and interconnected than
baseset industries, so a moderate (not high) density avoids an overcrowded
map where chains overlap confusingly.

## Town growth rate: moderate (`town_growth_rate = 2`)

Also the engine default. Combined with Renewed Village Growth (see below),
the *rate* setting controls the ceiling on how fast a town can grow once
its cargo-delivery requirements are met — RVG controls whether it grows at
all.

## Vehicle breakdowns: off (`vehicle_breakdowns = 0`)

**Deviates from the engine's own default**, which is `1` (Reduced), not
off. The profile goes one step further and disables breakdowns entirely.
Rationale (brief §34): the profile is meant to reward good network design
— sufficient capacity, sensible routing, appropriate vehicle choices — not
random vehicle failures unrelated to how well a network was built.

## Realistic acceleration & wagon speed limits: on

`train_acceleration_model = 1`, `roadveh_acceleration_model = 1`,
`wagon_speed_limits = true`. All three already match OpenTTD's current
engine defaults (recent OpenTTD releases ship with realistic acceleration
on by default) — pinned explicitly so the profile doesn't silently drift
if a future OpenTTD release changes its own defaults. Realistic
acceleration makes gradients, curves and train weight/power actually
matter for route planning, which is central to a "network planning
matters" profile.

## Economy: inflation and infrastructure maintenance on

`inflation = true`, `infrastructure_maintenance = true`. **Both deviate
from the current engine default**, which is `false` for each in this
OpenTTD release. The profile turns them back on: inflation keeps costs and
income meaningful across a long game rather than money becoming trivial by
the 2000s, and infrastructure maintenance means an oversized, poorly-used
network has an ongoing cost — rewarding networks sized to what they
actually carry, not "build everything everywhere for free."

Neither setting is tuned to be punishing — this is the same balance
OpenTTD shipped as default for years before the recent default change, not
a custom harsh-economy configuration.

## CargoDist (`[linkgraph]`)

- `distribution_pax = 2` (Symmetric) — most players make return trips, so
  passenger demand between two stations should roughly balance in both
  directions.
- `distribution_mail = 2` (Symmetric) — same reasoning as passengers.
- `distribution_armoured = 1` (Asymmetric) — valuables/gold-style cargo
  typically flows one way (mine → bank), so forcing symmetry would be
  wrong.
- `distribution_default = 1` (Asymmetric) — covers FIRS's general freight
  cargo (goods, food, materials, etc.): raw materials flow toward
  processing industries and finished goods flow toward towns, which is
  inherently one-directional. Note this key's valid range doesn't even
  permit Symmetric (`MaxNonSymmetric = 1` is its maximum) — OpenTTD itself
  treats default/freight cargo as asymmetric-only by design.

All four default to `Manual` (no automatic distribution) in current
OpenTTD if left unset — the profile turns CargoDist on deliberately for
all of them, since manual cargo routing at scale is exactly the
"exhausting spreadsheet simulator" the brief (§10) wants to avoid.

## FIRS economy selection

FIRS 5 ships with multiple selectable "economies" (Basic through more
elaborate chain structures) chosen in-game via the NewGRF Settings window,
not via an `openttd.cfg` key or install-time parameter. v0.1.0 leaves this
at FIRS's own default (Basic) — approachable without a wall of
prerequisite chains, while still meaningfully deeper than baseset
industries. Documented here rather than silently defaulted: a future
profile revision could pin a more advanced economy once the basic setup
has been played and validated.

## Renewed Village Growth parameters

Left at the script's own defaults for v0.1.0 — see
`docs/MODS.md` "Game Script parameters" for why, and what's tracked as a
follow-up.
