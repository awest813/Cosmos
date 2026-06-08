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

Examples:
  import_game.command run-installer ~/Downloads/GameSetup.exe
  import_game.command add-exe "drive_c/Games/MyGame/game.exe" --name "My Game"
  import_game.command add-gog ~/Downloads/setup_foo_1.2.3.exe --name "Foo"
  import_game.command add-itch ~/Downloads/GameName --name "Game Name"
  import_game.command list

After adding, run ./install_cosmos.command to build the .app launcher.
EOF
}

cmd_list() {
  local f
  shopt -s nullglob
  for f in "${CONFIGS_DIR}"/standalone-*.conf; do
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
        die "Path must be inside WINEPREFIX (${WINEPREFIX}) or use drive_c/... form"
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

main() {
  local cmd="${1:-}"; shift || true
  case "${cmd}" in
    list) cmd_list ;;
    add-exe) cmd_add_exe "$@" ;;
    run-installer) cmd_run_installer "$@" ;;
    add-gog) cmd_add_gog "$@" ;;
    add-itch) cmd_add_itch "$@" ;;
    ""|--help|-h|help) usage ;;
    *) die "Unknown command: ${cmd}" ;;
  esac
}

main "$@"
