#!/usr/bin/env bash
set -euo pipefail

# Cosmos bottle manager (roadmap milestone 0.3).
#
# A "bottle" is a named, isolated Wine prefix plus its settings (Wine version,
# Windows version, graphics backend, Retina mode, extra env vars). Bottles live
# under ~/Library/Application Support/Cosmos/Bottles/<name>/:
#
#   <name>/
#     bottle.conf   # KEY="value" settings, sourced by run.command as defaults
#     prefix/       # the WINEPREFIX (created on first launch)
#     logs/         # per-bottle launch logs
#
# run.command consumes a bottle when COSMOS_BOTTLE=<name> is set; `bottle.command
# launch <name>` is the convenient front door.

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
if [[ -f "${SCRIPT_DIR}/scripts/lib/prefix_arch.sh" ]]; then
  # shellcheck source=scripts/lib/prefix_arch.sh
  source "${SCRIPT_DIR}/scripts/lib/prefix_arch.sh"
fi
COSMOS_SUPPORT_DIR="${COSMOS_SUPPORT_DIR:-$HOME/Library/Application Support/Cosmos}"
BOTTLES_DIR="${COSMOS_BOTTLES_DIR:-${COSMOS_SUPPORT_DIR}/Bottles}"

VALID_BACKENDS=" recommended dxmt d3dmetal dxvk wined3d spockd3d9 "
VALID_WINDOWS=" winxp win7 win8 win10 win11 "

log() { printf "\n==> %s\n" "$1"; }
die() { printf "Error: %s\n" "$1" >&2; exit 1; }

usage() {
  cat <<'EOF'
Cosmos bottle manager — isolated Wine prefixes with their own settings.

Usage: bottle.command <command> [args]

Commands:
  list                          List all bottles and a one-line summary.
  create <name> [options]       Create a bottle (prefix is built on first launch).
      --wine <version>          Pin a Wine version (e.g. 11.8).
      --windows <ver>           winxp | win7 | win8 | win10 | win11.
      --backend <backend>       recommended | dxmt | d3dmetal | dxvk | wined3d | spockd3d9.
      --arch <layout>           wow64 (default) | win64 | win32.
                                wow64 runs 32-bit programs inside the 64-bit prefix.
      --retina <0|1>            Enable/disable Wine RetinaMode.
  info <name>                   Show a bottle's settings and status.
  set <name> <KEY> <VALUE>      Set/replace a setting (e.g. COSMOS_BACKEND dxmt).
  update <name> --expect-sha256 <hash> <KEY> <VALUE> [...]  Save settings atomically.
  path <name>                   Print the bottle's prefix path.
  launch <name> [run args...]   Launch into the bottle (runs run.command).
  logs <name>                   Show the bottle's latest launch log.
  filesystem <name>             Inspect Windows folders/drive mappings as JSON.
  clone <source> --name <new>    Stop source Wine and clone to a new environment.
  reset <name> [--force]        Delete the prefix only (keep settings/logs).
  delete <name> [--force]       Delete the whole bottle.

Known settings: WINE_VERSION, WINDOWS_VERSION, COSMOS_BACKEND, WINE_RETINA_MODE,
COSMOS_DETACH, GPTK_PATH, DXVK_PATH, plus any UPPER_SNAKE_CASE env var run.command honors.
EOF
}

# Bottle names become directory names, so keep them filesystem-safe.
validate_bottle_name() {
  local name="$1"
  [[ -n "${name}" ]] || die "Bottle name must not be empty."
  [[ "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
    || die "Invalid bottle name '${name}'. Use letters, digits, '.', '_' or '-' (not starting with '.', '_' or '-')."
  [[ "${name}" != *..* ]] || die "Invalid bottle name '${name}'."
}

bottle_dir() { printf '%s' "${BOTTLES_DIR}/$1"; }

require_bottle() {
  local name="$1"
  validate_bottle_name "${name}"
  [[ -d "$(bottle_dir "${name}")" ]] \
    || die "Bottle not found: ${name}. Create it with: bottle.command create ${name}"
}

confirm() {
  local prompt="$1" reply=""
  read -r -p "${prompt} [y/N]: " reply
  [[ "${reply}" == "y" || "${reply}" == "Y" ]]
}

validate_setting() {
  local key="$1" val="$2"
  [[ "${key}" =~ ^[A-Z][A-Z0-9_]*$ ]] || die "Setting name must be UPPER_SNAKE_CASE: ${key}"
  case "${key}" in
    COSMOS_BACKEND)
      [[ "${VALID_BACKENDS}" == *" ${val} "* ]] || die "COSMOS_BACKEND must be one of:${VALID_BACKENDS}"
      ;;
    WINDOWS_VERSION)
      [[ "${VALID_WINDOWS}" == *" ${val} "* ]] || die "WINDOWS_VERSION must be one of:${VALID_WINDOWS}"
      ;;
    WINE_RETINA_MODE|COSMOS_DETACH|COSMOS_METALFX)
      [[ "${val}" == "0" || "${val}" == "1" ]] || die "${key} must be 0 or 1."
      ;;
    COSMOS_SYNC_MODE)
      [[ " off esync msync " == *" ${val} "* ]] || die "COSMOS_SYNC_MODE must be off, esync, or msync."
      ;;
    COSMOS_DXMT_CHANNEL)
      [[ " stable latest experimental " == *" ${val} "* ]] || die "COSMOS_DXMT_CHANNEL must be stable or latest."
      ;;
    COSMOS_ALLOW_LGPL)
      [[ "${val}" == "0" || "${val}" == "1" ]] || die "COSMOS_ALLOW_LGPL must be 0 or 1."
      ;;
    COSMOS_MVK_PRESET)
      [[ " default performance compatibility " == *" ${val} "* ]] || die "COSMOS_MVK_PRESET must be default, performance, or compatibility."
      ;;
    COSMOS_PREFIX_ARCH)
      prefix_arch_normalize "${val}" >/dev/null \
        || die "COSMOS_PREFIX_ARCH must be wow64, win64, or win32."
      ;;
    WINEPREFIX|COSMOS_BOTTLE|WINEARCH)
      die "${key} is managed by Cosmos and cannot be set on a bottle."
      ;;
    *) : ;;
  esac
}

# Insert or replace KEY="value" in a bottle.conf (creating it if needed).
set_setting() {
  local dir="$1" key="$2" val="$3"
  val="${val//\"/}"   # keep the stored value a single clean double-quoted token
  mkdir -p "${dir}"
  local conf="${dir}/bottle.conf"
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/bottle.XXXXXX")"
  local found=0 line
  if [[ -f "${conf}" ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
      if [[ "${line}" == "${key}="* ]]; then
        printf '%s="%s"\n' "${key}" "${val}" >> "${tmp}"
        found=1
      else
        printf '%s\n' "${line}" >> "${tmp}"
      fi
    done < "${conf}"
  else
    printf '# Cosmos bottle settings. Sourced by run.command as defaults.\n' >> "${tmp}"
  fi
  (( found )) || printf '%s="%s"\n' "${key}" "${val}" >> "${tmp}"
  mv "${tmp}" "${conf}"
}

# Read one setting from a bottle.conf (empty if unset).
get_setting() {
  local conf="$1" key="$2" line val
  [[ -f "${conf}" ]] || return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" == "${key}="* ]]; then
      val="${line#*=}"; val="${val%\"}"; val="${val#\"}"
      printf '%s' "${val}"
      return 0
    fi
  done < "${conf}"
}

prefix_status() {
  local dir="$1" pfx="${1}/prefix"
  if [[ -f "${pfx}/system.reg" ]]; then
    if [[ -f "${pfx}/drive_c/Program Files (x86)/Steam/steam.exe" \
       || -f "${pfx}/drive_c/Program Files/Steam/steam.exe" ]]; then
      printf 'ready (Steam installed)'
    else
      printf 'initialized'
    fi
  else
    printf 'not created'
  fi
}

cmd_list() {
  mkdir -p "${BOTTLES_DIR}"
  local found=0 dir name backend
  shopt -s nullglob
  for dir in "${BOTTLES_DIR}"/*/; do
    dir="${dir%/}"
    [[ -f "${dir}/bottle.conf" || -d "${dir}/prefix" ]] || continue
    name="${dir##*/}"
    backend="$(get_setting "${dir}/bottle.conf" COSMOS_BACKEND)"
    printf '  %-20s %-14s %s\n' "${name}" "${backend:-recommended}" "$(prefix_status "${dir}")"
    found=1
  done
  shopt -u nullglob
  (( found )) || echo "No bottles yet. Create one with: bottle.command create <name>"
}

cmd_create() {
  local name="" wine="" windows="" backend="" retina="" arch=""
  while (($#)); do
    case "$1" in
      --wine) wine="${2:-}"; shift 2 ;;
      --windows) windows="${2:-}"; shift 2 ;;
      --backend) backend="${2:-}"; shift 2 ;;
      --arch) arch="${2:-}"; shift 2 ;;
      --retina) retina="${2:-}"; shift 2 ;;
      --*) die "Unknown create option: $1" ;;
      *) [[ -z "${name}" ]] || die "Unexpected argument: $1"; name="$1"; shift ;;
    esac
  done
  validate_bottle_name "${name}"
  [[ -n "${windows}" ]] && validate_setting WINDOWS_VERSION "${windows}"
  [[ -n "${backend}" ]] && validate_setting COSMOS_BACKEND "${backend}"
  [[ -n "${retina}" ]]  && validate_setting WINE_RETINA_MODE "${retina}"
  if [[ -n "${arch}" ]]; then
    arch="$(prefix_arch_normalize "${arch}")" || die "--arch must be wow64, win64, or win32."
  fi

  local dir; dir="$(bottle_dir "${name}")"
  [[ -e "${dir}" ]] && die "Bottle already exists: ${name}"

  mkdir -p "${dir}/logs"
  printf '# Cosmos bottle "%s". Sourced by run.command as defaults.\n' "${name}" > "${dir}/bottle.conf"

  [[ -n "${wine}" ]]    && set_setting "${dir}" WINE_VERSION "${wine}"
  [[ -n "${windows}" ]] && set_setting "${dir}" WINDOWS_VERSION "${windows}"
  [[ -n "${backend}" ]] && set_setting "${dir}" COSMOS_BACKEND "${backend}"
  [[ -n "${arch}" ]]    && set_setting "${dir}" COSMOS_PREFIX_ARCH "${arch}"
  [[ -n "${retina}" ]]  && set_setting "${dir}" WINE_RETINA_MODE "${retina}"

  log "Created bottle '${name}' at ${dir}"
  echo "Launch it with: bottle.command launch ${name}"
}

cmd_info() {
  local name="${1:-}"; require_bottle "${name}"
  local dir; dir="$(bottle_dir "${name}")"
  log "Bottle: ${name}"
  echo "Path:    ${dir}/prefix"
  echo "Status:  $(prefix_status "${dir}")"
  if [[ -d "${dir}/prefix" ]] && command -v du >/dev/null 2>&1; then
    echo "Size:    $(du -sh "${dir}/prefix" 2>/dev/null | cut -f1)"
  fi
  echo "Settings:"
  if [[ -f "${dir}/bottle.conf" ]]; then
    grep -v '^[[:space:]]*#' "${dir}/bottle.conf" | sed '/^[[:space:]]*$/d; s/^/  /' || true
  fi
}

cmd_set() {
  local name="${1:-}" key="${2:-}" val="${3:-}"
  require_bottle "${name}"
  [[ -n "${key}" ]] || die "Usage: bottle.command set <name> <KEY> <VALUE>"
  validate_setting "${key}" "${val}"
  if [[ "${key}" == "COSMOS_PREFIX_ARCH" ]]; then
    val="$(prefix_arch_normalize "${val}")"
  fi
  set_setting "$(bottle_dir "${name}")" "${key}" "${val}"
  echo "Set ${key}=\"${val}\" on bottle '${name}'."
}

cmd_path() {
  local name="${1:-}"; require_bottle "${name}"
  printf '%s\n' "$(bottle_dir "${name}")/prefix"
}

cmd_update() (
  local name="${1:-}" expected="" key value dir conf stage original actual current seen=" "
  require_bottle "${name}"; shift
  [[ $# -ge 4 && "$1" == --expect-sha256 ]] || die "Usage: bottle.command update <name> --expect-sha256 <hash> <KEY> <VALUE> [...]"
  expected="$2"; shift 2
  [[ "${expected}" =~ ^[a-f0-9]{64}$ && $(($# % 2)) == 0 ]] || die "Provide an SHA-256 revision and setting/value pairs."
  dir="$(bottle_dir "${name}")"; conf="${dir}/bottle.conf"
  [[ ! -L "${dir}" && ! -L "${conf}" && -f "${conf}" ]] || die "Linked or missing environment settings cannot be updated here."
  actual="$(shasum -a 256 "${conf}" | awk '{print $1}')"
  [[ "${actual}" == "${expected}" ]] || die "Environment settings changed. Reopen settings before saving."
  local -a pairs=("$@")
  while (($#)); do
    key="$1"; value="$2"; shift 2
    [[ "${seen}" != *" ${key} "* ]] || die "Duplicate setting: ${key}"
    seen="${seen}${key} "
    validate_setting "${key}" "${value}"
    if [[ "${key}" == COSMOS_PREFIX_ARCH && -f "${dir}/prefix/system.reg" ]]; then
      current="$(get_setting "${conf}" COSMOS_PREFIX_ARCH)"; current="${current:-wow64}"
      [[ "$(prefix_arch_normalize "${value}")" == "${current}" ]] || die "Create a new environment to change an initialized prefix's architecture."
    fi
  done
  stage="$(mktemp -d "${dir}/.settings.XXXXXX")"
  trap 'rm -rf "${stage}"' EXIT
  cp -p "${conf}" "${stage}/original"
  cp -p "${conf}" "${stage}/bottle.conf"
  set -- "${pairs[@]}"
  while (($#)); do
    key="$1"; value="$2"; shift 2
    if [[ "${key}" == COSMOS_PREFIX_ARCH ]]; then value="$(prefix_arch_normalize "${value}")"; fi
    set_setting "${stage}" "${key}" "${value}"
  done
  [[ "$(shasum -a 256 "${conf}" | awk '{print $1}')" == "${expected}" ]] \
    && cmp -s "${stage}/original" "${conf}" || die "Environment settings changed while saving. Reopen settings."
  mv "${stage}/bottle.conf" "${conf}"
  echo "Saved environment settings for '${name}'. Existing games and files were kept."
)

cmd_launch() {
  local name="${1:-}"; require_bottle "${name}"
  shift
  [[ -x "${SCRIPT_DIR}/run.command" ]] || die "run.command not found next to bottle.command (${SCRIPT_DIR})."
  exec env COSMOS_BOTTLE="${name}" "${SCRIPT_DIR}/run.command" "$@"
}

cmd_logs() {
  local name="${1:-}"; require_bottle "${name}"
  local dir; dir="$(bottle_dir "${name}")"
  local logf="${dir}/logs/launch.log"
  if [[ -f "${logf}" ]]; then
    echo "Log: ${logf}"
    if command -v open >/dev/null 2>&1; then open "${logf}"; else tail -n 40 "${logf}"; fi
  else
    echo "No log yet for bottle '${name}' (${logf})."
    echo "It is created the first time you launch the bottle in detached mode."
  fi
}

cmd_filesystem() {
  local name="${1:-}"; require_bottle "${name}"
  source "${SCRIPT_DIR}/scripts/lib/wine_filesystem.sh"
  wine_fs_inspect "$(bottle_dir "${name}")/prefix"
}

cmd_clone() {
  local name="${1:-}"; require_bottle "${name}"; shift
  [[ $# == 2 && "$1" == --name ]] || die "Usage: bottle.command clone <source> --name <new>"
  python3 "${SCRIPT_DIR}/scripts/lib/environment_clone.py" "${name}" --name "$2" --bottles-root "${BOTTLES_DIR}"
}

cmd_reset() {
  local name="${1:-}" force="${2:-}"
  require_bottle "${name}"
  local pfx; pfx="$(bottle_dir "${name}")/prefix"
  [[ -e "${pfx}" || -L "${pfx}" ]] || { echo "Bottle '${name}' has no prefix to reset."; return; }
  if [[ "${force}" != "--force" && "${COSMOS_FORCE:-0}" != "1" ]]; then
    if [[ -t 0 ]]; then
      confirm "Delete the prefix for bottle '${name}'? (settings/logs kept)" || { echo "Aborted."; return; }
    else
      die "Refusing to reset non-interactively. Pass --force (or COSMOS_FORCE=1)."
    fi
  fi
  python3 "${SCRIPT_DIR}/scripts/lib/environment_cleanup.py" reset "${name}" --bottles-root "${BOTTLES_DIR}"
}

cmd_delete() {
  local name="${1:-}" force="${2:-}"
  require_bottle "${name}"
  local dir; dir="$(bottle_dir "${name}")"
  if [[ "${force}" != "--force" && "${COSMOS_FORCE:-0}" != "1" ]]; then
    if [[ -t 0 ]]; then
      confirm "Delete bottle '${name}' entirely (${dir})?" || { echo "Aborted."; return; }
    else
      die "Refusing to delete non-interactively. Pass --force (or COSMOS_FORCE=1)."
    fi
  fi
  python3 "${SCRIPT_DIR}/scripts/lib/environment_cleanup.py" delete "${name}" --bottles-root "${BOTTLES_DIR}"
}

main() {
  local command="${1:-}"
  case "${command}" in
    list)           shift; cmd_list "$@" ;;
    create)         shift; cmd_create "$@" ;;
    info)           shift; cmd_info "$@" ;;
    set)            shift; cmd_set "$@" ;;
    update)         shift; cmd_update "$@" ;;
    path)           shift; cmd_path "$@" ;;
    launch)         shift; cmd_launch "$@" ;;
    logs)           shift; cmd_logs "$@" ;;
    filesystem)     shift; cmd_filesystem "$@" ;;
    clone)          shift; cmd_clone "$@" ;;
    reset)          shift; cmd_reset "$@" ;;
    delete)         shift; cmd_delete "$@" ;;
    ""|--help|-h|help) usage ;;
    *)              die "Unknown command: ${command} (try: bottle.command --help)" ;;
  esac
}

main "$@"
