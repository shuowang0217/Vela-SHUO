#!/usr/bin/env python3
"""Bake oil-impasto UI materials from the EXISTING approved Vela painting.

Every panel is a transparent texture with palette-knife edges, not a screenshot:
all texts, data and gestures are live Flutter widgets layered above the paint.
Run in CI on both targets immediately after prepare_oil_atlas.py.
"""
from pathlib import Path
import random
import math
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/oil/oil_map_clean.webp"
OUT = ROOT / "assets/oil/ui"
OUT.mkdir(parents=True, exist_ok=True)
C = (246, 230, 196)
D = (194, 163, 130)
H = (255, 253, 225)

def canvas(size, seed):
    # The former randomly cropped map included dark land/sky and introduced
    # hundreds of evenly spaced horizontal hatches (woodgrain, not oil paint).
    # Sample a proven text-free thick cloud and preserve its palette-knife
    # luminance ridges as genuine warm ivory pigment.
    src = Image.open(SOURCE).convert("RGB")
    cloud = src.crop((798, 545, 1190, 755))
    original = ImageOps.fit(cloud, size,
                            method=Image.Resampling.LANCZOS).convert("L")
    original = ImageEnhance.Contrast(original).enhance(1.33)
    pigment = ImageOps.colorize(
        original,
        black=(174, 150, 126), mid=(242, 219, 180),
        white=(255, 249, 224),
        blackpoint=30, whitepoint=239, midpoint=120)
    return ImageEnhance.Sharpness(pigment).enhance(1.26).convert("RGBA")


def tile():
    im = canvas((384,384), 39011)
    # Deliberately pronounced palette-knife pigment, but no repeated hatch.
    im.convert("RGB").save(OUT/"oil_canvas.webp", "WEBP",quality=91,method=5)

def mask_plaque(w,h,radius,seed):
    rng = random.Random(seed)
    m = Image.new("L",(w,h),0)
    d = ImageDraw.Draw(m)
    pad = max(11,int(h*.065))
    d.rounded_rectangle((pad,pad,w-pad-1,h-pad-1),
                        radius=radius,fill=255)
    # Lumped overpaint at the edge. The border is chunky and imperfect.
    for side in range(4):
        span = (w if side in (0,2) else h)
        for i in range(0,span,7):
            k=rng.randint(3,13)
            if side==0:
                x,y=i,pad+rng.randint(-5,3)
            elif side==2:
                x,y=i,h-pad+rng.randint(-3,5)
            elif side==1:
                x,y=w-pad+rng.randint(-5,3),i
            else:
                x,y=pad+rng.randint(-3,5),i
            d.ellipse((x-k//2,y-k//2,x+k//2,y+k//2),fill=255)
    return m.filter(ImageFilter.GaussianBlur(.7))

def plaque(name,size,seed,radius,round_button=False,dark_button=False):
    w,h=size
    rng=random.Random(seed)
    material=canvas(size,seed)
    if dark_button:
        material=ImageOps.colorize(ImageOps.grayscale(material),
            black=(12,28,59),white=(57,92,155)).convert("RGBA")
    alpha=Image.new("L",size,0)
    if round_button:
        d=ImageDraw.Draw(alpha)
        cx,cy=w//2,h//2
        d.ellipse((12,12,w-12,h-12),fill=255)
        for i in range(150):
            ang=rng.random()*math.tau
            rad=min(w,h)*(.45 + rng.random()*.045)
            x=cx+math.cos(ang)*rad
            y=cy+math.sin(ang)*rad
            rr=rng.randrange(4,12)
            d.ellipse((int(x-rr),int(y-rr),int(x+rr),int(y+rr)),fill=255)
        alpha=alpha.filter(ImageFilter.GaussianBlur(.9))
    else:
        alpha=mask_plaque(w,h,radius,seed)
    # Carved deep shadow under lighter paint, with an embossed rim.
    expanded=alpha.filter(ImageFilter.MaxFilter(13))
    inner=Image.new("RGBA",size,(0,0,0,0))
    dark=Image.new("RGBA",size,(*D,255));dark.putalpha(expanded)
    inner.alpha_composite(dark)
    paper=material.copy();paper.putalpha(alpha)
    inner.alpha_composite(paper)
    d=ImageDraw.Draw(inner,"RGBA")
    if round_button:
        d.ellipse((24,22,w-24,h-24),
                  outline=(255,254,229,215),width=5)
    else:
        d.rounded_rectangle((18,15,w-18,h-16),radius=radius,
                            outline=(255,255,237,200),width=6)
    # Organic little edge heaps catch light. No straight ornamental lines.
    for j in range(int((w+h)*.18)):
        x=rng.randrange(12,w-12); y=rng.randrange(10,h-10)
        if rng.random()<.67 and (min(x,w-x)<35 or min(y,h-y)<30):
            d.ellipse((x,y,x+rng.randrange(3,13),
                       y+rng.randrange(2,7)),
                      fill=(255,251,230,rng.randrange(90,180)))
    inner.save(OUT/name, "PNG", optimize=True)

def main():
    if not SOURCE.is_file():
        raise SystemExit("Approved oil art is required to build painted Vela UI")
    tile()
    # The previous cloud_beijing.png had literal BEIJING lettering painted
    # into the moving sprite. Never ship text as a moving cloud again.
    # Mirror the text-free northern cloud to make a distinct clean layer.
    north = Image.open(ROOT / "assets/oil/clouds/cloud_north.png").convert("RGBA")
    clean = ImageOps.mirror(north).resize((444, 211),
        Image.Resampling.LANCZOS)
    clean.save(ROOT / "assets/oil/clouds/cloud_beijing_clean.png",
        "PNG", optimize=True)
    # The southeast source also contains three cut-off circular HUD controls
    # at its lower edge. Make a second clean independent brushwork sprite.
    east = Image.open(ROOT / "assets/oil/clouds/cloud_east.png").convert("RGBA")
    southeast = ImageOps.mirror(east).resize((421, 180),
        Image.Resampling.LANCZOS)
    southeast.save(ROOT / "assets/oil/clouds/cloud_southeast_clean.png",
        "PNG", optimize=True)
    plaque("connection_plaque.png",(860,234),39012,58)
    plaque("speed_plaque.png",(740,230),39013,56)
    plaque("paint_medallion.png",(200,200),39014,92,True)
    plaque("power_medallion.png",(200,200),39015,92,True,True)
    # Always verify the alpha-supported material is not blank.
    for filename in ("connection_plaque.png","speed_plaque.png",
                     "paint_medallion.png","power_medallion.png"):
        im=Image.open(OUT/filename)
        assert im.mode=="RGBA" and im.getextrema()[3][0]==0
        assert im.getextrema()[3][1]>=250
    print("Vela impasto UI materials generated:", *(p.name for p in OUT.iterdir()))

if __name__=="__main__":
    main()
