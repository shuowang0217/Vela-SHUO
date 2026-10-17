import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/app.dart';
import 'package:vela_shuo/src/home/world_atlas.dart';
import 'package:vela_shuo/src/settings/settings_controller.dart';

void main() {
  testWidgets('immersive desktop preserves world map and opens pages from dock',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1366, 768);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(VelaShuoApp(settings: SettingsController()));
    await tester.pump();
    expect(find.byType(VelaWorldAtlas), findsOneWidget);
    expect(find.byKey(const ValueKey('immersive_connection')), findsOneWidget);
    expect(find.byKey(const ValueKey('voyage_speed_panel')), findsOneWidget);
    expect(find.text('风速 · 上传'), findsOneWidget);
    expect(find.text('航速 · 下载'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav_1')));
    await tester.pumpAndSettle();
    expect(find.byType(VelaWorldAtlas), findsOneWidget);
    expect(find.byKey(const ValueKey('voyage_speed_panel')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nav_0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('voyage_speed_panel')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
