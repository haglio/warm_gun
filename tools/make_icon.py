"""Generate the Warm Gun app icon — the Fun Time lettermark, one generation on.

Fun Time's icon is an F and a T sharing strokes on a 5x5 grid of pink cells;
Warm Gun is its satellite, so it wears the same mark with its own initials: a W
and a G overlaid on the same grid, the same pink, the corners rounded the same
way. iOS rejects alpha and rounds its own corners, so where Fun Time sits on a
transparent square this one sits on an opaque black one — the color the player
screen behind it is. One output:

- ``WarmGun/Assets.xcassets/AppIcon.appiconset/AppIcon.png`` — 1024x1024.

Drawn at 2x and downscaled with LANCZOS so the rounded corners are smooth.
Requires Pillow, which the Haglio workspace venv carries as a tooling-only
dependency::

    ../.venv/bin/python tools/make_icon.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

PINK = (200, 80, 160)   # sampled from fun_time/icon.ico
BLACK = (0, 0, 0)

# The two letters, drawn over one another the way the F and the T are: both are
# stroke skeletons that share the left spine and the bottom bar, so the union
# stays sparse enough to read. W is the whole frame — outer legs, center post,
# bottom — with its two counters open at the top; G is the left half, its top
# bar stopping short of the right leg (the notch that separates them) and its
# tongue rising through the middle.
W = [
    "#...#",
    "#...#",
    "#.#.#",
    "#.#.#",
    "#####",
]
G = [
    "###..",
    "#....",
    "#.#..",
    "#.#..",
    "###..",
]

S = 2048            # working scale; shipped at 1024
MARGIN = 0.16       # a touch wider than Fun Time's 0.12: the grid's corners are
                    # filled here, and iOS's corner mask must not shave them
RADIUS = 0.24       # corner rounding, as a fraction of one cell — Fun Time's
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
    image.paste(Image.new("RGB", (S, S), PINK), mask=mask)
    return image.resize((1024, 1024), Image.LANCZOS)


if __name__ == "__main__":
    OUT.parent.mkdir(parents=True, exist_ok=True)
    draw_icon().save(OUT, "PNG")
    print(OUT)
