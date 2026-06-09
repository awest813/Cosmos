#!/usr/bin/env bash
set -euo pipefail

# Packages the Cosmos desktop app into a double-clickable disk image
# (Cosmos.dmg) with a drag-to-/Applications layout.
#
# This closes the biggest distribution-friction gap vs. Proton (see
# docs/PROTON_GAP_ANALYSIS.md): instead of "download ZIP, compile from source",
# a user opens the .dmg and drags Cosmos into Applications.
#
# The image is ad-hoc signed (inherited from scripts/build_cosmos_app.command).
# A Developer ID signature + notarization is the follow-up step for a fully
# Gatekeeper-clean download; until then, first launch still uses right-click →
# Open once (documented in the README).
#
# Usage:
#   scripts/build_dmg.command            # build the app, then package build/Cosmos.dmg
#   SKIP_BUILD=1 scripts/build_dmg.command  # package an already-built build/Cosmos.app
#   OUTPUT_DIR=/tmp/out scripts/build_dmg.command  # choose where artifacts land

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="Cosmos"
VOL_NAME="${VOL_NAME:-Cosmos}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/build}"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"
DMG_PATH="${OUTPUT_DIR}/${APP_NAME}.dmg"

log() { printf "\n==> %s\n" "$1"; }
die() { printf "Error: %s\n" "$1" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "Building the DMG requires macOS (uses hdiutil)."
command -v hdiutil >/dev/null 2>&1 || die "hdiutil not found; cannot create a disk image."

# Build the app unless asked to reuse an existing bundle.
if [[ "${SKIP_BUILD:-0}" == "1" ]]; then
  [[ -d "${APP_BUNDLE}" ]] || die "SKIP_BUILD=1 but ${APP_BUNDLE} does not exist. Run scripts/build_cosmos_app.command first."
  log "Reusing existing ${APP_BUNDLE} (SKIP_BUILD=1)"
else
  log "Building ${APP_NAME}.app via scripts/build_cosmos_app.command"
  OUTPUT_DIR="${OUTPUT_DIR}" "${SCRIPT_DIR}/build_cosmos_app.command"
  [[ -d "${APP_BUNDLE}" ]] || die "Build did not produce ${APP_BUNDLE}"
fi

# Stage the app plus an /Applications symlink so the mounted image shows the
# familiar "drag Cosmos into Applications" layout.
staging="$(mktemp -d)"
cleanup() { rm -rf "${staging}"; }
trap cleanup EXIT

log "Staging disk image contents"
cp -R "${APP_BUNDLE}" "${staging}/${APP_NAME}.app"
ln -s /Applications "${staging}/Applications"

log "Creating ${DMG_PATH}"
rm -f "${DMG_PATH}"
mkdir -p "${OUTPUT_DIR}"
hdiutil create \
  -volname "${VOL_NAME}" \
  -srcfolder "${staging}" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "${DMG_PATH}" >/dev/null

# Ad-hoc sign the image itself when an identity-less codesign is available, so
# the download carries the same (unsigned-but-stable) signature as the app.
if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "${DMG_PATH}" 2>/dev/null \
    || echo "Note: ad-hoc signing the .dmg failed; the app inside is still signed."
fi

size="$(du -h "${DMG_PATH}" | cut -f1 | tr -d ' ')"
log "Built ${DMG_PATH} (${size})"
echo "Share this file. Users open it and drag ${APP_NAME} into Applications."
echo "First launch (unsigned build): right-click ${APP_NAME} → Open → confirm Open."
