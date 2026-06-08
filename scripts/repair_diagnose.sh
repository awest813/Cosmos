#!/usr/bin/env bash
# Log and prefix diagnostics for repair.command (sourced, not executed directly).

DIAG_SEEN=""
DIAG_LINES=()

repair_diagnose_reset() {
  DIAG_SEEN=""
  DIAG_LINES=()
}

repair_diagnose_note() {
  local key="$1" text="$2"
  case "${DIAG_SEEN}" in
    *"|${key}|"*) return 0 ;;
  esac
  DIAG_SEEN="${DIAG_SEEN}|${key}|"
  DIAG_LINES+=("${text}")
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
  if [[ ! -f "${pfx}/drive_c/Program Files (x86)/Steam/steam.exe" \
     && ! -f "${pfx}/drive_c/Program Files/Steam/steam.exe" ]]; then
    repair_diagnose_note steam-missing \
      "[prefix] Steam is not installed in this prefix
  Try: ./run.command --setup-steam"
  fi
  if pgrep -f "wineserver.*${pfx}" >/dev/null 2>&1; then
    repair_diagnose_note wineserver-running \
      "[prefix] Wine is still running for this prefix (can block launches)
  Try: ./repair.command apply-fix kill_wine"
  fi
}

repair_diagnose_scan_log() {
  local log_file="$1"
  [[ -f "${log_file}" ]] || return 0
  local blob
  blob="$(tail -n 500 "${log_file}" 2>/dev/null || true)"
  [[ -n "${blob}" ]] || return 0

  if printf '%s' "${blob}" | grep -Eiq 'prefix.*in use|already using this prefix|wineserver.*running'; then
    repair_diagnose_note prefix-busy \
      "[launch] Prefix was in use during launch
  Try: ./repair.command apply-fix kill_wine"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'MSVCP140|VCRUNTIME140|vcrun2015|Visual C\+\+.*2015'; then
    repair_diagnose_note dep-vcrun2015 \
      "[runtime] Visual C++ 2015 runtime may be missing
  Try: ./repair.command install-dep vcrun2015"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'MSVCP100|VCRUNTIME100|vcrun2010|Visual C\+\+.*2010'; then
    repair_diagnose_note dep-vcrun2010 \
      "[runtime] Visual C++ 2010 runtime may be missing
  Try: ./repair.command install-dep vcrun2010"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'd3dx9|D3DX9_43|d3dx9_43'; then
    repair_diagnose_note dep-d3dx9 \
      "[runtime] DirectX 9 components may be missing
  Try: ./repair.command install-dep d3dx9"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'shadercache|httpcache|shader.*cache|cache.*corrupt'; then
    repair_diagnose_note fix-caches \
      "[steam] Shader or HTTP cache issues detected
  Try: ./repair.command apply-fix clear_steam_caches"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'RetinaMode|hidpi|HiDPI|Retina|scaling'; then
    repair_diagnose_note fix-retina \
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
    repair_diagnose_note crash \
      "[crash] Wine or the game crashed
  Try: ./repair.command apply-fix kill_wine
       then: ./repair.command apply-fix clear_steam_caches
       then switch backend: COSMOS_BACKEND=wined3d ./repair.command apply-fix set_backend"
  fi

  if printf '%s' "${blob}" | grep -Eiq 'err:module:import_dll|\.dll.*not found|could not load library'; then
    repair_diagnose_note missing-dll \
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
