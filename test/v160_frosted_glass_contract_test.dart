import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/brand/vela_watercolor_chrome.dart';

void main() {
  testWidgets('all seven home control roles are translucent frosted glass',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final role in VelaOilReliefShape.values) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: VelaOilReliefSurface(
          shape: role, child: const Text('Live clickable content')),
      )));
      expect(find.text('Live clickable content'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsWidgets);
      expect(find.byType(Image), findsNothing);
      final decorated = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(VelaWatercolorSurface),
          matching: find.byType(DecoratedBox)).first);
      final decoration = decorated.decoration as BoxDecoration;
      expect(decoration.image, isNull);
      final gradient = decoration.gradient! as LinearGradient;
      for (final color in gradient.colors) {
        expect(color.a, closeTo(.50, .01));
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('v1.6 styling returns without changing the oil day/night map', () {
    final material = File('lib/src/brand/vela_watercolor_chrome.dart')
      .readAsStringSync();
    final stellar=File('lib/src/stellar/stellar_design.dart')
      .readAsStringSync();
    final toast=File('lib/src/brand/vela_glass_toast.dart')
      .readAsStringSync();
    final app=File('lib/src/app.dart').readAsStringSync();
    final atlas=File('lib/src/home/world_atlas.dart').readAsStringSync();
    final clouds=File('lib/src/home/vela_oil_scene.dart').readAsStringSync();
    expect(material, contains('t.surface.withValues(alpha: .50)'));
    expect(material, contains('sigmaX: 9, sigmaY: 9'));
    expect(material, isNot(contains('Image.asset(asset')));
    expect(stellar, contains('sigmaX: 9'));
    expect(toast, contains('sigmaX: 18, sigmaY: 18'));
    expect(app, contains('VelaVoyageGlyph('));
    expect(atlas, contains('oil_map_night.webp'));
    expect(clouds, contains(r'night_${cloud.file}.png'));
  });
}
