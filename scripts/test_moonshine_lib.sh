#!/usr/bin/env bash
# OpenGL byte check, crash notes, log preset, and launch directory.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/moonshine_lib.sh
source "${ROOT}/scripts/lib/moonshine_lib.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$1"; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

field() {
  printf '%s\n' "$1" | moonshine_status_field "$2"
}

byte_at() {
  moonshine_read_byte "$1" "$2"
}

# --- offset and a matching byte ----------------------------------------------
export COSMOS_OPENGL_PATCH_OFFSET=8
export COSMOS_WINEMAC_SO="${tmpdir}/winemac.so"
printf '\0\0\0\0\0\0\0\0\164' >"${COSMOS_WINEMAC_SO}"
[[ "$(byte_at "${COSMOS_WINEMAC_SO}" 8)" == "116" ]] || fail "fixture byte should be 116 (0x74)"

out="$(moonshine_opengl_status)"
[[ "$(field "${out}" status)" == "unpatched" ]] || fail "expected unpatched, got: ${out}"
[[ "$(field "${out}" byte)" == "74" ]] || fail "expected byte 74, got: ${out}"
[[ "$(field "${out}" offset)" == "8" ]] || fail "expected offset 8"
pass "unpatched status"

out="$(moonshine_opengl_apply)"
[[ "$(field "${out}" status)" == "patched" ]] || fail "apply should patch, got: ${out}"
[[ "$(byte_at "${COSMOS_WINEMAC_SO}" 8)" == "235" ]] || fail "file byte should be 235 (0xEB)"
[[ -f "${COSMOS_WINEMAC_SO}.cosmos-bak" ]] || fail "missing backup sidecar"
[[ "$(byte_at "${COSMOS_WINEMAC_SO}.cosmos-bak" 0)" == "116" ]] || fail "backup should keep 0x74"
pass "apply flips 0x74 to 0xEB and saves the original byte"

out="$(moonshine_opengl_apply)"
[[ "$(field "${out}" status)" == "patched" ]] || fail "second apply should stay patched"
[[ "$(byte_at "${COSMOS_WINEMAC_SO}.cosmos-bak" 0)" == "116" ]] || fail "second apply overwrote the backup"
pass "already patched is left alone"

out="$(moonshine_opengl_revert)"
[[ "$(field "${out}" status)" == "unpatched" ]] || fail "revert should restore, got: ${out}"
[[ "$(byte_at "${COSMOS_WINEMAC_SO}" 8)" == "116" ]] || fail "revert should write the backup byte"
[[ ! -f "${COSMOS_WINEMAC_SO}.cosmos-bak" ]] || fail "backup should be removed after restore"
pass "revert restores the backup"

# No backup, byte already 0xEB: write 0x74.
printf '\0\0\0\0\0\0\0\0\353' >"${COSMOS_WINEMAC_SO}"
out="$(moonshine_opengl_revert)"
[[ "$(field "${out}" status)" == "unpatched" ]] || fail "revert without backup failed: ${out}"
[[ "$(byte_at "${COSMOS_WINEMAC_SO}" 8)" == "116" ]] || fail "revert without backup should write 0x74"
pass "revert without a backup writes 0x74"

# --- mismatch and short files are not modified --------------------------------
printf '\0\0\0\0\0\0\0\0\001' >"${COSMOS_WINEMAC_SO}"
before="$(od -An -tx1 "${COSMOS_WINEMAC_SO}")"
out="$(moonshine_opengl_apply)"
after="$(od -An -tx1 "${COSMOS_WINEMAC_SO}")"
[[ "$(field "${out}" status)" == "mismatch" ]] || fail "unexpected byte should mismatch: ${out}"
[[ "${before}" == "${after}" ]] || fail "mismatch apply modified the file"
[[ ! -f "${COSMOS_WINEMAC_SO}.cosmos-bak" ]] || fail "mismatch apply wrote a backup"
pass "mismatch is left unchanged"

unset COSMOS_OPENGL_PATCH_OFFSET
printf 'short' >"${tmpdir}/short.so"
export COSMOS_WINEMAC_SO="${tmpdir}/short.so"
out="$(moonshine_opengl_status)"
[[ "$(field "${out}" status)" == "mismatch" ]] || fail "short file should mismatch: ${out}"
[[ "$(field "${out}" offset)" == "$((0x329fb))" ]] || fail "default offset should be 0x329fb"
short_before="$(wc -c < "${tmpdir}/short.so" | tr -d '[:space:]')"
moonshine_opengl_apply >/dev/null
short_after="$(wc -c < "${tmpdir}/short.so" | tr -d '[:space:]')"
[[ "${short_before}" == "${short_after}" ]] || fail "short file grew during apply"
pass "short file is not patched"

export COSMOS_OPENGL_PATCH_OFFSET=0x8
export COSMOS_WINEMAC_SO="${tmpdir}/winemac.so"
printf '\0\0\0\0\0\0\0\0\164' >"${COSMOS_WINEMAC_SO}"
[[ "$(moonshine_opengl_offset)" == "8" ]] || fail "hex offset override"
pass "hex offset override"

# --- auto mode -----------------------------------------------------------------
export COSMOS_OPENGL_PATCH=off
auto_out="$(moonshine_opengl_auto)"
[[ -z "${auto_out}" ]] || fail "off mode should be silent, got: ${auto_out}"
[[ "$(byte_at "${COSMOS_WINEMAC_SO}" 8)" == "116" ]] || fail "off mode patched anyway"
pass "off mode skips the fix"

export COSMOS_OPENGL_PATCH=auto
auto_out="$(moonshine_opengl_auto)"
printf '%s\n' "${auto_out}" | grep -q 'Applied the OpenGL 3.2 fix' || fail "auto should apply: ${auto_out}"
[[ "$(byte_at "${COSMOS_WINEMAC_SO}" 8)" == "235" ]] || fail "auto did not flip the byte"
auto_again="$(moonshine_opengl_auto)"
[[ -z "${auto_again}" ]] || fail "already patched auto should be silent: ${auto_again}"
pass "auto applies once and stays quiet"

printf '\0\0\0\0\0\0\0\0\001' >"${COSMOS_WINEMAC_SO}"
rm -f "${COSMOS_WINEMAC_SO}.cosmos-bak"
export COSMOS_OPENGL_PATCH=auto
[[ -z "$(moonshine_opengl_auto)" ]] || fail "auto mismatch should be silent"
export COSMOS_OPENGL_PATCH=on
warn="$(moonshine_opengl_auto)"
printf '%s\n' "${warn}" | grep -q '^Warning:' || fail "on mismatch should warn: ${warn}"
[[ "$(byte_at "${COSMOS_WINEMAC_SO}" 8)" == "1" ]] || fail "warning path modified the file"
pass "mismatch warns only when the fix is forced on"

export COSMOS_WINEMAC_SO="${tmpdir}/missing.so"
export COSMOS_OPENGL_PATCH=auto
out="$(moonshine_opengl_status)"
[[ "$(field "${out}" status)" == "missing" ]] || fail "missing driver: ${out}"
[[ -z "$(moonshine_opengl_auto)" ]] || fail "missing driver auto should be silent"
pass "missing driver"

# --- logs ----------------------------------------------------------------------
unset COSMOS_WINEDEBUG_PRESET
[[ "$(moonshine_winedebug_default)" == "-all,err+all" ]] || fail "default log preset"
export COSMOS_WINEDEBUG_PRESET=moonshine
[[ "$(moonshine_winedebug_default)" == "fixme-all,err+all,warn+module" ]] || fail "moonshine log preset"
export WINEDEBUG="caller"
chosen="${WINEDEBUG:-$(moonshine_winedebug_default)}"
[[ "${chosen}" == "caller" ]] || fail "explicit WINEDEBUG should win"
unset WINEDEBUG
export COSMOS_WINEDEBUG_PRESET=moonshine
chosen="${WINEDEBUG:-$(moonshine_winedebug_default)}"
[[ "${chosen}" == "fixme-all,err+all,warn+module" ]] || fail "preset should fill an empty WINEDEBUG"
pass "Wine log preset"

export COSMOS_LAUNCH_LOG="${tmpdir}/launch.log"
{
  echo "normal line"
  echo "page fault on read access"
  i=0
  while (( i < 10 )); do
    echo "err:module:load dll load failed ${i}"
    i=$((i + 1))
  done
} >"${COSMOS_LAUNCH_LOG}"
report="$(moonshine_report_exit "Game" 139)"
printf '%s\n' "${report}" | grep -q 'Game ended: status=139 reason=uncaught signal' || fail "signal note: ${report}"
err_count="$(printf '%s\n' "${report}" | grep -c 'err:module' || true)"
[[ "${err_count}" == "7" ]] || fail "expected 7 err lines inside the 8-line cap, got ${err_count}"
printf '%s\n' "${report}" | grep -q 'page fault' || fail "page fault line missing"
grep -q 'Game ended: status=139 reason=uncaught signal' "${COSMOS_LAUNCH_LOG}" || fail "note was not appended to the log"
rc=0
moonshine_report_exit "Game" 1 >/dev/null || rc=$?
[[ "${rc}" == "0" ]] || fail "report itself should return 0"
pass "crash note"

# --- working directory ----------------------------------------------------------
mkdir -p "${tmpdir}/External Game"
: >"${tmpdir}/External Game/game.exe"
start_pwd="$(pwd)"
seen=""
record_dir() { seen="$(pwd)"; return 7; }
rc=0
moonshine_with_program_dir "${tmpdir}/External Game/game.exe" record_dir || rc=$?
[[ "${rc}" == "7" ]] || fail "directory wrapper should return the command status"
[[ "${seen}" == "${tmpdir}/External Game" ]] || fail "command ran in ${seen}"
[[ "$(pwd)" == "${start_pwd}" ]] || fail "wrapper did not restore the working directory"
pass "launch directory"

# --- run.command wiring ---------------------------------------------------------
export COSMOS_OPENGL_PATCH_OFFSET=8
export COSMOS_WINEMAC_SO="${tmpdir}/cli.so"
printf '\0\0\0\0\0\0\0\0\164' >"${COSMOS_WINEMAC_SO}"
cli="$(
  env -u SCRIPT_DIR \
    COSMOS_SUPPORT_DIR="${tmpdir}/support" \
    COSMOS_BOTTLE="" \
    COSMOS_WINEMAC_SO="${COSMOS_WINEMAC_SO}" \
    COSMOS_OPENGL_PATCH_OFFSET=8 \
    "${ROOT}/run.command" --opengl-status
)"
[[ "$(field "${cli}" status)" == "unpatched" ]] || fail "--opengl-status: ${cli}"
cli="$(
  env -u SCRIPT_DIR \
    COSMOS_SUPPORT_DIR="${tmpdir}/support" \
    COSMOS_BOTTLE="" \
    COSMOS_WINEMAC_SO="${COSMOS_WINEMAC_SO}" \
    COSMOS_OPENGL_PATCH_OFFSET=8 \
    "${ROOT}/run.command" --opengl-patch
)"
[[ "$(field "${cli}" status)" == "patched" ]] || fail "--opengl-patch: ${cli}"
[[ "$(byte_at "${COSMOS_WINEMAC_SO}" 8)" == "235" ]] || fail "CLI apply did not write 0xEB"
cli="$(
  env -u SCRIPT_DIR \
    COSMOS_SUPPORT_DIR="${tmpdir}/support" \
    COSMOS_BOTTLE="" \
    COSMOS_WINEMAC_SO="${COSMOS_WINEMAC_SO}" \
    COSMOS_OPENGL_PATCH_OFFSET=8 \
    "${ROOT}/run.command" --opengl-revert
)"
[[ "$(field "${cli}" status)" == "unpatched" ]] || fail "--opengl-revert: ${cli}"
pass "run.command OpenGL flags"

(
  unset SCRIPT_DIR
  export COSMOS_SUPPORT_DIR="${tmpdir}/sanitize"
  export COSMOS_BOTTLE=""
  export COSMOS_LAUNCH_LOG="${tmpdir}/sanitize.log"
  export COSMOS_WINEDEBUG_PRESET=bogus
  export COSMOS_OPENGL_PATCH=nope
  # shellcheck source=run.command
  source "${ROOT}/run.command"
  [[ "${COSMOS_WINEDEBUG_PRESET}" == "cosmos" ]] || exit 1
  [[ "${COSMOS_OPENGL_PATCH}" == "auto" ]] || exit 1
  [[ "$(moonshine_winedebug_default)" == "-all,err+all" ]] || exit 1
)
pass "invalid presets fall back to the quiet defaults"

(
  unset SCRIPT_DIR
  export COSMOS_SUPPORT_DIR="${tmpdir}/launch-support"
  export COSMOS_BOTTLE=""
  export COSMOS_LAUNCH_LOG="${tmpdir}/launch-cwd.log"
  export COSMOS_WINEDEBUG_PRESET=moonshine
  # shellcheck source=run.command
  source "${ROOT}/run.command"
  [[ "$(moonshine_winedebug_default)" == "fixme-all,err+all,warn+module" ]] || exit 1
  mkdir -p "${tmpdir}/External Game"
  : >"${tmpdir}/External Game/game.exe"
  WINE_BIN="fake-wine"
  PROFILE_EXECUTABLE="${tmpdir}/External Game/game.exe"
  PROFILE_ARGS=()
  CAPTURED=()
  LAUNCH_PWD=""
  run_launch_cmd() { CAPTURED=("$@"); LAUNCH_PWD="$(pwd)"; }
  launch_profile
  [[ "${CAPTURED[2]}" == "fake-wine" ]] || exit 1
  [[ "${CAPTURED[3]}" == "${PROFILE_EXECUTABLE}" ]] || exit 1
  [[ "${LAUNCH_PWD}" == "${tmpdir}/External Game" ]] || exit 1
  [[ "$(pwd)" != "${tmpdir}/External Game" ]] || exit 1
)
pass "profile launch stays beside the program"

(
  unset SCRIPT_DIR
  export COSMOS_SUPPORT_DIR="${tmpdir}/fail-support"
  export COSMOS_BOTTLE=""
  export COSMOS_LAUNCH_LOG="${tmpdir}/fail.log"
  export COSMOS_DETACH=0
  export COSMOS_LAUNCH_RETRIES=0
  # shellcheck source=run.command
  source "${ROOT}/run.command"
  printf 'err:module:load dll load failed\n' >"${COSMOS_LAUNCH_LOG}"
  rc=0
  report="$(run_launch_cmd "Game" 0 false 2>/dev/null)" || rc=$?
  [[ "${rc}" == "1" ]] || exit 1
  printf '%s\n' "${report}" | grep -q 'Game ended: status=1 reason=exit' || exit 1
  grep -q 'reason=exit' "${COSMOS_LAUNCH_LOG}" || exit 1
)
pass "failed launch keeps its exit code and records the note"

printf 'OK: moonshine_lib tests passed\n'
