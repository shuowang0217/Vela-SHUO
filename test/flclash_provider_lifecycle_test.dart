import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/network/flclash_core_api.dart';
import 'package:vela_shuo/src/subscription/flclash_profile_downloader.dart';
import 'package:vela_shuo/src/network/flclash_windows_backend.dart';
import 'package:vela_shuo/src/network/vela_flclash_core_adapter.dart';
import 'package:vela_shuo/src/network/vela_flclash_subscription_adapter.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_vault.dart';

class _Vault implements VelaSubscriptionVault {
  String? payload;
  @override
  Future<String?> read() async => payload;
  @override
  Future<void> write(String data) async { payload = data; }
  @override
  Future<void> delete() async { payload = null; }
}

class _NativeFlClash implements FlClashCoreTransport {
  bool updated = false;
  bool failUpdate = false;
  bool dropSelected = false;
  String? selected;
  final calls = <String>[];

  @override
  Future<String?> invoke(String requestJson) async {
    final msg = jsonDecode(requestJson) as Map<String, dynamic>;
    final method = msg['method'] as String;
    calls.add(method);
    Object? result;
    switch (method) {
      case 'initClash':
        result = true;
      case 'velaLoadProfile':
        result = {
          'groups': ['GLOBAL'],
          'provider-count': 1,
          'raw-proxies': [
            {'name': 'Japan', 'server': 'jp.test', 'type': 'vless'},
            {'name': 'USA', 'server': 'us.test', 'type': 'ss'},
          ],
          'proxies': updated
              ? {
                  'GLOBAL': {'type': 'Selector'},
                  'USA': {'type': 'Shadowsocks'},
                  'Japan': {'type': 'VLESS'},
                }
              : {
                  'GLOBAL': {'type': 'Selector'},
                  'Japan': {'type': 'VLESS'},
                  'USA': {'type': 'Shadowsocks'},
                },
        };
      case 'getExternalProviders':
        result = [
          {'name': 'RemoteNodes', 'vehicle-type': 'HTTP', 'count': 2},
        ];
      case 'updateExternalProvider':
        if (failUpdate) {
          return jsonEncode({
            'id': msg['id'],
            'error': {'code': 'provider_update_error',
                      'message': 'synthetic error'},
          });
        }
        updated = true;
        result = null;
      case 'getProxies':
        result = {
          'all': ['GLOBAL'],
          'proxies': updated
              ? {
                  'GLOBAL': {'type': 'Selector', 'now': selected},
                  'USA': {'type': 'Shadowsocks'},
                  if (!dropSelected) 'Japan': {'type': 'VLESS'},
                }
              : {
                  'GLOBAL': {'type': 'Selector', 'now': selected},
                  'Japan': {'type': 'VLESS'},
                  'USA': {'type': 'Shadowsocks'},
                },
        };
      case 'changeProxy':
        final args = msg['arguments'] as Map;
        if (args['group-name'] != 'GLOBAL') {
          throw StateError('Vela must use FlClash global route');
        }
        selected = args['proxy-name'] as String;
        result = {'changed': true, 'message': ''};
      case 'shutdown':
        result = true;
      case 'stopListener':
        result = true;
      default:
        throw StateError('Unexpected Vela local handler: $method');
    }
    return jsonEncode({'id': msg['id'], 'result': result});
  }
}

const _profile = '''
proxies:
  - name: Japan
    type: vless
    server: jp.test
    port: 443
proxy-providers:
  RemoteNodes:
    type: http
    url: https://example.test/remote.yaml
''';

void main() {
  test('online fetch stages a second airport without interrupting active core',
      () async {
    final dir = await Directory.systemTemp.createTemp('vela_staged_airport_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = _Vault();
    final backend = FlClashWindowsBackend(homeDir: dir.path,
        transport: _NativeFlClash());
    final core = VelaFlClashCoreController(backend);
    final sub = VelaFlClashSubscriptionController(
      backend: backend, core: core,
      profileVault: vault, vault: _Vault(),
      downloader: FlClashProfileDownloader(
        mode: VelaSubscriptionDownloadMode.direct,
        requestStep: (uri, route) async => FlClashProfileResponse(
          200, Uint8List.fromList(utf8.encode(_profile)),
          subscriptionUserInfo: 'upload=100; download=200; total=1000'),
      ),
    );
    expect(await sub.importFromText(_profile), true);
    final oldId = sub.activeProfileId!;
    final oldName = backend.activeName;
    backend.listenerStarted = true; // Simulate connected listener.
    expect(await sub.importFromUrlNamed(
        'https://example.test/sub?token=private-token',
        name: '第二机场', stageOnly: true), true);
    expect(sub.profiles, hasLength(2));
    expect(sub.activeProfileId, oldId);
    expect(backend.activeName, oldName);
    expect(backend.listenerStarted, true);
    expect(vault.payload, isNot(contains('private-token')));
    expect(sub.profiles.last.usage?['total'], 1000);
    backend.listenerStarted = false;
    expect(await sub.activateProfile(sub.profiles.last.id), true);
    expect(sub.profileName, '第二机场');
    expect(backend.subscriptionUsage?.total, 1000);
    sub.dispose();
    core.dispose();
  });

  test('named profiles switch independently and restore active profile',
      () async {
    final dir = await Directory.systemTemp.createTemp('vela_multi_profile_');
    addTearDown(() => dir.delete(recursive: true));
    final singleVault = _Vault();
    final profileVault = _Vault();
    final backend = FlClashWindowsBackend(homeDir: dir.path,
        transport: _NativeFlClash());
    final core = VelaFlClashCoreController(backend);
    final sub = VelaFlClashSubscriptionController(
        backend: backend, core: core,
        vault: singleVault, profileVault: profileVault);

    expect(await sub.importFromText(_profile), true);
    expect(await sub.selectNode(0), true);
    expect(sub.toggleFavorite(1), true);
    // Successful imports now auto-save the active airport.
    final japanId = sub.activeProfileId!;
    expect(await sub.renameProfile(japanId, '日本订阅'), true);

    expect(await sub.importFromText('$_profile\n# second profile'), true);
    expect(sub.selectedIndex, 0); // Default route is usable immediately.
    expect(sub.favoriteCount, 0);
    expect(await sub.selectNode(1), true);
    expect(sub.toggleFavorite(0), true);
    final usaId = sub.activeProfileId!;
    expect(await sub.renameProfile(usaId, '美国订阅'), true);
    expect(sub.profiles, hasLength(2));

    expect(await sub.activateProfile(japanId), true);
    expect(sub.selected?.name, 'Japan');
    expect(sub.isFavorite(1), true);
    expect(sub.isFavorite(0), false);

    expect(await sub.activateProfile(usaId), true);
    expect(sub.selected?.name, 'USA');
    expect(sub.isFavorite(0), true);
    expect(sub.isFavorite(1), false);
    sub.dispose();
    core.dispose();

    final restoredBackend = FlClashWindowsBackend(homeDir: dir.path,
        transport: _NativeFlClash());
    final restoredCore = VelaFlClashCoreController(restoredBackend);
    final restored = VelaFlClashSubscriptionController(
        backend: restoredBackend, core: restoredCore,
        vault: singleVault, profileVault: profileVault);
    expect(await restored.restoreSaved(), true);
    expect(restored.profileName, '美国订阅');
    expect(restored.selected?.name, 'USA');
    expect(restored.isFavorite(0), true);
    expect(restored.profiles, hasLength(2));
    expect(await restored.renameProfile(japanId, '日本线路'), true);
    expect(await restored.removeProfile(japanId), true);
    expect(restored.profiles, hasLength(1));
    restored.dispose();
    restoredCore.dispose();
  });

  test('opt-in encrypted profile snapshot also restores FlClash server quota',
      () async {
    final dir = await Directory.systemTemp.createTemp('vela_quota_snapshot_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = _Vault();
    final firstNative = _NativeFlClash();
    final firstBackend = FlClashWindowsBackend(
        homeDir: dir.path, transport: firstNative);
    final firstCore = VelaFlClashCoreController(firstBackend);
    final first = VelaFlClashSubscriptionController(
        backend: firstBackend, core: firstCore, vault: vault);
    expect(await first.importFromText(_profile), true);
    firstBackend.subscriptionUsage = const FlClashSubscriptionUsage(
      upload: 300, download: 700, total: 10000, expire: 2000000000,
    );
    expect(await first.saveOnDevice(), true);
    expect(jsonDecode(vault.payload!)['subscriptionUsage']['total'], 10000);
    first.dispose();
    firstCore.dispose();

    final nextBackend = FlClashWindowsBackend(
        homeDir: dir.path, transport: _NativeFlClash());
    final nextCore = VelaFlClashCoreController(nextBackend);
    final restored = VelaFlClashSubscriptionController(
        backend: nextBackend, core: nextCore, vault: vault);
    expect(await restored.restoreSaved(), true);
    expect(nextBackend.subscriptionUsage?.used, 1000);
    expect(nextBackend.subscriptionUsage?.total, 10000);
    expect(nextBackend.subscriptionUsage?.expire, 2000000000);
    restored.dispose();
    nextCore.dispose();
  });

  test('native HTTP provider refresh preserves selected and starred node by name',
      () async {
    final dir = await Directory.systemTemp.createTemp('vela_provider_refresh_');
    addTearDown(() => dir.delete(recursive: true));
    final native = _NativeFlClash();
    final backend = FlClashWindowsBackend(
        homeDir: dir.path, transport: native);
    final core = VelaFlClashCoreController(backend);
    final vault = _Vault();
    final sub = VelaFlClashSubscriptionController(
        backend: backend, core: core, vault: vault);
    expect(await sub.importFromText(_profile), true);
    expect(sub.remoteProviderCount, 1);
    expect(sub.nodes.map((node) => node.name), ['Japan', 'USA']);
    expect(sub.toggleFavorite(1), true);
    expect(sub.isFavorite(1), true);
    expect(await sub.selectNode(0), true);
    expect(sub.selected?.name, 'Japan');
    expect(await sub.saveOnDevice(), true);
    expect(vault.payload, isNot(contains('https://example.test/remote.yaml?token=')));
    expect(jsonDecode(vault.payload!)['selectedName'], 'Japan');
    expect(jsonDecode(vault.payload!)['favoriteNames'], ['USA']);

    // Actual FlClash Go provider implementation returns reversed node order.
    expect(await sub.refreshNativeProviders(), true);
    expect(sub.nodes.map((node) => node.name), ['USA', 'Japan']);
    expect(sub.selectedIndex, 1);
    expect(sub.selected?.name, 'Japan');
    expect(sub.isFavorite(0), true);
    expect(sub.isFavorite(1), false);
    expect(sub.favoriteCount, 1);
    expect(sub.storedOnDevice, false);
    expect(native.calls, contains('updateExternalProvider'));
    expect(native.calls, contains('getProxies'));

    sub.dispose();
    core.dispose();
  });

  test('encrypted snapshot restores names even after node ordering changes',
      () async {
    final dir = await Directory.systemTemp.createTemp('vela_provider_vault_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = _Vault();
    final previousNative = _NativeFlClash();
    final previousBackend = FlClashWindowsBackend(
        homeDir: dir.path, transport: previousNative);
    final previousCore = VelaFlClashCoreController(previousBackend);
    final before = VelaFlClashSubscriptionController(
        backend: previousBackend, core: previousCore, vault: vault);
    expect(await before.importFromText(_profile), true);
    expect(await before.selectNode(0), true);
    expect(before.toggleFavorite(1), true);
    expect(await before.saveOnDevice(), true);
    before.dispose();
    previousCore.dispose();

    final nextNative = _NativeFlClash()..updated = true;
    final nextBackend = FlClashWindowsBackend(
        homeDir: dir.path, transport: nextNative);
    final nextCore = VelaFlClashCoreController(nextBackend);
    final after = VelaFlClashSubscriptionController(
        backend: nextBackend, core: nextCore, vault: vault);
    expect(await after.restoreSaved(), true);
    expect(after.nodes.map((node) => node.name), ['USA', 'Japan']);
    expect(after.selected?.name, 'Japan');
    expect(after.selectedIndex, 1);
    expect(after.isFavorite(0), true);
    expect(after.isFavorite(1), false);
    expect(after.favoriteCount, 1);
    expect(after.storedOnDevice, true);
    after.dispose();
    nextCore.dispose();
  });

  test('native FlClash provider failure retains previous selection and nodes',
      () async {
    final dir = await Directory.systemTemp.createTemp('vela_provider_failure_');
    addTearDown(() => dir.delete(recursive: true));
    final native = _NativeFlClash()..failUpdate = true;
    final backend = FlClashWindowsBackend(
        homeDir: dir.path, transport: native);
    final core = VelaFlClashCoreController(backend);
    final sub = VelaFlClashSubscriptionController(
        backend: backend, core: core, vault: _Vault());
    expect(await sub.importFromText(_profile), true);
    expect(await sub.selectNode(0), true);
    expect(sub.toggleFavorite(1), true);
    expect(await sub.refreshNativeProviders(), false);
    expect(sub.nodes.map((node) => node.name), ['Japan', 'USA']);
    expect(sub.selected?.name, 'Japan');
    expect(sub.isFavorite(1), true);
    expect(sub.error, isNotNull);
    sub.dispose();
    core.dispose();
  });
}
