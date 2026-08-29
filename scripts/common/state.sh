#!/usr/bin/env bash
# Read/write blueprint-state.json — the record of what OpenTTD Blueprint
# itself changed, used by --verify and uninstall to act precisely instead
# of guessing. See docs/ARCHITECTURE.md "Ownership metadata".
set -euo pipefail

# write_state <state_file> <blueprint_version> <profile_name> <manifest_version> \
#             <backup_dir> <preexisting_content_json_array> <added_content_json_array>
write_state() {
	local state_file="$1" blueprint_version="$2" profile_name="$3" manifest_version="$4"
	local backup_dir="$5" preexisting_json="$6" added_json="$7"

	jq -n \
		--arg blueprint_version "$blueprint_version" \
		--arg profile "$profile_name" \
		--arg manifest_version "$manifest_version" \
		--arg installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		--arg backup_dir "$backup_dir" \
		--argjson preexisting_content "$preexisting_json" \
		--argjson added_content "$added_json" \
		'{
			blueprint_version: $blueprint_version,
			profile: $profile,
			manifest_version: $manifest_version,
			installed_at: $installed_at,
			config_backup: $backup_dir,
			content_detected_before_install: $preexisting_content,
			content_added_by_install: $added_content
		}' >"$state_file"
}

# read_state_field <state_file> <jq_filter>
read_state_field() {
	local state_file="$1" filter="$2"
	[[ -f "$state_file" ]] || return 1
	jq -r "$filter" "$state_file"
}
