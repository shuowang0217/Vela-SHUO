#!/usr/bin/env python3
"""Refine the original watercolor atlas for Vela v1.4.4 on both platforms.

This script fixes the 180-degree tile join and adds REAL geographical night
radiance from the project's existing earth_night_lights.png. It does not
redraw coastlines, replace the submitted artwork, or change the map projection.

Run before flutter pub get/build (the GitHub workflow runs it on all platforms).
"""
from pathlib import Path
from PIL import Image, ImageEnhance, ImageFilter, ImageOps, ImageChops

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


def polish_day(image):
    """Gently reveal pigment and coastline detail without redrawing the map.

    Small global adjustments retain the exact original watercolor paper,
    terrain, city coordinates and 2:1 projection on both platforms.
    """
    image = ImageEnhance.Contrast(image).enhance(1.055)
    image = ImageEnhance.Color(image).enhance(1.075)
    image = ImageEnhance.Brightness(image).enhance(1.014)
    return ImageEnhance.Sharpness(image).enhance(1.10)


def polish_night(image):
    """Give the original night watercolor blue-hour depth, not a dark overlay.

    The image still contains its original paper, terrain and coastline;
    real geographic city radiance is applied separately *after* this grade.
    """
    cool = ImageOps.colorize(
        ImageOps.grayscale(image),
        black="#071629", mid="#376078", white="#C7D7DB",
        blackpoint=0, whitepoint=255, midpoint=118,
    )
    image = Image.blend(image, cool, 0.44)
    image = ImageEnhance.Contrast(image).enhance(1.065)
    image = ImageEnhance.Color(image).enhance(0.91)
    return ImageEnhance.Sharpness(image).enhance(1.075)


def blend_city_lights(night):
    if not LIGHTS.exists():
        raise SystemExit('Real georeferenced satellite night-light asset missing')
    w, h = night.size
    radiance = Image.open(LIGHTS).convert('RGB')
    if abs(radiance.width / radiance.height - 2) > .02:
        raise SystemExit('Night lights asset must be 2:1 equirectangular')
    gray = ImageOps.grayscale(radiance)
    gray = gray.resize((w, h), Image.Resampling.LANCZOS)
    # Filter out satellite low-level sensor noise (especially at sea).
    # Stronger population centers receive a warm core plus two soft halos.
    alpha = gray.point(lambda v: min(226, round(max(0, v - 15) * 2.45)))
    outer_alpha = alpha.filter(ImageFilter.GaussianBlur(11)).point(
        lambda v: round(v * .23))
    inner_alpha = alpha.filter(ImageFilter.GaussianBlur(2.4)).point(
        lambda v: round(v * .54))
    backdrop = night.convert('RGBA')
    for color, opacity in (
        ((228, 150, 72, 0), outer_alpha),
        ((255, 192, 104, 0), inner_alpha),
        ((255, 226, 164, 0), alpha),
    ):
        glow = Image.new('RGBA', (w, h), color)
        glow.putalpha(opacity)
        backdrop = Image.alpha_composite(backdrop, glow)
    return backdrop.convert('RGB')


def main():
    day = Image.open(DAY).convert('RGB')
    night = Image.open(NIGHT).convert('RGB')
    if day.size != night.size or abs(day.width / day.height - 2) > .02:
        raise SystemExit('Day/night world atlases must share a 2:1 pixel grid')
    # Identical build-time artwork on Windows and Android; no runtime filter.
    day = blend_wrap_seam(polish_day(day))
    night_base = polish_night(night)
    night_with_lights = blend_city_lights(night_base)
    if ImageChops.difference(night_with_lights, night_base).getbbox() is None:
        raise SystemExit('Night city lights are absent after composition')
    night = blend_wrap_seam(night_with_lights)
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
