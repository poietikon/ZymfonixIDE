#!/usr/bin/env python3
"""Validate the generated icons in overlay/vscodium/src/stable (no dependencies).

Checks file formats and pixel sizes: every .icns contains the sizes macOS
needs, PNGs and the favicon have the right dimensions, SVGs are well-formed.
Runs anywhere (CI lint job), unlike build-icons.sh which needs macOS.
"""

import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "overlay" / "vscodium" / "src" / "stable"

# icns element types holding PNG data -> pixel size
ICNS_PNG_TYPES = {
    b"icp4": 16, b"icp5": 32, b"icp6": 64, b"ic07": 128, b"ic08": 256,
    b"ic09": 512, b"ic10": 1024, b"ic11": 32, b"ic12": 64, b"ic13": 256, b"ic14": 512,
}
APP_ICNS_REQUIRED = {b"ic07", b"ic08", b"ic09", b"ic10", b"ic11", b"ic12", b"ic13", b"ic14"}
# Upstream document icons top out at 512 px.
DOC_ICNS_REQUIRED = {b"ic07", b"ic08", b"ic09"}

errors = []


def png_size(data: bytes):
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return None
    return struct.unpack(">II", data[16:24])


def check_icns(path: Path, required: set):
    data = path.read_bytes()
    if data[:4] != b"icns" or struct.unpack(">I", data[4:8])[0] != len(data):
        errors.append(f"{path}: not a valid icns file")
        return
    found, pos = {}, 8
    while pos < len(data):
        kind, length = data[pos:pos + 4], struct.unpack(">I", data[pos + 4:pos + 8])[0]
        if kind in ICNS_PNG_TYPES:
            size = png_size(data[pos + 8:pos + length])
            expected = ICNS_PNG_TYPES[kind]
            if size != (expected, expected):
                errors.append(f"{path}: {kind.decode()} is {size}, expected {expected}x{expected}")
            found[kind] = size
        pos += length
    missing = required - set(found)
    if missing:
        errors.append(f"{path}: missing icon sizes {sorted(k.decode() for k in missing)}")


def check_png(path: Path, size: int):
    actual = png_size(path.read_bytes()[:32])
    if actual != (size, size):
        errors.append(f"{path}: {actual}, expected {size}x{size}")


def check_ico(path: Path, required: set):
    data = path.read_bytes()
    reserved, kind, count = struct.unpack("<HHH", data[:6])
    if reserved != 0 or kind != 1:
        errors.append(f"{path}: not an ico file")
        return
    sizes = {data[6 + 16 * i] or 256 for i in range(count)}
    if not required <= sizes:
        errors.append(f"{path}: has sizes {sorted(sizes)}, needs {sorted(required)}")


def check_svg(path: Path):
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as e:
        errors.append(f"{path}: invalid SVG ({e})")
        return
    if not root.tag.endswith("svg") or not root.get("viewBox"):
        errors.append(f"{path}: missing <svg viewBox>")


def main() -> None:
    darwin = ROOT / "resources" / "darwin"
    check_icns(darwin / "code.icns", APP_ICNS_REQUIRED)
    docs = sorted(p for p in darwin.glob("*.icns") if p.name != "code.icns")
    if len(docs) < 20:
        errors.append(f"{darwin}: only {len(docs)} document icons")
    for p in docs:
        check_icns(p, DOC_ICNS_REQUIRED)
    check_png(ROOT / "resources" / "linux" / "code.png", 1024)
    check_png(ROOT / "resources" / "server" / "code-192.png", 192)
    check_png(ROOT / "resources" / "server" / "code-512.png", 512)
    check_ico(ROOT / "resources" / "server" / "favicon.ico", {16, 32, 48, 256})
    for p in [ROOT / "resources" / "linux" / "code.svg", ROOT / "src" / "vs" / "workbench" / "browser" / "media" / "code-icon.svg",
              *sorted((ROOT / "src" / "vs" / "workbench" / "browser" / "parts" / "editor" / "media").glob("letterpress-*.svg"))]:
        check_svg(p)

    if errors:
        print("verify-icons: FAILED", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        sys.exit(1)
    print(f"verify-icons: OK (app icon + {len(docs)} document icons, Linux, web and in-app icons)")


if __name__ == "__main__":
    main()
