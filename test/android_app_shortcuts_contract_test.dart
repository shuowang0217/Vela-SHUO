import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android publishes exactly one changing compass launcher shortcut', () {
    final generator = File('scripts/configure_android_vpn.py').readAsStringSync();
    final shortcut = File('native/android/VelaCompassShortcut.kt').readAsStringSync();
    final activity = File('native/android/VelaShortcutToggleActivity.kt').readAsStringSync();
    final main = File('native/android/MainActivity.kt').readAsStringSync();
    final vpn = File('native/android/VelaVpnService.kt').readAsStringSync();
    final state = File('native/android/VelaVpnState.kt').readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();

    expect(shortcut, contains('setDynamicShortcuts(listOf(shortcut))'));
    expect(shortcut, contains('vela_compass_toggle'));
    expect(shortcut, contains('"启航"'));
    expect(shortcut, contains('"返航"'));
    expect(shortcut, contains('R.drawable.vela_shortcut_compass'));
    expect(shortcut, contains('VelaShortcutToggleActivity::class.java'));
    expect(activity, contains('VpnService.prepare(this)'));
    expect(activity, contains('VelaVpnService.ACTION_STOP'));
    expect(activity, contains('VelaVpnService.ACTION_START'));
    expect(activity, contains('FlClash-Core/config.yaml'));
    expect(activity, isNot(contains('MainActivity::class.java')));
    expect(generator, contains('Theme.Translucent.NoTitleBar'));
    expect(generator, contains('VelaShortcutToggleActivity.kt'));
    expect(generator, contains('oil_nav_compass.png'));
    expect(generator, isNot(contains('android.app.shortcuts')));
    expect(generator, isNot(contains('appwidget-provider')));
    expect(main, contains('cacheShortcutSelection'));
    expect(app, contains('_cacheAndroidCompassSelection'));
    expect(app, isNot(contains('consumeAppShortcut')));
    expect(vpn, contains('VelaCompassShortcut.refresh(this)'));
    expect(state, contains('VelaCompassShortcut.refresh(it, next == "connected")'));
    expect(File('pubspec.yaml').readAsStringSync(),
        contains('version: 1.9.0+55'));
  });
}
