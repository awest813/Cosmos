#!/usr/bin/env bash
# Helpers for import_game.command (roadmap 0.6).

import_slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

import_safe_name() {
  local name="$1"
  name="${name//\\/}"
  name="${name//\//-}"
  name="${name//:/ -}"
  name="${name//\"/}"
  name="${name//\$/}"
  name="${name//\`/}"
  printf '%s' "${name}"
}

# Convert a host path or drive_c-relative path to a Wine Z: path for launch.
import_resolve_exe_path() {
  local pfx="$1" path="$2"
  if [[ "${path}" == drive_c/* ]]; then
    printf 'Z:\\%s' "$(printf '%s' "${path#drive_c/}" | tr '/' '\\')"
    return 0
  fi
  if [[ -f "${path}" ]]; then
    printf '%s' "${path}"
    return 0
  fi
  if [[ -f "${pfx}/${path}" ]]; then
    printf '%s' "${pfx}/${path}"
    return 0
  fi
  return 1
}

# Find the first plausible game .exe under a directory (skip uninstall/setup helpers).
import_find_game_exe() {
  local root="$1"
  [[ -d "${root}" ]] || return 1
  local f base
  while IFS= read -r f; do
    base="$(basename "${f}")"
    printf '%s' "${base}" | grep -Eqi '^(uninstall|setup)' && continue
    printf '%s' "${base}" | grep -Eqi 'redist' && continue
    printf '%s' "${f}"
    return 0
  done < <(find "${root}" -type f \( -iname '*.exe' \) 2>/dev/null | head -n 50)
  return 1
}

import_write_config() {
  local configs_dir="$1" slug="$2" app_name="$3" bundle_id="$4" exe_path="$5"
  local file="${configs_dir}/standalone-${slug}.conf"
  mkdir -p "${configs_dir}"
  {
    printf '# Created by import_game.command\n'
    printf 'APP_NAME="%s (Cosmos)"\n' "$(import_safe_name "${app_name}")"
    printf 'BUNDLE_ID="%s"\n' "${bundle_id}"
    printf '\nRUN_ENV_NAMES=(\n'
    printf '  GAME_EXE_PATH\n'
    printf '  COSMOS_SKIP_STEAM\n'
    printf ')\n\n'
    printf 'GAME_EXE_PATH="%s"\n' "${exe_path}"
    printf 'COSMOS_SKIP_STEAM="1"\n'
  } > "${file}"
  printf '%s' "${file}"
}
