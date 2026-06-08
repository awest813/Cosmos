#!/usr/bin/env bash
# Unit-style tests for Steam game detection helpers (scripts/lib/steam_lib.sh).
# Runs on Linux/macOS in CI — no Wine prefix or Steam install required.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
FIXTURE_PREFIX="${REPO_ROOT}/scripts/fixtures/steam_detection/wineprefix"

# shellcheck source=scripts/lib/steam_lib.sh
source "${REPO_ROOT}/scripts/lib/steam_lib.sh"

pass=0
fail=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    pass=$((pass + 1))
    printf '  ok  %s\n' "${label}"
  else
    fail=$((fail + 1))
    printf '  FAIL %s\n       expected: %q\n       actual:   %q\n' \
      "${label}" "${expected}" "${actual}" >&2
  fi
}

assert_ok() {
  local label="$1"
  shift
  if "$@"; then
    pass=$((pass + 1))
    printf '  ok  %s\n' "${label}"
  else
    fail=$((fail + 1))
    printf '  FAIL %s (expected success)\n' "${label}" >&2
  fi
}

assert_fail() {
  local label="$1"
  shift
  if "$@"; then
    fail=$((fail + 1))
    printf '  FAIL %s (expected failure)\n' "${label}" >&2
  else
    pass=$((pass + 1))
    printf '  ok  %s\n' "${label}"
  fi
}

WINEPREFIX="${FIXTURE_PREFIX}"
export WINEPREFIX

steam_dir="$(steam_find_steam_dir)"
acf_570="${steam_dir}/steamapps/appmanifest_570.acf"
acf_730="${steam_dir}/steamapps/appmanifest_730.acf"
acf_440="${steam_dir}/steamapps/appmanifest_440.acf"
acf_999="${steam_dir}/steamapps/appmanifest_999.acf"
acf_rust="${WINEPREFIX}/drive_d/SteamLibrary/steamapps/appmanifest_252490.acf"
vdf="${steam_dir}/steamapps/libraryfolders.vdf"

printf '== steam_lib detection helpers ==\n'

assert_eq "steam_acf_read_field name" "Dota 2" "$(steam_acf_read_field "${acf_570}" "name")"
assert_eq "steam_acf_read_field StateFlags" "4" "$(steam_acf_read_field "${acf_570}" "StateFlags")"

assert_ok "fully installed is playable" steam_acf_is_playable "${acf_570}"
assert_fail "downloading is not playable" steam_acf_is_playable "${acf_730}"
assert_fail "uninstalled is not playable" steam_acf_is_playable "${acf_440}"
assert_fail "stale manifest (.tmp.save) is not playable" steam_acf_is_playable "${acf_999}"

COSMOS_DETECT_INCLUDE_PARTIAL=1
export COSMOS_DETECT_INCLUDE_PARTIAL
assert_ok "partial override includes downloading" steam_acf_is_playable "${acf_730}"
unset COSMOS_DETECT_INCLUDE_PARTIAL

assert_eq "steam_find_app_manifest primary" "${acf_570}" "$(steam_find_app_manifest "${steam_dir}" "570")"
manifest_rust="$(steam_find_app_manifest "${steam_dir}" "252490")"
assert_ok "secondary library manifest exists" test -f "${manifest_rust}"
assert_eq "secondary library appid" "252490" "$(steam_acf_read_field "${manifest_rust}" "appid")"

common_570="$(steam_verify_installdir "${acf_570}")"
assert_ok "installdir exists for dota" test -d "${common_570}"

assert_eq "library v2 path" 'D:\\SteamLibrary' "$(steam_library_paths_from_vdf "${vdf}" | head -n1)"

unix_path="$(steam_win_to_unix "$(steam_library_paths_from_vdf "${vdf}" | head -n1)")"
assert_eq "win_to_unix drive letter" \
  "${WINEPREFIX}/dosdevices/d:/SteamLibrary" \
  "${unix_path}"

dirs="$(steam_collect_steamapps_dirs "${steam_dir}" | tr '\n' '|')"
case "${dirs}" in
  *"drive_d/SteamLibrary/steamapps"*) assert_ok "collects secondary library" true ;;
  *) assert_fail "collects secondary library" false ;;
esac

printf '\n== detect_steam_games.command (fixture prefix) ==\n'
list_out="$("${REPO_ROOT}/detect_steam_games.command" --list 2>&1)" || true
case "${list_out}" in
  *"570"*"Dota 2"*) assert_ok "lists fully installed dota" true ;;
  *) assert_fail "lists fully installed dota" false ;;
esac
case "${list_out}" in
  *"252490"*"Rust"*) assert_ok "lists secondary-library rust" true ;;
  *) assert_fail "lists secondary-library rust" false ;;
esac
case "${list_out}" in
  *"730"*) assert_fail "skips downloading cs2" false ;;
  *) assert_ok "skips downloading cs2" true ;;
esac
case "${list_out}" in
  *"skipped"*) assert_ok "reports skipped partial count" true ;;
  *) assert_fail "reports skipped partial count" false ;;
esac

printf '\nResults: %s passed, %s failed\n' "${pass}" "${fail}"
(( fail == 0 ))
