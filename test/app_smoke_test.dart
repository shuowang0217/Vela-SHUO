import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/app.dart';
import 'package:vela_shuo/src/settings/settings_controller.dart';

void main() {
  testWidgets('the globe dashboard is clearly identified as UI-only', (tester) async {
    await tester.pumpWidget(
      VelaShuoApp(settings: SettingsController()),
    );
    await tester.pump();
    expect(find.text('VELA'), findsOneWidget);
    expect(find.textContaining('UI 演示'), findsWidgets);
    expect(find.byType(MaterialApp), findsOneWidget);
    // A simulated node must never be described as a real VPN connection.
    expect(find.text('连接已保护'), findsNothing);
  });
}
