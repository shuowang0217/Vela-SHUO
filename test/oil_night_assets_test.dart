import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/vela_oil_scene.dart';
import 'package:vela_shuo/src/theme/vela_palettes.dart';

void main() {
  test('night map and six moonlit clouds are actually different assets', () {
    final day = File('assets/oil/oil_map_clean.webp');
    final night = File('assets/oil/oil_map_night.webp');
    expect(day.existsSync(), isTrue);
    expect(night.existsSync(), isTrue);
    expect(night.lengthSync(), greaterThan(100000));
    expect(night.readAsBytesSync(), isNot(orderedEquals(day.readAsBytesSync())));
    for (final cloud in VelaOilScene.clouds) {
      final dayCloud = File('assets/oil/clouds/${cloud.file}.png');
      final nightCloud = File('assets/oil/clouds/night_${cloud.file}.png');
      expect(nightCloud.existsSync(), isTrue);
      expect(nightCloud.lengthSync(), greaterThan(5000));
      expect(nightCloud.readAsBytesSync(),
          isNot(orderedEquals(dayCloud.readAsBytesSync())));
    }
  });

  test('nighttime image-based modules retain transparent live controls', () {
    final panel = File('lib/src/brand/vela_watercolor_chrome.dart')
        .readAsStringSync();
    expect(panel, contains('ImageFilter.blur(sigmaX: 9, sigmaY: 9)'));
    expect(panel, contains('t.surface.withValues(alpha: .42)'));
    expect(panel, isNot(contains('oil_canvas_night.webp')));
    final map = File('lib/src/home/world_atlas.dart').readAsStringSync();
    expect(map, contains("asset: 'assets/oil/oil_map_night.webp'"));
    expect(map, contains('opacity: dark ? 1.0 : 0.0'));
    final clouds = File('lib/src/home/vela_oil_scene.dart')
        .readAsStringSync();
    expect(clouds, contains(r"night_${cloud.file}.png"));
    expect(File('scripts/prepare_oil_night.py').readAsStringSync(),
        contains('urban_lights('));
  });

  test('all eight palettes permit actual dark-mode oil materials', () {
    for (final palette in VelaPalette.all) {
      expect(VelaThemeRuntime.oilTokens(palette, Brightness.light).dark,
          isFalse);
      expect(VelaThemeRuntime.oilTokens(palette, Brightness.dark).dark,
          isTrue);
      expect(VelaThemeRuntime.oilTokens(palette, Brightness.dark).background,
          isNot(VelaThemeRuntime.oilTokens(
            palette, Brightness.light).background));
    }
  });
}
