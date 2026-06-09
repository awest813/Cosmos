#!/usr/bin/env bash
# Cross-check bash/awk VDF parsing against ValvePython/vdf on fixture files.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/steam_lib.sh
source "${ROOT}/scripts/lib/steam_lib.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || fail "python3 required"

if ! python3 -c 'import vdf' 2>/dev/null; then
  printf 'SKIP: python vdf package not installed (pip install vdf)\n'
  exit 0
fi

FIXTURE_VDF="${ROOT}/scripts/fixtures/steam_detection/wineprefix/drive_c/Program Files (x86)/Steam/steamapps/libraryfolders.vdf"
[[ -f "${FIXTURE_VDF}" ]] || fail "missing fixture VDF"

normalize_vdf_path() {
  printf '%s' "$1" | sed 's/\\\\/\\/g'
}

mapfile -t bash_paths < <(steam_library_paths_from_vdf "${FIXTURE_VDF}")
mapfile -t py_paths < <(python3 "${ROOT}/scripts/steam_vdf_paths.py" "${FIXTURE_VDF}")

bash_join=""
py_join=""
for p in "${bash_paths[@]}"; do
  bash_join+="$(normalize_vdf_path "${p}")|"
done
for p in "${py_paths[@]}"; do
  py_join+="$(normalize_vdf_path "${p}")|"
done
[[ "${bash_join}" == "${py_join}" ]] \
  || fail "bash vs python VDF paths differ: bash=${bash_join} python=${py_join}"

printf 'OK: VDF python cross-check passed (%s path(s))\n' "${#bash_paths[@]}"
