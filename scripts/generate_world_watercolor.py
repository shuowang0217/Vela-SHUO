#!/usr/bin/env python3
"""Actual georeferenced steel-pen/watercolor world atlas, generated offline.
The coastline source is assets/maps/world_110m.json (lon,lat coordinates).
A concept painting must NEVER be substituted for georeferenced map geometry.
"""
import json
import random
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageOps

ROOT=Path(__file__).resolve().parents[1]
SIZE=(2400,1200)
SEED=51320

def point(lon,lat):
    return (round((lon+180)*SIZE[0]/360),round((90-lat)*SIZE[1]/180))

def noise(a,b,seed=SEED,span=60):
    random.seed(seed)
    low=Image.effect_noise((SIZE[0]//span,SIZE[1]//span),46)
    return ImageOps.colorize(low.resize(SIZE,Image.Resampling.BICUBIC),a,b)

def wash(canvas,color,region,rng,n=150):
    x1,y1,x2,y2=region
    x1=max(0,x1);x2=min(SIZE[0],x2);y1=max(0,y1);y2=min(SIZE[1],y2)
    if x2<=x1 or y2<=y1:return
    mask=Image.new('L',SIZE)
    draw=ImageDraw.Draw(mask)
    for _ in range(n):
        x=rng.randrange(x1,x2);y=rng.randrange(y1,y2)
        a=rng.randrange(12,80);b=rng.randrange(12,60)
        draw.ellipse((x-a,y-b,x+a,y+b),fill=120)
    canvas.paste(color,(0,0,*SIZE),mask.filter(ImageFilter.GaussianBlur(19)))

def map_polygons():
    data=json.loads((ROOT/'assets/maps/world_110m.json').read_text())
    if not isinstance(data,list) or len(data)<100:
        raise SystemExit('Missing geographical atlas polygons')
    return [[point(*map(float,p)) for p in ring] for ring in data
            if len(ring)>2]

def artwork(polygons,dark):
    rng=random.Random(SEED+int(dark))
    water=noise('#092339' if dark else '#cfe8e6',
                '#23536e' if dark else '#4a9fc3',SEED+int(dark))
    scattered=Image.new('RGBA',SIZE,(0,0,0,0))
    sd=ImageDraw.Draw(scattered)
    for _ in range(800):
        x=rng.randrange(SIZE[0]);y=rng.randrange(SIZE[1])
        a=rng.randrange(12,110);b=rng.randrange(4,43)
        sd.ellipse((x-a,y-b,x+a,y+b),
          fill=(85,152,166,20) if dark else (243,248,222,33))
    water=Image.alpha_composite(water.convert('RGBA'),
       scattered.filter(ImageFilter.GaussianBlur(9))).convert('RGB')
    mask=Image.new('L',SIZE)
    md=ImageDraw.Draw(mask)
    for ring in polygons:md.polygon(ring,fill=255)
    land=noise('#ad9d70' if dark else '#c4b37d',
               '#c6c4a0' if dark else '#f4e9c6',SEED+8,54)
    regions=[
      ((-17,8,53,38),'#d1aa75' if dark else '#edca90'),
      ((10,35,135,66),'#678576' if dark else '#81ab87'),
      ((65,15,125,46),'#6b9683' if dark else '#8fbd9a'),
      ((-127,28,-65,66),'#769686' if dark else '#8faf84'),
      ((-82,-23,-43,14),'#668c6d' if dark else '#7fa579'),
      ((15,-30,39,15),'#8c956d' if dark else '#9caa75'),
      ((113,-39,151,-10),'#ad866b' if dark else '#e2a66f'),
      ((-63,60,-22,84),'#bdc6b8' if dark else '#f6f4e6'),
      ((-180,-90,180,-72),'#b2bdc0' if dark else '#e7f4ee'),
    ]
    for (lon1,lat1,lon2,lat2),pigment in regions:
        x1,y1=point(lon1,lat2);x2,y2=point(lon2,lat1)
        wash(land,pigment,(x1,y1,x2,y2),rng,230)
    composite=Image.composite(land,water,mask)
    beach=ImageChops.subtract(mask.filter(ImageFilter.MaxFilter(19)),mask)
    beach=beach.filter(ImageFilter.GaussianBlur(7))
    composite.paste('#709f9c' if dark else '#c9e1d3',
         (0,0,*SIZE),beach.point(lambda x:x//2))
    contour=ImageChops.difference(mask.filter(ImageFilter.MaxFilter(5)),
                                  mask.filter(ImageFilter.MinFilter(5)))
    composite.paste('#cab98d' if dark else '#31555c',
         (0,0,*SIZE),contour.point(lambda a:round(a*.66)))
    art=Image.new('RGBA',SIZE,(0,0,0,0))
    draw=ImageDraw.Draw(art)
    mountains=[(-110,42,12,20),(-72,-15,9,31),(83,32,28,9),
               (10,47,13,5),(45,41,9,5),(139,37,5,5)]
    for lon,lat,w,h in mountains:
        for _ in range(47):
            x,y=point(lon+rng.uniform(-w,w),lat+rng.uniform(-h,h))
            a=rng.randrange(6,21)
            ink=(218,197,150,135) if dark else (59,74,66,144)
            draw.line([(x-a//2,y+3),(x,y-a),(x+a//2,y+3)],
                      fill=ink,width=2)
            draw.line([(x-2,y-a+5),(x+2,y-a+8)],
                      fill=(244,230,194,130) if dark else (251,245,216,160),width=2)
    trees=[(-99,48,28,11),(-59,-7,12,18),(40,57,57,9),
           (107,28,15,12),(19,-4,15,11)]
    for lon,lat,w,h in trees:
        for _ in range(78):
            x,y=point(lon+rng.uniform(-w,w),lat+rng.uniform(-h,h))
            a=rng.randrange(5,12)
            ink=(142,166,135,135) if dark else (54,102,86,140)
            draw.line([(x-a//2,y+2),(x,y-a),(x+a//2,y+2)],
                      fill=ink,width=2)
    waves=(170,204,191,80) if dark else (241,250,229,150)
    for _ in range(430):
        x=rng.randrange(1,SIZE[0]-45);y=rng.randrange(1,SIZE[1]-15)
        if mask.getpixel((x,y))>0:continue
        length=rng.randrange(10,44)
        draw.arc((x,y,x+length,y+9),18,160,fill=waves,width=1)
    composite=Image.alpha_composite(composite.convert('RGBA'),art).convert('RGB')
    grain=ImageOps.colorize(Image.effect_noise(SIZE,10).convert('L'),
            '#18303a' if dark else '#d9d0b7',
            '#567a82' if dark else '#fff7e6')
    return Image.blend(composite,grain,.055 if dark else .11)

def paper(dark):
    dimensions=(720,480)
    film=Image.effect_noise(dimensions,14).convert('L')
    base=ImageOps.colorize(film,
       '#1b3540' if dark else '#ebddc2',
       '#355563' if dark else '#fff9ec')
    stains=Image.new('RGBA',dimensions,(0,0,0,0))
    d=ImageDraw.Draw(stains);rng=random.Random(SEED)
    for _ in range(120):
        x=rng.randrange(720);y=rng.randrange(480);r=rng.randrange(15,75)
        d.ellipse((x-r,y-r//2,x+r,y+r//2),
             fill=(81,137,144,18) if dark else (92,157,156,26))
    return Image.alpha_composite(base.convert('RGBA'),
          stains.filter(ImageFilter.GaussianBlur(11))).convert('RGB')

def main():
    polygons=map_polygons()
    out=ROOT/'assets/journal';out.mkdir(parents=True,exist_ok=True)
    for dark in (False,True):
        mode='night' if dark else 'day'
        destination=ROOT/f'assets/earth/earth_watercolor_{mode}.jpg'
        destination.parent.mkdir(parents=True,exist_ok=True)
        artwork(polygons,dark).save(destination,'JPEG',quality=90,
            optimize=True,progressive=True,subsampling=0)
        paper(dark).save(out/f'paper_{mode}.jpg','JPEG',quality=88,
                         optimize=True)
        print(mode,'map bytes',destination.stat().st_size)

if __name__=='__main__':main()
