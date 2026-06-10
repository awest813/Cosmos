#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=scripts/lib/steam_lib.sh
source "${SCRIPT_DIR}/scripts/lib/steam_lib.sh"
if [[ -f "${SCRIPT_DIR}/scripts/lib/import_lib.sh" ]]; then
  # shellcheck source=scripts/lib/import_lib.sh
  source "${SCRIPT_DIR}/scripts/lib/import_lib.sh"
fi
# profile_lib powers the pre-launch compatibility heads-up (best-effort).
if [[ -f "${SCRIPT_DIR}/scripts/lib/profile_lib.sh" ]]; then
  # shellcheck source=scripts/lib/profile_lib.sh
  source "${SCRIPT_DIR}/scripts/lib/profile_lib.sh"
fi
if [[ -f "${SCRIPT_DIR}/scripts/lib/runtime_lib.sh" ]]; then
  # shellcheck source=scripts/lib/runtime_lib.sh
  source "${SCRIPT_DIR}/scripts/lib/runtime_lib.sh"
fi
if [[ -f "${SCRIPT_DIR}/scripts/lib/rosetta_lib.sh" ]]; then
  # shellcheck source=scripts/lib/rosetta_lib.sh
  source "${SCRIPT_DIR}/scripts/lib/rosetta_lib.sh"
fi
if [[ -f "${SCRIPT_DIR}/scripts/lib/wine_lib.sh" ]]; then
  # shellcheck source=scripts/lib/wine_lib.sh
  source "${SCRIPT_DIR}/scripts/lib/wine_lib.sh"
fi
if [[ -f "${SCRIPT_DIR}/scripts/lib/sync_lib.sh" ]]; then
  # shellcheck source=scripts/lib/sync_lib.sh
  source "${SCRIPT_DIR}/scripts/lib/sync_lib.sh"
fi
if [[ -f "${SCRIPT_DIR}/scripts/lib/gptk_lib.sh" ]]; then
  # shellcheck source=scripts/lib/gptk_lib.sh
  source "${SCRIPT_DIR}/scripts/lib/gptk_lib.sh"
fi
if [[ -f "${SCRIPT_DIR}/scripts/lib/graphics_lib.sh" ]]; then
  # shellcheck source=scripts/lib/graphics_lib.sh
  source "${SCRIPT_DIR}/scripts/lib/graphics_lib.sh"
fi

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
STEAM_LAUNCH_ARGS="-no-cef-sandbox -cef-single-process -noverifyfiles"
COSMOS_STEAM_WEBHELPER_WRAPPER="1"
COSMOS_STEAM_SEED_FONTS="1"
COSMOS_STEAM_CA_BUNDLE="1"
COSMOS_STEAM_WINEDLLOVERRIDES="dxgi,d3d11,d3d10core=n,b;bcrypt=b;ncrypt=b;gameoverlayrenderer,gameoverlayrenderer64=d"
WINE_VIRTUAL_DESKTOP="auto"
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
  case "${COSMOS_STEAM_WEBHELPER_WRAPPER}" in 0|1) ;; *) COSMOS_STEAM_WEBHELPER_WRAPPER=1 ;; esac
  case "${COSMOS_STEAM_SEED_FONTS}" in 0|1) ;; *) COSMOS_STEAM_SEED_FONTS=1 ;; esac
  case "${COSMOS_STEAM_CA_BUNDLE}" in 0|1) ;; *) COSMOS_STEAM_CA_BUNDLE=1 ;; esac
  case "${WINE_RETINA_MODE}" in 0|1) ;; *) WINE_RETINA_MODE=0 ;; esac
  case "${WINDOWS_VERSION}" in
    ""|winxp|win7|win8|win10|win11) ;;
    *) WINDOWS_VERSION="" ;;
  esac
  if declare -F cosmos_sync_mode_normalize >/dev/null 2>&1; then
    COSMOS_SYNC_MODE="$(cosmos_sync_mode_normalize "${COSMOS_SYNC_MODE:-off}")"
  fi
  case "${COSMOS_DXMT_CHANNEL:-stable}" in
    stable|latest|experimental) ;;
    *) COSMOS_DXMT_CHANNEL="stable" ;;
  esac
  case "${COSMOS_METALFX:-0}" in 0|1) ;; *) COSMOS_METALFX=0 ;; esac
  case "${COSMOS_MVK_PRESET:-default}" in
    default|performance|compatibility) ;;
    *) COSMOS_MVK_PRESET="default" ;;
  esac
}

load_bottle
ensure_steam_conf
load_steam_conf
sanitize_steam_settings
if declare -F cosmos_graphics_env_apply >/dev/null 2>&1; then
  cosmos_graphics_env_apply
fi
if declare -F cosmos_sync_mode_apply >/dev/null 2>&1; then
  cosmos_sync_mode_apply
fi
# -----------------------------------------------------------------------------

if declare -F runtime_load_manifest >/dev/null 2>&1; then
  runtime_load_manifest
fi

WINE_VERSION="${WINE_VERSION:-11.8}"
# Pinned in runtime/cosmos-runtime.json (0.80 MIT; Latest channel may use LGPL 0.81+).
DXMT_VERSION="${DXMT_VERSION:-0.80}"

if declare -F runtime_assert_dxmt_license >/dev/null 2>&1; then
  runtime_assert_dxmt_license || exit 1
fi

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
# 1=skip Steam install (standalone / non-Steam launchers).
COSMOS_SKIP_STEAM="${COSMOS_SKIP_STEAM:-0}"
COSMOS_LAUNCH_LOG="${COSMOS_LAUNCH_LOG:-${MERLOT_LAUNCH_LOG:-${COSMOS_STEAM_LOG:-${MERLOT_STEAM_LOG:-${STEAM_LAUNCH_LOG_DEFAULT}}}}}"
# Automatic recovery for launches that fail or crash on startup. The most common
# "small issue" is a stale wineserver from a previous crashed session holding the
# prefix; before each retry we clear it so the game still runs. Number of extra
# attempts after the first; set to 0 to disable.
COSMOS_LAUNCH_RETRIES="${COSMOS_LAUNCH_RETRIES:-1}"
# Seconds a detached launch must survive before it counts as healthy. A process
# that exits within this window is treated as a crash-on-startup and retried.
COSMOS_LAUNCH_GRACE="${COSMOS_LAUNCH_GRACE:-6}"
# Fall back to safe defaults if these were set to something non-numeric.
[[ "${COSMOS_LAUNCH_RETRIES}" =~ ^[0-9]+$ ]] || COSMOS_LAUNCH_RETRIES=1
[[ "${COSMOS_LAUNCH_GRACE}" =~ ^[0-9]+$ ]] || COSMOS_LAUNCH_GRACE=6
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
# 1=skip the pre-launch compatibility heads-up that warns about games marked
# broken/blocked (anti-cheat/DRM) in their curated profile. See compat_preflight.
COSMOS_SKIP_COMPAT_CHECK="${COSMOS_SKIP_COMPAT_CHECK:-0}"
# Override the profiles directory used by the compatibility check (default:
# the profiles/ folder next to this script or bundled into the .app).
COSMOS_PROFILES_DIR="${COSMOS_PROFILES_DIR:-${SCRIPT_DIR}/profiles}"
PROFILE_EXECUTABLE=""
PROFILE_ARGS=()
INSTALLER_PATH=""
COMPAT_CHECK_APPID=""

WINE_URL="${WINE_URL:-https://github.com/Gcenx/macOS_Wine_builds/releases/download/${WINE_VERSION}/wine-devel-${WINE_VERSION}-osx64.tar.xz}"
STEAM_URL="https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"
DXMT_URL="${DXMT_URL:-https://github.com/3Shain/dxmt/releases/download/v${DXMT_VERSION}/dxmt-v${DXMT_VERSION}-builtin.tar.gz}"

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
  --install-steam         Install or reinstall Steam in an existing prefix only.
  --status                 Show setup progress and the next step, then exit.
  --runtime-status         Print machine-readable Wine/Rosetta status (key=value).
  --install-rosetta        Install Rosetta 2 on Apple Silicon if missing, then exit.
  --compat-check <appid>   Print the curated compatibility status for a Steam
                           App ID (warns if broken/blocked), then exit.
  --validate-gptk <path>   Validate a user-supplied GPTK install (key=value), then exit.
  --game <path> [args...]  Launch a saved profile executable directly.
  --run-installer <file>   Run a Windows .exe/.msi installer in the prefix.
  --profiles               Open the saved profiles folder in Finder and exit.
  --logs                   Open the latest launch log and exit.
  --check-update           Compare local app/runtime version to GitHub Releases.
  --install-update         Download Cosmos.dmg from GitHub and install to /Applications.
  --sync-steam             Build launchers for newly installed Steam games only.
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
    --install-steam)
      if (($# > 1)); then
        die "The --install-steam flag does not accept additional arguments."
      fi
      COSMOS_LAUNCH_MODE="install-steam"
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
    --run-installer)
      if (($# < 2)); then
        die "Missing required argument for --run-installer."
      fi
      INSTALLER_PATH="$2"
      COSMOS_LAUNCH_MODE="run-installer"
      return 0
      ;;
    --logs)
      if (($# > 1)); then
        die "The --logs flag does not accept additional arguments."
      fi
      COSMOS_LAUNCH_MODE="logs"
      return 0
      ;;
    --check-update)
      if (($# > 1)); then
        die "The --check-update flag does not accept additional arguments."
      fi
      COSMOS_LAUNCH_MODE="check-update"
      return 0
      ;;
    --install-update)
      if (($# > 1)); then
        die "The --install-update flag does not accept additional arguments."
      fi
      COSMOS_LAUNCH_MODE="install-update"
      return 0
      ;;
    --sync-steam)
      if (($# > 1)); then
        die "The --sync-steam flag does not accept additional arguments."
      fi
      COSMOS_LAUNCH_MODE="sync-steam"
      return 0
      ;;
    --status|--doctor)
      if (($# > 1)); then
        die "The $1 flag does not accept additional arguments."
      fi
      COSMOS_LAUNCH_MODE="status"
      return 0
      ;;
    --runtime-status)
      if (($# > 1)); then
        die "The --runtime-status flag does not accept additional arguments."
      fi
      COSMOS_LAUNCH_MODE="runtime-status"
      return 0
      ;;
    --install-rosetta)
      if (($# > 1)); then
        die "The --install-rosetta flag does not accept additional arguments."
      fi
      COSMOS_LAUNCH_MODE="install-rosetta"
      return 0
      ;;
    --compat-check)
      if (($# < 2)); then
        die "Missing required Steam App ID for --compat-check."
      fi
      if (($# > 2)); then
        die "The --compat-check flag accepts only one Steam App ID."
      fi
      COMPAT_CHECK_APPID="$2"
      COSMOS_LAUNCH_MODE="compat-check"
      return 0
      ;;
    --validate-gptk)
      if (($# < 2)); then
        die "Missing required path for --validate-gptk."
      fi
      if (($# > 2)); then
        die "The --validate-gptk flag accepts only one path."
      fi
      GPTK_VALIDATE_PATH="$2"
      COSMOS_LAUNCH_MODE="validate-gptk"
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

require_supported_macos() {
  log "Checking platform"
  [[ "$(uname -s)" == "Darwin" ]] || die "This script supports macOS only."
  if declare -F cosmos_host_supported >/dev/null 2>&1; then
    cosmos_host_supported || die "Unsupported Mac architecture: $(uname -m). Cosmos supports Apple Silicon (arm64) and Intel (x86_64)."
  else
    case "$(uname -m)" in
      arm64|x86_64) ;;
      *) die "Unsupported Mac architecture: $(uname -m). Cosmos supports Apple Silicon (arm64) and Intel (x86_64)." ;;
    esac
  fi
  if declare -F cosmos_host_platform_label >/dev/null 2>&1; then
    echo "Host: $(cosmos_host_platform_label) ($(uname -m))"
  fi
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
  rosetta_ensure || die "Rosetta installation failed. Apple Silicon needs Rosetta 2 to run x86_64 Wine."
}

ensure_wine_installed() {
  log "Ensuring Wine ${WINE_VERSION} is installed"
  if declare -F wine_is_installed >/dev/null 2>&1 && wine_is_installed; then
    WINE_BIN="$(wine_resolve_bin)"
    WINE_APP="$(wine_resolve_app)"
    WINE_ROOT="$(wine_default_root)"
    echo "Wine already installed at ${WINE_APP}. Skipping."
    return
  fi
  if [[ -x "${WINE_BIN}" ]]; then
    echo "Wine already installed at ${WINE_APP}. Skipping."
    return
  fi

  if declare -F runtime_try_offline_stack >/dev/null 2>&1; then
    if runtime_try_offline_stack; then
      [[ -x "${WINE_BIN}" ]] && return 0
    fi
  fi

  mkdir -p "${WINE_ROOT}"
  if ! curl -L --fail --retry 5 --retry-delay 1 "${WINE_URL}" | tar xJf - -C "${WINE_ROOT}"; then
    die "Wine download failed. Check your network connection and try again."
  fi
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
    echo "Wine prefix already initialized at ${WINEPREFIX} — aligning with current Wine."
    "${WINE_BIN}" wineboot -u >/dev/null 2>&1 || true
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

STEAM_SETUP_MIN_BYTES=1000000

find_steam_exe() {
  local candidate
  candidate="$(steam_find_exe_candidate || true)"
  [[ -n "${candidate}" ]] && steam_exe_is_valid "${candidate}" && printf '%s\n' "${candidate}"
}

# True when a Steam folder exists but steam.exe is missing or looks corrupt.
steam_install_incomplete() {
  local candidate
  candidate="$(steam_find_exe_candidate || true)"
  if [[ -n "${candidate}" ]]; then
    steam_exe_is_valid "${candidate}" && return 1
    echo "Found invalid steam.exe at ${candidate} (too small or not a PE executable)." >&2
    return 0
  fi
  local base
  for base in \
    "${WINEPREFIX}/drive_c/Program Files (x86)/Steam" \
    "${WINEPREFIX}/drive_c/Program Files/Steam"; do
    [[ -d "${base}" ]] && return 0
  done
  return 1
}

remove_steam_from_prefix() {
  local base removed=0
  stop_wine_prefix
  for base in \
    "${WINEPREFIX}/drive_c/Program Files (x86)/Steam" \
    "${WINEPREFIX}/drive_c/Program Files/Steam"; do
    if [[ -d "${base}" ]]; then
      rm -rf "${base}"
      echo "Removed incomplete Steam install at ${base}."
      removed=1
    fi
  done
  (( removed )) || echo "No Steam directories found to remove."
}

validate_steam_setup() {
  [[ -f "${STEAM_SETUP}" ]] || return 1
  local size magic
  size="$(wc -c <"${STEAM_SETUP}" | tr -d ' ')"
  (( size >= STEAM_SETUP_MIN_BYTES )) || return 1
  magic="$(dd if="${STEAM_SETUP}" bs=1 count=2 2>/dev/null || true)"
  [[ "${magic}" == $'MZ' ]] || return 1
}

download_steam_setup() {
  if validate_steam_setup; then
    echo "Using cached Steam installer at ${STEAM_SETUP}."
    return 0
  fi
  [[ ! -f "${STEAM_SETUP}" ]] || {
    echo "Removing invalid cached Steam installer at ${STEAM_SETUP}."
    rm -f "${STEAM_SETUP}"
  }
  echo "Downloading Steam installer..."
  curl -L --fail --retry 5 --retry-delay 1 -o "${STEAM_SETUP}" "${STEAM_URL}"
  validate_steam_setup || die "Downloaded Steam installer looks invalid. Check your network and try again."
  echo "Downloaded $(wc -c <"${STEAM_SETUP}" | tr -d ' ') bytes."
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
  steam_stop_lingering_processes
}

# Attempt an unattended Steam install using the NSIS /S flag. Prints progress and
# returns 0 once steam.exe appears, or 1 on timeout so the caller can fall back
# to the interactive wizard.
install_steam_silently() {
  log "Installing Steam silently (no wizard)"
  echo "Running the Steam installer unattended — this usually takes 30–90 seconds."
  stop_wine_prefix

  local install_log="${COSMOS_SUPPORT_DIR}/logs/steam-install.log"
  mkdir -p "$(dirname "${install_log}")"
  : >"${install_log}" || install_log="/dev/null"

  # NSIS installers accept /S for a silent install. Run it detached so a
  # post-install auto-launch of Steam can't block us while we poll for steam.exe.
  WINEPREFIX="${WINEPREFIX}" nohup "${WINE_BIN}" "${STEAM_SETUP}" /S </dev/null >>"${install_log}" 2>&1 &
  disown

  local waited=0 steam_exe="" candidate=""
  local timeout=180
  printf 'Waiting for steam.exe'
  while ((waited < timeout)); do
    candidate="$(steam_find_exe_candidate || true)"
    if [[ -n "${candidate}" ]] && steam_exe_is_valid "${candidate}"; then
      steam_exe="${candidate}"
      break
    fi
    printf '.'
    sleep 3
    waited=$((waited + 3))
  done
  printf '\n'

  if [[ -z "${steam_exe}" ]]; then
    if [[ -n "${candidate}" ]]; then
      echo "Silent install produced an invalid steam.exe at ${candidate} — falling back to the installer wizard."
    else
      echo "Silent install did not finish within ${waited}s — falling back to the installer wizard."
    fi
    echo "Installer log: ${install_log}"
    stop_wine_prefix
    return 1
  fi

  local size
  size="$(wc -c <"${steam_exe}" | tr -d ' ')"
  echo "Steam installed at ${steam_exe} (${size} bytes)."
  stop_wine_prefix
  return 0
}

run_steam_installer_wizard() {
  echo "Launching Steam installer. Complete the wizard in the Wine window."
  WINEPREFIX="${WINEPREFIX}" "${WINE_BIN}" "${STEAM_SETUP}"
}

ensure_steam_installed() {
  log "Ensuring Steam is installed in Wine prefix"
  local steam_exe
  steam_exe="$(find_steam_exe || true)"
  if [[ -n "${steam_exe}" ]]; then
    echo "Steam already installed at ${steam_exe}. Skipping installer."
    return
  fi

  if steam_install_incomplete; then
    echo "Found an incomplete Steam install in the prefix — removing it before retrying."
    remove_steam_from_prefix
  fi

  download_steam_setup

  if [[ "${COSMOS_STEAM_SILENT}" == "1" ]] && install_steam_silently; then
    cleanup_steam_setup
    return
  fi

  if steam_install_incomplete; then
    echo "Clearing leftover Steam files before the installer wizard."
    remove_steam_from_prefix
  fi

  run_steam_installer_wizard

  steam_exe="$(find_steam_exe || true)"
  [[ -n "${steam_exe}" ]] || die "Steam installation appears incomplete (steam.exe not found)."
  stop_wine_prefix
  cleanup_steam_setup
}

install_steam_only() {
  require_macos_version
  ensure_wine_installed
  setup_wine_env
  [[ -f "${WINEPREFIX}/system.reg" ]] \
    || die "Wine prefix not initialized at ${WINEPREFIX}. Run ./run.command --setup-steam first."
  steam_prepare_prefix
  ensure_steam_installed
  steam_ensure_webhelper_wrapper || true
}

ensure_dxmt_installed() {
  if declare -F runtime_assert_dxmt_license >/dev/null 2>&1; then
    runtime_assert_dxmt_license || exit 1
  fi
  log "Ensuring DXMT ${DXMT_VERSION} is installed"
  if [[ -d "${DXMT_ROOT}/i386-windows" && -d "${DXMT_ROOT}/x86_64-windows" && -d "${DXMT_ROOT}/x86_64-unix" ]]; then
    echo "DXMT already installed at ${DXMT_ROOT}. Skipping."
    return
  fi

  if declare -F runtime_install_dxmt_from_offline_bundle >/dev/null 2>&1; then
    local tarball
    tarball="$(runtime_find_offline_tarball 2>/dev/null || true)"
    if [[ -n "${tarball}" ]]; then
      runtime_extract_offline_tarball "${tarball}" && runtime_install_dxmt_from_offline_bundle && return 0
    fi
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d /tmp/dxmt.XXXXXX)"

  if ! curl -L --fail --retry 5 --retry-delay 1 "${DXMT_URL}" | tar xzf - -C "${tmp_dir}"; then
    rm -rf "${tmp_dir}"
    die "DXMT download failed. Check your network connection and try again."
  fi

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

ensure_gptk_installed() {
  log "Installing GPTK DLLs into the Wine prefix"
  [[ -d "${GPTK_PATH}" ]] || die "GPTK_PATH is not a directory: ${GPTK_PATH}"

  local src
  if ! src="$(gptk_find_dll_dir "${GPTK_PATH}")"; then
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
  if declare -F runtime_auto_fetch_dxvk_stack >/dev/null 2>&1; then
    runtime_auto_fetch_dxvk_stack || true
  fi
  [[ -n "${DXVK_PATH}" ]] || die "The dxvk backend needs DXVK_PATH set to a folder of DXVK DLLs (d3d11.dll, dxgi.dll, ...), or set COSMOS_AUTO_DXVK=1 to download DXVK-macOS + MoltenVK into Application Support/Cosmos/Runtime/. DXVK on macOS is experimental; use dxmt or d3dmetal for a supported path."
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

# Clear common transient blockers before a relaunch. A leftover wineserver from
# a previous crashed session can hold the prefix and make the next launch fail or
# hang; killing it lets the retry start from a clean state. Best-effort and safe
# to call when nothing is actually wrong.
recover_wine_prefix() {
  log "Clearing the Wine prefix before retrying"
  stop_wine_prefix
  # Give wineserver a moment to release the prefix before relaunching.
  sleep 2
}

# Run a launch command with automatic recovery so a small hiccup does not stop
# the game from running. Usage: run_launch_cmd LABEL DETACH_RETRY CMD [ARGS...]
#   LABEL        - human name used in progress messages.
#   DETACH_RETRY - 1 to also retry crash-on-startup in detached mode, else 0.
#                  Steam passes 0 because its bootstrapper can exit its first
#                  process while Steam keeps running, which would look like a
#                  crash; standalone games/profiles pass 1.
# Honors COSMOS_DETACH, COSMOS_LAUNCH_RETRIES, and COSMOS_LAUNCH_GRACE.
run_launch_cmd() {
  local label="$1" detach_retry="$2"
  shift 2
  local -a cmd=("$@")
  local attempts=$((COSMOS_LAUNCH_RETRIES + 1))
  local attempt=1 status=0

  if [[ "${COSMOS_DETACH}" != "0" && "${COSMOS_DETACH}" != "1" ]]; then
    die "COSMOS_DETACH must be 0 or 1."
  fi

  # Foreground: the call blocks until the process really exits, so the exit code
  # is trustworthy and we retry any non-zero result.
  if [[ "${COSMOS_DETACH}" == "0" ]]; then
    while (( attempt <= attempts )); do
      status=0
      "${cmd[@]}" || status=$?
      (( status == 0 )) && return 0
      if (( attempt < attempts )); then
        echo "${label} exited with status ${status}. Recovering and retrying (attempt $((attempt + 1)) of ${attempts})..."
        recover_wine_prefix
      fi
      attempt=$((attempt + 1))
    done
    echo "${label} still failed after ${attempts} attempt(s) (status ${status})."
    return "${status}"
  fi

  # Detached.
  mkdir -p "$(dirname "${COSMOS_LAUNCH_LOG}")"

  # Classic fire-and-forget when crash-on-startup retries are not wanted here.
  if [[ "${detach_retry}" != "1" || "${COSMOS_LAUNCH_RETRIES}" -le 0 ]]; then
    : >"${COSMOS_LAUNCH_LOG}" || die "Cannot write to ${COSMOS_LAUNCH_LOG}"
    log "Detaching ${label} from this Terminal (log: ${COSMOS_LAUNCH_LOG})"
    nohup "${cmd[@]}" </dev/null >>"${COSMOS_LAUNCH_LOG}" 2>&1 &
    local pid="$!"
    disown
    echo "${label} is running in the background (PID ${pid}). Safe to close this Terminal window."
    echo "Tail the log with: tail -f ${COSMOS_LAUNCH_LOG}"
    return 0
  fi

  while (( attempt <= attempts )); do
    : >"${COSMOS_LAUNCH_LOG}" || die "Cannot write to ${COSMOS_LAUNCH_LOG}"
    log "Detaching ${label} from this Terminal (log: ${COSMOS_LAUNCH_LOG})"
    nohup "${cmd[@]}" </dev/null >>"${COSMOS_LAUNCH_LOG}" 2>&1 &
    local pid="$!"
    # Watch briefly so a crash-on-startup is retried instead of silently failing.
    local waited=0
    while (( waited < COSMOS_LAUNCH_GRACE )); do
      kill -0 "${pid}" 2>/dev/null || break
      sleep 1
      waited=$((waited + 1))
    done
    if kill -0 "${pid}" 2>/dev/null; then
      disown
      echo "${label} is running in the background (PID ${pid}). Safe to close this Terminal window."
      echo "Tail the log with: tail -f ${COSMOS_LAUNCH_LOG}"
      return 0
    fi
    status=0
    wait "${pid}" 2>/dev/null || status=$?
    if (( status == 0 )); then
      echo "${label} exited right after starting (status 0). See ${COSMOS_LAUNCH_LOG}."
      return 0
    fi
    if (( attempt < attempts )); then
      echo "${label} crashed on startup (status ${status}). Recovering and retrying (attempt $((attempt + 1)) of ${attempts})..."
      recover_wine_prefix
    fi
    attempt=$((attempt + 1))
  done
  echo "${label} could not start after ${attempts} attempt(s) (status ${status}). See ${COSMOS_LAUNCH_LOG}."
  return "${status}"
}

# Pre-launch compatibility heads-up. When launching a known Steam game, check its
# curated profile and warn if it is marked broken/blocked (e.g. anti-cheat) so the
# user is not surprised — the macOS equivalent of a ProtonDB "Blocked" badge.
# Best-effort: never blocks the launch. Set COSMOS_SKIP_COMPAT_CHECK=1 to silence,
# or returns quietly when profile_lib or the profiles folder is unavailable.
# Echoes a final "no known blockers" line only in verbose mode ($2 == "verbose").
compat_preflight() {
  [[ "${COSMOS_SKIP_COMPAT_CHECK}" == "1" ]] && return 0
  local appid="${1:-}" verbose="${2:-}"
  [[ -n "${appid}" ]] || return 0
  command -v profile_find_by_appid >/dev/null 2>&1 || return 0
  [[ -d "${COSMOS_PROFILES_DIR}" ]] || return 0

  local file status name notes msg
  file="$(profile_find_by_appid "${COSMOS_PROFILES_DIR}" "${appid}" 2>/dev/null)" || {
    [[ "${verbose}" == "verbose" ]] && echo "No curated profile for App ID ${appid} — compatibility unknown."
    return 0
  }
  status="$(profile_get_scalar "${file}" status 2>/dev/null)"
  name="$(profile_get_scalar "${file}" name 2>/dev/null)"
  notes="$(profile_get_notes "${file}" 2>/dev/null)"
  [[ -n "${name}" ]] || name="App ID ${appid}"

  if msg="$(profile_compat_warning "${status}" "${name}" "${notes}")"; then
    log "Compatibility check"
    printf '%s\n' "${msg}"
    printf 'Continuing anyway — set COSMOS_SKIP_COMPAT_CHECK=1 to silence this.\n'
  elif [[ "${verbose}" == "verbose" ]]; then
    echo "${name}: status ${status:-unknown}, no known blockers."
  fi
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

  steam_prepare_launch

  local -a steam_cmd=()
  steam_build_steam_launch_cmd steam_cmd "${steam_exe}"
  if [[ -n "${STEAM_LAUNCH_ARGS:-}" ]]; then
    echo "Steam launch flags: ${STEAM_LAUNCH_ARGS}"
  fi
  if [[ -n "${COSMOS_STEAM_WINEDLLOVERRIDES:-}" ]]; then
    echo "Steam DLL overrides: ${WINEDLLOVERRIDES:-}"
  fi
  if [[ -n "${WINE_VIRTUAL_DESKTOP:-}" && "${WINE_VIRTUAL_DESKTOP}" != "0" ]]; then
    echo "Virtual desktop: ${WINE_VIRTUAL_DESKTOP_NAME:-cosmos-steam} @ ${WINE_VIRTUAL_DESKTOP}"
  fi
  if declare -F cosmos_sync_mode_label >/dev/null 2>&1; then
    echo "Thread sync: $(cosmos_sync_mode_label)"
  elif [[ "${WINEESYNC:-}" == "1" ]]; then
    echo "Thread sync: esync enabled (WINEESYNC=1)"
  elif [[ "${WINEMSYNC:-}" == "1" ]]; then
    echo "Thread sync: msync enabled (WINEMSYNC=1)"
  fi
  if [[ -n "${STEAM_GAME_ID:-}" ]]; then
    compat_preflight "${STEAM_GAME_ID}"
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

  # Steam opts out of detached crash-on-startup retries: its bootstrapper can
  # exit the first process while Steam keeps running, which a retry would
  # misread as a crash. Foreground retries still apply.
  run_launch_cmd "Steam" 0 "${steam_cmd[@]}"
}

find_legendary_bin() {
  if command -v legendary >/dev/null 2>&1; then
    command -v legendary
    return 0
  fi
  local candidate
  for candidate in \
    "${HOME}/.local/bin/legendary" \
    "/opt/homebrew/bin/legendary" \
    "/usr/local/bin/legendary"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  return 1
}

launch_epic_via_legendary() {
  local leg="$1"
  log "Launching Epic game via Legendary: ${LEGENDARY_APP_NAME}"
  local -a leg_cmd=("${leg}" launch "${LEGENDARY_APP_NAME}" \
    --wine "${WINE_BIN}" --wine-prefix "${WINEPREFIX}")
  [[ "${LEGENDARY_OFFLINE:-0}" == "1" ]] && leg_cmd+=(--offline)
  if [[ -n "${GAME_ARGS:-}" ]]; then
    local -a extra_args=()
    read -r -a extra_args <<< "${GAME_ARGS}"
    (( ${#extra_args[@]} > 0 )) && leg_cmd+=("${extra_args[@]}")
  fi

  run_launch_cmd "Epic game (${LEGENDARY_APP_NAME})" 1 "${leg_cmd[@]}"
}

resolve_game_exe_path() {
  local path="${GAME_EXE_PATH:-}"
  [[ -n "${path}" ]] || return 1
  if [[ "${path}" == drive_c/* ]]; then
    printf '%s' "${WINEPREFIX}/${path}"
    return 0
  fi
  if [[ -f "${path}" ]]; then
    printf '%s' "${path}"
    return 0
  fi
  if [[ -f "${WINEPREFIX}/${path}" ]]; then
    printf '%s' "${WINEPREFIX}/${path}"
    return 0
  fi
  return 1
}

battlenet_agent_running() {
  pgrep -if 'Battle\.net|Battle.net Agent|Agent\.exe' >/dev/null 2>&1
}

resolve_prefix_path() {
  local path="$1"
  [[ -n "${path}" ]] || return 1
  if [[ "${path}" == drive_c/* ]]; then
    printf '%s' "${WINEPREFIX}/${path}"
    return 0
  fi
  if [[ -f "${path}" ]]; then
    printf '%s' "${path}"
    return 0
  fi
  if [[ -f "${WINEPREFIX}/${path}" ]]; then
    printf '%s' "${WINEPREFIX}/${path}"
    return 0
  fi
  return 1
}

ensure_battlenet_agent() {
  local launcher_rel="${BATTLENET_LAUNCHER_EXE:-}"
  [[ -n "${launcher_rel}" ]] || return 0
  battlenet_agent_running && return 0

  local launcher_host
  launcher_host="$(resolve_prefix_path "${launcher_rel}" 2>/dev/null || true)"
  [[ -f "${launcher_host}" ]] || {
    log "BATTLENET_LAUNCHER_EXE not found (${launcher_rel}); launching game directly"
    return 0
  }

  log "Starting Battle.net agent: ${launcher_host}"
  nohup "${WINE_BIN}" "${launcher_host}" >/dev/null 2>&1 &
  local waited=0
  while (( waited < 30 )); do
    battlenet_agent_running && return 0
    sleep 1
    waited=$((waited + 1))
  done
  log "Battle.net agent may still be starting; continuing with game launch"
}

launch_standalone_game() {
  if [[ -n "${LEGENDARY_APP_NAME:-}" ]]; then
    local leg=""
    leg="$(find_legendary_bin || true)"
    if [[ -n "${leg}" ]]; then
      launch_epic_via_legendary "${leg}"
      return
    fi
    log "LEGENDARY_APP_NAME is set but legendary was not found; falling back to GAME_EXE_PATH"
  fi

  ensure_battlenet_agent

  local game_exe
  game_exe="$(resolve_game_exe_path)" || die "GAME_EXE_PATH not found: ${GAME_EXE_PATH:-}"
  [[ -f "${game_exe}" ]] || die "Standalone executable not found: ${game_exe}"

  log "Launching standalone game: ${game_exe}"
  local -a game_cmd=("${WINE_BIN}" "${game_exe}")
  if [[ -n "${GAME_ARGS:-}" ]]; then
    local -a extra_args=()
    read -r -a extra_args <<< "${GAME_ARGS}"
    (( ${#extra_args[@]} > 0 )) && game_cmd+=("${extra_args[@]}")
  fi

  run_launch_cmd "Game" 1 "${game_cmd[@]}"
}

run_installer() {
  [[ -n "${INSTALLER_PATH}" ]] || die "--run-installer requires a file path."
  [[ -f "${INSTALLER_PATH}" ]] || die "Installer not found: ${INSTALLER_PATH}"
  log "Running installer: ${INSTALLER_PATH}"
  local abs
  abs="$(cd "$(dirname "${INSTALLER_PATH}")" && pwd)/$(basename "${INSTALLER_PATH}")"
  if printf '%s' "${abs}" | grep -qi '\.msi$'; then
    "${WINE_BIN}" msiexec /i "${abs}"
  else
    "${WINE_BIN}" "${abs}"
  fi
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

  run_launch_cmd "Profile" 1 "${profile_cmd[@]}"
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
  if [[ "${COSMOS_SKIP_STEAM}" != "1" ]]; then
    steam_prepare_prefix
    ensure_steam_installed
    steam_ensure_webhelper_wrapper || true
  fi

  log "Graphics backend: ${RESOLVED_BACKEND} (requested: ${COSMOS_BACKEND})"
  case "${RESOLVED_BACKEND}" in
    dxmt)
      ensure_dxmt_installed
      enable_dxmt_env
      steam_stage_dxmt_prefix_dlls || true
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
    echo "Steam installer did not finish — re-run ./run.command --install-steam (or --setup-steam for a full bottle prep)."
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
  local rosetta_ok=0 rosetta_label=""
  if declare -F rosetta_status_code >/dev/null 2>&1; then
    case "$(rosetta_status_code)" in
      available|not_required) rosetta_ok=1 ;;
    esac
    rosetta_label="$(rosetta_status_label)"
  else
    rosetta_ok=1
    rosetta_label="Rosetta check unavailable"
  fi
  local rosetta_detail="Run: ./run.command --install-rosetta"
  if [[ "${rosetta_ok}" -eq 1 ]]; then
    if declare -F rosetta_needs_translation >/dev/null 2>&1 && rosetta_needs_translation; then
      rosetta_detail="x86_64 Wine runs via Rosetta on Apple Silicon"
    else
      rosetta_detail="Native x86_64 host — Wine runs without Rosetta"
    fi
  fi
  status_line "${rosetta_ok}" "${rosetta_label}" "${rosetta_detail}"
  status_line "${wine_ok}" "Wine ${WINE_VERSION} downloaded" \
    "$([[ "${wine_ok}" -eq 1 ]] && echo "${WINE_APP}" || echo "Downloads on first --setup-steam or --steam")"
  status_line "${prefix_ok}" "Wine prefix created" \
    "$([[ "${prefix_ok}" -eq 1 ]] && echo "${WINEPREFIX}" || echo "Created during --setup-steam")"
  status_line "${steam_ok}" "Steam installed in prefix" \
    "$([[ "${steam_ok}" -eq 1 ]] && echo "${steam_exe}" || echo "$([[ "${COSMOS_STEAM_SILENT}" == "1" ]] && echo "Run ./run.command --install-steam (unattended, wizard fallback)" || echo "Run ./run.command --install-steam and complete the wizard")")"
  status_line "$([[ "${profiles_count}" -gt 0 ]] && echo 1 || echo 0)" "Game launchers built" \
    "$([[ "${profiles_count}" -gt 0 ]] && echo "${profiles_count} profile(s) in ${PROFILE_DIRECTORY}" || echo "Run ./detect_steam_games.command --install after installing a game")"

  echo ""
  local sync_label="off"
  if declare -F cosmos_sync_mode_label >/dev/null 2>&1; then
    sync_label="$(cosmos_sync_mode_label)"
  fi
  echo "  Backend: ${COSMOS_BACKEND}   Windows: ${WINDOWS_VERSION:-Wine default}   Retina: $([[ "${WINE_RETINA_MODE}" == "1" ]] && echo on || echo off)   Sync: ${sync_label}"
  echo "  Install: $([[ "${COSMOS_STEAM_SILENT}" == "1" ]] && echo silent || echo wizard)   GPTK: ${GPTK_PATH:-not set}   DXMT channel: ${COSMOS_DXMT_CHANNEL:-stable}"
  if [[ -n "${RUNTIME_MANIFEST_VERSION:-}" ]]; then
    echo "  Runtime manifest: ${RUNTIME_MANIFEST_VERSION} (DXMT ${DXMT_VERSION}, Wine ${WINE_VERSION})"
    [[ -n "${COSMOS_RUNTIME_DIR:-}" ]] && echo "  Runtime cache: ${COSMOS_RUNTIME_DIR}"
  fi
  echo ""
  if [[ "${rosetta_ok}" -eq 0 ]]; then
    echo "  Next step: ./run.command --install-rosetta"
  elif [[ "${wine_ok}" -eq 0 || "${prefix_ok}" -eq 0 ]]; then
    echo "  Next step: ./run.command --setup-steam"
  elif [[ "${steam_ok}" -eq 0 ]]; then
    echo "  Next step: ./run.command --install-steam"
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
  # Read-only compatibility lookup: works on any platform (no Wine/macOS needed),
  # so the dashboard and CI can query a game's status without a full launch.
  if [[ "${COSMOS_LAUNCH_MODE}" == "compat-check" ]]; then
    compat_preflight "${COMPAT_CHECK_APPID}" verbose
    return
  fi
  if [[ "${COSMOS_LAUNCH_MODE}" == "validate-gptk" ]]; then
    if declare -F gptk_validate_path >/dev/null 2>&1; then
      gptk_validate_path "${GPTK_VALIDATE_PATH}"
      return $?
    fi
    die "GPTK validation is unavailable (gptk_lib.sh not loaded)."
  fi
  if [[ "${COSMOS_LAUNCH_MODE}" == "runtime-status" ]]; then
    wine_runtime_status_lines
    return
  fi
  if [[ "${COSMOS_LAUNCH_MODE}" == "check-update" ]]; then
    "${SCRIPT_DIR}/scripts/check_updates.sh"
    return $?
  fi
  if [[ "${COSMOS_LAUNCH_MODE}" == "install-update" ]]; then
    "${SCRIPT_DIR}/scripts/check_updates.sh" --install
    return $?
  fi
  require_supported_macos
  [[ -n "${COSMOS_BOTTLE}" ]] && log "Bottle: ${COSMOS_BOTTLE} (prefix: ${WINEPREFIX})"
  case "${COSMOS_LAUNCH_MODE}" in
    profiles) open_profiles_folder; return ;;
    logs) open_logs; return ;;
    status) show_status; return ;;
    runtime-status) wine_runtime_status_lines; return ;;
    install-rosetta)
      if declare -F rosetta_needs_translation >/dev/null 2>&1 && ! rosetta_needs_translation; then
        echo "Rosetta 2 is not required on Intel Macs."
        return 0
      fi
      log "Installing Rosetta 2"
      rosetta_ensure || die "Rosetta installation failed"
      echo "Rosetta 2 is ready."
      return ;;
    reset-bottle) reset_bottle; return ;;
    setup-steam)
      log "Preparing Steam bottle (no launch)"
      prepare_steam_bottle
      finish_steam_setup
      return ;;
    install-steam)
      log "Installing Steam in existing prefix (no launch)"
      install_steam_only
      finish_steam_setup
      return ;;
  esac
  prepare_steam_bottle
  case "${COSMOS_LAUNCH_MODE}" in
    profile) launch_profile ;;
    run-installer) run_installer ;;
    *)
      if [[ -n "${GAME_EXE_PATH:-}" ]]; then
        launch_standalone_game
      else
        launch_steam
      fi
      ;;
  esac
}

# Run main unless this file is being sourced (e.g. by the test harness), which
# lets tests exercise individual functions like run_launch_cmd in isolation.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi