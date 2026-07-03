#!/usr/bin/env bash
# Release-readiness audit — bundled scripts, VERSION alignment, workflow wiring.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${APP_BUNDLE:-${ROOT}/build/Cosmos.app}"
RESOURCES="${APP_BUNDLE}/Contents/Resources"

fail() { printf 'AUDIT FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf '  ok  %s\n' "$1"; }

echo "Cosmos release audit"

version="$(tr -d '[:space:]' < "${ROOT}/VERSION")"
[[ -n "${version}" ]] || fail "VERSION is empty"
pass "VERSION=${version}"

grep -q -- '--install-update' "${ROOT}/run.command" || fail "run.command missing --install-update"
pass "CLI install-update flag wired"

grep -q -- '--install' "${ROOT}/scripts/check_updates.sh" || fail "check_updates.sh missing --install"
pass "check_updates --install flag present"

for script in check_updates.sh install_update.sh terminal_wrap.sh; do
  [[ -x "${ROOT}/scripts/${script}" ]] || fail "missing scripts/${script}"
done
[[ -f "${ROOT}/scripts/lib/release_lib.sh" ]] || fail "missing scripts/lib/release_lib.sh"
[[ -f "${ROOT}/scripts/fixtures/github_release_latest.json" ]] || fail "missing release fixture"
pass "update + terminal helper scripts executable"

[[ -f "${ROOT}/app/cosmos.entitlements" ]] || fail "missing app/cosmos.entitlements"
[[ -x "${ROOT}/scripts/sign_and_notarize.command" ]] || fail "missing sign_and_notarize.command"
[[ -f "${ROOT}/.github/workflows/release.yml" ]] || fail "missing release workflow"
pass "signing + release workflow present"

for swift in TerminalJobTracker.swift UpdateChecker.swift; do
  [[ -f "${ROOT}/app/${swift}" ]] || fail "missing app/${swift}"
done
pass "in-app update + terminal trackers present"

if [[ -d "${APP_BUNDLE}" ]]; then
  app_binary="${APP_BUNDLE}/Contents/MacOS/Cosmos"
  [[ -x "${app_binary}" ]] || fail "bundle missing executable Contents/MacOS/Cosmos"
  for script in check_updates.sh install_update.sh terminal_wrap.sh; do
    [[ -x "${RESOURCES}/scripts/${script}" ]] || fail "bundle missing Resources/scripts/${script}"
  done
  [[ -f "${RESOURCES}/VERSION" ]] || fail "bundle missing Resources/VERSION"
  bundled_version="$(tr -d '[:space:]' < "${RESOURCES}/VERSION")"
  [[ "${bundled_version}" == "${version}" ]] || fail "bundled VERSION ${bundled_version} != ${version}"
  pass "Cosmos.app bundles update scripts and VERSION"
  if [[ -n "${COSMOS_EXPECTED_APP_ARCHS:-}" ]]; then
    command -v lipo >/dev/null 2>&1 || fail "lipo required to verify COSMOS_EXPECTED_APP_ARCHS"
    binary_arches="$(lipo -archs "${app_binary}" 2>/dev/null || true)"
    [[ -n "${binary_arches}" ]] || fail "could not read app binary architectures"
    for expected_arch in ${COSMOS_EXPECTED_APP_ARCHS//,/ }; do
      [[ " ${binary_arches} " == *" ${expected_arch} "* ]] \
        || fail "Cosmos binary missing ${expected_arch}; found: ${binary_arches}"
    done
    pass "Cosmos.app executable architectures: ${binary_arches}"
  fi
else
  printf '  ..  Cosmos.app not built (set APP_BUNDLE to audit a bundle)\n'
fi

if [[ -n "${RELEASE_TAG:-}" ]]; then
  expected="${RELEASE_TAG#v}"
  [[ "${expected}" == "${version}" ]] || fail "tag ${RELEASE_TAG} does not match VERSION ${version}"
  pass "RELEASE_TAG matches VERSION"
fi

echo ""
echo "OK: release audit passed"
