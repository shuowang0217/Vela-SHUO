import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'demo_connection.dart';

const _cyan = Color(0xFF83CCF8);
const _sea = Color(0xFF071C31);
const _startLongitude = 116.4;
const _startLatitude = 39.9;

class VelaGlobe extends StatefulWidget {
  const VelaGlobe({super.key, required this.demo});

  final VelaDemoController demo;

  @override
  State<VelaGlobe> createState() => _VelaGlobeState();
}

class _VelaGlobeState extends State<VelaGlobe>
    with SingleTickerProviderStateMixin {
  static Future<List<List<Offset>>>? _coastlines;
  late final AnimationController _turn;
  double _fromLon = 111;
  double _toLon = 111;
  double _fromLat = 29;
  double _toLat = 29;

  static Future<List<List<Offset>>> _readMap() async {
    final raw = await rootBundle.loadString('assets/maps/world_110m.json');
    final decoded = jsonDecode(raw) as List<dynamic>;
    return [
      for (final ring in decoded)
        [
          for (final pair in ring as List<dynamic>)
            Offset(
              ((pair as List<dynamic>)[0] as num).toDouble(),
              (pair[1] as num).toDouble(),
            ),
        ],
    ];
  }

  @override
  void initState() {
    super.initState();
    _coastlines ??= _readMap();
    _turn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1650),
    );
    widget.demo.addListener(_syncView);
    _syncView();
  }

  void _syncView() {
    if (!mounted) return;
    final idle = widget.demo.phase == VelaPhase.idle;
    final destinationLon = idle ? 111.0 : widget.demo.selected.longitude;
    final destinationLat = idle ? 29.0 : widget.demo.selected.latitude;
    final f = Curves.easeInOutCubic.transform(_turn.value);
    final currentLon = _fromLon + (_toLon - _fromLon) * f;
    final currentLat = _fromLat + (_toLat - _fromLat) * f;
    final delta = ((destinationLon - currentLon + 540) % 360) - 180;
    if ((delta).abs() < .1 && (destinationLat - currentLat).abs() < .1) {
      setState(() {});
      return;
    }
    _fromLon = currentLon;
    _fromLat = currentLat;
    _toLon = currentLon + delta;
    _toLat = destinationLat;
    _turn.forward(from: 0);
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant VelaGlobe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.demo != widget.demo) {
      oldWidget.demo.removeListener(_syncView);
      widget.demo.addListener(_syncView);
      _syncView();
    }
  }

  @override
  void dispose() {
    widget.demo.removeListener(_syncView);
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<List<Offset>>>(
      future: _coastlines,
      builder: (context, snapshot) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_turn, widget.demo]),
          builder: (context, _) {
            final f = Curves.easeInOutCubic.transform(_turn.value);
            return CustomPaint(
              painter: _GlobePainter(
                coastlines: snapshot.data ?? const [],
                longitude: _fromLon + (_toLon - _fromLon) * f,
                latitude: _fromLat + (_toLat - _fromLat) * f,
                node: widget.demo.selected,
                phase: widget.demo.phase,
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}

/// Orthographic Earth: public-domain Natural Earth outlines, softly shaded
/// ocean/land, deterministic night lights, geographic route and minimal sail.
class _GlobePainter extends CustomPainter {
  const _GlobePainter({
    required this.coastlines,
    required this.longitude,
    required this.latitude,
    required this.node,
    required this.phase,
  });

  final List<List<Offset>> coastlines;
  final double longitude;
  final double latitude;
  final VelaDemoNode node;
  final VelaPhase phase;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final center = Offset(size.width * .5, size.height * .51);
    final radius = side * .439;
    final sphereRect = Rect.fromCircle(center: center, radius: radius);
    final projector = _Projector(center, radius, longitude, latitude);

    // Soft atmospheric bloom outside the sphere.
    canvas.drawCircle(
      center,
      radius + 4,
      Paint()
        ..color = const Color(0xFF2D94EC).withValues(alpha: .56)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .065),
    );
    canvas.drawCircle(
      center,
      radius + 1,
      Paint()
        ..color = const Color(0xFF81D0FF).withValues(alpha: .30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(sphereRect));

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.43, -.39),
          radius: 1.1,
          colors: const [
            Color(0xFF295E87),
            Color(0xFF123A61),
            _sea,
            Color(0xFF030914),
          ],
          stops: const [0, .36, .71, 1],
        ).createShader(sphereRect),
    );

    _drawGrid(canvas, projector);
    _drawLand(canvas, projector);
    _drawLights(canvas, projector);
    _drawRoute(canvas, projector);

    // Night-side limb and reflected light lend depth without any photo asset.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.24, -.32),
          radius: 1.08,
          colors: [
            Colors.transparent,
            const Color(0xFF051426).withValues(alpha: .06),
            const Color(0xFF030916).withValues(alpha: .74),
          ],
          stops: const [0, .66, 1],
        ).createShader(sphereRect),
    );
    canvas.restore();

    canvas.drawCircle(
      center,
      radius - .6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, radius * .006)
        ..shader = const SweepGradient(
          colors: [
            Color(0xFF2F719F), Color(0xFFC2E9FF),
            Color(0xFF2D87C4), Color(0xFF75C1F2), Color(0xFF2F719F),
          ],
        ).createShader(sphereRect),
    );

    // Draw markers after the atmosphere so they remain readable.
    _drawMarkers(canvas, projector, side);
  }

  void _drawGrid(Canvas canvas, _Projector p) {
    final gridPaint = Paint()
      ..color = const Color(0xFF6EB0D6).withValues(alpha: .115)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.5, p.radius * .00125);
    for (var lat = -60; lat <= 60; lat += 30) {
      final path = Path();
      var drawing = false;
      for (var lon = -180; lon <= 180; lon += 3) {
        final xy = p.project(lon.toDouble(), lat.toDouble());
        if (xy == null) { drawing = false; continue; }
        if (!drawing) { path.moveTo(xy.dx, xy.dy); drawing = true; }
        else { path.lineTo(xy.dx, xy.dy); }
      }
      canvas.drawPath(path, gridPaint);
    }
    for (var lon = -180; lon < 180; lon += 30) {
      final path = Path();
      var drawing = false;
      for (var lat = -87; lat <= 87; lat += 3) {
        final xy = p.project(lon.toDouble(), lat.toDouble());
        if (xy == null) { drawing = false; continue; }
        if (!drawing) { path.moveTo(xy.dx, xy.dy); drawing = true; }
        else { path.lineTo(xy.dx, xy.dy); }
      }
      canvas.drawPath(path, gridPaint);
    }
  }

  void _drawLand(Canvas canvas, _Projector p) {
    final fill = Paint()
      ..color = const Color(0xFF32526B).withValues(alpha: .72)
      ..style = PaintingStyle.fill;
    final coast = Paint()
      ..color = const Color(0xFF8CC2DE).withValues(alpha: .49)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.65, p.radius * .002);
    for (final ring in coastlines) {
      if (ring.length < 3) continue;
      final path = Path();
      var points = 0;
      var open = false;
      for (final geo in ring) {
        final xy = p.project(geo.dx, geo.dy);
        if (xy == null) {
          open = false;
          continue;
        }
        if (!open) {
          path.moveTo(xy.dx, xy.dy);
          open = true;
        } else {
          path.lineTo(xy.dx, xy.dy);
        }
        points++;
      }
      if (points >= 3) {
        // Avoid stretching filled shapes across the invisible hemisphere.
        if (points > ring.length * .83) {
          path.close();
          canvas.drawPath(path, fill);
        }
        canvas.drawPath(path, coast);
      }
    }
  }

  void _drawLights(Canvas canvas, _Projector p) {
    // Populated regions only; seeded and deterministic, never live traffic.
    const clusters = <(double, double, double, double, int)>[
      (113, 32, 13, 10, 95), // Eastern China
      (121, 32, 5, 7, 40),
      (138, 36, 5, 8, 50), // Japan
      (126, 37, 4, 4, 30), // Korea
      (77, 24, 10, 10, 70), // India
      (104, 15, 12, 7, 35), // Southeast Asia
      (9, 49, 13, 10, 60), // Europe
      (-75, 39, 11, 9, 70), // US east coast
      (-120, 36, 8, 11, 50), // US west coast
      (-99, 28, 12, 8, 35),
      (-45, -22, 9, 9, 25),
    ];
    final rng = math.Random(20261009);
    for (final (lon, lat, dx, dy, count) in clusters) {
      for (var i = 0; i < count; i++) {
        final offset = p.project(
          lon + (rng.nextDouble() - rng.nextDouble()) * dx,
          lat + (rng.nextDouble() - rng.nextDouble()) * dy,
        );
        final brightness = .28 + rng.nextDouble() * .63;
        if (offset == null) continue;
        canvas.drawCircle(
          offset,
          p.radius * (.0013 + rng.nextDouble() * .0023),
          Paint()
            ..color = const Color(0xFFFFDC9E)
                .withValues(alpha: brightness),
        );
      }
    }
  }

  void _drawRoute(Canvas canvas, _Projector p) {
    if (phase == VelaPhase.idle) return;
    final route = Path();
    final points = <Offset>[];
    var drawing = false;
    for (var i = 0; i <= 110; i++) {
      final gps = _greatCircle(
        _startLongitude, _startLatitude,
        node.longitude, node.latitude, i / 110,
      );
      final xy = p.project(gps.dx, gps.dy);
      if (xy == null) { drawing = false; continue; }
      if (!drawing) { route.moveTo(xy.dx, xy.dy); drawing = true; }
      else { route.lineTo(xy.dx, xy.dy); }
      points.add(xy);
    }
    if (points.length < 2) return;
    canvas.drawPath(
      route,
      Paint()
        ..color = const Color(0xFF56B7FF).withValues(alpha: .8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, p.radius * .011)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawPath(
      route,
      Paint()
        ..color = const Color(0xFFB6E6FF).withValues(alpha: .90)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.2, p.radius * .0045),
    );
  }

  void _drawMarkers(Canvas canvas, _Projector p, double side) {
    final china = p.project(_startLongitude, _startLatitude);
    if (china != null) {
      _mark(canvas, china, p.radius * .012, const Color(0xFF8FD9FF));
      _label(canvas, '中国', china.translate(-12, -p.radius * .085), side);
    }
    if (phase == VelaPhase.idle) {
      if (china != null) {
        _drawSail(canvas, china.translate(p.radius * .095, -p.radius * .09),
            p.radius * .060);
      }
      return;
    }
    final end = p.project(node.longitude, node.latitude);
    if (end != null) {
      _mark(canvas, end, p.radius * .014, const Color(0xFFBAEAFF));
      _drawSail(canvas, end.translate(-p.radius * .065, -p.radius * .13),
          p.radius * .058);
      _label(canvas, node.country, end.translate(5, p.radius * .032), side);
    }
  }

  void _mark(Canvas canvas, Offset at, double dotSize, Color color) {
    canvas.drawCircle(
      at, dotSize * 4,
      Paint()
        ..color = color.withValues(alpha: .48)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(
      at, dotSize * 1.75,
      Paint()
        ..color = color.withValues(alpha: .65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.8, dotSize * .35),
    );
    canvas.drawCircle(at, dotSize, Paint()..color = color);
  }

  void _drawSail(Canvas canvas, Offset location, double size) {
    final left = Path()
      ..moveTo(location.dx + size * .10, location.dy - size * .95)
      ..lineTo(location.dx - size * .73, location.dy + size * .48)
      ..lineTo(location.dx + size * .10, location.dy + size * .48)
      ..close();
    final right = Path()
      ..moveTo(location.dx + size * .28, location.dy - size * .62)
      ..lineTo(location.dx + size * .90, location.dy + size * .48)
      ..lineTo(location.dx + size * .28, location.dy + size * .48)
      ..close();
    canvas.drawCircle(
      location, size * 1.6,
      Paint()
        ..color = _cyan.withValues(alpha: .26)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * .8),
    );
    canvas.drawPath(left, Paint()..color = const Color(0xFFC7EFFF));
    canvas.drawPath(right, Paint()..color = const Color(0xFF6FB8E9));
    final hull = Path()
      ..moveTo(location.dx - size * .83, location.dy + size * .67)
      ..quadraticBezierTo(
        location.dx, location.dy + size * .93,
        location.dx + size * .94, location.dy + size * .67,
      );
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0xFFB2E6FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, size * .12)
        ..strokeCap = StrokeCap.round,
    );
  }

  void _label(Canvas canvas, String text, Offset position, double side) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFFE8F7FF),
          fontSize: math.max(11, side * .025),
          fontWeight: FontWeight.w600,
          shadows: const [Shadow(color: Colors.black, blurRadius: 8)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, position);
  }

  static Offset _greatCircle(
    double aLon, double aLat, double bLon, double bLat, double t,
  ) {
    const rad = math.pi / 180;
    final phi0 = aLat * rad, phi1 = bLat * rad;
    final lam0 = aLon * rad, lam1 = bLon * rad;
    final x0 = math.cos(phi0) * math.cos(lam0);
    final y0 = math.cos(phi0) * math.sin(lam0);
    final z0 = math.sin(phi0);
    final x1 = math.cos(phi1) * math.cos(lam1);
    final y1 = math.cos(phi1) * math.sin(lam1);
    final z1 = math.sin(phi1);
    final dot = (x0 * x1 + y0 * y1 + z0 * z1).clamp(-1.0, 1.0);
    final omega = math.acos(dot);
    if (omega < .00001) return Offset(aLon, aLat);
    final divisor = math.sin(omega);
    final a = math.sin((1 - t) * omega) / divisor;
    final b = math.sin(t * omega) / divisor;
    final x = a * x0 + b * x1;
    final y = a * y0 + b * y1;
    final z = a * z0 + b * z1;
    return Offset(math.atan2(y, x) / rad,
        math.atan2(z, math.sqrt(x * x + y * y)) / rad);
  }

  @override
  bool shouldRepaint(covariant _GlobePainter old) =>
      old.longitude != longitude ||
      old.latitude != latitude ||
      old.phase != phase ||
      old.node != node ||
      old.coastlines != coastlines;
}

class _Projector {
  _Projector(this.center, this.radius, double longitude, double latitude)
      : lon0 = longitude * math.pi / 180,
        lat0 = latitude * math.pi / 180;

  final Offset center;
  final double radius;
  final double lon0;
  final double lat0;

  Offset? project(double longitude, double latitude) {
    final lon = longitude * math.pi / 180;
    final lat = latitude * math.pi / 180;
    final cosc = math.sin(lat0) * math.sin(lat) +
        math.cos(lat0) * math.cos(lat) * math.cos(lon - lon0);
    if (cosc < .015) return null;
    return Offset(
      center.dx + radius * math.cos(lat) * math.sin(lon - lon0),
      center.dy - radius * (math.cos(lat0) * math.sin(lat) -
          math.sin(lat0) * math.cos(lat) * math.cos(lon - lon0)),
    );
  }
}
