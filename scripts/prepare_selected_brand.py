#!/usr/bin/env python3
"""Prepare the ACTUAL approved navy/gold oil-sail and painted VELA wordmark.

The source is a small transparent WEBP atlas cut from the user's selected
painting (not a vector repaint). Native launcher sizes are derived from the
same pixels as the Flutter masthead. All outputs are generated before tests.
"""
from pathlib import Path
from PIL import Image, ImageFilter, ImageOps

ROOT=Path(__file__).resolve().parents[1]
ASSET=ROOT/"assets/brand/selected_oil_identity.webp"
OUT=ROOT/"assets/brand"

def upscale(image, size):
    result=image.resize(size,Image.Resampling.LANCZOS)
    # Restore small pigment highlights without re-illustrating the artwork.
    return result.filter(ImageFilter.UnsharpMask(radius=1.1,percent=115,threshold=3))

def main():
    if not ASSET.is_file():
        raise FileNotFoundError("Approved Vela icon/wordmark atlas is missing")
    atlas=Image.open(ASSET).convert("RGBA")
    assert atlas.size==(144,160),atlas.size
    icon=atlas.crop((28,0,116,88))
    wordmark=atlas.crop((2,92,143,160))
    icon=upscale(icon,(512,512))
    wordmark=upscale(wordmark,(704,340))
    for image in (icon,wordmark):
        assert image.getchannel("A").getextrema()[0]==0
        assert image.getchannel("A").getbbox() is not None
    OUT.mkdir(parents=True,exist_ok=True)
    icon.save(OUT/"vela_selected_icon.png",optimize=True)
    wordmark.save(OUT/"vela_selected_wordmark.png",optimize=True)
    print("User-approved oil sail and handwritten VELA image assets ready")

if __name__=="__main__":
    main()
