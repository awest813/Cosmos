#!/usr/bin/env bash
set -euo pipefail

# Build and install the MIT steamwebhelper wrapper (notpop/steam-on-m1-wine)
# into the Steam CEF directories inside the active Wine prefix.
#
# Requires: Steam installed, mingw-w64 (brew install mingw-w64)

_HELPER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${_HELPER_DIR}" == *.app/Contents/Resources/scripts ]]; then
  SCRIPT_DIR="${SCRIPT_DIR:-${_HELPER_DIR%/scripts}}"
else
  SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "${_HELPER_DIR}/.." && pwd)}"
fi
WINEPREFIX="${WINEPREFIX:-$HOME/.wine-steam-11}"
WINE_VERSION="${WINE_VERSION:-11.8}"
WINE_ROOT="${WINE_ROOT:-$HOME/wine-${WINE_VERSION}}"
WINE_BIN="${WINE_BIN:-${WINE_ROOT}/Wine Devel.app/Contents/Resources/wine/bin/wine}"

# shellcheck source=scripts/lib/steam_lib.sh
source "${SCRIPT_DIR}/scripts/lib/steam_lib.sh"

log() { printf "\n==> %s\n" "$1"; }
die() { printf "Error: %s\n" "$1" >&2; exit 1; }

[[ -x "${WINE_BIN}" ]] || die "Wine not found at ${WINE_BIN}. Run ./run.command --setup-steam first."
[[ -f "${WINEPREFIX}/system.reg" ]] || die "Prefix not initialized at ${WINEPREFIX}."

log "Installing steamwebhelper wrapper into ${WINEPREFIX}"
steam_install_webhelper_wrapper || die "Wrapper installation failed or was skipped."
