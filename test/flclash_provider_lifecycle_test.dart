import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/network/flclash_core_api.dart';
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
