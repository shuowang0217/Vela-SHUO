import 'dart:async';

import 'package:flutter/foundation.dart';

import 'flclash_core_api.dart';

/// Watches the selected native Mihomo group without sending an Internet
/// request. URLTest/Fallback can change its "now" member without a Flutter
/// node-selection event. Only the root selector's reachable chain is watched;
/// domain-specific RULE destinations can use different chains.
class VelaAutoRouteWatcher extends ChangeNotifier {
  VelaAutoRouteWatcher({
    required FlClashCoreApi api,
    Duration interval = const Duration(seconds: 15),
  }) : _api = api, _interval = interval;

  final FlClashCoreApi _api;
  final Duration _interval;
  Timer? _timer;
  bool _closed = false;
  bool _connected = false;
  bool _busy = false;
  int _generation = 0;
  String _root = '';
  String? _signature;
  String? _lastError;

  String? get signature => _signature;
  String? get lastError => _lastError;
  bool get connected => _connected;
  String get displayChain => _signature?.replaceAll('|', ' → ') ?? '暂无';

  void sync(bool connected, String root) {
    if (_closed) return;
    final normalized = root.trim();
    if (_connected == connected && _root == normalized) return;
    _generation++;
    _connected = connected;
    _root = normalized;
    _signature = null;
    _lastError = null;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
    if (!connected || normalized.isEmpty) return;
    unawaited(checkNow());
    _timer = Timer.periodic(_interval, (_) => unawaited(checkNow()));
  }

  /// A manual or resume check is independent of periodic IP lookups.
  Future<void> checkNow() async {
    if (_closed || !_connected || _root.isEmpty || _busy) return;
    final generation = _generation;
    final root = _root;
    _busy = true;
    try {
      final states = await _api.getProxies().timeout(
        const Duration(seconds: 5));
      if (_closed || generation != _generation) return;
      final next = resolveNativeChain(states, root);
      if (next == null) {
        if (_lastError != '当前路由组不可查询') {
          _lastError = '当前路由组不可查询';
          notifyListeners();
        }
        return;
      }
      _lastError = null;
      if (next != _signature) {
        _signature = next;
        notifyListeners();
      }
    } catch (_) {
      if (!_closed && generation == _generation &&
          _lastError != '原生路由状态查询失败') {
        _lastError = '原生路由状态查询失败';
        notifyListeners();
      }
    } finally {
      _busy = false;
    }
  }

  /// Traverse only "now" links (never every member in "all"). Bound depth
  /// and reject cycles so malicious/invalid proxy metadata cannot hang UI.
  @visibleForTesting
  static String? resolveNativeChain(Map<String, dynamic> states, String root) {
    final chain = <String>[];
    final seen = <String>{};
    var current = root;
    for (var depth = 0; depth < 12; depth++) {
      if (current.isEmpty || !seen.add(current)) return null;
      chain.add(current);
      final item = states[current];
      if (item is! Map) {
        // A leaf might not be present in an incomplete proxy registry.
        return depth == 0 ? null : chain.join('|');
      }
      final kind = (item['type'] ?? '').toString().toLowerCase();
      final next = item['now'];
      if (next is! String || next.trim().isEmpty ||
          next == current) {
        return kind == 'selector' || kind == 'urltest' ||
            kind == 'fallback' || kind == 'loadbalance'
            ? null : chain.join('|');
      }
      current = next;
    }
    return null;
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
