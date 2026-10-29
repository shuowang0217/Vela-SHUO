import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/network/flclash_core_api.dart';
import 'package:vela_shuo/src/network/vela_layered_connectivity.dart';

class _UnusedTransport implements FlClashCoreTransport {
  @override
  Future<String?> invoke(String requestJson) async => null;
}

void main() {
  test('DNS and native HTTPS are separate success checks', () async {
    final probe = VelaLayeredConnectivityProbe(
      api: FlClashCoreApi(_UnusedTransport()),
      dnsLookup: (hostname) async {
        expect(hostname, 'example.com');
        return [InternetAddress('93.184.215.14')];
      },
      httpsProbe: (url, proxy) async {
        expect(proxy, '');
        expect(url, startsWith('https://'));
        return {'status-code': 204, 'error': null};
      },
    );
    final report = await probe.run();
    expect(report.dnsOk, isTrue);
    expect(report.httpsOk, isTrue);
    expect(report.dnsDetail, contains('不代表代理 DNS'));
  });

  test('valid OS DNS does not hide proxy HTTPS failures', () async {
    final probe = VelaLayeredConnectivityProbe(
      api: FlClashCoreApi(_UnusedTransport()),
      dnsLookup: (_) async => [InternetAddress('1.1.1.1')],
      httpsProbe: (_, _) async => {
        'status-code': 0, 'error': 'timeout',
      },
    );
    final report = await probe.run();
    expect(report.dnsOk, isTrue);
    expect(report.httpsOk, isFalse);
    expect(report.httpsDetail, contains('超时'));
  });

  test('native HTTPS success does not misrepresent OS DNS errors', () async {
    final probe = VelaLayeredConnectivityProbe(
      api: FlClashCoreApi(_UnusedTransport()),
      dnsLookup: (_) async => throw const SocketException('unavailable'),
      httpsProbe: (_, _) async => {'status-code': 200},
    );
    final report = await probe.run();
    expect(report.dnsOk, isFalse);
    expect(report.httpsOk, isTrue);
  });
}
