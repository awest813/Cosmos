#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="${ROOT}/scripts/fixtures/protonfix/bethesda_exe_swap.py"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

out="$(python3 "${ROOT}/scripts/protonfix_port_hint.py" 22380 --repo "${ROOT}" --json 2>/dev/null || true)"
# Network may be unavailable in CI — test local parser via inline python
parsed="$(python3 - "${ROOT}" "${FIX}" <<'PY'
import importlib.util
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location(
    "protonfix_port_hint", root / "scripts" / "protonfix_port_hint.py"
)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
text = Path(sys.argv[2]).read_text(encoding="utf-8")
print(json.dumps(mod.parse_fix(text)))
PY
)"

printf '%s' "${parsed}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["winetricks_verbs"] == ["vcrun2019"], d
assert d["suggested_dependencies"] == ["vcrun2019"], d
assert d["exe_replacements"] and d["exe_replacements"][0]["from"] == "FalloutNV.exe", d
'

"${ROOT}/profile.command" validate >/dev/null \
  || fail "profiles failed validate after protonfix note updates"

chmod +x "${ROOT}/scripts/import_macos_wine_steam.sh"
"${ROOT}/scripts/import_macos_wine_steam.sh" --dry-run >/dev/null \
  || fail "import_macos_wine_steam dry-run failed"

draft_out="$("${ROOT}/scripts/import_macos_wine_steam.sh" 2>&1)"
case "${draft_out}" in
  *"steam-250900"*) ;;
  *) fail "expected binding of isaac draft for app 250900: ${draft_out}" ;;
esac

[[ -f "${ROOT}/profiles/drafts/steam-250900-binding-of-isaac-rebirth.yaml" ]] \
  || [[ -f "${ROOT}/profiles/drafts/steam-250900-binding-of-isaac.yaml" ]] \
  || fail "missing binding of isaac draft"

printf 'OK: protonfix port + macos-wine-steam import tests passed\n'
