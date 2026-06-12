#!/usr/bin/env bash
# Tests import_game.command sync-gog registration flow.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

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

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

game_dir="${tmp}/drive_c/GOG Games/Celeste"
mkdir -p "${game_dir}"
printf 'MZgame' > "${game_dir}/celeste.exe"

configs="${tmp}/configs"
mkdir -p "${configs}"

WINEPREFIX="${tmp}" COSMOS_CONFIGS_DIR="${configs}" \
  "${REPO_ROOT}/import_game.command" sync-gog >"${tmp}/out.txt" 2>&1

out="$(cat "${tmp}/out.txt")"
assert_eq "sync_status" "updated" "$(printf '%s\n' "${out}" | awk -F= '$1=="sync_status"{print $2; exit}')"
assert_eq "sync_new" "1" "$(printf '%s\n' "${out}" | awk -F= '$1=="sync_new"{print $2; exit}')"
[[ -f "${configs}/gog-celeste.conf" ]] && { pass=$((pass + 1)); printf '  ok  wrote gog-celeste.conf\n'; } \
  || { fail=$((fail + 1)); printf '  FAIL missing gog-celeste.conf\n' >&2; }

WINEPREFIX="${tmp}" COSMOS_CONFIGS_DIR="${configs}" \
  "${REPO_ROOT}/import_game.command" sync-gog >"${tmp}/out2.txt" 2>&1
out2="$(cat "${tmp}/out2.txt")"
assert_eq "second sync current" "current" "$(printf '%s\n' "${out2}" | awk -F= '$1=="sync_status"{print $2; exit}')"
assert_eq "second sync new zero" "0" "$(printf '%s\n' "${out2}" | awk -F= '$1=="sync_new"{print $2; exit}')"

if "${REPO_ROOT}/profile.command" for-gog-slug celeste show >/dev/null 2>&1; then
  pass=$((pass + 1))
  printf '  ok  profile.command for-gog-slug celeste\n'
else
  fail=$((fail + 1))
  printf '  FAIL profile.command for-gog-slug\n' >&2
fi

printf '\nResults: %s passed, %s failed\n' "${pass}" "${fail}"
[[ "${fail}" -eq 0 ]]
