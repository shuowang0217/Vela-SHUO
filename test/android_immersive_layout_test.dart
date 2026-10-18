import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/app.dart';
import 'package:vela_shuo/src/brand/vela_watercolor_chrome.dart';
import 'package:vela_shuo/src/home/world_atlas.dart';
import 'package:vela_shuo/src/settings/settings_controller.dart';

void main() {
  testWidgets('mobile shows watercolored world and detached four-button dock',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(VelaShuoApp(settings: SettingsController()));
    await tester.pump();
    expect(find.byType(VelaWorldAtlas), findsOneWidget);
    expect(find.text('VELA'), findsOneWidget);
    expect(find.text('— SHUO —'), findsNothing);
    expect(find.text('风速 · 上传'), findsOneWidget);
    expect(find.text('航速 · 下载'), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile_connect_button')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(VelaVoyageGlyph), findsNothing);
    expect(find.byType(VelaOilReliefSurface), findsAtLeastNWidgets(4));
    for (final i in [1, 4, 2, 3]) {
      expect(find.byKey(ValueKey('nav_$i')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('nav_4')));
    await tester.pumpAndSettle();
    expect(find.text('配置管理'), findsOneWidget);
    expect(find.byKey(const ValueKey('nav_0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav_0')));
    await tester.pumpAndSettle();
    expect(find.text('风速 · 上传'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('narrow phone can reach connection and navigation',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(VelaShuoApp(settings: SettingsController()));
    await tester.pump();
    expect(find.byKey(const ValueKey('mobile_connect_button')), findsOneWidget);
    expect(find.byKey(const ValueKey('voyage_speed_panel')), findsOneWidget);
    expect(find.byType(VelaVoyageGlyph), findsNothing);
    expect(find.byType(VelaOilReliefSurface), findsAtLeastNWidgets(4));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
