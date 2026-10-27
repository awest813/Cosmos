#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/cosmos-bottle-update.XXXXXX")"
trap 'rm -rf "${work}"' EXIT
export COSMOS_BOTTLES_DIR="${work}/Bottles"
fail() { echo "FAIL: $1" >&2; exit 1; }
hash() { shasum -a 256 "$1" | awk '{print $1}'; }
"${ROOT}/bottle.command" create test --backend wined3d --arch wow64 --windows win10 >/dev/null
conf="${COSMOS_BOTTLES_DIR}/test/bottle.conf"
printf '# Keep this comment\nCUSTOM_METADATA="kept"\n' >> "${conf}"
before="$(hash "${conf}")"
"${ROOT}/bottle.command" update test --expect-sha256 "${before}" COSMOS_BACKEND dxmt WINE_RETINA_MODE 1 >/dev/null
grep -q '^COSMOS_BACKEND="dxmt"$' "${conf}" || fail "backend did not save"
grep -q '^WINE_RETINA_MODE="1"$' "${conf}" || fail "retina did not save"
grep -q '^CUSTOM_METADATA="kept"$' "${conf}" || fail "metadata lost"
grep -q '^# Keep this comment$' "${conf}" || fail "comment lost"
current="$(hash "${conf}")"
if "${ROOT}/bottle.command" update test --expect-sha256 "${before}" COSMOS_BACKEND wined3d >/dev/null 2>&1; then fail "stale revision accepted"; fi
[[ "$(hash "${conf}")" == "${current}" ]] || fail "stale update modified source"
if "${ROOT}/bottle.command" update test --expect-sha256 "${current}" COSMOS_BACKEND wined3d WINDOWS_VERSION invalid >/dev/null 2>&1; then fail "invalid second value accepted"; fi
[[ "$(hash "${conf}")" == "${current}" ]] || fail "partial update published"
if "${ROOT}/bottle.command" update test --expect-sha256 "${current}" COSMOS_BACKEND dxmt COSMOS_BACKEND wined3d >/dev/null 2>&1; then fail "duplicate key accepted"; fi
mkdir -p "${COSMOS_BOTTLES_DIR}/test/prefix"
printf 'WINE REGISTRY Version 2\n#arch=win64\n' > "${COSMOS_BOTTLES_DIR}/test/prefix/system.reg"
if "${ROOT}/bottle.command" update test --expect-sha256 "${current}" COSMOS_BACKEND wined3d COSMOS_PREFIX_ARCH win32 >/dev/null 2>&1; then fail "initialized architecture changed"; fi
[[ "$(hash "${conf}")" == "${current}" ]] || fail "architecture rejection modified settings"
mv "${conf}" "${work}/external.conf"
ln -s "${work}/external.conf" "${conf}"
if "${ROOT}/bottle.command" update test --expect-sha256 "${current}" COSMOS_BACKEND wined3d >/dev/null 2>&1; then fail "linked configuration overwritten"; fi
[[ "$(hash "${work}/external.conf")" == "${current}" ]] || fail "external configuration changed"
echo "OK: atomic environment settings contracts"
