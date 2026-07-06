#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/import_lib.sh
source "${ROOT}/scripts/lib/import_lib.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ "$(import_slugify 'My Cool Game!')" == "my-cool-game" ]] \
  || fail "slugify failed"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
file="$(import_write_config "${tmpdir}" "demo" "Demo Game" "com.cosmos.standalone-demo" "drive_c/Games/demo/game.exe")"
grep -q 'GAME_EXE_PATH="drive_c/Games/demo/game.exe"' "${file}" || fail "config missing exe path"
grep -q 'COSMOS_SKIP_STEAM="1"' "${file}" || fail "config missing skip steam"

fixture="${ROOT}/scripts/fixtures/legendary-installed.json"
path="$(printf '%s' "$(cat "${fixture}")" | python3 -c '
import json, sys
data = json.load(sys.stdin)
for entry in data:
    if entry.get("app_name", "").lower() == "sugar":
        print(entry.get("install_path", ""))
        break
' 2>/dev/null)"
[[ "${path}" == "/Users/tester/Games/SuperMeatBoy" ]] || fail "legendary JSON path parse failed"

epic_file="$(import_write_epic_config "${tmpdir}" "smb" "Super Meat Boy" "com.cosmos.epic-smb" "/Games/SMB.exe" "Sugar")"
grep -q 'LEGENDARY_APP_NAME="Sugar"' "${epic_file}" || fail "epic config missing legendary app name"

itch_file="$(import_write_itch_config "${tmpdir}" "demo" "Demo Game" "com.cosmos.itch-demo" "drive_c/Games/demo/game.exe")"
[[ "${itch_file}" == *"/itch-demo.conf" ]] || fail "itch config wrong filename"
grep -q 'GAME_EXE_PATH="drive_c/Games/demo/game.exe"' "${itch_file}" || fail "itch config missing exe path"

bnet_file="$(import_write_battlenet_config "${tmpdir}" "sc2" "StarCraft II" "com.cosmos.battlenet-sc2" \
  "drive_c/Program Files (x86)/StarCraft II/SC2.exe" \
  "drive_c/Program Files (x86)/Battle.net/Battle.net Launcher.exe")"
[[ "${bnet_file}" == *"/battlenet-sc2.conf" ]] || fail "battlenet config wrong filename"
grep -q 'BATTLENET_LAUNCHER_EXE=' "${bnet_file}" || fail "battlenet config missing launcher path"

bnet_fixture="${ROOT}/scripts/fixtures/battlenet_detection"
launcher="$(import_find_battlenet_launcher "${bnet_fixture}")"
[[ "${launcher}" == "drive_c/Program Files (x86)/Battle.net/Battle.net Launcher.exe" ]] \
  || fail "battlenet launcher detection failed: ${launcher}"

scan="$(import_scan_battlenet_games "${bnet_fixture}")"
printf '%s' "${scan}" | grep -q $'starcraft-ii\tStarCraft II\t' \
  || fail "battlenet game scan failed: ${scan}"

gog_fixture="${ROOT}/scripts/fixtures/gog_detection/wineprefix"
gog_exe="$(import_find_gog_game_exe "${gog_fixture}" "Celeste")"
[[ "${gog_exe}" == *"/Celeste/celeste.exe" ]] \
  || fail "gog exe finder failed: ${gog_exe}"

gog_scan="$(import_scan_gog_games "${gog_fixture}")"
printf '%s' "${gog_scan}" | grep -q $'celeste\tCeleste\t' \
  || fail "gog game scan failed: ${gog_scan}"

witcher_exe="$(import_find_gog_game_exe "${gog_fixture}" "The Witcher 3")"
[[ "${witcher_exe}" == *"/bin/x64/witcher3.exe" ]] \
  || fail "gog info metadata exe failed: ${witcher_exe}"

depth_exe="$(import_find_best_game_exe "${gog_fixture}/drive_c/GOG Games/Depth Test" "Depth Test")"
[[ "${depth_exe}" == *"/bin/x64/depth-test.exe" ]] \
  || fail "scored exe should prefer bin/x64 game: ${depth_exe}"

nested_exe="$(import_find_best_game_exe "${gog_fixture}/drive_c/GOG Games/Nested Game" "Nested Game")"
[[ "${nested_exe}" == *"/Nested Game/nested-game.exe" ]] \
  || fail "nested install folder exe failed: ${nested_exe}"

meta="$(import_describe_game_exe "${gog_fixture}/drive_c/GOG Games/The Witcher 3 Wild Hunt" "Witcher")"
printf '%s' "${meta}" | grep -q $'goggame-info' \
  || fail "describe should report goggame-info source: ${meta}"

gog_file="$(import_write_gog_config "${tmpdir}" "celeste" "Celeste" "com.cosmos.gog-celeste" \
  "drive_c/GOG Games/Celeste/celeste.exe")"
[[ "${gog_file}" == *"/gog-celeste.conf" ]] || fail "gog config wrong filename"
grep -q 'GAME_EXE_PATH="drive_c/GOG Games/Celeste/celeste.exe"' "${gog_file}" \
  || fail "gog config missing exe path"

import_exe_is_helper "uninstall.exe" || fail "uninstall should be helper"
import_exe_is_helper "vcredist_x64.exe" || fail "vcredist should be helper"
import_exe_is_helper "celeste.exe" && fail "celeste should not be helper"
import_exe_is_helper "bootstrap.exe" || fail "bootstrap should be helper"
import_exe_is_helper "vcredist_x64.exe" || fail "vcredist should be helper"

import_exe_has_pe_header "${gog_fixture}/drive_c/GOG Games/Celeste/celeste.exe" \
  || fail "celeste fixture should look like PE"
import_exe_has_pe_header "${gog_fixture}/drive_c/GOG Games/Celeste/redist/vcredist.exe" \
  || fail "vcredist fixture should look like PE"

# DX9 GOG game (Dragonshard): main .exe sits in the game root alongside GOG's
# uninstaller and a __redist/ tree holding the DirectX 9 / VC++ installers.
# Detection must pick the game and reject all the redist/helper noise.
dragonshard_dir="${gog_fixture}/drive_c/GOG Games/Dragonshard"
dragonshard_exe="$(import_find_best_game_exe "${dragonshard_dir}" "Dragonshard")"
[[ "${dragonshard_exe}" == *"/Dragonshard/Dragonshard.exe" ]] \
  || fail "dx9 gog game should resolve to root game exe: ${dragonshard_exe}"

dragonshard_scan="$(import_scan_gog_games "${gog_fixture}")"
printf '%s' "${dragonshard_scan}" | grep -q $'dragonshard\tDragonshard\tdrive_c/GOG Games/Dragonshard/Dragonshard.exe' \
  || fail "dx9 gog scan should list Dragonshard root exe: ${dragonshard_scan}"

import_exe_is_helper "unins000.exe" || fail "GOG unins000 should be helper"
import_exe_is_helper "DXSETUP.exe" || fail "DX9 DXSETUP should be helper"

# GOG stows redistributables under __redist/ (sibling of the existing __support);
# it must be treated as an ignored dir so non-helper-named installers under it
# (e.g. __redist/ISI/isi.exe) never become detection candidates.
import_path_is_ignored_dir "__redist" || fail "__redist should be an ignored dir"
import_path_has_ignored_segment "__redist/ISI/isi.exe" \
  || fail "exe under __redist should be ignored"

printf 'OK: import_lib tests passed\n'
