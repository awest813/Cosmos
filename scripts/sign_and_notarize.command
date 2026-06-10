#!/usr/bin/env bash
# Developer ID sign + notarize Cosmos.app and Cosmos.dmg for Gatekeeper-clean releases.
#
# Required environment (GitHub Actions secrets or local export):
#   DEVELOPER_ID_APPLICATION   e.g. "Developer ID Application: Your Name (TEAMID)"
#   APPLE_ID                   Apple ID email for notarytool
#   APPLE_TEAM_ID              Team ID
#   APPLE_APP_SPECIFIC_PASSWORD  App-specific password (or NOTARY_API_KEY_* for API key auth)
#
# Optional:
#   SKIP_NOTARIZE=1            Sign only (local testing with a real cert)
#   ENTITLEMENTS=path          Defaults to app/cosmos.entitlements
#
# Usage:
#   DEVELOPER_ID_APPLICATION="..." APPLE_ID="..." ... scripts/sign_and_notarize.command build/Cosmos.app build/Cosmos.dmg

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

APP_BUNDLE="${1:-${REPO_ROOT}/build/Cosmos.app}"
DMG_PATH="${2:-${REPO_ROOT}/build/Cosmos.dmg}"
ENTITLEMENTS="${ENTITLEMENTS:-${REPO_ROOT}/app/cosmos.entitlements}"

log() { printf "\n==> %s\n" "$1"; }
die() { printf "Error: %s\n" "$1" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "Signing and notarization require macOS."
[[ -f "${ENTITLEMENTS}" ]] || die "Entitlements not found: ${ENTITLEMENTS}"
[[ -n "${DEVELOPER_ID_APPLICATION:-}" ]] || die "Set DEVELOPER_ID_APPLICATION to your Developer ID Application identity."

command -v codesign >/dev/null 2>&1 || die "codesign not found."
command -v xcrun >/dev/null 2>&1 || die "xcrun not found."

sign_app_bundle() {
  [[ -d "${APP_BUNDLE}" ]] || die "App bundle not found: ${APP_BUNDLE}"
  log "Signing ${APP_BUNDLE}"
  while IFS= read -r -d '' bin; do
    codesign --force --options runtime --timestamp \
      --entitlements "${ENTITLEMENTS}" \
      --sign "${DEVELOPER_ID_APPLICATION}" "${bin}"
  done < <(find "${APP_BUNDLE}" -type f \( -perm -111 -o -name '*.command' -o -name '*.sh' \) -print0)

  codesign --force --deep --options runtime --timestamp \
    --entitlements "${ENTITLEMENTS}" \
    --sign "${DEVELOPER_ID_APPLICATION}" "${APP_BUNDLE}"

  log "Verifying app signature"
  codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
}

sign_dmg() {
  [[ -f "${DMG_PATH}" ]] || die "DMG not found: ${DMG_PATH}"
  log "Signing ${DMG_PATH}"
  codesign --force --sign "${DEVELOPER_ID_APPLICATION}" "${DMG_PATH}"
}

if [[ "${SKIP_APP:-0}" != "1" ]]; then
  sign_app_bundle
fi

if [[ "${SKIP_DMG:-0}" == "1" ]]; then
  log "SKIP_DMG=1 — app signed; DMG step skipped"
  exit 0
fi

sign_dmg

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
  log "SKIP_NOTARIZE=1 — skipping notarization"
  exit 0
fi

[[ -n "${APPLE_ID:-}" ]] || die "Set APPLE_ID for notarization."
[[ -n "${APPLE_TEAM_ID:-}" ]] || die "Set APPLE_TEAM_ID for notarization."

notary_auth=()
if [[ -n "${NOTARY_API_KEY_PATH:-}" && -n "${NOTARY_API_KEY_ID:-}" ]]; then
  notary_auth=(--key "${NOTARY_API_KEY_PATH}" --key-id "${NOTARY_API_KEY_ID}" --issuer "${NOTARY_API_ISSUER:-}")
elif [[ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  notary_auth=(--apple-id "${APPLE_ID}" --password "${APPLE_APP_SPECIFIC_PASSWORD}" --team-id "${APPLE_TEAM_ID}")
else
  die "Set APPLE_APP_SPECIFIC_PASSWORD or NOTARY_API_KEY_PATH + NOTARY_API_KEY_ID for notarization."
fi

log "Submitting ${DMG_PATH} to Apple notary service"
submission="$(xcrun notarytool submit "${DMG_PATH}" "${notary_auth[@]}" --wait)"
printf '%s\n' "${submission}"

log "Stapling notarization ticket to ${DMG_PATH}"
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"

log "Notarized ${DMG_PATH} is ready for distribution"
