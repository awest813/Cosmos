#!/usr/bin/env bash
# Helpers for runtime/wine-gap-validation.json ↔ cosmos-runtime.json sync.

WINE_GAP_ROOT=""
WINE_GAP_MANIFEST_PATH=""
WINE_GAP_VALIDATION_PATH=""

wine_gap_init() {
  local root="$1"
  [[ -n "${root}" ]] || return 1
  WINE_GAP_ROOT="${root}"
  WINE_GAP_MANIFEST_PATH="${root}/runtime/cosmos-runtime.json"
  WINE_GAP_VALIDATION_PATH="${root}/runtime/wine-gap-validation.json"
}

wine_gap_manifest_wine_version() {
  python3 - "${WINE_GAP_MANIFEST_PATH}" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
print(data["components"]["wine"]["version"])
PY
}

wine_gap_pinned_version() {
  python3 - "${WINE_GAP_VALIDATION_PATH}" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
print(data.get("pinned_wine_version", ""))
PY
}

wine_gap_gap_status() {
  local gap_id="$1"
  python3 - "${WINE_GAP_VALIDATION_PATH}" "${gap_id}" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
gap = (data.get("gaps") or {}).get(sys.argv[2]) or {}
print(gap.get("status", "missing"))
PY
}

wine_gap_sync_check() {
  [[ -f "${WINE_GAP_MANIFEST_PATH}" ]] || { printf 'FAIL: missing %s\n' "${WINE_GAP_MANIFEST_PATH}" >&2; return 1; }
  [[ -f "${WINE_GAP_VALIDATION_PATH}" ]] || { printf 'FAIL: missing %s\n' "${WINE_GAP_VALIDATION_PATH}" >&2; return 1; }

  python3 - "${WINE_GAP_MANIFEST_PATH}" "${WINE_GAP_VALIDATION_PATH}" <<'PY' || return 1
import json, sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text())
validation = json.loads(Path(sys.argv[2]).read_text())

if validation.get("schema") != "cosmos-wine-gap-validation-1":
    raise SystemExit("FAIL: invalid wine-gap-validation schema")

wine_ver = manifest["components"]["wine"]["version"]
pin = validation.get("pinned_wine_version")
if pin != wine_ver:
    raise SystemExit(
        f"FAIL: Gcenx pin mismatch — cosmos-runtime.json wine={wine_ver} "
        f"but wine-gap-validation.json pinned_wine_version={pin}. "
        f"After bumping the manifest, set pinned_wine_version={wine_ver}, "
        f"reset wine_29384 status to untested, run ./scripts/validate_wine_gaps.sh probe "
        f"on macOS, then record results. See docs/WINE_GAP_VALIDATION.md"
    )

gap = (validation.get("gaps") or {}).get("wine_29384_virtualprotect_cow")
if not gap:
    raise SystemExit("FAIL: missing gaps.wine_29384_virtualprotect_cow")

status = gap.get("status")
if status not in ("pass", "fail", "untested", "mitigated"):
    raise SystemExit(f"FAIL: invalid wine_29384 status: {status!r}")
PY
  return 0
}

wine_gap_record_gap() {
  local gap_id="$1" status="$2" notes="${3:-}"
  python3 - "${WINE_GAP_VALIDATION_PATH}" "${gap_id}" "${status}" "${notes}" <<'PY'
import json, sys
from datetime import date
from pathlib import Path

path = Path(sys.argv[1])
gap_id, status, notes = sys.argv[2:5]
data = json.loads(path.read_text())
gaps = data.setdefault("gaps", {})
gap = gaps.setdefault(gap_id, {})
gap["status"] = status
if notes:
    gap["notes"] = notes
data["last_reviewed"] = date.today().isoformat()
path.write_text(json.dumps(data, indent=2) + "\n")
PY
}

wine_gap_record_test() {
  local gap_id="$1" test_id="$2" status="$3" notes="${4:-}"
  python3 - "${WINE_GAP_VALIDATION_PATH}" "${gap_id}" "${test_id}" "${status}" "${notes}" <<'PY'
import json, sys
from datetime import date
from pathlib import Path

path = Path(sys.argv[1])
gap_id, test_id, status, notes = sys.argv[2:6]
data = json.loads(path.read_text())
gap = data.setdefault("gaps", {}).setdefault(gap_id, {})
tests = gap.setdefault("tests", {})
entry = tests.setdefault(test_id, {})
entry["status"] = status
if notes:
    entry["notes"] = notes
data["last_reviewed"] = date.today().isoformat()
path.write_text(json.dumps(data, indent=2) + "\n")
PY
}
