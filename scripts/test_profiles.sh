#!/usr/bin/env bash
set -euo pipefail

# Schema-validation tests for the shipped game profiles (roadmap 0.4).
# Asserts every profile under profiles/** passes `profile.command validate`
# (required fields, valid enums, filename/appid match, referenced recipes
# exist) and that the validator rejects a deliberately broken profile.

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_CMD="${ROOT}/profile.command"
# shellcheck source=scripts/lib/profile_lib.sh
source "${ROOT}/scripts/lib/profile_lib.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# All shipped profiles validate.
"${PROFILE_CMD}" validate >/dev/null 2>&1 \
  || fail "shipped profiles did not pass 'profile.command validate'"

# The validator rejects a broken profile (bad status/backend + missing recipe).
tmp="$(mktemp -t cosmos_profile_XXXX).yaml"
trap 'rm -f "${tmp}"' EXIT
cat > "${tmp}" <<'EOF'
id: broken
name: "Broken"
store: steam
steam_appid: 999999
status: notastatus
recommended_backend: notabackend
wine_version: cosmos-stable
dependencies:
  - this_recipe_does_not_exist
EOF
if "${PROFILE_CMD}" validate "${tmp}" >/dev/null 2>&1; then
  fail "validator accepted a broken profile"
fi

count="$(profile_shipped_paths "${ROOT}/profiles" | wc -l | tr -d ' ')"
printf 'OK: all %s shipped profiles passed schema validation\n' "${count}"
