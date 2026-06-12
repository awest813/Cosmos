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

# True when a basename looks like a helper binary, not the game itself.
import_exe_is_helper() {
  local base="${1##*/}"
  base="${base%.exe}"
  base="${base%.EXE}"
  printf '%s' "${base}" | grep -Eqi \
    '^(uninstall|setup|unins|goggalaxy|galaxyclient|goggalaxy|crashreporter|webhelper|gogcom|galaxycommunication|goggamecontroller|easyanticheat|beservice|eos|unitycrashhandler|ue4prereq|dxsetup|oobefix|installscript|activation|register|bootstrap|stub|prereq|prerequisite)' \
    && return 0
  printf '%s' "${base}" | grep -Eqi \
    'redist|vcredist|dotnet|physx|openal|bink|helper|updater|patch|patcher|modlauncher|editor|submarine|server|dedicated|benchmark|config|tool|utility' \
    && return 0
  local lower
  lower="$(printf '%s' "${base}" | tr '[:upper:]' '[:lower:]')"
  [[ "${lower}" == *launcher* && "${lower}" != *game* ]] && return 0
  return 1
}

import_exe_has_pe_header() {
  local path="$1"
  [[ -f "${path}" ]] || return 1
  local magic
  magic="$(dd if="${path}" bs=1 count=2 2>/dev/null || true)"
  [[ "${magic}" == $'MZ' ]]
}

import_exe_size_bytes() {
  local path="$1"
  [[ -f "${path}" ]] || return 0
  wc -c <"${path}" | tr -d ' '
}

# True for vendor/redist folders that should not host the main game binary.
import_path_is_ignored_dir() {
  local segment
  segment="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "${segment}" in
    redist|_commonredist|commonredist|directx|directx11|directx9|prerequisites|prereq|support|__support|win_install|win_gdk_runtime|_redist|dotnet|physx|nvidia|amd|vcredist|openal|bink|videos|movies|manual|docs|bonus|dlc_cache|webcache|cache|temp|tmp|logs|crashes|backup|update|patches|installers|_installer)
      return 0
      ;;
  esac
  return 1
}

import_path_has_ignored_segment() {
  local rel="$1"
  local part
  IFS='/' read -r -a parts <<< "${rel}"
  for part in "${parts[@]}"; do
    [[ -n "${part}" ]] || continue
    import_path_is_ignored_dir "${part}" && return 0
  done
  return 1
}

# Resolve primary executable from GOG Galaxy goggame-*.info metadata when present.
import_gog_find_info_exe() {
  local game_dir="$1"
  local info exe_path rel_path
  shopt -s nullglob
  for info in "${game_dir}"/goggame-*.info; do
    [[ -f "${info}" ]] || continue
    rel_path="$(python3 - "${info}" <<'PY'
import json, os, sys
path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
except (OSError, json.JSONDecodeError):
    sys.exit(1)
tasks = data.get("playTasks") or []
primary = next((t for t in tasks if t.get("isPrimary")), None)
if not primary and tasks:
    primary = tasks[0]
if not primary or primary.get("type") == "URLTask":
    sys.exit(1)
exe = (primary.get("path") or "").replace("\\", "/")
wd = (primary.get("workingDir") or "").replace("\\", "/")
if wd and exe:
    exe = os.path.join(wd, exe).replace("\\", "/")
elif wd:
    exe = wd
if exe:
    print(exe.lstrip("./"))
PY
)" || continue
    [[ -n "${rel_path}" ]] || continue
    exe_path="${game_dir}/${rel_path}"
    exe_path="${exe_path//\\//}"
    if [[ -f "${exe_path}" ]] && import_exe_has_pe_header "${exe_path}" \
      && ! import_exe_is_helper "$(basename "${exe_path}")"; then
      shopt -u nullglob
      printf '%s' "${exe_path}"
      return 0
    fi
  done
  shopt -u nullglob
  return 1
}

# When a GOG folder only contains one playable subfolder, search there too.
import_list_game_subroots() {
  local root="$1"
  local sub count=0 only="" has_exe
  shopt -s nullglob
  for sub in "${root}"/*; do
    [[ -d "${sub}" ]] || continue
    import_path_is_ignored_dir "$(basename "${sub}")" && continue
    has_exe="$(find "${sub}" -maxdepth 4 -type f -iname '*.exe' -print -quit 2>/dev/null || true)"
    [[ -n "${has_exe}" ]] || continue
    only="${sub}"
    count=$((count + 1))
  done
  shopt -u nullglob
  (( count == 1 )) && printf '%s\n' "${only}"
}

# Score a candidate executable (higher is better). Prints score to stdout; returns 1 when rejected.
import_score_exe() {
  local root="$1" exe="$2" hint="${3:-}"
  local base size depth rel folder_slug hint_slug base_slug score=0
  [[ -f "${exe}" ]] || return 1
  base="$(basename "${exe}")"
  import_exe_is_helper "${base}" && return 1
  rel="${exe#${root}/}"
  import_path_has_ignored_segment "${rel}" && return 1
  import_exe_has_pe_header "${exe}" || return 1

  score=10
  size="$(import_exe_size_bytes "${exe}")"
  (( size >= 100000 )) && score=$((score + 20))
  (( size >= 500000 )) && score=$((score + 30))
  (( size >= 2000000 )) && score=$((score + 20))

  folder_slug="$(import_slugify "$(basename "${root}")")"
  hint_slug="$(import_slugify "${hint}")"
  base_slug="$(import_slugify "${base%.exe}")"

  if [[ -n "${hint_slug}" ]]; then
    [[ "${base_slug}" == *"${hint_slug}"* || "${hint_slug}" == *"${base_slug}"* ]] \
      && score=$((score + 100))
  fi
  if [[ -n "${folder_slug}" ]]; then
    [[ "${base_slug}" == *"${folder_slug}"* || "${folder_slug}" == *"${base_slug}"* ]] \
      && score=$((score + 80))
  fi

  [[ "${rel}" == *"/x64/"* || "${rel}" == *"/win64/"* || "${rel}" == *"/win_x64/"* ]] \
    && score=$((score + 40))
  [[ "${rel}" == *"/x86/"* || "${rel}" == *"/win32/"* ]] && score=$((score - 15))
  [[ "${rel}" == *"/bin/"* ]] && score=$((score + 15))

  depth="$(printf '%s' "${rel}" | awk -F/ '{print NF}')"
  score=$((score - depth * 3))

  printf '%s' "${score}"
  return 0
}

# Pick the best game .exe under a directory using GOG metadata, then scored candidates.
import_find_best_game_exe() {
  local root="$1" hint="${2:-}"
  local search_root info_exe best_exe="" best_score=-1 score exe
  [[ -d "${root}" ]] || return 1

  info_exe="$(import_gog_find_info_exe "${root}" 2>/dev/null || true)"
  if [[ -n "${info_exe}" ]]; then
    printf '%s' "${info_exe}"
    return 0
  fi

  while IFS= read -r search_root; do
    [[ -n "${search_root}" && -d "${search_root}" ]] || continue
    while IFS= read -r exe; do
      [[ -n "${exe}" ]] || continue
      score="$(import_score_exe "${search_root}" "${exe}" "${hint}" 2>/dev/null || true)"
      [[ -n "${score}" ]] || continue
      if (( score > best_score )); then
        best_score="${score}"
        best_exe="${exe}"
      elif (( score == best_score )) && [[ -n "${best_exe}" ]]; then
        # Tie-break toward larger binaries (usually the real game).
        if (( $(import_exe_size_bytes "${exe}") > $(import_exe_size_bytes "${best_exe}") )); then
          best_exe="${exe}"
        fi
      fi
    done < <(find "${search_root}" -type f \( -iname '*.exe' \) 2>/dev/null)
  done < <(printf '%s\n' "${root}"; import_list_game_subroots "${root}")

  [[ -n "${best_exe}" ]] || return 1
  printf '%s' "${best_exe}"
  return 0
}

# Describe chosen executable: path<TAB>source<TAB>score
import_describe_game_exe() {
  local root="$1" hint="${2:-}"
  local info_exe score
  [[ -d "${root}" ]] || return 1

  info_exe="$(import_gog_find_info_exe "${root}" 2>/dev/null || true)"
  if [[ -n "${info_exe}" ]]; then
    score="$(import_score_exe "${root}" "${info_exe}" "${hint}" 2>/dev/null || echo 0)"
    printf '%s\tgoggame-info\t%s\n' "${info_exe}" "${score}"
    return 0
  fi

  info_exe="$(import_find_best_game_exe "${root}" "${hint}")" || return 1
  score="$(import_score_exe "${root}" "${info_exe}" "${hint}" 2>/dev/null || echo 0)"
  printf '%s\tscored\t%s\n' "${info_exe}" "${score}"
}

# Find the main game .exe under a directory (skip uninstall/setup/redist helpers).
import_find_game_exe() {
  local root="$1" hint="${2:-}"
  import_find_best_game_exe "${root}" "${hint}"
}

# --- GOG offline installers (roadmap 0.6) ---

import_gog_games_dirs() {
  local pfx="$1"
  local dir
  for dir in \
    "${pfx}/drive_c/GOG Games" \
    "${pfx}/drive_c/Program Files (x86)/GOG Galaxy/Games" \
    "${pfx}/drive_c/Program Files/GOG Galaxy/Games"; do
    [[ -d "${dir}" ]] && printf '%s\n' "${dir}"
  done
}

# Pick the most recently modified game folder under GOG install roots.
import_gog_newest_game_dir() {
  local pfx="$1"
  local root game_dir best_dir="" best_mtime=0 mtime
  while IFS= read -r root; do
    [[ -d "${root}" ]] || continue
    shopt -s nullglob
    for game_dir in "${root}"/*; do
      [[ -d "${game_dir}" ]] || continue
      mtime="$(stat -f %m "${game_dir}" 2>/dev/null || stat -c %Y "${game_dir}" 2>/dev/null || echo 0)"
      if (( mtime >= best_mtime )); then
        best_mtime="${mtime}"
        best_dir="${game_dir}"
      fi
    done
    shopt -u nullglob
  done < <(import_gog_games_dirs "${pfx}")
  [[ -n "${best_dir}" ]] && printf '%s' "${best_dir}"
}

# Find the main game .exe after a GOG offline install.
import_find_gog_game_exe() {
  local pfx="$1" game_name="${2:-}"
  local root game_dir exe hint_dir="" hint

  if [[ -n "${game_name}" ]]; then
    hint="$(import_slugify "${game_name}")"
    while IFS= read -r root; do
      [[ -d "${root}" ]] || continue
      shopt -s nullglob
      for game_dir in "${root}"/*; do
        [[ -d "${game_dir}" ]] || continue
        if printf '%s' "$(basename "${game_dir}")" | grep -Eqi "${game_name// /[[:space:]]+}"; then
          hint_dir="${game_dir}"
          break 2
        fi
        if [[ "$(import_slugify "$(basename "${game_dir}")")" == *"${hint}"* ]]; then
          hint_dir="${game_dir}"
        fi
      done
      shopt -u nullglob
    done < <(import_gog_games_dirs "${pfx}")
  fi

  if [[ -z "${hint_dir}" ]]; then
    hint_dir="$(import_gog_newest_game_dir "${pfx}" || true)"
  fi
  [[ -n "${hint_dir}" ]] || return 1
  exe="$(import_find_best_game_exe "${hint_dir}" "${game_name}")" && {
    printf '%s' "${exe}"
    return 0
  }
  return 1
}

# Print lines: slug<TAB>title<TAB>exe_relative_path[<TAB>source<TAB>score]
import_scan_gog_games() {
  local pfx="$1" with_meta="${2:-0}"
  local root game_dir slug title exe meta source score
  while IFS= read -r root; do
    [[ -d "${root}" ]] || continue
    shopt -s nullglob
    for game_dir in "${root}"/*; do
      [[ -d "${game_dir}" ]] || continue
      title="$(basename "${game_dir}")"
      if [[ "${with_meta}" == "1" ]]; then
        meta="$(import_describe_game_exe "${game_dir}" "${title}" 2>/dev/null || true)"
        [[ -n "${meta}" ]] || continue
        IFS=$'\t' read -r exe source score <<< "${meta}"
      else
        exe="$(import_find_best_game_exe "${game_dir}" "${title}" 2>/dev/null || true)"
        [[ -n "${exe}" ]] || continue
        source=""; score=""
      fi
      slug="$(import_slugify "${title}")"
      if [[ "${with_meta}" == "1" ]]; then
        printf '%s\t%s\t%s\t%s\t%s\n' "${slug}" "${title}" "${exe#${pfx}/}" "${source}" "${score}"
      else
        printf '%s\t%s\t%s\n' "${slug}" "${title}" "${exe#${pfx}/}"
      fi
    done
    shopt -u nullglob
  done < <(import_gog_games_dirs "${pfx}")
}

import_write_gog_config() {
  local configs_dir="$1" slug="$2" app_name="$3" bundle_id="$4" exe_path="$5"
  local file="${configs_dir}/gog-${slug}.conf"
  mkdir -p "${configs_dir}"
  {
    printf '# Created by import_game.command (GOG offline installer)\n'
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
  exe="$(import_find_best_game_exe "${install_dir}" "${app_name}")" && {
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

import_write_itch_config() {
  local configs_dir="$1" slug="$2" app_name="$3" bundle_id="$4" exe_path="$5"
  local file="${configs_dir}/itch-${slug}.conf"
  mkdir -p "${configs_dir}"
  {
    printf '# Created by import_game.command (itch.io)\n'
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

# --- Battle.net / Blizzard (roadmap 0.6+) ---

import_find_battlenet_launcher() {
  local pfx="$1"
  local candidate
  for candidate in \
    "${pfx}/drive_c/Program Files (x86)/Battle.net/Battle.net Launcher.exe" \
    "${pfx}/drive_c/Program Files (x86)/Battle.net/Battle.net.exe" \
    "${pfx}/drive_c/Program Files/Battle.net/Battle.net Launcher.exe" \
    "${pfx}/drive_c/Program Files/Battle.net/Battle.net.exe"; do
    if [[ -f "${candidate}" ]]; then
      printf '%s' "${candidate#${pfx}/}"
      return 0
    fi
  done
  return 1
}

# Known Blizzard game install folder names under Program Files.
import_battlenet_game_dirs() {
  printf '%s\n' \
    'StarCraft II' \
    'Diablo III' \
    'Diablo IV' \
    'Hearthstone' \
    'Heroes of the Storm' \
    'Overwatch' \
    'World of Warcraft' \
    'Call of Duty'
}

# Print lines: slug<TAB>title<TAB>exe_relative_path
import_scan_battlenet_games() {
  local pfx="$1"
  local root dir slug title exe
  for root in \
    "${pfx}/drive_c/Program Files (x86)" \
    "${pfx}/drive_c/Program Files"; do
    [[ -d "${root}" ]] || continue
    while IFS= read -r dir; do
      [[ -n "${dir}" ]] || continue
      [[ -d "${root}/${dir}" ]] || continue
      exe="$(import_find_best_game_exe "${root}/${dir}" "${dir}" 2>/dev/null || true)"
      [[ -n "${exe}" ]] || continue
      slug="$(import_slugify "${dir}")"
      title="${dir}"
      printf '%s\t%s\t%s\n' "${slug}" "${title}" "${exe#${pfx}/}"
    done < <(import_battlenet_game_dirs)
  done
}

import_write_battlenet_config() {
  local configs_dir="$1" slug="$2" app_name="$3" bundle_id="$4" exe_path="$5" launcher_path="${6:-}"
  local file="${configs_dir}/battlenet-${slug}.conf"
  mkdir -p "${configs_dir}"
  {
    printf '# Created by import_game.command (Battle.net)\n'
    printf 'APP_NAME="%s (Cosmos)"\n' "$(import_safe_name "${app_name}")"
    printf 'BUNDLE_ID="%s"\n' "${bundle_id}"
    printf '\nRUN_ENV_NAMES=(\n'
    printf '  GAME_EXE_PATH\n'
    printf '  COSMOS_SKIP_STEAM\n'
    if [[ -n "${launcher_path}" ]]; then
      printf '  BATTLENET_LAUNCHER_EXE\n'
    fi
    printf ')\n\n'
    printf 'GAME_EXE_PATH="%s"\n' "${exe_path}"
    printf 'COSMOS_SKIP_STEAM="1"\n'
    if [[ -n "${launcher_path}" ]]; then
      printf 'BATTLENET_LAUNCHER_EXE="%s"\n' "${launcher_path}"
    fi
  } > "${file}"
  printf '%s' "${file}"
}
