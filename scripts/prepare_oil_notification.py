#!/usr/bin/env python3
"""Render the exact approved sea/gull/sailboat art into native notifications.

The source is a clean crop of the user's approved oil-style mockup, excluding
the baked app icon, text, clock, chevron and system notification shell.
The right side contains the original gulls, sails, ocean and painted sky.
"""
from pathlib import Path

from PIL import Image, ImageEnhance, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/oil/ui/notification_maritime_reference.webp"
DESTINATION = ROOT / "assets/oil/ui"
SIZE = (900, 210)


def build(dark: bool) -> None:
    if not SOURCE.is_file():
        raise FileNotFoundError("Approved sea, birds and sail artwork missing")
    with Image.open(SOURCE) as art:
        canvas = art.convert("RGBA").resize(SIZE, Image.Resampling.LANCZOS)

    # Night mode recolors only pigments. It retains the same maritime scene.
    if dark:
        alpha = canvas.getchannel("A")
        night = ImageOps.colorize(
            ImageEnhance.Contrast(ImageOps.grayscale(canvas)).enhance(1.05),
            black=(14, 30, 48),
            mid=(61, 94, 121),
            white=(194, 205, 206),
            midpoint=115).convert("RGBA")
        night.putalpha(alpha)
        canvas = night

    # Edges are alpha-feathered in the approved source to avoid a rectangular
    # inner image floating inside the system-owned One UI notification card.
    alpha = canvas.getchannel("A")
    assert alpha.getextrema()[0] == 0
    assert alpha.getbbox() is not None
    name = "night" if dark else "day"
    target = DESTINATION / f"notification_oil_{name}.png"
    canvas.save(target, "PNG", optimize=True)
    assert target.is_file() and target.stat().st_size > 0
    print("Approved real maritime Vela notification asset:", target)


def main() -> None:
    DESTINATION.mkdir(parents=True, exist_ok=True)
    build(False)
    build(True)


if __name__ == "__main__":
    main()
