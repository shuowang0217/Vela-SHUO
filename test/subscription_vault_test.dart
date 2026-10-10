import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/vela_core_controller.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_controller.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_vault.dart';

const _yaml = '''
proxies:
  - name: "Tokyo 01"
    type: ss
    server: jp.example.test
    port: 443
    cipher: aes-128-gcm
    password: saved-node-credential
''';

class _MemoryVault implements VelaSubscriptionVault {
  String? value;
  int writes = 0;
  int deletes = 0;
  bool failRead = false;
  bool failWrite = false;

  @override
  Future<String?> read() async {
    if (failRead) throw StateError('sensitive credential here');
    return value;
  }

  @override
  Future<void> write(String data) async {
    if (failWrite) throw StateError('sensitive credential here');
    writes++;
    value = data;
  }

  @override
  Future<void> delete() async {
    deletes++;
    value = null;
  }
}

class _Fetcher implements VelaSubscriptionFetcher {
  String? lastUrl;
  @override
  Future<String> download(String url) async {
    lastUrl = url;
    return _yaml;
  }
}

void main() {
  test('opt-in encrypted snapshot keeps URL out and restores node safely',
      () async {
    final vault = _MemoryVault();
    final fetcher = _Fetcher();
    final core = VelaCoreController(supported: false);
    final sub = VelaSubscriptionController(
      core: core, previewOnly: true, vault: vault, fetcher: fetcher,
    );
    const url = 'https://provider.example.test/sub?token=private-bearer';
    expect(await sub.importFromUrl(url), true);
    expect(vault.value, null); // Default: no persistence.
    expect(vault.writes, 0);
    expect(await sub.selectNode(0), true);
    expect(await sub.saveOnDevice(), true);
    expect(sub.storedOnDevice, true);
    expect(vault.writes, 1);
    expect(vault.value, isNot(contains('private-bearer')));
    expect(vault.value, contains('saved-node-credential'));
    expect(jsonDecode(vault.value!)['selected'], 0);
    sub.dispose();
    core.dispose();

    final nextCore = VelaCoreController(supported: false);
    final restored = VelaSubscriptionController(
      core: nextCore, previewOnly: true, vault: vault,
      fetcher: _Fetcher(),
    );
    expect(await restored.restoreSaved(), true);
    expect(restored.nodes.single.name, 'Tokyo 01');
    expect(restored.selectedIndex, 0);
    expect(restored.storedOnDevice, true);
    expect(nextCore.isListening, false);
    expect(nextCore.hasConfig, false);
    expect(await restored.clearSaved(), true);
    expect(vault.deletes, 1);
    expect(vault.value, null);
    // Clearing storage does not silently destroy current UI/session.
    expect(restored.nodes, hasLength(1));
    restored.dispose();
    nextCore.dispose();
  });

  test('saved snapshot never changes automatically on later imports',
      () async {
    final vault = _MemoryVault();
    final core = VelaCoreController(supported: false);
    final sub = VelaSubscriptionController(
      core: core, previewOnly: true, vault: vault,
    );
    expect(await sub.importFromText(_yaml), true);
    expect(await sub.saveOnDevice(), true);
    final previous = vault.value;
    expect(await sub.importFromText(
      'trojan://changed@us.example.test:443?security=tls#US',
    ), true);
    expect(sub.storedOnDevice, false);
    expect(vault.value, previous);
    expect(await sub.saveOnDevice(), true);
    expect(vault.value, isNot(previous));
    sub.dispose();
    core.dispose();
  });

  test('corrupt or unreadable vault fails closed without exposing credentials',
      () async {
    final vault = _MemoryVault()..value = '{"v":1,"raw":"sensitive-token"}';
    final core = VelaCoreController(supported: false);
    final sub = VelaSubscriptionController(
      core: core, previewOnly: true, vault: vault,
    );
    expect(await sub.restoreSaved(), false);
    expect(sub.nodes, isEmpty);
    expect(sub.error, isNot(contains('sensitive-token')));
    vault.failRead = true;
    expect(await sub.restoreSaved(), false);
    expect(sub.error, isNot(contains('sensitive')));
    vault.failRead = false;
    expect(await sub.clearSaved(), true);
    sub.dispose();
    core.dispose();
  });

  test('secure storage error never claims saved state', () async {
    final vault = _MemoryVault()..failWrite = true;
    final core = VelaCoreController(supported: false);
    final sub = VelaSubscriptionController(
      core: core, previewOnly: true, vault: vault,
    );
    expect(await sub.importFromText(_yaml), true);
    expect(await sub.saveOnDevice(), false);
    expect(sub.storedOnDevice, false);
    expect(vault.value, isNull);
    expect(sub.error, isNot(contains('sensitive credential')));
    sub.dispose();
    core.dispose();
  });
}
