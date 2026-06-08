#!/usr/bin/env bash
# Shared Steam helpers for Cosmos shell scripts.
#
# Patterns adapted from MIT-licensed projects (see docs/OPEN_SOURCE_INTEGRATIONS.md):
#   - find-steam-app (Ciberusps/find-steam-app) — libraryfolders.vdf v1/v2 paths
#   - steam-on-m1-wine (notpop/steam-on-m1-wine) — CEF launch flags, Chromium lock cleanup
#   - macos-wine-steam (ByMedion/macos-wine-steam) — Wine prefix Steam layout
#
# Source from repo scripts:
#   source "$(dirname "$0")/lib/steam_lib.sh"   # when cwd is scripts/
#   source "${SCRIPT_DIR}/scripts/lib/steam_lib.sh"

# Default Steam client flags for Wine on Apple Silicon. Chromium's sandbox relies on
# Windows integrity levels Wine does not model; -cef-single-process avoids fragile
# multi-process CEF startup under DXMT. Override with STEAM_LAUNCH_ARGS in steam.conf.
: "${STEAM_LAUNCH_ARGS:=-no-cef-sandbox -cef-single-process}"

# Locate libraryfolders.vdf (Steam has used a few names over the years).
steam_find_libraryfolders_vdf() {
  local steam_dir="$1"
  local f
  for f in \
    "${steam_dir}/steamapps/libraryfolders.vdf" \
    "${steam_dir}/steamapps/libraryfolder.vdf"; do
    [[ -f "${f}" ]] && { printf '%s' "${f}"; return 0; }
  done
  return 1
}

# Print library root paths from libraryfolders.vdf (newline-separated, deduped).
# Handles v1 ("1" "C:\\path") and v2 ("path" "C:\\path") layouts per find-steam-app.
steam_library_paths_from_vdf() {
  local vdf="$1"
  [[ -f "${vdf}" ]] || return 0
  {
    awk -F'"' '$2=="path"{print $4}' "${vdf}"
    awk -F'"' '$2 ~ /^[0-9]+$/ && $4 ~ /\\/ {print $4}' "${vdf}"
  } | awk '!seen[$0]++'
}

# Remove Chromium SingletonLock files left by crashed Steam sessions. Without this,
# the next launch can hit Steam's single-instance guard and open with no window.
steam_clear_chromium_locks() {
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  local cache cleared=0
  for cache in "${pfx}/drive_c/users"/*/AppData/Local/Steam/htmlcache; do
    [[ -d "${cache}" ]] || continue
    find "${cache}" -maxdepth 2 \
      \( -name 'Singleton*' -o -name '*.lock' \) \
      -delete 2>/dev/null || true
    cleared=1
  done
  (( cleared )) && echo "Cleared stale Chromium lock files under Steam htmlcache."
}

# Best-effort prep immediately before launching steam.exe.
steam_prepare_launch() {
  steam_clear_chromium_locks
}

# Append STEAM_LAUNCH_ARGS (from env / steam.conf) to a command array variable name.
steam_append_launch_args() {
  local -n _cmd="$1"
  [[ -n "${STEAM_LAUNCH_ARGS:-}" ]] || return 0
  local -a extra=()
  read -r -a extra <<< "${STEAM_LAUNCH_ARGS}"
  ((${#extra[@]})) || return 0
  _cmd+=("${extra[@]}")
}
