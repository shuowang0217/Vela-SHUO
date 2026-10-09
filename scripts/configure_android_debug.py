#!/usr/bin/env python3
"""Give disposable Android test builds the Vela-SHUO DEV identity.

Generated Kotlin namespace: com.shuowang.vela_shuo.
Product applicationId: com.shuowang.vela.dev.
A production release key must never be used in this script.
"""
from pathlib import Path
import re

build_file = Path("android/app/build.gradle.kts")
if not build_file.is_file():
    raise SystemExit("Flutter Kotlin Gradle DSL template missing")
source = build_file.read_text(encoding="utf-8")
application = re.search(r'^\s*applicationId\s*=\s*"([^"]+)"', source, re.MULTILINE)
if application is None or application.group(1) != "com.shuowang.vela_shuo":
    raise SystemExit("Unexpected generated applicationId")
source = source.replace('applicationId = "com.shuowang.vela_shuo"',
                        'applicationId = "com.shuowang.vela"', 1)
anchor = "    buildTypes {"
if source.count(anchor) != 1:
    raise SystemExit("Unexpected Gradle buildTypes template")
source = source.replace(
    anchor,
    anchor + '\n        getByName("debug") {\n'
    '            applicationIdSuffix = ".dev"\n'
    '            versionNameSuffix = "-dev"\n'
    '        }',
    1,
)
build_file.write_text(source, encoding="utf-8")

manifest = Path("android/app/src/main/AndroidManifest.xml")
text = manifest.read_text(encoding="utf-8")
text, count = re.subn(r'android:label="[^"]+"',
                      'android:label="Vela-SHUO DEV"', text, count=1)
if count != 1:
    raise SystemExit("Unable to set DEV app label")
manifest.write_text(text, encoding="utf-8")
print("Configured Android DEV identity: com.shuowang.vela.dev")
