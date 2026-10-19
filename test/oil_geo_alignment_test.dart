import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/world_atlas.dart';
import 'package:vela_shuo/src/home/maritime_route.dart';

void main() {
  test('calibrated oil canvas landmarks share one image coordinate system', () {
    const camera = VelaWorldCamera(
      size: Size(1672, 941), longitude: 116.4, latitude: 39.9,
      oilIllustration: true,
    );
    final beijing = camera.projectArtwork(VelaWorldCamera.beijing);
    expect(beijing.dx, closeTo(836, .01));
    final tokyo = camera.projectArtwork(const Offset(139.69, 35.68));
    expect(tokyo.dx, greaterThan(beijing.dx + 100));
    expect(tokyo.dy, greaterThan(beijing.dy));
    expect(camera.projectAlongArtwork(VelaWorldCamera.beijing,
        const Offset(139.69, 35.68)), tokyo);
  });

  test('wide idle China pin uses the same cover transform as its map', () {
    const camera = VelaWorldCamera(
      size: Size(1279, 1536), longitude: 116.4, latitude: 39.9,
      oilIllustration: true);
    final scale = camera.oilImageScale;
    // Beijing-centered idle and connected cameras must share one
    // transform, so the first animation frame cannot snap to a new image.
    final focused = VelaWorldCamera(
      size: const Size(1279, 1536), longitude: 116.4, latitude: 39.9,
      oilIllustration: true, focusOil: true);
    expect(camera.oilImageOrigin, focused.oilImageOrigin);
    expect(camera.projectArtwork(VelaWorldCamera.beijing).dx,
        closeTo(1279 / 2, .001));
    expect(camera.oilImageOrigin.dy, lessThanOrEqualTo(0));
    expect(camera.oilImageOrigin.dy + 941 * scale,
        greaterThanOrEqualTo(1536));
  });

  test('v1.6-like focus centers every selected node on oil panorama', () {
    for (final node in [
      const Offset(139.69, 35.68), // Tokyo
      const Offset(-0.13, 51.5), // London
      const Offset(-118.24, 34.05), // Los Angeles
      const Offset(103.8, 1.3), // Singapore
    ]) {
      final camera = VelaWorldCamera(
        size: const Size(390, 844), longitude: node.dx,
        latitude: node.dy, oilIllustration: true, focusOil: true);
      final pin = camera.projectArtwork(node);
      expect(pin.dx, closeTo(195, .001));
      expect(pin.dy, inInclusiveRange(0, 844));
      // The bitmap is not allowed to uncover the screen at top or bottom.
      expect(camera.oilImageOrigin.dy, lessThanOrEqualTo(0));
      expect(camera.oilImageOrigin.dy + 941 * camera.oilImageScale,
          greaterThanOrEqualTo(844));
    }
  });

  test('cover-fit crop is applied identically to background and route', () {
    const screen = Size(1200, 900);
    const camera = VelaWorldCamera(size: screen,
      longitude: 116.4, latitude: 39.9, oilIllustration: true);
    final scale = camera.oilImageScale;
    final start = camera.projectArtwork(VelaWorldCamera.beijing);
    expect((start - (camera.oilImageOrigin +
        VelaWorldCamera.oilBeijing * scale)).distance, lessThan(.001));
    expect(camera.projectAlongArtwork(const Offset(116.4, 39.9),
      const Offset(139.69, 35.68)),
      camera.projectArtwork(const Offset(139.69, 35.68)));
  });

  test('route start and last ship point match rendered city pins', () {
    const camera=VelaWorldCamera(size: Size(1672,941),
      longitude:116.4,latitude:39.9,oilIllustration:true);
    const route=VelaMaritimeRoute(from: VelaWorldCamera.beijing,
      to: Offset(139.69,35.68));
    final actual=route.samples;
    expect(actual.first,route.from);
    expect((actual.last-route.to).distance,lessThan(.000001));
    final start=camera.projectAlongArtwork(route.from,actual.first);
    final finish=camera.projectAlongArtwork(route.from,actual.last);
    expect((start-camera.projectArtwork(route.from)).distance,
        lessThan(.001));
    expect((finish-camera.projectArtwork(route.to)).distance,
        lessThan(.001));
    expect(finish.dx,greaterThan(start.dx));
    expect(finish.dy,greaterThan(start.dy));
  });
}
