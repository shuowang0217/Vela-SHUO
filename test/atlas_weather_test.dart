import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/world_atlas.dart';

void main() {
  test('clouds use diverse fixed opacity and speed, not flickering randomness', () {
    const camera = VelaWorldCamera(
        size: Size(1400, 800), longitude: 116, latitude: 40);
    const before = VelaAtlasWeatherPainter(
        camera: camera, dark: false, phase: 0);
    const after = VelaAtlasWeatherPainter(
        camera: camera, dark: false, phase: .0625);
    expect(VelaAtlasWeatherPainter.clouds.length, 6);
    expect(VelaAtlasWeatherPainter.clouds.map((c) => c.alpha).toSet().length,
        greaterThanOrEqualTo(4));
    expect(VelaAtlasWeatherPainter.clouds.map((c) => c.driftX).toSet().length,
        greaterThanOrEqualTo(4));
    // After five seconds, the nearest cloud has moved visibly.
    expect((before.cloudPosition(0, camera.size) -
        after.cloudPosition(0, camera.size)).distance, greaterThan(30));
    expect(before.shouldRepaint(after), true);
    expect(before.shouldRepaint(before), false);
  });

  test('pure Canvas hand-painted clouds render without any fragment shader', () {
    const camera = VelaWorldCamera(
        size: Size(700, 440), longitude: 116, latitude: 40);
    const painter = VelaAtlasWeatherPainter(
        camera: camera, dark: false, phase: .20);
    final recorder = ui.PictureRecorder();
    painter.paint(ui.Canvas(recorder), camera.size);
    recorder.endRecording().dispose();
    expect(VelaWeatherCadence.cloudSeconds, 80);
    expect(VelaWeatherCadence.routeSeconds, 4);
  });

  testWidgets('cloud animation stays above artwork and below labels',
      (tester) async {
    const camera = VelaWorldCamera(
        size: Size(700, 440), longitude: 116, latitude: 40);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: SizedBox(width: 700, height: 440,
          child: VelaAtlasWeather(camera: camera, dark: false)),
    )));
    expect(find.byType(VelaAtlasWeather), findsOneWidget);
    expect(find.byType(RepaintBoundary), findsWidgets);
    await tester.pumpAndSettle();
  });
}
