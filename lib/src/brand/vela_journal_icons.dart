import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/vela_palettes.dart';
import 'vela_sail_mark.dart';

enum VelaJournalSymbol { sail, route, compass, journal, settings }

/// Hand-inked navigation symbols with a thin diluted watercolor wash.
class VelaJournalIcon extends StatelessWidget {
  const VelaJournalIcon({super.key, required this.symbol,
    this.selected = false, this.size = 24});
  final VelaJournalSymbol symbol;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (symbol == VelaJournalSymbol.sail) {
      return VelaSailMark(size: size, monochrome: !selected);
    }
    final tokens = VelaThemeRuntime.active;
    return SizedBox(width: size, height: size,
      child: CustomPaint(painter: _JournalIconPainter(
        symbol, selected ? tokens.accent : tokens.muted,
        tokens.accentSoft, selected)));
  }
}

class _JournalIconPainter extends CustomPainter {
  const _JournalIconPainter(this.symbol, this.ink, this.watercolor, this.active);
  final VelaJournalSymbol symbol;
  final Color ink;
  final Color watercolor;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    canvas.drawOval(const Rect.fromLTWH(2, 3, 28, 26), Paint()
      ..color = watercolor.withValues(alpha: active ? .24 : .11));
    final pen = Paint()
      ..color = ink
      ..strokeWidth = 1.65
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final thin = Paint()
      ..color = ink.withValues(alpha: .5)
      ..strokeWidth = .8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    switch (symbol) {
      case VelaJournalSymbol.route:
        canvas.drawPath(Path()
          ..moveTo(5, 23)
          ..cubicTo(10, 21, 9, 9, 16, 12)
          ..cubicTo(21, 14, 23, 20, 28, 8), pen);
        canvas.drawCircle(const Offset(5, 23), 2.7, pen);
        canvas.drawCircle(const Offset(27, 8), 2.6, pen);
        canvas.drawPath(Path()
          ..moveTo(11, 24)..quadraticBezierTo(18, 27, 25, 23), thin);
        break;
      case VelaJournalSymbol.compass:
        canvas.drawCircle(const Offset(16, 16), 11, pen);
        canvas.drawCircle(const Offset(16, 16), 8.8, thin);
        canvas.drawPath(Path()
          ..moveTo(20, 11)..lineTo(14.3, 14.3)
          ..lineTo(11, 21)..lineTo(17.5, 17.5)..close(), pen);
        canvas.drawCircle(const Offset(16, 16), 1.25,
          Paint()..color = ink);
        break;
      case VelaJournalSymbol.journal:
        canvas.drawPath(Path()
          ..moveTo(5, 8)..quadraticBezierTo(10, 5, 15.7, 9)
          ..quadraticBezierTo(21, 5, 27, 8)
          ..lineTo(27, 25)
          ..quadraticBezierTo(21, 22, 16, 26)
          ..quadraticBezierTo(10, 22, 5, 25)..close(), pen);
        canvas.drawLine(const Offset(16, 9),
          const Offset(16, 25), thin);
        canvas.drawLine(const Offset(8, 13),
          const Offset(13, 14), thin);
        canvas.drawLine(const Offset(20, 14),
          const Offset(24, 13), thin);
        break;
      case VelaJournalSymbol.settings:
        canvas.drawCircle(const Offset(16, 16), 9.5, pen);
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          final x = math.cos(angle), y = math.sin(angle);
          canvas.drawLine(Offset(16 + 9.5 * x, 16 + 9.5 * y),
            Offset(16 + 12.8 * x, 16 + 12.8 * y), pen);
        }
        canvas.drawCircle(const Offset(16, 16), 3.8, pen);
        break;
      case VelaJournalSymbol.sail:
        break;
    }
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant _JournalIconPainter old) =>
      old.symbol != symbol || old.ink != ink ||
      old.watercolor != watercolor || old.active != active;
}
