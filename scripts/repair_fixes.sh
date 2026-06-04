#!/usr/bin/env bash
# Fix action implementations for repair.command (sourced, not executed directly).

repair_kill_wine() {
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  if command -v wineserver >/dev/null 2>&1; then
    wineserver -k || true
  fi
  pkill -f "wineserver.*${pfx}" 2>/dev/null || true
  pkill -f "wine.*${pfx}" 2>/dev/null || true
  echo "Sent kill signals for Wine processes tied to ${pfx}."
}

repair_clear_steam_caches() {
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  local removed=0 dir
  for dir in \
    "${pfx}/drive_c/users"/*/AppData/Local/Steam/htmlcache \
    "${pfx}/drive_c/users"/*/AppData/Local/Steam/logs \
    "${pfx}/drive_c/Program Files (x86)/Steam/appcache/httpcache" \
    "${pfx}/drive_c/Program Files (x86)/Steam/steamapps/shadercache" \
    "${pfx}/drive_c/Program Files/Steam/appcache/httpcache" \
    "${pfx}/drive_c/Program Files/Steam/steamapps/shadercache"; do
    if [[ -d "${dir}" ]]; then
      rm -rf "${dir}"
      echo "Removed ${dir}"
      removed=$((removed + 1))
    fi
  done
  (( removed )) || echo "No Steam cache directories found to clear."
}

repair_set_windows_version() {
  [[ -n "${WINDOWS_VERSION:-}" ]] || {
    echo "Set WINDOWS_VERSION (winxp|win7|win8|win10|win11) before applying this fix."
    return 1
  }
  [[ -x "${SCRIPT_DIR}/run.command" ]] || {
    echo "run.command not found; cannot apply Windows version."
    return 1
  }
  COSMOS_LAUNCH_MODE=noop WINDOWS_VERSION="${WINDOWS_VERSION}" \
    "${SCRIPT_DIR}/run.command" --help >/dev/null 2>&1 || true
  echo "Windows version ${WINDOWS_VERSION} should be applied on next run.command launch."
  echo "Tip: bottle.command set <name> WINDOWS_VERSION ${WINDOWS_VERSION}"
}
