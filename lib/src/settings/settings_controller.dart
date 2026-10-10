import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/vela_diagnostics.dart';
import '../theme/vela_palettes.dart';

/// Small storage boundary to make invalid values and I/O errors testable.
abstract class VelaPreferenceStore {
  Future<String?> readTheme();
  Future<void> writeTheme(String value);
  Future<void> removeTheme();
}

abstract class VelaPalettePreferenceStore {
  Future<String?> readPalette();
  Future<void> writePalette(String value);
  Future<void> removePalette();
}

class VelaSharedPreferencesStore implements VelaPreferenceStore, VelaPalettePreferenceStore {
  VelaSharedPreferencesStore();

  // Defer native plugin initialization until the first actual disk access.
  // Constructing an inactive UI controller must work in widget tests too.
  late final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  static const String themeKey = 'vela.shuo.theme.v1';
  static const String paletteKey = 'vela.shuo.palette.v1';

  @override
  Future<String?> readPalette() => _preferences.getString(paletteKey);

  @override
  Future<void> writePalette(String value) => _preferences.setString(paletteKey, value);

  @override
  Future<void> removePalette() => _preferences.remove(paletteKey);

  @override
  Future<String?> readTheme() => _preferences.getString(themeKey);

  @override
  Future<void> writeTheme(String value) =>
      _preferences.setString(themeKey, value);

  @override
  Future<void> removeTheme() => _preferences.remove(themeKey);
}

/// Local UI preferences, independent of the future proxy core.
/// Unsupported/corrupted data resets to a safe default; storage failure
/// cannot prevent offline launch or overwrite unrelated application keys.
class SettingsController extends ChangeNotifier {
  SettingsController({
    VelaPreferenceStore? store,
    VelaDiagnostics? diagnostics,
    this.ioTimeout = const Duration(seconds: 3),
  })  : _store = store ?? VelaSharedPreferencesStore(),
        _diagnostics = diagnostics;

  final VelaPreferenceStore _store;
  final VelaDiagnostics? _diagnostics;
  final Duration ioTimeout;
  ThemeMode _themeMode = ThemeMode.dark;
  String _paletteId = VelaPalette.defaultId;
  String get paletteId => _paletteId;
  VelaPalette get palette => VelaPalette.byId(_paletteId);
  Future<void> _writes = Future<void>.value();

  ThemeMode get themeMode => _themeMode;

  Future<void> load() async {
    try {
      final value = await _store.readTheme().timeout(ioTimeout);
      if (value != null &&
          value != 'dark' &&
          value != 'light' &&
          value != 'system') {
        _themeMode = ThemeMode.dark;
        _diagnostics?.record(VelaDiagnosticEvent.settingsRecovered);
        // Repair only this application's known theme key.
        try {
          await _store.removeTheme().timeout(ioTimeout);
        } catch (_) {
          _diagnostics?.record(VelaDiagnosticEvent.settingsWriteFailed);
        }
      } else {
        _themeMode = switch (value) {
          'light' => ThemeMode.light,
          'system' => ThemeMode.system,
          _ => ThemeMode.dark,
        };
        _diagnostics?.record(VelaDiagnosticEvent.settingsLoaded);
      }
    } catch (_) {
      // Includes malformed value types and permissions/I/O failures.
      _themeMode = ThemeMode.dark;
      _diagnostics?.record(VelaDiagnosticEvent.settingsReadFailed);
      try {
        await _store.removeTheme().timeout(ioTimeout);
      } catch (_) {
        // Storage may be unreadable; the application remains usable.
      }
    }
    final paletteStore = _store;
    if (paletteStore is VelaPalettePreferenceStore) {
      try {
        final saved = await paletteStore.readPalette().timeout(ioTimeout);
        if (saved != null && !VelaPalette.containsId(saved)) {
          _paletteId = VelaPalette.defaultId;
          _diagnostics?.record(VelaDiagnosticEvent.settingsRecovered);
          try {
            await paletteStore.removePalette().timeout(ioTimeout);
          } catch (_) {
            _diagnostics?.record(VelaDiagnosticEvent.settingsWriteFailed);
          }
        } else {
          _paletteId = saved ?? VelaPalette.defaultId;
        }
      } catch (_) {
        _paletteId = VelaPalette.defaultId;
        _diagnostics?.record(VelaDiagnosticEvent.settingsReadFailed);
      }
    }
    notifyListeners();
  }

  Future<void> setPalette(String paletteId) async {
    if (!VelaPalette.containsId(paletteId)) return;
    if (_paletteId == paletteId) return;
    _paletteId = paletteId;
    _themeMode = VelaPalette.byId(paletteId).prefersDark
        ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    // Save mode and palette in the same serialized queue.
    _writes = _writes.then((_) async {
      try {
        await _store.writeTheme(_themeMode.name).timeout(ioTimeout);
        if (_store case final VelaPalettePreferenceStore store) {
          await store.writePalette(paletteId).timeout(ioTimeout);
        }
        _diagnostics?.record(VelaDiagnosticEvent.settingsSaved);
      } catch (_) {
        _diagnostics?.record(VelaDiagnosticEvent.settingsWriteFailed);
      }
    });
    await _writes;
  }

  Future<void> setThemeMode(ThemeMode next) async {
    if (_themeMode == next) return;
    _themeMode = next;
    notifyListeners();

    // A user may toggle multiple times before a disk write completes.
    // Serialize writes so the last selected theme wins after restart.
    final value = next.name;
    _writes = _writes.then((_) async {
      try {
        await _store.writeTheme(value).timeout(ioTimeout);
        _diagnostics?.record(VelaDiagnosticEvent.settingsSaved);
      } catch (_) {
        _diagnostics?.record(VelaDiagnosticEvent.settingsWriteFailed);
      }
    });
    await _writes;
  }

  Future<void> flush() => _writes;
}
