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

# Real PE headers exercise file-type/architecture validation, not the bypass above.
unset COSMOS_SKIP_PE_CHECK
python3 - "${tmpdir}" <<'PYTEST'
from pathlib import Path
import struct, sys
root = Path(sys.argv[1])
for arch, machine, magic, size in [('x86', 0x14c, 0x10b, 224), ('x64', 0x8664, 0x20b, 240)]:
    data = bytearray(1024)
    data[:2] = b'MZ'
    struct.pack_into('<I', data, 60, 128)
    data[128:132] = b'PE\0\0'
    struct.pack_into('<HHIIIHH', data, 132, machine, 1, 0, 0, 0, size, 0x2102)
    struct.pack_into('<H', data, 152, magic)
    struct.pack_into('<H', data, 220, 2)
    (root / 'spock' / arch / 'd3d9.dll').write_bytes(data)
PYTEST
spockd3d9_validate_path "${tmpdir}/spock" >/dev/null || fail "matching PE headers should validate"
cp "${tmpdir}/spock/x64/d3d9.dll" "${tmpdir}/spock/x86/d3d9.dll"
spockd3d9_validate_path "${tmpdir}/spock" >/dev/null 2>&1 && fail "wrong x86 DLL must fail even with valid x64 present"
rm "${tmpdir}/spock/x86/d3d9.dll"
spockd3d9_validate_path "${tmpdir}/spock" >/dev/null || fail "64-bit-only builds remain valid and report their architecture"

[[ "$(spockd3d9_merge_overrides '')" == 'd3d9=n,b' ]] || fail "empty overrides"
[[ "$(spockd3d9_merge_overrides 'dxgi=n;bcrypt=b')" == 'dxgi=n;bcrypt=b;d3d9=n,b' ]] || fail "preserve unrelated overrides"
[[ "$(spockd3d9_merge_overrides 'd3d9,dxgi=b;d3d11=n;d3d9=n')" == 'dxgi=b;d3d11=n;d3d9=n,b' ]] || fail "remove conflicting D3D9 entries"
[[ "$(spockd3d9_merge_overrides '*D3D9.dll=b;dinput8=n,b')" == 'dinput8=n,b;d3d9=n,b' ]] || fail "normalize D3D9 spelling"

export COSMOS_SKIP_PE_CHECK=1
mkdir -p "${tmpdir}/spock/x86"
printf 'MZ\n' > "${tmpdir}/spock/x86/d3d9.dll"
cp "${tmpdir}/spock/x86/d3d9.dll" "${tmpdir}/saved-x86.dll"
[[ -f "${tmpdir}/spock/x64/d3d9.dll" ]] || printf 'MZ\n' > "${tmpdir}/spock/x64/d3d9.dll"
prefix="${tmpdir}/prefix"
mkdir -p "${prefix}/drive_c/windows/system32"
unset COSMOS_PREFIX_ARCH COSMOS_PROGRAM_ARCH
spockd3d9_install_into_prefix "${tmpdir}/spock" "${prefix}" >/dev/null \
  || fail "wow64 should install the DLLs that exist"
[[ -f "${prefix}/drive_c/windows/system32/d3d9.dll" ]] || fail "wow64 should copy the 64-bit DLL"
[[ -f "${prefix}/drive_c/windows/syswow64/d3d9.dll" ]] || fail "wow64 should copy the 32-bit DLL into syswow64"

rm -rf "${prefix}/drive_c"
mkdir -p "${prefix}/drive_c/windows/system32"
COSMOS_PREFIX_ARCH=win64 COSMOS_PROGRAM_ARCH=win32 \
  spockd3d9_install_into_prefix "${tmpdir}/spock" "${prefix}" \
  | grep -q "64-bit only" || fail "64-bit-only prefix should leave a 32-bit program on WineD3D"
[[ ! -f "${prefix}/drive_c/windows/syswow64/d3d9.dll" ]] || fail "64-bit-only prefix should not create syswow64"

rm -rf "${prefix}/drive_c"
mkdir -p "${prefix}/drive_c/windows/system32"
COSMOS_PREFIX_ARCH=win32 spockd3d9_install_into_prefix "${tmpdir}/spock" "${prefix}" >/dev/null \
  || fail "32-bit-only prefix should install the x86 DLL"
[[ -f "${prefix}/drive_c/windows/system32/d3d9.dll" ]] || fail "32-bit DLL should land in system32"
[[ ! -d "${prefix}/drive_c/windows/syswow64" ]] || fail "32-bit-only prefix has no syswow64 folder"

rm -f "${tmpdir}/spock/x86/d3d9.dll"
rm -rf "${prefix}/drive_c"
mkdir -p "${prefix}/drive_c/windows/system32"
if COSMOS_PREFIX_ARCH=win32 spockd3d9_install_into_prefix "${tmpdir}/spock" "${prefix}"; then
  fail "32-bit-only prefix should fail when the 32-bit DLL is missing"
fi
COSMOS_PREFIX_ARCH=wow64 COSMOS_PROGRAM_ARCH=win32 \
  spockd3d9_install_into_prefix "${tmpdir}/spock" "${prefix}" \
  | grep -q "WineD3D" || fail "missing 32-bit DLL should say WineD3D remains"

# Fallback must force the builtin DLL, even if a stale native DLL and a grouped
# native override are present from a previous graphics backend.
log() { :; }
runtime_prepare_moltenvk_env() { :; }
COSMOS_PROGRAM_ARCH=win32
COSMOS_PREFIX_ARCH=wow64
WINEDLLOVERRIDES='d3d9,dxgi=n;dinput8=n,b'
spockd3d9_install_into_prefix "${tmpdir}/spock" "${prefix}" >/dev/null
enable_spockd3d9_env >/dev/null
[[ "${WINEDLLOVERRIDES}" == 'dxgi=n;dinput8=n,b;d3d9=b' ]] || fail "WineD3D fallback must override stale native D3D9 without removing DXMT"

cp "${tmpdir}/saved-x86.dll" "${tmpdir}/spock/x86/d3d9.dll"
spockd3d9_install_into_prefix "${tmpdir}/spock" "${prefix}" >/dev/null
enable_spockd3d9_env >/dev/null
[[ "${WINEDLLOVERRIDES}" == 'dxgi=n;dinput8=n,b;d3d9=n,b' ]] || fail "matching x86 DLL should enable Spock again"

# A changed creation preference must not install a 64-bit DLL into an existing
# 32-bit prefix's system32. Also cover Windows registry CRLF line endings.
printf 'WINE REGISTRY Version 2\r\n#arch=win32\r\n' > "${prefix}/system.reg"
rm -rf "${prefix}/drive_c/windows/syswow64"
COSMOS_PREFIX_ARCH=wow64 spockd3d9_install_into_prefix "${tmpdir}/spock" "${prefix}" >/dev/null
cmp "${tmpdir}/spock/x86/d3d9.dll" "${prefix}/drive_c/windows/system32/d3d9.dll" || fail "existing win32 layout must win over preference"
[[ ! -d "${prefix}/drive_c/windows/syswow64" ]] || fail "win32 prefix must not create syswow64"
printf 'WINE REGISTRY Version 2\n#arch=win64\n' > "${prefix}/system.reg"
if COSMOS_PREFIX_ARCH=win32 spockd3d9_install_into_prefix "${tmpdir}/spock" "${prefix}" >/dev/null 2>&1; then
  fail "win32 preference must not overwrite an existing win64 system32"
fi

if (
  cp() { return 1; }
  COSMOS_PREFIX_ARCH=wow64 spockd3d9_install_into_prefix "${tmpdir}/spock" "${prefix}"
) >/dev/null 2>&1; then
  fail "copy failures must fail installation even when called in a conditional"
fi

printf 'OK: Spock path, PE architecture, and override-merge tests passed\n'
