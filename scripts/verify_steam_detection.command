#!/usr/bin/env bash
set -euo pipefail

# Cross-check Cosmos Steam game detection against the prefix on disk.
# Intended to run after detect_steam_games.command --list or on its own.
#
# Optional external cross-checks:
#   COSMOS_VERIFY_NODE=1          @ciberus/find-steam-app (MIT)
#   COSMOS_VERIFY_STEAM_LOCATE=1  steam-locate (MIT)
#   COSMOS_VERIFY_VDF_PYTHON=1    ValvePython/vdf vs bash parser

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}"
WINEPREFIX="${WINEPREFIX:-$HOME/.wine-steam-11}"
COSMOS_VERIFY_NODE="${COSMOS_VERIFY_NODE:-0}"
COSMOS_VERIFY_STEAM_LOCATE="${COSMOS_VERIFY_STEAM_LOCATE:-0}"
COSMOS_VERIFY_VDF_PYTHON="${COSMOS_VERIFY_VDF_PYTHON:-0}"

# shellcheck source=scripts/lib/steam_lib.sh
source "${REPO_ROOT}/scripts/lib/steam_lib.sh"

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

verify_game() {
  local steam_dir="$1" appid="$2" name="$3"
  local acf common
  acf="$(steam_find_app_manifest "${steam_dir}" "${appid}" || true)"
  if [[ -z "${acf}" ]]; then
    printf '  WARN %s (%s): manifest not found in any library\n' "${appid}" "${name}"
    issues=$((issues + 1))
    return
  fi
  if [[ -f "${acf}.tmp.save" ]]; then
    printf '  WARN %s (%s): stale manifest (%s.tmp.save present) at %s\n' \
      "${appid}" "${name}" "${acf##*/}" "${acf}"
    issues=$((issues + 1))
    return
  fi
  if ! steam_acf_is_playable "${acf}"; then
    local flags
    flags="$(steam_acf_read_field "${acf}" "StateFlags")"
    printf '  WARN %s (%s): not fully installed (StateFlags=%s)\n' \
      "${appid}" "${name}" "${flags:-unknown}"
    issues=$((issues + 1))
    return
  fi
  common="$(steam_verify_installdir "${acf}" || true)"
  if [[ -z "${common}" ]]; then
    local installdir
    installdir="$(steam_acf_read_field "${acf}" "installdir")"
    printf '  WARN %s (%s): installdir not on disk: %s/common/%s\n' \
      "${appid}" "${name}" "$(dirname "${acf}")" "${installdir:-?}"
    issues=$((issues + 1))
  fi
}

steam_dir="$(steam_find_steam_dir || true)"
[[ -n "${steam_dir}" ]] || die "Steam not found under ${WINEPREFIX}"

log "Verifying manifests and installdir paths for detected games"
while IFS= read -r line; do
  [[ "${line}" =~ ^[[:space:]]*[0-9]+ ]] || continue
  appid="$(printf '%s' "${line}" | awk '{print $1}')"
  name="$(printf '%s' "${line}" | sed -E 's/^[[:space:]]*[0-9]+[[:space:]]+//; s/[[:space:]]+\[.*$//')"
  games=$((games + 1))
  verify_game "${steam_dir}" "${appid}" "${name}"
done < "${TMP_LIST}"

log "Summary: ${games} game(s) listed, ${issues} warning(s)"
if (( issues > 0 )); then
  printf 'Review warnings above — partial installs or stale manifests are common.\n'
fi

if [[ "${COSMOS_VERIFY_VDF_PYTHON}" == "1" ]]; then
  verifier="${REPO_ROOT}/scripts/verify_vdf_python.sh"
  if [[ -x "${verifier}" ]]; then
    log "Optional: ValvePython/vdf cross-check"
    "${verifier}" || issues=$((issues + 1))
  fi
fi

if [[ "${COSMOS_VERIFY_STEAM_LOCATE}" == "1" ]]; then
  if command -v npx >/dev/null 2>&1; then
    log "Optional: steam-locate library folders (MIT)"
    npx --yes -p steam-locate@1.0.6 -c "
import('steam-locate').then(({ findSteamLocation }) =>
  findSteamLocation().then((info) => {
    console.log('steam path:', info.path);
    for (const p of info.libraryFolders || []) console.log('  library:', p);
  })
).catch((e) => { console.error(e); process.exit(1); });
" 2>/dev/null || printf '  (steam-locate failed — needs Node.js)\n'
  else
    printf 'COSMOS_VERIFY_STEAM_LOCATE=1 but npx not found; skip.\n'
  fi
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
