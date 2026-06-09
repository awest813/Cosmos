#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/offline-rt.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

export OUTPUT_DIR="${TMP}/offline-runtime"
FIXTURE=1 bash "${ROOT}/scripts/stage_offline_runtime.command" \
  || fail "stage_offline_runtime failed"

[[ -f "${OUTPUT_DIR}/cosmos-runtime-offline.tar.xz" ]] \
  || fail "missing offline tarball"

export SCRIPT_DIR="${ROOT}"
export COSMOS_RUNTIME_DIR="${TMP}/runtime-cache"
export WINE_VERSION=11.8
export WINE_ROOT="${TMP}/wine-root"
export DXMT_VERSION=0.74
export DXMT_ROOT="${TMP}/dxmt-root"
export COSMOS_USE_BUNDLED_RUNTIME=1
export COSMOS_OFFLINE_RUNTIME_TARBALL="${OUTPUT_DIR}/cosmos-runtime-offline.tar.xz"

# shellcheck source=scripts/lib/runtime_lib.sh
source "${ROOT}/scripts/lib/runtime_lib.sh"

runtime_try_offline_stack || fail "runtime_try_offline_stack failed"
[[ -x "${WINE_ROOT}/Wine Devel.app/Contents/MacOS/wine/bin/wine" ]] \
  || fail "wine not installed from bundle"
[[ -f "${DXMT_ROOT}/x86_64-windows/d3d11.dll" ]] \
  || fail "dxmt not installed from bundle"

printf 'OK: offline runtime tests passed\n'
