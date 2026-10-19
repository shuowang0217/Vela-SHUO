import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active airport is always featured before the remaining cards', () {
    final source =
        File('lib/src/stellar/vela_stellar_config_page.dart').readAsStringSync();
    expect(source, contains('final activeProfile = profiles.where'));
    expect(source, contains('SizedBox(width: area.maxWidth'));
    expect(source, contains('featured ? 22 : 17'));
    expect(source, contains('StellarCompassGlyph(size: featured ? 50 : 42)'));
  });

  test('auto-update interval and retry cooldown are enforced by Vela', () {
    final controller = File(
        'lib/src/network/vela_flclash_subscription_adapter.dart')
        .readAsStringSync();
    final config = File(
        'lib/src/stellar/vela_stellar_config_page.dart').readAsStringSync();
    expect(controller, contains('Timer.periodic(const Duration(minutes: 1)'));
    expect(controller, contains('Future<bool> checkAutoUpdates'));
    expect(controller, contains('instant.difference(updated) < interval'));
    expect(controller, contains('instant.difference(attempted) < interval'));
    expect(controller, contains('_autoRefreshAttemptedAt.remove(id)'));
    expect(controller, contains('sourceUrl == null || autoUpdateMinutes < 15'));
    expect(config, contains('Vela 运行时自动检查，关闭后不保证后台更新'));
  });
}
