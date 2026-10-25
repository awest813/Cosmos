#!/usr/bin/env bash
# Apple Silicon wine ports — Sikarugir-style wrappers on Cosmos bottles.
#
# A port is one Windows program opened like a Mac app. The graphics stack
# matches the Sikarugir (cosmosNEW) defaults for Apple Silicon:
#   DXMT on, D9VK on, CNC-DDRAW on, WineD3D on, DXVK off, D3DMetal off.
# D3DMetal is personal-only. Apple's license does not allow it in a port
# you share, and Cosmos never bundles those DLLs.
#
# Keep the resolver in sync with app/WinePort.swift.

# Sentence shared with WinePort.sharedD3DMetalMessage.
port_shared_d3dmetal_error() {
  printf '%s' "Shared ports cannot use D3DMetal. Apple's license does not allow a port you give to someone else to include it."
}

port_no_renderer_error() {
  printf '%s' "Turn on at least one graphics renderer."
}

port_is_on() {
  case "${1:-0}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

# Print 1 or 0. Return 1 when the value is not a recognized flag.
port_normalize_flag() {
  case "${1:-0}" in
    1|true|yes|on) printf '1' ;;
    0|false|no|off|"") printf '0' ;;
    *) return 1 ;;
  esac
}

port_slugify() {
  local name="$1" slug
  slug="$(printf '%s' "${name}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-')"
  while [[ "${slug}" == *--* ]]; do
    slug="${slug//--/-}"
  done
  slug="${slug#-}"
  slug="${slug%-}"
  while [[ -n "${slug}" && ! "${slug}" =~ ^[a-z0-9] ]]; do
    slug="${slug:1}"
  done
  slug="${slug%-}"
  if [[ -z "${slug}" ]]; then
    slug="port"
  fi
  printf '%s' "${slug}"
}

port_validate_slug() {
  local slug="$1"
  [[ -n "${slug}" ]] || return 1
  [[ "${slug}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1
  [[ "${slug}" != *..* ]] || return 1
  return 0
}

port_validate_name() {
  local name="$1"
  [[ -n "${name}" ]] || return 1
  [[ "${name}" != */* && "${name}" != *:* ]] || return 1
  [[ "${name}" != "." && "${name}" != ".." ]] || return 1
  [[ "${name}" != *$'\n'* ]] || return 1
  return 0
}

# Reads PORT_RENDER_* and PORT_DISTRIBUTION. Prints a Cosmos backend:
#   d3dmetal | spockd3d9 | dxmt | dxvk | wined3d
# Returns 1 and writes a user-facing reason to stderr when the stack is invalid.
port_resolve_primary() {
  local dist dxmt d3dmetal dxvk d9vk cnc wined3d
  dist="${PORT_DISTRIBUTION:-personal}"
  [[ -n "${dist}" ]] || dist="personal"
  dxmt="${PORT_RENDER_DXMT:-0}"
  d3dmetal="${PORT_RENDER_D3DMETAL:-0}"
  dxvk="${PORT_RENDER_DXVK:-0}"
  d9vk="${PORT_RENDER_D9VK:-0}"
  cnc="${PORT_RENDER_CNC_DDRAW:-0}"
  wined3d="${PORT_RENDER_WINED3D:-0}"

  if port_is_on "${d3dmetal}"; then
    if [[ "${dist}" == "share" ]]; then
      printf 'Error: %s\n' "$(port_shared_d3dmetal_error)" >&2
      return 1
    fi
    printf '%s' "d3dmetal"
    return 0
  fi
  if port_is_on "${dxmt}" && port_is_on "${d9vk}"; then
    printf '%s' "spockd3d9"
    return 0
  fi
  if port_is_on "${dxmt}"; then
    printf '%s' "dxmt"
    return 0
  fi
  if port_is_on "${dxvk}"; then
    printf '%s' "dxvk"
    return 0
  fi
  if port_is_on "${d9vk}"; then
    printf '%s' "spockd3d9"
    return 0
  fi
  if port_is_on "${wined3d}" || port_is_on "${cnc}"; then
    printf '%s' "wined3d"
    return 0
  fi
  printf 'Error: %s\n' "$(port_no_renderer_error)" >&2
  return 1
}

# Stable renderer list for launch env and the port note.
port_renderers_csv() {
  local out=""
  if port_is_on "${PORT_RENDER_DXMT:-0}"; then out="${out},dxmt"; fi
  if port_is_on "${PORT_RENDER_D3DMETAL:-0}"; then out="${out},d3dmetal"; fi
  if port_is_on "${PORT_RENDER_DXVK:-0}"; then out="${out},dxvk"; fi
  if port_is_on "${PORT_RENDER_D9VK:-0}"; then out="${out},d9vk"; fi
  if port_is_on "${PORT_RENDER_CNC_DDRAW:-0}"; then out="${out},cnc-ddraw"; fi
  if port_is_on "${PORT_RENDER_WINED3D:-0}"; then out="${out},wined3d"; fi
  out="${out#,}"
  printf '%s' "${out}"
}

port_require_apple_silicon() {
  local os arch
  if [[ "${COSMOS_PORT_SKIP_ARCH:-0}" == "1" ]]; then
    return 0
  fi
  os="$(uname -s)"
  arch="$(uname -m)"
  if [[ "${os}" != "Darwin" || "${arch}" != "arm64" ]]; then
    printf 'Error: %s\n' "Cosmos ports are for Apple Silicon Macs (macOS 14.6 or later). This machine is ${os} ${arch}." >&2
    return 1
  fi
}

port_get_setting() {
  local conf="$1" key="$2" line val
  [[ -f "${conf}" ]] || return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" == "${key}="* ]]; then
      val="${line#*=}"
      val="${val%\"}"
      val="${val#\"}"
      printf '%s' "${val}"
      return 0
    fi
  done < "${conf}"
}

port_set_setting() {
  local conf="$1" key="$2" val="$3"
  local tmp found=0 line dir
  val="${val//\"/}"
  val="${val//$'\n'/}"
  dir="$(dirname -- "${conf}")"
  mkdir -p "${dir}"
  tmp="$(mktemp "${TMPDIR:-/tmp}/port.XXXXXX")"
  if [[ -f "${conf}" ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
      if [[ "${line}" == "${key}="* ]]; then
        printf '%s="%s"\n' "${key}" "${val}" >> "${tmp}"
        found=1
      else
        printf '%s\n' "${line}" >> "${tmp}"
      fi
    done < "${conf}"
  fi
  if (( found == 0 )); then
    printf '%s="%s"\n' "${key}" "${val}" >> "${tmp}"
  fi
  mv "${tmp}" "${conf}"
}

port_load_conf() {
  local conf="$1"
  PORT_SCHEMA="$(port_get_setting "${conf}" PORT_SCHEMA)"
  PORT_NAME="$(port_get_setting "${conf}" PORT_NAME)"
  PORT_SLUG="$(port_get_setting "${conf}" PORT_SLUG)"
  PORT_EXE="$(port_get_setting "${conf}" PORT_EXE)"
  PORT_ARGS="$(port_get_setting "${conf}" PORT_ARGS)"
  PORT_PROGRAM_ARCH="$(port_get_setting "${conf}" PORT_PROGRAM_ARCH)"
  PORT_BOTTLE="$(port_get_setting "${conf}" PORT_BOTTLE)"
  PORT_WINDOWS="$(port_get_setting "${conf}" PORT_WINDOWS)"
  PORT_RETINA="$(port_get_setting "${conf}" PORT_RETINA)"
  PORT_DISTRIBUTION="$(port_get_setting "${conf}" PORT_DISTRIBUTION)"
  PORT_PLATFORM="$(port_get_setting "${conf}" PORT_PLATFORM)"
  PORT_MIN_MACOS="$(port_get_setting "${conf}" PORT_MIN_MACOS)"
  PORT_PRIMARY="$(port_get_setting "${conf}" PORT_PRIMARY)"
  PORT_RENDER_DXMT="$(port_get_setting "${conf}" PORT_RENDER_DXMT)"
  PORT_RENDER_D3DMETAL="$(port_get_setting "${conf}" PORT_RENDER_D3DMETAL)"
  PORT_RENDER_DXVK="$(port_get_setting "${conf}" PORT_RENDER_DXVK)"
  PORT_RENDER_D9VK="$(port_get_setting "${conf}" PORT_RENDER_D9VK)"
  PORT_RENDER_CNC_DDRAW="$(port_get_setting "${conf}" PORT_RENDER_CNC_DDRAW)"
  PORT_RENDER_WINED3D="$(port_get_setting "${conf}" PORT_RENDER_WINED3D)"
  PORT_CNC_DDRAW_PATH="$(port_get_setting "${conf}" PORT_CNC_DDRAW_PATH)"
  PORT_GPTK_PATH="$(port_get_setting "${conf}" PORT_GPTK_PATH)"
  PORT_BUILT_APP="$(port_get_setting "${conf}" PORT_BUILT_APP)"
  [[ -n "${PORT_DISTRIBUTION}" ]] || PORT_DISTRIBUTION="personal"
  [[ -n "${PORT_PROGRAM_ARCH}" ]] || PORT_PROGRAM_ARCH="win64"
  [[ -n "${PORT_WINDOWS}" ]] || PORT_WINDOWS="win10"
  [[ -n "${PORT_RETINA}" ]] || PORT_RETINA="0"
  [[ -n "${PORT_PLATFORM}" ]] || PORT_PLATFORM="apple-silicon"
  [[ -n "${PORT_MIN_MACOS}" ]] || PORT_MIN_MACOS="14.6"
  export PORT_SCHEMA PORT_NAME PORT_SLUG PORT_EXE PORT_ARGS PORT_PROGRAM_ARCH PORT_BOTTLE
  export PORT_WINDOWS PORT_RETINA PORT_DISTRIBUTION PORT_PLATFORM PORT_MIN_MACOS
  export PORT_PRIMARY PORT_RENDER_DXMT PORT_RENDER_D3DMETAL PORT_RENDER_DXVK
  export PORT_RENDER_D9VK PORT_RENDER_CNC_DDRAW PORT_RENDER_WINED3D
  export PORT_CNC_DDRAW_PATH PORT_GPTK_PATH PORT_BUILT_APP
}

port_xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  printf '%s' "${value}"
}

port_write_info_plist() {
  local destination="$1" app_name="$2" bundle_id="$3" app_version="$4" min_system="$5"
  cat > "${destination}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$(port_xml_escape "${app_name}")</string>
    <key>CFBundleDisplayName</key>
    <string>$(port_xml_escape "${app_name}")</string>
    <key>CFBundleExecutable</key>
    <string>launcher</string>
    <key>CFBundleIdentifier</key>
    <string>$(port_xml_escape "${bundle_id}")</string>
    <key>CFBundleVersion</key>
    <string>$(port_xml_escape "${app_version}")</string>
    <key>CFBundleShortVersionString</key>
    <string>$(port_xml_escape "${app_version}")</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>$(port_xml_escape "${min_system}")</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Allen West. A Cosmos port. Licensed under GPL-3.0-or-later. D3DMetal is not included.</string>
</dict>
</plist>
EOF
}

port_write_launcher() {
  local destination="$1"
  cat > "${destination}" <<'EOF'
#!/bin/bash
# Cosmos port launcher. Apple Silicon (arm64), macOS 14.6 or later.
set -euo pipefail
if [[ "${COSMOS_PORT_SKIP_ARCH:-0}" != "1" ]]; then
  if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
    echo "This Cosmos port runs on Apple Silicon Macs (arm64)." >&2
    exit 1
  fi
fi
HERE="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${HERE}/Resources/port.env"
RUN=""
if [[ -n "${COSMOS_ROOT:-}" && -f "${COSMOS_ROOT}/run.command" ]]; then
  RUN="${COSMOS_ROOT}/run.command"
elif [[ -f "/Applications/Cosmos.app/Contents/Resources/run.command" ]]; then
  RUN="/Applications/Cosmos.app/Contents/Resources/run.command"
fi
if [[ -z "${RUN}" ]]; then
  echo "Cosmos runtime not found. Install Cosmos, or rebuild this port." >&2
  exit 1
fi
cd "${COSMOS_ROOT}"
extra=()
if [[ -n "${PORT_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  extra=(${PORT_ARGS})
fi
exec /bin/bash "${RUN}" --game "${GAME_EXE_PATH}" ${extra[@]+"${extra[@]}"}
EOF
  chmod +x "${destination}"
}

port_write_env() {
  local destination="$1" cosmos_root="$2" backend="$3" renderers="$4"
  local cnc_flag="0"
  {
    printf 'export COSMOS_ROOT=%q\n' "${cosmos_root}"
    printf 'export COSMOS_PORT=1\n'
    printf 'export COSMOS_PORT_DISTRIBUTION=%q\n' "${PORT_DISTRIBUTION:-personal}"
    printf 'export COSMOS_PORT_PLATFORM=%q\n' "${PORT_PLATFORM:-apple-silicon}"
    printf 'export COSMOS_PORT_RENDERERS=%q\n' "${renderers}"
    if port_is_on "${PORT_RENDER_CNC_DDRAW:-0}"; then
      cnc_flag="1"
    fi
    printf 'export COSMOS_PORT_CNC_DDRAW=%q\n' "${cnc_flag}"
    printf 'export COSMOS_BACKEND=%q\n' "${backend}"
    printf 'export COSMOS_SKIP_STEAM=1\n'
    printf 'export GAME_EXE_PATH=%q\n' "${PORT_EXE}"
    printf 'export PORT_ARGS=%q\n' "${PORT_ARGS:-}"
    printf 'export COSMOS_PROGRAM_ARCH=%q\n' "${PORT_PROGRAM_ARCH:-win64}"
    printf 'export WINDOWS_VERSION=%q\n' "${PORT_WINDOWS:-win10}"
    printf 'export WINE_RETINA_MODE=%q\n' "${PORT_RETINA:-0}"
    if [[ -n "${PORT_BOTTLE:-}" ]]; then
      printf 'export COSMOS_BOTTLE=%q\n' "${PORT_BOTTLE}"
    fi
    if [[ -n "${PORT_CNC_DDRAW_PATH:-}" ]]; then
      printf 'export CNC_DDRAW_PATH=%q\n' "${PORT_CNC_DDRAW_PATH}"
    fi
    # GPTK stays on this Mac. Never write it into a port meant to be shared.
    if [[ "${PORT_DISTRIBUTION:-personal}" == "personal" && -n "${PORT_GPTK_PATH:-}" ]]; then
      printf 'export GPTK_PATH=%q\n' "${PORT_GPTK_PATH}"
    fi
  } > "${destination}"
}

port_write_note() {
  local destination="$1" backend="$2" renderers="$3"
  cat > "${destination}" <<EOF
Cosmos port
This Mac app wraps a Windows program for Apple Silicon (macOS 14.6 or later).

Program: ${PORT_EXE}
Graphics renderers: ${renderers}
Launch backend: ${backend}
Distribution: ${PORT_DISTRIBUTION:-personal}

D3DMetal is not included. It is Apple software with a license that forbids
putting it in a port you share. A personal port uses D3DMetal only when you
have installed Game Porting Toolkit yourself.
EOF
}

# Build <Name>.app under output_dir. Prints the .app path.
# Uses the PORT_* variables loaded by port_load_conf.
port_write_bundle() {
  local output_dir="$1" cosmos_root="$2" conf="$3"
  local backend renderers bundle_name app_dir
  backend="$(port_resolve_primary)" || return 1
  renderers="$(port_renderers_csv)"
  port_validate_name "${PORT_NAME}" || {
    printf 'Error: %s\n' "Port name must not be empty or contain '/' or ':'." >&2
    return 1
  }
  bundle_name="${PORT_NAME}"
  if [[ "${bundle_name}" == *.app ]]; then
    bundle_name="${bundle_name%.app}"
  fi
  [[ -n "${bundle_name}" ]] || {
    printf 'Error: %s\n' "Port name must not be empty." >&2
    return 1
  }
  mkdir -p "${output_dir}"
  app_dir="${output_dir}/${bundle_name}.app"
  rm -rf "${app_dir}"
  mkdir -p "${app_dir}/Contents/MacOS" "${app_dir}/Contents/Resources"
  port_write_info_plist \
    "${app_dir}/Contents/Info.plist" \
    "${bundle_name}" \
    "com.cosmos.port.${PORT_SLUG}" \
    "1.0" \
    "${PORT_MIN_MACOS:-14.6}"
  printf 'APPL????' > "${app_dir}/Contents/PkgInfo"
  port_write_launcher "${app_dir}/Contents/MacOS/launcher"
  port_write_env "${app_dir}/Contents/Resources/port.env" "${cosmos_root}" "${backend}" "${renderers}"
  port_write_note "${app_dir}/Contents/Resources/ReadMe.txt" "${backend}" "${renderers}"
  if [[ -f "${conf}" ]]; then
    cp "${conf}" "${app_dir}/Contents/Resources/port.conf"
  fi
  printf '%s' "${app_dir}"
}

# Called from run.command when COSMOS_PORT=1. Refuses a shared port that
# resolved to D3DMetal (hand-edited env, not only the port CLI).
port_guard_shared_d3dmetal() {
  if [[ "${COSMOS_PORT_DISTRIBUTION:-}" == "share" && "${RESOLVED_BACKEND:-}" == "d3dmetal" ]]; then
    return 1
  fi
  return 0
}

# When a port asked for CNC-DDRAW and the user supplied ddraw.dll, prefer it
# for classic DirectDraw without replacing the primary backend.
port_apply_cnc_ddraw() {
  local path dll
  port_is_on "${COSMOS_PORT_CNC_DDRAW:-0}" || return 0
  path="${CNC_DDRAW_PATH:-}"
  dll=""
  if [[ -n "${path}" && -f "${path}/ddraw.dll" ]]; then
    dll="${path}/ddraw.dll"
  elif [[ -n "${path}" && -f "${path}" ]]; then
    dll="${path}"
    path="$(dirname -- "${path}")"
  fi
  if [[ -z "${dll}" ]]; then
    printf '\n==> %s\n' "CNC-DDRAW is on for this port, but CNC_DDRAW_PATH has no ddraw.dll. Classic DirectDraw stays on WineD3D."
    return 0
  fi
  case ":${WINEDLLPATH_PREPEND:-}:" in
    *":${path}:"*) ;;
    *) WINEDLLPATH_PREPEND="${path}${WINEDLLPATH_PREPEND:+:${WINEDLLPATH_PREPEND}}" ;;
  esac
  export WINEDLLPATH_PREPEND
  if [[ "${WINEDLLOVERRIDES:-}" != *"ddraw="* ]]; then
    if [[ -n "${WINEDLLOVERRIDES:-}" ]]; then
      WINEDLLOVERRIDES="${WINEDLLOVERRIDES};ddraw=n"
    else
      WINEDLLOVERRIDES="ddraw=n"
    fi
    export WINEDLLOVERRIDES
  fi
  printf '\n==> %s\n' "CNC-DDRAW enabled from ${path}"
}
