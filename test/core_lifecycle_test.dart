import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/vela_core_controller.dart';

const _config = '''
{
  "inbounds": [{"type":"mixed","listen":"127.0.0.1","listen_port":20808}],
  "outbounds": [{"type":"direct"}]
}''';

class _FakeHandle implements VelaCoreHandle {
  final Completer<int> stopped = Completer<int>();
  int killCount = 0;
  @override
  Future<int> get exitCode => stopped.future;
  @override
  void kill() {
    killCount++;
    if (!stopped.isCompleted) stopped.complete(-1);
  }
  void fail() {
    if (!stopped.isCompleted) stopped.complete(1);
  }
}

class _FakeRunner implements VelaCoreRunner {
  bool ready = true;
  bool preflightFails = false;
  bool checkFails = false;
  int checks = 0;
  int launches = 0;
  final List<_FakeHandle> handles = [];

  @override
  Future<void> check(String binary, String config) async {
    checks++;
    if (checkFails) throw const FormatException('内核配置自检未通过');
  }

  @override
  Future<void> assertPortFree(int port) async {
    if (preflightFails) throw const SocketException('port busy');
  }

  @override
  Future<VelaCoreHandle> launch(String binary, String config) async {
    launches++;
    final handle = _FakeHandle();
    handles.add(handle);
    return handle;
  }

  @override
  Future<bool> awaitLocalListener(int port) async => ready;
}

Future<(VelaCoreController, Directory)> _setup(_FakeRunner runner) async {
  final folder = await Directory.systemTemp.createTemp('vela_core_test_');
  final core = File('${folder.path}/sing-box.exe');
  final config = File('${folder.path}/profile.json');
  await core.writeAsString('fake-executable');
  await config.writeAsString(_config);
  final controller = VelaCoreController(runner: runner, supported: true);
  expect(await controller.chooseBinary(core.path), isTrue);
  expect(await controller.chooseConfig(config.path), isTrue);
  return (controller, folder);
}

void main() {
  test('localhost listener only becomes ready after core check and probe',
      () async {
    final runner = _FakeRunner();
    final (controller, folder) = await _setup(runner);
    try {
      expect(controller.phase, VelaCorePhase.idle);
      expect(await controller.start(), isTrue);
      expect(runner.checks, 1);
      expect(runner.launches, 1);
      expect(controller.phase, VelaCorePhase.listening);
      expect(controller.localAddress, '127.0.0.1:20808');

      await controller.stop();
      expect(controller.phase, VelaCorePhase.idle);
      expect(runner.handles.single.killCount, 1);
    } finally {
      controller.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('failed checks never launch a core process', () async {
    final runner = _FakeRunner()..checkFails = true;
    final (controller, folder) = await _setup(runner);
    try {
      expect(await controller.start(), isFalse);
      expect(controller.phase, VelaCorePhase.failed);
      expect(runner.launches, 0);
    } finally {
      controller.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('port collision and timeout never leave false ready state', () async {
    final runner = _FakeRunner()..preflightFails = true;
    final (controller, folder) = await _setup(runner);
    try {
      expect(await controller.start(), isFalse);
      expect(controller.phase, VelaCorePhase.failed);
      expect(runner.launches, 0);
      runner.preflightFails = false;
      runner.ready = false;
      expect(await controller.start(), isFalse);
      expect(controller.phase, VelaCorePhase.failed);
      expect(runner.handles.single.killCount, 1);
    } finally {
      controller.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('unexpected process death changes ready into failed', () async {
    final runner = _FakeRunner();
    final (controller, folder) = await _setup(runner);
    try {
      expect(await controller.start(), isTrue);
      runner.handles.single.fail();
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, VelaCorePhase.failed);
      expect(controller.isListening, isFalse);
    } finally {
      controller.dispose();
      await folder.delete(recursive: true);
    }
  });

  test('imports reject malformed files without retaining invalid port',
      () async {
    final runner = _FakeRunner();
    final (controller, folder) = await _setup(runner);
    try {
      final invalid = File('${folder.path}/invalid.json');
      await invalid.writeAsString(_config.replaceFirst('127.0.0.1', '0.0.0.0'));
      expect(await controller.chooseConfig(invalid.path), isFalse);
      expect(controller.phase, VelaCorePhase.failed);
      expect(controller.localPort, 20808);
      expect(await controller.start(), isTrue);
      await controller.stop();
    } finally {
      controller.dispose();
      await folder.delete(recursive: true);
    }
  });
}
