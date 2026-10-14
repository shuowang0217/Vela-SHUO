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
                    .withValues(alpha: t.dark ? .18 : .38),
                t.surface.withValues(alpha: t.dark ? .10 : .25),
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

/// Metallic bezel, etched 48-tick dial and two-tone directional needle.
class _CompassPainter extends CustomPainter {
  _CompassPainter(this.accent, this.dark);
  final Color accent;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) * .455;
    final bezel = Rect.fromCircle(center: c, radius: r);
    final metal = Color.lerp(accent, Colors.white, dark ? .30 : .65)!;
    final shadow = Color.lerp(accent, Colors.black, .65)!;

    canvas.drawCircle(c, r * 1.04, Paint()
      ..color = accent.withValues(alpha: dark ? .19 : .12)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .19));
    canvas.drawCircle(c, r, Paint()
      ..shader = SweepGradient(colors: [
        metal, shadow, metal, shadow, metal,
      ]).createShader(bezel));
    canvas.drawCircle(c, r * .91, Paint()
      ..color = dark ? const Color(0xD9091727) : const Color(0xC6F6FAFF));
    canvas.drawCircle(c, r * .88, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.7, r * .024)
      ..color = metal.withValues(alpha: .8));
    canvas.drawCircle(c, r * .73, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.5, r * .015)
      ..color = accent.withValues(alpha: .28));

    for (var i = 0; i < 48; i++) {
      final angle = (i * math.pi / 24) - math.pi / 2;
      final major = i % 4 == 0;
      final inside = r * (major ? .76 : .82);
      final outside = r * .87;
      final dx = math.cos(angle), dy = math.sin(angle);
      canvas.drawLine(
        Offset(c.dx + inside * dx, c.dy + inside * dy),
        Offset(c.dx + outside * dx, c.dy + outside * dy),
        Paint()
          ..strokeWidth = major ? math.max(1, r * .033) : math.max(.5, r * .013)
          ..strokeCap = StrokeCap.round
          ..color = metal.withValues(alpha: major ? .9 : .46),
      );
    }

    // Fine starburst at the exact intersection of the compass points.
    final cross = Paint()
      ..strokeWidth = math.max(.6, r * .014)
      ..color = accent.withValues(alpha: .33);
    canvas.drawLine(Offset(c.dx - r * .54, c.dy),
        Offset(c.dx + r * .54, c.dy), cross);
    canvas.drawLine(Offset(c.dx, c.dy - r * .54),
        Offset(c.dx, c.dy + r * .54), cross);

    void triangle(Offset tip, Offset left, Offset right, Color fill) {
      canvas.drawPath(Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close(), Paint()..color = fill);
    }
    final wing = r * .15;
    triangle(Offset(c.dx, c.dy - r * .55),
      Offset(c.dx - wing, c.dy + r * .09),
      Offset(c.dx + wing, c.dy + r * .09), metal);
    triangle(Offset(c.dx, c.dy + r * .55),
      Offset(c.dx - wing, c.dy - r * .09),
      Offset(c.dx + wing, c.dy - r * .09),
      accent.withValues(alpha: .64));
    // Cut one thin central line for an engraved-metal finish.
    canvas.drawLine(Offset(c.dx, c.dy - r * .51),
      Offset(c.dx, c.dy + r * .46),
      Paint()..color = shadow.withValues(alpha: .45)
        ..strokeWidth = math.max(.6, r * .025));
    canvas.drawCircle(c, r * .105, Paint()..color = shadow);
    canvas.drawCircle(c, r * .066, Paint()..color = metal);

    if (r >= 18) {
      final tp = TextPainter(
        text: TextSpan(text: 'N', style: TextStyle(
          fontSize: r * .24, fontWeight: FontWeight.w800,
          color: metal)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(c.dx - tp.width / 2,
          c.dy - r * .74 - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _CompassPainter old) =>
      accent != old.accent || dark != old.dark;
}
