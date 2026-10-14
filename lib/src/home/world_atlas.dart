import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../brand/vela_sail_mark.dart';
import 'demo_connection.dart';
import 'flight_route.dart';
import 'vela_world_cities.dart';

/// Camera for a precisely georeferenced 2:1 equirectangular world map.
@immutable
class VelaWorldCamera {
  const VelaWorldCamera({required this.size, required this.longitude,
    required this.latitude});
  final Size size;
  final double longitude;
  final double latitude;
  static const beijing = Offset(116.4, 39.9);

  static double shortestDelta(double from, double to) =>
      (to - from + 540) % 360 - 180;

  double get worldWidth => math.max(size.width * 2.2, size.height * 4.8);
  double get worldHeight => worldWidth / 2;
  double get top => size.height / 2 -
      (90 - latitude) / 180 * worldHeight;

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
    size.height / 2 +
        (latitude - geo.dy) / 180 * worldHeight,
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
  VelaWorldCity? _destinationCity;
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
    return Offset(
      _routeFrom.dx +
          VelaWorldCamera.shortestDelta(_routeFrom.dx, _routeTo.dx) * fraction,
      _routeFrom.dy + (_routeTo.dy - _routeFrom.dy) * fraction,
    );
  }

  void _sync() {
    if (!mounted) return;
    final phase = widget.demo.phase;
    final node = widget.demo.selected;
    final realName = widget.demo.realNodeName;
    final key = '${node.id}:${realName ?? node.title}';
    if (_lastPhase == phase && _lastNode == key) return;
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
      final city = VelaWorldCityCatalog.resolve(realName ?? node.title, node);
      final sameNode = _destinationCity?.label == city.label;
      final resumeReturn = sameNode && _returning;
      _returning = false;
      _homebound = false;
      if (!sameNode) {
        // The route starts at the current boat position if retargeted.
        _routeFrom = _destination == null
            ? VelaWorldCamera.beijing : _currentBoatLocation;
        _routeTo = city.coordinate;
        _destinationCity = city;
        _destination = node;
        _sail.forward(from: 0);
      } else if (resumeReturn) {
        _sail.forward();
      } else if (!_sail.isAnimating && _sail.value < 1) {
        // Core may confirm connected before the visual voyage is finished.
        _sail.forward();
      }
      _focus(city.coordinate);
    }
    _lastPhase = phase;
    _lastNode = key;
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
          final camera = VelaWorldCamera(
            size: Size(bounds.maxWidth, bounds.maxHeight),
            longitude: _focusLongitude, latitude: _focusLatitude);
          final active = _returning || (
              widget.demo.phase != VelaPhase.idle &&
              widget.demo.phase != VelaPhase.error);
          return ClipRect(child: Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: Color(0xFF071929)),
            _WorldTiles(camera: camera,
              asset: 'assets/earth/earth_watercolor_day.jpg', show: !dark),
            _WorldTiles(camera: camera,
              asset: 'assets/earth/earth_watercolor_night.jpg', show: dark),
            IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0x44071728), Color(0x110B233F),
                        Color(0x77040C18)]
                    : const [Color(0x28D7E8F4), Color(0x080A3B69),
                        Color(0x33091B32)],
              ),
            ))),
            CustomPaint(painter: _WorldRoutePainter(
              camera: camera, from: _routeFrom, to: _routeTo,
              label: _destinationCity?.label ?? 'BEIJING',
              progress: Curves.easeInOutCubic.transform(_sail.value),
              active: active, homebound: _homebound, dark: dark,
            ), child: const SizedBox.expand()),
          ]));
        },
      ));
    });
  }
}

class _WorldTiles extends StatelessWidget {
  const _WorldTiles({required this.camera, required this.asset,
    required this.show, this.darkTint = false, this.cityLights = false});
  final VelaWorldCamera camera;
  final String asset;
  final bool show;
  final bool darkTint;
  final bool cityLights;

  // v1.3.0 night_lights.png contains only NASA-like city-light radiance.
  // Black pixels must be transparent, or nighttime loses the continents.
  static const _lightsAlpha = ColorFilter.matrix([
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    .28, .55, .17, 0, 0,
  ]);
  static const _midnightTerrain = ColorFilter.matrix([
    .30, .05, .02, 0, 0,
    .02, .40, .04, 0, 0,
    .01, .06, .51, 0, 0,
    0, 0, 0, 1, 0,
  ]);
  static const _natural = ColorFilter.matrix([
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedOpacity(
      opacity: show ? 1 : 0,
      duration: const Duration(milliseconds: 950),
      curve: Curves.easeInOutCubic,
      child: ColorFiltered(
        colorFilter: _natural,
        child: Stack(clipBehavior: Clip.none, children: [
          for (final index in const [-1, 0, 1])
            Positioned(
              left: camera.tileLeft + index * camera.worldWidth,
              top: camera.top,
              width: camera.worldWidth,
              height: camera.worldHeight,
              child: Image.asset(asset,
                fit: BoxFit.fill, filterQuality: FilterQuality.high,
                gaplessPlayback: true),
            ),
        ]),
      ),
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
    final home = camera.project(VelaWorldCamera.beijing);
    _drawCityNames(canvas);
    _marker(canvas, home, 'BEIJING', const Color(0xFFE3B777),
      showLabel: !active || homebound);
    if (!active || (from - to).distance < .01) return;
    final route = VelaFlightRoute(
      start: camera.project(from),
      end: camera.projectAlong(from, to),
      globeRadius: size.shortestSide * .42,
    );
    canvas.drawPath(route.path(), Paint()
      ..style = PaintingStyle.stroke ..strokeWidth = 1.5
      ..color = const Color(0x77B9DFFF));
    final traveled = route.path(until: progress);
    canvas.drawPath(traveled, Paint()
      ..style = PaintingStyle.stroke ..strokeWidth = 8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9)
      ..color = const Color(0xB06FCBFF));
    canvas.drawPath(traveled, Paint()
      ..style = PaintingStyle.stroke ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round ..color = const Color(0xFFE6BB76));
    _marker(canvas, camera.projectAlong(from, to), label,
      const Color(0xFF84D0FF), showLabel: true);
    final boat = route.pointAt(progress);
    canvas.drawCircle(boat, 17, Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
      ..color = const Color(0x6685D4FF));
    canvas.save();
    canvas.translate(boat.dx - 15, boat.dy - 15);
    const VelaSailPainter().paint(canvas, const Size(30, 30));
    canvas.restore();
  }

  void _drawCityNames(Canvas canvas) {
    // Keep the atlas readable; don't pile overlapping names in East Asia.
    final occupied = <Rect>[];
    for (final city in VelaWorldCityCatalog.cityList) {
      if (city.label == 'BEIJING' || city.label == label) continue;
      final center = camera.project(city.coordinate);
      if (center.dx < 15 || center.dx > camera.size.width - 75 ||
          center.dy < 16 || center.dy > camera.size.height - 16) {
        continue;
      }
      final place = Rect.fromLTWH(center.dx, center.dy - 13, 90, 23);
      if (occupied.any((rect) => rect.overlaps(place))) continue;
      occupied.add(place);
      final dot = Paint()
        ..color = dark ? const Color(0xFFDBCA9C) : const Color(0xFF355B5A);
      canvas.drawCircle(center, 2, dot);
      _placeText(canvas, center + const Offset(7, -16),
          city.label, tiny: true);
    }
  }

  void _placeText(Canvas canvas, Offset position, String value,
      {bool tiny = false}) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: TextStyle(
        color: dark ? const Color(0xFFEADCB9) : const Color(0xFF284B55),
        fontFamily: 'Georgia',
        fontSize: tiny ? 9 : 11,
        fontWeight: tiny ? FontWeight.w500 : FontWeight.w700,
        letterSpacing: tiny ? .75 : 1.0,
        shadows: dark ? const [Shadow(
          color: Color(0xFF102537), blurRadius: 5)] : null,
      )), textDirection: TextDirection.ltr, maxLines: 1,
    )..layout();
    painter.paint(canvas, Offset(
      position.dx.clamp(0.0, math.max(0.0, camera.size.width - painter.width)),
      position.dy.clamp(0.0, math.max(0.0, camera.size.height - painter.height)),
    ));
  }

  void _marker(Canvas canvas, Offset position, String label, Color color,
      {required bool showLabel}) {
    if (position.dx < -180 || position.dx > camera.size.width + 180 ||
        position.dy < -60 || position.dy > camera.size.height + 60) {
      return;
    }
    canvas.drawCircle(position, 10,
        Paint()..color = color.withValues(alpha: .16));
    canvas.drawCircle(position, 3.5, Paint()..color = color);
    if (!showLabel) {
      return;
    }
    _placeText(canvas, position + const Offset(13, -16), label);
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
