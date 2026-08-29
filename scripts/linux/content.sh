#!/usr/bin/env bash
# Content acquisition and [newgrf]/[game_scripts] block generation for Linux.
# See docs/RESEARCH.md §3/§5 and docs/ARCHITECTURE.md "Download mechanism"
# for why this drives OpenTTD's own console `content` commands rather than
# talking to BaNaNaS directly, and why NewGRF filenames/GameScript names are
# resolved from OpenTTD's own output instead of guessed.
set -euo pipefail

# content_tar_path <data_dir> <type> <content_id> — print the path of an
# already-downloaded content tar for this ID, if present (glob match on the
# content_id prefix, since the slug/version suffix isn't predictable).
content_tar_path() {
	local data_dir="$1" type="$2" content_id="$3" match
	match="$(find "${data_dir}/content_download/${type}" -maxdepth 1 -type f -iname "${content_id}-*.tar" 2>/dev/null | head -n1)"
	[[ -n "$match" ]] && echo "$match"
}

# content_present <data_dir> <type> <content_id> — exit 0 if already downloaded.
content_present() {
	[[ -n "$(content_tar_path "$1" "$2" "$3")" ]]
}

# _wait_log_idle <log_file> <min_seconds> <max_seconds>
# Polls a growing log file once a second and returns once its size has been
# unchanged for 3 consecutive polls (and at least min_seconds have passed),
# or once max_seconds have elapsed — whichever comes first. There is no
# documented "operation complete" marker for `content update`/`content
# download` reliable enough to grep for (see docs/RESEARCH.md §3), so
# idle-detection on the log OpenTTD is actively writing to is used instead.
_wait_log_idle() {
	local log_file="$1" min_seconds="$2" max_seconds="$3"
	local elapsed=0 last_size=-1 stable=0 size
	while [[ "$elapsed" -lt "$max_seconds" ]]; do
		sleep 1
		elapsed=$((elapsed + 1))
		size="$(wc -c <"$log_file" 2>/dev/null || echo 0)"
		if [[ "$size" == "$last_size" ]]; then
			stable=$((stable + 1))
		else
			stable=0
		fi
		last_size="$size"
		if [[ "$elapsed" -ge "$min_seconds" && "$stable" -ge 3 ]]; then
			return 0
		fi
	done
	return 0
}

# _generate_content_commands <log_file> <manifest_file> <data_dir>
# Emitted as this session's stdin, interleaved with real-time waits so each
# command only fires once the previous one's network round-trip has settled
# (see docs/RESEARCH.md §3 — there is no synchronous request/response
# console API to script against instead). Because this runs in a process
# substitution subshell that shares the same log_file OpenTTD is writing to
# concurrently, it can poll and parse that file mid-stream to decide what
# to send next — no separate FIFO/control channel needed.
_generate_content_commands() {
	local log_file="$1" manifest="$2" data_dir="$3"
	# The console/network-content subsystem isn't immediately ready when the
	# dedicated server starts — a command sent too early is silently dropped
	# ("Command 'content' not found."), verified empirically. A short fixed
	# delay before the first command avoids the race.
	sleep 2
	echo "content update"
	# `content update` triggers a full-catalog fetch from the content
	# server (observed: several thousand items) that takes well over a
	# minute in practice. Give it its own generous, separate wait before
	# issuing `content state` — issuing both back-to-back was observed
	# (empirically, during development) to make the whole exchange take
	# dramatically longer, plausibly because `content state` running while
	# the update fetch is still in flight disrupts it. Idle-detection alone
	# is not fully reliable here (the dedicated server's own game tick can
	# keep the log trickling), so this also has a floor of MinSeconds
	# regardless of apparent idleness.
	_wait_log_idle "$log_file" 15 180
	echo "content state"
	_wait_log_idle "$log_file" 5 60

	local content_id type numeric_id
	while IFS=$'\t' read -r content_id type; do
		[[ -n "$content_id" ]] || continue
		if content_present "$data_dir" "$type" "$content_id"; then
			continue
		fi
		# First matching row for this content_id in the just-printed state
		# table (see docs/RESEARCH.md §3 on why "first match" — the table
		# can list multiple historical versions under the same content_id).
		numeric_id="$(grep -i ", ${content_id}," "$log_file" | head -n1 | awk -F', ' '{print $1}')"
		if [[ -n "$numeric_id" ]]; then
			echo "content select ${numeric_id}"
		else
			echo "# WARNING: ${content_id} not found in content state — server may not have it" >&2
		fi
	done < <(jq -r '.content[] | select(.required == true and .source == "bananas") | [.content_id, (if .type == "game_script" then "game" else .type end)] | @tsv' "$manifest")

	echo "content download"
	_wait_log_idle "$log_file" 5 200
	echo "quit"
}

# download_required_content <openttd_exe> <manifest_file> <log_file> <data_dir>
# Drives a headless dedicated-server session through the console `content`
# command family for every required, not-yet-present bananas-sourced item.
# Returns 0 if every required item is present on disk afterwards, 1 otherwise.
# NOTE: this resolves each package by content_id to *a* currently-listed
# version, not provably the exact version pinned in the manifest — OpenTTD's
# console protocol doesn't expose a documented way to select an exact
# historical version non-interactively. Callers should treat the manifest's
# "version" field as the last-tested version and diff it against what
# actually landed (the downloaded tar's filename) rather than assume an
# exact match; see docs/RESEARCH.md §3 and docs/TROUBLESHOOTING.md.
download_required_content() {
	local exe="$1" manifest="$2" log_file="$3" data_dir="$4"
	local id type name missing=0 pid waited=0

	: >"$log_file"
	# shellcheck disable=SC2086 # $exe may be "flatpak run <id>"
	$exe -D -x < <(_generate_content_commands "$log_file" "$manifest" "$data_dir") >>"$log_file" 2>&1 &
	pid=$!

	# _generate_content_commands paces itself and ends with "quit", but a
	# dedicated server (-D) is designed to run indefinitely and does not
	# reliably exit on "quit" (verified empirically — see
	# docs/RESEARCH.md §3). Poll for natural exit, then force-terminate
	# rather than risk hanging forever.
	while kill -0 "$pid" 2>/dev/null && [[ "$waited" -lt 480 ]]; do
		sleep 1
		waited=$((waited + 1))
	done
	if kill -0 "$pid" 2>/dev/null; then
		kill "$pid" 2>/dev/null || true
		sleep 1
		kill -9 "$pid" 2>/dev/null || true
	fi
	wait "$pid" 2>/dev/null || true

	while IFS=$'\t' read -r id type name; do
		[[ -n "$id" ]] || continue
		if ! content_present "$data_dir" "$type" "$id"; then
			echo "MISSING after download: ${name} (${type} ${id})" >&2
			missing=1
		fi
	done < <(jq -r '.content[] | select(.required == true and .source == "bananas") | [.content_id, (if .type == "game_script" then "game" else .type end), .name] | @tsv' "$manifest")

	return "$missing"
}

# resolve_newgrf_filename <data_dir> <content_id> — print the .grf filename
# found inside the downloaded tar for this content ID (first match).
resolve_newgrf_filename() {
	local data_dir="$1" content_id="$2" tar_path
	tar_path="$(content_tar_path "$data_dir" "newgrf" "$content_id")"
	[[ -n "$tar_path" ]] || return 1
	tar -tf "$tar_path" | grep -i '\.grf$' | head -n1 | xargs -r basename
}

# resolve_gamescript_name <openttd_exe> <manifest_item_name> — print the
# registered short name OpenTTD uses for a downloaded Game Script, found by
# fuzzy-matching manifest item's display name (spaces stripped) against
# `openttd -h`'s "List of Game Scripts:" listing. Returns empty if not found
# (e.g. content wasn't actually downloaded).
resolve_gamescript_name() {
	local exe="$1" display_name="$2" needle line token
	needle="$(printf '%s' "$display_name" | tr -d ' ')"
	# shellcheck disable=SC2086
	while IFS= read -r line; do
		token="${line%% (v*}"
		if [[ "$token" == "$needle"* || "$needle" == "$token"* ]]; then
			echo "$token"
			return 0
		fi
	done < <($exe -h 2>&1 | awk '/^List of Game Scripts:/{f=1;next} /^List of /{f=0} f && NF')
	return 1
}

# build_newgrf_lines <data_dir> <manifest_file> — print "[newgrf]"-ready
# "filename = params" lines, one per required newgrf item, in manifest order.
build_newgrf_lines() {
	local data_dir="$1" manifest="$2" content_id filename params
	while IFS=$'\t' read -r content_id params; do
		[[ -n "$content_id" ]] || continue
		filename="$(resolve_newgrf_filename "$data_dir" "$content_id")" || {
			echo "build_newgrf_lines: could not resolve filename for content ${content_id}" >&2
			return 1
		}
		if [[ -n "$params" ]]; then
			printf '%s = %s\n' "$filename" "$params"
		else
			printf '%s =\n' "$filename"
		fi
	done < <(jq -r '[.content[] | select(.required == true and .type == "newgrf" and .source == "bananas")] | sort_by(.order) | .[] | [.content_id, .parameters] | @tsv' "$manifest")
}

# build_gamescript_line <openttd_exe> <manifest_file> — print the single
# "[game_scripts]" line for the required game_script item, or nothing if
# no game_script is in the manifest.
build_gamescript_line() {
	local exe="$1" manifest="$2" display_name script_name
	display_name="$(jq -r '.content[] | select(.required == true and .type == "game_script" and .source == "bananas") | .name' "$manifest" | head -n1)"
	[[ -n "$display_name" ]] || return 0
	script_name="$(resolve_gamescript_name "$exe" "$display_name")" || {
		echo "build_gamescript_line: could not resolve registered name for '${display_name}'" >&2
		return 1
	}
	printf '%s =\n' "$script_name"
}
