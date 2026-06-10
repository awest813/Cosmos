#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="${ROOT}/scripts/fixtures/github_release_latest.json"
# shellcheck source=scripts/lib/release_lib.sh
source "${ROOT}/scripts/lib/release_lib.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tag="$(COSMOS_RELEASE_FIXTURE="${FIXTURE}" release_lib_latest_tag)" \
  || fail "fixture tag lookup failed"
[[ "${tag}" == "99.0.0-fixture" ]] || fail "unexpected fixture tag: ${tag}"

url="$(COSMOS_RELEASE_FIXTURE="${FIXTURE}" release_lib_asset_url "Cosmos.dmg")" \
  || fail "fixture asset lookup failed"
[[ "${url}" == "https://example.com/fixtures/Cosmos.dmg" ]] || fail "unexpected asset url: ${url}"

printf 'OK: release_lib tests passed\n'
