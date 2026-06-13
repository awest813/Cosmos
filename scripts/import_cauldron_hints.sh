#!/usr/bin/env bash
# List portable per-game hints from Cauldron's db/seed.sql (LGPL-2.1 reference).
# Does not modify profiles — use output to guide manual YAML ports.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/profile_lib.sh
source "${ROOT}/scripts/lib/profile_lib.sh"

CAULDRON_SEED_URL="https://raw.githubusercontent.com/cashcon57/cauldron/main/db/seed.sql"
CACHE="${ROOT}/.cache/cauldron-seed.sql"

usage() {
  cat <<'EOF'
Usage: import_cauldron_hints.sh [--list | --diff | --fetch]

  --list   Print Cauldron game_recommended_settings rows from seed.sql (default)
  --diff   List steam_app_ids in Cauldron seed that lack a Cosmos profile
  --fetch  Only download seed.sql to .cache/ (no parse)
EOF
}

fetch_seed() {
  mkdir -p "$(dirname -- "${CACHE}")"
  if [[ -f "${CACHE}" ]]; then
    return 0
  fi
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${CAULDRON_SEED_URL}" -o "${CACHE}.tmp"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "${CACHE}.tmp" "${CAULDRON_SEED_URL}"
  else
    echo "Need curl or wget to fetch Cauldron seed.sql" >&2
    exit 1
  fi
  mv "${CACHE}.tmp" "${CACHE}"
}

list_hints() {
  fetch_seed
  python3 - "${CACHE}" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
pattern = re.compile(
    r"INSERT OR REPLACE INTO game_recommended_settings\s*\([^)]+\)\s*VALUES\s*\(([^;]+)\);",
    re.IGNORECASE | re.DOTALL,
)
for m in pattern.finditer(text):
    row = " ".join(m.group(1).split())
    appid = row.split(",", 1)[0].strip()
    if appid.isdigit():
        print(f"{appid}\t{row}")
PY
}

cmd_diff() {
  fetch_seed
  local appid missing=0
  while IFS=$'\t' read -r appid _rest; do
    [[ "${appid}" =~ ^[0-9]+$ ]] || continue
    if ! profile_find_by_appid "${ROOT}/profiles" "${appid}" >/dev/null 2>&1; then
      printf '%s\n' "${appid}"
      missing=$((missing + 1))
    fi
  done < <(list_hints)
  printf '# %s Cauldron hinted app IDs without a Cosmos profile\n' "${missing}" >&2
}

main() {
  local mode="list"
  case "${1:---list}" in
    --list|list) mode="list" ;;
    --diff|diff) mode="diff" ;;
    --fetch|fetch) fetch_seed; echo "Cached ${CACHE}"; return 0 ;;
    -h|--help) usage; return 0 ;;
    *) usage; exit 1 ;;
  esac
  case "${mode}" in
    list) list_hints ;;
    diff) cmd_diff ;;
  esac
}

main "$@"
