#!/usr/bin/env bash
# Tests Steam direct-launch config generation (GAME_EXE_PATH from detected install).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
FIXTURE_PREFIX="${REPO_ROOT}/scripts/fixtures/steam_detection/wineprefix"

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

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
configs="${tmp}/configs"
mkdir -p "${configs}"

WINEPREFIX="${FIXTURE_PREFIX}" COSMOS_CONFIGS_DIR="${configs}" \
  "${REPO_ROOT}/detect_steam_games.command" --write >/dev/null 2>&1 || true

cfg="$(ls "${configs}"/steam-570*.conf 2>/dev/null | head -n1 || true)"
assert_ok "wrote dota config" test -n "${cfg:-}"
if [[ -n "${cfg}" ]]; then
  if grep -q '^GAME_EXE_PATH=' "${cfg}" 2>/dev/null; then
    fail=$((fail + 1))
    printf '  FAIL default config uses applaunch\n' >&2
  else
    pass=$((pass + 1))
    printf '  ok  default config uses applaunch\n'
  fi
fi

rm -f "${configs}"/steam-*.conf
overrides="${configs}/overrides"
mkdir -p "${overrides}"
printf 'COSMOS_STEAM_DIRECT_LAUNCH=1\nCOSMOS_SKIP_STEAM=1\n' > "${overrides}/570.env"

WINEPREFIX="${FIXTURE_PREFIX}" COSMOS_CONFIGS_DIR="${configs}" \
  "${REPO_ROOT}/detect_steam_games.command" --write >/dev/null 2>&1

cfg="$(ls "${configs}"/steam-570*.conf 2>/dev/null | head -n1 || true)"
assert_ok "direct override wrote config" test -n "${cfg:-}"
if [[ -n "${cfg}" ]]; then
  assert_ok "config has GAME_EXE_PATH" grep -q '^GAME_EXE_PATH=' "${cfg}"
  assert_ok "config has COSMOS_SKIP_STEAM" grep -q '^COSMOS_SKIP_STEAM=' "${cfg}"
  assert_ok "exe path points at dota2" grep -q 'dota2\.exe' "${cfg}"
fi

printf '\nprofile export direct launch\n'
override_out="${tmp}/22380.env"
# shellcheck source=scripts/lib/profile_lib.sh
source "${REPO_ROOT}/scripts/lib/profile_lib.sh"
profile_export_override_to \
  "${REPO_ROOT}/profiles/steam/steam-22380-fallout-new-vegas.yaml" \
  22380 "${override_out}"
assert_ok "fallout profile exports direct launch" grep -q 'COSMOS_STEAM_DIRECT_LAUNCH=1' "${override_out}"
assert_ok "fallout profile exports skip steam" grep -q 'COSMOS_SKIP_STEAM=1' "${override_out}"

printf '\nResults: %s passed, %s failed\n' "${pass}" "${fail}"
[[ "${fail}" -eq 0 ]]
