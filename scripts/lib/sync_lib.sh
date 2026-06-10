#!/usr/bin/env bash
# Thread-sync mode helpers (Phase E). Maps COSMOS_SYNC_MODE to Wine env vars.

cosmos_sync_mode_normalize() {
  local mode="${1:-off}"
  case "${mode}" in
    off|esync|msync) printf '%s' "${mode}" ;;
    *) printf '%s' "off" ;;
  esac
}

# Infer COSMOS_SYNC_MODE from legacy WINEESYNC/WINEMSYNC when unset.
cosmos_sync_mode_from_legacy() {
  if [[ -n "${COSMOS_SYNC_MODE:-}" ]]; then
    return 0
  fi
  if [[ "${WINEMSYNC:-}" == "1" ]]; then
    COSMOS_SYNC_MODE="msync"
    return 0
  fi
  if [[ "${WINEESYNC:-}" == "1" ]]; then
    COSMOS_SYNC_MODE="esync"
    return 0
  fi
  COSMOS_SYNC_MODE="off"
}

# Apply COSMOS_SYNC_MODE to WINEESYNC/WINEMSYNC exports.
cosmos_sync_mode_apply() {
  cosmos_sync_mode_from_legacy
  COSMOS_SYNC_MODE="$(cosmos_sync_mode_normalize "${COSMOS_SYNC_MODE}")"
  case "${COSMOS_SYNC_MODE}" in
    esync)
      export WINEESYNC=1
      unset WINEMSYNC
      ;;
    msync)
      export WINEMSYNC=1
      unset WINEESYNC
      ;;
    off)
      unset WINEESYNC WINEMSYNC
      ;;
  esac
}

cosmos_sync_mode_label() {
  cosmos_sync_mode_from_legacy
  case "$(cosmos_sync_mode_normalize "${COSMOS_SYNC_MODE}")" in
    esync) printf '%s' "esync (WINEESYNC=1)" ;;
    msync) printf '%s' "msync (WINEMSYNC=1)" ;;
    *) printf '%s' "off" ;;
  esac
}
