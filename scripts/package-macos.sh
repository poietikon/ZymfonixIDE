#!/usr/bin/env bash
# Turn the built Zymfonix IDE.app into release assets (DMG + ZIP) in dist/.
#
# The app is signed ad hoc ("-"): no Apple Developer certificate is involved and
# the app is NOT notarized, so macOS asks the user to approve it on first launch
# (see README). An ad-hoc signature is still required: Apple Silicon refuses to
# run code without a valid signature, and the bundle seal changes during the
# build (renaming, Info.plist). Gatekeeper is not bypassed or modified.

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

[[ "${OS_NAME}" == "osx" ]] || die "package-macos.sh runs on macOS only"

APP="${VSCODIUM_DIR}/VSCode-darwin-${VSCODE_ARCH}/${APP_NAME}.app"
[[ -d "${APP}" ]] || die "app bundle not found: ${APP} (run scripts/build.sh first)"

DMG="${ZYM_DIST_DIR}/$( asset_macos_dmg "${VSCODE_ARCH}" )"
ZIP="${ZYM_DIST_DIR}/$( asset_macos_zip "${VSCODE_ARCH}" )"
mkdir -p "${ZYM_DIST_DIR}"
rm -f "${DMG}" "${ZIP}"

log "ad-hoc signing ${APP}"
codesign --force --deep --sign - "${APP}"
codesign --verify --deep --strict --verbose=2 "${APP}"

log "creating ${ZIP}"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"

log "creating ${DMG}"
WORK="$( mktemp -d )"
MOUNT="${WORK}/mnt"
cleanup() {
  if [[ -d "${MOUNT}" ]] && mount | grep -q "${MOUNT}"; then hdiutil detach -force "${MOUNT}" > /dev/null || true; fi
  rm -rf "${WORK}"
}
trap cleanup EXIT

mkdir -p "${WORK}/staging" "${MOUNT}"
ditto "${APP}" "${WORK}/staging/${APP_NAME}.app"
ln -s /Applications "${WORK}/staging/Applications"

hdiutil create -quiet -volname "${APP_NAME}" -srcfolder "${WORK}/staging" -fs HFS+ -format UDRW -ov "${WORK}/rw.dmg"
hdiutil attach -quiet -nobrowse -noverify -noautoopen -mountpoint "${MOUNT}" "${WORK}/rw.dmg"

# Volume icon (the mounted disk shows the Zymfonix icon in Finder).
cp "${APP}/Contents/Resources/$( /usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "${APP}/Contents/Info.plist" )" "${MOUNT}/.VolumeIcon.icns"
if command -v SetFile > /dev/null; then
  SetFile -c icnC "${MOUNT}/.VolumeIcon.icns"
  SetFile -a C "${MOUNT}"
else
  log "warning: SetFile not found (Xcode command line tools); DMG keeps the generic volume icon"
fi

for i in 1 2 3 4 5; do
  hdiutil detach -quiet "${MOUNT}" && break
  [[ "${i}" == 5 ]] && die "could not detach ${MOUNT}"
  sleep $(( i * 2 ))
done

hdiutil convert -quiet "${WORK}/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "${DMG}"
hdiutil verify -quiet "${DMG}"

log "macOS ${VSCODE_ARCH} assets:"
ls -lh "${DMG}" "${ZIP}" >&2
