#!/usr/bin/env python3
"""Apply a pinned, auditable Vela-SHUO visual overlay to a FlClash checkout.

No Vela subscription downloader, DNS policy, HTTP proxy or VPN service
is copied into FlClash. FlClash remains the network and settings owner.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path

FLCLASH_SHA = "4b59eca853778d4e7be3de26589252889c899bc5"
FLCLASH_REPO = "https://github.com/chen08209/FlClash"
COPY_FILES = (
    "lib/src/home/globe.dart",
    "lib/src/home/flight_route.dart",
    "lib/src/home/demo_connection.dart",
    "lib/src/theme/vela_palettes.dart",
    "assets/earth/earth_day.jpg",
    "assets/earth/earth_night_lights.png",
    "assets/earth/ATTRIBUTION.md",
    "assets/maps/world_110m.json",
)
OVERLAY = (
    "scripts/migration/flclash/vela_flight_header.dart",
    "lib/vela_shuo/vela_flight_header.dart",
)
IMPORT = "import 'package:fl_clash/vela_shuo/vela_flight_header.dart';"
SLIVER = """                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: dashboardMaxGridWidth,
                          ),
                          child: const VelaFlightHeader(),
                        ),
                      ),
                    ),
                  ),
"""


def replace_once(text: str, old: str, new: str, where: str) -> str:
    if text.count(old) != 1:
        raise ValueError(f"Unsupported FlClash layout in {where}: {old[:70]!r}")
    return text.replace(old, new, 1)


def verify_commit(upstream: Path) -> None:
    actual = subprocess.check_output(
        ["git", "-C", str(upstream), "rev-parse", "HEAD"], text=True
    ).strip()
    if actual != FLCLASH_SHA:
        raise RuntimeError(f"FlClash SHA mismatch: {actual}; expected {FLCLASH_SHA}")


def apply_overlay(vela: Path, upstream: Path, *, verify_sha: bool = True) -> None:
    if verify_sha:
        verify_commit(upstream)
    if not (upstream / "LICENSE").is_file():
        raise RuntimeError("FlClash GPL-3.0 license missing")
    for rel in COPY_FILES:
        src = vela / rel
        if not src.is_file():
            raise FileNotFoundError(src)
        target = upstream / rel.replace("lib/src/", "lib/vela_shuo/")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, target)
    src, dst = OVERLAY
    target = upstream / dst
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(vela / src, target)

    pubspec = upstream / "pubspec.yaml"
    yaml_text = pubspec.read_text(encoding="utf-8")
    yaml_text = replace_once(
        yaml_text, "    - assets/data/\n",
        "    - assets/data/\n    - assets/earth/\n    - assets/maps/\n",
        "pubspec.yaml",
    )
    pubspec.write_text(yaml_text, encoding="utf-8")

    dashboard = upstream / "lib/views/dashboard/dashboard.dart"
    dart = dashboard.read_text(encoding="utf-8")
    dart = replace_once(
        dart, "import 'package:fl_clash/common/common.dart';",
        "import 'package:fl_clash/common/common.dart';\n" + IMPORT,
        "dashboard.dart:import",
    )
    dart = replace_once(
        dart, "                slivers: [\n",
        "                slivers: [\n" + SLIVER,
        "dashboard.dart:slivers",
    )
    dart = replace_once(
        dart, "title: context.appLocalizations.dashboard,",
        "title: 'Vela-SHUO',",
        "dashboard.dart:title",
    )
    dashboard.write_text(dart, encoding="utf-8")
    # A full upstream source tree plus our Git-tracked overlay is the
    # redistributable corresponding source for this GPL-derived build.
    notice = upstream / "VELA-SHUO-UPSTREAM.txt"
    notice.write_text(
        "Vela-SHUO migration preview, licensed under GPL-3.0-or-later.\n"
        f"Based on {FLCLASH_REPO} at commit {FLCLASH_SHA}.\n"
        "FlClash original authors and copyright notices retained.\n"
        "Vela-SHUO UI assets retain their individual attribution.\n"
        "Modification patch: shuowang0217/Vela-SHUO "
        "(branch migration/flclash-base), scripts/migration/.\n"
        "No subscription tokens should appear in build logs.\n",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vela-root", type=Path, required=True)
    parser.add_argument("--upstream-root", type=Path, required=True)
    args = parser.parse_args()
    apply_overlay(args.vela_root.resolve(), args.upstream_root.resolve())


if __name__ == "__main__":
    main()
