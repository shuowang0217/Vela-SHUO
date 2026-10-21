import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native Android icon shortcuts replace the old widget preview', () {
    final generator = File('scripts/configure_android_vpn.py').readAsStringSync();
    final shortcutXml = File('native/android/vela_app_shortcuts.xml')
        .readAsStringSync();
    final activity = File('native/android/MainActivity.kt').readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();

    expect(generator, contains('android.app.shortcuts'));
    expect(generator, contains('vela_app_shortcuts.xml'));
    expect(generator, contains('vela_shortcut_start.xml'));
    expect(generator, contains('vela_shortcut_stop.xml'));
    expect(generator, isNot(contains('VelaVoyageWidget')));
    expect(generator, isNot(contains('appwidget-provider')));
    expect(shortcutXml, contains('SHORTCUT_START'));
    expect(shortcutXml, contains('SHORTCUT_STOP'));
    expect(shortcutXml, contains('com.shuowang.vela_shuo.MainActivity'));
    expect(activity, contains('consumeAppShortcut'));
    expect(activity, contains('onNewIntent'));
    expect(app, contains('_consumeAppShortcut()'));
    expect(app, contains('applyPendingProfileIfIdle'));
    expect(app, contains('modes.synchronize'));
    expect(app, contains('vpn.start(sub)'));
    expect(app, contains('vpn.stop()'));
    expect(File('pubspec.yaml').readAsStringSync(),
        contains('version: 1.9.0+54'));
  });
}
