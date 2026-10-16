import 'dart:math' as math;
import 'package:flutter/material.dart';

/// An illustrative sea-going route across actual geographic waypoints,
/// projected by the same 2:1 world map camera as the cities and coastlines.
/// No screen-space parabolic arc. This is NOT nautical navigation guidance.
@immutable
class VelaMaritimeRoute {
  const VelaMaritimeRoute({required this.from, required this.to});
  final Offset from; // longitude, latitude
  final Offset to;

  static const shanghai = Offset(121.47, 31.23);

  List<Offset> get waypoints {
    final east = _shortestDelta(from.dx, to.dx) > 0;
    final result = <Offset>[from];
    final asia = from.dx > 95 && from.dx < 151;
    if (asia && to.dx > 127 && to.dx < 155 && to.dy > 22) {
      // Japan / Korea through the East China Sea and Philippine Sea.
      result.addAll(const [
        Offset(124.6, 29.3), Offset(129.8, 30.5),
        Offset(135.2, 33.5),
      ]);
    } else if (asia && east && to.dx < -65 && to.dy > 15) {
      // North Pacific trade lanes outside the Aleutian arc.
      result.addAll(const [
        Offset(135.0, 31.0), Offset(153.0, 35.0),
        Offset(176.0, 41.0), Offset(-164.0, 43.0),
        Offset(-144.0, 41.0), Offset(-128.0, 37.0),
      ]);
    } else if (asia && to.dx < 50 && to.dx > -25 && to.dy > 25) {
      // Malacca, Indian Ocean, Red Sea, Suez, Mediterranean, Atlantic.
      result.addAll(const [
        Offset(124.0, 21.0), Offset(113.0, 9.0),
        Offset(103.5, 1.6), Offset(85.0, 3.0),
        Offset(58.0, 13.0), Offset(43.0, 13.0),
        Offset(33.0, 28.0), Offset(31.0, 32.0),
        Offset(16.0, 35.5), Offset(-6.0, 36.0),
      ]);
    } else if (asia && to.dy < 5 && to.dx > 92 && to.dx < 160) {
      result.addAll(const [
        Offset(123.0, 22.0), Offset(117.0, 12.0),
        Offset(106.0, 2.0), Offset(113.0, -8.0),
      ]);
    }
    // For other pairs, sample a great-circle geographically, not a
    // hand-bent on-screen quadratic. Some routes can still cross land.
    result.add(to);
    return result;
  }

  static double _shortestDelta(double a, double b) =>
      (b - a + 540) % 360 - 180;

  /// Smooth sailing curves through real geographic waypoints.
  /// A Catmull-Rom spline shares tangents at joins, unlike the former
  /// straight segments that caused visible sharp corners at each waypoint.
  /// Longitudes are unwrapped first to avoid the +/-180 degree discontinuity.
  List<Offset> get samples {
    final raw = waypoints;
    if (raw.length < 2) return raw;
    final knots = <Offset>[raw.first];
    for (var i = 1; i < raw.length; i++) {
      final previous = knots.last;
      final delta = _shortestDelta(raw[i - 1].dx, raw[i].dx);
      knots.add(Offset(previous.dx + delta, raw[i].dy));
    }
    final output = <Offset>[knots.first];
    for (var i = 0; i < knots.length - 1; i++) {
      final a = i == 0 ? knots[i] : knots[i - 1];
      final b = knots[i];
      final c = knots[i + 1];
      final d = i + 2 >= knots.length ? c : knots[i + 2];
      final chord = (c - b).distance;
      // Dense samples also keep each polyline sub-segment visually smooth.
      final count = math.max(8, (chord / 0.65).ceil());
      for (var n = 1; n <= count; n++) {
        final t = n / count;
        final t2 = t * t;
        final t3 = t2 * t;
        // Cubic Hermite with shared Catmull-Rom tangents at each knot.
        final tangentStart = (c - a) * .5;
        final tangentEnd = (d - b) * .5;
        final p = b * (2 * t3 - 3 * t2 + 1) +
            tangentStart * (t3 - 2 * t2 + t) +
            c * (-2 * t3 + 3 * t2) +
            tangentEnd * (t3 - t2);
        output.add(Offset(p.dx, p.dy.clamp(-85.0, 85.0).toDouble()));
      }
    }
    return output;
  }

  Offset pointAt(double progress) {
    final points = samples;
    final p = progress.clamp(0.0, 1.0);
    if (p == 0) return from;
    if (p == 1) return to;
    final scaled = p * (points.length - 1);
    final idx = math.min(points.length - 2, scaled.floor());
    return Offset.lerp(points[idx], points[idx + 1],
        scaled - idx)!;
  }

  Path path(Offset Function(Offset) project, {double until = 1}) {
    final points = samples;
    final endIndex = until.clamp(0.0, 1.0) * (points.length - 1);
    final lastIndex = math.min(points.length - 1, endIndex.floor());
    final start = project(points.first);
    final line = Path()..moveTo(start.dx, start.dy);
    for (var i = 1; i <= lastIndex; i++) {
      final p = project(points[i]);
      line.lineTo(p.dx, p.dy);
    }
    if (lastIndex < points.length - 1 &&
        endIndex > lastIndex) {
      final p = project(pointAt(until));
      line.lineTo(p.dx, p.dy);
    }
    return line;
  }
}
