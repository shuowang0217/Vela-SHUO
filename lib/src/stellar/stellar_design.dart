import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/vela_palettes.dart';

/// Shared maritime visual language for Vela pages. Every color is
/// derived from the existing eight Vela palettes, including light themes.
class StellarAtmosphere extends StatelessWidget {
  const StellarAtmosphere({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = VelaThemeRuntime.active;
    return Stack(children: [
      Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            t.background,
            Color.lerp(t.background, t.accent, t.dark ? .12 : .05)!,
            t.background,
          ],
        ),
      ))),
      Positioned.fill(child: IgnorePointer(child: CustomPaint(
        painter: _StellarFieldPainter(t.accent, t.dark),
      ))),
      child,
    ]);
  }
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
    // Shared airport/node cards must also show the scene behind them.
    // A backdrop-filtered translucent tint preserves text contrast.
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(t.surface, t.accent, selected ? .20 : .05)!
                    .withValues(alpha: t.dark ? .72 : .80),
                t.surface.withValues(alpha: t.dark ? .56 : .72),
              ],
            ),
            border: Border.all(
              color: selected ? t.accent.withValues(alpha: .85)
                  : t.line.withValues(alpha: .56),
              width: selected ? 1.4 : 1,
            ),
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
        color: t.text, fontSize: 27, fontWeight: FontWeight.w700,
        letterSpacing: 1,
      )),
      const SizedBox(height: 5),
      Text(subtitle, style: TextStyle(color: t.muted, fontSize: 13)),
    ]);
  }
}

class StellarPlanetGlyph extends StatelessWidget {
  const StellarPlanetGlyph({super.key, this.size = 72});
  final double size;
  @override
  Widget build(BuildContext context) {
    final t = VelaThemeRuntime.active;
    return SizedBox(width: size, height: size,
      child: CustomPaint(painter: _PlanetPainter(t.accent, t.dark)));
  }
}

/// Quiet contour waves and chart guides, rather than a star field.
class _StellarFieldPainter extends CustomPainter {
  const _StellarFieldPainter(this.accent, this.dark);
  final Color accent;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = accent.withValues(alpha: dark ? .14 : .075);
    for (var row = 0; row < 7; row++) {
      final y = size.height * (.16 + row * .13);
      final wave = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += 8) {
        wave.lineTo(x, y + math.sin(x * .014 + row * 1.6) * 11);
      }
      canvas.drawPath(wave, paint);
    }
    // Faint dotted shipping lane; graphic decoration only.
    final lane = Paint()
      ..color = accent.withValues(alpha: dark ? .23 : .12);
    for (var i = 0; i < 28; i++) {
      final x = size.width * (i + .5) / 29;
      final y = size.height * (.17 + .23 * math.sin(i * .11));
      canvas.drawCircle(Offset(x, y), 1.25, lane);
    }
  }

  @override
  bool shouldRepaint(covariant _StellarFieldPainter other) =>
      other.accent != accent || other.dark != dark;
}

/// A compact sailboat emblem, using theme colors in light and dark mode.
class _PlanetPainter extends CustomPainter {
  const _PlanetPainter(this.accent, this.dark);
  final Color accent;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = math.min(size.width, size.height) / 100;
    canvas.save();
    canvas.translate((size.width - 100 * unit) / 2,
        (size.height - 100 * unit) / 2);
    canvas.scale(unit);

    canvas.drawCircle(const Offset(50, 50), 46, Paint()
      ..color = accent.withValues(alpha: dark ? .18 : .10));
    canvas.drawArc(const Rect.fromLTWH(7, 8, 86, 86), -.3, 2.8, false,
        Paint()..color = accent.withValues(alpha: .35)
          ..style = PaintingStyle.stroke..strokeWidth = 1.5);

    final mast = Paint()..color = accent..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(51, 16), const Offset(51, 71), mast);
    final mainsail = Path()
      ..moveTo(54, 19)..lineTo(77, 65)..lineTo(54, 65)..close();
    canvas.drawPath(mainsail, Paint()..color =
        Color.lerp(accent, Colors.white, dark ? .48 : .26)!);
    final jib = Path()
      ..moveTo(48, 27)..lineTo(48, 65)..lineTo(29, 65)..close();
    canvas.drawPath(jib, Paint()..color = accent.withValues(alpha: .84));

    final hull = Path()
      ..moveTo(23, 71)..quadraticBezierTo(50, 78, 81, 70)
      ..lineTo(73, 82)..quadraticBezierTo(48, 88, 30, 81)
      ..close();
    canvas.drawPath(hull, Paint()..color = accent);
    final wake = Paint()..color = accent.withValues(alpha: .50)
      ..strokeWidth = 2..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(const Rect.fromLTWH(18, 80, 30, 9),
        .12, 2.8, false, wake);
    canvas.drawArc(const Rect.fromLTWH(55, 80, 28, 9),
        .25, 2.8, false, wake);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlanetPainter old) =>
      old.accent != accent || old.dark != dark;
}
