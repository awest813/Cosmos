#!/usr/bin/env bash
set -euo pipefail

# Cosmos profile loader (roadmap 0.4) — read YAML profiles and apply settings.
# See docs/PROFILE_FORMAT.md and docs/LUTRIS_MAPPING.md.

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
PROFILE_LIB="${SCRIPT_DIR}/scripts/lib/profile_lib.sh"
PROFILES_DIR="${SCRIPT_DIR}/profiles"
COSMOS_SUPPORT_DIR="${COSMOS_SUPPORT_DIR:-$HOME/Library/Application Support/Cosmos}"

# Match detect_steam_games.command / install_cosmos.command config resolution.
resolve_configs_dir() {
  if [[ -n "${COSMOS_CONFIGS_DIR:-}" ]]; then
    printf '%s' "${COSMOS_CONFIGS_DIR}"
    return
  fi
  local bundled="${SCRIPT_DIR}/cosmos_configs"
  if [[ "${SCRIPT_DIR}" == *.app/Contents/Resources ]]; then
    local data="${COSMOS_SUPPORT_DIR}/cosmos_configs"
    mkdir -p "${data}"
    if [[ -d "${bundled}" ]]; then
      cp -Rn "${bundled}/." "${data}/" 2>/dev/null || true
    fi
    printf '%s' "${data}"
    return
  fi
  printf '%s' "${bundled}"
}

CONFIGS_DIR="$(resolve_configs_dir)"
OVERRIDES_DIR="${COSMOS_OVERRIDES_DIR:-${CONFIGS_DIR}/overrides}"

# shellcheck source=scripts/lib/profile_lib.sh
source "${PROFILE_LIB}"

log() { printf "\n==> %s\n" "$1"; }
die() { printf "Error: %s\n" "$1" >&2; exit 1; }

usage() {
  cat <<'EOF'
Cosmos profile manager — v0 YAML profiles under profiles/.

Usage: profile.command <command> [args]

Commands:
  list                          List profiles (store / appid / name).
  show <path-or-id>             Print resolved settings from a profile file.
  validate [path-or-id]         Lint one profile (or all) against the v0 schema
                                and check referenced recipes exist.
  export-override <path> <appid> Write cosmos_configs/overrides/<appid>.env from profile.
  apply <path>                  export-override + install-deps + apply-fixes from profile.
  for-appid <appid> <cmd...>    Run show|apply using the profile matching steam_appid.

Examples:
  profile.command list
  profile.command show profiles/steam/steam-250900-binding-of-isaac.yaml
  profile.command validate
  profile.command export-override profiles/steam/steam-250900-binding-of-isaac.yaml 250900
  profile.command apply profiles/steam/steam-22380-fallout-new-vegas.yaml
EOF
}

resolve_profile() {
  local arg="${1:-}"
  [[ -n "${arg}" ]] || return 1
  if [[ -f "${arg}" ]]; then
    printf '%s' "${arg}"
    return 0
  fi
  local f
  shopt -s nullglob
  for f in "${PROFILES_DIR}"/*/"${arg}".yaml "${PROFILES_DIR}"/*/"${arg}".yml \
           "${PROFILES_DIR}"/*/*"${arg}"*.yaml; do
    [[ -f "${f}" ]] && { printf '%s' "${f}"; shopt -u nullglob; return 0; }
  done
  shopt -u nullglob
  return 1
}

cmd_list() {
  local f store appid name
  shopt -s nullglob
  for f in "${PROFILES_DIR}"/*/*.yaml "${PROFILES_DIR}"/*/*.yml; do
    [[ -f "${f}" ]] || continue
    store="$(profile_get_scalar "${f}" store)"
    appid="$(profile_get_scalar "${f}" steam_appid)"
    name="$(profile_get_scalar "${f}" name)"
    printf '  %-8s %-10s %s\n' "${appid:-"—"}" "${store:-"?"}" "${name:-"${f}"}"
  done
  shopt -u nullglob
}

cmd_show() {
  local file; file="$(resolve_profile "${1:-}")" || die "Profile not found: $1"
  log "Profile: ${file}"
  printf '  id:                  %s\n' "$(profile_get_scalar "${file}" id)"
  printf '  name:                %s\n' "$(profile_get_scalar "${file}" name)"
  printf '  store:               %s\n' "$(profile_get_scalar "${file}" store)"
  printf '  steam_appid:         %s\n' "$(profile_get_scalar "${file}" steam_appid)"
  printf '  status:              %s\n' "$(profile_get_scalar "${file}" status)"
  printf '  recommended_backend: %s\n' "$(profile_get_scalar "${file}" recommended_backend)"
  printf '  windows_version:     %s\n' "$(profile_get_scalar "${file}" settings.windows_version)"
  printf '  retina:              %s\n' "$(profile_get_scalar "${file}" settings.retina)"
  echo "  settings.env:"
  local env_keys="DXMT_CONFIG STEAM_GAME_ARGS COSMOS_BACKEND"
  local k v
  for k in ${env_keys}; do
    v="$(profile_get_env_line "${file}" "${k}")"
    [[ -n "${v}" ]] && printf '    %s=%s\n' "${k}" "${v}"
  done
  echo "  dependencies:"
  profile_list_dependencies "${file}" | sed 's/^/    /' || echo "    (none)"
  echo "  fixes:"
  profile_list_fixes "${file}" | sed 's/^/    /' || echo "    (none)"
  local notes; notes="$(profile_get_notes "${file}")"
  if [[ -n "${notes}" ]]; then
    printf '  notes:               %s\n' "${notes}"
  fi
}

cmd_export_override() {
  local file appid
  file="$(resolve_profile "${1:-}")" || die "Profile not found: $1"
  appid="${2:-$(profile_get_scalar "${file}" steam_appid)}"
  [[ "${appid}" =~ ^[0-9]+$ ]] || die "steam_appid required (arg or in profile)"
  local out="${OVERRIDES_DIR}/${appid}.env"
  profile_export_override_to "${file}" "${appid}" "${out}" \
    || die "Failed to export override for ${appid}"
  echo "Wrote ${out}"
}

cmd_apply() {
  local file; file="$(resolve_profile "${1:-}")" || die "Profile not found: $1"
  local appid; appid="$(profile_get_scalar "${file}" steam_appid)"
  cmd_export_override "${file}" "${appid}"
  if [[ -x "${SCRIPT_DIR}/repair.command" ]]; then
  local dep fix
  while IFS= read -r dep; do
    [[ -n "${dep}" ]] || continue
    "${SCRIPT_DIR}/repair.command" install-dep "${dep}" || true
  done < <(profile_list_dependencies "${file}")
  while IFS= read -r fix; do
    [[ -n "${fix}" ]] || continue
    "${SCRIPT_DIR}/repair.command" apply-fix "${fix}" || true
  done < <(profile_list_fixes "${file}")
  fi
  log "Profile applied. Re-run detect_steam_games.command to refresh launchers if needed."
}

# --- validation -------------------------------------------------------------

# in_set <value> <allowed...> -> 0 if value is one of the allowed words.
in_set() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [[ "${needle}" == "${item}" ]] && return 0
  done
  return 1
}

# validate_one <file> -> prints FAIL lines, returns the number of errors found.
validate_one() {
  local file="$1"
  local errs=0
  err() { printf '  FAIL %s: %s\n' "${file##*/}" "$1" >&2; errs=$((errs + 1)); }

  local id name store status backend
  id="$(profile_get_scalar "${file}" id)"
  name="$(profile_get_scalar "${file}" name)"
  store="$(profile_get_scalar "${file}" store)"
  status="$(profile_get_scalar "${file}" status)"
  backend="$(profile_get_scalar "${file}" recommended_backend)"

  [[ -n "${id}" ]] || err "missing required field: id"
  [[ -n "${name}" ]] || err "missing required field: name"
  [[ -n "${store}" ]] || err "missing required field: store"
  [[ -n "${status}" ]] || err "missing required field: status"
  [[ -n "${backend}" ]] || err "missing required field: recommended_backend"

  if [[ -n "${store}" ]] && ! in_set "${store}" steam gog epic itch battlenet standalone; then
    err "invalid store: ${store}"
  fi
  if [[ -n "${status}" ]] && ! in_set "${status}" \
      platinum gold silver playable bronze broken blocked; then
    err "invalid status: ${status}"
  fi
  if [[ -n "${backend}" ]] && ! in_set "${backend}" \
      recommended d3dmetal dxmt dxvk wined3d; then
    err "invalid recommended_backend: ${backend}"
  fi

  local winver; winver="$(profile_get_scalar "${file}" settings.windows_version)"
  if [[ -n "${winver}" ]] && ! in_set "${winver}" winxp win7 win8 win10 win11; then
    err "invalid settings.windows_version: ${winver}"
  fi

  # store-specific required identifiers
  if [[ "${store}" == "steam" ]]; then
    local appid; appid="$(profile_get_scalar "${file}" steam_appid)"
    if [[ "${appid}" =~ ^[0-9]+$ ]]; then
      # filename convention: steam-<appid>-<slug>.yaml
      local base="${file##*/}"
      [[ "${base}" == steam-"${appid}"-* ]] \
        || err "filename ${base} does not match steam_appid ${appid}"
    else
      err "store: steam requires numeric steam_appid"
    fi
  elif [[ "${store}" == "standalone" || "${store}" == "itch" || "${store}" == "battlenet" ]]; then
    local exe; exe="$(profile_get_scalar "${file}" exe_path)"
    [[ -n "${exe}" ]] || err "store: ${store} requires exe_path"
  fi

  # referenced recipes must exist on disk
  local dep fix
  while IFS= read -r dep; do
    [[ -n "${dep}" ]] || continue
    [[ -f "${SCRIPT_DIR}/recipes/dependencies/${dep}.recipe" ]] \
      || err "unknown dependency recipe: ${dep}"
  done < <(profile_list_dependencies "${file}")
  while IFS= read -r fix; do
    [[ -n "${fix}" ]] || continue
    [[ -f "${SCRIPT_DIR}/recipes/fixes/${fix}.recipe" ]] \
      || err "unknown fix recipe: ${fix}"
  done < <(profile_list_fixes "${file}")

  return "${errs}"
}

cmd_validate() {
  local target="${1:-}"
  local files=()
  if [[ -n "${target}" ]]; then
    local f; f="$(resolve_profile "${target}")" || die "Profile not found: ${target}"
    files=("${f}")
  else
    shopt -s nullglob
    files=("${PROFILES_DIR}"/*/*.yaml "${PROFILES_DIR}"/*/*.yml)
    shopt -u nullglob
  fi
  [[ "${#files[@]}" -gt 0 ]] || die "No profiles found under ${PROFILES_DIR}"

  local bad=0 file
  for file in "${files[@]}"; do
    if validate_one "${file}"; then
      printf '  ok  %s\n' "${file##*/}"
    else
      bad=$((bad + 1))
    fi
  done
  [[ "${bad}" -eq 0 ]] || die "${bad} of ${#files[@]} profile(s) failed validation"
  log "All ${#files[@]} profile(s) valid."
}

main() {
  local cmd="${1:-}"; shift || true
  case "${cmd}" in
    list) cmd_list ;;
    show) cmd_show "${1:-}" ;;
    validate) cmd_validate "${1:-}" ;;
    export-override) cmd_export_override "${1:-}" "${2:-}" ;;
    apply) cmd_apply "${1:-}" ;;
    for-appid)
      local appid="${1:-}"; shift
      local pf
      pf="$(profile_find_by_appid "${PROFILES_DIR}" "${appid}")" \
        || die "No profile for steam_appid ${appid}"
      case "${1:-}" in
        show) cmd_show "${pf}" ;;
        apply) cmd_apply "${pf}" ;;
        *) die "Usage: profile.command for-appid <appid> show|apply" ;;
      esac
      ;;
    ""|--help|-h|help) usage ;;
    *) die "Unknown command: ${cmd}" ;;
  esac
}

main "$@"
