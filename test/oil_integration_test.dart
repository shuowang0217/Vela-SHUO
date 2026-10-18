import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/vela_oil_scene.dart';
import 'package:vela_shuo/src/theme/vela_palettes.dart';
import 'package:vela_shuo/src/home/world_atlas.dart';

void main() {
  test('oil route uses the same georeferenced tiles as the ship', () {
    final source = File('lib/src/home/world_atlas.dart').readAsStringSync();
    expect(source, contains('_WorldTiles(camera: camera,'));
    expect(source, contains('oil_atlas_day.webp'));
    expect(source, contains('oil_atlas_night.webp'));
    expect(File('scripts/prepare_oil_atlas.py').existsSync(), isTrue);
    expect(source, contains('camera.projectAlongArtwork(from, geo)'));
    expect(source, contains('const VelaOilScene()'));
    expect(source, contains("Image.asset('assets/oil/oil_map_clean.webp'"));
    // Only the pure painted MAP image is used; HUD elements remain live.
    expect(source, contains('oilIllustration: VelaThemeRuntime.oilPreview'));
    const camera = VelaWorldCamera(size: Size(1400, 800),
      longitude: 116.4, latitude: 39.9);
    final beijing = camera.projectArtwork(VelaWorldCamera.beijing);
    final tokyo = camera.projectAlongArtwork(
      VelaWorldCamera.beijing, const Offset(139.69, 35.68));
    expect(tokyo.dx, greaterThan(beijing.dx));
  });

  test('oil materials reach screens, dialogs, toasts and menus', () {
    final common = File('lib/src/brand/vela_watercolor_chrome.dart')
        .readAsStringSync();
    final toast = File('lib/src/brand/vela_glass_toast.dart')
        .readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();
    expect(common, contains('sigmaX: 9, sigmaY: 9'));
    expect(common, contains('t.surface.withValues(alpha: .50)'));
    expect(common, isNot(contains('DecorationImage(')));
    expect(toast, contains('BackdropFilter('));
    expect(app, contains('popupMenuTheme: PopupMenuThemeData'));
    expect(app, contains('bottomSheetTheme: BottomSheetThemeData'));
    expect(app, contains("ValueKey('immersive_connection')"));
    expect(app, contains("ValueKey('voyage_speed_panel')"));
    expect(VelaThemeRuntime.oilPreview, isTrue);
  });

  test('clouds are alpha overlays, not the background asset', () {
    final source=File('lib/src/home/vela_oil_scene.dart').readAsStringSync();
    expect(source, contains("assets/oil/clouds/"));
    expect(source, isNot(contains('Image.asset(VelaOilScene.backgroundAsset')));
    expect(VelaOilScene.clouds.every((c) => c.opacity >= .9), isTrue);
  });
}
