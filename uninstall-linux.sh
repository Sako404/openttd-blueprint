#!/usr/bin/env bash
# OpenTTD Blueprint — Linux uninstaller.
#
# This does NOT uninstall OpenTTD, and does NOT delete downloaded NewGRF/
# Game Script content (it may be shared with saves or content you added
# yourself — see docs/ARCHITECTURE.md "Additive content"). Its only job is
# restoring openttd.cfg to how it was before OpenTTD Blueprint touched it.
#
# Usage:
#   ./uninstall-linux.sh [--list] [--restore DIR] [--profile NAME]
#
#   (no args)        restore the most recent backup for the profile's config
#   --list           list available backups, newest first, then exit
#   --restore DIR    restore a specific backup directory instead of latest
set -euo pipefail

BP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/backup.sh
source "${BP_ROOT}/scripts/common/backup.sh"
# shellcheck source=scripts/linux/detect.sh
source "${BP_ROOT}/scripts/linux/detect.sh"

PROFILE="logistics"
ACTION="restore-latest"
RESTORE_DIR=""

for arg in "$@"; do
	case "$arg" in
	--list) ACTION="list" ;;
	--restore=*)
		ACTION="restore-specific"
		RESTORE_DIR="${arg#--restore=}"
		;;
	--profile=*) PROFILE="${arg#--profile=}" ;;
	-h | --help)
		sed -n '2,13p' "${BASH_SOURCE[0]}"
		exit 0
		;;
	*)
		echo "ERROR: unrecognised argument: $arg (see --help)" >&2
		exit 2
		;;
	esac
done

DETECTED_JSON="$(detect_all)"
CONFIG_DIR="$(echo "$DETECTED_JSON" | jq -r '.config_dir')"
CONFIG_FILE="$(echo "$DETECTED_JSON" | jq -r '.config_file')"
BACKUP_ROOT="${XDG_STATE_HOME:-${HOME}/.local/state}/openttd-blueprint/backups"
STATE_FILE="${CONFIG_DIR}/blueprint-state.json"

if [[ "$ACTION" == "list" ]]; then
	echo "Backups under ${BACKUP_ROOT}:"
	found=0
	while IFS= read -r dir; do
		[[ -n "$dir" ]] || continue
		found=1
		profile="$(jq -r '.profile // "unknown"' "${dir}/metadata.json" 2>/dev/null || echo unknown)"
		date="$(jq -r '.date_utc // "unknown"' "${dir}/metadata.json" 2>/dev/null || echo unknown)"
		echo "  ${dir}  (profile: ${profile}, date: ${date})"
	done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)
	[[ "$found" -eq 1 ]] || echo "  (none found)"
	exit 0
fi

if [[ "$ACTION" == "restore-specific" ]]; then
	TARGET_DIR="$RESTORE_DIR"
else
	TARGET_DIR="$(latest_backup "$BACKUP_ROOT")"
fi

if [[ -z "$TARGET_DIR" || ! -d "$TARGET_DIR" ]]; then
	echo "ERROR: no backup found to restore (looked under ${BACKUP_ROOT})." >&2
	echo "       Run with --list to see available backups." >&2
	exit 1
fi

if [[ ! -f "${TARGET_DIR}/openttd.cfg" ]]; then
	echo "ERROR: ${TARGET_DIR} does not contain an openttd.cfg backup." >&2
	exit 1
fi

echo "Restoring ${CONFIG_FILE} from ${TARGET_DIR}/openttd.cfg"
cp -p "${TARGET_DIR}/openttd.cfg" "$CONFIG_FILE"

if [[ -f "$STATE_FILE" ]]; then
	rm -f "$STATE_FILE"
	echo "Removed ${STATE_FILE} (profile '${PROFILE}' is no longer marked installed)."
fi

echo "Restore complete. Downloaded content under the OpenTTD data directory was left untouched."
