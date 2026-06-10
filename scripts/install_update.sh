#!/usr/bin/env bash
# Download the latest Cosmos.dmg from GitHub Releases and install Cosmos.app.
# Shell-based updater (no Sparkle dependency); complements check_updates.sh.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/release_lib.sh
source "${ROOT}/scripts/lib/release_lib.sh"

REPO="$(release_lib_repo)"
ASSET_NAME="${COSMOS_UPDATE_ASSET:-Cosmos.dmg}"
TARGET_APP="/Applications/Cosmos.app"

log() { printf '==> %s\n' "$1"; }
die() { printf 'Error: %s\n' "$1" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "Installing updates requires macOS."
command -v curl >/dev/null 2>&1 || die "curl is required to download updates."
command -v hdiutil >/dev/null 2>&1 || die "hdiutil is required to mount the update image."

usage() {
  cat <<'EOF'
Download and install the latest Cosmos release from GitHub.

Usage: scripts/install_update.sh [--dry-run]

Quits a running Cosmos.app when possible, downloads Cosmos.dmg from the latest
GitHub Release, and copies Cosmos.app into /Applications (sudo only if needed).

Set COSMOS_RELEASE_FIXTURE for offline --dry-run tests.
EOF
}

dry_run=0
while (($#)); do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

release_json="$(release_lib_fetch_json 2>/dev/null || true)"
[[ -n "${release_json}" ]] || die "Could not fetch latest release metadata for ${REPO}."

asset_url="$(printf '%s' "${release_json}" | COSMOS_UPDATE_ASSET="${ASSET_NAME}" python3 -c 'import json,sys,os
name=os.environ["COSMOS_UPDATE_ASSET"]
data=json.load(sys.stdin)
for a in data.get("assets",[]):
    if a.get("name")==name and a.get("browser_download_url"):
        print(a["browser_download_url"])
        break
' 2>/dev/null || true)"

[[ -n "${asset_url}" ]] || die "No ${ASSET_NAME} asset found on the latest GitHub Release for ${REPO}."

tag="$(printf '%s' "${release_json}" | python3 -c 'import json,sys; print((json.load(sys.stdin).get("tag_name") or "").lstrip("v"))' 2>/dev/null || true)"
log "Latest release: ${tag:-unknown} (${ASSET_NAME})"

if (( dry_run )); then
  printf 'dry_run=1\nasset=%s\n' "${asset_url}"
  exit 0
fi

if pgrep -xq Cosmos; then
  log "Quitting Cosmos.app before installing the update"
  osascript -e 'tell application "Cosmos" to quit' 2>/dev/null || true
  for _ in $(seq 1 20); do
    pgrep -xq Cosmos || break
    sleep 0.5
  done
fi

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "${tmpdir}"; }
trap cleanup EXIT

dmg_path="${tmpdir}/${ASSET_NAME}"
log "Downloading ${asset_url}"
curl -fL --progress-bar --max-time 600 --retry 2 --retry-delay 2 -o "${dmg_path}" "${asset_url}"

log "Mounting ${ASSET_NAME}"
attach_out="$(hdiutil attach -nobrowse -readonly -plist "${dmg_path}")"
mount_point="$(printf '%s' "${attach_out}" | plutil -extract system-entities xml1 -o - - 2>/dev/null \
  | python3 -c 'import plistlib,sys; ents=plistlib.load(sys.stdin.buffer);
for e in ents:
    if e.get("mount-point"):
        print(e["mount-point"]); break' 2>/dev/null || true)"

if [[ -z "${mount_point}" ]]; then
  mount_point="$(printf '%s\n' "${attach_out}" | awk '/\/Volumes\// {print $NF; exit}')"
fi
[[ -n "${mount_point}" && -d "${mount_point}/Cosmos.app" ]] \
  || die "Could not find Cosmos.app inside the mounted disk image."

src_app="${mount_point}/Cosmos.app"
log "Installing to ${TARGET_APP}"

install_app() {
  rm -rf "${TARGET_APP}"
  cp -R "${src_app}" "${TARGET_APP}"
}

if install_app 2>/dev/null; then
  :
else
  log "Need administrator permission to write ${TARGET_APP}"
  sudo rm -rf "${TARGET_APP}"
  sudo cp -R "${src_app}" "${TARGET_APP}"
fi

hdiutil detach "${mount_point}" -quiet >/dev/null 2>&1 || hdiutil detach "${mount_point}" -force >/dev/null 2>&1 || true

if command -v codesign >/dev/null 2>&1; then
  codesign --verify --deep --strict "${TARGET_APP}" 2>/dev/null \
    && log "Codesign verification passed" \
    || echo "Note: installed app is not Developer ID signed (Gatekeeper may prompt on first launch)."
fi

log "Cosmos ${tag:-update} installed to ${TARGET_APP}"
printf 'Restart Cosmos from Applications to use the new version.\n'
