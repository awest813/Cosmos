#!/usr/bin/env bash
# Phase F (partial): compare local app + runtime versions to GitHub Releases.
# Does not download or install — dashboard and CLI use this for update awareness.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="${ROOT}/VERSION"
RUNTIME_MANIFEST="${ROOT}/runtime/cosmos-runtime.json"
REPO="${COSMOS_GITHUB_REPO:-awest813/Cosmos}"

local_app() {
  if [[ -f "${VERSION_FILE}" ]]; then
    tr -d '[:space:]' < "${VERSION_FILE}"
    return
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
  local api="https://api.github.com/repos/${REPO}/releases/latest"
  if ! command -v curl >/dev/null 2>&1; then
    return 1
  fi
  curl -fsSL --max-time 15 -H 'Accept: application/vnd.github+json' "${api}" 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("tag_name") or "").lstrip("v"))' 2>/dev/null
}

usage() {
  cat <<'EOF'
Check whether a newer Cosmos release is published on GitHub.

Usage: scripts/check_updates.sh [--json]

Prints key=value lines (default) or JSON with --json.
Exit 0 when up to date or release lookup unavailable; exit 2 when a newer release exists.
EOF
}

json=0
while (($#)); do
  case "$1" in
    --json) json=1; shift ;;
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
