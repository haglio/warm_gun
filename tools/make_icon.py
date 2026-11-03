from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

MAGENTA = (200, 80, 160)   # sampled from fun_time/icon.ico
# iOS rejects alpha in an app icon and rounds its own corners, so the square is opaque black.
BLACK = (0, 0, 0)

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
RADIUS = 0.15       # measured off the ico corner alpha map (~6px of 256)
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
    mask = mask.filter(ImageFilter.GaussianBlur(cell * RADIUS)).point(lambda v: 255 if v >= 128 else 0)
    image = Image.new("RGB", (S, S), BLACK)
    image.paste(Image.new("RGB", (S, S), MAGENTA), mask=mask)
    return image.resize((1024, 1024), Image.LANCZOS)


if __name__ == "__main__":
    OUT.parent.mkdir(parents=True, exist_ok=True)
    draw_icon().save(OUT, "PNG")
    print(OUT)
