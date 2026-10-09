import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/app.dart';
import 'package:vela_shuo/src/settings/settings_controller.dart';

void main() {
  test('the approved poetic tagline is a single shared constant', () {
    expect(velaBrandTagline, '一帆越洋，尽览四方。');
  });

  testWidgets('desktop displays only approved hero branding', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      VelaShuoApp(settings: SettingsController()),
    );
    await tester.pump();

    expect(find.text('VELA'), findsWidgets);
    expect(find.text('— SHUO —'), findsWidgets);
    expect(find.text(velaBrandTagline), findsOneWidget);
    expect(find.text('INTELLIGENT CONNECTIVITY'), findsNothing);
    expect(find.text('更 自 由 的 连 接 世 界'), findsNothing);
    expect(find.text('更自由的连接世界'), findsNothing);
    expect(find.textContaining('智能路由，畅行全球'), findsNothing);
    // Removing the old tagline must not remove the simulation disclosure.
    expect(find.textContaining('UI 演示'), findsWidgets);
  });

  testWidgets('narrow dashboard preserves the approved tagline', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(780, 860);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      VelaShuoApp(settings: SettingsController()),
    );
    await tester.pump();

    expect(find.text('Vela-SHUO'), findsOneWidget);
    expect(find.text(velaBrandTagline), findsOneWidget);
    expect(find.text('INTELLIGENT CONNECTIVITY'), findsNothing);
    expect(find.textContaining('UI 演示'), findsWidgets);
  });
}
