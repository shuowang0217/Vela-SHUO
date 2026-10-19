import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/network/flclash_core_api.dart';
import 'package:vela_shuo/src/network/flclash_windows_backend.dart';
import 'package:vela_shuo/src/network/vela_flclash_core_adapter.dart';
import 'package:vela_shuo/src/network/vela_flclash_subscription_adapter.dart';
import 'package:vela_shuo/src/subscription/flclash_profile_downloader.dart';
import 'package:vela_shuo/src/subscription/vela_profile_library.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_vault.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_controller.dart';

class _TestCoreTransport implements FlClashCoreTransport {
  String active = 'Tokyo';

  @override
  Future<String?> invoke(String input) async {
    final request = jsonDecode(input) as Map<String, dynamic>;
    final method = request['method'] as String;
    final arguments = request['arguments'];
    Object? result;
    switch (method) {
      case 'initClash':
        result = true;
      case 'velaLoadProfile':
        result = {
          'groups': ['VELA_SELECT', 'GLOBAL'],
          'provider-count': 0,
          'raw-proxies': [
            {
              'name': 'Tokyo', 'type': 'vless',
              'server': 'tokyo.example.test', 'port': 443, 'network': 'grpc',
            },
          ],
          'proxies': {
            'VELA_SELECT': {'type': 'Selector', 'now': active},
            'GLOBAL': {'type': 'Selector', 'now': active},
            'Tokyo': {'type': 'VLESS'},
          },
          'raw-proxy-groups': [
            {'name': 'VELA_SELECT', 'type': 'select', 'proxies': ['Tokyo']},
            {'name': 'GLOBAL', 'type': 'select', 'proxies': ['Tokyo']},
          ],
        };
      case 'changeProxy':
        active = (arguments as Map)['proxy-name'] as String;
        result = {'message': '', 'changed': true};
      case 'getProxies':
        result = {
          'proxies': {
            'VELA_SELECT': {'type': 'Selector', 'now': active},
            'GLOBAL': {'type': 'Selector', 'now': active},
          },
          'all': ['VELA_SELECT', 'GLOBAL'],
        };
      case 'getExternalProviders':
        result = [];
      default:
        result = true;
    }
    return jsonEncode({'id': request['id'], 'result': result});
  }
}

Future<({
  Directory temp,
  VelaFlClashCoreController core,
  VelaFlClashSubscriptionController subscription,
  VelaMemoryProfileVault vault,
})> _setup({
  required List<VelaStoredProfile> profiles,
  required String activeId,
  required DateTime Function() clock,
  FlClashProfileDownloader? downloader,
}) async {
  final temp = await Directory.systemTemp.createTemp('vela-airport-test-');
  final vault = VelaMemoryProfileVault();
  await VelaProfileLibrary(vault).write(profiles, activeId);
  final backend = FlClashWindowsBackend(
    transport: _TestCoreTransport(),
    homeDir: temp.path,
  );
  final core = VelaFlClashCoreController(backend);
  final subscription = VelaFlClashSubscriptionController(
    backend: backend,
    core: core,
    vault: VelaMemoryProfileVault(),
    profileVault: vault,
    downloader: downloader,
    clock: clock,
  );
  expect(await subscription.restoreSaved().timeout(
      const Duration(seconds: 5)), isTrue);
  return (
    temp: temp,
    core: core,
    subscription: subscription,
    vault: vault,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('active airport layout is featured before the remaining cards', () {
    final source = File(
        'lib/src/stellar/vela_stellar_config_page.dart').readAsStringSync();
    expect(source, contains('final activeProfile = profiles.where'));
    expect(source, contains('SizedBox(width: area.maxWidth'));
    expect(source, contains('featured ? 22 : 17'));
    expect(source, contains('StellarCompassGlyph(size: featured ? 50 : 42)'));
  });

  test('15-minute auto-update downloads only when due and records success',
      () async {
    var now = DateTime.utc(2026, 10, 19, 5);
    var downloads = 0;
    final downloader = FlClashProfileDownloader(
      mode: VelaSubscriptionDownloadMode.direct,
      requestStep: (uri, route) async {
        downloads++;
        return FlClashProfileResponse(
          HttpStatus.ok,
          Uint8List.fromList(utf8.encode('proxies:\n  - name: Updated\n')),
        );
      },
    );
    final setup = await _setup(
      profiles: [
        VelaStoredProfile(
          id: 'active', name: '当前机场', raw: 'proxies: []',
          updatedAt: now,
        ),
        VelaStoredProfile(
          id: 'scheduled', name: '良心云', raw: 'proxies: []',
          sourceUrl: 'https://subscription.example.test/config',
          autoUpdateMinutes: 15,
          updatedAt: now.subtract(const Duration(minutes: 16)),
        ),
      ],
      activeId: 'active',
      clock: () => now,
      downloader: downloader,
    );
    addTearDown(() async {
      setup.subscription.dispose();
      setup.core.dispose();
      await setup.temp.delete(recursive: true);
    });

    expect(await setup.subscription.checkAutoUpdates(), isTrue);
    expect(downloads, 1);
    final saved = setup.subscription.profiles.singleWhere(
        (profile) => profile.id == 'scheduled');
    expect(saved.updatedAt, now);
    expect(saved.raw, contains('Updated'));

    expect(await setup.subscription.checkAutoUpdates(), isFalse);
    expect(downloads, 1);
    now = now.add(const Duration(minutes: 14));
    expect(await setup.subscription.checkAutoUpdates(), isFalse);
    expect(downloads, 1);
    now = now.add(const Duration(minutes: 1));
    expect(await setup.subscription.checkAutoUpdates(), isTrue);
    expect(downloads, 2);
  });

  test('failed auto-update retries at its interval, not every minute',
      () async {
    var now = DateTime.utc(2026, 10, 19, 5);
    var downloads = 0;
    var fail = true;
    final downloader = FlClashProfileDownloader(
      mode: VelaSubscriptionDownloadMode.direct,
      requestStep: (uri, route) async {
        downloads++;
        if (fail) {
          return FlClashProfileResponse(HttpStatus.serviceUnavailable,
              Uint8List(0));
        }
        return FlClashProfileResponse(
          HttpStatus.ok,
          Uint8List.fromList(utf8.encode('proxies:\n  - name: Updated\n')),
        );
      },
    );
    final setup = await _setup(
      profiles: [
        VelaStoredProfile(
          id: 'active', name: '当前机场', raw: 'proxies: []',
          updatedAt: now,
        ),
        VelaStoredProfile(
          id: 'scheduled', name: '良心云', raw: 'proxies: []',
          sourceUrl: 'https://subscription.example.test/config',
          autoUpdateMinutes: 15,
          updatedAt: now.subtract(const Duration(minutes: 16)),
        ),
      ],
      activeId: 'active',
      clock: () => now,
      downloader: downloader,
    );
    addTearDown(() async {
      setup.subscription.dispose();
      setup.core.dispose();
      await setup.temp.delete(recursive: true);
    });

    expect(await setup.subscription.checkAutoUpdates(), isFalse);
    expect(downloads, 1);
    now = now.add(const Duration(minutes: 1));
    expect(await setup.subscription.checkAutoUpdates(), isFalse);
    expect(downloads, 1, reason: 'a failed profile must not retry each minute');

    now = now.add(const Duration(minutes: 14));
    fail = false;
    expect(await setup.subscription.checkAutoUpdates(), isTrue);
    expect(downloads, 2);
    expect(setup.subscription.profiles.singleWhere(
        (profile) => profile.id == 'scheduled').updatedAt, now);
  });

  test('auto-update cannot be enabled without a subscription URL', () async {
    final now = DateTime.utc(2026, 10, 19, 5);
    final setup = await _setup(
      profiles: [
        VelaStoredProfile(
          id: 'active', name: '当前机场', raw: 'proxies: []',
          updatedAt: now,
        ),
      ],
      activeId: 'active',
      clock: () => now,
    );
    addTearDown(() async {
      setup.subscription.dispose();
      setup.core.dispose();
      await setup.temp.delete(recursive: true);
    });
    expect(await setup.subscription.updateProfileSettings(
      'active',
      name: '当前机场',
      sourceUrl: null,
      autoUpdateMinutes: 15,
    ), isFalse);
  });
}
