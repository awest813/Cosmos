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

printf '\n== steam_lib install validation ==\n'

tmp_steam_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_steam_dir}"' EXIT

valid_exe="${tmp_steam_dir}/drive_c/Program Files (x86)/Steam/steam.exe"
mkdir -p "$(dirname "${valid_exe}")"
{
  printf 'MZ'
  dd if=/dev/zero bs=1 count=$((STEAM_EXE_MIN_BYTES - 2)) 2>/dev/null
} > "${valid_exe}"

stub_exe="${tmp_steam_dir}/drive_c/Program Files/Steam/steam.exe"
mkdir -p "$(dirname "${stub_exe}")"
printf 'MZstub' > "${stub_exe}"

saved_prefix="${WINEPREFIX}"
WINEPREFIX="${tmp_steam_dir}"
export WINEPREFIX

assert_ok "valid steam.exe passes size check" steam_exe_is_valid "${valid_exe}"
assert_fail "stub steam.exe fails size check" steam_exe_is_valid "${stub_exe}"
assert_fail "missing steam.exe fails" steam_exe_is_valid "${tmp_steam_dir}/missing.exe"
assert_eq "find_exe_candidate prefers x86 path" "${valid_exe}" "$(steam_find_exe_candidate)"
resolved=""
candidate="$(steam_find_exe_candidate || true)"
[[ -n "${candidate}" ]] && steam_exe_is_valid "${candidate}" && resolved="${candidate}"
assert_eq "validated exe resolves to valid binary" "${valid_exe}" "${resolved}"

WINEPREFIX="${saved_prefix}"
export WINEPREFIX

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

printf '\n== steam_lib native dual-path scan ==\n'

NATIVE_FIXTURE="${REPO_ROOT}/scripts/fixtures/steam_detection/native_steam"
COSMOS_STEAM_NATIVE_PATH="${NATIVE_FIXTURE}"
COSMOS_STEAM_NATIVE_SCAN=1
export COSMOS_STEAM_NATIVE_PATH COSMOS_STEAM_NATIVE_SCAN

native_dirs="$(steam_collect_native_steamapps_dirs | tr '\n' '|')"
case "${native_dirs}" in
  *"native_steam/steamapps"*) assert_ok "native fixture steamapps discovered" true ;;
  *) assert_fail "native fixture steamapps discovered" false ;;
esac

list_native="$("${REPO_ROOT}/detect_steam_games.command" --list 2>&1)" || true
case "${list_native}" in
  *"620"*"Portal 2"*) assert_ok "native scan lists portal 2" true ;;
  *) assert_fail "native scan lists portal 2" false ;;
esac
case "${list_native}" in
  *"native only"*) assert_ok "portal 2 tagged native only" true ;;
  *) assert_fail "portal 2 tagged native only" false ;;
esac
case "${list_native}" in
  *"570"*"Dota 2"*) assert_ok "wine games still listed with native scan" true ;;
  *) assert_fail "wine games still listed with native scan" false ;;
esac
case "${list_native}" in
  *"wine+native"*) assert_ok "dual install tagged wine+native" true ;;
  *) assert_fail "dual install tagged wine+native" false ;;
esac

dual_ids="$(steam_dual_install_appids "${steam_dir}" | tr '\n' ' ')"
case "${dual_ids}" in
  *"570"*) assert_ok "dual install detects shared appid 570" true ;;
  *) assert_fail "dual install detects shared appid 570" false ;;
esac

unset COSMOS_STEAM_NATIVE_PATH COSMOS_STEAM_NATIVE_SCAN

printf '\n== detect_steam_games.command --list --json ==\n'

json_out="$("${REPO_ROOT}/detect_steam_games.command" --list --json 2>/dev/null || true)"
if python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d, list)' <<<"${json_out}" 2>/dev/null; then
  assert_ok "json list parses as array" true
else
  assert_fail "json list parses as array" false
fi

dota_json="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(g for g in d if g.get("appid")=="570"))' <<<"${json_out}" 2>/dev/null || true)"
case "${dota_json}" in
  *'"sync_eligible": true'*) assert_ok "dota sync_eligible true" true ;;
  *) assert_fail "dota sync_eligible true" false ;;
esac
case "${dota_json}" in
  *'"installdir_ok": true'*) assert_ok "dota installdir_ok in json" true ;;
  *) assert_fail "dota installdir_ok in json" false ;;
esac

rust_json="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(g for g in d if g.get("appid")=="252490"))' <<<"${json_out}" 2>/dev/null || true)"
case "${rust_json}" in
  *'"sync_eligible": false'*) assert_ok "rust sync_eligible false when exe missing" true ;;
  *) assert_fail "rust sync_eligible false when exe missing" false ;;
esac

COSMOS_STEAM_NATIVE_PATH="${NATIVE_FIXTURE}"
COSMOS_STEAM_NATIVE_SCAN=1
export COSMOS_STEAM_NATIVE_PATH COSMOS_STEAM_NATIVE_SCAN
json_native="$("${REPO_ROOT}/detect_steam_games.command" --list --json 2>/dev/null || true)"
portal_json="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(g for g in d if g.get("appid")=="620"))' <<<"${json_native}" 2>/dev/null || true)"
case "${portal_json}" in
  *'"install_status": "native_only"'*) assert_ok "native portal install_status" true ;;
  *) assert_fail "native portal install_status" false ;;
esac
case "${portal_json}" in
  *'"sync_eligible": false'*) assert_ok "native portal not sync eligible" true ;;
  *) assert_fail "native portal not sync eligible" false ;;
esac
case "${portal_json}" in
  *installdir_ok*) assert_fail "native portal omits installdir_ok" false ;;
  *) assert_ok "native portal omits installdir_ok" true ;;
esac
unset COSMOS_STEAM_NATIVE_PATH COSMOS_STEAM_NATIVE_SCAN

printf '\nResults: %s passed, %s failed\n' "${pass}" "${fail}"
(( fail == 0 ))
