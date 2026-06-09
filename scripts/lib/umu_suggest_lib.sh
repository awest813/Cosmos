#!/usr/bin/env bash
# UMU / protonfix → Cosmos recipe suggestions for repair diagnose.

umu_suggest_recipes() {
  local appid="$1"
  [[ "${appid}" =~ ^[0-9]+$ ]] || return 1
  local py="${SCRIPT_DIR:-}/scripts/umu_suggest_recipes.py"
  [[ -f "${py}" ]] || return 1
  command -v python3 >/dev/null 2>&1 || return 1

  local args=(--repo "${SCRIPT_DIR:-.}")
  if [[ -n "${COSMOS_UMU_HINT_FIXTURE:-}" && -f "${COSMOS_UMU_HINT_FIXTURE}" ]]; then
    args+=(--fixture "${COSMOS_UMU_HINT_FIXTURE}")
  elif [[ "${COSMOS_DIAGNOSE_FETCH_UMU:-0}" != "1" ]]; then
    args+=(--offline)
  fi
  python3 "${py}" "${appid}" "${args[@]}"
}
