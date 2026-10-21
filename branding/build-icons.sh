#!/usr/bin/env bash
# Regenerate every Zymfonix IDE icon from branding/source/zymfonix.svg.
#
# Outputs are committed under overlay/vscodium/src/stable/ (the same layout as
# VSCodium's src/stable/, which VSCodium copies into the Code OSS tree), so CI
# never needs image tooling. Re-run this only when the logo changes or when
# upstream changes its macOS document icons.
#
# Requirements (macOS): rsvg-convert + magick (brew install librsvg imagemagick),
# iconutil (built in), python3.
# The macOS document-type icons are built on top of the Code OSS originals, so
# an upstream checkout is needed: run `scripts/prepare-source.sh` first, or pass
# --vscode <dir> --vscodium <dir>.

set -euo pipefail

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LOGO="${ROOT}/branding/source/zymfonix.svg"
OUT="${ROOT}/overlay/vscodium/src/stable"
VSCODIUM_DIR="${ROOT}/.build/vscodium"
VSCODE_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vscode) VSCODE_DIR="$2"; shift 2 ;;
    --vscodium) VSCODIUM_DIR="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
VSCODE_DIR="${VSCODE_DIR:-${VSCODIUM_DIR}/vscode}"

for tool in rsvg-convert magick iconutil python3; do
  command -v "${tool}" > /dev/null || { echo "build-icons: '${tool}' is required" >&2; exit 1; }
done
[[ -d "${VSCODE_DIR}/resources/darwin" ]] || { echo "build-icons: Code OSS sources not found at ${VSCODE_DIR} (run scripts/prepare-source.sh first)" >&2; exit 1; }
[[ -f "${VSCODIUM_DIR}/icons/corner_512.png" ]] || { echo "build-icons: VSCodium checkout not found at ${VSCODIUM_DIR}" >&2; exit 1; }

WORK="$( mktemp -d )"
trap 'rm -rf "${WORK}"' EXIT

# PNGs without timestamps, so re-running on unchanged input yields identical files.
png() { magick "${@:1:$#-1}" -strip -define png:exclude-chunks=date,time "${@: -1}"; }
render() { rsvg-convert -w "$2" -h "$2" "$1" -o "$3"; }

# 1. Measure the glyph bounding box in logo coordinates.
python3 "${ROOT}/branding/compose.py" glyph "${LOGO}" "${WORK}/glyph.svg"
render "${WORK}/glyph.svg" 5000 "${WORK}/glyph.png"
read -r BX BY BW BH < <( magick "${WORK}/glyph.png" -alpha extract -trim -format '%X %Y %w %h\n' info: | tr -d '+' )
echo "build-icons: glyph bbox x=${BX} y=${BY} w=${BW} h=${BH}"

# 2. Compose SVG masters.
python3 "${ROOT}/branding/compose.py" icons "${LOGO}" "${WORK}/svg" "${BX}" "${BY}" "${BW}" "${BH}"

mkdir -p "${OUT}/resources/darwin" "${OUT}/resources/linux/rpm" "${OUT}/resources/server" \
  "${OUT}/src/vs/workbench/browser/media" "${OUT}/src/vs/workbench/browser/parts/editor/media"

# 3. macOS application icon (.icns with every size rendered from vector).
ICONSET="${WORK}/code.iconset"
mkdir -p "${ICONSET}"
for size in 16 32 128 256 512; do
  render "${WORK}/svg/app-macos.svg" "${size}" "${ICONSET}/icon_${size}x${size}.png"
  render "${WORK}/svg/app-macos.svg" "$(( size * 2 ))" "${ICONSET}/icon_${size}x${size}@2x.png"
done
iconutil -c icns -o "${OUT}/resources/darwin/code.icns" "${ICONSET}"

# 4. macOS document-type icons: Code OSS page + Zymfonix badge in the corner.
#    Same composition VSCodium uses (corner patch hides the upstream badge).
render "${WORK}/svg/badge.svg" 128 "${WORK}/badge.png"
for src in "${VSCODE_DIR}"/resources/darwin/*.icns; do
  name="$( basename "${src}" .icns )"
  [[ "${name}" == "code" ]] && continue
  iconutil -c iconset -o "${WORK}/${name}.src.iconset" "${src}"
  base="${WORK}/${name}.src.iconset/icon_512x512.png"
  [[ -f "${base}" ]] || base="${WORK}/${name}.src.iconset/icon_256x256@2x.png"
  [[ -f "${base}" ]] || { echo "build-icons: no 512px image in ${src}" >&2; exit 1; }
  magick "${base}" -resize 512x512 "${WORK}/${name}.png"
  magick "${WORK}/${name}.png" \
    "${VSCODIUM_DIR}/icons/corner_512.png" -geometry +323+365 -compose blend -define compose:args=100 -composite \
    "${WORK}/badge.png" -geometry +359+374 -compose over -composite "${WORK}/${name}.png"
  set="${WORK}/${name}.iconset"
  mkdir -p "${set}"
  for size in 16 32 128 256 512; do
    png "${WORK}/${name}.png" -resize "${size}x${size}" "${set}/icon_${size}x${size}.png"
    [[ "${size}" -lt 512 ]] && png "${WORK}/${name}.png" -resize "$(( size * 2 ))x$(( size * 2 ))" "${set}/icon_${size}x${size}@2x.png"
  done
  iconutil -c icns -o "${OUT}/resources/darwin/${name}.icns" "${set}"
done

# 5. Linux: 1024px PNG (pixmaps), scalable SVG (AppImage), XPM (rpm metadata).
render "${WORK}/svg/app-linux.svg" 1024 "${WORK}/code.png"
png "${WORK}/code.png" "${OUT}/resources/linux/code.png"
cp "${WORK}/svg/app-linux.svg" "${OUT}/resources/linux/code.svg"
magick "${WORK}/code.png" -resize 256x256 "${OUT}/resources/linux/rpm/code.xpm"

# 6. Web/server manifest icons and favicon.
render "${WORK}/svg/app-linux.svg" 192 "${WORK}/code-192.png"
render "${WORK}/svg/app-linux.svg" 512 "${WORK}/code-512.png"
png "${WORK}/code-192.png" "${OUT}/resources/server/code-192.png"
png "${WORK}/code-512.png" "${OUT}/resources/server/code-512.png"
for size in 16 24 32 48 64 128 256; do render "${WORK}/svg/app-tile.svg" "${size}" "${WORK}/fav-${size}.png"; done
magick "${WORK}"/fav-{16,24,32,48,64,128,256}.png "${OUT}/resources/server/favicon.ico"

# 7. In-app vector logos: title bar / welcome page icon and empty-editor letterpress.
cp "${WORK}/svg/app-tile.svg" "${OUT}/src/vs/workbench/browser/media/code-icon.svg"
for variant in dark light hcDark hcLight; do
  cp "${WORK}/svg/letterpress-${variant}.svg" "${OUT}/src/vs/workbench/browser/parts/editor/media/letterpress-${variant}.svg"
done

# 8. Contact sheet for humans (README / review): icon at Dock sizes on light and dark.
sheet() {
  local bg="$1" out="$2" row=()
  for size in 512 256 128 64 32 16; do
    render "${WORK}/svg/app-macos.svg" "${size}" "${WORK}/p-${size}.png"
    row+=( "(" "${WORK}/p-${size}.png" -background "${bg}" -gravity center -extent "$(( size + 24 ))x536" ")" )
  done
  magick "${row[@]}" +append -background "${bg}" "${out}"
}
sheet "#ececec" "${WORK}/sheet-light.png"
sheet "#1e1e1e" "${WORK}/sheet-dark.png"
magick "${OUT}/resources/linux/code.png" -resize 256x256 -background "#ececec" -gravity center -extent 280x280 "${WORK}/linux.png"
magick "${WORK}/javascript.png" -resize 256x256 -background "#ececec" -gravity center -extent 280x280 "${WORK}/doc.png"
mkdir -p "${ROOT}/branding/preview"
png "${WORK}/sheet-light.png" "${WORK}/sheet-dark.png" -append "${ROOT}/branding/preview/macos-icon-sizes.png"
png "${WORK}/linux.png" "${WORK}/doc.png" +append "${ROOT}/branding/preview/linux-and-document-icons.png"

echo "build-icons: done -> ${OUT}"
