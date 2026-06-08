#!/usr/bin/env bash
# Minimal YAML profile reader for Cosmos v0 profiles (no PyYAML required).
# Supports top-level scalar keys and settings.* scalars used by profile.command.

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

profile_find_by_appid() {
  local root="$1" appid="$2"
  local f
  shopt -s nullglob
  for f in "${root}"/*/*.yaml "${root}"/*/*.yml; do
    [[ -f "${f}" ]] || continue
    if grep -qE "^steam_appid:[[:space:]]*${appid}[[:space:]]*$" "${f}" 2>/dev/null; then
      printf '%s\n' "${f}"
      shopt -u nullglob
      return 0
    fi
  done
  shopt -u nullglob
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

# Write cosmos_configs/overrides/<appid>.env from a v0 YAML profile.
profile_export_override_to() {
  local file="$1" appid="$2" out="$3"
  [[ -f "${file}" ]] || return 1
  appid="${appid:-$(profile_get_scalar "${file}" steam_appid)}"
  [[ "${appid}" =~ ^[0-9]+$ ]] || return 1
  mkdir -p "$(dirname -- "${out}")"
  local backend windows retina
  backend="$(profile_get_scalar "${file}" recommended_backend)"
  windows="$(profile_get_scalar "${file}" settings.windows_version)"
  retina="$(profile_get_scalar "${file}" settings.retina)"
  {
    printf '# Generated from %s\n' "${file}"
    [[ -n "${backend}" ]] && printf 'COSMOS_BACKEND=%s\n' "${backend}"
    [[ -n "${windows}" ]] && printf 'WINDOWS_VERSION=%s\n' "${windows}"
    [[ "${retina}" == "1" || "${retina}" == "true" ]] && printf 'WINE_RETINA_MODE=1\n'
    local k v
    for k in DXMT_CONFIG STEAM_GAME_ARGS; do
      v="$(profile_get_env_line "${file}" "${k}")"
      [[ -n "${v}" ]] && printf '%s=%s\n' "${k}" "${v}"
    done
  } > "${out}"
  return 0
}
