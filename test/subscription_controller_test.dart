import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/vela_core_controller.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_controller.dart';

class _StubFetcher implements VelaSubscriptionFetcher {
  _StubFetcher(this.response);
  final String response;
  String? requested;
  @override
  Future<String> download(String url) async {
    requested = url;
    return response;
  }
}

const _simple = '''
proxies:
  - name: "Japan SS"
    type: ss
    server: jp.example.test
    port: 443
    cipher: aes-128-gcm
    password: super-private
''';

void main() {
  test('URL contains a token but is never retained in displayed state',
      () async {
    final dir = await Directory.systemTemp.createTemp('vela_subtest_');
    addTearDown(() => dir.delete(recursive: true));
    final core = VelaCoreController(
      supported: true, managedProfileDirectory: dir,
    );
    final fetcher = _StubFetcher(_simple);
    final sub = VelaSubscriptionController(fetcher: fetcher, core: core);
    const secretUrl = 'https://example.test/sub?token=do-not-log';
    expect(await sub.importFromUrl(secretUrl), isTrue);
    expect(sub.nodes.single.name, 'Japan SS');
    expect(sub.nodes.single.protocol, 'shadowsocks');
    expect(sub.error, isNull);

    expect(await sub.selectNode(0), isTrue);
    expect(sub.selectedIndex, 0);
    expect(core.directTestProfile, isFalse);
    expect(core.localPort, 20808);
    final generated = await File('${dir.path}/subscription-active.json')
        .readAsString();
    expect(generated, contains('super-private'));
    expect(generated, isNot(contains(secretUrl)));
    expect(generated, contains('"selected"'));
    sub.dispose();
    core.dispose();
  });

  test('failed format import exposes no source token in error state',
      () async {
    final dir = await Directory.systemTemp.createTemp('vela_subfail_');
    addTearDown(() => dir.delete(recursive: true));
    final core = VelaCoreController(
      supported: true, managedProfileDirectory: dir,
    );
    final sub = VelaSubscriptionController(
      core: core, fetcher: _StubFetcher('not a supported subscription'),
    );
    expect(await sub.importFromUrl('https://example.test/?token=top-secret'),
        isFalse);
    expect(sub.error, isNot(contains('top-secret')));
    expect(sub.nodes, isEmpty);
    sub.dispose();
    core.dispose();
  });

  test('HTTPS fetcher rejects local/private/plaintext destination before I/O',
      () async {
    const fetcher = VelaHttpsSubscriptionFetcher();
    for (final uri in [
      'http://example.com/sub',
      'https://127.0.0.1/sub',
      'https://localhost/sub',
      'https://192.168.1.11/private',
      'https://user:pass@example.com/sub',
    ]) {
      await expectLater(fetcher.download(uri), throwsFormatException);
    }
  });
}
