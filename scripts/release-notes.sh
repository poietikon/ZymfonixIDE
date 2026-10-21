#!/usr/bin/env bash
# Print GitHub release notes (Markdown) for RELEASE_VERSION.
#
# Usage: scripts/release-notes.sh [previous-tag]

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

PREVIOUS="${1:-}"
REPO="https://github.com/${GH_REPO_PATH}"
DL="${REPO}/releases/download/v${RELEASE_VERSION}"
MS_MINOR="$( cut -d. -f1,2 <<< "${MS_TAG_PINNED}" | tr . _ )"

cat << EOF
Zymfonix IDE ${RELEASE_VERSION} is based on **Code - OSS ${MS_TAG_PINNED}** ([what's new in VS Code ${MS_TAG_PINNED%.*}](https://code.visualstudio.com/updates/v${MS_MINOR})), built with the VSCodium ${VSCODIUM_TAG} build scripts.

## Downloads

| Platform | File |
| --- | --- |
| macOS, Apple Silicon (M1 and newer) | [$( asset_macos_dmg arm64 )](${DL}/$( asset_macos_dmg arm64 )) |
| macOS, Intel | [$( asset_macos_dmg x64 )](${DL}/$( asset_macos_dmg x64 )) |
| Linux x64, Debian/Ubuntu | [$( asset_linux_deb )](${DL}/$( asset_linux_deb )) |
| Linux x64, any distribution | [$( asset_linux_appimage )](${DL}/$( asset_linux_appimage )) |
| Linux x64, archive | [$( asset_linux_tar )](${DL}/$( asset_linux_tar )) |

ZIP archives of the macOS apps are attached too. Not sure which Mac you have? Apple menu > About This Mac: "Chip: Apple M…" means Apple Silicon, "Processor: Intel" means Intel.

## First launch on macOS

These builds are not signed with an Apple Developer ID or notarized, so macOS blocks the first launch:

1. Drag **Zymfonix IDE** from the DMG to **Applications** and open it once. macOS says it cannot verify the app; click **Done**.
2. Open **System Settings > Privacy & Security**, scroll to **Security**, and click **Open Anyway** next to "Zymfonix IDE was blocked".
3. Confirm with **Open Anyway** and your password. Later launches work normally.

## Updating

Installed copies do **not** update themselves. To update, download the new version from this page and replace the old one (macOS: drag it to Applications again; Debian/Ubuntu: \`sudo apt install ./$( asset_linux_deb )\`). Settings and extensions are kept.

## Verify downloads

Linux: \`sha256sum -c --ignore-missing SHA256SUMS.txt\` in the download folder. macOS: compare \`shasum -a 256 <file>\` with the file's line in \`SHA256SUMS.txt\`.
EOF

if [[ -n "${PREVIOUS}" ]] && git -C "${ZYM_ROOT}" rev-parse -q --verify "refs/tags/${PREVIOUS}" > /dev/null; then
  echo
  echo "## Changes in this repository since ${PREVIOUS}"
  echo
  git -C "${ZYM_ROOT}" log --no-merges --format='- %s (%h)' "${PREVIOUS}..HEAD"
fi

cat << EOF

---
Zymfonix IDE is an independent distribution of [Code - OSS](https://github.com/microsoft/vscode) (MIT license), built with [VSCodium](https://github.com/VSCodium/vscodium)'s tooling. It is not affiliated with or endorsed by Microsoft. Extensions come from [Open VSX](https://open-vsx.org).
EOF
