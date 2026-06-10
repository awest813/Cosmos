#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/rosetta_lib.sh
source "${ROOT}/scripts/lib/rosetta_lib.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

arch="$(rosetta_host_arch)"
[[ -n "${arch}" ]] || fail "rosetta_host_arch empty"

code="$(rosetta_status_code)"
[[ "${code}" == "available" || "${code}" == "missing" || "${code}" == "not_required" ]] \
  || fail "unexpected rosetta_status_code: ${code}"

label="$(rosetta_status_label)"
[[ -n "${label}" ]] || fail "rosetta_status_label empty"

if [[ "${arch}" == "arm64" ]]; then
  rosetta_needs_translation || fail "arm64 host should need translation"
else
  rosetta_needs_translation && fail "non-arm64 host should not need translation"
fi

if [[ "${arch}" == "arm64" || "${arch}" == "x86_64" ]]; then
  cosmos_host_supported || fail "supported arch should pass cosmos_host_supported"
else
  cosmos_host_supported && fail "unsupported arch should fail cosmos_host_supported"
fi

label_platform="$(cosmos_host_platform_label)"
[[ -n "${label_platform}" ]] || fail "cosmos_host_platform_label empty"

printf 'OK: rosetta_lib tests passed (arch=%s code=%s platform=%s)\n' "${arch}" "${code}" "${label_platform}"
