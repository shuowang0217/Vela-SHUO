import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/app.dart';
import 'package:vela_shuo/src/brand/vela_watercolor_chrome.dart';
import 'package:vela_shuo/src/home/world_atlas.dart';
import 'package:vela_shuo/src/settings/settings_controller.dart';

void main() {
  testWidgets('all desktop pages share four functional painted oil medallions',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(VelaShuoApp(settings: SettingsController()));
    await tester.pumpAndSettle();
    expect(find.byType(VelaWorldAtlas), findsOneWidget);
    expect(find.byType(VelaVoyageGlyph), findsNothing);
    expect(find.byType(VelaOilReliefSurface), findsAtLeastNWidgets(4));
    for (final target in [1, 4, 2, 3]) {
      expect(find.byKey(ValueKey('nav_$target')), findsOneWidget);
      final surface = find.ancestor(
        of: find.byKey(ValueKey('nav_$target')),
        matching: find.byType(VelaOilReliefSurface));
      expect(surface, findsOneWidget);
    }

    for (final target in [1, 4, 2, 3]) {
      await tester.tap(find.byKey(ValueKey('nav_$target')));
      await tester.pumpAndSettle();
      expect(find.byType(VelaWorldAtlas), findsOneWidget);
      expect(find.byKey(const ValueKey('nav_0')), findsOneWidget);
      expect(find.byType(VelaVoyageGlyph), findsNothing);
    expect(find.byType(VelaOilReliefSurface), findsAtLeastNWidgets(4));
      // Tapping the currently selected module a second time returns Home.
      await tester.tap(find.byKey(ValueKey('nav_$target')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('immersive_connection')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav_0')), findsNothing);
      // Reopen it to exercise switching to the next different module.
      await tester.tap(find.byKey(ValueKey('nav_$target')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('nav_0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('immersive_connection')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav_0')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
