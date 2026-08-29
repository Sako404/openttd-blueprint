#!/usr/bin/env bash
# Read-only detection of the local OpenTTD installation on Linux.
# Nothing in this file writes to disk. See docs/LINUX.md for the directory
# layout this assumes, and docs/RESEARCH.md for how it was verified.
set -euo pipefail

# steam_library_paths — print every Steam library root that might contain
# "steamapps/common/OpenTTD", one per line. Always includes the default
# native Steam path; adds any extra libraries listed in libraryfolders.vdf.
steam_library_paths() {
	local candidates=(
		"${HOME}/.local/share/Steam"
		"${HOME}/.steam/steam"
		"${HOME}/.steam/root"
	)
	local vdf lib
	for lib in "${candidates[@]}"; do
		[[ -d "$lib/steamapps" ]] || continue
		printf '%s\n' "$lib"
	done

	for vdf in "${candidates[@]/%//steamapps/libraryfolders.vdf}"; do
		[[ -f "$vdf" ]] || continue
		# Lines look like:   "path"		"/mnt/games/SteamLibrary"
		grep -oP '"path"\s+"\K[^"]+' "$vdf" 2>/dev/null || true
	done
}

# find_openttd_executable — print the first working "openttd" executable
# path found, preferring a Steam install (this project's primary target),
# then Flatpak, then PATH. Empty output means not found.
find_openttd_executable() {
	local lib exe
	while IFS= read -r lib; do
		exe="${lib}/steamapps/common/OpenTTD/openttd"
		if [[ -x "$exe" ]]; then
			echo "$exe"
			return 0
		fi
	done < <(steam_library_paths)

	if command -v flatpak >/dev/null 2>&1 && flatpak info org.openttd.OpenTTD >/dev/null 2>&1; then
		echo "flatpak run org.openttd.OpenTTD"
		return 0
	fi

	if command -v openttd >/dev/null 2>&1; then
		command -v openttd
		return 0
	fi

	return 1
}

# openttd_version <executable-or-command> — print "MAJOR.MINOR[.PATCH]" by
# parsing the first line of `-h` output, e.g. "OpenTTD 15.3" -> "15.3".
# `-h` (not `-v`, which sets the video driver) is the flag that reliably
# exits 0 and prints the version as its first line — verified against the
# locally installed Steam build. Exits non-zero if it can't be determined.
openttd_version() {
	local exe="$1" line
	# shellcheck disable=SC2086 # $exe may be "flatpak run <id>", intentionally word-split
	line="$($exe -h 2>&1 | head -n1)"
	if [[ "$line" =~ ^OpenTTD\ ([0-9][0-9A-Za-z\.\-]*) ]]; then
		echo "${BASH_REMATCH[1]}"
		return 0
	fi
	return 1
}

# openttd_config_dir — print the directory openttd.cfg lives in (may not
# exist yet on a fresh install). Respects XDG_CONFIG_HOME. Flatpak installs
# use a different sandboxed base; detect that first since a Flatpak install
# would otherwise resolve to the same native path without actually being
# read by that OpenTTD.
openttd_config_dir() {
	if command -v flatpak >/dev/null 2>&1 && flatpak info org.openttd.OpenTTD >/dev/null 2>&1; then
		echo "${HOME}/.var/app/org.openttd.OpenTTD/config/openttd"
		return 0
	fi
	echo "${XDG_CONFIG_HOME:-${HOME}/.config}/openttd"
}

# openttd_data_dir — print the directory containing newgrf/ai/game/save/etc.
openttd_data_dir() {
	if command -v flatpak >/dev/null 2>&1 && flatpak info org.openttd.OpenTTD >/dev/null 2>&1; then
		echo "${HOME}/.var/app/org.openttd.OpenTTD/data/openttd"
		return 0
	fi
	echo "${XDG_DATA_HOME:-${HOME}/.local/share}/openttd"
}

# detect_all — print a single JSON object with everything detected, for
# --dry-run reporting and for the installer to consume via jq. Does not
# fail if OpenTTD isn't found; the caller decides whether that's fatal.
detect_all() {
	local exe version config_dir data_dir
	exe="$(find_openttd_executable || true)"
	version=""
	[[ -n "$exe" ]] && version="$(openttd_version "$exe" || true)"
	config_dir="$(openttd_config_dir)"
	data_dir="$(openttd_data_dir)"

	jq -n \
		--arg exe "$exe" \
		--arg version "$version" \
		--arg config_dir "$config_dir" \
		--arg config_file "${config_dir}/openttd.cfg" \
		--arg data_dir "$data_dir" \
		--argjson config_exists "$([[ -f "${config_dir}/openttd.cfg" ]] && echo true || echo false)" \
		'{
			executable: (if $exe == "" then null else $exe end),
			version: (if $version == "" then null else $version end),
			config_dir: $config_dir,
			config_file: $config_file,
			config_exists: $config_exists,
			data_dir: $data_dir
		}'
}
