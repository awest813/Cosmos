#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/rosetta_lib.sh
source "${ROOT}/scripts/lib/rosetta_lib.sh"
# shellcheck source=scripts/lib/wine_lib.sh
source "${ROOT}/scripts/lib/wine_lib.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ "$(wine_default_version)" == "11.8" ]] || fail "default wine version"
[[ "$(wine_default_root)" == "${HOME}/wine-11.8" ]] || fail "default wine root"

export WINE_VERSION=9.0
export WINE_ROOT="${TMPDIR:-/tmp}/cosmos-wine-lib-test"
[[ "$(wine_default_root)" == "${WINE_ROOT}" ]] || fail "WINE_ROOT override"

mkdir -p "${WINE_ROOT}/Wine Devel.app/Contents/Resources/wine/bin"
printf '#!/bin/sh\necho wine-9.0\n' > "${WINE_ROOT}/Wine Devel.app/Contents/Resources/wine/bin/wine"
chmod +x "${WINE_ROOT}/Wine Devel.app/Contents/Resources/wine/bin/wine"

wine_is_installed || fail "expected wine installed in temp root"
[[ "$(wine_reported_version)" == *"wine-9.0"* ]] || fail "wine_reported_version"

lines="$(wine_runtime_status_lines)"
echo "${lines}" | grep -q '^chip=' || fail "missing chip line"
echo "${lines}" | grep -q '^rosetta=' || fail "missing rosetta line"
echo "${lines}" | grep -q '^wine_installed=1' || fail "missing wine_installed"
echo "${lines}" | grep -q '^wine_bin=' || fail "missing wine_bin line"

rm -rf "${WINE_ROOT}"
unset WINE_ROOT WINE_VERSION

printf 'OK: wine_lib tests passed\n'
