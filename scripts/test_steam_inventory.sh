#!/usr/bin/env bash
# Tests Steam install verification and game .exe detection.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
FIXTURE_PREFIX="${REPO_ROOT}/scripts/fixtures/steam_detection/wineprefix"

# shellcheck source=scripts/lib/steam_lib.sh
source "${REPO_ROOT}/scripts/lib/steam_lib.sh"
# shellcheck source=scripts/lib/import_lib.sh
source "${REPO_ROOT}/scripts/lib/import_lib.sh"

pass=0
fail=0

assert_ok() {
  local label="$1"
  shift
  if "$@"; then
    pass=$((pass + 1))
    printf '  ok  %s\n' "${label}"
  else
    fail=$((fail + 1))
    printf '  FAIL %s\n' "${label}" >&2
  fi
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    pass=$((pass + 1))
    printf '  ok  %s\n' "${label}"
  else
    fail=$((fail + 1))
    printf '  FAIL %s\n       expected %q actual %q\n' "${label}" "${expected}" "${actual}" >&2
  fi
}

WINEPREFIX="${FIXTURE_PREFIX}"
export WINEPREFIX
steam_dir="$(steam_find_steam_dir)"

printf 'steam_verify_game_install\n'
lines="$(steam_verify_game_install "${steam_dir}" "570")"
assert_eq "dota installdir ok" "1" "$(printf '%s\n' "${lines}" | awk -F= '$1=="installdir_ok"{print $2; exit}')"
assert_eq "dota exe ok" "1" "$(printf '%s\n' "${lines}" | awk -F= '$1=="exe_ok"{print $2; exit}')"
assert_eq "dota status" "ok" "$(printf '%s\n' "${lines}" | awk -F= '$1=="status"{print $2; exit}')"

broken="$(steam_verify_game_install "${steam_dir}" "123456" || true)"
assert_eq "broken installdir" "0" "$(printf '%s\n' "${broken}" | awk -F= '$1=="installdir_ok"{print $2; exit}')"
assert_eq "broken status" "missing_installdir" "$(printf '%s\n' "${broken}" | awk -F= '$1=="status"{print $2; exit}')"

printf '\nsteam_inventory_counts\n'
inv="$(steam_inventory_counts "${steam_dir}")"
installed="$(printf '%s\n' "${inv}" | awk -F= '$1=="games_installed"{print $2; exit}')"
broken_count="$(printf '%s\n' "${inv}" | awk -F= '$1=="games_broken"{print $2; exit}')"
assert_ok "inventory has installed games" test "${installed:-0}" -gt 0
assert_ok "inventory reports broken installs" test "${broken_count:-0}" -ge 1

printf '\ndetect_steam_games --list --json\n'
json="$(WINEPREFIX="${FIXTURE_PREFIX}" "${REPO_ROOT}/detect_steam_games.command" --list --json 2>/dev/null)"
python3 -c 'import json,sys; d=json.load(sys.stdin); assert any(g.get("appid")=="570" and g.get("exe_ok") for g in d)' <<<"${json}" \
  && { pass=$((pass + 1)); printf '  ok  json includes verified dota install\n'; } \
  || { fail=$((fail + 1)); printf '  FAIL json verify fields\n' >&2; }

printf '\nResults: %s passed, %s failed\n' "${pass}" "${fail}"
[[ "${fail}" -eq 0 ]]
