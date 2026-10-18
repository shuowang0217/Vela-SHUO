import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/brand/vela_watercolor_chrome.dart';
import 'package:vela_shuo/src/theme/vela_palettes.dart';

void main() {
  test('approved oil artwork becomes four real transparent HUD assets', () {
    for (final name in [
      'connection_plaque.png', 'speed_plaque.png',
      'paint_medallion.png', 'power_medallion.png',
      'oil_nav_book.png','oil_nav_compass.png','oil_nav_helm.png',
    ]) {
      final file = File('assets/oil/ui/$name');
      expect(file.existsSync(), isTrue, reason: name);
      expect(file.lengthSync(), greaterThan(10000), reason: name);
    }
    final pigment = File('assets/oil/ui/oil_canvas.webp');
    expect(pigment.existsSync(), isTrue);
    expect(pigment.lengthSync(), greaterThan(5000));
  });

  testWidgets('painted plaque retains live Flutter status', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(
        child: VelaOilReliefSurface(
          shape: VelaOilReliefShape.connection,
          child: Text('ACTIVE VPN'),
        ),
      )),
    ));
    await tester.pump();
    expect(find.text('ACTIVE VPN'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsWidgets);
    expect(find.byType(VelaOilReliefSurface), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('both responsive homes wire all four painted components', () {
    final source=File('lib/src/app.dart').readAsStringSync();
    final map=File('lib/src/home/world_atlas.dart').readAsStringSync();
    final clouds=File('lib/src/home/vela_oil_scene.dart').readAsStringSync();
    expect(map,contains("Image.asset('assets/oil/oil_map_clean.webp'"));
    expect(map,contains("Image.asset('assets/oil/oil_map_night.webp'"));
    expect(clouds,contains("'assets/oil/clouds/night_"));
    expect(File('assets/oil/oil_map_night.webp').existsSync(),isTrue);
    for (final cloud in [
      'cloud_beijing_clean','cloud_north','cloud_east',
      'cloud_southwest','cloud_equator','cloud_southeast_clean',
    ]) {
      expect(File('assets/oil/clouds/night_$cloud.png').existsSync(),isTrue);
    }
    expect(clouds,contains("file:'cloud_beijing_clean'"));
    expect(clouds, isNot(contains("file:'cloud_beijing',")));
    expect(File('assets/oil/clouds/cloud_beijing_clean.png').existsSync(),
        isTrue);
    expect(source,contains('shape: VelaOilReliefShape.connection'));
    expect(source,contains('shape: VelaOilReliefShape.speed'));
    expect(source,contains('1 => VelaOilReliefShape.medallion'));
    expect(source,contains('shape: VelaOilReliefShape.power'));
    expect(source,contains('VelaOilReliefShape.book'));
    expect(source,contains('VelaOilReliefShape.compass'));
    expect(source,contains('VelaOilReliefShape.helm'));
    expect(source,contains('VelaThemeRuntime.oilPreview'));
    expect(File('assets/oil/ui/reference_atlas.webp').existsSync(),isTrue);
    expect(source,contains("ValueKey('immersive_connection')"));
    expect(source,contains("ValueKey('mobile_oil_status')"));
  });

  test('oil material tint stays sensitive to palette selection', () {
    final mint=VelaThemeRuntime.oilTokens(
      VelaPalette.byId('mint'), Brightness.light);
    final navy=VelaThemeRuntime.oilTokens(
      VelaPalette.byId('navy'),Brightness.light);
    expect(mint.surface,isNot(navy.surface));
    final ui=File('lib/src/brand/vela_watercolor_chrome.dart')
        .readAsStringSync();
    expect(ui,contains('BackdropFilter('));
    expect(ui,contains('t.surface.withValues(alpha: .50)'));
    expect(ui,isNot(contains('Image.asset(asset')));
  });
}
