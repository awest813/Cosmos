#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || fail "python3 required"

out="$(python3 "${ROOT}/scripts/umu_suggest_recipes.py" 1091500 --offline \
  --fixture "${ROOT}/scripts/fixtures/umu/protonfix-1091500.py")"
printf '%s\n' "${out}" | grep -q '^dep vcrun2019$' || fail "expected vcrun2019 dep"

fixes="$(python3 "${ROOT}/scripts/umu_suggest_recipes.py" 962130 --offline --json)"
printf '%s' "${fixes}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert "grounded-mscoree-fix" in d["fixes"], d
'

printf 'OK: umu suggest tests passed\n'
