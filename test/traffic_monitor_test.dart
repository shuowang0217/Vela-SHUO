import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/traffic/vela_traffic_monitor.dart';

void main() {
  test('real counter deltas become Mbps and duration', () async {
    var now = DateTime.utc(2026, 10, 11, 0, 0);
    final values = <(int, int)>[(1000, 2000), (126000, 252000)];
    var index = 0;
    final monitor = VelaTrafficMonitor(
      reader: () async => values[index++],
      clock: () => now,
      interval: const Duration(days: 1),
    );
    monitor.sync(true);
    await Future<void>.delayed(Duration.zero);
    expect(monitor.uploadBytesPerSecond, isNull);
    expect(monitor.downloadBytesPerSecond, isNull);
    now = now.add(const Duration(seconds: 1));
    await monitor.sample();
    expect(VelaTrafficMonitor.rateMbps(monitor.uploadBytesPerSecond), '1.00');
    expect(VelaTrafficMonitor.rateMbps(monitor.downloadBytesPerSecond), '2.00');
    expect(monitor.elapsedLabel, '00:01');
    expect(monitor.downloadedBytes, 252000);
    monitor.sync(false);
    expect(monitor.elapsedLabel, '—');
    expect(monitor.downloadBytesPerSecond, null);
    expect(monitor.uploadedBytes, null);
    monitor.dispose();
  });

  test('counter reset or error must not retain stale speed', () async {
    var now = DateTime.utc(2026);
    final values = <(int, int)?>[(1000, 2000), (2000, 3000), (5, 9), null];
    var index = 0;
    final monitor = VelaTrafficMonitor(
      reader: () async => values[index++],
      clock: () => now,
      interval: const Duration(days: 1),
    );
    monitor.sync(true);
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(seconds: 1));
    await monitor.sample();
    expect(monitor.downloadBytesPerSecond, 1000);
    now = now.add(const Duration(seconds: 1));
    await monitor.sample();
    expect(monitor.downloadBytesPerSecond, isNull);
    now = now.add(const Duration(seconds: 1));
    await monitor.sample();
    expect(monitor.downloadBytesPerSecond, isNull);
    expect(monitor.uploadBytesPerSecond, isNull);
    monitor.dispose();
  });

  test('delayed poll cannot update disconnected session', () async {
    final delayed = Completer<(int, int)?>();
    final monitor = VelaTrafficMonitor(
      reader: () => delayed.future,
      interval: const Duration(days: 1),
    );
    monitor.sync(true);
    monitor.sync(false);
    delayed.complete((123456, 987654));
    await Future<void>.delayed(Duration.zero);
    expect(monitor.downloadedBytes, isNull);
    expect(monitor.connected, false);
    monitor.dispose();
  });

  test('byte formatting uses binary units and missing data marker', () {
    expect(VelaTrafficMonitor.totalLabel(null), '暂无数据');
    expect(VelaTrafficMonitor.totalLabel(0), '0 B');
    expect(VelaTrafficMonitor.totalLabel(1024), '1.0 KB');
    expect(VelaTrafficMonitor.totalLabel(1048576), '1.0 MB');
    expect(VelaTrafficMonitor.totalLabel(1073741824), '1.00 GB');
  });
}
