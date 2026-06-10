#!/usr/bin/env bash
# Wine runtime path helpers shared by run.command, repair, and status reporting.

wine_default_version() {
  printf '%s' "${WINE_VERSION:-11.8}"
}

wine_default_root() {
  if [[ -n "${WINE_ROOT:-}" ]]; then
    printf '%s' "${WINE_ROOT}"
    return 0
  fi
  printf '%s' "${HOME}/wine-$(wine_default_version)"
}

wine_resolve_app() {
  printf '%s' "$(wine_default_root)/Wine Devel.app"
}

wine_resolve_bin() {
  printf '%s' "$(wine_resolve_app)/Contents/Resources/wine/bin/wine"
}

wine_resolve_wineserver() {
  printf '%s' "$(wine_resolve_app)/Contents/Resources/wine/bin/wineserver"
}

wine_is_installed() {
  [[ -x "$(wine_resolve_bin)" ]]
}

wine_reported_version() {
  local bin
  bin="$(wine_resolve_bin)"
  [[ -x "${bin}" ]] || return 1
  "${bin}" --version 2>/dev/null | head -n1
}

# Machine-readable runtime status (key=value lines).
wine_runtime_status_lines() {
  local chip arch rosetta wine_ok wine_ver wine_report
  chip="$(rosetta_host_arch 2>/dev/null || uname -m)"
  if declare -F rosetta_status_code >/dev/null 2>&1; then
    rosetta="$(rosetta_status_code)"
  else
    rosetta="unknown"
  fi
  wine_ver="$(wine_default_version)"
  if wine_is_installed; then
    wine_ok=1
    wine_report="$(wine_reported_version 2>/dev/null || true)"
  else
    wine_ok=0
    wine_report=""
  fi
  printf 'chip=%s\n' "${chip}"
  printf 'rosetta=%s\n' "${rosetta}"
  printf 'wine_version=%s\n' "${wine_ver}"
  printf 'wine_installed=%s\n' "${wine_ok}"
  printf 'wine_root=%s\n' "$(wine_default_root)"
  printf 'wine_bin=%s\n' "$(wine_resolve_bin)"
  [[ -n "${wine_report}" ]] && printf 'wine_report=%s\n' "${wine_report}"
}
