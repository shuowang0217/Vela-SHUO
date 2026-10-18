import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/vela_palettes.dart';

/// Real painterly plaques cut from the same impasto material as Vela's map.
/// Raster assets carry irregular paint edges; content remains real Flutter UI.
enum VelaOilReliefShape { connection, speed, medallion, power }

class VelaOilReliefSurface extends StatelessWidget {
  const VelaOilReliefSurface({
    super.key, required this.child, required this.shape,
    this.padding = EdgeInsets.zero, this.selected = false,
    this.radius = 22,
  });
  final Widget child;
  final VelaOilReliefShape shape;
  final EdgeInsetsGeometry padding;
  final bool selected;
  final double radius;

  String get _file => switch (shape) {
    VelaOilReliefShape.connection =>
      'assets/oil/ui/connection_plaque.png',
    VelaOilReliefShape.speed => 'assets/oil/ui/speed_plaque.png',
    VelaOilReliefShape.medallion =>
      'assets/oil/ui/paint_medallion.png',
    VelaOilReliefShape.power => 'assets/oil/ui/power_medallion.png',
  };

  @override
  Widget build(BuildContext context) {
    if (!VelaThemeRuntime.oilPreview) {
      return VelaWatercolorSurface(
        selected: selected, padding: padding,
        radius: radius, child: child,
      );
    }
    final tone = VelaThemeRuntime.active;
    final asset = tone.dark ? _file.replaceFirst('/ui/', '/ui/night_') : _file;
    // The image is NOT a screenshot of the UI: it contains no fixed text,
    // routes, or buttons. All status, speeds and actions stay interactive.
    return Stack(fit: StackFit.passthrough, children: [
      Positioned.fill(child: IgnorePointer(
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(
            Color.lerp(Colors.white,
              tone.dark ? tone.accentSoft : tone.surface,
              tone.dark ? .29 : .21)!,
            BlendMode.modulate),
          child: Image.asset(asset, fit: BoxFit.fill,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true),
        ),
      )),
      Padding(padding: padding, child: child),
      if (selected)
        Positioned.fill(child: IgnorePointer(child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
                shape == VelaOilReliefShape.medallion ? 50 : 22),
            border: Border.all(
                color: tone.accent.withValues(alpha: .42), width: 1.8),
          ),
        ))),
    ]);
  }
}

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
        // Reuse the ACTUAL approved impasto map painting as an image material:
        // this is no longer a flat glass card with decorative lines.
        image: oil ? DecorationImage(
          image: AssetImage(t.dark
              ? 'assets/oil/ui/oil_canvas_night.webp'
              : 'assets/oil/ui/oil_canvas.webp'),
          fit: BoxFit.cover,
          alignment: Alignment.center,
          opacity: .91,
          colorFilter: ColorFilter.mode(
            Color.lerp(Colors.white, t.surface, t.dark ? .13 : .18)!,
            BlendMode.modulate),
        ) : null,
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
        // Oil cards display actual paint IMAGE only; no hatch strokes.
        painter: oil ? null : _VelaInkStroke(
          t.dark ? t.accentSoft : t.text, t.accent, t.line, radius, oil),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _VelaInkStroke extends CustomPainter {
  const _VelaInkStroke(
    this.ink, this.pigment, this.edge, this.radius, this.oil);
  final Color ink, pigment, edge;
  final double radius;
  final bool oil;

  @override
  void paint(Canvas c, Size size) {
    if (size.width < 28 || size.height < 28) return;
    c.save();
    c.clipRRect(RRect.fromRectAndRadius(
      Offset.zero & size, Radius.circular(radius)));

    if (oil) {
      // Broad palette-coloured PAINT DABS over the real reference image.
      // Organic patches and ridges replace the previous uniform line grid.
      final impasto = Paint()..style = PaintingStyle.fill;
      for (var y = -5.0; y < size.height + 15; y += 23) {
        for (var x = -7.0; x < size.width + 18; x += 34) {
          final n = ((x.toInt() * 41 ^ y.toInt() * 71) & 127) / 127;
          final dx = 11.0 + n * 26;
          final dy = 4.0 + n * 6;
          impasto.color = Color.lerp(
            n < .45 ? pigment : edge, pigment,
            .25 + n * .32)!.withValues(alpha: .12 + n * .18);
          final stroke = Path()
            ..moveTo(x, y)
            ..quadraticBezierTo(x + dx * .36, y - dy * .65,
                x + dx, y - dy * .36)
            ..quadraticBezierTo(x + dx * 1.04, y + dy * .18,
                x + dx * .81, y + dy * .46)
            ..quadraticBezierTo(x + dx * .28, y + dy * .76,
                x - 1.5, y + dy * .35)
            ..close();
          c.drawPath(stroke, impasto);
          impasto.color = Colors.white.withValues(alpha: .09 + n * .14);
          c.drawPath(Path()
            ..moveTo(x + 2, y)
            ..quadraticBezierTo(x + dx * .50, y - dy * .80,
                x + dx * .87, y - dy * .30)
            ..quadraticBezierTo(x + dx * .43, y - dy * .12,
                x + 2, y)
            ..close(), impasto);
        }
      }
      final rim = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = edge.withValues(alpha: .70);
      c.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 2, size.width - 4, size.height - 4),
        Radius.circular(math.max(0, radius - 2))), rim);
    } else {
      final line = Paint()
        ..color = ink.withValues(alpha: .13)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .75
        ..strokeCap = StrokeCap.round;
      c.drawLine(Offset(radius + 5, 3.8),
          Offset(size.width - radius - 5, 4.3), line);
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
