"""Make both approved oil panoramas horizontally loopable before bundling.

The city/ship projection uses the original 1672x941 coordinate system.
Only a narrow strip along the east/west raster edge is feather-blended;
there is no crop, resize, recoloring, or geometry change.
"""
from pathlib import Path
import math
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets" / "oil"

def make_seamless(path: Path, edge_width: int = 124) -> None:
    with Image.open(path) as source:
        im = np.asarray(source.convert("RGB"), dtype=np.float32).copy()
    height, width, _ = im.shape
    band = min(edge_width, width // 10)
    # Both sides converge to the same color at the actual image boundary.
    # Preserve the interior and every surveyed city landmark unchanged.
    for distance in range(band):
        fade = (1 + math.cos(math.pi * distance / band)) * 0.5
        left = im[:, distance, :].copy()
        right = im[:, width - 1 - distance, :].copy()
        shared = (left + right) * 0.5
        im[:, distance, :] = left * (1 - fade) + shared * fade
        im[:, width - 1 - distance, :] = right * (1 - fade) + shared * fade
    image = Image.fromarray(np.clip(im + 0.5, 0, 255).astype("uint8"), "RGB")
    image.save(path, "WEBP", quality=94, method=6)
    # Lossy WebP rounding has a 1-2 level drift at edges; this is acceptable
    # for soft paint and eliminates hard cut seams on repeating image tiles.

if __name__ == "__main__":
    for name in ("oil_map_clean.webp", "oil_map_night.webp"):
        file = ASSETS / name
        if not file.is_file():
            raise FileNotFoundError(file)
        make_seamless(file)
        print("Seamless oil panorama:", file)
