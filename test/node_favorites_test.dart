import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/vela_core_controller.dart';
import 'package:vela_shuo/src/subscription/vela_node_filter_panel.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_controller.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_vault.dart';

const _nodes = '''
proxies:
  - name: "Tokyo Fast"
    type: ss
    server: jp.example.test
    port: 443
    cipher: aes-128-gcm
    password: private-tokyo
  - name: "US Streaming"
    type: ss
    server: us.example.test
    port: 443
    cipher: aes-128-gcm
    password: private-us
  - name: "日本 Backup"
    type: ss
    server: jp-backup.example.test
    port: 443
    cipher: aes-128-gcm
    password: private-backup
''';

class _MemoryVault implements VelaSubscriptionVault {
  String? value;

  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String data) async => value = data;
  @override
  Future<void> delete() async => value = null;
}

void main() {
  test('favorite order preserves real indices and the smart ranking', () async {
    final core = VelaCoreController(supported: false);
    final sub = VelaSubscriptionController(core: core, previewOnly: true);
    addTearDown(() { sub.dispose(); core.dispose(); });
    expect(await sub.importFromText(_nodes), true);
    expect(sub.visibleNodeIndices(), [0, 1, 2]);
    expect(sub.toggleFavorite(2), true);
    expect(sub.toggleFavorite(0), true);
    expect(sub.favoriteCount, 2);
    expect(sub.visibleNodeIndices(order: [1, 2, 0]), [2, 0, 1]);
    expect(sub.visibleNodeIndices(order: [2, 2, 999, -1]), [2, 0, 1]);
    expect(sub.visibleNodeIndices(favoritesOnly: true), [0, 2]);
    expect(sub.visibleNodeIndices(query: ' TOKYO '), [0]);
    expect(sub.visibleNodeIndices(query: 'SHADOWSOCKS'), [0, 2, 1]);
    expect(sub.visibleNodeIndices(query: 'not-a-region'), isEmpty);
    expect(sub.toggleFavorite(-1), false);
    expect(sub.toggleFavorite(9), false);
    expect(await sub.selectNode(1), true);
    expect(sub.toggleFavorite(1), true);
    // The star has no side effects on the running/selected node.
    expect(sub.selectedIndex, 1);
    expect(core.isListening, false);

    expect(await sub.importFromText(_nodes), true);
    expect(sub.favoriteCount, 0);
    expect(sub.visibleNodeIndices(), [0, 1, 2]);
  });

  test('favorites persist only inside the opt-in encrypted snapshot',
      () async {
    final vault = _MemoryVault();
    final core = VelaCoreController(supported: false);
    final sub = VelaSubscriptionController(
      core: core, previewOnly: true, vault: vault);
    expect(await sub.importFromText(_nodes), true);
    sub.toggleFavorite(2);
    sub.toggleFavorite(0);
    expect(vault.value, isNull);
    expect(await sub.saveOnDevice(), true);
    final stored = jsonDecode(vault.value!) as Map;
    expect(stored['v'], 1);
    expect(stored['favorites'], [0, 2]);
    sub.dispose();
    core.dispose();

    final freshCore = VelaCoreController(supported: false);
    final fresh = VelaSubscriptionController(
      core: freshCore, previewOnly: true, vault: vault);
    expect(await fresh.restoreSaved(), true);
    expect(fresh.favoriteCount, 2);
    expect(fresh.visibleNodeIndices(favoritesOnly: true), [0, 2]);
    expect(fresh.selectedIndex, isNull);
    expect(freshCore.isListening, false);
    fresh.dispose();
    freshCore.dispose();
  });

  test('legacy and malformed favorite indices restore safely', () async {
    final vault = _MemoryVault()..value =
        jsonEncode({'v': 1, 'raw': _nodes, 'selected': null});
    final core = VelaCoreController(supported: false);
    final sub = VelaSubscriptionController(
      core: core, previewOnly: true, vault: vault);
    expect(await sub.restoreSaved(), true);
    expect(sub.favoriteCount, 0);
    sub.dispose();
    core.dispose();

    vault.value = jsonEncode({
      'v': 1, 'raw': _nodes, 'selected': null,
      'favorites': [2, 2, 'bad', -1, 999],
    });
    final secondCore = VelaCoreController(supported: false);
    final restored = VelaSubscriptionController(
      core: secondCore, previewOnly: true, vault: vault);
    expect(await restored.restoreSaved(), true);
    expect(restored.favoriteCount, 1);
    expect(restored.visibleNodeIndices(favoritesOnly: true), [2]);
    restored.dispose();
    secondCore.dispose();
  });

  testWidgets('shared search and favorite-only panel reacts to edits',
      (tester) async {
    final core = VelaCoreController(supported: false);
    final sub = VelaSubscriptionController(core: core, previewOnly: true);
    expect(await sub.importFromText(_nodes), true);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: VelaNodeFilterPanel(
        controller: sub,
        builder: (_, indices) => Column(children: [
          for (final i in indices)
            Text(sub.nodes[i].name, key: ValueKey('result_$i')),
        ]),
      )),
    )));
    expect(find.byKey(const ValueKey('result_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('result_1')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('node_search_input')), 'US');
    await tester.pump();
    expect(find.byKey(const ValueKey('result_0')), findsNothing);
    expect(find.byKey(const ValueKey('result_1')), findsOneWidget);
    sub.toggleFavorite(2);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('node_favorites_only')));
    await tester.pump();
    expect(find.textContaining('没有匹配的节点'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('node_search_clear')));
    await tester.pump();
    expect(find.byKey(const ValueKey('result_2')), findsOneWidget);
    expect(find.byKey(const ValueKey('result_1')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    sub.dispose();
    core.dispose();
  });
}
