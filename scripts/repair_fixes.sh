#!/usr/bin/env bash
# Fix action implementations for repair.command (sourced, not executed directly).

REPAIR_STEAM_LIB="${SCRIPT_DIR:-}/scripts/lib/steam_lib.sh"
if [[ -f "${REPAIR_STEAM_LIB}" ]]; then
  # shellcheck source=scripts/lib/steam_lib.sh
  source "${REPAIR_STEAM_LIB}"
fi

REPAIR_WINE_BIN=""

repair_find_wine_bin() {
  local ver="${WINE_VERSION:-11.8}"
  local root="${WINE_ROOT:-$HOME/wine-${ver}}"
  local candidate="${root}/Wine Devel.app/Contents/Resources/wine/bin/wine"
  if [[ -x "${candidate}" ]]; then
    REPAIR_WINE_BIN="${candidate}"
    export WINEPREFIX
    export PATH="$(dirname "${REPAIR_WINE_BIN}"):${PATH}"
    return 0
  fi
  if [[ -n "${WINE_BIN:-}" && -x "${WINE_BIN}" ]]; then
    REPAIR_WINE_BIN="${WINE_BIN}"
    export WINEPREFIX
    export PATH="$(dirname "${REPAIR_WINE_BIN}"):${PATH}"
    return 0
  fi
  if command -v wine >/dev/null 2>&1; then
    REPAIR_WINE_BIN="$(command -v wine)"
    export WINEPREFIX
    export PATH="$(dirname "${REPAIR_WINE_BIN}"):${PATH}"
    return 0
  fi
  echo "Wine not found. Run ./run.command --setup-steam first (or set WINE_BIN)."
  return 1
}

repair_require_prefix() {
  [[ -f "${WINEPREFIX:?WINEPREFIX required}/system.reg" ]] || {
    echo "Prefix not initialized at ${WINEPREFIX}."
    return 1
  }
}

repair_wine_reg_set() {
  local reg_path="$1" value_name="$2" value_data="$3"
  "${REPAIR_WINE_BIN}" reg add "${reg_path}" /v "${value_name}" /t REG_SZ /d "${value_data}" /f >/dev/null
}

repair_merge_override_env() {
  local appid="$1" key="$2" val="$3"
  local overrides_dir="${SCRIPT_DIR:-}/cosmos_configs/overrides"
  mkdir -p "${overrides_dir}"
  local out="${overrides_dir}/${appid}.env"
  local tmp found=0 line
  tmp="$(mktemp "${TMPDIR:-/tmp}/override.XXXXXX")"
  if [[ -f "${out}" ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
      if [[ "${line}" == "${key}="* ]]; then
        printf '%s=%s\n' "${key}" "${val}" >> "${tmp}"
        found=1
      else
        printf '%s\n' "${line}" >> "${tmp}"
      fi
    done < "${out}"
  else
    printf '# Added by repair.command\n' >> "${tmp}"
  fi
  (( found )) || printf '%s=%s\n' "${key}" "${val}" >> "${tmp}"
  mv "${tmp}" "${out}"
  echo "Wrote ${out} (${key}=${val})."
}

repair_persist_setting() {
  local key="$1" val="$2"
  if [[ -n "${COSMOS_BOTTLE:-}" && -x "${SCRIPT_DIR:-}/bottle.command" ]]; then
    "${SCRIPT_DIR}/bottle.command" set "${COSMOS_BOTTLE}" "${key}" "${val}" && return 0
  fi
  local support="${COSMOS_SUPPORT_DIR:-$HOME/Library/Application Support/Cosmos}"
  local conf="${support}/steam.conf"
  mkdir -p "${support}"
  [[ -f "${conf}" ]] || {
    cat >"${conf}" <<EOF
# Cosmos default Steam bottle settings. Applied on each launch.
COSMOS_BACKEND="recommended"
COSMOS_DETACH="1"
COSMOS_STEAM_SILENT="1"
STEAM_LAUNCH_ARGS="-no-cef-sandbox -cef-single-process -noverifyfiles"
COSMOS_STEAM_WEBHELPER_WRAPPER="1"
COSMOS_STEAM_SEED_FONTS="1"
COSMOS_STEAM_CA_BUNDLE="1"
WINE_RETINA_MODE="0"
WINDOWS_VERSION=""
WINE_VERSION="11.8"
EOF
  }
  local tmp found=0 line
  tmp="$(mktemp "${TMPDIR:-/tmp}/steam.XXXXXX")"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" == "${key}="* ]]; then
      printf '%s="%s"\n' "${key}" "${val}" >> "${tmp}"
      found=1
    else
      printf '%s\n' "${line}" >> "${tmp}"
    fi
  done < "${conf}"
  (( found )) || printf '%s="%s"\n' "${key}" "${val}" >> "${tmp}"
  mv "${tmp}" "${conf}"
}

repair_map_dll_flag() {
  case "$1" in
    n|native) printf 'native' ;;
    b|builtin) printf 'builtin' ;;
    d|disabled) printf 'disabled' ;;
    e|empty) printf '' ;;
    *) printf '%s' "$1" ;;
  esac
}

repair_apply_dll_override_entry() {
  local dll="$1" flags="$2" mapped="" part mapped_flags="" IFS=','
  dll="${dll%.dll}"
  [[ -n "${dll}" && -n "${flags}" ]] || return 0
  for part in ${flags}; do
    mapped="$(repair_map_dll_flag "${part}")"
    [[ -n "${mapped}" ]] || continue
    if [[ -n "${mapped_flags}" ]]; then
      mapped_flags+=",${mapped}"
    else
      mapped_flags="${mapped}"
    fi
  done
  [[ -n "${mapped_flags}" ]] || return 0
  repair_wine_reg_set "HKCU\\Software\\Wine\\DllOverrides" "${dll}" "${mapped_flags}"
  echo "Set DllOverrides\\${dll}=${mapped_flags}"
}

repair_kill_wine() {
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  if command -v wineserver >/dev/null 2>&1; then
    wineserver -k || true
  fi
  pkill -f "wineserver.*${pfx}" 2>/dev/null || true
  pkill -f "wine.*${pfx}" 2>/dev/null || true
  echo "Sent kill signals for Wine processes tied to ${pfx}."
}

repair_install_steamwebhelper_wrapper() {
  repair_find_wine_bin || return 1
  repair_require_prefix || return 1
  export WINE_BIN="${REPAIR_WINE_BIN}"
  steam_install_webhelper_wrapper
}

repair_seed_japanese_fonts() {
  repair_find_wine_bin || return 1
  repair_require_prefix || return 1
  export WINE_BIN="${REPAIR_WINE_BIN}"
  steam_seed_japanese_fonts
}

repair_fix_steam_ssl() {
  repair_require_prefix || return 1
  steam_install_ca_bundle
}

repair_reinstall_steam() {
  repair_kill_wine
  repair_require_prefix || return 1
  repair_find_wine_bin || return 1
  local base removed=0
  for base in \
    "${WINEPREFIX}/drive_c/Program Files (x86)/Steam" \
    "${WINEPREFIX}/drive_c/Program Files/Steam"; do
    if [[ -d "${base}" ]]; then
      rm -rf "${base}"
      echo "Removed Steam at ${base}."
      removed=1
    fi
  done
  (( removed )) || echo "No existing Steam install found — running installer."
  local runner="${SCRIPT_DIR:-}/run.command"
  [[ -x "${runner}" ]] || {
    echo "run.command not found at ${runner}."
    return 1
  }
  echo "Re-running Steam installer via ${runner} --install-steam ..."
  WINE_BIN="${REPAIR_WINE_BIN}" "${runner}" --install-steam
}

repair_clear_steam_caches() {
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  if declare -F steam_clear_chromium_locks >/dev/null 2>&1; then
    steam_clear_chromium_locks
  fi
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

repair_clear_steam_download_cache() {
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  local removed=0 dir
  for dir in \
    "${pfx}/drive_c/Program Files (x86)/Steam/steamapps/downloading" \
    "${pfx}/drive_c/Program Files/Steam/steamapps/downloading" \
    "${pfx}/drive_c/Program Files (x86)/Steam/depotcache" \
    "${pfx}/drive_c/Program Files/Steam/depotcache" \
    "${pfx}/drive_c/Program Files (x86)/Steam/appcache/stats" \
    "${pfx}/drive_c/Program Files/Steam/appcache/stats"; do
    if [[ -d "${dir}" ]]; then
      rm -rf "${dir}"
      echo "Removed ${dir}"
      removed=$((removed + 1))
    fi
  done
  (( removed )) || echo "No Steam download/depot cache directories found to clear."
}

repair_set_windows_version() {
  [[ -n "${WINDOWS_VERSION:-}" ]] || {
    echo "Set WINDOWS_VERSION (winxp|win7|win8|win10|win11) before applying this fix."
    return 1
  }
  case "${WINDOWS_VERSION}" in
    winxp|win7|win8|win10|win11) ;;
    *) echo "WINDOWS_VERSION must be one of: winxp | win7 | win8 | win10 | win11."; return 1 ;;
  esac
  repair_find_wine_bin || return 1
  repair_require_prefix || return 1
  repair_wine_reg_set "HKCU\\Software\\Wine" "Version" "${WINDOWS_VERSION}"
  echo "Set Windows version=${WINDOWS_VERSION} in prefix registry."
  repair_persist_setting WINDOWS_VERSION "${WINDOWS_VERSION}"
  echo "Persisted WINDOWS_VERSION to bottle/steam settings."
}

repair_disable_retina() {
  repair_find_wine_bin || return 1
  repair_require_prefix || return 1
  repair_wine_reg_set "HKCU\\Software\\Wine\\Mac Driver" "RetinaMode" "n"
  echo "Set RetinaMode=n in prefix registry."
  repair_persist_setting WINE_RETINA_MODE "0"
  echo "Persisted WINE_RETINA_MODE=0 for future launches."
}

repair_apply_reg_commands() {
  local commands="${RECIPE_REG_COMMANDS:-${REG_COMMANDS:-}}"
  [[ -n "${commands}" ]] || {
    echo "No REG_COMMANDS set for apply_reg_commands."
    return 1
  }
  repair_find_wine_bin || return 1
  repair_require_prefix || return 1
  python3 - "${REPAIR_WINE_BIN}" "${commands}" <<'PY'
import shlex
import subprocess
import sys

def split_escaped(blob: str, sep: str = "|") -> list[str]:
    out: list[str] = []
    cur: list[str] = []
    i = 0
    while i < len(blob):
        if blob[i] == "\\" and i + 1 < len(blob) and blob[i + 1] == sep:
            cur.append(sep)
            i += 2
            continue
        if blob[i] == sep:
            out.append("".join(cur))
            cur = []
            i += 1
            continue
        cur.append(blob[i])
        i += 1
    out.append("".join(cur))
    return out

wine_bin, blob = sys.argv[1], sys.argv[2]
for line in split_escaped(blob):
    line = line.strip()
    if not line:
        continue
    if line.lower().startswith("wine "):
        line = line[5:].lstrip()
    try:
        args = shlex.split(line)
    except ValueError as exc:
        print(f"Unparsed reg command: {line} ({exc})")
        continue
    if not args:
        continue
    proc = subprocess.run([wine_bin, *args], capture_output=True, text=True)
    if proc.returncode == 0:
        print(f"Applied: {' '.join(args)}")
    else:
        err = (proc.stderr or proc.stdout or "").strip()
        print(f"Failed ({proc.returncode}): {' '.join(args)}")
        if err:
            print(err)
PY
}

repair_dll_override() {
  [[ -n "${DLL_OVERRIDE:-}" ]] || {
    echo "Set DLL_OVERRIDE before applying (WINEDLLOVERRIDES-style, e.g. ddraw=n,b or ddraw=native,builtin)."
    return 1
  }
  repair_find_wine_bin || return 1
  repair_require_prefix || return 1
  local entry dll flags
  local IFS=';'
  for entry in ${DLL_OVERRIDE}; do
    [[ "${entry}" == *"="* ]] || continue
    dll="${entry%%=*}"
    flags="${entry#*=}"
    repair_apply_dll_override_entry "${dll}" "${flags}"
  done
}

repair_rebuild_prefix() {
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  repair_kill_wine
  if [[ "${COSMOS_FORCE:-0}" != "1" ]]; then
    if [[ -t 0 ]]; then
      local reply=""
      read -r -p "Delete prefix ${pfx}? Steam and games inside it will be removed. [y/N]: " reply
      [[ "${reply}" == "y" || "${reply}" == "Y" ]] || { echo "Aborted."; return 1; }
    else
      echo "Set COSMOS_FORCE=1 for non-interactive prefix rebuild."
      return 1
    fi
  fi
  if [[ -d "${pfx}" ]]; then
    rm -rf "${pfx}"
    echo "Removed ${pfx}."
  else
    echo "No prefix found at ${pfx}."
  fi
  echo "Prefix rebuild complete. The next launch recreates the prefix and reinstalls Steam."
}

repair_force_borderless() {
  repair_find_wine_bin || return 1
  repair_require_prefix || return 1
  repair_wine_reg_set "HKCU\\Software\\Wine\\Mac Driver" "CaptureDisplays" "n"
  repair_wine_reg_set "HKCU\\Software\\Wine\\Mac Driver" "RetinaMode" "n"
  echo "Disabled display capture and Retina mode (common fullscreen/borderless fix)."
  repair_persist_setting WINE_RETINA_MODE "0"
}

repair_disable_intro_video() {
  local args="${INTRO_SKIP_ARGS:--novid}"
  local appid="${STEAM_APPID:-}"
  [[ "${appid}" =~ ^[0-9]+$ ]] || {
    echo "Set STEAM_APPID to the game's Steam App ID before applying this fix."
    echo "Default skip args: ${args} (override with INTRO_SKIP_ARGS)."
    return 1
  }
  local overrides_dir="${SCRIPT_DIR:-}/cosmos_configs/overrides"
  local out="${overrides_dir}/${appid}.env"
  local existing="" line
  if [[ -f "${out}" ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
      [[ "${line}" == STEAM_GAME_ARGS=* ]] && existing="${line#STEAM_GAME_ARGS=}"
    done < "${out}"
  fi
  local merged="${args}"
  if [[ -n "${existing}" && "${existing}" != *"${args}"* ]]; then
    merged="${existing} ${args}"
  elif [[ -n "${existing}" ]]; then
    merged="${existing}"
  fi
  repair_merge_override_env "${appid}" STEAM_GAME_ARGS "${merged}"
  echo "Re-run detect_steam_games.command --install to refresh launchers."
}

repair_set_backend() {
  local backend="${COSMOS_BACKEND:-}"
  [[ -n "${backend}" ]] || {
    echo "Set COSMOS_BACKEND (recommended|dxmt|d3dmetal|dxvk|wined3d) before applying this fix."
    return 1
  }
  backend="$(printf '%s' "${backend}" | tr '[:upper:]' '[:lower:]')"
  [[ "${backend}" == "gptk" ]] && backend="d3dmetal"
  case "${backend}" in
    recommended|dxmt|d3dmetal|dxvk|wined3d) ;;
    *) echo "COSMOS_BACKEND must be one of: recommended | dxmt | d3dmetal | dxvk | wined3d."; return 1 ;;
  esac
  repair_persist_setting COSMOS_BACKEND "${backend}"
  echo "Persisted COSMOS_BACKEND=${backend} for future launches."
  local appid="${STEAM_APPID:-}"
  if [[ "${appid}" =~ ^[0-9]+$ ]]; then
    repair_merge_override_env "${appid}" COSMOS_BACKEND "${backend}"
    echo "Re-run detect_steam_games.command --install to refresh launchers."
  fi
  if [[ "${backend}" == "d3dmetal" && -z "${GPTK_PATH:-}" ]]; then
    echo "Note: d3dmetal needs GPTK_PATH pointing at your Game Porting Toolkit install."
  fi
  if [[ "${backend}" == "dxvk" && -z "${DXVK_PATH:-}" ]]; then
    echo "Note: dxvk needs DXVK_PATH pointing at a folder of DXVK DLLs."
  fi
}
