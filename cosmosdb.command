#!/usr/bin/env bash
set -euo pipefail

# CosmosDB client (roadmap 0.7) — fetch compatibility hints and store local reports.
# External hints: ProtonDB, AppleGamingWiki, MacGamingDB.
# macOS-specific reports are stored locally until a shared host exists.

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
COSMOS_SUPPORT_DIR="${COSMOS_SUPPORT_DIR:-$HOME/Library/Application Support/Cosmos}"
COSMOSDB_DIR="${COSMOSDB_DIR:-${COSMOS_SUPPORT_DIR}/CosmosDB}"
REPORTS_DIR="${COSMOSDB_DIR}/reports"
CACHE_DIR="${COSMOSDB_DIR}/cache"
COSMOSDB_CACHE_DIR="${CACHE_DIR}"

# shellcheck source=scripts/lib/cosmosdb_lib.sh
source "${SCRIPT_DIR}/scripts/lib/cosmosdb_lib.sh"

log() { printf "\n==> %s\n" "$1"; }
note() { printf '\n%s\n' "$1"; }

usage() {
  cat <<'EOF'
CosmosDB — compatibility lookup and local macOS reports.

Usage: cosmosdb.command <command> [args]

Commands:
  lookup <steam_appid> [source]
      Fetch compatibility hints (cached 24h). Sources:
        all (default) | protondb | applegamingwiki | macgamingdb | umu
  report <appid> <status> [note]
      Save a local macOS compatibility report (JSON).
  list-reports [appid]
      List local reports (optionally filter by App ID).
  cache-clear [source]
      Remove cached responses (all sources, or one of: protondb,
      applegamingwiki, macgamingdb, umu).

Status values: platinum | gold | silver | playable | bronze | broken | blocked

Environment:
  COSMOSDB_DIR                  Storage root
  COSMOS_PROTONDB_API_URL       ProtonDB API base
  COSMOS_APPLEGAMINGWIKI_API_URL  MediaWiki API base
  COSMOS_MACGAMINGDB_API_URL    MacGamingDB REST base (…/api/rest)
  COSMOS_UMU_API_URL            UMU database API (GPL data; hints only)
  COSMOSDB_CACHE_TTL_SECONDS    Cache lifetime (default 86400)
  COSMOSDB_HTTP_USER_AGENT      HTTP User-Agent for wiki/API requests

See docs/COSMOSDB.md for schemas and attribution.
EOF
}

cmd_lookup_one() {
  local source="$1" appid="$2"
  local status_line body
  case "${source}" in
    protondb)
      log "ProtonDB summary for App ID ${appid}"
      if ! body="$(cosmosdb_fetch_protondb "${appid}")"; then
        note "(ProtonDB lookup failed — network or API down.)"
        return 1
      fi
      status_line="$(printf '%s' "${body}" | head -n1)"
      body="$(printf '%s' "${body}" | tail -n +2)"
      [[ -n "${body}" ]] && printf '%s\n' "${body}"
      note "(ProtonDB reflects Linux/Proton. Treat as a weak hint for macOS Wine.)"
      ;;
    applegamingwiki|agw)
      log "AppleGamingWiki macOS compatibility for App ID ${appid}"
      if ! body="$(cosmosdb_fetch_applegamingwiki "${appid}")"; then
        note "(AppleGamingWiki lookup failed — no page found or network error.)"
        return 1
      fi
      status_line="$(printf '%s' "${body}" | head -n1)"
      body="$(printf '%s' "${body}" | tail -n +2)"
      [[ -n "${body}" ]] && printf '%s\n' "${body}"
      note "(AppleGamingWiki is community-maintained. Wine/CrossOver columns are hints for Cosmos backends.)"
      ;;
    macgamingdb|mgd)
      log "MacGamingDB Apple Silicon data for App ID ${appid}"
      if ! body="$(cosmosdb_fetch_macgamingdb "${appid}")"; then
        note "(MacGamingDB lookup failed — game not found or network error.)"
        return 1
      fi
      status_line="$(printf '%s' "${body}" | head -n1)"
      body="$(printf '%s' "${body}" | tail -n +2)"
      [[ -n "${body}" ]] && printf '%s\n' "${body}"
      note "(MacGamingDB reports community FPS/benchmarks. DXMT/D3D_METAL map to Cosmos graphics backends.)"
      ;;
    umu)
      log "UMU database fix metadata for App ID ${appid}"
      if ! body="$(cosmosdb_fetch_umu "${appid}")"; then
        note "(UMU lookup failed — network error.)"
        return 1
      fi
      status_line="$(printf '%s' "${body}" | head -n1)"
      body="$(printf '%s' "${body}" | tail -n +2)"
      [[ -n "${body}" ]] && printf '%s\n' "${body}"
      if printf '%s' "${body}" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("has_fix_database_entry") else 1)' 2>/dev/null; then
        note "(UMU lists Proton fix metadata. Port concepts to Cosmos recipes — do not import GPL scripts.)"
      else
        note "(No UMU database entry — game may run without Proton-specific fixes.)"
      fi
      ;;
    *)
      cosmosdb_die "Unknown lookup source: ${source}"
      ;;
  esac
}

cmd_lookup() {
  local appid="${1:-}" source="${2:-all}"
  [[ "${appid}" =~ ^[0-9]+$ ]] || cosmosdb_die "Usage: cosmosdb.command lookup <steam_appid> [source]"
  cosmosdb_require_curl

  case "${source}" in
    all)
      local failed=0
      cmd_lookup_one protondb "${appid}" || failed=1
      cmd_lookup_one applegamingwiki "${appid}" || failed=1
      cmd_lookup_one macgamingdb "${appid}" || failed=1
      cmd_lookup_one umu "${appid}" || failed=1
      (( failed == 0 )) || note "(One or more sources failed. Local Cosmos reports override external hints.)"
      ;;
    protondb|applegamingwiki|agw|macgamingdb|mgd|umu)
      local norm="${source}"
      [[ "${norm}" == agw ]] && norm=applegamingwiki
      [[ "${norm}" == mgd ]] && norm=macgamingdb
      cmd_lookup_one "${norm}" "${appid}"
      ;;
    *)
      cosmosdb_die "Unknown source '${source}'. Use all, protondb, applegamingwiki, macgamingdb, or umu."
      ;;
  esac
}

cmd_report() {
  local appid="${1:-}" status="${2:-}" note="${3:-}"
  [[ "${appid}" =~ ^[0-9]+$ ]] || cosmosdb_die "Usage: cosmosdb.command report <appid> <status> [note]"
  [[ -n "${status}" ]] || cosmosdb_die "status required"
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
  local source="${1:-all}"
  mkdir -p "${CACHE_DIR}"
  case "${source}" in
    all)
      rm -f "${CACHE_DIR}"/*.json
      echo "Cleared compatibility cache under ${CACHE_DIR}"
      ;;
    protondb|applegamingwiki|macgamingdb|umu)
      rm -f "${CACHE_DIR}/${source}-"*.json
      echo "Cleared ${source} cache under ${CACHE_DIR}"
      ;;
    *)
      cosmosdb_die "Unknown cache source '${source}'"
      ;;
  esac
}

main() {
  local cmd="${1:-}"; shift || true
  case "${cmd}" in
    lookup) cmd_lookup "$@" ;;
    report) cmd_report "$@" ;;
    list-reports) cmd_list_reports "$@" ;;
    cache-clear) cmd_cache_clear "$@" ;;
    ""|--help|-h|help) usage ;;
    *) cosmosdb_die "Unknown command: ${cmd}" ;;
  esac
}

main "$@"
