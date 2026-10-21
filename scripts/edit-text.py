#!/usr/bin/env python3
"""Literal text replacement that fails when the expected text is not there.

Usage: edit-text.py [--count N | --regex] FILE OLD NEW

Every edit Zymfonix IDE makes to VSCodium or Code OSS files goes through this
script, so an upstream change that moves or rewords the text we rely on stops
the build with a clear message instead of silently producing a half-branded
application.

--count N  exact number of occurrences expected (default 1)
--regex    OLD is a Python regular expression (must match at least once)
"""

import re
import sys
from pathlib import Path


def main() -> None:
    args = sys.argv[1:]
    count, regex = 1, False
    while args and args[0].startswith("--"):
        if args[0] == "--count":
            count = int(args[1])
            args = args[2:]
        elif args[0] == "--regex":
            regex = True
            args = args[1:]
        else:
            sys.exit(f"edit-text: unknown option {args[0]}")
    if len(args) != 3:
        sys.exit(__doc__)

    path, old, new = Path(args[0]), args[1], args[2]
    if not path.is_file():
        sys.exit(f"edit-text: {path} does not exist (upstream layout changed?)")
    text = path.read_text(encoding="utf-8")

    if regex:
        result, found = re.subn(old, new, text, flags=re.M)
        if found == 0:
            sys.exit(f"edit-text: pattern not found in {path}:\n  {old}\n(upstream changed; update scripts accordingly)")
    else:
        found = text.count(old)
        if found != count:
            sys.exit(
                f"edit-text: expected {count} occurrence(s) in {path}, found {found}:\n  {old!r}\n"
                "(upstream changed; update scripts accordingly)"
            )
        result = text.replace(old, new)

    path.write_text(result, encoding="utf-8")
    print(f"edit-text: {path}: {found} replacement(s)")


if __name__ == "__main__":
    main()
