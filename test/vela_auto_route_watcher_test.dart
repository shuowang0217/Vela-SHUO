import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/network/flclash_core_api.dart';
import 'package:vela_shuo/src/network/vela_auto_route_watcher.dart';

class _ProxyTransport implements FlClashCoreTransport {
  Map<String, dynamic> states = {};
  @override
  Future<String?> invoke(String requestJson) async {
    final req = jsonDecode(requestJson) as Map;
    expect(req['method'], 'getProxies');
    return jsonEncode({'id': req['id'], 'result': states});
  }
}

void main() {
  test('resolves nested URLTest/Fallback selected native "now" chain', () {
    final states = <String, dynamic>{
      'GLOBAL': {'type': 'Selector', 'now': 'Auto'},
      'Auto': {'type': 'URLTest', 'now': 'JP-01',
          'all': ['JP-01', 'US-01']},
      'JP-01': {'type': 'Shadowsocks'},
    };
    expect(VelaAutoRouteWatcher.resolveNativeChain(states, 'GLOBAL'),
        'GLOBAL|Auto|JP-01');
    (states['Auto'] as Map)['now'] = 'US-01';
    expect(VelaAutoRouteWatcher.resolveNativeChain(states, 'GLOBAL'),
        'GLOBAL|Auto|US-01');
    expect(VelaAutoRouteWatcher.resolveNativeChain(states, 'missing'), isNull);
    (states['Auto'] as Map)['now'] = 'GLOBAL';
    expect(VelaAutoRouteWatcher.resolveNativeChain(states, 'GLOBAL'), isNull);
  });

  test('native watcher notices automatic member changes without user selection',
      () async {
    final transport = _ProxyTransport();
    transport.states = {
      'GLOBAL': {'type': 'Selector', 'now': 'Auto'},
      'Auto': {'type': 'Fallback', 'now': 'JP-01'},
      'JP-01': {'type': 'Shadowsocks'},
    };
    final watcher = VelaAutoRouteWatcher(
      api: FlClashCoreApi(transport),
      interval: const Duration(days: 1),
    );
    watcher.sync(true, 'GLOBAL');
    await Future<void>.delayed(Duration.zero);
    expect(watcher.signature, 'GLOBAL|Auto|JP-01');
    final previous = watcher.signature;
    await watcher.checkNow();
    expect(watcher.signature, previous);
    transport.states['Auto'] = {'type': 'Fallback', 'now': 'US-01'};
    transport.states['US-01'] = {'type': 'Shadowsocks'};
    await watcher.checkNow();
    expect(watcher.signature, 'GLOBAL|Auto|US-01');
    watcher.sync(false, '');
    expect(watcher.signature, isNull);
    watcher.dispose();
  });
}
