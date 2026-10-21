#!/usr/bin/env bash
# Build Zymfonix IDE with VSCodium's build scripts.
#
#   macOS            -> .build/vscodium/VSCode-darwin-<arch>/Zymfonix IDE.app
#                       (then: scripts/package-macos.sh)
#   Linux, local     -> .build/vscodium/VSCode-linux-x64   (CI_BUILD=no)
#                       (then: scripts/package-linux.sh)
#   Linux, CI        -> compiled sources only; packaging runs in VSCodium's
#                       Linux build container (see .github/workflows/build.yml)
#
# Needs the Node.js version in .build/vscodium/.nvmrc, python3, jq, git, and
# roughly 20 GB of free disk space. RELEASE_VERSION defaults to <code-oss>00.

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log "building ${APP_NAME} ${RELEASE_VERSION} for ${OS_NAME}/${VSCODE_ARCH} (CI_BUILD=${CI_BUILD})"

"${ZYM_ROOT}/scripts/fetch-upstream.sh"
"${ZYM_ROOT}/scripts/apply-overlay.sh"

cd "${VSCODIUM_DIR}"

NODE_WANTED="$( cat .nvmrc )"
NODE_HAVE="$( node -v 2> /dev/null || echo none )"
if [[ "${NODE_HAVE#v}" != "${NODE_WANTED}" ]]; then
  log "warning: VSCodium expects Node.js ${NODE_WANTED}, found ${NODE_HAVE}"
fi

export MAX_OLD_SPACE_SIZE="${MAX_OLD_SPACE_SIZE:-8192}"

# VSCodium's scripts are not written for `set -u`.
set +u
# shellcheck disable=SC1091
. ./get_repo.sh
./build.sh
set -u

log "build finished: $( ls -d "${VSCODIUM_DIR}"/VSCode-* 2> /dev/null || echo 'compiled sources (CI Linux)' )"
