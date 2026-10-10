import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Strictly allowlisted diagnostics: callers cannot pass exception text,
/// stack traces, URLs, hostnames, subscriptions, or other user content.
enum VelaDiagnosticEvent {
  appStarted,
  appResumed,
  appPaused,
  flutterError,
  uncaughtError,
  settingsLoaded,
  settingsRecovered,
  settingsReadFailed,
  settingsSaved,
  settingsWriteFailed,
}

/// Windows-only local, bounded diagnostic journal. No telemetry or upload.
/// On unsupported systems (or when LOCALAPPDATA is unavailable) it keeps only
/// a short in-memory history without writing to the working directory.
class VelaDiagnostics extends ChangeNotifier {
  VelaDiagnostics({Directory? directory, DateTime Function()? clock})
      : _directory = directory ?? _windowsDirectory(),
        _clock = clock ?? DateTime.now;

  static const int maxMemoryEntries = 80;
  static const int maxLogBytes = 128 * 1024;

  final Directory? _directory;
  final DateTime Function() _clock;
  final List<String> _entries = <String>[];
  Future<void> _pending = Future<void>.value();
  bool _diskAvailable = true;
  bool _closed = false;

  bool get persistent => _directory != null && _diskAvailable;
  List<String> get recentEntries => List<String>.unmodifiable(_entries);
  String get report => [
        'Vela-SHUO local diagnostics (event codes only)',
        ..._entries,
      ].join('\n');

  static Directory? _windowsDirectory() {
    if (!Platform.isWindows) return null;
    final root = Platform.environment['LOCALAPPDATA'];
    if (root == null || root.trim().isEmpty) return null;
    return Directory(
      '$root${Platform.pathSeparator}Vela-SHUO'
      '${Platform.pathSeparator}Diagnostics',
    );
  }

  void record(VelaDiagnosticEvent event) {
    if (_closed) return;
    // Only enum identifiers enter the journal. Never stringify exceptions.
    final line = jsonEncode(<String, String>{
      'utc': _clock().toUtc().toIso8601String(),
      'event': event.name,
    });
    _entries.add(line);
    if (_entries.length > maxMemoryEntries) _entries.removeAt(0);
    notifyListeners();

    if (_directory == null || !_diskAvailable) return;
    // Serialized writes avoid interleaved JSON or concurrent log rotation.
    _pending = _pending.then((_) async {
      try {
        await _append(line);
      } catch (_) {
        _diskAvailable = false;
        if (!_closed) notifyListeners();
      }
    });
  }

  Future<void> _append(String line) async {
    final directory = _directory;
    if (directory == null) return;
    await directory.create(recursive: true);
    final active = File(
      '${directory.path}${Platform.pathSeparator}events.jsonl',
    );
    final previous = File(
      '${directory.path}${Platform.pathSeparator}events.previous.jsonl',
    );
    // Rotate before exceeding the cap; keep at most two small journals.
    if (await active.exists() &&
        await active.length() + utf8.encode(line).length + 1 > maxLogBytes) {
      if (await previous.exists()) await previous.delete();
      await active.rename(previous.path);
    }
    await active.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  /// Await pending local writes, e.g. during test verification.
  Future<void> flush() => _pending;

  /// Explicit local delete, including both rotation files. No upload occurs.
  Future<bool> clear() async {
    await _pending;
    try {
      final directory = _directory;
      if (directory != null) {
        for (final name in ['events.jsonl', 'events.previous.jsonl']) {
          final file = File(
            '${directory.path}${Platform.pathSeparator}$name',
          );
          if (await file.exists()) await file.delete();
        }
      }
      _entries.clear();
      if (!_closed) notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
