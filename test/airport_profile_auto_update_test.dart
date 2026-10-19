import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/demo_connection.dart';
import 'package:vela_shuo/src/network/flclash_core_api.dart';
import 'package:vela_shuo/src/network/flclash_windows_backend.dart';
import 'package:vela_shuo/src/network/vela_flclash_core_adapter.dart';
import 'package:vela_shuo/src/network/vela_flclash_subscription_adapter.dart';
import 'package:vela_shuo/src/stellar/stellar_design.dart';
import 'package:vela_shuo/src/stellar/vela_stellar_config_page.dart';
import 'package:vela_shuo/src/subscription/flclash_profile_downloader.dart';
import 'package:vela_shuo/src/subscription/vela_profile_library.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_vault.dart';
import 'package:vela_shuo/src/theme/vela_palettes.dart';

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
    profileVault: vault,
    downloader: downloader,
    clock: clock,
  );
  expect(await subscription.restoreSaved(), isTrue);
  return (
    temp: temp,
    core: core,
    subscription: subscription,
    vault: vault,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('active airport is always first and enlarged on shared UI',
      (tester) async {
    var now = DateTime.utc(2026, 10, 19, 5);
    await tester.binding.setSurfaceSize(const Size(1180, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final setup = await _setup(
      profiles: [
        VelaStoredProfile(
          id: 'newer', name: '牛逼', raw: 'proxies: []',
          updatedAt: now,
        ),
        VelaStoredProfile(
          id: 'active', name: '良心云', raw: 'proxies: []',
          updatedAt: now.subtract(const Duration(hours: 2)),
        ),
      ],
      activeId: 'active',
      clock: () => now,
    );
    final demo = VelaDemoController();
    addTearDown(() {
      demo.dispose();
      setup.subscription.dispose();
      setup.core.dispose();
      setup.temp.delete(recursive: true);
    });
    VelaThemeRuntime.select(VelaPalette.byId('ocean'), Brightness.light);

    Widget page() => MaterialApp(
      home: Scaffold(
        body: VelaStellarConfigPage(
          demo: demo,
          core: setup.core,
          subscription: setup.subscription,
        ),
      ),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('airport_card_active'));
    final other = find.byKey(const ValueKey('airport_card_newer'));
    expect(active, findsOneWidget);
    expect(other, findsOneWidget);
    expect(tester.getTopLeft(active).dy, lessThan(tester.getTopLeft(other).dy));
    expect(tester.getSize(active).width,
        greaterThan(tester.getSize(other).width * 1.5));

    // The same shared configuration page remains correctly ordered on narrow
    // Android layouts; the selected card uses the larger compass treatment.
    await tester.binding.setSurfaceSize(const Size(470, 1300));
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(active).dy, lessThan(tester.getTopLeft(other).dy));
    final activeGlyph = tester.widget<StellarCompassGlyph>(
      find.descendant(of: active, matching: find.byType(StellarCompassGlyph)),
    );
    final otherGlyph = tester.widget<StellarCompassGlyph>(
      find.descendant(of: other, matching: find.byType(StellarCompassGlyph)),
    );
    expect(activeGlyph.size, 50);
    expect(otherGlyph.size, 42);
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
