#!/usr/bin/env bash
# Rosetta 2 helpers for Apple Silicon Wine integration (x86_64 Wine on arm64).

rosetta_host_arch() {
  uname -m 2>/dev/null || printf 'unknown'
}

# Cosmos supports Apple Silicon (arm64) and Intel (x86_64) Macs.
cosmos_host_supported() {
  case "$(rosetta_host_arch)" in
    arm64|x86_64) return 0 ;;
    *) return 1 ;;
  esac
}

cosmos_host_platform_label() {
  case "$(rosetta_host_arch)" in
    arm64) printf 'Apple Silicon' ;;
    x86_64) printf 'Intel' ;;
    *) printf '%s' "$(rosetta_host_arch)" ;;
  esac
}

# True when Cosmos must run x86_64 Wine under Rosetta (Apple Silicon hosts).
rosetta_needs_translation() {
  [[ "$(rosetta_host_arch)" == "arm64" ]]
}

rosetta_is_installed() {
  /usr/bin/arch -x86_64 /usr/bin/true >/dev/null 2>&1
}

# Prints: available | missing | not_required
rosetta_status_code() {
  if ! rosetta_needs_translation; then
    printf 'not_required'
    return 0
  fi
  if rosetta_is_installed; then
    printf 'available'
  else
    printf 'missing'
  fi
}

rosetta_status_label() {
  case "$(rosetta_status_code)" in
    available) printf 'Rosetta 2 ready' ;;
    missing) printf 'Rosetta 2 required' ;;
    *) printf 'Rosetta not needed (Intel Mac)' ;;
  esac
}

rosetta_ensure() {
  if ! rosetta_needs_translation; then
    echo "Intel host detected — Rosetta 2 is not required."
    return 0
  fi
  if rosetta_is_installed; then
    echo "Rosetta 2 is already available."
    return 0
  fi
  if declare -F ensure_sudo_ready >/dev/null 2>&1; then
    ensure_sudo_ready
  else
    sudo -v
  fi
  sudo softwareupdate --install-rosetta --agree-to-license
  rosetta_is_installed || {
    echo "Rosetta installation check failed." >&2
    return 1
  }
}
