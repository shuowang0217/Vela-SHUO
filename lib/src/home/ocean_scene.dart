import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/vela_palettes.dart';
import 'demo_connection.dart';

/// Vela's maritime illustration: sail, ocean, compass and voyage track.
/// Decorative only: it never displays invented proxy metrics or locations.
class VelaOceanScene extends StatelessWidget {
  const VelaOceanScene({super.key, required this.demo});

  final VelaDemoController demo;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: demo,
    builder: (context, _) => CustomPaint(
      painter: _OceanPainter(
        accent: VelaThemeRuntime.active.accent,
        dark: VelaThemeRuntime.active.dark,
        connected: demo.isConnected,
      ),
      child: const SizedBox.expand(),
    ),
  );
}

class _OceanPainter extends CustomPainter {
  const _OceanPainter({
    required this.accent,
    required this.dark,
    required this.connected,
  });

  final Color accent;
  final bool dark;
  final bool connected;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final width = size.width;
    final height = size.height;
    final base = dark ? const Color(0xFF0E1D31) : const Color(0xFFCCE6EF);
    final ocean = Color.lerp(const Color(0xFF154E73), accent, .32)!;
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [base.withValues(alpha: .18),
          base.withValues(alpha: .55),
          ocean.withValues(alpha: dark ? .55 : .40)],
        stops: const [0, .52, 1],
      ).createShader(Offset.zero & size));

    // Keep maritime shapes proportional even inside the tall desktop hero.
    canvas.save();
    final factor = math.min(width / 1000, height / 650);
    canvas.translate((width - 1000 * factor) / 2,
        (height - 650 * factor) / 2);
    canvas.scale(factor);

    // Horizon and mist.
    final haze = Paint()..color = accent.withValues(alpha: .12);
    canvas.drawOval(const Rect.fromLTWH(130, 240, 780, 165), haze);
    final horizon = Paint()
      ..color = accent.withValues(alpha: dark ? .30 : .27)
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(60, 386), const Offset(945, 386), horizon);

    // Distant sea and layered wave surfaces.
    for (var i = 0; i < 5; i++) {
      final baseline = 390.0 + i * 52;
      final wave = Path()..moveTo(-40, baseline);
      for (var x = -40.0; x <= 1040; x += 12) {
        wave.lineTo(x, baseline + math.sin(x * .013 + i * 1.2) * (9 + i * 2));
      }
      wave..lineTo(1040, 660)..lineTo(-40, 660)..close();
      final shade = Color.lerp(ocean, base, (i / 6).clamp(0.0, 1.0).toDouble())!;
      canvas.drawPath(wave, Paint()
        ..color = shade.withValues(alpha: dark ? .36 : .28));
      final crest = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: dark ? .12 : .23);
      canvas.drawPath(Path()
        ..moveTo(-40, baseline)
        ..quadraticBezierTo(190, baseline - 14, 380, baseline)
        ..quadraticBezierTo(650, baseline + 15, 1040, baseline - 8), crest);
    }

    // Nautical route marker arcs (ornament, not a geolocation claim).
    final compassPaint = Paint()
      ..color = accent.withValues(alpha: .24)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawArc(const Rect.fromLTWH(250, 102, 515, 515), -2.65, 2.7,
        false, compassPaint);
    canvas.drawArc(const Rect.fromLTWH(306, 158, 403, 403), .40, 1.35,
        false, compassPaint);
    for (var i = 0; i < 19; i++) {
      final theta = 2.7 + i * .13;
      canvas.drawCircle(
        Offset(510 + 257 * math.cos(theta),
            360 + 257 * math.sin(theta)), 2.4,
        Paint()..color = accent.withValues(alpha: i.isEven ? .49 : .23));
    }

    // A real sailboat silhouette: hull, mast, two sails and bow pennant.
    final hull = Path()
      ..moveTo(320, 417)
      ..quadraticBezierTo(487, 451, 705, 405)
      ..lineTo(665, 464)
      ..quadraticBezierTo(493, 504, 366, 463)
      ..close();
    canvas.drawPath(hull, Paint()..color = dark
        ? const Color(0xFF83C0D8) : const Color(0xFF1B668A));

    final mast = Paint()
      ..color = dark ? const Color(0xFFE2F5FF) : const Color(0xFF236989)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(505, 137), const Offset(505, 428), mast);
    final mainsail = Path()
      ..moveTo(514, 150)
      ..lineTo(661, 381)
      ..quadraticBezierTo(588, 406, 515, 404)
      ..close();
    canvas.drawPath(mainsail, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Colors.white.withValues(alpha: .96),
          accent.withValues(alpha: .82)],
      ).createShader(const Rect.fromLTWH(510, 145, 157, 265)));
    final foresail = Path()
      ..moveTo(495, 182)
      ..lineTo(495, 395)
      ..quadraticBezierTo(414, 408, 365, 397)
      ..close();
    canvas.drawPath(foresail, Paint()
      ..color = const Color(0xFF5CA6CC).withValues(alpha: .91));
    final pennant = Path()
      ..moveTo(504, 137)..lineTo(564, 155)
      ..lineTo(505, 162)..close();
    canvas.drawPath(pennant, Paint()..color =
        connected ? const Color(0xFF38D5B2) : accent);

    // Small compass reference above the horizon.
    final compass = Paint()
      ..color = accent.withValues(alpha: .45)
      ..strokeWidth = 2..style = PaintingStyle.stroke;
    canvas.drawCircle(const Offset(804, 224), 39, compass);
    canvas.drawLine(const Offset(804, 165), const Offset(804, 192), compass);
    canvas.drawLine(const Offset(804, 256), const Offset(804, 283), compass);
    canvas.drawLine(const Offset(746, 224), const Offset(771, 224), compass);
    canvas.drawLine(const Offset(838, 224), const Offset(861, 224), compass);
    final needle = Path()
      ..moveTo(804, 195)..lineTo(813, 229)
      ..lineTo(804, 222)..lineTo(795, 229)..close();
    canvas.drawPath(needle, Paint()..color = accent.withValues(alpha: .86));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OceanPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.dark != dark ||
      oldDelegate.connected != connected;
}
