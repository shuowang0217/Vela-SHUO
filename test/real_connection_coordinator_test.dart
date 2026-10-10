// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/vela_connection_coordinator.dart';
import 'package:vela_shuo/src/core/vela_core_controller.dart';
import 'package:vela_shuo/src/core/vela_system_proxy.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_controller.dart';

class _Handle implements VelaCoreHandle {
  final complete = Completer<int>();
  @override
  Future<int> get exitCode => complete.future;
  @override
  void kill() {
    if (!complete.isCompleted) complete.complete(-1);
  }
  void crash() {
    if (!complete.isCompleted) complete.complete(1);
  }
}

class _Runner implements VelaCoreRunner {
  final handles = <_Handle>[];
  @override
  Future<void> check(String executable, String config) async {}
  @override
  Future<void> assertPortFree(int port) async {}
  @override
  Future<bool> awaitLocalListener(int port) async => true;
  @override
  Future<VelaCoreHandle> launch(String executable, String config) async {
    final handle = _Handle();
    handles.add(handle);
    return handle;
  }
}
class _GatedProbe implements VelaRemoteProbe {
  final Completer<void> entered = Completer<void>();
  final Completer<bool> answer = Completer<bool>();
  @override
  Future<bool> verify(int localPort) {
    if (!entered.isCompleted) entered.complete();
    return answer.future;
  }
}

class _Probe implements VelaRemoteProbe {
  _Probe(this.answer);
  bool answer;
  @override
  Future<bool> verify(int localPort) async => answer;
}
class _Fetch implements VelaSubscriptionFetcher {
  @override
  Future<String> download(String url) async => '''
proxies:
  - name: "Japan 01"
    type: ss
    server: jp.example.test
    port: 443
    cipher: aes-128-gcm
    password: dummy-secret
''';
}
class _Backend implements VelaWindowsProxyBackend {
  bool blockRestore = false;
  VelaProxySnapshot state = const VelaProxySnapshot(
      enabled: 1, server: '127.0.0.1:7890');
  @override
  Future<VelaProxySnapshot> read() async => state;
  @override
  Future<bool> hasPac() async => false;
  @override
  Future<void> write(VelaProxySnapshot next) async {
    if (blockRestore && next.server == '127.0.0.1:7890') {
      throw StateError('simulated Windows registry write failure');
    }
    state = next;
  }
  @override
  Future<void> refresh() async {}
}

Future<(VelaConnectionCoordinator, Directory, _Runner, _Probe, _Backend,
    VelaSubscriptionController, VelaCoreController, VelaSystemProxyManager)>
    _setup({VelaRemoteProbe? remoteProbe}) async {
  final dir = await Directory.systemTemp.createTemp('vela_real_conn_');
  final exe = File(dir.path + '/mihomo.exe');
  await exe.writeAsString('dummy');
  final runner = _Runner();
  final probe = _Probe(true);
  final core = VelaCoreController(
    supported: true, runner: runner, remoteProbe: remoteProbe ?? probe,
    managedProfileDirectory: dir,
  );
  await core.chooseBinary(exe.path);
  final sub = VelaSubscriptionController(core: core, fetcher: _Fetch());
  expect(await sub.importFromUrl('https://example.test'), isTrue);
  expect(await sub.selectNode(0), isTrue);
  final backend = _Backend();
  final proxy = VelaSystemProxyManager(
    backend: backend, stateDirectory: dir, supported: true,
  );
  final connection = VelaConnectionCoordinator(
    core: core, subscription: sub, proxy: proxy,
  );
  return (connection, dir, runner, probe, backend, sub, core, proxy);
}

void main() {
  test('real connect requires remote probe before Windows proxy takeover',
      () async {
    final (connection, dir, runner, probe, backend, sub, core, proxy) =
        await _setup();
    try {
      probe.answer = false;
      expect(await connection.connect(), isFalse);
      expect(connection.connected, isFalse);
      expect(proxy.active, isFalse);
      expect(core.isListening, isFalse);
      expect(backend.state.server, '127.0.0.1:7890');
      probe.answer = true;
      expect(await connection.connect(), isTrue);
      expect(connection.connected, isTrue);
      expect(proxy.active, isTrue);
      expect(backend.state.server, '127.0.0.1:20808');
      expect(await connection.disconnect(), isTrue);
      expect(connection.phase, VelaRealPhase.idle);
      expect(proxy.active, isFalse);
      expect(core.isListening, isFalse);
      expect(backend.state.server, '127.0.0.1:7890');
      expect(runner.handles.length, 2);
    } finally {
      connection.dispose();
      sub.dispose();
      core.dispose();
      proxy.dispose();
      await dir.delete(recursive: true);
    }
  });

  test('unexpected core exit recovers the previous system proxy', () async {
    final (connection, dir, runner, probe, backend, sub, core, proxy) =
        await _setup();
    try {
      expect(await connection.connect(), isTrue);
      runner.handles.last.crash();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(proxy.active, isFalse);
      expect(backend.state.server, '127.0.0.1:7890');
      expect(connection.phase, VelaRealPhase.error);
    } finally {
      connection.dispose();
      sub.dispose();
      core.dispose();
      proxy.dispose();
      await dir.delete(recursive: true);
    }
  });
  test('window-close shutdown restores proxy before ending Mihomo', () async {
    final (connection, dir, runner, probe, backend, sub, core, proxy) =
        await _setup();
    try {
      expect(await connection.connect(), isTrue);
      expect(await connection.shutdown(), isTrue);
      expect(proxy.active, isFalse);
      expect(core.isListening, isFalse);
      expect(backend.state.server, '127.0.0.1:7890');
      expect(await connection.connect(), isFalse);
      expect(runner.handles.single.complete.isCompleted, isTrue);
    } finally {
      connection.dispose();
      sub.dispose();
      core.dispose();
      proxy.dispose();
      await dir.delete(recursive: true);
    }
  });

  test('close request waits for an in-flight connect to finish safely',
      () async {
    final gated = _GatedProbe();
    final (connection, dir, runner, probe, backend, sub, core, proxy) =
        await _setup(remoteProbe: gated);
    try {
      final connecting = connection.connect();
      await gated.entered.future;
      final closing = connection.shutdown();
      var finished = false;
      closing.then((_) { finished = true; });
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(finished, false);
      gated.answer.complete(true);
      expect(await connecting, true);
      expect(await closing, true);
      expect(proxy.active, false);
      expect(core.isListening, false);
      expect(backend.state.server, '127.0.0.1:7890');
    } finally {
      connection.dispose();
      sub.dispose();
      core.dispose();
      proxy.dispose();
      await dir.delete(recursive: true);
    }
  });

  test('failed Windows proxy restoration blocks shutdown and supports retry',
      () async {
    final (connection, dir, runner, probe, backend, sub, core, proxy) =
        await _setup();
    try {
      expect(await connection.connect(), true);
      backend.blockRestore = true;
      expect(await connection.shutdown(), false);
      expect(core.isListening, true);
      expect(proxy.active, true);
      expect(backend.state.server, '127.0.0.1:20808');
      backend.blockRestore = false;
      expect(await connection.shutdown(), true);
      expect(core.isListening, false);
      expect(backend.state.server, '127.0.0.1:7890');
    } finally {
      connection.dispose();
      sub.dispose();
      core.dispose();
      proxy.dispose();
      await dir.delete(recursive: true);
    }
  });

}
