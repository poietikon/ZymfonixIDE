#!/usr/bin/env bash
# Final gate before publishing: dist/ must contain exactly the expected release
# assets for RELEASE_VERSION, all non-empty, nothing VSCodium-named. Writes
# SHA256SUMS.txt.
#
# Usage: scripts/verify-assets.sh [dist-dir]

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

DIST="${1:-${ZYM_DIST_DIR}}"
[[ -d "${DIST}" ]] || die "no asset directory ${DIST}"
cd "${DIST}"
rm -f SHA256SUMS.txt

fail=0
while IFS= read -r name; do
  if [[ -s "${name}" ]]; then
    printf '  ok      %-55s %s\n' "${name}" "$( du -h "${name}" | cut -f1 )"
  else
    echo "  MISSING ${name}" >&2; fail=1
  fi
done < <( expected_assets )

for name in *; do
  if ! expected_assets | grep -qxF -- "${name}"; then
    echo "  UNEXPECTED ${name}" >&2; fail=1
  fi
  if tr '[:upper:]' '[:lower:]' <<< "${name}" | grep -q codium; then
    echo "  VSCODIUM-NAMED ${name}" >&2; fail=1
  fi
done

[[ "${fail}" == 0 ]] || die "release assets for ${RELEASE_VERSION} are incomplete or unexpected; refusing to publish"

SHA256=( sha256sum ); command -v sha256sum > /dev/null || SHA256=( shasum -a 256 )
# shellcheck disable=SC2046
"${SHA256[@]}" $( expected_assets ) > SHA256SUMS.txt
log "all $( expected_assets | wc -l | tr -d ' ' ) assets present; SHA256SUMS.txt written"
