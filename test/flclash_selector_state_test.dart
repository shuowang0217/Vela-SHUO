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

/// The three native tabs shown in the user's FlClash screenshot are
/// NOT separate routing modes; they are the profile's actual group list.
class _GroupTransport extends _NativeTransport {
  _GroupTransport() {
    now.addAll({
      '🐮牛逼': '自动选择',
      '自动选择': 'JP',
      '故障转移': 'US',
      '隐藏组': 'US',
    });
  }

  @override
  Map<String, Object?> get registry {
    final base = super.registry;
    return {
      ...base,
      'groups': ['GLOBAL', '🐮牛逼', '自动选择', '故障转移', '隐藏组'],
      'match-group': '🐮牛逼',
      'raw-proxy-groups': [
        {'name': '🐮牛逼', 'type': 'select'},
        {'name': '自动选择', 'type': 'url-test'},
        {'name': '故障转移', 'type': 'fallback'},
        {'name': '隐藏组', 'type': 'select', 'hidden': true},
      ],
      'proxies': {
        ...base['proxies'] as Map,
        '🐮牛逼': {
          'type': 'Selector', 'now': now['🐮牛逼'],
          'all': ['JP', 'US', '自动选择', '故障转移'],
        },
        '自动选择': {
          'type': 'URLTest', 'now': now['自动选择'],
          'all': ['JP', 'US'],
        },
        '故障转移': {
          'type': 'Fallback', 'now': now['故障转移'],
          'all': ['JP', 'US'],
        },
        '隐藏组': {
          'type': 'Selector', 'now': now['隐藏组'],
          'all': ['JP', 'US'],
        },
      },
    };
  }
}

void main() {
  test('RULE has only exact upstream visible groups, no fake ALL or GLOBAL',
      () async {
    final dir = await Directory.systemTemp.createTemp('vela_flclash_tabs_');
    addTearDown(() => dir.delete(recursive: true));
    final transport = _GroupTransport();
    final backend = FlClashWindowsBackend(
        homeDir: dir.path, transport: transport);
    await backend.importText('rules:\n  - MATCH,🐮牛逼\n');
    expect(backend.visibleGroups, ['🐮牛逼', '自动选择', '故障转移']);
    expect(backend.groupTypes['自动选择'], 'URLTest');
    expect(backend.groupTypes['故障转移'], 'Fallback');
    expect(backend.groupMembers['🐮牛逼'],
        containsAll(['自动选择', '故障转移']));
    expect(backend.selectableGroups.contains('自动选择'), false);

    // FlClash changes its current *tab* even with an active connection,
    // without calling changeProxy or affecting upstream RULE mode.
    backend.listenerStarted = true;
    expect(backend.selectRoutingGroup('自动选择'), true);
    expect(transport.changes, isEmpty);
    expect(transport.mode, 'rule');
    backend.listenerStarted = false;

    expect(backend.selectRoutingGroup('🐮牛逼'), true);
    expect(await backend.selectGroupMember('故障转移'), true);
    expect(backend.selectedMap['🐮牛逼'], '故障转移');
    expect(transport.changes.last, '🐮牛逼=>故障转移');
    expect(backend.activeName, isNull);

    expect(await backend.updateRoutingMode('global'), true);
    expect(backend.visibleGroups, contains('GLOBAL'));
    expect(backend.visibleGroups, contains('隐藏组'));
    expect(await backend.updateRoutingMode('direct'), true);
    expect(backend.visibleGroups, isEmpty);
  });

  test('Vela group page uses the native FlClash group list', () {
    final source = File('lib/src/stellar/vela_stellar_proxy_page.dart')
        .readAsStringSync();
    expect(source, contains('backend.visibleGroups'));
    expect(source, contains('backend.groups.contains(member)'));
    expect(source, isNot(contains("final groupNames = ['全部节点'")));
    expect(source, contains('widget.routing'));
  });


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
