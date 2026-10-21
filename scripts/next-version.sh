#!/usr/bin/env bash
# Print the next release version for the pinned Code OSS version:
# <code-oss tag><2-digit revision>, starting at 01 (00 is for test builds).
# Needs the repository's tags (git fetch --tags).

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$( dirname "${BASH_SOURCE[0]}" )/lib.sh"

LAST="$( git -C "${ZYM_ROOT}" tag --list "v${MS_TAG_PINNED}[0-9][0-9]" | sed "s/^v${MS_TAG_PINNED}//" | sort -n | tail -n 1 )"
NEXT=$(( 10#${LAST:-00} + 1 ))
(( NEXT <= 99 )) || die "revision 99 reached for ${MS_TAG_PINNED}"
printf '%s%02d\n' "${MS_TAG_PINNED}" "${NEXT}"
