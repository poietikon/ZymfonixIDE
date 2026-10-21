#!/usr/bin/env bash
# Verify the Linux release assets (.deb, .tar.gz, AppImage) on an Ubuntu runner.
# Installs the .deb for real (needs sudo), runs the CLI, then removes it again.
#
# Usage: scripts/verify-linux.sh   (uses RELEASE_VERSION / dist/)

set -euo pipefail
export OS_NAME=linux VSCODE_ARCH=x64
# shellcheck source=scripts/lib.sh
. "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

DEB="${ZYM_DIST_DIR}/$( asset_linux_deb )"
TAR="${ZYM_DIST_DIR}/$( asset_linux_tar )"
APPIMAGE="${ZYM_DIST_DIR}/$( asset_linux_appimage )"
PNG="${ZYM_ROOT}/overlay/vscodium/src/stable/resources/linux/code.png"
SVG="${ZYM_ROOT}/overlay/vscodium/src/stable/resources/linux/code.svg"
for f in "${DEB}" "${TAR}" "${APPIMAGE}" "${APPIMAGE}.zsync"; do [[ -s "${f}" ]] || die "missing ${f}"; done

WORK="$( mktemp -d )"
trap 'rm -rf "${WORK}"' EXIT

fail=0
check() { # description, command...
  local what="$1"; shift
  if "$@"; then echo "  ok   ${what}"; else echo "  FAIL ${what}" >&2; fail=1; fi
}
has_line() { grep -qxF -- "$2" "$1"; }

check_desktop() { # main .desktop, url handler .desktop
  check "launcher name is ${APP_NAME}" has_line "$1" "Name=${APP_NAME}"
  check "launcher icon is zymfonix-ide" has_line "$1" "Icon=zymfonix-ide"
  check "launcher window class matches (taskbar icon)" has_line "$1" "StartupWMClass=zymfonix-ide"
  check "launcher opens files and folders" grep -q '^MimeType=text/plain;inode/directory;' "$1"
  check "URL handler registers zymfonix-ide://" grep -q '^MimeType=x-scheme-handler/zymfonix-ide;' "$2"
  check "launchers do not mention VSCodium" bash -c "[ -f '$1' ] && [ -f '$2' ] && ! grep -qi 'codium' '$1' '$2'"
}

# {{{ .deb
echo "DEB: ${DEB}"
check "package name is zymfonix-ide" test "$( dpkg-deb -f "${DEB}" Package )" = "zymfonix-ide"
check "package version starts with ${RELEASE_VERSION}" bash -c "dpkg-deb -f '${DEB}' Version | grep -q '^${RELEASE_VERSION}-'"
check "architecture is amd64" test "$( dpkg-deb -f "${DEB}" Architecture )" = "amd64"
check "maintainer is Zymfonix" bash -c "dpkg-deb -f '${DEB}' Maintainer | grep -q '^Zymfonix'"
dpkg-deb -e "${DEB}" "${WORK}/control"
dpkg-deb -x "${DEB}" "${WORK}/deb"
check "postinst does not register Microsoft's apt repository" grep -qF 'if [ "zymfonix-ide" != "zymfonix-ide" ]; then' "${WORK}/control/postinst"
check "postrm does not remove Microsoft's apt repository" grep -qF 'if false; then' "${WORK}/control/postrm"
D="${WORK}/deb/usr/share/applications"
check "desktop files installed" test -f "${D}/zymfonix-ide.desktop"
URL_DESKTOP="$( find "${D}" -name '*.desktop' ! -name 'zymfonix-ide.desktop' | head -n 1 )"
check_desktop "${D}/zymfonix-ide.desktop" "${URL_DESKTOP:-/missing}"
check "application icon is the Zymfonix icon" cmp -s "${WORK}/deb/usr/share/pixmaps/zymfonix-ide.png" "${PNG}"
check "product.json is Zymfonix IDE" python3 "${ZYM_ROOT}/scripts/check-product.py" "${WORK}/deb/usr/share/zymfonix-ide/resources/app/product.json"

echo "DEB install test"
# shellcheck disable=SC2024 # the log is meant to be written as the current user
sudo apt-get install -y -qq "${DEB}" > "${WORK}/apt.log" 2>&1 || { tail -n 30 "${WORK}/apt.log" >&2; die "apt-get install failed"; }
check "zymfonix-ide is on PATH" test -x /usr/bin/zymfonix-ide
VERSION="$( zymfonix-ide --version 2> /dev/null | head -n 1 || true )"
check "zymfonix-ide --version prints ${RELEASE_VERSION} (got '${VERSION}')" test "${VERSION}" = "${RELEASE_VERSION}"
check "no Microsoft apt source was added" bash -c "! find /etc/apt/sources.list.d -name 'vscode*' 2> /dev/null | grep -q ."
# shellcheck disable=SC2024
sudo apt-get purge -y -qq zymfonix-ide > "${WORK}/apt.log" 2>&1 || { tail -n 30 "${WORK}/apt.log" >&2; die "apt-get purge failed"; }
check "uninstall removed /usr/bin/zymfonix-ide" test ! -e /usr/bin/zymfonix-ide
# }}}

# {{{ .tar.gz
echo "TAR: ${TAR}"
tar -xzf "${TAR}" -C "${WORK}"
T="${WORK}/ZymfonixIDE-linux-x64"
check "archive has ZymfonixIDE-linux-x64/zymfonix-ide" test -x "${T}/zymfonix-ide"
check "product.json is Zymfonix IDE" python3 "${ZYM_ROOT}/scripts/check-product.py" "${T}/resources/app/product.json"
VERSION="$( "${T}/bin/zymfonix-ide" --version 2> /dev/null | head -n 1 || true )"
check "bin/zymfonix-ide --version prints ${RELEASE_VERSION} (got '${VERSION}')" test "${VERSION}" = "${RELEASE_VERSION}"
# }}}

# {{{ AppImage
echo "AppImage: ${APPIMAGE}"
chmod +x "${APPIMAGE}"
( cd "${WORK}" && "${APPIMAGE}" --appimage-extract > /dev/null )
A="${WORK}/squashfs-root"
check "AppImage launcher present" test -f "${A}/zymfonix-ide.desktop"
check_desktop "${A}/zymfonix-ide.desktop" "${A}/share/applications/zymfonix-ide-url-handler.desktop"
check "AppImage icon is the Zymfonix icon" cmp -s "${A}/zymfonix-ide.svg" "${SVG}"
check "AppImage .DirIcon is the Zymfonix icon" cmp -s "${A}/.DirIcon" "${SVG}"
check "product.json is Zymfonix IDE" python3 "${ZYM_ROOT}/scripts/check-product.py" "${A}/bin/resources/app/product.json"
check "zsync file belongs to this AppImage" bash -c "head -c 4096 '${APPIMAGE}.zsync' | grep -q '^Filename: $( asset_linux_appimage )'"
VERSION="$( "${A}/AppRun" --version 2> /dev/null | head -n 1 || true )"
check "AppImage --version prints ${RELEASE_VERSION} (got '${VERSION}')" test "${VERSION}" = "${RELEASE_VERSION}"
# }}}

[[ "${fail}" == 0 ]] || die "Linux verification failed"
log "Linux assets verified"
