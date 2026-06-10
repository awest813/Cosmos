#!/usr/bin/env bash
# Game Porting Toolkit path validation (Phase E). Apple GPTK is user-supplied.

gptk_find_dll_dir() {
  local root="$1"
  local candidates=(
    "${root}"
    "${root}/redist/lib/external"
    "${root}/lib/external"
    "${root}/lib"
    "${root}/Libraries"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -f "${c}/d3d11.dll" ]]; then
      printf '%s\n' "${c}"
      return 0
    fi
  done
  return 1
}

# Machine-readable validation (key=value lines) for dashboard and CI.
gptk_validate_path() {
  local path="${1:-}"
  if [[ -z "${path}" ]]; then
    printf 'valid=0\n'
    printf 'error=GPTK_PATH is empty\n'
    return 1
  fi
  if [[ ! -d "${path}" ]]; then
    printf 'valid=0\n'
    printf 'path=%s\n' "${path}"
    printf 'error=Not a directory\n'
    return 1
  fi
  local dll_dir count
  if ! dll_dir="$(gptk_find_dll_dir "${path}")"; then
    printf 'valid=0\n'
    printf 'path=%s\n' "${path}"
    printf 'error=Could not find d3d11.dll under GPTK_PATH. Point at your Game Porting Toolkit root from developer.apple.com.\n'
    return 1
  fi
  count=0
  local f
  for f in "${dll_dir}"/*.dll; do
    [[ -f "${f}" ]] || continue
    count=$((count + 1))
  done
  if (( count == 0 )); then
    printf 'valid=0\n'
    printf 'path=%s\n' "${path}"
    printf 'dll_dir=%s\n' "${dll_dir}"
    printf 'error=No .dll files found in GPTK folder\n'
    return 1
  fi
  printf 'valid=1\n'
  printf 'path=%s\n' "${path}"
  printf 'dll_dir=%s\n' "${dll_dir}"
  printf 'dll_count=%s\n' "${count}"
  return 0
}
