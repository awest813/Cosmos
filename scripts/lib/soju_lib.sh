#!/usr/bin/env bash
# Store-launcher fixes documented by Soju (https://github.com/BCD1210/soju).
#
# Soju is GPL-3.0. This file does not include its source. It reimplements four
# facts about launching Battle.net, Epic, and GOG on Apple Silicon:
#   - Rosetta must advertise AVX or some loaders wait forever
#   - Battle.net's login page needs Wine's writecopy simulation
#   - D3DMetal engages only when its Metal library, Windows shims, and unix
#     symlinks are all installed, and those unix files must be symlinks
#   - macOS drops DYLD_* variables when the launch goes through nohup or arch
#   - Battle.net checks the caller's signature against a copy of Battle.net.exe
#     in the versioned folder it was started from (error BLZBNTBNA00000005)
#
# Apple's D3DMetal and CodeWeavers' Wine are not redistributed.

SOJU_GPTK_SHIMS="d3d11 d3d12 dxgi"
SOJU_GPTK_OPTIONAL_SHIMS="d3d10 atidxx64 nvapi64 nvngx"

soju_host_arch() {
  if [[ -n "${COSMOS_HOST_ARCH:-}" ]]; then
    printf '%s' "${COSMOS_HOST_ARCH}"
    return 0
  fi
  uname -m
}

soju_store_client() {
  case "${COSMOS_STORE:-}" in
    battlenet|epic|gog)
      printf '%s' "${COSMOS_STORE}"
      return 0
      ;;
  esac
  if [[ -n "${BATTLENET_LAUNCHER_EXE:-}" ]]; then
    printf '%s' "battlenet"
    return 0
  fi
  if [[ -n "${LEGENDARY_APP_NAME:-}" ]]; then
    printf '%s' "epic"
    return 0
  fi
  printf '%s' ""
}

# Leave an explicit ROSETTA_ADVERTISE_AVX value alone.
# COSMOS_ROSETTA_AVX: auto (default, on for arm64), on, off.
soju_apply_rosetta_avx() {
  [[ -n "${ROSETTA_ADVERTISE_AVX:-}" ]] && return 0
  case "${COSMOS_ROSETTA_AVX:-auto}" in
    off|0) return 0 ;;
    on|1)
      export ROSETTA_ADVERTISE_AVX=1
      ;;
    auto)
      case "$(soju_host_arch)" in
        arm64|aarch64) export ROSETTA_ADVERTISE_AVX=1 ;;
      esac
      ;;
  esac
  return 0
}

# Battle.net, Epic, and GOG login pages need this. Steam stays unchanged.
# An explicit WINE_SIMULATE_WRITECOPY value wins.
# COSMOS_WINE_WRITECOPY: auto (default), on, off.
soju_apply_writecopy() {
  [[ -n "${WINE_SIMULATE_WRITECOPY:-}" ]] && return 0
  case "${COSMOS_WINE_WRITECOPY:-auto}" in
    off|0) return 0 ;;
    on|1)
      export WINE_SIMULATE_WRITECOPY=1
      ;;
    auto)
      case "$(soju_store_client)" in
        battlenet|epic|gog) export WINE_SIMULATE_WRITECOPY=1 ;;
      esac
      ;;
  esac
  return 0
}

soju_apply_launch_env() {
  soju_apply_rosetta_avx
  soju_apply_writecopy
}

soju_wine_lib_dir() {
  local bin=""
  if [[ -n "${COSMOS_WINE_LIB:-}" ]]; then
    printf '%s' "${COSMOS_WINE_LIB}"
    return 0
  fi
  if declare -F wine_resolve_bin >/dev/null 2>&1; then
    bin="$(wine_resolve_bin)"
  elif [[ -n "${WINE_BIN:-}" ]]; then
    bin="${WINE_BIN}"
  fi
  [[ -n "${bin}" ]] || return 1
  local parent
  parent="$(cd "$(dirname -- "${bin}")/.." 2>/dev/null && pwd)" || return 1
  printf '%s' "${parent}/lib"
}

soju_gptk_payload_dir() {
  if [[ -n "${COSMOS_GPTK_PAYLOAD:-}" ]]; then
    printf '%s' "${COSMOS_GPTK_PAYLOAD}"
    return 0
  fi
  local root="${1:-${GPTK_PATH:-}}"
  [[ -n "${root}" ]] || return 1
  local candidate
  for candidate in \
    "${root}" \
    "${root}/lib/external" \
    "${root}/redist/lib/external" \
    "${root}/Contents/Resources/wine/lib/external"
  do
    if [[ -f "${candidate}/libd3dshared.dylib" && -d "${candidate}/D3DMetal.framework" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  return 1
}

soju_gptk_pe_dir() {
  local payload="$1"
  local sibling
  sibling="$(cd "${payload}/.." 2>/dev/null && pwd)/wine/x86_64-windows"
  if [[ -d "${sibling}" ]]; then
    printf '%s' "${sibling}"
    return 0
  fi
  if [[ -d "${payload}/wine/x86_64-windows" ]]; then
    printf '%s' "${payload}/wine/x86_64-windows"
    return 0
  fi
  return 1
}

soju_shim_link_ok() {
  local path="$1" target
  [[ -L "${path}" ]] || return 1
  target="$(readlink "${path}")"
  case "${target}" in
    *libd3dshared.dylib) return 0 ;;
  esac
  return 1
}

soju_gptk_layout_status() {
  local payload="" wine_lib="" pe_src="" external=0 pe=0 links=0 copied=0
  local layout="missing" message name
  payload="$(soju_gptk_payload_dir 2>/dev/null || true)"
  wine_lib="$(soju_wine_lib_dir 2>/dev/null || true)"
  if [[ -n "${payload}" ]]; then
    pe_src="$(soju_gptk_pe_dir "${payload}" 2>/dev/null || true)"
  fi
  if [[ -n "${wine_lib}" \
    && -f "${wine_lib}/external/libd3dshared.dylib" \
    && -d "${wine_lib}/external/D3DMetal.framework" ]]; then
    external=1
  fi
  if [[ -n "${wine_lib}" ]]; then
    pe=1
    links=1
    for name in ${SOJU_GPTK_SHIMS}; do
      [[ -f "${wine_lib}/wine/x86_64-windows/${name}.dll" ]] || pe=0
      if [[ -e "${wine_lib}/wine/x86_64-unix/${name}.so" && ! -L "${wine_lib}/wine/x86_64-unix/${name}.so" ]]; then
        copied=1
      fi
      soju_shim_link_ok "${wine_lib}/wine/x86_64-unix/${name}.so" || links=0
    done
  fi
  if [[ "${external}" -eq 1 && "${pe}" -eq 1 && "${links}" -eq 1 && "${copied}" -eq 0 ]]; then
    layout="complete"
    message="D3DMetal layout is installed. The unix libraries are symlinks."
  elif [[ "${external}" -eq 1 || "${pe}" -eq 1 || "${links}" -eq 1 || "${copied}" -eq 1 ]]; then
    layout="partial"
    if [[ "${copied}" -eq 1 ]]; then
      message="A D3DMetal unix library is a real file. That breaks the Metal loader. Install the layout again to replace it with a symlink."
    else
      message="D3DMetal is only partly installed. The Metal library, Windows shims, and unix symlinks are all required."
    fi
  elif [[ -n "${payload}" ]]; then
    message="A Game Porting Toolkit payload was found. The Wine tree does not have the D3DMetal layout yet."
  else
    message="No Game Porting Toolkit payload found. Download it from Apple, then point Cosmos at it."
  fi
  printf 'layout=%s\n' "${layout}"
  if [[ -n "${payload}" ]]; then
    printf 'payload=found\n'
    printf 'payload_path=%s\n' "${payload}"
  else
    printf 'payload=missing\n'
    printf 'payload_path=\n'
  fi
  printf 'pe_source=%s\n' "${pe_src}"
  printf 'wine_lib=%s\n' "${wine_lib}"
  printf 'external=%s\n' "${external}"
  printf 'pe_shims=%s\n' "${pe}"
  printf 'unix_symlinks=%s\n' "${links}"
  printf 'copied_so=%s\n' "${copied}"
  printf 'message=%s\n' "${message}"
}

soju_gptk_required_present() {
  local pe_src="$1" name
  for name in ${SOJU_GPTK_SHIMS}; do
    [[ -f "${pe_src}/${name}.dll" ]] || return 1
  done
}

# Install the three-part layout into the Wine tree. Unix libraries are symlinks
# to libd3dshared.dylib. A real file at that path is replaced.
soju_gptk_layout_apply() {
  local payload="" wine_lib="" pe_src="" name dest bak unix_dir
  payload="$(soju_gptk_payload_dir 2>/dev/null || true)"
  wine_lib="$(soju_wine_lib_dir 2>/dev/null || true)"
  if [[ -z "${payload}" ]]; then
    soju_gptk_layout_status
    return 0
  fi
  if [[ -z "${wine_lib}" || ! -d "${wine_lib}" ]]; then
    printf 'layout=error\n'
    printf 'message=%s\n' "Wine's library folder was not found. Install Wine, then try again."
    return 1
  fi
  pe_src="$(soju_gptk_pe_dir "${payload}" 2>/dev/null || true)"
  if [[ -n "${pe_src}" ]] && ! soju_gptk_required_present "${pe_src}"; then
    printf 'layout=partial\n'
    printf 'payload_path=%s\n' "${payload}"
    printf 'message=%s\n' "The payload is missing d3d11.dll, d3d12.dll, or dxgi.dll. Nothing was changed."
    return 0
  fi
  mkdir -p "${wine_lib}/external" "${wine_lib}/wine/x86_64-windows" "${wine_lib}/wine/x86_64-unix"
  rm -rf "${wine_lib}/external/D3DMetal.framework"
  cp -R "${payload}/D3DMetal.framework" "${wine_lib}/external/D3DMetal.framework"
  cp -f "${payload}/libd3dshared.dylib" "${wine_lib}/external/libd3dshared.dylib"
  unix_dir="${wine_lib}/wine/x86_64-unix"
  if [[ -n "${pe_src}" ]]; then
    for name in ${SOJU_GPTK_SHIMS} ${SOJU_GPTK_OPTIONAL_SHIMS}; do
      [[ -f "${pe_src}/${name}.dll" ]] || continue
      dest="${wine_lib}/wine/x86_64-windows/${name}.dll"
      bak="${dest}.cosmos-bak"
      if [[ -f "${dest}" && ! -f "${bak}" ]]; then
        cp -p "${dest}" "${bak}"
      elif [[ ! -e "${dest}" && ! -f "${dest}.cosmos-new" ]]; then
        : >"${dest}.cosmos-new"
      fi
      cp -f "${pe_src}/${name}.dll" "${dest}"
      ln -sfn ../../external/libd3dshared.dylib "${unix_dir}/${name}.so"
    done
  fi
  soju_gptk_layout_status
}

soju_gptk_layout_revert() {
  local wine_lib name dest bak so target
  wine_lib="$(soju_wine_lib_dir 2>/dev/null || true)"
  if [[ -z "${wine_lib}" || ! -d "${wine_lib}" ]]; then
    printf 'layout=missing\n'
    printf 'message=%s\n' "Wine's library folder was not found. Nothing to restore."
    return 0
  fi
  for name in ${SOJU_GPTK_SHIMS} ${SOJU_GPTK_OPTIONAL_SHIMS}; do
    dest="${wine_lib}/wine/x86_64-windows/${name}.dll"
    bak="${dest}.cosmos-bak"
    if [[ -f "${bak}" ]]; then
      mv -f "${bak}" "${dest}"
    elif [[ -f "${dest}.cosmos-new" ]]; then
      rm -f "${dest}" "${dest}.cosmos-new"
    fi
    so="${wine_lib}/wine/x86_64-unix/${name}.so"
    if [[ -L "${so}" ]]; then
      target="$(readlink "${so}")"
      case "${target}" in
        *libd3dshared.dylib) rm -f "${so}" ;;
      esac
    fi
  done
  rm -rf "${wine_lib}/external/D3DMetal.framework"
  rm -f "${wine_lib}/external/libd3dshared.dylib"
  soju_gptk_layout_status
}

soju_apply_d3dmetal_env() {
  local wine_lib shared
  wine_lib="$(soju_wine_lib_dir 2>/dev/null || true)"
  [[ -n "${wine_lib}" ]] || return 0
  shared="${wine_lib}/external/libd3dshared.dylib"
  [[ -f "${shared}" ]] || return 0
  export CX_APPLEGPTK_LIBD3DSHARED_PATH="${shared}"
  export CX_ACTIVE_GRAPHICS_BACKEND="${CX_ACTIVE_GRAPHICS_BACKEND:-d3dmetal}"
  export CX_GRAPHICS_BACKEND="${CX_GRAPHICS_BACKEND:-d3dmetal}"
  case ":${DYLD_FALLBACK_LIBRARY_PATH:-}:" in
    *":${wine_lib}:"*) ;;
    *)
      export DYLD_FALLBACK_LIBRARY_PATH="${wine_lib}${DYLD_FALLBACK_LIBRARY_PATH:+:${DYLD_FALLBACK_LIBRARY_PATH}}"
      ;;
  esac
}

# Copy the signed Battle.net.exe into each versioned Battle.net.NNNN folder.
# The agent resolves that relative name against the folder it was started in.
soju_seed_battlenet() {
  local prefix="${WINEPREFIX:-}" seeded=0 checked=0 root v
  local -a roots=()
  if [[ -n "${prefix}" ]]; then
    roots+=("${prefix}/drive_c/Program Files (x86)/Battle.net")
    roots+=("${prefix}/drive_c/Program Files/Battle.net")
  fi
  if [[ -n "${BATTLENET_LAUNCHER_EXE:-}" ]]; then
    local launcher="${BATTLENET_LAUNCHER_EXE}"
    if [[ "${launcher}" == drive_c/* && -n "${prefix}" ]]; then
      launcher="${prefix}/${launcher}"
    fi
    if [[ -f "${launcher}" ]]; then
      roots+=("$(dirname -- "${launcher}")")
    fi
  fi
  if [[ "${#roots[@]}" -gt 0 ]]; then
  for root in "${roots[@]}"; do
    [[ -f "${root}/Battle.net.exe" ]] || continue
    for v in "${root}"/Battle.net.[0-9]*; do
      [[ -d "${v}" ]] || continue
      checked=$((checked + 1))
      if [[ -f "${v}/Battle.net.exe" ]] && cmp -s "${root}/Battle.net.exe" "${v}/Battle.net.exe"; then
        continue
      fi
      cp -p "${root}/Battle.net.exe" "${v}/Battle.net.exe" || {
        printf 'seeded=%s\n' "${seeded}"
        printf 'checked=%s\n' "${checked}"
        printf 'message=%s\n' "Could not copy Battle.net.exe into a versioned folder."
        return 1
      }
      seeded=$((seeded + 1))
    done
  done
  fi
  printf 'seeded=%s\n' "${seeded}"
  printf 'checked=%s\n' "${checked}"
  if [[ "${seeded}" -gt 0 ]]; then
    printf 'message=%s\n' "Copied Battle.net.exe into ${seeded} versioned folder(s)."
  elif [[ "${checked}" -gt 0 ]]; then
    printf 'message=%s\n' "Battle.net.exe is already in each versioned folder."
  else
    printf 'message=%s\n' "Battle.net is not installed in this environment."
  fi
}

# Start a command in the background without nohup or arch. Those platform
# binaries drop DYLD_* before Wine starts, which leaves D3DMetal unloaded.
# The caller disowns the job. $! is the new process.
soju_spawn_detached() {
  local log="$1"
  shift
  if [[ -z "${log}" ]]; then
    log="/dev/null"
  fi
  "$@" </dev/null >>"${log}" 2>&1 &
}
