import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/flight_route.dart';

void main() {
  test('China to nearby Japan draws a visibly curved route', () {
    const route = VelaFlightRoute(
      start: Offset(75, 135),
      end: Offset(170, 135),
      globeRadius: 215,
    );
    final mid = route.pointAt(.5);
    expect(mid.dy, lessThan(104));
    expect(mid.dx, closeTo(122.5, .0001));
    expect(route.pointAt(0), const Offset(75, 135));
    expect(route.pointAt(1), const Offset(170, 135));
  });

  test('vertical connections have sideways curvature, not a straight line', () {
    const route = VelaFlightRoute(
      start: Offset(120, 80),
      end: Offset(120, 220),
      globeRadius: 215,
    );
    expect((route.pointAt(.5).dx - 120).abs(), greaterThan(20));
  });

  test('animated partial path has the same endpoint as the moving sail', () {
    const route = VelaFlightRoute(
      start: Offset(75, 135),
      end: Offset(270, 170),
      globeRadius: 215,
    );
    for (final t in [0.1, .4, .7, 1.0]) {
      final cursor = route.pointAt(t);
      final bounds = route.path(until: t).getBounds();
      expect(bounds.contains(cursor), isTrue);
    }
  });
}
