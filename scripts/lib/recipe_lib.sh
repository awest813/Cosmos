#!/usr/bin/env bash
# Shared helpers for Cosmos recipe files (*.recipe) under recipes/.
# Recipes are simple KEY=value files (shell-safe, no eval of arbitrary values).

recipe_load() {
  local file="$1"
  RECIPE_TYPE="" RECIPE_ID="" RECIPE_DESCRIPTION="" RECIPE_WINETRICKS=""
  RECIPE_ACTION="" RECIPE_SCRIPT=""
  [[ -f "${file}" ]] || return 1
  local line key val
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ "${line}" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "${line}" == *=* ]] || continue
    key="${line%%=*}"; key="${key//[[:space:]]/}"
    val="${line#*=}"; val="${val%\"}"; val="${val#\"}"
    case "${key}" in
      TYPE) RECIPE_TYPE="${val}" ;;
      ID) RECIPE_ID="${val}" ;;
      DESCRIPTION) RECIPE_DESCRIPTION="${val}" ;;
      WINETRICKS) RECIPE_WINETRICKS="${val}" ;;
      ACTION) RECIPE_ACTION="${val}" ;;
      SCRIPT) RECIPE_SCRIPT="${val}" ;;
    esac
  done < "${file}"
  [[ -n "${RECIPE_ID}" ]] || return 1
  return 0
}

recipe_list_dir() {
  local dir="$1" kind="$2"
  local f
  shopt -s nullglob
  for f in "${dir}"/*.recipe; do
    recipe_load "${f}" || continue
    [[ "${RECIPE_TYPE}" == "${kind}" ]] || continue
    printf '  %-24s %s\n' "${RECIPE_ID}" "${RECIPE_DESCRIPTION:-"(no description)"}"
  done
  shopt -u nullglob
}
