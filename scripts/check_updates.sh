#!/usr/bin/env bash
# Compare local app + runtime versions to GitHub Releases.
# Use scripts/install_update.sh to download and install Cosmos.dmg when an update exists.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/release_lib.sh
source "${ROOT}/scripts/lib/release_lib.sh"

VERSION_FILE="${ROOT}/VERSION"
RUNTIME_MANIFEST="${ROOT}/runtime/cosmos-runtime.json"
REPO="$(release_lib_repo)"

# When running from Cosmos.app/Contents/Resources, Info.plist holds the bundle version.
bundle_info_plist() {
  local resources="${ROOT}"
  local plist="${resources}/../Info.plist"
  if [[ -f "${plist}" ]]; then
    printf '%s' "${plist}"
    return 0
  fi
  if [[ "${resources}" == *.app/Contents/Resources ]]; then
    plist="${resources%/Resources}/Info.plist"
    [[ -f "${plist}" ]] && printf '%s' "${plist}" && return 0
  fi
  return 1
}

local_app() {
  if [[ -f "${VERSION_FILE}" ]]; then
    tr -d '[:space:]' < "${VERSION_FILE}"
    return
  fi
  local plist
  if plist="$(bundle_info_plist)"; then
    if command -v plutil >/dev/null 2>&1; then
      plutil -extract CFBundleShortVersionString raw -o - "${plist}" 2>/dev/null && return
    fi
    if command -v defaults >/dev/null 2>&1; then
      defaults read "${plist%.plist}" CFBundleShortVersionString 2>/dev/null && return
    fi
  fi
  printf 'unknown'
}

local_runtime() {
  if [[ -f "${RUNTIME_MANIFEST}" ]] && command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "${RUNTIME_MANIFEST}" 2>/dev/null \
      || printf 'unknown'
    return
  fi
  printf 'unknown'
}

fetch_latest_release_tag() {
  release_lib_latest_tag
}

usage() {
  cat <<'EOF'
Check whether a newer Cosmos release is published on GitHub.

Usage: scripts/check_updates.sh [--json] [--install]

  --json     Print machine-readable JSON (stdout only)
  --install  Download and install Cosmos.dmg when a newer release exists

Set COSMOS_RELEASE_FIXTURE to a GitHub /releases/latest JSON file for offline tests.

Exit 0 when up to date or release lookup unavailable; exit 2 when a newer release exists.
EOF
}

json=0
install=0
while (($#)); do
  case "$1" in
    --json) json=1; shift ;;
    --install) install=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

app="$(local_app)"
runtime="$(local_runtime)"
latest="$(fetch_latest_release_tag || true)"
status="unknown"

if [[ -z "${latest}" ]]; then
  status="unavailable"
elif [[ "${app}" == "${latest}" ]]; then
  status="current"
elif [[ "${app}" == "unknown" ]]; then
  status="unknown"
else
  status="update_available"
fi

if (( install )); then
  if [[ "${status}" != "update_available" ]]; then
    echo "No newer release to install (status=${status}, app=${app}, latest=${latest:-n/a})." >&2
    exit 0
  fi
  exec "${ROOT}/scripts/install_update.sh"
fi

if (( json )); then
  python3 - "${app}" "${runtime}" "${latest}" "${status}" <<'PY'
import json, sys
app, runtime, latest, status = sys.argv[1:5]
print(json.dumps({
    "app_version": app,
    "runtime_version": runtime,
    "latest_release": latest or None,
    "status": status,
}, indent=2))
PY
else
  printf 'app_version=%s\n' "${app}"
  printf 'runtime_version=%s\n' "${runtime}"
  printf 'latest_release=%s\n' "${latest:-}"
  printf 'status=%s\n' "${status}"
  case "${status}" in
    update_available)
      printf '\nA newer Cosmos release (%s) may be available. You are on %s.\n' "${latest}" "${app}"
      printf 'Install: ./run.command --install-update\n'
      printf 'See: https://github.com/%s/releases\n' "${REPO}"
      ;;
    unavailable)
      printf '\nCould not reach GitHub Releases (offline or API limit). Local: app %s, runtime %s.\n' "${app}" "${runtime}"
      ;;
    current)
      printf '\nCosmos app %s matches the latest published release.\n' "${app}"
      ;;
    *)
      printf '\nLocal app %s · runtime %s\n' "${app}" "${runtime}"
      ;;
  esac
fi

[[ "${status}" == "update_available" ]] && exit 2
exit 0
