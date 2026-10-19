import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android oil notification uses real static painted assets', () {
    final service = File('native/android/VelaVpnService.kt').readAsStringSync();
    final script = File('scripts/configure_android_vpn.py').readAsStringSync();
    for (final text in [
      'setCustomContentView(compact)',
      'setCustomBigContentView(expanded)',
      'Notification.DecoratedCustomViewStyle()',
      'R.drawable.vela_notification_oil_day',
      'R.drawable.vela_notification_oil_night',
      'R.drawable.vela_notification_brand',
      'views.setTextViewText(R.id.vela_notice_rates, rates)',
      '2L, TimeUnit.SECONDS',
    ]) {
      expect(service, contains(text));
    }
    for (final text in [
      'assets/oil/ui/connection_plaque.png',
      'assets/oil/ui/night_connection_plaque.png',
      'assets/brand/vela_selected_icon.png',
      'drawable-nodpi',
      'vela_notification_compact.xml',
      'vela_notification_expanded.xml',
    ]) {
      expect(script, contains(text));
    }
    expect(File('native/android/vela_notification_compact.xml').existsSync(), true);
    expect(File('native/android/vela_notification_expanded.xml').existsSync(), true);
    expect(service, isNot(contains('SYSTEM_ALERT_WINDOW')));
  });
}
