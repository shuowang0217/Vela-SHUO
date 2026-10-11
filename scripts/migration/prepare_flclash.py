#!/usr/bin/env python3
"""Apply a pinned, auditable Vela-SHUO visual overlay to a FlClash checkout.

No Vela subscription downloader, DNS policy, HTTP proxy or VPN service
is copied into FlClash. FlClash remains the networking owner; Vela is UI.
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
                          constraints: BoxConstraints(
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
    # Vela owns the ENTIRE visible four-tab shell, not a FlClash dashboard card.
    shell_source = vela / "scripts/migration/flclash/vela_shell.dart"
    shell_target = upstream / "lib/vela_shuo/vela_shell.dart"
    shutil.copy2(shell_source, shell_target)
    original_home = vela / "scripts/migration/flclash/vela_original_home.dart"
    shutil.copy2(original_home, upstream / "lib/vela_shuo/vela_original_home.dart")

    app = upstream / "lib/application.dart"
    app_text = app.read_text(encoding="utf-8")
    app_text = replace_once(
        app_text,
        "import 'pages/pages.dart';",
        "import 'package:fl_clash/vela_shuo/vela_shell.dart';",
        "application.dart:import",
    )
    app_text = replace_once(
        app_text,
        "child: const HomePage(),",
        "child: const VelaShell(),",
        "application.dart:home",
    )
    app_text = replace_once(
        app_text, "title: appName,", "title: 'Vela-SHUO',",
        "application.dart:title",
    )
    # Vela is also responsible for all *visible window chrome*. Retain
    # FlClash's network, VPN, tray, lifecycle and hotkey managers, but do not
    # stack the upstream Flutter title bar or PRE banner above Vela.
    app_text = replace_once(
        app_text,
        "  final platformApp = isDesktop\n"
        "      ? WindowHeaderContainer(child: child)\n"
        "      : VpnManager(child: child);",
        "  final platformApp = isDesktop\n"
        "      ? child\n"
        "      : VpnManager(child: child);",
        "application.dart:desktop_chrome",
    )
    app_text = replace_once(
        app_text,
        "  return AppEnvManager(\n"
        "    child: LocaleManager(\n"
        "      child: StatusManager(child: ThemeManager(child: platformState)),\n"
        "    ),\n"
        "  );",
        "  return LocaleManager(\n"
        "    child: StatusManager(child: ThemeManager(child: platformState)),\n"
        "  );",
        "application.dart:preview_banner",
    )
    app.write_text(app_text, encoding="utf-8")

    # The upstream default desktop window is just 680x580 logical pixels;
    # at 125% display scaling it looks like a phone layout on Windows.
    # Restore Windows native caption and Vela's useful desktop canvas size.
    window = upstream / "lib/common/window.dart"
    window_text = window.read_text(encoding="utf-8")
    window_text = replace_once(
        window_text,
        "    if (!system.isMacOS || version > 10) {\n"
        "      await desktopWindow.setTitleBarStyle(TitleBarStyle.hidden);\n"
        "    }\n"
        "    await desktopWindow.setSize(props.size);\n"
        "    await desktopWindow.setMinimumSize(const Size(380, 400));\n"
        "    await _windowPosition(props);",
        "    if (system.isWindows) {\n"
        "      await desktopWindow.setTitleBarStyle(TitleBarStyle.normal);\n"
        "    } else if (!system.isMacOS || version > 10) {\n"
        "      await desktopWindow.setTitleBarStyle(TitleBarStyle.hidden);\n"
        "    }\n"
        "    final size = props.size;\n"
        "    final restoredSize = system.isWindows\n"
        "        ? Size(size.width < 1120 ? 1120 : size.width,\n"
        "            size.height < 760 ? 760 : size.height)\n"
        "        : size;\n"
        "    await desktopWindow.setSize(restoredSize);\n"
        "    await desktopWindow.setMinimumSize(system.isWindows\n"
        "        ? const Size(980, 660) : const Size(380, 400));\n"
        "    await _windowPosition(system.isWindows\n"
        "        ? props.copyWith(width: restoredSize.width,\n"
        "            height: restoredSize.height) : props);",
        "window.dart:original_desktop_geometry",
    )
    window.write_text(window_text, encoding="utf-8")
    # Brand only platform-visible app names. Do not rename private IPC,
    # VPN service classes, Android application IDs or background engine paths.
    cosmetic_names = (
        ("lib/common/constant.dart", "const appName = 'FlClash';",
         "const appName = 'Vela-SHUO';"),
        ("android/common/src/main/res/values/strings.xml",
         '<string name="app_name">FlClash</string>',
         '<string name="app_name">Vela-SHUO</string>'),
        ("windows/runner/main.cpp", 'window.Create(L"FlClash",',
         'window.Create(L"Vela-SHUO",'),
        ("windows/runner/Runner.rc", 'VALUE "FileDescription", "FlClash"',
         'VALUE "FileDescription", "Vela-SHUO"'),
    )
    for rel, old, new in cosmetic_names:
        path = upstream / rel
        path.write_text(
            replace_once(path.read_text(encoding="utf-8"), old, new, rel),
            encoding="utf-8",
        )

    pubspec = upstream / "pubspec.yaml"
    yaml_text = pubspec.read_text(encoding="utf-8")
    yaml_text = replace_once(
        yaml_text, "    - assets/data/\n",
        "    - assets/data/\n    - assets/earth/\n    - assets/maps/\n",
        "pubspec.yaml",
    )
    pubspec.write_text(yaml_text, encoding="utf-8")

    # FlClash navigation and pages remain internal source only and are never
    # mounted by VelaShell. Do not attach a Vela widget to FlClash dashboard.
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
