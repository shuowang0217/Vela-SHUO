import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_controller.dart';

InternetAddress _ip(String raw) => InternetAddress(raw);

void main() {
  test('Fake-IP from Mihomo is accepted without trusting any LAN IP', () {
    expect(VelaHttpsSubscriptionFetcher.isFakeIp(_ip('198.18.1.32')), true);
    expect(VelaHttpsSubscriptionFetcher.isFakeIp(_ip('198.19.254.1')), true);
    expect(VelaHttpsSubscriptionFetcher.isPublicIp(_ip('198.18.1.32')), false);
    expect(VelaHttpsSubscriptionFetcher.isPublicIp(_ip('8.8.8.8')), true);
    final safe = VelaHttpsSubscriptionFetcher.checkedAddresses([
      _ip('192.168.0.3'), _ip('198.18.20.30'), _ip('8.8.8.8'),
      _ip('127.0.0.1'), _ip('8.8.8.8'), _ip('10.0.0.1'),
    ]);
    expect(safe.map((ip) => ip.address).toList(),
        ['8.8.8.8', '198.18.20.30']);
  });

  test('private-only, loopback and non-global destinations remain rejected', () {
    for (final raw in [
      '127.0.0.1', '10.0.1.1', '172.17.1.1', '192.168.8.1',
      '169.254.0.4', '100.64.2.1', '0.0.0.0', '::1',
      'fc00::1', 'fe80::a', '192.0.2.1', '203.0.113.7',
    ]) {
      expect(
        () => VelaHttpsSubscriptionFetcher.checkedAddresses([_ip(raw)]),
        throwsFormatException,
        reason: raw,
      );
    }
  });

  test('local HTTP proxy resolves subscription without a DNS preflight',
      () async {
    var dnsQueries = 0;
    final fetcher = VelaHttpsSubscriptionFetcher(
      mode: VelaSubscriptionDownloadMode.systemProxy,
      proxyLookup: () async => 'PROXY 127.0.0.1:7890',
      dnsLookup: (_) async {
        dnsQueries++;
        return [_ip('10.0.0.9')];
      },
      fetchTransport: (uri, route) async {
        expect(route, 'PROXY 127.0.0.1:7890');
        expect(uri.host, 'subscribe.example.com');
        return 'proxies: []';
      },
    );
    expect(await fetcher.download('https://subscribe.example.com/sub'),
        'proxies: []');
    expect(dnsQueries, 0);
  });

  test('direct mode can use checked Mihomo Fake-IP DNS results', () async {
    var attempts = 0;
    final fetcher = VelaHttpsSubscriptionFetcher(
      mode: VelaSubscriptionDownloadMode.direct,
      dnsLookup: (_) async => [_ip('198.18.1.20')],
      fetchTransport: (uri, route) async {
        attempts++;
        expect(route, 'DIRECT');
        expect(uri.scheme, 'https');
        return 'proxies: []';
      },
    );
    expect(await fetcher.download('https://subscribe.example.com/sub'),
        'proxies: []');
    expect(attempts, 1);
  });

  test('system DNS private-only addresses trigger pinned safe DoH', () async {
    var secureCalls = 0;
    final fetcher = VelaHttpsSubscriptionFetcher(
      mode: VelaSubscriptionDownloadMode.direct,
      dnsLookup: (_) async => [_ip('10.10.1.2')],
      secureDnsLookup: (_) async {
        secureCalls++;
        return [_ip('1.1.1.1')];
      },
      fetchTransport: (_, route) async {
        expect(route, 'DIRECT');
        return 'proxies: []';
      },
    );
    expect(await fetcher.download('https://subscribe.example.com/sub'),
        'proxies: []');
    expect(secureCalls, 1);
  });

  test('private DNS and DoH private answers never authorize a socket',
      () async {
    var attempts = 0;
    final fetcher = VelaHttpsSubscriptionFetcher(
      mode: VelaSubscriptionDownloadMode.direct,
      dnsLookup: (_) async => [_ip('192.168.1.8'), _ip('127.0.0.1')],
      secureDnsLookup: (_) async => [_ip('10.42.0.2')],
      fetchTransport: (uri, route) async {
        attempts++;
        return 'unsafe';
      },
    );
    await expectLater(
        fetcher.download('https://subscribe.example.com/private'),
        throwsFormatException);
    expect(attempts, 0);
  });

  test('direct mode blocks private-only DNS before any transport', () async {
    var attempts = 0;
    final fetcher = VelaHttpsSubscriptionFetcher(
      mode: VelaSubscriptionDownloadMode.direct,
      dnsLookup: (_) async => [_ip('192.168.1.8'), _ip('127.0.0.1')],
      secureDnsLookup: (_) async => [],
      fetchTransport: (uri, route) async {
        attempts++;
        return 'unsafe';
      },
    );
    await expectLater(
        fetcher.download('https://subscribe.example.com/private'),
        throwsFormatException);
    expect(attempts, 0);
  });

  test('proxy failure retries checked direct route, not insecure DNS', () async {
    final attempts = <String>[];
    final fetcher = VelaHttpsSubscriptionFetcher(
      mode: VelaSubscriptionDownloadMode.automatic,
      proxyLookup: () async => 'PROXY 127.0.0.1:7890',
      dnsLookup: (_) async => [_ip('198.18.99.123')],
      fetchTransport: (_, route) async {
        attempts.add(route);
        if (route.startsWith('PROXY')) throw TimeoutException('unreachable');
        return 'ok';
      },
    );
    expect(await fetcher.download('https://provider.example.com/config'),
        'ok');
    expect(attempts, ['PROXY 127.0.0.1:7890', 'DIRECT']);
  });
}
