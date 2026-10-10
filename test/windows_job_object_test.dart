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
      final watch = Stopwatch()..start();
      guard.close();
      // Windows may return exit code 0 for termination by a Job Object.
      // What matters is that the 30-second sleeper ends promptly.
      await child.exitCode.timeout(const Duration(seconds: 8));
      watch.stop();
      expect(watch.elapsed, lessThan(const Duration(seconds: 8)));
    } finally {
      child.kill();
    }
  });
}
