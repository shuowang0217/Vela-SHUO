#!/usr/bin/env python3
"""Unpack user-approved individual oil painted HUD skins.

The source atlas reproduces three concrete user-supplied reference modules
(connection, upload/download, and five clickable painted medallions).
The atlas has NO live strings or fixed telemetry. Live widgets render on top.
"""
import base64
import hashlib
from io import BytesIO
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'assets/oil/ui/reference_atlas.b64'
OUT=ROOT/'assets/oil/ui'
EXPECTED='71bae9103532d37ec33b534dd167ca0b7e797db1afca3323c8d5f3cbeda90fb6'

def main():
    raw=base64.b64decode(''.join(SRC.read_text().split()),validate=True)
    if hashlib.sha256(raw).hexdigest()!=EXPECTED:
        raise ValueError('Painted HUD reference atlas corrupt')
    atlas=Image.open(BytesIO(raw)).convert('RGBA')
    assert atlas.size==(220,184),atlas.size
    # Each separate image is just paint and icon art, NOT an interactive
    # screenshot. Node text, VPN state and traffic remain native Flutter.
    regions=[
      ('connection_plaque.png',(0,0,220,72),(860,279)),
      ('speed_plaque.png',(0,72,220,140),(740,230)),
      ('paint_medallion.png',(0,142,39,182),(200,200)),
      ('oil_nav_book.png',(44,142,83,182),(200,200)),
      ('oil_nav_compass.png',(87,142,126,182),(200,200)),
      ('oil_nav_helm.png',(131,142,170,182),(200,200)),
      ('power_medallion.png',(174,142,213,182),(200,200)),
    ]
    for name,box,size in regions:
        image=atlas.crop(box).resize(size,Image.Resampling.LANCZOS)
        image.save(OUT/name,'PNG',optimize=True)
        assert image.getchannel('A').getbbox()
    print('Prepared 7 user-approved thick-oil HUD image skins with alpha')

if __name__=='__main__':
    main()
