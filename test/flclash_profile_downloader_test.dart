import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/subscription/flclash_profile_downloader.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_controller.dart';

FlClashProfileResponse reply(int code, String text, {String? redirect}) =>
    FlClashProfileResponse(code, Uint8List.fromList(utf8.encode(text)),
        redirect: redirect);

void main() {
  test('Dio-compatible profile import follows HTTPS redirect while preserving proxy route', () async {
    final visits = <String>[];
    final fetcher = FlClashProfileDownloader(
      proxyLookup: () async => 'PROXY 127.0.0.1:7890',
      discoverProxy: () async => null,
      requestStep: (uri, route) async {
        visits.add('${uri.path}|$route');
        if (uri.path == '/subscribe') {
          return reply(302, '', redirect: '/config.yaml');
        }
        return reply(200, 'proxies:\n  - name: Japan\n    type: ss');
      },
    );
    final body = await fetcher.download('https://subscription.example/subscribe?token=sensitive');
    expect(body, contains('proxies:'));
    expect(visits, [
      '/subscribe|PROXY 127.0.0.1:7890',
      '/config.yaml|PROXY 127.0.0.1:7890',
    ]);
  });

  test('automatic route retries through FlClash-compatible proxy then DIRECT', () async {
    final visits = <String>[];
    final fetcher = FlClashProfileDownloader(
      proxyLookup: () async => 'PROXY 127.0.0.1:7890',
      discoverProxy: () async => 'PROXY 127.0.0.1:7897',
      requestStep: (_, route) async {
        visits.add(route);
        if (route != 'DIRECT') throw TimeoutException('request timeout');
        return reply(200, 'proxies: []');
      },
    );
    expect(await fetcher.download('https://example.org/subscribe'), 'proxies: []');
    expect(visits, [
      'PROXY 127.0.0.1:7890',
      'PROXY 127.0.0.1:7897',
      'DIRECT',
    ]);
  });

  test('never leak subscription token to HTTP redirect or a local endpoint', () async {
    for (final redirect in [
      'http://subscription.example/final',
      'https://127.0.0.1/admin',
      'https://localhost:7890/api',
    ]) {
      final visits = <Uri>[];
      final fetcher = FlClashProfileDownloader(
        mode: VelaSubscriptionDownloadMode.direct,
        requestStep: (uri, _) async {
          visits.add(uri);
          return reply(302, '', redirect: redirect);
        },
      );
      await expectLater(
        fetcher.download('https://subscription.example/sub?token=private'),
        throwsFormatException,
      );
      expect(visits.length, 1);
    }
  });

  test('manual proxy mode uses only explicitly selected local HTTP port', () async {
    final fetcher = FlClashProfileDownloader(
      mode: VelaSubscriptionDownloadMode.localHttp,
      localHttpProxyPort: 7897,
      requestStep: (_, route) async {
        expect(route, 'PROXY 127.0.0.1:7897');
        return reply(200, 'ok');
      },
    );
    expect(await fetcher.download('https://example.net/sub'), 'ok');
  });
}
