#!/usr/bin/env bash
# Apply the Zymfonix IDE overlay to a fresh VSCodium checkout (.build/vscodium).
#
#   1. copy overlay/vscodium/ over the checkout (icons, desktop files, appdata)
#   2. merge branding/product.json into VSCodium's product.json, which VSCodium
#      merges last into Code OSS's product.json
#   3. a few counted edits to VSCodium's scripts: run our post-prepare hook,
#      AppImage naming, and disable VSCodium's own publishing scripts
#
# Run it exactly once per checkout; scripts/fetch-upstream.sh gives a clean one.

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

cd "${VSCODIUM_DIR}" 2> /dev/null || die "no VSCodium checkout at ${VSCODIUM_DIR}; run scripts/fetch-upstream.sh"
MARKER=".zymfonix-overlay"
[[ ! -e "${MARKER}" ]] || die "overlay already applied to ${VSCODIUM_DIR}; run scripts/fetch-upstream.sh for a clean checkout"
[[ -z "$( git status --porcelain --untracked-files=no )" ]] || die "VSCodium checkout has local modifications; run scripts/fetch-upstream.sh"

# {{{ 1. files
cp -R "${ZYM_ROOT}/overlay/vscodium/." .

# VSCodium ships its LICENSE as the app's LICENSE.txt. Ours carries the same
# MIT text and every upstream copyright line, plus Zymfonix's.
while IFS= read -r line; do
  grep -qxF -- "${line}" "${ZYM_ROOT}/LICENSE" || die "LICENSE is missing upstream notice '${line}' (copy it from VSCodium's LICENSE)"
done < <( grep '^Copyright' LICENSE )
cp "${ZYM_ROOT}/LICENSE" LICENSE
log "overlay files copied"
# }}}

# {{{ 2. product.json
OVERRIDES="$( sed "s|@@GH_REPO_PATH@@|${GH_REPO_PATH}|g" "${ZYM_ROOT}/branding/product.json" )"
MERGED="$( jq -s '.[0] * .[1]' product.json <( echo "${OVERRIDES}" ) )"
echo "${MERGED}" > product.json
log "product.json overrides merged"
# }}}

# {{{ 3. VSCodium script edits
# Re-brand what VSCodium hard-codes after prepare_vscode.sh, before compiling.
edit_text build.sh $'  . prepare_vscode.sh\n' \
  $'  . prepare_vscode.sh\n\n  # Zymfonix IDE: re-brand what VSCodium hard-codes\n'"  bash \"${ZYM_ROOT}/scripts/post-prepare.sh\""$'\n'

# AppImage: our file name (no space), and no self-updater hook (updates are manual).
edit_text build/linux/anylinux-appimage/build.sh \
  'export OUTNAME=${APP_NAME}-${VERSION}-anylinux-"${ARCH}".AppImage' \
  'export OUTNAME=ZymfonixIDE-${VERSION}-linux-"${ARCH}".AppImage'
edit_text build/linux/anylinux-appimage/build.sh \
  'export ADD_HOOKS="self-updater.hook:fix-namespaces.hook"' \
  'export ADD_HOOKS="fix-namespaces.hook"'
# AppImage root icon named after the desktop entry's Icon= (AppImage convention).
cp src/stable/resources/linux/code.svg src/stable/resources/linux/zymfonix-ide.svg
edit_text build/linux/anylinux-appimage/build.sh \
  'export ICON="src/${VSCODE_QUALITY}/resources/linux/code.svg"' \
  'export ICON="src/${VSCODE_QUALITY}/resources/linux/zymfonix-ide.svg"'

# VSCodium's publishing scripts target VSCodium's repositories and update
# server. They are never used here; make any accidental call fail.
for script in release.sh update_version.sh upload_sourcemaps.sh check_tags.sh; do
  [[ -f "${script}" ]] || die "expected VSCodium script ${script} is missing (upstream layout changed?)"
  printf '#!/usr/bin/env bash\necho "%s is disabled in Zymfonix IDE builds" >&2\nexit 1\n' "${script}" > "${script}"
done
# }}}

{
  echo "vscodium=${VSCODIUM_TAG} ${VSCODIUM_COMMIT}"
  echo "vscode=${MS_TAG_PINNED} ${MS_COMMIT_PINNED}"
  echo "repo=${GH_REPO_PATH}"
} > "${MARKER}"
log "overlay applied to ${VSCODIUM_DIR}"
