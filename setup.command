#!/usr/bin/env bash
set -euo pipefail

# Guided first-time setup for new Cosmos users (macOS Apple Silicon).
# Runs the same steps as the dashboard checklist in order, in Terminal.
#
# Usage:
#   ./setup.command              # full guided setup
#   ./setup.command --skip-install   # skip install_cosmos (launchers already present)

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COSMOS_APPS="/Applications/Cosmos Apps"
SKIP_INSTALL=0

log() { printf "\n==> %s\n" "$1"; }
die() { printf "Error: %s\n" "$1" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: setup.command [OPTIONS]

Guided setup for new users: install Cosmos launchers, prepare the Steam
Wine bottle, then remind you to sign in to Steam and build game launchers.

Options:
  --skip-install   Skip install_cosmos.command (use when Cosmos Apps is already installed).
  -h, --help       Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
    --skip-install) SKIP_INSTALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

[[ "$(uname -s)" == "Darwin" ]] || die "Cosmos setup requires macOS."
[[ "$(uname -m)" == "arm64" ]] || die "Cosmos setup is intended for Apple Silicon (arm64)."

cat <<'EOF'

  Cosmos — guided setup
  =====================
  This walks through first-time setup in Terminal. The dashboard can run
  the same steps one at a time if you prefer.

  What to expect:
    • Step 1 may ask for your password (installs /Applications/Cosmos Apps).
    • Step 2 downloads Wine and DXMT, then installs Steam (unattended by default).
    • After setup, open Cosmos.app, sign in to Steam, install a Windows game,
      then use "Build Launchers" in the app.

EOF

if [[ "${SKIP_INSTALL}" -eq 0 ]]; then
  if [[ -d "${COSMOS_APPS}" ]]; then
    log "Step 1/2: Cosmos Apps already installed at ${COSMOS_APPS} — skipping install."
  else
    log "Step 1/2: Installing Cosmos Apps (may ask for sudo)"
    "${SCRIPT_DIR}/install_cosmos.command"
  fi
else
  log "Step 1/2: Skipped (--skip-install)"
fi

log "Step 2/2: Preparing Steam bottle (Wine prefix + Steam installer)"
"${SCRIPT_DIR}/run.command" --setup-steam

cat <<'EOF'

  Setup scripts finished
  ======================
  Next in the Cosmos app (or manually):

    1. Launch Steam — sign in and install at least one Windows game.
    2. Build Launchers — creates Dock-friendly apps in Cosmos Apps.

  Commands if you prefer Terminal:
    ./run.command --status              # check progress and the next step
    ./run.command --steam
    ./detect_steam_games.command --install

  Troubleshooting: docs/STEAM_SETUP.md

EOF
