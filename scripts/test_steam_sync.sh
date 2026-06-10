#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_PREFIX="${ROOT}/scripts/fixtures/steam_detection/wineprefix"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

support="${TMPDIR:-/tmp}/cosmos-steam-sync-$$"
export COSMOS_SUPPORT_DIR="${support}"
export WINEPREFIX="${FIXTURE_PREFIX}"
mkdir -p "${support}"

json="$(
  "${ROOT}/detect_steam_games.command" --list --json 2>/dev/null
)" || fail "fixture --list --json failed"
printf '%s\n' "${json}" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d, list) and len(d) >= 1'

printf '999\n' > "${support}/steam-library.snapshot"

out="$(
  COSMOS_SYNC_DRY_RUN=1 COSMOS_ALLOW_USER_APPS=1 \
    "${ROOT}/detect_steam_games.command" --sync 2>/dev/null
)" || fail "fixture --sync failed"
printf '%s\n' "${out}" | grep -q '^sync_status=updated$' || fail "expected sync_status=updated"
printf '%s\n' "${out}" | grep -q '^sync_new=' || fail "expected sync_new count"

rm -rf "${support}"
printf 'OK: steam sync tests passed\n'
