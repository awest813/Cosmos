#!/usr/bin/env bash
# Build SpockD3D9 experimental Windows PE d3d9.dll into the Cosmos Runtime directory.
#
# Clones https://github.com/awest813/SpockD3D9 when needed and delegates to the
# upstream cross-compile script. Requires meson, ninja, mingw-w64, and glslang.
#
# Output layout (SPOCK_D3D9_PATH):
#   <runtime>/spockd3d9/x86/d3d9.dll
#   <runtime>/spockd3d9/x64/d3d9.dll

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/spockd3d9_lib.sh
source "${ROOT}/scripts/lib/spockd3d9_lib.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/build-pe-d3d9.sh [--arch x86|x64|both] [--wipe] [--src DIR]

Build SpockD3D9 PE d3d9.dll for Wine/Cosmos hosting.

Options:
  --arch ARCH   Target architecture: x86 (32-bit games), x64, or both (default).
  --wipe        Remove the SpockD3D9 source build directories before configuring.
  --src DIR     Use an existing SpockD3D9 checkout instead of cloning.
EOF
}

arch="both"
wipe=0
src_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch) shift; arch="${1:-}" ;;
    --arch=*) arch="${1#*=}" ;;
    --wipe) wipe=1 ;;
    --src) shift; src_dir="${1:-}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

case "${arch}" in
  x86|x64|both) ;;
  *) echo "error: --arch must be x86, x64, or both (got: ${arch})" >&2; exit 1 ;;
esac

for tool in meson ninja; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "error: ${tool} is required. Install with: brew install meson ninja mingw-w64 glslang" >&2
    exit 1
  }
done

if ! command -v glslangValidator >/dev/null 2>&1 && ! command -v glslang >/dev/null 2>&1; then
  echo "error: glslangValidator (glslang) is required." >&2
  exit 1
fi

cache_root="${ROOT}/.cache/spockd3d9-src"
if [[ -n "${src_dir}" ]]; then
  [[ -d "${src_dir}" ]] || { echo "error: --src directory not found: ${src_dir}" >&2; exit 1; }
  spock_src="${src_dir}"
else
  spock_src="${cache_root}/SpockD3D9"
  if [[ ! -d "${spock_src}/.git" ]]; then
    mkdir -p "${cache_root}"
    echo "Cloning SpockD3D9..."
    git clone --depth 1 https://github.com/awest813/SpockD3D9.git "${spock_src}"
  fi
fi

[[ -f "${spock_src}/scripts/build-pe-d3d9.sh" ]] || {
  echo "error: SpockD3D9 checkout missing scripts/build-pe-d3d9.sh at ${spock_src}" >&2
  exit 1
}

build_args=()
[[ "${wipe}" -eq 1 ]] && build_args+=(--wipe)
case "${arch}" in
  x86) build_args+=(--arch x86) ;;
  x64) build_args+=(--arch x64) ;;
  both) build_args+=(--arch both) ;;
esac

echo "Building SpockD3D9 PE d3d9.dll from ${spock_src}..."
bash "${spock_src}/scripts/build-pe-d3d9.sh" "${build_args[@]}"

dest_root="$(spockd3d9_default_root)"
mkdir -p "${dest_root}/x86" "${dest_root}/x64"

if [[ -f "${spock_src}/build-pe-d3d9-x86/d3d9.dll" ]]; then
  cp -f "${spock_src}/build-pe-d3d9-x86/d3d9.dll" "${dest_root}/x86/d3d9.dll"
  echo "Installed ${dest_root}/x86/d3d9.dll"
fi
if [[ -f "${spock_src}/build-pe-d3d9/d3d9.dll" ]]; then
  cp -f "${spock_src}/build-pe-d3d9/d3d9.dll" "${dest_root}/x64/d3d9.dll"
  echo "Installed ${dest_root}/x64/d3d9.dll"
fi

export SPOCK_D3D9_PATH="${dest_root}"
echo ""
echo "SpockD3D9 PE DLLs ready at ${dest_root}"
echo "Set SPOCK_D3D9_PATH=${dest_root} or use COSMOS_BACKEND=spockd3d9."
