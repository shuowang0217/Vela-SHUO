#!/usr/bin/env python3
"""Add the exact pinned FlClash geo assets only to Android Flutter packaging.

The original Vela UI asset manifest is unchanged in source control. CI copies
FlClash's original .dat/.metadb/.mmdb files from its pinned source checkout.
"""
from pathlib import Path

manifest = Path("pubspec.yaml")
text = manifest.read_text(encoding="utf-8")
anchor = "    - assets/earth/earth_night_lights.png"
if text.count(anchor) != 1:
    raise SystemExit("Vela asset manifest changed")
files = ("GEOIP.metadb", "GEOIP.dat", "GEOSITE.dat", "ASN.mmdb")
for name in files:
    item = Path("assets/flclash") / name
    if not item.is_file() or item.stat().st_size <= 0:
        raise SystemExit(f"Missing pinned FlClash Geo resource: {name}")
additional = "".join(f"\n    - assets/flclash/{name}" for name in files)
manifest.write_text(text.replace(anchor, anchor + additional), encoding="utf-8")
print("Pinned FlClash geo resource bundle added to Android package")
