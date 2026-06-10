#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/graphics_lib.sh
source "${ROOT}/scripts/lib/graphics_lib.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

export RUNTIME_DXMT_LATEST_VERSION=0.81
export RUNTIME_DXMT_LATEST_URL='https://example.com/dxmt-v0.81-builtin.tar.gz'
unset DXMT_VERSION DXMT_URL COSMOS_ALLOW_LGPL

export COSMOS_DXMT_CHANNEL=latest
cosmos_dxmt_channel_apply
[[ "${DXMT_VERSION}" == "0.81" ]] || fail "latest channel should pin 0.81"
[[ "${COSMOS_ALLOW_LGPL}" == "1" ]] || fail "latest channel should allow LGPL"
[[ "${DXMT_URL}" == *"0.81"* ]] || fail "latest channel should set DXMT_URL"

unset DXMT_VERSION DXMT_URL
export COSMOS_DXMT_CHANNEL=experimental
cosmos_dxmt_channel_apply
[[ "${COSMOS_DXMT_CHANNEL}" == "latest" ]] || fail "experimental alias should normalize to latest"

printf 'OK: graphics_lib tests passed\n'
