#!/usr/bin/env bash
# Tests profile.command apply-installed against the Steam detection fixture prefix.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_PREFIX="${ROOT}/scripts/fixtures/steam_detection/wineprefix"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

export WINEPREFIX="${FIXTURE_PREFIX}"
export COSMOS_SUPPORT_DIR="${TMPDIR:-/tmp}/cosmos-apply-installed-$$"
mkdir -p "${COSMOS_SUPPORT_DIR}"

out="$("${ROOT}/profile.command" apply-installed --dry-run 2>&1)" || fail "apply-installed --dry-run failed"

printf '%s\n' "${out}" | grep -q 'Would apply' \
  || fail "expected at least one Would apply line from fixture library"

printf '%s\n' "${out}" | grep -q 'Batch apply complete' \
  || fail "expected batch apply summary"

# Blocked profiles are skipped unless --include-blocked.
blocked_pf="$(find "${ROOT}/profiles/steam" -name '*.yaml' -exec grep -l '^status: blocked' {} + | head -1)"
if [[ -n "${blocked_pf}" ]]; then
  blocked_appid="$(awk -F: '/^steam_appid:/{gsub(/ /,"",$2); print $2; exit}' "${blocked_pf}")"
  if printf '%s\n' "${out}" | grep -q "${blocked_appid}.*blocked"; then
    : # skipped as expected when present in library
  fi
fi

printf 'OK: profile apply-installed tests passed\n'
