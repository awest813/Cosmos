#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="${ROOT}/scripts/fixtures/github_release_latest.json"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "${FIXTURE}" ]] || fail "missing fixture ${FIXTURE}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'SKIP: install_update install path requires macOS\n'
  exit 0
fi

out="$(
  COSMOS_RELEASE_FIXTURE="${FIXTURE}" "${ROOT}/scripts/install_update.sh" --dry-run 2>/dev/null
)" || rc=$?
rc=${rc:-0}
printf '%s\n' "${out}" | grep -q '^dry_run=1$' || fail "expected dry_run=1 (rc=${rc})"
printf '%s\n' "${out}" | grep -q '^asset=https://example.com/fixtures/Cosmos.dmg$' || fail "expected fixture asset URL"

printf 'OK: install_update dry-run tests passed\n'
