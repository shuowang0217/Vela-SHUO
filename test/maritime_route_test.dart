import 'package:flutter/material.dart';
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
  });
}
