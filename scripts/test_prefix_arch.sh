#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/prefix_arch.sh
source "${ROOT}/scripts/lib/prefix_arch.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ "$(prefix_arch_normalize '')" == "wow64" ]] || fail "empty prefix arch"
[[ "$(prefix_arch_normalize wow)" == "wow64" ]] || fail "wow alias"
[[ "$(prefix_arch_normalize x64)" == "win64" ]] || fail "x64 alias"
[[ "$(prefix_arch_normalize 32)" == "win32" ]] || fail "32 alias"
prefix_arch_normalize nope >/dev/null 2>&1 && fail "unknown prefix arch should fail"
[[ "$(prefix_arch_label wow64)" == "64-bit and 32-bit" ]] || fail "wow64 label"
[[ "$(program_arch_normalize '')" == "win64" ]] || fail "empty program arch"
[[ "$(program_arch_normalize win32)" == "win32" ]] || fail "win32 program"
[[ "$(program_arch_label win32)" == "32-bit" ]] || fail "32-bit label"

(
  unset WINEARCH COSMOS_PREFIX_ARCH
  prefix_arch_export_winearch
  [[ "${WINEARCH}" == "win64" ]] || fail "default WINEARCH"
  [[ "${COSMOS_PREFIX_ARCH}" == "wow64" ]] || fail "default layout"
)
(
  export WINEARCH=win32
  unset COSMOS_PREFIX_ARCH
  prefix_arch_export_winearch
  [[ "${WINEARCH}" == "win32" ]] || fail "explicit WINEARCH should stay"
)
(
  unset WINEARCH
  prefix_arch_export_winearch win32
  [[ "${WINEARCH}" == "win32" && "${COSMOS_PREFIX_ARCH}" == "win32" ]] || fail "win32 export"
)

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
COSMOS_BOTTLES_DIR="${tmpdir}/bottles" "${ROOT}/bottle.command" create retro --arch 32 --windows winxp --backend spockd3d9 >/dev/null
conf="${tmpdir}/bottles/retro/bottle.conf"
grep -q 'COSMOS_PREFIX_ARCH="win32"' "${conf}" || fail "create should store win32: $(cat "${conf}")"
grep -q 'COSMOS_BACKEND="spockd3d9"' "${conf}" || fail "backend stored"
COSMOS_BOTTLES_DIR="${tmpdir}/bottles" "${ROOT}/bottle.command" set retro COSMOS_PREFIX_ARCH wow64 >/dev/null
grep -q 'COSMOS_PREFIX_ARCH="wow64"' "${conf}" || fail "set should normalize to wow64"
if COSMOS_BOTTLES_DIR="${tmpdir}/bottles" "${ROOT}/bottle.command" set retro COSMOS_PREFIX_ARCH weird >/dev/null 2>&1; then
  fail "unknown arch should be refused"
fi

printf 'OK: prefix arch tests passed\n'
