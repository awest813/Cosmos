#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="${ROOT}/scripts/fixtures/github_release_latest.json"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "${FIXTURE}" ]] || fail "missing fixture ${FIXTURE}"

# Offline: default output shape (no network).
out="$("${ROOT}/scripts/check_updates.sh" 2>/dev/null)" || true
printf '%s\n' "${out}" | grep -q '^app_version=' || fail "expected app_version line"
printf '%s\n' "${out}" | grep -q '^runtime_version=' || fail "expected runtime_version line"
printf '%s\n' "${out}" | grep -q '^status=' || fail "expected status line"

json="$("${ROOT}/scripts/check_updates.sh" --json 2>/dev/null)" || true
printf '%s\n' "${json}" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "app_version" in d and "status" in d'

# Hermetic: fixture release newer than local VERSION -> exit 2 + update_available.
rc=0
fixture_json="$(
  COSMOS_RELEASE_FIXTURE="${FIXTURE}" "${ROOT}/scripts/check_updates.sh" --json 2>/dev/null
)" || rc=$?
[[ "${rc}" -eq 2 ]] || fail "fixture newer release should exit 2 (got ${rc})"
printf '%s\n' "${fixture_json}" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["status"]=="update_available", d'

# Hermetic: matching version -> current.
local_ver="$(tr -d "[:space:]" < "${ROOT}/VERSION")"
match_fixture="$(mktemp)"
trap 'rm -f "${match_fixture}"' EXIT
python3 - "${match_fixture}" "${local_ver}" <<'PY'
import json, sys
path, ver = sys.argv[1], sys.argv[2]
json.dump({"tag_name": f"v{ver}", "assets": []}, open(path, "w"))
PY
rc=0
COSMOS_RELEASE_FIXTURE="${match_fixture}" "${ROOT}/scripts/check_updates.sh" --json >/dev/null 2>&1 || rc=$?
[[ "${rc}" -eq 0 ]] || fail "matching fixture should exit 0 (got ${rc})"

printf 'OK: check_updates tests passed\n'
