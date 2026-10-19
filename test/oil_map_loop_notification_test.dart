import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/world_atlas.dart';
import 'package:vela_shuo/src/brand/vela_glass_toast.dart';
import 'package:vela_shuo/src/theme/vela_palettes.dart';

void main() {
  test('oil tiles cover full height and stay continuous at longitude wrap', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      for (final size in [const Size(390, 844), const Size(844, 390)]) {
        final scale = math.max(size.width / 1672, size.height / 941);
        final camera = VelaWorldCamera(
          size: size, longitude: 116.4, latitude: 39.9,
          oilIllustration: true);
        expect(camera.oilImageScale, closeTo(scale, .00001));
        expect(camera.oilImageOrigin.dy, lessThanOrEqualTo(0));
        expect(camera.oilImageOrigin.dy + 941 * scale,
            greaterThanOrEqualTo(size.height));

        // Adjacent geographic points at either side of the Pacific map seam
        // must use neighboring raster copies, not jump an entire map width.
        final west = camera.projectArtwork(const Offset(-64.1, 37.0));
        final east = camera.projectArtwork(const Offset(-63.1, 37.0));
        expect((east.dx - west.dx).abs(), lessThan(55));
        final project = camera.seaLaneProjector(
            const Offset(-64.1, 37.0), const Offset(-63.1, 37.0));
        final p = project(const Offset(-64.1, 37.0));
        final q = project(const Offset(-63.1, 37.0));
        expect((p.dx - q.dx).abs(), lessThan(55));
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('every short in-app notice uses top floating popup, not a SnackBar', () {
    for (final entity in Directory('lib/src')
        .listSync(recursive: true).whereType<File>()) {
      if (!entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      expect(source, isNot(contains('showSnackBar(')),
          reason: entity.path);
      expect(source, isNot(contains('ScaffoldMessenger.of(')),
          reason: entity.path);
    }
    final source = File('lib/src/brand/vela_glass_toast.dart')
        .readAsStringSync();
    expect(source, contains('VelaThemeRuntime.active'));
    // Confirmation dialogs requiring explicit permission remain modal.
    expect(File('lib/src/smart/vela_smart_panel.dart').readAsStringSync(),
        contains('AlertDialog('));
  });

  testWidgets('floating toast wash and icon follow selected theme',
      (tester) async {
    Color? first;
    await tester.pumpWidget(MaterialApp(home: Builder(
      builder: (context) => Scaffold(body: TextButton(
        onPressed: () => VelaGlassToast.show(context, '通知内容'),
        child: const Text('显示'),
      )),
    )));
    for (final name in ['mint', 'rose']) {
      VelaThemeRuntime.select(VelaPalette.byId(name), Brightness.light);
      await tester.tap(find.text('显示'));
      await tester.pump(const Duration(milliseconds: 300));
      final decorated = tester.widgetList<DecoratedBox>(find.descendant(
        of: find.byKey(const ValueKey('vela_glass_toast')),
        matching: find.byType(DecoratedBox))).where((box) =>
            (box.decoration as BoxDecoration).gradient is LinearGradient);
      final colors = ((decorated.single.decoration as BoxDecoration)
          .gradient! as LinearGradient).colors;
      if (first == null) {
        first = colors.first;
      } else {
        expect(colors.first, isNot(first));
      }
      VelaGlassToast.dismiss();
      await tester.pump();
    }
  });
}
