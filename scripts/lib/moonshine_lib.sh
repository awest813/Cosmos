#!/usr/bin/env bash
# Moonshine-style launch behavior, written for Cosmos.
#
# Moonshine (https://github.com/ybmeng/moonshine) and Whisky are GPL-3.0.
# This file does not include their source. It reimplements three behaviors:
#   - flip one OpenGL 3.2 check in Wine's Mac driver only when that byte matches
#   - record why a launch ended, including an uncaught signal
#   - start a program with its own folder as the working directory
#
# The check lives in winemac.so. Moonshine's Wine Staging 11.2 build has a
# conditional jump (0x74) at file offset 0x329fb (207355). Replacing it with an
# unconditional jump (0xEB) lets SDL3 create an OpenGL 3.2 context. Cosmos
# writes that byte only when the current byte is still 0x74. Wine 11.8 and any
# other build are left unchanged.

moonshine_opengl_offset() {
  local raw="${COSMOS_OPENGL_PATCH_OFFSET:-}"
  local fallback=$((0x329fb))
  if [[ -z "${raw}" ]]; then
    printf '%s' "${fallback}"
    return 0
  fi
  if [[ "${raw}" =~ ^0[xX][0-9A-Fa-f]+$ || "${raw}" =~ ^[0-9]+$ ]]; then
    printf '%s' "$((raw))"
    return 0
  fi
  printf '%s' "${fallback}"
}

moonshine_winemac_path() {
  local candidate="" bin="" root=""
  if [[ -n "${COSMOS_WINEMAC_SO:-}" ]]; then
    printf '%s' "${COSMOS_WINEMAC_SO}"
    return 0
  fi
  if declare -F wine_resolve_bin >/dev/null 2>&1; then
    bin="$(wine_resolve_bin)"
  elif [[ -n "${WINE_BIN:-}" ]]; then
    bin="${WINE_BIN}"
  fi
  if [[ -n "${bin}" ]]; then
    candidate="$(cd "$(dirname -- "${bin}")/.." 2>/dev/null && pwd)/lib/wine/x86_64-unix/winemac.so"
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  fi
  if [[ -n "${WINE_APP:-}" ]]; then
    candidate="${WINE_APP}/Contents/Resources/wine/lib/wine/x86_64-unix/winemac.so"
    if [[ -f "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  fi
  if declare -F wine_resolve_app >/dev/null 2>&1; then
    candidate="$(wine_resolve_app)/Contents/Resources/wine/lib/wine/x86_64-unix/winemac.so"
    if [[ -f "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  fi
  if declare -F wine_default_root >/dev/null 2>&1; then
    root="$(wine_default_root)"
  else
    root="${WINE_ROOT:-${HOME}/wine-${WINE_VERSION:-11.8}}"
  fi
  printf '%s' "${root}/lib/wine/x86_64-unix/winemac.so"
}

moonshine_backup_path() {
  printf '%s.cosmos-bak' "$1"
}

# Print the unsigned byte at offset, or return 1 when the file is shorter.
moonshine_read_byte() {
  local file="$1" offset="$2" size raw
  size="$(wc -c < "${file}" | tr -d '[:space:]')"
  if [[ -z "${size}" ]] || (( size <= offset )); then
    return 1
  fi
  raw="$(od -An -tu1 -j "${offset}" -N 1 "${file}" 2>/dev/null || true)"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%%[[:space:]]*}"
  [[ -n "${raw}" ]] || return 1
  printf '%s' "${raw}"
}

moonshine_write_byte() {
  local file="$1" offset="$2" value="$3" octal
  printf -v octal '%03o' "${value}"
  # shellcheck disable=SC2059
  printf "\\${octal}" | dd of="${file}" bs=1 seek="${offset}" conv=notrunc 2>/dev/null
}

moonshine_status_field() {
  local key="$1" line
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" == "${key}="* ]] || continue
    printf '%s' "${line#"${key}"=}"
    return 0
  done
  return 1
}

moonshine_emit_status() {
  local status="$1" path="$2" offset="$3" byte="$4" message="$5" hex=""
  if [[ -n "${byte}" ]]; then
    printf -v hex '%02x' "${byte}"
  fi
  printf 'status=%s\n' "${status}"
  printf 'path=%s\n' "${path}"
  printf 'offset=%s\n' "${offset}"
  if [[ -n "${offset}" ]]; then
    printf 'offset_hex=0x%x\n' "${offset}"
  fi
  printf 'byte=%s\n' "${hex}"
  printf 'message=%s\n' "${message}"
}

# status=missing|unpatched|patched|mismatch. Always exits 0.
moonshine_opengl_status() {
  local path offset byte message
  path="$(moonshine_winemac_path)"
  offset="$(moonshine_opengl_offset)"
  if [[ -z "${path}" || ! -f "${path}" ]]; then
    moonshine_emit_status missing "${path}" "${offset}" "" \
      "Wine's Mac driver was not found. Install Wine, then check again."
    return 0
  fi
  if ! byte="$(moonshine_read_byte "${path}" "${offset}")"; then
    moonshine_emit_status mismatch "${path}" "${offset}" "" \
      "This Wine build is shorter than the OpenGL check. Left unchanged."
    return 0
  fi
  case "${byte}" in
    116)
      message="OpenGL 3.2 check is still the original jump. Cosmos can flip it."
      moonshine_emit_status unpatched "${path}" "${offset}" "${byte}" "${message}"
      ;;
    235)
      message="OpenGL 3.2 check is already flipped."
      moonshine_emit_status patched "${path}" "${offset}" "${byte}" "${message}"
      ;;
    *)
      message="This Wine build does not match the OpenGL check. Left unchanged."
      moonshine_emit_status mismatch "${path}" "${offset}" "${byte}" "${message}"
      ;;
  esac
  return 0
}

moonshine_backup_original_byte() {
  local file="$1" offset="$2" byte="$3" backup
  backup="$(moonshine_backup_path "${file}")"
  [[ -f "${backup}" ]] && return 0
  moonshine_write_byte "${backup}" 0 "${byte}"
}

# Flip 0x74 to 0xEB only. Already flipped is success. Anything else is unchanged.
moonshine_opengl_apply() {
  local path offset byte backup
  path="$(moonshine_winemac_path)"
  offset="$(moonshine_opengl_offset)"
  if [[ -z "${path}" || ! -f "${path}" ]]; then
    moonshine_emit_status missing "${path}" "${offset}" "" \
      "Wine's Mac driver was not found. Install Wine, then check again."
    return 0
  fi
  if ! byte="$(moonshine_read_byte "${path}" "${offset}")"; then
    moonshine_emit_status mismatch "${path}" "${offset}" "" \
      "This Wine build is shorter than the OpenGL check. Left unchanged."
    return 0
  fi
  case "${byte}" in
    235)
      moonshine_emit_status patched "${path}" "${offset}" "${byte}" \
        "OpenGL 3.2 check is already flipped."
      return 0
      ;;
    116)
      moonshine_backup_original_byte "${path}" "${offset}" "${byte}" || {
        moonshine_emit_status error "${path}" "${offset}" "${byte}" \
          "Could not save a backup of Wine's Mac driver. Left unchanged."
        return 1
      }
      if ! moonshine_write_byte "${path}" "${offset}" 235; then
        moonshine_emit_status error "${path}" "${offset}" "${byte}" \
          "Could not update Wine's Mac driver. Left unchanged."
        return 1
      fi
      byte="$(moonshine_read_byte "${path}" "${offset}" || true)"
      if [[ "${byte}" != "235" ]]; then
        moonshine_emit_status error "${path}" "${offset}" "${byte}" \
          "Could not update Wine's Mac driver. Left unchanged."
        return 1
      fi
      backup="$(moonshine_backup_path "${path}")"
      moonshine_emit_status patched "${path}" "${offset}" "${byte}" \
        "Flipped the OpenGL 3.2 check in Wine's Mac driver."
      [[ -f "${backup}" ]] && printf 'backup=%s\n' "${backup}"
      return 0
      ;;
    *)
      moonshine_emit_status mismatch "${path}" "${offset}" "${byte}" \
        "This Wine build does not match the OpenGL check. Left unchanged."
      return 0
      ;;
  esac
}

moonshine_opengl_revert() {
  local path offset byte backup backup_byte=""
  path="$(moonshine_winemac_path)"
  offset="$(moonshine_opengl_offset)"
  if [[ -z "${path}" || ! -f "${path}" ]]; then
    moonshine_emit_status missing "${path}" "${offset}" "" \
      "Wine's Mac driver was not found. Nothing to restore."
    return 0
  fi
  if ! byte="$(moonshine_read_byte "${path}" "${offset}")"; then
    moonshine_emit_status mismatch "${path}" "${offset}" "" \
      "This Wine build is shorter than the OpenGL check. Left unchanged."
    return 0
  fi
  backup="$(moonshine_backup_path "${path}")"
  if [[ -f "${backup}" ]]; then
    backup_byte="$(moonshine_read_byte "${backup}" 0 || true)"
  fi
  if [[ "${byte}" == "116" ]]; then
    rm -f "${backup}"
    moonshine_emit_status unpatched "${path}" "${offset}" "${byte}" \
      "OpenGL 3.2 check is already original."
    return 0
  fi
  if [[ -n "${backup_byte}" && "${byte}" == "235" ]]; then
    moonshine_write_byte "${path}" "${offset}" "${backup_byte}" || {
      moonshine_emit_status error "${path}" "${offset}" "${byte}" \
        "Could not restore Wine's Mac driver."
      return 1
    }
    rm -f "${backup}"
    byte="$(moonshine_read_byte "${path}" "${offset}" || true)"
    moonshine_emit_status unpatched "${path}" "${offset}" "${byte}" \
      "Restored Wine's Mac driver."
    return 0
  fi
  if [[ -z "${backup_byte}" && "${byte}" == "235" ]]; then
    moonshine_write_byte "${path}" "${offset}" 116 || {
      moonshine_emit_status error "${path}" "${offset}" "${byte}" \
        "Could not restore Wine's Mac driver."
      return 1
    }
    byte="$(moonshine_read_byte "${path}" "${offset}" || true)"
    moonshine_emit_status unpatched "${path}" "${offset}" "${byte}" \
      "Restored the original OpenGL check."
    return 0
  fi
  moonshine_emit_status mismatch "${path}" "${offset}" "${byte}" \
    "This Wine build does not match the OpenGL check. Left unchanged."
  return 0
}

# Apply only when the byte is still 0x74. Never fails Wine install.
# COSMOS_OPENGL_PATCH: auto (default), on/1, off/0.
# auto stays quiet when the driver is missing, already flipped, or a mismatch.
# on/1 prints a warning on mismatch.
moonshine_opengl_auto() {
  local mode="${COSMOS_OPENGL_PATCH:-auto}" output status message
  case "${mode}" in
    off|0) return 0 ;;
    auto|on|1) ;;
    *) return 0 ;;
  esac
  output="$(moonshine_opengl_status)"
  status="$(printf '%s\n' "${output}" | moonshine_status_field status || true)"
  case "${status}" in
    unpatched)
      if moonshine_opengl_apply >/dev/null; then
        printf '%s\n' "Applied the OpenGL 3.2 fix in Wine's Mac driver."
      fi
      ;;
    mismatch)
      if [[ "${mode}" == "on" || "${mode}" == "1" ]]; then
        message="$(printf '%s\n' "${output}" | moonshine_status_field message || true)"
        printf 'Warning: %s\n' "${message:-OpenGL fix does not match this Wine build. Left unchanged.}"
      fi
      ;;
  esac
  return 0
}

# cosmos (default) keeps the quiet log. moonshine records module warnings too.
# An explicit WINEDEBUG value still wins at the call site.
moonshine_winedebug_default() {
  case "${COSMOS_WINEDEBUG_PRESET:-cosmos}" in
    moonshine) printf '%s' 'fixme-all,err+all,warn+module' ;;
    *) printf '%s' '-all,err+all' ;;
  esac
}

# Print and append a termination note. Does not change the caller's exit code.
moonshine_report_exit() {
  local label="$1" status="$2" reason="exit" note lines=""
  if (( status >= 128 && status <= 159 )); then
    reason="uncaught signal"
  fi
  note="${label} ended: status=${status} reason=${reason}"
  if [[ -n "${COSMOS_LAUNCH_LOG:-}" && -f "${COSMOS_LAUNCH_LOG}" ]]; then
    lines="$(grep -E -i 'page fault|err:|unhandled exception|dll load fail' "${COSMOS_LAUNCH_LOG}" 2>/dev/null | head -n 8 || true)"
  fi
  printf '%s\n' "${note}"
  if [[ -n "${lines}" ]]; then
    printf '%s\n' "${lines}"
  fi
  if [[ -n "${COSMOS_LAUNCH_LOG:-}" ]]; then
    mkdir -p "$(dirname -- "${COSMOS_LAUNCH_LOG}")" 2>/dev/null || true
    {
      printf '%s\n' "${note}"
      if [[ -n "${lines}" ]]; then
        printf '%s\n' "${lines}"
      fi
    } >>"${COSMOS_LAUNCH_LOG}" 2>/dev/null || true
  fi
  return 0
}

# Run a command with the program's folder as the working directory, then restore
# this shell's directory. The command itself is not wrapped in a subshell, so a
# stub can still record arguments in the caller.
moonshine_with_program_dir() {
  local exe="$1"
  shift
  local dir prev="" status=0
  dir="$(dirname -- "${exe}")"
  if [[ -d "${dir}" ]]; then
    prev="$(pwd)"
    if ! cd "${dir}"; then
      prev=""
    fi
  fi
  "$@" || status=$?
  if [[ -n "${prev}" ]]; then
    cd "${prev}" || true
  fi
  return "${status}"
}
