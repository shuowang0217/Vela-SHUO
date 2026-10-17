import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/demo_connection.dart';
import 'package:vela_shuo/src/home/world_atlas.dart';

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
}
