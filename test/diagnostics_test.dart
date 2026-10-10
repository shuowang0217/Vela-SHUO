import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/diagnostics/vela_diagnostics.dart';

void main() {
  test('diagnostic records contain only timestamp and allowlisted codes',
      () async {
    final directory = await Directory.systemTemp.createTemp('vela_logs_');
    addTearDown(() => directory.delete(recursive: true));
    final diagnostics = VelaDiagnostics(
      directory: directory,
      clock: () => DateTime.utc(2026, 10, 10, 1, 0),
    );

    diagnostics.record(VelaDiagnosticEvent.appStarted);
    diagnostics.record(VelaDiagnosticEvent.settingsRecovered);
    await diagnostics.flush();

    final file = File('${directory.path}/events.jsonl');
    final text = await file.readAsString();
    expect(text, contains('2026-10-10T01:00:00.000Z'));
    expect(text, contains('settingsRecovered'));
    expect(text, isNot(contains('stack')));
    expect(text, isNot(contains('subscription')));
    expect(text.trim().split('\n').length, 2);
    expect(diagnostics.persistent, isTrue);
    diagnostics.dispose();
  });

  test('large journals rotate once and can be cleared locally', () async {
    final directory = await Directory.systemTemp.createTemp('vela_rotate_');
    addTearDown(() => directory.delete(recursive: true));
    final active = File('${directory.path}/events.jsonl');
    await active.writeAsString('x' * (VelaDiagnostics.maxLogBytes - 2));
    final diagnostics = VelaDiagnostics(directory: directory);
    diagnostics.record(VelaDiagnosticEvent.appStarted);
    await diagnostics.flush();

    final previous = File('${directory.path}/events.previous.jsonl');
    expect(await previous.exists(), isTrue);
    expect(await active.exists(), isTrue);
    expect(await active.length(), lessThan(512));
    expect(await diagnostics.clear(), isTrue);
    expect(await active.exists(), isFalse);
    expect(await previous.exists(), isFalse);
    expect(diagnostics.recentEntries, isEmpty);
    diagnostics.dispose();
  });

  test('failed disk writes degrade to bounded memory-only diagnostics',
      () async {
    final directory = await Directory.systemTemp.createTemp('vela_error_');
    addTearDown(() => directory.delete(recursive: true));
    final collision = File('${directory.path}/not_a_directory');
    await collision.writeAsString('do not overwrite');
    final diagnostics = VelaDiagnostics(directory: Directory(collision.path));

    diagnostics.record(VelaDiagnosticEvent.appStarted);
    await diagnostics.flush();
    expect(diagnostics.persistent, isFalse);
    for (var i = 0; i < 120; i++) {
      diagnostics.record(VelaDiagnosticEvent.appResumed);
    }
    expect(diagnostics.recentEntries.length, VelaDiagnostics.maxMemoryEntries);
    expect(await collision.readAsString(), 'do not overwrite');
    diagnostics.dispose();
  });
}
