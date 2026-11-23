from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

MAGENTA = (200, 80, 160)   # sampled from fun_time/icon.ico
PREVIEW_INK = (255, 200, 120)   # shared_ui.palette.PREVIEW_INK: a build from a worktree wears it
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
ASSETS = Path(__file__).resolve().parent.parent / "WarmGun" / "Assets.xcassets"


def union(*letters: list[str]) -> list[str]:
    return ["".join("#" if any(l[r][c] == "#" for l in letters) else "."
                    for c in range(5)) for r in range(5)]


def draw_icon(ink: tuple[int, int, int]) -> Image.Image:
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
    image.paste(Image.new("RGB", (S, S), ink), mask=mask)
    return image.resize((1024, 1024), Image.LANCZOS)


def write_icon_set(name: str, ink: tuple[int, int, int]) -> Path:
    folder = ASSETS / f"{name}.appiconset"
    folder.mkdir(parents=True, exist_ok=True)
    draw_icon(ink).save(folder / f"{name}.png", "PNG")
    images = [{"filename": f"{name}.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
              {"filename": f"{name}.png", "idiom": "mac", "scale": "2x", "size": "512x512"}]
    (folder / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}},
                                                     indent=2, separators=(",", " : ")) + "\n")
    return folder


if __name__ == "__main__":
    print(write_icon_set("AppIcon", MAGENTA))
    print(write_icon_set("AppIconPreview", PREVIEW_INK))
