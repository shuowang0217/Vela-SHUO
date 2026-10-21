#!/usr/bin/env python3
"""Produce Android bitmap from the real Vela oil atlas, without runtime animation."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance

source = Path("assets/oil/oil_atlas_day.webp")
if not source.is_file():
    source = Path("assets/oil/oil_map_clean.webp")
im = Image.open(source).convert("RGB")
w, h = 1200, 480
scale = max(w / im.width, h / im.height)
im = im.resize((round(im.width * scale), round(im.height * scale)), Image.Resampling.LANCZOS)
x, y = (im.width - w) // 2, (im.height - h) // 2
base = ImageEnhance.Color(im.crop((x, y, x + w, y + h))).enhance(.87).convert("RGBA")
wash = Image.new("RGBA", (w, h), (0, 0, 0, 0))
draw = ImageDraw.Draw(wash)
for px in range(w):
    alpha = round(226 * max(0, 1 - px / (w * .76)) ** 1.45)
    draw.line((px, 0, px, h), fill=(246, 231, 199, alpha))
result = Image.alpha_composite(base, wash).convert("RGB")
target = Path("android/app/src/main/res/drawable-nodpi/vela_widget_oil.png")
target.parent.mkdir(parents=True, exist_ok=True)
result.save(target, optimize=True)
print("Vela oil voyage background:", target)
