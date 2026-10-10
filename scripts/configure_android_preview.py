#!/usr/bin/env python3
"""Configure an independently installable, clearly preview-only Android APK.

Flutter's generated Android release uses debug signing by default.
This must not be distributed as a signed production release.
"""
from pathlib import Path
import re

gradle = Path("android/app/build.gradle.kts")
manifest = Path("android/app/src/main/AndroidManifest.xml")
if not gradle.is_file() or not manifest.is_file():
    raise SystemExit("Flutter Android platform files were not generated")
source = gradle.read_text(encoding="utf-8")
old = 'applicationId = "com.shuowang.vela_shuo"'
if source.count(old) != 1:
    raise SystemExit("Unexpected Android applicationId")
source = source.replace(old, 'applicationId = "com.shuowang.vela.preview"', 1)
gradle.write_text(source, encoding="utf-8")

xml = manifest.read_text(encoding="utf-8")
xml, count = re.subn(r'android:label="[^"]+"',
                     'android:label="Vela-SHUO Preview"', xml, count=1)
if count != 1 or "<manifest" not in xml:
    raise SystemExit("Android manifest is not recognized")
if "android.permission.INTERNET" not in xml:
    pos = xml.index(">", xml.index("<manifest")) + 1
    xml = xml[:pos] + '\n    <uses-permission android:name="android.permission.INTERNET"/>' + xml[pos:]
if 'android:allowBackup=' not in xml:
    xml = xml.replace('<application', '<application android:allowBackup="false"', 1)
if "BIND_VPN_SERVICE" in xml or "VpnService" in xml:
    raise SystemExit("Android preview must not declare a VPN service")
manifest.write_text(xml, encoding="utf-8")
print("Android preview: com.shuowang.vela.preview, INTERNET only, no VPN")
