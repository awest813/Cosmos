#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/sync_lib.sh
source "${ROOT}/scripts/lib/sync_lib.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

unset COSMOS_SYNC_MODE WINEESYNC WINEMSYNC
cosmos_sync_mode_apply
[[ -z "${WINEESYNC:-}" && -z "${WINEMSYNC:-}" ]] || fail "off mode should clear sync vars"

export COSMOS_SYNC_MODE=esync
cosmos_sync_mode_apply
[[ "${WINEESYNC:-}" == "1" ]] || fail "esync should set WINEESYNC=1"
[[ -z "${WINEMSYNC:-}" ]] || fail "esync should unset WINEMSYNC"

unset WINEESYNC WINEMSYNC
export COSMOS_SYNC_MODE=msync
cosmos_sync_mode_apply
[[ "${WINEMSYNC:-}" == "1" ]] || fail "msync should set WINEMSYNC=1"
[[ -z "${WINEESYNC:-}" ]] || fail "msync should unset WINEESYNC"

unset COSMOS_SYNC_MODE WINEESYNC WINEMSYNC
export WINEESYNC=1
cosmos_sync_mode_from_legacy
[[ "${COSMOS_SYNC_MODE}" == "esync" ]] || fail "legacy WINEESYNC should infer esync"

printf 'OK: sync_lib tests passed\n'
