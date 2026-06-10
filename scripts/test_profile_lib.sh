#!/usr/bin/env bash
set -euo pipefail

# Unit tests for scripts/lib/profile_lib.sh (roadmap 0.4).

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/profile_lib.sh
source "${ROOT}/scripts/lib/profile_lib.sh"

PROFILE="${ROOT}/profiles/steam/steam-250900-binding-of-isaac.yaml"
FALLOUT="${ROOT}/profiles/steam/steam-22380-fallout-new-vegas.yaml"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_eq() {
  [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'"
}

assert_eq "$(profile_get_scalar "${PROFILE}" id)" "binding_of_isaac"
assert_eq "$(profile_get_scalar "${PROFILE}" steam_appid)" "250900"
assert_eq "$(profile_get_scalar "${PROFILE}" recommended_backend)" "dxmt"
assert_eq "$(profile_get_scalar "${PROFILE}" settings.windows_version)" "win10"
assert_eq "$(profile_get_env_line "${PROFILE}" DXMT_CONFIG)" "d3d11.preferredMaxFrameRate=60;"

notes="$(profile_get_notes "${PROFILE}")"
[[ -n "${notes}" ]] || fail "expected notes on binding of isaac profile"

found="$(profile_find_by_appid "${ROOT}/profiles" "250900")"
[[ -f "${found}" ]] || fail "profile_find_by_appid did not find 250900"

deps="$(profile_list_dependencies "${FALLOUT}" | tr '\n' ' ')"
[[ "${deps}" == *"vcrun2010"* ]] || fail "expected vcrun2010 in fallout deps"
[[ "${deps}" == *"d3dx9"* ]] || fail "expected d3dx9 in fallout deps"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
profile_export_override_to "${PROFILE}" "250900" "${tmpdir}/250900.env"
grep -q 'COSMOS_BACKEND=dxmt' "${tmpdir}/250900.env" || fail "override missing backend"
grep -q 'DXMT_CONFIG=' "${tmpdir}/250900.env" || fail "override missing DXMT_CONFIG"

count="$(find "${ROOT}/profiles/steam" -name '*.yaml' | wc -l | tr -d ' ')"
(( count >= 50 )) || fail "expected at least 50 steam profiles, found ${count}"

printf 'OK: profile_lib tests passed (%s profiles)\n' "${count}"
