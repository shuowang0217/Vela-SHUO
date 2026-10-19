#!/usr/bin/env python3
"""Package approved oil-painted Vela icon into native Windows/Android assets.

Requires Pillow, which is installed only in the release CI image; Flutter's
runtime mark is independently painted with lib/src/brand/vela_sail_mark.dart.
No external branding, templates or mutable network downloads are used.
"""
from __future__ import annotations
import argparse
import random
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps

SIZE = 768
SCALE = SIZE / 160


def q(v: float) -> int:
    return round(v * SCALE)


def point(x: float, y: float):
    return q(x), q(y)


def cubic(p0, p1, p2, p3, count=48):
    output = []
    for i in range(count + 1):
        t = i / count
        v = 1 - t
        x = v**3*p0[0] + 3*v*v*t*p1[0] + 3*v*t*t*p2[0] + t**3*p3[0]
        y = v**3*p0[1] + 3*v*v*t*p1[1] + 3*v*t*t*p2[1] + t**3*p3[1]
        output.append(point(x, y))
    return output


def gradient(top, bottom):
    image = Image.new("RGBA", (SIZE, SIZE))
    pixels = image.load()
    for y in range(SIZE):
        t = y / (SIZE - 1)
        c = tuple(round(top[i] * (1 - t) + bottom[i] * t)
                  for i in range(3)) + (255,)
        for x in range(SIZE):
            pixels[x, y] = c
    return image


def paths(layer: Image.Image, inactive=False):
    draw = ImageDraw.Draw(layer)
    gold = (213, 172, 116, 255) if not inactive else (140, 158, 176, 255)
    silver = (247, 241, 220, 255) if not inactive else (186, 205, 223, 255)
    dark = (40, 86, 98, 255) if not inactive else (105, 126, 148, 255)

    # Open champagne compass arc.
    draw.arc((q(22), q(17), q(147), q(143)), start=191, end=261,
             fill=gold, width=q(2.2))

    # Main midnight-steel sail, with a positive beveled face.
    right = (cubic((83, 12), (110, 27), (120, 65), (121, 107))
             + cubic((121, 107), (105, 95), (95, 95), (87, 96))
             + cubic((87, 96), (85, 59), (83, 31), (83, 12)))
    sail_mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(sail_mask).polygon(right, fill=255)
    steel_gradient = gradient((40, 86, 98), (232, 201, 149))
    layer.paste(steel_gradient, (0, 0), sail_mask)
    if inactive:
        layer.paste(dark, (0, 0), sail_mask)

    left = (cubic((80, 16), (72, 48), (56, 84), (37, 105))
            + cubic((37, 105), (55, 98), (66, 100), (75, 105))
            + cubic((75, 105), (83, 78), (82, 41), (80, 16)))
    draw.polygon(left, fill=dark)
    inner = (cubic((81, 23), (83, 52), (82, 80), (75, 104))
             + cubic((75, 104), (78, 109), (83, 112), (85, 109))
             + cubic((85, 109), (87, 70), (86, 46), (81, 23)))
    draw.polygon(inner, fill=silver)

    hull = (cubic((9, 126), (39, 108), (70, 113), (91, 120))
            + cubic((91, 120), (111, 127), (133, 131), (153, 119))
            + cubic((153, 119), (136, 143), (108, 142), (83, 133))
            + cubic((83, 133), (52, 124), (34, 119), (9, 126)))
    draw.polygon(hull, fill=dark)
    wave = cubic((12, 140), (47, 131), (79, 141), (105, 144))
    wave += cubic((105, 144), (120, 147), (133, 143), (145, 138))
    draw.line(wave, fill=gold, width=q(2.5), joint="curve")
    star = [(135, 32), (138, 40), (146, 43), (138, 46),
            (135, 54), (132, 46), (124, 43), (132, 40)]
    draw.polygon([point(*p) for p in star], fill=gold)


def render(inactive=False):
    # ONE APPROVED ART SOURCE FOR ALL PLATFORMS. No procedural gradient,
    # generic vector sail, or old icon substitution during packaging.
    original=Path("assets/brand/vela_selected_icon.png")
    if not original.is_file():
        raise FileNotFoundError(
            "Generate the selected brand images before launcher icons")
    image=Image.open(original).convert("RGBA")
    if image.size != (512,512):
        raise ValueError("Selected artwork was not prepared at 512x512")
    image=image.resize((SIZE,SIZE),Image.Resampling.LANCZOS)
    if inactive:
        gray=ImageOps.grayscale(image.convert("RGB")).convert("RGBA")
        gray.putalpha(image.getchannel("A"))
        return gray
    return image


def save_icon(image: Image.Image, destination: Path):
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, format="ICO",
               sizes=[(16, 16), (24, 24), (32, 32),
                      (48, 48), (64, 64), (128, 128), (256, 256)])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--windows", action="store_true")
    parser.add_argument("--android", action="store_true")
    args = parser.parse_args()
    if not (args.windows or args.android):
        parser.error("Specify --windows or --android")
    active = render()
    if args.windows:
        save_icon(active, Path("windows/runner/resources/app_icon.ico"))
        save_icon(active, Path("assets/tray/proxy_on.ico"))
        save_icon(render(inactive=True), Path("assets/tray/proxy_off.ico"))
        print("Vela Windows launcher and ON/OFF system tray icons ready")
    if args.android:
        root = Path("android/app/src/main/res")
        for density, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                            ("xxhdpi", 144), ("xxxhdpi", 192)):
            icon = root / f"mipmap-{density}" / "ic_launcher.png"
            icon.parent.mkdir(parents=True, exist_ok=True)
            active.resize((px, px), Image.Resampling.LANCZOS).save(icon)
        print("Vela Android launcher icons ready for all five densities")


if __name__ == "__main__":
    main()
