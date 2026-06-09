#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/repair_diagnose.sh
source "${ROOT}/scripts/repair_diagnose.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

export WINEPREFIX="${TMPDIR:-/tmp}/cosmos-repair-test-$$"
export SCRIPT_DIR="${ROOT}"
mkdir -p "${WINEPREFIX}/drive_c/windows/system32"
printf 'fake\n' > "${WINEPREFIX}/system.reg"

repair_diagnose_reset
repair_diagnose_scan_log "${ROOT}/scripts/fixtures/repair-vcrun2015.log"
[[ " ${DIAG_SUGGESTIONS[*]} " == *" dep:vcrun2015 "* ]] \
  || fail "expected dep:vcrun2015 from fixture log"

repair_diagnose_reset
repair_diagnose_scan_log "${ROOT}/scripts/fixtures/repair-steam-ssl.log"
[[ " ${DIAG_SUGGESTIONS[*]} " == *" fix:fix_steam_ssl "* ]] \
  || fail "expected fix:fix_steam_ssl from fixture log"

repair_diagnose_reset
repair_diagnose_scan_log "${ROOT}/scripts/fixtures/repair-mscoree.log"
[[ " ${DIAG_SUGGESTIONS[*]} " == *" fix:grounded-mscoree-fix "* ]] \
  || fail "expected fix:grounded-mscoree-fix from mscoree fixture log"

repair_suggestion_is_auto_applicable dep:vcrun2015 || fail "dep should be auto-applicable"
repair_suggestion_is_auto_applicable fix:kill_wine || fail "kill_wine should be auto-applicable"
repair_suggestion_is_auto_applicable fix:set_backend && fail "set_backend should not be auto-applicable"

printf 'OK: repair diagnose tests passed\n'
