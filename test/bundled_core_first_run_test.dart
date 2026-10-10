import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/vela_core_controller.dart';

void main() {
  test('first run discovers the bundled binary and prepares direct profile',
      () async {
    final sandbox = await Directory.systemTemp.createTemp('vela_first_run_');
    addTearDown(() => sandbox.delete(recursive: true));
    final exe = File('${sandbox.path}/sing-box.exe');
    await exe.writeAsString('dummy for test only');
    final profiles = Directory('${sandbox.path}/profiles');
    final core = VelaCoreController(
      supported: true,
      bundledCorePath: exe.path,
      managedProfileDirectory: profiles,
    );
    await core.initialize();
    expect(core.hasCore, isTrue);
    expect(core.usingBundledCore, isTrue);
    expect(core.hasConfig, isTrue);
    expect(core.directTestProfile, isTrue);
    expect(core.localAddress, '127.0.0.1:20808');
    expect(core.isListening, isFalse); // absolutely no auto-start
    final file = File('${profiles.path}/local-direct.json');
    final source = await file.readAsString();
    expect(source, contains('"type": "direct"'));
    expect(source, contains('"listen": "127.0.0.1"'));
    expect(source, isNot(contains('password')));
    expect(source, isNot(contains('server":')));
    // Reinitializing must not launch, change active state or download.
    await core.initialize();
    expect(core.phase, VelaCorePhase.idle);
    core.dispose();
  });

  test('missing packaged binary never claims to have a core', () async {
    final dir = await Directory.systemTemp.createTemp('vela_missing_core_');
    addTearDown(() => dir.delete(recursive: true));
    final controller = VelaCoreController(
      supported: true,
      bundledCorePath: '${dir.path}/missing/sing-box.exe',
      managedProfileDirectory: Directory('${dir.path}/profiles'),
    );
    await controller.initialize();
    expect(controller.hasCore, isFalse);
    expect(controller.hasConfig, isTrue);
    expect(await controller.start(), isFalse);
    expect(controller.isListening, isFalse);
    controller.dispose();
  });

  test('can rebuild local-direct test config without a subscription',
      () async {
    final dir = await Directory.systemTemp.createTemp('vela_direct_');
    addTearDown(() => dir.delete(recursive: true));
    final core = VelaCoreController(
      supported: true,
      managedProfileDirectory: dir,
    );
    expect(await core.useLocalDirectProfile(), isTrue);
    expect(core.directTestProfile, isTrue);
    expect(core.localPort, 20808);
    expect(core.hasConfig, isTrue);
    core.dispose();
  });
}
