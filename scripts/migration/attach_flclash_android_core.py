#!/usr/bin/env python3
"""Adapt the *native* FlClash Android Go/JNI backend to the original Vela app.

Inputs:
  flutter create and scripts/configure_android_vpn.py have prepared android/
  FlClash (pinned source) has built libclash.so and generated libclash.h
This script does not read or modify a single Vela Flutter UI file.
"""
from __future__ import annotations

import shutil
from pathlib import Path

VELA_APP = Path("android/app")
FLCLASH = Path("../flclash")
ABI = "arm64-v8a"


def replace_once(value: str, old: str, new: str, label: str) -> str:
    if value.count(old) != 1:
        raise RuntimeError(f"FlClash Android backend API changed: {label}")
    return value.replace(old, new, 1)


def copy(source: Path, dest: Path) -> None:
    if not source.is_file():
        raise FileNotFoundError(source)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, dest)


def attach() -> None:
    if not (VELA_APP / "build.gradle.kts").is_file():
        raise RuntimeError("Generate Vela Flutter Android runner first")
    android_core = FLCLASH / "android/core"
    go_so = android_core / f"src/main/jniLibs/{ABI}/libclash.so"
    go_header = android_core / f"src/main/cpp/includes/{ABI}/libclash.h"
    go_bridge = FLCLASH / "core/bride.h"
    cpp = android_core / "src/main/cpp"
    target_cpp = VELA_APP / "src/main/cpp"
    target_kotlin = (
        VELA_APP / "src/main/kotlin/com/follow/clash/core"
    )
    for name in ("CMakeLists.txt", "core.cpp", "jni_helper.cpp", "jni_helper.h"):
        copy(cpp / name, target_cpp / name)
    for name in ("Core.kt", "TunInterface.kt", "InvokeInterface.kt"):
        copy(
            android_core / "src/main/java/com/follow/clash/core" / name,
            target_kotlin / name,
        )
    copy(go_so, VELA_APP / f"src/main/jniLibs/{ABI}/libclash.so")
    copy(go_header, target_cpp / f"includes/{ABI}/libclash.h")
    copy(go_bridge, target_cpp / f"includes/{ABI}/bride.h")

    gradle = VELA_APP / "build.gradle.kts"
    source = gradle.read_text(encoding="utf-8")
    source = replace_once(
        source,
        'implementation(files("libs/libmihomo.aar"))',
        "// FlClash Go libclash.so and its JNI libcore.so are built from pinned source",
        "remove legacy oviron libmihomo AAR",
    )
    source += """
// Vela is the Flutter host. FlClash contributes only native Go/JNI networking.
android {
    ndkVersion = "27.3.13750724"
    defaultConfig {
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
}
"""
    gradle.write_text(source, encoding="utf-8")

    src = Path("native/android/MainActivity.kt").read_text(encoding="utf-8")
    src = replace_once(
        src, "import io.github.oviron.libmihomo.Clash",
        "import com.follow.clash.core.Core", "MainActivity JNI import")
    src = replace_once(
        src,
        'VelaVpnState.state != "connected" || !Clash.isLoaded()',
        'VelaVpnState.state != "connected"',
        "MainActivity JNI traffic status",
    )
    src = replace_once(
        src, "Clash.getTotalTraffic()", "Core.getTotalTraffic(false)",
        "MainActivity JNI counters",
    )
    (VELA_APP / "src/main/kotlin/com/shuowang/vela_shuo/MainActivity.kt"
     ).write_text(src, encoding="utf-8")

    src = Path("native/android/VelaVpnService.kt").read_text(encoding="utf-8")
    src = replace_once(
        src,
        "import io.github.oviron.libmihomo.Clash\n"
        "import io.github.oviron.libmihomo.TunInterface",
        "import com.follow.clash.core.Core",
        "VpnService JNI import",
    )
    start = src.index("    private val tunCallback = object : TunInterface {")
    end = src.index("\n    override fun onCreate()", start)
    src = src[:start] + src[end:]
    src = replace_once(
        src, '                Clash.load(applicationInfo.nativeLibraryDir)\n'
        '                require(Clash.bridgeABI() == Clash.EXPECTED_BRIDGE_ABI)\n',
        "", "FlClash Core loads its own JNI binding",
    )
    src = replace_once(
        src, '                Clash.quickSetup(initJson, "{}") { message ->',
        '                Core.quickSetup(initJson, "{}") { message ->',
        "Go quickSetup",
    )
    old = '''                        Clash.startTUN(goFd, tunCallback, "vela-tun",
                            "mixed", "172.19.0.1/30,fd80:19::1/126",
                            "198.18.0.2", 1400)'''
    new = '''                        val started = Core.startTun(
                            fd = goFd,
                            protect = { socketFd -> this@VelaVpnService.protect(socketFd) },
                            resolveUid = { protocol, source, target ->
                                if (Build.VERSION.SDK_INT >= 29)
                                    getConnectionOwnerUid(protocol, source, target)
                                else -1
                            },
                            resolvePackage = { uid ->
                                packageManager.getPackagesForUid(uid)?.firstOrNull() ?: ""
                            },
                            stack = "mixed",
                            address = "172.19.0.1/30,fd80:19::1/126",
                            dns = "198.18.0.2",
                        )
                        check(started) { "FlClash Go core rejected TUN descriptor" }'''
    src = replace_once(src, old, new, "FlClash Go TUN hook")
    src = replace_once(
        src, "if (Clash.isLoaded()) Clash.stopTun()",
        "if (nativeStarted) Core.stopTun()",
        "FlClash stop TUN",
    )
    src = src.replace(
        "// AAR contains libclash.so (Mihomo) and libmihomo-jni.so.",
        "// FlClash pinned Go source supplies libclash.so; JNI wrapper is libcore.so.",
    )
    (VELA_APP / "src/main/kotlin/com/shuowang/vela_shuo/VelaVpnService.kt"
     ).write_text(src, encoding="utf-8")

    # The entire Flutter UI remains in this app's lib/src/, unchanged.
    for expected in (
        VELA_APP / f"src/main/jniLibs/{ABI}/libclash.so",
        target_cpp / f"includes/{ABI}/libclash.h",
        target_kotlin / "Core.kt",
        VELA_APP / "src/main/kotlin/com/shuowang/vela_shuo/VelaVpnService.kt",
    ):
        assert expected.is_file()
    print("Vela UI retained. FlClash Go/JNI native network backend installed.")


if __name__ == "__main__":
    attach()
