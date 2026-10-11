#!/usr/bin/env python3
"""Dependency-free overlay contract tests, run before costly Go/Rust builds."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

SOURCE = Path(__file__).with_name("prepare_flclash.py")
spec = importlib.util.spec_from_file_location("prepare_flclash", SOURCE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class OverlayTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.vela = Path(self.temp.name) / "vela"
        self.upstream = Path(self.temp.name) / "flclash"
        self.vela.mkdir()
        self.upstream.mkdir()
        for path in module.COPY_FILES:
            target = self.vela / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("fake test asset", encoding="utf-8")
        script_overlay = self.vela / module.OVERLAY[0]
        script_overlay.parent.mkdir(parents=True, exist_ok=True)
        script_overlay.write_text("class VelaFlightHeader {}\n", encoding="utf-8")
        app = self.upstream / "lib/application.dart"
        app.parent.mkdir(parents=True, exist_ok=True)
        app.write_text(
            "import 'pages/pages.dart';\n"
            "return MaterialApp(title: appName, child: const HomePage(),);\n",
            encoding="utf-8",
        )
        shell = self.vela / "scripts/migration/flclash/vela_shell.dart"
        shell.parent.mkdir(parents=True, exist_ok=True)
        shell.write_text("class VelaShell {}\n", encoding="utf-8")
        (self.upstream / "LICENSE").write_text("GNU GPLv3")
        (self.upstream / "pubspec.yaml").write_text(
            "flutter:\n  assets:\n    - assets/data/\n",
            encoding="utf-8",
        )

    def test_preserves_flclash_backend_and_adds_animated_visual_only(self):
        module.apply_overlay(self.vela, self.upstream, verify_sha=False)
        app = (self.upstream / "lib/application.dart").read_text()
        self.assertIn("child: const VelaShell()", app)
        self.assertNotIn("child: const HomePage()", app)
        self.assertIn("title: 'Vela-SHUO'", app)
        self.assertTrue((self.upstream / "lib/vela_shuo/vela_shell.dart").exists())
        pubspec = (self.upstream / "pubspec.yaml").read_text()
        self.assertIn("assets/earth/", pubspec)
        self.assertIn("assets/maps/", pubspec)
        self.assertTrue((self.upstream / module.OVERLAY[1]).exists())
        self.assertTrue((self.upstream / "lib/vela_shuo/home/globe.dart").exists())
        self.assertTrue((self.upstream / "LICENSE").exists())

    def test_refuses_unknown_upstream_app_shape(self):
        (self.upstream / "lib/application.dart").write_text(
            "changed upstream internals", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Unsupported FlClash layout"):
            module.apply_overlay(self.vela, self.upstream, verify_sha=False)


if __name__ == "__main__":
    unittest.main()
