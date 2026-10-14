#!/usr/bin/env python3
"""Derive geo-aligned ink-and-watercolor atlas assets from the existing Earth map.

The attached hand-painted concept is a visual reference, NOT a geo source:
node coordinates must never be placed directly on AI-invented coastlines.
This deterministic script transforms the already licensed Vela 2:1 terrain
image, preserving accurate lon/lat coordinates and image wrap behavior.
"""
from pathlib import Path
from PIL import Image, ImageEnhance, ImageFilter, ImageOps, ImageChops

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/earth/earth_day.jpg"
SIZE = (2048, 1024)


def _ink_edges(image):
    gray = ImageOps.grayscale(image).filter(ImageFilter.GaussianBlur(1.2))
    return gray.filter(ImageFilter.FIND_EDGES).point(
        lambda n: min(126, round(n * .70))
    )


def _paper_grain(size):
    noise = Image.effect_noise(size, 13).convert("L")
    paper = Image.new("RGB", size, (247, 241, 225))
    paper.paste((236, 228, 208), mask=noise.point(lambda n: n // 6))
    return paper


def generate():
    if not SOURCE.is_file():
        raise SystemExit(f"Missing geo-registered source map: {SOURCE}")
    source = Image.open(SOURCE).convert("RGB")
    if abs(source.width / source.height - 2.0) > .015:
        raise SystemExit("World terrain must be a 2:1 equirectangular image")
    original = source.resize(SIZE, Image.Resampling.LANCZOS)
    smooth = original.filter(ImageFilter.GaussianBlur(.75))
    painted = ImageOps.posterize(smooth, 5)
    painted = ImageEnhance.Color(painted).enhance(.83)
    painted = ImageEnhance.Contrast(painted).enhance(.96)
    paper = _paper_grain(SIZE)
    # Matte watercolor pigment, parchment wash and restrained coastal ink.
    day = Image.blend(painted, paper, .14)
    day.paste((40, 69, 79), mask=_ink_edges(smooth))
    day = ImageEnhance.Color(day).enhance(.97)
    # A matching midnight journal palette—not a blank city-light texture.
    night = ImageOps.colorize(
        ImageOps.grayscale(painted),
        black="#091d30", white="#adc9c7", mid="#547c88",
        blackpoint=12, whitepoint=248,
    )
    night = Image.blend(night, Image.new("RGB", SIZE, "#112b42"), .12)
    night.paste((158, 190, 178), mask=_ink_edges(smooth).point(
        lambda n: n * 3 // 5
    ))
    night = Image.blend(night, ImageChops.multiply(night, paper), .04)
    outputs = [
        (ROOT / "assets/earth/earth_watercolor_day.jpg", day),
        (ROOT / "assets/earth/earth_watercolor_night.jpg", night),
    ]
    for path, image in outputs:
        path.parent.mkdir(parents=True, exist_ok=True)
        image.save(path, "JPEG", quality=88, subsampling=0,
                   optimize=True, progressive=True)
        print(f"Generated {path.relative_to(ROOT)} [{image.size[0]}x{image.size[1]}]")


if __name__ == "__main__":
    generate()
