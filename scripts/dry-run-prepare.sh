#!/usr/bin/env bash
# Cheap validation of everything up to compilation, in minutes instead of hours:
# fetch the pinned VSCodium + Code OSS sources, apply our overlay, run
# VSCodium's prepare_vscode.sh (all VSCodium patches) and our post-prepare
# hook, then check the result.
#
# npm/node dependency installation is stubbed out, so this does NOT prove the
# application compiles; only a full build (build.yml) does. It does prove that
# every VSCodium patch and every Zymfonix edit still applies to this upstream.
#
# Usage: scripts/dry-run-prepare.sh [--os osx|linux]   (default: host OS)
# GNU sed is required for --os linux (VSCodium's Linux branch uses `sed -i`).

set -euo pipefail

while [[ $# -gt 0 ]]; do
  case "$1" in
    --os) export OS_NAME="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# shellcheck source=scripts/lib.sh
. "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

if [[ "${OS_NAME}" == "linux" ]] && ! sed --version > /dev/null 2>&1; then
  die "--os linux needs GNU sed (run on Linux, or install gnu-sed and put it first in PATH)"
fi

"${ZYM_ROOT}/scripts/fetch-upstream.sh"
"${ZYM_ROOT}/scripts/apply-overlay.sh"

cd "${VSCODIUM_DIR}"
# VSCodium's scripts are not written for `set -u`.
( set +u; . ./get_repo.sh ) > "${ZYM_BUILD_DIR}/dry-run-get-repo.log" 2>&1 || {
  tail -n 30 "${ZYM_BUILD_DIR}/dry-run-get-repo.log" >&2
  die "VSCodium get_repo.sh failed"
}

# {{{ stubs: skip dependency installation, provide the ripgrep VSCodium expects
STUBS="$( mktemp -d )"
trap 'rm -rf "${STUBS}"' EXIT
REAL_NODE="$( command -v node || true )"
cat > "${STUBS}/npm" << 'EOF'
#!/usr/bin/env bash
# dry-run stub: `npm ci` only creates the ripgrep path undo_telemetry.sh uses
if [[ "$1" == "ci" ]]; then
  mkdir -p node_modules/@vscode/ripgrep/bin
  cat > node_modules/@vscode/ripgrep/bin/rg << 'EOR'
#!/usr/bin/env bash
# dry-run stub for `rg --no-ignore -l PATTERN DIR`
pattern="${*: -2:1}"; dir="${*: -1}"
grep -rlE --exclude-dir=.git --exclude-dir=node_modules -- "${pattern}" "${dir}"
EOR
  chmod +x node_modules/@vscode/ripgrep/bin/rg
fi
exit 0
EOF
cat > "${STUBS}/node" << EOF
#!/usr/bin/env bash
# dry-run stub: skip Code OSS's npm preinstall checks, run everything else
[[ "\$1" == "build/npm/preinstall.ts" ]] && exit 0
exec "${REAL_NODE:-false}" "\$@"
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "${STUBS}/clang++"
chmod +x "${STUBS}"/*
# }}}

log "dry run: VSCodium prepare_vscode.sh for ${OS_NAME}/${VSCODE_ARCH} (dependency install stubbed)"
(
  set +u
  export PATH="${STUBS}:${PATH}"
  # shellcheck disable=SC1091
  . ./prepare_vscode.sh
) > "${ZYM_BUILD_DIR}/dry-run-prepare.log" 2>&1 || {
  tail -n 60 "${ZYM_BUILD_DIR}/dry-run-prepare.log" >&2
  die "VSCodium prepare_vscode.sh failed (full log: ${ZYM_BUILD_DIR}/dry-run-prepare.log)"
}
grep -E '^applying patch' "${ZYM_BUILD_DIR}/dry-run-prepare.log" | sed 's/^/  /' >&2 || true

# What VSCodium's build.sh runs next (injected by apply-overlay.sh).
bash "${ZYM_ROOT}/scripts/post-prepare.sh"

# {{{ checks on the prepared tree
cd vscode
fail=0
for f in resources/darwin/code.icns resources/linux/code.png resources/linux/code.svg \
  src/vs/workbench/browser/media/code-icon.svg src/vs/workbench/browser/parts/editor/media/letterpress-dark.svg; do
  if ! cmp -s "${f}" "${ZYM_ROOT}/overlay/vscodium/src/stable/${f}"; then
    echo "  icon not taken from overlay: ${f}" >&2; fail=1
  fi
done
for f in resources/darwin/*.icns; do
  if [[ ! -f "${ZYM_ROOT}/overlay/vscodium/src/stable/${f}" ]]; then
    echo "  upstream has a document icon we did not regenerate: ${f} (run branding/build-icons.sh)" >&2; fail=1
  fi
done
grep -q "companyName: 'Zymfonix'" build/lib/electron.ts || { echo "  electron.ts not re-branded" >&2; fail=1; }
cmp -s LICENSE.txt "${ZYM_ROOT}/LICENSE" || { echo "  LICENSE.txt shipped in the app is not ours" >&2; fail=1; }
[[ "$( jq -r '.version' package.json )" == "${RELEASE_VERSION}" ]] || { echo "  package.json version is not ${RELEASE_VERSION}" >&2; fail=1; }
if [[ "${OS_NAME}" == "linux" ]]; then
  grep -q 'if \[ "@@NAME@@" != "zymfonix-ide" \]; then' resources/linux/debian/postinst.template || { echo "  postinst guard missing" >&2; fail=1; }
fi
[[ "${fail}" == 0 ]] || die "dry run checks failed"

log "dry run OK: VSCodium ${VSCODIUM_TAG} + Code OSS ${MS_TAG_PINNED} prepared for ${OS_NAME} as ${APP_NAME} ${RELEASE_VERSION}"
# }}}
