#!/usr/bin/env bash
# Log and prefix diagnostics for repair.command (sourced, not executed directly).

DIAG_SEEN=""
DIAG_LINES=()
DIAG_SUGGESTIONS=()

repair_diagnose_reset() {
  DIAG_SEEN=""
  DIAG_LINES=()
  DIAG_SUGGESTIONS=()
}

repair_diagnose_note() {
  local key="$1" text="$2"
  case "${DIAG_SEEN}" in
    *"|${key}|"*) return 0 ;;
  esac
  DIAG_SEEN="${DIAG_SEEN}|${key}|"
  DIAG_LINES+=("${text}")
}

# Record a one-click recipe suggestion (dep:id or fix:id).
repair_diagnose_suggest() {
  local kind="$1" id="$2" text="$3"
  local token="${kind}:${id}"
  repair_diagnose_note "${kind}-${id}" "${text}"
  case " ${DIAG_SUGGESTIONS[*]} " in
    *" ${token} "*) return 0 ;;
  esac
  DIAG_SUGGESTIONS+=("${token}")
}

repair_resolve_launch_log() {
  local support="${COSMOS_SUPPORT_DIR:-$HOME/Library/Application Support/Cosmos}"
  if [[ -n "${COSMOS_LOG:-}" ]]; then
    printf '%s' "${COSMOS_LOG}"
    return 0
  fi
  if [[ -n "${COSMOS_BOTTLE:-}" ]]; then
    local dir="${support}/Bottles/${COSMOS_BOTTLE}/logs/launch.log"
    printf '%s' "${dir}"
    return 0
  fi
  printf '%s' "${support}/logs/steam-launch.log"
}

repair_diagnose_prefix_health() {
  local pfx="${WINEPREFIX:?WINEPREFIX required}"
  if [[ ! -d "${pfx}" ]]; then
    repair_diagnose_note prefix-missing \
      "[prefix] No Wine prefix at ${pfx}
  Try: ./run.command --setup-steam"
    return
  fi
  if [[ ! -f "${pfx}/system.reg" ]]; then
    repair_diagnose_note prefix-empty \
      "[prefix] Prefix directory exists but is not initialized
  Try: ./run.command --setup-steam"
    return
  fi
  local steam_candidate=""
  if [[ -f "${pfx}/drive_c/Program Files (x86)/Steam/steam.exe" ]]; then
    steam_candidate="${pfx}/drive_c/Program Files (x86)/Steam/steam.exe"
  elif [[ -f "${pfx}/drive_c/Program Files/Steam/steam.exe" ]]; then
    steam_candidate="${pfx}/drive_c/Program Files/Steam/steam.exe"
  fi

  if [[ -z "${steam_candidate}" ]]; then
    local steam_hint="./run.command --install-steam"
    if [[ -d "${pfx}/drive_c/Program Files (x86)/Steam" \
       || -d "${pfx}/drive_c/Program Files/Steam" ]]; then
      repair_diagnose_suggest fix reinstall_steam \
        "[prefix] Steam is not installed in this prefix
  Try: ./repair.command apply-fix reinstall_steam"
    else
      repair_diagnose_note steam-missing \
        "[prefix] Steam is not installed in this prefix
  Try: ${steam_hint}"
    fi
  elif declare -F steam_exe_is_valid >/dev/null 2>&1 && ! steam_exe_is_valid "${steam_candidate}"; then
    repair_diagnose_suggest fix reinstall_steam \
      "[prefix] Steam install looks corrupt (steam.exe is missing or invalid)
  Try: ./repair.command apply-fix reinstall_steam"
  fi
  if pgrep -f "wineserver.*${pfx}" >/dev/null 2>&1; then
    repair_diagnose_suggest fix kill_wine \
      "[prefix] Wine is still running for this prefix (can block launches)
  Try: ./repair.command apply-fix kill_wine"
  fi
}

repair_diagnose_umu_hints() {
  local appid="${COSMOS_PROFILE_APPID:-${STEAM_APPID:-}}"
  [[ "${appid}" =~ ^[0-9]+$ ]] || return 0
  # shellcheck disable=SC1091
  [[ -f "${SCRIPT_DIR}/scripts/lib/umu_suggest_lib.sh" ]] \
    && source "${SCRIPT_DIR}/scripts/lib/umu_suggest_lib.sh" 2>/dev/null || return 0

  local line kind id
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    kind="${line%% *}"
    id="${line#* }"
    case "${kind}:${id}" in
      dep:*)
        repair_diagnose_suggest dep "${id}" \
          "[umu] Proton/UMU port hint suggests dependency ${id}
  Try: ./repair.command install-dep ${id}"
        ;;
      fix:*)
        repair_diagnose_suggest fix "${id}" \
          "[umu] Proton/UMU port hint suggests fix ${id}
  Try: ./repair.command apply-fix ${id}"
        ;;
    esac
  done < <(umu_suggest_recipes "${appid}" 2>/dev/null || true)
}

repair_diagnose_profile_hints() {
  local appid="${COSMOS_PROFILE_APPID:-${STEAM_APPID:-}}"
  [[ "${appid}" =~ ^[0-9]+$ ]] || return 0
  local profiles_root="${SCRIPT_DIR:-.}/profiles"
  [[ -d "${profiles_root}" ]] || return 0
  # shellcheck disable=SC1091
  [[ -f "${SCRIPT_DIR}/scripts/lib/profile_lib.sh" ]] \
    && source "${SCRIPT_DIR}/scripts/lib/profile_lib.sh" 2>/dev/null || return 0
  local pf
  pf="$(profile_find_by_appid "${profiles_root}" "${appid}")" || return 0
  local name deps fixes
  name="$(profile_get_scalar "${pf}" name)"
  deps="$(profile_list_dependencies "${pf}" | tr '\n' ' ')"
  fixes="$(profile_list_fixes "${pf}" | tr '\n' ' ')"
  if [[ -n "${deps}${fixes}" ]]; then
    repair_diagnose_note "profile-${appid}" \
      "[profile] Curated profile for ${name:-App ID ${appid}}
  Try: ./profile.command for-appid ${appid} apply"
  fi
}

repair_diagnose_scan_log() {
  local log_file="$1"
  [[ -f "${log_file}" ]] || return 0
  local blob
  blob="$(tail -n 500 "${log_file}" 2>/dev/null || true)"
  [[ -n "${blob}" ]] || return 0

  if printf '%s' "${blob}" | grep -Eiq 'prefix.*in use|already using this prefix|wineserver.*running'; then
    repair_diagnose_suggest fix kill_wine \
      "[launch] Prefix was in use during launch
  Try: ./repair.command apply-fix kill_wine"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'MSVCP140|VCRUNTIME140|vcrun2015|Visual C\+\+.*2015'; then
    repair_diagnose_suggest dep vcrun2015 \
      "[runtime] Visual C++ 2015 runtime may be missing
  Try: ./repair.command install-dep vcrun2015"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'VCRUNTIME140_1|MSVCP140_1|vcrun2019|Visual C\+\+.*2019'; then
    repair_diagnose_suggest dep vcrun2019 \
      "[runtime] Visual C++ 2019 runtime may be missing
  Try: ./repair.command install-dep vcrun2019"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'mscoree|mscoree\.dll|\.NET Framework|clr\.dll|mscorlib'; then
    repair_diagnose_suggest fix grounded-mscoree-fix \
      "[runtime] .NET / mscoree.dll issues detected (common Unity black screen)
  Try: ./repair.command apply-fix grounded-mscoree-fix
       or: ./repair.command install-dep dotnet48"
    repair_diagnose_note dep-dotnet \
      "[runtime] .NET Framework may be required
  Try: ./repair.command install-dep dotnet48"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'MSVCP100|VCRUNTIME100|vcrun2010|Visual C\+\+.*2010'; then
    repair_diagnose_suggest dep vcrun2010 \
      "[runtime] Visual C++ 2010 runtime may be missing
  Try: ./repair.command install-dep vcrun2010"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'd3dx9|D3DX9_43|d3dx9_43'; then
    repair_diagnose_suggest dep d3dx9 \
      "[runtime] DirectX 9 components may be missing
  Try: ./repair.command install-dep d3dx9"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'shadercache|httpcache|shader.*cache|cache.*corrupt'; then
    repair_diagnose_suggest fix clear_steam_caches \
      "[steam] Shader or HTTP cache issues detected
  Try: ./repair.command apply-fix clear_steam_caches"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'SingletonLock|single.instance|already running|--silent'; then
    repair_diagnose_suggest fix clear_steam_caches \
      "[steam] Steam may be stuck on Chromium single-instance lock
  Try: ./repair.command apply-fix clear_steam_caches"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'Silent install did not finish|invalid steam\.exe|Steam installation appears incomplete'; then
    repair_diagnose_suggest fix reinstall_steam \
      "[steam] Unattended Steam install did not complete
  Try: ./repair.command apply-fix reinstall_steam
       or: COSMOS_STEAM_SILENT=0 ./run.command --install-steam"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'handshake failed|SSL error code|net_error -100|net_error -107'; then
    repair_diagnose_suggest fix fix_steam_ssl \
      "[steam] Chromium TLS handshake failures detected
  Try: ./repair.command apply-fix fix_steam_ssl
       then: ./repair.command apply-fix install_steamwebhelper_wrapper"
    repair_diagnose_suggest fix install_steamwebhelper_wrapper \
      "[steam] Install the steamwebhelper wrapper after fixing SSL
  Try: ./repair.command apply-fix install_steamwebhelper_wrapper"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'black window|steamwebhelper|CEF.*fail|CreateDevice|D3D11'; then
    repair_diagnose_suggest fix install_steamwebhelper_wrapper \
      "[steam] Steam CEF / D3D11 UI issues detected
  Try: ./repair.command apply-fix install_steamwebhelper_wrapper
       COSMOS_BACKEND=dxmt ./repair.command apply-fix set_backend"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'RetinaMode|hidpi|HiDPI|Retina|scaling'; then
    repair_diagnose_suggest fix disable_retina \
      "[display] Retina / scaling issues detected
  Try: ./repair.command apply-fix disable_retina"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'ddraw|DirectDraw'; then
    repair_diagnose_note fix-ddraw \
      "[graphics] DirectDraw / ddraw issues detected
  Try: DLL_OVERRIDE='ddraw=n,b' ./repair.command apply-fix dll_override"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'GPTK_PATH|Game Porting Toolkit|d3dmetal.*not|Could not find d3d11\.dll under GPTK'; then
    repair_diagnose_note backend-gptk \
      "[graphics] D3DMetal / GPTK is not configured
  Try: COSMOS_BACKEND=dxmt ./repair.command apply-fix set_backend
       (or set GPTK_PATH to your Apple Game Porting Toolkit install)"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'DXVK_PATH|MoltenVK|vulkan.*not found|VK_ERROR'; then
    repair_diagnose_note backend-dxvk \
      "[graphics] DXVK / Vulkan / MoltenVK issues detected
  Try: COSMOS_BACKEND=dxmt ./repair.command apply-fix set_backend
       or: COSMOS_BACKEND=wined3d ./repair.command apply-fix set_backend"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'DXMT|d3d11.*fail|Metal.*error|dxgi.*fail|CreateDevice.*fail'; then
    repair_diagnose_note backend-dxmt \
      "[graphics] DXMT / D3D11 translation errors detected
  Try: COSMOS_BACKEND=wined3d ./repair.command apply-fix set_backend
       or: COSMOS_BACKEND=d3dmetal ./repair.command apply-fix set_backend (if GPTK_PATH is set)"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'black screen|fullscreen|borderless|CaptureDisplays'; then
    repair_diagnose_note fix-borderless \
      "[display] Fullscreen / borderless window issues detected
  Try: ./repair.command apply-fix force_borderless"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'intro|bink|video.*skip|FMV'; then
    repair_diagnose_note fix-intro \
      "[launch] Intro / FMV video issues detected
  Try: STEAM_APPID=<id> ./repair.command apply-fix disable_intro_video"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'segmentation fault|SIGSEGV|wine:.*crashed|abort\(\)|stack overflow'; then
    repair_diagnose_suggest fix kill_wine \
      "[crash] Wine or the game crashed — stop lingering processes first
  Try: ./repair.command apply-fix kill_wine"
    repair_diagnose_suggest fix clear_steam_caches \
      "[crash] Clear caches after killing Wine
  Try: ./repair.command apply-fix clear_steam_caches"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'err:module:import_dll|\.dll.*not found|could not load library'; then
    repair_diagnose_suggest dep vcrun2015 \
      "[module] Missing DLL reported in log
  Try: ./repair.command install-dep vcrun2015
       or: DLL_OVERRIDE='<dll>=n,b' ./repair.command apply-fix dll_override"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'prefix.*corrupt|registry.*corrupt|system\.reg'; then
    repair_diagnose_note prefix-corrupt \
      "[prefix] Prefix or registry corruption suspected
  Try: COSMOS_FORCE=1 ./repair.command apply-fix rebuild_prefix"
  fi
}

repair_diagnose_run() {
  local log_file="${1:-}"
  repair_diagnose_reset
  repair_diagnose_prefix_health
  repair_diagnose_profile_hints
  repair_diagnose_umu_hints

  if [[ -z "${log_file}" ]]; then
    log_file="$(repair_resolve_launch_log)"
  fi

  echo "Prefix: ${WINEPREFIX}"
  if [[ -n "${COSMOS_BOTTLE:-}" ]]; then
    echo "Bottle: ${COSMOS_BOTTLE}"
  fi

  if [[ -f "${log_file}" ]]; then
    local size modified=""
    size="$(wc -c <"${log_file}" | tr -d ' ')"
    if command -v stat >/dev/null 2>&1; then
      if modified="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "${log_file}" 2>/dev/null)"; then
        :
      else
        modified="$(stat -c '%y' "${log_file}" 2>/dev/null | cut -d. -f1 || true)"
      fi
    fi
    echo "Log: ${log_file} (${size} bytes${modified:+, ${modified}})"
    repair_diagnose_scan_log "${log_file}"
  else
    echo "Log: (not found at ${log_file})"
    repair_diagnose_note no-log \
      "[info] No launch log yet — run a game, then diagnose again
  Tip: detached launches write to the path above (see run.command --logs)"
  fi

  echo ""
  if ((${#DIAG_LINES[@]} == 0)); then
    echo "No issues detected. If a game still fails, try switching backends:"
    echo "  COSMOS_BACKEND=wined3d ./repair.command apply-fix set_backend"
    return 0
  fi

  echo "Suggested fixes (${#DIAG_LINES[@]}):"
  echo ""
  local item
  for item in "${DIAG_LINES[@]}"; do
    printf '%s\n\n' "${item}"
  done
}

# Print machine-readable suggestions (dep:id / fix:id), one per line.
repair_diagnose_print_suggestions() {
  local item
  for item in "${DIAG_SUGGESTIONS[@]}"; do
    printf '%s\n' "${item}"
  done
}

# Fixes safe to run without extra env vars (used by apply-suggested).
repair_suggestion_is_auto_applicable() {
  local token="$1"
  case "${token}" in
    dep:*) return 0 ;;
    fix:kill_wine|fix:clear_steam_caches|fix:disable_retina|fix:fix_steam_ssl|fix:install_steamwebhelper_wrapper|fix:reinstall_steam|fix:seed_japanese_fonts|fix:grounded-mscoree-fix)
      return 0
      ;;
    *) return 1 ;;
  esac
}
