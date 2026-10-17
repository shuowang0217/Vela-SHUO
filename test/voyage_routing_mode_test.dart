import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vela_shuo/src/network/flclash_core_api.dart';
import 'package:vela_shuo/src/network/flclash_windows_backend.dart';
import 'package:vela_shuo/src/network/vela_routing_mode.dart';

class _RoutingTransport implements FlClashCoreTransport {
  final modes = <String>[];
  bool reject = false;

  @override
  Future<String?> invoke(String requestJson) async {
    final request = jsonDecode(requestJson) as Map<String, dynamic>;
    if (request['method'] != 'updateConfig') {
      throw StateError('Unexpected native method');
    }
    final args = request['arguments'] as Map<String, dynamic>;
    modes.add(args['mode'] as String);
    return jsonEncode({
      'id': request['id'],
      'result': reject ? 'native rejected' : '',
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native mode switching uses updateConfig, not a cosmetic toggle',
      () async {
    SharedPreferences.setMockInitialValues({});
    final transport = _RoutingTransport();
    final directory = await Directory.systemTemp.createTemp('voyage_mode_');
    addTearDown(() => directory.delete(recursive: true));
    final backend = FlClashWindowsBackend(
        homeDir: directory.path, transport: transport);
    backend.imported = true;
    final modes = VelaRoutingModeController(backend);
    await modes.restore();
    expect(await modes.setMode(VelaRoutingMode.rule, 'airport-a'), true);
    expect(transport.modes, ['rule']);
    expect(modes.current, VelaRoutingMode.rule);
    expect(await modes.setMode(VelaRoutingMode.direct, 'airport-a'), true);
    expect(transport.modes, ['rule', 'direct']);
    final saved = await SharedPreferences.getInstance();
    expect(saved.getString(VelaRoutingModeController.preferenceKey), 'direct');
    modes.dispose();
  });

  test('rejected native response never changes selected mode', () async {
    SharedPreferences.setMockInitialValues({});
    final transport = _RoutingTransport();
    transport.reject = true;
    final directory = await Directory.systemTemp.createTemp('voyage_reject_');
    addTearDown(() => directory.delete(recursive: true));
    final backend = FlClashWindowsBackend(
        homeDir: directory.path, transport: transport);
    backend.imported = true;
    final modes = VelaRoutingModeController(backend);
    await modes.restore();
    expect(await modes.setMode(VelaRoutingMode.direct, 'airport-a'), false);
    expect(modes.current, VelaRoutingMode.rule);
    expect(modes.error, contains('保留原模式'));
    modes.dispose();
  });

  test('reapplying an imported airport preserves the selected core mode',
      () async {
    SharedPreferences.setMockInitialValues({
      VelaRoutingModeController.preferenceKey: 'rule',
    });
    final transport = _RoutingTransport();
    final directory = await Directory.systemTemp.createTemp('voyage_restore_');
    addTearDown(() => directory.delete(recursive: true));
    final backend = FlClashWindowsBackend(
        homeDir: directory.path, transport: transport);
    backend.imported = true;
    final modes = VelaRoutingModeController(backend);
    await modes.restore();
    expect(await modes.synchronize('airport-a'), true);
    expect(await modes.synchronize('airport-a'), true);
    expect(await modes.synchronize('airport-b'), true);
    expect(transport.modes, ['rule']);
    backend.profileRevision++;
    expect(await modes.synchronize('airport-b'), true);
    expect(transport.modes, ['rule', 'rule']);
    modes.invalidateAfterVpnStart();
    expect(await modes.synchronize('airport-b'), true);
    expect(transport.modes, ['rule', 'rule', 'rule']);
    modes.dispose();
  });
}
