#!/usr/bin/env bash
# Shared Steam helpers for Cosmos shell scripts.
#
# Patterns adapted from MIT-licensed projects (see docs/OPEN_SOURCE_INTEGRATIONS.md):
#   - steam-on-m1-wine (notpop/steam-on-m1-wine) — CEF wrapper, launch flags, prefix prep
#   - find-steam-app (Ciberusps/find-steam-app) — libraryfolders.vdf v1/v2 paths
#   - macos-wine-steam (ByMedion/macos-wine-steam) — Wine prefix Steam layout
#
# Source from repo scripts:
#   source "${SCRIPT_DIR}/scripts/lib/steam_lib.sh"

# --- Defaults (override via steam.conf / environment) -----------------------

: "${STEAM_LAUNCH_ARGS:=-no-cef-sandbox -cef-single-process -noverifyfiles}"
: "${COSMOS_STEAM_WEBHELPER_WRAPPER:=1}"
: "${COSMOS_STEAM_SEED_FONTS:=1}"
: "${COSMOS_STEAM_CA_BUNDLE:=1}"
: "${COSMOS_STEAM_WINEDLLOVERRIDES:=dxgi,d3d11,d3d10core=n,b;bcrypt=b;ncrypt=b;gameoverlayrenderer,gameoverlayrenderer64=d}"
: "${WINE_VIRTUAL_DESKTOP_NAME:=cosmos-steam}"

steam_third_party_root() {
  local root
  for root in \
    "${SCRIPT_DIR:-}/third_party/steam-on-m1-wine" \
    "${SCRIPT_DIR:-}/../third_party/steam-on-m1-wine"; do
    [[ -d "${root}" ]] && { printf '%s' "${root}"; return 0; }
  done
  return 1
}

# --- libraryfolders.vdf -----------------------------------------------------

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

steam_library_paths_from_vdf() {
  local vdf="$1"
  [[ -f "${vdf}" ]] || return 0
  {
    awk -F'"' '$2=="path"{print $4}' "${vdf}"
    awk -F'"' '$2 ~ /^[0-9]+$/ && $4 ~ /\\/ {print $4}' "${vdf}"
  } | awk '!seen[$0]++'
}

# --- Prefix preparation (steam-on-m1-wine 02, 05) ---------------------------

steam_wine_run() {
  WINEPREFIX="${WINEPREFIX:?WINEPREFIX required}" "${WINE_BIN:?WINE_BIN required}" "$@"
}

steam_import_reg_file() {
  local reg_file="$1"
  [[ -f "${reg_file}" ]] || return 1
  local wine_path=""
  wine_path="$(steam_wine_run winepath -w "${reg_file}" 2>/dev/null | tr -d '\r')" || true
  if [[ -n "${wine_path}" ]]; then
    steam_wine_run regedit /S "${wine_path}" >/dev/null 2>&1 && return 0
  fi
  steam_wine_run regedit /S "Z:${reg_file}" >/dev/null 2>&1
}

steam_seed_japanese_fonts() {
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  local fonts_dir="${pfx}/drive_c/windows/Fonts"
  mkdir -p "${fonts_dir}"

  local -a font_sources=(
    "/System/Library/Fonts/Hiragino Sans GB.ttc"
  )
  local f src dst copied=0 skipped=0
  while IFS= read -r -d '' f; do
    font_sources+=("${f}")
  done < <(find /System/Library/AssetsV2 -type f \
    \( -iname "YuGothic-*.otf" \
      -o -iname "Osaka.ttf" \
      -o -iname "OsakaMono.ttf" \
      -o -iname "ToppanBunkyuGothicPr6N.ttc" \) -print0 2>/dev/null)

  for src in "${font_sources[@]}"; do
    [[ -r "${src}" ]] || continue
    dst="${fonts_dir}/$(basename "${src}")"
    if [[ -f "${dst}" ]] && [[ ! "${src}" -nt "${dst}" ]]; then
      skipped=$((skipped + 1))
      continue
    fi
    cp "${src}" "${dst}"
    copied=$((copied + 1))
  done
  echo "Japanese host fonts: ${copied} copied, ${skipped} already up to date."

  local tp reg_file
  tp="$(steam_third_party_root || true)"
  reg_file="${tp}/assets/japanese-fonts.reg"
  if [[ -f "${reg_file}" ]]; then
    steam_import_reg_file "${reg_file}" \
      && echo "Applied Japanese font substitution registry." \
      || echo "Warning: font substitution registry import failed."
  fi
}

steam_install_ca_bundle() {
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  local ca_src="/etc/ssl/cert.pem"
  local ca_dst="${pfx}/drive_c/windows/cacert.pem"
  if [[ -r "${ca_src}" ]]; then
    cp "${ca_src}" "${ca_dst}"
    echo "Copied macOS CA bundle to ${ca_dst}."
  else
    echo "No CA bundle at ${ca_src}; skipping."
  fi
}

steam_stage_dxmt_prefix_dlls() {
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  local dxmt_root="${DXMT_ROOT:?DXMT_ROOT required}"
  local sys32="${pfx}/drive_c/windows/system32"
  local syswow64="${pfx}/drive_c/windows/syswow64"
  mkdir -p "${sys32}" "${syswow64}"
  local copied=0
  if [[ -f "${dxmt_root}/x86_64-windows/winemetal.dll" ]]; then
    cp -f "${dxmt_root}/x86_64-windows/winemetal.dll" "${sys32}/winemetal.dll"
    copied=1
  fi
  if [[ -f "${dxmt_root}/i386-windows/winemetal.dll" ]]; then
    cp -f "${dxmt_root}/i386-windows/winemetal.dll" "${syswow64}/winemetal.dll"
    copied=1
  fi
  (( copied )) && echo "Staged DXMT winemetal.dll into prefix system32/syswow64."
}

steam_prepare_prefix() {
  [[ "${COSMOS_STEAM_SEED_FONTS:-1}" == "1" ]] && steam_seed_japanese_fonts
  [[ "${COSMOS_STEAM_CA_BUNDLE:-1}" == "1" ]] && steam_install_ca_bundle
}

# --- steamwebhelper wrapper (steam-on-m1-wine 06) ---------------------------

steam_find_mingw_gcc() {
  local candidate
  for candidate in \
    "${HOMEBREW_PREFIX:-/opt/homebrew}/bin/x86_64-w64-mingw32-gcc" \
    "/opt/homebrew/bin/x86_64-w64-mingw32-gcc" \
    "/usr/local/bin/x86_64-w64-mingw32-gcc"; do
    [[ -x "${candidate}" ]] && { printf '%s' "${candidate}"; return 0; }
  done
  command -v x86_64-w64-mingw32-gcc 2>/dev/null || return 1
}

steam_wrapper_size_ceiling() { printf '%s' '500000'; }

steam_is_wrapper_like() {
  local path="$1"
  [[ -f "${path}" ]] || return 1
  local size ceiling
  size="$(wc -c <"${path}" | tr -d ' ')"
  ceiling="$(steam_wrapper_size_ceiling)"
  (( size < ceiling ))
}

# Build and install the MIT steamwebhelper wrapper into every cef.win* dir.
# Returns 0 on success, 1 if skipped (no toolchain / no Steam CEF), 2 on hard error.
steam_install_webhelper_wrapper() {
  local tp wrapper_dir wrapper_bin mingw
  tp="$(steam_third_party_root || true)"
  [[ -n "${tp}" ]] || { echo "third_party/steam-on-m1-wine not found."; return 1; }
  wrapper_dir="${tp}/wrapper"
  wrapper_bin="${wrapper_dir}/steamwebhelper.exe"
  [[ -d "${wrapper_dir}" ]] || return 1

  mingw="$(steam_find_mingw_gcc || true)"
  if [[ -z "${mingw}" ]]; then
    echo "mingw-w64 not found (brew install mingw-w64). Skipping steamwebhelper wrapper."
    return 1
  fi

  echo "Building steamwebhelper wrapper with ${mingw}..."
  make -C "${wrapper_dir}" clean >/dev/null 2>&1 || true
  make -C "${wrapper_dir}" CC="${mingw}" || {
    echo "Wrapper build failed."
    return 2
  }
  [[ -f "${wrapper_bin}" ]] || { echo "Wrapper binary missing after build."; return 2; }

  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  local cef_root="${pfx}/drive_c/Program Files (x86)/Steam/bin/cef"
  [[ -d "${cef_root}" ]] || {
    echo "Steam CEF directory not found at ${cef_root} — install Steam first."
    return 1
  }

  local installed=0 cef_dir target real
  while IFS= read -r -d '' cef_dir; do
    target="${cef_dir}/steamwebhelper.exe"
    real="${cef_dir}/steamwebhelper_real.exe"
    [[ -f "${target}" ]] || continue

    if steam_is_wrapper_like "${target}"; then
      if [[ ! -f "${real}" ]] || steam_is_wrapper_like "${real}"; then
        echo "Error: ${cef_dir} has wrapper-sized binaries but no Valve original."
        echo "Re-run ./run.command --install-steam to recover Steam."
        return 2
      fi
    else
      if [[ ! -f "${real}" ]] || steam_is_wrapper_like "${real}"; then
        cp "${target}" "${real}" || return 2
      fi
    fi
    cp "${wrapper_bin}" "${target}" || return 2
    echo "Installed wrapper at ${target}"
    installed=$((installed + 1))
  done < <(find "${cef_root}" -maxdepth 1 -type d -name 'cef.win*' -print0 2>/dev/null)

  if (( installed == 0 )); then
    echo "No cef.win* directories found under ${cef_root}."
    return 1
  fi
  echo "steamwebhelper wrapper installed in ${installed} CEF directory/directories."
  return 0
}

steam_ensure_webhelper_wrapper() {
  [[ "${COSMOS_STEAM_WEBHELPER_WRAPPER:-1}" == "1" ]] || return 0
  steam_install_webhelper_wrapper
}

steam_verify_webhelper_wrapper() {
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  local tp wrapper_bin wrapper_md5 cef_root
  tp="$(steam_third_party_root || true)"
  [[ -n "${tp}" ]] || return 0
  wrapper_bin="${tp}/wrapper/steamwebhelper.exe"
  [[ -f "${wrapper_bin}" ]] || return 0
  wrapper_md5="$(md5 -q "${wrapper_bin}" 2>/dev/null || md5sum "${wrapper_bin}" | awk '{print $1}')"
  cef_root="${pfx}/drive_c/Program Files (x86)/Steam/bin/cef"
  [[ -d "${cef_root}" ]] || return 0
  local needs=0 cef_dir target_md5
  while IFS= read -r -d '' cef_dir; do
    target_md5="$(md5 -q "${cef_dir}/steamwebhelper.exe" 2>/dev/null || true)"
    [[ "${target_md5}" == "${wrapper_md5}" ]] || needs=1
  done < <(find "${cef_root}" -maxdepth 1 -type d -name 'cef.win*' -print0 2>/dev/null)
  (( needs )) && steam_install_webhelper_wrapper
}

# --- Launch preparation (steam-on-m1-wine launch-steam.sh) ------------------

steam_stop_wine_prefix() {
  local wineserver_bin
  wineserver_bin="$(dirname "${WINE_BIN:?WINE_BIN required}")/wineserver"
  [[ -x "${wineserver_bin}" ]] || return 0
  WINEPREFIX="${WINEPREFIX}" "${wineserver_bin}" -k 2>/dev/null || true
}

steam_stop_lingering_processes() {
  steam_stop_wine_prefix
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  pkill -f "wineserver.*${pfx}" 2>/dev/null || true
  pkill -f "wine.*${pfx}" 2>/dev/null || true
}

steam_clear_chromium_locks() {
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  local cache cleared=0
  for cache in "${pfx}/drive_c/users"/*/AppData/Local/Steam/htmlcache; do
    [[ -d "${cache}" ]] || continue
    find "${cache}" -maxdepth 2 \
      \( -name 'Singleton*' -o -name '*.lock' -o -name 'CrashpadMetrics*.pma' \) \
      -delete 2>/dev/null || true
    cleared=1
  done
  (( cleared )) && echo "Cleared stale Chromium lock files under Steam htmlcache."
}

steam_scrub_user_reg() {
  local user_reg="${WINEPREFIX:?WINEPREFIX required}/user.reg"
  [[ -f "${user_reg}" ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 0

  python3 - "${user_reg}" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8', errors='surrogateescape') as f:
    data = f.read()
pattern = re.compile(r'"([^"]+\.exe)"="([^"]*)"')
changed = False
def fix(m):
    global changed
    value = m.group(2)
    if 'DISABLEDXMAXIMIZEDWINDOWEDMODE' not in value:
        return m.group(0)
    tokens = [t for t in value.split() if t and t != 'DISABLEDXMAXIMIZEDWINDOWEDMODE']
    new = '' if tokens == ['~'] else ' '.join(tokens)
    changed = True
    return f'"{m.group(1)}"="{new}"'
new = pattern.sub(fix, data)
new = re.sub(r'\n"[^"]+\.exe"=""\n', '\n', new)
if changed:
    with open(path, 'w', encoding='utf-8', errors='surrogateescape') as f:
        f.write(new)
PYEOF

  if ! grep -q '"AllowImmovableWindows"' "${user_reg}" 2>/dev/null; then
    python3 - "${user_reg}" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'r', encoding='utf-8', errors='surrogateescape') as f:
    data = f.read()
section_re = re.compile(r'^\[Software\\\\Wine\\\\Mac Driver\][^\n]*\n', re.MULTILINE)
m = section_re.search(data)
insert = '"AllowImmovableWindows"="n"\n'
if m:
    data = data[:m.end()] + insert + data[m.end():]
else:
    data = data.rstrip() + '\n\n[Software\\\\Wine\\\\Mac Driver]\n' + insert
with open(path, 'w', encoding='utf-8', errors='surrogateescape') as f:
    f.write(data)
PYEOF
  fi
}

steam_merge_launch_dll_overrides() {
  local steam_overrides="${COSMOS_STEAM_WINEDLLOVERRIDES:-}"
  [[ -n "${steam_overrides}" ]] || return 0
  if [[ -n "${WINEDLLOVERRIDES:-}" ]]; then
    export WINEDLLOVERRIDES="${steam_overrides};${WINEDLLOVERRIDES}"
  else
    export WINEDLLOVERRIDES="${steam_overrides}"
  fi
}

steam_detect_display_size() {
  local bounds width height
  bounds="$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null || true)"
  if [[ "${bounds}" =~ ,[[:space:]]*([0-9]+),[[:space:]]*([0-9]+)$ ]]; then
    width="${BASH_REMATCH[1]}"
    height="${BASH_REMATCH[2]}"
    if [[ "${width}" -gt 0 && "${height}" -gt 0 ]]; then
      printf '%sx%s' "${width}" "${height}"
      return 0
    fi
  fi
  printf '%s' '1440x900'
}

steam_prepare_launch() {
  steam_stop_lingering_processes
  steam_clear_chromium_locks
  steam_scrub_user_reg
  steam_verify_webhelper_wrapper
  steam_merge_launch_dll_overrides
}

steam_append_launch_args() {
  local -n _cmd="$1"
  [[ -n "${STEAM_LAUNCH_ARGS:-}" ]] || return 0
  local -a extra=()
  read -r -a extra <<< "${STEAM_LAUNCH_ARGS}"
  ((${#extra[@]})) || return 0
  _cmd+=("${extra[@]}")
}

# Build the Wine command array for launching steam.exe (handles virtual desktop).
steam_build_steam_launch_cmd() {
  local -n _out="$1"
  local steam_exe="$2"
  local desktop="${WINE_VIRTUAL_DESKTOP-__unset__}"
  local desktop_name="${WINE_VIRTUAL_DESKTOP_NAME:-cosmos-steam}"

  _out=()
  if [[ "${desktop}" == "auto" ]]; then
    desktop="$(steam_detect_display_size)"
  elif [[ "${desktop}" == "__unset__" || -z "${desktop}" || "${desktop}" == "0" ]]; then
    _out=("${WINE_BIN}" "${steam_exe}")
    steam_append_launch_args _out
    return
  fi
  _out=("${WINE_BIN}" explorer.exe "/desktop=${desktop_name},${desktop}" "${steam_exe}")
  steam_append_launch_args _out
}
