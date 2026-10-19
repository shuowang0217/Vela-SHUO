import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/demo_connection.dart';
import 'package:vela_shuo/src/home/world_atlas.dart';
import 'package:vela_shuo/src/home/maritime_route.dart';

void main() {
  test('wide map keeps China on screen and shows nearby continents', () {
    const camera = VelaWorldCamera(
      size: Size(1280, 800), longitude: 116.4, latitude: 39.9);
    final china = camera.project(VelaWorldCamera.beijing);
    expect(china.dx, closeTo(640, .001));
    // Vertical position is biased upward so full artwork covers the screen.
    expect(china.dy, inInclusiveRange(120.0, 500.0));
    expect(camera.worldWidth / camera.worldHeight, 2.0);
    expect(camera.worldWidth, lessThan(camera.size.width * 1.6));
    expect(camera.worldWidth, greaterThan(camera.size.width));
    expect(camera.top, inInclusiveRange(
        camera.size.height - camera.worldHeight, 0.0));
    expect(camera.tileLeft, lessThanOrEqualTo(0));
    expect(camera.tileLeft + camera.worldWidth, greaterThan(0));
    // Los Angeles is visible to the east across the Pacific at rest.
    expect(camera.project(const Offset(-118.24, 34.05)).dx,
        inInclusiveRange(0.0, 1280.0));
  });

  test('camera never exposes upper/lower map edge on city focus changes', () {
    for (final size in [const Size(1280, 800), const Size(390, 850)]) {
      for (final location in [
        const Offset(116.4, 39.9), // China
        const Offset(139.7, 35.7), // Tokyo
        const Offset(-118.2, 34.1), // Los Angeles
        const Offset(103.8, 1.3), // Singapore
        const Offset(-.13, 51.5), // London
        const Offset(151.21, -33.86), // Sydney
      ]) {
        final camera = VelaWorldCamera(
          size: size, longitude: location.dx, latitude: location.dy);
        expect(camera.worldHeight, greaterThanOrEqualTo(size.height));
        expect(camera.top, lessThanOrEqualTo(0));
        expect(camera.top + camera.worldHeight,
            greaterThanOrEqualTo(size.height));
        final pin = camera.project(location);
        expect(pin.dx, closeTo(size.width / 2, .001));
        expect(pin.dy, inInclusiveRange(0, size.height));
      }
    }
  });

  test('seam takes the Pacific short path between China and America', () {
    expect(VelaWorldCamera.shortestDelta(116.4, -118.2),
        closeTo(125.4, .001));
    expect(VelaWorldCamera.shortestDelta(-118.2, 116.4),
        closeTo(-125.4, .001));
  });

  test('map remains periodic and shared with enlarged city positions', () {
    const camera = VelaWorldCamera(size: Size(1200, 680),
        longitude: 139.7, latitude: 35.7);
    final tokyo = camera.project(const Offset(139.7, 35.7));
    expect(tokyo.dx, closeTo(600, .01));
    final us = camera.project(const Offset(-118.2, 34.0));
    expect(us.dx, inInclusiveRange(-100, 1300));
    final reverse = VelaWorldCamera.shortestDelta(-118.2, 139.7);
    expect(reverse, closeTo(-102.1, .001));
  });


  test('compact Android portrait camera reveals more geography at native size', () {
    const size = Size(390, 844);
    const full = VelaWorldCamera(
      size: size, longitude: 116.4, latitude: 39.9);
    const compact = VelaWorldCamera(
      size: size, longitude: 116.4, latitude: 39.9,
      portraitWidthScale: VelaWorldCamera.androidCompactScale);
    expect(compact.worldWidth, lessThan(full.worldWidth * .85));
    expect(compact.worldHeight, lessThan(size.height));
    expect(compact.top, greaterThan(0));
    expect(compact.top + compact.worldHeight, lessThan(size.height));
    expect(compact.project(VelaWorldCamera.beijing).dx, closeTo(195, .001));
  });

  testWidgets('real connection state moves atlas and disconnects safely',
      (tester) async {
    final demo = VelaDemoController();
    addTearDown(demo.dispose);
    await tester.pumpWidget(MaterialApp(home: SizedBox(
      width: 640, height: 360, child: VelaWorldAtlas(demo: demo),
    )));
    expect(find.byType(VelaWorldAtlas), findsOneWidget);
    demo.projectRealState(VelaPhase.connecting, 'Japan Tokyo JP');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 600));
    demo.projectRealState(VelaPhase.connected, 'Japan Tokyo JP');
    await tester.pump();
    demo.projectRealState(VelaPhase.idle, 'Japan Tokyo JP');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('hand-lettered labels are uppercase English and avoid vessel', () {
    expect(VelaAtlasInk.englishLabel('东京 Tokyo-01'), 'TOKYO');
    expect(VelaAtlasInk.englishLabel('终点'), 'DESTINATION');
    expect(VelaAtlasInk.englishLabel('上海'), 'DESTINATION');
    expect(VelaAtlasInk.family(TargetPlatform.windows), 'Segoe Print');
    expect(VelaAtlasInk.family(TargetPlatform.android), 'casual');
    const canvas = Size(390, 840);
    const marker = Offset(190, 310);
    final top = VelaAtlasInk.position(canvas, marker,
        const Size(94, 25), above: true);
    expect(top.dy, lessThan(marker.dy - 30));
    expect(top.dx, greaterThan(marker.dx + 10));
    final left = VelaAtlasInk.position(canvas, marker,
        const Size(94, 25), toLeft: true);
    expect(left.dx, lessThan(marker.dx - 90));
  });

  test('watercolor coastline calibration stays shared across route points', () {
    const camera = VelaWorldCamera(size: Size(1600, 840),
        longitude: 139.7, latitude: 35.7);
    final shanghai = camera.projectArtwork(
        VelaMaritimeRoute.shanghai);
    final tokyo = camera.projectArtwork(const Offset(139.7, 35.7));
    expect(shanghai.dx, lessThan(camera.project(
        VelaMaritimeRoute.shanghai).dx - 55));
    expect(tokyo.dx, lessThan(camera.project(
        const Offset(139.7, 35.7)).dx - 55));
    expect(shanghai.dy, lessThan(camera.project(
        VelaMaritimeRoute.shanghai).dy - 20));
    expect(camera.projectAlongArtwork(VelaMaritimeRoute.shanghai,
        const Offset(139.7, 35.7)), tokyo);
    // Real geographic calculations remain unchanged.
    expect(camera.project(const Offset(139.7, 35.7)).dx,
        closeTo(800, .001));
  });

  test('Beijing home port uses actual Beijing coordinates', () {
    expect(VelaMaritimeRoute.homePort, VelaWorldCamera.beijing);
    const camera = VelaWorldCamera(
        size: Size(1200, 720), longitude: 116.4, latitude: 39.9);
    final point = camera.projectArtwork(VelaMaritimeRoute.homePort);
    expect(point.dx, inInclusiveRange(450, 650));
    expect(point.dy, greaterThan(0));
  });
  test('Android oil portrait shows wider panorama with aligned camera', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      const size = Size(390, 844);
      const camera = VelaWorldCamera(
        size: size, longitude: 116.4, latitude: 39.9,
        oilIllustration: true);
      final oldCoverScale = math.max(size.width / 1672, size.height / 941);
      expect(camera.oilImageScale, closeTo(oldCoverScale, .0001));
      expect((camera.projectArtwork(VelaWorldCamera.beijing) -
          const Offset(195, 422)).distance, lessThan(.001));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });


}
