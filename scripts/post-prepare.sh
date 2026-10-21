#!/usr/bin/env bash
# Hook run by VSCodium's build.sh right after prepare_vscode.sh (see
# apply-overlay.sh): replaces the few VSCodium names VSCodium writes into the
# Code OSS tree itself, then checks the final product.json.
#
# Every edit is counted (scripts/edit-text.py): if upstream rewords one of these
# files the build stops here instead of shipping VSCodium branding.

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

cd "${VSCODIUM_DIR}/vscode"

REPO_URL="https://github.com/${GH_REPO_PATH}"

# {{{ application metadata (all platforms)
# macOS Info.plist copyright / company name (Finder "Get Info", About panel).
edit_text build/lib/electron.ts "companyName: 'VSCodium'," "companyName: 'Zymfonix',"
edit_text --regex build/lib/electron.ts \
  "copyright: 'Copyright \\(C\\) ([0-9]{4}) VSCodium\\. All rights reserved'" \
  "copyright: 'Copyright (C) \\1 Zymfonix. Based on Code - OSS, Copyright (C) Microsoft Corporation. MIT License'"

# package.json author (VSCodium replaced Microsoft's name with its own).
jq '.author.name = "Zymfonix"' package.json > package.json.zym && mv package.json.zym package.json

# Web manifest names.
jq --arg n "${APP_NAME}" '.name = $n | .short_name = $n' resources/server/manifest.json > manifest.zym \
  && mv manifest.zym resources/server/manifest.json
# }}}

# {{{ Linux packages
if [[ "${OS_NAME}" == "linux" ]]; then
  DEB=resources/linux/debian

  # Upstream's postinst registers Microsoft's apt repository for any package
  # not named "code-oss"; VSCodium rewrote the check for "codium". Ours:
  edit_text "${DEB}/postinst.template" 'if [ "@@NAME@@" != "codium" ]; then' 'if [ "@@NAME@@" != "zymfonix-ide" ]; then'

  # Upstream's postrm deletes Microsoft's apt source and key. Zymfonix IDE never
  # adds them, and removing it must not break a real VS Code installation.
  edit_text "${DEB}/postrm.template" 'if [ "$RET" = "true" ]; then' \
    'if false; then # Zymfonix IDE: never touch the Microsoft apt repository of a VS Code install'

  # Package metadata (RPM is not built, so only the Debian control file).
  edit_text --regex "${DEB}/control.template" '^Maintainer: .*$' "Maintainer: Zymfonix <${REPO_URL}>"
  edit_text --regex "${DEB}/control.template" 'https://github\.com/VSCodium/vscodium#download-install' "${REPO_URL}#installation"
  edit_text --regex "${DEB}/control.template" 'https://vscodium\.com/?' 'https://zymfonix.com/'
  edit_text --regex "${DEB}/control.template" 'VSCodium' 'Zymfonix IDE'

  if grep -n -i 'vscodium\|microsoft corporation <' "${DEB}/control.template"; then
    die "VSCodium/Microsoft maintainer text left in ${DEB}/control.template"
  fi
fi
# }}}

python3 "${ZYM_ROOT}/scripts/check-product.py" product.json
log "post-prepare: Code OSS tree re-branded"
