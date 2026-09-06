"""Generate the Warm Gun app icon — the Fun Time lettermark, one generation on.

Fun Time's icon is an F and a T sharing bars on a 5x5 grid of magenta cells;
Warm Gun is its satellite, so it wears the same mark with its own initials: a W
and a G overlaid on the same grid, the same magenta, the corners rounded the same
way. iOS rejects alpha and rounds its own corners, so where Fun Time sits on a
transparent square this one sits on an opaque black one — the color of the
player screen under it. One output:

- ``WarmGun/Assets.xcassets/AppIcon.appiconset/AppIcon.png`` — 1024x1024.

Drawn at 2x and downscaled with LANCZOS so the rounded corners are smooth.
Requires Pillow, which the Haglio workspace venv carries as a tooling-only
dependency::

    ../.venv/bin/python tools/make_icon.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

MAGENTA = (200, 80, 160)   # sampled from fun_time/icon.ico
BLACK = (0, 0, 0)

# The two letters, LITERALLY overlaid — the union of a whole W and a whole G on
# the same grid, exactly as the original is the union of a whole F and a whole
# T. Both letters wear Fun Time's maximally chunky square face (every bar the
# full width, every post the full height).
W = [
    "#.#.#",
    "#.#.#",
    "#.#.#",
    "#.#.#",
    "#####",
]
G = [
    "#####",
    "#....",
    "#..##",
    "#...#",
    "#####",
]

S = 2048            # working scale; shipped at 1024
MARGIN = 0.121      # measured off fun_time/icon.ico: the glyph spans 194 of 256
RADIUS = 0.15       # measured off the ico corner alpha map (~6px of 256) — far
                    # squarer than it reads at a glance
OUT = Path(__file__).resolve().parent.parent / "WarmGun" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"


def union(*letters: list[str]) -> list[str]:
    return ["".join("#" if any(l[r][c] == "#" for l in letters) else "."
                    for c in range(5)) for r in range(5)]


def draw_icon() -> Image.Image:
    margin = S * MARGIN
    cell = (S - 2 * margin) / 5
    mask = Image.new("L", (S, S), 0)
    draw = ImageDraw.Draw(mask)
    for r, row in enumerate(union(W, G)):
        for c, filled in enumerate(row):
            if filled == "#":
                draw.rectangle([margin + c * cell, margin + r * cell,
                                margin + (c + 1) * cell, margin + (r + 1) * cell], fill=255)
    # Blur-and-threshold rounds every corner of the union — convex and concave
    # alike — by about the blur radius, which is how the original's cells melt
    # into one glyph instead of reading as 19 squares.
    mask = mask.filter(ImageFilter.GaussianBlur(cell * RADIUS)).point(lambda v: 255 if v >= 128 else 0)
    image = Image.new("RGB", (S, S), BLACK)
    image.paste(Image.new("RGB", (S, S), MAGENTA), mask=mask)
    return image.resize((1024, 1024), Image.LANCZOS)


if __name__ == "__main__":
    OUT.parent.mkdir(parents=True, exist_ok=True)
    draw_icon().save(OUT, "PNG")
    print(OUT)
