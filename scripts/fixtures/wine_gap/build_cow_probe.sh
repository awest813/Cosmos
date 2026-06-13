#!/usr/bin/env bash
# Cross-compile cow_probe.exe for Wine #29384 validation (mingw-w64).
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="${ROOT}/cow_probe.c"
OUT="${ROOT}/cow_probe.exe"

if command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
  CC=x86_64-w64-mingw32-gcc
elif command -v mingw64-gcc >/dev/null 2>&1; then
  CC=mingw64-gcc
else
  echo "Install mingw-w64: brew install mingw-w64" >&2
  exit 1
fi

"${CC}" -O2 -static -o "${OUT}" "${SRC}"
echo "Built ${OUT}"
