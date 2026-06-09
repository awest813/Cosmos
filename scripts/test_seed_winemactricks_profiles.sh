#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || fail "python3 required"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/seed-profiles.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

mkdir -p "${TMP}/profiles/steam" "${TMP}/recipes/dependencies" "${TMP}/recipes/fixes"
mkdir -p "${TMP}/scripts/data" "${TMP}/third_party/winemactricks-json"
cp "${ROOT}/scripts/data/winemactricks-profile-map.json" "${TMP}/scripts/data/"
cp "${ROOT}/third_party/winemactricks-json/winemactricks.json" "${TMP}/third_party/winemactricks-json/"
cp "${ROOT}/recipes/fixes/grounded-mscoree-fix.recipe" "${TMP}/recipes/fixes/"
cp "${ROOT}/recipes/dependencies/vcrun2019.recipe" "${TMP}/recipes/dependencies/"

cat > "${TMP}/profiles/steam/steam-962130-grounded.yaml" <<'EOF'
id: grounded
name: "Grounded"
store: steam
steam_appid: 962130
status: playable
recommended_backend: dxmt
wine_version: cosmos-stable
settings:
  retina: false
  windows_version: win10
notes: "test"
EOF

python3 "${ROOT}/scripts/seed_winemactricks_profile_deps.py" --repo "${TMP}" --appid 962130
grep -q 'grounded-mscoree-fix' "${TMP}/profiles/steam/steam-962130-grounded.yaml" \
  || fail "expected grounded fix seeded"

before="$(md5sum "${ROOT}/profiles/steam/steam-22380-fallout-new-vegas.yaml" | awk '{print $1}')"
python3 "${ROOT}/scripts/seed_winemactricks_profile_deps.py" --appid 22380
after="$(md5sum "${ROOT}/profiles/steam/steam-22380-fallout-new-vegas.yaml" | awk '{print $1}')"
[[ "${before}" == "${after}" ]] || fail "22380 should be idempotent"

python3 "${ROOT}/scripts/seed_winemactricks_profile_deps.py" --dry-run --appid 1091500 \
  | grep -q 'steam-1091500' || fail "cyberpunk dry-run"

bash "${ROOT}/profile.command" validate profiles/steam/steam-22380-fallout-new-vegas.yaml \
  || fail "profile validate failed after seed pass"

printf 'OK: seed winemactricks profiles tests passed\n'
