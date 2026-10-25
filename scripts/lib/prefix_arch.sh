#!/usr/bin/env bash
# Prefix layout for Apple Silicon Wine.
_COSMOS_PREFIX_ARCH_LOADED=1
#
# Sikarugir runs 32-bit programs inside a 64-bit prefix (WoW64). That is the
# Cosmos default. A 64-bit-only prefix skips the 32-bit DLL folder. A 32-bit-only
# prefix is the older WINEARCH=win32 layout.

# wow64 | win64 | win32. Empty means wow64.
prefix_arch_normalize() {
  local raw
  raw="$(printf '%s' "${1:-wow64}" | tr '[:upper:]' '[:lower:]')"
  case "${raw}" in
    ""|wow64|wow|both) printf 'wow64' ;;
    win64|64|x64) printf 'win64' ;;
    win32|32|x86) printf 'win32' ;;
    *) return 1 ;;
  esac
}

prefix_arch_label() {
  case "$(prefix_arch_normalize "${1:-wow64}")" in
    win64) printf '%s' "64-bit only" ;;
    win32) printf '%s' "32-bit only" ;;
    *) printf '%s' "64-bit and 32-bit" ;;
  esac
}

# win64 | win32. Empty means win64 (the program itself, not the prefix).
program_arch_normalize() {
  local raw
  raw="$(printf '%s' "${1:-win64}" | tr '[:upper:]' '[:lower:]')"
  case "${raw}" in
    ""|win64|64|x64) printf 'win64' ;;
    win32|32|x86) printf 'win32' ;;
    *) return 1 ;;
  esac
}

program_arch_label() {
  case "$(program_arch_normalize "${1:-win64}")" in
    win32) printf '%s' "32-bit" ;;
    *) printf '%s' "64-bit" ;;
  esac
}

# Set WINEARCH for a prefix that has not been created yet.
# An explicit WINEARCH is kept when Cosmos has no prefix-arch choice.
prefix_arch_export_winearch() {
  local arch requested="${1:-${COSMOS_PREFIX_ARCH:-}}"
  if [[ -z "${requested}" && -n "${WINEARCH:-}" ]]; then
    return 0
  fi
  arch="$(prefix_arch_normalize "${requested:-wow64}")" || return 1
  export COSMOS_PREFIX_ARCH="${arch}"
  case "${arch}" in
    win32) export WINEARCH=win32 ;;
    *) export WINEARCH=win64 ;;
  esac
}
