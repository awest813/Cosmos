#!/usr/bin/env bash
# Rosetta AVX, Battle.net login page, D3DMetal layout, and signature seed.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/soju_lib.sh
source "${ROOT}/scripts/lib/soju_lib.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$1"; }
field() { printf '%s\n' "$1" | awk -F= -v k="$2" '$1==k { print substr($0, index($0, "=")+1); exit }'; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

# --- AVX ----------------------------------------------------------------------
unset ROSETTA_ADVERTISE_AVX COSMOS_ROSETTA_AVX
export COSMOS_HOST_ARCH=x86_64
soju_apply_rosetta_avx
[[ -z "${ROSETTA_ADVERTISE_AVX:-}" ]] || fail "Intel auto should leave AVX unset"
export COSMOS_HOST_ARCH=arm64
soju_apply_rosetta_avx
[[ "${ROSETTA_ADVERTISE_AVX}" == "1" ]] || fail "arm64 auto should advertise AVX"
export ROSETTA_ADVERTISE_AVX=0
export COSMOS_ROSETTA_AVX=on
soju_apply_rosetta_avx
[[ "${ROSETTA_ADVERTISE_AVX}" == "0" ]] || fail "explicit AVX value should win"
unset ROSETTA_ADVERTISE_AVX
export COSMOS_ROSETTA_AVX=off
export COSMOS_HOST_ARCH=arm64
soju_apply_rosetta_avx
[[ -z "${ROSETTA_ADVERTISE_AVX:-}" ]] || fail "off should not advertise AVX"
pass "Rosetta AVX"

# --- writecopy ----------------------------------------------------------------
unset WINE_SIMULATE_WRITECOPY BATTLENET_LAUNCHER_EXE LEGENDARY_APP_NAME COSMOS_STORE
export COSMOS_WINE_WRITECOPY=auto
soju_apply_writecopy
[[ -z "${WINE_SIMULATE_WRITECOPY:-}" ]] || fail "Steam-style launch should leave writecopy unset"
export BATTLENET_LAUNCHER_EXE="drive_c/Program Files (x86)/Battle.net/Battle.net.exe"
soju_apply_writecopy
[[ "${WINE_SIMULATE_WRITECOPY}" == "1" ]] || fail "Battle.net should enable writecopy"
unset WINE_SIMULATE_WRITECOPY BATTLENET_LAUNCHER_EXE
export COSMOS_STORE=gog
soju_apply_writecopy
[[ "${WINE_SIMULATE_WRITECOPY}" == "1" ]] || fail "GOG should enable writecopy"
unset WINE_SIMULATE_WRITECOPY
export COSMOS_WINE_WRITECOPY=off
export COSMOS_STORE=epic
soju_apply_writecopy
[[ -z "${WINE_SIMULATE_WRITECOPY:-}" ]] || fail "off should not enable writecopy"
export WINE_SIMULATE_WRITECOPY=already
export COSMOS_WINE_WRITECOPY=on
soju_apply_writecopy
[[ "${WINE_SIMULATE_WRITECOPY}" == "already" ]] || fail "explicit writecopy should win"
pass "login-page writecopy"

# --- Battle.net signature seed ------------------------------------------------
unset BATTLENET_LAUNCHER_EXE COSMOS_STORE
export WINEPREFIX="${tmpdir}/prefix"
bn="${WINEPREFIX}/drive_c/Program Files (x86)/Battle.net"
mkdir -p "${bn}/Battle.net.12345" "${bn}/Battle.net.9" "${bn}/notes"
printf 'signed-exe' >"${bn}/Battle.net.exe"
printf 'stale' >"${bn}/Battle.net.12345/Battle.net.exe"
out="$(soju_seed_battlenet)"
[[ "$(field "${out}" seeded)" == "2" ]] || fail "expected 2 seeds, got: ${out}"
cmp -s "${bn}/Battle.net.exe" "${bn}/Battle.net.12345/Battle.net.exe" || fail "version folder has the wrong exe"
cmp -s "${bn}/Battle.net.exe" "${bn}/Battle.net.9/Battle.net.exe" || fail "second version folder was not seeded"
[[ ! -f "${bn}/notes/Battle.net.exe" ]] || fail "non-version folder was seeded"
out="$(soju_seed_battlenet)"
[[ "$(field "${out}" seeded)" == "0" ]] || fail "second seed should be a no-op: ${out}"
[[ "$(field "${out}" checked)" == "2" ]] || fail "second seed should still see both folders"
pass "Battle.net signature seed"

# --- D3DMetal layout ----------------------------------------------------------
payload="${tmpdir}/gptk/lib/external"
pe="${tmpdir}/gptk/lib/wine/x86_64-windows"
engine="${tmpdir}/engine/lib"
mkdir -p "${payload}/D3DMetal.framework" "${pe}" \
  "${engine}/wine/x86_64-windows" "${engine}/wine/x86_64-unix"
printf 'metal' >"${payload}/libd3dshared.dylib"
printf 'apple-d3d11' >"${pe}/d3d11.dll"
printf 'apple-d3d12' >"${pe}/d3d12.dll"
printf 'apple-dxgi' >"${pe}/dxgi.dll"
printf 'wine-d3d11' >"${engine}/wine/x86_64-windows/d3d11.dll"
printf 'not-a-symlink' >"${engine}/wine/x86_64-unix/d3d11.so"
export COSMOS_GPTK_PAYLOAD="${payload}"
export COSMOS_WINE_LIB="${engine}"

out="$(soju_gptk_layout_status)"
[[ "$(field "${out}" layout)" == "partial" ]] || fail "regular .so should be partial: ${out}"
[[ "$(field "${out}" copied_so)" == "1" ]] || fail "expected copied_so=1"

# Missing required shim must not change the tree.
mv "${pe}/d3d12.dll" "${pe}/d3d12.dll.aside"
out="$(soju_gptk_layout_apply)"
[[ "$(field "${out}" layout)" == "partial" ]] || fail "incomplete payload should not install: ${out}"
grep -q 'Nothing was changed' <<<"${out}" || fail "incomplete payload message: ${out}"
cmp -s "${engine}/wine/x86_64-windows/d3d11.dll" <(printf 'wine-d3d11') || fail "incomplete apply overwrote Wine's dll"
[[ -f "${engine}/wine/x86_64-unix/d3d11.so" && ! -L "${engine}/wine/x86_64-unix/d3d11.so" ]] || fail "incomplete apply replaced the real .so"
mv "${pe}/d3d12.dll.aside" "${pe}/d3d12.dll"
pass "incomplete payload is refused"

out="$(soju_gptk_layout_apply)"
[[ "$(field "${out}" layout)" == "complete" ]] || fail "apply should complete the layout: ${out}"
[[ -L "${engine}/wine/x86_64-unix/d3d11.so" ]] || fail "d3d11.so should be a symlink"
[[ "$(readlink "${engine}/wine/x86_64-unix/d3d11.so")" == "../../external/libd3dshared.dylib" ]] || fail "symlink target"
[[ -L "${engine}/wine/x86_64-unix/dxgi.so" ]] || fail "dxgi.so symlink"
cmp -s "${engine}/wine/x86_64-windows/d3d11.dll.cosmos-bak" <(printf 'wine-d3d11') || fail "backup should keep Wine's dll"
cmp -s "${engine}/wine/x86_64-windows/d3d11.dll" "${pe}/d3d11.dll" || fail "installed shim should be Apple's"
[[ -f "${engine}/external/libd3dshared.dylib" ]] || fail "libd3dshared was not installed"
[[ -d "${engine}/external/D3DMetal.framework" ]] || fail "framework was not installed"
pass "layout install uses symlinks"

out="$(soju_gptk_layout_revert)"
[[ "$(field "${out}" layout)" == "missing" ]] || fail "revert should clear the layout: ${out}"
cmp -s "${engine}/wine/x86_64-windows/d3d11.dll" <(printf 'wine-d3d11') || fail "revert should restore Wine's dll"
[[ ! -e "${engine}/wine/x86_64-unix/d3d11.so" ]] || fail "symlink should be removed"
[[ ! -f "${engine}/external/libd3dshared.dylib" ]] || fail "libd3dshared should be removed"
pass "layout revert"

unset COSMOS_GPTK_PAYLOAD
export COSMOS_WINE_LIB="${tmpdir}/empty-lib"
mkdir -p "${COSMOS_WINE_LIB}"
out="$(soju_gptk_layout_status)"
[[ "$(field "${out}" payload)" == "missing" ]] || fail "missing payload: ${out}"
[[ "$(field "${out}" layout)" == "missing" ]] || fail "missing layout: ${out}"
pass "missing payload"

# --- detach avoids nohup ------------------------------------------------------
log="${tmpdir}/spawn.log"
export ROSETTA_ADVERTISE_AVX=1
soju_spawn_detached "${log}" bash -c 'printf "avx=%s\n" "$ROSETTA_ADVERTISE_AVX"'
pid="$!"
wait "${pid}"
grep -q '^avx=1$' "${log}" || fail "detached child lost the environment: $(cat "${log}")"
if grep -n 'nohup' "${ROOT}/run.command" >/dev/null; then
  fail "run.command still launches through nohup"
fi
pass "detached launch keeps the environment"

# --- run.command flags --------------------------------------------------------
export COSMOS_GPTK_PAYLOAD="${payload}"
export COSMOS_WINE_LIB="${engine}"
# Reinstall so the CLI sees a real tree, then revert through the CLI.
soju_gptk_layout_apply >/dev/null
cli="$(
  env -u SCRIPT_DIR \
    COSMOS_SUPPORT_DIR="${tmpdir}/support" \
    COSMOS_BOTTLE="" \
    COSMOS_GPTK_PAYLOAD="${payload}" \
    COSMOS_WINE_LIB="${engine}" \
    WINEPREFIX="${WINEPREFIX}" \
    "${ROOT}/run.command" --gptk-layout-status
)"
[[ "$(field "${cli}" layout)" == "complete" ]] || fail "--gptk-layout-status: ${cli}"
cli="$(
  env -u SCRIPT_DIR \
    COSMOS_SUPPORT_DIR="${tmpdir}/support" \
    COSMOS_BOTTLE="" \
    WINEPREFIX="${WINEPREFIX}" \
    "${ROOT}/run.command" --battlenet-seed
)"
[[ "$(field "${cli}" seeded)" == "0" ]] || fail "--battlenet-seed: ${cli}"
[[ "$(field "${cli}" checked)" == "2" ]] || fail "--battlenet-seed checked: ${cli}"
pass "run.command Soju flags"

(
  unset SCRIPT_DIR
  export COSMOS_SUPPORT_DIR="${tmpdir}/sanitize"
  export COSMOS_BOTTLE=""
  export COSMOS_LAUNCH_LOG="${tmpdir}/sanitize.log"
  export COSMOS_ROSETTA_AVX=bogus
  export COSMOS_WINE_WRITECOPY=nope
  # shellcheck source=run.command
  source "${ROOT}/run.command"
  [[ "${COSMOS_ROSETTA_AVX}" == "auto" ]] || exit 1
  [[ "${COSMOS_WINE_WRITECOPY}" == "auto" ]] || exit 1
)
pass "invalid Soju settings fall back to auto"

printf 'OK: soju_lib tests passed\n'
