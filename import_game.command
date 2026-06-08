#!/usr/bin/env bash
set -euo pipefail

# Cosmos store importer (roadmap 0.6) — add non-Steam Windows games.
# See docs/STORE_IMPORT.md.

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
IMPORT_LIB="${SCRIPT_DIR}/scripts/lib/import_lib.sh"
COSMOS_SUPPORT_DIR="${COSMOS_SUPPORT_DIR:-$HOME/Library/Application Support/Cosmos}"

# shellcheck source=scripts/lib/import_lib.sh
source "${IMPORT_LIB}"

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

usage() {
  cat <<'EOF'
Cosmos store importer — add non-Steam Windows games.

Usage: import_game.command <command> [args]

Commands:
  list                          List standalone launcher configs.
  add-exe <path> --name <title> [--slug <id>] [--bottle <name>]
                                Register an installed .exe as a Cosmos launcher.
  run-installer <file>        Run a Windows .exe/.msi installer in the prefix.
  add-gog <setup.exe> --name <title> [--slug <id>] [--bottle <name>]
                                Run a GOG offline installer, then register the game.
  add-itch <folder> --name <title> [--slug <id>]
                                Find a .exe in an itch.io download folder and register it.
  list-epic                       List Epic games via Legendary (Windows builds).
  auth-epic                       Authenticate Legendary with your Epic account.
  add-epic <app-name> --name <title> [--install] [--slug <id>] [--bottle <name>]
                                Install/register an Epic game via Legendary.

Examples:
  import_game.command run-installer ~/Downloads/GameSetup.exe
  import_game.command add-exe "drive_c/Games/MyGame/game.exe" --name "My Game"
  import_game.command add-gog ~/Downloads/setup_foo_1.2.3.exe --name "Foo"
  import_game.command add-itch ~/Downloads/GameName --name "Game Name"
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
  for f in "${CONFIGS_DIR}"/standalone-*.conf "${CONFIGS_DIR}"/epic-*.conf; do
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
  echo "Installer finished. Locate the game .exe, then:"
  echo "  ./import_game.command add-exe <path> --name \"Game Title\""
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

  local exe_path="${path}"
  if [[ "${path}" != drive_c/* ]]; then
    if [[ -f "${path}" ]]; then
      local rel="${path#${WINEPREFIX}/}"
      if [[ "${rel}" != "${path}" ]]; then
        exe_path="${rel}"
      else
        # Host paths (e.g. Legendary ~/Games/...) are allowed for direct Wine launch.
        exe_path="${path}"
      fi
    else
      die "Executable not found: ${path}"
    fi
  fi

  [[ -n "${slug}" ]] || slug="$(import_slugify "${name}")"
  local bundle_id="com.cosmos.standalone-${slug}"
  local file
  file="$(import_write_config "${CONFIGS_DIR}" "${slug}" "${name}" "${bundle_id}" "${exe_path}")"
  log "Wrote ${file}"
  echo "Next: ./install_cosmos.command ${file##*/}"
}

cmd_add_gog() {
  local installer="${1:-}"
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
  [[ -n "${installer}" && -f "${installer}" ]] \
    || die "Usage: import_game.command add-gog <setup.exe> --name <title>"
  [[ -n "${name}" ]] || die "--name is required"
  cmd_run_installer "${installer}"
  local games_dir="${WINEPREFIX}/drive_c/GOG Games"
  [[ -d "${games_dir}" ]] || games_dir="${WINEPREFIX}/drive_c/Program Files (x86)/GOG Galaxy/Games"
  [[ -d "${games_dir}" ]] || games_dir="${WINEPREFIX}/drive_c/Program Files/GOG Galaxy/Games"
  local exe
  exe="$(import_find_game_exe "${games_dir}" 2>/dev/null || import_find_game_exe "${WINEPREFIX}/drive_c" || true)"
  [[ -n "${exe}" ]] || die "Could not find game .exe after GOG install. Use add-exe manually."
  local rel="${exe#${WINEPREFIX}/}"
  cmd_add_exe "${rel}" --name "${name}" ${slug:+--slug "${slug}"} ${bottle:+--bottle "${bottle}"}
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
  local exe host_exe
  exe="$(import_find_game_exe "${folder}")" || die "No .exe found under ${folder}"
  host_exe="$(cd "$(dirname "${exe}")" && pwd)/$(basename "${exe}")"
  local dest="${WINEPREFIX}/drive_c/Games/$(import_slugify "${name}")"
  mkdir -p "${dest}"
  cp -R "${folder}/." "${dest}/"
  local rel_exe installed
  installed="$(import_find_game_exe "${dest}")" || die "Copied files but no .exe found in ${dest}"
  rel_exe="${installed#${WINEPREFIX}/}"
  cmd_add_exe "${rel_exe}" --name "${name}" ${slug:+--slug "${slug}"}
  echo "Copied itch.io files to ${dest}"
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
    add-itch) cmd_add_itch "$@" ;;
    list-epic) cmd_list_epic ;;
    auth-epic) cmd_auth_epic ;;
    add-epic) cmd_add_epic "$@" ;;
    ""|--help|-h|help) usage ;;
    *) die "Unknown command: ${cmd}" ;;
  esac
}

main "$@"
