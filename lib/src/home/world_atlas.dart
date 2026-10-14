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
            ColoredBox(color: dark ? const Color(0xFF102A36)
                : const Color(0xFFBFD6D3)),
            _WorldTiles(camera: camera,
              asset: 'assets/earth/earth_watercolor_day.jpg', show: !dark),
            _WorldTiles(camera: camera,
              asset: 'assets/earth/earth_watercolor_night.jpg', show: dark),
            IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0x0E071728), Color(0x000B233F),
                        Color(0x29040C18)]
                    : const [Color(0x0AD7E8F4), Color(0x000A3B69),
                        Color(0x11091B32)],
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
            left: camera.tileLeft + index * camera.worldWidth,
            top: camera.top,
            width: camera.worldWidth,
            height: camera.worldHeight,
            child: Image.asset(asset, fit: BoxFit.fill,
              filterQuality: FilterQuality.high,
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
    final home = camera.project(VelaWorldCamera.beijing);
    _drawCityNames(canvas);
    if (size.width > 720) _drawCompass(canvas, size);
    _marker(canvas, home, 'BEIJING', const Color(0xFFE3B777),
      showLabel: !active || homebound);
    if (!active || (from - to).distance < .01) return;
    final route = VelaFlightRoute(
      start: camera.project(from),
      end: camera.projectAlong(from, to),
      globeRadius: size.shortestSide * .42,
    );
    final dashedInk = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = dark ? const Color(0xD1D4B57D)
          : const Color(0xB7336171);
    for (final metric in route.path().computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 15) {
        canvas.drawPath(metric.extractPath(
          d, math.min(d + 7, metric.length)), dashedInk);
      }
    }
    final traveled = route.path(until: progress);
    canvas.drawPath(traveled, Paint()
      ..style = PaintingStyle.stroke ..strokeWidth = 8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9)
      ..color = dark ? const Color(0x72C1A97E)
          : const Color(0x779BC7CB));
    canvas.drawPath(traveled, Paint()
      ..style = PaintingStyle.stroke ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = dark ? const Color(0xFFE9C78D)
          : const Color(0xFF365A61));
    _marker(canvas, camera.projectAlong(from, to), label,
      dark ? const Color(0xFFD6BE87)
           : const Color(0xFF2E6E79), showLabel: true);
    final boat = route.pointAt(progress);
    canvas.drawCircle(boat, 17, Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
      ..color = dark ? const Color(0x77E4C77B)
          : const Color(0x77A5CED1));
    canvas.save();
    canvas.translate(boat.dx - 15, boat.dy - 15);
    const VelaSailPainter().paint(canvas, const Size(30, 30));
    canvas.restore();
  }

  String _titleCase(String input) =>
    input.toLowerCase().split(' ')
      .map((word) => word.isEmpty ? word :
        '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');

  void _drawCompass(Canvas canvas, Size size) {
    final center = Offset(size.width - 85, 165);
    final ink = dark ? const Color(0xFFDEC99D)
        : const Color(0xFF234C5B);
    final p = Paint()..color = ink.withValues(alpha: .8)
      ..style = PaintingStyle.stroke..strokeWidth = 1.2;
    canvas.drawCircle(center, 41, p);
    canvas.drawCircle(center, 34, p..strokeWidth = .6);
    for (var i = 0; i < 16; i++) {
      final a = (i * math.pi / 8) - math.pi / 2;
      final v = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(center + v * (i.isEven ? 31 : 35),
        center + v * 39, p..strokeWidth = i.isEven ? 1.2 : .6);
    }
    final up = Path()..moveTo(center.dx, center.dy-28)
      ..lineTo(center.dx-7,center.dy+5)
      ..lineTo(center.dx+6,center.dy-4)..close();
    final down = Path()..moveTo(center.dx,center.dy+28)
      ..lineTo(center.dx+7,center.dy-5)
      ..lineTo(center.dx-6,center.dy+4)..close();
    canvas.drawPath(up,Paint()
      ..color = ink.withValues(alpha: .85));
    canvas.drawPath(down,Paint()
      ..color = ink.withValues(alpha: .35));
    _placeText(canvas, center + const Offset(-4,-58), 'N');
    _placeText(canvas, center + const Offset(-4,43), 'S');
    _placeText(canvas, center + const Offset(44,-6), 'E');
    _placeText(canvas, center + const Offset(-57,-6), 'W');
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
          _titleCase(city.label), tiny: true);
    }
  }

  void _placeText(Canvas canvas, Offset position, String value,
      {bool tiny = false}) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: TextStyle(
        color: dark ? const Color(0xFFEADCB9) : const Color(0xFF284B55),
        fontFamily: 'Georgia',
        fontStyle: FontStyle.italic,
        fontSize: tiny ? 12 : 14,
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
    _placeText(canvas, position + const Offset(13, -16),
      _titleCase(label));
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
