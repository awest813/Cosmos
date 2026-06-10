#!/usr/bin/env bash
# Guard docs/PLAN.md tracking metrics — run in CI after profile/recipe changes.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILES_STEAM="${ROOT}/profiles/steam"
FIXES_DIR="${ROOT}/recipes/fixes"
DEPS_DIR="${ROOT}/recipes/dependencies"

fail() { printf 'AUDIT FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf '  ok  %s\n' "$1"; }

count_shipped_steam() {
  find "${PROFILES_STEAM}" -maxdepth 1 -name 'steam-*.yaml' 2>/dev/null | wc -l | tr -d ' '
}

count_with_fixes() {
  rg -l '^fixes:' "${PROFILES_STEAM}"/*.yaml 2>/dev/null | wc -l | tr -d ' '
}

count_blocked() {
  rg -l '^status: blocked' "${PROFILES_STEAM}"/*.yaml 2>/dev/null | wc -l | tr -d ' '
}

count_multiplayer_tagged() {
  python3 - "${PROFILES_STEAM}" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
tags = {"co-op", "online", "lan", "pvp"}
n = 0
for p in root.glob("steam-*.yaml"):
    text = p.read_text(encoding="utf-8", errors="replace")
    block = ""
    in_tags = False
    for line in text.splitlines():
        if line.startswith("tags:"):
            in_tags = True
            block = line
            continue
        if in_tags:
            if line.startswith(" ") and not line.strip().startswith("-"):
                in_tags = False
            else:
                block += "\n" + line
                continue
        in_tags = False
    if any(t in block for t in tags):
        n += 1
print(n)
PY
}

count_fix_recipes() {
  find "${FIXES_DIR}" -maxdepth 1 -name '*.recipe' 2>/dev/null | wc -l | tr -d ' '
}

count_dep_recipes() {
  find "${DEPS_DIR}" -maxdepth 1 -name '*.recipe' 2>/dev/null | wc -l | tr -d ' '
}

echo "Cosmos phase metric audit"
steam_n="$(count_shipped_steam)"
fixes_n="$(count_with_fixes)"
blocked_n="$(count_blocked)"
mp_n="$(count_multiplayer_tagged)"
fix_recipes_n="$(count_fix_recipes)"
dep_recipes_n="$(count_dep_recipes)"

(( steam_n >= 100 )) || fail "shipped steam profiles: ${steam_n} (need 100+)"
pass "shipped steam profiles: ${steam_n}"

(( fixes_n >= 30 )) || fail "profiles with fixes: ${fixes_n} (need 30+)"
pass "profiles with fixes: ${fixes_n}"

(( blocked_n >= 25 )) || fail "blocked profiles: ${blocked_n} (need 25+)"
pass "blocked anti-cheat profiles: ${blocked_n}"

(( mp_n >= 15 )) || fail "multiplayer-tagged profiles: ${mp_n} (need 15+)"
pass "multiplayer-tagged profiles: ${mp_n}"

(( fix_recipes_n >= 25 )) || fail "fix recipes: ${fix_recipes_n} (need 25+)"
pass "fix recipes: ${fix_recipes_n}"

(( dep_recipes_n >= 6 )) || fail "dependency recipes: ${dep_recipes_n} (need 6+)"
pass "dependency recipes: ${dep_recipes_n}"

[[ -f "${ROOT}/VERSION" ]] || fail "missing VERSION file"
pass "VERSION file present ($(tr -d '[:space:]' < "${ROOT}/VERSION"))"

[[ -x "${ROOT}/scripts/check_updates.sh" ]] || fail "missing scripts/check_updates.sh"
pass "update check script present"

[[ -f "${ROOT}/runtime/cosmos-runtime.json" ]] || fail "missing runtime/cosmos-runtime.json"
pass "runtime manifest present"

echo ""
echo "OK: phase metric audit passed (${fix_recipes_n} fix + ${dep_recipes_n} dep recipes)"
