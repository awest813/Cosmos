#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

support="${TMPDIR:-/tmp}/cosmos-terminal-wrap-$$"
export COSMOS_SUPPORT_DIR="${support}"
job_dir="${support}/terminal-jobs"
mkdir -p "${job_dir}"

job_id="test-job-$$"
"${ROOT}/scripts/terminal_wrap.sh" "${job_id}" -- /usr/bin/true
[[ -f "${job_dir}/${job_id}.exit" ]] || fail "missing exit file"
[[ "$(tr -d '[:space:]' < "${job_dir}/${job_id}.exit")" == "0" ]] || fail "expected exit 0"

job_id_fail="test-job-fail-$$"
set +e
"${ROOT}/scripts/terminal_wrap.sh" "${job_id_fail}" -- /usr/bin/false
rc=$?
set -e
[[ "${rc}" -eq 1 ]] || fail "wrapper should propagate exit code"
[[ "$(tr -d '[:space:]' < "${job_dir}/${job_id_fail}.exit")" == "1" ]] || fail "expected exit 1 on disk"

rm -rf "${support}"
printf 'OK: terminal_wrap tests passed\n'
