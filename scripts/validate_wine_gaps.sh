#!/usr/bin/env bash
# Wine gap validation — sync manifest pin with runtime/wine-gap-validation.json
# and optional macOS synthetic probe for Wine #29384.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/wine_gap_lib.sh
source "${ROOT}/scripts/lib/wine_gap_lib.sh"
wine_gap_init "${ROOT}"

die() { printf 'Error: %s\n' "$1" >&2; exit 1; }

usage() {
  cat <<'EOF'
Wine gap validation (Wine #29384 VirtualProtect COW vs Gcenx pin).

Usage:
  validate_wine_gaps.sh check              CI: manifest ↔ validation JSON sync
  validate_wine_gaps.sh status             Human-readable gap summary
  validate_wine_gaps.sh manual-checklist   macOS manual test steps
  validate_wine_gaps.sh probe [--wine PATH] Run cow_probe.exe under Wine (macOS)
  validate_wine_gaps.sh record <gap> <pass|fail|untested|mitigated> [notes]
  validate_wine_gaps.sh record-test <gap> <test_id> <pass|fail|untested> [notes]

Environment:
  COSMOS_ENFORCE_WINE_GAP=1   Fail check when #29384 status is untested
  WINE                        Wine binary for probe (default: discover Gcenx install)

When bumping runtime/cosmos-runtime.json wine.version:
  1. ./validate_wine_gaps.sh check          (will fail until JSON updated)
  2. Set wine_29384 status to untested in runtime/wine-gap-validation.json
  3. ./validate_wine_gaps.sh probe          (macOS + Rosetta + mingw probe)
  4. Run manual-checklist SKSE/F4SE/Steam CEF
  5. ./validate_wine_gaps.sh record wine_29384 pass|fail "..."

See docs/WINE_GAP_VALIDATION.md
EOF
}

cmd_check() {
  wine_gap_sync_check || return 1
  local gap_status
  gap_status="$(wine_gap_gap_status wine_29384_virtualprotect_cow)"
  if [[ "${gap_status}" == "untested" ]]; then
    printf 'WARN: Wine #29384 status is untested for pinned Gcenx build\n' >&2
    [[ "${COSMOS_ENFORCE_WINE_GAP:-0}" == "1" ]] && return 1
  fi
  if [[ "${gap_status}" == "pass" ]]; then
    printf 'OK: Wine #29384 marked pass on pin %s\n' "$(wine_gap_pinned_version)"
  else
    printf 'OK: wine gap validation in sync (Wine #29384 status=%s on pin %s)\n' \
      "${gap_status}" "$(wine_gap_pinned_version)"
  fi
  return 0
}

cmd_status() {
  wine_gap_sync_check || true
  python3 - "${WINE_GAP_VALIDATION_PATH}" "${WINE_GAP_MANIFEST_PATH}" <<'PY'
import json, sys
from pathlib import Path

val = json.loads(Path(sys.argv[1]).read_text())
manifest = json.loads(Path(sys.argv[2]).read_text())
wine_ver = manifest["components"]["wine"]["version"]
pin = val.get("pinned_wine_version", "?")
print(f"Gcenx Wine pin: {wine_ver} (validation JSON: {pin})")
print(f"Last reviewed: {val.get('last_reviewed', 'n/a')} by {val.get('reviewer', 'n/a')}")
print()
for key, gap in (val.get("gaps") or {}).items():
    print(f"[{gap.get('status', '?').upper()}] {key}")
    if gap.get("title"):
        print(f"  {gap['title']}")
    if gap.get("winehq"):
        print(f"  {gap['winehq']}")
    if gap.get("notes"):
        print(f"  {gap['notes']}")
    tests = gap.get("tests") or {}
    for tid, t in tests.items():
        st = t.get("status", "n/a")
        print(f"  - {tid}: {st}")
    print()
PY
}

cmd_manual_checklist() {
  cat <<'EOF'
=== macOS manual checklist (after Gcenx Wine pin bump) ===

Prerequisites
  - Rosetta 2 on Apple Silicon: softwareupdate --install-rosetta
  - Gcenx Wine extracted (./run.command --setup-steam or offline bundle)
  - Optional: brew install mingw-w64 && ./scripts/fixtures/wine_gap/build_cow_probe.sh

1) Synthetic probe (Wine #29384)
   ./scripts/validate_wine_gaps.sh probe
   Expect exit 2 on unfixed Gcenx (cow_lost). Exit 0 → update validation JSON to pass.

2) Skyrim SE + SKSE (489830)
   - Install SKSE into the game folder (skse64_loader.exe present)
   - ./profile.command apply profiles/steam/steam-489830-skyrim-se.yaml
   - Launch via Cosmos; confirm SKSE loads (console ~ version, mods active)

3) Fallout 4 + F4SE (377160)
   - Same pattern with f4se_loader.exe and steam-377160-fallout-4.yaml

4) Steam CEF regression
   - ./run.command --steam
   - Confirm Steam library UI loads (steamwebhelper builtin D3D overrides intact)

5) Record results
   ./scripts/validate_wine_gaps.sh record wine_29384_virtualprotect_cow pass "Gcenx X.Y probe+SKSE"
   ./scripts/validate_wine_gaps.sh record-test wine_29384_virtualprotect_cow synthetic_cow_probe pass

6) CI
   ./scripts/validate_wine_gaps.sh check
   ./scripts/test_wine_gap_validation.sh
EOF
}

wine_gap_find_wine() {
  local candidate="${1:-}"
  if [[ -n "${candidate}" && -x "${candidate}" ]]; then
    printf '%s' "${candidate}"
    return 0
  fi
  if [[ -n "${WINE:-}" && -x "${WINE}" ]]; then
    printf '%s' "${WINE}"
    return 0
  fi
  local ver home
  ver="$(wine_gap_manifest_wine_version)"
  home="${WINE_VERSION:+${HOME}/wine-${WINE_VERSION}}"
  home="${home:-${HOME}/wine-${ver}}"
  candidate="${home}/Wine Devel.app/Contents/Resources/wine/bin/wine64"
  [[ -x "${candidate}" ]] && { printf '%s' "${candidate}"; return 0; }
  candidate="${home}/Wine Devel.app/Contents/Resources/wine/bin/wine"
  [[ -x "${candidate}" ]] && { printf '%s' "${candidate}"; return 0; }
  return 1
}

cmd_probe() {
  local wine_bin="" probe="${ROOT}/scripts/fixtures/wine_gap/cow_probe.exe"
  while (($#)); do
    case "$1" in
      --wine) wine_bin="$2"; shift 2 ;;
      *) die "unknown probe arg: $1" ;;
    esac
  done

  [[ "$(uname -s)" == "Darwin" ]] || die "probe requires macOS (Gcenx Wine is osx64)"

  if [[ ! -f "${probe}" ]]; then
    if [[ -x "${ROOT}/scripts/fixtures/wine_gap/build_cow_probe.sh" ]]; then
      "${ROOT}/scripts/fixtures/wine_gap/build_cow_probe.sh"
    fi
  fi
  [[ -f "${probe}" ]] || die "missing ${probe}; run build_cow_probe.sh"

  wine_bin="$(wine_gap_find_wine "${wine_bin}")" \
    || die "Wine not found; set WINE or install Gcenx Wine via run.command"

  printf '==> cow_probe via %s\n' "${wine_bin}"
  local rc=0
  if [[ "$(uname -m)" == "arm64" ]]; then
    arch -x86_64 "${wine_bin}" "${probe}" || rc=$?
  else
    "${wine_bin}" "${probe}" || rc=$?
  fi

  local expected
  expected="$(wine_gap_gap_status wine_29384_virtualprotect_cow)"
  case "${rc}" in
    0)
      printf 'probe: PASS (COW preserved)\n'
      if [[ "${expected}" == "fail" ]]; then
        printf 'ACTION: Wine #29384 may be fixed — update runtime/wine-gap-validation.json to pass\n' >&2
      fi
      ;;
    2)
      printf 'probe: FAIL (COW lost — Wine #29384 still present)\n'
      if [[ "${expected}" == "pass" ]]; then
        die "REGRESSION: validation JSON says pass but probe failed"
      fi
      ;;
    *)
      printf 'probe: ERROR exit=%s\n' "${rc}" >&2
      ;;
  esac
  return "${rc}"
}

cmd_record() {
  local gap="$1" status="$2"
  shift 2
  local notes="${*:-}"
  wine_gap_record_gap "${gap}" "${status}" "${notes}"
  printf 'Recorded %s → %s\n' "${gap}" "${status}"
}

cmd_record_test() {
  local gap="$1" test_id="$2" status="$3"
  shift 3
  local notes="${*:-}"
  wine_gap_record_test "${gap}" "${test_id}" "${status}" "${notes}"
  printf 'Recorded %s.%s → %s\n' "${gap}" "${test_id}" "${status}"
}

main() {
  local cmd="${1:-check}"
  shift || true
  case "${cmd}" in
    check) cmd_check ;;
    status) cmd_status ;;
    manual-checklist|checklist) cmd_manual_checklist ;;
    probe) cmd_probe "$@" ;;
    record) (($# >= 2)) || die "usage: record <gap_id> <status> [notes]"; cmd_record "$@" ;;
    record-test) (($# >= 3)) || die "usage: record-test <gap_id> <test_id> <status> [notes]"; cmd_record_test "$@" ;;
    -h|--help|help) usage ;;
    *) die "unknown command: ${cmd}" ;;
  esac
}

main "$@"
