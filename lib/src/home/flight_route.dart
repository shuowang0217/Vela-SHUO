import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A deliberately elevated *screen-space* arc, rather than a surface
/// great-circle projection. A nearby route (China to Japan, for example)
/// must still have a clearly visible bend.
@immutable
class VelaFlightRoute {
  const VelaFlightRoute({
    required this.start,
    required this.end,
    required this.globeRadius,
  });

  final Offset start;
  final Offset end;
  final double globeRadius;

  Offset get control {
    final direction = end - start;
    final length = direction.distance;
    // For almost overlapping points, a subtle loop still communicates a trip.
    final distance = math.max(1, length);
    var perpendicular = Offset(direction.dy / distance, -direction.dx / distance);
    // Prefer an upward curve; choose left for an exactly vertical chord.
    if (perpendicular.dy > 0 ||
        (perpendicular.dy.abs() < 1e-5 && perpendicular.dx > 0)) {
      perpendicular = -perpendicular;
    }
    if (length < 1e-5) perpendicular = const Offset(0, -1);
    final lift = math.min(
      globeRadius * .32,
      math.max(globeRadius * .15, length * .27),
    );
    // A quadratic Bezier reaches half the control-point displacement at t=.5.
    return Offset.lerp(start, end, .5)! + perpendicular * (lift * 2);
  }

  Offset pointAt(double t) {
    final progress = t.clamp(0.0, 1.0);
    final a = 1 - progress;
    return start * (a * a) +
        control * (2 * a * progress) +
        end * (progress * progress);
  }

  Path path({double until = 1}) {
    final t = until.clamp(0.0, 1.0);
    final p = Path()..moveTo(start.dx, start.dy);
    if (t == 0) return p;
    if (t == 1) {
      p.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
      return p;
    }
    // De Casteljau subdivision preserves the exact curvature of a partial arc.
    final firstControl = Offset.lerp(start, control, t)!;
    final lastControl = Offset.lerp(control, end, t)!;
    final finalPoint = Offset.lerp(firstControl, lastControl, t)!;
    p.quadraticBezierTo(
      firstControl.dx,
      firstControl.dy,
      finalPoint.dx,
      finalPoint.dy,
    );
    return p;
  }
}
