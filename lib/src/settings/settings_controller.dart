import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores only local UI preferences. Never blocks first launch on I/O errors.
class SettingsController extends ChangeNotifier {
  static const _themeKey = 'vela.shuo.theme.v1';
  ThemeMode _themeMode = ThemeMode.dark;

  ThemeMode get themeMode => _themeMode;

  Future<void> load() async {
    try {
      final prefs = SharedPreferencesAsync();
      final saved = await prefs.getString(_themeKey);
      _themeMode = switch (saved) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.dark,
      };
    } catch (_) {
      _themeMode = ThemeMode.dark;
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode next) async {
    if (_themeMode == next) return;
    _themeMode = next;
    notifyListeners();
    try {
      final prefs = SharedPreferencesAsync();
      await prefs.setString(_themeKey, next.name);
    } catch (_) {
      // The running application remains usable if persistent storage fails.
    }
  }
}
