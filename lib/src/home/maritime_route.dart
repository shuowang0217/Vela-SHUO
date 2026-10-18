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
  // Beijing is the visual route origin, though inland. The drawn voyage
  // heads towards the Tianjin shoreline before entering the Bohai Sea.
  static const homePort = Offset(116.40, 39.90);

  List<Offset> get waypoints {
    final east = _shortestDelta(from.dx, to.dx) > 0;
    final result = <Offset>[from];
    final asia = from.dx > 95 && from.dx < 151;
    if ((from - homePort).distance < 1.5 &&
        to.dx > 127 && to.dx < 155 && to.dy > 22) {
      // Beijing -> Tianjin -> Bohai -> Yellow Sea -> Japanese coast.
      result.addAll(const [
        Offset(117.8, 39.0), Offset(120.2, 38.4),
        Offset(122.6, 37.5), Offset(125.4, 35.1),
        Offset(129.4, 34.0), Offset(134.5, 33.4),
      ]);
    } else if (asia && to.dx > 127 && to.dx < 155 && to.dy > 22) {
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

  /// Painted sea corridor, separate from node city coordinates. Starting
  /// from Beijing requires a short conceptual transfer to Tianjin's coast;
  /// the VISIBLE sailing track begins offshore, never across the capital.
  /// For Tokyo, the last paint mark sits in Tokyo Bay, not inland at the node.
  /// These are illustrative sea lanes, not charts for marine navigation.
  List<Offset> get oceanWaypoints {
    final china = from.dx >= 110 && from.dx < 125 &&
        from.dy >= 29 && from.dy <= 43;
    final japan = to.dx >= 135 && to.dx <= 142 &&
        to.dy >= 33 && to.dy <= 37.5;
    if (china && japan) {
      return const [
        Offset(117.90, 38.84), // Tianjin harbor mouth / Bohai Gulf
        Offset(120.60, 38.05), // central Bohai Strait
        Offset(122.80, 36.20), // Yellow Sea offshore
        Offset(125.65, 34.00), // southwest of Korea
        Offset(129.20, 31.90), // open East China Sea
        Offset(133.30, 32.05), // Pacific south of Shikoku
        Offset(137.35, 33.85), // Pacific south of Honshu
        Offset(139.73, 35.23), // Tokyo Bay harbor approach
      ];
    }
    return waypoints;
  }

  List<Offset> get oceanSamples => _smooth(oceanWaypoints);

  /// An arc-length parameterization prevents the painted ship from changing
  /// speed at irregularly spaced navigation control points.
  Offset oceanPointAt(double fraction) {
    final points = oceanSamples;
    if (points.length < 2) return from;
    final progress = fraction.clamp(0.0, 1.0);
    if (progress <= 0) return points.first;
    if (progress >= 1) return points.last;
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      length += (points[i] - points[i - 1]).distance;
    }
    var remaining = length * progress;
    for (var i = 1; i < points.length; i++) {
      final segment = (points[i] - points[i - 1]).distance;
      if (remaining <= segment) {
        return Offset.lerp(points[i - 1], points[i],
            segment <= 0 ? 0.0 : remaining / segment)!;
      }
      remaining -= segment;
    }
    return points.last;
  }

  /// Continuous quadratic Bézier segments. A boat location is read back from
  /// the SAME rendered PathMetric, so it can never drift off this stroke.
  static Path smoothPath(List<Offset> coords,
      Offset Function(Offset) project) {
    if (coords.isEmpty) return Path();
    final first = project(coords.first);
    final path = Path()..moveTo(first.dx, first.dy);
    if (coords.length == 1) return path;
    for (var i = 1; i < coords.length - 1; i++) {
      final control = project(coords[i]);
      final ahead = project(coords[i + 1]);
      final midway = Offset.lerp(control, ahead, .5)!;
      path.quadraticBezierTo(control.dx, control.dy,
          midway.dx, midway.dy);
    }
    final end = project(coords.last);
    path.lineTo(end.dx, end.dy);
    return path;
  }

  Path oceanPath(Offset Function(Offset) project, {double until = 1}) {
    final full = smoothPath(oceanSamples, project);
    if (until >= 1) return full;
    final partial = Path();
    for (final metric in full.computeMetrics()) {
      partial.addPath(metric.extractPath(0,
          metric.length * until.clamp(0.0, 1.0)), Offset.zero);
    }
    return partial;
  }

  static double _shortestDelta(double a, double b) =>
      (b - a + 540) % 360 - 180;

  /// Rounded geographic sailing corridor. Chaikin corner cutting converges
  /// to a continuous quadratic B-spline, avoiding the occasional cusp that a
  /// Catmull-Rom spline can produce at unevenly spaced ocean waypoints.
  List<Offset> get samples {
    final raw = waypoints;
    if (raw.length < 2) return raw;
    var points = <Offset>[raw.first];
    // Unwrap the international date line before geometry operations.
    for (var i = 1; i < raw.length; i++) {
      points.add(Offset(points.last.dx +
          _shortestDelta(raw[i - 1].dx, raw[i].dx), raw[i].dy));
    }
    // Do not mutate the stored, real-world geographic guidance waypoints.
    // Five iterations remove harsh joints but retain the sea lane's shape.
    for (var pass = 0; pass < 5; pass++) {
      final smooth = <Offset>[points.first];
      for (var i = 0; i < points.length - 1; i++) {
        final a = points[i];
        final b = points[i + 1];
        smooth.add(a * .75 + b * .25);
        smooth.add(a * .25 + b * .75);
      }
      smooth.add(points.last);
      points = smooth;
    }
    final output = <Offset>[points.first];
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final count = math.max(1, ((b - a).distance / .65).ceil());
      for (var n = 1; n <= count; n++) {
        final p = Offset.lerp(a, b, n / count)!;
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
