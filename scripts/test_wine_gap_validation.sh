#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# shellcheck source=scripts/lib/wine_gap_lib.sh
source "${ROOT}/scripts/lib/wine_gap_lib.sh"
wine_gap_init "${ROOT}"

[[ -x "${ROOT}/scripts/validate_wine_gaps.sh" ]] \
  || fail "validate_wine_gaps.sh not executable"

"${ROOT}/scripts/validate_wine_gaps.sh" check \
  || fail "wine gap sync check failed"

# Schema + required fields
python3 - "${ROOT}/runtime/wine-gap-validation.json" <<'PY' || fail "validation JSON schema"
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
assert data["schema"] == "cosmos-wine-gap-validation-1"
assert data["pinned_wine_version"]
gap = data["gaps"]["wine_29384_virtualprotect_cow"]
assert gap["status"] in ("pass", "fail", "untested")
assert "synthetic_cow_probe" in gap["tests"]
assert gap["tests"]["skse64_loader"]["steam_appid"] == 489830
PY

# Simulated bump must fail until validation JSON is updated
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
cp "${ROOT}/runtime/cosmos-runtime.json" "${tmpdir}/cosmos-runtime.json"
python3 - "${tmpdir}/cosmos-runtime.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text())
data["components"]["wine"]["version"] = "99.9-bump-test"
p.write_text(json.dumps(data, indent=2) + "\n")
PY

WINE_GAP_MANIFEST_PATH="${tmpdir}/cosmos-runtime.json"
if wine_gap_sync_check 2>/dev/null; then
  fail "sync check should fail when manifest wine version != validation pin"
fi

# record helpers mutate a copy
cp "${ROOT}/runtime/wine-gap-validation.json" "${tmpdir}/wine-gap-validation.json"
WINE_GAP_VALIDATION_PATH="${tmpdir}/wine-gap-validation.json"
wine_gap_record_test wine_29384_virtualprotect_cow synthetic_cow_probe pass "test"
status="$(wine_gap_gap_status wine_29384_virtualprotect_cow)"
[[ "${status}" == "fail" ]] || fail "record_test should not change gap status"

probe_src="${ROOT}/scripts/fixtures/wine_gap/cow_probe.c"
[[ -f "${probe_src}" ]] || fail "missing cow_probe.c"
grep -q 'VirtualProtect' "${probe_src}" || fail "cow_probe.c should use VirtualProtect"

printf 'OK: wine gap validation tests passed (pin %s)\n' "$(wine_gap_pinned_version)"
