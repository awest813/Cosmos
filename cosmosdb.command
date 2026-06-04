#!/usr/bin/env bash
set -euo pipefail

# CosmosDB client (roadmap 0.7) — fetch compatibility hints and store local reports.
# Uses the MIT ProtonDB Community API as one data source (Linux/Proton reports).
# macOS-specific reports are stored locally until a shared host exists.

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
COSMOS_SUPPORT_DIR="${COSMOS_SUPPORT_DIR:-$HOME/Library/Application Support/Cosmos}"
COSMOSDB_DIR="${COSMOSDB_DIR:-${COSMOS_SUPPORT_DIR}/CosmosDB}"
REPORTS_DIR="${COSMOSDB_DIR}/reports"
CACHE_DIR="${COSMOSDB_DIR}/cache"

# Default public instance; override with COSMOS_PROTONDB_API_URL.
PROTONDB_API_URL="${COSMOS_PROTONDB_API_URL:-https://protondb-community-api.vercel.app}"

log() { printf "\n==> %s\n" "$1"; }
die() { printf "Error: %s\n" "$1" >&2; exit 1; }

usage() {
  cat <<'EOF'
CosmosDB — compatibility lookup and local macOS reports.

Usage: cosmosdb.command <command> [args]

Commands:
  lookup <steam_appid>          Fetch ProtonDB summary (cached 24h). Hint only on macOS.
  report <appid> <status> [note] Save a local macOS compatibility report (JSON).
  list-reports [appid]          List local reports (optionally filter by App ID).
  cache-clear                   Remove cached ProtonDB responses.

Status values: platinum | gold | silver | playable | bronze | broken | blocked

See docs/COSMOSDB.md for the full schema and data sources.
EOF
}

require_curl() {
  command -v curl >/dev/null 2>&1 || die "curl is required for ProtonDB lookup"
}

cache_path() {
  printf '%s/protondb-%s.json' "${CACHE_DIR}" "$1"
}

cmd_lookup() {
  local appid="${1:-}"
  [[ "${appid}" =~ ^[0-9]+$ ]] || die "Usage: cosmosdb.command lookup <steam_appid>"
  require_curl
  mkdir -p "${CACHE_DIR}"
  local cache; cache="$(cache_path "${appid}")"
  if [[ -f "${cache}" ]]; then
    local age=$(( $(date +%s) - $(stat -f %m "${cache}" 2>/dev/null || stat -c %Y "${cache}") ))
    if (( age < 86400 )); then
      log "ProtonDB summary (cached) for App ID ${appid}"
      cat "${cache}"
      printf '\n\n(Note: ProtonDB reflects Linux/Proton. Treat as a hint for macOS Wine.)\n'
      return 0
    fi
  fi
  local url="${PROTONDB_API_URL}/api/games/${appid}/summary"
  log "Fetching ${url}"
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/cosmosdb.XXXXXX")"
  if ! curl -fsSL --retry 3 --connect-timeout 10 -o "${tmp}" "${url}"; then
    rm -f "${tmp}"
    die "ProtonDB lookup failed (network or API down). Set COSMOS_PROTONDB_API_URL or try later."
  fi
  mv "${tmp}" "${cache}"
  cat "${cache}"
  printf '\n\n(Note: ProtonDB reflects Linux/Proton. Treat as a hint for macOS Wine.)\n'
}

cmd_report() {
  local appid="${1:-}" status="${2:-}" note="${3:-}"
  [[ "${appid}" =~ ^[0-9]+$ ]] || die "Usage: cosmosdb.command report <appid> <status> [note]"
  [[ -n "${status}" ]] || die "status required"
  mkdir -p "${REPORTS_DIR}"
  local chip osv
  chip="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "unknown")"
  osv="$(sw_vers -productVersion 2>/dev/null || echo "unknown")"
  local file="${REPORTS_DIR}/${appid}-$(date +%Y%m%dT%H%M%S).json"
  local note_escaped="${note//\\/\\\\}"
  note_escaped="${note_escaped//\"/\\\"}"
  printf '%s\n' "{
  \"schema\": \"cosmosdb-report-v0\",
  \"platform\": \"macos\",
  \"steam_appid\": ${appid},
  \"status\": \"${status}\",
  \"note\": \"${note_escaped}\",
  \"macos_version\": \"${osv}\",
  \"chip\": \"${chip}\",
  \"cosmos_backend\": \"${COSMOS_BACKEND:-}\",
  \"wine_version\": \"${WINE_VERSION:-}\",
  \"created_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
}" > "${file}"
  echo "Wrote local report: ${file}"
}

cmd_list_reports() {
  local filter="${1:-}"
  mkdir -p "${REPORTS_DIR}"
  shopt -s nullglob
  local f
  for f in "${REPORTS_DIR}"/*.json; do
    [[ -z "${filter}" || "${f}" == *"${filter}"* ]] || continue
    printf '%s\n' "${f}"
  done
  shopt -u nullglob
}

cmd_cache_clear() {
  rm -rf "${CACHE_DIR}"
  mkdir -p "${CACHE_DIR}"
  echo "Cleared ProtonDB cache under ${CACHE_DIR}"
}

main() {
  local cmd="${1:-}"; shift || true
  case "${cmd}" in
    lookup) cmd_lookup "$@" ;;
    report) cmd_report "$@" ;;
    list-reports) cmd_list_reports "$@" ;;
    cache-clear) cmd_cache_clear ;;
    ""|--help|-h|help) usage ;;
    *) die "Unknown command: ${cmd}" ;;
  esac
}

main "$@"
