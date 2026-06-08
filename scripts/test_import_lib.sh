#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/import_lib.sh
source "${ROOT}/scripts/lib/import_lib.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ "$(import_slugify 'My Cool Game!')" == "my-cool-game" ]] \
  || fail "slugify failed"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
file="$(import_write_config "${tmpdir}" "demo" "Demo Game" "com.cosmos.standalone-demo" "drive_c/Games/demo/game.exe")"
grep -q 'GAME_EXE_PATH="drive_c/Games/demo/game.exe"' "${file}" || fail "config missing exe path"
grep -q 'COSMOS_SKIP_STEAM="1"' "${file}" || fail "config missing skip steam"

printf 'OK: import_lib tests passed\n'
