import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/vela_connection_coordinator.dart';
import 'package:vela_shuo/src/core/vela_core_controller.dart';
import 'package:vela_shuo/src/core/vela_system_proxy.dart';
import 'package:vela_shuo/src/smart/vela_node_probe.dart';
import 'package:vela_shuo/src/smart/vela_download_probe.dart';
import 'package:vela_shuo/src/smart/vela_smart_controller.dart';
import 'package:vela_shuo/src/smart/vela_smart_country.dart';
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

class _BatchProbe implements VelaNodeLatencyProbe, VelaBatchLatencyProbe {
  int calls = 0;
  bool broken = false;

  @override
  Future<VelaLatencySample> measure(VelaSubscriptionNode node) =>
      throw StateError('Flutter must not call per-node latency RPC');

  @override
  Future<Map<String, VelaLatencySample>> measureBatch(
      List<VelaSubscriptionNode> nodes) async {
    ++calls;
    if (broken) throw StateError('Synthetic FlClash IPC disconnect');
    return {
      for (var i = 0; i < nodes.length; i++)
        nodes[i].name: VelaLatencySample(
          ok: i.isEven,
          elapsed: i.isEven ? Duration(milliseconds: 100 + i) : null,
        ),
    };
  }
}

class _SpeedProbe implements VelaNodeDownloadProbe {
  final List<String> tested = [];
  bool succeeds = true;
  @override
  Future<VelaDownloadSample> measureDownload(VelaSubscriptionNode node) async {
    tested.add(node.name);
    return succeeds
        ? const VelaDownloadSample(ok: true, mbps: 65.4,
            bytes: VelaHttpsDownloadTransport.sampleBytes)
        : const VelaDownloadSample(ok: false);
  }
}

// A slow native CDN probe cannot safely overlap with the next node here.
// A sweep must use one active native download at a time.
class _BoundedDownloadProbe implements VelaNodeDownloadProbe {
  int active = 0;
  int maxActive = 0;
  final List<String> tested = [];

  @override
  Future<VelaDownloadSample> measureDownload(VelaSubscriptionNode node) async {
    active++;
    if (active > maxActive) maxActive = active;
    tested.add(node.name);
    final underCap = active <= 2;
    await Future<void>.delayed(const Duration(milliseconds: 2));
    active--;
    return underCap
        ? const VelaDownloadSample(ok: true, mbps: 65.4,
            bytes: VelaHttpsDownloadTransport.sampleBytes)
        : const VelaDownloadSample(ok: false, reason: 'busy');
  }
}

class _GatedDownloadProbe implements VelaNodeDownloadProbe {
  final Completer<void> gate = Completer<void>();
  final List<String> tested = [];

  @override
  Future<VelaDownloadSample> measureDownload(VelaSubscriptionNode node) async {
    tested.add(node.name);
    await gate.future;
    return const VelaDownloadSample(
        ok: true, mbps: 65.4, bytes: VelaHttpsDownloadTransport.sampleBytes);
  }
}

class _BothProbe implements VelaFullNodeProbe {
  final List<String> names = [];
  @override
  Future<VelaFullNodeSample> measureBoth(VelaSubscriptionNode node) async {
    final number = int.parse(node.name.substring(5));
    names.add(node.name);
    final speed = [20.0, 88.0, 45.0, 64.0, 34.0][number];
    final delay = [35, 150, 42, 65, 30][number];
    return VelaFullNodeSample(
      latency: VelaLatencySample(
          ok: true, elapsed: Duration(milliseconds: delay)),
      download: VelaDownloadSample(ok: true, mbps: speed,
          bytes: VelaHttpsDownloadTransport.sampleBytes),
    );
  }
}

class _DownloadBlockedProbe implements VelaFullNodeProbe {
  @override
  Future<VelaFullNodeSample> measureBoth(VelaSubscriptionNode node) async =>
      const VelaFullNodeSample(
        latency: VelaLatencySample(
            ok: true, elapsed: Duration(milliseconds: 96)),
        download: VelaDownloadSample(ok: false),
      );
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
  final executable = File('${folder.path}/mihomo.exe');
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


class _LimitedProbe implements VelaNodeLatencyProbe {
  int active = 0;
  int maximum = 0;
  final List<int> visited = [];

  @override
  Future<VelaLatencySample> measure(VelaSubscriptionNode node) async {
    final index = int.parse(node.name.substring(5));
    visited.add(index);
    active++;
    if (active > maximum) { maximum = active; }
    try {
      await Future<void>.delayed(const Duration(milliseconds: 3));
      if (index % 7 == 0) {
        return const VelaLatencySample(ok: false);
      }
      return VelaLatencySample(ok: true,
          elapsed: Duration(milliseconds: 300 - index));
    } finally {
      active--;
    }
  }
}

class _GatedProbe implements VelaNodeLatencyProbe {
  final Completer<void> gate = Completer<void>();
  int started = 0;

  @override
  Future<VelaLatencySample> measure(VelaSubscriptionNode node) async {
    started++;
    await gate.future;
    return const VelaLatencySample(
        ok: true, elapsed: Duration(milliseconds: 150));
  }
}

void main() {
  test('Android native latency and download work without Windows proxy, '
      'and never auto-select while VPN is active', () async {
    final (folder, core, sub, proxy, link) = await setup(count: 3);
    var vpnActive = true;
    var vpnBusy = false;
    final delay = _BatchProbe();
    final speed = _SpeedProbe();
    final smart = VelaSmartController(
      core: core, subscription: sub,
      // Android has a VpnService, not VelaConnectionCoordinator.
      sessionActive: () => vpnActive,
      sessionBusy: () => vpnBusy,
      probe: delay, downloadProbe: speed,
    );
    try {
      expect(smart.canTestAll, true);
      expect(smart.safeToSelect, false);
      await smart.testAllLatencies();
      expect(delay.calls, 1);
      expect(smart.scanned, 3);
      expect(smart.resultAt(0)?.lastMs, 100);
      expect(smart.downloadAt(0), isNull);

      await smart.testAllNodes();
      expect(delay.calls, 2);
      expect(speed.tested, ['Node-0', 'Node-1', 'Node-2']);
      expect(smart.downloadAt(0)?.megabytesPerSecond, closeTo(8.175, .001));
      expect(smart.safeToSelect, false);
      expect(smart.canRecommend, false);

      expect(await smart.testSelectedDownload(), true);
      expect(smart.downloadAt(0)?.ok, true);
      vpnBusy = true;
      expect(smart.canTestAll, false);
      expect(smart.canTestSelectedDownload, false);
      vpnBusy = false;
      vpnActive = false;
      expect(smart.safeToSelect, true);
    } finally {
      smart.dispose();
      link.dispose();
      sub.dispose();
      core.dispose();
      proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('download-only sweep keeps latency and bounds two node downloads', () async {
    final (folder, core, sub, proxy, link) = await setup(count: 6);
    final delays = _BatchProbe();
    final speed = _BoundedDownloadProbe();
    final smart = VelaSmartController(core: core, subscription: sub,
      connection: link, probe: delays, downloadProbe: speed);
    try {
      await smart.testAllLatencies();
      expect(delays.calls, 1);
      final previous = smart.resultAt(0)?.lastMs;
      await smart.testAllDownloads();
      expect(smart.scanKind, 'download');
      expect(delays.calls, 1); // no URLTest on download button
      expect(smart.resultAt(0)?.lastMs, previous);
      expect(speed.maxActive, 2);
      expect(smart.downloadsTested, 6);
      expect(smart.downloadsSuccessful, 6);
      await smart.testAllLatencies();
      expect(delays.calls, 2);
      expect(smart.downloadsTested, 6); // no clearing download cache
    } finally {
      smart.dispose(); link.dispose(); sub.dispose();
      core.dispose(); proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('all-node native downloads are bounded to two workers', () async {
    final (folder, core, sub, proxy, link) = await setup(count: 6);
    final delay = _BatchProbe();
    final speed = _BoundedDownloadProbe();
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link,
      probe: delay, downloadProbe: speed,
    );
    try {
      await smart.testAllNodes(includeAllCountries: true);
      expect(delay.calls, 1);
      expect(speed.maxActive, 2);
      expect(speed.tested, [
        'Node-0', 'Node-1', 'Node-2', 'Node-3', 'Node-4', 'Node-5']);
      expect(smart.downloadsTested, 6);
      expect(smart.downloadsSuccessful, 6);
      expect(smart.resultAt(1)?.reachable, false);
      expect(smart.downloadAt(1)?.ok, true);
    } finally {
      smart.dispose(); link.dispose(); sub.dispose();
      core.dispose(); proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('native download error labels are safe, while latency stays valid', () {
    const reason = VelaDownloadSample(ok: false, reason: 'timeout');
    expect(reason.failureLabel, '下载超时');
    const busy = VelaDownloadSample(ok: false, reason: 'busy');
    expect(busy.failureLabel, '测速内核忙');
    const unknown = VelaDownloadSample(
        ok: false, reason: 'https://example.invalid/secret');
    expect(unknown.failureLabel, '下载失败');
  });

  test('batch delays appear before the all-node download phase completes',
      () async {
    final (folder, core, sub, proxy, link) = await setup(count: 4);
    final delay = _BatchProbe();
    final download = _GatedDownloadProbe();
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link,
      probe: delay, downloadProbe: download,
    );
    try {
      final pending = smart.testAllNodes(includeAllCountries: true);
      await Future<void>.delayed(Duration.zero);
      expect(smart.scanning, true);
      expect(smart.resultAt(0)?.lastMs, 100);
      expect(smart.resultAt(1)?.reachable, false);
      expect(smart.resultAt(2)?.lastMs, 102);
      expect(smart.downloadAt(0), isNull);
      expect(smart.scanned, 0);
      download.gate.complete();
      await pending;
      expect(smart.scanned, 4);
      expect(smart.downloadsSuccessful, 4);
      expect(smart.resultAt(0)?.samples, 1);
    } finally {
      smart.dispose(); link.dispose(); sub.dispose();
      core.dispose(); proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('proxy page full-node action combines latency and downloads '
      'even while Smart AI filters a different country', () async {
    final (folder, core, sub, proxy, link) = await setup(count: 5);
    final delay = _BatchProbe();
    final speed = _SpeedProbe();
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link,
      probe: delay, downloadProbe: speed,
    );
    try {
      // Node-* names do not match the Smart page's JP-only filter.
      smart.setAiMode(true);
      expect(smart.canTestAll, true);
      await smart.testAllNodes(includeAllCountries: true);

      expect(delay.calls, 1);
      expect(smart.scanned, 5);
      expect(smart.total, 5);
      expect(smart.successful, 3);
      expect(smart.failed, 2);
      expect(speed.tested, [
        'Node-0', 'Node-1', 'Node-2', 'Node-3', 'Node-4']);
      expect(smart.downloadsTested, 5);
      expect(smart.downloadsSuccessful, 5);
      expect(smart.resultAt(0)?.lastMs, 100);
      expect(smart.resultAt(1)?.reachable, false);
      expect(smart.downloadAt(1)?.megabytesPerSecond,
          closeTo(8.175, .001));
      expect(smart.status, contains('下载成功 5'));
    } finally {
      smart.dispose(); link.dispose(); sub.dispose();
      core.dispose(); proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('FlClash native latency batch updates real nodes without per-node RPC',
      () async {
    final (folder, core, sub, proxy, link) = await setup(count: 9);
    final probe = _BatchProbe();
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link, probe: probe,
    );
    try {
      await smart.testAllLatencies();
      expect(probe.calls, 1);
      expect(smart.scanned, 9);
      expect(smart.successful, 5);
      expect(smart.failed, 4);
      expect(smart.resultAt(0)?.lastMs, 100);
      expect(smart.resultAt(1)?.reachable, false);
    } finally {
      smart.dispose();
      link.dispose();
      sub.dispose();
      core.dispose();
      proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('broken batch RPC never misreports every node as unreachable',
      () async {
    final (folder, core, sub, proxy, link) = await setup(count: 8);
    final probe = _BatchProbe()..broken = true;
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link, probe: probe,
    );
    try {
      await smart.testAllLatencies();
      expect(probe.calls, 1);
      expect(smart.scanned, 0);
      expect(smart.failed, 0);
      expect(smart.successful, 0);
      expect(smart.status, contains('批量测速通信失败'));
    } finally {
      smart.dispose();
      link.dispose();
      sub.dispose();
      core.dispose();
      proxy.dispose();
      await folder.delete(recursive: true);
    }
  });


  test('proxy page latency-only test never measures download speed', () async {
    final (folder, core, sub, proxy, link) = await setup(count: 4);
    final delay = _Probe();
    final downloads = _BothProbe();
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link,
      probe: delay, fullProbe: downloads,
    );
    try {
      await smart.testAllLatencies();
      expect(delay.measured, [0, 1, 2, 3]);
      expect(downloads.names, isEmpty);
      expect(smart.successful, 4);
      expect(smart.failed, 0);
      expect(smart.resultAt(0)?.lastMs, 200);
      expect(smart.downloadAt(0), isNull);
      expect(smart.status, contains('延迟测试完成'));
    } finally {
      smart.dispose();
      link.dispose();
      sub.dispose();
      core.dispose();
      proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('FlClash latency sweep respects native concurrency and skips downloads',
      () async {
    final (folder, core, sub, proxy, link) = await setup(count: 25);
    final probe = _LimitedProbe();
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link, probe: probe,
    );
    try {
      await smart.testAllLatencies();
      expect(smart.scanned, 25);
      expect(probe.visited.toSet().length, 25);
      expect(probe.maximum, greaterThan(2));
      expect(probe.maximum, lessThanOrEqualTo(12));
      expect(smart.successful, 21); // 0,7,14,21 failed
      expect(smart.failed, 4);
      expect(smart.downloadAt(1), isNull);
    } finally {
      smart.dispose();
      link.dispose();
      sub.dispose();
      core.dispose();
      proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

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
  test('one click measures all 23 nodes exactly once, max concurrency two',
      () async {
    final (folder, core, sub, proxy, link) = await setup(count: 23);
    final probe = _LimitedProbe();
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link, probe: probe,
    );
    try {
      expect(smart.canTestAll, true);
      await smart.testAllNodes();
      expect(smart.allNodesScan, true);
      expect(smart.scanned, 23);
      expect(smart.total, 23);
      expect(smart.successful, 19); // 0,7,14,21 failed
      expect(smart.failed, 4);
      expect(probe.visited.toSet().length, 23);
      expect(probe.visited.toSet(),
          List<int>.generate(23, (i) => i).toSet());
      expect(probe.maximum, lessThanOrEqualTo(2));
      expect(probe.maximum, greaterThan(1));
      expect(smart.resultAt(21)?.reachable, false);
      expect(smart.resultAt(22)?.lastMs, 278);
      expect(smart.recommendedIndex, 22);
      expect(smart.sortedIndices.first, 22);
      expect(proxy.active, false);
      expect(core.isListening, false);
      expect(sub.selectedIndex, 0);
    } finally {
      smart.dispose(); link.dispose(); sub.dispose();
      core.dispose(); proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('stop full scan cancels queued tasks and leaves partial results',
      () async {
    final (folder, core, sub, proxy, link) = await setup(count: 17);
    final probe = _GatedProbe();
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link, probe: probe,
    );
    try {
      final pending = smart.testAllNodes();
      expect(smart.scanning, true);
      expect(probe.started, 2);
      expect(smart.canTestAll, false);
      smart.cancelScan();
      expect(smart.cancelling, true);
      probe.gate.complete();
      await pending;
      expect(smart.scanning, false);
      expect(probe.started, 2);
      expect(smart.scanned, 0);
      expect(smart.total, 17);
      expect(smart.status, contains('停止'));
      expect(proxy.active, false);
    } finally {
      smart.dispose(); link.dispose(); sub.dispose();
      core.dispose(); proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('one click can benchmark while connected without changing selection',
      () async {
    final (folder, core, sub, proxy, link) = await setup(count: 9);
    final probe = _LimitedProbe();
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link, probe: probe,
    );
    try {
      expect(await link.connect(), true);
      smart.setAutoPick(true);
      expect(smart.canTestAll, true);
      expect(smart.safeToSelect, false);
      await smart.testAllNodes();
      expect(smart.scanned, 9);
      expect(smart.canRecommend, false);
      expect(sub.selectedIndex, 0);
      expect(link.connected, true);
      expect(proxy.active, true);
      expect(core.isListening, true);
      expect(await link.disconnect(), true);
    } finally {
      smart.dispose(); link.dispose(); sub.dispose();
      core.dispose(); proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('empty subscription or repeated full-scan click is harmless',
      () async {
    final (folder, core, sub, proxy, link) = await setup(count: 4);
    final probe = _GatedProbe();
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link, probe: probe,
    );
    try {
      final first = smart.testAllNodes();
      await smart.testAllNodes();
      expect(probe.started, 2);
      smart.cancelScan();
      probe.gate.complete();
      await first;
      expect(probe.started, 2);
    } finally {
      smart.dispose(); link.dispose(); sub.dispose();
      core.dispose(); proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('selected-node download sample stores measured Mbps separately',
      () async {
    final (folder, core, sub, proxy, link) = await setup(count: 3);
    final speed = _SpeedProbe();
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link,
      probe: _Probe(), downloadProbe: speed,
    );
    try {
      expect(smart.canTestSelectedDownload, true);
      expect(await smart.testSelectedDownload(), true);
      expect(speed.tested, ['Node-0']);
      expect(smart.downloadAt(0)?.mbps, 65.4);
      expect(proxy.active, false);
      expect(core.isListening, false);

      expect(await sub.selectNode(1), true);
      speed.succeeds = false;
      expect(await smart.testSelectedDownload(), false);
      expect(speed.tested, ['Node-0', 'Node-1']);
      expect(smart.downloadAt(1)?.mbps, null);
      expect(smart.downloadAt(0)?.mbps, 65.4);
      expect(smart.downloadStatus, contains('失败'));
    } finally {
      smart.dispose(); link.dispose(); sub.dispose();
      core.dispose(); proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('download probe can run while proxy connected without changing it',
      () async {
    final (folder, core, sub, proxy, link) = await setup(count: 2);
    final speed = _SpeedProbe();
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link,
      probe: _Probe(), downloadProbe: speed,
    );
    try {
      expect(await link.connect(), true);
      expect(await smart.testSelectedDownload(), true);
      expect(link.connected, true);
      expect(proxy.active, true);
      expect(core.isListening, true);
      expect(sub.selectedIndex, 0);
      expect(await link.disconnect(), true);
    } finally {
      smart.dispose(); link.dispose(); sub.dispose();
      core.dispose(); proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('periodic health checks default off and skip connected sessions',
      () async {
    final (folder, core, sub, proxy, link) = await setup(count: 3);
    final probe = _Probe();
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link, probe: probe,
      periodicInterval: (_) => const Duration(milliseconds: 25),
    );
    try {
      expect(smart.scheduledMinutes, 0);
      smart.setScheduledMinutes(7); // Unsupported value must be ignored.
      expect(smart.scheduledMinutes, 0);
      smart.setScheduledMinutes(15);
      await Future<void>.delayed(const Duration(milliseconds: 110));
      expect(probe.measured, isNotEmpty);
      while (smart.scanning) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(await link.connect(), true);
      final checked = probe.measured.length;
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(probe.measured.length, checked);
      expect(link.connected, true);
      smart.setScheduledMinutes(0);
      expect(smart.scheduledMinutes, 0);
      expect(await link.disconnect(), true);
    } finally {
      smart.dispose(); link.dispose(); sub.dispose();
      core.dispose(); proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('download CDN failure does not mark valid FlClash delay failed',
      () async {
    final (folder, core, sub, proxy, link) = await setup(count: 3);
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link,
      probe: _Probe(), fullProbe: _DownloadBlockedProbe(),
    );
    try {
      await smart.testAllNodes();
      expect(smart.scanned, 3);
      expect(smart.successful, 3);
      expect(smart.failed, 0);
      expect(smart.resultAt(1)?.lastMs, 96);
      expect(smart.downloadAt(1)?.ok, false);
      expect(smart.status, contains('下载成功 0'));
    } finally {
      smart.dispose();
      link.dispose();
      sub.dispose();
      core.dispose();
      proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('single action measures download and latency for every node, speed-first',
      () async {
    final (folder, core, sub, proxy, link) = await setup(count: 5);
    final both = _BothProbe();
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link, probe: _Probe(),
      fullProbe: both, downloadProbe: _SpeedProbe(),
    );
    try {
      await smart.testAllNodes();
      expect(both.names.length, 5);
      expect(smart.scanned, 5);
      expect(smart.successful, 5);
      expect(smart.resultAt(1)!.lastMs, 150);
      expect(smart.downloadAt(1)!.megabytesPerSecond, 11);
      expect(smart.sortedIndices.first, 1); // Speed wins over latency.
      expect(smart.recommendedIndex, 1);
      expect(smart.canRecommend, true); // 88 vs 20 Mbps: >20%.
      expect(await smart.useRecommended(), true);
      expect(sub.selectedIndex, 1);
      expect(smart.manualHold, false); // Own AI choice isn't manual.
      expect(proxy.active, false);
      expect(core.isListening, false);
    } finally {
      smart.dispose(); link.dispose(); sub.dispose();
      core.dispose(); proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('manual node switching pauses smart selection until explicit resume',
      () async {
    final (folder, core, sub, proxy, link) = await setup(count: 5);
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link,
      probe: _Probe(), fullProbe: _BothProbe(),
    );
    try {
      await smart.testAllNodes();
      expect(await sub.selectNode(3), true);
      expect(smart.manualHold, true);
      expect(smart.canRecommend, false);
      smart.resumeAutoSelection();
      expect(smart.manualHold, false);
      expect(smart.canRecommend, true);
    } finally {
      smart.dispose(); link.dispose(); sub.dispose();
      core.dispose(); proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('AI country name matcher never matches incidental "us" in Russia',
      () {
    expect(velaSmartCountryMatches('🇯🇵 Tokyo-01', 'JP'), true);
    expect(velaSmartCountryMatches('Hong Kong 02', 'HK'), true);
    expect(velaSmartCountryMatches('US-California', 'US'), true);
    expect(velaSmartCountryMatches('Russia-01', 'US'), false);
    expect(velaSmartCountryMatches('日本 东京', 'JP'), true);
    expect(velaSmartCountryMatches('Germany Frankfurt', 'DE'), true);
  });

  test('latency progress uses Vela branding and keeps native measurements',
      () async {
    final (folder, core, sub, proxy, link) = await setup(count: 3);
    final probe = _BatchProbe();
    final smart = VelaSmartController(
      core: core, subscription: sub, connection: link, probe: probe,
    );
    try {
      await smart.testAllLatencies();
      expect(smart.status, contains('Vela 延迟测试完成'));
      expect(smart.status, isNot(contains('FlClash')));
      expect(smart.scanned, 3);
      expect(smart.successful, 2);
    } finally {
      smart.dispose();
      link.dispose();
      sub.dispose();
      core.dispose();
      proxy.dispose();
      await folder.delete(recursive: true);
    }
  });

}
