#!/usr/bin/env bash
# Unit-style tests for steam_health_lines (scripts/lib/steam_lib.sh).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/steam_lib.sh
source "${REPO_ROOT}/scripts/lib/steam_lib.sh"

pass=0
fail=0

assert_line() {
  local label="$1" key="$2" expected="$3" blob="$4"
  local actual
  actual="$(printf '%s\n' "${blob}" | awk -F= -v k="${key}" '$1==k {print $2; exit}')"
  if [[ "${expected}" == "${actual}" ]]; then
    pass=$((pass + 1))
    printf '  ok  %s\n' "${label}"
  else
    fail=$((fail + 1))
    printf '  FAIL %s\n       expected %s=%q actual %q\n' \
      "${label}" "${key}" "${expected}" "${actual}" >&2
  fi
}

tmp_prefix="$(mktemp -d)"
trap 'rm -rf "${tmp_prefix}"' EXIT

valid_exe="${tmp_prefix}/drive_c/Program Files (x86)/Steam/steam.exe"
mkdir -p "$(dirname "${valid_exe}")" "${tmp_prefix}/drive_c/Program Files (x86)/Steam/userdata"
touch "${tmp_prefix}/system.reg"
{
  printf 'MZ'
  dd if=/dev/zero bs=1 count=$((STEAM_EXE_MIN_BYTES - 2)) 2>/dev/null
} > "${valid_exe}"

WINEPREFIX="${tmp_prefix}"
export WINEPREFIX COSMOS_STEAM_NATIVE_SCAN=0

printf 'steam_health_lines\n'
lines="$(steam_health_lines)"
assert_line "prefix initialized" prefix_initialized 1 "${lines}"
assert_line "steam installed" steam_installed 1 "${lines}"
assert_line "userdata present" userdata_present 1 "${lines}"
assert_line "native scan off" native_scan_enabled 0 "${lines}"

COSMOS_STEAM_NATIVE_SCAN=1
export COSMOS_STEAM_NATIVE_SCAN
lines_native="$(steam_health_lines)"
assert_line "native scan on" native_scan_enabled 1 "${lines_native}"

printf '\nrun.command --steam-health\n'
out="$(WINEPREFIX="${tmp_prefix}" COSMOS_STEAM_NATIVE_SCAN=1 \
  "${REPO_ROOT}/run.command" --steam-health 2>/dev/null || true)"
assert_line "cli prefix" prefix_initialized 1 "${out}"
assert_line "cli native scan" native_scan_enabled 1 "${out}"

printf '\nResults: %s passed, %s failed\n' "${pass}" "${fail}"
[[ "${fail}" -eq 0 ]]
