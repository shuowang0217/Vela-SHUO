import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/demo_connection.dart';
import 'package:vela_shuo/src/home/world_atlas.dart';

void main() {
  test('world map projects the focused country to the viewport center', () {
    const camera = VelaWorldCamera(
      size: Size(1280, 800), longitude: 116.4, latitude: 39.9);
    expect(camera.project(VelaWorldCamera.beijing), const Offset(640, 400));
    expect(camera.worldWidth / camera.worldHeight, 2.0);
    expect(camera.tileLeft, lessThanOrEqualTo(0));
    expect(camera.tileLeft + camera.worldWidth, greaterThan(0));
  });

  test('seam takes the Pacific short path between China and America', () {
    expect(VelaWorldCamera.shortestDelta(116.4, -118.2),
        closeTo(125.4, .001));
    expect(VelaWorldCamera.shortestDelta(-118.2, 116.4),
        closeTo(-125.4, .001));
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
