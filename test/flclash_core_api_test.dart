import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/network/flclash_core_api.dart';

class _FakeTransport implements FlClashCoreTransport {
  _FakeTransport(this.handler);
  final Object? Function(Map<String, dynamic>) handler;
  @override
  Future<String?> invoke(String requestJson) async {
    final request = jsonDecode(requestJson) as Map<String, dynamic>;
    final result = handler(request);
    return jsonEncode({
      'id': request['id'],
      'result': result,
    });
  }
}

void main() {
  test('FlClash Core methods use upstream Go names and JSON arguments', () async {
    final calls = <Map<String, dynamic>>[];
    final api = FlClashCoreApi(_FakeTransport((call) {
      calls.add(call);
      return switch (call['method']) {
        'validateConfig' => '',
        'validateProxies' => ['', 'invalid proxy'],
        'getProxies' => <String, Object?>{'all': ['GLOBAL'], 'proxies': {}},
        'changeProxy' => <String, Object?>{'changed': true, 'message': ''},
        'asyncTestDelay' => <String, Object?>{'value': 163},
        'setupConfig' => '',
        _ => null,
      };
    }));
    expect(await api.validateConfig('safe.yaml'), '');
    expect(await api.validateProxies([{'type': 'tuic', 'name': 'JP'}]),
        ['', 'invalid proxy']);
    expect((await api.getProxies())['all'], ['GLOBAL']);
    expect(await api.changeProxy('GLOBAL', 'JP'), true);
    expect(await api.testDelay('JP', 'https://example.org/test'), 163);
    expect(await api.setupConfig(selectedMap: {'GLOBAL': 'JP'}), '');
    expect(calls.map((c) => c['method']), [
      'validateConfig', 'validateProxies', 'getProxies',
      'changeProxy', 'asyncTestDelay', 'setupConfig',
    ]);
    expect(calls[3]['arguments'], {
      'group-name': 'GLOBAL', 'proxy-name': 'JP',
    });
    expect(calls[4]['arguments']['test-url'], 'https://example.org/test');
    expect(calls[5]['arguments']['selected-map'], {'GLOBAL': 'JP'});
    expect(calls.map((c) => c['id']).toSet().length, calls.length);
  });

  test('core-provided failures are not silently converted to success', () async {
    final api = FlClashCoreApi(_FakeTransport((_) => null));
    await expectLater(api.getProxies(), throwsA(isA<FlClashCoreFailure>()));
    final failed = FlClashCoreApi(_ErrorTransport());
    await expectLater(failed.getProxies(),
        throwsA(isA<FlClashCoreFailure>()));
  });

  test('incorrect RPC response id is rejected', () async {
    final api = FlClashCoreApi(_WrongIdTransport());
    await expectLater(api.getProxies(),
        throwsA(isA<FlClashCoreFailure>()));
  });
}

class _ErrorTransport implements FlClashCoreTransport {
  @override
  Future<String?> invoke(String _) async => jsonEncode({
    'id': '1', 'error': {'code': 'not_implemented', 'message': 'unsupported'},
  });
}

class _WrongIdTransport implements FlClashCoreTransport {
  @override
  Future<String?> invoke(String _) async => jsonEncode({
    'id': 'different', 'result': {},
  });
}
