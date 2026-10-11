import 'dart:async';

import 'package:flutter/foundation.dart';

typedef VelaTrafficReader = Future<(int, int)?> Function();

/// Session-only Mihomo counters. Rates are sampled deltas, not node benchmark
/// speeds. All history is in RAM; no hostnames or traffic contents are read.
class VelaTrafficMonitor extends ChangeNotifier {
  VelaTrafficMonitor({
    required VelaTrafficReader reader,
    DateTime Function()? clock,
    Duration interval = const Duration(seconds: 1),
  })  : _reader = reader,
        _clock = clock ?? DateTime.now,
        _interval = interval;

  final VelaTrafficReader _reader;
  final DateTime Function() _clock;
  final Duration _interval;
  Timer? _timer;
  bool _disposed = false;
  bool _sampling = false;
  bool _connected = false;
  int _generation = 0;
  DateTime? _connectedAt;
  DateTime? _lastSampleAt;
  int? _lastUp;
  int? _lastDown;
  double? uploadBytesPerSecond;
  double? downloadBytesPerSecond;
  int? uploadedBytes;
  int? downloadedBytes;

  bool get connected => _connected;
  Duration get elapsed => _connectedAt == null || !_connected
      ? Duration.zero : _clock().difference(_connectedAt!);

  String get elapsedLabel {
    if (!_connected) return '—';
    final d = elapsed;
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours == 0 ? '$minutes:$seconds' : '$hours:$minutes:$seconds';
  }

  static String rateMbps(double? rate) =>
      rate == null ? '—' : (rate * 8 / 1000000).toStringAsFixed(2);

  static String totalLabel(int? bytes) {
    if (bytes == null) return '暂无数据';
    if (bytes >= 1073741824) {
      return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1048576) {
      return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  void sync(bool connected) {
    if (_disposed || _connected == connected) return;
    _generation++;
    _connected = connected;
    _timer?.cancel();
    _timer = null;
    _lastSampleAt = null;
    _lastUp = null;
    _lastDown = null;
    uploadBytesPerSecond = null;
    downloadBytesPerSecond = null;
    uploadedBytes = null;
    downloadedBytes = null;
    _connectedAt = connected ? _clock() : null;
    notifyListeners();
    if (connected) {
      unawaited(sample());
      _timer = Timer.periodic(_interval, (_) => unawaited(sample()));
    }
  }

  Future<void> sample() async {
    if (_disposed || !_connected || _sampling) return;
    _sampling = true;
    final generation = _generation;
    try {
      final pair = await _reader();
      if (_disposed || !_connected || generation != _generation) return;
      if (pair == null || pair.$1 < 0 || pair.$2 < 0) {
        _invalidateRate();
        return;
      }
      final now = _clock();
      final oldTime = _lastSampleAt;
      final oldUp = _lastUp;
      final oldDown = _lastDown;
      if (oldTime != null && oldUp != null && oldDown != null &&
          pair.$1 >= oldUp && pair.$2 >= oldDown) {
        final seconds = now.difference(oldTime).inMicroseconds / 1000000;
        if (seconds > 0.05) {
          uploadBytesPerSecond = (pair.$1 - oldUp) / seconds;
          downloadBytesPerSecond = (pair.$2 - oldDown) / seconds;
        } else {
          uploadBytesPerSecond = null;
          downloadBytesPerSecond = null;
        }
      } else {
        // Mihomo process restarted or this is the initial baseline.
        uploadBytesPerSecond = null;
        downloadBytesPerSecond = null;
      }
      uploadedBytes = pair.$1;
      downloadedBytes = pair.$2;
      _lastUp = pair.$1;
      _lastDown = pair.$2;
      _lastSampleAt = now;
      notifyListeners();
    } catch (_) {
      if (!_disposed && _connected && generation == _generation) {
        _invalidateRate();
      }
    } finally {
      _sampling = false;
    }
  }

  void _invalidateRate() {
    // Never leave a stale displayed speed after polling fails.
    uploadBytesPerSecond = null;
    downloadBytesPerSecond = null;
    _lastSampleAt = null;
    _lastUp = null;
    _lastDown = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
