#!/usr/bin/env bash
set -euo pipefail

# Cosmos game library — standardized install paths and unified registry.
#
# Cosmos-managed game files live under:
#   <prefix>/drive_c/Games/<store>/<slug>/
#
# A derived manifest is written to:
#   ~/Library/Application Support/Cosmos/library/manifest.json
#
# Usage:
#   library.command init [--bottle <name>]
#   library.command list [--json] [--bottle <name>]
#   library.command scan [--bottle <name>]
#   library.command path <store> <slug> [--bottle <name>]
#   library.command install-dir <store> <slug> [--bottle <name>]

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
COSMOS_SUPPORT_DIR="${COSMOS_SUPPORT_DIR:-$HOME/Library/Application Support/Cosmos}"

# shellcheck source=scripts/lib/steam_lib.sh
source "${SCRIPT_DIR}/scripts/lib/steam_lib.sh"
# shellcheck source=scripts/lib/library_lib.sh
source "${SCRIPT_DIR}/scripts/lib/library_lib.sh"

WINEPREFIX="${WINEPREFIX:-$HOME/.wine-steam-11}"
COSMOS_BOTTLE="${COSMOS_BOTTLE:-}"

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

resolve_prefix() {
  local bottle="${1:-${COSMOS_BOTTLE}}"
  if [[ -n "${bottle}" && -x "${SCRIPT_DIR}/bottle.command" ]]; then
    "${SCRIPT_DIR}/bottle.command" path "${bottle}" 2>/dev/null && return 0
  fi
  printf '%s' "${WINEPREFIX}"
}

log() { printf "\n==> %s\n" "$1"; }
die() { printf "Error: %s\n" "$1" >&2; exit 1; }

usage() {
  cat <<'EOF'
Cosmos game library — install paths and unified game registry.

Usage: library.command <command> [args]

Commands:
  init [--bottle <name>]              Create library dirs (drive_c/Games + manifest).
  list [--json] [--bottle <name>]     List installed games across all stores.
  scan [--bottle <name>]              Refresh library/manifest.json from disk.
  path <store> <slug> [--bottle <n>]  Print install path for a registered game.
  install-dir <store> <slug>          Print Cosmos-managed install dir (creates it).

Stores: steam, standalone, itch, gog, battlenet, epic

Cosmos-managed installs use:
  <prefix>/drive_c/Games/<store>/<slug>/

Examples:
  library.command init
  library.command scan --bottle default
  library.command list
  library.command list --json
  library.command path itch my-cool-game
  library.command install-dir standalone demo-game
EOF
}

cmd_init() {
  local bottle=""
  while (($#)); do
    case "$1" in
      --bottle) bottle="${2:-}"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  local pfx
  pfx="$(resolve_prefix "${bottle}")"
  library_ensure_dirs "${pfx}"
  log "Library root: $(library_dir)"
  log "Games root:   $(library_games_root "${pfx}")"
  echo "Run 'library.command scan' to build the game manifest."
}

cmd_list() {
  local bottle="" as_json=0
  while (($#)); do
    case "$1" in
      --json) as_json=1; shift ;;
      --bottle) bottle="${2:-}"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  local pfx configs_dir
  pfx="$(resolve_prefix "${bottle}")"
  configs_dir="$(resolve_configs_dir)"
  WINEPREFIX="${pfx}"

  if (( as_json )); then
    library_emit_json "${configs_dir}" "${pfx}" "${bottle}"
    return 0
  fi

  log "Installed games (prefix: ${pfx})"
  local count
  count="$(library_collect_all "${configs_dir}" "${pfx}" "${bottle}" | wc -l | tr -d ' ')"
  if [[ "${count}" == "0" ]]; then
    echo "  (no games found — run detect_steam_games.command or import_game.command)"
    return 0
  fi
  library_print_list "${configs_dir}" "${pfx}" "${bottle}"
  echo ""
  echo "${count} game(s). Run 'library.command scan' to refresh manifest.json."
}

cmd_scan() {
  local bottle=""
  while (($#)); do
    case "$1" in
      --bottle) bottle="${2:-}"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  local pfx configs_dir manifest
  pfx="$(resolve_prefix "${bottle}")"
  configs_dir="$(resolve_configs_dir)"
  WINEPREFIX="${pfx}"
  log "Scanning games in ${pfx}"
  manifest="$(library_write_manifest "${configs_dir}" "${pfx}" "${bottle}")"
  local count
  count="$(python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("games",[])))' < "${manifest}")"
  log "Wrote ${manifest} (${count} game(s))"
}

cmd_path() {
  local store="${1:-}" slug="${2:-}"
  shift 2 || true
  local bottle=""
  while (($#)); do
    case "$1" in
      --bottle) bottle="${2:-}"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  [[ -n "${store}" && -n "${slug}" ]] \
    || die "Usage: library.command path <store> <slug> [--bottle <name>]"
  local pfx configs_dir id line match
  pfx="$(resolve_prefix "${bottle}")"
  configs_dir="$(resolve_configs_dir)"
  WINEPREFIX="${pfx}"
  id="$(library_make_game_id "${store}" "${slug}")"
  match="$(library_collect_all "${configs_dir}" "${pfx}" "${bottle}" \
    | awk -F'\t' -v id="${id}" '$1==id {print $6; exit}')"
  if [[ -n "${match}" ]]; then
    printf '%s\n' "${match}"
    return 0
  fi
  local managed
  managed="$(library_install_dir "${pfx}" "${store}" "${slug}")"
  if [[ -d "${managed}" ]]; then
    printf '%s\n' "${managed}"
    return 0
  fi
  die "No install path found for ${store}/${slug}"
}

cmd_install_dir() {
  local store="${1:-}" slug="${2:-}"
  shift 2 || true
  local bottle=""
  while (($#)); do
    case "$1" in
      --bottle) bottle="${2:-}"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  [[ -n "${store}" && -n "${slug}" ]] \
    || die "Usage: library.command install-dir <store> <slug> [--bottle <name>]"
  local pfx dir
  pfx="$(resolve_prefix "${bottle}")"
  dir="$(library_install_dir "${pfx}" "${store}" "${slug}")"
  mkdir -p "${dir}"
  printf '%s\n' "${dir}"
}

main() {
  local cmd="${1:-}"; shift || true
  case "${cmd}" in
    init) cmd_init "$@" ;;
    list) cmd_list "$@" ;;
    scan) cmd_scan "$@" ;;
    path) cmd_path "$@" ;;
    install-dir) cmd_install_dir "$@" ;;
    ""|--help|-h|help) usage ;;
    *) die "Unknown command: ${cmd}" ;;
  esac
}

main "$@"
