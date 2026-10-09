import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'demo_connection.dart';
import 'flight_route.dart';

const _cyan = Color(0xFF83CCF8);
const _sea = Color(0xFF071C31);
const _startLongitude = 116.4;
const _startLatitude = 39.9;

class _EarthTextures {
  const _EarthTextures(this.day, this.night);
  final ui.Image day;
  final ui.Image night;
}

class VelaGlobe extends StatefulWidget {
  const VelaGlobe({super.key, required this.demo});

  final VelaDemoController demo;

  @override
  State<VelaGlobe> createState() => _VelaGlobeState();
}

class _VelaGlobeState extends State<VelaGlobe>
    with TickerProviderStateMixin {
  static Future<List<List<Offset>>>? _coastlines;
  static Future<_EarthTextures>? _textures;
  late final AnimationController _turn;
  late final AnimationController _sail;
  late final AnimationController _clouds;
  VelaPhase? _lastPhase;
  String? _lastNode;
  VelaDemoNode? _visibleNode;
  bool _returning = false;
  bool _homebound = false;

  static Future<_EarthTextures> _loadTextures() async {
    Future<ui.Image> loadImage(String file) async {
      final bytes = await rootBundle.load(file);
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      try {
        final frame = await codec.getNextFrame();
        return frame.image;
      } finally {
        codec.dispose();
      }
    }

    final pair = await Future.wait([
      loadImage('assets/earth/earth_day.jpg'),
      loadImage('assets/earth/earth_night_lights.png'),
    ]);
    return _EarthTextures(pair[0], pair[1]);
  }
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
    _textures ??= _loadTextures();
    _turn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1650),
    );
    _sail = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1550),
    );
    _sail.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && _returning && mounted) {
        // Keep the original route on screen until the boat reaches its
        // departure point, then rotate the globe home.
        _returning = false;
        _homebound = true;
        _rotateTo(111, 29);
        setState(() {});
      }
    });
    _turn.addStatusListener((status) {
      if (status == AnimationStatus.completed && _homebound && mounted) {
        setState(() => _homebound = false);
      }
    });
    _clouds = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 95),
    )..repeat();
    widget.demo.addListener(_syncView);
    _syncView();
  }

  void _rotateTo(double longitude, double latitude) {
    // Retarget from the actually displayed orientation. Interrupted
    // transitions therefore never snap back to a previous keyframe.
    final f = Curves.easeInOutCubic.transform(_turn.value);
    final currentLon = _fromLon + (_toLon - _fromLon) * f;
    final currentLat = _fromLat + (_toLat - _fromLat) * f;
    final delta = ((longitude - currentLon + 540) % 360) - 180;
    if (delta.abs() < .1 && (latitude - currentLat).abs() < .1) {
      return;
    }
    _fromLon = currentLon;
    _fromLat = currentLat;
    _toLon = currentLon + delta;
    _toLat = latitude;
    _turn.forward(from: 0);
  }

  void _syncView() {
    if (!mounted) return;
    final phase = widget.demo.phase;
    final node = widget.demo.selected;
    if (_lastPhase == phase && _lastNode == node.id) return;

    if (phase == VelaPhase.idle) {
      if (_lastPhase != null &&
          _lastPhase != VelaPhase.idle &&
          _sail.value > .001) {
        // Disconnect reverses the *current* animation, not an instant
        // repaint at the origin. Retain the previous node and route.
        _returning = true;
        _homebound = false;
        _sail.reverse();
      } else if (!_returning) {
        _homebound = true;
        _rotateTo(111, 29);
      }
    } else {
      final resumeReturn = _returning && _visibleNode?.id == node.id;
      _returning = false;
      _homebound = false;
      _visibleNode = node;
      if (phase == VelaPhase.connecting ||
          phase == VelaPhase.switching) {
        // Reconnecting to the same node midway through a return can
        // resume from the exact boat position.
        if (resumeReturn) {
          _sail.forward();
        } else {
          _sail.forward(from: 0);
        }
      } else if (phase == VelaPhase.connected) {
        // The UI becomes "connected" before the boat reaches the end.
        // Never force the boat to t=1 here: let its ticker finish.
        // Calling forward() again while already running restarts the ticker
        // timing; the phase change must not restart the sailing timeline.
        if (!_sail.isAnimating && _sail.value < 1) _sail.forward();
      } else {
        _sail.stop();
      }
      _rotateTo(node.longitude, node.latitude);
    }
    _lastPhase = phase;
    _lastNode = node.id;
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
    _sail.dispose();
    _clouds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<List<Offset>>>(
      future: _coastlines,
      builder: (context, outlines) => FutureBuilder<_EarthTextures>(
        future: _textures,
        builder: (context, texture) => RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([_turn, _sail, _clouds, widget.demo]),
            builder: (context, _) {
              final f = Curves.easeInOutCubic.transform(_turn.value);
              return CustomPaint(
                painter: _GlobePainter(
                  coastlines: outlines.data ?? const [],
                  textures: texture.data,
                  longitude: _fromLon + (_toLon - _fromLon) * f,
                  latitude: _fromLat + (_toLat - _fromLat) * f,
                  node: _visibleNode ?? widget.demo.selected,
                  phase: _returning
                      ? VelaPhase.switching : widget.demo.phase,
                  homebound: _homebound,
                  // One animation value drives BOTH the boat and the trail.
                  sailProgress: Curves.easeInOutCubic.transform(_sail.value),
                  cloudProgress: _clouds.value,
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
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
    required this.textures,
    required this.sailProgress,
    required this.homebound,
    required this.cloudProgress,
    required this.longitude,
    required this.latitude,
    required this.node,
    required this.phase,
  });

  final List<List<Offset>> coastlines;
  final _EarthTextures? textures;
  final double sailProgress;
  final bool homebound;
  final double cloudProgress;
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

    if (textures case final earth?) {
      _drawTexturedEarth(canvas, projector, earth);
    } else {
      _drawLand(canvas, projector);
      _drawLights(canvas, projector);
    }
    // Overlay extremely subtle coordinates and coastline highlights.
    _drawGrid(canvas, projector);
    if (textures != null) _drawLand(canvas, projector);

    _drawClouds(canvas, center, radius);

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

    // A screen-space flight arc lives ABOVE the sphere, rather than
    // flattening into a great-circle line on its surface.
    final flight = _visibleFlight(projector);
    if (flight != null) _drawRoute(canvas, projector, flight);
    _drawMarkers(canvas, projector, side, flight);
  }

  /// GPU-textured equirectangular Earth projected onto a real orthographic
  /// mesh. This is dramatically more detailed than the old flat land blobs.
  /// Texture samples remain attached to geographic coordinates as it turns.
  void _drawTexturedEarth(
    Canvas canvas,
    _Projector p,
    _EarthTextures earth,
  ) {
    // Smaller projection mesh reduces CPU work each frame while preserving
    // the full-resolution source texture and geographical detail.
    const columns = 96;
    const rows = 48;
    final positions = <Offset>[];
    final texels = <Offset>[];
    final visible = <bool>[];
    final indices = <int>[];
    for (var row = 0; row <= rows; row++) {
      final lat = 90 - row * 180.0 / rows;
      for (var column = 0; column <= columns; column++) {
        final lon = -180 + column * 360.0 / columns;
        final projected = p.project(lon, lat);
        visible.add(projected != null);
        positions.add(projected ?? p.center);
        texels.add(Offset(
          column * earth.day.width / columns,
          row * earth.day.height / rows,
        ));
      }
    }
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < columns; col++) {
        final a = row * (columns + 1) + col;
        final b = a + 1;
        final c = a + columns + 1;
        final d = c + 1;
        if (visible[a] && visible[b] && visible[c]) {
          indices.addAll([a, b, c]);
        }
        if (visible[b] && visible[d] && visible[c]) {
          indices.addAll([b, d, c]);
        }
      }
    }
    if (indices.isEmpty) return;
    final mesh = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: texels,
      indices: indices,
    );
    final earthShader = ui.ImageShader(
      earth.day, ui.TileMode.clamp, ui.TileMode.clamp,
      Matrix4.identity().storage,
    );
    canvas.drawVertices(
      mesh,
      BlendMode.modulate,
      Paint()
        ..shader = earthShader
        ..filterQuality = FilterQuality.medium
        // Cool, dim night-side globe palette while retaining genuine terrain.
        ..colorFilter = const ColorFilter.matrix([
          .38, .07, .03, 0, 4,
          .02, .51, .06, 0, 5,
          .06, .10, .68, 0, 9,
          0, 0, 0, 1, 0,
        ]),
    );

    final nightShader = ui.ImageShader(
      earth.night, ui.TileMode.clamp, ui.TileMode.clamp,
      Matrix4.identity().storage,
    );
    // Authentically located satellite city lights, not random ocean dots.
    canvas.drawVertices(
      mesh,
      BlendMode.modulate,
      Paint()
        ..shader = nightShader
        ..filterQuality = FilterQuality.medium
        ..blendMode = BlendMode.screen
        ..colorFilter = const ColorFilter.matrix([
          1.7, .08, 0, 0, 0,
          .07, 1.4, 0, 0, 0,
          0, .07, 1.15, 0, 0,
          0, 0, 0, 1, 0,
        ]),
    );
    mesh.dispose();
  }

  /// Lightweight atmospheric bands, clipped to the globe. The slow phase
  /// shift gives a gentle drift without a second textured projection mesh.
  void _drawClouds(Canvas canvas, Offset center, double radius) {
    final drift = cloudProgress * math.pi * 2;
    final paint = Paint()
      ..color = const Color(0xFFD3ECFA).withValues(alpha: .075)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .038);
    for (var i = 0; i < 9; i++) {
      final phase = i * 2.39996;
      final x = math.sin(phase + drift) * .72;
      final y = math.cos(phase * .81 + drift * .24) * .67;
      final width = radius * (.21 + (i % 3) * .075);
      final height = radius * (.035 + (i % 2) * .018);
      canvas.save();
      canvas.translate(center.dx + radius * x, center.dy + radius * y);
      canvas.rotate(-.25 + math.sin(phase) * .35);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: width, height: height),
        paint,
      );
      canvas.restore();
    }
  }

  void _drawGrid(Canvas canvas, _Projector p) {
    final gridPaint = Paint()
      ..color = const Color(0xFF6EB0D6).withValues(alpha: .060)
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
      ..color = const Color(0xFF8CC2DE).withValues(alpha: .18)
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
        if (textures == null && points > ring.length * .83) {
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

  /// Visible departure shared by the route and the homebound ship.
  /// This prevents a one-frame position jump when the return route fades.
  Offset _visibleDeparture(_Projector p) {
    final china = p.project(_startLongitude, _startLatitude);
    if (china != null) return china;
    for (var i = 1; i <= 180; i++) {
      final geo = _greatCircle(
        _startLongitude, _startLatitude,
        node.longitude, node.latitude, i / 180,
      );
      final visible = p.project(geo.dx, geo.dy);
      if (visible != null) return visible;
    }
    return p.projectAtLimb(_startLongitude, _startLatitude);
  }

  /// If China is behind the globe (e.g. when looking at North America),
  /// start the visible arc from the first point emerging at the limb.
  VelaFlightRoute? _visibleFlight(_Projector p) {
    if (phase == VelaPhase.idle) return null;
    final arrival = p.project(node.longitude, node.latitude);
    if (arrival == null) return null;
    final departure = _visibleDeparture(p);
    return VelaFlightRoute(
      start: departure,
      end: arrival,
      globeRadius: p.radius,
    );
  }

  void _drawRoute(Canvas canvas, _Projector p, VelaFlightRoute flight) {
    final isError = phase == VelaPhase.error;
    final glow = isError
        ? const Color(0xFFFF8992)
        : const Color(0xFF4CB5FF);
    // Separate subdued full arc and bright travelled progress.
    canvas.drawPath(
      flight.path(),
      Paint()
        ..color = glow.withValues(alpha: .17)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, p.radius * .005),
    );
    final fraction = sailProgress;
    final covered = flight.path(until: fraction);
    canvas.drawPath(
      covered,
      Paint()
        ..color = glow.withValues(alpha: .72)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(7, p.radius * .030)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawPath(
      covered,
      Paint()
        ..color = isError
            ? const Color(0xFFFFB3B5)
            : const Color(0xFFBFE9FF)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.8, p.radius * .007),
    );
    final beacon = flight.pointAt(fraction);
    canvas.drawCircle(
      beacon, math.max(3, p.radius * .009),
      Paint()..color = Colors.white.withValues(alpha: .8),
    );
  }

  void _drawMarkers(
    Canvas canvas,
    _Projector p,
    double side,
    VelaFlightRoute? flight,
  ) {
    final china = p.project(_startLongitude, _startLatitude);
    if (china != null) {
      _mark(canvas, china, p.radius * .012, const Color(0xFF8FD9FF));
      _label(canvas, 'BEIJING',
          china.translate(-p.radius * .085, -p.radius * .09), side);
    }
    if (phase == VelaPhase.idle) {
      // Use the SAME departure point and sprite offset as the route.
      // It stays continuous as the sphere rotates through the horizon.
      final position = homebound ? _visibleDeparture(p) : china;
      if (position != null) {
        _drawSail(
          canvas,
          position.translate(0, -p.radius * .041),
          p.radius * .058,
        );
      }
      return;
    }
    final target = p.project(node.longitude, node.latitude);
    if (target != null) {
      _mark(canvas, target, p.radius * .014, const Color(0xFFBAEAFF));
      _label(canvas, node.mapLabel,
          target.translate(p.radius * .035, p.radius * .034), side);
    }
    if (flight != null) {
      _drawSail(
        canvas, flight.pointAt(sailProgress).translate(0, -p.radius * .041),
        p.radius * .057,
      );
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
          fontFamily: 'Segoe UI',
          fontFamilyFallback: const ['Arial'],
          fontSize: math.max(10.5, side * .023),
          fontWeight: FontWeight.w600,
          letterSpacing: .85,
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
      old.homebound != homebound ||
      old.sailProgress != sailProgress ||
      old.cloudProgress != cloudProgress ||
      old.textures != textures ||
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

  /// Provides a stable off-screen coastline marker during the return
  /// rotation, instead of letting the boat vanish on the far hemisphere.
  Offset projectAtLimb(double longitude, double latitude) {
    final lon = longitude * math.pi / 180;
    final lat = latitude * math.pi / 180;
    final dx = math.cos(lat) * math.sin(lon - lon0);
    final dy = -(math.cos(lat0) * math.sin(lat) -
        math.sin(lat0) * math.cos(lat) * math.cos(lon - lon0));
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 1e-6) return center + Offset(radius * .97, 0);
    return center + Offset(dx / length, dy / length) * (radius * .97);
  }

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
