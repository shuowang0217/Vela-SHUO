import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../brand/vela_sail_mark.dart';
import '../theme/vela_palettes.dart';
import 'demo_connection.dart';
import 'maritime_route.dart';
import 'ocean_grid.dart';
import 'painted_ocean_route.dart';
import 'vela_oil_scene.dart';

/// Camera for a precisely georeferenced 2:1 equirectangular world map.
@immutable
class VelaWorldCamera {
  const VelaWorldCamera({required this.size, required this.longitude,
    required this.latitude,
    this.portraitWidthScale = portraitHeightScale,
    this.oilIllustration = false, this.focusOil = false});
  final Size size;
  final double longitude;
  final double latitude;
  final double portraitWidthScale;
  // Illustrated Vela oil world is a hand-drawn panorama, not a 2:1
  // geographic raster. Anchor the voyage locally to painted city positions.
  final bool oilIllustration;
  final bool focusOil;
  static const beijing = Offset(116.4, 39.9);

  // The artist-drawn watercolor texture is shifted relative to a strict
  // equirectangular coast map. These small *visual-only* calibration offsets
  // come from comparing Shanghai/Tokyo coastlines with the existing artwork.
  // Keep actual geo coordinates unchanged for route calculations.
  static const double artworkLongitudeCorrection = 12.2;
  static const double artworkLatitudeCorrection = 4.8;

  double get artworkDx =>
      artworkLongitudeCorrection / 360 * worldWidth;
  double get artworkDy =>
      artworkLatitudeCorrection / 180 * worldHeight;

  /// The oil canvas is a stylized panorama, not a map projection.
  /// Calibrated marks in the clean approved 1672x941 painting:
  /// Beijing = (592, 290), Tokyo = (806, 298).
  /// Use the *same* canvas fit and projection for route, labels and ship.
  static const oilImageSize = Size(1672, 941);
  static const oilBeijing = Offset(592, 290);
  static const oilTokyo = Offset(806, 298);



  // Cover both viewport dimensions without the blurred portrait underlay.
  // The original painting retains its aspect ratio on Android and Windows.
  bool get compactOilPortrait => oilIllustration &&
      defaultTargetPlatform == TargetPlatform.android &&
      size.height > size.width * 1.25;

  double get oilImageScale => math.max(
      size.width / oilImageSize.width,
      size.height / oilImageSize.height);
  double get oilTileWidth => oilImageSize.width * oilImageScale;

  // The camera origin is a function of the animated longitude/latitude
  // ONLY. Switching connection state must not swap projection formulas,
  // otherwise the background jumps on the first animation frame.
  Offset get oilImageOrigin {
    final focused = oilCanvasPosition(Offset(longitude, latitude));
    final height = oilImageSize.height * oilImageScale;
    final top = (size.height / 2 - focused.dy * oilImageScale)
        .clamp(size.height - height, 0.0).toDouble();
    return Offset(size.width / 2 - focused.dx * oilImageScale, top);
  }

  // Calibrated against actual painted continents: Europe is at the left,
  // China near the left-center, and North America on the right. Geographic
  // values outside the base world repeat with exactly one image width per
  // 360 degrees, keeping camera motion continuous across the date line.
  static const _oilLongitudeStops = <double>[
    -10, 0, 30, 60, 85, 103, 116.4, 139.69, 170, 180,
    242, 286, 320, 350,
  ];
  static const _oilPixelStops = <double>[
    80, 132, 248, 355, 466, 536, 592, 746, 850, 905,
    1255, 1452, 1600, 1752,
  ];

  Offset oilCanvasPosition(Offset geographicPoint) {
    final longitude = geographicPoint.dx;
    final cycle = ((longitude + 10) / 360).floor();
    final normalized = longitude - cycle * 360;
    var x = _oilPixelStops.last;
    for (var i = 0; i < _oilLongitudeStops.length - 1; i++) {
      if (normalized > _oilLongitudeStops[i + 1]) continue;
      final t = (normalized - _oilLongitudeStops[i]) /
          (_oilLongitudeStops[i + 1] - _oilLongitudeStops[i]);
      x = _oilPixelStops[i] +
          (_oilPixelStops[i + 1] - _oilPixelStops[i]) * t;
      break;
    }
    x += cycle * oilImageSize.width;
    final baseY = 505 - geographicPoint.dy * 5.4;
    // The eastern Asian coast is painted lower than its geographic latitude.
    final localEastAsia = ((longitude - 116.4) / 25).clamp(0.0, 1.0) *
        ((geographicPoint.dy - 17) / 22).clamp(0.0, 1.0) * 30;
    return Offset(x, baseY + localEastAsia);
  }

  Offset projectArtwork(Offset geographicPoint) {
    if (!oilIllustration) {
      return project(geographicPoint) - Offset(artworkDx, artworkDy);
    }
    return wrapOilPoint(oilImageOrigin +
        oilCanvasPosition(geographicPoint) * oilImageScale);
  }

  Offset wrapOilPoint(Offset point) {
    if (!oilIllustration) return point;
    final shift = ((size.width / 2 - point.dx) / oilTileWidth).round();
    return point + Offset(shift * oilTileWidth, 0);
  }

  /// Draw the route exclusively through the painted ocean, on exactly
  /// the same periodic image tiles used by city labels and camera movement.
  /// A failed coastline lookup intentionally produces no track.
  Path paintedRoutePath(Offset from, Offset to, {double until = 1}) {
    final grid = VelaPaintedOceanRoute.instance;
    if (!grid.ready) return Path();
    final coordinates = grid.routePixels(
        oilCanvasPosition(from), oilCanvasPosition(to));
    if (coordinates.length < 2) return Path();
    final path = Path();
    double? lastX;
    var first = true;
    for (final pixel in coordinates) {
      var x = pixel.dx;
      if (lastX != null) {
        x += ((lastX - x) / oilImageSize.width).round() *
            oilImageSize.width;
      }
      lastX = x;
      final screen = oilImageOrigin + Offset(x, pixel.dy) * oilImageScale;
      if (first) {
        path.moveTo(screen.dx, screen.dy);
        first = false;
      } else {
        path.lineTo(screen.dx, screen.dy);
      }
    }
    if (until >= 1) return path;
    final clip = Path();
    for (final metric in path.computeMetrics()) {
      clip.addPath(metric.extractPath(0,
          metric.length * until.clamp(0.0, 1.0)), Offset.zero);
    }
    return clip;
  }

  /// The painted world repeats left and right; traces must repeat as well.
  Path repeatPaintedPath(Path source) {
    if (!oilIllustration) return source;
    final result = Path();
    for (var copy = -2; copy <= 2; copy++) {
      result.addPath(source, Offset(copy * oilTileWidth, 0));
    }
    return result;
  }

  /// Create an unwrapped path projector for one ordered sea voyage.
  /// Individual markers choose the nearest tile; successive route points
  /// must also use neighboring copies so their strokes never jump a whole
  /// map width across the international date line.
  Offset Function(Offset) seaLaneProjector(Offset from, Offset to) {
    Offset? previous;
    return (geo) {
      var point = projectSeaLane(from, to, geo);
      if (oilIllustration && previous != null) {
        final shift = ((previous!.dx - point.dx) / oilTileWidth).round();
        point += Offset(shift * oilTileWidth, 0);
      }
      previous = point;
      return point;
    };
  }

  /// The oil painting is intentionally NOT a geographic projection.
  /// Its coast is stylized; dip the China-to-Tokyo maritime corridor into
  /// the painted sea rather than tracing a geographic line across green land.
  /// The moving sail, line, and shimmer all use this identical transform.
  Offset projectSeaLane(Offset origin, Offset destination, Offset geo) {
    final painted = projectAlongArtwork(origin, geo);
    // The oil painting is an illustration, not a georeferenced atlas.
    // The Europe/Asia voyage must follow an independently calibrated
    // southern-water corridor rather than project a geographic polyline
    // through the illustrated Eurasian mountains.
    final europe = destination.dx >= -12 && destination.dx <= 20 &&
        destination.dy >= 43 && destination.dy <= 62;
    final asia = origin.dx >= 105 && origin.dx <= 150 &&
        origin.dy >= 15 && origin.dy <= 47;
    if (oilIllustration && asia && europe) {
      const sea = <Offset>[
        Offset(120.6, 35.1), Offset(123, 22), Offset(117, 12),
        Offset(103.5, 1.6), Offset(85, 3), Offset(58, 13),
        Offset(43, 13), Offset(33, 28), Offset(31, 32),
        Offset(16, 35.5), Offset(-6, 36), Offset(-4, 48.5),
      ];
      const paintedSea = <Offset>[
        Offset(610, 322), Offset(612, 400), Offset(582, 520),
        Offset(520, 650), Offset(449, 720), Offset(366, 705),
        Offset(321, 666), Offset(289, 625), Offset(266, 550),
        Offset(241, 476), Offset(210, 410), Offset(151, 315),
      ];
      var best = double.infinity;
      var chosen = paintedSea.first;
      for (var i = 0; i < sea.length - 1; i++) {
        final a = sea[i];
        final b = sea[i + 1];
        final delta = b - a;
        final length = delta.distanceSquared;
        final t = length == 0 ? 0.0 :
            (((geo - a).dx * delta.dx + (geo - a).dy * delta.dy) /
                length).clamp(0.0, 1.0).toDouble();
        final at = Offset.lerp(a, b, t)!;
        final distance = (at - geo).distanceSquared;
        if (distance < best) {
          best = distance;
          chosen = Offset.lerp(paintedSea[i], paintedSea[i + 1], t)!;
        }
      }
      return wrapOilPoint(oilImageOrigin + chosen * oilImageScale);
    }
    if (!oilIllustration ||
        origin.dx < 110 || origin.dx > 125 ||
        destination.dx < 135 || destination.dx > 142 ||
        destination.dy < 33 || destination.dy > 38) {
      return painted;
    }
    final t = ((geo.dx - 117.90) / (139.73 - 117.90))
        .clamp(0.0, 1.0);
    // Measured visual off-shore displacement in 1672x941 paint coordinates.
    // Zero at Tokyo Bay, deepest over the Yellow Sea/East China Sea.
    final arc = math.sin(math.pi * t);
    return painted + Offset(
      25 * arc * oilImageScale,
      (26 * (1-t) + 76 * arc) * oilImageScale,
    );
  }

  // One projection, no alternate origin-relative formula. Previously the
  // route painter and city markers disagreed after selecting another node.
  Offset projectAlongArtwork(Offset origin, Offset destination) =>
      projectArtwork(destination);

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
  Offset _routeFrom = VelaMaritimeRoute.homePort;
  Offset _routeTo = VelaMaritimeRoute.homePort;
  VelaDemoNode? _destination;
  VelaPhase? _lastPhase;
  String? _lastNode;
  bool _returning = false;
  bool _homebound = false;
  String _originName = 'BEIJING';

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
    VelaOceanGrid.instance.initialize().then((_) {
      if (mounted) setState(() {});
    });
    VelaPaintedOceanRoute.instance.initialize().then((_) {
      if (mounted) setState(() {});
    });
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
        _routeFrom = VelaMaritimeRoute.homePort;
        _originName = 'BEIJING';
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
          final active = _returning || (
              widget.demo.phase != VelaPhase.idle &&
              widget.demo.phase != VelaPhase.error);
          final camera = VelaWorldCamera(
            size: size,
            longitude: _focusLongitude, latitude: _focusLatitude,
            oilIllustration: VelaThemeRuntime.oilPreview,
            focusOil: active,
            portraitWidthScale: compactAndroid
                ? VelaWorldCamera.androidCompactScale
                : VelaWorldCamera.portraitHeightScale);
          final coverCamera = compactAndroid ? VelaWorldCamera(
            size: size, longitude: _focusLongitude,
            latitude: _focusLatitude) : camera;
          return ClipRect(child: Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: Color(0xFF071929)),
            // Render the USER-APPROVED thick-oil artwork itself.
            // V1.8.5 mistakenly substituted a watercolor global tile then
            // drew fake procedural dashes on top: it could never look like
            // the approved blue/gold impasto composition.
            if (VelaThemeRuntime.oilPreview)
              Positioned.fill(child: IgnorePointer(
                child: Stack(fit: StackFit.expand, children: [
                  _OilMapLayer(camera: camera,
                      asset: 'assets/oil/oil_map_clean.webp'),
                  AnimatedOpacity(
                    opacity: dark ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 850),
                    child: _OilMapLayer(camera: camera,
                        asset: 'assets/oil/oil_map_night.webp')),
                ]))),
            if (!VelaThemeRuntime.oilPreview && compactAndroid)
              ImageFiltered(
                // The oil preview stays sharp on portrait Android.
                imageFilter: ImageFilter.blur(
                  sigmaX: VelaThemeRuntime.oilPreview ? 0 : 16,
                  sigmaY: VelaThemeRuntime.oilPreview ? 0 : 16),
                child: Stack(fit: StackFit.expand, children: [
                  _WorldTiles(camera: coverCamera,
                    asset: const bool.fromEnvironment('VELA_OIL_PREVIEW',
                      defaultValue: true)
                        ? 'assets/oil/oil_atlas_day.webp'
                        : 'assets/world/watercolor_day.webp', show: !dark),
                  _WorldTiles(camera: coverCamera,
                    asset: const bool.fromEnvironment('VELA_OIL_PREVIEW',
                      defaultValue: true)
                        ? 'assets/oil/oil_atlas_night.webp'
                        : 'assets/world/watercolor_night.webp', show: dark),
                ]),
              ),
            if (!VelaThemeRuntime.oilPreview) ShaderMask(
              shaderCallback: (rect) => (compactAndroid &&
                  !VelaThemeRuntime.oilPreview
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
                  asset: const bool.fromEnvironment('VELA_OIL_PREVIEW',
                      defaultValue: true)
                        ? 'assets/oil/oil_atlas_day.webp'
                        : 'assets/world/watercolor_day.webp', show: !dark),
                _WorldTiles(camera: camera,
                  asset: const bool.fromEnvironment('VELA_OIL_PREVIEW',
                      defaultValue: true)
                        ? 'assets/oil/oil_atlas_night.webp'
                        : 'assets/world/watercolor_night.webp', show: dark),
              ]),
            ),
            if (!VelaThemeRuntime.oilPreview)
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
            // Hand-painted moving clouds above the map, below the clear route.
            if (VelaThemeRuntime.oilPreview) ...[
              // Pigment is already in the approved map texture.
              // Only detached alpha clouds float above the painted world.
              const VelaOilScene(),
            ] else
              VelaAtlasWeather(camera: camera, dark: dark,
                connected: widget.demo.phase == VelaPhase.connected),
            CustomPaint(painter: _WorldRoutePainter(
              camera: camera, from: _routeFrom, to: _routeTo,
              label: _destination?.mapLabel ?? 'DESTINATION',
              originLabel: _originName,
              progress: Curves.easeInOutCubic.transform(_sail.value),
              active: active, connected: widget.demo.phase == VelaPhase.connected,
              homebound: _homebound, dark: dark,
            ), child: const SizedBox.expand()),
            VelaRouteSheen(camera: camera, from: _routeFrom, to: _routeTo,
              routingReady: VelaOceanGrid.instance.ready ||
                  VelaPaintedOceanRoute.instance.ready,
              connected: widget.demo.phase == VelaPhase.connected,
              dark: dark),
          ]));
        },
      ));
    });
  }
}





/// Full-viewport oil panorama. The approved artwork is not stretched or
/// blurred: identical horizontal tiles share the camera transform of every
/// city marker, route control point and moving ship. The assets' two edges
/// are feather-matched by scripts/stitch_oil_panorama.py before packaging.
class _OilMapLayer extends StatelessWidget {
  const _OilMapLayer({required this.camera, required this.asset});
  final VelaWorldCamera camera;
  final String asset;

  @override
  Widget build(BuildContext context) {
    final period = camera.oilTileWidth;
    final imageHeight = VelaWorldCamera.oilImageSize.height *
        camera.oilImageScale;
    final baseLeft = ((camera.oilImageOrigin.dx % period) + period) %
        period - period;
    final count = (camera.size.width / period).ceil() + 3;
    return ClipRect(child: Stack(clipBehavior: Clip.hardEdge, children: [
      for (var i = 0; i < count; i++)
        Positioned(
          left: baseLeft + i * period - .25,
          top: camera.oilImageOrigin.dy,
          width: period + .5,
          height: imageHeight,
          child: Image.asset(asset, fit: BoxFit.fill,
            filterQuality: FilterQuality.high, gaplessPlayback: true),
        ),
    ]));
  }
}

class VelaWeatherCadence {
  const VelaWeatherCadence._();
  static const int cloudSeconds = 80; // Full slow outward-and-back drift.
  static const int routeSeconds = 4;
}

@immutable
class VelaCloudSpec {
  const VelaCloudSpec(this.anchor, this.size, this.alpha,
      this.driftX, this.driftY, this.seed);
  final Offset anchor; // Relative to viewport, keeps composition consistent.
  final double size;
  final double alpha;
  final double driftX;
  final double driftY;
  final double seed;
}

/// Entirely Flutter Canvas — no GPU fragment program, image loading or
/// network calls. Animated above the still watercolor texture.
class VelaAtlasWeather extends StatefulWidget {
  const VelaAtlasWeather({super.key, required this.camera,
      required this.dark, this.connected = false});
  final VelaWorldCamera camera;
  final bool dark;
  final bool connected;

  @override
  State<VelaAtlasWeather> createState() => _VelaAtlasWeatherState();
}

class _VelaAtlasWeatherState extends State<VelaAtlasWeather>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion;
  bool _backgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _motion = AnimationController(vsync: this,
      duration: const Duration(seconds: VelaWeatherCadence.cloudSeconds));
  }

  void _syncMotion() {
    final testing = Platform.environment['FLUTTER_TEST'] == 'true';
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (testing || reduced || _backgrounded) {
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
    child: RepaintBoundary(child: AnimatedBuilder(
      animation: _motion,
      builder: (context, _) => CustomPaint(
        painter: VelaAtlasWeatherPainter(
          camera: widget.camera, dark: widget.dark, phase: _motion.value),
        child: const SizedBox.expand(),
      ),
    )),
  );
}

/// Five asymmetric, watercolored cloud banks with deterministic per-cloud
/// opacities, contours and varying left/right drift amplitudes.
/// Dense, irregular hand-painted clouds with visibly solid centers.
/// Unique cloud profiles, broken exterior pigment and brush strokes create
/// authentic watercolor atmosphere without repeated oval stamps.
@immutable
class VelaAtlasWeatherPainter extends CustomPainter {
  const VelaAtlasWeatherPainter({
    required this.camera, required this.dark, required this.phase,
  });
  final VelaWorldCamera camera;
  final bool dark;
  final double phase;

  // The primary body must be legible on both blue and cream map regions.
  // Each cloud has a different width, altitude, opacity and drift phase.
  static const clouds = <VelaCloudSpec>[
    VelaCloudSpec(Offset(.18, .27), 1.06, .96, 91, 14, .00),
    VelaCloudSpec(Offset(.44, .16), .90, .91, 75, 12, .17),
    VelaCloudSpec(Offset(.77, .36), 1.25, .98, 105, 19, .09),
    VelaCloudSpec(Offset(.28, .66), 1.02, .94, 86, 14, .41),
    VelaCloudSpec(Offset(.64, .72), 1.15, .97, 96, 17, .65),
    VelaCloudSpec(Offset(.88, .79), .83, .92, 80, 11, .81),
  ];

  static final List<Path> _bodies =
      List.generate(clouds.length, (i) => _cloudBody(i));
  static final List<Path> _fragments =
      List.generate(clouds.length, (i) => _brokenPigment(i));
  static final List<Path> _brushwork =
      List.generate(clouds.length, (i) => _brushStrokes(i));

  // Picture recording happens only once per theme. Animated frames simply
  // translate cached pictures: no shape generation or blur setup per tick.
  static final List<ui.Picture> _dayArtwork =
      List.generate(clouds.length, (i) => _recordCloud(i, false));
  static final List<ui.Picture> _nightArtwork =
      List.generate(clouds.length, (i) => _recordCloud(i, true));

  static List<Rect> get cloudOutlineBounds =>
      _bodies.map((p) => p.getBounds()).toList(growable: false);

  Offset cloudPosition(int index, Size size) {
    final spec = clouds[index];
    final t = (phase + spec.seed) * math.pi * 2;
    return Offset(
      size.width * spec.anchor.dx + math.sin(t) * spec.driftX,
      size.height * spec.anchor.dy + math.cos(t) * spec.driftY,
    );
  }

  /// Separate seeded cloud contours. Width, height and billowing peaks vary
  /// greatly; thin banks, lumpy cumulus and broken trails look different.
  static Path _cloudBody(int index) {
    const widths = <double>[152, 178, 143, 132, 163, 188];
    const tops = <double>[66, 35, 91, 58, 77, 40];
    const bottoms = <double>[27, 21, 37, 32, 29, 20];
    final rand = math.Random(1807 + index * 131);
    const steps = 22;
    final top = <Offset>[];
    final bottom = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final envelope = math.pow(math.sin(math.pi * t), .54).toDouble();
      final lobe = .60 + .86 * rand.nextDouble();
      final curl = math.sin(t * math.pi * (4.1 + index * .67) +
          index * .81) * 10;
      top.add(Offset((t * 2 - 1) * widths[index],
          11 - envelope * (tops[index] * lobe + curl)));
      final lowerRuffle = (rand.nextDouble() - .5) * 15;
      bottom.add(Offset((t * 2 - 1) * widths[index],
          11 + envelope * (bottoms[index] + lowerRuffle)));
    }
    final path = Path()..moveTo(top.first.dx, top.first.dy);
    for (var i = 1; i < top.length - 1; i++) {
      final next = top[i + 1];
      path.quadraticBezierTo(top[i].dx, top[i].dy,
          (top[i].dx + next.dx) / 2, (top[i].dy + next.dy) / 2);
    }
    path.lineTo(top.last.dx, top.last.dy);
    for (var i = bottom.length - 1; i > 0; i--) {
      final prior = bottom[i - 1];
      path.quadraticBezierTo(bottom[i].dx, bottom[i].dy,
          (bottom[i].dx + prior.dx) / 2,
          (bottom[i].dy + prior.dy) / 2);
    }
    return path..close();
  }

  /// Detached streaks and pigment fragments are deliberately not circles.
  static Path _brokenPigment(int index) {
    final random = math.Random(517 + index * 233);
    final path = Path();
    for (var i = 0; i < 15; i++) {
      final x = (random.nextDouble() * 2 - 1) * (103 + index * 6);
      final y = (random.nextDouble() * 2 - 1) * (33 + index * 3);
      final w = 9 + random.nextDouble() * 31;
      final h = 4 + random.nextDouble() * 13;
      final skew = (random.nextDouble() - .5) * 11;
      path.moveTo(x - w / 2, y);
      path.quadraticBezierTo(x - w * .3, y - h,
          x + skew, y - h * .68);
      path.quadraticBezierTo(x + w * .52, y - h * .36,
          x + w / 2, y + h * .21);
      path.quadraticBezierTo(x + w * .08, y + h,
          x - w / 2, y);
      path.close();
    }
    return path;
  }

  static Path _brushStrokes(int index) {
    final random = math.Random(113 + index * 199);
    final path = Path();
    for (var i = 0; i < 13; i++) {
      final x = (random.nextDouble() * 2 - 1) * 116;
      final y = (random.nextDouble() * 2 - 1) * 26 - 2;
      final length = 12 + random.nextDouble() * 27;
      path.moveTo(x, y);
      path.cubicTo(x + length * .2, y - 7,
          x + length * .7, y + 4, x + length, y - 3);
    }
    return path;
  }

  static ui.Picture _recordCloud(int index, bool dark) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final body = _bodies[index];
    final opacity = clouds[index].alpha;
    final shadow = dark
        ? const Color(0xFF253F58) : const Color(0xFF3C7185);

    canvas.save();
    canvas.translate(6, 10);
    canvas.drawPath(body, Paint()
      ..color = shadow.withValues(alpha: opacity * .66)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9));
    canvas.restore();

    // Uneven translucent fringe surrounds a brighter, nearly solid body.
    canvas.drawPath(_fragments[index], Paint()
      ..color = (dark ? const Color(0xFFB2CADB) :
          const Color(0xFFBCD4D7)).withValues(alpha: opacity * .58)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));

    // No blur on the main fill: that previously washed away the day clouds.
    canvas.drawPath(body, Paint()
      ..shader = ui.Gradient.linear(
        const Offset(-130, -78), const Offset(135, 68), [
          (dark ? const Color(0xFF92B3CC) :
              const Color(0xFFB9D6D9)).withValues(alpha: opacity * .93),
          (dark ? const Color(0xFFE1EEF8) :
              const Color(0xFFFFFCF1)).withValues(alpha: opacity),
          (dark ? const Color(0xFFB1CADB) :
              const Color(0xFFE8F2E9)).withValues(alpha: opacity * .96),
        ], [0, .46, 1],
      ));

    canvas.drawPath(_brushwork[index], Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.7
      ..color = (dark ? const Color(0xFFF1F7FF) :
          const Color(0xFFFFFFFF)).withValues(alpha: opacity * .83)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.1));
    canvas.drawPath(body, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..color = shadow.withValues(alpha: opacity * .15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    return recorder.endRecording();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final factor = (size.width / 1400).clamp(.56, 1.21).toDouble();
    final artworks = dark ? _nightArtwork : _dayArtwork;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var i = 0; i < clouds.length; i++) {
      final center = cloudPosition(i, size);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(clouds[i].size * factor);
      canvas.drawPicture(artworks[i]);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant VelaAtlasWeatherPainter old) =>
      old.phase != phase || old.dark != dark ||
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
    this.routingReady = false,
  });
  final bool routingReady;
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
        ? (widget.camera.oilIllustration
            ? <Offset>[widget.from, widget.to]
            : VelaMaritimeRoute(from: widget.from, to: widget.to).oceanSamples)
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
        oldWidget.routingReady != widget.routingReady ||
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
          camera: widget.camera, from: widget.from, to: widget.to,
          samples: _points, dark: widget.dark, phase: _progress.value),
        child: const SizedBox.expand(),
      ),
    )),
  );
}

class _VelaSilkRoutePainter extends CustomPainter {
  const _VelaSilkRoutePainter({
    required this.camera, required this.from, required this.to,
    required this.samples, required this.dark, required this.phase,
  });
  final VelaWorldCamera camera;
  final Offset from;
  final Offset to;
  final List<Offset> samples;
  final bool dark;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;
    final path = camera.oilIllustration
        ? camera.paintedRoutePath(from, to)
        : VelaMaritimeRoute(from: from, to: samples.last)
            .oceanPath(camera.seaLaneProjector(from, samples.last));
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
      canvas.drawPath(camera.repeatPaintedPath(segment), halo);
      canvas.drawPath(camera.repeatPaintedPath(segment), silk);
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

/// English cartographic hand-lettering, with no bundled font download.
/// Segoe Print is built into Windows; Android's casual typeface is the
/// handwritten platform family. Never fall back to Chinese point labels.
class VelaAtlasInk {
  const VelaAtlasInk._();

  static String englishLabel(String input) {
    final label = input.toUpperCase()
        .replaceAll(RegExp(r'[^A-Z ]'), '').trim();
    return label.isEmpty ? 'DESTINATION' : label;
  }

  static String family(TargetPlatform platform) => switch (platform) {
    TargetPlatform.windows => 'Segoe Print',
    TargetPlatform.android => 'casual',
    TargetPlatform.iOS => 'Noteworthy',
    TargetPlatform.macOS => 'Chalkduster',
    TargetPlatform.linux => 'URW Chancery L',
    TargetPlatform.fuchsia => 'casual',
  };

  static TextStyle labelStyle({required bool dark, bool compact = false,
      bool mainLabel = false}) => TextStyle(
    fontFamily: family(defaultTargetPlatform),
    fontFamilyFallback: const ['Segoe Print', 'casual', 'Chalkduster'],
    fontSize: compact ? 16 : (mainLabel ? 23 : 20),
    height: 1.0,
    letterSpacing: .45,
    fontWeight: FontWeight.w600,
    color: dark ? const Color(0xFFFFF1D6) : const Color(0xFF243D49),
    shadows: [
      Shadow(color: dark ? const Color(0xDF081A2B)
          : const Color(0xEEFFFFF8), blurRadius: 8),
    ],
  );

  static Offset position(Size viewport, Offset marker, Size labelSize,
      {bool above = false, bool toLeft = false}) {
    final dx = toLeft ? marker.dx - labelSize.width - 19
        : marker.dx + (above ? 25 : 17);
    final dy = marker.dy - (above ? 57 : 33);
    return Offset(
      dx.clamp(3.0, math.max(3.0, viewport.width - labelSize.width - 4)),
      dy.clamp(3.0, math.max(3.0, viewport.height - labelSize.height - 4)),
    );
  }
}

class _WorldRoutePainter extends CustomPainter {
  const _WorldRoutePainter({required this.camera, required this.from,
    required this.to, required this.label, required this.originLabel,
    required this.progress, required this.active, required this.connected,
    required this.homebound, required this.dark});
  final VelaWorldCamera camera;
  final Offset from;
  final Offset to;
  final String label;
  final String originLabel;
  final double progress;
  final bool active;
  final bool connected;
  final bool homebound;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (!connected) {
      _marker(canvas, camera.projectArtwork(VelaWorldCamera.beijing),
        'CHINA', const Color(0xFFE3B777), showLabel: true);
    }
    if (!active || (from - to).distance < .01) return;
    final route = VelaMaritimeRoute(from: from, to: to);
    final routePath = camera.oilIllustration
        ? camera.paintedRoutePath(from, to)
        : route.oceanPath(camera.seaLaneProjector(from, to));
    final traveled = camera.oilIllustration
        ? camera.paintedRoutePath(from, to, until: progress)
        : route.oceanPath(
            camera.seaLaneProjector(from, to), until: progress);
    final visibleRoute = camera.repeatPaintedPath(routePath);
    final visibleTravel = camera.repeatPaintedPath(traveled);
    // Hand-painted nautical chart line: warm gold below, pale silk highlights.
    // Every moving shimmer and the sail use this exact same curved path.
    canvas.drawPath(visibleRoute, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.3
      ..strokeCap = StrokeCap.round
      ..color = (dark ? const Color(0xFFC39C68) :
          const Color(0xFF8D5F32)).withValues(alpha: .78));
    canvas.drawPath(visibleRoute, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFF9DFAD).withValues(alpha: .88));
    canvas.drawPath(visibleTravel, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..color = const Color(0xFFB9D6EB).withValues(alpha: .30));
    canvas.drawPath(visibleTravel, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFEFC78A));
    final metrics = routePath.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    if (connected) {
      // City pins belong on the painted city, not on offshore lane
      // waypoints. The route itself remains a separate sea-only corridor.
      final homePin = camera.projectArtwork(from);
      final cityPin = camera.projectArtwork(to);
      _marker(canvas, homePin, VelaAtlasInk.englishLabel(originLabel),
        const Color(0xFFE3B777), showLabel: true,
        toLeft: (cityPin - homePin).distance < 170);
      _marker(canvas, cityPin, VelaAtlasInk.englishLabel(label),
        const Color(0xFF84D0FF), showLabel: true, above: true);
    }
    final tangent = metric.getTangentForOffset(
      metric.length * progress.clamp(0.0, 1.0));
    if (tangent == null) return;
    final boat = camera.oilIllustration
        ? camera.wrapOilPoint(tangent.position) : tangent.position;
    // Compact carved-ink silhouette; the previous 25 px blurred blue halo
    // made the middle of the painted coastline look out of focus.
    canvas.drawOval(Rect.fromCenter(center: boat + const Offset(0, 14),
      width: 45, height: 9), Paint()
      ..color = const Color(0xFF0C2B48).withValues(alpha: .25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.save();
    canvas.translate(boat.dx - 22, boat.dy - 22);
    const VelaSailPainter().paint(canvas, const Size(44, 44));
    canvas.restore();
  }

  void _marker(Canvas canvas, Offset position, String label, Color color,
      {required bool showLabel, bool above = false, bool toLeft = false}) {
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
      text: TextSpan(
        text: VelaAtlasInk.englishLabel(label),
        style: VelaAtlasInk.labelStyle(
          dark: dark, compact: camera.size.width < 540,
          mainLabel: label == 'CHINA'),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, VelaAtlasInk.position(camera.size, position,
        painter.size, above: above, toLeft: toLeft));
  }

  @override
  bool shouldRepaint(covariant _WorldRoutePainter old) =>
      old.camera.longitude != camera.longitude ||
      old.camera.latitude != camera.latitude ||
      old.camera.size != camera.size || old.from != from ||
      old.to != to || old.label != label ||
      old.originLabel != originLabel ||
      old.progress != progress || old.active != active ||
      old.connected != connected ||
      old.homebound != homebound || old.dark != dark;
}
