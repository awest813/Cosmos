#!/usr/bin/env bash
set -euo pipefail

# Cosmos repair engine (roadmap 0.5) — apply dependency and fix recipes.
# Dependencies invoke winetricks (LGPL) as an external tool; see docs/LICENSING.md.

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
RECIPE_LIB="${SCRIPT_DIR}/scripts/lib/recipe_lib.sh"
FIX_LIB="${SCRIPT_DIR}/scripts/repair_fixes.sh"
DIAG_LIB="${SCRIPT_DIR}/scripts/repair_diagnose.sh"
REGDIFF_LIB="${SCRIPT_DIR}/scripts/lib/regdiff_lib.sh"
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
# shellcheck source=scripts/lib/regdiff_lib.sh
source "${REGDIFF_LIB}"

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
  suggest [--log <path>]        Print actionable recipe tokens (dep:id / fix:id).
  apply-suggested [--log <path>] Diagnose, then auto-apply safe suggestions.
  install-dep <id>              Run winetricks for a dependency recipe.
  apply-fix <id>                Apply a fix recipe to the current WINEPREFIX.
  install-deps <id> [id...]     Install multiple dependencies.
  apply-fixes <id> [id...]      Apply multiple fixes.
  capture-reg <label>           Snapshot WINEPREFIX/user.reg for later diff.
  diff-reg <old> <new>          Diff two snapshots or .reg files (needs wineregdiff).
  recipe-from-diff <old> <new> [id]
                                Write recipes/fixes/<id>.recipe from a reg diff.

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
  COSMOS_PROFILE_APPID / STEAM_APPID
                      When set, diagnose includes UMU/protonfix recipe hints (offline
                      map + winemactricks). COSMOS_DIAGNOSE_FETCH_UMU=1 fetches live
                      protonfix scripts; COSMOS_UMU_HINT_FIXTURE=<path> for tests.

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
  echo "(winetricks is LGPL-2.1 — external tool; see runtime/WINETRICKS-NOTICE.txt)"
  winetricks -q "${RECIPE_WINETRICKS}"
  echo "Done: ${RECIPE_DESCRIPTION}"
}

cmd_apply_fix() {
  local id="${1:-}"; [[ -n "${id}" ]] || die "Usage: repair.command apply-fix <id>"
  local file; file="$(find_recipe fix "${id}")"
  recipe_load "${file}" || die "Invalid recipe: ${file}"
  export WINEPREFIX SCRIPT_DIR RECIPE_DLL_OVERRIDE RECIPE_REG_COMMANDS
  [[ -z "${DLL_OVERRIDE:-}" && -n "${RECIPE_DLL_OVERRIDE:-}" ]] && export DLL_OVERRIDE="${RECIPE_DLL_OVERRIDE}"
  log "Applying fix ${id} on ${WINEPREFIX}"
  case "${RECIPE_SCRIPT}" in
    kill_wine) repair_kill_wine ;;
    clear_steam_caches) repair_clear_steam_caches ;;
    clear_steam_download_cache) repair_clear_steam_download_cache ;;
    set_windows_version) repair_set_windows_version ;;
    disable_retina) repair_disable_retina ;;
    dll_override) repair_dll_override ;;
    apply_reg_commands) repair_apply_reg_commands ;;
    rebuild_prefix) repair_rebuild_prefix ;;
    force_borderless) repair_force_borderless ;;
    disable_intro_video) repair_disable_intro_video ;;
    set_backend) repair_set_backend ;;
    reinstall_steam) repair_reinstall_steam ;;
    install_steamwebhelper_wrapper) repair_install_steamwebhelper_wrapper ;;
    seed_japanese_fonts) repair_seed_japanese_fonts ;;
    fix_steam_ssl) repair_fix_steam_ssl ;;
    fix_steam_cloud_paths) repair_fix_steam_cloud_paths ;;
    *)
      die "Unknown fix script '${RECIPE_SCRIPT}' for ${id}"
      ;;
  esac
}

repair_parse_log_flag() {
  local _var="$1"
  shift
  local log_file=""
  while (($#)); do
    case "$1" in
      --log)
        log_file="${2:-}"
        [[ -n "${log_file}" ]] || die "Missing value for --log"
        shift 2
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done
  printf -v "${_var}" '%s' "${log_file}"
}

cmd_diagnose() {
  local log_file=""
  repair_parse_log_flag log_file "$@"
  export WINEPREFIX COSMOS_BOTTLE COSMOS_SUPPORT_DIR SCRIPT_DIR \
    COSMOS_PROFILE_APPID STEAM_APPID
  log "Diagnosing prefix and launch log"
  repair_diagnose_run "${log_file}"
}

cmd_suggest() {
  local log_file=""
  repair_parse_log_flag log_file "$@"
  export WINEPREFIX COSMOS_BOTTLE COSMOS_SUPPORT_DIR SCRIPT_DIR \
    COSMOS_PROFILE_APPID STEAM_APPID
  repair_diagnose_run "${log_file}" >/dev/null
  repair_diagnose_print_suggestions
}

cmd_apply_suggested() {
  local log_file=""
  repair_parse_log_flag log_file "$@"
  export WINEPREFIX COSMOS_BOTTLE COSMOS_SUPPORT_DIR SCRIPT_DIR \
    COSMOS_PROFILE_APPID STEAM_APPID
  repair_diagnose_run "${log_file}" >/dev/null
  local token applied=0 skipped=0
  if ((${#DIAG_SUGGESTIONS[@]} == 0)); then
    echo "No auto-applicable suggestions."
    return 0
  fi
  log "Applying safe suggestions (${#DIAG_SUGGESTIONS[@]} found)"
  for token in "${DIAG_SUGGESTIONS[@]}"; do
    if ! repair_suggestion_is_auto_applicable "${token}"; then
      echo "  skip   ${token} (needs manual env or confirmation)"
      skipped=$((skipped + 1))
      continue
    fi
    case "${token}" in
      dep:*)
        cmd_install_dep "${token#dep:}" || true
        applied=$((applied + 1))
        ;;
      fix:*)
        cmd_apply_fix "${token#fix:}" || true
        applied=$((applied + 1))
        ;;
    esac
  done
  echo "Applied ${applied} suggestion(s); skipped ${skipped}."
}

cmd_list_deps() {
  log "Dependency recipes"
  recipe_list_dir "${DEPS_DIR}" dependency
}

cmd_list_fixes() {
  log "Fix recipes"
  recipe_list_dir "${FIXES_DIR}" fix
}

cmd_capture_reg() {
  local label="${1:-}"
  [[ -n "${label}" ]] || die "Usage: repair.command capture-reg <label>"
  export WINEPREFIX
  regdiff_capture_user_reg "${label}"
}

cmd_diff_reg() {
  local old="${1:-}" new="${2:-}"
  [[ -n "${old}" && -n "${new}" ]] || die "Usage: repair.command diff-reg <old> <new>"
  local old_file new_file
  old_file="$(regdiff_resolve_reg_file "${old}")" || exit 1
  new_file="$(regdiff_resolve_reg_file "${new}")" || exit 1
  regdiff_run_diff "${old_file}" "${new_file}"
}

cmd_recipe_from_diff() {
  local old="${1:-}" new="${2:-}" id="${3:-}"
  [[ -n "${old}" && -n "${new}" ]] || die "Usage: repair.command recipe-from-diff <old> <new> [id]"
  local old_file new_file output desc recipe_path
  old_file="$(regdiff_resolve_reg_file "${old}")" || exit 1
  new_file="$(regdiff_resolve_reg_file "${new}")" || exit 1
  if [[ -z "${id}" ]]; then
    id="custom-$(regdiff_sanitize_label "${old}")-to-$(regdiff_sanitize_label "${new}")"
  fi
  output="$(regdiff_run_diff "${old_file}" "${new_file}")" || exit 1
  [[ -n "${output}" ]] || die "No registry differences found."
  desc="Registry diff from ${old} to ${new}"
  recipe_path="${FIXES_DIR}/${id}.recipe"
  mapfile -t cmds < <(printf '%s\n' "${output}")
  regdiff_commands_to_recipe "${id}" "${desc}" "${cmds[@]}" > "${recipe_path}"
  echo "Wrote ${recipe_path}"
  echo "Review the recipe, then: ./repair.command apply-fix ${id}"
}

main() {
  local cmd="${1:-}"; shift || true
  case "${cmd}" in
    list-deps) cmd_list_deps ;;
    list-fixes) cmd_list_fixes ;;
    diagnose) cmd_diagnose "$@" ;;
    suggest) cmd_suggest "$@" ;;
    apply-suggested) cmd_apply_suggested "$@" ;;
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
    capture-reg) cmd_capture_reg "$@" ;;
    diff-reg) cmd_diff_reg "$@" ;;
    recipe-from-diff) cmd_recipe_from_diff "$@" ;;
    ""|--help|-h|help) usage ;;
    *) die "Unknown command: ${cmd} (try: repair.command --help)" ;;
  esac
}

main "$@"
