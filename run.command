#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"

# --- Bottle pre-load (roadmap 0.3) -------------------------------------------
# A named bottle (COSMOS_BOTTLE) supplies an isolated Wine prefix plus default
# settings from its bottle.conf. Load them *before* the per-setting defaults
# below, so precedence is: explicit environment > bottle.conf > built-in default.
# When no bottle is named, nothing here changes and behavior is unchanged.
COSMOS_SUPPORT_DIR="${COSMOS_SUPPORT_DIR:-$HOME/Library/Application Support/Cosmos}"
STEAM_LAUNCH_LOG_DEFAULT="${COSMOS_SUPPORT_DIR}/logs/steam-launch.log"
COSMOS_BOTTLE="${COSMOS_BOTTLE:-}"
BOTTLES_DIR="${COSMOS_BOTTLES_DIR:-${COSMOS_SUPPORT_DIR}/Bottles}"

_bottle_die() { printf "Error: %s\n" "$1" >&2; exit 1; }

load_bottle() {
  [[ -n "${COSMOS_BOTTLE}" ]] || return 0
  [[ "${COSMOS_BOTTLE}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "${COSMOS_BOTTLE}" != *..* ]] \
    || _bottle_die "Invalid COSMOS_BOTTLE name: ${COSMOS_BOTTLE}"
  local dir="${BOTTLES_DIR}/${COSMOS_BOTTLE}"
  [[ -d "${dir}" ]] \
    || _bottle_die "Bottle not found: ${COSMOS_BOTTLE} (${dir}). Create it with: bottle.command create ${COSMOS_BOTTLE}"

  local conf="${dir}/bottle.conf"
  if [[ -f "${conf}" ]]; then
    local line key val
    while IFS= read -r line || [[ -n "${line}" ]]; do
      line="${line%$'\r'}"
      [[ "${line}" =~ ^[[:space:]]*(#|$) ]] && continue
      [[ "${line}" == *=* ]] || continue
      key="${line%%=*}"; key="${key//[[:space:]]/}"
      [[ "${key}" =~ ^[A-Z][A-Z0-9_]*$ ]] || continue
      case "${key}" in WINEPREFIX|COSMOS_BOTTLE) continue ;; esac
      [[ -n "${!key:-}" ]] && continue            # explicit environment wins
      val="${line#*=}"; val="${val%\"}"; val="${val#\"}"
      printf -v "${key}" '%s' "${val}"
      export "${key?}"
    done < "${conf}"
  fi

  # The bottle owns its prefix and (unless overridden) its launch log.
  WINEPREFIX="${dir}/prefix"
  mkdir -p "${dir}/logs"
  if [[ -z "${COSMOS_LAUNCH_LOG:-}${MERLOT_LAUNCH_LOG:-}${COSMOS_STEAM_LOG:-}${MERLOT_STEAM_LOG:-}" ]]; then
    COSMOS_LAUNCH_LOG="${dir}/logs/launch.log"
  fi
}

# Default Steam prefix settings (when no named bottle is active). Persisted in
# ~/Library/Application Support/Cosmos/steam.conf — same KEY="value" format as
# bottle.conf. Precedence: explicit environment > steam.conf > built-in defaults.
ensure_steam_conf() {
  [[ -z "${COSMOS_BOTTLE}" ]] || return 0
  local conf="${COSMOS_SUPPORT_DIR}/steam.conf"
  [[ -f "${conf}" ]] && return 0
  mkdir -p "${COSMOS_SUPPORT_DIR}/logs"
  cat >"${conf}" <<EOF
# Cosmos default Steam bottle settings. Applied on each launch.
COSMOS_BACKEND="recommended"
COSMOS_DETACH="1"
COSMOS_STEAM_SILENT="1"
WINE_RETINA_MODE="0"
WINDOWS_VERSION=""
WINE_VERSION="11.8"
COSMOS_LAUNCH_LOG="${STEAM_LAUNCH_LOG_DEFAULT}"
EOF
}

load_steam_conf() {
  [[ -z "${COSMOS_BOTTLE}" ]] || return 0
  local conf="${COSMOS_SUPPORT_DIR}/steam.conf"
  [[ -f "${conf}" ]] || return 0
  local line key val
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ "${line}" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "${line}" == *=* ]] || continue
    key="${line%%=*}"; key="${key//[[:space:]]/}"
    [[ "${key}" =~ ^[A-Z][A-Z0-9_]*$ ]] || continue
    case "${key}" in WINEPREFIX|COSMOS_BOTTLE) continue ;; esac
    [[ -n "${!key:-}" ]] && continue
    val="${line#*=}"; val="${val%\"}"; val="${val#\"}"
    printf -v "${key}" '%s' "${val}"
    export "${key?}"
  done < "${conf}"
}

sanitize_steam_settings() {
  [[ -z "${COSMOS_BOTTLE}" ]] || return 0
  case "${COSMOS_BACKEND}" in
    recommended|dxmt|d3dmetal|dxvk|wined3d) ;;
    *) COSMOS_BACKEND="recommended" ;;
  esac
  case "${COSMOS_DETACH}" in 0|1) ;; *) COSMOS_DETACH=1 ;; esac
  case "${COSMOS_STEAM_SILENT}" in 0|1) ;; *) COSMOS_STEAM_SILENT=1 ;; esac
  case "${WINE_RETINA_MODE}" in 0|1) ;; *) WINE_RETINA_MODE=0 ;; esac
  case "${WINDOWS_VERSION}" in
    ""|winxp|win7|win8|win10|win11) ;;
    *) WINDOWS_VERSION="" ;;
  esac
}

load_bottle
ensure_steam_conf
load_steam_conf
sanitize_steam_settings
# -----------------------------------------------------------------------------

WINE_VERSION="${WINE_VERSION:-11.8}"
# Pinned for MIT license on release artifacts; see docs/LICENSING.md before upgrading.
DXMT_VERSION="${DXMT_VERSION:-0.74}"

WINE_ROOT="${WINE_ROOT:-$HOME/wine-${WINE_VERSION}}"
WINE_APP="${WINE_ROOT}/Wine Devel.app"
WINE_BIN="${WINE_APP}/Contents/Resources/wine/bin/wine"

WINEPREFIX="${WINEPREFIX:-$HOME/.wine-steam-11}"
STEAM_SETUP="/tmp/SteamSetup.exe"
DXMT_ROOT="${DXMT_ROOT:-$HOME/DXMT}"
COSMOS_SUPPORT_DIR="${COSMOS_SUPPORT_DIR:-$HOME/Library/Application Support/Cosmos}"
# Legacy Application Support location used by pre-Cosmos (Cider) builds. Kept as
# a fallback so existing saved profiles are still found after the rename.
LEGACY_PROFILE_DIRECTORY="$HOME/Library/Application Support/Cider/Profiles"
if [[ -n "${PROFILE_DIRECTORY:-}" ]]; then
  : # Honor an explicit override unchanged.
elif [[ ! -d "${COSMOS_SUPPORT_DIR}/Profiles" && -d "${LEGACY_PROFILE_DIRECTORY}" ]]; then
  PROFILE_DIRECTORY="${LEGACY_PROFILE_DIRECTORY}"
else
  PROFILE_DIRECTORY="${COSMOS_SUPPORT_DIR}/Profiles"
fi
# GPTK_PATH: optional. When set, the D3D translation backend switches from
# DXMT (default) to Apple's Game Porting Toolkit (D3DMetal). Point this at
# either the GPTK root directory or the folder that contains the .dll files
# (we probe a few common layouts). GPTK is NOT downloaded automatically --
# Apple's EULA forbids redistribution, so the user must obtain it from
# developer.apple.com themselves. DXMT is the default precisely because it
# has no such constraint.
GPTK_PATH="${GPTK_PATH:-}"
# Graphics backend selector (roadmap 0.3): recommended | dxmt | d3dmetal | dxvk | wined3d.
# 'recommended' resolves to d3dmetal when GPTK_PATH is set, otherwise dxmt, which
# preserves the historical GPTK_PATH-driven behavior. d3dmetal needs a
# user-supplied GPTK_PATH; dxvk needs a user-supplied DXVK_PATH (experimental on
# macOS via MoltenVK); wined3d uses Wine's built-in D3D->OpenGL with no extra
# downloads. DXMT stays the no-setup default. See docs/BACKENDS.md.
COSMOS_BACKEND="${COSMOS_BACKEND:-recommended}"
# Folder of DXVK DLLs (d3d11.dll, dxgi.dll, ...) used by the dxvk backend.
DXVK_PATH="${DXVK_PATH:-}"
RESOLVED_BACKEND=""
WINEPREFIX_ALIAS_NAME="${WINEPREFIX_ALIAS_NAME:-WINEPREFIX}"
WINE_RETINA_MODE="${WINE_RETINA_MODE:-0}" # 1=enable RetinaMode, 0=disable RetinaMode (Default)
# 1=detach Steam from the Terminal after launch so closing the window doesn't kill it (Default).
# 0=keep the original foreground behavior (Terminal window must stay open).
# COSMOS_DETACH is the current name; MERLOT_DETACH is honored for back-compat.
COSMOS_DETACH="${COSMOS_DETACH:-${MERLOT_DETACH:-1}}"
# 1=install Steam unattended with the NSIS /S flag (no wizard clicks); falls back
# to the interactive installer if the silent run does not produce steam.exe.
# 0=always show the graphical Steam installer wizard.
COSMOS_STEAM_SILENT="${COSMOS_STEAM_SILENT:-1}"
COSMOS_LAUNCH_LOG="${COSMOS_LAUNCH_LOG:-${MERLOT_LAUNCH_LOG:-${COSMOS_STEAM_LOG:-${MERLOT_STEAM_LOG:-${STEAM_LAUNCH_LOG_DEFAULT}}}}}"
# Default before we added this: the value is not set in registry (Wine internal default).
# Set to force|enable|disable to override, or leave empty to keep default.
WINE_MOUSE_WARP_OVERRIDE="${WINE_MOUSE_WARP_OVERRIDE:-}"
# Reported Windows version inside the prefix. Empty = Wine's built-in default.
# Recognized: winxp | win7 | win8 | win10 | win11 (Wine's own version tokens,
# written to HKCU\Software\Wine\Version — the per-prefix override winecfg's
# "Windows Version" dropdown uses). Usually set per bottle via bottle.conf.
WINDOWS_VERSION="${WINDOWS_VERSION:-}"
COSMOS_LAUNCH_MODE="${COSMOS_LAUNCH_MODE:-${MERLOT_LAUNCH_MODE:-steam}}"
# Skip the interactive confirmation for destructive actions (e.g. --reset-bottle).
COSMOS_FORCE="${COSMOS_FORCE:-0}"
PROFILE_EXECUTABLE=""
PROFILE_ARGS=()

WINE_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/${WINE_VERSION}/wine-devel-${WINE_VERSION}-osx64.tar.xz"
STEAM_URL="https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"
DXMT_URL="https://github.com/3Shain/dxmt/releases/download/v${DXMT_VERSION}/dxmt-v${DXMT_VERSION}-builtin.tar.gz"

log() {
  printf "\n==> %s\n" "$1"
}

die() {
  printf "Error: %s\n" "$1" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: run.command [ACTION]

Actions:
  (none) | --steam        Set up the bottle if needed and launch Steam (default).
  --setup-steam           Prepare Wine, DXMT/backend, and Steam (no launch).
  --status                 Show setup progress and the next step, then exit.
  --game <path> [args...]  Launch a saved profile executable directly.
  --profiles               Open the saved profiles folder in Finder and exit.
  --logs                   Open the latest launch log and exit.
  --reset-bottle [--force] Delete the Wine prefix so it is recreated next launch.
EOF
}

parse_arguments() {
  case "${1:-}" in
    "")
      return 0
      ;;
    --steam)
      if (($# > 1)); then
        die "The --steam flag does not accept additional arguments."
      fi
      COSMOS_LAUNCH_MODE="steam"
      return 0
      ;;
    --setup-steam)
      if (($# > 1)); then
        die "The --setup-steam flag does not accept additional arguments."
      fi
      COSMOS_LAUNCH_MODE="setup-steam"
      return 0
      ;;
    --profiles)
      if (($# > 1)); then
        die "The --profiles flag does not accept additional arguments."
      fi
      COSMOS_LAUNCH_MODE="profiles"
      return 0
      ;;
    --game|--profile)
      if (($# < 2)); then
        die "Missing required argument for $1 flag."
      fi
      PROFILE_EXECUTABLE="$2"
      COSMOS_LAUNCH_MODE="profile"
      PROFILE_ARGS=("${@:3}")
      return 0
      ;;
    --logs)
      if (($# > 1)); then
        die "The --logs flag does not accept additional arguments."
      fi
      COSMOS_LAUNCH_MODE="logs"
      return 0
      ;;
    --status|--doctor)
      if (($# > 1)); then
        die "The $1 flag does not accept additional arguments."
      fi
      COSMOS_LAUNCH_MODE="status"
      return 0
      ;;
    --reset-bottle)
      if (($# > 1)); then
        [[ "$2" == "--force" ]] || die "Unknown argument for --reset-bottle: $2"
        COSMOS_FORCE=1
        if (($# > 2)); then
          die "The --reset-bottle flag accepts only an optional --force argument."
        fi
      fi
      COSMOS_LAUNCH_MODE="reset-bottle"
      return 0
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
}

open_profiles_folder() {
  log "Opening saved profiles folder"
  mkdir -p "${PROFILE_DIRECTORY}"
  open "${PROFILE_DIRECTORY}"
}

confirm() {
  local prompt="$1"
  local reply=""
  read -r -p "${prompt} [y/N]: " reply
  [[ "${reply}" == "y" || "${reply}" == "Y" ]]
}

open_logs() {
  log "Opening Cosmos launch log"
  if [[ -f "${COSMOS_LAUNCH_LOG}" ]]; then
    echo "Log file: ${COSMOS_LAUNCH_LOG}"
    open "${COSMOS_LAUNCH_LOG}"
    return
  fi
  echo "No log file yet at ${COSMOS_LAUNCH_LOG}."
  echo "It is created the first time Steam or a game launches in detached mode."
  open "$(dirname "${COSMOS_LAUNCH_LOG}")"
}

reset_bottle() {
  log "Resetting the Steam bottle"
  echo "This deletes the Wine prefix and everything installed inside it"
  echo "(Steam and any games). Wine and DXMT downloads are kept."
  echo "Prefix: ${WINEPREFIX}"

  if [[ "${COSMOS_FORCE}" != "1" ]]; then
    if [[ -t 0 ]]; then
      confirm "Delete this prefix?" || { echo "Aborted. Nothing was removed."; return; }
    else
      die "Refusing to reset non-interactively. Re-run with --force (or COSMOS_FORCE=1) to proceed."
    fi
  fi

  if [[ -d "${WINEPREFIX}" ]]; then
    rm -rf "${WINEPREFIX}"
    echo "Removed ${WINEPREFIX}."
  else
    echo "No prefix found at ${WINEPREFIX}. Nothing to remove."
  fi

  local alias_path="${SCRIPT_DIR}/${WINEPREFIX_ALIAS_NAME}"
  if [[ -L "${alias_path}" ]]; then
    rm -f "${alias_path}" && echo "Removed stale alias ${alias_path}."
  fi

  echo "Bottle reset. The next launch will recreate the prefix and reinstall Steam."
}

require_macos_arm64() {
  log "Checking platform"
  [[ "$(uname -s)" == "Darwin" ]] || die "This script supports macOS only."
  [[ "$(uname -m)" == "arm64" ]] || die "This script is intended for Apple Silicon (arm64)."
}

# Minimum macOS major version Cosmos supports. Matches the app bundles'
# LSMinimumSystemVersion. Override with COSMOS_MIN_MACOS_MAJOR if needed.
COSMOS_MIN_MACOS_MAJOR="${COSMOS_MIN_MACOS_MAJOR:-11}"

require_macos_version() {
  log "Checking macOS version"
  local product_version major
  product_version="$(sw_vers -productVersion 2>/dev/null || true)"
  if [[ -z "${product_version}" ]]; then
    echo "Could not determine macOS version (sw_vers unavailable). Continuing."
    return
  fi
  major="${product_version%%.*}"
  if [[ ! "${major}" =~ ^[0-9]+$ ]]; then
    echo "Unrecognized macOS version string '${product_version}'. Continuing."
    return
  fi
  if (( major < COSMOS_MIN_MACOS_MAJOR )); then
    die "Cosmos requires macOS ${COSMOS_MIN_MACOS_MAJOR} or newer (detected ${product_version})."
  fi
  echo "macOS ${product_version} meets the minimum (>= ${COSMOS_MIN_MACOS_MAJOR})."
}

ensure_sudo_ready() {
  log "Preparing sudo session (needed for Rosetta install if missing)"
  sudo -v
}

ensure_rosetta() {
  log "Ensuring Rosetta 2"
  if /usr/bin/arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
    echo "Rosetta is already available. Skipping."
    return
  fi

  ensure_sudo_ready
  sudo softwareupdate --install-rosetta --agree-to-license

  /usr/bin/arch -x86_64 /usr/bin/true >/dev/null 2>&1 || die "Rosetta installation check failed."
}

ensure_wine_installed() {
  log "Ensuring Wine ${WINE_VERSION} is installed"
  if [[ -x "${WINE_BIN}" ]]; then
    echo "Wine already installed at ${WINE_APP}. Skipping."
    return
  fi

  mkdir -p "${WINE_ROOT}"
  curl -L --fail --retry 5 --retry-delay 1 "${WINE_URL}" | tar xJf - -C "${WINE_ROOT}"
  [[ -x "${WINE_BIN}" ]] || die "Wine binary not found after extraction: ${WINE_BIN}"
}

ensure_wineprefix_alias() {
  log "Ensuring local alias to WINEPREFIX"
  local alias_path="${SCRIPT_DIR}/${WINEPREFIX_ALIAS_NAME}"
  local alias_dir
  alias_dir="$(dirname "${alias_path}")"

  if [[ -e "${alias_path}" && ! -L "${alias_path}" ]]; then
    echo "Path exists and is not a symlink: ${alias_path}. Skipping alias creation."
    return
  fi

  if [[ -L "${alias_path}" ]]; then
    local current_target
    current_target="$(readlink "${alias_path}")"
    if [[ "${current_target}" == "${WINEPREFIX}" ]]; then
      echo "Alias is already up to date: ${alias_path} -> ${WINEPREFIX}"
      return
    fi
  fi

  if [[ ! -d "${alias_dir}" ]]; then
    echo "Alias directory does not exist: ${alias_dir}. Skipping alias creation."
    return
  fi

  if [[ ! -w "${alias_dir}" ]]; then
    echo "Alias directory is not writable: ${alias_dir}. Skipping alias creation."
    return
  fi

  if ! ln -sfn "${WINEPREFIX}" "${alias_path}"; then
    echo "Could not create alias at ${alias_path}. Continuing without it."
    return
  fi

  echo "Alias created: ${alias_path} -> ${WINEPREFIX}"
}

setup_wine_env() {
  export WINEPREFIX
  export PATH
  PATH="$(dirname "${WINE_BIN}"):${PATH}"
}

ensure_wine_prefix() {
  log "Ensuring Wine prefix for Steam"
  if [[ -f "${WINEPREFIX}/system.reg" ]]; then
    echo "Wine prefix already initialized at ${WINEPREFIX}. Skipping."
    return
  fi
  "${WINE_BIN}" wineboot --init
}

ensure_wine_mouse_warp_override() {
  local mode="${WINE_MOUSE_WARP_OVERRIDE}"
  if [[ -z "${mode}" ]]; then
    log "Restoring default Wine MouseWarpOverride"
    if "${WINE_BIN}" reg query "HKCU\\Software\\Wine\\DirectInput" /v MouseWarpOverride >/dev/null 2>&1; then
      "${WINE_BIN}" reg delete "HKCU\\Software\\Wine\\DirectInput" /v MouseWarpOverride /f >/dev/null 2>&1 || true
      echo "Removed MouseWarpOverride from registry (Wine default behavior)."
    else
      echo "MouseWarpOverride is not set. Skipping."
    fi
    return
  fi

  case "${mode}" in
    force|enable|disable) ;;
    *) die "WINE_MOUSE_WARP_OVERRIDE must be one of: force | enable | disable | (empty for default)" ;;
  esac

  log "Configuring Wine MouseWarpOverride=${mode}"
  local query_out
  query_out="$("${WINE_BIN}" reg query "HKCU\\Software\\Wine\\DirectInput" /v MouseWarpOverride 2>/dev/null || true)"
  if printf "%s" "${query_out}" | grep -Eiq "MouseWarpOverride[[:space:]]+REG_SZ[[:space:]]+${mode}"; then
    echo "MouseWarpOverride is already set to ${mode}. Skipping."
    return
  fi

  "${WINE_BIN}" reg add "HKCU\\Software\\Wine\\DirectInput" /v MouseWarpOverride /t REG_SZ /d "${mode}" /f >/dev/null
  echo "Set MouseWarpOverride=${mode}."
}

ensure_wine_retina_mode() {
  local enabled="$1"
  [[ "${enabled}" == "0" || "${enabled}" == "1" ]] || die "WINE_RETINA_MODE must be 0 or 1."

  local desired_value="n"
  if [[ "${enabled}" == "1" ]]; then
    desired_value="y"
  fi

  log "Configuring Wine RetinaMode=${desired_value}"
  local query_out
  query_out="$("${WINE_BIN}" reg query "HKCU\\Software\\Wine\\Mac Driver" /v RetinaMode 2>/dev/null || true)"
  if printf "%s" "${query_out}" | grep -Eiq "RetinaMode[[:space:]]+REG_SZ[[:space:]]+${desired_value}"; then
    echo "RetinaMode is already set to ${desired_value}. Skipping."
    return
  fi

  "${WINE_BIN}" reg add "HKCU\\Software\\Wine\\Mac Driver" /v RetinaMode /t REG_SZ /d "${desired_value}" /f >/dev/null
  echo "Set RetinaMode=${desired_value}."
}

ensure_wine_windows_version() {
  local version="${WINDOWS_VERSION}"

  # Empty => leave Wine's built-in default; remove any prior override so the
  # bottle reverts cleanly (mirrors how the mouse-warp override behaves).
  if [[ -z "${version}" ]]; then
    log "Using Wine's default Windows version"
    if "${WINE_BIN}" reg query "HKCU\\Software\\Wine" /v Version >/dev/null 2>&1; then
      "${WINE_BIN}" reg delete "HKCU\\Software\\Wine" /v Version /f >/dev/null 2>&1 || true
      echo "Removed Windows-version override (Wine default)."
    else
      echo "No Windows-version override set. Skipping."
    fi
    return
  fi

  case "${version}" in
    winxp|win7|win8|win10|win11) ;;
    *) die "WINDOWS_VERSION must be one of: winxp | win7 | win8 | win10 | win11 (or empty for default)." ;;
  esac

  log "Configuring Windows version=${version}"
  local query_out
  query_out="$("${WINE_BIN}" reg query "HKCU\\Software\\Wine" /v Version 2>/dev/null || true)"
  if printf "%s" "${query_out}" | grep -Eiq "Version[[:space:]]+REG_SZ[[:space:]]+${version}([[:space:]]|$)"; then
    echo "Windows version is already set to ${version}. Skipping."
    return
  fi

  "${WINE_BIN}" reg add "HKCU\\Software\\Wine" /v Version /t REG_SZ /d "${version}" /f >/dev/null
  echo "Set Windows version=${version}."
}

ensure_wine_windows_mouse_accel_disabled() {
  log "Disabling Windows mouse acceleration in Wine"

  # Disable Windows "Enhanced Pointer Precision" (mouse acceleration) inside the prefix.
  # This is independent from macOS pointer acceleration.
  "${WINE_BIN}" reg add "HKCU\\Control Panel\\Mouse" /v MouseSpeed /t REG_SZ /d 0 /f >/dev/null
  "${WINE_BIN}" reg add "HKCU\\Control Panel\\Mouse" /v MouseThreshold1 /t REG_SZ /d 0 /f >/dev/null
  "${WINE_BIN}" reg add "HKCU\\Control Panel\\Mouse" /v MouseThreshold2 /t REG_SZ /d 0 /f >/dev/null

  echo "Set MouseSpeed=0, MouseThreshold1=0, MouseThreshold2=0."
}

find_steam_exe() {
  local steam32="${WINEPREFIX}/drive_c/Program Files (x86)/Steam/steam.exe"
  local steam64="${WINEPREFIX}/drive_c/Program Files/Steam/steam.exe"
  if [[ -f "${steam32}" ]]; then
    printf "%s\n" "${steam32}"
  elif [[ -f "${steam64}" ]]; then
    printf "%s\n" "${steam64}"
  fi
}

cleanup_steam_setup() {
  if [[ -f "${STEAM_SETUP}" ]]; then
    log "Cleaning up Steam installer cache"
    rm -f "${STEAM_SETUP}"
    echo "Removed ${STEAM_SETUP}."
  fi
}

# Best-effort terminate everything running in the active Wine prefix. A silent
# Steam install can auto-start Steam, so we stop it to leave a clean prefix for
# the explicit Launch Steam step.
stop_wine_prefix() {
  local wineserver_bin
  wineserver_bin="$(dirname "${WINE_BIN}")/wineserver"
  [[ -x "${wineserver_bin}" ]] || return 0
  WINEPREFIX="${WINEPREFIX}" "${wineserver_bin}" -k 2>/dev/null || true
}

# Attempt an unattended Steam install using the NSIS /S flag. Prints progress and
# returns 0 once steam.exe appears, or 1 on timeout so the caller can fall back
# to the interactive wizard.
install_steam_silently() {
  log "Installing Steam silently (no wizard)"
  echo "Running the Steam installer unattended — this usually takes under a minute."
  # NSIS installers accept /S for a silent install. Run it detached so a
  # post-install auto-launch of Steam can't block us while we poll for steam.exe.
  WINEPREFIX="${WINEPREFIX}" nohup "${WINE_BIN}" "${STEAM_SETUP}" /S </dev/null >/dev/null 2>&1 &
  disown

  local waited=0 steam_exe=""
  while ((waited < 120)); do
    steam_exe="$(find_steam_exe || true)"
    [[ -n "${steam_exe}" ]] && break
    sleep 3
    waited=$((waited + 3))
  done

  if [[ -z "${steam_exe}" ]]; then
    echo "Silent install did not finish within ${waited}s — falling back to the installer wizard."
    stop_wine_prefix
    return 1
  fi

  echo "Steam installed at ${steam_exe}."
  stop_wine_prefix
  return 0
}

ensure_steam_installed() {
  log "Ensuring Steam is installed in Wine prefix"
  local steam_exe
  steam_exe="$(find_steam_exe || true)"
  if [[ -n "${steam_exe}" ]]; then
    echo "Steam already installed at ${steam_exe}. Skipping installer."
    return
  fi

  if [[ ! -f "${STEAM_SETUP}" ]]; then
    echo "Downloading Steam installer..."
    curl -L --fail --retry 5 --retry-delay 1 -o "${STEAM_SETUP}" "${STEAM_URL}"
  fi

  if [[ "${COSMOS_STEAM_SILENT}" == "1" ]] && install_steam_silently; then
    cleanup_steam_setup
    return
  fi

  echo "Launching Steam installer. Complete the wizard in the Wine window."
  "${WINE_BIN}" "${STEAM_SETUP}"

  steam_exe="$(find_steam_exe || true)"
  [[ -n "${steam_exe}" ]] || die "Steam installation appears incomplete (steam.exe not found)."
  cleanup_steam_setup
}

ensure_dxmt_installed() {
  log "Ensuring DXMT ${DXMT_VERSION} is installed"
  if [[ -d "${DXMT_ROOT}/i386-windows" && -d "${DXMT_ROOT}/x86_64-windows" && -d "${DXMT_ROOT}/x86_64-unix" ]]; then
    echo "DXMT already installed at ${DXMT_ROOT}. Skipping."
    return
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d /tmp/dxmt.XXXXXX)"

  curl -L --fail --retry 5 --retry-delay 1 "${DXMT_URL}" | tar xzf - -C "${tmp_dir}"

  local payload_dir=""
  if [[ -d "${tmp_dir}/i386-windows" && -d "${tmp_dir}/x86_64-windows" && -d "${tmp_dir}/x86_64-unix" ]]; then
    payload_dir="${tmp_dir}"
  elif [[ -d "${tmp_dir}/v${DXMT_VERSION}/i386-windows" && -d "${tmp_dir}/v${DXMT_VERSION}/x86_64-windows" && -d "${tmp_dir}/v${DXMT_VERSION}/x86_64-unix" ]]; then
    payload_dir="${tmp_dir}/v${DXMT_VERSION}"
  fi

  [[ -n "${payload_dir}" ]] || die "DXMT extraction failed: payload directories not found."

  mkdir -p "${DXMT_ROOT}"
  rm -rf "${DXMT_ROOT}/i386-windows" "${DXMT_ROOT}/x86_64-windows" "${DXMT_ROOT}/x86_64-unix"
  cp -R "${payload_dir}/i386-windows" "${DXMT_ROOT}/"
  cp -R "${payload_dir}/x86_64-windows" "${DXMT_ROOT}/"
  cp -R "${payload_dir}/x86_64-unix" "${DXMT_ROOT}/"
  rm -rf "${tmp_dir}"
}

enable_dxmt_env() {
  log "Enabling DXMT via WINEDLLPATH_PREPEND"
  export WINEDLLPATH_PREPEND
  case ":${WINEDLLPATH_PREPEND:-}:" in
    *":${DXMT_ROOT}:"*) ;;
    *) WINEDLLPATH_PREPEND="${DXMT_ROOT}${WINEDLLPATH_PREPEND:+:${WINEDLLPATH_PREPEND}}" ;;
  esac

  export DXMT_LOG_LEVEL="${DXMT_LOG_LEVEL:-error}"
  export WINEDEBUG="${WINEDEBUG:--all,err+all}"
}

# Validate COSMOS_BACKEND and resolve 'recommended' to a concrete backend,
# storing the result in RESOLVED_BACKEND. Fails fast on an unknown value.
resolve_backend() {
  local requested
  requested="$(printf '%s' "${COSMOS_BACKEND}" | tr '[:upper:]' '[:lower:]')"
  case "${requested}" in
    recommended)
      if [[ -n "${GPTK_PATH}" ]]; then
        RESOLVED_BACKEND="d3dmetal"
      else
        RESOLVED_BACKEND="dxmt"
      fi
      ;;
    gptk)
      RESOLVED_BACKEND="d3dmetal"
      ;;
    dxmt|d3dmetal|dxvk|wined3d)
      RESOLVED_BACKEND="${requested}"
      ;;
    *)
      die "COSMOS_BACKEND must be one of: recommended | dxmt | d3dmetal | dxvk | wined3d (got '${COSMOS_BACKEND}')."
      ;;
  esac
}

find_gptk_dll_dir() {
  local root="$1"
  local candidates=(
    "${root}"
    "${root}/redist/lib/external"
    "${root}/lib/external"
    "${root}/lib"
    "${root}/Libraries"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -f "${c}/d3d11.dll" ]]; then
      printf '%s\n' "${c}"
      return 0
    fi
  done
  return 1
}

ensure_gptk_installed() {
  log "Installing GPTK DLLs into the Wine prefix"
  [[ -d "${GPTK_PATH}" ]] || die "GPTK_PATH is not a directory: ${GPTK_PATH}"

  local src
  if ! src="$(find_gptk_dll_dir "${GPTK_PATH}")"; then
    die "Could not find d3d11.dll under GPTK_PATH=${GPTK_PATH}. Obtain the Game Porting Toolkit from developer.apple.com and point GPTK_PATH at the root (or directly at the folder containing the DLLs)."
  fi

  local target="${WINEPREFIX}/drive_c/windows/system32"
  [[ -d "${target}" ]] || die "Prefix system32 not found (is the prefix initialized?): ${target}"

  echo "Copying GPTK DLLs from ${src} to ${target}"
  local f copied=0
  for f in "${src}"/*.dll; do
    [[ -f "${f}" ]] || continue
    cp -f "${f}" "${target}/"
    copied=$((copied + 1))
  done
  [[ "${copied}" -gt 0 ]] || die "No .dll files found in ${src}"
  echo "Copied ${copied} DLL(s)."
}

enable_gptk_env() {
  log "Enabling GPTK via WINEDLLOVERRIDES"
  export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d9,d3d10core,d3d11,d3d12,d3d12core,dxgi=n}"
  export WINEDEBUG="${WINEDEBUG:--all,err+all}"
  echo "WINEDLLOVERRIDES=${WINEDLLOVERRIDES}"
}

find_dxvk_dll_dir() {
  local root="$1"
  local candidates=(
    "${root}"
    "${root}/x64"
    "${root}/x32"
    "${root}/bin"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -f "${c}/dxgi.dll" || -f "${c}/d3d11.dll" ]]; then
      printf '%s\n' "${c}"
      return 0
    fi
  done
  return 1
}

ensure_dxvk_installed() {
  log "Installing DXVK DLLs into the Wine prefix (experimental)"
  [[ -n "${DXVK_PATH}" ]] || die "The dxvk backend needs DXVK_PATH set to a folder of DXVK DLLs (d3d11.dll, dxgi.dll, ...). DXVK on macOS routes through MoltenVK and is experimental; use dxmt or d3dmetal for a supported path."
  [[ -d "${DXVK_PATH}" ]] || die "DXVK_PATH is not a directory: ${DXVK_PATH}"

  local src
  if ! src="$(find_dxvk_dll_dir "${DXVK_PATH}")"; then
    die "Could not find DXVK DLLs (dxgi.dll / d3d11.dll) under DXVK_PATH=${DXVK_PATH}."
  fi

  local target="${WINEPREFIX}/drive_c/windows/system32"
  [[ -d "${target}" ]] || die "Prefix system32 not found (is the prefix initialized?): ${target}"

  echo "Copying DXVK DLLs from ${src} to ${target}"
  local f copied=0
  for f in d3d9 d3d10core d3d11 dxgi; do
    [[ -f "${src}/${f}.dll" ]] || continue
    cp -f "${src}/${f}.dll" "${target}/"
    copied=$((copied + 1))
  done
  [[ "${copied}" -gt 0 ]] || die "No DXVK DLLs found in ${src}"
  echo "Copied ${copied} DXVK DLL(s)."
}

enable_dxvk_env() {
  log "Enabling DXVK via WINEDLLOVERRIDES (experimental)"
  export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d9,d3d10core,d3d11,dxgi=n}"
  export WINEDEBUG="${WINEDEBUG:--all,err+all}"
  echo "WINEDLLOVERRIDES=${WINEDLLOVERRIDES}"
  echo "Note: DXVK needs a Vulkan driver (MoltenVK) on macOS. If games fail to"
  echo "start, install MoltenVK or switch to the dxmt / d3dmetal backend."
}

enable_wined3d_env() {
  log "Using Wine's built-in WineD3D (no translation layer)"
  # Force builtin d3d so any previously-installed DXMT/GPTK/DXVK native DLLs in the
  # prefix are ignored. WineD3D maps Direct3D to OpenGL: broadest compatibility,
  # slowest performance. Best used in a dedicated bottle.
  export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d9,d3d10core,d3d11,d3d12,d3d12core,dxgi=b}"
  export WINEDEBUG="${WINEDEBUG:--all,err+all}"
  echo "WINEDLLOVERRIDES=${WINEDLLOVERRIDES}"
}

launch_steam() {
  log "Launching Steam"
  local steam_exe
  steam_exe="$(find_steam_exe || true)"
  [[ -n "${steam_exe}" ]] || die "steam.exe not found."

  local wineserver_bin
  wineserver_bin="$(dirname "${WINE_BIN}")/wineserver"
  if [[ -x "${wineserver_bin}" ]] && ! WINEPREFIX="${WINEPREFIX}" "${wineserver_bin}" -w0 2>/dev/null; then
    echo "Note: Wine is already using this prefix. Quit Steam before launching again to avoid prefix corruption."
  fi

  local -a steam_cmd=("${WINE_BIN}" "${steam_exe}")
  if [[ -n "${STEAM_GAME_ID:-}" ]]; then
    echo "Launching Steam game ${STEAM_GAME_ID}..."
    steam_cmd+=(-applaunch "${STEAM_GAME_ID}")
    # Optional extra arguments handed to the game itself (Steam forwards anything
    # after the App ID). Split on whitespace; quoting is intentionally simple.
    if [[ -n "${STEAM_GAME_ARGS:-}" ]]; then
      local -a extra_args=()
      read -r -a extra_args <<< "${STEAM_GAME_ARGS}"
      if (( ${#extra_args[@]} > 0 )); then
        echo "Passing game arguments: ${STEAM_GAME_ARGS}"
        steam_cmd+=("${extra_args[@]}")
      fi
    fi
  fi

  case "${COSMOS_DETACH}" in
    0)
      "${steam_cmd[@]}"
      ;;
    1)
      log "Detaching Steam from this Terminal (log: ${COSMOS_LAUNCH_LOG})"
      mkdir -p "$(dirname "${COSMOS_LAUNCH_LOG}")"
      : >"${COSMOS_LAUNCH_LOG}" || die "Cannot write to ${COSMOS_LAUNCH_LOG}"
      nohup "${steam_cmd[@]}" </dev/null >>"${COSMOS_LAUNCH_LOG}" 2>&1 &
      local pid="$!"
      disown
      echo "Steam is running in the background (PID ${pid}). Safe to close this Terminal window."
      echo "Tail the log with: tail -f ${COSMOS_LAUNCH_LOG}"
      ;;
    *)
      die "COSMOS_DETACH must be 0 or 1."
      ;;
  esac
}

launch_profile() {
  log "Launching profile: ${PROFILE_EXECUTABLE}"
  [[ -n "${PROFILE_EXECUTABLE}" ]] || die "The --game/--profile flag requires a profile executable path."
  [[ -d "${PROFILE_DIRECTORY}" ]] || die "Profile directory is not available: ${PROFILE_DIRECTORY}"

  local profile_executable="${PROFILE_EXECUTABLE}"
  if [[ "${profile_executable}" != /* && -f "${PROFILE_DIRECTORY}/${profile_executable}" ]]; then
    # Relative names are resolved against the saved profiles directory first.
    profile_executable="${PROFILE_DIRECTORY}/${profile_executable}"
  fi

  [[ -f "${profile_executable}" ]] || die "Profile executable not found: ${PROFILE_EXECUTABLE}"

  local -a profile_cmd=("${WINE_BIN}" "${profile_executable}")
  if (( ${#PROFILE_ARGS[@]} > 0 )); then
    profile_cmd+=("${PROFILE_ARGS[@]}")
  fi

  case "${COSMOS_DETACH}" in
    0)
      "${profile_cmd[@]}"
      ;;
    1)
      log "Detaching profile launch from this Terminal (log: ${COSMOS_LAUNCH_LOG})"
      mkdir -p "$(dirname "${COSMOS_LAUNCH_LOG}")"
      : >"${COSMOS_LAUNCH_LOG}" || die "Cannot write to ${COSMOS_LAUNCH_LOG}"
      nohup "${profile_cmd[@]}" </dev/null >>"${COSMOS_LAUNCH_LOG}" 2>&1 &
      local pid="$!"
      disown
      echo "Profile is running in the background (PID ${pid}). Safe to close this Terminal window."
      echo "Tail the log with: tail -f ${COSMOS_LAUNCH_LOG}"
      ;;
    *)
      die "COSMOS_DETACH must be 0 or 1."
      ;;
  esac
}

prepare_steam_bottle() {
  resolve_backend

  require_macos_version
  ensure_rosetta
  ensure_wine_installed
  setup_wine_env
  ensure_wine_prefix
  ensure_wineprefix_alias
  ensure_wine_mouse_warp_override
  ensure_wine_retina_mode "${WINE_RETINA_MODE}"
  ensure_wine_windows_version
  ensure_wine_windows_mouse_accel_disabled
  ensure_steam_installed

  log "Graphics backend: ${RESOLVED_BACKEND} (requested: ${COSMOS_BACKEND})"
  case "${RESOLVED_BACKEND}" in
    dxmt)
      ensure_dxmt_installed
      enable_dxmt_env
      ;;
    d3dmetal)
      [[ -n "${GPTK_PATH}" ]] || die "The d3dmetal backend needs GPTK_PATH set to your Game Porting Toolkit install (Apple does not permit Cosmos to bundle it). Use the dxmt backend for a no-setup default."
      ensure_gptk_installed
      enable_gptk_env
      ;;
    dxvk)
      ensure_dxvk_installed
      enable_dxvk_env
      ;;
    wined3d)
      enable_wined3d_env
      ;;
    *)
      die "Unhandled backend: ${RESOLVED_BACKEND}"
      ;;
  esac
}

prepare_steam_bottle() {
  resolve_backend
  require_macos_version
  ensure_rosetta
  ensure_wine_installed
  setup_wine_env
  ensure_wine_prefix
  ensure_wineprefix_alias
  ensure_wine_mouse_warp_override
  ensure_wine_retina_mode "${WINE_RETINA_MODE}"
  ensure_wine_windows_version
  ensure_wine_windows_mouse_accel_disabled
  ensure_steam_installed
  log "Graphics backend: ${RESOLVED_BACKEND} (requested: ${COSMOS_BACKEND})"
  case "${RESOLVED_BACKEND}" in
    dxmt) ensure_dxmt_installed; enable_dxmt_env ;;
    d3dmetal)
      [[ -n "${GPTK_PATH}" ]] || die "The d3dmetal backend needs GPTK_PATH set to your Game Porting Toolkit install (Apple does not permit Cosmos to bundle it). Use the dxmt backend for a no-setup default."
      ensure_gptk_installed; enable_gptk_env ;;
    dxvk) ensure_dxvk_installed; enable_dxvk_env ;;
    wined3d) enable_wined3d_env ;;
    *) die "Unhandled backend: ${RESOLVED_BACKEND}" ;;
  esac
}

finish_steam_setup() {
  local steam_exe
  steam_exe="$(find_steam_exe || true)"
  echo ""
  echo "Steam bottle is ready at ${WINEPREFIX}."
  if [[ -n "${steam_exe}" ]]; then
    echo "Steam: ${steam_exe}"
    echo "Launch with: ./run.command --steam"
    echo "Or use Launch Steam in the Cosmos dashboard."
  else
    echo "Steam installer did not finish — re-run ./run.command --setup-steam and complete the wizard."
  fi
  echo "Launch log (detached mode): ${COSMOS_LAUNCH_LOG}"
  echo "Manual setup guide: docs/STEAM_SETUP.md"
}

# Count saved game profiles (.yaml) across the profile directory tree.
count_profiles() {
  [[ -d "${PROFILE_DIRECTORY}" ]] || { printf "0\n"; return; }
  find "${PROFILE_DIRECTORY}" -type f -name "*.yaml" 2>/dev/null | wc -l | tr -d ' '
}

# Print a check/cross marker line for a setup step.
status_line() {
  local done="$1" label="$2" detail="$3"
  if [[ "${done}" -eq 1 ]]; then
    printf "  [x] %s\n" "${label}"
  else
    printf "  [ ] %s\n" "${label}"
  fi
  [[ -n "${detail}" ]] && printf "        %s\n" "${detail}"
}

# Mirror the dashboard's setup checklist in Terminal: report which steps are
# done and recommend the next one. Read-only — never modifies the prefix.
show_status() {
  local wine_ok=0 prefix_ok=0 steam_ok=0 profiles_count steam_exe
  [[ -x "${WINE_BIN}" ]] && wine_ok=1
  [[ -f "${WINEPREFIX}/system.reg" ]] && prefix_ok=1
  steam_exe="$(find_steam_exe || true)"
  [[ -n "${steam_exe}" ]] && steam_ok=1
  profiles_count="$(count_profiles)"

  echo ""
  echo "  Cosmos — Steam setup status"
  echo "  ==========================="
  [[ -n "${COSMOS_BOTTLE}" ]] && echo "  Bottle: ${COSMOS_BOTTLE}"
  echo ""
  status_line "${wine_ok}" "Wine ${WINE_VERSION} downloaded" \
    "$([[ "${wine_ok}" -eq 1 ]] && echo "${WINE_APP}" || echo "Downloads on first --setup-steam or --steam")"
  status_line "${prefix_ok}" "Wine prefix created" \
    "$([[ "${prefix_ok}" -eq 1 ]] && echo "${WINEPREFIX}" || echo "Created during --setup-steam")"
  status_line "${steam_ok}" "Steam installed in prefix" \
    "$([[ "${steam_ok}" -eq 1 ]] && echo "${steam_exe}" || echo "Complete the Steam installer wizard")"
  status_line "$([[ "${profiles_count}" -gt 0 ]] && echo 1 || echo 0)" "Game launchers built" \
    "$([[ "${profiles_count}" -gt 0 ]] && echo "${profiles_count} profile(s) in ${PROFILE_DIRECTORY}" || echo "Run ./detect_steam_games.command --install after installing a game")"

  echo ""
  echo "  Backend: ${COSMOS_BACKEND}   Windows: ${WINDOWS_VERSION:-Wine default}   Retina: $([[ "${WINE_RETINA_MODE}" == "1" ]] && echo on || echo off)   Install: $([[ "${COSMOS_STEAM_SILENT}" == "1" ]] && echo silent || echo wizard)"
  echo ""
  if [[ "${wine_ok}" -eq 0 || "${prefix_ok}" -eq 0 || "${steam_ok}" -eq 0 ]]; then
    echo "  Next step: ./run.command --setup-steam"
  elif [[ "${profiles_count}" -eq 0 ]]; then
    echo "  Next step: launch Steam (./run.command --steam), install a Windows game,"
    echo "             then ./detect_steam_games.command --install"
  else
    echo "  Setup complete. Launch Steam with ./run.command --steam"
  fi
  echo ""
}

main() {
  parse_arguments "$@"
  require_macos_arm64
  [[ -n "${COSMOS_BOTTLE}" ]] && log "Bottle: ${COSMOS_BOTTLE} (prefix: ${WINEPREFIX})"
  case "${COSMOS_LAUNCH_MODE}" in
    profiles) open_profiles_folder; return ;;
    logs) open_logs; return ;;
    status) show_status; return ;;
    reset-bottle) reset_bottle; return ;;
    setup-steam)
      log "Preparing Steam bottle (no launch)"
      prepare_steam_bottle
      finish_steam_setup
      return ;;
  esac
  prepare_steam_bottle
  if [[ "${COSMOS_LAUNCH_MODE}" == "profile" ]]; then
    launch_profile
  else
    launch_steam
  fi
}

main "$@"