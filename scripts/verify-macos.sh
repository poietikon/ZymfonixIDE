#!/usr/bin/env bash
# Verify the macOS release assets of one architecture, from the user's point of
# view: mount the DMG, inspect the app inside it, and run its CLI.
#
# Usage: scripts/verify-macos.sh   (uses VSCODE_ARCH / RELEASE_VERSION / dist/)

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

DMG="${ZYM_DIST_DIR}/$( asset_macos_dmg "${VSCODE_ARCH}" )"
ZIP="${ZYM_DIST_DIR}/$( asset_macos_zip "${VSCODE_ARCH}" )"
ICNS="${ZYM_ROOT}/overlay/vscodium/src/stable/resources/darwin/code.icns"
[[ -s "${DMG}" && -s "${ZIP}" ]] || die "missing ${DMG} or ${ZIP}"

case "${VSCODE_ARCH}" in
  arm64) LIPO_ARCH="arm64" ;;
  x64) LIPO_ARCH="x86_64" ;;
  *) die "unexpected arch ${VSCODE_ARCH}" ;;
esac

WORK="$( mktemp -d )"
MOUNT="${WORK}/mnt"
cleanup() {
  if [[ -d "${MOUNT}" ]] && mount | grep -q "${MOUNT}"; then hdiutil detach -force "${MOUNT}" > /dev/null || true; fi
  rm -rf "${WORK}"
}
trap cleanup EXIT

fail=0
check() { # description, command...
  local what="$1"; shift
  if "$@"; then echo "  ok   ${what}"; else echo "  FAIL ${what}" >&2; fail=1; fi
}
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2> /dev/null; }

verify_app() { # app path, label
  local app="$1"
  echo "${2}: ${app}"
  check "bundle identifier is com.zymfonix.ide" test "$( plist "${app}" CFBundleIdentifier )" = "com.zymfonix.ide"
  check "bundle name is ${APP_NAME}" test "$( plist "${app}" CFBundleName )" = "${APP_NAME}"
  check "version is ${RELEASE_VERSION}" test "$( plist "${app}" CFBundleShortVersionString )" = "${RELEASE_VERSION}"
  check "registers the zymfonix-ide:// URL scheme" grep -q '<string>zymfonix-ide</string>' "${app}/Contents/Info.plist"
  local icon
  icon="$( plist "${app}" CFBundleIconFile )"
  [[ "${icon}" == *.icns ]] || icon="${icon}.icns"
  check "application icon is the Zymfonix icon" cmp -s "${app}/Contents/Resources/${icon}" "${ICNS}"
  check "Info.plist does not mention VSCodium" bash -c "! grep -q -i 'vscodium' '${app}/Contents/Info.plist'"
  check "product.json is Zymfonix IDE" python3 "${ZYM_ROOT}/scripts/check-product.py" "${app}/Contents/Resources/app/product.json"
  check "main executable is ${LIPO_ARCH}" bash -c "lipo -archs '${app}/Contents/MacOS/$( plist "${app}" CFBundleExecutable )' | grep -qw '${LIPO_ARCH}'"
  check "code signature (ad hoc) is valid" codesign --verify --deep --strict "${app}"
  check "zymfonix-ide CLI launcher present" test -x "${app}/Contents/Resources/app/bin/zymfonix-ide"
  check "no VSCodium tunnel CLI bundled" bash -c "! ls '${app}/Contents/Resources/app/bin/' | grep -q tunnel"
  local version
  version="$( "${app}/Contents/Resources/app/bin/zymfonix-ide" --version 2> /dev/null | head -n 1 || true )"
  check "zymfonix-ide --version prints ${RELEASE_VERSION} (got '${version}')" test "${version}" = "${RELEASE_VERSION}"
}

hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "${MOUNT}" "${DMG}"
verify_app "${MOUNT}/${APP_NAME}.app" "DMG"
check "DMG has an Applications shortcut" test -L "${MOUNT}/Applications"
check "DMG volume icon is the Zymfonix icon" cmp -s "${MOUNT}/.VolumeIcon.icns" "${ICNS}"
hdiutil detach -quiet "${MOUNT}"

mkdir -p "${WORK}/zip"
ditto -x -k "${ZIP}" "${WORK}/zip"
verify_app "${WORK}/zip/${APP_NAME}.app" "ZIP"

[[ "${fail}" == 0 ]] || die "macOS ${VSCODE_ARCH} verification failed"
log "macOS ${VSCODE_ARCH} assets verified"
