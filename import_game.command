#!/usr/bin/env bash
set -euo pipefail

# Cosmos store importer (roadmap 0.6) — add non-Steam Windows games.
# See docs/STORE_IMPORT.md.

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
IMPORT_LIB="${SCRIPT_DIR}/scripts/lib/import_lib.sh"
LIBRARY_LIB="${SCRIPT_DIR}/scripts/lib/library_lib.sh"
COSMOS_SUPPORT_DIR="${COSMOS_SUPPORT_DIR:-$HOME/Library/Application Support/Cosmos}"

# shellcheck source=scripts/lib/import_lib.sh
source "${IMPORT_LIB}"
# shellcheck source=scripts/lib/library_lib.sh
source "${LIBRARY_LIB}"

resolve_configs_dir() {
  if [[ -n "${COSMOS_CONFIGS_DIR:-}" ]]; then
    printf '%s' "${COSMOS_CONFIGS_DIR}"
    return
  fi
  local bundled="${SCRIPT_DIR}/cosmos_configs"
  if [[ "${SCRIPT_DIR}" == *.app/Contents/Resources ]]; then
    local data="${COSMOS_SUPPORT_DIR}/cosmos_configs"
    mkdir -p "${data}"
    if [[ -d "${bundled}" ]]; then
      cp -Rn "${bundled}/." "${data}/" 2>/dev/null || true
    fi
    printf '%s' "${data}"
    return
  fi
  printf '%s' "${bundled}"
}

CONFIGS_DIR="$(resolve_configs_dir)"
WINEPREFIX="${WINEPREFIX:-$HOME/.wine-steam-11}"
COSMOS_BOTTLE="${COSMOS_BOTTLE:-}"

if [[ -n "${COSMOS_BOTTLE}" && -x "${SCRIPT_DIR}/bottle.command" ]]; then
  WINEPREFIX="$("${SCRIPT_DIR}/bottle.command" path "${COSMOS_BOTTLE}" 2>/dev/null || echo "${WINEPREFIX}")"
fi

log() { printf "\n==> %s\n" "$1"; }
die() { printf "Error: %s\n" "$1" >&2; exit 1; }

import_refresh_library() {
  [[ -x "${SCRIPT_DIR}/library.command" ]] || return 0
  COSMOS_BOTTLE="${COSMOS_BOTTLE}" WINEPREFIX="${WINEPREFIX}" \
    "${SCRIPT_DIR}/library.command" scan ${COSMOS_BOTTLE:+--bottle "${COSMOS_BOTTLE}"} >/dev/null 2>&1 || true
}

usage() {
  cat <<'EOF'
Cosmos store importer — add non-Steam Windows games.

Usage: import_game.command <command> [args]

Commands:
  list                          List non-Steam launcher configs.
  list-gog [--json]               List GOG games detected under drive_c/GOG Games.
  sync-gog [--build]              Register all detected GOG games missing launcher configs.
  find-exe <folder> [--name <hint>] [--json]
                                Detect the main game .exe (GOG metadata or scored scan).
  add-exe <path> --name <title> [--slug <id>] [--bottle <name>]
                                Register an installed .exe as a Cosmos launcher.
  run-installer <file>        Run a Windows .exe/.msi installer in the prefix.
  add-gog <setup|slug|path> --name <title> [--slug <id>] [--bottle <name>]
                                Run a GOG offline installer or register an installed game.
  add-itch <folder> --name <title> [--slug <id>]
                                Find a .exe in an itch.io download folder and register it.
  install-battlenet <setup.exe> [--bottle <name>]
                                Install the Battle.net desktop app in the prefix.
  list-battlenet                  List Blizzard games detected in the prefix.
  add-battlenet <path|slug> --name <title> [--slug <id>] [--bottle <name>]
                                Register a Battle.net game (exe path or slug from list-battlenet).
  list-epic                       List Epic games via Legendary (Windows builds).
  auth-epic                       Authenticate Legendary with your Epic account.
  add-epic <app-name> --name <title> [--install] [--slug <id>] [--bottle <name>]
                                Install/register an Epic game via Legendary.

Examples:
  import_game.command run-installer ~/Downloads/GameSetup.exe
  import_game.command add-exe "drive_c/Games/MyGame/game.exe" --name "My Game"
  import_game.command add-gog ~/Downloads/setup_foo_1.2.3.exe --name "Foo"
  import_game.command add-itch ~/Downloads/GameName --name "Game Name"
  import_game.command install-battlenet ~/Downloads/Battle.net-Setup.exe
  import_game.command list-battlenet
  import_game.command add-battlenet starcraft-ii --name "StarCraft II"
  import_game.command auth-epic
  import_game.command list-epic
  import_game.command add-epic Sugar --name "Super Meat Boy" --install
  import_game.command list

Requires legendary (brew install legendary-gl, or pip install legendary-gl).

After adding, run ./install_cosmos.command to build the .app launcher.
EOF
}

legendary_die() {
  die "legendary not found. Install with: brew install legendary-gl  OR  pip install legendary-gl"
}

cmd_list() {
  local f
  shopt -s nullglob
  for f in "${CONFIGS_DIR}"/standalone-*.conf "${CONFIGS_DIR}"/gog-*.conf \
           "${CONFIGS_DIR}"/itch-*.conf "${CONFIGS_DIR}"/battlenet-*.conf \
           "${CONFIGS_DIR}"/epic-*.conf; do
    [[ -f "${f}" ]] || continue
    local name exe
    name="$(sed -n 's/^APP_NAME="\{0,1\}\(.*\) (Cosmos)"\{0,1\}$/\1/p' "${f}" | head -n1)"
    exe="$(sed -n 's/^GAME_EXE_PATH="\{0,1\}\(.*\)"\{0,1\}$/\1/p' "${f}" | head -n1)"
    printf '  %-40s %s\n' "${name:-${f##*/}}" "${exe:-?}"
  done
  shopt -u nullglob
}

cmd_run_installer() {
  local installer="${1:-}"
  [[ -n "${installer}" && -f "${installer}" ]] \
    || die "Usage: import_game.command run-installer <file.exe|.msi>"
  [[ -x "${SCRIPT_DIR}/run.command" ]] || die "run.command not found"
  log "Running installer in ${WINEPREFIX}"
  env COSMOS_BOTTLE="${COSMOS_BOTTLE}" WINEPREFIX="${WINEPREFIX}" COSMOS_SKIP_STEAM=1 \
    "${SCRIPT_DIR}/run.command" --run-installer "${installer}"
  echo "Installer finished. Detect the game .exe, then register it:"
  echo "  ./import_game.command find-exe drive_c/GOG\\ Games --name \"Game Title\""
  echo "  ./import_game.command add-exe <path-or-folder> --name \"Game Title\""
}

cmd_add_exe() {
  local path="" name="" slug="" bottle=""
  path="${1:-}"
  shift || true
  while (($#)); do
    case "$1" in
      --name) name="${2:-}"; shift 2 ;;
      --slug) slug="${2:-}"; shift 2 ;;
      --bottle) bottle="${2:-}"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  [[ -n "${path}" ]] || die "Usage: import_game.command add-exe <path> --name <title>"
  [[ -n "${name}" ]] || die "--name is required"
  [[ -n "${bottle}" ]] && COSMOS_BOTTLE="${bottle}" \
    && WINEPREFIX="$("${SCRIPT_DIR}/bottle.command" path "${COSMOS_BOTTLE}" 2>/dev/null || echo "${WINEPREFIX}")"

  local exe_path="${path}" host_check=""
  if [[ "${path}" != drive_c/* ]]; then
    if [[ -f "${path}" ]]; then
      host_check="${path}"
      local rel="${path#${WINEPREFIX}/}"
      if [[ "${rel}" != "${path}" ]]; then
        exe_path="${rel}"
      else
        # Host paths (e.g. Legendary ~/Games/...) are allowed for direct Wine launch.
        exe_path="${path}"
      fi
    elif [[ -d "${path}" ]]; then
      local found
      found="$(import_describe_game_exe "${path}" "${name}" 2>/dev/null || true)"
      [[ -n "${found}" ]] || die "No game .exe found under ${path}. Try: find-exe \"${path}\" --name \"${name}\""
      IFS=$'\t' read -r host_check _ _ <<< "${found}"
      exe_path="${host_check#${WINEPREFIX}/}"
      [[ "${exe_path}" == "${host_check}" ]] || host_check="${WINEPREFIX}/${exe_path}"
    else
      die "Executable not found: ${path}"
    fi
  else
    host_check="${WINEPREFIX}/${path}"
  fi

  if [[ -n "${host_check}" && -f "${host_check}" ]]; then
    import_exe_is_helper "$(basename "${host_check}")" \
      && die "That looks like a helper/redistributable binary, not the game. Run: find-exe on the install folder."
    import_exe_has_pe_header "${host_check}" \
      || die "File does not look like a Windows PE executable: ${host_check}"
  fi

  [[ -n "${slug}" ]] || slug="$(import_slugify "${name}")"
  local bundle_id="com.cosmos.standalone-${slug}"
  local file
  file="$(import_write_config "${CONFIGS_DIR}" "${slug}" "${name}" "${bundle_id}" "${exe_path}")"
  log "Wrote ${file}"
  import_refresh_library
  echo "Next: ./install_cosmos.command ${file##*/}"
}

cmd_list_gog() {
  local as_json=0
  while (($#)); do
    case "$1" in
      --json) as_json=1; shift ;;
      *) die "Unknown option: $1 (try: list-gog [--json])" ;;
    esac
  done

  if [[ "${as_json}" -eq 1 ]]; then
    local tmp
    tmp="$(mktemp)"
    import_scan_gog_games "${WINEPREFIX}" 1 >"${tmp}" || true
    python3 - "${tmp}" "${CONFIGS_DIR}" <<'PY'
import json, os, sys
games = []
configs_dir = sys.argv[2]
with open(sys.argv[1], encoding="utf-8") as fh:
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 3 and parts[0]:
            slug = parts[0]
            item = {"slug": slug, "title": parts[1], "exe": parts[2]}
            if len(parts) >= 5:
                item["exe_source"] = parts[3]
                try:
                    item["exe_score"] = int(parts[4])
                except ValueError:
                    pass
            conf = os.path.join(configs_dir, f"gog-{slug}.conf")
            item["config_registered"] = os.path.isfile(conf)
            games.append(item)
print(json.dumps(games))
PY
    rm -f "${tmp}"
    return 0
  fi

  log "Detected GOG games in ${WINEPREFIX}"
  local found=0 line slug title exe
  while IFS=$'\t' read -r slug title exe; do
    [[ -n "${slug}" ]] || continue
    found=1
    printf '  %-24s %-28s %s\n' "${slug}" "${title}" "${exe}"
  done < <(import_scan_gog_games "${WINEPREFIX}")
  if [[ "${found}" -eq 0 ]]; then
    echo "  (no GOG game folders with .exe found)"
    echo "Install with: ./import_game.command add-gog <setup.exe> --name \"Game Title\""
    echo "GOG offline installers place games under drive_c/GOG Games/ by default."
  fi
}

cmd_find_exe() {
  local target="${1:-}"
  shift || true
  local hint="" as_json=0
  while (($#)); do
    case "$1" in
      --name) hint="${2:-}"; shift 2 ;;
      --json) as_json=1; shift ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  [[ -n "${target}" ]] || die "Usage: import_game.command find-exe <folder> [--name <hint>] [--json]"
  local resolved="${target}"
  if [[ "${target}" == drive_c/* ]]; then
    resolved="${WINEPREFIX}/${target}"
  elif [[ ! -d "${target}" && -d "${WINEPREFIX}/${target}" ]]; then
    resolved="${WINEPREFIX}/${target}"
  fi
  [[ -d "${resolved}" ]] || die "Folder not found: ${target}"
  local meta exe source score rel
  meta="$(import_describe_game_exe "${resolved}" "${hint}" 2>/dev/null || true)"
  [[ -n "${meta}" ]] || die "No game .exe detected under ${resolved}"
  IFS=$'\t' read -r exe source score <<< "${meta}"
  rel="${exe#${WINEPREFIX}/}"
  if (( as_json )); then
    python3 - "${rel}" "${source}" "${score}" "${exe}" <<'PY'
import json, sys
print(json.dumps({
    "exe_rel": sys.argv[1],
    "source": sys.argv[2],
    "score": int(sys.argv[3]) if sys.argv[3].isdigit() else 0,
    "exe": sys.argv[4],
}))
PY
    return 0
  fi
  log "Detected game executable"
  printf '  exe:    %s\n' "${rel}"
  printf '  source: %s\n' "${source}"
  printf '  score:  %s\n' "${score}"
  printf '  host:   %s\n' "${exe}"
}

cmd_sync_gog() {
  local build=0
  while (($#)); do
    case "$1" in
      --build) build=1; shift ;;
      *) die "Unknown option: $1 (try: sync-gog [--build])" ;;
    esac
  done

  local slug title exe new_count=0 skipped=0
  local -a new_configs=()
  while IFS=$'\t' read -r slug title exe; do
    [[ -n "${slug}" ]] || continue
    local conf="${CONFIGS_DIR}/gog-${slug}.conf"
    if [[ -f "${conf}" ]]; then
      skipped=$((skipped + 1))
      continue
    fi
    local bundle_id="com.cosmos.gog-${slug}"
    import_write_gog_config "${CONFIGS_DIR}" "${slug}" "${title}" "${bundle_id}" "${exe}" >/dev/null
    new_configs+=("gog-${slug}.conf")
    new_count=$((new_count + 1))
    printf 'registered slug=%s title=%s\n' "${slug}" "${title}"
  done < <(import_scan_gog_games "${WINEPREFIX}")

  import_refresh_library

  if (( build && new_count > 0 )); then
    if [[ "$(uname -s)" == "Darwin" && -x "${SCRIPT_DIR}/install_cosmos.command" ]]; then
      log "Building GOG launchers via install_cosmos.command"
      COSMOS_ALLOW_USER_APPS="${COSMOS_ALLOW_USER_APPS:-1}" \
        "${SCRIPT_DIR}/install_cosmos.command" "${new_configs[@]}"
    else
      echo "Skipped launcher build (macOS + install_cosmos.command required)."
      echo "Next: ./install_cosmos.command ${new_configs[*]}"
    fi
  elif (( new_count > 0 )); then
    echo "Next: ./install_cosmos.command ${new_configs[*]}"
  fi

  if (( new_count > 0 )); then
    printf 'sync_status=updated\n'
  else
    printf 'sync_status=current\n'
  fi
  printf 'sync_new=%s\n' "${new_count}"
  printf 'sync_skipped=%s\n' "${skipped}"
}

cmd_add_gog() {
  local target="${1:-}"
  shift || true
  local name="" slug="" bottle=""
  while (($#)); do
    case "$1" in
      --name) name="${2:-}"; shift 2 ;;
      --slug) slug="${2:-}"; shift 2 ;;
      --bottle) bottle="${2:-}"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  [[ -n "${target}" ]] \
    || die "Usage: import_game.command add-gog <setup.exe|slug|path> --name <title>"
  [[ -n "${name}" ]] || die "--name is required"
  [[ -n "${bottle}" ]] && COSMOS_BOTTLE="${bottle}" \
    && WINEPREFIX="$("${SCRIPT_DIR}/bottle.command" path "${COSMOS_BOTTLE}" 2>/dev/null || echo "${WINEPREFIX}")"

  local exe_path="" exe rel line scan_slug scan_title scan_exe
  if [[ -f "${target}" ]]; then
    cmd_run_installer "${target}"
    exe="$(import_find_gog_game_exe "${WINEPREFIX}" "${name}")" \
      || die "Could not find game .exe after GOG install. Run list-gog or register with add-exe."
    exe_path="${exe#${WINEPREFIX}/}"
  elif [[ "${target}" == drive_c/* ]]; then
    exe_path="${target}"
  else
    scan_slug="$(import_slugify "${target}")"
    while IFS=$'\t' read -r line scan_title scan_exe; do
      [[ "${line}" == "${scan_slug}" ]] || continue
      exe_path="${scan_exe}"
      [[ "${name}" == "${target}" ]] && name="${scan_title}"
      break
    done < <(import_scan_gog_games "${WINEPREFIX}")
    [[ -n "${exe_path}" ]] \
      || die "Could not resolve GOG game '${target}'. Run list-gog or pass an installer/setup path."
  fi

  [[ -n "${slug}" ]] || slug="$(import_slugify "${name}")"
  local bundle_id="com.cosmos.gog-${slug}"
  local file
  file="$(import_write_gog_config "${CONFIGS_DIR}" "${slug}" "${name}" "${bundle_id}" "${exe_path}")"
  log "Wrote ${file}"
  import_refresh_library
  echo "Executable: ${exe_path}"
  echo "Next: ./install_cosmos.command ${file##*/}"
}

cmd_add_itch() {
  local folder="${1:-}"
  shift || true
  local name="" slug=""
  while (($#)); do
    case "$1" in
      --name) name="${2:-}"; shift 2 ;;
      --slug) slug="${2:-}"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  [[ -d "${folder}" ]] || die "Usage: import_game.command add-itch <folder> --name <title>"
  [[ -n "${name}" ]] || die "--name is required"
  [[ -n "${slug}" ]] || slug="$(import_slugify "${name}")"
  local exe host_exe dest
  exe="$(import_find_best_game_exe "${folder}" "${name}")" || die "No .exe found under ${folder}"
  host_exe="$(cd "$(dirname "${exe}")" && pwd)/$(basename "${exe}")"
  dest="$(library_install_dir "${WINEPREFIX}" "itch" "${slug}")"
  mkdir -p "${dest}"
  cp -R "${folder}/." "${dest}/"
  local rel_exe installed
  installed="$(import_find_best_game_exe "${dest}" "${name}")" || die "Copied files but no .exe found in ${dest}"
  rel_exe="${installed#${WINEPREFIX}/}"
  local bundle_id="com.cosmos.itch-${slug}"
  local file
  file="$(import_write_itch_config "${CONFIGS_DIR}" "${slug}" "${name}" "${bundle_id}" "${rel_exe}")"
  log "Wrote ${file}"
  import_refresh_library
  echo "Copied itch.io files to ${dest}"
  echo "Next: ./install_cosmos.command ${file##*/}"
}

cmd_install_battlenet() {
  local installer="${1:-}"
  shift || true
  local bottle=""
  while (($#)); do
    case "$1" in
      --bottle) bottle="${2:-}"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  [[ -n "${installer}" && -f "${installer}" ]] \
    || die "Usage: import_game.command install-battlenet <Battle.net-Setup.exe> [--bottle <name>]"
  [[ -n "${bottle}" ]] && COSMOS_BOTTLE="${bottle}" \
    && WINEPREFIX="$("${SCRIPT_DIR}/bottle.command" path "${COSMOS_BOTTLE}" 2>/dev/null || echo "${WINEPREFIX}")"
  cmd_run_installer "${installer}"
  if import_find_battlenet_launcher "${WINEPREFIX}" >/dev/null 2>&1; then
    echo "Battle.net client installed. Install games in the client, then:"
    echo "  ./import_game.command list-battlenet"
    echo "  ./import_game.command add-battlenet <slug> --name \"Game Title\""
  else
    echo "Installer finished. After installing games in Battle.net, run list-battlenet."
  fi
}

cmd_list_battlenet() {
  local launcher="" line slug title exe
  launcher="$(import_find_battlenet_launcher "${WINEPREFIX}" 2>/dev/null || true)"
  if [[ -n "${launcher}" ]]; then
    printf 'Battle.net launcher: %s\n\n' "${launcher}"
  else
    echo "Battle.net launcher not found in ${WINEPREFIX}."
    echo "Install with: ./import_game.command install-battlenet <Battle.net-Setup.exe>"
    echo ""
  fi
  log "Detected Blizzard games"
  local found=0
  while IFS=$'\t' read -r slug title exe; do
    [[ -n "${slug}" ]] || continue
    found=1
    printf '  %-24s %-28s %s\n' "${slug}" "${title}" "${exe}"
  done < <(import_scan_battlenet_games "${WINEPREFIX}")
  if [[ "${found}" -eq 0 ]]; then
    echo "  (no Blizzard game folders with .exe found)"
    echo "Install games through the Battle.net client, then run list-battlenet again."
  fi
}

cmd_add_battlenet() {
  local target="${1:-}"
  shift || true
  local name="" slug="" bottle=""
  while (($#)); do
    case "$1" in
      --name) name="${2:-}"; shift 2 ;;
      --slug) slug="${2:-}"; shift 2 ;;
      --bottle) bottle="${2:-}"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  [[ -n "${target}" ]] \
    || die "Usage: import_game.command add-battlenet <path|slug> --name <title>"
  [[ -n "${name}" ]] || die "--name is required"
  [[ -n "${bottle}" ]] && COSMOS_BOTTLE="${bottle}" \
    && WINEPREFIX="$("${SCRIPT_DIR}/bottle.command" path "${COSMOS_BOTTLE}" 2>/dev/null || echo "${WINEPREFIX}")"

  local exe_path="" line match_slug match_title match_exe
  if [[ "${target}" == drive_c/* ]]; then
    exe_path="${target}"
  elif [[ -f "${target}" ]]; then
    local rel="${target#${WINEPREFIX}/}"
    if [[ "${rel}" != "${target}" ]]; then
      exe_path="${rel}"
    else
      exe_path="${target}"
    fi
  else
    match_slug="$(import_slugify "${target}")"
    while IFS=$'\t' read -r line match_title match_exe; do
      [[ "${line}" == "${match_slug}" ]] || continue
      exe_path="${match_exe}"
      [[ -z "${name}" || "${name}" == "${target}" ]] && name="${match_title}"
      break
    done < <(import_scan_battlenet_games "${WINEPREFIX}")
  fi
  [[ -n "${exe_path}" ]] \
    || die "Could not resolve Battle.net game '${target}'. Run list-battlenet or pass an .exe path."

  local launcher
  launcher="$(import_find_battlenet_launcher "${WINEPREFIX}" 2>/dev/null || true)"
  [[ -n "${slug}" ]] || slug="$(import_slugify "${name}")"
  local bundle_id="com.cosmos.battlenet-${slug}"
  local file
  file="$(import_write_battlenet_config "${CONFIGS_DIR}" "${slug}" "${name}" "${bundle_id}" "${exe_path}" "${launcher}")"
  log "Wrote ${file}"
  import_refresh_library
  [[ -n "${launcher}" ]] && echo "Battle.net launcher: ${launcher}"
  echo "Executable:    ${exe_path}"
  echo "Next: ./install_cosmos.command ${file##*/}"
}

cmd_list_epic() {
  import_legendary_require || legendary_die
  log "Epic games available (Windows platform)"
  import_legendary_run list --platform Windows || true
  echo ""
  log "Installed via Legendary"
  import_legendary_run list-installed --show-dirs || true
}

cmd_auth_epic() {
  import_legendary_require || legendary_die
  log "Authenticate Legendary with Epic (browser login)"
  import_legendary_run auth
  echo "After auth, run: ./import_game.command list-epic"
}

cmd_add_epic() {
  local legendary_app="${1:-}"
  shift || true
  local name="" slug="" bottle="" do_install=0
  while (($#)); do
    case "$1" in
      --name) name="${2:-}"; shift 2 ;;
      --slug) slug="${2:-}"; shift 2 ;;
      --bottle) bottle="${2:-}"; shift 2 ;;
      --install) do_install=1; shift ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  [[ -n "${legendary_app}" ]] \
    || die "Usage: import_game.command add-epic <app-name> --name <title> [--install]"
  [[ -n "${name}" ]] || die "--name is required"
  import_legendary_require || legendary_die
  [[ -n "${bottle}" ]] && COSMOS_BOTTLE="${bottle}" \
    && WINEPREFIX="$("${SCRIPT_DIR}/bottle.command" path "${COSMOS_BOTTLE}" 2>/dev/null || echo "${WINEPREFIX}")"

  if (( do_install )) || ! import_legendary_is_installed "${legendary_app}"; then
    log "Installing '${legendary_app}' via Legendary (Windows build)"
    import_legendary_run install "${legendary_app}" --platform Windows -y
  fi

  local install_dir exe
  install_dir="$(import_legendary_install_path "${legendary_app}")" \
    || die "Game not installed in Legendary. Try: import_game.command add-epic ${legendary_app} --name \"${name}\" --install"
  exe="$(import_legendary_find_exe "${install_dir}" "${legendary_app}")" \
    || die "Could not find game .exe under ${install_dir}. Register manually with add-exe."

  [[ -n "${slug}" ]] || slug="$(import_slugify "${name}")"
  local bundle_id="com.cosmos.epic-${slug}"
  local file
  file="$(import_write_epic_config "${CONFIGS_DIR}" "${slug}" "${name}" "${bundle_id}" "${exe}" "${legendary_app}")"
  log "Wrote ${file}"
  import_refresh_library
  echo "Epic app name: ${legendary_app}"
  echo "Install dir:   ${install_dir}"
  echo "Executable:    ${exe}"
  echo "Next: ./install_cosmos.command ${file##*/}"
}

main() {
  local cmd="${1:-}"; shift || true
  case "${cmd}" in
    list) cmd_list ;;
    add-exe) cmd_add_exe "$@" ;;
    run-installer) cmd_run_installer "$@" ;;
    add-gog) cmd_add_gog "$@" ;;
    list-gog) cmd_list_gog "$@" ;;
    sync-gog) cmd_sync_gog "$@" ;;
    find-exe) cmd_find_exe "$@" ;;
    add-itch) cmd_add_itch "$@" ;;
    install-battlenet) cmd_install_battlenet "$@" ;;
    list-battlenet) cmd_list_battlenet ;;
    add-battlenet) cmd_add_battlenet "$@" ;;
    list-epic) cmd_list_epic ;;
    auth-epic) cmd_auth_epic ;;
    add-epic) cmd_add_epic "$@" ;;
    ""|--help|-h|help) usage ;;
    *) die "Unknown command: ${cmd}" ;;
  esac
}

main "$@"
