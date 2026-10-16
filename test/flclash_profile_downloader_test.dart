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
  test('FlClash root subscription HTTP header supplies exact quota', () async {
    final fetcher = FlClashProfileDownloader(
      mode: VelaSubscriptionDownloadMode.direct,
      requestStep: (uri, _) async {
        if (uri.path == '/start') {
          return reply(302, '', redirect: '/final');
        }
        // Only the final HTTP 200 may supply quota. Matches FlClash
        // Profile.update() and never reads it from the Mihomo YAML body.
        return FlClashProfileResponse(
          200, Uint8List.fromList(utf8.encode('proxies: []')),
          subscriptionUserInfo:
              'upload=1073741824; download=5368709120; '
              'total=107374182400; expire=2000000000',
        );
      },
    );
    final downloaded = await fetcher.downloadWithMetadata(
        'https://example.com/start?token=secret');
    expect(downloaded.content, 'proxies: []');
    expect(downloaded.usage?.upload, 1073741824);
    expect(downloaded.usage?.download, 5368709120);
    expect(downloaded.usage?.used, 6442450944);
    expect(downloaded.usage?.total, 107374182400);
    expect(downloaded.usage?.expire, 2000000000);
    expect(downloaded.usage?.fraction, closeTo(.06, .00001));
  });

  test('FlClash airport name comes from final response Content-Disposition',
      () async {
    final fetcher = FlClashProfileDownloader(
      mode: VelaSubscriptionDownloadMode.direct,
      requestStep: (uri, _) async {
        if (uri.path == '/redirect') {
          return FlClashProfileResponse(302, Uint8List(0),
            redirect: '/final',
            contentDisposition: 'attachment; filename="Old Airport.yaml"');
        }
        return FlClashProfileResponse(200,
            Uint8List.fromList(utf8.encode('proxies: []')),
            contentDisposition:
                "attachment; filename*=UTF-8''%E6%98%9F%E6%B2%B3%E6%9C%BA%E5%9C%BA");
      },
    );
    final downloaded = await fetcher.downloadWithMetadata(
        'https://example.com/redirect?token=private');
    expect(downloaded.suggestedName, '星河机场');
  });

  test('manual airport name overrides provider filename; empty uses provider',
      () {
    expect(VelaSubscriptionSuggestedName.displayName(
        ' 自定义机场 ', 'Provider Airport.yaml', 3), '自定义机场');
    expect(VelaSubscriptionSuggestedName.displayName(
        '   ', 'Provider Airport.yaml', 3), 'Provider Airport.yaml');
    expect(VelaSubscriptionSuggestedName.displayName(
        '', null, 3), '机场 3');
  });

  test('airport filename parsing rejects invalid names without URL token fallback',
      () {
    expect(VelaSubscriptionSuggestedName.fromContentDisposition(
      'attachment; filename="Wave Airport.yaml"'), 'Wave Airport.yaml');
    expect(VelaSubscriptionSuggestedName.fromContentDisposition(null), isNull);
    expect(VelaSubscriptionSuggestedName.fromContentDisposition(
      'attachment; filename="../../secret.yaml"'), isNull);
    expect(VelaSubscriptionSuggestedName.fromContentDisposition(
      'attachment; filename=""'), isNull);
    expect(VelaSubscriptionSuggestedName.fromContentDisposition(
      'attachment'), isNull);
  });

  test('quota parser rejects absent and corrupted server metadata', () {
    expect(FlClashSubscriptionUsage.parse(null), isNull);
    expect(FlClashSubscriptionUsage.parse('download=2; total=200'), isNull);
    expect(FlClashSubscriptionUsage.parse(
        'upload=-1;download=1;total=100'), isNull);
    expect(FlClashSubscriptionUsage.parse(
        'upload=1;download=2;total=0'), isNull);
    expect(FlClashSubscriptionUsage.parse(
        'Upload=1024; Download=1024; TOTAL=4096')?.fraction, .5);
  });


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
