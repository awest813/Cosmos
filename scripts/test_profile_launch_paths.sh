#!/usr/bin/env bash
# Resolve real launcher paths without starting Wine or touching user data.
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${TEST_DIR}/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
unset SCRIPT_DIR
export COSMOS_SUPPORT_DIR="${WORK}/support"
export COSMOS_BOTTLE=""
export COSMOS_LAUNCH_LOG="${WORK}/launch.log"
source "${REPO_ROOT}/run.command"

PROFILE_DIRECTORY="${WORK}/missing-profiles"
WINEPREFIX="${WORK}/selected-prefix"
WINE_BIN="fake-wine"
PROFILE_ARGS=("--name" "two words")
CAPTURED=()
run_launch_cmd() { CAPTURED=("$@"); }

mkdir -p "${WORK}/External Game" "${WINEPREFIX}/drive_c/GOG Games/Test"
touch "${WORK}/External Game/game.exe" "${WINEPREFIX}/drive_c/GOG Games/Test/game.exe"
PROFILE_EXECUTABLE="${WORK}/External Game/game.exe"
launch_profile
[[ "${CAPTURED[3]}" == "${PROFILE_EXECUTABLE}" ]]
[[ "${CAPTURED[4]}" == "--name" && "${CAPTURED[5]}" == "two words" ]]
echo 'PASS: absolute executable works without Profiles folder and preserves arguments'

PROFILE_EXECUTABLE="drive_c/GOG Games/Test/game.exe"
launch_profile
[[ "${CAPTURED[3]}" == "${WINEPREFIX}/${PROFILE_EXECUTABLE}" ]]
echo 'PASS: imported path resolves in selected prefix, including spaces'

mkdir -p "${PROFILE_DIRECTORY}/drive_c/GOG Games/Test"
touch "${PROFILE_DIRECTORY}/legacy.exe" "${PROFILE_DIRECTORY}/drive_c/GOG Games/Test/game.exe"
launch_profile
[[ "${CAPTURED[3]}" == "${WINEPREFIX}/${PROFILE_EXECUTABLE}" ]]
echo 'PASS: Windows paths never resolve to a different file in Profiles'

PROFILE_EXECUTABLE="legacy.exe"
launch_profile
[[ "${CAPTURED[3]}" == "${PROFILE_DIRECTORY}/legacy.exe" ]]
echo 'PASS: legacy relative profile paths still resolve'

PROFILE_EXECUTABLE="drive_c/GOG Games/Missing/game.exe"
if (launch_profile) >"${WORK}/missing.log" 2>&1; then
  echo 'FAIL: missing executable was accepted' >&2
  exit 1
fi
grep -q 'Profile executable not found' "${WORK}/missing.log"
echo 'PASS: missing executable fails with an actionable path error'
