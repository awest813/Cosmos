#!/usr/bin/env bash
# Shared GitHub Releases helpers for check_updates.sh and install_update.sh.
# Set COSMOS_RELEASE_FIXTURE to a JSON file path for hermetic tests (no network).

release_lib_repo() {
  printf '%s' "${COSMOS_GITHUB_REPO:-awest813/Cosmos}"
}

release_lib_fetch_json() {
  if [[ -n "${COSMOS_RELEASE_FIXTURE:-}" ]]; then
    [[ -f "${COSMOS_RELEASE_FIXTURE}" ]] || return 1
    cat "${COSMOS_RELEASE_FIXTURE}"
    return 0
  fi
  if ! command -v curl >/dev/null 2>&1; then
    return 1
  fi
  local repo; repo="$(release_lib_repo)"
  curl -fsSL --max-time 15 --retry 2 --retry-delay 1 \
    -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null
}

release_lib_latest_tag() {
  release_lib_fetch_json \
    | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(1)
print((d.get("tag_name") or "").lstrip("v"))' 2>/dev/null
}

release_lib_asset_url() {
  local asset_name="${1:?asset name required}"
  release_lib_fetch_json \
    | COSMOS_UPDATE_ASSET="${asset_name}" python3 -c 'import json,sys,os
name=os.environ["COSMOS_UPDATE_ASSET"]
try:
    data=json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(1)
for a in data.get("assets",[]):
    if a.get("name")==name and a.get("browser_download_url"):
        print(a["browser_download_url"])
        break
' 2>/dev/null
}

release_lib_default_dmg_asset() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    case "$(uname -m)" in
      arm64) printf 'Cosmos-macos-arm64.dmg'; return ;;
      x86_64) printf 'Cosmos-macos-x86_64.dmg'; return ;;
    esac
  fi
  printf 'Cosmos.dmg'
}

release_lib_asset_url_from_json() {
  local release_json="${1:?release json required}"
  local asset_name="${2:?asset name required}"
  printf '%s' "${release_json}" \
    | COSMOS_UPDATE_ASSET="${asset_name}" python3 -c 'import json,sys,os
name=os.environ["COSMOS_UPDATE_ASSET"]
try:
    data=json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(1)
for a in data.get("assets",[]):
    if a.get("name")==name and a.get("browser_download_url"):
        print(a["browser_download_url"])
        break
' 2>/dev/null
}
