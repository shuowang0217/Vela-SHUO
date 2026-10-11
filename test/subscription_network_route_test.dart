import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_controller.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_parser.dart';
import 'package:vela_shuo/src/subscription/vela_windows_proxy_detector.dart';

void main() {
  test('Windows registry HTTP(S) proxy parses local single and per-protocol forms', () {
    const enabled = 'ProxyEnable    REG_DWORD    0x1';
    expect(
      VelaWindowsProxyDetector.parseRegistryOutput(
        enabled, 'ProxyServer    REG_SZ    127.0.0.1:7890',
      ),
      'PROXY 127.0.0.1:7890',
    );
    expect(
      VelaWindowsProxyDetector.parseRegistryOutput(
        enabled,
        'ProxyServer    REG_SZ    http=127.0.0.1:7890;https=localhost:7891;socks=127.0.0.1:7892',
      ),
      'PROXY 127.0.0.1:7891',
    );
    expect(
      VelaWindowsProxyDetector.parseRegistryOutput(
        'ProxyEnable REG_DWORD 0x0',
        'ProxyServer REG_SZ 127.0.0.1:7890',
      ),
      isNull,
    );
  });

  test('proxy parsing rejects remote, credentialed, SOCKS-only and own proxy', () {
    for (final config in [
      'socks=127.0.0.1:1080',
      'http=example.com:7890;https=example.com:7890',
      'user:pass@127.0.0.1:7890',
      '0.0.0.0:7890',
      '127.0.0.1:20808',
      'http://127.0.0.1:70000',
    ]) {
      expect(VelaWindowsProxyDetector.parseProxyServer(config), isNull,
          reason: 'unsafe proxy settings must not receive subscription tokens');
    }
  });

  test('automatic mode prefers local system proxy and falls back to direct', () async {
    final attempted = <String>[];
    final fetcher = VelaHttpsSubscriptionFetcher(
      proxyLookup: () async => 'PROXY 127.0.0.1:7890',
      dnsCheck: (_) async {},
      fetchTransport: (uri, route) async {
        attempted.add(route);
        expect(uri.scheme, 'https');
        if (route.startsWith('PROXY')) {
          throw TimeoutException('sensitive hostname should never be shown');
        }
        return 'proxies: []';
      },
    );
    expect(await fetcher.download(
        'https://example.com/sub?token=private-token'), 'proxies: []');
    expect(attempted, ['PROXY 127.0.0.1:7890', 'DIRECT']);
  });

  test('system-proxy-only mode never falls back or leaks URL', () async {
    final attempted = <String>[];
    final fetcher = VelaHttpsSubscriptionFetcher(
      mode: VelaSubscriptionDownloadMode.systemProxy,
      proxyLookup: () async => 'PROXY 127.0.0.1:7890',
      dnsCheck: (_) async {},
      fetchTransport: (_, route) async {
        attempted.add(route);
        throw TimeoutException('private-token');
      },
    );
    try {
      await fetcher.download('https://example.com/?token=private-token');
      fail('must reject failed transport');
    } on FormatException catch (e) {
      expect(e.message, isNot(contains('private-token')));
      expect(e.message, contains('本机系统代理'));
    }
    expect(attempted, ['PROXY 127.0.0.1:7890']);
  });

  test('local HTTP proxy environment values retain strict loopback guard', () {
    expect(VelaWindowsProxyDetector.parseProxyServer(
        'http://127.0.0.1:7897'), 'PROXY 127.0.0.1:7897');
    expect(VelaWindowsProxyDetector.parseProxyServer(
        'http://proxy.example.com:7897'), null);
    expect(VelaWindowsProxyDetector.parseProxyServer(
        'socks5://127.0.0.1:7897'), null);
  });

  test('explicit loopback HTTP port never uses system DNS or proxy registry',
      () async {
    var systemLookups = 0;
    var dnsLookups = 0;
    final fetcher = VelaHttpsSubscriptionFetcher(
      mode: VelaSubscriptionDownloadMode.localHttp,
      localHttpProxyPort: 7897,
      proxyLookup: () async {
        systemLookups++;
        return null;
      },
      dnsLookup: (_) async {
        dnsLookups++;
        return [InternetAddress('192.168.1.25')];
      },
      fetchTransport: (uri, route) async {
        expect(route, 'PROXY 127.0.0.1:7897');
        expect(uri.scheme, 'https');
        return 'subscription response';
      },
    );
    expect(await fetcher.download(
        'https://provider.example/sub?token=do-not-log'),
        'subscription response');
    expect(systemLookups, 0);
    expect(dnsLookups, 0);
  });

  test('invalid or Vela-owned local proxy port is rejected before token I/O',
      () async {
    for (final port in [null, 0, -1, 65536, 20808, 20819]) {
      var forwarded = false;
      final fetcher = VelaHttpsSubscriptionFetcher(
        mode: VelaSubscriptionDownloadMode.localHttp,
        localHttpProxyPort: port,
        fetchTransport: (_, route) async {
          forwarded = true;
          return 'unsafe';
        },
      );
      await expectLater(
          fetcher.download('https://provider.example/sub?token=secret'),
          throwsFormatException);
      expect(forwarded, false);
    }
  });

  test('direct mode bypasses Windows proxy lookup entirely', () async {
    var resolved = false;
    final fetcher = VelaHttpsSubscriptionFetcher(
      mode: VelaSubscriptionDownloadMode.direct,
      proxyLookup: () async {
        resolved = true;
        return 'PROXY 127.0.0.1:7890';
      },
      dnsCheck: (_) async {},
      fetchTransport: (_, route) async {
        expect(route, 'DIRECT');
        return 'ok';
      },
    );
    expect(await fetcher.download('https://example.com/sub'), 'ok');
    expect(resolved, isFalse);
  });

  test('unsupported share links report only safe protocol totals', () {
    const links = '''
vless://uuid@host-one.example:443?type=xhttp&security=tls#Secret-Name
tuic://uuid:password@host-two.example:443#Another-Secret
anytls://secret@host-three.example:443#Private
''';
    try {
      VelaSubscriptionParser.parse(links);
      fail('must reject all unsupported nodes');
    } on FormatException catch (e) {
      expect(e.message, contains('VLESS 1'));
      expect(e.message, contains('TUIC 1'));
      expect(e.message, contains('AnyTLS 1'));
      expect(e.message, isNot(contains('Secret-Name')));
      expect(e.message, isNot(contains('host-one.example')));
      expect(e.message, isNot(contains('password')));
    }
  });
}
