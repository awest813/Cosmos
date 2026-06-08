#!/usr/bin/env bash
set -euo pipefail

# Cosmos repair engine (roadmap 0.5) — apply dependency and fix recipes.
# Dependencies invoke winetricks (LGPL) as an external tool; see docs/LICENSING.md.

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
RECIPE_LIB="${SCRIPT_DIR}/scripts/lib/recipe_lib.sh"
FIX_LIB="${SCRIPT_DIR}/scripts/repair_fixes.sh"
DIAG_LIB="${SCRIPT_DIR}/scripts/repair_diagnose.sh"
DEPS_DIR="${SCRIPT_DIR}/recipes/dependencies"
FIXES_DIR="${SCRIPT_DIR}/recipes/fixes"
COSMOS_SUPPORT_DIR="${COSMOS_SUPPORT_DIR:-$HOME/Library/Application Support/Cosmos}"

WINEPREFIX="${WINEPREFIX:-$HOME/.wine-steam-11}"
COSMOS_BOTTLE="${COSMOS_BOTTLE:-}"

# Honor named bottles the same way run.command does.
if [[ -n "${COSMOS_BOTTLE}" && -x "${SCRIPT_DIR}/bottle.command" ]]; then
  WINEPREFIX="$("${SCRIPT_DIR}/bottle.command" path "${COSMOS_BOTTLE}" 2>/dev/null || echo "${WINEPREFIX}")"
fi

# shellcheck source=scripts/lib/recipe_lib.sh
source "${RECIPE_LIB}"
# shellcheck source=scripts/repair_fixes.sh
source "${FIX_LIB}"
# shellcheck source=scripts/repair_diagnose.sh
source "${DIAG_LIB}"

log() { printf "\n==> %s\n" "$1"; }
die() { printf "Error: %s\n" "$1" >&2; exit 1; }

usage() {
  cat <<'EOF'
Cosmos repair engine — apply recipes from recipes/dependencies and recipes/fixes.

Usage: repair.command <command> [args]

Commands:
  list-deps                     List dependency recipes (winetricks verbs).
  list-fixes                    List fix recipes.
  diagnose [--log <path>]       Scan prefix health + launch log; suggest fixes.
  install-dep <id>              Run winetricks for a dependency recipe.
  apply-fix <id>                Apply a fix recipe to the current WINEPREFIX.
  install-deps <id> [id...]     Install multiple dependencies.
  apply-fixes <id> [id...]      Apply multiple fixes.

Environment:
  WINEPREFIX          Target prefix (default: ~/.wine-steam-11).
  COSMOS_BOTTLE       Named bottle (overrides WINEPREFIX via bottle.command).
  COSMOS_LOG          Override launch log path for diagnose.
  WINDOWS_VERSION     Required for fix set_windows_version.
  COSMOS_BACKEND      Required for fix set_backend.
  DLL_OVERRIDE        Required for fix dll_override (e.g. ddraw=n,b).
  STEAM_APPID         Optional for set_backend / required for disable_intro_video.
  INTRO_SKIP_ARGS     Optional skip-intro args (default: -novid).
  COSMOS_FORCE        Set to 1 for non-interactive rebuild_prefix.

Winetricks must be installed (brew install winetricks). Cosmos does not bundle it.
EOF
}

find_recipe() {
  local kind="$1" id="$2" dir
  case "${kind}" in
    dependency) dir="${DEPS_DIR}" ;;
    fix) dir="${FIXES_DIR}" ;;
    *) die "Unknown recipe kind: ${kind}" ;;
  esac
  local f="${dir}/${id}.recipe"
  [[ -f "${f}" ]] || die "Recipe not found: ${id} (expected ${f})"
  printf '%s' "${f}"
}

ensure_winetricks() {
  command -v winetricks >/dev/null 2>&1 || die "winetricks not found. Install with: brew install winetricks"
  export WINEPREFIX
  if [[ -n "${WINE_BIN:-}" ]]; then
    export PATH="$(dirname "${WINE_BIN}"):${PATH}"
  fi
}

cmd_install_dep() {
  local id="${1:-}"; [[ -n "${id}" ]] || die "Usage: repair.command install-dep <id>"
  local file; file="$(find_recipe dependency "${id}")"
  recipe_load "${file}" || die "Invalid recipe: ${file}"
  [[ -n "${RECIPE_WINETRICKS}" ]] || die "Recipe ${id} has no WINETRICKS verb."
  ensure_winetricks
  log "Installing dependency ${id} (${RECIPE_WINETRICKS}) into ${WINEPREFIX}"
  winetricks -q "${RECIPE_WINETRICKS}"
  echo "Done: ${RECIPE_DESCRIPTION}"
}

cmd_apply_fix() {
  local id="${1:-}"; [[ -n "${id}" ]] || die "Usage: repair.command apply-fix <id>"
  local file; file="$(find_recipe fix "${id}")"
  recipe_load "${file}" || die "Invalid recipe: ${file}"
  export WINEPREFIX SCRIPT_DIR
  log "Applying fix ${id} on ${WINEPREFIX}"
  case "${RECIPE_SCRIPT}" in
    kill_wine) repair_kill_wine ;;
    clear_steam_caches) repair_clear_steam_caches ;;
    set_windows_version) repair_set_windows_version ;;
    disable_retina) repair_disable_retina ;;
    dll_override) repair_dll_override ;;
    rebuild_prefix) repair_rebuild_prefix ;;
    force_borderless) repair_force_borderless ;;
    disable_intro_video) repair_disable_intro_video ;;
    set_backend) repair_set_backend ;;
    *)
      die "Unknown fix script '${RECIPE_SCRIPT}' for ${id}"
      ;;
  esac
}

cmd_diagnose() {
  local log_file=""
  while (($#)); do
    case "$1" in
      --log)
        log_file="${2:-}"
        [[ -n "${log_file}" ]] || die "Usage: repair.command diagnose [--log <path>]"
        shift 2
        ;;
      *)
        die "Unknown diagnose option: $1"
        ;;
    esac
  done
  export WINEPREFIX COSMOS_BOTTLE COSMOS_SUPPORT_DIR SCRIPT_DIR
  log "Diagnosing prefix and launch log"
  repair_diagnose_run "${log_file}"
}

cmd_list_deps() {
  log "Dependency recipes"
  recipe_list_dir "${DEPS_DIR}" dependency
}

cmd_list_fixes() {
  log "Fix recipes"
  recipe_list_dir "${FIXES_DIR}" fix
}

main() {
  local cmd="${1:-}"; shift || true
  case "${cmd}" in
    list-deps) cmd_list_deps ;;
    list-fixes) cmd_list_fixes ;;
    diagnose) cmd_diagnose "$@" ;;
    install-dep) cmd_install_dep "$@" ;;
    apply-fix) cmd_apply_fix "$@" ;;
    install-deps)
      local id
      for id in "$@"; do cmd_install_dep "${id}"; done
      ;;
    apply-fixes)
      local id
      for id in "$@"; do cmd_apply_fix "${id}"; done
      ;;
    ""|--help|-h|help) usage ;;
    *) die "Unknown command: ${cmd} (try: repair.command --help)" ;;
  esac
}

main "$@"
