import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/vela_connection_coordinator.dart';
import 'package:vela_shuo/src/core/vela_core_controller.dart';
import 'package:vela_shuo/src/core/vela_system_proxy.dart';
import 'package:vela_shuo/src/smart/vela_node_probe.dart';
import 'package:vela_shuo/src/smart/vela_smart_controller.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_controller.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_parser.dart';

class _Fetcher implements VelaSubscriptionFetcher {
  _Fetcher(this.count);
  final int count;
  @override
  Future<String> download(String url) async {
    final rows = List.generate(count, (i) =>
        '  - name: "Node-$i"\n'
        '    type: ss\n'
        '    server: n$i.example.test\n'
        '    port: 443\n'
        '    cipher: aes-128-gcm\n'
        '    password: secret-$i\n').join();
    return 'proxies:\n$rows';
  }
}

class _Probe implements VelaNodeLatencyProbe {
  final List<int> measured = [];
  final Set<int> fails = {};
  @override
  Future<VelaLatencySample> measure(VelaSubscriptionNode node) async {
    final i = int.parse(node.name.substring(5));
    measured.add(i);
    if (fails.contains(i)) return const VelaLatencySample(ok: false);
    return VelaLatencySample(ok: true,
        elapsed: Duration(milliseconds: 200 - 15 * i));
  }
}

class _ProxyBackend implements VelaWindowsProxyBackend {
  VelaProxySnapshot snapshot =
      const VelaProxySnapshot(enabled: 0, server: null);
  @override
  Future<VelaProxySnapshot> read() async => snapshot;
  @override
  Future<bool> hasPac() async => false;
  @override
  Future<void> write(VelaProxySnapshot value) async { snapshot = value; }
  @override
  Future<void> refresh() async {}
}

class _CoreHandle implements VelaCoreHandle {
  final _exited = Completer<int>();
  @override
  Future<int> get exitCode => _exited.future;
  @override
  void kill() {
    if (!_exited.isCompleted) _exited.complete(-1);
  }
}

class _CoreRunner implements VelaCoreRunner {
  @override
  Future<void> check(String binary, String config) async {}
  @override
  Future<void> assertPortFree(int port) async {}
  @override
  Future<VelaCoreHandle> launch(String binary, String config) async =>
      _CoreHandle();
  @override
  Future<bool> awaitLocalListener(int port) async => true;
}

class _Remote implements VelaRemoteProbe {
  @override
  Future<bool> verify(int port) async => true;
}

Future<(Directory, VelaCoreController, VelaSubscriptionController,
    VelaSystemProxyManager, VelaConnectionCoordinator)>
    setup({int count = 9}) async {
  final folder = await Directory.systemTemp.createTemp('vela-smart-');
  final executable = File('${folder.path}/sing-box.exe');
  await executable.writeAsString('fake');
  final core = VelaCoreController(
    supported: true, managedProfileDirectory: folder,
    runner: _CoreRunner(), remoteProbe: _Remote(),
  );
  expect(await core.chooseBinary(executable.path), true);
  final sub = VelaSubscriptionController(
    core: core, fetcher: _Fetcher(count),
  );
  expect(await sub.importFromUrl('https://example.test/sub'), true);
  expect(await sub.selectNode(0), true);
  final proxy = VelaSystemProxyManager(
    supported: true, backend: _ProxyBackend(),
    stateDirectory: folder,
  );
  final link = VelaConnectionCoordinator(
    core: core, subscription: sub, proxy: proxy,
  );
  return (folder, core, sub, proxy, link);
}

void main() {
  test('batched HTTPS tests measure 8 then remaining 1, rank by actual times',
      () async {
    final (folder, core, sub, proxy, link) = await setup();
    final probe = _Probe();
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link, probe: probe,
    );
    try {
      expect(smart.count, 9);
      expect(smart.nextBatchSize, 8);
      await smart.testNextBatch();
      expect(probe.measured, List<int>.generate(8, (i) => i));
      expect(smart.nextBatchSize, 1);
      expect(smart.recommendedIndex, 7);
      expect(smart.resultAt(7)?.lastMs, 95);
      await smart.testNextBatch();
      expect(probe.measured, List<int>.generate(9, (i) => i));
      expect(smart.recommendedIndex, 8);
      expect(smart.resultAt(8)?.lastMs, 80);
      expect(smart.canRecommend, isTrue);
      expect(await smart.useRecommended(), isTrue);
      expect(sub.selectedIndex, 8);
      expect(core.isListening, isFalse);
      expect(proxy.active, isFalse);
      expect(smart.nextBatchSize, 8);
    } finally {
      smart.dispose();
      link.dispose();
      sub.dispose();
      core.dispose();
      proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('automatic idle choice never starts core or changes system proxy',
      () async {
    final (folder, core, sub, proxy, link) = await setup(count: 5);
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link, probe: _Probe(),
    );
    try {
      smart.setAutoPick(true);
      await smart.testNextBatch();
      expect(sub.selectedIndex, 4); // 200ms → 140ms: >50ms and >20%
      expect(proxy.active, isFalse);
      expect(core.isListening, isFalse);
    } finally {
      smart.dispose(); link.dispose(); sub.dispose();
      core.dispose(); proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('connected session is protected from scan and node replacement',
      () async {
    final (folder, core, sub, proxy, link) = await setup(count: 3);
    final probe = _Probe();
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link, probe: probe,
    );
    try {
      expect(await link.connect(), isTrue);
      await smart.testNextBatch();
      expect(probe.measured, isEmpty);
      expect(smart.canRecommend, false);
      expect(sub.selectedIndex, 0);
      expect(link.connected, true);
      expect(await link.disconnect(), true);
      await smart.testNextBatch();
      expect(probe.measured.length, 3);
    } finally {
      smart.dispose(); link.dispose(); sub.dispose();
      core.dispose(); proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('cooldown, hysteresis and failures prevent oscillation', () {
    final now = DateTime.utc(2026, 10, 10, 12);
    const policy = VelaSmartSwitchPolicy();
    final old = VelaNodeHealth.first(0,
      const VelaLatencySample(ok: true,
          elapsed: Duration(milliseconds: 200)), now);
    final slight = VelaNodeHealth.first(1,
      const VelaLatencySample(ok: true,
          elapsed: Duration(milliseconds: 175)), now);
    final strong = VelaNodeHealth.first(2,
      const VelaLatencySample(ok: true,
          elapsed: Duration(milliseconds: 100)), now);
    expect(policy.shouldPrefer(
        current: old, candidate: slight, now: now), false);
    expect(policy.shouldPrefer(
        current: old, candidate: strong, now: now), true);
    expect(policy.shouldPrefer(
        current: old, candidate: strong, now: now,
        lastSelection: now.subtract(const Duration(seconds: 30))), false);
    final failed = strong.add(
        const VelaLatencySample(ok: false), now);
    expect(failed.reachable, false);
    expect(policy.shouldPrefer(
        current: old, candidate: failed, now: now), false);
  });

  test('probe failure cannot produce a fake latency score', () async {
    final (folder, core, sub, proxy, link) = await setup(count: 2);
    final probe = _Probe()..fails.add(1);
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link, probe: probe,
    );
    try {
      await smart.testNextBatch();
      expect(smart.resultAt(1)!.reachable, false);
      expect(smart.resultAt(1)!.score, isNull);
      expect(smart.resultAt(1)!.lastMs, isNull);
      expect(smart.recommendedIndex, 0);
    } finally {
      smart.dispose(); link.dispose(); sub.dispose();
      core.dispose(); proxy.dispose();
      await folder.delete(recursive: true);
    }
  });
}
