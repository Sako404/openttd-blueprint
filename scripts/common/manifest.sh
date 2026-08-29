#!/usr/bin/env bash
# Load and lightly validate profile.json / content-manifest.json.
# Full JSON-Schema validation is intentionally not implemented (it would
# need a schema validator dependency); these checks cover the required
# fields our schemas declare, which is what the installer actually depends
# on. See profiles/schema/*.schema.json for the authoritative shape.
set -euo pipefail

# validate_manifest <content-manifest.json path>
# Exits non-zero with a message on stderr on the first problem found.
validate_manifest() {
	local file="$1"

	jq -e . "$file" >/dev/null 2>&1 || {
		echo "validate_manifest: not valid JSON: ${file}" >&2
		return 1
	}

	local schema_version profile
	schema_version="$(jq -r '.schema_version // empty' "$file")"
	profile="$(jq -r '.profile // empty' "$file")"
	[[ "$schema_version" == "1" ]] || { echo "validate_manifest: schema_version must be 1" >&2; return 1; }
	[[ -n "$profile" ]] || { echo "validate_manifest: missing profile" >&2; return 1; }

	local bad
	bad="$(jq -r '
		.content[]?
		| select(
			(.name == null) or
			(.type == null or (.type != "newgrf" and .type != "game_script" and .type != "ai")) or
			(.required == null) or
			(.source == null or (.source != "bananas" and .source != "none")) or
			(.version_policy != "pinned") or
			(.purpose == null) or
			(.license == null) or
			(.source == "bananas" and (.content_id == null or .version == null)) or
			(.source == "none" and .omitted_reason == null)
		)
		| .name // "<unnamed>"
	' "$file")"

	if [[ -n "$bad" ]]; then
		echo "validate_manifest: invalid content entries in ${file}:" >&2
		echo "$bad" >&2
		return 1
	fi
}

# validate_profile <profile.json path>
validate_profile() {
	local file="$1"

	jq -e . "$file" >/dev/null 2>&1 || {
		echo "validate_profile: not valid JSON: ${file}" >&2
		return 1
	}

	local missing
	missing="$(jq -r '
		[
			(if .schema_version == 1 then null else "schema_version" end),
			(if (.name // "") != "" then null else "name" end),
			(if (.display_name // "") != "" then null else "display_name" end),
			(if (.blueprint_version // "") != "" then null else "blueprint_version" end),
			(if (.openttd_min_version // "") != "" then null else "openttd_min_version" end),
			(if .gameplay.starting_year != null then null else "gameplay.starting_year" end),
			(if .gameplay.map_size.x != null and .gameplay.map_size.y != null then null else "gameplay.map_size" end)
		] | map(select(. != null)) | join(", ")
	' "$file")"

	if [[ -n "$missing" ]]; then
		echo "validate_profile: missing required field(s) in ${file}: ${missing}" >&2
		return 1
	fi
}

# manifest_required_content <content-manifest.json path> — list required item names, one per line.
manifest_required_content() {
	jq -r '.content[] | select(.required == true and .source == "bananas") | .name' "$1"
}
