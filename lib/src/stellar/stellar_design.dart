import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/vela_palettes.dart';
import '../brand/vela_watercolor_chrome.dart';

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
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: VelaThemeRuntime.oilPreview ? 0 : 9,
        sigmaY: VelaThemeRuntime.oilPreview ? 0 : 9),
      child: VelaWatercolorSurface(
        padding: padding ?? const EdgeInsets.all(15),
        radius: radius, selected: selected, child: child),
    ),
  );
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
  Widget build(BuildContext context) {
    final oil = VelaThemeRuntime.oilPreview;
    final t = VelaThemeRuntime.active;
    final Widget button = filled
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: oil ? FilledButton.styleFrom(
              foregroundColor: t.text,
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              elevation: 0) : null,
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: oil ? OutlinedButton.styleFrom(
              foregroundColor: t.text,
              backgroundColor: Colors.transparent,
              side: BorderSide.none) : null,
          );
    return oil
        ? VelaWatercolorSurface(
            selected: filled,
            radius: 14,
            padding: EdgeInsets.zero,
            child: button,
          )
        : button;
  }
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
        color: t.text, fontSize: 24, fontWeight: FontWeight.w600,
        fontFamily: 'Georgia',
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

/// Engraved watercolor compass. Keep the map, not the metal, in focus.
class _CompassPainter extends CustomPainter {
  _CompassPainter(this.accent, this.dark);
  final Color accent;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) * .44;
    final ink = dark ? const Color(0xFFE8D9B9)
        : const Color(0xFF2A5663);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..color = ink.withValues(alpha: .85);
    canvas.drawCircle(c, r, Paint()
      ..color = accent.withValues(alpha: .12));
    canvas.drawCircle(c, r, outline);
    canvas.drawCircle(c, r * .8,
      outline..strokeWidth = .65..color = ink.withValues(alpha: .48));
    for (var i = 0; i < 16; i++) {
      final a = i * math.pi / 8;
      final vx = math.cos(a), vy = math.sin(a);
      canvas.drawLine(Offset(c.dx + r * .80 * vx,
          c.dy + r * .80 * vy),
        Offset(c.dx + r * .92 * vx, c.dy + r * .92 * vy),
        outline..strokeWidth = i % 2 == 0 ? 1.15 : .65);
    }
    final north = Path()
      ..moveTo(c.dx, c.dy - r * .59)
      ..lineTo(c.dx - r * .16, c.dy + r * .05)
      ..lineTo(c.dx + r * .12, c.dy - r * .08)..close();
    final south = Path()
      ..moveTo(c.dx, c.dy + r * .59)
      ..lineTo(c.dx + r * .16, c.dy - r * .05)
      ..lineTo(c.dx - r * .12, c.dy + r * .08)..close();
    canvas.drawPath(north, Paint()..color = ink);
    canvas.drawPath(south, Paint()
      ..color = accent.withValues(alpha: .55));
    canvas.drawCircle(c, r * .05, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(covariant _CompassPainter old) =>
      accent != old.accent || dark != old.dark;
}
