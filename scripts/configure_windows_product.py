#!/usr/bin/env python3
"""Apply the user-facing Vela product name to a generated Windows runner.

Preserve the Dart package and LOCALAPPDATA data paths so existing profiles
are not moved or discarded when upgrading the Windows portable build.
"""
from pathlib import Path

cmake = Path("windows/CMakeLists.txt")
main = Path("windows/runner/main.cpp")
resource = Path("windows/runner/Runner.rc")
for path in (cmake, main, resource):
    if not path.is_file():
        raise SystemExit(f"Missing generated Windows file: {path}")

code = cmake.read_text(encoding="utf-8")
old = 'set(BINARY_NAME "vela_shuo")'
if code.count(old) != 1:
    raise SystemExit("Unexpected Windows executable target: no safe rename")
cmake.write_text(code.replace(old, 'set(BINARY_NAME "Vela")', 1),
                 encoding="utf-8")

code = main.read_text(encoding="utf-8")
old_title = 'L"vela_shuo"'
if old_title not in code:
    raise SystemExit("Unexpected Windows window title")
main.write_text(code.replace(old_title, 'L"Vela"'), encoding="utf-8")

code = resource.read_text(encoding="utf-8")
code = code.replace("vela_shuo.exe", "Vela.exe")
code = code.replace("Vela-SHUO", "Vela")
code = code.replace("vela_shuo", "Vela")
resource.write_text(code, encoding="utf-8")
print("Windows application, executable and version metadata: Vela")
