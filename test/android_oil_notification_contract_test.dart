import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Samsung One UI notification has no doubled brand or embedded buttons',
      () {
    final native = File('native/android/VelaVpnService.kt').readAsStringSync();
    final build = File('scripts/configure_android_vpn.py').readAsStringSync();
    final art = File('scripts/prepare_oil_notification.py').readAsStringSync();
    final compact = File('native/android/vela_notification_compact.xml')
        .readAsStringSync();
    final expanded = File('native/android/vela_notification_expanded.xml')
        .readAsStringSync();
    expect(native, contains('setCustomContentView(compact)'));
    expect(native, contains('setCustomBigContentView(expanded)'));
    expect(native, contains('Notification.DecoratedCustomViewStyle()'));
    expect(native, contains('R.drawable.vela_notification_oil_day'));
    expect(native, contains('R.drawable.vela_notification_oil_night'));
    expect(native, contains('R.id.vela_notice_up'));
    expect(native, contains('R.id.vela_notice_down'));
    expect(native, contains('2L, TimeUnit.SECONDS'));
    expect(native, isNot(contains('R.id.vela_notice_icon')));
    expect(build, contains('scripts/prepare_oil_notification.py'));
    expect(build, contains('notification_oil_'));
    expect(build, isNot(contains('connection_plaque.png')));
    expect(art, contains('oil_canvas.webp'));
    expect(art, isNot(contains('connection_plaque.png')));
    expect(art, contains('GaussianBlur'));
    for (final layout in [compact, expanded]) {
      expect(layout, contains('@+id/vela_notice_title'));
      expect(layout, contains('@+id/vela_notice_up'));
      expect(layout, contains('@+id/vela_notice_down'));
      expect(layout, isNot(contains('vela_notice_icon')));
      expect(layout, isNot(contains('vela_notice_scrim')));
    }
  });
}
