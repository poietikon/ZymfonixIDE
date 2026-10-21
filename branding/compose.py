#!/usr/bin/env python3
"""Compose Zymfonix IDE icon SVGs from the original Zymfonix logo.

The glyph geometry is taken verbatim from branding/source/zymfonix.svg (the
white "Z" paths). Nothing is redrawn: this script only places those paths on
platform-appropriate backgrounds and writes plain SVG files that
build-icons.sh rasterises.

Usage:
  compose.py glyph <source-logo.svg> <out.svg>
  compose.py icons <source-logo.svg> <out-dir> <glyph-bbox: x y w h>
"""

import re
import sys
from pathlib import Path

# Colours come straight from the logo: black tile, white glyph.
TILE = "#000000"
GLYPH = "#FFFFFF"

# Letterpress (empty editor watermark) fills, same values VSCodium/VS Code use.
LETTERPRESS = {
    "dark": ("#B2B2B2", "0.3"),
    "light": ("#B2B2B2", "0.1"),
    "hcDark": ("#3C3C3C", "1"),
    "hcLight": ("#B2B2B2", "1"),
}


def glyph_paths(src: str) -> list[str]:
    """Return the path data of the white (glyph) group of the logo."""
    groups = re.findall(r'<g[^>]*fill="([^"]+)"[^>]*>(.*?)</g>\s*</g>', src, re.S)
    for fill, body in groups:
        if fill.replace(" ", "").lower() in ("rgb(255,255,255)", "#fff", "#ffffff"):
            paths = re.findall(r'\sd="([^"]+)"', body)
            if paths:
                return paths
    sys.exit("compose.py: could not find the white glyph group in the source logo")


def rounded_rect(x0: float, y0: float, size: float, radius: float) -> str:
    r = radius
    x1, y1 = x0 + size, y0 + size
    return (
        f"M{x0 + r:.2f},{y0:.2f} H{x1 - r:.2f} A{r:.2f},{r:.2f} 0 0 1 {x1:.2f},{y0 + r:.2f} "
        f"V{y1 - r:.2f} A{r:.2f},{r:.2f} 0 0 1 {x1 - r:.2f},{y1:.2f} H{x0 + r:.2f} "
        f"A{r:.2f},{r:.2f} 0 0 1 {x0:.2f},{y1 - r:.2f} V{y0 + r:.2f} "
        f"A{r:.2f},{r:.2f} 0 0 1 {x0 + r:.2f},{y0:.2f} Z"
    )


class Glyph:
    def __init__(self, paths: list[str], bbox: tuple[float, float, float, float]):
        self.paths = paths
        self.bx, self.by, self.bw, self.bh = bbox

    def place(self, cx: float, cy: float, width: float, fill: str, opacity: str = "1") -> str:
        """Group that draws the glyph with its bbox centred on (cx, cy), `width` wide."""
        k = width / self.bw
        tx = cx - k * (self.bx + self.bw / 2)
        ty = cy - k * (self.by + self.bh / 2)
        body = "".join(f'<path d="{d}"/>' for d in self.paths)
        return (
            f'<g transform="translate({tx:.3f},{ty:.3f}) scale({k:.6f})" '
            f'fill="{fill}" fill-opacity="{opacity}">{body}</g>'
        )


def svg(view: float, body: str, defs: str = "") -> str:
    v = f"{view:g}"
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{v}" height="{v}" viewBox="0 0 {v} {v}">'
        f"{'<defs>' + defs + '</defs>' if defs else ''}{body}</svg>\n"
    )


def macos_app(g: Glyph) -> str:
    # Apple icon grid: 1024 canvas, 824 body centred (corner radius 22.5%),
    # leaving room for the drop shadow.
    shape = rounded_rect(100, 100, 824, 824 * 0.225)
    defs = (
        '<filter id="shadow" x="-10%" y="-10%" width="120%" height="125%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="10"/>'
        '<feOffset dy="10" result="b"/>'
        '<feComponentTransfer><feFuncA type="linear" slope="0.30"/></feComponentTransfer>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>'
        f'<clipPath id="body"><path d="{shape}"/></clipPath>'
    )
    body = (
        f'<path d="{shape}" fill="{TILE}" filter="url(#shadow)"/>'
        # Hairline highlight so the black tile keeps its edge on a dark Dock.
        f'<path d="{shape}" fill="none" stroke="#FFFFFF" stroke-opacity="0.16" '
        f'stroke-width="6" clip-path="url(#body)"/>'
        + g.place(512, 512, 824 * 0.62, GLYPH)
    )
    return svg(1024, body, defs)


def tile(g: Glyph, view: float = 1024, margin: float = 0.0, glyph_ratio: float = 0.64) -> str:
    """Rounded black tile with the white glyph (Linux, favicon, in-app logo, badges)."""
    size = view * (1 - 2 * margin)
    x0 = view * margin
    shape = rounded_rect(x0, x0, size, size * 0.225)
    return svg(view, f'<path d="{shape}" fill="{TILE}"/>' + g.place(view / 2, view / 2, size * glyph_ratio, GLYPH))


def letterpress(g: Glyph, fill: str, opacity: str) -> str:
    return svg(40, g.place(20, 20, 32, fill, opacity))


def main() -> None:
    args = sys.argv[1:]
    if len(args) == 3 and args[0] == "glyph":
        # Glyph only, in the logo's own coordinate system (used to measure its bbox).
        paths = glyph_paths(Path(args[1]).read_text())
        body = "".join(f'<path d="{d}"/>' for d in paths)
        Path(args[2]).write_text(svg(5000, f'<g fill="#000000">{body}</g>'))
        return
    if len(args) != 7 or args[0] != "icons":
        sys.exit(__doc__)

    src = Path(args[1]).read_text()
    out = Path(args[2])
    bbox = tuple(float(v) for v in args[3:7])
    out.mkdir(parents=True, exist_ok=True)

    g = Glyph(glyph_paths(src), bbox)
    files = {
        "app-macos.svg": macos_app(g),
        "app-linux.svg": tile(g, margin=0.04),
        "app-tile.svg": tile(g),
        "badge.svg": tile(g, glyph_ratio=0.68),
    }
    for variant, (fill, opacity) in LETTERPRESS.items():
        files[f"letterpress-{variant}.svg"] = letterpress(g, fill, opacity)

    for name, text in files.items():
        (out / name).write_text(text)
        print(f"compose: wrote {out / name}")


if __name__ == "__main__":
    main()
