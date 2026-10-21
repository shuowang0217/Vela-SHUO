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
source = source.replace(old, 'applicationId = "com.shuowang.vela"', 1)
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
# Reuse the pinned FlClash-Custom permanent signing certificate:
# its ciphertext is public, only the password lives in Vela's Actions secret.
# Never generate another key: the stable certificate enables future upgrades.
source += '''
android {
    signingConfigs {
        create("velaRelease") {
            storeFile = file("vela-release.jks")
            val permanentPassword = System.getenv("SHUO_SIGNING_PASSWORD")
                ?: error("Missing SHUO permanent Android signing password")
            storePassword = permanentPassword
            keyAlias = "shuo-release"
            keyPassword = permanentPassword
        }
    }
    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("velaRelease")
        }
    }
}
'''
gradle.write_text(source, encoding="utf-8")

xml = manifest.read_text(encoding="utf-8")
xml, count = re.subn(r'android:label="[^"]+"',
    'android:label="Vela"', xml, count=1)
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
widget = '''
        <receiver android:name="com.shuowang.vela_shuo.VelaVoyageWidget"
            android:exported="true" android:label="Vela 航海油画">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE"/>
            </intent-filter>
            <meta-data android:name="android.appwidget.provider"
                android:resource="@xml/vela_voyage_widget_info"/>
        </receiver>
'''
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
xml = xml.replace('</application>', service + widget + '    </application>', 1)
manifest.write_text(xml, encoding="utf-8")

kotlin_dir.mkdir(parents=True, exist_ok=True)
for item in ("MainActivity.kt", "VelaVpnService.kt",
             "VelaVpnState.kt", "VelaVoyageWidget.kt"):
    shutil.copy2(Path("native/android") / item, kotlin_dir / item)

icon_source = Path("native/android/vela_notification_sail.xml")
drawable_dir = Path("android/app/src/main/res/drawable")
drawable_dir.mkdir(parents=True, exist_ok=True)
shutil.copy2(icon_source, drawable_dir / icon_source.name)

# Generate a text-free, unframed brushstroke surface; never reuse the
# dashboard's connection plaque (it contains decorative power/brand graphics).
import runpy
runpy.run_path("scripts/prepare_oil_notification.py", run_name="__main__")
painted_dir = Path("android/app/src/main/res/drawable-nodpi")
painted_dir.mkdir(parents=True, exist_ok=True)
for name in ("day", "night"):
    source_image = Path(f"assets/oil/ui/notification_oil_{name}.png")
    if not source_image.is_file() or source_image.stat().st_size == 0:
        raise SystemExit(f"Missing clean Vela notification art: {source_image}")
    shutil.copy2(source_image, painted_dir / f"vela_notification_oil_{name}.png")

layout_dir = Path("android/app/src/main/res/layout")
layout_dir.mkdir(parents=True, exist_ok=True)
for item in ("vela_notification_compact.xml", "vela_notification_expanded.xml"):
    shutil.copy2(Path("native/android") / item, layout_dir / item)
# Install native Android AppWidget resources after the Flutter project is created.
shutil.copy2(Path("native/android/vela_voyage_widget.xml"),
             layout_dir / "vela_voyage_widget.xml")
xml_dir = Path("android/app/src/main/res/xml")
xml_dir.mkdir(parents=True, exist_ok=True)
shutil.copy2(Path("native/android/vela_voyage_widget_info.xml"),
             xml_dir / "vela_voyage_widget_info.xml")
for item in ("vela_widget_progress.xml", "vela_widget_button.xml",
             "vela_widget_frame.xml"):
    shutil.copy2(Path("native/android") / item, drawable_dir / item)
import runpy
runpy.run_path("scripts/prepare_oil_widget.py", run_name="__main__")
print("Vela stable Android: fixed package ID and release signing enforced")
