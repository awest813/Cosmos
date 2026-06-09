#!/usr/bin/env bash
# Tests for the pre-launch compatibility heads-up: profile_lib helpers plus the
# run.command --compat-check action. A game marked broken/blocked (e.g. an
# anti-cheat title) must warn the user before launch — the macOS equivalent of a
# ProtonDB "Blocked" badge.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${TEST_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/profile_lib.sh
source "${REPO_ROOT}/scripts/lib/profile_lib.sh"

pass=0
fail=0
check() {
  if [[ "$2" == "$3" ]]; then
    echo "  ok  $1"
    pass=$((pass + 1))
  else
    echo "  FAIL $1: expected '$3' got '$2'"
    fail=$((fail + 1))
  fi
}
contains() {
  if [[ "$2" == *"$3"* ]]; then
    echo "  ok  $1"
    pass=$((pass + 1))
  else
    echo "  FAIL $1: '$2' does not contain '$3'"
    fail=$((fail + 1))
  fi
}

# --- profile_compat_warning: pure string logic ---
rc=0; out="$(profile_compat_warning blocked "Foo" "uses anti-cheat")" || rc=$?
check "blocked returns 0" "${rc}" "0"
contains "blocked message says BLOCKED" "${out}" "BLOCKED"
contains "blocked message includes the name" "${out}" "Foo"
contains "blocked message appends the note" "${out}" "uses anti-cheat"

rc=0; out="$(profile_compat_warning broken "Bar")" || rc=$?
check "broken returns 0" "${rc}" "0"
contains "broken message says BROKEN" "${out}" "BROKEN"

for ok_status in platinum gold silver playable bronze; do
  rc=0; out="$(profile_compat_warning "${ok_status}" "Baz")" || rc=$?
  check "${ok_status} returns 1 (no warning)" "${rc}" "1"
  check "${ok_status} prints nothing" "${out}" ""
done

# --- profile_status_for_appid + profile_find_by_appid against a temp library ---
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
mkdir -p "${WORK}/steam"
cat > "${WORK}/steam/steam-111-blocked.yaml" <<'EOF'
id: blocked_game
name: "Blocked Game"
store: steam
steam_appid: 111
status: blocked
recommended_backend: recommended
notes: "anti-cheat title"
EOF
cat > "${WORK}/steam/steam-222-good.yaml" <<'EOF'
id: good_game
name: "Good Game"
store: steam
steam_appid: 222
status: gold
recommended_backend: dxmt
EOF

check "status_for_appid blocked" "$(profile_status_for_appid "${WORK}" 111)" "blocked"
check "status_for_appid good" "$(profile_status_for_appid "${WORK}" 222)" "gold"
rc=0; profile_status_for_appid "${WORK}" 999 >/dev/null || rc=$?
check "status_for_appid unknown returns 1" "${rc}" "1"

# --- end-to-end: run.command --compat-check (read-only; no Wine/macOS needed) ---
export COSMOS_SUPPORT_DIR="${WORK}/support"
export COSMOS_PROFILES_DIR="${WORK}"

rc=0; out="$("${REPO_ROOT}/run.command" --compat-check 111 2>&1)" || rc=$?
check "compat-check blocked exits 0" "${rc}" "0"
contains "compat-check blocked warns" "${out}" "BLOCKED"

rc=0; out="$("${REPO_ROOT}/run.command" --compat-check 222 2>&1)" || rc=$?
check "compat-check good exits 0" "${rc}" "0"
contains "compat-check good reports no blockers" "${out}" "no known blockers"

rc=0; out="$("${REPO_ROOT}/run.command" --compat-check 999 2>&1)" || rc=$?
check "compat-check unknown exits 0" "${rc}" "0"
contains "compat-check unknown says unknown" "${out}" "unknown"

# Honor the suppression flag.
rc=0; out="$(COSMOS_SKIP_COMPAT_CHECK=1 "${REPO_ROOT}/run.command" --compat-check 111 2>&1)" || rc=$?
check "skip flag suppresses output" "${out}" ""

# --- the shipped Destiny 2 profile is a real blocked example ---
# Point at the real profiles/ dir (the temp override above is still exported).
rc=0; out="$(COSMOS_PROFILES_DIR="${REPO_ROOT}/profiles" "${REPO_ROOT}/run.command" --compat-check 1085660 2>&1)" || rc=$?
contains "shipped Destiny 2 is blocked" "${out}" "BLOCKED"

echo ""
echo "Results: ${pass} passed, ${fail} failed"
[[ ${fail} -eq 0 ]] && echo "OK: compat preflight tests passed"
[[ ${fail} -eq 0 ]]
