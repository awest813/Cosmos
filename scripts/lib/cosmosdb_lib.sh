#!/usr/bin/env bash
# CosmosDB helpers — fetch and normalize compatibility hints (roadmap 0.7).
# Data sources: ProtonDB, AppleGamingWiki, MacGamingDB.

COSMOSDB_HTTP_USER_AGENT="${COSMOSDB_HTTP_USER_AGENT:-Cosmos/0.7 (+https://github.com/Cosmos; macOS game compatibility)}"
COSMOSDB_CACHE_TTL_SECONDS="${COSMOSDB_CACHE_TTL_SECONDS:-86400}"

APPLEGAMINGWIKI_API_URL="${COSMOS_APPLEGAMINGWIKI_API_URL:-https://applegamingwiki.com/w/api.php}"
MACGAMINGDB_API_URL="${COSMOS_MACGAMINGDB_API_URL:-https://macgamingdb.app/api/rest}"
PROTONDB_API_URL="${COSMOS_PROTONDB_API_URL:-https://protondb-community-api.vercel.app}"

cosmosdb_die() { printf 'Error: %s\n' "$1" >&2; exit 1; }

cosmosdb_require_curl() {
  command -v curl >/dev/null 2>&1 || cosmosdb_die "curl is required for compatibility lookups"
}

cosmosdb_require_python3() {
  command -v python3 >/dev/null 2>&1 || cosmosdb_die "python3 is required to parse compatibility responses"
}

cosmosdb_file_mtime() {
  local path="$1"
  stat -f %m "${path}" 2>/dev/null || stat -c %Y "${path}"
}

cosmosdb_cache_path() {
  local source="$1" appid="$2"
  printf '%s/%s-%s.json' "${COSMOSDB_CACHE_DIR}" "${source}" "${appid}"
}

cosmosdb_cache_fresh() {
  local cache="$1"
  [[ -f "${cache}" ]] || return 1
  local age=$(( $(date +%s) - $(cosmosdb_file_mtime "${cache}") ))
  (( age < COSMOSDB_CACHE_TTL_SECONDS ))
}

cosmosdb_http_get() {
  local url="$1" outfile="$2"
  curl -fsSL --retry 3 --connect-timeout 15 --max-time 60 \
    -A "${COSMOSDB_HTTP_USER_AGENT}" \
    -H 'Accept: application/json' \
    -o "${outfile}" "${url}"
}

cosmosdb_fetch_url() {
  local source="$1" appid="$2" url="$3"
  cosmosdb_require_curl
  mkdir -p "${COSMOSDB_CACHE_DIR}"
  local cache; cache="$(cosmosdb_cache_path "${source}" "${appid}")"
  if cosmosdb_cache_fresh "${cache}"; then
    printf 'cached\n'
    cat "${cache}"
    return 0
  fi
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/cosmosdb.XXXXXX")"
  if ! cosmosdb_http_get "${url}" "${tmp}"; then
    rm -f "${tmp}"
    return 1
  fi
  mv "${tmp}" "${cache}"
  printf 'fetched\n'
  cat "${cache}"
}

# --- ProtonDB ---

cosmosdb_fetch_protondb() {
  local appid="$1"
  local url="${PROTONDB_API_URL}/api/games/${appid}/summary"
  cosmosdb_fetch_url "protondb" "${appid}" "${url}"
}

# --- AppleGamingWiki ---

cosmosdb_agw_search_page() {
  local appid="$1"
  cosmosdb_require_curl
  cosmosdb_require_python3
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/cosmosdb-agw-search.XXXXXX")"
  local enc_appid; enc_appid="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "steam appid ${appid}")"
  local url="${APPLEGAMINGWIKI_API_URL}?action=query&list=search&srsearch=${enc_appid}&srnamespace=0&srlimit=10&format=json"
  if ! cosmosdb_http_get "${url}" "${tmp}"; then
    rm -f "${tmp}"
    return 1
  fi
  python3 - "${appid}" "${tmp}" <<'PYEOF'
import json, sys, urllib.parse

appid = sys.argv[1]
with open(sys.argv[2], encoding="utf-8") as fh:
    data = json.load(fh)

hits = data.get("query", {}).get("search", [])
if not hits:
    sys.exit(1)

api = "https://applegamingwiki.com/w/api.php"
for hit in hits:
    title = hit.get("title", "")
    if not title:
        continue
    enc = urllib.parse.quote(title.replace(" ", "_"))
    print(enc)
    sys.exit(0)
sys.exit(1)
PYEOF
  local rc=$?
  rm -f "${tmp}"
  return "${rc}"
}

cosmosdb_agw_fetch_wikitext() {
  local page_enc="$1"
  local url="${APPLEGAMINGWIKI_API_URL}?action=parse&page=${page_enc}&prop=wikitext&format=json"
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/cosmosdb-agw-parse.XXXXXX")"
  if ! cosmosdb_http_get "${url}" "${tmp}"; then
    rm -f "${tmp}"
    return 1
  fi
  python3 - "${tmp}" <<'PYEOF'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
parse = data.get("parse") or {}
wikitext = (parse.get("wikitext") or {}).get("*", "")
title = parse.get("title", "")
if not wikitext:
    sys.exit(1)
print(title)
print("---WIKITEXT---")
print(wikitext)
PYEOF
  local rc=$?
  rm -f "${tmp}"
  return "${rc}"
}

cosmosdb_agw_parse_wikitext() {
  local appid="$1"
  cosmosdb_require_python3
  local tmp_in; tmp_in="$(mktemp "${TMPDIR:-/tmp}/cosmosdb-agw-in.XXXXXX")"
  cat > "${tmp_in}"
  python3 - "${appid}" "${tmp_in}" <<'PYEOF'
import json, re, sys

appid = sys.argv[1]
with open(sys.argv[2], encoding="utf-8") as fh:
    raw = fh.read()
title = ""
wikitext = raw
if "---WIKITEXT---" in raw:
    title, wikitext = raw.split("---WIKITEXT---", 1)
    title = title.strip()

def main_steam_appid(text: str):
    m = re.search(r"(?m)^\|steam appid\s*=\s*(\d+)\s*$", text, re.I)
    return m.group(1) if m else None

if main_steam_appid(wikitext) != appid:
  side = re.search(rf"\|steam appid side\s*=\s*([^\n|]+)", wikitext, re.I)
  side_ids = []
  if side:
      side_ids = [s.strip() for s in side.group(1).split(",") if s.strip()]
  if appid not in side_ids:
      sys.exit(2)

page_slug = title.replace(" ", "_") if title else ""
page_url = f"https://applegamingwiki.com/wiki/{page_slug}" if page_slug else ""

ratings = {}
notes = {}
for field in (
    "native", "rosetta 2", "ios-ipados app", "crossover", "wine",
    "parallels", "windows 10 arm", "linux arm", "RPCS3",
):
    key = field.replace(" ", "_").replace("-", "_")
    m = re.search(rf"\|{re.escape(field)}\s*=\s*([^\n|]+)", wikitext, re.I)
    if m:
        ratings[key] = m.group(1).strip()
    note_key = f"{field} notes"
    m = re.search(rf"\|{re.escape(note_key)}\s*=\s*([^\n|]+)", wikitext, re.I)
    if m:
        notes[key] = m.group(1).strip()

pcgw = ""
m = re.search(r"\|pcgamingwiki\s*=\s*([^\n|]+)", wikitext, re.I)
if m:
    pcgw = m.group(1).strip()

out = {
    "source": "applegamingwiki",
    "steam_appid": int(appid),
    "page_title": title,
    "page_url": page_url,
    "pcgamingwiki": pcgw or None,
    "compatibility": ratings,
    "notes": notes,
    "hint": (
        "Community wiki data for macOS (Wine/CrossOver/Parallels). "
        "Wine column often reflects Porting Kit / GPTK paths."
    ),
}
print(json.dumps(out, indent=2, ensure_ascii=False))
PYEOF
  local rc=$?
  rm -f "${tmp_in}"
  return "${rc}"
}

cosmosdb_fetch_applegamingwiki() {
  local appid="$1"
  cosmosdb_require_curl
  cosmosdb_require_python3
  mkdir -p "${COSMOSDB_CACHE_DIR}"
  local cache; cache="$(cosmosdb_cache_path "applegamingwiki" "${appid}")"
  if cosmosdb_cache_fresh "${cache}"; then
    printf 'cached\n'
    cat "${cache}"
    return 0
  fi

  local page_enc
  if ! page_enc="$(cosmosdb_agw_search_page "${appid}")"; then
    return 1
  fi

  local parsed
  if ! parsed="$(cosmosdb_agw_fetch_wikitext "${page_enc}")"; then
    return 1
  fi

  local summary
  if ! summary="$(printf '%s' "${parsed}" | cosmosdb_agw_parse_wikitext "${appid}")"; then
    return 1
  fi

  printf '%s\n' "${summary}" > "${cache}"
  printf 'fetched\n'
  cat "${cache}"
}

# --- MacGamingDB ---

cosmosdb_normalize_macgamingdb() {
  local appid="$1"
  cosmosdb_require_python3
  local tmp_in; tmp_in="$(mktemp "${TMPDIR:-/tmp}/cosmosdb-mgd-in.XXXXXX")"
  cat > "${tmp_in}"
  python3 - "${appid}" "${tmp_in}" <<'PYEOF'
import json, sys

appid = sys.argv[1]
with open(sys.argv[2], encoding="utf-8") as fh:
    raw = json.load(fh)
game = raw.get("game") or {}
details_raw = game.get("details") or "{}"
try:
    steam_details = json.loads(details_raw) if isinstance(details_raw, str) else details_raw
except json.JSONDecodeError:
    steam_details = {}

reviews = raw.get("reviews") or []
stats = raw.get("stats")

def count_layer(layer: str) -> int:
    return sum(1 for r in reviews if (r.get("translationLayer") or "") == layer)

def count_method(method: str) -> int:
    return sum(1 for r in reviews if (r.get("playMethod") or "") == method)

sample_notes = []
for r in reviews[:3]:
    note = (r.get("notes") or "").strip()
    if note:
        sample_notes.append(note[:240])

out = {
    "source": "macgamingdb",
    "steam_appid": str(game.get("id") or appid),
    "title": steam_details.get("name"),
    "aggregated_performance": game.get("aggregatedPerformance"),
    "review_count": game.get("reviewCount") or (stats or {}).get("totalReviews") or len(reviews),
    "stats": stats,
    "methods": {
        "native": count_method("NATIVE"),
        "crossover": count_method("CROSSOVER"),
        "parallels": count_method("PARALLELS"),
        "other": count_method("OTHER"),
    },
    "translation_layers": {
        "dxmt": count_layer("DXMT"),
        "dxvk": count_layer("DXVK"),
        "d3d_metal": count_layer("D3D_METAL"),
        "none": count_layer("NONE"),
    },
    "sample_notes": sample_notes,
    "hint": (
        "Community Apple Silicon benchmarks. DXMT/D3D_METAL map to Cosmos backends; "
        "CrossOver reviews are a useful proxy for Wine-on-Mac."
    ),
}
print(json.dumps(out, indent=2, ensure_ascii=False))
PYEOF
  local rc=$?
  rm -f "${tmp_in}"
  return "${rc}"
}

cosmosdb_fetch_macgamingdb() {
  local appid="$1"
  local url="${MACGAMINGDB_API_URL}/games/${appid}"
  cosmosdb_require_curl
  cosmosdb_require_python3
  mkdir -p "${COSMOSDB_CACHE_DIR}"
  local cache; cache="$(cosmosdb_cache_path "macgamingdb" "${appid}")"
  if cosmosdb_cache_fresh "${cache}"; then
    printf 'cached\n'
    cat "${cache}"
    return 0
  fi
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/cosmosdb-mgd.XXXXXX")"
  if ! cosmosdb_http_get "${url}" "${tmp}"; then
    rm -f "${tmp}"
    return 1
  fi
  local summary
  if ! summary="$(cat "${tmp}" | cosmosdb_normalize_macgamingdb "${appid}")"; then
    rm -f "${tmp}"
    return 1
  fi
  rm -f "${tmp}"
  printf '%s\n' "${summary}" > "${cache}"
  printf 'fetched\n'
  cat "${cache}"
}

# Parse wikitext from a fixture file (title on first line, ---WIKITEXT--- delimiter).
cosmosdb_agw_parse_fixture() {
  local appid="$1" fixture="$2"
  { head -n 1 "${fixture}"; printf '%s\n' '---WIKITEXT---'; tail -n +2 "${fixture}"; } \
    | cosmosdb_agw_parse_wikitext "${appid}"
}

# Normalize MacGamingDB JSON from a fixture file.
cosmosdb_macgamingdb_parse_fixture() {
  local appid="$1" fixture="$2"
  cat "${fixture}" | cosmosdb_normalize_macgamingdb "${appid}"
}
