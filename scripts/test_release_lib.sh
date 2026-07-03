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

arm_url="$(COSMOS_RELEASE_FIXTURE="${FIXTURE}" release_lib_asset_url "Cosmos-macos-arm64.dmg")" \
  || fail "fixture arm64 asset lookup failed"
[[ "${arm_url}" == "https://example.com/fixtures/Cosmos-macos-arm64.dmg" ]] \
  || fail "unexpected arm64 asset url: ${arm_url}"

default_asset="$(release_lib_default_dmg_asset)"
if [[ "$(uname -s)" == "Darwin" ]]; then
  case "$(uname -m)" in
    arm64) expected_default="Cosmos-macos-arm64.dmg" ;;
    x86_64) expected_default="Cosmos-macos-x86_64.dmg" ;;
    *) expected_default="Cosmos.dmg" ;;
  esac
else
  expected_default="Cosmos.dmg"
fi
[[ "${default_asset}" == "${expected_default}" ]] || fail "unexpected default asset: ${default_asset}"

printf 'OK: release_lib tests passed\n'
