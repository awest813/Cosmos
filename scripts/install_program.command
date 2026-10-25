#!/usr/bin/env bash
# Guided classic-game install: installer -> chosen folder -> installed EXE -> port.
set -euo pipefail
ROOT="${COSMOS_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
source "${ROOT}/scripts/lib/port_lib.sh"
source "${ROOT}/scripts/lib/import_lib.sh"

die() { printf 'Error: %s\n' "$1" >&2; exit 1; }
pick_path() {
  local kind="$1" prompt="$2" directory="$3"
  osascript - "${kind}" "${prompt}" "${directory}" <<'APPLESCRIPT'
on run argv
    set startFolder to POSIX file (item 3 of argv)
    if item 1 of argv is "folder" then
        set selection to choose folder with prompt (item 2 of argv) default location startFolder
    else
        set selection to choose file with prompt (item 2 of argv) default location startFolder
    end if
    return POSIX path of selection
end run
APPLESCRIPT
}

usage() {
  cat <<'EOF'
Install a classic Windows game into a folder, then open its installed EXE.

  install_program.command install <installer.exe> --name <title> [options]
  install_program.command prepare --name <title> [--install-dir <folder>]
  install_program.command resume --name <title> [options]

Options:
  --install-dir <folder>  Absolute Mac folder or drive_c/... inside the bottle.
                         install asks you to choose a folder when omitted.
  --game-exe <path>       Installed game EXE; otherwise choose it after setup.
  --bottle <name>         Dedicated bottle name. Default: game-<title-slug>.
  --no-launch            Register the installed game without opening it.
  --make-app             Also build a Mac app in ~/Applications/Cosmos Ports.

prepare creates only the bottle definition and target folder; it runs no EXE.
resume skips the installer after an interrupted registration/selection step.
The installer stays interactive: choose the printed destination in its window.
Baseline: WoW64 environment, Windows 10, WineD3D. Game compatibility is untested.
EOF
}

main() {
  local mode="${1:-}" installer="" name="" folder="" game="" bottle="" launch=1 make_app=0
  case "${mode}" in
    -h|--help|help|"") usage; return ;;
    install|prepare|resume) shift ;;
    *) die "Use install, prepare, or resume. See --help." ;;
  esac
  if [[ "${mode}" == install ]]; then
    [[ $# -gt 0 && "$1" != --* ]] || die "install requires an installer EXE."
    installer="$1"; shift
  fi
  while (($#)); do
    case "$1" in
      --name|--install-dir|--game-exe|--bottle)
        [[ $# -ge 2 && -n "$2" ]] || die "Missing value for $1."
        case "$1" in
          --name) name="$2" ;;
          --install-dir) folder="$2" ;;
          --game-exe) game="$2" ;;
          --bottle) bottle="$2" ;;
        esac
        shift 2 ;;
      --no-launch) launch=0; shift ;;
      --make-app) make_app=1; shift ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  name="$(printf '%s' "${name}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  port_validate_name "${name}" || die "Provide --name with the game title."
  local slug support bottles ports prefix default_folder windows_folder arch conf install_state
  slug="$(port_slugify "${name}")"
  port_validate_slug "${slug}" || die "The game title does not produce a valid port name."
  bottle="${bottle:-game-${slug}}"
  port_validate_slug "${bottle}" || die "Invalid bottle name."
  port_require_apple_silicon || exit 1
  support="${COSMOS_SUPPORT_DIR:-${HOME}/Library/Application Support/Cosmos}"
  bottles="${COSMOS_BOTTLES_DIR:-${support}/Bottles}"
  ports="${COSMOS_PORTS_DIR:-${support}/Ports}"
  [[ ! -e "${ports}/${slug}" ]] || die "A port named ${slug} already exists. Open it from Ports or use port.command launch ${slug}."
  if [[ "${mode}" == install ]]; then
    [[ -f "${installer}" ]] || die "Installer not found: ${installer}"
    [[ "$(printf '%s' "${installer}" | tr '[:upper:]' '[:lower:]')" == *.exe ]] || die "Choose the Windows installer .exe."
    import_exe_has_pe_header "${installer}" || die "The installer does not have a Windows executable header."
    installer="$(cd -- "$(dirname -- "${installer}")" && pwd -P)/$(basename -- "${installer}")"
  fi
  if [[ ! -e "${bottles}/${bottle}" ]]; then
    [[ "${mode}" != resume ]] || die "No existing installation environment was found. Run install first."
    SCRIPT_DIR="${ROOT}" "${ROOT}/bottle.command" create "${bottle}" --arch wow64 --backend wined3d --windows win10 --retina 0
  fi
  conf="${bottles}/${bottle}/bottle.conf"
  install_state="${bottles}/${bottle}/install-${slug}.conf"
  [[ -f "${conf}" ]] || die "The selected bottle has no settings. Choose another bottle name."
  arch="$(port_get_setting "${conf}" COSMOS_PREFIX_ARCH)"
  [[ -z "${arch}" || "${arch}" == wow64 ]] || die "Use a WoW64 bottle for this workflow, or choose another bottle name. Existing settings were kept."
  prefix="$(SCRIPT_DIR="${ROOT}" "${ROOT}/bottle.command" path "${bottle}")"
  if [[ "${mode}" == resume && ! -f "${prefix}/system.reg" ]]; then
    die "The installation environment is not initialized. Run install first."
  fi
  if grep -Eq '^#arch=win32[[:space:]]*$' "${prefix}/system.reg" 2>/dev/null; then
    die "This is an existing win32 prefix. Choose a separate WoW64 bottle."
  fi
  default_folder="${prefix}/drive_c/Games/${slug}"
  mkdir -p "${default_folder}"
  # Keep recovery tied to this game and bottle. Read as data, never source paths.
  if [[ -z "${folder}" && "${mode}" == resume ]]; then
    folder="$(port_get_setting "${install_state}" INSTALL_FOLDER)"
    if [[ -n "${folder}" && ! -d "${folder}" ]]; then
      die "The saved installation folder is unavailable: ${folder}. Reconnect its drive or use --install-dir with the actual folder."
    fi
  fi
  if [[ -z "${folder}" ]]; then
    if [[ "${mode}" == install ]]; then
      folder="$(pick_path folder "Choose the installation folder for ${name}. Select the same destination inside the Windows installer." "${default_folder}")" || die "Folder selection cancelled."
    else
      folder="${default_folder}"
    fi
  fi
  case "${folder}" in
    drive_c/*)
      [[ "/${folder}/" != */../* ]] || die "The install directory must stay inside drive_c."
      folder="${prefix}/${folder}" ;;
    /*) ;;
    *) die "Use an absolute Mac folder or drive_c/... for --install-dir." ;;
  esac
  mkdir -p "${folder}"
  folder="$(cd -- "${folder}" && pwd -P)"
  prefix="$(cd -- "${prefix}" && pwd -P)"
  [[ "${folder}" != *$'\n'* ]] || die "Choose an installation folder without line breaks."
  port_set_setting "${install_state}" INSTALL_FOLDER "${folder}"
  case "${folder}" in
    "${prefix}/drive_c"/*) windows_folder="C:\\${folder#"${prefix}/drive_c/"}" ;;
    *) windows_folder="Z:${folder}" ;;
  esac
  windows_folder="${windows_folder//\//\\}"
  printf '\nGame: %s\nEnvironment: %s\nMac folder: %s\nWindows destination: %s\n' "${name}" "${bottle}" "${folder}" "${windows_folder}"
  if [[ "${mode}" == prepare ]]; then
    echo "Prepared. No installer or game was run. Run install when the installer is available."
    return
  fi
  if [[ "${mode}" == install ]]; then
    echo "In the installer, choose the Windows destination printed above. Leave its Launch Game option unchecked if offered. Finish setup and close it before selecting the game EXE."
    env SCRIPT_DIR="${ROOT}" COSMOS_BOTTLE="${bottle}" COSMOS_SKIP_STEAM=1 \
      COSMOS_BACKEND=wined3d COSMOS_PREFIX_ARCH=wow64 WINDOWS_VERSION=win10 WINE_RETINA_MODE=0 COSMOS_INSTALLER_ARGS="" \
      "${ROOT}/run.command" --run-installer "${installer}" \
      || die "Installation did not finish successfully. No game port was created. Retry install, or use resume if setup completed."
  fi
  if [[ -z "${game}" ]]; then
    game="$(pick_path file "Choose the installed game EXE for ${name}, such as SC3U.exe for SimCity 3000 Unlimited. Select the game, not setup or uninstall." "${folder}")" \
      || die "Game selection cancelled. Installation was kept; run resume to select the game later."
  fi
  case "${game}" in
    drive_c/*) game="${prefix}/${game}" ;;
    /*) ;;
    *) game="${folder}/${game}" ;;
  esac
  [[ -f "${game}" ]] || die "Installed game EXE not found: ${game}. Installation was kept; use resume after locating it."
  game="$(cd -- "$(dirname -- "${game}")" && pwd -P)/$(basename -- "${game}")"
  [[ "${game}" == "${folder}/"* ]] || die "The game is outside the chosen installation folder. Resume with --install-dir pointing at its actual folder."
  [[ "${game}" != "${installer}" ]] || die "Choose the installed game EXE, not the installer."
  import_exe_is_helper "${game}" && die "That looks like setup, uninstall, or a helper. Choose the installed game EXE."
  arch="$(port_detect_program_arch "${game}" || true)"
  [[ -n "${arch}" ]] || die "Choose an installed x86/x64 Windows game EXE, not a DLL."
  SCRIPT_DIR="${ROOT}" "${ROOT}/port.command" create --name "${name}" --slug "${slug}" --exe "${game}" \
    --bottle "${bottle}" --program-arch "${arch}" --windows win10 --retina 0 \
    --dxmt 0 --d9vk 0 --dxvk 0 --d3dmetal 0 --cnc-ddraw 0 --wined3d 1
  if (( make_app )); then SCRIPT_DIR="${ROOT}" "${ROOT}/port.command" build "${slug}"; fi
  if (( launch )); then SCRIPT_DIR="${ROOT}" "${ROOT}/port.command" launch "${slug}"; fi
  echo "Game port registered. WineD3D is the baseline; confirm startup and gameplay on your Mac."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
