import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Vela 4x2 oil voyage widget is integrated into Android generator', () {
    final generator = File('scripts/configure_android_vpn.py').readAsStringSync();
    final widget = File('native/android/VelaVoyageWidget.kt').readAsStringSync();
    final layout = File('native/android/vela_voyage_widget.xml').readAsStringSync();
    expect(generator, contains('VelaVoyageWidget.kt'));
    expect(generator, contains('vela_voyage_widget_info.xml'));
    expect(generator, contains('prepare_oil_widget.py'));
    expect(widget, contains('VelaVpnService.ACTION_STOP'));
    expect(widget, contains('MainActivity::class.java'));
    expect(widget, contains('"CHINA"'));
    expect(widget, contains('setProgressBar'));
    expect(layout, contains('widget_airport'));
    expect(layout, contains('widget_button'));
    expect(layout, contains('vela_widget_oil'));
  });
}
