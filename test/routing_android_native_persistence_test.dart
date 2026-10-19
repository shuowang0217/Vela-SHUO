import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/network/flclash_windows_backend.dart';
import 'package:vela_shuo/src/network/vela_routing_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('vela_shuo/ui_preferences');

  test('Android route switching uses native durable mode storage', () async {
    String? saved;
    final binary = TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger;
    binary.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'readRoutingMode') return saved;
      if (call.method == 'writeRoutingMode') {
        saved = (call.arguments as Map<dynamic, dynamic>)['value'] as String?;
        return true;
      }
      throw PlatformException(code: 'UNSUPPORTED');
    });
    addTearDown(() => binary.setMockMethodCallHandler(channel, null));
    final backend = FlClashWindowsBackend()..imported = true;
    final first = VelaRoutingModeController(backend, useNativeStorage: true)
      ..testingApply = ((mode) async => true);
    await first.restore();
    expect(await first.setMode(VelaRoutingMode.global, 'airport'), isTrue);
    expect(first.error, isNull);
    expect(saved, 'global');
    first.dispose();

    final restored = VelaRoutingModeController(backend, useNativeStorage: true);
    await restored.restore();
    expect(restored.current, VelaRoutingMode.global);
    restored.dispose();
  });

  test('native save failure keeps applied mode but exposes clear error',
      () async {
    final binary = TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger;
    binary.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'readRoutingMode') return 'rule';
      if (call.method == 'writeRoutingMode') return false;
      return null;
    });
    addTearDown(() => binary.setMockMethodCallHandler(channel, null));
    final backend = FlClashWindowsBackend()..imported = true;
    final controller = VelaRoutingModeController(backend, useNativeStorage: true)
      ..testingApply = ((mode) async => true);
    await controller.restore();
    expect(await controller.setMode(VelaRoutingMode.direct, 'airport'), isTrue);
    expect(controller.current, VelaRoutingMode.direct);
    expect(controller.error, contains('本机保存设置失败'));
    controller.dispose();
  });

  test('mode selector does not darken the entire oil map', () {
    final source = File('lib/src/app.dart').readAsStringSync();
    expect(RegExp(r'barrierColor: Colors.transparent').allMatches(source).length,
        greaterThanOrEqualTo(2));
    final native = File('native/android/MainActivity.kt').readAsStringSync();
    expect(native, contains('prefs.getString("routing_mode", null)'));
    expect(native, contains('.putString("routing_mode", value).commit()'));
  });
}
