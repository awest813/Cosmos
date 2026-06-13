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

# steam.exe is typically several MB; smaller files are incomplete or corrupt installs.
STEAM_EXE_MIN_BYTES=500000

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

# --- Installed-game detection (find-steam-app patterns) ----------------------

# Convert a Windows path from libraryfolders.vdf to a path inside WINEPREFIX.
steam_win_to_unix() {
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  local p="$1"
  p="${p//\\//}"
  local drive rest
  drive="$(printf '%s' "${p:0:1}" | tr '[:upper:]' '[:lower:]')"
  rest="${p:2}"
  rest="${rest//\/\//\/}"
  [[ "${rest}" == /* ]] || rest="/${rest}"
  printf '%s/dosdevices/%s:%s' "${pfx}" "${drive}" "${rest}"
}

steam_find_steam_dir() {
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  local a="${pfx}/drive_c/Program Files (x86)/Steam"
  local b="${pfx}/drive_c/Program Files/Steam"
  if [[ -d "${a}" ]]; then printf '%s' "${a}"; elif [[ -d "${b}" ]]; then printf '%s' "${b}"; fi
}

# Return the first steam.exe candidate path in the prefix (may be invalid/incomplete).
steam_find_exe_candidate() {
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  local steam32="${pfx}/drive_c/Program Files (x86)/Steam/steam.exe"
  local steam64="${pfx}/drive_c/Program Files/Steam/steam.exe"
  if [[ -f "${steam32}" ]]; then
    printf '%s\n' "${steam32}"
  elif [[ -f "${steam64}" ]]; then
    printf '%s\n' "${steam64}"
  fi
}

# True when steam.exe exists and looks like a real Valve binary (not a stub).
steam_exe_is_valid() {
  local path="$1"
  [[ -f "${path}" ]] || return 1
  local size
  size="$(wc -c <"${path}" | tr -d ' ')"
  (( size >= STEAM_EXE_MIN_BYTES )) || return 1
  local magic
  magic="$(dd if="${path}" bs=1 count=2 2>/dev/null || true)"
  [[ "${magic}" == $'MZ' ]] || return 1
  return 0
}

# Print the steamapps directory for every Steam library (newline separated, deduped).
steam_collect_steamapps_dirs() {
  local steam_dir="$1"
  local vdf=""
  vdf="$(steam_find_libraryfolders_vdf "${steam_dir}" || true)"
  {
    printf '%s\n' "${steam_dir}/steamapps"
    if [[ -n "${vdf}" ]]; then
      local path
      while IFS= read -r path; do
        [[ -n "${path}" ]] || continue
        printf '%s/steamapps\n' "$(steam_win_to_unix "${path}")"
      done < <(steam_library_paths_from_vdf "${vdf}")
    fi
  } | awk '!seen[$0]++'
}

# --- Native macOS / Linux Steam (dual-path detection, Phase 2) ---------------

# Print candidate native Steam installation roots (one per line).
steam_native_roots() {
  if [[ -n "${COSMOS_STEAM_NATIVE_PATH:-}" ]]; then
    printf '%s\n' "${COSMOS_STEAM_NATIVE_PATH}"
    return 0
  fi
  case "$(uname -s)" in
    Darwin)
      printf '%s\n' "${HOME}/Library/Application Support/Steam"
      ;;
    Linux)
      [[ -d "${HOME}/.steam/steam" ]] && printf '%s\n' "${HOME}/.steam/steam"
      [[ -d "${HOME}/.local/share/Steam" ]] && printf '%s\n' "${HOME}/.local/share/Steam"
      ;;
  esac
}

# Resolve a library path from libraryfolders.vdf (Windows or Unix style).
steam_resolve_library_path() {
  local path="$1"
  [[ -n "${path}" ]] || return 1
  if [[ "${path}" == *'\'* ]] || [[ "${path}" =~ ^[A-Za-z]: ]]; then
    steam_win_to_unix "${path}"
  else
    printf '%s' "${path}"
  fi
}

# Collect steamapps directories from native Steam installs (not Wine prefix).
steam_collect_native_steamapps_dirs() {
  local root steam_dir vdf path resolved
  {
    while IFS= read -r root; do
      [[ -n "${root}" && -d "${root}" ]] || continue
      steam_dir="${root}"
      printf '%s/steamapps\n' "${steam_dir}"
      vdf="$(steam_find_libraryfolders_vdf "${steam_dir}" || true)"
      if [[ -n "${vdf}" ]]; then
        while IFS= read -r path; do
          [[ -n "${path}" ]] || continue
          resolved="$(steam_resolve_library_path "${path}" 2>/dev/null || true)"
          [[ -n "${resolved}" ]] || continue
          printf '%s/steamapps\n' "${resolved}"
        done < <(steam_library_paths_from_vdf "${vdf}")
      fi
    done < <(steam_native_roots)
  } | awk '!seen[$0]++'
}

# Wine-prefix libraries plus optional native Steam libraries (deduped paths).
steam_collect_detection_steamapps_dirs() {
  local steam_dir="$1"
  {
    steam_collect_steamapps_dirs "${steam_dir}"
    if [[ "${COSMOS_STEAM_NATIVE_SCAN:-0}" == "1" ]]; then
      steam_collect_native_steamapps_dirs
    fi
  } | awk '!seen[$0]++'
}

# Print installed Steam App IDs from a steamapps directory (one per line).
steam_collect_appids_from_steamapps() {
  local steamapps="$1"
  local acf appid
  [[ -d "${steamapps}" ]] || return 0
  shopt -s nullglob
  for acf in "${steamapps}"/appmanifest_*.acf; do
    appid="${acf##*/appmanifest_}"; appid="${appid%.acf}"
    [[ "${appid}" =~ ^[0-9]+$ ]] || continue
    steam_acf_is_playable "${acf}" || continue
    printf '%s\n' "${appid}"
  done
  shopt -u nullglob
}

# App IDs installed in both the Wine-prefix Steam and native macOS/Linux Steam.
steam_dual_install_appids() {
  local wine_steam_dir="$1"
  local wine_ids="" native_ids="" steamapps id
  [[ -n "${wine_steam_dir}" && -d "${wine_steam_dir}" ]] || return 0
  while IFS= read -r steamapps; do
    while IFS= read -r id || [[ -n "${id}" ]]; do
      [[ -n "${id}" ]] || continue
      wine_ids+=" ${id} "
    done < <(steam_collect_appids_from_steamapps "${steamapps}")
  done < <(steam_collect_steamapps_dirs "${wine_steam_dir}")

  while IFS= read -r steamapps; do
    while IFS= read -r id || [[ -n "${id}" ]]; do
      [[ -n "${id}" ]] || continue
      native_ids+=" ${id} "
    done < <(steam_collect_appids_from_steamapps "${steamapps}")
  done < <(steam_collect_native_steamapps_dirs)

  for id in ${wine_ids}; do
    [[ "${native_ids}" == *" ${id} "* ]] && printf '%s\n' "${id}"
  done | awk '!seen[$0]++'
  return 0
}

# Human-readable warning when the same App ID exists in Wine and native Steam.
steam_warn_dual_install_conflicts() {
  local wine_steam_dir="$1"
  local -a conflicts=()
  local id
  while IFS= read -r id || [[ -n "${id}" ]]; do
    [[ -n "${id}" ]] || continue
    conflicts+=("${id}")
  done < <(steam_dual_install_appids "${wine_steam_dir}")
  ((${#conflicts[@]})) || return 0
  printf 'Warning: %s App ID(s) are installed in both Wine Steam and native Steam:\n' "${#conflicts[@]}" >&2
  printf '  %s\n' "${conflicts[*]}" >&2
  printf '  Steam Cloud saves use different paths (Windows prefix vs macOS ~/Library).\n' >&2
  printf '  Pick one client per game to avoid sync conflicts. See docs/STEAM_SETUP.md#steam-cloud-saves.\n' >&2
}

# Print common Windows save roots inside a Wine prefix (guidance for Steam Cloud).
steam_cloud_save_roots() {
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  local steam_dir="${1:-}"
  if [[ -z "${steam_dir}" ]]; then
    steam_dir="$(steam_find_steam_dir 2>/dev/null || true)"
  fi
  printf 'Windows save paths (inside Wine prefix):\n'
  printf '  %s/drive_c/users/<user>/Documents/My Games/\n' "${pfx}"
  printf '  %s/drive_c/users/<user>/AppData/Local/\n' "${pfx}"
  printf '  %s/drive_c/users/<user>/AppData/Roaming/\n' "${pfx}"
  if [[ -n "${steam_dir}" ]]; then
    printf 'Steam userdata (cloud metadata):\n'
    printf '  %s/userdata/<account_id>/<appid>/\n' "${steam_dir}"
  fi
  printf 'Native macOS Steam (NOT used by Cosmos Wine launches):\n'
  case "$(uname -s)" in
    Darwin) printf '  %s/Library/Application Support/Steam/userdata/\n' "${HOME}" ;;
    Linux)
      printf '  %s/.local/share/Steam/userdata/\n' "${HOME}"
      printf '  %s/.steam/steam/userdata/\n' "${HOME}"
      ;;
  esac
}

# Read a quoted VDF field from an appmanifest_*.acf file.
steam_acf_read_field() {
  local acf="$1" field="$2"
  [[ -f "${acf}" ]] || return 1
  awk -F'"' -v f="${field}" '$2==f {print $4; exit}' "${acf}"
}

# True when an appmanifest looks like a finished install worth turning into a launcher.
# Skips uninstalled, in-progress downloads, and stale manifests left after library moves.
# Set COSMOS_DETECT_INCLUDE_PARTIAL=1 to treat partial installs as detectable.
steam_acf_is_playable() {
  local acf="$1"
  [[ -f "${acf}" ]] || return 1
  [[ "${COSMOS_DETECT_INCLUDE_PARTIAL:-0}" == "1" ]] && return 0
  [[ -f "${acf}.tmp.save" ]] && return 1

  local flags
  flags="$(steam_acf_read_field "${acf}" "StateFlags")"
  [[ -n "${flags}" && "${flags}" =~ ^[0-9]+$ ]] || return 0

  (( flags & 1 )) && return 1          # Uninstalled
  (( flags & 256 )) && return 1        # UpdateRunning
  (( flags & 2048 )) && return 1       # Uninstalling
  (( flags & 1048576 )) && return 1    # Downloading
  (( flags & 2097152 )) && return 1    # Staging
  (( flags & 4194304 )) && return 1    # Committing
  (( flags & 4 )) || return 1          # FullyInstalled required

  return 0
}

# Locate appmanifest_<appid>.acf under any library folder (first match wins).
steam_find_app_manifest() {
  local steam_dir="$1" appid="$2"
  local steamapps acf
  while IFS= read -r steamapps; do
    acf="${steamapps}/appmanifest_${appid}.acf"
    [[ -f "${acf}" ]] && { printf '%s' "${acf}"; return 0; }
  done < <(steam_collect_steamapps_dirs "${steam_dir}")
  return 1
}

# Verify installdir exists on disk for a manifest. Echoes the common/ path on success.
steam_verify_installdir() {
  local acf="$1"
  [[ -f "${acf}" ]] || return 1
  local steamapps installdir common
  steamapps="$(dirname "${acf}")"
  installdir="$(steam_acf_read_field "${acf}" "installdir")"
  [[ -n "${installdir}" ]] || return 1
  common="${steamapps}/common/${installdir}"
  [[ -d "${common}" ]] || return 1
  printf '%s' "${common}"
}

# Load import_lib scoring helpers when available (same directory as this file).
steam_load_import_lib() {
  declare -F import_find_best_game_exe >/dev/null 2>&1 && return 0
  local here
  here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=scripts/lib/import_lib.sh
  [[ -f "${here}/import_lib.sh" ]] && source "${here}/import_lib.sh"
}

# Find the main game .exe inside a Steam common/<installdir> folder.
steam_find_game_exe() {
  local common_dir="$1" game_name="${2:-}"
  [[ -d "${common_dir}" ]] || return 1
  steam_load_import_lib
  if declare -F import_find_best_game_exe >/dev/null 2>&1; then
    import_find_best_game_exe "${common_dir}" "${game_name}"
    return $?
  fi
  local f base
  while IFS= read -r f; do
    base="$(basename "${f}")"
    if declare -F import_exe_is_helper >/dev/null 2>&1; then
      import_exe_is_helper "${base}" && continue
    fi
    printf '%s' "${f}"
    return 0
  done < <(find "${common_dir}" -type f \( -iname '*.exe' \) 2>/dev/null | head -n 80)
  return 1
}

# Print playable Wine-prefix App IDs from steam_dir (one per line).
steam_collect_wine_playable_appids() {
  local steam_dir="$1"
  local steamapps acf appid
  while IFS= read -r steamapps; do
    [[ -d "${steamapps}" ]] || continue
    shopt -s nullglob
    for acf in "${steamapps}"/appmanifest_*.acf; do
      appid="${acf##*/appmanifest_}"; appid="${appid%.acf}"
      [[ "${appid}" =~ ^[0-9]+$ ]] || continue
      steam_acf_is_playable "${acf}" || continue
      printf '%s\n' "${appid}"
    done
    shopt -u nullglob
  done < <(steam_collect_steamapps_dirs "${steam_dir}")
}

# Verify a Wine Steam install on disk. Prints key=value lines; returns 0 when healthy.
steam_verify_game_install() {
  local steam_dir="$1" appid="$2"
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  local acf common exe rel name
  printf 'appid=%s\n' "${appid}"
  acf="$(steam_find_app_manifest "${steam_dir}" "${appid}" 2>/dev/null || true)"
  if [[ -z "${acf}" ]]; then
    printf 'installdir_ok=0\nexe_ok=0\nstatus=missing_manifest\n'
    return 1
  fi
  common="$(steam_verify_installdir "${acf}" 2>/dev/null || true)"
  if [[ -z "${common}" ]]; then
    printf 'installdir_ok=0\nexe_ok=0\nstatus=missing_installdir\n'
    return 1
  fi
  printf 'installdir_ok=1\n'
  printf 'common_path=%s\n' "${common}"
  name="$(steam_acf_read_field "${acf}" "name")"
  exe="$(steam_find_game_exe "${common}" "${name}" 2>/dev/null || true)"
  if [[ -n "${exe}" ]]; then
    printf 'exe_ok=1\n'
    printf 'game_exe=%s\n' "${exe}"
    rel="${exe#${pfx}/}"
    [[ "${rel}" != "${exe}" ]] && printf 'game_exe_rel=%s\n' "${rel}"
    printf 'status=ok\n'
    return 0
  fi
  printf 'exe_ok=0\nstatus=missing_exe\n'
  return 1
}

# Count installed vs broken Wine Steam games. Prints games_installed / games_broken lines.
steam_inventory_counts() {
  local steam_dir="$1"
  local total=0 broken=0 appid
  [[ -n "${steam_dir}" && -d "${steam_dir}" ]] || {
    printf 'games_installed=0\n'
    printf 'games_broken=0\n'
    return 0
  }
  while IFS= read -r appid || [[ -n "${appid}" ]]; do
    [[ -n "${appid}" ]] || continue
    total=$((total + 1))
    steam_verify_game_install "${steam_dir}" "${appid}" >/dev/null 2>&1 || broken=$((broken + 1))
  done < <(steam_collect_wine_playable_appids "${steam_dir}")
  printf 'games_installed=%s\n' "${total}"
  printf 'games_broken=%s\n' "${broken}"
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
  # Steam can auto-start during silent install and leave Chromium locks behind.
  pkill -f "${pfx}/drive_c/Program Files \\(x86\\)/Steam" 2>/dev/null || true
  pkill -f "${pfx}/drive_c/Program Files/Steam" 2>/dev/null || true
  sleep 1
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

# Machine-readable Steam prefix health (key=value lines) for dashboard and CI.
steam_health_lines() {
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  local prefix_ok=0 steam_ok=0 mingw_ok=0 wrapper_ok=0 wrapper_pending=0
  local native_scan=0 dual_count=0 userdata_ok=1 cloud_log_warn=0
  local steam_exe="" steam_dir="" dual_csv="" log_file="" cef_root target

  [[ -f "${pfx}/system.reg" ]] && prefix_ok=1

  steam_exe="$(steam_find_exe_candidate 2>/dev/null || true)"
  if [[ -n "${steam_exe}" ]] && steam_exe_is_valid "${steam_exe}"; then
    steam_ok=1
  fi

  if steam_find_mingw_gcc >/dev/null 2>&1; then
    mingw_ok=1
  fi

  if [[ "${COSMOS_STEAM_WEBHELPER_WRAPPER:-1}" == "1" && "${steam_ok}" -eq 1 ]]; then
    cef_root="${pfx}/drive_c/Program Files (x86)/Steam/bin/cef"
    if [[ -d "${cef_root}" ]]; then
      while IFS= read -r -d '' target; do
        [[ -f "${target}" ]] || continue
        if steam_is_wrapper_like "${target}"; then
          wrapper_ok=1
          break
        fi
      done < <(find "${cef_root}" -type f -name 'steamwebhelper.exe' -print0 2>/dev/null)
      (( wrapper_ok )) || wrapper_pending=1
    else
      wrapper_pending=1
    fi
  fi

  [[ "${COSMOS_STEAM_NATIVE_SCAN:-0}" == "1" ]] && native_scan=1

  steam_dir="$(steam_find_steam_dir 2>/dev/null || true)"
  if [[ -n "${steam_dir}" ]]; then
    [[ -d "${steam_dir}/userdata" ]] || userdata_ok=0
    dual_csv="$(steam_dual_install_appids "${steam_dir}" | paste -sd, - 2>/dev/null || true)"
    if [[ -n "${dual_csv}" ]]; then
      dual_count="$(printf '%s' "${dual_csv}" | awk -F, '{print NF}')"
    fi
  fi

  log_file="${COSMOS_LAUNCH_LOG:-}"
  if [[ -z "${log_file}" ]]; then
    log_file="${COSMOS_SUPPORT_DIR:-${HOME}/Library/Application Support/Cosmos}/logs/steam-launch.log"
  fi
  if [[ -f "${log_file}" ]]; then
    local tail_blob
    tail_blob="$(tail -n 400 "${log_file}" 2>/dev/null || true)"
    if printf '%s' "${tail_blob}" | grep -Eiq \
      'Unable to [Ss]ync|unable to sync|cloud.*out of sync|Steam Cloud|SteamRemoteStorage|remotecache|failed to resolve path'; then
      cloud_log_warn=1
    fi
  fi

  printf 'prefix_initialized=%s\n' "${prefix_ok}"
  printf 'steam_installed=%s\n' "${steam_ok}"
  printf 'mingw_available=%s\n' "${mingw_ok}"
  printf 'webhelper_wrapper=%s\n' "${wrapper_ok}"
  printf 'webhelper_wrapper_pending=%s\n' "${wrapper_pending}"
  printf 'native_scan_enabled=%s\n' "${native_scan}"
  printf 'dual_install_count=%s\n' "${dual_count}"
  [[ -n "${dual_csv}" ]] && printf 'dual_install_appids=%s\n' "${dual_csv}"
  printf 'userdata_present=%s\n' "${userdata_ok}"
  printf 'cloud_log_warning=%s\n' "${cloud_log_warn}"

  if [[ -n "${steam_dir}" ]]; then
    steam_inventory_counts "${steam_dir}"
  else
    printf 'games_installed=0\n'
    printf 'games_broken=0\n'
  fi
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
