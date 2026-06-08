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

# --- Legendary / Epic Games (experimental, roadmap 0.6) ---

import_find_legendary() {
  local candidate
  if command -v legendary >/dev/null 2>&1; then
    command -v legendary
    return 0
  fi
  for candidate in \
    "${HOME}/.local/bin/legendary" \
    "/opt/homebrew/bin/legendary" \
    "/usr/local/bin/legendary"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  return 1
}

import_legendary_run() {
  local bin
  bin="$(import_find_legendary)" || return 1
  "${bin}" "$@"
}

import_legendary_require() {
  import_find_legendary >/dev/null \
    || return 1
}

# Print install_path for a Legendary app name (installed games only).
import_legendary_install_path() {
  local app="$1"
  local json
  json="$(import_legendary_run list-installed --json --show-dirs 2>/dev/null)" || return 1
  printf '%s' "${json}" | python3 -c '
import json, sys
app = sys.argv[1].lower()
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(1)
if not isinstance(data, list):
    data = [data]
for entry in data:
    name = (entry.get("app_name") or "").lower()
    title = (entry.get("title") or "").lower()
    if app in (name, title) or app == name or app == title:
        path = entry.get("install_path") or entry.get("install_directory") or ""
        if path:
            print(path)
            sys.exit(0)
sys.exit(1)
' "${app}"
}

import_legendary_is_installed() {
  local app="$1"
  import_legendary_install_path "${app}" >/dev/null 2>&1
}

# Pick the main game executable under a Legendary install directory.
import_legendary_find_exe() {
  local install_dir="$1" app_name="${2:-}"
  local exe
  exe="$(import_find_game_exe "${install_dir}")" && {
    printf '%s' "${exe}"
    return 0
  }
  if [[ -n "${app_name}" ]] && command -v python3 >/dev/null 2>&1; then
    local launch_json
    launch_json="$(import_legendary_run launch "${app_name}" --json --offline 2>/dev/null || true)"
    if [[ -n "${launch_json}" ]]; then
      exe="$(printf '%s' "${launch_json}" | python3 -c '
import json, os, sys
root = sys.argv[1]
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(1)
for key in ("executable", "game_executable", "exe"):
    val = data.get(key)
    if val:
        path = val if os.path.isabs(val) else os.path.join(root, val)
        if os.path.isfile(path):
            print(path)
            sys.exit(0)
sys.exit(1)
' "${install_dir}")" && [[ -n "${exe}" ]] && { printf '%s' "${exe}"; return 0; }
    fi
  fi
  return 1
}

import_write_epic_config() {
  local configs_dir="$1" slug="$2" app_name="$3" bundle_id="$4" exe_path="$5" legendary_app="$6"
  local file="${configs_dir}/epic-${slug}.conf"
  mkdir -p "${configs_dir}"
  {
    printf '# Created by import_game.command (Epic / Legendary)\n'
    printf 'APP_NAME="%s (Cosmos)"\n' "$(import_safe_name "${app_name}")"
    printf 'BUNDLE_ID="%s"\n' "${bundle_id}"
    printf '\nRUN_ENV_NAMES=(\n'
    printf '  GAME_EXE_PATH\n'
    printf '  COSMOS_SKIP_STEAM\n'
    printf '  LEGENDARY_APP_NAME\n'
    printf ')\n\n'
    printf 'GAME_EXE_PATH="%s"\n' "${exe_path}"
    printf 'COSMOS_SKIP_STEAM="1"\n'
    printf 'LEGENDARY_APP_NAME="%s"\n' "${legendary_app}"
  } > "${file}"
  printf '%s' "${file}"
}
