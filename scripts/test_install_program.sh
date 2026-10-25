#!/usr/bin/env bash
# Verify install/folder/game sequencing with real bottle/port code and fake Wine.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
export COSMOS_ROOT="${tmp}/runtime"
export COSMOS_SUPPORT_DIR="${tmp}/support"
export COSMOS_PORTS_OUTPUT="${tmp}/apps"
export COSMOS_PORT_SKIP_ARCH=1
export TEST_EVENTS="${tmp}/events"
export TEST_GAME_FIXTURE="${tmp}/SC3U.exe"
unset SCRIPT_DIR COSMOS_BOTTLES_DIR COSMOS_PORTS_DIR COSMOS_BOTTLE WINEPREFIX
mkdir -p "${COSMOS_ROOT}/scripts/lib"
cp "${ROOT}/bottle.command" "${ROOT}/port.command" "${COSMOS_ROOT}/"
cp "${ROOT}/scripts/lib/port_lib.sh" "${ROOT}/scripts/lib/prefix_arch.sh" \
   "${ROOT}/scripts/lib/import_lib.sh" "${COSMOS_ROOT}/scripts/lib/"
cat > "${COSMOS_ROOT}/run.command" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
[[ "${COSMOS_BACKEND}" == wined3d && "${COSMOS_SKIP_STEAM}" == 1 ]] || exit 90
prefix="${COSMOS_SUPPORT_DIR}/Bottles/${COSMOS_BOTTLE}/prefix"
if [[ "$1" == --run-installer ]]; then
  echo "installer:$2" >> "${TEST_EVENTS}"
  mkdir -p "${prefix}"
  printf 'WINE REGISTRY Version 2\n#arch=win64\n' > "${prefix}/system.reg"
  [[ "${TEST_INSTALL_FAIL:-0}" == 0 ]] || exit 42
  mkdir -p "${TEST_GAME_DIR}/Apps"
  cp "${TEST_GAME_FIXTURE}" "${TEST_GAME_DIR}/Apps/SC3U.exe"
elif [[ "$1" == --game ]]; then
  [[ "${COSMOS_PROGRAM_ARCH}" == win32 ]] || exit 91
  echo "game:$2" >> "${TEST_EVENTS}"
else
  exit 92
fi
FAKE
chmod +x "${COSMOS_ROOT}/run.command"
python3 - "${TEST_GAME_FIXTURE}" <<'PY'
import struct, sys
from pathlib import Path
data = bytearray(1024)
data[:2] = b'MZ'
struct.pack_into('<I', data, 60, 128)
data[128:132] = b'PE\0\0'
struct.pack_into('<HHIIIHH', data, 132, 0x14c, 1, 0, 0, 0, 224, 0x102)
struct.pack_into('<H', data, 152, 0x10b)
struct.pack_into('<H', data, 220, 2)
Path(sys.argv[1]).write_bytes(data)
PY
installer="${tmp}/setup SimCity 3000.exe"
cp "${TEST_GAME_FIXTURE}" "${installer}"
workflow="${ROOT}/scripts/install_program.command"
prefix="${COSMOS_SUPPORT_DIR}/Bottles/game-simcity-3000-unlimited/prefix"
export TEST_GAME_DIR="${prefix}/drive_c/Games/simcity-3000-unlimited"
"${workflow}" prepare --name "SimCity 3000 Unlimited" > "${tmp}/prepare.log"
[[ -d "${TEST_GAME_DIR}" && ! -e "${TEST_EVENTS}" ]] || fail "prepare must not run an EXE"
"${workflow}" install "${installer}" --name "SimCity 3000 Unlimited" \
  --install-dir drive_c/Games/simcity-3000-unlimited \
  --game-exe drive_c/Games/simcity-3000-unlimited/Apps/SC3U.exe > "${tmp}/install.log"
[[ "$(sed -n '1p' "${TEST_EVENTS}")" == "installer:${installer}" ]] || fail "installer must run first"
[[ "$(sed -n '2p' "${TEST_EVENTS}")" == "game:${TEST_GAME_DIR}/Apps/SC3U.exe" ]] || fail "installed SC3U must run second"
grep -Fq 'Windows destination: C:\Games\simcity-3000-unlimited' "${tmp}/install.log" || fail "C: mapping"
conf="${COSMOS_SUPPORT_DIR}/Ports/simcity-3000-unlimited/port.conf"
grep -q 'PORT_BOTTLE="game-simcity-3000-unlimited"' "${conf}" || fail "port must retain its environment"
grep -q 'PORT_PROGRAM_ARCH="win32"' "${conf}" || fail "SC3U must be detected as 32-bit"
grep -q 'PORT_PRIMARY="wined3d"' "${conf}" || fail "baseline must be WineD3D"

if "${workflow}" install "${installer}" --name "SimCity 3000 Unlimited" --install-dir "${TEST_GAME_DIR}" --game-exe "${TEST_GAME_DIR}/Apps/SC3U.exe" >/dev/null 2>&1; then
  fail "duplicate port must not reinstall"
fi
[[ "$(wc -l < "${TEST_EVENTS}" | tr -d ' ')" == 2 ]] || fail "duplicate attempt ran an EXE"

export TEST_GAME_DIR="${tmp}/Chosen Game Folder"
if TEST_INSTALL_FAIL=1 "${workflow}" install "${installer}" --name "Failed Install" \
  --install-dir "${TEST_GAME_DIR}" --game-exe "${TEST_GAME_DIR}/Apps/SC3U.exe" >"${tmp}/failed.log" 2>&1; then
  fail "installer failure must stop the workflow"
fi
[[ ! -e "${COSMOS_SUPPORT_DIR}/Ports/failed-install" ]] || fail "failed installation registered a game"

# Preserve installation after a wrong file choice; resume must not rerun setup.
if "${workflow}" install "${installer}" --name "Resume SimCity" --install-dir "${TEST_GAME_DIR}" \
  --game-exe "${TEST_GAME_DIR}/missing.exe" > "${tmp}/selection.log" 2>&1; then
  fail "missing game must stop registration"
fi
[[ -f "${TEST_GAME_DIR}/Apps/SC3U.exe" ]] || fail "installation must survive failed selection"
before="$(wc -l < "${TEST_EVENTS}")"
"${workflow}" resume --name "Resume SimCity" \
  --game-exe "Apps/SC3U.exe" --no-launch > "${tmp}/resume.log"
[[ "$(wc -l < "${TEST_EVENTS}")" == "${before}" ]] || fail "resume/no-launch must not run setup or game"
grep -Fq 'Windows destination: Z:' "${tmp}/resume.log" || fail "Mac folder must map through Z:"
[[ -f "${COSMOS_SUPPORT_DIR}/Ports/resume-simcity/port.conf" ]] || fail "resume registration missing"

# Recovery must not silently create an empty replacement for a disconnected drive.
export TEST_GAME_DIR="${tmp}/Disconnected Game Drive"
if "${workflow}" install "${installer}" --name "Disconnected" --install-dir "${TEST_GAME_DIR}" \
  --game-exe missing.exe >"${tmp}/disconnect-install.log" 2>&1; then
  fail "missing game must stop registration"
fi
mv "${TEST_GAME_DIR}" "${TEST_GAME_DIR}-offline"
before="$(wc -l < "${TEST_EVENTS}")"
if "${workflow}" resume --name "Disconnected" --game-exe Apps/SC3U.exe >"${tmp}/disconnect-resume.log" 2>&1; then
  fail "unavailable saved folder must stop recovery"
fi
grep -Fq 'saved installation folder is unavailable' "${tmp}/disconnect-resume.log" || fail "missing folder recovery message"
[[ ! -e "${TEST_GAME_DIR}" ]] || fail "recovery created an empty replacement folder"
[[ "$(wc -l < "${TEST_EVENTS}")" == "${before}" ]] || fail "disconnected recovery ran an EXE"
"${workflow}" resume --name "Disconnected" --install-dir "${TEST_GAME_DIR}-offline" \
  --game-exe Apps/SC3U.exe --no-launch >"${tmp}/relocated.log"
export TEST_GAME_DIR="${tmp}/Chosen Game Folder"

cp "${TEST_GAME_FIXTURE}" "${TEST_GAME_DIR}/setup.exe"
if "${workflow}" resume --name "Wrong Game" --bottle game-resume-simcity \
  --install-dir "${TEST_GAME_DIR}" --game-exe setup.exe >"${tmp}/wrong-game.log" 2>&1; then
  fail "installed-executable selection must reject setup helpers"
fi
[[ ! -e "${COSMOS_SUPPORT_DIR}/Ports/wrong-game" ]] || fail "setup helper was registered"
if "${workflow}" resume --name "Wrong Folder" --bottle game-resume-simcity \
  --install-dir "${tmp}/Other Folder" --game-exe "${TEST_GAME_DIR}/Apps/SC3U.exe" >"${tmp}/wrong-folder.log" 2>&1; then
  fail "game selection outside the chosen folder must stop"
fi
[[ ! -e "${COSMOS_SUPPORT_DIR}/Ports/wrong-folder" ]] || fail "wrong folder registered a game"

echo 'OK: installer -> chosen folder -> installed game, dedicated environment, failure and resume checks passed'
