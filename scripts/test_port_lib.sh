#!/usr/bin/env bash
# Apple Silicon port resolver, D3DMetal share gate, and .app wrapper.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/port_lib.sh
source "${ROOT}/scripts/lib/port_lib.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

assert_backend() {
  local expected="$1"
  local got
  got="$(port_resolve_primary)" || fail "resolve failed, expected ${expected}"
  [[ "${got}" == "${expected}" ]] || fail "expected ${expected}, got ${got}"
}

reset_renderers() {
  PORT_DISTRIBUTION="personal"
  PORT_RENDER_DXMT=0
  PORT_RENDER_D3DMETAL=0
  PORT_RENDER_DXVK=0
  PORT_RENDER_D9VK=0
  PORT_RENDER_CNC_DDRAW=0
  PORT_RENDER_WINED3D=0
  export PORT_DISTRIBUTION PORT_RENDER_DXMT PORT_RENDER_D3DMETAL PORT_RENDER_DXVK
  export PORT_RENDER_D9VK PORT_RENDER_CNC_DDRAW PORT_RENDER_WINED3D
}

reset_renderers
PORT_RENDER_DXMT=1
PORT_RENDER_D9VK=1
PORT_RENDER_CNC_DDRAW=1
PORT_RENDER_WINED3D=1
assert_backend "spockd3d9"

reset_renderers
PORT_RENDER_DXMT=1
assert_backend "dxmt"

reset_renderers
PORT_RENDER_D3DMETAL=1
PORT_RENDER_DXMT=1
assert_backend "d3dmetal"

reset_renderers
PORT_DISTRIBUTION="share"
PORT_RENDER_D3DMETAL=1
share_err="$(mktemp)"
if port_resolve_primary >/dev/null 2>"${share_err}"; then
  fail "shared D3DMetal should be refused"
fi
grep -q "D3DMetal" "${share_err}" || fail "share error should name D3DMetal"
rm -f "${share_err}"

reset_renderers
PORT_RENDER_DXVK=1
assert_backend "dxvk"

reset_renderers
PORT_RENDER_D9VK=1
assert_backend "spockd3d9"

reset_renderers
PORT_RENDER_CNC_DDRAW=1
assert_backend "wined3d"

reset_renderers
if port_resolve_primary >/dev/null 2>&1; then
  fail "empty renderer stack should fail"
fi

[[ "$(port_slugify "My Game!")" == "my-game" ]] || fail "slugify My Game!"
[[ "$(port_slugify "!!!")" == "port" ]] || fail "slugify punctuation"
port_validate_slug "my-game" || fail "slug my-game"
if port_validate_slug ".." ; then fail "slug .. should fail"; fi
if port_validate_name "a/b"; then fail "name with slash should fail"; fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

cnc="${tmpdir}/cnc"
mkdir -p "${cnc}"
printf 'fake\n' > "${cnc}/ddraw.dll"
CNC_DDRAW_PATH="${cnc}"
COSMOS_PORT_CNC_DDRAW=1
unset WINEDLLOVERRIDES WINEDLLPATH_PREPEND || true
port_apply_cnc_ddraw >/dev/null
[[ "${WINEDLLOVERRIDES}" == "ddraw=n" ]] || fail "ddraw override: ${WINEDLLOVERRIDES:-}"
[[ "${WINEDLLPATH_PREPEND}" == "${cnc}" ]] || fail "ddraw path: ${WINEDLLPATH_PREPEND:-}"

RESOLVED_BACKEND="d3dmetal"
COSMOS_PORT_DISTRIBUTION="share"
if port_guard_shared_d3dmetal; then
  fail "guard should refuse shared D3DMetal"
fi
COSMOS_PORT_DISTRIBUTION="personal"
port_guard_shared_d3dmetal || fail "guard should allow personal D3DMetal"

export COSMOS_SUPPORT_DIR="${tmpdir}/support"
export COSMOS_PORTS_OUTPUT="${tmpdir}/apps"
exe="${tmpdir}/notepad.exe"
printf 'MZ\n' > "${exe}"

set +e
arch_out="$(env -u COSMOS_PORT_SKIP_ARCH COSMOS_SUPPORT_DIR="${COSMOS_SUPPORT_DIR}" \
  "${ROOT}/port.command" create --name "Notepad" --exe "${exe}" 2>&1)"
arch_code=$?
set -e
[[ "${arch_code}" -ne 0 ]] || fail "create should refuse this machine without COSMOS_PORT_SKIP_ARCH"
printf '%s' "${arch_out}" | grep -q "Apple Silicon" || fail "arch error should mention Apple Silicon: ${arch_out}"

export COSMOS_PORT_SKIP_ARCH=1

set +e
missing_out="$("${ROOT}/port.command" create --name "Ghost" --exe "${exe}" --bottle "no-such-bottle" 2>&1)"
missing_code=$?
set -e
[[ "${missing_code}" -ne 0 ]] || fail "missing bottle should fail"
printf '%s' "${missing_out}" | grep -q "Bottle not found" || fail "missing bottle message: ${missing_out}"

set +e
share_out="$("${ROOT}/port.command" create --name "Shared Metal" --exe "${exe}" \
  --distribution share --d3dmetal 1 2>&1)"
share_code=$?
set -e
[[ "${share_code}" -ne 0 ]] || fail "share + D3DMetal should fail"
printf '%s' "${share_out}" | grep -q "D3DMetal" || fail "share create error: ${share_out}"

"${ROOT}/port.command" create --name "Notepad" --exe "${exe}" >/dev/null
"${ROOT}/port.command" validate notepad >/dev/null
show="$("${ROOT}/port.command" show notepad)"
printf '%s\n' "${show}" | grep -q "spockd3d9" || fail "show should report spockd3d9: ${show}"
printf '%s\n' "${show}" | grep -q "apple-silicon" || fail "show should report apple-silicon"
printf '%s\n' "${show}" | grep -q "Program:       64-bit" || fail "default program should be 64-bit: ${show}"

fake="${tmpdir}/runtime"
mkdir -p "${fake}"
cat > "${fake}/run.command" <<'EOF'
#!/bin/bash
printf 'backend=%s\nskip=%s\nport=%s\ngame=%s\n' \
  "${COSMOS_BACKEND}" "${COSMOS_SKIP_STEAM}" "${COSMOS_PORT}" "$2"
printf 'program=%s\n' "${COSMOS_PROGRAM_ARCH:-}"
printf 'arg=<%s>\n' "$@"
EOF
chmod +x "${fake}/run.command"

COSMOS_PORT_RUNTIME_ROOT="${fake}" "${ROOT}/port.command" build notepad --output "${tmpdir}/apps" >/dev/null
app="${tmpdir}/apps/Notepad.app"
[[ -d "${app}" ]] || fail "app bundle missing"
[[ -x "${app}/Contents/MacOS/launcher" ]] || fail "launcher not executable"
grep -q "14.6" "${app}/Contents/Info.plist" || fail "minimum macOS should be 14.6"
grep -q "com.cosmos.port.notepad" "${app}/Contents/Info.plist" || fail "bundle id"
grep -q "Apple Silicon" "${app}/Contents/MacOS/launcher" || fail "launcher arch note"
grep -q "COSMOS_BACKEND=spockd3d9" "${app}/Contents/Resources/port.env" || fail "backend env"
grep -q "COSMOS_SKIP_STEAM=1" "${app}/Contents/Resources/port.env" || fail "skip steam"
grep -q "COSMOS_PORT=1" "${app}/Contents/Resources/port.env" || fail "port flag"
if grep -q "GPTK_PATH" "${app}/Contents/Resources/port.env"; then
  fail "default port should not embed GPTK_PATH"
fi
grep -q "D3DMetal is not included" "${app}/Contents/Resources/ReadMe.txt" || fail "readme license note"

stored_exe="$(printf '%s\n' "${show}" | sed -n 's/^Executable:[[:space:]]*//p')"
[[ -n "${stored_exe}" ]] || fail "show did not print the executable"
launch_out="$(COSMOS_PORT_SKIP_ARCH=1 "${app}/Contents/MacOS/launcher")"
printf '%s\n' "${launch_out}" | grep -q "backend=spockd3d9" || fail "launch backend: ${launch_out}"
printf '%s\n' "${launch_out}" | grep -q "skip=1" || fail "launch skip steam: ${launch_out}"
printf '%s\n' "${launch_out}" | grep -q "port=1" || fail "launch port flag: ${launch_out}"
printf '%s\n' "${launch_out}" | grep -Fq "game=${stored_exe}" || fail "launch game path: ${launch_out}"

set +e
blocked="$(env -u COSMOS_PORT_SKIP_ARCH "${app}/Contents/MacOS/launcher" 2>&1)"
blocked_code=$?
set -e
[[ "${blocked_code}" -ne 0 ]] || fail "launcher should refuse non-arm64 without the test override"
printf '%s' "${blocked}" | grep -q "Apple Silicon" || fail "launcher arch message: ${blocked}"

"${ROOT}/port.command" create \
  --name "Personal Metal" \
  --exe "${exe}" \
  --slug personal-metal \
  --distribution personal \
  --d3dmetal 1 \
  --gptk-path "${tmpdir}/GPTK" >/dev/null
COSMOS_PORT_RUNTIME_ROOT="${fake}" "${ROOT}/port.command" build personal-metal --output "${tmpdir}/apps" >/dev/null
metal_env="${tmpdir}/apps/Personal Metal.app/Contents/Resources/port.env"
grep -q "COSMOS_BACKEND=d3dmetal" "${metal_env}" || fail "personal port backend"
grep -q "GPTK_PATH" "${metal_env}" || fail "personal port should record GPTK_PATH"

"${ROOT}/port.command" create \
  --name "Shared Classic" \
  --exe "${exe}" \
  --slug shared-classic \
  --distribution share \
  --d3dmetal 0 >/dev/null
COSMOS_PORT_RUNTIME_ROOT="${fake}" "${ROOT}/port.command" build shared-classic --output "${tmpdir}/apps" >/dev/null
share_env="${tmpdir}/apps/Shared Classic.app/Contents/Resources/port.env"
if grep -q "GPTK_PATH" "${share_env}"; then
  fail "shared port env should not contain GPTK_PATH"
fi
if grep -q "d3dmetal" "${share_env}"; then
  fail "shared port env should not enable d3dmetal: $(cat "${share_env}")"
fi

"${ROOT}/port.command" create \
  --name "Old Game" \
  --exe "${exe}" \
  --slug old-game \
  --program-arch win32 \
  --args '--windowed --save "two words" --empty "" *.sav' >/dev/null
old_show="$("${ROOT}/port.command" show old-game)"
printf '%s\n' "${old_show}" | grep -q "Program:       32-bit" || fail "32-bit program: ${old_show}"
printf '%s\n' "${old_show}" | grep -Fq 'Arguments:     --windowed --save "two words"' || fail "launch arguments must retain quotes: ${old_show}"
COSMOS_PORT_RUNTIME_ROOT="${fake}" "${ROOT}/port.command" build old-game --output "${tmpdir}/apps" >/dev/null
old_env="${tmpdir}/apps/Old Game.app/Contents/Resources/port.env"
grep -q "COSMOS_PROGRAM_ARCH=win32" "${old_env}" || fail "port env should record the 32-bit program"
grep -q "PORT_ARGS=--windowed" "${old_env}" || fail "port env should record launch arguments"

# Exercise both the built app and CLI, without Wine or macOS. Literal glob
# arguments must survive even when the runtime directory contains matches.
touch "${fake}/expanded.sav"
old_out="$("${tmpdir}/apps/Old Game.app/Contents/MacOS/launcher")"
printf '%s\n' "${old_out}" | grep -Fxq 'program=win32' || fail "built app program architecture"
printf '%s\n' "${old_out}" | grep -Fxq 'arg=<two words>' || fail "quoted argument split in built launcher"
printf '%s\n' "${old_out}" | grep -Fxq 'arg=<>' || fail "empty argument lost in built launcher"
printf '%s\n' "${old_out}" | grep -Fxq 'arg=<*.sav>' || fail "glob expanded in built launcher"
mkdir -p "${fake}/scripts/lib"
cp "${ROOT}/scripts/lib/port_lib.sh" "${ROOT}/scripts/lib/prefix_arch.sh" "${fake}/scripts/lib/"
cli_out="$(SCRIPT_DIR="${fake}" COSMOS_PROGRAM_ARCH=win64 "${ROOT}/port.command" launch old-game)"
printf '%s\n' "${cli_out}" | grep -Fxq 'program=win32' || fail "CLI ignored port program architecture"
printf '%s\n' "${cli_out}" | grep -Fxq 'arg=<two words>' || fail "CLI split quoted arguments"
printf '%s\n' "${cli_out}" | grep -Fxq 'arg=<*.sav>' || fail "CLI expanded a literal glob"

if (port_exec_program "${fake}/run.command" "${exe}" '--save "unterminated') >"${tmpdir}/bad-args.log" 2>&1; then
  fail "malformed arguments should fail before launching"
fi
grep -q 'Invalid port launch arguments' "${tmpdir}/bad-args.log" || fail "malformed arguments need a useful error"
if grep -q '^backend=' "${tmpdir}/bad-args.log"; then fail "malformed arguments launched the game"; fi

"${ROOT}/port.command" delete notepad --force >/dev/null
[[ ! -d "${COSMOS_SUPPORT_DIR}/Ports/notepad" ]] || fail "delete should remove the port definition"
[[ -d "${app}" ]] || fail "delete should leave the built Mac app in place"

printf 'ok\n'
