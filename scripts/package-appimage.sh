#!/usr/bin/env bash
# Build the x86_64 AppImage with VSCodium's anylinux-appimage script (inside the
# pkgforge-dev Arch Linux container, see build.yml) from vscode-bin.tar.gz.

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

BIN="${1:-${ZYM_BUILD_DIR}/vscode-bin.tar.gz}"
[[ -f "${BIN}" ]] || die "usage: package-appimage.sh <vscode-bin.tar.gz>"
BIN="$( cd "$( dirname "${BIN}" )" && pwd )/$( basename "${BIN}" )"
[[ -f "${VSCODIUM_DIR}/.zymfonix-overlay" ]] || die "no prepared VSCodium tree (run linux-handoff.sh unpack)"

cd "${VSCODIUM_DIR}"
cp "${BIN}" vscode-bin.tar.gz
rm -rf AppDir dist

# GITHUB_REPOSITORY feeds the AppImage's embedded zsync update information
# (our own releases; nothing updates automatically).
export GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-${GH_REPO_PATH}}"
set +u
./build/linux/anylinux-appimage/build.sh
set -u

NAME="$( asset_linux_appimage )"
mkdir -p "${ZYM_DIST_DIR}"
for f in "dist/${NAME}" "dist/${NAME}.zsync"; do
  [[ -s "${f}" ]] || die "AppImage build did not produce ${f} (found: $( find dist -maxdepth 1 -type f 2> /dev/null | tr '\n' ' ' ))"
  mv "${f}" "${ZYM_DIST_DIR}/"
done
chmod +x "${ZYM_DIST_DIR}/${NAME}"

log "AppImage assets:"
ls -lh "${ZYM_DIST_DIR}" >&2
