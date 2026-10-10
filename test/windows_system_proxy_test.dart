import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/vela_system_proxy.dart';

class _FakeProxyBackend implements VelaWindowsProxyBackend {
  _FakeProxyBackend(this.current);
  VelaProxySnapshot current;
  bool pac = false;
  bool failWrite = false;
  bool failRestore = false;
  int refreshes = 0;
  final List<VelaProxySnapshot> writes = [];

  @override
  Future<VelaProxySnapshot> read() async => current;
  @override
  Future<bool> hasPac() async => pac;
  @override
  Future<void> write(VelaProxySnapshot snapshot) async {
    if (failWrite || (failRestore &&
        !snapshot.equals(VelaSystemProxyManager.managed))) {
      throw StateError('registry failure');
    }
    writes.add(snapshot);
    current = snapshot;
  }
  @override
  Future<void> refresh() async => refreshes++;
}

void main() {
  test('explicit takeover snapshots previous values and safely restores',
      () async {
    final dir = await Directory.systemTemp.createTemp('vela_win_proxy_');
    addTearDown(() => dir.delete(recursive: true));
    const old = VelaProxySnapshot(
      enabled: 1, server: '127.0.0.1:7890',
    );
    final backend = _FakeProxyBackend(old);
    final manager = VelaSystemProxyManager(
      backend: backend, stateDirectory: dir, supported: true,
    );
    expect(await manager.enable(), isTrue);
    expect(manager.active, isTrue);
    expect(backend.current.equals(VelaSystemProxyManager.managed), isTrue);
    expect(await File(dir.path + '/proxy-recovery.json').exists(), isTrue);
    expect(await manager.disable(), isTrue);
    expect(backend.current.equals(old), isTrue);
    expect(await File(dir.path + '/proxy-recovery.json').exists(), isFalse);
    manager.dispose();
  });

  test('crash restart restores only our previous manual proxy', () async {
    final dir = await Directory.systemTemp.createTemp('vela_crash_proxy_');
    addTearDown(() => dir.delete(recursive: true));
    const old = VelaProxySnapshot(enabled: 0, server: null);
    final backend = _FakeProxyBackend(old);
    final first = VelaSystemProxyManager(
      backend: backend, stateDirectory: dir, supported: true,
    );
    expect(await first.enable(), isTrue);
    first.dispose();
    final second = VelaSystemProxyManager(
      backend: backend, stateDirectory: dir, supported: true,
    );
    expect(await second.recover(), isTrue);
    expect(backend.current.equals(old), isTrue);
    expect(second.active, isFalse);
    second.dispose();
  });

  test('third-party proxy changes are never overwritten by recovery', () async {
    final dir = await Directory.systemTemp.createTemp('vela_conflict_');
    addTearDown(() => dir.delete(recursive: true));
    const old = VelaProxySnapshot(enabled: 0, server: null);
    final backend = _FakeProxyBackend(old);
    final manager = VelaSystemProxyManager(
      backend: backend, stateDirectory: dir, supported: true,
    );
    expect(await manager.enable(), isTrue);
    const thirdParty = VelaProxySnapshot(
      enabled: 1, server: '127.0.0.1:9999',
    );
    backend.current = thirdParty;
    expect(await manager.disable(), isTrue);
    expect(backend.current.equals(thirdParty), isTrue);
    manager.dispose();
  });

  test('PAC auto-configuration stops takeover without writing', () async {
    final dir = await Directory.systemTemp.createTemp('vela_pac_');
    addTearDown(() => dir.delete(recursive: true));
    final backend = _FakeProxyBackend(
        const VelaProxySnapshot(enabled: 0, server: null))..pac = true;
    final manager = VelaSystemProxyManager(
      backend: backend, stateDirectory: dir, supported: true,
    );
    expect(await manager.enable(), isFalse);
    expect(backend.writes, isEmpty);
    expect(manager.error, contains('PAC'));
    manager.dispose();
  });

  test('failed restoration leaves proxy enabled and journal intact',
      () async {
    final dir = await Directory.systemTemp.createTemp('vela_restore_fail_');
    addTearDown(() => dir.delete(recursive: true));
    final backend = _FakeProxyBackend(
        const VelaProxySnapshot(enabled: 0, server: null));
    final manager = VelaSystemProxyManager(
      backend: backend, stateDirectory: dir, supported: true,
    );
    expect(await manager.enable(), isTrue);
    backend.failRestore = true;
    expect(await manager.disable(), isFalse);
    expect(manager.active, isTrue);
    expect(await File(dir.path + '/proxy-recovery.json').exists(), isTrue);
    backend.failRestore = false;
    expect(await manager.disable(), isTrue);
    manager.dispose();
  });
}
