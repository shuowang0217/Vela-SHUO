import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/demo_connection.dart';
import 'package:vela_shuo/src/home/globe.dart';

double _sailProgress(WidgetTester tester) {
  final globe = tester.widgetList<CustomPaint>(find.byType(CustomPaint))
      .singleWhere((widget) =>
          widget.painter?.runtimeType.toString() == '_GlobePainter');
  return (globe.painter! as dynamic).sailProgress as double;
}

VelaPhase _visiblePhase(WidgetTester tester) {
  final globe = tester.widgetList<CustomPaint>(find.byType(CustomPaint))
      .singleWhere((widget) =>
          widget.painter?.runtimeType.toString() == '_GlobePainter');
  return (globe.painter! as dynamic).phase as VelaPhase;
}

void main() {
  test('all demo globe locations use consistent English map labels', () {
    expect(
      VelaDemoNode.samples.map((node) => node.mapLabel).toList(),
      ['TOKYO', 'SINGAPORE', 'LOS ANGELES', 'LONDON', 'FRANKFURT'],
    );
  });

  testWidgets('real Android VPN state sails even for unknown node names',
      (tester) async {
    final demo = VelaDemoController();
    await tester.pumpWidget(MaterialApp(home: SizedBox(
      width: 400, height: 400, child: VelaGlobe(demo: demo),
    )));
    demo.projectRealState(VelaPhase.connecting, 'My Private Node');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 500));
    expect(demo.phase, VelaPhase.connecting);
    expect(_sailProgress(tester), greaterThan(0));

    demo.projectRealState(VelaPhase.connected, 'My Private Node');
    await tester.pump();
    expect(demo.phase, VelaPhase.connected);

    demo.projectRealState(VelaPhase.idle, 'My Private Node');
    await tester.pump();
    expect(demo.phase, VelaPhase.idle);
    expect(_visiblePhase(tester), VelaPhase.switching);
    await tester.pumpWidget(const SizedBox.shrink());
    demo.dispose();
  });

  testWidgets('connection status never teleports the sailing marker',
      (tester) async {
    final demo = VelaDemoController();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(width: 500, height: 500, child: VelaGlobe(demo: demo)),
      ),
    ));

    demo.connect();
    await tester.pump();
    // Start the ticker on a real frame before advancing the fake clock.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 1400));

    // The card now says connected, but the 1550 ms sail has not
    // finished. Its painter must NOT jump to t=1.
    expect(demo.phase, VelaPhase.connected);
    expect(_sailProgress(tester), greaterThan(0));
    expect(_sailProgress(tester), lessThan(1));

    await tester.pump(const Duration(milliseconds: 250));
    expect(_sailProgress(tester), closeTo(1, .001));

    demo.disconnect();
    await tester.pump();
    expect(demo.phase, VelaPhase.idle);
    // Visual return continues even though the connection UI is idle.
    expect(_visiblePhase(tester), VelaPhase.switching);
    expect(_sailProgress(tester), closeTo(1, .001));

    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 750));
    expect(_sailProgress(tester), greaterThan(0));
    expect(_sailProgress(tester), lessThan(1));
    expect(_visiblePhase(tester), VelaPhase.switching);

    await tester.pump(const Duration(milliseconds: 850));
    expect(_sailProgress(tester), closeTo(0, .001));
    expect(_visiblePhase(tester), VelaPhase.idle);

    await tester.pumpWidget(const SizedBox.shrink());
    demo.dispose();
  });
}
