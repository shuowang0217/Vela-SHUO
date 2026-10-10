import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/diagnostics/vela_diagnostics.dart';
import 'package:vela_shuo/src/settings/settings_controller.dart';

class _FakeStore implements VelaPreferenceStore {
  _FakeStore({this.value, this.throwOnRead = false, this.throwOnWrite = false});

  String? value;
  bool throwOnRead;
  bool throwOnWrite;
  int removals = 0;
  final List<String> writes = [];
  Completer<void>? firstWrite;
  Completer<String?>? blockedRead;

  @override
  Future<String?> readTheme() async {
    if (blockedRead != null) return blockedRead!.future;
    if (throwOnRead) throw StateError('secret should never be logged');
    return value;
  }

  @override
  Future<void> writeTheme(String next) async {
    if (throwOnWrite) throw StateError('secret should never be logged');
    writes.add(next);
    if (writes.length == 1 && firstWrite != null) {
      await firstWrite!.future;
    }
    value = next;
  }

  @override
  Future<void> removeTheme() async {
    removals++;
    value = null;
  }
}

void main() {
  test('valid saved theme is restored, including system mode', () async {
    final store = _FakeStore(value: 'system');
    final controller = SettingsController(store: store);
    await controller.load();

    expect(controller.themeMode, ThemeMode.system);
    expect(store.removals, 0);
    controller.dispose();
  });

  test('invalid saved preferences recover only the theme key', () async {
    final diagnostics = VelaDiagnostics();
    final store = _FakeStore(value: 'untrusted-invalid-value');
    final controller = SettingsController(store: store, diagnostics: diagnostics);
    await controller.load();

    expect(controller.themeMode, ThemeMode.dark);
    expect(store.value, isNull);
    expect(store.removals, 1);
    expect(diagnostics.report, contains('settingsRecovered'));
    expect(diagnostics.report, isNot(contains('untrusted-invalid-value')));
    controller.dispose();
    diagnostics.dispose();
  });

  test('failed storage read never prevents offline launch', () async {
    final diagnostics = VelaDiagnostics();
    final store = _FakeStore(throwOnRead: true);
    final controller = SettingsController(store: store, diagnostics: diagnostics);
    await controller.load();

    expect(controller.themeMode, ThemeMode.dark);
    expect(diagnostics.report, contains('settingsReadFailed'));
    expect(diagnostics.report, isNot(contains('secret')));
    controller.dispose();
    diagnostics.dispose();
  });

  test('failed write changes UI but never exposes an exception', () async {
    final diagnostics = VelaDiagnostics();
    final store = _FakeStore(throwOnWrite: true);
    final controller = SettingsController(store: store, diagnostics: diagnostics);
    await controller.setThemeMode(ThemeMode.light);

    expect(controller.themeMode, ThemeMode.light);
    expect(diagnostics.report, contains('settingsWriteFailed'));
    expect(diagnostics.report, isNot(contains('secret')));
    controller.dispose();
    diagnostics.dispose();
  });

  test('unresponsive preference read times out without freezing startup',
      () async {
    final store = _FakeStore()..blockedRead = Completer<String?>();
    final diagnostics = VelaDiagnostics();
    final controller = SettingsController(
      store: store,
      diagnostics: diagnostics,
      ioTimeout: const Duration(milliseconds: 25),
    );

    await controller.load();
    expect(controller.themeMode, ThemeMode.dark);
    expect(diagnostics.report, contains('settingsReadFailed'));
    controller.dispose();
    diagnostics.dispose();
  });

  test('rapid changes are serialized, latest selection persists', () async {
    final store = _FakeStore()..firstWrite = Completer<void>();
    final controller = SettingsController(store: store);

    final first = controller.setThemeMode(ThemeMode.light);
    // Let the first pending operation begin.
    await Future<void>.delayed(Duration.zero);
    final second = controller.setThemeMode(ThemeMode.system);
    expect(controller.themeMode, ThemeMode.system);

    store.firstWrite!.complete();
    await Future.wait([first, second]);
    expect(store.writes, ['light', 'system']);
    expect(store.value, 'system');
    controller.dispose();
  });
}
