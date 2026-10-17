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
    # Group pigments into brush-sized patches yet retain coastlines.
    opaque_paint = original.filter(ImageFilter.ModeFilter(size=3))
    base = Image.blend(original, opaque_paint, .48)
    base = ImageEnhance.Color(base).enhance(1.09 if night else 1.22)
    base = ImageEnhance.Contrast(base).enhance(1.05)
    # Warm natural canvas relief; slight curved, individual bristle marks.
    overlay = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay, "RGBA")
    r = random.Random(180034 if not night else 180035)
    for i in range(11000):
        x = r.randrange(width)
        y = r.randrange(height)
        length = r.randrange(5, 17)
        dy = r.randrange(-4, 5)
        # Every mark is visible but remains behind the original geographic
        # contours; shift instead of changing any coordinate calibration.
        light = r.random() < .54
        color = (255, 251, 230, 25 if light else 11) if light else (
            45, 44, 58, 22 if night else 15)
        stroke = max(1, r.randrange(1, 4))
        x2 = x + length
        draw.line((x, y, x2, y + dy), fill=color, width=stroke,
                  joint="curve")
        # Periodic brushwork at horizontal map seams: no visible wrap jump.
        if x2 >= width:
            draw.line((x-width, y, x2-width, y+dy),
                      fill=color, width=stroke)
    base = Image.alpha_composite(base.convert("RGBA"), overlay).convert("RGB")
    base.save(target, "WEBP", quality=94, method=6)
    print(f"{target.name}: {width}x{height}, {target.stat().st_size} bytes")

render(ASSETS / "world" / "watercolor_day.webp",
       DEST / "oil_atlas_day.webp", night=False)
render(ASSETS / "world" / "watercolor_night.webp",
       DEST / "oil_atlas_night.webp", night=True)
