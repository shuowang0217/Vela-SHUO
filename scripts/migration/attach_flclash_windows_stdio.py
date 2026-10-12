#!/usr/bin/env python3
"""Connect original FlClash Go RPC dispatcher to Vela's secure loopback IPC.

The pinned FlClash method handlers, Mihomo proxy algorithms and RPC framing
are unchanged. Only the process-host transport is adapted.
"""
from pathlib import Path
import shutil

root = Path("../flclash/core")
main = root / "main.go"
src = main.read_text(encoding="utf-8")
old = """\tgo exitOnTermination()
\tstartServer(args[1])"""
new = """\tgo exitOnTermination()
\tif strings.HasPrefix(args[1], "--vela-loopback=") {
\t\tif err := velaServeLoopback(args[1]); err != nil {
\t\t\tfmt.Fprintln(os.Stderr, "Vela loopback IPC failed")
\t\t}
\t\treturn
\t}
\tstartServer(args[1])"""
if src.count(old) != 1:
    raise SystemExit("Pinned FlClash main.go changed; refusing to patch")
if src.count('"os"') != 1:
    raise SystemExit("FlClash main.go import block changed")
src = src.replace('"os"', '"os"\n\t"strings"', 1)
main.write_text(src.replace(old, new, 1), encoding="utf-8")
shutil.copy2(
    "scripts/migration/flclash_native/vela_loopback_windows.go",
    root / "vela_loopback_windows.go",
)
shutil.copy2(
    "scripts/migration/flclash_native/vela_profile_windows.go",
    root / "vela_profile_windows.go",
)
print("FlClash Go RPC loopback transport installed")
