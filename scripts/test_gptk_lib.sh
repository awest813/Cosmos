#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/gptk_lib.sh
source "${ROOT}/scripts/lib/gptk_lib.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

gptk_validate_path "" >/dev/null 2>&1 && fail "empty path should fail"
mkdir -p "${tmpdir}/empty"
gptk_validate_path "${tmpdir}/empty" >/dev/null 2>&1 && fail "empty dir should fail"

mkdir -p "${tmpdir}/gptk/lib"
touch "${tmpdir}/gptk/lib/d3d11.dll" "${tmpdir}/gptk/lib/d3d12.dll"
out="$(gptk_validate_path "${tmpdir}/gptk")"
printf '%s\n' "${out}" | grep -q '^valid=1$' || fail "valid GPTK layout should pass"
printf '%s\n' "${out}" | grep -q '^dll_count=2$' || fail "expected dll_count=2"

printf 'OK: gptk_lib tests passed\n'
