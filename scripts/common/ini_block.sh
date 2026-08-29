#!/usr/bin/env bash
# Idempotent marked-block patching for OpenTTD's INI-style openttd.cfg.
#
# Every value OpenTTD Blueprint writes lives between a pair of marker
# comments inside the target [section]. Re-running a patch with the same
# inputs reproduces byte-identical output; re-running with different block
# content replaces only the marked lines. Everything outside the markers is
# passed through untouched. See docs/ARCHITECTURE.md "Config ownership".
set -euo pipefail

# ini_patch_block <file> <section> <marker_id> <block_file>
#
#   file       path to the INI file to patch (e.g. openttd.cfg)
#   section    section name without brackets, e.g. "linkgraph"
#   marker_id  unique text identifying this block, e.g. "profile: logistics, section: linkgraph"
#   block_file file containing the raw lines to inject (no markers, no section header)
#
# If [section] does not exist in the file at all, this is a no-op (OpenTTD
# always writes every known section to openttd.cfg, so a missing section
# means something unexpected about the target file — callers should treat
# that as a detection failure, not silently create it).
ini_patch_block() {
	local file="$1" section="$2" marker_id="$3" block_file="$4"
	local begin="### BEGIN OPENTTD BLUEPRINT (${marker_id}) ###"
	local end="### END OPENTTD BLUEPRINT (${marker_id}) ###"
	local tmp

	if ! grep -qxF "[${section}]" "$file"; then
		echo "ini_patch_block: section [${section}] not found in ${file}" >&2
		return 1
	fi

	tmp="$(mktemp "${file}.XXXXXX")"
	trap 'rm -f "$tmp"' RETURN

	awk -v section="[${section}]" -v begin="$begin" -v end="$end" -v blockfile="$block_file" '
		function emit_block(   line) {
			print begin
			while ((getline line < blockfile) > 0) print line
			close(blockfile)
			print end
		}
		{
			is_header = ($0 ~ /^\[[^]]*\]$/)
		}
		is_header && $0 == section {
			in_section = 1
			print
			next
		}
		is_header && in_section && $0 != section {
			if (!emitted) { emit_block(); emitted = 1 }
			in_section = 0
			print
			next
		}
		in_section && $0 == begin {
			in_block = 1
			emit_block()
			emitted = 1
			next
		}
		in_section && in_block && $0 == end {
			in_block = 0
			next
		}
		in_block { next }
		{ print }
		END {
			if (in_section && !emitted) emit_block()
		}
	' "$file" >"$tmp"

	mv "$tmp" "$file"
	trap - RETURN
}

# ini_extract_block <file> <marker_id> — print the current content of a
# marked block (without markers), or nothing if absent. Used by --verify
# and by the idempotency no-op check.
ini_extract_block() {
	local file="$1" marker_id="$2"
	local begin="### BEGIN OPENTTD BLUEPRINT (${marker_id}) ###"
	local end="### END OPENTTD BLUEPRINT (${marker_id}) ###"
	awk -v begin="$begin" -v end="$end" '
		$0 == begin { inb = 1; next }
		$0 == end { inb = 0; next }
		inb { print }
	' "$file"
}

# ini_split_sections <source_block_file> <out_dir>
# Splits a file containing one or more "[section]\nkey = value\n..." groups
# into <out_dir>/<section>.body files (one per section, body only). Blank
# lines and comment lines starting with a section header are preserved
# as written; a source file with no section headers is an error.
ini_split_sections() {
	local source="$1" out_dir="$2"
	mkdir -p "$out_dir"
	awk -v out_dir="$out_dir" '
		/^\[[^]]*\]$/ {
			sect = substr($0, 2, length($0) - 2)
			outfile = out_dir "/" sect ".body"
			close(outfile)
			next
		}
		sect != "" { print > (out_dir "/" sect ".body") }
	' "$source"
}
