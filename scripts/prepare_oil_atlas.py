#!/usr/bin/env python3
"""Thick palette-knife Vela day/night atlases on the real world 2:1 map.

A real-world route requires real coordinates: unlike a flattened screenshot,
these are the same georeferenced pixels used by route and ship projections.
Oil reference provides pigment relief; moving clouds stay separate PNG layers.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageChops, ImageOps
import random, math

ROOT=Path(__file__).resolve().parents[1]
ASSETS=ROOT/"assets"
DEST=ASSETS/"oil"
DEST.mkdir(parents=True,exist_ok=True)
REFERENCE=DEST/"oil_map_clean.webp"

def render(source,target,*,night):
    original=Image.open(source).convert("RGB")
    w,h=original.size
    if w != h*2:
        raise ValueError("Oil atlas must keep original 2:1 coordinate grid")
    # Oil-painted colour fields, not a watercolour atlas with faint lines.
    base=Image.blend(original,original.filter(ImageFilter.ModeFilter(7)),.56)
    base=ImageEnhance.Color(base).enhance(1.20 if night else 1.43)
    base=ImageEnhance.Contrast(base).enhance(1.12 if night else 1.19)
    base=ImageEnhance.Sharpness(base).enhance(1.45)
    # The original approved impasto painting contributes tactile elevation.
    # Only its small-scale luminance relief is transferred; no fake continents,
    # static clouds, UI or geographic labels enter the georeferenced atlas.
    approved=Image.open(REFERENCE).convert("L").resize(
        (w,h),Image.Resampling.LANCZOS)
    relieved=ImageChops.difference(
        approved,approved.filter(ImageFilter.GaussianBlur(8)))
    relieved=ImageEnhance.Contrast(relieved).enhance(1.65)
    relief=ImageOps.colorize(relieved,black=(0,0,0),white=(245,232,212))
    base=Image.blend(base,ImageChops.add(base,relief,scale=1.0,offset=0),.20)
    strokes=Image.new("RGBA",(w,h),(0,0,0,0))
    draw=ImageDraw.Draw(strokes,"RGBA")
    pixels=base.load()
    rng=random.Random(185037 if night else 185036)
    # Wide, irregular, overlapping palette-knife paint dabs.
    # Water curls mostly horizontally while land follows the same atlas.
    for i in range(102000):
        x=rng.randrange(w);y=rng.randrange(h)
        pixel=pixels[x,y]
        bright=sum(pixel)/3
        blue=pixel[2]>pixel[0]*1.12 and pixel[2]>pixel[1]*.96
        length=rng.randrange(9,38) if blue else rng.randrange(7,29)
        dy=rng.randrange(-4,5) if blue else rng.randrange(-8,9)
        width=rng.randrange(2,8)
        delta=rng.randrange(-25,28)
        color=tuple(max(0,min(255,v+delta)) for v in pixel)
        a=rng.randrange(78,166)
        draw.line((x,y,x+length,y+dy),fill=(*color,a),
                  width=width,joint="curve")
        if rng.random()<.43:
            highlight=tuple(min(255,int(c*.65+255*.35)) for c in color)
            draw.line((x+1,y-2,x+length*.75,y+dy-2),
                      fill=(*highlight,rng.randrange(65,139)),
                      width=rng.randrange(1,3))
        # Use repeated pigment across both ends to hide map wrap seam.
        if x+length >= w:
            draw.line((x-w,y,x+length-w,y+dy),
                      fill=(*color,a),width=width)
    base=Image.alpha_composite(base.convert("RGBA"),strokes).convert("RGB")
    base.paste(base.crop((0,0,1,h)),(w-1,0))
    base.save(target,"WEBP",quality=95,method=6)
    print("impasto georeferenced atlas:",target.name,w,h,target.stat().st_size)

render(ASSETS/"world"/"watercolor_day.webp",
       DEST/"oil_atlas_day.webp",night=False)
render(ASSETS/"world"/"watercolor_night.webp",
       DEST/"oil_atlas_night.webp",night=True)
