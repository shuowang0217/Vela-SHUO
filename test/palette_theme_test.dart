import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/app.dart';
import 'package:vela_shuo/src/settings/settings_controller.dart';
import 'package:vela_shuo/src/theme/vela_palettes.dart';
import 'package:vela_shuo/src/brand/vela_watercolor_chrome.dart';

class _PaletteStore implements VelaPreferenceStore, VelaPalettePreferenceStore {
  String? theme = 'dark';
  String? palette;
  bool rejectThemeWrites = false;
  final List<String> saved = [];

  @override
  Future<String?> readTheme() async => theme;

  @override
  Future<void> writeTheme(String value) async {
    if (rejectThemeWrites) throw StateError('theme write failed');
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

  test('palette survives restart even when theme write fails', () async {
    final store = _PaletteStore()..rejectThemeWrites = true;
    final settings = SettingsController(store: store);
    await settings.load();
    await settings.setPalette('mint');
    expect(store.palette, 'mint');
    settings.dispose();
    final restored = SettingsController(store: store);
    await restored.load();
    expect(restored.paletteId, 'mint');
    restored.dispose();
  });

  test('on-device preference backend reopens saved palette', () async {
    SharedPreferences.setMockInitialValues({});
    final first = SettingsController();
    await first.load();
    await first.setPalette('lavender');
    await first.flush();
    first.dispose();

    final restored = SettingsController();
    await restored.load();
    expect(restored.paletteId, 'lavender');
    expect(restored.themeMode, ThemeMode.dark);
    restored.dispose();
  });

  test('v2 palette wins over stale v1 after restart', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.vela.shuo.palette.v1': 'ocean',
      'flutter.vela.shuo.palette.v2': 'peach',
    });
    final restored = SettingsController();
    await restored.load();
    expect(restored.paletteId, 'peach');
    restored.dispose();
  });

  test('old Android preference palette migrates into v2', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.vela.shuo.palette.v1': 'lavender',
    });
    final first = SettingsController();
    await first.load();
    expect(first.paletteId, 'lavender');
    first.dispose();
    final next = SettingsController();
    await next.load();
    expect(next.paletteId, 'lavender');
    next.dispose();
  });

  test('Android native preference commit outlives controller restart', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final store = <String, String>{};
    const channel = MethodChannel('vela_shuo/ui_preferences');
    final messenger = TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'readPalette':
          return store['palette'];
        case 'readTheme':
          return store['theme'];
        case 'writePalette':
          store['palette'] = (call.arguments as Map)['value'] as String;
          return true;
        case 'writeTheme':
          store['theme'] = (call.arguments as Map)['value'] as String;
          return true;
        case 'removePalette':
          store.remove('palette');
          return true;
        case 'removeTheme':
          store.remove('theme');
          return true;
        default:
          throw PlatformException(code: 'UNSUPPORTED');
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    SharedPreferences.setMockInitialValues({
      'flutter.vela.shuo.palette.v1': 'ocean',
      'flutter.vela.shuo.palette.v2': 'peach',
    });
    final first = SettingsController(
        store: VelaSharedPreferencesStore(useAndroidNative: true));
    await first.load();
    await first.setPalette('mint');
    expect(first.lastPaletteSaveSucceeded, isTrue);
    expect(store['palette'], 'mint');
    first.dispose();

    final restarted = SettingsController(
        store: VelaSharedPreferencesStore(useAndroidNative: true));
    await restarted.load();
    expect(restarted.paletteId, 'mint');
    restarted.dispose();
  });

  test('failed native disk commit is never reported as saved', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('vela_shuo/ui_preferences');
    final messenger = TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'readPalette' ||
          call.method == 'readTheme') return null;
      throw PlatformException(code: 'STORAGE');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    SharedPreferences.setMockInitialValues({});
    final controller = SettingsController(
        store: VelaSharedPreferencesStore(useAndroidNative: true));
    await controller.load();
    await controller.setPalette('rose');
    expect(controller.lastPaletteSaveSucceeded, isFalse);
    controller.dispose();
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
    expect(nextDecoration.image, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    settings.dispose();
  });
}
