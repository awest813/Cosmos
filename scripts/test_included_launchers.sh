#!/usr/bin/env bash
# The included-launcher build scripts print real binary paths.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

highball="${ROOT}/scripts/build_highball.command"
vermut="${ROOT}/scripts/build_vermut.command"

[[ -x "${highball}" ]] || fail "build_highball.command is not executable"
[[ -x "${vermut}" ]] || fail "build_vermut.command is not executable"
bash -n "${highball}"
bash -n "${vermut}"

grep -q 'third_party/highball/.build/release/highball' "${highball}" \
  || fail "Highball script should print the CLI path"
grep -q 'third_party/highball/.build/release/HighballApp' "${highball}" \
  || fail "Highball script should print the app path"
if grep -q 'echo "App: swift build' "${highball}"; then
  fail "Highball script should print the app binary, not a build command"
fi

grep -q 'third_party/vermut/.build/release/Vermut' "${vermut}" \
  || fail "Vermut script should print the app path"

grep -q 'scripts/build_highball.command' "${ROOT}/app/IncludedLaunchers.swift" \
  || fail "dashboard catalog should point at the Highball build script"
grep -q 'scripts/build_vermut.command' "${ROOT}/app/IncludedLaunchers.swift" \
  || fail "dashboard catalog should point at the Vermut build script"
grep -q 'Building Highball' "${ROOT}/app/CosmosOperationLabel.swift" \
  || fail "Highball build should have an operation title"
grep -q 'Building Vermut' "${ROOT}/app/CosmosOperationLabel.swift" \
  || fail "Vermut build should have an operation title"

printf 'OK: included launcher build scripts\n'
