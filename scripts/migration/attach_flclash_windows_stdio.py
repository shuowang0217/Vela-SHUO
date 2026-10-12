#!/usr/bin/env python3
"""Patch pinned FlClash *Go* backend to accept Vela stdio IPC.

This never edits Vela Flutter UI; the original FlClash method handlers,
Mihomo parser, RPC responses and frame reader are all left intact.
"""
from pathlib import Path
import shutil

root = Path("../flclash/core")
main = root / "main.go"
src = main.read_text(encoding="utf-8")
old = """\tgo exitOnTermination()
\tstartServer(args[1])"""
new = """\tgo exitOnTermination()
\tif args[1] == "--vela-stdio" {
\t\tvelaServeStdio()
\t\treturn
\t}
\tstartServer(args[1])"""
if src.count(old) != 1:
    raise SystemExit("Pinned FlClash main.go changed; refusing to patch")
main.write_text(src.replace(old, new, 1), encoding="utf-8")
shutil.copy2(
    "scripts/migration/flclash_native/vela_stdio_windows.go",
    root / "vela_stdio_windows.go",
)
shutil.copy2(
    "scripts/migration/flclash_native/vela_profile_windows.go",
    root / "vela_profile_windows.go",
)
print("FlClash Go RPC stdio transport installed without changing its handlers")
