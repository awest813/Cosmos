#!/usr/bin/env bash
# SpockD3D9 PE d3d9.dll helpers — experimental D3D9 → Vulkan path for Wine on macOS.

spockd3d9_default_root() {
  local base="${COSMOS_RUNTIME_DIR:-}"
  if [[ -z "${base}" ]] && declare -F runtime_default_dir >/dev/null 2>&1; then
    base="$(runtime_default_dir)"
  fi
  base="${base:-${HOME}/Library/Application Support/Cosmos/Runtime}"
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
  local path="$1"
  [[ -f "${path}" ]] || return 1
  if [[ "${COSMOS_SKIP_PE_CHECK:-0}" == "1" ]]; then
    return 0
  fi
  command -v file >/dev/null 2>&1 || return 0
  file "${path}" | grep -Eq 'PE32\+ executable \(DLL\)|PE32 executable \(DLL\)'
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
    if spockd3d9_pe_ok "${x86}"; then
      count=$((count + 1))
    else
      x86=""
    fi
  fi
  if x64="$(spockd3d9_find_arch_dll "${path}" x64)"; then
    if spockd3d9_pe_ok "${x64}"; then
      count=$((count + 1))
    else
      x64=""
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
  [[ -x "${script}" ]] || script="${SCRIPT_DIR:-}/scripts/build-pe-d3d9.sh"
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

  local target32="${WINEPREFIX}/drive_c/windows/syswow64"
  local target64="${WINEPREFIX}/drive_c/windows/system32"
  [[ -d "${target64}" ]] || die "Prefix system32 not found (is the prefix initialized?): ${target64}"

  local x86="" x64="" copied=0
  x86="$(spockd3d9_find_arch_dll "${root}" x86 || true)"
  x64="$(spockd3d9_find_arch_dll "${root}" x64 || true)"

  if [[ -n "${x86}" ]]; then
    mkdir -p "${target32}"
    cp -f "${x86}" "${target32}/d3d9.dll"
    copied=$((copied + 1))
    echo "Copied 32-bit SpockD3D9 d3d9.dll to syswow64."
  fi
  if [[ -n "${x64}" ]]; then
    cp -f "${x64}" "${target64}/d3d9.dll"
    copied=$((copied + 1))
    echo "Copied 64-bit SpockD3D9 d3d9.dll to system32."
  fi
  (( copied > 0 )) || die "No SpockD3D9 d3d9.dll files found under ${root}."
}

enable_spockd3d9_env() {
  log "Enabling SpockD3D9 for D3D9 (DXMT still handles D3D10/11)"
  export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d9=n,b}"
  export MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS="${MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS:-2}"
  export WINEDEBUG="${WINEDEBUG:--all,err+all}"
  if declare -F runtime_prepare_moltenvk_env >/dev/null 2>&1; then
    runtime_prepare_moltenvk_env || echo "Note: MoltenVK auto-fetch failed; ensure Vulkan/MoltenVK is available for SpockD3D9."
  fi
  echo "WINEDLLOVERRIDES=${WINEDLLOVERRIDES}"
  echo "Note: SpockD3D9 is experimental. Classic D3D9 titles are often 32-bit — build x86 with ./scripts/build-pe-d3d9.sh --arch x86."
}
