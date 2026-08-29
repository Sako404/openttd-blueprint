# Content — the `logistics` profile

Every item below is verified against a primary source (BaNaNaS package
page, the content's own project repository, or OpenTTD's own
documentation/source) as of 2026-08-29 — see `docs/RESEARCH.md` for the
full verification trail, including two cases where an initial
search-engine summary was stale and had to be corrected against the
primary source.

## Included

| Content | Type | Version | Required | Purpose | Source | License |
| --- | --- | --- | ---: | --- | --- | --- |
| OpenGFX+ Landscape | NewGRF | 1.1.2 | Yes | Landscape graphics enhancement | BaNaNaS `4f472b34` | GPL-2.0 |
| OpenGFX+ Trees | NewGRF | 0.8.0 | Yes | Tree graphics enhancement | BaNaNaS `46727806` | GPL-2.0 |
| FIRS Industries 5 | NewGRF | 5.2.0 | Yes | Primary industry replacement | BaNaNaS `f1250009` | GPL-2.0 |
| CHIPS Station Set 2 | NewGRF | 2.0.0 | Yes | Industrial-freight station tiles | BaNaNaS `43485054` | GPL-2.0 |
| Iron Horse 4 | NewGRF | 4.30.0 | Yes | Train set, 1860–2020 | BaNaNaS `43411223` | GPL-2.0 |
| Road Hog | NewGRF | 1.4.1 | Yes | Road vehicles (bus/truck/tram) | BaNaNaS `9787eafe` | GPL-2.0 |
| SHARK | NewGRF | 1.0 | Yes | Ships | BaNaNaS `4a44bbb1` | GPL-2.0 |
| ITL Houses | NewGRF | 2.1 | Yes | Town/building visual variety | BaNaNaS `54540301` | GPL-3.0 |
| Renewed Village Growth | Game Script | 12.1 | Yes | Transport-driven town growth | BaNaNaS `52455649` | GPL-2.0 |

### Why each was selected

**OpenGFX+ Landscape / Trees** — official-lineage graphics add-ons
(maintained alongside OpenTTD's own OpenGFX2 base set), low risk, improve
visual coherence with the rest of the stack. Loaded first (order 10–11) so
other content's tile/terrain references have them available.

**FIRS Industries 5** — the profile's centrepiece: replaces baseset
industries with deeper, chained ones (raw material → processing → goods),
which is what makes "network planning matters" true. No NewGRF parameters
were changed from default; FIRS's *economy* selection (Basic vs its more
complex alternatives) is an in-game choice, not a cfg-level parameter — see
`docs/CONFIGURATION.md`.

**CHIPS Station Set 2** — purpose-built "for use with industry sets such as
FIRS" per its own description; current (2021) versus the alternative
below.

**Iron Horse 4** — the actively-developed current generation of a
long-running, gameplay-focused train set (steam through modern electric,
1860–2020), refits to FIRS-style cargo. The original design brief
suggested "Iron Horse 3"; verified current is generation 4 (see
`docs/RESEARCH.md`).

**Road Hog / SHARK** — the road-vehicle and ship sets with the clearest
BaNaNaS presence and community track record for a FIRS-oriented setup.
Both are feature-complete but not actively updated (Road Hog since 2018,
SHARK since 2021) — flagged here for transparency, not treated as
disqualifying: neither shows an open compatibility problem, and "no
recent commits" is normal for a finished, single-purpose NewGRF in this
ecosystem.

**ITL Houses** — actively maintained (GitHub, 148+ commits), explicitly
states compatibility with all industry sets and Game Scripts, and doesn't
touch town-growth logic itself — no interaction risk with Renewed Village
Growth.

**Renewed Village Growth** — the only maintained Game Script found that
makes town growth depend on FIRS-style varied cargo delivery rather than
simple passenger/mail service spam, which is exactly the "transport
matters for city growth" mechanic the `logistics` profile is meant to
deliver (brief §22). Confirmed compatible with FIRS 5 via the project's
own current `readme.txt` (v12.1) — earlier BaNaNaS-indexed search results
looked capped at "FIRS 4.3," which turned out to be a stale summary of an
older listing (see `docs/RESEARCH.md` §4).

## Deliberately excluded

| Candidate | Why not |
| --- | --- |
| **AXIS**, **ECS** | Alternative industry-replacement sets. Running more than one alongside FIRS creates conflicting industry/cargo definitions for the same climate — a hard incompatibility, not a preference. Never combine with FIRS. |
| **Industrial Stations Renewal (ISR)** | Overlaps CHIPS Station Set 2 for the same industrial-freight station use case. Last released 2015 vs CHIPS 2's 2021; including both would be unnecessary duplication (brief §16) for no documented gameplay benefit. |
| **World Airliners Set** / **av8 Aviators Aircraft Set** | No aircraft set found showed sustained maintenance comparable to the rest of the stack, and aircraft is peripheral to the profile's stated surface-transport/logistics focus (brief §10). Either can be added manually via the in-game Online Content browser without conflicting with anything in this profile. |
| **U&RaTT** (roadtype/tramtype) | A real, current NewGRF, but adds roadtype-selection complexity without solving a specific gap in the default profile (brief §18). Can be added manually. |
| **"U&ReRMM"** (railtype) | No verifiable current package found under this name via BaNaNaS or its authors' own channels — this project doesn't include unverified content (brief §5, §17). Standard rail is sufficient for the default profile. |
| **City Objects** | Purely decorative; not included by default per brief §21's "materially improve player creativity" bar. Fine as a manual, optional addition. |
| **"New Renewed Village Growth"** | Targets the JGR Patch Pack fork specifically (requires JGRPP ≥0.39.0 when its non-default preset is used) — out of scope, since v0.1.0 targets vanilla upstream OpenTTD only (brief §9). |

## NewGRF load order

Order (lower loads first), and why:

1. **OpenGFX+ Landscape**, **OpenGFX+ Trees** — graphics/terrain
   extensions other content may reference.
2. **FIRS Industries 5** — defines the cargo types the rest of the stack
   refits to and interacts with.
3. **CHIPS Station Set 2** — station tiles reference FIRS's cargo classes.
4. **Iron Horse 4**, **Road Hog**, **SHARK** — vehicle sets; mutually
   order-independent, all consume FIRS cargo definitions.
5. **ITL Houses** — cosmetic house replacement with no cargo/industry
   interaction; safe to load last.

The exact `order` value for each item lives in
`profiles/logistics/content-manifest.json`, not duplicated here — see
`docs/RESEARCH.md` §5 for how OpenTTD actually determines load order
(verified against source, not guessed).

## Game Script parameters

Renewed Village Growth ships with its author's defaults for v0.1.0 — its
parameter set is extensive (display mode, growth-rate tuning, minimum
transported-cargo percentage, randomisation mode, and more; see the
project's own readme for the full list). Reviewing and tuning these is
tracked as a follow-up rather than blocking v0.1.0 on tuning every knob of
a script whose defaults are already designed to be sensible; any change
will be documented here when made.

## Optional AI opponent (`--with-ai` / `-WithAI`)

Not installed by default. Pass `--with-ai` (Linux) or `-WithAI` (Windows)
to pin one AI opponent to a company slot:

| Content | Type | Version | Purpose | Source | License |
| --- | --- | --- | --- | --- | --- |
| RailwAI | AI | 30 | Optional single opponent | BaNaNaS `52776169` | GPL-3.0 |

Selected over AdmiralAI (documented to repeatedly build airports and go
bankrupt once infrastructure maintenance is enabled — a direct conflict
with this profile's default economy settings), CivilAI (no release since
January 2022, unclear/custom licence), and SimpleAI (same maintenance-cost
failure class as AdmiralAI unless manually reconfigured to drop
aircraft). RailwAI's own description covers only trains, road vehicles
and ships — no aircraft at all — which avoids that whole failure class
structurally. Full comparison and source verification:
`docs/RESEARCH.md` §9.

Not confirmed as explicitly FIRS-tested by its author (no AI candidate
found was) — OpenTTD's AI scripting API is industry/cargo-set agnostic by
design, so baseline compatibility is expected but not a verified
guarantee. When enabled, the installer also sets
`difficulty.max_no_competitors = 1` (an AI pinned to a company slot has no
effect if the game isn't allowed to create that company at all) — see
`docs/CONFIGURATION.md`.
