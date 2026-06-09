#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/cosmos-wmt-import-$$"
mkdir -p "${TMP}/fixes"
export TMP

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# shellcheck source=scripts/lib/recipe_lib.sh
source "${ROOT}/scripts/lib/recipe_lib.sh"

"${ROOT}/scripts/import_winemactricks.sh" --dry-run >/dev/null

[[ -f "${ROOT}/recipes/fixes/grounded-mscoree-fix.recipe" ]] \
  || fail "expected grounded-mscoree-fix.recipe"

recipe_load "${ROOT}/recipes/fixes/grounded-mscoree-fix.recipe" \
  || fail "could not load grounded-mscoree-fix recipe"
[[ "${RECIPE_SCRIPT}" == "dll_override" ]] \
  || fail "expected SCRIPT=dll_override"
[[ "${RECIPE_DLL_OVERRIDE}" == "mscoree=n" ]] \
  || fail "expected DLL_OVERRIDE=mscoree=n"
[[ "${RECIPE_SOURCE}" == "winemactricks:grounded.mscoree_fix" ]] \
  || fail "expected SOURCE attribution"

for dep in vcrun2019 dotnet48 corefonts; do
  [[ -f "${ROOT}/recipes/dependencies/${dep}.recipe" ]] \
    || fail "missing dependency recipe ${dep}"
done

printf 'OK: import_winemactricks tests passed\n'
