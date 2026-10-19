import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/painted_ocean_route.dart';
import 'package:vela_shuo/src/home/world_atlas.dart';

void main() {
  test('oil focus pans smoothly instead of snapping on connection', () {
    const idle = VelaWorldCamera(
      size: Size(390, 844), longitude: 116.4, latitude: 39.9,
      oilIllustration: true);
    const connecting = VelaWorldCamera(
      size: Size(390, 844), longitude: 116.4, latitude: 39.9,
      oilIllustration: true, focusOil: true);
    expect(idle.oilImageOrigin, connecting.oilImageOrigin);

    // Sample successive frames of the 1.8 s ease-in/out focus animation.
    final origin = idle.oilImageOrigin;
    var previous = origin.dx;
    for (var i = 1; i <= 40; i++) {
      final fraction = Curves.easeInOutCubic.transform(i / 40);
      final cam = VelaWorldCamera(
        size: const Size(390, 844),
        longitude: 116.4 +
            VelaWorldCamera.shortestDelta(116.4, -118.24) * fraction,
        latitude: 39.9 + (34.05 - 39.9) * fraction,
        oilIllustration: true, focusOil: true);
      expect((cam.oilImageOrigin.dx - previous).abs(), lessThan(90),
          reason: 'A focus frame must not jump to another world copy');
      previous = cam.oilImageOrigin.dx;
    }
    expect((previous - origin.dx).abs(), greaterThan(100));
  });

  test('oil focus crosses date line continuously and reuses the same tile',
      () {
    const a = VelaWorldCamera(
      size: Size(390,844), longitude: 179.9, latitude: 34.0,
      oilIllustration: true);
    const b = VelaWorldCamera(
      size: Size(390,844), longitude: 180.1, latitude: 34.0,
      oilIllustration: true);
    expect((a.oilImageOrigin.dx - b.oilImageOrigin.dx).abs(), lessThan(10));
    final aPin = a.projectArtwork(const Offset(-118.24,34.05));
    final bPin = b.projectArtwork(const Offset(-118.24,34.05));
    expect((aPin.dx-bPin.dx).abs(), lessThan(10));
  });

  test('visual A-star connects ocean pixels without tracing land', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final sea = VelaPaintedOceanRoute.instance;
    await sea.initialize();
    expect(sea.ready, isTrue);
    const camera = VelaWorldCamera(
      size: Size(390,844), longitude: 116.4, latitude: 39.9,
      oilIllustration: true);
    for (final city in [
      const Offset(139.69,35.68),
      const Offset(-.13,51.5),
      const Offset(-118.24,34.05),
    ]) {
      final pixels = sea.routePixels(
        camera.oilCanvasPosition(const Offset(116.4,39.9)),
        camera.oilCanvasPosition(city));
      expect(pixels.length, greaterThan(2));
      final path = camera.paintedRoutePath(
          const Offset(116.4,39.9), city);
      expect(path.computeMetrics().isNotEmpty, isTrue);
      final metric = path.computeMetrics().first;
      expect(metric.length, greaterThan(0));
      final half = camera.paintedRoutePath(
          const Offset(116.4,39.9), city, until: .5);
      expect(half.computeMetrics().first.length,
          closeTo(metric.length / 2, 1.0));
    }
  });
}
