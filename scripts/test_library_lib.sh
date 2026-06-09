#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_PREFIX="${ROOT}/scripts/fixtures/steam_detection/wineprefix"

# shellcheck source=scripts/lib/steam_lib.sh
source "${ROOT}/scripts/lib/steam_lib.sh"
# shellcheck source=scripts/lib/library_lib.sh
source "${ROOT}/scripts/lib/library_lib.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
export COSMOS_SUPPORT_DIR="${tmpdir}/CosmosSupport"

# --- install path helpers ---
rel="$(library_games_root_rel)"
[[ "${rel}" == "drive_c/Games" ]] || fail "games root rel wrong: ${rel}"

install="$(library_install_dir "${tmpdir}/prefix" "itch" "my-game")"
[[ "${install}" == *"/drive_c/Games/itch/my-game" ]] \
  || fail "install dir wrong: ${install}"

rel_install="$(library_install_dir_rel "standalone" "demo")"
[[ "${rel_install}" == "drive_c/Games/standalone/demo" ]] \
  || fail "rel install dir wrong: ${rel_install}"

library_ensure_dirs "${tmpdir}/prefix"
[[ -d "${tmpdir}/prefix/drive_c/Games" ]] || fail "ensure_dirs did not create Games root"
[[ -d "$(library_dir)" ]] || fail "ensure_dirs did not create library dir"

# --- config parsing ---
configs="${tmpdir}/configs"
mkdir -p "${configs}"
cat > "${configs}/itch-demo.conf" <<'EOF'
APP_NAME="Demo Game (Cosmos)"
GAME_EXE_PATH="drive_c/Games/itch/demo/game.exe"
EOF
cat > "${configs}/steam-570-dota-2.conf" <<'EOF'
APP_NAME="Dota 2 (Cosmos)"
STEAM_GAME_ID="570"
GAME_EXE_PATH=""
EOF

store="$(library_store_from_conf_basename "itch-demo.conf")"
[[ "${store}" == "itch" ]] || fail "store from conf: ${store}"

slug="$(library_slugify 'My Cool Game!')"
[[ "${slug}" == "my-cool-game" ]] || fail "slugify: ${slug}"

rows="$(library_collect_from_configs "${configs}" "${FIXTURE_PREFIX}")"
printf '%s' "${rows}" | grep -q $'\titch\tDemo Game\t' \
  || fail "collect itch config failed: ${rows}"
printf '%s' "${rows}" | grep -q $'\tsteam\tDota 2\t' \
  || fail "collect steam config failed: ${rows}"

# --- steam-only detection from fixture prefix ---
WINEPREFIX="${FIXTURE_PREFIX}"
steam_rows="$(library_collect_steam_only "${FIXTURE_PREFIX}" "${configs}")"
printf '%s' "${steam_rows}" | grep -q $'\tsteam\t' \
  || fail "steam-only collect failed: ${steam_rows}"

# --- JSON manifest ---
json="$(library_emit_json "${configs}" "${FIXTURE_PREFIX}" "test-bottle")"
printf '%s' "${json}" | python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["version"] == 1
assert data["bottle"] == "test-bottle"
assert data["prefix"] == sys.argv[1]
assert len(data["games"]) >= 2
stores = {g["store"] for g in data["games"]}
assert "itch" in stores
assert "steam" in stores
' "${FIXTURE_PREFIX}" || fail "json emit failed"

manifest="$(library_write_manifest "${configs}" "${FIXTURE_PREFIX}" "test-bottle")"
[[ -f "${manifest}" ]] || fail "manifest not written"
count="$(python3 -c 'import json, sys; print(len(json.load(open(sys.argv[1])).get("games",[])))' "${manifest}")"
(( count >= 2 )) || fail "manifest game count: ${count}"

# --- install path resolution for steam fixture ---
install_path="$(library_resolve_install_path "${FIXTURE_PREFIX}" "steam" "570" "" "${configs}/steam-570-dota-2.conf")"
[[ -n "${install_path}" ]] || fail "steam install path empty"
[[ -d "${install_path}" ]] || fail "steam install path not a dir: ${install_path}"

printf 'OK: library_lib tests passed\n'
