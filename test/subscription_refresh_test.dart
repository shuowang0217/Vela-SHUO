import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/vela_core_controller.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_controller.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_vault.dart';

const first = '''
proxies:
  - name: Tokyo
    type: ss
    server: jp.example.test
    port: 443
    cipher: aes-128-gcm
    password: old-tokyo-secret
  - name: Singapore
    type: ss
    server: sg.example.test
    port: 443
    cipher: aes-128-gcm
    password: sg-secret
''';

const reordered = '''
proxies:
  - name: Singapore
    type: ss
    server: sg.example.test
    port: 443
    cipher: aes-128-gcm
    password: sg-secret-new
  - name: Tokyo
    type: ss
    server: jp.example.test
    port: 443
    cipher: aes-128-gcm
    password: new-tokyo-secret
  - name: London
    type: ss
    server: gb.example.test
    port: 443
    cipher: aes-128-gcm
    password: gb-secret
''';

class _Fetcher implements VelaSubscriptionFetcher {
  String data = first;
  bool broken = false;
  int reads = 0;

  @override
  Future<String> download(String url) async {
    reads++;
    if (broken) throw const FormatException('远程订阅临时不可达');
    return data;
  }
}

class _Vault implements VelaSubscriptionVault {
  String? value;

  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String data) async => value = data;
  @override
  Future<void> delete() async => value = null;
}

void main() {
  test('failed refresh preserves nodes, selection, favorites and vault',
      () async {
    final core = VelaCoreController(supported: false);
    final vault = _Vault();
    final fetcher = _Fetcher();
    final sub = VelaSubscriptionController(
        core: core, previewOnly: true, fetcher: fetcher, vault: vault);
    addTearDown(() { sub.dispose(); core.dispose(); });

    const url = 'https://provider.example.test/sub?token=private-credential';
    expect(await sub.importFromUrl(url), true);
    expect(await sub.selectNode(0), true);
    expect(sub.toggleFavorite(1), true);
    expect(await sub.saveOnDevice(), true);
    final previous = vault.value;
    expect(jsonDecode(previous!)['selected'], 0);
    expect(previous, isNot(contains('private-credential')));

    fetcher.broken = true;
    expect(await sub.refreshLastUrl(), false);
    expect(sub.nodes.length, 2);
    expect(sub.selected?.name, 'Tokyo');
    expect(sub.favoriteCount, 1);
    expect(sub.isFavorite(1), true);
    expect(sub.storedOnDevice, true);
    expect(vault.value, previous);
    expect(sub.canRefresh, true);
    expect(sub.error, isNotNull);
    expect(await sub.importFromText('this is not a node list'), false);
    expect(sub.nodes.length, 2);
    expect(core.isListening, false);
  });

  test('manual refresh preserves node identity and favorite after reordering',
      () async {
    final core = VelaCoreController(supported: false);
    final vault = _Vault();
    final fetcher = _Fetcher();
    final sub = VelaSubscriptionController(
        core: core, previewOnly: true, fetcher: fetcher, vault: vault);
    addTearDown(() { sub.dispose(); core.dispose(); });
    expect(await sub.importFromUrl('https://provider.example.test/sub'),
        true);
    expect(await sub.selectNode(0), true);
    expect(sub.toggleFavorite(1), true);
    expect(await sub.saveOnDevice(), true);
    final oldVault = vault.value;

    fetcher.data = reordered;
    expect(await sub.refreshLastUrl(), true);
    expect(sub.nodes.length, 3);
    expect(sub.selectedIndex, 1);
    expect(sub.selected?.name, 'Tokyo');
    expect(sub.isFavorite(0), true);
    expect(sub.isFavorite(1), false);
    expect(sub.storedOnDevice, false);
    expect(vault.value, oldVault);
    expect(core.isListening, false);
    expect(fetcher.reads, 2);
  });

  test('refresh is manually opt-in and URL never enters encrypted vault',
      () async {
    final vault = _Vault();
    final core = VelaCoreController(supported: false);
    final fetcher = _Fetcher();
    final sub = VelaSubscriptionController(
        core: core, previewOnly: true, fetcher: fetcher, vault: vault);
    expect(sub.hasSessionUrl, false);
    expect(await sub.refreshLastUrl(), false);
    expect(await sub.importFromUrl(
        'https://provider.example.test/sub?token=private-token'), true);
    expect(sub.hasSessionUrl, true);
    expect(fetcher.reads, 1);
    expect(await sub.saveOnDevice(), true);
    expect(vault.value, isNot(contains('private-token')));
    sub.dispose();
    core.dispose();

    final restoredCore = VelaCoreController(supported: false);
    final restored = VelaSubscriptionController(
        core: restoredCore, previewOnly: true, vault: vault);
    expect(await restored.restoreSaved(), true);
    expect(restored.hasSessionUrl, false);
    expect(restored.canRefresh, false);
    restored.dispose();
    restoredCore.dispose();
  });
}
