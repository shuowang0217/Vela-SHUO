import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/vela_palettes.dart';

/// One material for every Vela screen: translucent watercolor paper and an
/// imperfect pen line. Palette selection only changes the tint/ink colors.
class VelaWatercolorSurface extends StatelessWidget {
  const VelaWatercolorSurface({super.key, required this.child,
    this.padding = const EdgeInsets.all(16), this.radius = 19,
    this.selected = false, this.hovered = false});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool selected;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final t = VelaThemeRuntime.active;
    final wash = Color.lerp(t.surface, t.accentSoft, t.dark ? .10 : .075)!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
        child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          // Android floats on a genuine 50%-opaque watercolor wash;
          // Windows preserves its already approved desktop material.
          colors: defaultTargetPlatform == TargetPlatform.android
              ? [
                  t.surface.withValues(alpha: .50),
                  wash.withValues(alpha: .50),
                  t.surface.withValues(alpha: .50),
                ]
              : [
                  t.surface.withValues(alpha: t.dark ? .82 : .88),
                  wash.withValues(alpha: t.dark ? .69 : .78),
                  t.surface.withValues(alpha: t.dark ? .79 : .84),
                ],
          stops: const [0, .58, 1],
        ),
        border: Border.all(color: selected || hovered
            ? t.accent.withValues(alpha: .78)
            : t.line.withValues(alpha: t.dark ? .96 : .92),
          width: selected ? 1.7 : 1.25),
        boxShadow: [BoxShadow(
          color: const Color(0xFF18384B).withValues(
            alpha: t.dark ? .20 : .095),
          blurRadius: hovered ? 19 : 10,
          offset: const Offset(0, 4),
        )],
      ),
      child: CustomPaint(
        painter: _VelaInkStroke(
          t.dark ? t.accentSoft : t.text, radius),
        child: Padding(padding: padding, child: child),
      ),
        ),
      ),
    );
  }
}

class _VelaInkStroke extends CustomPainter {
  const _VelaInkStroke(this.ink, this.radius);
  final Color ink;
  final double radius;

  @override
  void paint(Canvas c, Size size) {
    if (size.width < 28 || size.height < 28) return;
    final p = Paint()
      ..color = ink.withValues(alpha: .13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .75
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(radius + 5, 3.8)
      ..quadraticBezierTo(size.width * .42, 3.1,
          size.width - radius - 5, 4.3);
    c.drawPath(path, p);
    c.drawLine(Offset(14, size.height - 4.3),
        Offset(math.min(size.width - 16, size.width * .4),
            size.height - 3.7), p);
  }
  @override
  bool shouldRepaint(covariant _VelaInkStroke old) =>
    old.ink != ink || old.radius != radius;
}

/// v1.8.9: all legacy oil-plaque roles use the original v1.6 glass.
enum VelaOilReliefShape { connection, speed, medallion, book, compass, helm, power }
class VelaOilReliefSurface extends StatelessWidget {
  const VelaOilReliefSurface({super.key, required this.child,
    required this.shape, this.padding = EdgeInsets.zero,
    this.selected = false, this.radius = 19});
  final Widget child;
  final VelaOilReliefShape shape;
  final EdgeInsetsGeometry padding;
  final bool selected;
  final double radius;

  @override
  Widget build(BuildContext context) => VelaWatercolorSurface(
    selected: selected, radius: radius, padding: padding, child: child);
}

/// Distinct nautical ink silhouettes, not generic Material icon shapes.
enum VelaVoyageSymbol { globe, logbook, compass, helm }

class VelaVoyageGlyph extends StatelessWidget {
  const VelaVoyageGlyph({super.key, required this.symbol,
    this.size = 23, this.active = false});
  final VelaVoyageSymbol symbol;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = VelaThemeRuntime.active;
    return SizedBox(width: size, height: size,
      child: CustomPaint(painter: _VoyageGlyphPainter(
        symbol, active ? t.accent : t.text, t.accentSoft)));
  }
}

class _VoyageGlyphPainter extends CustomPainter {
  const _VoyageGlyphPainter(this.symbol, this.ink, this.wash);
  final VelaVoyageSymbol symbol;
  final Color ink, wash;
  @override
  void paint(Canvas c, Size s) {
    c.save();
    c.scale(s.width / 32, s.height / 32);
    final p = Paint()
      ..color = ink
      ..strokeWidth = 2.05
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final faint = Paint()
      ..color = wash.withValues(alpha: .38)
      ..style = PaintingStyle.fill;
    switch (symbol) {
      case VelaVoyageSymbol.globe:
        c.drawCircle(const Offset(16, 16), 11, faint);
        c.drawCircle(const Offset(16, 16), 11, p);
        c.drawOval(const Rect.fromLTRB(11, 5, 21, 27), p);
        c.drawLine(const Offset(5, 16), const Offset(27, 16), p);
        c.drawArc(const Rect.fromLTRB(7, 9, 25, 23),
            .08, math.pi - .16, false, p);
        break;
      case VelaVoyageSymbol.logbook:
        c.drawPath(Path()..moveTo(5, 7)
          ..quadraticBezierTo(10, 4, 16, 8)
          ..quadraticBezierTo(22, 5, 27, 7)
          ..lineTo(27, 25)
          ..quadraticBezierTo(21, 23, 16, 27)
          ..quadraticBezierTo(10, 23, 5, 25)..close(), p);
        c.drawLine(const Offset(16, 8), const Offset(16, 26), p);
        c.drawLine(const Offset(8, 12), const Offset(13, 13), p);
        c.drawLine(const Offset(19, 13), const Offset(24, 12), p);
        break;
      case VelaVoyageSymbol.compass:
        c.drawCircle(const Offset(16, 16), 11, p);
        c.drawCircle(const Offset(16, 16), 8, p);
        c.drawPath(Path()..moveTo(21, 10)..lineTo(14, 14)
          ..lineTo(10, 22)..lineTo(18, 18)..close(),
          Paint()..color = wash.withValues(alpha: .7));
        c.drawPath(Path()..moveTo(21, 10)..lineTo(14, 14)
          ..lineTo(10, 22)..lineTo(18, 18)..close(), p);
        c.drawCircle(const Offset(16, 16), 1.4, p);
        break;
      case VelaVoyageSymbol.helm:
        c.drawCircle(const Offset(16, 16), 8, p);
        c.drawCircle(const Offset(16, 16), 3, p);
        for (var n = 0; n < 8; n++) {
          final a = n * math.pi / 4;
          final vx = math.cos(a), vy = math.sin(a);
          c.drawLine(Offset(16 + 3 * vx, 16 + 3 * vy),
              Offset(16 + 13 * vx, 16 + 13 * vy), p);
        }
        break;
    }
    // A few raised ivory/gold brush ridges keep the icon readable on glass
    // while giving its contours the same hand-painted texture as the map.
    final ridge = Paint()
      ..color = wash.withValues(alpha: .82)
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    c.drawPath(Path()..moveTo(6, 7)..quadraticBezierTo(9, 4, 12, 6), ridge);
    c.drawPath(Path()..moveTo(22, 25)..quadraticBezierTo(24, 23, 26, 19), ridge);
    final flecks = Paint()
      ..color = ink.withValues(alpha: .55)
      ..style = PaintingStyle.fill;
    for (var i = 0; i < 7; i++) {
      final x = 7.0 + (i * 17 % 19).toDouble();
      final y = 5.0 + (i * 11 % 23).toDouble();
      c.drawOval(Rect.fromCenter(
        center: Offset(x,y), width: i.isEven ? 1.8 : 1.1,
        height: 0.8), flecks);
    }
    c.restore();
  }
  @override
  bool shouldRepaint(covariant _VoyageGlyphPainter old) =>
    old.ink != ink || old.wash != wash || old.symbol != symbol;
}
