#!/usr/bin/env bash
# Is there a newer stable VSCodium release (and with it a newer Code OSS)?
#
# Zymfonix IDE follows VSCodium *releases*: each one pins a stable Code OSS
# version that VSCodium's patches are known to apply to. Code OSS releases that
# VSCodium has not caught up with yet are reported, not used.
#
# Usage: scripts/check-upstream.sh [--write] [--pr-body FILE]
#   --write        update upstream.json when a newer release exists
#   --pr-body F    write a pull request description to F
# In GitHub Actions, results are also written to GITHUB_OUTPUT
# (changed, vscodium_tag, vscode_tag).

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

WRITE="no"
PR_BODY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --write) WRITE="yes"; shift ;;
    --pr-body) PR_BODY="$2"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

VSCODIUM_SLUG="VSCodium/vscodium"
CURL=( curl -fsSL --retry 3 -H "Accept: application/vnd.github+json" )
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
[[ -n "${TOKEN}" ]] && CURL+=( -H "Authorization: Bearer ${TOKEN}" )

output() { [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "$1=$2" >> "${GITHUB_OUTPUT}"; return 0; }

LATEST_TAG="$( "${CURL[@]}" "https://api.github.com/repos/${VSCODIUM_SLUG}/releases/latest" | jq -er '.tag_name' )"
MS_LATEST="$( curl -fsSL --retry 3 "https://update.code.visualstudio.com/api/update/darwin/stable/0000000000000000000000000000000000000000" | jq -r '.name' 2> /dev/null || echo unknown )"

log "pinned:  VSCodium ${VSCODIUM_TAG} -> Code OSS ${MS_TAG_PINNED}"
log "latest:  VSCodium ${LATEST_TAG}; VS Code stable ${MS_LATEST}"

newer() { [[ "$1" != "$2" && "$( printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1 )" == "$1" ]]; }

if ! newer "${LATEST_TAG}" "${VSCODIUM_TAG}"; then
  log "up to date: nothing to do"
  if newer "${MS_LATEST}" "${MS_TAG_PINNED}"; then
    log "note: VS Code ${MS_LATEST} exists, but VSCodium has not released it yet; it will be picked up once they do"
  fi
  output changed false
  exit 0
fi

REFS="$( git ls-remote "${VSCODIUM_REPOSITORY}" "refs/tags/${LATEST_TAG}" "refs/tags/${LATEST_TAG}^{}" )"
NEW_COMMIT="$( awk '$2 ~ /\^\{\}$/ { print $1 }' <<< "${REFS}" )"
[[ -n "${NEW_COMMIT}" ]] || NEW_COMMIT="$( awk '{ print $1 }' <<< "${REFS}" | head -n 1 )"
[[ "${NEW_COMMIT}" =~ ^[0-9a-f]{40}$ ]] || die "could not resolve VSCodium tag ${LATEST_TAG}"

STABLE="$( "${CURL[@]}" "https://raw.githubusercontent.com/${VSCODIUM_SLUG}/${NEW_COMMIT}/upstream/stable.json" )"
NEW_MS_TAG="$( jq -er '.tag' <<< "${STABLE}" )"
NEW_MS_COMMIT="$( jq -er '.commit' <<< "${STABLE}" )"
[[ "${NEW_MS_COMMIT}" =~ ^[0-9a-f]{40}$ ]] || die "bad Code OSS commit in VSCodium ${LATEST_TAG}: ${NEW_MS_COMMIT}"
[[ "${LATEST_TAG}" == "${NEW_MS_TAG}"* ]] || die "VSCodium ${LATEST_TAG} does not match its Code OSS tag ${NEW_MS_TAG}"
newer "${NEW_MS_TAG}" "${MS_TAG_PINNED}" || [[ "${NEW_MS_TAG}" == "${MS_TAG_PINNED}" ]] || die "refusing to downgrade Code OSS ${MS_TAG_PINNED} -> ${NEW_MS_TAG}"

log "update available: VSCodium ${VSCODIUM_TAG} -> ${LATEST_TAG}, Code OSS ${MS_TAG_PINNED} -> ${NEW_MS_TAG}"
output changed true
output vscodium_tag "${LATEST_TAG}"
output vscode_tag "${NEW_MS_TAG}"

if [[ "${WRITE}" == "yes" ]]; then
  jq --arg vt "${LATEST_TAG}" --arg vc "${NEW_COMMIT}" --arg mt "${NEW_MS_TAG}" --arg mc "${NEW_MS_COMMIT}" \
    '.vscodium.tag = $vt | .vscodium.commit = $vc | .vscode.tag = $mt | .vscode.commit = $mc' \
    "${ZYM_ROOT}/upstream.json" > "${ZYM_ROOT}/upstream.json.new"
  mv "${ZYM_ROOT}/upstream.json.new" "${ZYM_ROOT}/upstream.json"
  log "upstream.json updated"
fi

if [[ -n "${PR_BODY}" ]]; then
  # Files whose changes are most likely to need a matching change here.
  WATCH='^(build\.sh|prepare_vscode\.sh|get_repo\.sh|utils\.sh|version\.sh|product\.json|build_cli\.sh|undo_telemetry\.sh|build/linux/(package_bin\.sh|deps\.sh|prepare_assets\.sh|anylinux-appimage/)|build/osx/|src/stable/|\.nvmrc|\.github/workflows/publish-stable-(linux|macos)\.yml)'
  FILES="$( "${CURL[@]}" "https://api.github.com/repos/${VSCODIUM_SLUG}/compare/${VSCODIUM_COMMIT}...${NEW_COMMIT}" \
    | jq -r '.files[]?.filename' | grep -E "${WATCH}" | sed 's/^/- `/; s/$/`/' || true )"
  MS_MINOR="$( cut -d. -f1,2 <<< "${NEW_MS_TAG}" | tr . _ )"
  cat > "${PR_BODY}" << EOF
Automated upstream update.

| | Current | New |
| --- | --- | --- |
| VSCodium (build scripts) | [${VSCODIUM_TAG}](https://github.com/${VSCODIUM_SLUG}/releases/tag/${VSCODIUM_TAG}) | [${LATEST_TAG}](https://github.com/${VSCODIUM_SLUG}/releases/tag/${LATEST_TAG}) |
| Code OSS | ${MS_TAG_PINNED} | [${NEW_MS_TAG}](https://github.com/microsoft/vscode/tree/${NEW_MS_COMMIT}) ([release notes](https://code.visualstudio.com/updates/v${MS_MINOR})) |

VSCodium changes: https://github.com/${VSCODIUM_SLUG}/compare/${VSCODIUM_COMMIT}...${NEW_COMMIT}

### VSCodium files that Zymfonix IDE depends on and that changed
${FILES:-_none_}

If any of these changed, compare them with \`scripts/apply-overlay.sh\`, \`scripts/post-prepare.sh\` and \`.github/workflows/build.yml\` (runner images, container images, setup steps).

### Before merging
- [ ] The **CI** checks on this branch passed (patches and Zymfonix edits apply to the new upstream).
- [ ] Optional: a full **Build** run on this branch passed (Actions > Build > Run workflow > this branch).

Merging does not publish anything. Publish with the **Release** workflow afterwards (see MAINTENANCE.md).
EOF
  log "PR description written to ${PR_BODY}"
fi
