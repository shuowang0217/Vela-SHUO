"""Generate an offline water-only routing mask from the FINAL painted map.

The source artwork is an illustration, not a georeferenced map. Sailing tracks
must use water in the actual rendered bitmap, rather than geographic sea cells
projected across its distorted land contours.
"""
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/oil/oil_map_clean.webp'
OUT = ROOT / 'assets/oil/oil_sea_grid.txt'
COLUMNS, ROWS = 120, 68

def main():
    image = cv2.imread(str(SOURCE), cv2.IMREAD_COLOR)
    if image is None:
        raise SystemExit('Missing painted oil map')
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    hue, saturation = hsv[:,:,0], hsv[:,:,1]
    blue, green, red = cv2.split(image)
    # Blue/azure brush strokes denote ocean; green, brown and beige denote
    # continents. Close narrow gaps caused by clouds and white wave highlights.
    water = ((hue >= 78) & (hue <= 139) & (saturation >= 47) &
             (blue.astype(np.float32) > red.astype(np.float32) * 1.06) &
             (blue > 75)).astype(np.uint8)
    water = cv2.morphologyEx(
        water, cv2.MORPH_CLOSE, np.ones((21, 21), np.uint8))
    water = cv2.morphologyEx(
        water, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    h, w = water.shape
    rows = []
    for row in range(ROWS):
        y0 = round(row * h / ROWS)
        y1 = round((row + 1) * h / ROWS)
        chars = []
        for col in range(COLUMNS):
            x0 = round(col * w / COLUMNS)
            x1 = round((col + 1) * w / COLUMNS)
            # Strict occupancy threshold: a cell must be mostly painted sea.
            ratio = np.mean(water[y0:y1, x0:x1])
            chars.append('1' if ratio >= 0.62 else '0')
        rows.append(''.join(chars))
    OUT.write_text('\n'.join(rows) + '\n', encoding='ascii')
    print('Painted sea grid:', COLUMNS, ROWS, 'water cells',
          sum(r.count('1') for r in rows))

if __name__ == '__main__':
    main()
