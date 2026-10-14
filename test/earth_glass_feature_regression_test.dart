import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/app.dart';
import 'package:vela_shuo/src/home/world_atlas.dart';
import 'package:vela_shuo/src/settings/settings_controller.dart';

void main() {
  testWidgets('single Earth canvas persists across dashboard and config tabs',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      VelaShuoApp(settings: SettingsController()),
    );
    await tester.pump();
    expect(find.byType(VelaWorldAtlas), findsOneWidget);
    expect(find.text(velaBrandTagline), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav_4')));
    await tester.pump();
    expect(find.byType(VelaWorldAtlas), findsOneWidget);
    expect(find.text('配置管理'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav_0')));
    await tester.pump();
    expect(find.byType(VelaWorldAtlas), findsOneWidget);
  });
}
