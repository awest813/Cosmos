#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'SKIP: install_update tests require macOS\n'
  exit 0
fi

out="$("${ROOT}/scripts/install_update.sh" --dry-run 2>&1)" || rc=$?
rc=${rc:-0}
if printf '%s\n' "${out}" | grep -q '^dry_run=1$'; then
  printf '%s\n' "${out}" | grep -q '^asset=https://' || fail "expected asset URL"
elif printf '%s\n' "${out}" | grep -qi 'No .* asset found\|Could not reach\|curl'; then
  printf 'SKIP: install_update dry-run (no published Cosmos.dmg yet or offline)\n'
  exit 0
else
  fail "unexpected install_update dry-run output (rc=${rc})"
fi

printf 'OK: install_update dry-run tests passed\n'
