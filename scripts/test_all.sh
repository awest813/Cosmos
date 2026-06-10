#!/usr/bin/env bash
# Full local test suite — mirrors .github/workflows/ci.yml shell job + extras.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

log() { printf '\n==> %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

log "bash syntax check"
status=0
while IFS= read -r -d '' file; do
  bash -n "${file}" || status=1
done < <(find . -type f \( -name '*.command' -o -name '*.sh' \) -print0)
(( status == 0 )) || fail "bash syntax errors"

UNIT_TESTS=(
  scripts/test_steam_detection.sh
  scripts/test_steam_sync.sh
  scripts/test_profile_lib.sh
  scripts/test_sync_lib.sh
  scripts/test_gptk_lib.sh
  scripts/test_graphics_lib.sh
  scripts/test_profiles.sh
  scripts/test_anticheat_profiles.sh
  scripts/test_repair_diagnose.sh
  scripts/test_import_winemactricks.sh
  scripts/test_profile_apply_installed.sh
  scripts/test_check_updates.sh
  scripts/test_release_lib.sh
  scripts/test_terminal_wrap.sh
  scripts/test_install_update.sh
  scripts/audit_phases.sh
  scripts/audit_release.sh
  scripts/test_protonfix_port_hint.sh
  scripts/test_import_lib.sh
  scripts/test_library_lib.sh
  scripts/test_launch_recovery.sh
  scripts/test_compat_preflight.sh
  scripts/test_rosetta_lib.sh
  scripts/test_wine_lib.sh
  scripts/test_cosmosdb_lib.sh
  scripts/test_runtime_lib.sh
  scripts/test_offline_runtime.sh
  scripts/test_cosmosdb_community.sh
  scripts/test_profile_export_reg.sh
  scripts/test_seed_winemactricks_profiles.sh
  scripts/test_umu_suggest.sh
)

for t in "${UNIT_TESTS[@]}"; do
  log "${t}"
  "./${t}"
done

if command -v python3 >/dev/null 2>&1; then
  log "VDF python cross-check"
  pip install -q vdf 2>/dev/null || pip install vdf
  ./scripts/verify_vdf_python.sh
fi

log "winemactricks upstream sync (dry-run)"
./scripts/import_winemactricks.sh --sync --dry-run >/dev/null

log "CLI smoke: profile validate"
./profile.command validate >/dev/null

log "CLI smoke: check-update (fixture)"
COSMOS_RELEASE_FIXTURE="${ROOT}/scripts/fixtures/github_release_latest.json" \
  ./run.command --check-update >/dev/null || true

log "CLI smoke: sync-steam dry-run (fixture prefix)"
COSMOS_SUPPORT_DIR="${TMPDIR:-/tmp}/cosmos-sync-steam-smoke-$$" \
  COSMOS_CONFIGS_DIR="${COSMOS_SUPPORT_DIR}/cosmos_configs" \
  COSMOS_SYNC_DRY_RUN=1 WINEPREFIX="${ROOT}/scripts/fixtures/steam_detection/wineprefix" \
  ./run.command --sync-steam >/dev/null
rm -rf "${COSMOS_SUPPORT_DIR:-}"

log "CLI smoke: apply-installed dry-run (fixture prefix)"
WINEPREFIX="${ROOT}/scripts/fixtures/steam_detection/wineprefix" \
  ./profile.command apply-installed --dry-run >/dev/null

if [[ "$(uname -s)" == "Darwin" ]] && command -v swift >/dev/null 2>&1; then
  log "swift build (debug)"
  swift build
  log "swift build (release)"
  swift build -c release
  log "swift test"
  swift test
else
  printf 'SKIP: swift build/test requires macOS (AppKit) — covered by the macos-14 CI job\n'
fi

log "All tests passed"
