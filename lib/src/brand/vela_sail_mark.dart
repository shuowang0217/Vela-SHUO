import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Vela's selected blue / champagne-gold sail, drawn as vectors at every size.
/// This is shared by the main shell, native navigation badges and empty states.
class VelaSailMark extends StatelessWidget {
  const VelaSailMark({super.key, this.size = 48,
      this.monochrome = false, this.active = true});
  final double size;
  final bool monochrome;
  final bool active;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size, height: size,
    child: CustomPaint(painter: VelaSailPainter(
      monochrome: monochrome, active: active)),
  );
}

class VelaSailPainter extends CustomPainter {
  const VelaSailPainter({this.monochrome = false, this.active = true});
  final bool monochrome;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final ratio = math.min(size.width / 160, size.height / 160);
    canvas.save();
    canvas.translate((size.width - 160 * ratio) / 2,
        (size.height - 160 * ratio) / 2);
    canvas.scale(ratio);
    const navy = Color(0xFF0B294B);
    const steel = Color(0xFF7294AE);
    const pearl = Color(0xFFE7F5FF);
    const gold = Color(0xFFE7BA72);
    final muted = !active || monochrome;
    final primary = muted ? const Color(0xFF7890A6) : navy;
    final glow = muted ? const Color(0xFFADBAC5) : gold;

    // The partial horizon arc remains legible at launcher icon sizes.
    final arc = Path()
      ..moveTo(25, 93)
      ..cubicTo(21, 58, 39, 29, 70, 19);
    canvas.drawPath(arc, Paint()
      ..color = glow.withValues(alpha: .86)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round);

    final outer = Path()
      ..moveTo(83, 12)
      ..cubicTo(110, 27, 120, 65, 121, 107)
      ..cubicTo(105, 95, 95, 95, 87, 96)
      ..cubicTo(85, 59, 83, 31, 83, 12)
      ..close();
    canvas.drawPath(outer, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: muted ? [primary, glow] :
          [navy, steel, pearl, gold],
        stops: const [0, .43, .78, 1],
      ).createShader(const Rect.fromLTWH(76, 10, 50, 110)));

    final inner = Path()
      ..moveTo(80, 16)
      ..cubicTo(72, 48, 56, 84, 37, 105)
      ..cubicTo(55, 98, 66, 100, 75, 105)
      ..cubicTo(83, 78, 82, 41, 80, 16)
      ..close();
    canvas.drawPath(inner, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: muted ? [primary, glow] :
          [navy, const Color(0xFF4E789C), pearl],
      ).createShader(const Rect.fromLTWH(35, 16, 55, 95)));

    // White negative-space curvature is a stable silhouette, not a glow.
    final cut = Path()
      ..moveTo(81, 23)
      ..cubicTo(83, 52, 82, 80, 75, 104)
      ..cubicTo(78, 109, 83, 112, 85, 109)
      ..cubicTo(87, 70, 86, 46, 81, 23)
      ..close();
    canvas.drawPath(cut, Paint()..color = pearl.withValues(alpha: .93));

    final hull = Path()
      ..moveTo(9, 126)
      ..cubicTo(39, 108, 70, 113, 91, 120)
      ..cubicTo(111, 127, 133, 131, 153, 119)
      ..cubicTo(136, 143, 108, 142, 83, 133)
      ..cubicTo(52, 124, 34, 119, 9, 126)
      ..close();
    canvas.drawPath(hull, Paint()
      ..shader = LinearGradient(colors: muted
        ? [primary, glow] : [navy, steel, gold, navy])
          .createShader(const Rect.fromLTWH(9, 113, 144, 31)));

    canvas.drawPath(Path()
      ..moveTo(12, 140)
      ..cubicTo(47, 131, 79, 141, 105, 144)
      ..cubicTo(120, 147, 133, 143, 145, 138),
      Paint()
        ..color = glow.withValues(alpha: .76)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke);

    // Navigation star: deliberately simple for 16 px tray displays.
    final star = Path()
      ..moveTo(135, 32)
      ..lineTo(138, 40)
      ..lineTo(146, 43)
      ..lineTo(138, 46)
      ..lineTo(135, 54)
      ..lineTo(132, 46)
      ..lineTo(124, 43)
      ..lineTo(132, 40)
      ..close();
    canvas.drawPath(star, Paint()..color = glow);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant VelaSailPainter old) =>
      old.monochrome != monochrome || old.active != active;
}
