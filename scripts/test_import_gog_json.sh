#!/usr/bin/env bash
# Tests import_game.command list-gog --json output.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
FIXTURE_PREFIX="${REPO_ROOT}/scripts/fixtures/gog_detection/wineprefix"

pass=0
fail=0

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "${haystack}" | grep -Fq "${needle}"; then
    pass=$((pass + 1))
    printf '  ok  %s\n' "${label}"
  else
    fail=$((fail + 1))
    printf '  FAIL %s (missing %q)\n' "${label}" "${needle}" >&2
  fi
}

WINEPREFIX="${FIXTURE_PREFIX}" \
  "${REPO_ROOT}/import_game.command" list-gog --json > /tmp/cosmos-gog.json 2>/dev/null || true

json="$(cat /tmp/cosmos-gog.json 2>/dev/null || true)"
if python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d, list)' <<<"${json}" 2>/dev/null; then
  pass=$((pass + 1))
  count="$(python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' <<<"${json}")"
  printf '  ok  parsed json array (%s game(s))\n' "${count}"
  if python3 -c 'import json,sys; d=json.load(sys.stdin); assert all("exe_source" in g for g in d)' <<<"${json}" 2>/dev/null; then
    pass=$((pass + 1))
    printf '  ok  json includes exe_source metadata\n'
  else
    fail=$((fail + 1))
    printf '  FAIL json missing exe_source\n' >&2
  fi
  if python3 -c 'import json,sys; d=json.load(sys.stdin); assert all("config_registered" in g for g in d)' <<<"${json}" 2>/dev/null; then
    pass=$((pass + 1))
    printf '  ok  json includes config_registered\n'
  else
    fail=$((fail + 1))
    printf '  FAIL json missing config_registered\n' >&2
  fi
else
  fail=$((fail + 1))
  printf '  FAIL list-gog --json did not return a JSON array\n' >&2
fi

find_json="$(WINEPREFIX="${FIXTURE_PREFIX}" \
  "${REPO_ROOT}/import_game.command" find-exe "drive_c/GOG Games/The Witcher 3 Wild Hunt" --json 2>/dev/null || true)"
if python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("exe_rel") and d.get("source")' <<<"${find_json}" 2>/dev/null; then
  pass=$((pass + 1))
  printf '  ok  find-exe --json returns structured output\n'
else
  fail=$((fail + 1))
  printf '  FAIL find-exe --json\n' >&2
fi
case "${find_json}" in
  *'"source": "goggame-info"'*) pass=$((pass + 1)); printf '  ok  find-exe prefers goggame metadata\n' ;;
  *) fail=$((fail + 1)); printf '  FAIL find-exe goggame source\n' >&2 ;;
esac

printf '\nResults: %s passed, %s failed\n' "${pass}" "${fail}"
[[ "${fail}" -eq 0 ]]
