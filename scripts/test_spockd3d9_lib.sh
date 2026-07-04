#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/spockd3d9_lib.sh
source "${ROOT}/scripts/lib/spockd3d9_lib.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

export COSMOS_SKIP_PE_CHECK=1

spockd3d9_validate_path "" >/dev/null 2>&1 && fail "empty path should fail"
mkdir -p "${tmpdir}/empty"
spockd3d9_validate_path "${tmpdir}/empty" >/dev/null 2>&1 && fail "empty dir should fail"

mkdir -p "${tmpdir}/spock/x86" "${tmpdir}/spock/x64"
touch "${tmpdir}/spock/x86/d3d9.dll" "${tmpdir}/spock/x64/d3d9.dll"
out="$(spockd3d9_validate_path "${tmpdir}/spock")"
printf '%s\n' "${out}" | grep -q '^valid=1$' || fail "valid SpockD3D9 layout should pass"
printf '%s\n' "${out}" | grep -q '^dll_count=2$' || fail "expected dll_count=2"
printf '%s\n' "${out}" | grep -q '^x86_dll=' || fail "expected x86_dll"
printf '%s\n' "${out}" | grep -q '^x64_dll=' || fail "expected x64_dll"

x86_only="$(spockd3d9_find_arch_dll "${tmpdir}/spock" x86)"
[[ "${x86_only}" == "${tmpdir}/spock/x86/d3d9.dll" ]] || fail "x86 dll lookup failed"

printf 'OK: spockd3d9_lib tests passed\n'
