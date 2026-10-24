#!/bin/bash
# Build the vendored Highball CLI and app. macOS 14+ only.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}/third_party/highball"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Highball builds on macOS 14 or later. This machine is $(uname -s)." >&2
  exit 1
fi

swift build -c release "$@"
echo "CLI: ${ROOT}/third_party/highball/.build/release/highball"
echo "App: swift build -c release --product HighballApp"
