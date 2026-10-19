#!/usr/bin/env python3
"""Generate clean, subtly feathered notification oil paint from Vela art.

No controls, icons, map text, or power buttons are permitted in this asset.
The entire painting is static; VpnService updates only native TextViews.
Android SystemUI still draws the outer notification frame and icon.
"""
from pathlib import Path
import math
import random

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/oil/ui/oil_canvas.webp"
DESTINATION = ROOT / "assets/oil/ui"
SIZE = (900, 210)


def build(dark: bool) -> None:
    if not SOURCE.is_file():
        raise FileNotFoundError("Run prepare_oil_ui.py before notification art")
    raw = Image.open(SOURCE).convert("RGB")
    material = ImageOps.fit(raw, SIZE, method=Image.Resampling.LANCZOS)
    relief = ImageEnhance.Contrast(ImageOps.grayscale(material)).enhance(1.23)
    if dark:
        base = ImageOps.colorize(relief, black=(24, 44, 63),
                                 mid=(57, 90, 113), white=(136, 159, 166),
                                 midpoint=114).convert("RGBA")
    else:
        base = ImageOps.colorize(relief, black=(187, 164, 133),
                                 mid=(242, 222, 187), white=(255, 248, 222),
                                 midpoint=119).convert("RGBA")

    # A few translucent, irregular ocean brush marks add nautical character
    # without introducing any literal buttons, words, logos or photographs.
    waves = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    brush = ImageDraw.Draw(waves, "RGBA")
    randomizer = random.Random(180052 if dark else 180051)
    for i in range(48):
        left = randomizer.randrange(440, 940)
        y = randomizer.randrange(105, 205)
        length = randomizer.randrange(40, 180)
        w = randomizer.randrange(2, 9)
        palette = ((83, 170, 185), (95, 161, 188), (156, 192, 202)) if dark \
            else ((25, 116, 162), (33, 144, 185), (110, 190, 202))
        color = palette[i % len(palette)]
        brush.line((left, y, left + length, y - randomizer.randrange(-8, 9)),
                   fill=(*color, randomizer.randrange(26, 95)),
                   width=w)
    base = Image.alpha_composite(base, waves)

    # Feather all sides into SystemUI's system-painted card rather than
    # introducing a hard rectangular border around the smaller custom slot.
    mask = Image.new("L", SIZE, 0)
    shape = ImageDraw.Draw(mask)
    shape.rounded_rectangle((22, 9, 878, 201), radius=38,
                            fill=220 if dark else 202)
    mask = mask.filter(ImageFilter.GaussianBlur(radius=18))
    # Gaussian support can leave nonzero alpha right at the PNG boundary.
    # Multiply by a second gradual edge ramp to reach exactly zero at every
    # outside edge, without introducing a visible rectangular cut-off.
    edge = Image.new("L", SIZE, 0)
    edge_pixels = edge.load()
    width, height = SIZE
    for y in range(height):
        vertical = min(1.0, y / 25.0, (height - 1 - y) / 25.0)
        for x in range(width):
            horizontal = min(1.0, x / 35.0, (width - 1 - x) / 35.0)
            edge_pixels[x, y] = int(255 * min(vertical, horizontal))
    mask = ImageChops.multiply(mask, edge)
    base.putalpha(ImageChops.multiply(base.getchannel("A"), mask))
    name = "night" if dark else "day"
    target = DESTINATION / f"notification_oil_{name}.png"
    base.save(target, "PNG", optimize=True)
    assert target.is_file() and target.stat().st_size > 0
    assert base.getchannel("A").getextrema()[0] == 0
    print("Vela clean native notification oil:", target)


def main() -> None:
    DESTINATION.mkdir(parents=True, exist_ok=True)
    build(False)
    build(True)


if __name__ == "__main__":
    main()
