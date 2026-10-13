import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Coordinates are illustrative coastal waypoints inferred from node names.
/// Never represent them as an IP-geolocation or verified server location.
@immutable
class VelaVoyageTarget {
  const VelaVoyageTarget(this.label, this.longitude, this.latitude);
  final String label;
  final double longitude;
  final double latitude;

  static VelaVoyageTarget? fromNodeName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final value = name.toLowerCase();
    const destinations = <(List<String>, VelaVoyageTarget)>[
      (['🇯🇵', '日本', '东京', '大阪', 'japan', 'tokyo', 'osaka', 'jp-'],
       VelaVoyageTarget('日本近海', 139.9, 35.3)),
      (['🇭🇰', '香港', 'hong kong', 'hk-'],
       VelaVoyageTarget('香港水域', 114.3, 22.2)),
      (['🇸🇬', '新加坡', '狮城', 'singapore', 'sg-'],
       VelaVoyageTarget('新加坡海峡', 103.9, 1.2)),
      (['🇹🇼', '台湾', '台北', 'taiwan', 'tw-'],
       VelaVoyageTarget('台湾海峡', 121.5, 24.7)),
      (['🇰🇷', '韩国', '首尔', '釜山', 'korea', 'seoul', 'kr-'],
       VelaVoyageTarget('韩国近海', 129.2, 35.1)),
      (['🇺🇸', '美国', '洛杉矶', '纽约', 'united states', 'usa', 'us-'],
       VelaVoyageTarget('美国近海', -118.6, 33.5)),
      (['🇨🇦', '加拿大', '温哥华', 'canada', 'vancouver', 'ca-'],
       VelaVoyageTarget('加拿大近海', -123.4, 49.1)),
      (['🇬🇧', '英国', '伦敦', 'united kingdom', 'london', 'uk-'],
       VelaVoyageTarget('英国近海', 1.3, 51.7)),
      (['🇩🇪', '德国', '法兰克福', 'germany', 'frankfurt', 'de-'],
       VelaVoyageTarget('德国近海', 8.3, 53.6)),
      (['🇫🇷', '法国', '巴黎', 'france', 'paris', 'fr-'],
       VelaVoyageTarget('法国近海', 2.1, 50.9)),
      (['🇳🇱', '荷兰', 'amsterdam', 'netherlands', 'nl-'],
       VelaVoyageTarget('荷兰近海', 4.6, 52.5)),
      (['🇦🇺', '澳大利亚', '悉尼', 'australia', 'sydney', 'au-'],
       VelaVoyageTarget('澳大利亚近海', 151.3, -34.0)),
      (['🇹🇭', '泰国', '曼谷', 'thailand', 'bangkok', 'th-'],
       VelaVoyageTarget('泰国近海', 100.5, 13.0)),
      (['🇲🇾', '马来西亚', '吉隆坡', 'malaysia', 'kuala lumpur', 'my-'],
       VelaVoyageTarget('马来西亚近海', 101.5, 2.9)),
      (['🇻🇳', '越南', '河内', 'vietnam', 'hanoi', 'vn-'],
       VelaVoyageTarget('越南近海', 107.0, 20.6)),
    ];
    for (final (markers, target) in destinations) {
      if (markers.any(value.contains)) return target;
    }
    return null;
  }
}

class _VoyageAssets {
  const _VoyageAssets(this.coastlines, this.night);
  final List<List<Offset>> coastlines;
  final ui.Image night;
}

/// A full-bleed geographically projected sea chart. The map is an asset,
/// never a remote website, and the sailing animation never touches the proxy.
class VelaVoyageMap extends StatefulWidget {
  const VelaVoyageMap({
    super.key,
    required this.connected,
    required this.nodeName,
  });

  final bool connected;
  final String? nodeName;

  @override
  State<VelaVoyageMap> createState() => _VelaVoyageMapState();
}

class _VelaVoyageMapState extends State<VelaVoyageMap>
    with SingleTickerProviderStateMixin {
  static Future<_VoyageAssets>? _assetFuture;
  late final AnimationController _voyage;
  String? _lastNode;

  static Future<_VoyageAssets> _load() async {
    final results = await Future.wait([
      rootBundle.loadString('assets/maps/world_110m.json'),
      rootBundle.load('assets/earth/earth_night_lights.png'),
    ]);
    final decoded = jsonDecode(results[0] as String) as List<dynamic>;
    final coast = <List<Offset>>[
      for (final raw in decoded)
        [
          for (final point in raw as List<dynamic>)
            Offset(((point as List<dynamic>)[0] as num).toDouble(),
                (point[1] as num).toDouble()),
        ],
    ];
    final bytes = results[1] as ByteData;
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    try {
      final frame = await codec.getNextFrame();
      return _VoyageAssets(coast, frame.image);
    } finally {
      codec.dispose();
    }
  }

  @override
  void initState() {
    super.initState();
    _assetFuture ??= _load();
    _voyage = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3100),
      reverseDuration: const Duration(milliseconds: 1800),
    );
    _lastNode = widget.nodeName;
    if (widget.connected) _voyage.forward();
  }

  @override
  void didUpdateWidget(covariant VelaVoyageMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.nodeName != _lastNode) {
      _lastNode = widget.nodeName;
      if (widget.connected) _voyage.forward(from: 0);
    } else if (widget.connected != oldWidget.connected) {
      if (widget.connected) {
        _voyage.forward();
      } else {
        _voyage.reverse();
      }
    }
  }

  @override
  void dispose() {
    _voyage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_VoyageAssets>(
    future: _assetFuture,
    builder: (context, snapshot) => RepaintBoundary(
      child: AnimatedBuilder(
        animation: _voyage,
        builder: (context, _) => CustomPaint(
          painter: _VoyagePainter(
            assets: snapshot.data,
            target: VelaVoyageTarget.fromNodeName(widget.nodeName),
            connected: widget.connected,
            progress: Curves.easeInOutCubic.transform(_voyage.value),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

class _VoyagePainter extends CustomPainter {
  const _VoyagePainter({
    required this.assets,
    required this.target,
    required this.connected,
    required this.progress,
  });
  final _VoyageAssets? assets;
  final VelaVoyageTarget? target;
  final bool connected;
  final double progress;

  static const start = Offset(122.5, 30.3); // China coast, offshore.
  static const cyan = Color(0xFF4AF2F0);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF092B4D), Color(0xFF030C1B)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ).createShader(Offset.zero & size));

    // Expand longitude for cross-Pacific and Europe routes without falsifying
    // the named country. The viewport contains both waypoints.
    var targetLon = target?.longitude ?? 139.9;
    if (targetLon - start.dx < -180) targetLon += 360;
    if (targetLon - start.dx > 180) targetLon -= 360;
    final left = math.min(96.0, math.min(start.dx, targetLon) - 13);
    final right = math.max(158.0, math.max(start.dx, targetLon) + 13);
    final bottom = math.min(4.0, (target?.latitude ?? 35) - 12);
    final top = math.max(53.0, (target?.latitude ?? 35) + 12);
    Offset project(double longitude, double latitude) => Offset(
      (longitude - left) * size.width / (right - left),
      (top - latitude) * size.height / (top - bottom),
    );
    final earth = assets;
    if (earth != null) {
      final image = earth.night;
      // Equirectangular texture, duplicated across the antimeridian.
      for (var turn = -1; turn <= 2; turn++) {
        final west = math.max(left, -180.0 + turn * 360);
        final east = math.min(right, 180.0 + turn * 360);
        if (east <= west) continue;
        final westSource = west - turn * 360;
        final eastSource = east - turn * 360;
        final src = Rect.fromLTRB(
          (westSource + 180) * image.width / 360,
          (90 - top) * image.height / 180,
          (eastSource + 180) * image.width / 360,
          (90 - bottom) * image.height / 180,
        );
        final dst = Rect.fromPoints(project(west, top), project(east, bottom));
        canvas.drawImageRect(image, src, dst,
          Paint()..filterQuality = FilterQuality.medium
              ..color = Colors.white.withValues(alpha: .76));
      }

      // A sharp coastal tracing, grounded in local bundled Natural Earth data.
      final coast = Paint()..color = const Color(0xFF46C7F3)
        .withValues(alpha: .72)
        ..style = PaintingStyle.stroke..strokeWidth = 1.2
        ..isAntiAlias = true;
      for (final ring in earth.coastlines) {
        if (ring.length < 2) continue;
        final path = Path();
        var started = false;
        Offset? previous;
        for (final vertex in ring) {
          var lon = vertex.dx;
          while (lon < left - 180) {
            lon += 360;
          }
          while (lon > right + 180) {
            lon -= 360;
          }
          final position = project(lon, vertex.dy);
          // Avoid drawing a false chord across the international date line.
          if (previous == null || (position.dx - previous.dx).abs() >
              size.width * .50) {
            path.moveTo(position.dx, position.dy);
          } else {
            path.lineTo(position.dx, position.dy);
          }
          previous = position;
          started = true;
        }
        if (started) canvas.drawPath(path, coast);
      }
    }

    // Overlay sea contour guides. They are decorative, not boundaries.
    final contour = Paint()
      ..color = const Color(0xFF57C6EA).withValues(alpha: .13)
      ..style = PaintingStyle.stroke..strokeWidth = 1;
    for (var i = 0; i < 17; i++) {
      final y = size.height * (.20 + i * .055);
      final wave = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += 18) {
        wave.lineTo(x, y + math.sin(x * .008 + i * .75) * 13);
      }
      canvas.drawPath(wave, contour);
    }

    // The departing boat is near China until a real connection starts.
    final departure = project(start.dx, start.dy);
    final destination = target == null
        ? departure : project(targetLon, target!.latitude);
    final delta = destination - departure;
    var normal = delta.distance < 1 ? const Offset(0, -1) :
      Offset(delta.dy, -delta.dx) / delta.distance;
    if (normal.dy > 0) normal = -normal;
    final control = Offset.lerp(departure, destination, .5)! +
        normal * math.min(size.height * .24, delta.distance * .28);
    Offset pointAt(double t) {
      final s = 1 - t;
      return departure * (s * s) + control * (2 * s * t) +
          destination * (t * t);
    }
    final hasRoute = target != null && progress > .0001;
    if (hasRoute) {
      final glowing = Paint()..strokeWidth = 7
        ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round
        ..color = cyan.withValues(alpha: .20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
      final light = Paint()..strokeWidth = 2.5
        ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round
        ..color = cyan.withValues(alpha: .9);
      final path = Path()..moveTo(departure.dx, departure.dy);
      for (var i = 1; i <= 80; i++) {
        final t = progress * i / 80;
        final p = pointAt(t);
        if (i % 3 != 0 || i % 12 == 0) {
          path.lineTo(p.dx, p.dy);
        } else {
          path.moveTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, glowing);
      canvas.drawPath(path, light);
      if (progress > .96) {
        _beacon(canvas, destination, cyan);
      }
    }

    _beacon(canvas, departure, const Color(0xFF54A9F3));
    final boatAt = hasRoute ? pointAt(progress) : departure;
    final next = pointAt(math.min(1, progress + .012));
    final prev = pointAt(math.max(0, progress - .012));
    final heading = hasRoute
        ? math.atan2(next.dy - prev.dy, next.dx - prev.dx)
        : -.85;
    _sailboat(canvas, boatAt, heading, math.max(0.70,
        math.min(size.width / 960, size.height / 600)));

    final labelStyle = const TextStyle(
      color: Color(0xFFB8E5FF), fontSize: 14,
      fontWeight: FontWeight.w500, letterSpacing: 1.3);
    _label(canvas, '中国沿海', departure + const Offset(-82, 26), labelStyle);
    if (target != null && (connected || progress > 0)) {
      _label(canvas, target!.label,
        destination + const Offset(12, -26), labelStyle);
    }
    _label(canvas, 'E A S T  A S I A  ·  海洋航图',
      Offset(size.width * .05, size.height - 43),
      const TextStyle(color: Color(0xFF89B7D6), fontSize: 10,
        letterSpacing: 1.8));
    canvas.restore();
  }

  void _label(Canvas canvas, String label, Offset origin, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr, maxLines: 1,
    )..layout();
    painter.paint(canvas, origin);
  }

  void _beacon(Canvas canvas, Offset center, Color color) {
    canvas.drawCircle(center, 18, Paint()
      ..color = color.withValues(alpha: .11)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11));
    canvas.drawCircle(center, 8, Paint()..color = color.withValues(alpha: .12));
    canvas.drawCircle(center, 4, Paint()..color = color);
    canvas.drawCircle(center, 12, Paint()..color = color.withValues(alpha: .6)
      ..strokeWidth = 1..style = PaintingStyle.stroke);
  }

  void _sailboat(Canvas canvas, Offset pos, double direction, double scale) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(direction + math.pi / 2);
    canvas.scale(scale);
    final glow = Paint()..color = cyan.withValues(alpha: .24)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13);
    canvas.drawOval(const Rect.fromLTWH(-17, -34, 34, 70), glow);
    final hull = Path()
      ..moveTo(-14, 19)..quadraticBezierTo(0, 33, 14, 19)
      ..lineTo(8, -16)..quadraticBezierTo(0, -25, -8, -16)..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFFDFEFFF));
    canvas.drawLine(const Offset(0, 17), const Offset(0, -32),
      Paint()..color = const Color(0xFFDCF5FF)
        ..strokeWidth = 2.6..strokeCap = StrokeCap.round);
    canvas.drawPath(Path()
      ..moveTo(2, -30)..lineTo(17, 12)
      ..quadraticBezierTo(7, 15, 2, 12)..close(),
      Paint()..color = const Color(0xFFB6EDFF));
    canvas.drawPath(Path()
      ..moveTo(-3, -24)..lineTo(-3, 12)
      ..quadraticBezierTo(-12, 15, -16, 12)..close(),
      Paint()..color = const Color(0xFF55C2EA));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VoyagePainter old) =>
      old.assets != assets || old.target != target ||
      old.progress != progress || old.connected != connected;
}
