#!/usr/bin/env bash
set -euo pipefail

# Builds the Cosmos desktop app shell (roadmap milestone 0.1).
#
# Compiles the SwiftUI sources via SwiftPM, then assembles a double-clickable
# Cosmos.app bundle with the helper scripts (run.command, install_cosmos.command,
# uninstall.command) copied into Resources so the app is self-contained.
#
# Usage:
#   scripts/build_cosmos_app.command          # build into ./build/Cosmos.app
#   INSTALL=1 scripts/build_cosmos_app.command # also copy into /Applications

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="Cosmos"
BUNDLE_ID="com.cosmos.app"
APP_VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo "0.7.0")"
MIN_MACOS="13.0"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/build}"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"
ICON_SRC="${REPO_ROOT}/app/cosmos/AppIcon.icns"
SCRIPTS_TO_BUNDLE=(
  run.command setup.command install_cosmos.command uninstall.command
  detect_steam_games.command bottle.command
  repair.command profile.command cosmosdb.command import_game.command
  scripts/install_steamwebhelper_wrapper.command
)

log() { printf "\n==> %s\n" "$1"; }
die() { printf "Error: %s\n" "$1" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "Building the Cosmos app requires macOS."
command -v swift >/dev/null 2>&1 || die "swift not found. Install Xcode or the Command Line Tools."

log "Compiling ${APP_NAME} (swift build -c release)"
(cd "${REPO_ROOT}" && swift build -c release)

local_bin_dir="$(cd "${REPO_ROOT}" && swift build -c release --show-bin-path)"
built_binary="${local_bin_dir}/${APP_NAME}"
[[ -x "${built_binary}" ]] || die "Build did not produce ${built_binary}"

log "Assembling ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

cp "${built_binary}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Allen West. Licensed under LGPL-3.0-or-later.</string>
</dict>
</plist>
EOF

printf 'APPL????' > "${APP_BUNDLE}/Contents/PkgInfo"

if [[ -f "${ICON_SRC}" ]]; then
  cp "${ICON_SRC}" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
else
  echo "Warning: icon not found at ${ICON_SRC}; building without one."
fi

mkdir -p "${APP_BUNDLE}/Contents/Resources/docs"
if [[ -f "${REPO_ROOT}/docs/STEAM_SETUP.md" ]]; then
  cp "${REPO_ROOT}/docs/STEAM_SETUP.md" "${APP_BUNDLE}/Contents/Resources/docs/STEAM_SETUP.md"
fi

for script in "${SCRIPTS_TO_BUNDLE[@]}"; do
  src="${REPO_ROOT}/${script}"
  [[ -f "${src}" ]] || die "Missing helper script: ${src}"
  dest="${APP_BUNDLE}/Contents/Resources/${script}"
  mkdir -p "$(dirname "${dest}")"
  cp "${src}" "${dest}"
  chmod +x "${dest}"
done

# The icon converter lives under scripts/; flatten it into Resources so the
# bundled detect_steam_games.command can find it (see its ICON_TOOL resolution).
icon_tool_src="${REPO_ROOT}/scripts/make_app_icon.command"
if [[ -f "${icon_tool_src}" ]]; then
  cp "${icon_tool_src}" "${APP_BUNDLE}/Contents/Resources/make_app_icon.command"
  chmod +x "${APP_BUNDLE}/Contents/Resources/make_app_icon.command"
fi

verify_src="${REPO_ROOT}/scripts/verify_steam_detection.command"
if [[ -f "${verify_src}" ]]; then
  mkdir -p "${APP_BUNDLE}/Contents/Resources/scripts"
  cp "${verify_src}" "${APP_BUNDLE}/Contents/Resources/scripts/verify_steam_detection.command"
  chmod +x "${APP_BUNDLE}/Contents/Resources/scripts/verify_steam_detection.command"
fi
for helper in check_updates.sh install_update.sh terminal_wrap.sh; do
  src="${REPO_ROOT}/scripts/${helper}"
  [[ -f "${src}" ]] || die "Missing helper script: ${src}"
  mkdir -p "${APP_BUNDLE}/Contents/Resources/scripts"
  cp "${src}" "${APP_BUNDLE}/Contents/Resources/scripts/${helper}"
  chmod +x "${APP_BUNDLE}/Contents/Resources/scripts/${helper}"
done
cp "${REPO_ROOT}/VERSION" "${APP_BUNDLE}/Contents/Resources/VERSION"
if [[ -d "${REPO_ROOT}/scripts/lib" ]]; then
  mkdir -p "${APP_BUNDLE}/Contents/Resources/scripts/lib"
  cp -R "${REPO_ROOT}/scripts/lib/." "${APP_BUNDLE}/Contents/Resources/scripts/lib/"
fi
if [[ -d "${REPO_ROOT}/third_party/steam-on-m1-wine" ]]; then
  mkdir -p "${APP_BUNDLE}/Contents/Resources/third_party"
  cp -R "${REPO_ROOT}/third_party/steam-on-m1-wine" \
    "${APP_BUNDLE}/Contents/Resources/third_party/steam-on-m1-wine"
fi
if [[ -f "${REPO_ROOT}/scripts/repair_fixes.sh" ]]; then
  mkdir -p "${APP_BUNDLE}/Contents/Resources/scripts"
  cp "${REPO_ROOT}/scripts/repair_fixes.sh" "${APP_BUNDLE}/Contents/Resources/scripts/repair_fixes.sh"
fi
if [[ -f "${REPO_ROOT}/scripts/repair_diagnose.sh" ]]; then
  mkdir -p "${APP_BUNDLE}/Contents/Resources/scripts"
  cp "${REPO_ROOT}/scripts/repair_diagnose.sh" "${APP_BUNDLE}/Contents/Resources/scripts/repair_diagnose.sh"
fi
if [[ -d "${REPO_ROOT}/recipes" ]]; then
  cp -R "${REPO_ROOT}/recipes" "${APP_BUNDLE}/Contents/Resources/recipes"
fi
if [[ -d "${REPO_ROOT}/profiles" ]]; then
  cp -R "${REPO_ROOT}/profiles" "${APP_BUNDLE}/Contents/Resources/profiles"
fi
if [[ -d "${REPO_ROOT}/runtime" ]]; then
  cp -R "${REPO_ROOT}/runtime" "${APP_BUNDLE}/Contents/Resources/runtime"
fi
OFFLINE_TAR="${REPO_ROOT}/build/offline-runtime/cosmos-runtime-offline.tar.xz"
if [[ -f "${OFFLINE_TAR}" ]]; then
  mkdir -p "${APP_BUNDLE}/Contents/Resources/runtime"
  cp "${OFFLINE_TAR}" "${APP_BUNDLE}/Contents/Resources/runtime/cosmos-runtime-offline.tar.xz"
  log "Bundled offline runtime tarball into app Resources"
fi
if [[ -d "${REPO_ROOT}/cosmos-db" ]]; then
  cp -R "${REPO_ROOT}/cosmos-db" "${APP_BUNDLE}/Contents/Resources/cosmos-db"
fi
if [[ -d "${REPO_ROOT}/docs" ]]; then
  mkdir -p "${APP_BUNDLE}/Contents/Resources/docs"
  [[ -f "${REPO_ROOT}/docs/LICENSING.md" ]] \
    && cp "${REPO_ROOT}/docs/LICENSING.md" "${APP_BUNDLE}/Contents/Resources/docs/LICENSING.md"
  [[ -f "${REPO_ROOT}/docs/LGPL_IMPACT.md" ]] \
    && cp "${REPO_ROOT}/docs/LGPL_IMPACT.md" "${APP_BUNDLE}/Contents/Resources/docs/LGPL_IMPACT.md"
fi
[[ -f "${REPO_ROOT}/LICENSE" ]] \
  && cp "${REPO_ROOT}/LICENSE" "${APP_BUNDLE}/Contents/Resources/LICENSE"

# Bundle the launcher template (app/cosmos: CosmosLauncher + AppIcon.icns) so
# install_cosmos.command can build game .app bundles from the installed app,
# without needing the repository checkout.
log "Bundling launcher template (app/cosmos)"
mkdir -p "${APP_BUNDLE}/Contents/Resources/app"
cp -R "${REPO_ROOT}/app/cosmos" "${APP_BUNDLE}/Contents/Resources/app/cosmos"
chmod +x "${APP_BUNDLE}/Contents/Resources/app/cosmos/CosmosLauncher"

# Bundle curated configs so the installed app ships with known-good presets. They
# are seeded into ~/Library/Application Support/Cosmos/cosmos_configs on first use
# (the bundle's Resources are read-only); generated configs/icons never live in
# the bundle, so strip any that exist in the working tree.
log "Bundling curated configs (cosmos_configs)"
cp -R "${REPO_ROOT}/cosmos_configs" "${APP_BUNDLE}/Contents/Resources/cosmos_configs"
rm -f "${APP_BUNDLE}/Contents/Resources/cosmos_configs/steam-"*.conf
rm -rf "${APP_BUNDLE}/Contents/Resources/cosmos_configs/icons"
rm -f "${APP_BUNDLE}/Contents/Resources/cosmos_configs/overrides/"*.env

# Ad-hoc sign the bundle so it launches without Gatekeeper complaints, especially
# on Apple Silicon. This is not a Developer ID signature (no notarization); for
# distribution, re-sign with a real identity.
if command -v codesign >/dev/null 2>&1; then
  log "Ad-hoc signing the bundle"
  codesign --force --deep --sign - "${APP_BUNDLE}" || echo "Warning: ad-hoc codesign failed; the app may be blocked by Gatekeeper."
else
  echo "Warning: codesign not found; skipping ad-hoc signature."
fi

log "Built ${APP_BUNDLE}"

if [[ "${INSTALL:-0}" == "1" ]]; then
  log "Installing to /Applications/${APP_NAME}.app (may prompt for your password)"
  sudo rm -rf "/Applications/${APP_NAME}.app"
  sudo cp -R "${APP_BUNDLE}" "/Applications/"
  echo "Installed /Applications/${APP_NAME}.app"
else
  echo "Run INSTALL=1 ${BASH_SOURCE[0]##*/} to copy it into /Applications."
fi
