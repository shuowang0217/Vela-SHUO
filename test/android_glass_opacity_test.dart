import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/brand/vela_watercolor_chrome.dart';
import 'package:vela_shuo/src/theme/vela_palettes.dart';

void main() {
  testWidgets('Android oil canvas is opaque, legacy watercolor keeps 50% opacity',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
    await tester.pumpWidget(const MaterialApp(home: Center(
      child: VelaWatercolorSurface(child: Text('Android glass')))));
    final decorated = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(VelaWatercolorSurface),
        matching: find.byType(DecoratedBox)).first,
    );
    final decoration = decorated.decoration as BoxDecoration;
    expect(decoration.gradient, isNotNull);
    final gradient = decoration.gradient! as LinearGradient;
    for (final color in gradient.colors) {
      expect(color.a, closeTo(VelaThemeRuntime.oilPreview ? .96 : .5, .03));
    }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
