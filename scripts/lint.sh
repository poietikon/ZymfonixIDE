#!/usr/bin/env bash
# Static checks: shell scripts, workflows, JSON, Python, icons, product overrides.
# Needs shellcheck; uses actionlint when installed (CI installs it).

set -euo pipefail
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "${ROOT}"

fail=0
step() { echo "== $1"; }

step "shellcheck"
shellcheck -x scripts/*.sh branding/*.sh || fail=1

step "bash -n"
for f in scripts/*.sh branding/*.sh; do bash -n "${f}" || fail=1; done

step "python"
for f in scripts/*.py branding/*.py; do python3 -m py_compile "${f}" || fail=1; done

step "JSON"
for f in upstream.json branding/product.json; do jq empty "${f}" || { echo "invalid JSON: ${f}"; fail=1; }; done

step "upstream pin format"
jq -e '(.vscodium.commit | test("^[0-9a-f]{40}$")) and (.vscode.commit | test("^[0-9a-f]{40}$")) and (.vscodium.tag | startswith($ARGS.named.ms))' \
  --arg ms "$( jq -r .vscode.tag upstream.json )" upstream.json > /dev/null || { echo "upstream.json pins are malformed"; fail=1; }

step "branding/product.json identifiers"
TMP="$( mktemp )"
# Check the overrides on their own, with the Open VSX gallery VSCodium adds.
sed 's|@@GH_REPO_PATH@@|zymfonix/zymfonix-ide|g' branding/product.json \
  | jq '. + {extensionsGallery: {serviceUrl: "https://open-vsx.org/vscode/gallery"}}' > "${TMP}"
python3 scripts/check-product.py "${TMP}" || fail=1
rm -f "${TMP}"

step "icons"
python3 branding/verify-icons.py || fail=1

step "actionlint"
if command -v actionlint > /dev/null; then
  actionlint || fail=1
else
  echo "actionlint not installed; skipped"
fi

if [[ "${fail}" != 0 ]]; then echo "lint: FAILED"; exit 1; fi
echo "lint: OK"
