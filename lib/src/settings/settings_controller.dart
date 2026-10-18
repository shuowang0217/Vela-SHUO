import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  VelaSharedPreferencesStore({bool? useAndroidNative})
      : _useAndroidNative = useAndroidNative ?? Platform.isAndroid;

  final bool _useAndroidNative;
  static const MethodChannel _native =
      MethodChannel('vela_shuo/ui_preferences');

  Future<String?> _readNative(String method) async {
    return _native.invokeMethod<String>(method);
  }

  Future<void> _writeNative(String method, String value) async {
    final saved = await _native.invokeMethod<bool>(
        method, <String, String>{'value': value});
    if (saved != true) {
      throw StateError('Native preference write failed');
    }
  }

  Future<void> _removeNative(String method) async {
    final removed = await _native.invokeMethod<bool>(method);
    if (removed != true) {
      throw StateError('Native preference removal failed');
    }
  }


  // One authoritative v2 key is used on every restart. The previous
  // implementation read legacy Android preferences BEFORE DataStore, so a
  // stale v1 value could override the user's newest selected palette.
  // Read v1 only once to migrate; do not consult it after v2 exists.
  late final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  static const String themeKey = 'vela.shuo.theme.v1';
  static const String paletteKey = 'vela.shuo.palette.v2';
  static const String legacyPaletteKey = 'vela.shuo.palette.v1';

  Future<String?> _getAsync(String key) async {
    try {
      return await _preferences.getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _getLegacy(String key) async {
    try {
      return (await SharedPreferences.getInstance()).getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _read(String key) async {
    if (_useAndroidNative) {
      // Native disk commit is the single source of truth on Android.
      // A null value allows one-time migration from older Flutter stores.
      final native = await _readNative(
          key == paletteKey ? 'readPalette' : 'readTheme');
      if (native != null) return native;
    }
    final current = await _getAsync(key);
    if (current != null) return current;
    final backup = await _getLegacy(key);
    if (backup != null) return backup;
    if (key != paletteKey) return null;

    // Migrate the old palette key, preferring a non-default choice when the
    // two old Android backends disagree.
    final oldAsync = await _getAsync(legacyPaletteKey);
    final oldLegacy = await _getLegacy(legacyPaletteKey);
    final selected = oldAsync != null &&
            oldAsync != VelaPalette.defaultId
        ? oldAsync
        : oldLegacy != null && oldLegacy != VelaPalette.defaultId
            ? oldLegacy
            : oldAsync ?? oldLegacy;
    if (selected != null) {
      try {
        await _write(paletteKey, selected);
      } catch (_) {
        // Still display the saved choice even if a migration write fails.
      }
    }
    return selected;
  }

  Future<void> _write(String key, String value) async {
    if (_useAndroidNative) {
      await _writeNative(
          key == paletteKey ? 'writePalette' : 'writeTheme', value);
      // Do not depend on a second asynchronous plugin write. The native
      // result is returned only after commit() and readback succeed.
      return;
    }
    var asyncSaved = false;
    var legacySaved = false;
    try {
      await _preferences.setString(key, value);
      asyncSaved = await _preferences.getString(key) == value;
    } catch (_) {}
    try {
      final legacy = await SharedPreferences.getInstance();
      legacySaved = await legacy.setString(key, value);
    } catch (_) {}
    if (!asyncSaved && !legacySaved) {
      throw StateError('Preference storage unavailable');
    }
  }

  Future<void> _remove(String key) async {
    if (_useAndroidNative) {
      await _removeNative(key == paletteKey ? 'removePalette' : 'removeTheme');
      return;
    }
    var success = false;
    try {
      await _preferences.remove(key);
      success = true;
    } catch (_) {}
    try {
      final legacy = await SharedPreferences.getInstance();
      success = await legacy.remove(key) || success;
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
  bool _lastPaletteSaveSucceeded = true;
  bool get lastPaletteSaveSucceeded => _lastPaletteSaveSucceeded;

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
    if (_paletteId == paletteId && _lastPaletteSaveSucceeded) return;
    _paletteId = paletteId;
    _themeMode = VelaPalette.byId(paletteId).prefersDark
        ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    _lastPaletteSaveSucceeded = false;
    // Save mode and palette in the same serialized queue.
    final selectedMode = _themeMode.name;
    _writes = _writes.then((_) async {
      // A failed theme write must never prevent the palette from saving.
      // Prioritize the user's selected color before the light/dark mode.
      var failed = false;
      if (_store case final VelaPalettePreferenceStore store) {
        try {
          await store.writePalette(paletteId).timeout(ioTimeout);
          _lastPaletteSaveSucceeded = true;
        } catch (_) {
          failed = true;
          _lastPaletteSaveSucceeded = false;
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
