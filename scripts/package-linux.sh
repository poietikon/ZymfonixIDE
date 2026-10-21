#!/usr/bin/env bash
# Linux x64 packaging: .deb and .tar.gz into dist/, plus vscode-bin.tar.gz (the
# raw application directory) for the AppImage job.
#
# CI (CI_BUILD=yes): runs inside VSCodium's Linux build container on a tree
#   unpacked by linux-handoff.sh; VSCodium's package_bin.sh does the final
#   native build against the glibc 2.28 sysroot, so the result runs on older
#   distributions too.
# Local (CI_BUILD=no): packages the VSCode-linux-x64 directory from build.sh.

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

[[ "${OS_NAME}" == "linux" && "${VSCODE_ARCH}" == "x64" ]] || die "package-linux.sh builds linux/x64 only"
cd "${VSCODIUM_DIR}"

set +u
if [[ "${CI_BUILD}" != "no" ]]; then
  [[ -f vscode.tar.gz ]] || die "vscode.tar.gz not found (run linux-handoff.sh unpack first)"
  export npm_config_arch="x64"
  # package_bin.sh reports the sysroot it used through GITHUB_OUTPUT; the deb
  # step needs the same values (VSCodium passes them between steps).
  SYSROOT_OUT="$( mktemp )"
  GITHUB_OUTPUT="${SYSROOT_OUT}" ./build/linux/package_bin.sh
  while IFS='=' read -r key value; do
    [[ "${key}" == VSCODE_SYSROOT_* ]] && export "${key}=${value}"
  done < "${SYSROOT_OUT}"
fi

# The .deb, built like VSCodium's build/linux/prepare_assets.sh does (that
# script is not called directly: in local mode it also builds a snap).
(
  cd vscode
  for var in VSCODE_SYSROOT_REPOSITORY VSCODE_SYSROOT_VERSION VSCODE_SYSROOT_PREFIX; do
    [[ -n "${!var}" ]] || unset "${var}"
  done
  npm run gulp "vscode-linux-x64-prepare-deb"
  npm run gulp "vscode-linux-x64-build-deb"
)
set -u

APP_DIR="${VSCODIUM_DIR}/VSCode-linux-x64"
[[ -x "${APP_DIR}/zymfonix-ide" ]] || die "built application not found at ${APP_DIR}"

mkdir -p "${ZYM_DIST_DIR}"
shopt -s nullglob
DEBS=( vscode/.build/linux/deb/*/deb/zymfonix-ide_*_amd64.deb )
[[ "${#DEBS[@]}" == 1 ]] || die "expected exactly one zymfonix-ide .deb, found: ${DEBS[*]:-none}"
mv "${DEBS[0]}" "${ZYM_DIST_DIR}/$( asset_linux_deb )"

TAR="${ZYM_DIST_DIR}/$( asset_linux_tar )"
tar -czf "${TAR}" --transform 's|^VSCode-linux-x64|ZymfonixIDE-linux-x64|' -C "${VSCODIUM_DIR}" VSCode-linux-x64
tar -czf "${ZYM_BUILD_DIR}/vscode-bin.tar.gz" -C "${APP_DIR}" .

log "Linux assets:"
ls -lh "${ZYM_DIST_DIR}" >&2
