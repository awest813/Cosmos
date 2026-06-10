#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

out="$("${ROOT}/scripts/check_updates.sh" 2>&1)" || true
printf '%s\n' "${out}" | grep -q '^app_version=' || fail "expected app_version line"
printf '%s\n' "${out}" | grep -q '^runtime_version=' || fail "expected runtime_version line"
printf '%s\n' "${out}" | grep -q '^status=' || fail "expected status line"

json="$("${ROOT}/scripts/check_updates.sh" --json 2>&1)" || true
printf '%s\n' "${json}" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "app_version" in d and "status" in d'

printf 'OK: check_updates tests passed\n'
