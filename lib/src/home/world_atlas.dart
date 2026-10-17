import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../brand/vela_sail_mark.dart';
import 'demo_connection.dart';
import 'maritime_route.dart';

/// Camera for a precisely georeferenced 2:1 equirectangular world map.
@immutable
class VelaWorldCamera {
  const VelaWorldCamera({required this.size, required this.longitude,
    required this.latitude,
    this.portraitWidthScale = portraitHeightScale});
  final Size size;
  final double longitude;
  final double latitude;
  final double portraitWidthScale;
  static const beijing = Offset(116.4, 39.9);

  static double shortestDelta(double from, double to) =>
      (to - from + 540) % 360 - 180;

  // "Wide voyage": reveal oceans and neighboring continents instead of
  // magnifying one country across the entire dashboard. On portrait screens,
  // keep enough height to cover the canvas without stretching the 2:1 map.
  static const double landscapeWidthScale = 1.28;
  static const double portraitHeightScale = 2.08;
  static const double androidCompactScale = 1.68;
  double get worldWidth => math.max(
      size.width * landscapeWidthScale,
      size.height * portraitWidthScale);
  double get worldHeight => worldWidth / 2;

  // Land near the poles may sit above/below the visual center. Keep the
  // background fully covering the viewport rather than exposing black strips.
  // The route and city labels must share this exact same vertical transform.
  double get top {
    if (worldHeight < size.height) {
      // Compact portrait atlas is centered over a blurred full-bleed map,
      // instead of stretching the artwork to fit the tall Android screen.
      return (size.height - worldHeight) / 2;
    }
    final desired = size.height / 2 -
        (90 - latitude) / 180 * worldHeight;
    return desired.clamp(size.height - worldHeight, 0.0).toDouble();
  }

  // A periodic world map is tiled to eliminate seams at +/-180 degrees.
  double get tileLeft {
    final left = size.width / 2 -
        (longitude + 180) / 360 * worldWidth;
    final wrapped = left % worldWidth;
    return wrapped > 0 ? wrapped - worldWidth : wrapped;
  }

  Offset project(Offset geo) => Offset(
    size.width / 2 +
        shortestDelta(longitude, geo.dx) / 360 * worldWidth,
    top + (90 - geo.dy) / 180 * worldHeight,
  );

  Offset projectAlong(Offset origin, Offset destination) => Offset(
    project(origin).dx +
        shortestDelta(origin.dx, destination.dx) / 360 * worldWidth,
    project(destination).dy,
  );
}

/// A background-only feature. The existing native VPN/core and glass UI remain
/// untouched. The controller already projects real network status to the UI.
class VelaWorldAtlas extends StatefulWidget {
  const VelaWorldAtlas({super.key, required this.demo});
  final VelaDemoController demo;
  @override
  State<VelaWorldAtlas> createState() => _VelaWorldAtlasState();
}

class _VelaWorldAtlasState extends State<VelaWorldAtlas>
    with TickerProviderStateMixin {
  late final AnimationController _pan;
  late final AnimationController _sail;
  double _fromLon = VelaWorldCamera.beijing.dx;
  double _toLon = VelaWorldCamera.beijing.dx;
  double _fromLat = VelaWorldCamera.beijing.dy;
  double _toLat = VelaWorldCamera.beijing.dy;
  Offset _routeFrom = VelaWorldCamera.beijing;
  Offset _routeTo = VelaWorldCamera.beijing;
  VelaDemoNode? _destination;
  VelaPhase? _lastPhase;
  String? _lastNode;
  bool _returning = false;
  bool _homebound = false;

  @override
  void initState() {
    super.initState();
    _pan = AnimationController(vsync: this,
      value: 1, duration: const Duration(milliseconds: 1800));
    _sail = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 2000));
    _sail.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && _returning && mounted) {
        _returning = false;
        _homebound = true;
        _focus(VelaWorldCamera.beijing);
        setState(() {});
      }
    });
    widget.demo.addListener(_sync);
    _sync();
  }

  double get _focusLongitude => _fromLon +
      (_toLon - _fromLon) * Curves.easeInOutCubic.transform(_pan.value);
  double get _focusLatitude => _fromLat +
      (_toLat - _fromLat) * Curves.easeInOutCubic.transform(_pan.value);

  void _focus(Offset destination) {
    final lon = _focusLongitude;
    final lat = _focusLatitude;
    final delta = VelaWorldCamera.shortestDelta(lon, destination.dx);
    if (delta.abs() < .01 && (destination.dy - lat).abs() < .01) return;
    _fromLon = lon;
    _fromLat = lat;
    _toLon = lon + delta;
    _toLat = destination.dy;
    _pan.forward(from: 0);
  }

  Offset get _currentBoatLocation {
    final fraction = Curves.easeInOutCubic.transform(_sail.value);
    return VelaMaritimeRoute(from: _routeFrom, to: _routeTo)
        .pointAt(fraction);
  }

  void _sync() {
    if (!mounted) return;
    final phase = widget.demo.phase;
    final node = widget.demo.selected;
    if (_lastPhase == phase && _lastNode == node.id) return;
    if (phase == VelaPhase.idle || phase == VelaPhase.error) {
      if (_sail.value > .001 && !_returning) {
        _returning = true;
        _homebound = false;
        _sail.reverse();
      } else if (!_returning) {
        _homebound = true;
        _focus(VelaWorldCamera.beijing);
      }
    } else {
      final sameNode = _destination?.id == node.id;
      final resumeReturn = sameNode && _returning;
      _returning = false;
      _homebound = false;
      if (!sameNode) {
        // The route starts at the current boat position if retargeted.
        _routeFrom = _destination == null
            ? VelaMaritimeRoute.shanghai : _currentBoatLocation;
        _routeTo = Offset(node.longitude, node.latitude);
        _destination = node;
        _sail.forward(from: 0);
      } else if (resumeReturn) {
        _sail.forward();
      } else if (!_sail.isAnimating && _sail.value < 1) {
        // Core may confirm connected before the visual voyage is finished.
        _sail.forward();
      }
      _focus(Offset(node.longitude, node.latitude));
    }
    _lastPhase = phase;
    _lastNode = node.id;
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant VelaWorldAtlas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.demo, widget.demo)) {
      oldWidget.demo.removeListener(_sync);
      widget.demo.addListener(_sync);
      _lastPhase = null;
      _sync();
    }
  }

  @override
  void dispose() {
    widget.demo.removeListener(_sync);
    _pan.dispose();
    _sail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(builder: (context, bounds) {
      if (!bounds.maxWidth.isFinite || !bounds.maxHeight.isFinite ||
          bounds.maxWidth <= 0 || bounds.maxHeight <= 0) {
        return const SizedBox.shrink();
      }
      return RepaintBoundary(child: AnimatedBuilder(
        animation: Listenable.merge([_pan, _sail]),
        builder: (context, _) {
          final size = Size(bounds.maxWidth, bounds.maxHeight);
          final compactAndroid = defaultTargetPlatform ==
              TargetPlatform.android && size.height > size.width * 1.25;
          final camera = VelaWorldCamera(
            size: size,
            longitude: _focusLongitude, latitude: _focusLatitude,
            portraitWidthScale: compactAndroid
                ? VelaWorldCamera.androidCompactScale
                : VelaWorldCamera.portraitHeightScale);
          final coverCamera = compactAndroid ? VelaWorldCamera(
            size: size, longitude: _focusLongitude,
            latitude: _focusLatitude) : camera;
          final active = _returning || (
              widget.demo.phase != VelaPhase.idle &&
              widget.demo.phase != VelaPhase.error);
          return ClipRect(child: Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: Color(0xFF071929)),
            if (compactAndroid)
              ImageFiltered(
                // Full-bleed soft watercolor beneath a smaller atlas avoids
                // exposed black strips at the north/south edges.
                imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Stack(fit: StackFit.expand, children: [
                  _WorldTiles(camera: coverCamera,
                    asset: 'assets/world/watercolor_day.webp', show: !dark),
                  _WorldTiles(camera: coverCamera,
                    asset: 'assets/world/watercolor_night.webp', show: dark),
                ]),
              ),
            ShaderMask(
              shaderCallback: (rect) => (compactAndroid
                ? const LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.white,
                      Colors.white, Colors.transparent],
                    stops: [0, .16, .84, 1],
                  )
                : const LinearGradient(
                    colors: [Colors.white, Colors.white],
                  )).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: Stack(fit: StackFit.expand, children: [
                _WorldTiles(camera: camera,
                  asset: 'assets/world/watercolor_day.webp', show: !dark),
                _WorldTiles(camera: camera,
                  asset: 'assets/world/watercolor_night.webp', show: dark),
              ]),
            ),
            IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0x44071728), Color(0x110B233F),
                        Color(0x77040C18)]
                    : const [Color(0x33F8F5E8), Color(0x1AEAF4F4),
                        Color(0x40F5F1E8)],
              ),
            ))),
            CustomPaint(painter: _WorldRoutePainter(
              camera: camera, from: _routeFrom, to: _routeTo,
              label: _destination?.mapLabel ?? 'WORLD',
              progress: Curves.easeInOutCubic.transform(_sail.value),
              active: active, homebound: _homebound, dark: dark,
            ), child: const SizedBox.expand()),
            // The animated layer does not invalidate the static watercolor.
            VelaAtlasWeather(camera: camera, dark: dark,
              connected: widget.demo.phase == VelaPhase.connected,
              routeFrom: _routeFrom, routeTo: _routeTo),
          ]));
        },
      ));
    });
  }
}



class VelaWeatherCadence {
  const VelaWeatherCadence._();
  // 480s is divisible by every independent effect's duration.
  static const int timelineSeconds = 480;
  static const int cloudSeconds = 96; // 60–120s
  static const int oceanSeconds = 12; // 8–15s
  static const int windSeconds = 30; // 20–40s
  static const int routeSeconds = 4; // 3–6s
  static const int nightSeconds = 15; // 10–20s

  static double progress(double timeline, int periodSeconds) {
    final cycles = timeline * timelineSeconds / periodSeconds;
    return cycles - cycles.floorToDouble();
  }
}

/// Transparent animations only; no image decode, network calls, or new
/// VPN/FlClash listeners on an animation frame.
class VelaAtlasWeather extends StatefulWidget {
  const VelaAtlasWeather({
    super.key, required this.camera, required this.dark,
    this.connected = false,
    this.routeFrom = VelaMaritimeRoute.shanghai,
    this.routeTo = VelaMaritimeRoute.shanghai,
  });
  final VelaWorldCamera camera;
  final bool dark;
  final bool connected;
  final Offset routeFrom;
  final Offset routeTo;

  @override
  State<VelaAtlasWeather> createState() => _VelaAtlasWeatherState();
}

class _VelaAtlasWeatherState extends State<VelaAtlasWeather>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion;
  bool _backgrounded = false;
  List<Offset> _route = const <Offset>[];

  void _rebuildRoute() {
    // Spline sampling is done once per route change, never every frame.
    _route = widget.connected &&
        (widget.routeFrom - widget.routeTo).distance > .01
        ? VelaMaritimeRoute(
            from: widget.routeFrom, to: widget.routeTo).samples
        : const <Offset>[];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _motion = AnimationController(vsync: this,
        duration: const Duration(seconds: VelaWeatherCadence.timelineSeconds));
    _rebuildRoute();
  }

  void _syncMotion() {
    // Flutter widget tests must settle even though production repeats.
    final inTest = Platform.environment['FLUTTER_TEST'] == 'true';
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (inTest || reduce || _backgrounded) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant VelaAtlasWeather oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connected != widget.connected ||
        oldWidget.routeFrom != widget.routeFrom ||
        oldWidget.routeTo != widget.routeTo) {
      _rebuildRoute();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _backgrounded = state != AppLifecycleState.resumed;
    _syncMotion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: AnimatedBuilder(animation: _motion, builder: (context, _) =>
        CustomPaint(
          painter: VelaAtlasWeatherPainter(
            camera: widget.camera, dark: widget.dark, phase: _motion.value,
            connected: widget.connected, routeFrom: widget.routeFrom,
            route: _route),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

/// Five perceptible, gentle watercolor movements. Static world art is not
/// re-decoded or repainted by this independent animated painter.
@immutable
class VelaAtlasWeatherPainter extends CustomPainter {
  const VelaAtlasWeatherPainter({
    required this.camera, required this.dark, required this.phase,
    this.connected = false,
    this.routeFrom = VelaMaritimeRoute.shanghai,
    this.route = const <Offset>[],
  });
  final VelaWorldCamera camera;
  final bool dark;
  final double phase;
  final bool connected;
  final Offset routeFrom;
  final List<Offset> route;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final cloudTime = VelaWeatherCadence.progress(
        phase, VelaWeatherCadence.cloudSeconds) * math.pi * 2;
    final oceanTime = VelaWeatherCadence.progress(
        phase, VelaWeatherCadence.oceanSeconds) * math.pi * 2;
    final windCycle = (VelaWeatherCadence.progress(
        phase, VelaWeatherCadence.windSeconds) + .18) % 1;
    final windTime = windCycle * math.pi * 2;
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // Wider pearl-blue sea crests are intentionally noticeable, but remain
    // geographically anchored to open-water coordinates during camera pans.
    final water = Paint()
      ..color = (dark ? const Color(0xFF9EDBEE) : const Color(0xFF2D8296))
          .withValues(alpha: dark ? .37 : .39)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round;
    final seaLight = Paint()
      ..color = (dark ? const Color(0xFFDAF9FF) : const Color(0xFFFFFFFF))
          .withValues(alpha: dark ? .29 : .57)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.15
      ..strokeCap = StrokeCap.round;
    for (final geo in const [
      Offset(-152, 23), Offset(-120, -16), Offset(-90, 6),
      Offset(-39, -26), Offset(-20, 5), Offset(34, -28),
      Offset(76, -16), Offset(96, -36), Offset(155, 5),
      Offset(173, -33), Offset(-167, -45),
    ]) {
      final center = camera.project(geo);
      if (center.dx < -140 || center.dx > size.width + 140 ||
          center.dy < -75 || center.dy > size.height + 75) {
        continue;
      }
      for (var k = 0; k < 3; k++) {
        final y = center.dy + k * 11.0;
        final drift = math.sin(oceanTime + k * .9 + geo.dx * .035);
        final x = center.dx + drift * 9;
        final scale = .78 + .16 * math.sin(oceanTime + k + 1);
        final span = 58 * scale;
        final path = Path()
          ..moveTo(x - span, y)
          ..cubicTo(x - span * .4, y - 6 - drift * 2,
              x + span * .25, y + 5 + drift * 2, x + span, y - 1);
        canvas.drawPath(path, k.isEven ? seaLight : water);
      }
    }

    // Semi-transparent, softly edged cloud banks with independent drift.
    // Multi-lobed shapes look like watercolor wisps rather than flat dots.
    for (var i = 0; i < 6; i++) {
      final drift = math.sin(cloudTime + i * .84);
      final x = size.width * ((i + .42) / 6) +
          drift * math.max(38.0, size.width * .07);
      final y = size.height * (.12 + (i % 4) * .215) +
          math.cos(cloudTime + i * .72) * 13;
      final width = math.min(230.0, math.max(115.0, size.width * .32));
      final cloudColor = dark
          ? const Color(0xFFE0EEFD) : const Color(0xFFFFFFFF);
      final diffuse = Paint()
        ..color = cloudColor.withValues(alpha: dark ? .19 : .31)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 17);
      final fringe = Paint()
        ..color = cloudColor.withValues(alpha: dark ? .11 : .19)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y),
          width: width, height: 42), diffuse);
      canvas.drawOval(Rect.fromCenter(
          center: Offset(x - width * .25, y - 8),
          width: width * .61, height: 43), fringe);
      canvas.drawOval(Rect.fromCenter(
          center: Offset(x + width * .19, y + 6),
          width: width * .72, height: 28), diffuse);
    }

    // 30-second appearing/disappearing wind currents; a hairline underneath
    // the pearl stroke gives contrast on both light and dark world textures.
    final windEnvelope =
        math.pow(math.sin(math.pi * windCycle), 2).toDouble();
    final windPaint = Paint()
      ..color = (dark ? const Color(0xFFDBECFF) : const Color(0xFF2C91A7))
          .withValues(alpha: (dark ? .13 : .17) + windEnvelope * .46)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final windSheen = Paint()
      ..color = const Color(0xFFF7FFFF)
          .withValues(alpha: .11 + windEnvelope * .35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .85
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 7; i++) {
      final x = size.width * ((i + .2) / 7) +
          math.sin(windTime + i * .92) * 33;
      final y = size.height * (.09 + (i % 5) * .195) +
          math.cos(windTime + i) * 13;
      final span = math.min(112.0, size.width * .22);
      final curve = Path()
        ..moveTo(x - span * .5, y)
        ..cubicTo(x - span * .23, y - 16,
            x + span * .22, y + 13, x + span * .5, y - 5);
      canvas.drawPath(curve, windPaint);
      canvas.drawPath(curve.shift(const Offset(0, -2)), windSheen);
    }

    // Tiny coastal atmospheric glows, only in dark mode. This is decorative,
    // not a live physical location/port map.
    if (dark) {
      final nightTime = VelaWeatherCadence.progress(
          phase, VelaWeatherCadence.nightSeconds) * math.pi * 2;
      final alpha = .14 + .13 * (.5 + .5 * math.sin(nightTime));
      final glow = Paint()
        ..color = const Color(0xFFF8D99C).withValues(alpha: alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      final core = Paint()
        ..color = const Color(0xFFFFE9BC).withValues(alpha: alpha * .82);
      for (final geo in const [
        Offset(121.47, 31.23), Offset(139.69, 35.68),
        Offset(103.82, 1.35), Offset(-74.01, 40.71),
        Offset(-.13, 51.50),
      ]) {
        final pos = camera.project(geo);
        if (pos.dx < -30 || pos.dx > size.width + 30 ||
            pos.dy < -30 || pos.dy > size.height + 30) {
          continue;
        }
        canvas.drawCircle(pos, 18, glow);
        canvas.drawCircle(pos, 2.2, core);
      }
    }

    // Premium route effect: a single soft tapered light streak rather than
    // obvious moving dots. It follows the cached real spline only while
    // connected, softly fades at both endpoints and repeats every four sec.
    if (connected && route.length >= 2) {
      final progress = VelaWeatherCadence.progress(
          phase, VelaWeatherCadence.routeSeconds);
      final fade = math.sin(math.pi * progress);
      if (fade > .01) {
        final gleam = Path();
        const tailLength = .09;
        for (var i = 0; i <= 24; i++) {
          final t = (progress - tailLength * (1 - i / 24))
              .clamp(0.0, 1.0);
          final scaled = t * (route.length - 1);
          final index = math.min(route.length - 2, scaled.floor());
          final geo = Offset.lerp(route[index], route[index + 1],
              scaled - index)!;
          final pos = camera.projectAlong(routeFrom, geo);
          if (i == 0) {
            gleam.moveTo(pos.dx, pos.dy);
          } else {
            gleam.lineTo(pos.dx, pos.dy);
          }
        }
        final ambient = Paint()
          ..color = const Color(0xFFE2F7FF)
              .withValues(alpha: .26 * fade)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 7
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        final pearl = Paint()
          ..color = const Color(0xFFFFEAC2)
              .withValues(alpha: .75 * fade)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.2;
        canvas.drawPath(gleam, ambient);
        canvas.drawPath(gleam, pearl);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant VelaAtlasWeatherPainter old) =>
      old.phase != phase || old.dark != dark ||
      old.connected != connected || old.routeFrom != routeFrom ||
      old.route != route ||
      old.camera.size != camera.size ||
      old.camera.longitude != camera.longitude ||
      old.camera.latitude != camera.latitude ||
      old.camera.portraitWidthScale != camera.portraitWidthScale;
}

/// Exactly the same artwork and georeferenced coordinates in both themes.
/// Only the source texture changes; camera projection and route are unchanged.
class _WorldTiles extends StatelessWidget {
  const _WorldTiles({required this.camera, required this.asset,
    required this.show});
  final VelaWorldCamera camera;
  final String asset;
  final bool show;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedOpacity(
      opacity: show ? 1 : 0,
      duration: const Duration(milliseconds: 950),
      curve: Curves.easeInOutCubic,
      child: Stack(clipBehavior: Clip.none, children: [
        for (final index in const [-1, 0, 1])
          Positioned(
            // A subpixel overlap hides raster-edge anti-aliasing. The source
            // artwork itself is blended seamlessly at build time.
            left: camera.tileLeft + index * camera.worldWidth - .65,
            top: camera.top,
            width: camera.worldWidth + 1.3,
            height: camera.worldHeight,
            child: Image.asset(asset,
              fit: BoxFit.fill, filterQuality: FilterQuality.high,
              gaplessPlayback: true),
          ),
      ]),
    ),
  );
}

class _WorldRoutePainter extends CustomPainter {
  const _WorldRoutePainter({required this.camera, required this.from,
    required this.to, required this.label, required this.progress,
    required this.active, required this.homebound, required this.dark});
  final VelaWorldCamera camera;
  final Offset from;
  final Offset to;
  final String label;
  final double progress;
  final bool active;
  final bool homebound;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final home = camera.project(VelaMaritimeRoute.shanghai);
    _drawGeographicCities(canvas);
    _marker(canvas, home, 'SHANGHAI', const Color(0xFFE3B777),
      showLabel: !active || homebound);
    if (!active || (from - to).distance < .01) return;
    final route = VelaMaritimeRoute(from: from, to: to);
    Offset geoProject(Offset geo) => camera.projectAlong(from, geo);
    canvas.drawPath(route.path(geoProject), Paint()
      ..style = PaintingStyle.stroke ..strokeWidth = 2.8
      ..color = const Color(0xA4B9DFFF));
    final traveled = route.path(geoProject, until: progress);
    canvas.drawPath(traveled, Paint()
      ..style = PaintingStyle.stroke ..strokeWidth = 13
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11)
      ..color = const Color(0xB06FCBFF));
    canvas.drawPath(traveled, Paint()
      ..style = PaintingStyle.stroke ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round ..color = const Color(0xFFE6BB76));
    _marker(canvas, camera.projectAlong(from, to), label,
      const Color(0xFF84D0FF), showLabel: true);
    final boat = geoProject(route.pointAt(progress));
    canvas.drawCircle(boat, 25, Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
      ..color = const Color(0x6685D4FF));
    canvas.save();
    canvas.translate(boat.dx - 23, boat.dy - 23);
    const VelaSailPainter().paint(canvas, const Size(46, 46));
    canvas.restore();
  }

  static const _cities = <(String, Offset)>[
    ('Shanghai', Offset(121.47, 31.23)),
    ('Tokyo', Offset(139.69, 35.68)),
    ('Singapore', Offset(103.82, 1.35)),
    ('Hong Kong', Offset(114.17, 22.32)),
    ('Los Angeles', Offset(-118.24, 34.05)),
    ('New York', Offset(-74.01, 40.71)),
    ('London', Offset(-.13, 51.50)),
    ('Frankfurt', Offset(8.68, 50.11)),
    ('Sydney', Offset(151.21, -33.86)),
  ];

  void _drawGeographicCities(Canvas canvas) {
    final occupied = <Rect>[];
    for (final (city, coordinates) in _cities) {
      final position = camera.project(coordinates);
      if (position.dx < 24 || position.dx > camera.size.width - 120 ||
          position.dy < 35 || position.dy > camera.size.height - 20) {
        continue;
      }
      final labelRect = Rect.fromLTWH(position.dx, position.dy - 22, 96, 24);
      if (occupied.any((rect) => rect.overlaps(labelRect))) continue;
      occupied.add(labelRect);
      canvas.drawCircle(position, 4.0, Paint()
        ..color = dark ? const Color(0xFFE8C78E)
            : const Color(0xFF23546A));
      final text = TextPainter(
        text: TextSpan(text: city, style: TextStyle(
          color: dark ? const Color(0xFFFFEDC7)
              : const Color(0xFF153A4A),
          fontSize: 13,
          fontWeight: FontWeight.w700,
          shadows: [
            Shadow(color: dark ? const Color(0xE9001528)
                : const Color(0xEEFFFFFF), blurRadius: 6),
          ],
        )), textDirection: TextDirection.ltr, maxLines: 1,
      )..layout();
      text.paint(canvas, position + const Offset(7, -21));
    }
  }

  void _marker(Canvas canvas, Offset position, String label, Color color,
      {required bool showLabel}) {
    if (position.dx < -180 || position.dx > camera.size.width + 180 ||
        position.dy < -60 || position.dy > camera.size.height + 60) {
      return;
    }
    canvas.drawCircle(position, 14,
        Paint()..color = color.withValues(alpha: .23));
    canvas.drawCircle(position, 5, Paint()..color = color);
    if (!showLabel) {
      return;
    }
    final painter = TextPainter(
      text: TextSpan(text: label, style: TextStyle(
        color: dark ? const Color(0xFFEAF6FF) : const Color(0xFF163451),
        fontSize: 15, letterSpacing: 1.0, fontWeight: FontWeight.w800,
        shadows: const [Shadow(blurRadius: 5, color: Color(0xEEFFFFFF)),],
      )),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, Offset(
      (position.dx + 13).clamp(0.0,
        math.max(0.0, camera.size.width - painter.width)),
      (position.dy - 16).clamp(0.0,
        math.max(0.0, camera.size.height - painter.height)),
    ));
  }

  @override
  bool shouldRepaint(covariant _WorldRoutePainter old) =>
      old.camera.longitude != camera.longitude ||
      old.camera.latitude != camera.latitude ||
      old.camera.size != camera.size || old.from != from ||
      old.to != to || old.label != label ||
      old.progress != progress || old.active != active ||
      old.homebound != homebound || old.dark != dark;
}
