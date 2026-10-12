import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/network/flclash_core_api.dart';
import 'package:vela_shuo/src/network/flclash_windows_backend.dart';

class _GoCoreFake implements FlClashCoreTransport {
  final methods = <String>[];
  String? active;
  String? changedGroup;
  String? probedName;
  bool wrongRoute = false;
  bool primary204Blocked = false;
  bool blockEveryUrlTest = false;
  bool blockEveryProbe = false;
  final testedUrls = <String>[];
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
        changedGroup = (data['arguments'] as Map)['group-name'] as String;
        active = (data['arguments'] as Map)['proxy-name'] as String;
        result = {'message': '', 'changed': true};
      case 'getProxies':
        result = {
          'proxies': {
            'GLOBAL': {'type': 'Selector', 'now': active},
          },
          'all': ['GLOBAL', 'VELA_SELECT'],
        };
      case 'startListener':
        started = true;
        result = true;
      case 'stopListener':
        started = false;
        result = true;
      case 'probe':
        probedName = (data['arguments'] as Map)['proxy-name'] as String;
        result = {
          'status-code': blockEveryProbe ? 0 : 204,
          'delay': blockEveryProbe ? 0 : 184,
          'error': blockEveryProbe ? 'timeout' : '',
          'chains': [wrongRoute ? 'DIRECT' : active],
        };
      case 'asyncTestDelay':
        final params = data['arguments'] as Map;
        final url = params['test-url'] as String;
        testedUrls.add(url);
        expect(params['timeout'], 8000);
        result = {
          'name': params['proxy-name'],
          'value': blockEveryUrlTest ||
              (primary204Blocked && url.contains('gstatic.com'))
              ? -1 : 126,
          'url': url,
        };
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
    expect(backend.activeGroup, 'GLOBAL');
    expect(fake.changedGroup, 'GLOBAL');
    await backend.start();
    expect(backend.listenerStarted, true);
    expect(await backend.verifyInternet(), true);
    expect(fake.probedName, isEmpty,
        reason: 'Routing probe must not bypass Mihomo by naming a node');
    fake.wrongRoute = true;
    expect(await backend.verifyInternet(), false,
        reason: 'A DIRECT bypass must never be reported connected');
    fake.wrongRoute = false;
    expect(await backend.verifyInternet(), true);
    expect(await backend.delay('JP-VLESS'), 126);
    fake.blockEveryUrlTest = true;
    expect(await backend.delay('JP-VLESS'), 184,
        reason: 'Native FlClash probe must recover working nodes when URLTest fails');
    fake.blockEveryProbe = true;
    expect(await backend.delay('JP-VLESS'), isNull);
    expect(backend.delayFailureFor('JP-VLESS'), '节点响应超时');
    fake.blockEveryUrlTest = false;
    fake.blockEveryProbe = false;
    fake.primary204Blocked = true;
    expect(await backend.delay('JP-VLESS'), 126);
    expect(fake.testedUrls, containsAll([
      'https://www.gstatic.com/generate_204',
      'https://cp.cloudflare.com/generate_204',
    ]));
    expect(await backend.traffic(), (214, 897));
    await backend.stop();
    expect(fake.started, false);
    await backend.shutdown();
    expect(fake.methods, containsAll([
      'initClash', 'velaLoadProfile', 'changeProxy',
      'getProxies',
      'startListener', 'probe', 'asyncTestDelay',
      'getTotalTraffic', 'stopListener', 'shutdown',
    ]));
    expect(fake.methods, isNot(contains('VelaSubscriptionParser')));
  });
}
