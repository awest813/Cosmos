#!/usr/bin/env bash
set -euo pipefail

# Cosmos ports — Apple Silicon Mac apps that wrap one Windows program.
#
# Bottles and the game library stay the Whisky/Lutris side of Cosmos.
# A port is the Sikarugir (cosmosNEW) side: a double-clickable .app with an
# explicit graphics stack. D3DMetal can be enabled for a personal port.
# It is refused for a port you share, and it is never bundled.

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
if [[ -f "${SCRIPT_DIR}/scripts/lib/prefix_arch.sh" ]]; then
  # shellcheck source=scripts/lib/prefix_arch.sh
  source "${SCRIPT_DIR}/scripts/lib/prefix_arch.sh"
fi
# shellcheck source=scripts/lib/port_lib.sh
source "${SCRIPT_DIR}/scripts/lib/port_lib.sh"
source "${SCRIPT_DIR}/scripts/lib/wine_filesystem.sh"

COSMOS_SUPPORT_DIR="${COSMOS_SUPPORT_DIR:-$HOME/Library/Application Support/Cosmos}"
PORTS_DIR="${COSMOS_PORTS_DIR:-${COSMOS_SUPPORT_DIR}/Ports}"
BOTTLES_DIR="${COSMOS_BOTTLES_DIR:-${COSMOS_SUPPORT_DIR}/Bottles}"
DEFAULT_OUTPUT_DIR="${COSMOS_PORTS_OUTPUT:-${HOME}/Applications/Cosmos Ports}"

log() { printf "\n==> %s\n" "$1"; }
die() { printf "Error: %s\n" "$1" >&2; exit 1; }

usage() {
  cat <<'EOF'
Cosmos ports — wrap a Windows program as an Apple Silicon Mac app.

Usage: port.command <command> [args]

Commands:
  list                          List ports.
  create [options]              Create a port definition (prefix is the bottle's).
      --name <name>             Display name (required).
      --exe <path>              Windows program (required). drive_c/... is allowed.
      --slug <slug>             Directory name. Default: slug of --name.
      --bottle <name>           Existing bottle. Omit to use the main environment.
      --distribution <kind>     personal (default) | share
      --windows <ver>           winxp | win7 | win8 | win10 (default) | win11
      --retina <0|1>            Default 0.
      --args <text>             Extra arguments passed to the program.
      --program-arch <arch>     win64 | win32. Detects existing EXEs; otherwise win64.
                                inside the 64-bit prefix on Apple Silicon.
      --dxmt <0|1>              DirectX 10/11 → Metal. Default 1.
      --d3dmetal <0|1>          DirectX 11/12 → Metal. Personal ports only. Default 0.
      --dxvk <0|1>              DirectX 10/11 → Vulkan. Default 0.
      --d9vk <0|1>              SpockD3D9 for DirectX 8/9, beside DXMT. Default 1.
      --cnc-ddraw <0|1>         Classic DirectDraw. Default 1.
      --wined3d <0|1>           DirectX 7 and below. Default 1.
      --cnc-ddraw-path <path>   Folder containing ddraw.dll (not bundled).
      --gptk-path <path>        Your Game Porting Toolkit install. Personal only.
  show <slug>                   Print a port's settings and launch backend.
  update <slug> [options]        Edit settings using create options (except --slug).
                                Empty args/paths/bottle clear saved values.
  validate <slug>               Check the graphics stack. Does not launch.
  build <slug> [--output dir]   Write a double-clickable .app.
  launch <slug>                 Open the Windows program in the port's bottle.
  delete <slug> [--force]       Remove the port definition (not the built .app).

Ports target Apple Silicon (arm64) and macOS 14.6 or later.
Set COSMOS_PORT_SKIP_ARCH=1 to create and build on another machine for tests.
EOF
}

port_dir() { printf '%s' "${PORTS_DIR}/$1"; }

port_host_executable() {
  local path="$1" bottle="$2" prefix="${WINEPREFIX:-${HOME}/.wine-steam-11}"
  if [[ -n "${bottle}" ]]; then
    port_validate_slug "${bottle}" || return 1
    prefix="${BOTTLES_DIR}/${bottle}/prefix"
  fi
  if [[ "${path}" != drive_c/* && "${path}" != [A-Za-z]:* && -f "${path}" ]]; then
    path="$(cd -- "$(dirname -- "${path}")" && pwd)/$(basename -- "${path}")"
  fi
  wine_fs_host_path "${prefix}" "${path}"
}

require_port() {
  local slug="$1"
  port_validate_slug "${slug}" || die "Invalid port name '${slug}'."
  [[ -f "$(port_dir "${slug}")/port.conf" ]] \
    || die "Port not found: ${slug}. Create it with: port.command create --name ... --exe ..."
}

confirm() {
  local prompt="$1" reply=""
  read -r -p "${prompt} [y/N]: " reply
  [[ "${reply}" == "y" || "${reply}" == "Y" ]]
}

take_opt() {
  local flag="$1"
  [[ $# -ge 2 && -n "${2:-}" ]] || die "Missing value for ${flag}."
  printf '%s' "$2"
}

cmd_list() {
  mkdir -p "${PORTS_DIR}"
  local found=0 dir slug name dist primary
  shopt -s nullglob
  for dir in "${PORTS_DIR}"/*/; do
    dir="${dir%/}"
    [[ -f "${dir}/port.conf" ]] || continue
    slug="${dir##*/}"
    name="$(port_get_setting "${dir}/port.conf" PORT_NAME)"
    dist="$(port_get_setting "${dir}/port.conf" PORT_DISTRIBUTION)"
    primary="$(port_get_setting "${dir}/port.conf" PORT_PRIMARY)"
    printf '  %-20s %-10s %-12s %s\n' "${slug}" "${dist:-personal}" "${primary:-?}" "${name}"
    found=1
  done
  shopt -u nullglob
  if (( found == 0 )); then
    echo "No ports yet. Create one with: port.command create --name \"My Program\" --exe /path/to/app.exe"
  fi
}

cmd_save() {
  local mode="$1"; shift
  local name="" exe="" slug="" bottle="" distribution="personal" windows="win10"
  local retina="0" args="" program_arch="" dxmt="1" d3dmetal="0" dxvk="0" d9vk="1" cnc="1" wined3d="1"
  local cnc_path="" gptk_path=""
  local exe_changed=0 arch_explicit=0
  port_require_apple_silicon || exit 1
  if [[ "${mode}" == update ]]; then
    slug="${1:-}"
    require_port "${slug}"
    shift
    port_load_conf "$(port_dir "${slug}")/port.conf"
    name="${PORT_NAME}"; exe="${PORT_EXE}"; bottle="${PORT_BOTTLE}"
    distribution="${PORT_DISTRIBUTION}"; windows="${PORT_WINDOWS}"; retina="${PORT_RETINA}"
    args="${PORT_ARGS}"; program_arch="${PORT_PROGRAM_ARCH}"
    dxmt="${PORT_RENDER_DXMT}"; d3dmetal="${PORT_RENDER_D3DMETAL}"; dxvk="${PORT_RENDER_DXVK}"
    d9vk="${PORT_RENDER_D9VK}"; cnc="${PORT_RENDER_CNC_DDRAW}"; wined3d="${PORT_RENDER_WINED3D}"
    cnc_path="${PORT_CNC_DDRAW_PATH}"; gptk_path="${PORT_GPTK_PATH}"
  fi
  while (($#)); do
    case "$1" in
      --name) name="$(take_opt "$1" "${2:-}")"; shift 2 ;;
      --exe) exe="$(take_opt "$1" "${2:-}")"; exe_changed=1; shift 2 ;;
      --slug)
        [[ "${mode}" == create ]] || die "The port ID cannot be changed. Use --name for its display name."
        slug="$(take_opt "$1" "${2:-}")"; shift 2 ;;
      --bottle) [[ $# -ge 2 ]] || die "Missing value for $1."; bottle="$2"; shift 2 ;;
      --distribution) distribution="$(take_opt "$1" "${2:-}")"; shift 2 ;;
      --windows) windows="$(take_opt "$1" "${2:-}")"; shift 2 ;;
      --retina) retina="$(take_opt "$1" "${2:-}")"; shift 2 ;;
      --args) [[ $# -ge 2 ]] || die "Missing value for $1."; args="$2"; shift 2 ;;
      --program-arch) program_arch="$(take_opt "$1" "${2:-}")"; arch_explicit=1; shift 2 ;;
      --dxmt) dxmt="$(take_opt "$1" "${2:-}")"; shift 2 ;;
      --d3dmetal) d3dmetal="$(take_opt "$1" "${2:-}")"; shift 2 ;;
      --dxvk) dxvk="$(take_opt "$1" "${2:-}")"; shift 2 ;;
      --d9vk) d9vk="$(take_opt "$1" "${2:-}")"; shift 2 ;;
      --cnc-ddraw) cnc="$(take_opt "$1" "${2:-}")"; shift 2 ;;
      --wined3d) wined3d="$(take_opt "$1" "${2:-}")"; shift 2 ;;
      --cnc-ddraw-path) [[ $# -ge 2 ]] || die "Missing value for $1."; cnc_path="$2"; shift 2 ;;
      --gptk-path) [[ $# -ge 2 ]] || die "Missing value for $1."; gptk_path="$2"; shift 2 ;;
      --*) die "Unknown ${mode} option: $1" ;;
      *) die "Unexpected argument: $1" ;;
    esac
  done

  name="$(printf '%s' "${name}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  exe="$(printf '%s' "${exe}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  port_validate_name "${name}" || die "Name must not be empty or contain '/' or ':'."
  [[ -n "${exe}" && "${exe}" != *$'\n'* ]] || die "A Windows program path is required (--exe)."
  case "${distribution}" in
    personal|share) ;;
    *) die "Distribution must be personal or share." ;;
  esac
  case "${windows}" in
    winxp|win7|win8|win10|win11) ;;
    *) die "Windows version must be winxp, win7, win8, win10, or win11." ;;
  esac
  dxmt="$(port_normalize_flag "${dxmt}")" || die "--dxmt must be 0 or 1."
  d3dmetal="$(port_normalize_flag "${d3dmetal}")" || die "--d3dmetal must be 0 or 1."
  dxvk="$(port_normalize_flag "${dxvk}")" || die "--dxvk must be 0 or 1."
  d9vk="$(port_normalize_flag "${d9vk}")" || die "--d9vk must be 0 or 1."
  cnc="$(port_normalize_flag "${cnc}")" || die "--cnc-ddraw must be 0 or 1."
  wined3d="$(port_normalize_flag "${wined3d}")" || die "--wined3d must be 0 or 1."
  retina="$(port_normalize_flag "${retina}")" || die "--retina must be 0 or 1."
  local detected_arch host_exe
  host_exe="$(port_host_executable "${exe}" "${bottle}")" || die "The Windows program path is invalid or its drive is not mapped."
  detected_arch="$(port_detect_program_arch "${host_exe}" || true)"
  # Keep Windows/drive_c paths logical: a store update may retarget a junction.
  if [[ "${mode}" == update && "${exe_changed}" == 1 && "${arch_explicit}" == 0 && -n "${detected_arch}" ]]; then
    program_arch="${detected_arch}"
  fi
  program_arch="$(program_arch_normalize "${program_arch:-${detected_arch:-win64}}")" || die "--program-arch must be win64 or win32."
  if [[ -n "${detected_arch}" && "${detected_arch}" != "${program_arch}" ]]; then
    die "The executable is ${detected_arch}, but --program-arch is ${program_arch}. Choose the matching program architecture."
  fi
  [[ "${args}" != *$'\n'* ]] || die "Launch arguments must be a single line."

  if [[ "${distribution}" == "share" && "${d3dmetal}" == "1" ]]; then
    die "$(port_shared_d3dmetal_error)"
  fi
  if [[ "${distribution}" == "share" && -n "${gptk_path}" ]]; then
    die "A Game Porting Toolkit path is only saved on a personal port."
  fi

  if [[ -z "${slug}" ]]; then
    slug="$(port_slugify "${name}")"
  fi
  port_validate_slug "${slug}" || die "Invalid slug '${slug}'. Use letters, digits, '.', '_' or '-'."

  if [[ -n "${bottle}" ]]; then
    port_validate_slug "${bottle}" || die "Invalid bottle name '${bottle}'."
    [[ -d "${BOTTLES_DIR}/${bottle}" ]] \
      || die "Bottle not found: ${bottle}. Create it with: bottle.command create ${bottle}"
  fi

  local dir conf primary
  dir="$(port_dir "${slug}")"
  if [[ "${mode}" == create ]]; then
    [[ ! -e "${dir}" ]] || die "Port already exists: ${slug}"
  fi

  if [[ -f "${exe}" ]]; then
    exe="$(cd -- "$(dirname -- "${exe}")" && pwd)/$(basename -- "${exe}")"
  fi

  PORT_DISTRIBUTION="${distribution}"
  PORT_RENDER_DXMT="${dxmt}"
  PORT_RENDER_D3DMETAL="${d3dmetal}"
  PORT_RENDER_DXVK="${dxvk}"
  PORT_RENDER_D9VK="${d9vk}"
  PORT_RENDER_CNC_DDRAW="${cnc}"
  PORT_RENDER_WINED3D="${wined3d}"
  export PORT_DISTRIBUTION PORT_RENDER_DXMT PORT_RENDER_D3DMETAL PORT_RENDER_DXVK
  export PORT_RENDER_D9VK PORT_RENDER_CNC_DDRAW PORT_RENDER_WINED3D
  primary="$(port_resolve_primary)" || exit 1

  mkdir -p "${dir}"
  # Stage a complete definition beside the original, then replace it atomically.
  # Retain extension metadata and built-app location during an edit.
  conf="$(mktemp "${dir}/.port.conf.XXXXXX")"
  trap "$(printf 'rm -f -- %q' "${conf}")" EXIT
  if [[ "${mode}" == update ]]; then
    cp "${dir}/port.conf" "${conf}"
  else
    printf '%s\n' "# Cosmos port \"${name}\". Apple Silicon wrapper. Do not put D3DMetal in a shared port." > "${conf}"
  fi
  port_set_setting "${conf}" PORT_SCHEMA "cosmos-port-v1"
  port_set_setting "${conf}" PORT_NAME "${name}"
  port_set_setting "${conf}" PORT_SLUG "${slug}"
  port_set_setting "${conf}" PORT_EXE "${exe}"
  port_set_setting "${conf}" PORT_ARGS "${args}"
  port_set_setting "${conf}" PORT_PROGRAM_ARCH "${program_arch}"
  port_set_setting "${conf}" PORT_BOTTLE "${bottle}"
  port_set_setting "${conf}" PORT_WINDOWS "${windows}"
  port_set_setting "${conf}" PORT_RETINA "${retina}"
  port_set_setting "${conf}" PORT_DISTRIBUTION "${distribution}"
  port_set_setting "${conf}" PORT_PLATFORM "apple-silicon"
  port_set_setting "${conf}" PORT_MIN_MACOS "14.6"
  port_set_setting "${conf}" PORT_PRIMARY "${primary}"
  port_set_setting "${conf}" PORT_RENDER_DXMT "${dxmt}"
  port_set_setting "${conf}" PORT_RENDER_D3DMETAL "${d3dmetal}"
  port_set_setting "${conf}" PORT_RENDER_DXVK "${dxvk}"
  port_set_setting "${conf}" PORT_RENDER_D9VK "${d9vk}"
  port_set_setting "${conf}" PORT_RENDER_CNC_DDRAW "${cnc}"
  port_set_setting "${conf}" PORT_RENDER_WINED3D "${wined3d}"
  port_set_setting "${conf}" PORT_CNC_DDRAW_PATH "${cnc_path}"
  port_set_setting "${conf}" PORT_GPTK_PATH "${gptk_path}"
  mv "${conf}" "${dir}/port.conf"
  trap - EXIT

  if [[ "${mode}" == update ]]; then
    log "Updated port '${slug}' (${name})"
    echo "Existing Mac apps keep their previous settings. Rebuild with port.command build ${slug} to apply these changes to an app."
  else
    log "Created port '${slug}' (${name})"
  fi
  echo "Launch backend: ${primary}"
  echo "Definition: ${dir}/port.conf"
  if [[ ! -f "${exe}" && "${exe}" != drive_c/* ]]; then
    echo "Note: ${exe} is not on disk yet. The Mac app can still be built; launch works once the program is there."
  fi
  echo "Build a Mac app with: port.command build ${slug}"
}

cmd_create() { cmd_save create "$@"; }
cmd_update() { cmd_save update "$@"; }

cmd_show() {
  local slug="${1:-}"
  require_port "${slug}"
  local conf dir
  dir="$(port_dir "${slug}")"
  conf="${dir}/port.conf"
  port_load_conf "${conf}"
  echo "Port:          ${PORT_SLUG}"
  echo "Name:          ${PORT_NAME}"
  echo "Executable:    ${PORT_EXE}"
  if [[ -n "${PORT_ARGS}" ]]; then
    echo "Arguments:     ${PORT_ARGS}"
  fi
  echo "Program:       $(program_arch_label "${PORT_PROGRAM_ARCH:-win64}")"
  if [[ -n "${PORT_BOTTLE}" ]]; then
    echo "Bottle:        ${PORT_BOTTLE}"
  else
    echo "Bottle:        main environment"
  fi
  echo "Distribution:  ${PORT_DISTRIBUTION}"
  echo "Platform:      ${PORT_PLATFORM} (macOS ${PORT_MIN_MACOS}+)"
  echo "Windows:       ${PORT_WINDOWS}"
  echo "Retina:        $([[ "${PORT_RETINA}" == "1" ]] && printf 'on' || printf 'off')"
  echo "Renderers:     $(port_renderers_csv)"
  echo "Launch backend:${PORT_PRIMARY:+ }${PORT_PRIMARY}"
  if [[ -n "${PORT_BUILT_APP}" ]]; then
    echo "Mac app:       ${PORT_BUILT_APP}"
  fi
  if [[ -n "${PORT_GPTK_PATH}" ]]; then
    echo "GPTK:          ${PORT_GPTK_PATH}"
  fi
  if [[ -n "${PORT_CNC_DDRAW_PATH}" ]]; then
    echo "CNC-DDRAW:     ${PORT_CNC_DDRAW_PATH}"
  fi
}

cmd_validate() {
  local slug="${1:-}"
  require_port "${slug}"
  port_load_conf "$(port_dir "${slug}")/port.conf"
  local backend
  backend="$(port_resolve_primary)" || exit 1
  if [[ "${PORT_PRIMARY}" != "${backend}" ]]; then
    die "Stored launch backend '${PORT_PRIMARY}' does not match the renderer stack (${backend})."
  fi
  if [[ "${PORT_PLATFORM}" != "apple-silicon" ]]; then
    die "Ports in this version of Cosmos are Apple Silicon only."
  fi
  echo "Valid: ${slug} launches with ${backend}."
}

cmd_build() {
  local slug="" output="${DEFAULT_OUTPUT_DIR}"
  port_require_apple_silicon || exit 1
  while (($#)); do
    case "$1" in
      --output) output="$(take_opt "$1" "${2:-}")"; shift 2 ;;
      --*) die "Unknown build option: $1" ;;
      *)
        [[ -z "${slug}" ]] || die "Unexpected argument: $1"
        slug="$1"
        shift
        ;;
    esac
  done
  require_port "${slug}"
  local conf app_path runtime_root
  conf="$(port_dir "${slug}")/port.conf"
  port_load_conf "${conf}"
  runtime_root="${COSMOS_PORT_RUNTIME_ROOT:-${SCRIPT_DIR}}"
  if [[ ! -f "${runtime_root}/run.command" ]]; then
    echo "Warning: run.command not found at ${runtime_root}. The port will look there when it opens." >&2
  fi
  app_path="$(port_write_bundle "${output}" "${runtime_root}" "${conf}")" || exit 1
  port_set_setting "${conf}" PORT_BUILT_APP "${app_path}"
  log "Built ${app_path}"
  echo "Double-click it on an Apple Silicon Mac, or run: port.command launch ${slug}"
  if [[ "${PORT_DISTRIBUTION}" == "share" ]]; then
    echo "This is a shared port. D3DMetal is not included and cannot be turned on."
  fi
}

cmd_launch() {
  local slug="${1:-}"
  port_require_apple_silicon || exit 1
  require_port "${slug}"
  local conf
  conf="$(port_dir "${slug}")/port.conf"
  port_load_conf "${conf}"
  local backend
  backend="$(port_resolve_primary)" || exit 1
  local host_exe
  host_exe="$(port_host_executable "${PORT_EXE}" "${PORT_BOTTLE}")" || die "The game's Windows drive is not mapped in this environment."
  if [[ ! -f "${host_exe}" ]]; then
    die "Windows program not found: ${PORT_EXE}"
  fi
  if [[ -n "${PORT_BOTTLE}" && ! -d "${BOTTLES_DIR}/${PORT_BOTTLE}" ]]; then
    die "Bottle not found: ${PORT_BOTTLE}"
  fi
  export COSMOS_PORT=1
  export COSMOS_PORT_DISTRIBUTION="${PORT_DISTRIBUTION}"
  export COSMOS_PORT_PLATFORM="${PORT_PLATFORM}"
  export COSMOS_PORT_RENDERERS
  COSMOS_PORT_RENDERERS="$(port_renderers_csv)"
  export COSMOS_PORT_RENDERERS
  if port_is_on "${PORT_RENDER_CNC_DDRAW}"; then
    export COSMOS_PORT_CNC_DDRAW=1
  else
    export COSMOS_PORT_CNC_DDRAW=0
  fi
  if [[ -n "${PORT_CNC_DDRAW_PATH}" ]]; then
    export CNC_DDRAW_PATH="${PORT_CNC_DDRAW_PATH}"
  fi
  if [[ "${PORT_DISTRIBUTION}" == "personal" && -n "${PORT_GPTK_PATH}" ]]; then
    export GPTK_PATH="${PORT_GPTK_PATH}"
  fi
  export COSMOS_BACKEND="${backend}"
  export COSMOS_SKIP_STEAM=1
  export COSMOS_PROGRAM_ARCH="${PORT_PROGRAM_ARCH}"
  export WINDOWS_VERSION="${PORT_WINDOWS}"
  export WINE_RETINA_MODE="${PORT_RETINA}"
  if [[ -n "${PORT_BOTTLE}" ]]; then
    export COSMOS_BOTTLE="${PORT_BOTTLE}"
  else
    unset COSMOS_BOTTLE || true
  fi
  log "Opening ${PORT_NAME} with ${backend}"
  port_exec_program "${SCRIPT_DIR}/run.command" "${host_exe}" "${PORT_ARGS}"
}

cmd_delete() {
  local slug="" force=0
  while (($#)); do
    case "$1" in
      --force) force=1; shift ;;
      --*) die "Unknown delete option: $1" ;;
      *)
        [[ -z "${slug}" ]] || die "Unexpected argument: $1"
        slug="$1"
        shift
        ;;
    esac
  done
  require_port "${slug}"
  local dir built
  dir="$(port_dir "${slug}")"
  built="$(port_get_setting "${dir}/port.conf" PORT_BUILT_APP)"
  if (( force == 0 )); then
    confirm "Delete port '${slug}'?" || die "Cancelled."
  fi
  rm -rf "${dir}"
  echo "Deleted port ${slug}."
  if [[ -n "${built}" ]]; then
    echo "The Mac app was left in place: ${built}"
  fi
}

main() {
  local cmd="${1:-}"
  case "${cmd}" in
    ""|-h|--help|help) usage ;;
    list) shift; cmd_list "$@" ;;
    create) shift; cmd_create "$@" ;;
    update) shift; cmd_update "$@" ;;
    show) shift; cmd_show "$@" ;;
    validate) shift; cmd_validate "$@" ;;
    build) shift; cmd_build "$@" ;;
    launch) shift; cmd_launch "$@" ;;
    delete) shift; cmd_delete "$@" ;;
    *) die "Unknown command: ${cmd}. Run port.command --help." ;;
  esac
}

main "$@"
