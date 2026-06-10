#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/profile_lib.sh
source "${ROOT}/scripts/lib/profile_lib.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

python3 "${ROOT}/scripts/anticheat_profile_audit.py" --repo "${ROOT}" \
  || fail "anticheat profile audit failed"

"${ROOT}/profile.command" anticheat-audit >/dev/null \
  || fail "profile.command anticheat-audit failed"

blocked=0
while IFS= read -r f; do
  [[ -n "${f}" ]] || continue
  if grep -qE '^status:[[:space:]]*blocked[[:space:]]*$' "${f}"; then
    blocked=$((blocked + 1))
  fi
done < <(profile_shipped_paths "${ROOT}/profiles")

(( blocked >= 20 )) || fail "expected at least 20 blocked profiles, found ${blocked}"

for appid in 1085660 252490 1172470 578080 381210 359550; do
  status="$(profile_status_for_appid "${ROOT}/profiles" "${appid}")" \
    || fail "missing profile for blocked appid ${appid}"
  [[ "${status}" == "blocked" ]] \
    || fail "appid ${appid} should be blocked, got ${status}"
done

# Online-only titles must warn but stay playable-tier.
for appid in 1245620 271590 1174180; do
  status="$(profile_status_for_appid "${ROOT}/profiles" "${appid}")" \
    || fail "missing profile for online_only appid ${appid}"
  [[ "${status}" != "blocked" ]] \
    || fail "appid ${appid} is online_only and should not be fully blocked"
done

printf 'OK: anti-cheat profile tests passed (%s blocked profiles)\n' "${blocked}"
