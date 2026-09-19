#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then
  echo "SKIP: native macOS command runner smoke test"
  exit 0
fi
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
swiftc "${ROOT}/app/CosmosCommandRunner.swift" "${ROOT}/Tests/CommandRunnerSmoke.swift" -o "${WORK}/command-runner-test"
"${WORK}/command-runner-test"
