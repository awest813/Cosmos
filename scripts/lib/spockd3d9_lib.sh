#!/usr/bin/env bash
# SpockD3D9 PE d3d9.dll helpers — experimental D3D9 → Vulkan path for Wine on macOS.
# DXMT stays responsible for DirectX 10 and 11. This file only places d3d9.dll.
# 32-bit programs on Apple Silicon read syswow64 (Sikarugir / WoW64).

if [[ -z "${_COSMOS_PREFIX_ARCH_LOADED:-}" ]]; then
  _spock_arch_lib="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/prefix_arch.sh"
  if [[ -f "${_spock_arch_lib}" ]]; then
    # shellcheck source=scripts/lib/prefix_arch.sh
    source "${_spock_arch_lib}"
  fi
  unset _spock_arch_lib
fi

spockd3d9_default_root() {
  local base="${COSMOS_RUNTIME_DIR:-}"
  if [[ -z "${base}" ]] && declare -F runtime_default_dir >/dev/null 2>&1; then
    base="$(runtime_default_dir)"
  fi
  base="${base:-${COSMOS_SUPPORT_DIR:-${HOME}/Library/Application Support/Cosmos}/Runtime}"
  printf '%s/spockd3d9' "${base}"
}

spockd3d9_find_arch_dll() {
  local root="$1" arch="$2"
  local candidates=()
  case "${arch}" in
    x86)
      candidates=(
        "${root}/x86/d3d9.dll"
        "${root}/build-pe-d3d9-x86/d3d9.dll"
        "${root}/d3d9-x86.dll"
      )
      ;;
    x64)
      candidates=(
        "${root}/x64/d3d9.dll"
        "${root}/build-pe-d3d9/d3d9.dll"
        "${root}/d3d9.dll"
      )
      ;;
    *)
      return 1
      ;;
  esac
  local c
  for c in "${candidates[@]}"; do
    [[ -f "${c}" ]] || continue
    printf '%s' "${c}"
    return 0
  done
  return 1
}

spockd3d9_pe_ok() {
  local path="$1" arch="${2:-}"
  [[ -f "${path}" ]] || return 1
  if [[ "${COSMOS_SKIP_PE_CHECK:-0}" == "1" ]]; then
    return 0
  fi
  command -v file >/dev/null 2>&1 || return 1
  local description
  description="$(file -b "${path}")" || return 1
  case "${arch}" in
    x86) printf '%s' "${description}" | grep -Eq 'PE32 executable .*\(DLL\).*Intel 80386' ;;
    x64) printf '%s' "${description}" | grep -Eq 'PE32\+ executable .*\(DLL\).*x86-64' ;;
    *) return 1 ;;
  esac
}

# Machine-readable validation (key=value lines) for dashboard and CI.
spockd3d9_validate_path() {
  local path="${1:-}"
  if [[ -z "${path}" ]]; then
    printf 'valid=0\n'
    printf 'error=SPOCK_D3D9_PATH is empty\n'
    return 1
  fi
  if [[ ! -d "${path}" ]]; then
    printf 'valid=0\n'
    printf 'path=%s\n' "${path}"
    printf 'error=Not a directory\n'
    return 1
  fi

  local x86="" x64="" count=0
  if x86="$(spockd3d9_find_arch_dll "${path}" x86)"; then
    if spockd3d9_pe_ok "${x86}" x86; then
      count=$((count + 1))
    else
      printf 'valid=0\nerror=The x86 d3d9.dll is not a valid 32-bit Windows DLL. Rebuild with --arch x86.\n'
      return 1
    fi
  fi
  if x64="$(spockd3d9_find_arch_dll "${path}" x64)"; then
    if spockd3d9_pe_ok "${x64}" x64; then
      count=$((count + 1))
    else
      printf 'valid=0\nerror=The x64 d3d9.dll is not a valid 64-bit Windows DLL. Rebuild with --arch x64.\n'
      return 1
    fi
  fi

  if (( count == 0 )); then
    printf 'valid=0\n'
    printf 'path=%s\n' "${path}"
    printf 'error=No SpockD3D9 d3d9.dll found. Build with ./scripts/build-pe-d3d9.sh or point at a folder containing x86/d3d9.dll and/or x64/d3d9.dll.\n'
    return 1
  fi

  printf 'valid=1\n'
  printf 'path=%s\n' "${path}"
  printf 'dll_count=%s\n' "${count}"
  [[ -n "${x86}" ]] && printf 'x86_dll=%s\n' "${x86}"
  [[ -n "${x64}" ]] && printf 'x64_dll=%s\n' "${x64}"
  return 0
}

spockd3d9_resolve_root() {
  if [[ -n "${SPOCK_D3D9_PATH:-}" ]]; then
    printf '%s' "${SPOCK_D3D9_PATH}"
    return 0
  fi
  local built
  built="$(spockd3d9_default_root)"
  if spockd3d9_validate_path "${built}" >/dev/null 2>&1; then
    printf '%s' "${built}"
    return 0
  fi
  return 1
}

spockd3d9_auto_build() {
  [[ "${COSMOS_AUTO_SPOCK_D3D9:-0}" == "1" ]] || return 0
  local script="${SCRIPT_DIR:-}/scripts/build-pe-d3d9.sh"
  [[ -f "${script}" ]] || {
    echo "COSMOS_AUTO_SPOCK_D3D9=1 but ${script} is missing." >&2
    return 1
  }
  bash "${script}" --arch both
}

ensure_spockd3d9_installed() {
  log "Installing SpockD3D9 PE d3d9.dll into the Wine prefix (experimental)"
  spockd3d9_auto_build || true

  local root
  if ! root="$(spockd3d9_resolve_root)"; then
    die "The spockd3d9 backend needs SPOCK_D3D9_PATH pointing at a folder of SpockD3D9 PE d3d9.dll files (x86 and/or x64), or set COSMOS_AUTO_SPOCK_D3D9=1 to build from source. See docs/BACKENDS.md."
  fi
  spockd3d9_validate_path "${root}" >/dev/null \
    || die "SPOCK_D3D9_PATH=${root} does not contain valid SpockD3D9 d3d9.dll files."

  spockd3d9_install_into_prefix "${root}" "${WINEPREFIX}" \
    || die "SpockD3D9 could not be installed for this environment. Build the matching DLL with ./scripts/build-pe-d3d9.sh --arch x86, --arch x64, or --arch both."
}

# Place d3d9.dll for COSMOS_PREFIX_ARCH and, when set, COSMOS_PROGRAM_ARCH.
# wow64 copies 64-bit into system32 and 32-bit into syswow64.
# win64 copies 64-bit only. win32 copies 32-bit into system32.
# A missing 32-bit DLL warns and leaves DirectX 9 on WineD3D. Returns 1 only
# when the DLL this environment needs is absent.
spockd3d9_install_into_prefix() {
  local root="$1" prefix="$2"
  local arch program x86="" x64="" copied=0
  local sys32="${prefix}/drive_c/windows/system32"
  local syswow="${prefix}/drive_c/windows/syswow64"
  [[ -d "${sys32}" ]] || return 1
  arch="$(prefix_arch_normalize "${COSMOS_PREFIX_ARCH:-wow64}")" || return 1
  program=""
  if [[ -n "${COSMOS_PROGRAM_ARCH:-}" ]]; then
    program="$(program_arch_normalize "${COSMOS_PROGRAM_ARCH}")" || return 1
  fi
  x86="$(spockd3d9_find_arch_dll "${root}" x86 || true)"
  x64="$(spockd3d9_find_arch_dll "${root}" x64 || true)"

  case "${arch}" in
    win64)
      if [[ "${program}" == "win32" ]]; then
        echo "This environment is 64-bit only, so this 32-bit program keeps WineD3D for DirectX 9."
        return 0
      fi
      [[ -n "${x64}" ]] || return 1
      cp -f "${x64}" "${sys32}/d3d9.dll"
      echo "Copied 64-bit SpockD3D9 d3d9.dll to system32."
      ;;
    win32)
      [[ -n "${x86}" ]] || return 1
      cp -f "${x86}" "${sys32}/d3d9.dll"
      echo "Copied 32-bit SpockD3D9 d3d9.dll to system32."
      ;;
    *)
      if [[ "${program}" == "win64" && -z "${x64}" ]]; then
        return 1
      fi
      if [[ -n "${x64}" ]]; then
        cp -f "${x64}" "${sys32}/d3d9.dll"
        echo "Copied 64-bit SpockD3D9 d3d9.dll to system32."
        copied=$((copied + 1))
      fi
      if [[ -n "${x86}" ]]; then
        mkdir -p "${syswow}"
        cp -f "${x86}" "${syswow}/d3d9.dll"
        echo "Copied 32-bit SpockD3D9 d3d9.dll to syswow64."
        copied=$((copied + 1))
      elif [[ "${program}" == "win32" || -z "${program}" ]]; then
        echo "32-bit programs will use WineD3D for DirectX 9 until the 32-bit SpockD3D9 DLL is built (--arch x86)."
      fi
      if [[ "${program}" == "win32" ]]; then
        return 0
      fi
      [[ "${copied}" -gt 0 ]] || return 1
      ;;
  esac
}

# Replace only D3D9's load order, including when it shares a group with other DLLs.
# Appending a second conflicting entry is ambiguous, so preserve all other entries.
spockd3d9_merge_overrides() {
  local entry names order name kept result=""
  local entries=() dlls=()
  IFS=';' read -r -a entries <<< "${1:-}"
  for entry in ${entries[@]+"${entries[@]}"}; do
    [[ -n "${entry}" ]] || continue
    if [[ "${entry}" != *=* ]]; then
      result="${result}${result:+;}${entry}"
      continue
    fi
    names="${entry%%=*}"
    order="${entry#*=}"
    kept=""
    IFS=',' read -r -a dlls <<< "${names}"
    for name in ${dlls[@]+"${dlls[@]}"}; do
      case "${name//[[:space:]]/}" in
        [dD]3[dD]9|[dD]3[dD]9.[dD][lL][lL]|\*[dD]3[dD]9|\*[dD]3[dD]9.[dD][lL][lL]) continue ;;
      esac
      kept="${kept}${kept:+,}${name}"
    done
    [[ -z "${kept}" ]] || result="${result}${result:+;}${kept}=${order}"
  done
  printf '%s' "${result}${result:+;}d3d9=n,b"
}

enable_spockd3d9_env() {
  log "Enabling SpockD3D9 for D3D9 (DXMT still handles D3D10/11)"
  export WINEDLLOVERRIDES="$(spockd3d9_merge_overrides "${WINEDLLOVERRIDES:-}")"
  export MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS="${MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS:-2}"
  if declare -F moonshine_winedebug_default >/dev/null 2>&1; then
    export WINEDEBUG="${WINEDEBUG:-$(moonshine_winedebug_default)}"
  else
    export WINEDEBUG="${WINEDEBUG:--all,err+all}"
  fi
  if declare -F runtime_prepare_moltenvk_env >/dev/null 2>&1; then
    runtime_prepare_moltenvk_env || echo "Note: MoltenVK auto-fetch failed; ensure Vulkan/MoltenVK is available for SpockD3D9."
  fi
  echo "WINEDLLOVERRIDES=${WINEDLLOVERRIDES}"
  echo "Note: SpockD3D9 is experimental. Classic D3D9 titles are often 32-bit — build x86 with ./scripts/build-pe-d3d9.sh --arch x86."
}
