import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/vela_palettes.dart';

/// Shared visual language for the two approved stellar pages. Every color is
/// derived from the existing eight Vela palettes, including light themes.
/// Shared Earth is left unobstructed; each panel frosts only its own bounds.
class StellarAtmosphere extends StatelessWidget {
  const StellarAtmosphere({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class StellarPanel extends StatelessWidget {
  const StellarPanel({super.key, required this.child, this.padding,
      this.selected = false, this.radius = 20});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool selected;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = VelaThemeRuntime.active;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [
                Color.lerp(t.raised, t.accent, selected ? .15 : .04)!
                  .withValues(alpha: t.dark ? .78 : .86),
                t.surface.withValues(alpha: t.dark ? .73 : .83),
              ],
            ),
            border: Border.all(
              color: selected ? t.accent.withValues(alpha: .78)
                  : t.line.withValues(alpha: t.dark ? .68 : .79),
              width: selected ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: selected ? t.accent.withValues(alpha: .19)
                    : Colors.black.withValues(alpha: t.dark ? .22 : .10),
                blurRadius: selected ? 20 : 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class StellarLabel extends StatelessWidget {
  const StellarLabel(this.label, {super.key, this.accent = false, this.size = 12});
  final String label;
  final bool accent;
  final double size;
  @override
  Widget build(BuildContext context) => Text(label, style: TextStyle(
    color: accent ? VelaThemeRuntime.active.accent
        : VelaThemeRuntime.active.muted,
    fontSize: size,
  ));
}

class StellarAction extends StatelessWidget {
  const StellarAction({super.key, required this.label, required this.icon,
    this.onPressed, this.filled = false});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;
  @override
  Widget build(BuildContext context) => filled
      ? FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
        )
      : OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
        );
}

class StellarSectionHeading extends StatelessWidget {
  const StellarSectionHeading(this.title, this.subtitle, {super.key});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) {
    final t = VelaThemeRuntime.active;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(
        color: t.text, fontFamily: 'Georgia', fontSize: 26, fontWeight: FontWeight.w600,
        letterSpacing: 1,
      )),
      const SizedBox(height: 5),
      Text(subtitle, style: TextStyle(color: t.muted, fontSize: 13)),
    ]);
  }
}

/// Engraved navigation compass replacing the ornamental planets.
class StellarCompassGlyph extends StatelessWidget {
  const StellarCompassGlyph({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = VelaThemeRuntime.active;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CompassPainter(t.accent, t.dark)),
    );
  }
}

/// Ink compass on diluted watercolor paper, matching the new world atlas.
class _CompassPainter extends CustomPainter {
  _CompassPainter(this.accent, this.dark);
  final Color accent;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .455;
    final ink = dark ? const Color(0xFFE0D7B6)
        : const Color(0xFF29505A);
    final wash = dark ? const Color(0xFF668A85)
        : const Color(0xFFADCDD0);
    canvas.drawCircle(center, radius * 1.01, Paint()
      ..color = wash.withValues(alpha: .24));
    canvas.drawCircle(center, radius * .90, Paint()
      ..color = wash.withValues(alpha: .19));
    canvas.drawCircle(center, radius, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, radius * .035)
      ..color = ink);
    canvas.drawCircle(center, radius * .88, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .75
      ..color = accent.withValues(alpha: .6));
    for (var i = 0; i < 24; i++) {
      final theta = math.pi * i / 12 - math.pi / 2;
      final vector = Offset(math.cos(theta), math.sin(theta));
      canvas.drawLine(center + vector * radius * (i % 3 == 0 ? .73 : .81),
        center + vector * radius * .89, Paint()
        ..color = ink.withValues(alpha: .72)
        ..strokeWidth = i % 3 == 0 ? 1.15 : .55
        ..strokeCap = StrokeCap.round);
    }
    final north = Path()
      ..moveTo(center.dx, center.dy - radius * .58)
      ..lineTo(center.dx - radius * .17, center.dy + radius * .08)
      ..lineTo(center.dx + radius * .12, center.dy - radius * .02)
      ..close();
    final south = Path()
      ..moveTo(center.dx, center.dy + radius * .58)
      ..lineTo(center.dx - radius * .12, center.dy + radius * .02)
      ..lineTo(center.dx + radius * .17, center.dy - radius * .08)
      ..close();
    canvas.drawPath(north, Paint()
      ..color = accent.withValues(alpha: .78));
    canvas.drawPath(south, Paint()
      ..color = wash.withValues(alpha: .86));
    final outline = Paint()
      ..color = ink..style = PaintingStyle.stroke
      ..strokeWidth = 1.2..strokeJoin = StrokeJoin.round;
    canvas.drawPath(north, outline);
    canvas.drawPath(south, outline);
    canvas.drawCircle(center, radius * .075,
      Paint()..color = ink);
  }

  @override
  bool shouldRepaint(covariant _CompassPainter old) =>
      accent != old.accent || dark != old.dark;
}
