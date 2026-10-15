import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/subscription/vela_profile_library.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_vault.dart';

void main() {
  test('encrypted source URL and auto-update survive app restart', () async {
    final vault = VelaMemoryProfileVault();
    final library = VelaProfileLibrary(vault);
    const source = 'https://example.test/sub?token=secret-value';
    const profile = VelaStoredProfile(id: 'a', name: 'Airport',
        raw: 'proxies: []', sourceUrl: source, autoUpdateMinutes: 1440);
    await library.write([profile], 'a');
    final saved = (await library.read()).profiles.single;
    expect(saved.sourceUrl, source);
    expect(saved.autoUpdateMinutes, 1440);
    expect(saved.copyWith(name: 'Renamed').sourceUrl, source);
    expect(saved.copyWith(disableAutoUpdate: true).autoUpdateMinutes, isNull);
    expect(saved.copyWith(clearSourceUrl: true).sourceUrl, isNull);
    expect(VelaStoredProfile.isSafeSubscriptionUrl('http://example.test'), false);
    expect(VelaStoredProfile.isSafeSubscriptionUrl('https://localhost/sub'), false);
    expect(VelaStoredProfile.isSafeSubscriptionUrl('https://127.0.0.1/sub'), false);
  });

  test('encrypted library persists separate subscription selections', () async {
    final vault = VelaMemoryProfileVault();
    final library = VelaProfileLibrary(vault);
    const one = VelaStoredProfile(
        id: 'a', name: 'Japan', raw: 'proxies: jp',
        selectedName: 'JP1', favorites: ['JP2']);
    const two = VelaStoredProfile(
        id: 'b', name: 'US', raw: 'proxies: us',
        selectedName: 'US3', favorites: ['US4']);
    await library.write([one, two], 'b');
    final stored = await library.read();
    expect(stored.activeId, 'b');
    expect(stored.profiles.map((e) => e.name), ['Japan', 'US']);
    expect(stored.profiles[0].selectedName, 'JP1');
    expect(stored.profiles[1].favorites, ['US4']);
    expect(vault.data, isNot(contains('https://example.test?token=')));

    await library.write([one], 'a');
    final afterDelete = await library.read();
    expect(afterDelete.profiles, hasLength(1));
    expect(afterDelete.activeId, 'a');
  });

  test('malformed and duplicate encrypted index is rejected', () async {
    final vault = VelaMemoryProfileVault();
    final library = VelaProfileLibrary(vault);
    await vault.write(jsonEncode({
      'v': 1, 'activeId': 'x', 'profiles': [
        {'id': 'x', 'name': 'A', 'raw': 'a'},
        {'id': 'x', 'name': 'B', 'raw': 'b'},
      ],
    }));
    await expectLater(library.read(), throwsFormatException);
  });

  test('empty vault and invalid active id fail safely', () async {
    final vault = VelaMemoryProfileVault();
    final library = VelaProfileLibrary(vault);
    expect((await library.read()).profiles, isEmpty);
    await library.write([
      const VelaStoredProfile(id: 'p', name: 'P', raw: 'config')
    ], 'invalid');
    final restored = await library.read();
    expect(restored.activeId, isNull);
    expect(restored.profiles.single.name, 'P');
  });

  test('profile count limit is enforced before writing', () async {
    final vault = VelaMemoryProfileVault();
    final library = VelaProfileLibrary(vault);
    await expectLater(
      library.write([
        for (var i = 0; i < 21; i++)
          VelaStoredProfile(id: '$i', name: 'Profile $i', raw: 'config')
      ], null),
      throwsFormatException,
    );
  });
}
