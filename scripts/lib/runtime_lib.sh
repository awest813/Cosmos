#!/usr/bin/env bash
# Cosmos Runtime manifest loader (roadmap 1.0).
# Pins Wine, DXMT, DXVK-macOS, and MoltenVK versions from runtime/cosmos-runtime.json.

RUNTIME_MANIFEST_PATH=""
RUNTIME_MANIFEST_VERSION=""
COSMOS_RUNTIME_DIR="${COSMOS_RUNTIME_DIR:-}"

runtime_manifest_path() {
  local root="${SCRIPT_DIR:-}"
  local candidate
  for candidate in \
    "${root}/runtime/cosmos-runtime.json" \
    "${root}/cosmos-runtime.json"; do
    [[ -f "${candidate}" ]] && {
      RUNTIME_MANIFEST_PATH="${candidate}"
      printf '%s' "${candidate}"
      return 0
    }
  done
  return 1
}

runtime_support_root() {
  printf '%s' "${COSMOS_SUPPORT_DIR:-$HOME/Library/Application Support/Cosmos}"
}

runtime_default_dir() {
  printf '%s/%s' "$(runtime_support_root)" "Runtime"
}

runtime_load_manifest() {
  local manifest
  manifest="$(runtime_manifest_path || true)"
  [[ -n "${manifest}" ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 0

  eval "$(python3 - "${manifest}" <<'PY'
import json, os, sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
comps = data.get("components") or {}

def emit(key, val):
    if val is None:
        return
    safe = str(val).replace("'", "'\\''")
    print(f"export {key}='{safe}'")

emit("RUNTIME_MANIFEST_LOADED", "1")
emit("RUNTIME_MANIFEST_VERSION", data.get("version", ""))
emit("RUNTIME_DXMT_MIT_MAX", (data.get("defaults") or {}).get("dxmt_mit_max_version", "0.80"))

wine = comps.get("wine") or {}
dxmt = comps.get("dxmt") or {}
dxvk = comps.get("dxvk_macos") or {}
mvk = comps.get("moltenvk") or {}

if wine.get("version") and not os.environ.get("WINE_VERSION"):
    emit("WINE_VERSION", wine["version"])
if wine.get("url") and not os.environ.get("WINE_URL"):
    emit("WINE_URL", wine["url"])

if dxmt.get("version") and not os.environ.get("DXMT_VERSION"):
    emit("DXMT_VERSION", dxmt["version"])
if dxmt.get("url") and not os.environ.get("DXMT_URL"):
    emit("DXMT_URL", dxmt["url"])

emit("RUNTIME_DXVK_VERSION", dxvk.get("version", ""))
emit("RUNTIME_DXVK_URL", dxvk.get("url", ""))
emit("RUNTIME_DXVK_SUBDIR", dxvk.get("install_subdir", "dxvk-macOS-{version}"))

emit("RUNTIME_MVK_VERSION", mvk.get("version", ""))
emit("RUNTIME_MVK_URL", mvk.get("url", ""))
emit("RUNTIME_MVK_SUBDIR", mvk.get("install_subdir", "MoltenVK-{version}"))
PY
)"

  if [[ -z "${COSMOS_RUNTIME_DIR}" ]]; then
    COSMOS_RUNTIME_DIR="$(runtime_default_dir)"
    export COSMOS_RUNTIME_DIR
  fi
}

runtime_assert_dxmt_license() {
  local ver="${DXMT_VERSION:-0.74}"
  local max="${RUNTIME_DXMT_MIT_MAX:-0.80}"
  [[ "${COSMOS_ALLOW_LGPL:-0}" == "1" ]] && return 0
  python3 - "${ver}" "${max}" <<'PY' || return 1
import sys

def parse(v):
    return tuple(int(x) for x in v.split("."))

cur, limit = parse(sys.argv[1]), parse(sys.argv[2])
if cur > limit:
    print(
        f"DXMT {sys.argv[1]} exceeds MIT pin (max {sys.argv[2]}). "
        "Set COSMOS_ALLOW_LGPL=1 after reviewing docs/LICENSING.md.",
        file=sys.stderr,
    )
    sys.exit(1)
PY
}

runtime_subdir_expand() {
  local template="$1" version="$2"
  printf '%s' "${template//\{version\}/${version}}"
}

runtime_find_icd_json() {
  local root="$1"
  local found
  found="$(find "${root}" -name 'MoltenVK_icd.json' 2>/dev/null | head -n1)"
  [[ -n "${found}" ]] || return 1
  printf '%s' "${found}"
}

runtime_prepare_moltenvk_env() {
  local ver="${RUNTIME_MVK_VERSION:-}"
  local url="${RUNTIME_MVK_URL:-}"
  [[ -n "${ver}" && -n "${url}" ]] || return 1

  local root="${COSMOS_RUNTIME_DIR:-$(runtime_default_dir)}"
  local subdir
  subdir="$(runtime_subdir_expand "${RUNTIME_MVK_SUBDIR:-MoltenVK-{version}}" "${ver}")"
  local dest="${root}/${subdir}"

  if [[ ! -f "${dest}/lib/libMoltenVK.dylib" && ! -f "${dest}/MoltenVK/dylib/libMoltenVK.dylib" ]]; then
    mkdir -p "${root}"
    local tmp
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/cosmos-mvk.XXXXXX")"
    echo "Downloading MoltenVK ${ver}..."
    curl -fsSL --retry 3 "${url}" -o "${tmp}/moltenvk.tar"
    rm -rf "${dest}"
    mkdir -p "${dest}"
    tar xf "${tmp}/moltenvk.tar" -C "${dest}"
    rm -rf "${tmp}"
  fi

  local icd libdir
  icd="$(runtime_find_icd_json "${dest}" || true)"
  [[ -n "${icd}" ]] || {
    echo "MoltenVK ICD json not found under ${dest}" >&2
    return 1
  }
  libdir="$(dirname "${icd}")"
  export VK_ICD_FILENAMES="${icd}"
  export DYLD_LIBRARY_PATH="${libdir}${DYLD_LIBRARY_PATH:+:${DYLD_LIBRARY_PATH}}"
  echo "MoltenVK ready at ${dest} (VK_ICD_FILENAMES=${icd})"
}

runtime_prepare_dxvk_path() {
  local ver="${RUNTIME_DXVK_VERSION:-}"
  local url="${RUNTIME_DXVK_URL:-}"
  [[ -n "${ver}" && -n "${url}" ]] || return 1

  local root="${COSMOS_RUNTIME_DIR:-$(runtime_default_dir)}"
  local subdir
  subdir="$(runtime_subdir_expand "${RUNTIME_DXVK_SUBDIR:-dxvk-macOS-{version}}" "${ver}")"
  local dest="${root}/${subdir}"

  if [[ ! -d "${dest}" ]] || ! find "${dest}" -name 'd3d11.dll' 2>/dev/null | grep -q .; then
    mkdir -p "${root}"
    local tmp
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/cosmos-dxvk.XXXXXX")"
    echo "Downloading DXVK-macOS ${ver}..."
    curl -fsSL --retry 3 "${url}" -o "${tmp}/dxvk.tar.gz"
    rm -rf "${dest}"
    mkdir -p "${dest}"
    tar xzf "${tmp}/dxvk.tar.gz" -C "${dest}"
    rm -rf "${tmp}"
  fi

  DXVK_PATH="${dest}"
  export DXVK_PATH
  echo "DXVK-macOS ready at ${DXVK_PATH}"
}

runtime_auto_fetch_dxvk_stack() {
  [[ "${COSMOS_AUTO_DXVK:-0}" == "1" ]] || return 0
  [[ -n "${DXVK_PATH:-}" ]] && return 0
  runtime_prepare_dxvk_path || return 1
  runtime_prepare_moltenvk_env || return 1
}
