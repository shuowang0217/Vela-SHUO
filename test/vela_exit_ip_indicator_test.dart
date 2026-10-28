import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/network/vela_exit_ip_indicator.dart';
import 'package:vela_shuo/src/network/vela_exit_ip_monitor.dart';

void main() {
  Widget subject(VelaExitIpInfo? info, String status) {
    return MaterialApp(home: Scaffold(body: SizedBox(
      width: 250,
      child: VelaExitIpIndicator(
        info: info,
        statusText: status,
        accentColor: Colors.blue,
        mutedColor: Colors.grey,
      ),
    )));
  }

  testWidgets('shows a graphic Japanese flag instead of Windows JP letters',
      (tester) async {
    await tester.pumpWidget(subject(
      const VelaExitIpInfo(address: '43.206.160.247', countryCode: 'JP'),
      '🇯🇵 43.206.160.247',
    ));
    expect(find.byType(CountryFlag), findsOneWidget);
    expect(find.byKey(const ValueKey('vela_exit_country_flag')), findsOneWidget);
    expect(find.text('43.206.160.247'), findsOneWidget);
    expect(find.textContaining('🇯🇵'), findsNothing);
    expect(find.textContaining('JP 43.'), findsNothing);
  });

  testWidgets('timeout is plain text without a flag', (tester) async {
    await tester.pumpWidget(subject(null, 'timeout'));
    expect(find.text('timeout'), findsOneWidget);
    expect(find.byType(CountryFlag), findsNothing);
  });
}
