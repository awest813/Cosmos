#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || fail "python3 required"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cosmosdb-comm.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

export SCRIPT_DIR="${ROOT}"
export COSMOS_REPO_ROOT="${ROOT}"
export COSMOSDB_DIR="${TMP}/CosmosDB"
export COSMOSDB_CACHE_DIR="${COSMOSDB_DIR}/cache"
mkdir -p "${COSMOSDB_CACHE_DIR}"

# shellcheck source=scripts/lib/cosmosdb_lib.sh
source "${ROOT}/scripts/lib/cosmosdb_lib.sh"

mode="$(cosmosdb_sync_community)" || fail "sync failed"
[[ "${mode}" == synced-bundled ]] || fail "expected synced-bundled, got ${mode}"
[[ -f "${COSMOSDB_DIR}/community/games/22380.json" ]] || fail "missing synced 22380"

entry="$(cosmosdb_read_community_entry 22380)" || fail "read community entry"
printf '%s' "${entry}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["schema"] == "cosmosdb-community-v0"
assert d["status"] == "gold"
'

badge="$(cosmosdb_badge_resolve 22380)" || fail "badge resolve"
printf '%s' "${badge}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["status"] == "playable", d
assert d["source"] == "profile"
'

badge2="$(cosmosdb_badge_resolve 1145360)" || fail "badge2"
printf '%s' "${badge2}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["status"] == "gold" and d["source"] == "profile", d
'

out="$(python3 "${ROOT}/scripts/cosmosdb_suggest_profile.py" 250900 --repo "${ROOT}" \
  --community-dir "${COSMOSDB_DIR}/community/games" 2>/dev/null)" || fail "suggest profile"
printf '%s' "${out}" | grep -q 'steam_appid: 250900' || fail "draft missing appid"
printf '%s' "${out}" | grep -q 'recommended_backend: dxmt' || fail "draft missing backend"

printf 'OK: cosmosdb community tests passed\n'
