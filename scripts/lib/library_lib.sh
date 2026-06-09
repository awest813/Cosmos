#!/usr/bin/env bash
# Game library filesystem — standardized install paths and unified registry.
#
# Cosmos-managed installs live under:
#   <prefix>/drive_c/Games/<store>/<slug>/
#
# A derived manifest is written to:
#   ~/Library/Application Support/Cosmos/library/manifest.json
#
# Source from repo scripts:
#   source "${SCRIPT_DIR}/scripts/lib/library_lib.sh"

LIBRARY_MANIFEST_VERSION=1
LIBRARY_GAMES_ROOT_REL="drive_c/Games"

library_support_dir() {
  printf '%s' "${COSMOS_SUPPORT_DIR:-$HOME/Library/Application Support/Cosmos}"
}

library_dir() {
  printf '%s/library' "$(library_support_dir)"
}

library_manifest_path() {
  printf '%s/manifest.json' "$(library_dir)"
}

# Prefix-relative Cosmos-managed games root (drive_c/Games).
library_games_root_rel() {
  printf '%s' "${LIBRARY_GAMES_ROOT_REL}"
}

# Absolute host path to drive_c/Games inside a Wine prefix.
library_games_root() {
  local pfx="$1"
  printf '%s/%s' "${pfx}" "$(library_games_root_rel)"
}

# Absolute host path for a Cosmos-managed install: drive_c/Games/<store>/<slug>.
library_install_dir() {
  local pfx="$1" store="$2" slug="$3"
  printf '%s/%s/%s/%s' "${pfx}" "$(library_games_root_rel)" "${store}" "${slug}"
}

# Prefix-relative install path for launcher configs.
library_install_dir_rel() {
  local store="$1" slug="$2"
  printf '%s/%s/%s' "$(library_games_root_rel)" "${store}" "${slug}"
}

library_ensure_dirs() {
  local pfx="${1:-}"
  mkdir -p "$(library_dir)"
  if [[ -n "${pfx}" ]]; then
    mkdir -p "$(library_games_root "${pfx}")"
  fi
}

library_store_from_conf_basename() {
  local base="$1"
  case "${base}" in
    steam-*) printf 'steam' ;;
    standalone-*) printf 'standalone' ;;
    itch-*) printf 'itch' ;;
    battlenet-*) printf 'battlenet' ;;
    epic-*) printf 'epic' ;;
    gog-*) printf 'gog' ;;
    *) printf 'unknown' ;;
  esac
}

library_read_conf_field() {
  local conf="$1" field="$2"
  [[ -f "${conf}" ]] || return 1
  sed -n "s/^${field}=\"\\(.*\\)\"$/\\1/p" "${conf}" | head -n1
}

library_slug_from_conf_basename() {
  local base="$1" store slug
  store="$(library_store_from_conf_basename "${base}")"
  slug="${base#${store}-}"
  slug="${slug%.conf}"
  printf '%s' "${slug}"
}

library_make_game_id() {
  local store="$1" key="$2"
  printf '%s-%s' "${store}" "${key}"
}

library_slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# Resolve install_path for a launcher config entry.
library_resolve_install_path() {
  local pfx="$1" store="$2" slug="$3" exe_path="${4:-}" conf="${5:-}"
  local install_path="" acf appid steam_dir

  case "${store}" in
    steam)
      appid="$(library_read_conf_field "${conf}" "STEAM_GAME_ID" 2>/dev/null || true)"
      [[ -n "${appid}" ]] || appid="${slug%%-*}"
      if [[ -n "${appid}" && "${appid}" =~ ^[0-9]+$ ]]; then
        steam_dir="$(steam_find_steam_dir 2>/dev/null || true)"
        if [[ -n "${steam_dir}" ]]; then
          acf="$(steam_find_app_manifest "${steam_dir}" "${appid}" 2>/dev/null || true)"
          if [[ -n "${acf}" ]]; then
            install_path="$(steam_verify_installdir "${acf}" 2>/dev/null || true)"
          fi
        fi
      fi
      ;;
    itch|standalone|gog)
      if [[ -n "${exe_path}" ]]; then
        if [[ "${exe_path}" == drive_c/* ]]; then
          install_path="${pfx}/${exe_path%/*}"
        elif [[ "${exe_path}" == "${pfx}"/* ]]; then
          install_path="${exe_path%/*}"
        fi
      fi
      local managed
      managed="$(library_install_dir "${pfx}" "${store}" "${slug}")"
      if [[ -d "${managed}" ]]; then
        install_path="${managed}"
      fi
      ;;
    battlenet)
      if [[ -n "${exe_path}" && "${exe_path}" == drive_c/* ]]; then
        install_path="${pfx}/${exe_path%/*}"
      fi
      ;;
    epic)
      if [[ -n "${exe_path}" ]]; then
        if [[ -f "${exe_path}" ]]; then
          install_path="${exe_path%/*}"
        elif [[ "${exe_path}" == drive_c/* && -d "${pfx}/${exe_path%/*}" ]]; then
          install_path="${pfx}/${exe_path%/*}"
        fi
      fi
      ;;
  esac

  [[ -n "${install_path}" ]] && printf '%s' "${install_path}"
}

# Print TSV: id, store, title, slug, app_id, install_path, exe_path, launcher_conf, managed_by
library_collect_from_configs() {
  local configs_dir="$1" pfx="$2" bottle="${3:-}"
  local f base store slug title app_id exe_path install_path id managed_by launcher_conf

  shopt -s nullglob
  for f in \
    "${configs_dir}"/steam-*.conf \
    "${configs_dir}"/standalone-*.conf \
    "${configs_dir}"/itch-*.conf \
    "${configs_dir}"/battlenet-*.conf \
    "${configs_dir}"/epic-*.conf \
    "${configs_dir}"/gog-*.conf; do
    [[ -f "${f}" ]] || continue
    base="$(basename "${f}")"
    [[ "${base}" == "steam.conf" || "${base}" == *-template.conf ]] && continue
    [[ "${base}" == "binding-of-isaac.conf" ]] && continue

    store="$(library_store_from_conf_basename "${base}")"
    slug="$(library_slug_from_conf_basename "${base}")"
    title="$(library_read_conf_field "${f}" "APP_NAME")"
    title="${title% (Cosmos)}"
    exe_path="$(library_read_conf_field "${f}" "GAME_EXE_PATH")"
    app_id="$(library_read_conf_field "${f}" "STEAM_GAME_ID")"
    [[ -z "${app_id}" ]] && app_id="$(library_read_conf_field "${f}" "LEGENDARY_APP_NAME")"

    install_path="$(library_resolve_install_path "${pfx}" "${store}" "${slug}" "${exe_path}" "${f}" || true)"
    managed_by="${store}"
    [[ "${store}" == "steam" ]] && managed_by="steam"
    [[ "${store}" == "epic" ]] && managed_by="legendary"
    [[ "${store}" == "itch" || "${store}" == "standalone" ]] && managed_by="cosmos"

    id="$(library_make_game_id "${store}" "${slug}")"
    launcher_conf="${base}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${id}" "${store}" "${title}" "${slug}" "${app_id}" \
      "${install_path}" "${exe_path}" "${launcher_conf}" "${managed_by}"
  done
  shopt -u nullglob
}

# Print TSV rows for installed Steam games not already covered by a launcher config.
library_collect_steam_only() {
  local pfx="$1" configs_dir="$2"
  local steam_dir steamapps acf appid name slug install_path id found c
  local -a covered=()

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    covered+=("${line}")
  done < <(library_collect_from_configs "${configs_dir}" "${pfx}" | awk -F'\t' '$2=="steam" {print $5}')

  WINEPREFIX="${pfx}" steam_dir="$(steam_find_steam_dir 2>/dev/null || true)"
  [[ -n "${steam_dir}" ]] || return 0

  while IFS= read -r steamapps; do
    [[ -d "${steamapps}" ]] || continue
    shopt -s nullglob
    for acf in "${steamapps}"/appmanifest_*.acf; do
      appid="${acf##*/appmanifest_}"; appid="${appid%.acf}"
      [[ "${appid}" =~ ^[0-9]+$ ]] || continue
      found=0
      for c in ${covered[@]+"${covered[@]}"}; do
        [[ "${c}" == "${appid}" ]] && { found=1; break; }
      done
      (( found )) && continue
      steam_acf_is_playable "${acf}" || continue
      name="$(steam_acf_read_field "${acf}" "name")"
      [[ -n "${name}" ]] || name="Steam App ${appid}"
      slug="$(library_slugify "${name}")"
      install_path="$(steam_verify_installdir "${acf}" 2>/dev/null || true)"
      id="$(library_make_game_id "steam" "${appid}")"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${id}" "steam" "${name}" "${slug}" "${appid}" \
        "${install_path}" "" "" "steam"
    done
    shopt -u nullglob
  done < <(steam_collect_steamapps_dirs "${steam_dir}")
}

# Aggregate all games as TSV.
library_collect_all() {
  local configs_dir="$1" pfx="$2" bottle="${3:-}"
  library_collect_from_configs "${configs_dir}" "${pfx}" "${bottle}"
  library_collect_steam_only "${pfx}" "${configs_dir}"
}

library_emit_json() {
  local configs_dir="$1" pfx="$2" bottle="${3:-}"
  command -v python3 >/dev/null 2>&1 || return 1
  library_collect_all "${configs_dir}" "${pfx}" "${bottle}" | python3 -c '
import json, sys
from datetime import datetime, timezone

bottle = sys.argv[1]
prefix = sys.argv[2]
rows = []
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    parts = line.split("\t", 8)
    while len(parts) < 9:
        parts.append("")
    gid, store, title, slug, app_id, install_path, exe_path, launcher_conf, managed_by = parts
    rows.append({
        "id": gid,
        "store": store,
        "title": title,
        "slug": slug,
        "app_id": app_id or None,
        "install_path": install_path or None,
        "exe_path": exe_path or None,
        "launcher_conf": launcher_conf or None,
        "managed_by": managed_by,
        "bottle": bottle or None,
    })
print(json.dumps({
    "version": 1,
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "bottle": bottle or None,
    "prefix": prefix,
    "games": rows,
}, indent=2))
' "${bottle}" "${pfx}"
}

library_write_manifest() {
  local configs_dir="$1" pfx="$2" bottle="${3:-}"
  local out
  library_ensure_dirs "${pfx}"
  out="$(library_manifest_path)"
  library_emit_json "${configs_dir}" "${pfx}" "${bottle}" > "${out}"
  printf '%s' "${out}"
}

library_read_manifest_json() {
  local manifest
  manifest="$(library_manifest_path)"
  [[ -f "${manifest}" ]] || return 1
  cat "${manifest}"
}

library_print_list() {
  local configs_dir="$1" pfx="$2" bottle="${3:-}"
  local line id store title install_path launcher_conf
  while IFS=$'\t' read -r id store title _slug _app_id install_path _exe launcher_conf _managed; do
    [[ -n "${id}" ]] || continue
    printf '  %-10s %-36s %s\n' "[${store}]" "${title}" "${install_path:-${launcher_conf:-no path}}"
  done < <(library_collect_all "${configs_dir}" "${pfx}" "${bottle}" | sort -t$'\t' -k3)
}
