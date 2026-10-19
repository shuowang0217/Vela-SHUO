import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selected airport sorts first without resizing its card', () {
    final source =
        File('lib/src/stellar/vela_stellar_config_page.dart').readAsStringSync();
    expect(source, contains('...profiles.where((p) => p.id == activeId)'));
    expect(source, contains('...profiles.where((p) => p.id != activeId)'));
    expect(source, contains('return Wrap(spacing: 12, runSpacing: 12'));
    expect(source, contains('SizedBox(width: cardWidth'));
    expect(source, contains('padding: const EdgeInsets.all(17)'));
    expect(source, contains('const StellarCompassGlyph(size: 42)'));
    expect(source, isNot(contains('featured: true')));
    expect(source, contains('if (selected)'));
    expect(source, contains('t.accent.withValues(alpha: .52)'));
    expect(source, contains('代理正在使用'));
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
