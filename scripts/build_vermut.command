#!/bin/bash
# Build the vendored Vermut 1.2.0 app. macOS 14+ only.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}/third_party/vermut"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Vermut builds on macOS 14 or later. This machine is $(uname -s)." >&2
  exit 1
fi

swift build -c release "$@"
echo "App: ${ROOT}/third_party/vermut/.build/release/Vermut"
