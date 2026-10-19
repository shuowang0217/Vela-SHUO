import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/maritime_route.dart';

void main() {
  test('Shanghai to Los Angeles follows Pacific waypoints, not a Bézier', () {
    const route = VelaMaritimeRoute(
      from: VelaMaritimeRoute.shanghai,
      to: Offset(-118.24, 34.05),
    );
    expect(route.waypoints.length, greaterThan(5));
    expect(route.waypoints.any((p) => p.dx > 170), true);
    expect(route.waypoints.any((p) => p.dx < -150), true);
    expect(route.pointAt(0), route.from);
    expect(route.pointAt(1), route.to);
    expect(route.samples.length, greaterThan(20));
    final path = route.path((p) => p);
    expect(path.computeMetrics().first.length, greaterThan(0));
  });

  test('Shanghai to London uses Malacca and Suez, not a screen-space parabola', () {
    const route = VelaMaritimeRoute(
      from: VelaMaritimeRoute.shanghai,
      to: Offset(-.13, 51.5),
    );
    expect(route.waypoints.any((p) => p.dx < 107 && p.dx > 100), true);
    expect(route.waypoints.any((p) => p.dx < 35 && p.dx > 30), true);
    for (final t in [0.1, .45, .7, 1.0]) {
      final current = route.pointAt(t);
      final path = route.path((p) => p, until: t);
      expect(path.getBounds().inflate(1).contains(current), true);
    }
  });

  test('short regional sail crosses intermediate geographic points', () {
    const route = VelaMaritimeRoute(
      from: VelaMaritimeRoute.shanghai,
      to: Offset(139.69, 35.68),
    );
    expect(route.waypoints.length, greaterThan(2));
    expect(route.pointAt(0.5).dy, lessThan(34.0));
  });  test('geographic waypoint turns form smooth arcs without sharp corners', () {
    const route = VelaMaritimeRoute(
      from: VelaMaritimeRoute.shanghai,
      to: Offset(-.13, 51.5),
    );
    final points = route.samples;
    // Interior sampled segments must not form visible angular kinks.
    // The curve still passes through its actual sea-lane waypoints.
    for (var i = 1; i < points.length - 1; i++) {
      final before = points[i] - points[i - 1];
      final after = points[i + 1] - points[i];
      if (before.distance < 0.000001 || after.distance < 0.000001) continue;
      final cross = (before.dx * after.dy - before.dy * after.dx).abs();
      final sinTurn = cross / (before.distance * after.distance);
      expect(sinTurn, lessThan(.30), reason: 'sharp turn at sample $i');
    }
    expect(route.path((p) => p).computeMetrics().first.length,
        greaterThan(0));
  });



  test('Beijing visual home port reaches Japan via Bohai and Yellow Sea', () {
    expect(VelaMaritimeRoute.homePort, const Offset(116.4, 39.9));
    const route = VelaMaritimeRoute(
      from: VelaMaritimeRoute.homePort,
      to: Offset(139.7, 35.7));
    expect(route.waypoints.first, VelaMaritimeRoute.homePort);
    expect(route.waypoints.last, const Offset(139.7, 35.7));
    expect(route.waypoints.any((p) =>
        p.dx > 119 && p.dx < 125 && p.dy > 36 && p.dy < 39), true);
    expect(route.waypoints.any((p) =>
        p.dx > 125 && p.dx < 131 && p.dy < 36), true);
    expect(route.pointAt(0), VelaMaritimeRoute.homePort);
    expect(route.samples.length, greaterThan(20));
  });
  test('Beijing to London uses the v1.6 sea corridor instead of Eurasia', () {
    const route = VelaMaritimeRoute(
      from: VelaMaritimeRoute.homePort, to: Offset(-0.13, 51.5));
    final sea = route.oceanWaypoints;
    expect(sea.first.dy, lessThan(40));
    expect(sea.any((p) => p.dx > 100 && p.dx < 107 && p.dy < 6), true);
    expect(sea.any((p) => p.dx > 30 && p.dx < 35 && p.dy < 35), true);
    expect(sea.last.dx, lessThan(0));
    expect(sea.last.dy, greaterThan(45));
    // No direct segment across the Eurasian interior.
    expect(sea.length, greaterThan(8));
  });

  test('London to Beijing reverses the same safe maritime passage', () {
    const outward = VelaMaritimeRoute(
      from: VelaMaritimeRoute.homePort, to: Offset(-0.13, 51.5));
    const returning = VelaMaritimeRoute(
      from: Offset(-0.13, 51.5), to: VelaMaritimeRoute.homePort);
    expect(returning.oceanWaypoints, outward.oceanWaypoints.reversed.toList());
  });

}
