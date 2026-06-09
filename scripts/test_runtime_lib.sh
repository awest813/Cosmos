#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || fail "python3 required"

MANIFEST="${ROOT}/runtime/cosmos-runtime.json"
[[ -f "${MANIFEST}" ]] || fail "missing runtime manifest"

python3 - "${MANIFEST}" <<'PY' || fail "invalid cosmos-runtime.json"
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
assert data["schema"] == "cosmos-runtime-1.0"
for key in ("wine", "dxmt", "dxvk_macos", "moltenvk"):
    assert key in data["components"], key
    assert data["components"][key].get("url"), key
assert data["components"]["dxmt"]["version"] == "0.74"
PY

# shellcheck source=scripts/lib/runtime_lib.sh
export SCRIPT_DIR="${ROOT}"
source "${ROOT}/scripts/lib/runtime_lib.sh"

unset WINE_VERSION DXMT_VERSION WINE_URL DXMT_URL RUNTIME_MANIFEST_LOADED
runtime_load_manifest || fail "runtime_load_manifest failed"
[[ "${RUNTIME_MANIFEST_LOADED:-}" == "1" ]] || fail "manifest not loaded"
[[ "${WINE_VERSION}" == "11.8" ]] || fail "expected WINE_VERSION from manifest"
[[ "${DXMT_VERSION}" == "0.74" ]] || fail "expected DXMT_VERSION from manifest"

export DXMT_VERSION="0.74"
unset COSMOS_ALLOW_LGPL
runtime_assert_dxmt_license || fail "0.74 should pass MIT gate"

export DXMT_VERSION="0.81"
if runtime_assert_dxmt_license 2>/dev/null; then
  fail "DXMT 0.81 should fail without COSMOS_ALLOW_LGPL"
fi

export COSMOS_ALLOW_LGPL=1
runtime_assert_dxmt_license || fail "0.81 should pass with COSMOS_ALLOW_LGPL=1"

bash "${ROOT}/scripts/test_offline_runtime.sh" || fail "offline runtime tests failed"

printf 'OK: runtime_lib tests passed\n'
