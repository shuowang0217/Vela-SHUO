import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/app.dart';
import 'package:vela_shuo/src/settings/settings_controller.dart';

void main() {
  testWidgets('no misleading proxy status before engine integration', (tester) async {
    await tester.pumpWidget(VelaShuoApp(settings: SettingsController()));
    await tester.pumpAndSettle();
    expect(find.text('Vela-SHUO'), findsOneWidget);
    expect(find.text('尚未连接'), findsOneWidget);
    expect(find.text('连接功能将在 v0.2 开放'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '连接功能尚未开放'),
    );
    expect(button.onPressed, isNull);
  });
}
