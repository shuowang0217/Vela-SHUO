import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/network/flclash_core_api.dart';
import 'package:vela_shuo/src/network/flclash_windows_backend.dart';

class _GoCoreFake implements FlClashCoreTransport {
  final methods = <String>[];
  String? active;
  bool started = false;

  @override
  Future<String?> invoke(String input) async {
    final data = jsonDecode(input) as Map<String, dynamic>;
    final method = data['method'] as String;
    methods.add(method);
    Object? result;
    switch (method) {
      case 'initClash':
        result = true;
      case 'velaLoadProfile':
        result = {
          'groups': ['VELA_SELECT', 'GLOBAL'],
          'provider-count': 1,
          'raw-proxies': [
            {'name': 'JP-VLESS', 'type': 'vless',
             'server': 'jp.example.test', 'port': 443, 'network': 'grpc'},
          ],
          'proxies': {
            'VELA_SELECT': {'type': 'Selector'},
            'GLOBAL': {'type': 'Selector'},
            'JP-VLESS': {'type': 'VLESS'},
            'US-TUIC': {'type': 'TUIC'},
            'DIRECT': {'type': 'Direct'},
          },
        };
      case 'changeProxy':
        active = (data['arguments'] as Map)['proxy-name'] as String;
        result = {'message': '', 'changed': true};
      case 'startListener':
        started = true;
        result = true;
      case 'stopListener':
        started = false;
        result = true;
      case 'probe':
        result = {'status-code': 204, 'error': ''};
      case 'asyncTestDelay':
        result = {'name': 'JP-VLESS', 'value': 126, 'url': 'https://example.org'};
      case 'getTotalTraffic':
        result = {'up': 214, 'down': 897};
      case 'shutdown':
        result = true;
      default:
        throw StateError('Unexpected call: $method');
    }
    return jsonEncode({'id': data['id'], 'result': result});
  }
}

void main() {
  test('Vela import/selection/connection runs through FlClash Core only',
      () async {
    final dir = await Directory.systemTemp.createTemp('flclash_backend_');
    addTearDown(() => dir.delete(recursive: true));
    final fake = _GoCoreFake();
    final backend = FlClashWindowsBackend(
        transport: fake, homeDir: dir.path);
    await backend.initialize();
    const raw = '''
proxy-providers:
  Remote:
    type: http
    url: https://subscription.example/full.yaml
''';
    final nodes = await backend.importText(raw);
    expect(nodes.map((n) => n.name), containsAll(['JP-VLESS', 'US-TUIC']));
    expect(nodes.any((n) => n.name == 'DIRECT'), isFalse);
    expect(nodes.firstWhere((n) => n.name == 'JP-VLESS').server,
        'jp.example.test');
    expect(backend.groups, contains('VELA_SELECT'));
    expect(await backend.selectNode('US-TUIC'), true);
    expect(backend.activeName, 'US-TUIC');
    await backend.start();
    expect(backend.listenerStarted, true);
    expect(await backend.verifyInternet(), true);
    expect(await backend.delay('JP-VLESS'), 126);
    expect(await backend.traffic(), (214, 897));
    await backend.stop();
    expect(fake.started, false);
    await backend.shutdown();
    expect(fake.methods, containsAll([
      'initClash', 'velaLoadProfile', 'changeProxy',
      'startListener', 'probe', 'asyncTestDelay',
      'getTotalTraffic', 'stopListener', 'shutdown',
    ]));
    expect(fake.methods, isNot(contains('VelaSubscriptionParser')));
  });
}
