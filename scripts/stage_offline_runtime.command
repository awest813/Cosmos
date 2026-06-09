#!/usr/bin/env bash
set -euo pipefail

# Stage Wine + DXMT offline bundle for DMG / Cosmos.app (roadmap 1.0).
#
# Usage:
#   scripts/stage_offline_runtime.command
#   FIXTURE=1 scripts/stage_offline_runtime.command   # CI stub (no network)
#   OUTPUT_DIR=build/offline-runtime scripts/stage_offline_runtime.command

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/build/offline-runtime}"
STAGING="${OUTPUT_DIR}/staging"
TARBALL="${OUTPUT_DIR}/cosmos-runtime-offline.tar.xz"
MANIFEST="${REPO_ROOT}/runtime/cosmos-runtime.json"

log() { printf "\n==> %s\n" "$1"; }
die() { printf "Error: %s\n" "$1" >&2; exit 1; }

[[ -f "${MANIFEST}" ]] || die "Missing ${MANIFEST}"
command -v python3 >/dev/null 2>&1 || die "python3 required"

eval "$(python3 - "${MANIFEST}" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
wine = data["components"]["wine"]
dxmt = data["components"]["dxmt"]
def q(s): return "'" + str(s).replace("'", "'\\''") + "'"
print(f"WINE_VERSION={q(wine['version'])}")
print(f"WINE_URL={q(wine['url'])}")
print(f"DXMT_VERSION={q(dxmt['version'])}")
print(f"DXMT_URL={q(dxmt['url'])}")
PY
)"

stage_fixture_bundle() {
  log "Staging fixture offline runtime (FIXTURE=1)"
  rm -rf "${STAGING}"
  mkdir -p "${STAGING}/wine-${WINE_VERSION}/Wine Devel.app/Contents/MacOS/wine/bin"
  mkdir -p "${STAGING}/dxmt-${DXMT_VERSION}/"{i386-windows,x86_64-windows,x86_64-unix}
  printf '#!/bin/sh\necho fixture-wine\n' > "${STAGING}/wine-${WINE_VERSION}/Wine Devel.app/Contents/MacOS/wine/bin/wine"
  chmod +x "${STAGING}/wine-${WINE_VERSION}/Wine Devel.app/Contents/MacOS/wine/bin/wine"
  touch "${STAGING}/dxmt-${DXMT_VERSION}/x86_64-windows/d3d11.dll"
  cp "${MANIFEST}" "${STAGING}/cosmos-runtime.json"
  printf 'fixture-offline-runtime\n' > "${STAGING}/.cosmos-offline-bundle"
}

stage_download_bundle() {
  [[ "$(uname -s)" == "Darwin" ]] || die "Downloading macOS Wine/DXMT requires Darwin (use FIXTURE=1 on Linux CI)"
  command -v curl >/dev/null 2>&1 || die "curl required"
  log "Downloading Wine ${WINE_VERSION}"
  rm -rf "${STAGING}"
  mkdir -p "${STAGING}/wine-${WINE_VERSION}"
  curl -fsSL --retry 3 "${WINE_URL}" | tar xJf - -C "${STAGING}/wine-${WINE_VERSION}"

  log "Downloading DXMT ${DXMT_VERSION}"
  local dxmt_tmp
  dxmt_tmp="$(mktemp -d "${TMPDIR:-/tmp}/cosmos-dxmt-stage.XXXXXX")"
  curl -fsSL --retry 3 "${DXMT_URL}" | tar xzf - -C "${dxmt_tmp}"
  mkdir -p "${STAGING}/dxmt-${DXMT_VERSION}"
  local payload="${dxmt_tmp}"
  if [[ -d "${dxmt_tmp}/v${DXMT_VERSION}/i386-windows" ]]; then
    payload="${dxmt_tmp}/v${DXMT_VERSION}"
  fi
  cp -R "${payload}/i386-windows" "${payload}/x86_64-windows" "${payload}/x86_64-unix" \
    "${STAGING}/dxmt-${DXMT_VERSION}/"
  rm -rf "${dxmt_tmp}"
  cp "${MANIFEST}" "${STAGING}/cosmos-runtime.json"
  printf 'offline-runtime\n' > "${STAGING}/.cosmos-offline-bundle"
}

if [[ "${FIXTURE:-0}" == "1" ]]; then
  stage_fixture_bundle
else
  stage_download_bundle
fi

log "Creating ${TARBALL}"
mkdir -p "${OUTPUT_DIR}"
rm -f "${TARBALL}"
tar -cJf "${TARBALL}" -C "${STAGING}" .
log "Offline runtime bundle: ${TARBALL} ($(du -h "${TARBALL}" | awk '{print $1}'))"
