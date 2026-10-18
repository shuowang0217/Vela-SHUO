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
D = (115, 82, 55)
H = (255, 253, 225)

def canvas(size, seed):
    r = random.Random(seed)
    src = Image.open(SOURCE).convert("RGB")
    w, h = size
    # Use genuine thick painted clouds in the reference, rather than a
    # procedural line drawing or an unprocessed map screenshot.
    cloud = src.crop((300, 70, 1120, 575))
    original = ImageOps.fit(cloud, size, method=Image.Resampling.LANCZOS)
    color = Image.new("RGB", size, C)
    img = Image.blend(original, color, .74).convert("RGBA")
    draw = ImageDraw.Draw(img, "RGBA")
    for i in range(w*h//65):
        x, y = r.randrange(w), r.randrange(h)
        base = r.choice([(255,252,228,54), (255,255,246,62),
                         (176,137,94,29),(214,177,123,53),
                         (239,213,170,80)])
        dx, dy = r.randrange(8,28),r.randrange(-4,5)
        width = r.randrange(2,7)
        draw.line((x,y,x+dx,y+dy),fill=base,width=width)
        if r.random() < .5:
            draw.line((x+2,y-1,x+dx-4,y+dy-1),
                      fill=(255,255,252,65),width=2)
    return img

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

def plaque(name,size,seed,radius,round_button=False):
    w,h=size
    rng=random.Random(seed)
    material=canvas(size,seed)
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
    contracted=alpha.filter(ImageFilter.MinFilter(13))
    inner=Image.new("RGBA",size,(0,0,0,0))
    dark=Image.new("RGBA",size,(*D,255));dark.putalpha(expanded)
    inner.alpha_composite(dark)
    paper=material.copy();paper.putalpha(alpha)
    inner.alpha_composite(paper)
    d=ImageDraw.Draw(inner,"RGBA")
    if round_button:
        d.ellipse((24,22,w-24,h-24),
                  outline=(255,254,229,215),width=5)
        d.arc((15,15,w-15,h-15),180,345,fill=(148,99,57,152),width=5)
    else:
        d.rounded_rectangle((18,15,w-18,h-16),radius=radius,
                            outline=(255,255,237,200),width=6)
        d.arc((21,18,w-20,h-20),190,342,
              fill=(151,109,72,140),width=5)
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
    plaque("connection_plaque.png",(860,234),39012,58)
    plaque("speed_plaque.png",(740,230),39013,56)
    plaque("paint_medallion.png",(200,200),39014,92,True)
    # Always verify the alpha-supported material is not blank.
    for filename in ("connection_plaque.png","speed_plaque.png",
                     "paint_medallion.png"):
        im=Image.open(OUT/filename)
        assert im.mode=="RGBA" and im.getextrema()[3][0]==0
        assert im.getextrema()[3][1]>=250
    print("Vela impasto UI materials generated:", *(p.name for p in OUT.iterdir()))

if __name__=="__main__":
    main()
