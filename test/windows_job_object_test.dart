import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/vela_windows_job.dart';

void main() {
  test('Windows Job Object kills the owned child without PID scanning',
      () async {
    if (!Platform.isWindows) return;
    final child = await Process.start('powershell.exe', [
      '-NoProfile', '-NonInteractive',
      '-Command', 'Start-Sleep -Seconds 30',
    ], runInShell: false);
    try {
      final guard = VelaWindowsJob.attach(child.pid);
      guard.close();
      final exit = await child.exitCode.timeout(const Duration(seconds: 8));
      expect(exit, isNot(0));
    } finally {
      child.kill();
    }
  });
}
