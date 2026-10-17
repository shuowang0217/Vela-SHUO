import 'dart:math' as math;
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
    final oil = VelaThemeRuntime.oilPreview;
    final wash = Color.lerp(t.surface, t.accentSoft,
        oil ? .16 : (t.dark ? .10 : .075))!;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          // Android floats on a genuine 50%-opaque watercolor wash;
          // Windows preserves its already approved desktop material.
          colors: oil ? [
                  t.raised.withValues(alpha:.96),
                  wash.withValues(alpha:.97),
                  t.surface.withValues(alpha:.98),
                ] : defaultTargetPlatform == TargetPlatform.android
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
            : t.line.withValues(alpha: oil ? .75 : (t.dark ? .86 : .78)),
          width: selected ? 1.7 : (oil ? 1.3 : 1.05)),
        boxShadow: [BoxShadow(
          color: (oil ? const Color(0xFF513B22) : const Color(0xFF18384B))
              .withValues(alpha: oil ? .23 : (t.dark ? .20 : .095)),
          blurRadius: hovered ? 20 : (oil ? 15 : 10),
          offset: const Offset(0, 5),
        )],
      ),
      child: CustomPaint(
        painter: _VelaInkStroke(
          t.dark ? t.accentSoft : t.text, t.accent, t.line, radius, oil),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _VelaInkStroke extends CustomPainter {
  const _VelaInkStroke(
    this.ink, this.pigment, this.edge, this.radius, this.oil);
  final Color ink;
  final Color pigment;
  final Color edge;
  final double radius;
  final bool oil;

  @override
  void paint(Canvas c, Size size) {
    if (size.width < 28 || size.height < 28) return;
    c.save();
    c.clipRRect(RRect.fromRectAndRadius(
      Offset.zero & size, Radius.circular(radius)));
    final p = Paint()
      ..color = ink.withValues(alpha: .15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .85
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(radius + 5, 3.8)
      ..quadraticBezierTo(size.width * .42, 3.1,
          size.width - radius - 5, 4.3);
    c.drawPath(path, p);
    c.drawLine(Offset(14, size.height - 4.3),
        Offset(math.min(size.width - 16, size.width * .4),
            size.height - 3.7), p);

    if (oil) {
      // Deterministic little impasto strokes, far denser and more tactile
      // than the former near-invisible crosshatch. Shared by every screen.
      final bristle = Paint()
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (var y = 6.0; y < size.height - 3; y += 13) {
        for (var x = 7.0; x < size.width - 4; x += 19) {
          final salt = ((x.toInt() * 37 ^ y.toInt() * 43) & 63) / 63.0;
          final dx = 5.0 + salt * 10.0;
          bristle.color = (salt < .50 ? pigment : ink)
              .withValues(alpha: .14 + salt * .13);
          bristle.strokeWidth = 1.6 + salt * 2.2;
          c.drawLine(Offset(x + salt * 4, y + 1),
              Offset(x + dx, y - 1.8 + salt * 3.8), bristle);
          if (salt > .70) {
            bristle.color = edge.withValues(alpha: .24);
            bristle.strokeWidth = .9 + salt;
            c.drawLine(Offset(x + 1, y + 4),
              Offset(x + dx * .7, y + 3), bristle);
          }
        }
      }
      final rim = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..color = edge.withValues(alpha: .62)
        ..strokeWidth = 1.7;
      c.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 2, size.width - 4, size.height - 4),
        Radius.circular(math.max(0, radius - 2))), rim);
      final highlight = Paint()
        ..color = pigment.withValues(alpha: .47)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2;
      c.drawArc(
        Rect.fromLTWH(7, 7, math.max(1, size.width - 14),
          math.max(1, size.height - 14)),
        math.pi * .96, math.pi * .22, false, highlight);
    }
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _VelaInkStroke old) =>
      old.ink != ink || old.pigment != pigment || old.edge != edge ||
      old.radius != radius || old.oil != oil;
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
      ..strokeWidth = 1.65
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
    c.restore();
  }
  @override
  bool shouldRepaint(covariant _VoyageGlyphPainter old) =>
    old.ink != ink || old.wash != wash || old.symbol != symbol;
}
