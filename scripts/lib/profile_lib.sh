#!/usr/bin/env bash
# Minimal YAML profile reader for Cosmos v0 profiles (no PyYAML required).
# Supports top-level scalar keys and settings.* scalars used by profile.command.

# Store subfolders that ship curated profiles (excludes profiles/drafts/).
PROFILE_SHIPPED_STORES=(steam gog itch battlenet standalone)

# Print one shipped profile path per line under ${root}/ (never drafts/).
profile_shipped_paths() {
  local root="$1" store f
  shopt -s nullglob
  for store in "${PROFILE_SHIPPED_STORES[@]}"; do
    [[ -d "${root}/${store}" ]] || continue
    for f in "${root}/${store}"/*.yaml "${root}/${store}"/*.yml; do
      [[ -f "${f}" ]] && printf '%s\n' "${f}"
    done
  done
  shopt -u nullglob
}

profile_get_scalar() {
  local file="$1" key="$2"
  awk -v want="${key}" '
    BEGIN { in_env=0 }
    /^[[:space:]]*#/ { next }
    /^settings:[[:space:]]*$/ { in_settings=1; next }
    /^[[:alpha:]_][[:alnum:]_]*:[[:space:]]*/ {
      if (in_settings && $0 ~ /^  env:/) { in_env=1; next }
      if (in_settings && $0 !~ /^  /) { in_settings=0; in_env=0 }
      if (!in_settings) {
        split($0, a, ":")
        k=a[1]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
        if (k == want) {
          val=$0
          sub(/^[^:]*:[[:space:]]*/, "", val)
          gsub(/^["'\'']|["'\'']$/, "", val)
          print val
          exit
        }
      }
    }
    in_settings && !in_env && $0 ~ /^  [a-z_]+:/ {
      split($0, a, ":")
      k=a[1]; gsub(/^[[:space:]]+/, "", k)
      full="settings." want
      if (k == substr(want, 10)) {
        val=$0; sub(/^[^:]*:[[:space:]]*/, "", val)
        gsub(/^["'\'']|["'\'']$/, "", val)
        if (val == "true") val="1"
        if (val == "false") val="0"
        print val
        exit
      }
    }
  ' "${file}" 2>/dev/null
}

profile_get_env_line() {
  local file="$1" env_key="$2"
  awk -v want="${env_key}" '
    /^settings:/ { in_settings=1; next }
    in_settings && /^  env:/ { in_env=1; next }
    in_env && /^    / {
      line=$0; sub(/^    /, "", line)
      split(line, a, ":")
      k=a[1]; gsub(/[[:space:]]+$/, "", k)
      if (k == want) {
        val=line; sub(/^[^:]*:[[:space:]]*/, "", val)
        gsub(/^["'\'']|["'\'']$/, "", val)
        print val
        exit
      }
    }
    in_env && /^  [a-z]/ && $0 !~ /^    / { in_env=0 }
    /^[a-z]/ && $0 !~ /^  / { in_settings=0; in_env=0 }
  ' "${file}" 2>/dev/null
}

profile_list_dependencies() {
  local file="$1"
  awk '/^dependencies:/{flag=1;next} /^[a-zA-Z_]/ && flag{exit} flag && /^  - /{sub(/^  - /,""); gsub(/["'\'']/, ""); print}' "${file}"
}

profile_list_fixes() {
  local file="$1"
  awk '/^fixes:/{flag=1;next} /^[a-zA-Z_]/ && flag{exit} flag && /^  - /{sub(/^  - /,""); gsub(/["'\'']/, ""); print}' "${file}"
}

profile_list_tags() {
  local file="$1"
  awk '/^tags:/{flag=1;next} /^[a-zA-Z_]/ && flag{exit} flag && /^  - /{sub(/^  - /,""); gsub(/["'\'']/, ""); print}' "${file}"
}

profile_has_multiplayer_tag() {
  local file="$1" tag
  while IFS= read -r tag; do
    [[ -n "${tag}" ]] || continue
    case "${tag}" in
      co-op|online|lan|pvp) return 0 ;;
    esac
  done < <(profile_list_tags "${file}")
  return 1
}

profile_find_by_appid() {
  local root="$1" appid="$2"
  local f
  while IFS= read -r f; do
    [[ -n "${f}" ]] || continue
    if grep -qE "^steam_appid:[[:space:]]*${appid}[[:space:]]*$" "${f}" 2>/dev/null; then
      printf '%s\n' "${f}"
      return 0
    fi
  done < <(profile_shipped_paths "${root}")
  return 1
}

profile_get_notes() {
  local file="$1"
  awk '
    /^notes:[[:space:]]*/ {
      val=$0; sub(/^notes:[[:space:]]*/, "", val)
      gsub(/^["'\'']|["'\'']$/, "", val)
      print val
      exit
    }
    /^notes:[[:space:]]*$/ { multiline=1; next }
    multiline && /^  / {
      line=$0; sub(/^  /, "", line)
      if (notes != "") notes = notes " "
      notes = notes line
      next
    }
    multiline && !/^  / { print notes; exit }
    END { if (multiline) print notes }
  ' "${file}" 2>/dev/null
}

# Compatibility status for a Steam App ID, read from the curated profile under
# ${root} (e.g. profiles/). Prints the status (platinum|gold|…|broken|blocked)
# and returns 0, or returns 1 when no profile matches the App ID.
profile_status_for_appid() {
  local root="$1" appid="$2" file
  file="$(profile_find_by_appid "${root}" "${appid}")" || return 1
  profile_get_scalar "${file}" status
}

# Emit a pre-launch heads-up line for known-bad statuses and return 0; for
# playable/good statuses print nothing and return 1. This keeps users from being
# surprised by anti-cheat/DRM blockers — the macOS equivalent of a ProtonDB
# "Borked"/"Blocked" badge. Pure string logic, so it is easy to unit-test.
profile_compat_warning() {
  local status="$1" name="${2:-this game}" notes="${3:-}"
  case "${status}" in
    blocked)
      printf 'WARNING: %s is marked BLOCKED on macOS (anti-cheat, DRM, or an unsupported CPU feature). It almost certainly will not run.' "${name}"
      ;;
    broken)
      printf 'WARNING: %s is marked BROKEN on macOS — it is not currently expected to work.' "${name}"
      ;;
    *)
      return 1
      ;;
  esac
  [[ -n "${notes}" ]] && printf ' Note: %s' "${notes}"
  printf '\n'
  return 0
}

# Write cosmos_configs/overrides/<appid>.env from a v0 YAML profile.
profile_export_override_to() {
  local file="$1" appid="$2" out="$3"
  [[ -f "${file}" ]] || return 1
  appid="${appid:-$(profile_get_scalar "${file}" steam_appid)}"
  [[ "${appid}" =~ ^[0-9]+$ ]] || return 1
  mkdir -p "$(dirname -- "${out}")"
  local backend windows retina sync_mode esync
  backend="$(profile_get_scalar "${file}" recommended_backend)"
  windows="$(profile_get_scalar "${file}" settings.windows_version)"
  retina="$(profile_get_scalar "${file}" settings.retina)"
  sync_mode="$(profile_get_scalar "${file}" settings.sync_mode)"
  esync="$(profile_get_scalar "${file}" settings.esync)"
  if [[ -z "${sync_mode}" && ( "${esync}" == "1" || "${esync}" == "true" ) ]]; then
    sync_mode="esync"
  fi
  {
    printf '# Generated from %s\n' "${file}"
    [[ -n "${backend}" ]] && printf 'COSMOS_BACKEND=%s\n' "${backend}"
    [[ -n "${windows}" ]] && printf 'WINDOWS_VERSION=%s\n' "${windows}"
    [[ "${retina}" == "1" || "${retina}" == "true" ]] && printf 'WINE_RETINA_MODE=1\n'
    case "${sync_mode}" in
      esync|msync) printf 'COSMOS_SYNC_MODE=%s\n' "${sync_mode}" ;;
    esac
    local k v
    for k in DXMT_CONFIG STEAM_GAME_ARGS WINEDLLOVERRIDES; do
      v="$(profile_get_env_line "${file}" "${k}")"
      [[ -n "${v}" ]] && printf '%s=%s\n' "${k}" "${v}"
    done
  } > "${out}"
  return 0
}
