import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/network/vela_exit_ip_monitor.dart';

class _FakeExitProbe extends VelaExitIpProbe {
  final requests = <(bool, int?)>[];
  final pending = <Completer<VelaExitIpInfo?>>[];
  int cancelled = 0;

  @override
  Future<VelaExitIpInfo?> lookup({
    required bool useProxy, int? proxyPort,
  }) {
    requests.add((useProxy, proxyPort));
    final future = Completer<VelaExitIpInfo?>();
    pending.add(future);
    return future.future;
  }

  @override
  void cancel() => cancelled++;
}

void main() {
  test('trace parser renders real country flag and address only', () {
    final result = VelaExitIpInfo.parseTrace(
        'fl=test\nip=203.0.113.11\nloc=JP\ncolo=NRT\n');
    expect(result?.address, '203.0.113.11');
    expect(result?.label, '🇯🇵 203.0.113.11');
    expect(VelaExitIpInfo.parseTrace('ip=203.0.113.11\n'), isNull);
    expect(VelaExitIpInfo.parseTrace('ip=not-an-ip\nloc=US\n'), isNull);
    expect(VelaExitIpInfo.parseTrace('ip=127.0.0.1\nloc=JP\n'), isNull);
    expect(VelaExitIpInfo.parseTrace('ip=203.0.113.11\nloc=??\n'), isNull);
  });

  test('disconnected state never sends a probe and reads timeout', () {
    final probe = _FakeExitProbe();
    final monitor = VelaExitIpMonitor(
      useProxy: true, proxyPort: () => 20808,
      probe: probe, interval: const Duration(days: 1),
    );
    expect(monitor.label, 'timeout');
    monitor.sync(false, 'JP');
    expect(probe.requests, isEmpty);
    monitor.dispose();
  });

  test('connected route shows flag and IP; failed refresh shows timeout',
      () async {
    final probe = _FakeExitProbe();
    final monitor = VelaExitIpMonitor(
      useProxy: true, proxyPort: () => 20808,
      probe: probe, interval: const Duration(days: 1),
    );
    monitor.sync(true, 'airport-a|JP');
    expect(monitor.label, '检测中…');
    expect(probe.requests, [(true, 20808)]);
    probe.pending.first.complete(const VelaExitIpInfo(
      address: '203.0.113.17', countryCode: 'JP'));
    await Future<void>.delayed(Duration.zero);
    expect(monitor.label, '🇯🇵 203.0.113.17');

    final retry = monitor.refresh();
    expect(monitor.label, '检测中…');
    probe.pending.last.complete(null);
    await retry;
    expect(monitor.label, 'timeout');
    expect(monitor.info, isNull);
    monitor.dispose();
  });

  test('old node response cannot overwrite new route or disconnect',
      () async {
    final probe = _FakeExitProbe();
    final monitor = VelaExitIpMonitor(
      useProxy: false, proxyPort: () => null,
      probe: probe, interval: const Duration(days: 1),
    );
    monitor.sync(true, 'node-one');
    monitor.sync(true, 'node-two');
    expect(probe.requests, [(false, null), (false, null)]);
    probe.pending.first.complete(const VelaExitIpInfo(
        address: '203.0.113.1', countryCode: 'US'));
    await Future<void>.delayed(Duration.zero);
    expect(monitor.info, isNull);
    probe.pending.last.complete(const VelaExitIpInfo(
        address: '203.0.113.2', countryCode: 'JP'));
    await Future<void>.delayed(Duration.zero);
    expect(monitor.label, '🇯🇵 203.0.113.2');
    monitor.sync(false, '');
    expect(monitor.label, 'timeout');
    expect(monitor.info, isNull);
    monitor.dispose();
  });
}
