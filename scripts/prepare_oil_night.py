#!/usr/bin/env python3
"""Independent moonlit oil atlas: city lights and six painted night clouds."""
from pathlib import Path
import random
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageOps

OIL=Path(__file__).resolve().parents[1]/'assets/oil'
CITIES=[
 (135,170,22,12,160),(195,178,20,13,145),(265,163,19,10,130),
 (325,175,16,12,110),(310,380,17,12,95),
 (425,365,22,16,170),(450,445,26,24,180),
 (515,340,23,16,190),(575,288,32,18,325),
 (635,306,25,17,230),(675,320,22,13,205),
 (740,327,18,12,200),(706,357,13,10,135),
 (584,421,15,15,135),(634,420,12,16,105),
 (600,496,17,14,125),(649,539,15,16,120),
 (726,514,12,12,125),(690,586,27,12,165),
 (410,522,11,13,65),(820,732,16,12,94),
 (924,781,21,12,118),(967,766,16,12,150),
 (1014,715,13,9,70),(1110,843,9,7,70),
 (1460,235,25,13,200),(1530,320,28,15,205),
 (1580,392,20,18,145),(1502,520,18,12,115),(1620,626,12,9,80),
]
def moonlight(image):
    r,g,b=image.convert('RGB').split()
    a=r.point([min(255,int(i*.32+2)) for i in range(256)])
    c=g.point([min(255,int(i*.40+9)) for i in range(256)])
    d=b.point([min(255,int(i*.62+23)) for i in range(256)])
    return ImageEnhance.Color(ImageEnhance.Contrast(
        Image.merge('RGB',(a,c,d))).enhance(1.15)).enhance(.84)

def urban_lights(base):
    w,h=base.size
    sx,sy=w/1672.,h/941.
    stars=Image.new('RGBA',(w,h),(0,0,0,0))
    glow=Image.new('RGBA',(w,h),(0,0,0,0))
    brush=ImageDraw.Draw(stars,'RGBA')
    haze=ImageDraw.Draw(glow,'RGBA')
    rng=random.Random(418104)
    for cx,cy,rx,ry,count in CITIES:
        cx,cy,rx,ry=cx*sx,cy*sy,rx*sx,ry*sy
        haze.ellipse((cx-rx*2,cy-ry*2,cx+rx*2,cy+ry*2),
                     fill=(236,155,44,13))
        for _ in range(count):
            x,y=cx+rng.gauss(0,rx*.62),cy+rng.gauss(0,ry*.62)
            if not (1<x<w-2 and 1<y<h-2):continue
            rad=rng.choice([.55,.8,.85,1.,1.15,1.8])*max(.8,sx)
            color=rng.choice([(255,181,72,238),(255,211,117,205),
                              (255,236,162,242),(241,151,52,198)])
            brush.ellipse((x-rad,y-rad,x+rad,y+rad),fill=color)
            if rng.random()<.23:
                brush.line((x-rad,y,x+rad*2,y-.5),
                  fill=(245,168,61,rng.randrange(70,140)),width=1)
    painted=Image.alpha_composite(base.convert('RGBA'),
         glow.filter(ImageFilter.GaussianBlur(22)))
    painted=Image.alpha_composite(painted,
         stars.filter(ImageFilter.GaussianBlur(6)))
    return Image.alpha_composite(painted,stars).convert('RGB')

def colorize_oil(image,mid_color,shadow,highlight):
    rgba=image.convert('RGBA')
    lum=ImageEnhance.Contrast(ImageOps.grayscale(rgba)).enhance(1.13)
    painted=ImageOps.colorize(lum,black=shadow,
                  mid=mid_color,white=highlight,midpoint=120)
    painted.putalpha(rgba.getchannel('A'))
    return painted

def main():
    day=Image.open(OIL/'oil_map_clean.webp').convert('RGB')
    night=urban_lights(moonlight(day))
    night.save(OIL/'oil_map_night.webp','WEBP',quality=94,method=5)
    assert night.size==day.size
    for name in ['cloud_beijing_clean','cloud_north','cloud_east',
                 'cloud_southwest','cloud_equator','cloud_southeast_clean']:
        cloud=colorize_oil(
            Image.open(OIL/'clouds'/f'{name}.png'),
            (98,111,152),(33,48,83),(208,217,243))
        cloud.save(OIL/'clouds'/f'night_{name}.png','PNG',optimize=True)
        assert cloud.getchannel('A').getbbox() is not None
    ui=OIL/'ui'
    colorize_oil(Image.open(ui/'oil_canvas.webp'),(101,111,145),
                 (30,37,66),(207,204,196)).convert('RGB').save(
                     ui/'oil_canvas_night.webp','WEBP',quality=90,method=5)
    for name in ['connection_plaque.png','speed_plaque.png',
                 'paint_medallion.png','power_medallion.png']:
        colored=colorize_oil(Image.open(ui/name),
             (101,111,145),(30,37,66),(207,204,196))
        colored.save(ui/f'night_{name}','PNG',optimize=True)
    print('Created moonlit oil panorama, warm city lights and six night clouds')

if __name__=='__main__':
    main()
