#!/usr/bin/env python3
"""Vela 1.8 geographic oil atlas: painted from the original seamless 2:1 map.

The source is the existing Vela geographic watercolor atlas, NOT the approved
flattened UI screenshot, which cannot be projected to actual node locations.
Consequently real route and sail coordinates remain pixel-aligned worldwide.
No floating cloud assets are baked into these backgrounds.
Requires Pillow (already installed by each CI build job).
"""
from pathlib import Path
from PIL import Image, ImageEnhance, ImageFilter, ImageDraw
import math, random

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
DEST = ASSETS / "oil"
DEST.mkdir(parents=True, exist_ok=True)

def render(source: Path, target: Path, *, night: bool) -> None:
    original = Image.open(source).convert("RGB")
    width, height = original.size
    if width != height * 2:
        raise ValueError("Vela oil map must preserve the 2:1 georeferenced grid")
    # Dense pigmented impasto brushwork, preserving the real 2:1 map grid.
    opaque_paint = original.filter(ImageFilter.ModeFilter(size=7))
    base = Image.blend(original, opaque_paint, .48)
    base = ImageEnhance.Color(base).enhance(1.15 if night else 1.28)
    base = ImageEnhance.Contrast(base).enhance(1.10)
    overlay = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay, "RGBA")
    r = random.Random(180236 if night else 180235)
    pixels = base.load()
    for i in range(42000):
        x = r.randrange(width)
        y = r.randrange(height)
        length = r.randrange(7, 26)
        dy = r.randrange(-4, 5)
        pigment = pixels[x, y]
        delta = r.randrange(-20, 21)
        pigment = tuple(max(0, min(255, channel + delta))
                        for channel in pigment)
        color = (*pigment, r.randrange(54, 116))
        stroke = r.randrange(2, 6)
        draw.line((x, y, x + length, y + dy),
                  fill=color, width=stroke, joint="curve")
        if x + length >= width:
            draw.line((x - width, y, x + length - width, y + dy),
                      fill=color, width=stroke)
    for i in range(8000):
        x = r.randrange(width)
        y = r.randrange(height)
        pigment = pixels[x, y]
        delta = r.choice((-36, 26))
        pigment = tuple(max(0, min(255, channel + delta))
                        for channel in pigment)
        draw.line((x, y, x + r.randrange(7, 16),
                   y + r.randrange(-2, 3)),
                  fill=(*pigment, 89), width=2)
    base = Image.alpha_composite(base.convert("RGBA"), overlay).convert("RGB")
    # The repeated geographic tile must not show a hard seam.
    edge = base.crop((0, 0, 1, height))
    base.paste(edge, (width - 1, 0))
    base.save(target, "WEBP", quality=94, method=6)
    print(f"{target.name}: {width}x{height}, {target.stat().st_size} bytes")

render(ASSETS / "world" / "watercolor_day.webp",
       DEST / "oil_atlas_day.webp", night=False)
render(ASSETS / "world" / "watercolor_night.webp",
       DEST / "oil_atlas_night.webp", night=True)
