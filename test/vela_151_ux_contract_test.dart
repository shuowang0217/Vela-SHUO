import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/vela_session_time.dart';

void main() {
  test('connection duration only reports confirmed active sessions', () {
    expect(VelaSessionTime.format(null), '连接时长 —');
    expect(VelaSessionTime.format(Duration.zero), '连接时长 00:00:00');
    expect(VelaSessionTime.format(const Duration(seconds: 9)), '连接时长 00:00:09');
    expect(VelaSessionTime.format(const Duration(minutes: 5, seconds: 7)),
        '连接时长 00:05:07');
    expect(VelaSessionTime.format(const Duration(hours: 12, seconds: 1)),
        '连接时长 12:00:01');
  });

  test('both connect cards have a real session clock and Vela About', () {
    final ui = File('lib/src/app.dart').readAsStringSync();
    final vpn = File('lib/src/android/vela_android_vpn.dart')
        .readAsStringSync();
    final windows = File('lib/src/core/vela_connection_coordinator.dart')
        .readAsStringSync();
    expect(ui, contains('desktop_connection_uptime'));
    expect(ui, contains('mobile_connection_uptime'));
    expect(ui, contains("const Text('关于 Vela')"));
    expect(ui, contains('VelaUpdateService.currentVersion'));
    expect(vpn, contains('Stopwatch()..start()'));
    expect(windows, contains('Stopwatch()..start()'));
    expect(vpn, contains('_durationTicker?.cancel()'));
    expect(windows, contains('_durationTicker?.cancel()'));
  });

  test('mobile node cards and benchmark actions are independent', () {
    final proxy = File('lib/src/stellar/vela_stellar_proxy_page.dart')
        .readAsStringSync();
    final smart = File('lib/src/smart/vela_smart_controller.dart')
        .readAsStringSync();
    expect(proxy, contains('grid.maxWidth > 850 ? 3 : 2'));
    expect(proxy, contains("stellar_latency_benchmark"));
    expect(proxy, contains("stellar_download_benchmark"));
    expect(proxy, contains('smart!.testAllLatencies'));
    expect(proxy, contains('smart.testAllDownloads()'));
    expect(smart, contains('Future<void> testAllDownloads()'));
    expect(smart, contains("_scanKind = 'download'"));
  });
}
