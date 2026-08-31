#!/usr/bin/env bash
# OpenTTD Blueprint — Linux installer.
#
# Usage:
#   ./install-linux.sh [--dry-run] [--verify] [--with-ai] [--profile NAME] [--help]
#
# --with-ai pins one optional AI opponent (see profiles/<name>/content-manifest.json,
# type "ai") to a company slot. Off by default — see docs/CONFIGURATION.md.
#
# See docs/ARCHITECTURE.md for the full design (config ownership,
# transactional install order, idempotency) and docs/LINUX.md for
# platform-specific notes.
set -euo pipefail

BP_VERSION="0.2.0"
BP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/common/manifest.sh
source "${BP_ROOT}/scripts/common/manifest.sh"
# shellcheck source=scripts/common/ini_block.sh
source "${BP_ROOT}/scripts/common/ini_block.sh"
# shellcheck source=scripts/common/backup.sh
source "${BP_ROOT}/scripts/common/backup.sh"
# shellcheck source=scripts/common/state.sh
source "${BP_ROOT}/scripts/common/state.sh"
# shellcheck source=scripts/linux/detect.sh
source "${BP_ROOT}/scripts/linux/detect.sh"
# shellcheck source=scripts/linux/content.sh
source "${BP_ROOT}/scripts/linux/content.sh"

PROFILE="logistics"
MODE="install"
WITH_AI=0

for arg in "$@"; do
	case "$arg" in
	--dry-run) MODE="dry-run" ;;
	--verify) MODE="verify" ;;
	--with-ai) WITH_AI=1 ;;
	--profile=*) PROFILE="${arg#--profile=}" ;;
	--profile)
		echo "ERROR: --profile requires a value, e.g. --profile=logistics" >&2
		exit 2
		;;
	-h | --help)
		sed -n '2,12p' "${BASH_SOURCE[0]}"
		exit 0
		;;
	*)
		echo "ERROR: unrecognised argument: $arg (see --help)" >&2
		exit 2
		;;
	esac
done

PROFILE_DIR="${BP_ROOT}/profiles/${PROFILE}"
MANIFEST_FILE="${PROFILE_DIR}/content-manifest.json"
PROFILE_FILE="${PROFILE_DIR}/profile.json"
CFG_BLOCK_FILE="${PROFILE_DIR}/openttd.cfg.block"

if [[ ! -d "$PROFILE_DIR" ]]; then
	echo "ERROR: unknown profile '${PROFILE}' (no such directory: ${PROFILE_DIR})" >&2
	exit 1
fi

for tool in jq awk tar find mktemp; do
	command -v "$tool" >/dev/null 2>&1 || {
		echo "ERROR: required tool '${tool}' not found on PATH." >&2
		exit 1
	}
done

echo "OpenTTD Blueprint v${BP_VERSION}"
echo "Profile: ${PROFILE}"
echo

validate_manifest "$MANIFEST_FILE"
validate_profile "$PROFILE_FILE"

DETECTED_JSON="$(detect_all)"
EXE="$(echo "$DETECTED_JSON" | jq -r '.executable // empty')"
VERSION="$(echo "$DETECTED_JSON" | jq -r '.version // empty')"
CONFIG_DIR="$(echo "$DETECTED_JSON" | jq -r '.config_dir')"
CONFIG_FILE="$(echo "$DETECTED_JSON" | jq -r '.config_file')"
CONFIG_EXISTS="$(echo "$DETECTED_JSON" | jq -r '.config_exists')"
DATA_DIR="$(echo "$DETECTED_JSON" | jq -r '.data_dir')"

echo "Detected:"
echo "  OpenTTD executable : ${EXE:-not found}"
echo "  OpenTTD version    : ${VERSION:-unknown}"
echo "  Config file        : ${CONFIG_FILE} $( [[ "$CONFIG_EXISTS" == "true" ]] && echo "(exists)" || echo "(will be created)" )"
echo "  Data directory      : ${DATA_DIR}"
echo

if [[ -z "$EXE" ]]; then
	echo "ERROR: OpenTTD was not found (checked Steam libraries, Flatpak, PATH)." >&2
	echo "       See docs/TROUBLESHOOTING.md." >&2
	exit 1
fi

MIN_VERSION="$(jq -r '.openttd_min_version' "$PROFILE_FILE")"
if [[ -n "$VERSION" ]] && ! printf '%s\n%s\n' "$MIN_VERSION" "$VERSION" | sort -C -V 2>/dev/null; then
	echo "ERROR: OpenTTD was found, but version ${VERSION} is too old for the ${PROFILE} profile." >&2
	echo "       Required: OpenTTD >= ${MIN_VERSION}" >&2
	echo "       Detected: ${VERSION}" >&2
	exit 1
fi

BACKUP_ROOT="${XDG_STATE_HOME:-${HOME}/.local/state}/openttd-blueprint/backups"
STATE_FILE="${CONFIG_DIR}/blueprint-state.json"

# ensure_config_skeleton — if openttd.cfg genuinely doesn't exist yet (a
# never-launched OpenTTD), write the minimal set of empty sections this
# installer needs to patch. OpenTTD fills in every other section/key with
# its own defaults the first time it actually runs; this never removes
# anything because there's nothing there yet.
ensure_config_skeleton() {
	mkdir -p "$CONFIG_DIR"
	if [[ ! -f "$CONFIG_FILE" ]]; then
		printf '[difficulty]\n\n[economy]\n\n[vehicle]\n\n[linkgraph]\n\n[game_creation]\n\n[newgrf]\n\n[game_scripts]\n\n[ai_players]\n' >"$CONFIG_FILE"
	fi
	for section in difficulty economy vehicle linkgraph game_creation newgrf game_scripts ai_players; do
		grep -qxF "[${section}]" "$CONFIG_FILE" || printf '\n[%s]\n' "$section" >>"$CONFIG_FILE"
	done
}

# compute_patched_config <src_config> <out_config> — apply every profile
# section block plus the (already-resolved) [newgrf]/[game_scripts] blocks
# to a copy of the config, without touching the real file. Used both to
# decide whether anything would actually change (idempotency / dry-run) and
# as the real apply step.
compute_patched_config() {
	local src="$1" out="$2" split_dir section
	cp -p "$src" "$out"

	split_dir="$(mktemp -d)"
	ini_split_sections "$CFG_BLOCK_FILE" "$split_dir"
	for section in difficulty economy vehicle linkgraph game_creation; do
		[[ -f "${split_dir}/${section}.body" ]] || continue
		if [[ "$section" == "difficulty" && "$WITH_AI" -eq 1 ]]; then
			# --with-ai needs at least one competitor slot enabled, or the
			# [ai_players] pin below has no effect (max_no_competitors=0
			# means no AI companies get created regardless of what's
			# pinned to a slot — verified against OpenTTD's own settings
			# table, docs/RESEARCH.md §9).
			printf '%s\n' "max_no_competitors = 1" >>"${split_dir}/${section}.body"
		fi
		ini_patch_block "$out" "$section" "profile: ${PROFILE}, section: ${section}" "${split_dir}/${section}.body"
	done
	rm -rf "$split_dir"

	local newgrf_lines gs_line
	newgrf_lines="$(mktemp)"
	build_newgrf_lines "$DATA_DIR" "$MANIFEST_FILE" >"$newgrf_lines"
	ini_patch_block "$out" "newgrf" "profile: ${PROFILE}, section: newgrf" "$newgrf_lines"
	rm -f "$newgrf_lines"

	gs_line="$(mktemp)"
	build_gamescript_line "$EXE" "$MANIFEST_FILE" >"$gs_line"
	if [[ -s "$gs_line" ]]; then
		ini_patch_block "$out" "game_scripts" "profile: ${PROFILE}, section: game_scripts" "$gs_line"
	fi
	rm -f "$gs_line"

	if [[ "$WITH_AI" -eq 1 ]]; then
		local ai_lines
		ai_lines="$(mktemp)"
		build_ai_players_lines "$EXE" "$MANIFEST_FILE" >"$ai_lines"
		if [[ -s "$ai_lines" ]]; then
			ini_patch_block "$out" "ai_players" "profile: ${PROFILE}, section: ai_players" "$ai_lines"
		fi
		rm -f "$ai_lines"
	fi
}

REQUIRED_ITEMS_MISSING=0
PREEXISTING_NAMES=()
MISSING_NAMES=()
while IFS=$'\t' read -r content_id type name; do
	[[ -n "$content_id" ]] || continue
	ctype="newgrf"; [[ "$type" == "game_script" ]] && ctype="game"
	if content_present "$DATA_DIR" "$ctype" "$content_id"; then
		PREEXISTING_NAMES+=("$name")
	else
		REQUIRED_ITEMS_MISSING=$((REQUIRED_ITEMS_MISSING + 1))
		MISSING_NAMES+=("$name")
		echo "  content missing: ${name}"
	fi
done < <(jq -r --argjson with_ai "$WITH_AI" \
	'.content[] | select((.required == true or (.type == "ai" and $with_ai == 1)) and .source == "bananas") | [.content_id, .type, .name] | @tsv' \
	"$MANIFEST_FILE")

if [[ "$WITH_AI" -eq 1 ]]; then
	echo "  (--with-ai: AI opponent included above if not already present)"
fi

if [[ "$MODE" == "dry-run" ]]; then
	echo "--- DRY RUN: no changes will be made ---"
	echo
	if [[ "$REQUIRED_ITEMS_MISSING" -gt 0 ]]; then
		echo "${REQUIRED_ITEMS_MISSING} required content item(s) would be downloaded (see list above)."
	else
		echo "All required content already present."
	fi
	echo
	if [[ "$CONFIG_EXISTS" == "true" ]]; then
		tmp_check="$(mktemp)"
		# Dry-run can't resolve real NewGRF filenames for content that isn't
		# downloaded yet, so it only shows the gameplay-settings diff here;
		# a content-download run is needed to preview the [newgrf] block itself.
		split_dir="$(mktemp -d)"
		ini_split_sections "$CFG_BLOCK_FILE" "$split_dir"
		cp -p "$CONFIG_FILE" "$tmp_check"
		changed=0
		for section in difficulty economy vehicle linkgraph game_creation; do
			[[ -f "${split_dir}/${section}.body" ]] || continue
			before_hash="$(ini_extract_block "$CONFIG_FILE" "profile: ${PROFILE}, section: ${section}" | md5sum)"
			ini_patch_block "$tmp_check" "$section" "profile: ${PROFILE}, section: ${section}" "${split_dir}/${section}.body"
			after_hash="$(ini_extract_block "$tmp_check" "profile: ${PROFILE}, section: ${section}" | md5sum)"
			if [[ "$before_hash" != "$after_hash" ]]; then
				echo "  [${section}] would be added/updated"
				changed=1
			fi
		done
		[[ "$changed" -eq 0 ]] && echo "  gameplay settings already up to date"
		rm -rf "$split_dir" "$tmp_check"
	else
		echo "  openttd.cfg does not exist yet — would be created with all profile sections."
	fi
	if [[ "$WITH_AI" -eq 1 ]]; then
		echo "  [difficulty] would also set max_no_competitors = 1 (--with-ai)"
		echo "  [ai_players] would pin one AI opponent to a company slot (--with-ai)"
	fi
	echo
	echo "Backup would be created under: ${BACKUP_ROOT}/<timestamp>/ (only if config actually changes)"
	exit 0
fi

if [[ "$MODE" == "verify" ]]; then
	fail=0
	if [[ ! -f "$STATE_FILE" ]]; then
		echo "FAIL: no blueprint-state.json at ${STATE_FILE} — profile not installed." >&2
		exit 1
	fi
	installed_profile="$(read_state_field "$STATE_FILE" '.profile')"
	if [[ "$installed_profile" != "$PROFILE" ]]; then
		echo "FAIL: installed profile is '${installed_profile}', not '${PROFILE}'." >&2
		fail=1
	fi
	while IFS=$'\t' read -r content_id type name; do
		[[ -n "$content_id" ]] || continue
		ctype="newgrf"; [[ "$type" == "game_script" ]] && ctype="game"
		if ! content_present "$DATA_DIR" "$ctype" "$content_id"; then
			echo "FAIL: required content missing: ${name}" >&2
			fail=1
		fi
	done < <(jq -r --argjson with_ai "$WITH_AI" \
		'.content[] | select((.required == true or (.type == "ai" and $with_ai == 1)) and .source == "bananas") | [.content_id, .type, .name] | @tsv' \
		"$MANIFEST_FILE")
	for section in difficulty economy vehicle linkgraph game_creation newgrf; do
		if [[ -z "$(ini_extract_block "$CONFIG_FILE" "profile: ${PROFILE}, section: ${section}")" ]]; then
			echo "FAIL: no OpenTTD Blueprint block found in [${section}] of ${CONFIG_FILE}" >&2
			fail=1
		fi
	done
	if [[ "$WITH_AI" -eq 1 ]] && [[ -z "$(ini_extract_block "$CONFIG_FILE" "profile: ${PROFILE}, section: ai_players")" ]]; then
		echo "FAIL: --with-ai requested but no OpenTTD Blueprint block found in [ai_players] of ${CONFIG_FILE}" >&2
		fail=1
	fi
	if [[ "$fail" -eq 0 ]]; then
		echo "OK: profile '${PROFILE}' is installed and consistent."
		exit 0
	else
		exit 1
	fi
fi

# --- real install from here ---

ensure_config_skeleton

if [[ "$REQUIRED_ITEMS_MISSING" -gt 0 ]]; then
	echo "Downloading ${REQUIRED_ITEMS_MISSING} required content item(s) via OpenTTD's Online Content system..."
	echo "(a first sync of OpenTTD's content catalog can take several minutes — see docs/RESEARCH.md §3)"
	LOG_FILE="$(mktemp)"
	if ! download_required_content "$EXE" "$MANIFEST_FILE" "$LOG_FILE" "$DATA_DIR" "$WITH_AI"; then
		echo "ERROR: content download did not complete. Log:" >&2
		cat "$LOG_FILE" >&2
		exit 1
	fi
	rm -f "$LOG_FILE"
	echo "Content download complete."
else
	echo "All required content already present — skipping download."
fi

PATCHED="$(mktemp)"
compute_patched_config "$CONFIG_FILE" "$PATCHED"

if cmp -s "$CONFIG_FILE" "$PATCHED"; then
	echo "Configuration already up to date — no changes needed."
	BACKUP_DIR=""
else
	BACKUP_DIR="$(backup_config "$CONFIG_FILE" "$BACKUP_ROOT" "$PROFILE" "${VERSION:-unknown}" "$BP_VERSION")"
	echo "Backed up existing config to: ${BACKUP_DIR}"
	mv "$PATCHED" "$CONFIG_FILE"
	echo "Applied ${PROFILE} profile configuration."
fi
[[ -f "$PATCHED" ]] && rm -f "$PATCHED"

PREEXISTING_JSON="$(printf '%s\n' "${PREEXISTING_NAMES[@]:-}" | jq -R . | jq -s 'map(select(length > 0))')"
ADDED_JSON="$(printf '%s\n' "${MISSING_NAMES[@]:-}" | jq -R . | jq -s 'map(select(length > 0))')"
write_state "$STATE_FILE" "$BP_VERSION" "$PROFILE" "$(jq -r '.blueprint_version' "$PROFILE_FILE")" \
	"${BACKUP_DIR:-none}" "$PREEXISTING_JSON" "$ADDED_JSON"
echo "Wrote state: ${STATE_FILE}"

echo
echo "Install complete. Run './install-linux.sh --verify' to confirm."
