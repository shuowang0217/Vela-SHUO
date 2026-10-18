#!/usr/bin/env python3
"""Unpack user-approved individual oil painted HUD skins.

The source atlas reproduces three concrete user-supplied reference modules
(connection, upload/download, and five clickable painted medallions).
The atlas has NO live strings or fixed telemetry. Live widgets render on top.
"""
import hashlib
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'assets/oil/ui/reference_atlas.webp'
OUT=ROOT/'assets/oil/ui'
EXPECTED='aa0c5123f4582042d133b66766a53fac1dcc4dc157f241fae42f00b41474ad3c'

def main():
    raw=SRC.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=EXPECTED:
        raise ValueError('Painted HUD reference atlas corrupt')
    atlas=Image.open(SRC).convert('RGBA')
    assert atlas.size==(176,148),atlas.size
    # Each separate image is just paint and icon art, NOT an interactive
    # screenshot. Node text, VPN state and traffic remain native Flutter.
    regions=[
      ('connection_plaque.png',(0,0,487,158),(860,279)),
      ('speed_plaque.png',(0,161,487,311),(740,230)),
      ('paint_medallion.png',(0,316,84,404),(200,200)),
      ('oil_nav_book.png',(97,316,181,404),(200,200)),
      ('oil_nav_compass.png',(194,316,278,404),(200,200)),
      ('oil_nav_helm.png',(291,316,375,404),(200,200)),
      ('power_medallion.png',(388,316,472,404),(200,200)),
    ]
    for name,box,size in regions:
        x0,y0,x1,y1=box
        sx,sy=atlas.width/490.,atlas.height/410.
        area=tuple(round(v*sx) if i%2==0 else round(v*sy)
             for i,v in enumerate(box))
        image=atlas.crop(area).resize(size,Image.Resampling.LANCZOS)
        image.save(OUT/name,'PNG',optimize=True)
        assert image.getchannel('A').getbbox() is not None
    print('Prepared 7 user-approved thick-oil HUD image skins with alpha')

if __name__=='__main__':
    main()
