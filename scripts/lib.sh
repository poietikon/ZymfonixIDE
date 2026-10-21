#!/usr/bin/env bash
# shellcheck disable=SC2034 # variables are used by the scripts that source this file
# Shared settings for the Zymfonix IDE build scripts. Source this file.
#
# Everything that makes the build "Zymfonix IDE" rather than VSCodium is either
# set here (the knobs VSCodium's scripts already read from the environment),
# in branding/product.json, or in overlay/. Nothing else should hard-code
# branding.

ZYM_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
ZYM_BUILD_DIR="${ZYM_BUILD_DIR:-${ZYM_ROOT}/.build}"
VSCODIUM_DIR="${ZYM_BUILD_DIR}/vscodium"
ZYM_DIST_DIR="${ZYM_DIST_DIR:-${ZYM_ROOT}/dist}"

log() { echo "[zymfonix] $*" >&2; }
die() { echo "[zymfonix] ERROR: $*" >&2; exit 1; }

command -v jq > /dev/null || die "jq is required"

# {{{ pinned upstream (upstream.json is the only place versions are pinned)
VSCODIUM_REPOSITORY="$( jq -er '.vscodium.repository' "${ZYM_ROOT}/upstream.json" )"
VSCODIUM_TAG="$( jq -er '.vscodium.tag' "${ZYM_ROOT}/upstream.json" )"
VSCODIUM_COMMIT="$( jq -er '.vscodium.commit' "${ZYM_ROOT}/upstream.json" )"
MS_TAG_PINNED="$( jq -er '.vscode.tag' "${ZYM_ROOT}/upstream.json" )"
MS_COMMIT_PINNED="$( jq -er '.vscode.commit' "${ZYM_ROOT}/upstream.json" )"
# }}}

# {{{ VSCodium knobs (read by VSCodium's utils.sh, get_repo.sh, build.sh, ...)
export APP_NAME="Zymfonix IDE"
export BINARY_NAME="zymfonix-ide"
export ORG_NAME="Zymfonix"
export GH_REPO_PATH="${GH_REPO_PATH:-poietikon/ZymfonixIDE}"
export ASSETS_REPOSITORY="${GH_REPO_PATH}"
export GLOBAL_DIRNAME="zymfonix-ide"
export TUNNEL_APP_NAME="zymfonix-ide-tunnel"
export VSCODE_QUALITY="stable"
export VSCODE_LATEST="no"
export SHOULD_BUILD="yes"

# No updater: VSCodium's update server would serve VSCodium builds.
export DISABLE_UPDATE="yes"

# Not shipped: remote server (REH), the Rust CLI (it embeds VSCodium update and
# download endpoints), RPM and snap. Forced, not defaults.
export SHOULD_BUILD_REH="no"
export SHOULD_BUILD_REH_WEB="no"
export SHOULD_BUILD_CLI="no"
export SHOULD_BUILD_RPM="no"
export SHOULD_BUILD_TAR="no"
export SHOULD_BUILD_SRC="no"
export SHOULD_BUILD_DEB="yes"

# CI_BUILD=no is VSCodium's "local build" mode (also avoids editing the global
# git config). GitHub Actions runs in CI mode.
if [[ -z "${CI_BUILD:-}" ]]; then
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then export CI_BUILD="yes"; else export CI_BUILD="no"; fi
fi

if [[ -z "${OS_NAME:-}" ]]; then
  case "$( uname -s )" in
    Darwin) OS_NAME="osx" ;;
    Linux) OS_NAME="linux" ;;
    *) die "unsupported OS: $( uname -s ) (only macOS and Linux are built)" ;;
  esac
fi
export OS_NAME

if [[ -z "${VSCODE_ARCH:-}" ]]; then
  case "$( uname -m )" in
    arm64 | aarch64) VSCODE_ARCH="arm64" ;;
    x86_64 | amd64) VSCODE_ARCH="x64" ;;
    *) die "unsupported architecture: $( uname -m )" ;;
  esac
fi
export VSCODE_ARCH
# }}}

# {{{ version
# RELEASE_VERSION = <Code OSS tag><2-digit Zymfonix revision>, e.g. 1.140.0 + 01
# -> 1.140.001. This is the format VSCodium's get_repo.sh accepts, and it sorts
# correctly. Revision 00 is reserved for non-release (CI/local) builds.
export RELEASE_VERSION="${RELEASE_VERSION:-${MS_TAG_PINNED}00}"
if [[ ! "${RELEASE_VERSION}" =~ ^${MS_TAG_PINNED//./\\.}[0-9]{2}$ ]]; then
  die "RELEASE_VERSION '${RELEASE_VERSION}' must be ${MS_TAG_PINNED} followed by a 2-digit revision (e.g. ${MS_TAG_PINNED}01)"
fi
# }}}

# {{{ release asset names (one place, used by packaging and verification)
asset_macos_dmg() { echo "ZymfonixIDE-${RELEASE_VERSION}-macos-$1.dmg"; }
asset_macos_zip() { echo "ZymfonixIDE-${RELEASE_VERSION}-macos-$1.zip"; }
asset_linux_tar() { echo "ZymfonixIDE-${RELEASE_VERSION}-linux-x64.tar.gz"; }
asset_linux_deb() { echo "zymfonix-ide_${RELEASE_VERSION}_amd64.deb"; }
asset_linux_appimage() { echo "ZymfonixIDE-${RELEASE_VERSION}-linux-x86_64.AppImage"; }

expected_assets() {
  asset_macos_dmg arm64
  asset_macos_zip arm64
  asset_macos_dmg x64
  asset_macos_zip x64
  asset_linux_deb
  asset_linux_tar
  asset_linux_appimage
  echo "$( asset_linux_appimage ).zsync"
}
# }}}

# Literal, counted text replacement; fails loudly when upstream text changed.
edit_text() { python3 "${ZYM_ROOT}/scripts/edit-text.py" "$@"; }
