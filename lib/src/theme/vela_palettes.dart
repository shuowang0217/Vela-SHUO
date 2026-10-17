import 'package:flutter/material.dart';

/// Eight top palettes shown in Color Hunt Popular / All time (2026-10).
/// Swatches are stored in their original vertical display order.
/// Source: https://colorhunt.co/palettes/popular
@immutable
class VelaPalette {
  const VelaPalette({
    required this.id,
    required this.name,
    required this.swatches,
    required this.prefersDark,
    required this.darkBaseIndex,
    required this.accentIndex,
  });

  final String id;
  final String name;
  final List<Color> swatches;
  final bool prefersDark;
  final int darkBaseIndex;
  final int accentIndex;

  static const List<VelaPalette> all = [
    VelaPalette(
      id: 'mint',
      name: '薄荷海风',
      swatches: [Color(0xFFE3FDFD), Color(0xFFCBF1F5),
        Color(0xFFA6E3E9), Color(0xFF71C9CE)],
      prefersDark: false, darkBaseIndex: 3, accentIndex: 3,
    ),
    VelaPalette(
      id: 'navy',
      name: '雾蓝晨光',
      swatches: [Color(0xFFF9F7F7), Color(0xFFDBE2EF),
        Color(0xFF3F72AF), Color(0xFF112D4E)],
      prefersDark: true, darkBaseIndex: 3, accentIndex: 2,
    ),
    VelaPalette(
      id: 'peach',
      name: '蜜桃暮色',
      swatches: [Color(0xFFFFF5E4), Color(0xFFFFE3E1),
        Color(0xFFFFD1D1), Color(0xFFFF9494)],
      prefersDark: false, darkBaseIndex: 3, accentIndex: 3,
    ),
    VelaPalette(
      id: 'pink',
      name: '樱粉轻语',
      swatches: [Color(0xFFF9F5F6), Color(0xFFF8E8EE),
        Color(0xFFFDCEDF), Color(0xFFF2BED1)],
      prefersDark: false, darkBaseIndex: 2, accentIndex: 3,
    ),
    VelaPalette(
      id: 'sand',
      name: '暖沙时光',
      swatches: [Color(0xFFAD8B73), Color(0xFFCEAB93),
        Color(0xFFE3CAA5), Color(0xFFFFFBE9)],
      prefersDark: false, darkBaseIndex: 0, accentIndex: 0,
    ),
    VelaPalette(
      id: 'rose',
      name: '玫瑰薄雾',
      swatches: [Color(0xFFFFC7C7), Color(0xFFFFE2E2),
        Color(0xFFF6F6F6), Color(0xFF8785A2)],
      prefersDark: false, darkBaseIndex: 3, accentIndex: 3,
    ),
    VelaPalette(
      id: 'lavender',
      name: '薰衣草夜',
      swatches: [Color(0xFFF4EEFF), Color(0xFFDCD6F7),
        Color(0xFFA6B1E1), Color(0xFF424874)],
      prefersDark: true, darkBaseIndex: 3, accentIndex: 2,
    ),
    VelaPalette(
      id: 'ocean',
      name: '深海航迹',
      swatches: [Color(0xFF1B262C), Color(0xFF0F4C75),
        Color(0xFF3282B8), Color(0xFFBBE1FA)],
      prefersDark: true, darkBaseIndex: 0, accentIndex: 3,
    ),
  ];

  static const String defaultId = 'ocean';

  static VelaPalette byId(String id) {
    for (final palette in all) {
      if (palette.id == id) return palette;
    }
    return all.last;
  }

  static bool containsId(String id) => all.any((p) => p.id == id);

  VelaThemeTokens tokens(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final base = swatches[darkBaseIndex];
    final light = swatches.reduce((a, b) =>
        a.computeLuminance() > b.computeLuminance() ? a : b);
    final target = swatches[accentIndex];
    final surface = dark
        ? Color.lerp(base, const Color(0xFF080E17), .35)!
        : Color.lerp(light, Colors.white, .10)!;
    final background = dark
        ? Color.lerp(base, const Color(0xFF05080F), .57)!
        : Color.lerp(light, Colors.white, .27)!;
    final content = dark ? const Color(0xFFF6F8FC) :
        const Color(0xFF202630);
    final muted = dark ? const Color(0xFFBAC8D7) :
        const Color(0xFF505963);
    // Bright pastel accents disappear against bright surfaces; mix toward
    // the darkest swatch until the accent remains legible.
    final accent = dark
        ? (target.computeLuminance() < .3
            ? Color.lerp(target, Colors.white, .55)!
            : target)
        : (target.computeLuminance() > .27
            ? Color.lerp(target, Colors.black, .43)!
            : target);
    return VelaThemeTokens(
      background: background,
      surface: surface,
      raised: Color.lerp(surface, dark ? Colors.white : Colors.black,
          dark ? .055 : .045)!,
      line: Color.lerp(background, dark ? Colors.white : Colors.black,
          dark ? .24 : .17)!,
      accent: accent,
      accentSoft: Color.lerp(accent, dark ? Colors.white : Colors.black,
          dark ? .16 : .08)!,
      text: content,
      muted: muted,
      dark: dark,
    );
  }
}

@immutable
class VelaThemeTokens {
  const VelaThemeTokens({
    required this.background,
    required this.surface,
    required this.raised,
    required this.line,
    required this.accent,
    required this.accentSoft,
    required this.text,
    required this.muted,
    required this.dark,
  });

  final Color background;
  final Color surface;
  final Color raised;
  final Color line;
  final Color accent;
  final Color accentSoft;
  final Color text;
  final Color muted;
  final bool dark;
}

/// The dashboard's legacy private color constants now resolve to this
/// palette at runtime. The app chooses the palette before rebuilding the
/// dashboard; the historical layout and globe assets remain unchanged.
class VelaThemeRuntime {
  VelaThemeRuntime._();

  static VelaThemeTokens active =
      VelaPalette.byId(VelaPalette.defaultId).tokens(Brightness.dark);

  /// In the v1.8 experimental skin all surfaces share the same oil-painted
  /// canvas/ink palette; user palette preferences remain stored for rollback.
  static const bool oilPreview =
      bool.fromEnvironment('VELA_OIL_PREVIEW', defaultValue: true);

  static void select(VelaPalette palette, Brightness brightness) {
    if (!oilPreview) {
      active = palette.tokens(brightness);
      return;
    }
    active = const VelaThemeTokens(
      background: Color(0xFFE9DDC5),
      surface: Color(0xFFFFF1D9),
      raised: Color(0xFFFFF8E8),
      line: Color(0xFFAD906D),
      accent: Color(0xFF8B5929),
      accentSoft: Color(0xFFD9B37A),
      text: Color(0xFF243646),
      muted: Color(0xFF5F6570),
      dark: false,
    );
  }
}
