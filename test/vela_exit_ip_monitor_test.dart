import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/network/flclash_core_api.dart';
import 'package:vela_shuo/src/network/vela_exit_ip_monitor.dart';

class _RecordingTransport implements FlClashCoreTransport {
  final requests = <Map<String, dynamic>>[];
  final replies = <Map<String, dynamic>>[];

  @override
  Future<String?> invoke(String requestJson) async {
    final request = jsonDecode(requestJson) as Map<String, dynamic>;
    requests.add(request);
    final result = replies.removeAt(0);
    return jsonEncode({'id': request['id'], 'result': result});
  }
}

class _FakeExitProbe extends VelaExitIpProbe {
  _FakeExitProbe() : super(FlClashCoreApi(_RecordingTransport()));
  final pending = <Completer<VelaExitIpInfo?>>[];
  int cancelled = 0;

  @override
  Future<VelaExitIpInfo?> lookup() {
    final future = Completer<VelaExitIpInfo?>();
    pending.add(future);
    return future.future;
  }

  @override
  void cancel() => cancelled++;
}

void main() {
  test('FlClash source formats decode the real exit address and flag', () {
    final sources = <(String, String)>[
      (VelaExitIpProbe.cloudflare,
          'fl=test\nip=203.0.113.11\nloc=JP\ncolo=NRT\n'),
      (VelaExitIpProbe.ipSb,
          '{"ip":"203.0.113.11","country_code":"JP"}'),
      (VelaExitIpProbe.ipInfo,
          '{"ip":"203.0.113.11","country":"JP"}'),
      (VelaExitIpProbe.ipWhoIs,
          '{"ip":"203.0.113.11","country_code":"JP"}'),
      (VelaExitIpProbe.geoJs,
          '{"ip":"203.0.113.11","country_code":"JP"}'),
      (VelaExitIpProbe.countryIs,
          '{"ip":"203.0.113.11","country":"JP"}'),
      (VelaExitIpProbe.ipQuery,
          '{"ip":"203.0.113.11","location":{"country_code":"JP"}}'),
      (VelaExitIpProbe.identMe,
          '{"ip":"203.0.113.11","cc":"JP"}'),
    ];
    expect(VelaExitIpProbe.sources, hasLength(8));
    for (final (url, body) in sources) {
      expect(VelaExitIpInfo.parseSource(url, body)?.label,
          '🇯🇵 203.0.113.11', reason: url);
    }
  });

  test('rejects private addresses, invalid countries and unknown sources', () {
    expect(VelaExitIpInfo.parseSource(
        VelaExitIpProbe.cloudflare, 'ip=127.0.0.1\nloc=JP\n'), isNull);
    expect(VelaExitIpInfo.parseSource(
        VelaExitIpProbe.cloudflare, 'ip=192.168.1.2\nloc=JP\n'), isNull);
    expect(VelaExitIpInfo.parseSource(
        VelaExitIpProbe.cloudflare, 'ip=100.64.0.1\nloc=JP\n'), isNull);
    expect(VelaExitIpInfo.parseSource(
        VelaExitIpProbe.cloudflare, 'ip=203.0.113.1\nloc=ZZ\n'), isNull);
    expect(VelaExitIpInfo.parseSource(
        VelaExitIpProbe.cloudflare, 'ip=203.0.113.1\n'), isNull);
    expect(VelaExitIpInfo.parseSource(
        'https://unknown.example', '{"ip":"203.0.113.1","country":"JP"}'),
        isNull);
    expect(VelaExitIpInfo.parseSource(
        VelaExitIpProbe.countryIs, '{"ip":23}'), isNull);
  });

  test('sends eight HTTPS providers through the real FlClash Go RPC',
      () async {
    final transport = _RecordingTransport();
    transport.replies.add({
      'url': VelaExitIpProbe.cloudflare,
      'body': 'ip=203.0.113.15\nloc=US\n',
      'chains': ['US-01', 'GLOBAL'],
      'core-epoch': 2,
      'picks-version': 8,
    });
    final probe = VelaExitIpProbe(FlClashCoreApi(transport));
    final result = await probe.lookup();
    expect(result?.label, '🇺🇸 203.0.113.15');
    expect(result?.chains, ['US-01', 'GLOBAL']);
    expect(result?.routeVerified, isTrue);
    expect(result?.coreEpoch, 2);
    expect(result?.picksVersion, 8);
    expect(result?.source, VelaExitIpProbe.cloudflare);
    expect(transport.requests, hasLength(1));
    final request = transport.requests.single;
    expect(request['method'], 'outboundIp');
    final args = request['arguments'] as Map;
    expect(args['proxy-name'], '');
    expect(args['timeout'], 6000);
    expect(args['urls'], VelaExitIpProbe.sources);
    expect((args['urls'] as List).every((x) =>
        (x as String).startsWith('https://')), isTrue);
  });

  test('bad provider body retries without the rejected source', () async {
    final transport = _RecordingTransport();
    transport.replies.addAll([
      {
        'url': VelaExitIpProbe.cloudflare,
        'body': 'ip=203.0.113.12\nloc=ZZ\n',
      },
      {
        'url': VelaExitIpProbe.countryIs,
        'body': '{"ip":"203.0.113.12","country":"GB"}',
      },
    ]);
    final result = await VelaExitIpProbe(
        FlClashCoreApi(transport)).lookup();
    expect(result?.label, '🇬🇧 203.0.113.12');
    expect(transport.requests, hasLength(2));
    final second = transport.requests[1]['arguments'] as Map;
    expect(second['urls'], isNot(contains(VelaExitIpProbe.cloudflare)));
  });

  test('disconnected state never probes and displays timeout', () {
    final probe = _FakeExitProbe();
    final monitor = VelaExitIpMonitor(
        probe: probe, interval: const Duration(days: 1),
        connectionSettle: Duration.zero,
        initialRetries: const []);
    expect(monitor.label, 'timeout');
    monitor.sync(false, 'JP');
    expect(probe.pending, isEmpty);
    monitor.dispose();
  });

  test('refresh does not erase valid IP or replace it on transient timeout',
      () async {
    final probe = _FakeExitProbe();
    final monitor = VelaExitIpMonitor(
        probe: probe, interval: const Duration(days: 1),
        connectionSettle: Duration.zero,
        initialRetries: const []);
    monitor.sync(true, 'airport-a|JP');
    expect(monitor.label, '检测中…');
    probe.pending.first.complete(const VelaExitIpInfo(
        address: '203.0.113.17', countryCode: 'JP'));
    await Future<void>.delayed(Duration.zero);
    expect(monitor.label, '🇯🇵 203.0.113.17');

    final retry = monitor.refresh();
    expect(monitor.label, '🇯🇵 203.0.113.17');
    probe.pending.last.complete(null);
    await retry;
    expect(monitor.label, '🇯🇵 203.0.113.17');
    expect(monitor.info?.address, '203.0.113.17');
    monitor.dispose();
  });

  testWidgets('initial timeout retries automatically without focus or node '
      'change', (tester) async {
    final probe = _FakeExitProbe();
    final monitor = VelaExitIpMonitor(
      probe: probe,
      interval: const Duration(days: 1),
      connectionSettle: const Duration(milliseconds: 100),
      initialRetries: const [Duration(milliseconds: 250)],
    );

    monitor.sync(true, 'node-one');
    expect(monitor.label, '检测中…');
    expect(probe.pending, isEmpty);
    await tester.pump(const Duration(milliseconds: 101));
    expect(probe.pending, hasLength(1));
    probe.pending.first.complete(null);
    await tester.pump();
    expect(monitor.label, 'timeout');
    // The second request must start without any UI lifecycle event.
    await tester.pump(const Duration(milliseconds: 251));
    expect(probe.pending, hasLength(2));
    probe.pending.last.complete(const VelaExitIpInfo(
        address: '203.0.113.21', countryCode: 'US'));
    await tester.pump();
    expect(monitor.label, '🇺🇸 203.0.113.21');
    monitor.dispose();
  });

  test('unchanged connected route is a no-op, including window resume',
      () async {
    final probe = _FakeExitProbe();
    final monitor = VelaExitIpMonitor(
      probe: probe,
      interval: const Duration(days: 1),
      connectionSettle: Duration.zero,
    );
    monitor.sync(true, 'same-route');
    probe.pending.single.complete(const VelaExitIpInfo(
        address: '203.0.113.23', countryCode: 'JP'));
    await Future<void>.delayed(Duration.zero);
    monitor.sync(true, 'same-route');
    expect(probe.pending, hasLength(1));
    expect(monitor.label, '🇯🇵 203.0.113.23');
    monitor.dispose();
  });

  test('old node results cannot overwrite a new route or disconnect',
      () async {
    final probe = _FakeExitProbe();
    final monitor = VelaExitIpMonitor(
        probe: probe, interval: const Duration(days: 1),
        connectionSettle: Duration.zero,
        initialRetries: const []);
    monitor.sync(true, 'node-one');
    monitor.sync(true, 'node-two');
    expect(probe.pending, hasLength(2));
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
  testWidgets('old IP expires after six minutes even without a focus change',
      (tester) async {
    final probe = _FakeExitProbe();
    var now = DateTime(2026, 10, 29, 8);
    final monitor = VelaExitIpMonitor(
      probe: probe,
      interval: const Duration(minutes: 20),
      maxAge: const Duration(minutes: 6),
      clock: () => now,
      connectionSettle: Duration.zero,
      initialRetries: const [],
    );
    monitor.sync(true, 'node-one');
    probe.pending.single.complete(const VelaExitIpInfo(
      address: '203.0.113.9', countryCode: 'JP'));
    await tester.pump();
    expect(monitor.info?.address, '203.0.113.9');
    expect(monitor.verifiedAt, now);
    now = now.add(const Duration(minutes: 6));
    await tester.pump(const Duration(minutes: 6));
    expect(monitor.info, isNull);
    expect(monitor.label, 'timeout');
    expect(monitor.hasExpired, isTrue);
    monitor.dispose();
  });

  test('global rejects DIRECT native chain, rule accepts actual DIRECT',
      () async {
    final probe = _FakeExitProbe();
    final monitor = VelaExitIpMonitor(
      probe: probe,
      interval: const Duration(days: 1),
      connectionSettle: Duration.zero,
      initialRetries: const [],
    );
    const directResult = VelaExitIpInfo(
      address: '203.0.113.19', countryCode: 'JP',
      chains: ['DIRECT', 'GLOBAL'],
      coreEpoch: 12, picksVersion: 7,
    );
    monitor.sync(true, 'airport|global', mode: 'global');
    probe.pending[0].complete(directResult);
    await Future<void>.delayed(Duration.zero);
    expect(monitor.info, isNull);
    expect(monitor.failureReason, contains('代理模式不一致'));

    monitor.sync(true, 'airport|rule', mode: 'rule');
    probe.pending[1].complete(directResult);
    await Future<void>.delayed(Duration.zero);
    expect(monitor.info?.chains, ['DIRECT', 'GLOBAL']);
    expect(monitor.routeValidation, contains('内核真实路由链'));
    monitor.dispose();
  });

  test('long resume rejects expired IP immediately then retries',
      () async {
    final probe = _FakeExitProbe();
    var now = DateTime(2026, 10, 29, 9);
    final monitor = VelaExitIpMonitor(
      probe: probe,
      interval: const Duration(days: 1),
      maxAge: const Duration(minutes: 6),
      clock: () => now,
      connectionSettle: Duration.zero,
      initialRetries: const [],
    );
    monitor.sync(true, 'node-a');
    probe.pending.first.complete(const VelaExitIpInfo(
        address: '203.0.113.9', countryCode: 'JP'));
    await Future<void>.delayed(Duration.zero);
    expect(monitor.info?.countryCode, 'JP');

    now = now.add(const Duration(minutes: 8));
    final awake = monitor.recheckAfterWake();
    expect(monitor.info, isNull);
    expect(monitor.loading, isTrue);
    expect(probe.pending, hasLength(2));
    probe.pending.last.complete(const VelaExitIpInfo(
        address: '203.0.113.18', countryCode: 'US'));
    await awake;
    expect(monitor.info?.countryCode, 'US');
    monitor.dispose();
  });

}
