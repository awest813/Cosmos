#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/profile-export-reg.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

export COSMOS_SUPPORT_DIR="${TMP}/support"
export WINEPREFIX="${TMP}/prefix"
mkdir -p "${WINEPREFIX}"
printf 'Windows Registry Editor Version 5.00\n\n' > "${WINEPREFIX}/user.reg"

export SCRIPT_DIR="${ROOT}"
out="$(
  bash "${ROOT}/profile.command" export-reg \
    profiles/steam/steam-22380-fallout-new-vegas.yaml test-snapshot 2>&1
)" || fail "export-reg failed: ${out}"

printf '%s' "${out}" | grep -q 'Captured' || fail "expected capture message"
[[ -f "${COSMOS_SUPPORT_DIR}/reg-snapshots/test-snapshot.user.reg" ]] \
  || fail "snapshot file missing"

printf 'OK: profile export-reg tests passed\n'
