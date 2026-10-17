import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
            // Render in fixed layers: base atlas, shader atmosphere,
            // soft route, finally the few labels relevant to this session.
            VelaAtlasWeather(camera: camera, dark: dark,
              connected: widget.demo.phase == VelaPhase.connected),
            CustomPaint(painter: _WorldRoutePainter(
              camera: camera, from: _routeFrom, to: _routeTo,
              label: _destination?.mapLabel ?? 'WORLD',
              progress: Curves.easeInOutCubic.transform(_sail.value),
              active: active, connected: widget.demo.phase == VelaPhase.connected,
              homebound: _homebound, dark: dark,
            ), child: const SizedBox.expand()),
            VelaRouteSheen(camera: camera, from: _routeFrom, to: _routeTo,
              connected: widget.demo.phase == VelaPhase.connected,
              dark: dark),
          ]));
        },
      ));
    });
  }
}




class VelaWeatherCadence {
  const VelaWeatherCadence._();
  // The master timeline is divisible by every animation period.
  static const int timelineSeconds = 480;
  static const int cloudSeconds = 96;
  static const int oceanSeconds = 12;
  static const int windSeconds = 30;
  static const int routeSeconds = 4;
  static const int nightSeconds = 15;

  static double progress(double timeline, int periodSeconds) {
    final cycles = timeline * timelineSeconds / periodSeconds;
    return cycles - cycles.floorToDouble();
  }
}

/// A low-overhead GPU atmosphere. One procedural fragment shader produces
/// soft cloud volumes, masked watercolor sea flow and sparse wind currents.
/// The map and labels do NOT repaint when time advances.
class VelaAtlasWeather extends StatefulWidget {
  const VelaAtlasWeather({
    super.key, required this.camera, required this.dark,
    this.connected = false,
  });
  final VelaWorldCamera camera;
  final bool dark;
  final bool connected;

  @override
  State<VelaAtlasWeather> createState() => _VelaAtlasWeatherState();
}

class _VelaAtmosphereAssets {
  const _VelaAtmosphereAssets(this.program, this.ocean);
  final ui.FragmentProgram program;
  final ui.Image ocean;
}

class _VelaWorldAtmosphereLoader {
  static Future<_VelaAtmosphereAssets>? _cached;

  static Future<_VelaAtmosphereAssets> load() =>
      _cached ??= _create();

  static Future<_VelaAtmosphereAssets> _create() async {
    final program = await ui.FragmentProgram.fromAsset(
        'shaders/vela_watercolor_atmosphere.frag');
    final polygons = jsonDecode(
        await rootBundle.loadString('assets/maps/world_110m.json')) as List;
    // Geographic mask: white sea, black land. Draw once at startup on an
    // equirectangular canvas, with international-date-line wrap copies.
    const width = 1024;
    const height = 512;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    final ink = Paint()..color = Colors.black
        ..isAntiAlias = true;
    for (final raw in polygons) {
      if (raw is! List || raw.length < 3) { continue; }
      final path = Path();
      double? previousLon;
      double unwrapped = 0;
      var first = true;
      for (final pair in raw) {
        if (pair is! List || pair.length < 2 ||
            pair[0] is! num || pair[1] is! num) { continue; }
        final lon = (pair[0] as num).toDouble();
        final lat = (pair[1] as num).toDouble();
        unwrapped = previousLon == null ? lon :
          unwrapped + VelaWorldCamera.shortestDelta(previousLon, lon);
        final dx = (unwrapped + 180) / 360 * width;
        final dy = (90 - lat) / 180 * height;
        if (first) {
          path.moveTo(dx, dy);
          first = false;
        } else {
          path.lineTo(dx, dy);
        }
        previousLon = lon;
      }
      if (first) continue;
      path.close();
      for (final shift in [-width.toDouble(), 0.0, width.toDouble()]) {
        canvas.save();
        canvas.translate(shift, 0);
        canvas.drawPath(path, ink);
        canvas.restore();
      }
    }
    final picture = recorder.endRecording();
    final mask = await picture.toImage(width, height);
    picture.dispose();
    return _VelaAtmosphereAssets(program, mask);
  }
}

class _VelaAtlasWeatherState extends State<VelaAtlasWeather>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion;
  _VelaAtmosphereAssets? _assets;
  bool _backgrounded = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _motion = AnimationController(vsync: this,
        duration: const Duration(seconds: VelaWeatherCadence.timelineSeconds));
    // During widget tests don't request a GPU program: tests still verify
    // route/label state and ticker lifecycle without endless frames.
    if (Platform.environment['FLUTTER_TEST'] != 'true') {
      _loadShader();
    }
  }

  Future<void> _loadShader() async {
    try {
      final result = await _VelaWorldAtmosphereLoader.load();
      if (!mounted || _disposed) return;
      setState(() => _assets = result);
      // Shader loading is asynchronous: start the ticker immediately after
      // the GPU resource arrives, even if no other widget state changes.
      _syncMotion();
    } catch (_) {
      // An unsupported renderer still keeps the original artwork, route and
      // network controls usable. The shader never becomes a VPN dependency.
    }
  }

  void _syncMotion() {
    final testing = Platform.environment['FLUTTER_TEST'] == 'true';
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (testing || reduced || _backgrounded || _assets == null) {
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
  void didUpdateWidget(covariant VelaAtlasWeather old) {
    super.didUpdateWidget(old);
    _syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _backgrounded = state != AppLifecycleState.resumed;
    _syncMotion();
  }

  @override
  void dispose() {
    _disposed = true;
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
            program: _assets?.program, oceanMask: _assets?.ocean),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

/// The cloud/ocean/wind pass is handled entirely in the GPU. Shader uniforms
/// follow the SAME camera projection as the geographic map texture.
@immutable
class VelaAtlasWeatherPainter extends CustomPainter {
  const VelaAtlasWeatherPainter({
    required this.camera, required this.dark, required this.phase,
    this.program, this.oceanMask,
  });
  final VelaWorldCamera camera;
  final bool dark;
  final double phase;
  final ui.FragmentProgram? program;
  final ui.Image? oceanMask;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || program == null || oceanMask == null) return;
    final shader = program!.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, phase * VelaWeatherCadence.timelineSeconds)
      ..setFloat(3, dark ? 1 : 0)
      ..setFloat(4, camera.tileLeft)
      ..setFloat(5, camera.top)
      ..setFloat(6, camera.worldWidth)
      ..setFloat(7, camera.worldHeight)
      ..setFloat(8, 1.0) // Clearly visible, still restrained.
      ..setImageSampler(0, oceanMask!);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant VelaAtlasWeatherPainter old) =>
      old.phase != phase || old.dark != dark ||
      old.program != program || old.oceanMask != oceanMask ||
      old.camera.size != camera.size ||
      old.camera.longitude != camera.longitude ||
      old.camera.latitude != camera.latitude ||
      old.camera.portraitWidthScale != camera.portraitWidthScale;
}

/// Soft golden silk flowing over the active sea lane. It has no particle dots,
/// no sharply lit head, and draws only when the VPN is actually connected.
class VelaRouteSheen extends StatefulWidget {
  const VelaRouteSheen({
    super.key, required this.camera, required this.from,
    required this.to, required this.connected, required this.dark,
  });
  final VelaWorldCamera camera;
  final Offset from;
  final Offset to;
  final bool connected;
  final bool dark;

  @override
  State<VelaRouteSheen> createState() => _VelaRouteSheenState();
}

class _VelaRouteSheenState extends State<VelaRouteSheen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _progress;
  bool _backgrounded = false;
  List<Offset> _points = const <Offset>[];

  void _refresh() {
    _points = widget.connected && (widget.to - widget.from).distance > .01
        ? VelaMaritimeRoute(from: widget.from, to: widget.to).samples
        : const <Offset>[];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _progress = AnimationController(vsync: this,
      duration: const Duration(seconds: VelaWeatherCadence.routeSeconds));
    _refresh();
  }

  void _motion() {
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final test = Platform.environment['FLUTTER_TEST'] == 'true';
    if (test || reduced || _backgrounded || !widget.connected) {
      _progress.stop();
    } else if (!_progress.isAnimating) {
      _progress.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion();
  }

  @override
  void didUpdateWidget(covariant VelaRouteSheen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connected != widget.connected ||
        oldWidget.from != widget.from || oldWidget.to != widget.to) {
      _refresh();
      if (!widget.connected) _progress.value = 0;
    }
    _motion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _backgrounded = state != AppLifecycleState.resumed;
    _motion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(child: AnimatedBuilder(
      animation: _progress, builder: (context, _) => CustomPaint(
        painter: _VelaSilkRoutePainter(
          camera: widget.camera, from: widget.from,
          samples: _points, dark: widget.dark, phase: _progress.value),
        child: const SizedBox.expand(),
      ),
    )),
  );
}

class _VelaSilkRoutePainter extends CustomPainter {
  const _VelaSilkRoutePainter({
    required this.camera, required this.from, required this.samples,
    required this.dark, required this.phase,
  });
  final VelaWorldCamera camera;
  final Offset from;
  final List<Offset> samples;
  final bool dark;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;
    final path = Path();
    for (var k = 0; k < samples.length; k++) {
      final p = camera.projectAlong(from, samples[k]);
      if (k == 0) { path.moveTo(p.dx, p.dy); }
      else { path.lineTo(p.dx, p.dy); }
    }
    for (final metric in path.computeMetrics()) {
      if (metric.length == 0) continue;
      final start = (phase - .16).clamp(0.0, 1.0) * metric.length;
      final stop = (phase + .035).clamp(0.0, 1.0) * metric.length;
      if (stop <= start) continue;
      final segment = metric.extractPath(start, stop);
      final midpoint = metric.getTangentForOffset((start + stop) / 2);
      if (midpoint == null) continue;
      final head = midpoint.position;
      final halo = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFB5E4F3).withValues(alpha: .17)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      final silk = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = dark ? 1.8 : 1.6
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.radial(head,
          math.max(16.0, metric.length * .16),
          [
            const Color(0xFFFAE9BF).withValues(alpha: .64),
            const Color(0xFFCAECF3).withValues(alpha: .30),
            Colors.transparent,
          ], [0, .5, 1]);
      canvas.drawPath(segment, halo);
      canvas.drawPath(segment, silk);
    }
  }

  @override
  bool shouldRepaint(covariant _VelaSilkRoutePainter old) =>
      old.phase != phase || old.dark != dark || old.samples != samples ||
      old.from != from ||
      old.camera.longitude != camera.longitude ||
      old.camera.latitude != camera.latitude ||
      old.camera.size != camera.size;
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
    required this.active, required this.connected,
    required this.homebound, required this.dark});
  final VelaWorldCamera camera;
  final Offset from;
  final Offset to;
  final String label;
  final double progress;
  final bool active;
  final bool connected;
  final bool homebound;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (!connected) {
      _marker(canvas, camera.project(VelaWorldCamera.beijing),
        'China', const Color(0xFFE3B777), showLabel: true);
    }
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
    if (connected) {
      _marker(canvas, camera.project(from), '起点',
        const Color(0xFFE3B777), showLabel: true);
      _marker(canvas, camera.projectAlong(from, to), '终点 · $label',
        const Color(0xFF84D0FF), showLabel: true);
    }
    final boat = geoProject(route.pointAt(progress));
    canvas.drawCircle(boat, 25, Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
      ..color = const Color(0x6685D4FF));
    canvas.save();
    canvas.translate(boat.dx - 23, boat.dy - 23);
    const VelaSailPainter().paint(canvas, const Size(46, 46));
    canvas.restore();
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
      old.connected != connected ||
      old.homebound != homebound || old.dark != dark;
}
