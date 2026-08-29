#!/usr/bin/env bash
# Timestamped config backups. See docs/ARCHITECTURE.md "Backup strategy".
set -euo pipefail

# backup_config <config_file> <backup_root> <profile_name> <openttd_version> <blueprint_version>
# Creates <backup_root>/<UTC timestamp>/openttd.cfg + metadata.json.
# Prints the created backup directory path on stdout.
backup_config() {
	local config_file="$1" backup_root="$2" profile_name="$3" openttd_version="$4" blueprint_version="$5"
	local stamp dest

	stamp="$(date -u +%Y-%m-%d_%H%M%S)"
	dest="${backup_root}/${stamp}"
	mkdir -p "$dest"
	cp -p "$config_file" "$dest/openttd.cfg"

	cat >"$dest/metadata.json" <<-EOF
	{
	  "date_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
	  "openttd_version": "${openttd_version}",
	  "source_path": "${config_file}",
	  "profile": "${profile_name}",
	  "blueprint_version": "${blueprint_version}"
	}
	EOF

	echo "$dest"
}

# latest_backup <backup_root> — print the path of the most recent backup dir, or nothing.
latest_backup() {
	local backup_root="$1"
	[[ -d "$backup_root" ]] || return 0
	find "$backup_root" -mindepth 1 -maxdepth 1 -type d -name '20*' | sort | tail -n1
}
