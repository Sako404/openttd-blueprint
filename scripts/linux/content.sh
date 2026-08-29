#!/usr/bin/env bash
# Content acquisition and [newgrf]/[game_scripts] block generation for Linux.
# See docs/RESEARCH.md §3/§5 and docs/ARCHITECTURE.md "Download mechanism"
# for why this drives OpenTTD's own console `content` commands rather than
# talking to BaNaNaS directly, and why NewGRF filenames/GameScript names are
# resolved from OpenTTD's own output instead of guessed.
set -euo pipefail

# _byteswap_hex <8-hex-char-id> — print the same 4 bytes in reverse order.
# BaNaNaS's own package-page URLs and the downloaded tar's filename always
# use one canonical byte order for a content ID, but the console's own
# `content state` listing was observed, live, to report at least Game
# Script and AI content in the *opposite* byte order for the same package
# (NewGRF entries matched directly, un-swapped, in every case observed).
# Rather than assume which types get swapped, callers try both forms when
# matching a content_state row. See docs/RESEARCH.md §3.
_byteswap_hex() {
	local h="$1"
	echo "${h:6:2}${h:4:2}${h:2:2}${h:0:2}"
}

# content_tar_path <data_dir> <type> <content_id> — print the path of an
# already-downloaded content tar for this ID, if present (glob match on the
# content_id prefix, since the slug/version suffix isn't predictable).
content_tar_path() {
	local data_dir="$1" type="$2" content_id="$3" match
	# `|| true`: find exits non-zero if the target directory doesn't exist
	# yet (e.g. content_download/<type>/ before anything of that type has
	# ever been downloaded) — under set -e that would otherwise be treated
	# as fatal instead of the normal "nothing found yet" this function is
	# meant to report. See the near-identical, confirmed-live-observed bug
	# this same lesson came from further down in this file (numeric_id).
	match="$(find "${data_dir}/content_download/${type}" -maxdepth 1 -type f -iname "${content_id}-*.tar" 2>/dev/null | head -n1 || true)"
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
	local log_file="$1" manifest="$2" data_dir="$3" with_ai="${4:-0}"
	# The console/network-content subsystem isn't immediately ready when the
	# dedicated server starts — a command sent too early is silently dropped
	# ("Command 'content' not found."), verified empirically. A short fixed
	# delay before the first command avoids the race.
	sleep 2
	echo "content update"
	# `content update` is a silent background fetch of the server's full
	# catalog (observed: tens of thousands of items) — there is no
	# documented completion signal for it specifically, so this waits a
	# fixed, empirically-generous duration rather than idle-polling (the
	# dedicated server's own background activity means the log is never
	# reliably "idle" anyway). Verified: `content state` issued once this
	# has had ~40s does return complete, correct results.
	sleep 60

	# `content state <filter>` narrows the listing to just matching names
	# instead of dumping the entire catalog — verified empirically to be
	# both far faster (seconds, not minutes) and more reliable: sending an
	# *unfiltered* `content state` for a 9-item manifest was observed
	# (during development) to sometimes leave the dedicated server too busy
	# digesting its own multi-thousand-line output to reliably process the
	# `content select`/`content download` commands that followed. One
	# filtered call per required item avoids that entirely.
	#
	# Phase 1: resolve every item's numeric ID first, *without* selecting
	# anything yet, and collect them. Phase 2 below then issues every
	# `content select` back-to-back, immediately before `content download`.
	# This two-phase split exists because interleaving `content select`
	# with further `content state` calls was observed, on a real live run,
	# to silently lose most selections — only 4 of 9 correctly-resolved
	# items actually got downloaded, with no error at all. The content
	# server's internal numeric IDs are apparently not guaranteed stable
	# across separate `content state` calls in the same session; issuing
	# every select immediately before download (no further state queries
	# in between) avoids relying on that stability. See docs/RESEARCH.md §3.
	local content_id type item_name numeric_id start_line
	local selected_ids=()
	while IFS=$'\t' read -r content_id type item_name; do
		[[ -n "$content_id" ]] || continue
		if content_present "$data_dir" "$type" "$content_id"; then
			continue
		fi
		start_line="$(wc -l <"$log_file" 2>/dev/null || echo 0)"
		# The console splits an unquoted argument on whitespace — an
		# unquoted multi-word filter (e.g. "Road Hog (Buses, Trucks,
		# Trams)") was observed to effectively match on just one generic
		# word ("Road"), returning dozens of unrelated packages instead of
		# one. Quoting the whole filter gives an exact-substring match
		# instead (verified empirically: `content state "Road Hog..."`
		# returns exactly one row). See docs/RESEARCH.md §3.
		echo "content state \"${item_name}\""
		# Round-trip time for a single filtered query varies a lot in
		# practice (a few seconds to tens of seconds, observed empirically)
		# — idle-detection per item, rather than a fixed sleep, adapts to
		# that instead of either wasting time on fast items or truncating
		# slow ones.
		_wait_log_idle "$log_file" 10 40
		# First matching row for this content_id (tried in both byte
		# orders — see _byteswap_hex above) among the lines this filtered
		# call actually produced (see docs/RESEARCH.md §3 on why "first
		# match" — the same content_id can appear more than once,
		# representing different historical versions).
		# `|| true` is load-bearing: under `set -euo pipefail`, grep finding
		# no match (a normal, expected outcome the code below already
		# handles) makes the whole pipeline "fail", which would otherwise
		# kill this entire subshell via `set -e` before it reaches that
		# check — silently aborting mid-manifest with no error visible.
		# Diagnosed via a genuinely stuck live run: the subshell had become
		# a zombie after resolving only 2 of 9 items, with no error output
		# anywhere, because set -e's exit is exactly that quiet.
		numeric_id="$(tail -n "+$((start_line + 1))" "$log_file" | grep -iE ", (${content_id}|$(_byteswap_hex "$content_id"))," | head -n1 | awk -F', ' '{print $1}' || true)"
		if [[ -n "$numeric_id" ]]; then
			selected_ids+=("$numeric_id")
		else
			echo "# WARNING: ${content_id} not found via 'content state ${item_name}' — server may not have it" >&2
		fi
	done < <(jq -r --argjson with_ai "$with_ai" \
		'.content[] | select((.required == true or (.type == "ai" and $with_ai == 1)) and .source == "bananas") | [.content_id, (if .type == "game_script" then "game" else .type end), .name] | @tsv' \
		"$manifest")

	# Phase 2: select everything, then download. A short pause after each
	# select (no intervening `content state` query) was necessary: sending
	# all selects with zero delay between them was *also* observed, on a
	# real live run, to lose every single one (0/9 downloaded despite every
	# ID having resolved correctly) — the console apparently needs a brief
	# moment to register each selection even without a competing query in
	# between. See docs/RESEARCH.md §3.
	local id
	for id in "${selected_ids[@]+"${selected_ids[@]}"}"; do
		echo "content select ${id}"
		sleep 2
	done
	sleep 3

	echo "content download"
	_wait_log_idle "$log_file" 5 180
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
	local exe="$1" manifest="$2" log_file="$3" data_dir="$4" with_ai="${5:-0}"
	local id type name missing=0 pid waited=0

	: >"$log_file"
	# shellcheck disable=SC2086 # $exe may be "flatpak run <id>"
	# shellcheck disable=SC2094 # deliberate: _generate_content_commands polls
	# $log_file via its own fresh `wc`/`tail`/`grep` opens on the path, not a
	# shared fd with this append redirect — safe, and is how it paces itself
	# against the openttd process's real-time output (see that function's
	# own header comment and docs/RESEARCH.md §3).
	$exe -D -x < <(_generate_content_commands "$log_file" "$manifest" "$data_dir" "$with_ai") >>"$log_file" 2>&1 &
	pid=$!

	# _generate_content_commands paces itself and ends with "quit", but a
	# dedicated server (-D) is designed to run indefinitely and does not
	# reliably exit on "quit" (verified empirically — see
	# docs/RESEARCH.md §3). Poll for natural exit, then force-terminate
	# rather than risk hanging forever.
	while kill -0 "$pid" 2>/dev/null && [[ "$waited" -lt 700 ]]; do
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
	done < <(jq -r --argjson with_ai "$with_ai" \
		'.content[] | select((.required == true or (.type == "ai" and $with_ai == 1)) and .source == "bananas") | [.content_id, (if .type == "game_script" then "game" else .type end), .name] | @tsv' \
		"$manifest")

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

# _resolve_registered_name <openttd_exe> <section_heading> <display_name>
# Shared by resolve_gamescript_name/resolve_ai_name: prints the registered
# short name OpenTTD uses for downloaded content, found by fuzzy-matching a
# manifest item's display name (spaces stripped) against the named section
# of `openttd -h`'s output (e.g. "List of Game Scripts:", "List of AIs:").
# Returns empty if not found (e.g. content wasn't actually downloaded).
_resolve_registered_name() {
	local exe="$1" heading="$2" display_name="$3" needle line token token_bare
	needle="$(printf '%s' "$display_name" | tr -d ' ')"
	while IFS= read -r line; do
		# `\(` — a literal, escaped paren in the glob pattern. Unescaped,
		# bash treats "(v*" as the start of an extglob group and raises
		# "bad pattern" instead of matching literally, at least when
		# invoked in some shells/contexts — confirmed via a real crash
		# (build_gamescript_line failing) that only appeared once a live
		# run finally got far enough to reach this code path for the
		# first time. See docs/RESEARCH.md §3.
		token="${line%% \(v*}"
		# Compare space-insensitively: `needle` above has spaces already
		# stripped, but `token` (straight from openttd -h's own output,
		# e.g. "Renewed Village Growth") does not — comparing them
		# directly would never match a multi-word name. `token` itself
		# (with spaces) is what's echoed and used as the actual
		# [game_scripts]/[ai_players] cfg key, since that's the format
		# openttd -h itself displays and (per AILoadConfig/AISaveConfig
		# in OpenTTD's own source) is what config->GetName() round-trips.
		token_bare="$(printf '%s' "$token" | tr -d ' ')"
		if [[ "$token_bare" == "$needle"* || "$needle" == "$token_bare"* ]]; then
			echo "$token"
			return 0
		fi
	done < <($exe -h 2>&1 | awk -v h="$heading" '$0==h{f=1;next} /^List of /{f=0} f && NF')
	return 1
}

# resolve_gamescript_name <openttd_exe> <manifest_item_name>
resolve_gamescript_name() {
	_resolve_registered_name "$1" "List of Game Scripts:" "$2"
}

# resolve_ai_name <openttd_exe> <manifest_item_name>
resolve_ai_name() {
	_resolve_registered_name "$1" "List of AIs:" "$2"
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

# build_ai_players_lines <openttd_exe> <manifest_file> — print the
# "[ai_players]" lines that pin the manifest's optional AI opponent to a
# company slot, or nothing if no `ai`-type item is in the manifest. Per
# OpenTTD's own AILoadConfig (see docs/RESEARCH.md), [ai_players] holds one
# entry per company slot in order; slot 0 is left "none" (the human
# player's usual slot in a single-player new game) and the AI is pinned to
# slot 1. Only called when the user opted in (--with-ai / -WithAI) — this
# is deliberately never installed by default (brief: AI support is
# opt-in).
build_ai_players_lines() {
	local exe="$1" manifest="$2" display_name ai_name
	display_name="$(jq -r '.content[] | select(.type == "ai" and .source == "bananas") | .name' "$manifest" | head -n1)"
	[[ -n "$display_name" ]] || return 0
	ai_name="$(resolve_ai_name "$exe" "$display_name")" || {
		echo "build_ai_players_lines: could not resolve registered name for '${display_name}'" >&2
		return 1
	}
	printf 'none =\n%s =\n' "$ai_name"
}
