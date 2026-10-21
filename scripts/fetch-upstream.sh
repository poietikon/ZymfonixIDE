#!/usr/bin/env bash
# Fresh checkout of VSCodium at the commit pinned in upstream.json, in .build/vscodium.
#
# Verifies that the pinned tag still points at the pinned commit and that this
# VSCodium commit pins the same Code OSS tag/commit as upstream.json, so the
# build can never silently drift from what was reviewed.

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

log "VSCodium ${VSCODIUM_TAG} (${VSCODIUM_COMMIT}) from ${VSCODIUM_REPOSITORY}"

rm -rf "${VSCODIUM_DIR}"
mkdir -p "${VSCODIUM_DIR}"
cd "${VSCODIUM_DIR}"

git init -q
git remote add origin "${VSCODIUM_REPOSITORY}"

REFS="$( git ls-remote origin "refs/tags/${VSCODIUM_TAG}" "refs/tags/${VSCODIUM_TAG}^{}" )"
TAG_COMMIT="$( awk '$2 ~ /\^\{\}$/ { print $1 }' <<< "${REFS}" )"
[[ -n "${TAG_COMMIT}" ]] || TAG_COMMIT="$( awk '{ print $1 }' <<< "${REFS}" | head -n 1 )"

[[ -n "${TAG_COMMIT}" ]] || die "VSCodium tag ${VSCODIUM_TAG} not found"
[[ "${TAG_COMMIT}" == "${VSCODIUM_COMMIT}" ]] || die "VSCodium tag ${VSCODIUM_TAG} points at ${TAG_COMMIT}, upstream.json pins ${VSCODIUM_COMMIT}"

git fetch -q --depth 1 origin "${VSCODIUM_COMMIT}"
git checkout -q --detach FETCH_HEAD
[[ "$( git rev-parse HEAD )" == "${VSCODIUM_COMMIT}" ]] || die "checked out commit does not match the pin"

STABLE_TAG="$( jq -er '.tag' upstream/stable.json )"
STABLE_COMMIT="$( jq -er '.commit' upstream/stable.json )"
if [[ "${STABLE_TAG}" != "${MS_TAG_PINNED}" || "${STABLE_COMMIT}" != "${MS_COMMIT_PINNED}" ]]; then
  die "VSCodium ${VSCODIUM_TAG} builds Code OSS ${STABLE_TAG} (${STABLE_COMMIT}), but upstream.json says ${MS_TAG_PINNED} (${MS_COMMIT_PINNED})"
fi

log "OK: VSCodium ${VSCODIUM_TAG} -> Code OSS ${MS_TAG_PINNED} (${MS_COMMIT_PINNED})"
