#!/usr/bin/env python3
"""Prepare the existing user-approved watercolor artwork for Vela v1.3.1.

This script fixes the 180-degree tile join and adds REAL geographical night
radiance from the project's existing earth_night_lights.png. It does not
redraw coastlines, replace the submitted artwork, or change the map projection.

Run before flutter pub get/build (the GitHub workflow runs it on all platforms).
"""
from pathlib import Path
from PIL import Image, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parents[1]
DAY = ROOT / 'assets/world/watercolor_day.webp'
NIGHT = ROOT / 'assets/world/watercolor_night.webp'
LIGHTS = ROOT / 'assets/earth/earth_night_lights.png'
# About five percent of the map; subtle seamless blending in mid-Pacific.
SEAM_FRACTION = 0.045


def blend_wrap_seam(image):
    image = image.convert('RGB')
    w, h = image.size
    band = max(18, int(w * SEAM_FRACTION))
    left = image.crop((0, 0, band, h))
    right = ImageOps.mirror(image.crop((w - band, 0, w, h)))
    midpoint = Image.blend(left, right, .5)
    weights = Image.new('L', (band, 1))
    weights.putdata([
        int(255 * (1.0 - (i / (band - 1))) ** 1.7)
        for i in range(band)
    ])
    weights = weights.resize((band, h))
    repaired_left = Image.composite(midpoint, left, weights)
    repaired_right = Image.composite(midpoint, right, weights)
    image.paste(repaired_left, (0, 0))
    image.paste(ImageOps.mirror(repaired_right), (w - band, 0))
    # Verify that the actual seam endpoints are identical.
    assert image.crop((0, 0, 1, h)).tobytes() == \
        image.crop((w - 1, 0, w, h)).tobytes()
    return image


def blend_city_lights(night):
    if not LIGHTS.exists():
        raise SystemExit('Real georeferenced satellite night-light asset missing')
    w, h = night.size
    radiance = Image.open(LIGHTS).convert('RGB')
    if abs(radiance.width / radiance.height - 2) > .02:
        raise SystemExit('Night lights asset must be 2:1 equirectangular')
    gray = ImageOps.grayscale(radiance)
    gray = gray.resize((w, h), Image.Resampling.LANCZOS)
    # Dark ocean remains transparent; bright city clusters turn warm gold.
    alpha = gray.point(lambda v: min(218, round(max(0, v - 11) * 2.5)))
    glow_alpha = alpha.filter(ImageFilter.GaussianBlur(5)).point(
        lambda v: round(v * .38))
    backdrop = night.convert('RGBA')
    halo = Image.new('RGBA', (w, h), (250, 175, 77, 0))
    halo.putalpha(glow_alpha)
    backdrop = Image.alpha_composite(backdrop, halo)
    center = Image.new('RGBA', (w, h), (255, 221, 147, 0))
    center.putalpha(alpha)
    return Image.alpha_composite(backdrop, center).convert('RGB')


def main():
    day = Image.open(DAY).convert('RGB')
    night = Image.open(NIGHT).convert('RGB')
    if day.size != night.size or abs(day.width / day.height - 2) > .02:
        raise SystemExit('Day/night world atlases must share a 2:1 pixel grid')
    day = blend_wrap_seam(day)
    night = blend_city_lights(night)
    night = blend_wrap_seam(night)
    # Lossless output keeps the two edges bit-for-bit identical.
    day.save(DAY, format='WEBP', lossless=True, method=5)
    night.save(NIGHT, format='WEBP', lossless=True, method=5)
    for filename in (DAY, NIGHT):
        check = Image.open(filename)
        if check.getpixel((0, check.height // 2)) != \
            check.getpixel((check.width - 1, check.height // 2)):
            raise SystemExit(f'Atlas has a visible wrap seam: {filename}')
        print(f'Prepared {filename.name} ({check.width}x{check.height})')


if __name__ == '__main__':
    main()
