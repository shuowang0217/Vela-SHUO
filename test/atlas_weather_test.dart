import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/world_atlas.dart';

void main() {
  test('weather painter repaints only when animation or camera moves', () {
    const camera = VelaWorldCamera(
        size: Size(700, 440), longitude: 116, latitude: 40);
    const painter = VelaAtlasWeatherPainter(
        camera: camera, dark: false, phase: 0);
    expect(painter.shouldRepaint(const VelaAtlasWeatherPainter(
        camera: camera, dark: false, phase: .25)), true);
    expect(painter.shouldRepaint(const VelaAtlasWeatherPainter(
        camera: camera, dark: true, phase: 0)), true);
    expect(painter.shouldRepaint(const VelaAtlasWeatherPainter(
        camera: camera, dark: false, phase: 0)), false);
  });

  testWidgets('weather layer preserves navigation test settling', (tester) async {
    const camera = VelaWorldCamera(
        size: Size(700, 440), longitude: 116, latitude: 40);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
        body: SizedBox(width: 700, height: 440,
            child: VelaAtlasWeather(camera: camera, dark: false)))));
    expect(find.byType(VelaAtlasWeather), findsOneWidget);
    expect(find.byType(RepaintBoundary), findsWidgets);
    await tester.pumpAndSettle();
  });

  test('five independent cycles return to phase zero without drift', () {
    expect(VelaWeatherCadence.cloudSeconds, inInclusiveRange(60, 120));
    expect(VelaWeatherCadence.oceanSeconds, inInclusiveRange(8, 15));
    expect(VelaWeatherCadence.windSeconds, inInclusiveRange(20, 40));
    expect(VelaWeatherCadence.routeSeconds, inInclusiveRange(3, 6));
    expect(VelaWeatherCadence.nightSeconds, inInclusiveRange(10, 20));
    for (final period in [
      VelaWeatherCadence.cloudSeconds, VelaWeatherCadence.oceanSeconds,
      VelaWeatherCadence.windSeconds, VelaWeatherCadence.routeSeconds,
      VelaWeatherCadence.nightSeconds,
    ]) {
      expect(VelaWeatherCadence.timelineSeconds % period, 0);
      final normalized = period / VelaWeatherCadence.timelineSeconds;
      expect(VelaWeatherCadence.progress(normalized, period), closeTo(0, 1e-10));
      expect(VelaWeatherCadence.progress(normalized / 2, period),
          closeTo(.5, 1e-10));
    }
  });

  testWidgets('connected silk route toggles without timer leakage',
      (tester) async {
    const camera = VelaWorldCamera(
        size: Size(700, 440), longitude: 116, latitude: 40);
    Widget weather(bool connected, bool dark) => MaterialApp(home: Scaffold(
      body: SizedBox(width: 700, height: 440, child: VelaAtlasWeather(
        camera: camera, dark: dark, connected: connected,
        
      )),
    ));
    await tester.pumpWidget(weather(false, false));
    await tester.pumpWidget(weather(true, true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(weather(false, true));
    await tester.pumpAndSettle();
  });

  test('watercolor shader remains compatible with Windows SkSL', () {
    // GLSL array constructors fail on Flutter Windows' Skia backend.
    final source = File('shaders/vela_watercolor_atmosphere.frag')
        .readAsStringSync();
    expect(source, contains('coastalLight('));
    expect(source, isNot(contains('vec2 cities[')));
    expect(source, isNot(contains('vec2[4](')));
  });
  test('alpha compositing uses premultiplied color and a low visual cap', () {
    final source = File('shaders/vela_watercolor_atmosphere.frag')
        .readAsStringSync();
    // Previously ink / opacity sent straight RGB to a premultiplied GPU
    // renderer, giving the entire wallpaper a glaring white wash.
    expect(source, contains('fragColor = vec4(ink * scale, opacity);'));
    expect(source, contains('float opacity = min(total, 0.16);'));
    expect(source, isNot(contains('ink / opacity')));
    expect(source, contains('(.17 + .83 * sea)'));
  });

  testWidgets('weather has a live fallback without a loaded GPU program',
      (tester) async {
    const camera = VelaWorldCamera(
        size: Size(700, 440), longitude: 116, latitude: 40);
    const zero = VelaAtlasWeatherPainter(
        camera: camera, dark: false, phase: 0);
    const moved = VelaAtlasWeatherPainter(
        camera: camera, dark: false, phase: .25);
    expect(moved.shouldRepaint(zero), isTrue);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    zero.paint(canvas, const Size(700, 440));
    recorder.endRecording().dispose();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: SizedBox(width: 700, height: 440,
          child: VelaAtlasWeather(camera: camera, dark: false)))));
    await tester.pumpAndSettle();
  });
}
