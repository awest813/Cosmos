#!/usr/bin/env bash
set -euo pipefail

# Convert a source image (jpg/png) into a macOS .icns suitable for a Cosmos game
# launcher's app bundle. Used by detect_steam_games.command to turn Steam's
# locally-cached artwork into per-game icons.
#
# Usage:
#   make_app_icon.command <source-image> <output.icns>
#
# Requires the macOS tools `sips` and `iconutil`. If either is missing, or the
# source image cannot be read, it exits non-zero with a message so callers can
# fall back to the default Cosmos icon instead of failing the whole build.

SRC="${1:-}"
OUT="${2:-}"

die() { printf 'make_app_icon: %s\n' "$1" >&2; exit 1; }

[[ -n "${SRC}" && -n "${OUT}" ]] || { printf 'usage: make_app_icon.command <source-image> <output.icns>\n' >&2; exit 2; }
[[ -f "${SRC}" ]] || die "source image not found: ${SRC}"
command -v sips >/dev/null 2>&1 || die "sips not available (macOS only)"
command -v iconutil >/dev/null 2>&1 || die "iconutil not available (macOS only)"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/cosmos-icon.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

# Read source dimensions so non-square art can be centre-cropped to a square
# (avoids the distortion that resizing a rectangle straight to a square causes).
width="$(sips -g pixelWidth "${SRC}" 2>/dev/null | awk '/pixelWidth:/{print $2}')"
height="$(sips -g pixelHeight "${SRC}" 2>/dev/null | awk '/pixelHeight:/{print $2}')"

base_png="${tmp_dir}/base.png"
sips -s format png "${SRC}" --out "${tmp_dir}/source.png" >/dev/null 2>&1 \
  || die "could not decode source image: ${SRC}"

if [[ "${width}" =~ ^[0-9]+$ && "${height}" =~ ^[0-9]+$ && "${width}" != "${height}" ]]; then
  side=$(( width < height ? width : height ))
  # sips -c takes height then width.
  sips -c "${side}" "${side}" "${tmp_dir}/source.png" --out "${base_png}" >/dev/null 2>&1 \
    || die "could not crop source image to square"
else
  mv "${tmp_dir}/source.png" "${base_png}"
fi

iconset="${tmp_dir}/icon.iconset"
mkdir -p "${iconset}"
for size in 16 32 128 256 512; do
  sips -z "${size}" "${size}" "${base_png}" \
    --out "${iconset}/icon_${size}x${size}.png" >/dev/null 2>&1 \
    || die "could not generate ${size}x${size} icon"
  sips -z "$(( size * 2 ))" "$(( size * 2 ))" "${base_png}" \
    --out "${iconset}/icon_${size}x${size}@2x.png" >/dev/null 2>&1 \
    || die "could not generate ${size}x${size}@2x icon"
done

mkdir -p "$(dirname "${OUT}")"
iconutil -c icns "${iconset}" -o "${OUT}" \
  || die "iconutil failed to assemble ${OUT}"

printf 'Wrote %s\n' "${OUT}"
