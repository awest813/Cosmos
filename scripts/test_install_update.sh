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
case "$(uname -m)" in
  arm64) expected_asset='https://example.com/fixtures/Cosmos-macos-arm64.dmg' ;;
  *) expected_asset='https://example.com/fixtures/Cosmos.dmg' ;;
esac
printf '%s\n' "${out}" | grep -q "^asset=${expected_asset}$" || fail "expected fixture asset URL"

legacy_out="$(
  COSMOS_UPDATE_ASSET=Cosmos.dmg COSMOS_RELEASE_FIXTURE="${FIXTURE}" \
    "${ROOT}/scripts/install_update.sh" --dry-run 2>/dev/null
)" || legacy_rc=$?
legacy_rc=${legacy_rc:-0}
printf '%s\n' "${legacy_out}" | grep -q '^dry_run=1$' || fail "expected legacy dry_run=1 (rc=${legacy_rc})"
printf '%s\n' "${legacy_out}" | grep -q '^asset=https://example.com/fixtures/Cosmos.dmg$' \
  || fail "expected legacy fixture asset URL"

printf 'OK: install_update dry-run tests passed\n'
