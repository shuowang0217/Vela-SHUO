import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/vela_palettes.dart';

/// Shared visual language for the two approved stellar pages. Every color is
/// derived from the existing eight Vela palettes, including light themes.
class StellarAtmosphere extends StatelessWidget {
  const StellarAtmosphere({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = VelaThemeRuntime.active;
    return Stack(children: [
      // Preserve the shared Earth instead of painting a solid page background.
      Positioned.fill(child: IgnorePointer(child: DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [
            t.background.withValues(alpha: .07),
            t.accent.withValues(alpha: .025),
            Colors.transparent,
          ],
        )),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [
                Color.lerp(t.surface, t.accent,
                    selected ? .19 : .065)!
                    .withValues(alpha: t.dark ? .35 : .67),
                t.surface.withValues(alpha: t.dark ? .23 : .55),
              ],
            ),
            border: Border.all(
              color: selected ? t.accent.withValues(alpha: .78)
                  : t.text.withValues(alpha: .16),
              width: selected ? 1.4 : 1,
            ),
            boxShadow: selected ? [
              BoxShadow(
                color: t.accent.withValues(alpha: t.dark ? .16 : .08),
                blurRadius: 20, spreadRadius: 1,
              ),
            ] : null,
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

class _StellarFieldPainter extends CustomPainter {
  _StellarFieldPainter(this.accent, this.dark);
  final Color accent;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(12411);
    for (var i = 0; i < 75; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final radius = i % 8 == 0 ? 1.5 : .65;
      canvas.drawCircle(Offset(x, y), radius, Paint()
        ..color = accent.withValues(alpha: dark ? .20 : .08));
    }
    final ray = Paint()
      ..strokeWidth = .7
      ..color = accent.withValues(alpha: dark ? .14 : .08);
    for (var i = 0; i < 3; i++) {
      final offset = size.width * (.2 + i * .3);
      canvas.drawLine(
          Offset(offset, 0), Offset(offset + size.width * .22, size.height), ray);
    }
  }
  @override
  bool shouldRepaint(covariant _StellarFieldPainter other) =>
      other.accent != accent || other.dark != dark;
}

class _PlanetPainter extends CustomPainter {
  _PlanetPainter(this.accent, this.dark);
  final Color accent;
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width * .5, size.height * .5);
    final radius = math.min(size.width, size.height) * .35;
    canvas.drawCircle(c, radius * 1.35, Paint()
      ..color = accent.withValues(alpha: .17)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .42));
    final rect = Rect.fromCircle(center: c, radius: radius);
    canvas.drawCircle(c, radius, Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.48, -.54),
        colors: [
          Color.lerp(accent, Colors.white, .43)!,
          accent,
          Color.lerp(accent, Colors.black, .72)!,
        ],
      ).createShader(rect));
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-.3);
    final orbit = Rect.fromCenter(center: Offset.zero,
        width: radius * 2.85, height: radius * .62);
    canvas.drawOval(orbit, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = accent.withValues(alpha: .65));
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant _PlanetPainter old) =>
      accent != old.accent || dark != old.dark;
}
