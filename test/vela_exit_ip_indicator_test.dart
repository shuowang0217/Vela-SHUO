import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/network/vela_exit_ip_indicator.dart';
import 'package:vela_shuo/src/network/vela_exit_ip_monitor.dart';

void main() {
  Widget subject(VelaExitIpInfo? info, String status) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 250,
          child: VelaExitIpIndicator(
            info: info,
            statusText: status,
            accentColor: Colors.blue,
            mutedColor: Colors.grey,
          ),
        ),
      ),
    );
  }

  testWidgets('Japan shows an oil-painted local flag instead of JP or emoji',
      (tester) async {
    await tester.pumpWidget(subject(
      const VelaExitIpInfo(
        address: '43.206.160.247',
        countryCode: 'JP',
      ),
      'JP 43.206.160.247',
    ));
    expect(find.byType(VelaOilFlag), findsOneWidget);
    expect(find.byKey(const ValueKey('vela_exit_oil_flag')), findsOneWidget);
    expect(find.byType(CountryFlag), findsOneWidget);
    expect(find.byType(VelaOilFlagTexturePainter), findsNothing);
    expect(
      find.byKey(const ValueKey('vela_oil_flag_brush_texture')),
      findsOneWidget,
    );
    expect(find.text('43.206.160.247'), findsOneWidget);
    expect(find.textContaining('JP 43.'), findsNothing);
    expect(find.textContaining('🇯🇵'), findsNothing);
  });

  testWidgets('all eight primary airport flags use local graphical artwork',
      (tester) async {
    for (final code in const ['JP', 'US', 'SG', 'HK', 'TW', 'KR', 'GB', 'DE']) {
      await tester.pumpWidget(subject(
        VelaExitIpInfo(address: '203.0.113.20', countryCode: code),
        'irrelevant',
      ));
      expect(find.byType(CountryFlag), findsOneWidget, reason: code);
      expect(find.byType(VelaOilFlag), findsOneWidget, reason: code);
    }
  });

  testWidgets('unsupported country uses painted fallback, no missing asset',
      (tester) async {
    await tester.pumpWidget(subject(
      const VelaExitIpInfo(address: '203.0.113.4', countryCode: 'XX'),
      'irrelevant',
    ));
    expect(find.byType(CountryFlag), findsNothing);
    expect(find.byKey(const ValueKey('vela_exit_flag_fallback')), findsOneWidget);
    expect(find.text('XX'), findsOneWidget);
  });

  testWidgets('timeout is text without flag', (tester) async {
    await tester.pumpWidget(subject(null, 'timeout'));
    expect(find.text('timeout'), findsOneWidget);
    expect(find.byType(VelaOilFlag), findsNothing);
    expect(find.byType(CountryFlag), findsNothing);
  });
}
