#!/usr/bin/env bash
set -euo pipefail

# Unit tests for scripts/lib/cosmosdb_lib.sh parsers (no network).

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="${ROOT}/scripts/fixtures/cosmosdb"
COSMOSDB_CACHE_DIR="${TMPDIR:-/tmp}/cosmosdb-test-cache-$$"
mkdir -p "${COSMOSDB_CACHE_DIR}"
trap 'rm -rf "${COSMOSDB_CACHE_DIR}"' EXIT

# shellcheck source=scripts/lib/cosmosdb_lib.sh
source "${ROOT}/scripts/lib/cosmosdb_lib.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || fail "python3 required"

agw_out="$(cosmosdb_agw_parse_fixture 22380 "${FIX}/agw_fallout_new_vegas.wikitext")"
printf '%s' "${agw_out}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["source"] == "applegamingwiki"
assert d["steam_appid"] == 22380
assert d["compatibility"]["crossover"] == "playable"
assert d["compatibility"]["wine"] == "playable"
assert "sluggish" in d["notes"]["crossover"]
'

mgd_out="$(cosmosdb_macgamingdb_parse_fixture 1145360 "${FIX}/macgamingdb_1145360.json")"
printf '%s' "${mgd_out}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["source"] == "macgamingdb"
assert d["title"] == "Hades"
assert d["aggregated_performance"] == "EXCELLENT"
assert d["methods"]["crossover"] == 2
assert d["translation_layers"]["dxmt"] == 1
assert d["translation_layers"]["d3d_metal"] == 1
'

# Side-appid match (listed in steam appid side)
side_fixture="$(mktemp)"
cat > "${side_fixture}" <<'EOF'
Some DLC
|steam appid = 99999
|steam appid side = 22380,88888
{{Compatibility/macOS
|wine = perfect
|wine notes = Side app id entry.
}}
EOF
side_out="$( { printf '%s\n' 'Some DLC'; printf '%s\n' '---WIKITEXT---'; tail -n +2 "${side_fixture}"; } | cosmosdb_agw_parse_wikitext 22380)"
printf '%s' "${side_out}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["compatibility"]["wine"] == "perfect"
'
rm -f "${side_fixture}"

# Reject wrong main appid when not in side list
bad_fixture="$(mktemp)"
printf '|steam appid = 1\n|wine = broken\n' > "${bad_fixture}"
if { printf 'Wrong\n---WIKITEXT---\n'; cat "${bad_fixture}"; } | cosmosdb_agw_parse_wikitext 22380 >/dev/null 2>&1; then
  fail "expected parse rejection for mismatched appid"
fi
rm -f "${bad_fixture}"

umu_out="$(cosmosdb_umu_parse_fixture 1091500 "${FIX}/umu_1091500.json")"
printf '%s' "${umu_out}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["source"] == "umu"
assert d["umu_id"] == "umu-1091500"
assert d["has_fix_database_entry"] is True
assert d["title"] == "Cyberpunk 2077"
assert len(d["store_entries"]) == 2
'

empty_umu="$(printf '[]' | cosmosdb_normalize_umu 999999)"
printf '%s' "${empty_umu}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["has_fix_database_entry"] is False
'

printf 'OK: cosmosdb_lib tests passed\n'
