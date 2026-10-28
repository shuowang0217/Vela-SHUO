import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

import 'vela_exit_ip_monitor.dart';

/// A miniature oil-painted flag instead of a platform emoji. The flag's
/// accurate underlying geometry ships locally with the app. A warm pigment
/// glaze, short raised brush marks, canvas grain, and a gently worn border
/// are drawn by Flutter and do not depend on platform fonts.
class VelaOilFlag extends StatelessWidget {
  const VelaOilFlag({super.key, required this.countryCode});

  final String countryCode;

  // Frequently used airport regions; uncommon or unsupported codes use
  // an equally styled two-letter canvas plaque instead of a broken SVG.
  static const supported = <String>{
    'JP', 'US', 'SG', 'HK', 'TW', 'KR', 'GB', 'DE',
    'CA', 'AU', 'FR', 'NL', 'TH', 'VN', 'MY', 'ID',
    'PH', 'IN', 'IT', 'CH', 'TR', 'BR', 'NZ', 'AE',
  };

  @override
  Widget build(BuildContext context) {
    final code = countryCode.toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        color: const Color(0xFFDDCBAE),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33594D40),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          width: 22,
          height: 16,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (supported.contains(code))
                CountryFlag.fromCountryCode(
                  code,
                  key: const ValueKey('vela_exit_country_flag'),
                  theme: const ImageTheme(
                    width: 22,
                    height: 16,
                    shape: RoundedRectangle(3),
                  ),
                )
              else
                Center(
                  child: Text(
                    code,
                    key: const ValueKey('vela_exit_flag_fallback'),
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF756249),
                    ),
                  ),
                ),
              const IgnorePointer(
                child: CustomPaint(
                  key: ValueKey('vela_oil_flag_brush_texture'),
                  foregroundPainter: VelaOilFlagTexturePainter(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Deterministic pigment marks: no animation, image loading, network request
/// or random repaint. Flags are deliberately a little warmer than the raw
/// vector artwork to harmonize with Vela's painted connection plaque.
class VelaOilFlagTexturePainter extends CustomPainter {
  const VelaOilFlagTexturePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0x16E6D1AD));

    // Fine, raised dabs. Alternating light/dark pigments add an oil-paint
    // surface without obscuring stars, sun, stripes, or other flag emblems.
    final light = Paint()
      ..color = const Color(0x35FFF7E3)
      ..strokeCap = StrokeCap.round;
    final shadow = Paint()
      ..color = const Color(0x20564538)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 38; i++) {
      final x = (i * 47 % 101) / 101 * size.width;
      final y = (i * 31 % 83) / 83 * size.height;
      final brush = i.isEven ? light : shadow;
      brush.strokeWidth = i % 5 == 0 ? 0.7 : 0.32;
      final dx = 0.9 + (i % 4) * 0.44;
      final dy = i % 3 == 0 ? -0.5 : 0.25;
      canvas.drawLine(Offset(x, y), Offset(x + dx, y + dy), brush);
    }

    // Uneven translucent glaze under a small antique-gold bevel.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0x22FFF6D8),
            Color(0x005C4C3A),
            Color(0x15553C2B),
          ],
        ).createShader(rect),
    );
    final rim = RRect.fromRectAndRadius(
      rect.deflate(0.55), const Radius.circular(2.5),
    );
    canvas.drawRRect(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x886F5942),
    );
    canvas.drawLine(
      const Offset(2, 1),
      Offset(size.width - 3, 1),
      Paint()
        ..color = const Color(0x72FFF6DD)
        ..strokeWidth = 0.75,
    );
  }

  @override
  bool shouldRepaint(covariant VelaOilFlagTexturePainter oldDelegate) => false;
}

/// A subtle single line inside the original top-right connection plaque.
class VelaExitIpIndicator extends StatelessWidget {
  const VelaExitIpIndicator({
    super.key,
    required this.info,
    required this.statusText,
    required this.accentColor,
    required this.mutedColor,
  });

  final VelaExitIpInfo? info;
  final String statusText;
  final Color accentColor;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    const fontSize = 10.5;
    final details = info;
    if (details == null) {
      return Text(
        statusText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: mutedColor,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return Semantics(
      label: '出口 ${details.countryCode} ${details.address}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          VelaOilFlag(
            key: const ValueKey('vela_exit_oil_flag'),
            countryCode: details.countryCode,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              details.address,
              key: const ValueKey('vela_exit_ip_address'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accentColor,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
