#!/usr/bin/env bash
# Wrap a Terminal-launched Cosmos helper so the desktop app can read exit status.
# Writes ~/Library/Application Support/Cosmos/terminal-jobs/<job_id>.exit when done.
set -euo pipefail

if (($# < 3)) || [[ "$2" != "--" ]]; then
  echo "Usage: scripts/terminal_wrap.sh <job_id> -- <command> [args...]" >&2
  exit 2
fi

job_id="$1"
shift 2

support_dir="${COSMOS_SUPPORT_DIR:-$HOME/Library/Application Support/Cosmos}"
job_dir="${support_dir}/terminal-jobs"
mkdir -p "${job_dir}"

state_file="${job_dir}/${job_id}.state"
exit_file="${job_dir}/${job_id}.exit"
meta_file="${job_dir}/${job_id}.meta"

printf 'running\n' >"${state_file}"
{
  printf 'pid=%s\n' "$$"
  printf 'started=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [[ -n "${COSMOS_TERMINAL_LABEL:-}" ]] && printf 'label=%s\n' "${COSMOS_TERMINAL_LABEL}"
} >"${meta_file}"

set +e
"$@"
exit_code=$?
set -e

printf '%s\n' "${exit_code}" >"${exit_file}"
rm -f "${state_file}"

printf '\nCosmos: command finished with exit status %s.\n' "${exit_code}"
printf 'Return to Cosmos — the dashboard will update automatically.\n'
exit "${exit_code}"
