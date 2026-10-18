#!/usr/bin/env python3
"""Restore the blurred radial smear baked into the supplied painted map.

The damaged patch is in the underlying source image, not the Flutter blur
filter. Preserve all intact oil-paint details; inpaint only this corrupted
region and restore nearby relief detail. Deterministic, offline, no network.
Runs before the night artwork is derived so both scenes remain aligned.
"""
from pathlib import Path
import cv2
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets/oil/oil_map_clean.webp'

def main():
    original=np.array(Image.open(SOURCE).convert('RGB'))
    height,width=original.shape[:2]
    # Coordinates were measured on the 1672x941 approved *background-only*
    # canvas. Do not mask the coastline outside the corrupted paint region.
    contour=np.array([
        (570,264),(614,250),(660,245),(735,242),(835,245),
        (831,304),(796,338),(760,382),(695,380),
        (624,358),(574,334),
    ],dtype=np.float32)
    contour[:,0]*=width/1672.
    contour[:,1]*=height/941.
    mask=np.zeros((height,width),dtype=np.uint8)
    cv2.fillPoly(mask,[contour.astype(np.int32)],255)
    repaired=cv2.cvtColor(
        cv2.inpaint(cv2.cvtColor(original,cv2.COLOR_RGB2BGR),
                    mask,7,cv2.INPAINT_TELEA),cv2.COLOR_BGR2RGB)
    # Add raised ocean-brush microtexture. Plain Telea alone would look
    # airbrushed and contradict the thick oil paint everywhere else.
    detail=np.zeros_like(original)
    x0,y0,x1,y1=[round(v*scale) for v,scale in
        zip((560,230,860,410),
            (width/1672.,height/941.,width/1672.,height/941.))]
    donor=original[round(355*height/941.):round(535*height/941.),
                   round(850*width/1672.):round(1150*width/1672.)]
    if donor.size==0:
        raise ValueError('Oil map dimensions unexpectedly small')
    detail[y0:y1,x0:x1]=cv2.resize(donor,(x1-x0,y1-y0))
    feather=cv2.GaussianBlur(mask,(0,0),10)[:,:,None]/255.
    highpass=(detail.astype(np.float32)-
              cv2.GaussianBlur(detail,(0,0),2).astype(np.float32))
    fixed=np.clip(original*(1-feather)+
                  (repaired+.55*highpass)*feather,0,255).astype(np.uint8)
    Image.fromarray(fixed).save(SOURCE,'WEBP',quality=96,method=6)
    print('Repaired baked radial blur in oil canvas:',width,height)

if __name__=='__main__':
    main()
