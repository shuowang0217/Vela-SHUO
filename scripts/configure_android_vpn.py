#!/usr/bin/env python3
"""Overlay Android VpnService and verified Mihomo AAR wiring onto Flutter runner."""
from pathlib import Path
import re
import shutil

gradle = Path("android/app/build.gradle.kts")
manifest = Path("android/app/src/main/AndroidManifest.xml")
kotlin_dir = Path("android/app/src/main/kotlin/com/shuowang/vela_shuo")
if not gradle.is_file() or not manifest.is_file():
    raise SystemExit("flutter create --platforms android was not run")
source = gradle.read_text(encoding="utf-8")
old = 'applicationId = "com.shuowang.vela_shuo"'
if source.count(old) != 1:
    raise SystemExit("Unexpected generated Flutter application id")
source = source.replace(old, 'applicationId = "com.shuowang.vela.vpn.beta"', 1)
if "dependencies {" in source:
    source += '\n// AAR is downloaded separately and SHA-256-verified by CI.\n'
source += '\ndependencies {\n    implementation(files("libs/libmihomo.aar"))\n}\n'
source += '''
android {
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}
'''
gradle.write_text(source, encoding="utf-8")

xml = manifest.read_text(encoding="utf-8")
xml, count = re.subn(r'android:label="[^"]+"',
    'android:label="Vela-SHUO Mihomo VPN Beta"', xml, count=1)
if count != 1:
    raise SystemExit("Unexpected Flutter manifest label")
if 'android:allowBackup=' not in xml:
    xml = xml.replace('<application', '<application android:allowBackup="false"', 1)
if 'android:extractNativeLibs=' not in xml:
    xml = xml.replace('<application', '<application android:extractNativeLibs="true"', 1)
if 'android:usesCleartextTraffic=' not in xml:
    xml = xml.replace('<application', '<application android:usesCleartextTraffic="false"', 1)
marker = '<application'
root_end = xml.index('>', xml.index('<manifest')) + 1
permissions = '''
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SYSTEM_EXEMPTED"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
'''
xml = xml[:root_end] + permissions + xml[root_end:]
service = '''
        <service
            android:name="com.shuowang.vela_shuo.VelaVpnService"
            android:permission="android.permission.BIND_VPN_SERVICE"
            android:foregroundServiceType="systemExempted"
            android:exported="false">
            <intent-filter>
                <action android:name="android.net.VpnService"/>
            </intent-filter>
            <meta-data android:name="android.net.VpnService.SUPPORTS_ALWAYS_ON"
                android:value="false"/>
        </service>
'''
if xml.count('</application>') != 1:
    raise SystemExit("Generated Flutter manifest lacks a single application")
xml = xml.replace('</application>', service + '    </application>', 1)
manifest.write_text(xml, encoding="utf-8")

kotlin_dir.mkdir(parents=True, exist_ok=True)
for item in ("MainActivity.kt", "VelaVpnService.kt", "VelaVpnState.kt"):
    shutil.copy2(Path("native/android") / item, kotlin_dir / item)
print("Android real VPN Beta: VpnService, JNI native bridge, ARM64 and foreground service configured")
