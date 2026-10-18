import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/app.dart';
import 'package:vela_shuo/src/settings/settings_controller.dart';
import 'package:vela_shuo/src/theme/vela_palettes.dart';
import 'package:vela_shuo/src/brand/vela_watercolor_chrome.dart';

class _PaletteStore implements VelaPreferenceStore, VelaPalettePreferenceStore {
  String? theme = 'dark';
  String? palette;
  final List<String> saved = [];

  @override
  Future<String?> readTheme() async => theme;

  @override
  Future<void> writeTheme(String value) async {
    theme = value;
    saved.add('mode:$value');
  }

  @override
  Future<void> removeTheme() async => theme = null;

  @override
  Future<String?> readPalette() async => palette;

  @override
  Future<void> writePalette(String value) async {
    palette = value;
    saved.add('palette:$value');
  }

  @override
  Future<void> removePalette() async => palette = null;
}

void main() {
  test('exactly eight Color Hunt All-time swatch combinations', () {
    expect(VelaPalette.all.length, 8);
    expect(VelaPalette.all.map((e) => e.id), [
      'mint', 'navy', 'peach', 'pink', 'sand',
      'rose', 'lavender', 'ocean',
    ]);
    expect(VelaPalette.all.first.swatches,
      [Color(0xFFE3FDFD), Color(0xFFCBF1F5),
       Color(0xFFA6E3E9), Color(0xFF71C9CE)]);
    expect(VelaPalette.all.last.swatches,
      [Color(0xFF1B262C), Color(0xFF0F4C75),
       Color(0xFF3282B8), Color(0xFFBBE1FA)]);
  });

  test('selection instantly updates mode and persists palette across reload',
      () async {
    final store = _PaletteStore();
    final settings = SettingsController(store: store);
    await settings.load();
    expect(settings.paletteId, 'ocean');

    await settings.setPalette('peach');
    expect(settings.paletteId, 'peach');
    expect(settings.themeMode, ThemeMode.light);
    expect(store.palette, 'peach');
    expect(store.theme, 'light');

    final restored = SettingsController(store: store);
    await restored.load();
    expect(restored.paletteId, 'peach');
    expect(restored.themeMode, ThemeMode.light);

    settings.dispose();
    restored.dispose();
  });

  test('invalid palette key restores only that key', () async {
    final store = _PaletteStore()..palette = 'invalid-user-palette';
    final settings = SettingsController(store: store);
    await settings.load();

    expect(settings.paletteId, VelaPalette.defaultId);
    expect(store.palette, isNull);
    expect(store.theme, 'dark');
    settings.dispose();
  });

  test('contrast-aware token colors differ between themes and modes', () {
    final mint = VelaPalette.byId('mint').tokens(Brightness.light);
    final ocean = VelaPalette.byId('ocean').tokens(Brightness.dark);
    expect(mint.background, isNot(ocean.background));
    expect(mint.accent, isNot(ocean.accent));
    expect(mint.text.computeLuminance(), lessThan(.25));
    expect(ocean.text.computeLuminance(), greaterThan(.6));
  });

  testWidgets('settings displays eight interactive palette cards', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final settings = SettingsController(store: _PaletteStore());
    await tester.pumpWidget(VelaShuoApp(settings: settings));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('nav_3')));
    // Cloud animation is perpetual; do not wait for every ticker to settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('主题配色'), findsOneWidget);
    for (final p in VelaPalette.all) {
      expect(find.byKey(ValueKey('palette_${p.id}')), findsOneWidget);
    }
    final painted = find.byType(VelaWatercolorSurface).first;
    final previousBox = tester.widget<DecoratedBox>(find.descendant(
      of: painted, matching: find.byType(DecoratedBox)).first);
    final previousGradient =
        (previousBox.decoration as BoxDecoration).gradient
            as LinearGradient;
    final previousPigment = previousGradient.colors.first;
    await tester.tap(find.byKey(const ValueKey('palette_mint')));
    await tester.pump();
    expect(settings.paletteId, 'mint');
    expect(settings.themeMode, ThemeMode.light);
    final nextBox = tester.widget<DecoratedBox>(find.descendant(
      of: find.byType(VelaWatercolorSurface).first,
      matching: find.byType(DecoratedBox)).first);
    final nextDecoration = nextBox.decoration as BoxDecoration;
    expect((nextDecoration.gradient! as LinearGradient).colors.first,
        isNot(previousPigment));
    expect(nextDecoration.image, isNotNull);
    expect((nextDecoration.image!.image as AssetImage).assetName,
        'assets/oil/oil_map_clean.webp');
    await tester.pumpWidget(const SizedBox.shrink());
    settings.dispose();
  });
}
