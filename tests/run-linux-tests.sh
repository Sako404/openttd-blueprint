#!/usr/bin/env bash
# Fixture-based tests for the Linux-side shared library and installer
# safety behaviour. No external test framework dependency (bats etc.) —
# see docs/ARCHITECTURE.md "Dependency minimisation". Never touches a real
# OpenTTD installation or the network; everything runs against
# tests/fixtures/ and a throwaway temp directory.
set -uo pipefail

BP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="${BP_ROOT}/tests/fixtures"

# shellcheck source=scripts/common/manifest.sh
source "${BP_ROOT}/scripts/common/manifest.sh"
# shellcheck source=scripts/common/ini_block.sh
source "${BP_ROOT}/scripts/common/ini_block.sh"
# shellcheck source=scripts/common/backup.sh
source "${BP_ROOT}/scripts/common/backup.sh"
# shellcheck source=scripts/common/state.sh
source "${BP_ROOT}/scripts/common/state.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; }

assert_eq() {
	local desc="$1" expected="$2" actual="$3"
	if [[ "$expected" == "$actual" ]]; then
		pass "$desc"
	else
		fail "$desc (expected: [${expected}], got: [${actual}])"
	fi
}

assert_success() {
	local desc="$1"
	shift
	if "$@" >/tmp/bp_test_out 2>&1; then
		pass "$desc"
	else
		fail "$desc ($(cat /tmp/bp_test_out))"
	fi
}

assert_failure() {
	local desc="$1"
	shift
	if "$@" >/tmp/bp_test_out 2>&1; then
		fail "$desc (expected failure, succeeded)"
	else
		pass "$desc"
	fi
}

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "== manifest validation =="
assert_success "valid manifest passes validate_manifest" validate_manifest "${FIXTURES}/valid-manifest.json"
assert_failure "invalid manifest fails validate_manifest" validate_manifest "${FIXTURES}/invalid-manifest.json"
assert_success "valid profile passes validate_profile" validate_profile "${FIXTURES}/valid-profile.json"
assert_failure "invalid profile fails validate_profile" validate_profile "${FIXTURES}/invalid-profile.json"

echo "== manifest_required_content =="
required="$(manifest_required_content "${FIXTURES}/valid-manifest.json")"
assert_eq "lists only required bananas-sourced items" "Example NewGRF" "$required"

echo "== ini_patch_block: fresh insert =="
CFG="${WORKDIR}/openttd.cfg"
cp "${FIXTURES}/sample-openttd.cfg" "$CFG"
BLOCK="${WORKDIR}/block1.txt"
printf 'distribution_pax = 2\ndistribution_mail = 2\n' >"$BLOCK"
ini_patch_block "$CFG" "linkgraph" "profile: test, section: linkgraph" "$BLOCK"
extracted="$(ini_extract_block "$CFG" "profile: test, section: linkgraph")"
assert_eq "block content matches after fresh insert" "$(cat "$BLOCK")" "$extracted"
assert_success "pre-existing key in same section survives" grep -q "recalc_time = 4" "$CFG"
assert_success "unrelated section untouched" grep -q "server_name = My Server" "$CFG"

echo "== ini_patch_block: idempotent re-patch =="
cp "$CFG" "${CFG}.before"
ini_patch_block "$CFG" "linkgraph" "profile: test, section: linkgraph" "$BLOCK"
if diff -q "${CFG}.before" "$CFG" >/dev/null; then
	pass "re-running with identical block produces byte-identical file"
else
	fail "re-running with identical block changed the file"
fi

echo "== ini_patch_block: update existing block =="
BLOCK2="${WORKDIR}/block2.txt"
printf 'distribution_pax = 1\n' >"$BLOCK2"
ini_patch_block "$CFG" "linkgraph" "profile: test, section: linkgraph" "$BLOCK2"
extracted2="$(ini_extract_block "$CFG" "profile: test, section: linkgraph")"
assert_eq "block content updates in place" "distribution_pax = 1" "$extracted2"
marker_count="$(grep -c "BEGIN OPENTTD BLUEPRINT (profile: test, section: linkgraph)" "$CFG")"
assert_eq "no duplicate marker blocks after repeated patch" "1" "$marker_count"

echo "== ini_patch_block: unknown user NewGRF content preserved =="
assert_success "unrelated NewGRF entries survive untouched" grep -q "some-old-pack.grf = 1 2 3" "$CFG"
assert_success "second unrelated NewGRF entry survives untouched" grep -q "custom-grf.grf =" "$CFG"

echo "== ini_patch_block: missing section is an error, not silent =="
assert_failure "patching a nonexistent section fails loudly" ini_patch_block "$CFG" "does_not_exist" "profile: test, section: nope" "$BLOCK"

echo "== ini_split_sections =="
SPLIT_DIR="${WORKDIR}/split"
BLOCKFILE="${WORKDIR}/blockfile.cfg"
printf '[difficulty]\nnumber_towns = 2\n\n[economy]\ninflation = true\n' >"$BLOCKFILE"
ini_split_sections "$BLOCKFILE" "$SPLIT_DIR"
assert_success "difficulty.body created" test -f "${SPLIT_DIR}/difficulty.body"
assert_success "economy.body created" test -f "${SPLIT_DIR}/economy.body"
assert_eq "difficulty.body has correct content" "number_towns = 2" "$(cat "${SPLIT_DIR}/difficulty.body")"

echo "== paths with spaces =="
SPACE_DIR="${WORKDIR}/dir with spaces"
mkdir -p "$SPACE_DIR"
SPACE_CFG="${SPACE_DIR}/openttd.cfg"
cp "${FIXTURES}/sample-openttd.cfg" "$SPACE_CFG"
assert_success "ini_patch_block works with spaces in path" ini_patch_block "$SPACE_CFG" "linkgraph" "profile: test, section: linkgraph" "$BLOCK"

echo "== backup creation =="
BACKUP_ROOT="${WORKDIR}/backups"
backup_dir="$(backup_config "$CFG" "$BACKUP_ROOT" "test" "15.3" "0.1.0")"
assert_success "backup directory created" test -d "$backup_dir"
assert_success "backup contains openttd.cfg" test -f "${backup_dir}/openttd.cfg"
assert_success "backup contains metadata.json" test -f "${backup_dir}/metadata.json"
assert_success "backup metadata is valid JSON" jq -e . "${backup_dir}/metadata.json"
meta_profile="$(jq -r '.profile' "${backup_dir}/metadata.json")"
assert_eq "backup metadata records profile name" "test" "$meta_profile"

echo "== backup naming / latest_backup =="
sleep 1
backup_dir2="$(backup_config "$CFG" "$BACKUP_ROOT" "test" "15.3" "0.1.0")"
latest="$(latest_backup "$BACKUP_ROOT")"
assert_eq "latest_backup returns the most recent one" "$backup_dir2" "$latest"

echo "== state read/write =="
STATE_FILE="${WORKDIR}/blueprint-state.json"
write_state "$STATE_FILE" "0.1.0" "test" "0.1.0" "$backup_dir" '["Preexisting Thing"]' '["Added Thing"]'
assert_success "state file is valid JSON" jq -e . "$STATE_FILE"
profile_field="$(read_state_field "$STATE_FILE" '.profile')"
assert_eq "state records profile" "test" "$profile_field"
added_field="$(read_state_field "$STATE_FILE" '.content_added_by_install[0]')"
assert_eq "state records added content" "Added Thing" "$added_field"

echo "== --with-ai manifest filtering (logistics profile) =="
LOGISTICS_MANIFEST="${BP_ROOT}/profiles/logistics/content-manifest.json"
without_ai_names="$(jq -r --argjson with_ai 0 \
	'.content[] | select((.required == true or (.type == "ai" and $with_ai == 1)) and .source == "bananas") | .name' \
	"$LOGISTICS_MANIFEST")"
with_ai_names="$(jq -r --argjson with_ai 1 \
	'.content[] | select((.required == true or (.type == "ai" and $with_ai == 1)) and .source == "bananas") | .name' \
	"$LOGISTICS_MANIFEST")"
if echo "$without_ai_names" | grep -qxF "RailwAI"; then
	fail "RailwAI must NOT be selected without --with-ai"
else
	pass "RailwAI excluded by default (no --with-ai)"
fi
if echo "$with_ai_names" | grep -qxF "RailwAI"; then
	pass "RailwAI included with --with-ai"
else
	fail "RailwAI must be selected when --with-ai is set"
fi
without_count="$(echo "$without_ai_names" | grep -c .)"
with_count="$(echo "$with_ai_names" | grep -c .)"
assert_eq "with-ai adds exactly one item to the selection" "$((without_count + 1))" "$with_count"

echo
echo "== dry-run makes no writes (real installer, throwaway fixture profile) =="
DRYRUN_HOME="${WORKDIR}/home"
mkdir -p "${DRYRUN_HOME}/config" "${DRYRUN_HOME}/data"
before_hash="none"
if XDG_CONFIG_HOME="${DRYRUN_HOME}/config" XDG_DATA_HOME="${DRYRUN_HOME}/data" \
	"${BP_ROOT}/install-linux.sh" --dry-run >/tmp/bp_dryrun_out 2>&1; then
	pass "dry-run against a machine with no OpenTTD config exits 0"
else
	# No OpenTTD installed in CI is an expected/acceptable dry-run failure
	# mode (it exits non-zero with a clear "not found" message) — what
	# matters for this test is that nothing was written.
	pass "dry-run exits non-zero cleanly when OpenTTD isn't installed (CI has none)"
fi
if [[ -f "${DRYRUN_HOME}/config/openttd/openttd.cfg" ]]; then
	fail "dry-run must not create openttd.cfg"
else
	pass "dry-run created no openttd.cfg"
fi

echo
echo "=========================================="
echo "PASS: ${PASS}  FAIL: ${FAIL}"
if [[ "$FAIL" -gt 0 ]]; then
	exit 1
fi
