#!/usr/bin/env bash
set -euo pipefail

# Cross-check Cosmos Steam game detection against the prefix on disk.
# Intended to run after detect_steam_games.command --list or on its own.
#
# Optional external cross-check (MIT find-steam-app):
#   npm install -g @ciberus/find-steam-app
#   COSMOS_VERIFY_NODE=1 ./scripts/verify_steam_detection.command

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}"
WINEPREFIX="${WINEPREFIX:-$HOME/.wine-steam-11}"
COSMOS_VERIFY_NODE="${COSMOS_VERIFY_NODE:-0}"

log() { printf "\n==> %s\n" "$1"; }
die() { printf "Error: %s\n" "$1" >&2; exit 1; }

[[ -x "${REPO_ROOT}/detect_steam_games.command" ]] \
  || die "detect_steam_games.command not found at ${REPO_ROOT}"

TMP_LIST="$(mktemp "${TMPDIR:-/tmp}/cosmos-detect.XXXXXX")"
trap 'rm -f "${TMP_LIST}"' EXIT

log "Running Cosmos detection (--list)"
WINEPREFIX="${WINEPREFIX}" "${REPO_ROOT}/detect_steam_games.command" --list >"${TMP_LIST}" 2>&1 || true

issues=0
games=0

verify_installdir() {
  local steam_dir="$1" appid="$2" name="$3"
  local steamapps="${steam_dir}/steamapps"
  local acf="${steamapps}/appmanifest_${appid}.acf"
  [[ -f "${acf}" ]] || { printf '  WARN %s: missing manifest %s\n' "${appid}" "${acf}"; issues=$((issues + 1)); return; }
  local installdir
  installdir="$(awk -F'"' '$2=="installdir"{print $4; exit}' "${acf}")"
  [[ -n "${installdir}" ]] || { printf '  WARN %s: no installdir in manifest\n' "${appid}"; issues=$((issues + 1)); return; }
  local common="${steamapps}/common/${installdir}"
  if [[ ! -d "${common}" ]]; then
    printf '  WARN %s (%s): installdir not on disk: %s\n' "${appid}" "${name}" "${common}"
    issues=$((issues + 1))
  fi
}

steam_dir=""
for base in \
  "${WINEPREFIX}/drive_c/Program Files (x86)/Steam" \
  "${WINEPREFIX}/drive_c/Program Files/Steam"; do
  [[ -d "${base}" ]] && steam_dir="${base}" && break
done
[[ -n "${steam_dir}" ]] || die "Steam not found under ${WINEPREFIX}"

log "Verifying installdir paths for detected games"
while IFS= read -r line; do
  [[ "${line}" =~ ^[[:space:]]*[0-9]+ ]] || continue
  appid="$(printf '%s' "${line}" | awk '{print $1}')"
  name="$(printf '%s' "${line}" | sed -E 's/^[[:space:]]*[0-9]+[[:space:]]+//; s/[[:space:]]+\[.*$//')"
  games=$((games + 1))
  verify_installdir "${steam_dir}" "${appid}" "${name}"
done < "${TMP_LIST}"

log "Summary: ${games} game(s) listed, ${issues} warning(s)"
if (( issues > 0 )); then
  printf 'Review warnings above — partial installs or stale manifests are common.\n'
fi

if [[ "${COSMOS_VERIFY_NODE}" == "1" ]]; then
  if command -v npx >/dev/null 2>&1; then
    log "Optional: cross-check with @ciberus/find-steam-app (MIT)"
    printf 'Compare App IDs manually; Wine prefix paths differ from native Steam.\n'
    npx --yes @ciberus/find-steam-app@4 2>/dev/null | head -n 40 || \
      printf '  (find-steam-app failed — install Node.js or set COSMOS_VERIFY_NODE=0)\n'
  else
    printf 'COSMOS_VERIFY_NODE=1 but npx not found; skip external cross-check.\n'
  fi
fi

(( issues == 0 )) || exit 2
exit 0
