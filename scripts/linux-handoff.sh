#!/usr/bin/env bash
# Move the prepared build between CI jobs, the way VSCodium's Linux workflow does
# (compile on the runner, package inside VSCodium's Linux build container).
#
#   linux-handoff.sh pack   <out-dir>  -> vscodium-tree.tar.gz + vscode.tar.gz
#   linux-handoff.sh unpack <in-dir>   -> .build/vscodium (+ vscode.tar.gz for package_bin.sh)
#
# vscodium-tree.tar.gz is the already patched VSCodium checkout (no Code OSS
# sources), so later jobs use exactly what the compile job used.

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

MODE="${1:-}"
DIR="${2:-}"
[[ -n "${MODE}" && -n "${DIR}" ]] || die "usage: linux-handoff.sh pack|unpack <dir>"

case "${MODE}" in
  pack)
    mkdir -p "${DIR}"
    DIR="$( cd "${DIR}" && pwd )"
    cd "${VSCODIUM_DIR}"
    # Same file selection as VSCodium's "Compress vscode artifact" step.
    find vscode -type f -not -path "*/node_modules/*" -not -path "vscode/.build/node/*" -not -path "vscode/.git/*" > vscode.txt
    echo "vscode/.build/extensions/node_modules" >> vscode.txt
    echo "vscode/.git" >> vscode.txt
    tar -czf "${DIR}/vscode.tar.gz" -T vscode.txt
    rm vscode.txt
    tar -czf "${DIR}/vscodium-tree.tar.gz" --exclude=./vscode .
    ls -lh "${DIR}" >&2
    ;;
  unpack)
    rm -rf "${VSCODIUM_DIR}"
    mkdir -p "${VSCODIUM_DIR}"
    tar -xzf "${DIR}/vscodium-tree.tar.gz" -C "${VSCODIUM_DIR}"
    [[ -f "${VSCODIUM_DIR}/.zymfonix-overlay" ]] || die "handoff tree was not prepared by apply-overlay.sh"
    if [[ -f "${DIR}/vscode.tar.gz" ]]; then
      mv "${DIR}/vscode.tar.gz" "${VSCODIUM_DIR}/vscode.tar.gz"
    fi
    log "unpacked prepared VSCodium tree into ${VSCODIUM_DIR}"
    ;;
  *) die "unknown mode ${MODE}" ;;
esac
