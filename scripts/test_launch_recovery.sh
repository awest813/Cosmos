#!/usr/bin/env bash
# Tests for run.command's launch recovery/retry helper (run_launch_cmd). A small
# transient issue — most commonly a stale wineserver holding the prefix — should
# not stop a game from running: the launcher recovers and retries.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${TEST_DIR}/.." && pwd)"
# run.command derives its own SCRIPT_DIR from BASH_SOURCE; make sure ours does
# not leak in and point it at the wrong place.
unset SCRIPT_DIR

# Sandbox all side effects (steam.conf creation, launch log) into a temp dir so
# sourcing run.command never touches the real support directory.
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
export COSMOS_SUPPORT_DIR="${WORK}/support"
export COSMOS_BOTTLE=""
export COSMOS_LAUNCH_LOG="${WORK}/launch.log"

# Source the launcher; the BASH_SOURCE guard keeps main() from running.
# shellcheck source=/dev/null
source "${REPO_ROOT}/run.command"

# Replace the real recovery (which kills wineserver) with a counter so the tests
# stay hermetic and assert how often recovery was attempted.
RECOVER_CALLS=0
recover_wine_prefix() { RECOVER_CALLS=$((RECOVER_CALLS + 1)); }

pass=0
fail=0
check() {
  if [[ "$2" == "$3" ]]; then
    echo "  ok  $1"
    pass=$((pass + 1))
  else
    echo "  FAIL $1: expected '$3' got '$2'"
    fail=$((fail + 1))
  fi
}

# 1. Foreground success on the first try: no recovery.
RECOVER_CALLS=0; COSMOS_DETACH=0; COSMOS_LAUNCH_RETRIES=1
rc=0; run_launch_cmd "ok" 0 true >/dev/null 2>&1 || rc=$?
check "foreground success returns 0" "${rc}" "0"
check "foreground success skips recovery" "${RECOVER_CALLS}" "0"

# 2. Foreground hard failure: retries once, recovers once, still reports failure.
RECOVER_CALLS=0; COSMOS_DETACH=0; COSMOS_LAUNCH_RETRIES=1
rc=0; run_launch_cmd "fail" 0 false >/dev/null 2>&1 || rc=$?
check "foreground failure returns nonzero" "${rc}" "1"
check "foreground failure recovers once" "${RECOVER_CALLS}" "1"

# 3. Foreground flaky launch: fails once then succeeds -> recovers once, rc 0.
RECOVER_CALLS=0; COSMOS_DETACH=0; COSMOS_LAUNCH_RETRIES=1
marker="${WORK}/flaky"; rm -f "${marker}"
rc=0
run_launch_cmd "flaky" 0 bash -c 'm="$0"; if [[ -f "$m" ]]; then exit 0; fi; touch "$m"; exit 1' "${marker}" \
  >/dev/null 2>&1 || rc=$?
check "foreground flaky eventually succeeds" "${rc}" "0"
check "foreground flaky recovers once" "${RECOVER_CALLS}" "1"

# 4. Detached with retries disabled: fire-and-forget, returns 0 immediately.
RECOVER_CALLS=0; COSMOS_DETACH=1; COSMOS_LAUNCH_RETRIES=0
rc=0; run_launch_cmd "ff" 1 true >/dev/null 2>&1 || rc=$?
check "detached no-retry returns 0" "${rc}" "0"

# 5. Detached healthy process survives the grace window: rc 0, no recovery.
RECOVER_CALLS=0; COSMOS_DETACH=1; COSMOS_LAUNCH_RETRIES=1; COSMOS_LAUNCH_GRACE=2
rc=0; run_launch_cmd "healthy" 1 sleep 5 >/dev/null 2>&1 || rc=$?
check "detached healthy returns 0" "${rc}" "0"
check "detached healthy skips recovery" "${RECOVER_CALLS}" "0"

# 6. Detached crash-on-startup: dies within grace -> recover, retry, then fail.
RECOVER_CALLS=0; COSMOS_DETACH=1; COSMOS_LAUNCH_RETRIES=1; COSMOS_LAUNCH_GRACE=3
rc=0; run_launch_cmd "crash" 1 bash -c 'exit 3' >/dev/null 2>&1 || rc=$?
check "detached crash returns the exit code" "${rc}" "3"
check "detached crash recovers once" "${RECOVER_CALLS}" "1"

# 7. Steam-style detached launch (detach_retry=0) never grace-polls or retries,
#    so a bootstrapper that exits its first process is not misread as a crash.
RECOVER_CALLS=0; COSMOS_DETACH=1; COSMOS_LAUNCH_RETRIES=1; COSMOS_LAUNCH_GRACE=3
rc=0; run_launch_cmd "steam" 0 bash -c 'exit 3' >/dev/null 2>&1 || rc=$?
check "detached steam-style returns 0" "${rc}" "0"
check "detached steam-style skips recovery" "${RECOVER_CALLS}" "0"

echo ""
echo "Results: ${pass} passed, ${fail} failed"
[[ ${fail} -eq 0 ]] && echo "OK: launch recovery tests passed"
[[ ${fail} -eq 0 ]]
