import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/network/flclash_core_api.dart';
import 'package:vela_shuo/src/network/flclash_windows_backend.dart';
import 'package:vela_shuo/src/subscription/vela_profile_library.dart';

/// Fake only the transport. FlClash's core-mode and selector RPC shapes
/// remain unchanged; route algorithms themselves are in native Mihomo.
class _NativeTransport implements FlClashCoreTransport {
  final now = <String, String>{
    'GLOBAL': 'JP',
    '🚀 代理': 'US',
  };
  final changes = <String>[];
  String mode = 'rule';

  Map<String, Object?> get registry => {
    'groups': ['GLOBAL', '🚀 代理'],
    'match-group': '🚀 代理',
    'raw-proxies': [
      {'name': 'JP', 'type': 'ss', 'server': 'jp.invalid', 'port': 443},
      {'name': 'US', 'type': 'ss', 'server': 'us.invalid', 'port': 443},
    ],
    'proxies': {
      for (final g in now.keys)
        g: {'type': 'Selector', 'now': now[g], 'all': ['JP', 'US']},
      'JP': {'type': 'SS'},
      'US': {'type': 'SS'},
      'DIRECT': {'type': 'Direct'},
    },
    'provider-count': 0,
  };

  @override
  Future<String> invoke(String json) async {
    final req = jsonDecode(json) as Map<String, dynamic>;
    final method = req['method'] as String;
    Object? result;
    switch (method) {
      case 'initClash':
        result = true;
      case 'velaLoadProfile':
        result = registry;
      case 'getProxies':
        result = {'proxies': registry['proxies'], 'all': registry['groups']};
      case 'changeProxy':
        final args = req['arguments'] as Map;
        final group = args['group-name'] as String;
        final choice = args['proxy-name'] as String;
        now[group] = choice;
        changes.add('$group=>$choice');
        result = {'message': '', 'changed': true};
      case 'updateConfig':
        mode = (req['arguments'] as Map)['mode'] as String;
        result = '';
      default:
        throw StateError('Unexpected FlClash method: $method');
    }
    return jsonEncode({'id': req['id'], 'result': result});
  }
}

void main() {
  test('RULE selects MATCH strategy, not built-in GLOBAL', () async {
    final dir = await Directory.systemTemp.createTemp('vela_rule_strategy_');
    addTearDown(() => dir.delete(recursive: true));
    final transport = _NativeTransport();
    final backend = FlClashWindowsBackend(
        homeDir: dir.path, transport: transport);
    await backend.importText('rules:\n  - MATCH,🚀 代理\n');
    expect(backend.activeRoutingMode, 'rule');
    expect(backend.activeGroup, '🚀 代理');
    expect(await backend.selectNode('JP'), true);
    expect(backend.selectedMap['🚀 代理'], 'JP');
    expect(backend.selectedMap['GLOBAL'], 'JP');
    expect(transport.changes.last, '🚀 代理=>JP');

    expect(await backend.updateRoutingMode('global'), true);
    expect(backend.activeGroup, 'GLOBAL');
    expect(await backend.selectNode('US'), true);
    expect(backend.selectedMap['GLOBAL'], 'US');
    expect(backend.selectedMap['🚀 代理'], 'JP');
    expect(await backend.updateRoutingMode('rule'), true);
    expect(backend.activeGroup, '🚀 代理');
    expect(backend.selectedMap['GLOBAL'], 'US');
  });

  test('FlClash group selections survive profile serialization and reimport',
      () async {
    final dir = await Directory.systemTemp.createTemp('vela_rule_persist_');
    addTearDown(() => dir.delete(recursive: true));
    final transport = _NativeTransport();
    final backend = FlClashWindowsBackend(
        homeDir: dir.path, transport: transport);
    await backend.importText('rules:\n  - MATCH,🚀 代理\n');
    await backend.restoreSelectedMap({
      'GLOBAL': 'US',
      '🚀 代理': 'JP',
      'removed-provider': 'STALE',
    }, selectedGroup: '🚀 代理');
    expect(backend.selectedMap['GLOBAL'], 'US');
    expect(backend.selectedMap['🚀 代理'], 'JP');
    expect(backend.selectedMap.containsKey('removed-provider'), false);
    final saved = VelaStoredProfile(
      id: 'airport-1',
      name: 'Test Airport',
      raw: 'rules:\n  - MATCH,🚀 代理\n',
      selectedMap: backend.selectedMap,
      selectedGroup: backend.activeGroup,
      selectedName: 'JP',
    );
    final loaded = VelaStoredProfile.fromJson(saved.toJson());
    expect(loaded, isNotNull);
    expect(loaded!.selectedMap, {
      'GLOBAL': 'US',
      '🚀 代理': 'JP',
    });
    expect(loaded.selectedGroup, '🚀 代理');
    // Old v1.0/v1.3 saved profiles are compatible with the new fields.
    final previous = VelaStoredProfile.fromJson({
      'id': 'legacy', 'name': 'Legacy', 'raw': 'proxies: []',
      'selectedName': 'JP',
    });
    expect(previous?.selectedMap, isEmpty);

    await backend.importText(saved.raw);
    await backend.restoreSelectedMap(loaded.selectedMap,
        selectedGroup: loaded.selectedGroup);
    expect(backend.selectedMap['GLOBAL'], 'US');
    expect(backend.selectedMap['🚀 代理'], 'JP');
    expect(backend.activeGroup, '🚀 代理');
  });
}
