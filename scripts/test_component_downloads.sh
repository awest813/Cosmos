#!/usr/bin/env bash
# Exercise component routing and interrupted-download recovery without networking.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
unset SCRIPT_DIR
export COSMOS_SUPPORT_DIR="${WORK}/support"
export COSMOS_BOTTLE=""
export COSMOS_LAUNCH_LOG="${WORK}/launch.log"
source "${ROOT}/run.command"

require_supported_macos() { :; }
ensure_wine_installed() { echo wine >>"${WORK}/calls"; }
ensure_dxmt_installed() { echo dxmt >>"${WORK}/calls"; }
# Preserve real download helpers for the failure tests below.
eval "$(declare -f runtime_prepare_dxvk_path | sed '1s/runtime_prepare_dxvk_path/real_dxvk/')"
eval "$(declare -f runtime_prepare_moltenvk_env | sed '1s/runtime_prepare_moltenvk_env/real_moltenvk/')"
runtime_prepare_dxvk_path() { echo dxvk >>"${WORK}/calls"; }
runtime_prepare_moltenvk_env() { echo moltenvk >>"${WORK}/calls"; }
prepare_steam_bottle() { echo 'FAIL: download prepared a game environment' >&2; exit 90; }
launch_steam() { echo 'FAIL: download launched Steam' >&2; exit 91; }
for component in wine dxmt recommended moltenvk dxvk; do
  : >"${WORK}/calls"
  main --download-component "${component}"
  case "${component}" in
    recommended) expected=$'wine\ndxmt' ;;
    dxvk) expected=$'dxvk\nmoltenvk' ;;
    *) expected="${component}" ;;
  esac
  [[ "$(cat "${WORK}/calls")" == "${expected}" ]]
done
echo 'PASS: component downloads call only requested installers'
for args in '--download-component' '--download-component unknown' '--download-component wine extra'; do
  if ( main ${args} ) >"${WORK}/error" 2>&1; then
    echo "FAIL: invalid arguments accepted: ${args}" >&2
    exit 1
  fi
done
echo 'PASS: missing, unknown and extra arguments rejected'

export COSMOS_RUNTIME_DIR="${WORK}/runtime"
RUNTIME_DXVK_VERSION=test
RUNTIME_DXVK_URL=https://invalid.example/dxvk
RUNTIME_DXVK_SUBDIR=dxvk-test
RUNTIME_MVK_VERSION=test
RUNTIME_MVK_URL=https://invalid.example/mvk
RUNTIME_MVK_SUBDIR=mvk-test
mkdir -p "${COSMOS_RUNTIME_DIR}/dxvk-test" "${COSMOS_RUNTIME_DIR}/mvk-test"
touch "${COSMOS_RUNTIME_DIR}/dxvk-test/existing" "${COSMOS_RUNTIME_DIR}/mvk-test/existing"
curl() { return 22; }
if real_dxvk; then echo 'FAIL: failed DXVK download reported success'; exit 1; fi
if real_moltenvk; then echo 'FAIL: failed MoltenVK download reported success'; exit 1; fi
[[ -f "${COSMOS_RUNTIME_DIR}/dxvk-test/existing" && -f "${COSMOS_RUNTIME_DIR}/mvk-test/existing" ]]
echo 'PASS: failed downloads preserve existing files and report failure'

# A successful HTTP response with a valid but wrong archive must also fail.
mkdir -p "${WORK}/empty"
tar czf "${WORK}/wrong.tar.gz" -C "${WORK}/empty" .
curl() {
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == -o ]]; then cp "${WORK}/wrong.tar.gz" "$2"; return; fi
    shift
  done
  return 1
}
if real_dxvk; then echo 'FAIL: empty DXVK archive accepted'; exit 1; fi
if real_moltenvk; then echo 'FAIL: empty MoltenVK archive accepted'; exit 1; fi
echo 'PASS: incomplete archives are rejected before replacing components'

mkdir -p "${COSMOS_RUNTIME_DIR}/dxvk-test/x64" "${COSMOS_RUNTIME_DIR}/mvk-test/MoltenVK/dylib/macOS"
touch "${COSMOS_RUNTIME_DIR}/dxvk-test/x64/d3d11.dll"
touch "${COSMOS_RUNTIME_DIR}/mvk-test/MoltenVK/dylib/macOS/libMoltenVK.dylib"
touch "${COSMOS_RUNTIME_DIR}/mvk-test/MoltenVK/dylib/macOS/MoltenVK_icd.json"
curl() { echo 'FAIL: downloaded an existing component' >&2; exit 92; }
real_dxvk
real_moltenvk
echo 'PASS: existing components are reused, including nested MoltenVK archives'
