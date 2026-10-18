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

class VelaSharedPreferencesStore
    implements VelaPreferenceStore, VelaPalettePreferenceStore {
  VelaSharedPreferencesStore();

  // SharedPreferencesAsync on Android defaults to DataStore, while the
  // older Flutter preferences API writes to Android SharedPreferences.
  // Read both stores to migrate existing selections across app revisions.
  // A successful write to either store is enough to retain the preference.
  late final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  static const String themeKey = 'vela.shuo.theme.v1';
  static const String paletteKey = 'vela.shuo.palette.v1';

  Future<String?> _read(String key) async {
    // The legacy Android backend is the primary restart-safe store.
    // Existing DataStore values are copied into it only when absent.
    try {
      final legacy = await SharedPreferences.getInstance();
      final saved = legacy.getString(key);
      if (saved != null) return saved;
    } catch (_) {
      // Legacy platform implementation may be absent (desktop/tests).
    }
    final saved = await _preferences.getString(key);
    if (saved != null) {
      try {
        await (await SharedPreferences.getInstance()).setString(key, saved);
      } catch (_) {
        // Async DataStore remains authoritative if migration is unavailable.
      }
    }
    return saved;
  }

  Future<void> _write(String key, String value) async {
    var success = false;
    // Explicitly use the Android SharedPreferences backend as well as
    // DataStore: user selections survive process termination and upgrades.
    try {
      final legacy = await SharedPreferences.getInstance();
      success = await legacy.setString(key, value);
    } catch (_) {
      // Try the other backend even if this one fails.
    }
    try {
      await _preferences.setString(key, value);
      success = true;
    } catch (_) {
      // A successfully committed legacy write is sufficient.
    }
    if (!success) throw StateError('Preference storage unavailable');
  }

  Future<void> _remove(String key) async {
    var success = false;
    try {
      final legacy = await SharedPreferences.getInstance();
      success = await legacy.remove(key);
    } catch (_) {}
    try {
      await _preferences.remove(key);
      success = true;
    } catch (_) {}
    if (!success) throw StateError('Preference storage unavailable');
  }

  @override
  Future<String?> readPalette() => _read(paletteKey);
  @override
  Future<void> writePalette(String value) => _write(paletteKey, value);
  @override
  Future<void> removePalette() => _remove(paletteKey);
  @override
  Future<String?> readTheme() => _read(themeKey);
  @override
  Future<void> writeTheme(String value) => _write(themeKey, value);
  @override
  Future<void> removeTheme() => _remove(themeKey);
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
      // Never erase a saved theme on a transient Android I/O error.
    }
    if (_store is VelaPalettePreferenceStore) {
      final paletteStore = _store as VelaPalettePreferenceStore;
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
    final selectedMode = _themeMode.name;
    _writes = _writes.then((_) async {
      // A failed theme write must never prevent the palette from saving.
      // Prioritize the user's selected color before the light/dark mode.
      var failed = false;
      if (_store case final VelaPalettePreferenceStore store) {
        try {
          await store.writePalette(paletteId).timeout(ioTimeout);
        } catch (_) {
          failed = true;
        }
      }
      try {
        await _store.writeTheme(selectedMode).timeout(ioTimeout);
      } catch (_) {
        failed = true;
      }
      _diagnostics?.record(failed
          ? VelaDiagnosticEvent.settingsWriteFailed
          : VelaDiagnosticEvent.settingsSaved);
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
