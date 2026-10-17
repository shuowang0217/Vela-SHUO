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
}
