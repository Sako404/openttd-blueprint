# Research

Findings backing every architectural and content decision in this repo.
Where this repo's original design brief assumed something that verification
contradicted, that's called out explicitly as a **Deviation**. All source
excerpts below were fetched directly (WebFetch/WebSearch, and for the most
load-bearing claims, `curl` against raw source files) on 2026-08-29 against
OpenTTD `master` and the current stable release.

## 1. Current OpenTTD version

The local Steam installation reports **OpenTTD 15.3** (`openttd -h`, first
line — this is the correct flag; see §2). This is the current stable
release line; Steam distributes stable releases, not nightlies. All
manifest entries in this repo are verified against 15.3 behaviour and
source (`master` branch, which tracks post-15.3 development but has not
changed any of the settings/config mechanisms referenced here).

## 2. Directories and version detection

Confirmed on this machine (Linux, native Steam, XDG):

- Executable: `~/.local/share/Steam/steamapps/common/OpenTTD/openttd`
  (Steam appid `1536610`)
- Config dir: `${XDG_CONFIG_HOME:-~/.config}/openttd/openttd.cfg`
- Data dir: `${XDG_DATA_HOME:-~/.local/share}/openttd/`, containing
  `newgrf/`, `ai/`, `game/`, `scenario/`, `save/`, `screenshot/`,
  `content_download/{newgrf,ai,game,scenario,baseset,social_integration}/`

Windows (per OpenTTD's own directory-structure documentation, not locally
verified — see §Windows validation caveat in ARCHITECTURE.md): config and
data both live under `%USERPROFILE%\Documents\OpenTTD\`, i.e. no
config/data split like Linux's XDG scheme — `openttd.cfg` and `newgrf/`
etc. are siblings in that one directory.

**Deviation:** the brief assumed a version-flag check; `-v` sets the video
driver (confirmed: `openttd -v` with no argument exits 1 after printing the
version, which is not a stable "success" signal to script against). `-h`
reliably exits 0 with `OpenTTD <version>` as its first output line — this
repo's detection scripts use `-h`, not `-v`.

## 3. Content automation

Verified console command family (OpenTTD wiki "Dedicated server" manual):

```
content update              # refresh the available-content list from the server
content state [filter]      # list content, optionally filtered
content select <id>         # mark one content ID for download (repeatable)
content download            # download everything currently selected
```

Download does **not** activate content — activation means the NewGRF/Game
Script actually appears in `openttd.cfg`'s `[newgrf]`/`[game_scripts]`
sections, which is a separate step.

**Command-line flags relevant to automation** (verified directly:
`openttd -h` on the local install):

- `-D [host][:port]` — start a dedicated server, which exposes the console
  over stdin without needing a GUI.
- `-f` — fork dedicated server to background.
- `-x` — never save configuration changes to disk (useful for a
  content-only run that shouldn't touch `openttd.cfg`).
- No flag exists to pass a console-command script file directly (no
  `--script`/`-x <file>` equivalent in the option list).

**Decision:** drive content acquisition by launching
`openttd -D -x` and piping a newline-separated command sequence
(`content update`, one `content select <id>` per required manifest entry,
`content download`, `quit`) to its stdin, capturing stdout to a log for
`--dry-run`/failure reporting. This is the officially documented mechanism
(console content commands via dedicated-server mode) — not scraping, not
an unofficial endpoint. Confirmed non-interactive: the dedicated server
reads commands from stdin line-by-line with no GUI required.

**Resolving content IDs to `[newgrf]` cfg entries:** downloaded content
lands as `content_download/<type>/<content_id>-<slug>-<version>.tar`
(confirmed from this machine's pre-existing AI/GameScript downloads, e.g.
`content_download/ai/41444d4c-AdmiralAI-25.tar`). `tar -tf` on that archive
lists the `.grf` filename(s) it contains without extracting or executing
anything. OpenTTD's own file-search (`Fio`, `Subdirectory::NewGrf`) scans
`content_download/newgrf/` as a NewGRF search path, so the plain filename
found inside the tar is a valid `[newgrf]` key with no separate extraction
step and no need to compute a GRF's internal 4-byte ID or MD5 (see §5) —
**Decision**: the installer resolves each manifest entry's real on-disk
filename this way at install time, rather than hard-coding filenames that
could silently drift from what BaNaNaS actually serves.

BaNaNaS itself exposes no separate documented public API beyond the
in-game content protocol; using the game's own client (headless, as above)
is the correct "official mechanism," ranked above scraping the BaNaNaS web
UI.

## 4. Content stack

All content IDs are BaNaNaS's content ID (verified from each package's own
`bananas.openttd.org/package/<type>/<id>` URL), all versions are the
current "available ingame" (i.e. actively downloadable, not
savegame-only-legacy) release as of 2026-08-29.

| Item | Type | ID | Version | License | Status |
|---|---|---|---|---|---|
| FIRS Industries 5 | newgrf | `f1250009` | 5.2.0 | GPL v2 | active (last release 2026-01-25) |
| Iron Horse 4 | newgrf | `43411223` | 4.30.0 | GPL v2 | active (last release 2026-08-29) |
| Road Hog | newgrf | `9787eafe` | 1.4.1 | GPL v2 | feature-complete, unmaintained since 2018 |
| SHARK | newgrf | `4a44bbb1` | 1.0 | GPL v2 | feature-complete, unmaintained since 2021 |
| CHIPS Station Set 2 | newgrf | `43485054` | 2.0.0 | GPL v2 | stable since 2021 |
| OpenGFX+ Landscape | newgrf | `4f472b34` | 1.1.x | GPL v2 | stable |
| OpenGFX+ Trees | newgrf | `46727806` | 0.8.0 | GPL v2 | stable since 2013 |
| ITL Houses | newgrf | `54540301` | 2.1 | **GPL v3** | active (GitHub, 148+ commits) |
| Renewed Village Growth | game_script | `52455649` | 12.1 | GPL v2 | active (last release 2025-07-12) |

Omitted candidates (documented in full in `docs/MODS.md`): Industrial
Stations Renewal (redundant with CHIPS 2), any aircraft set, a railtype
NewGRF, U&RaTT roadtype, decorative City Objects.

### FIRS 5 × Renewed Village Growth compatibility

**This needed real verification, and the first source checked was wrong.**
BaNaNaS's own package-history view for Renewed Village Growth (fetched via
its search-indexed summary) showed old 2020-era versions (4.0–4.2) and a
compatibility list capped at "FIRS 4.3." Fetching the *raw* `readme.txt`
from the script's actual GitHub repository
(`github.com/F1rrel/RenewedVillageGrowth`, current released version 12.1,
2025-07-12) shows the up-to-date compatibility line: **"FIRS 1.4, 2, 3,
4.3, 5 (all economies)."** FIRS 5 support was added well after BaNaNaS's
indexed history became stale in search results. Always prefer the primary
project source over a search-engine summary of a listing page — confirmed
here by cross-checking the exact version number (12.1) against BaNaNaS's
own package page, which does list 12.1 as current.

There is also a "New Renewed Village Growth" package (content ID
`4e525647`) — checked and rejected: its README requires **JGRPP 0.39.0+**
when its "preset" option is non-default, i.e. it targets the JGR Patch
Pack fork, not vanilla upstream OpenTTD. Out of scope for v0.1.0 (§9 of the
brief: JGRPP is explicitly not a v0.1.0 dependency).

### Iron Horse generation

The brief suggested "Iron Horse 3." Verified current: **Iron Horse 4**
(content ID `43411223`) is the actively maintained generation — released
today (2026-08-29) at time of research, versions climbing from 4.3.0 in
January 2026 to 4.30.0 same year, i.e. near-continuous development. Iron
Horse 3 (`43411222`) still exists on BaNaNaS but is the previous
generation. **Decision:** ship Iron Horse 4. **Deviation from brief**:
generation 4, not 3 — the brief's suggestion predates Iron Horse 4 becoming
the current line.

### Stations: CHIPS 2 vs Industrial Stations Renewal

Both provide industrial-freight-oriented station tiles compatible with
FIRS-style cargos. ISR's last release is 2015 (v1.0.2); CHIPS 2's is 2021
and is explicitly described as built "for use with industry sets such as
FIRS." **Decision:** ship CHIPS 2 only. Running both would duplicate
station-tile coverage for the same cargo types without a documented
reason to combine them (brief §16: "if they create unnecessary
duplication, choose the better combination"). ISR is documented as a
rejected alternative in `docs/MODS.md`, not included in the manifest.

### Aircraft — omitted

Two candidates found: World Airliners Set (WAS, content ID `57415332` /
also listed at `57a50001`, current tag "r7876 0.2") and av8 Aviators
Aircraft Set (`44440a01`). Neither shows the kind of sustained,
version-incrementing activity seen for Iron Horse or FIRS, and the
`logistics` profile's stated focus (§10 of the brief) is industrial
chains, freight, rail and road networks — aircraft is peripheral to that
goal. **Decision:** omit an aircraft set from the default profile for
v0.1.0 rather than include one on weak footing; documented as an optional
manual addition in `docs/MODS.md`.

### Railtype / roadtype — omitted

No current, verifiable NewGRF matching the brief's "U&ReRMM" name was
found on BaNaNaS or via search — likely a naming mix-up or a very obscure
package that isn't indexed well enough to verify against a primary source,
which this project's philosophy (§5, §17 of the brief: "avoid depending on
old forum posts... verify current behaviour") rules out including
unverified. **Decision:** no default railtype NewGRF — standard rail is
sufficient for the `logistics` profile and this keeps the stack simpler
(brief §17: "select the simplest strong option").

U&RaTT (roadtype, content ID `55464989`, "U&RaTT 2" at `55464950`) *does*
exist and is verifiable, but adds roadtype-selection complexity with no
specific gameplay problem it solves for this profile's freight/industry
focus. **Decision:** omit from the default profile (brief §18: "avoid
adding roadtype complexity unless it improves gameplay"); documented as an
optional add-on in `docs/MODS.md`, not installed by default.

### City Objects — omitted

Purely decorative; brief §21 gates inclusion on "materially improve player
creativity" for the *default* profile. Left as a manual, optional
suggestion in `docs/MODS.md`.

### AXIS / ECS — explicitly excluded

Both are alternative industry-replacement sets to FIRS. Running more than
one industry set simultaneously creates conflicting industry/cargo
definitions in the same climate — this is a hard incompatibility, not a
style preference (brief §11). Never combine with FIRS.

## 5. `[newgrf]` config syntax and load order

Verified directly against OpenTTD source
(`src/settings.cpp: GRFSaveConfig` / `GRFLoadConfig`,
`src/newgrf_config.cpp: GRFBuildParamList`, `master` branch, 2026-08-29):

```cpp
// GRFSaveConfig (settings.cpp)
std::string key = fmt::format("{}|{}|{}", FormatArrayAsHex(c->ident.grfid),
        FormatArrayAsHex(c->ident.md5sum), c->filename);
group.GetOrCreateItem(key).SetValue(GRFBuildParamList(*c));

// GRFBuildParamList (newgrf_config.cpp) — SPACE separated, not comma
for (const uint32_t &value : c.param) {
    if (!result.empty()) result += ' ';
    format_append(result, "{}", value);
}
```

So the full form OpenTTD itself writes is:

```
[newgrf]
<grfid-hex>|<md5sum-hex>|<filename> = <param1> <param2> ...
```

**But** `GRFLoadConfig` (the reader) explicitly supports a simpler form:
if the key contains no `|`, or the `grfid|md5|` prefix fails to resolve to
a known GRF, it falls back to treating the *entire key as a plain
filename* and searches for it via `FioCheckFileExists(...,
Subdirectory::NewGrf)`. **Decision:** author `newgrf.cfg` using plain
filenames (e.g. `firs.grf = 5 0 1`), not the grfid|md5|filename form —
simpler to author and review, and fully supported by the loader. Real
filenames are resolved from each downloaded content tar at install time
(§3), not guessed in advance.

**Order**: `GRFLoadConfig` iterates `group->items` in the order they
appear in the ini file and builds the `GRFConfigList` in that order — line
order in `[newgrf]` **is** load order.

**Deviation from brief**: the brief guessed comma-separated parameters;
verified: space-separated integers (`ParseIntList`), and no default
`grfid|md5sum|` prefix is required.

**Chosen load order** (documented rationale — see `docs/MODS.md` for the
full per-item reasoning): graphics/landscape first (OpenGFX+ Landscape,
OpenGFX+ Trees) → industry set (FIRS, defines the cargo types everything
else refits to) → stations (CHIPS 2, references FIRS cargo classes) →
vehicles (Iron Horse, Road Hog, SHARK — mutually order-independent, cargo
consumers) → houses (ITL Houses, purely cosmetic, no cargo interaction).

### Stability check: three bugs found by actually starting the game

Every earlier check in this project (unit tests, dry-run, `--verify`,
idempotency, backup/restore) validates the *installer's own* claims about
what it wrote — none of them start OpenTTD with the result and watch what
happens. Doing exactly that (`openttd -D -x` against a real installed
config, log inspected for `error`/`fatal`/`not found`/`removed from list`)
surfaced three real problems the installer's own checks were structurally
blind to:

1. **NewGRFs resolved but not loadable.** `[newgrf]` plain-filename
   resolution (§5 above) only finds a file that is *loose* directly under
   `newgrf/`. The installer originally left downloaded content packed
   inside `content_download/newgrf/<id>-*.tar` — present on disk, correctly
   detected by `content_present()`, but invisible to `FioCheckFileExists`.
   Live symptom: all 8 required NewGRFs logged `ignoring invalid NewGRF
   '...': not found`. Fix: `resolve_newgrf_filename` (`scripts/linux/content.sh`,
   mirrored in `scripts/windows/Content.ps1`) now extracts the `.grf` out of
   its tar and copies it (flattened) into `newgrf/` if not already loose
   there. Verified in isolation before implementing (manual extraction of
   one file made that file's "not found" error disappear) and again after,
   end-to-end, for all 8.

2. **Multi-word `[game_scripts]`/`[ai_players]` keys silently truncated.**
   OpenTTD's ini parser splits an unquoted key on the first space, so
   `Renewed Village Growth =` was read as key `Renewed`. Live symptom: `The
   GameScript by the name 'Renewed' was no longer found`. Fix:
   `build_gamescript_line`/`build_ai_players_lines` now wrap any key
   containing a space in double quotes. Verified in isolation (a manually
   quoted key loaded correctly, no "not found"/"removed from list" message,
   only cosmetic upstream Squirrel translation-string warnings) and again
   end-to-end.

3. **`inflation = true` conflicts with a required NewGRF.** With both bugs
   above fixed and NewGRFs actually loading, live testing surfaced a third,
   unrelated problem: `The NewGRF "Iron Horse 4.30.0" has returned a fatal
   error: Iron Horse is not compatible with OpenTTD Inflation. Please turn
   Inflation off in OpenTTD settings.` — Iron Horse's own author-authored
   error string, triggered by checking OpenTTD's inflation setting at load
   time. This is a genuine design conflict between two of the profile's own
   choices (economy toughness vs. the required train set), not an installer
   bug. The server did not crash and the rest of the map/game continued,
   but the train set — central to a "logistics" profile — silently failed
   to load, which is a stability regression by any practical definition.
   Resolved by reverting `economy.inflation` to the engine default
   (`false`); see `docs/CONFIGURATION.md` and §7 below.

None of these three would have been caught by testing only the installer's
own success criteria (file present, config byte-identical, no error exit
code) — all three required actually starting OpenTTD against the result.

## 6. CargoDist / `[linkgraph]`

Verified against `src/table/settings/linkgraph_settings.ini` and
`src/linkgraph/linkgraph_type.h` (`enum class DistributionType`):

```
Manual = 0, Asymmetric = 1, Symmetric = 2
```

Keys (all `[linkgraph]`, all default to `Manual` in current OpenTTD —
**deviation**: earlier community guidance assumed a non-manual default;
15.3's actual default is Manual for all four):

- `distribution_pax` — set to `2` (Symmetric)
- `distribution_mail` — set to `2` (Symmetric)
- `distribution_armoured` — set to `1` (Asymmetric)
- `distribution_default` — set to `1` (Asymmetric; this key's valid max is
  `MaxNonSymmetric = 1`, i.e. it **cannot** be set to Symmetric at all —
  confirms freight-type cargo is asymmetric-only by design, matching the
  brief's intent)

## 7. Gameplay config keys

Verified against `src/table/settings/{difficulty,economy,world,game}_settings.ini`
and `src/settings_type.h` enum definitions:

| Setting | Section.key | Type/enum | Engine default (15.3/master) | Profile value | Note |
|---|---|---|---|---|---|
| Train acceleration | `vehicle.train_acceleration_model` | `AccelerationModel` (Original=0, Realistic=1) | **Realistic (1)** | `1` | Already the engine default — pinned explicitly for reproducibility |
| Road vehicle acceleration | `vehicle.roadveh_acceleration_model` | same enum | **Realistic (1)** | `1` | Same |
| Wagon speed limits | `vehicle.wagon_speed_limits` | bool | `true` | `true` | Already default, pinned |
| Vehicle breakdowns | `difficulty.vehicle_breakdowns` | `VehicleBreakdowns` (None=0, Reduced=1, Normal=2) | Reduced (1) | `0` (None) | **Deviation**: engine default is already "Reduced," profile goes further to fully Off per brief's "network design should matter more than random breakdown frustration" |
| Inflation | `economy.inflation` | bool | `false` | `false` | Left at engine default — see §5 "Stability check" below. An earlier iteration of this profile turned it on deliberately; reverted after live testing showed Iron Horse (required NewGRF) fatal-errors when inflation is on |
| Infrastructure maintenance | `economy.infrastructure_maintenance` | bool | `false` | `true` | Same — deliberately enabled |
| Starting year | `game_creation.starting_year` | int | 1950 | `1950` | Matches brief; still correct for a stack spanning 1860–2020 |
| Map size | `game_creation.map_x` / `map_y` | **bits**, not tiles (`size = 2^bits`) | `8` (256) | `10` / `10` | 2^10 = 1024, matching the brief's 1024×1024. **Important**: these keys store the bit exponent, not the tile count — a common mistake to hard-code `1024` literally |
| Town count | `difficulty.number_towns` | enum 0–4 | 2 (Normal) | `2` | Matches "moderate," pinned explicitly |
| Industry density | `difficulty.industry_density` | `IndustryDensity` (0–5, Normal=4) | Normal (4) | `4` | Matches "moderate," pinned explicitly |
| Town growth rate | `economy.town_growth_rate` | int 0–4 | `2` | `2` | Matches "moderate," pinned explicitly |

## 8. Save compatibility

- Loading a save requires every NewGRF/Game Script referenced in it to be
  present (same grfid) — a compatible *version* is usually enough (OpenTTD
  tracks per-GRF version/MD5 and can often substitute the newest
  compatible install), but a missing NewGRF entirely blocks loading.
- Since this profile pins exact versions (§4) and installs both platforms
  from the same manifest, a save made on Linux should open on Windows
  running the same profile version, and vice versa, provided both machines
  ran `install-*` against the same manifest version.
- OpenTTD-engine version mismatches across a save are generally
  forward-compatible (newer OpenTTD loads older saves) but not reliably
  backward-compatible; keep both machines on the same or newer OpenTTD
  release than the one the save was created with.
- Renewed Village Growth stores its own state in the save; upgrading its
  version mid-save is generally safe (script versions are designed to
  read older state), but downgrading is not supported by GameScript
  semantics in general.
- Full detail and a pre-flight checklist live in `docs/SAVE_COMPATIBILITY.md`.

## 9. AI opponent (optional, `--with-ai` / `-WithAI`)

Added after the initial v0.1.0 build, as a scoped, opt-in addition — off
by default, using the same manifest/versioning/download architecture as
every other content item (§3–§5), never a custom or hand-written AI.

**Candidates evaluated** (via BaNaNaS package pages, the outdated-but-
still-useful wiki "Comparison of AIs" page, and community discussion
threads — no single current, authoritative "best AI" source exists, so
this drew on more, individually weaker sources than the NewGRF research
above, and is flagged as such):

| AI | Latest version | License | Last released | Notes |
|---|---|---|---|---|
| AdmiralAI | — | — | — | **Rejected.** Multiple independent sources describe it repeatedly building airports and going bankrupt once infrastructure maintenance costs are enabled — this profile turns `economy.infrastructure_maintenance` on by default (§7), so this is a direct, known conflict, not a hypothetical one. |
| CivilAI | 37 | Custom (author "Pikka") | 2022-01-09 | General-purpose, all transport types. No maintenance-cost issue found, but no release since Jan 2022 and a non-standard/unclear licence — weaker footing than RailwAI on both maintenance recency and licensing clarity. |
| SimpleAI | — | — | — | Described as basic/stable/light, closest to the original TTD AI — but sources note it also needs manual reconfiguration (disable aircraft) to survive infrastructure maintenance, i.e. the same failure class as AdmiralAI unless tuned. |
| **RailwAI** (selected) | 30 | GPL-3.0 | 2023-05-12 | Trains/road vehicles/ships only — no aircraft mentioned in its own description at all, which sidesteps the airport-bankruptcy failure class structurally rather than needing configuration to avoid it. More recently released than CivilAI, and clearly GPL-3.0 licensed. BaNaNaS content ID `52776169`. |

**Decision:** RailwAI, content ID `52776169`, version 30. Not confirmed as
explicitly "FIRS-tested" by its author — no candidate found was. OpenTTD's
AI scripting API is industry/cargo-set agnostic by design (an AI queries
live game state for available cargos/industries rather than hardcoding a
specific NewGRF), so baseline functionality alongside FIRS is expected,
but this is a reasonable inference, not a verified claim — documented as
such in `docs/MODS.md`, not oversold.

**Activation mechanism**, verified directly against OpenTTD source
(`src/settings.cpp: AILoadConfig`/`AISaveConfig`, same file already used
for §5's `[newgrf]` verification): `[ai_players]` holds one INI item per
company slot, in file order — `AILoadConfig` walks `group->items` in
sequence, calling `AIConfig::Change(item.name)` for company slot 0, then
1, then 2, and so on. The item's **key** is the AI's registered short
name (found the same way as a Game Script's — §5/`resolve_ai_name`,
matching against `openttd -h`'s "List of AIs:" listing), the **value** is
its settings string (empty = author defaults). Slot 0 is conventionally
the human player in a single-player game, so the installer writes
`none =` first (explicitly clearing/skipping that slot) then the AI's
name for slot 1.

Pinning an AI to a slot has no visible effect unless
`difficulty.max_no_competitors` (default 0 — verified against
`src/table/settings/difficulty_settings.ini`) allows at least that many
AI companies to actually spawn — `--with-ai`/`-WithAI` therefore also
sets `max_no_competitors = 1` alongside the `[ai_players]` block, both
within the installer's own owned/marked blocks (§ "Config ownership" in
`docs/ARCHITECTURE.md`).

**Scope note:** this was not independently live-download-tested to the
same depth as the core NewGRF/GameScript stack (§3's live validation) —
the download/select/resolve mechanism is identical and already proven
correct for other `ai`-type-shaped entries in the content catalog, but a
full in-game confirmation that RailwAI actually appears as a playable
opponent was not performed in this session. Treat as implemented and
architecturally consistent, not exhaustively play-tested.
