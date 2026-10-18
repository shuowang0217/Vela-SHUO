import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/vela_oil_scene.dart';
import 'package:vela_shuo/src/theme/vela_palettes.dart';

void main() {
  test('oil palette switching changes pigments and preserves dark mode', () {
    final mint = VelaPalette.byId('mint');
    final rose = VelaPalette.byId('rose');
    final mintDay = VelaThemeRuntime.oilTokens(mint, Brightness.light);
    final roseDay = VelaThemeRuntime.oilTokens(rose, Brightness.light);
    final mintNight = VelaThemeRuntime.oilTokens(mint, Brightness.dark);
    expect(mintDay.surface, isNot(roseDay.surface));
    expect(mintDay.accent, isNot(roseDay.accent));
    expect(mintDay.dark, false);
    expect(mintNight.dark, true);
    expect(mintNight.background, isNot(mintDay.background));
    VelaThemeRuntime.select(mint, Brightness.light);
    expect(VelaThemeRuntime.active.accent, mintDay.accent);
    VelaThemeRuntime.select(rose, Brightness.light);
    expect(VelaThemeRuntime.active.accent, roseDay.accent);
    VelaThemeRuntime.select(
        VelaPalette.byId(VelaPalette.defaultId), Brightness.dark);
  });

  testWidgets('six detached cloud sprites actually drift in a few seconds',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: VelaOilScene(debugAllowTestWind: true)),
    ));
    await tester.pump();
    final cloud = find.byKey(const ValueKey('oil_cloud_cloud_north'));
    final movement = find.descendant(
        of: cloud, matching: find.byType(Transform)).first;
    final start = tester.widget<Transform>(movement).transform.getTranslation();
    await tester.pump(const Duration(seconds: 4));
    final finish = tester.widget<Transform>(movement).transform.getTranslation();
    final moved = (Offset(start.x, start.y) -
        Offset(finish.x, finish.y)).distance;
    expect(moved, greaterThan(4));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('all major panels and import notifications use painterly surfaces', () {
    final shell = File('lib/src/app.dart').readAsStringSync();
    final shared =
        File('lib/src/brand/vela_watercolor_chrome.dart').readAsStringSync();
    final stellar = File('lib/src/stellar/stellar_design.dart')
        .readAsStringSync();
    final importing = File('lib/src/stellar/vela_stellar_import_dialog.dart')
        .readAsStringSync();
    final toast = File('lib/src/brand/vela_glass_toast.dart')
        .readAsStringSync();
    expect(shell, contains('VelaThemeRuntime.active.dark'));
    expect(shared, contains("AssetImage('assets/oil/oil_map_clean.webp')"));
    expect(shared, contains('c.drawPath(stroke, impasto)'));
    expect(stellar, contains('VelaWatercolorSurface('));
    expect(importing, contains('child: VelaWatercolorSurface('));
    expect(toast, contains('color:paint.accent'));
  });
}
