import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../subscription/vela_subscription_controller.dart';
import '../network/flclash_core_api.dart';
import '../network/vela_flclash_subscription_adapter.dart';

enum VelaAndroidVpnPhase { disconnected, preparing, connecting, connected, error }

/// Reflects only statuses reported by Android VpnService, not animation or
/// activity launch. On non-Android platforms no channel calls are made.
class VelaAndroidVpnController extends ChangeNotifier {
  VelaAndroidVpnController({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('vela_shuo/android_vpn') {
    _channel.setMethodCallHandler(_handleNative);
  }

  final MethodChannel _channel;
  VelaAndroidVpnPhase _phase = VelaAndroidVpnPhase.disconnected;
  String? _error;
  bool _disposed = false;

  VelaAndroidVpnPhase get phase => _phase;
  String? get error => _error;
  bool get busy => _phase == VelaAndroidVpnPhase.preparing ||
      _phase == VelaAndroidVpnPhase.connecting;
  bool get connected => _phase == VelaAndroidVpnPhase.connected;
  bool get active => busy || connected;
  String get phaseText => switch (_phase) {
    VelaAndroidVpnPhase.disconnected => 'VPN 未连接',
    VelaAndroidVpnPhase.preparing => '正在请求 Android VPN 授权…',
    VelaAndroidVpnPhase.connecting => '正在建立 Vela VPN…',
    VelaAndroidVpnPhase.connected => 'Android VPN 已连接',
    VelaAndroidVpnPhase.error => 'VPN 连接失败',
  };

  void _setPhase(VelaAndroidVpnPhase next, [String? error]) {
    if (_disposed) return;
    _phase = next;
    _error = error;
    notifyListeners();
  }

  Future<dynamic> _handleNative(MethodCall call) async {
    if (call.method == 'statusChanged' && call.arguments is Map) {
      final value = Map<String, dynamic>.from(call.arguments as Map);
      _setPhase(_decode(value['state'] as String?),
          value['error'] is String ? value['error'] as String : null);
    }
  }

  static VelaAndroidVpnPhase _decode(String? value) => switch (value) {
    'preparing' => VelaAndroidVpnPhase.preparing,
    'connecting' => VelaAndroidVpnPhase.connecting,
    'connected' => VelaAndroidVpnPhase.connected,
    'error' => VelaAndroidVpnPhase.error,
    _ => VelaAndroidVpnPhase.disconnected,
  };

  /// Mihomo native process counters; disabled unless the VPN is verified.
  Future<(int, int)?> readTrafficCounters() async {
    if (!Platform.isAndroid || _disposed || !connected) return null;
    try {
      final values = await _channel.invokeMapMethod<String, dynamic>('traffic')
          .timeout(const Duration(seconds: 3));
      final up = values?['up'];
      final down = values?['down'];
      if (up is! int || down is! int || up < 0 || down < 0) {
        return null;
      }
      return (up, down);
    } catch (_) {
      return null;
    }
  }

  Future<void> refresh() async {
    if (!Platform.isAndroid || _disposed) return;
    try {
      final data = await _channel.invokeMapMethod<String, dynamic>('status');
      if (data != null) {
        _setPhase(_decode(data['state'] as String?),
            data['error'] is String ? data['error'] as String : null);
      }
    } catch (_) {
      _setPhase(VelaAndroidVpnPhase.error, '无法查询 Android VPN 服务状态');
    }
  }

  Future<bool> start(VelaSubscriptionController subscription) async {
    // FlClash can start VPN with native selectors and selectedMap even
    // when the root selected outbound is URLTest/Fallback, not a leaf node.
    if (!Platform.isAndroid || _disposed || active ||
        subscription.androidVpnProfile == null) {
      return false;
    }
    final profile = subscription.androidVpnProfile;
    if (profile == null) {
      _setPhase(VelaAndroidVpnPhase.error, '请先导入有效订阅并选择节点');
      return false;
    }
    _setPhase(VelaAndroidVpnPhase.preparing);
    try {
      final started = await _channel.invokeMethod<bool>(
          'start', <String, dynamic>{'profile': profile});
      if (started != true) {
        _setPhase(VelaAndroidVpnPhase.disconnected, '未授权 Android VPN');
        return false;
      }
      // Starting the service is not a successful tunnel connection.
      if (_phase == VelaAndroidVpnPhase.preparing) {
        _setPhase(VelaAndroidVpnPhase.connecting);
      }
      return true;
    } catch (_) {
      _setPhase(VelaAndroidVpnPhase.error, '启动 VPN 失败，请检查系统权限');
      return false;
    }
  }

  /// User-triggered real HTTPS check through the already established VPN.
  /// The native Android channel returns the outcome of actual TLS requests;
  /// this is not inferred from the existence of a local port or a timer.
  Future<bool> testConnectivity() async {
    if (!Platform.isAndroid || _disposed || !connected) return false;
    try {
      return await _channel.invokeMethod<bool>('testConnection')
          .timeout(const Duration(seconds: 26)) == true && connected;
    } catch (_) {
      return false;
    }
  }

  /// Change a live VPN node through FlClash's actual Go selector RPC.
  /// Confirm actual Mihomo selector state, not arbitrary HTTP reachability.
  Future<bool> switchNode(
      VelaSubscriptionController subscription, int index) async {
    if (!Platform.isAndroid || _disposed || !connected ||
        index < 0 || index >= subscription.nodes.length ||
        subscription.selectedIndex == null) {
      return false;
    }
    final current = subscription.selectedIndex!;
    if (current == index) return true;
    final oldName = subscription.configuredNameFor(current);
    final nextName = subscription.configuredNameFor(index);
    if (oldName == null || nextName == null) return false;
    final api = FlClashCoreApi(const FlClashAndroidTransport());
    final group = subscription is VelaFlClashSubscriptionController
        ? (subscription.backend.activeGroup ?? 'GLOBAL')
        : 'VELA_SELECT';
    try {
      // FlClash changes the native Mihomo selector directly. A public
      // reachability probe is diagnostic, not a node-selection veto.
      await api.changeProxy(group, nextName);
      final snapshot = await api.getProxies();
      final proxies = snapshot['proxies'];
      final state = proxies is Map ? proxies[group] : null;
      if (state is Map && state['now'] == nextName) {
        return subscription.confirmVpnSelection(index);
      }
      await api.changeProxy(group, oldName);
      _error = 'FlClash 核心未确认新节点，已恢复原节点';
      notifyListeners();
    } catch (_) {
      try {
        await api.changeProxy(group, oldName);
      } catch (_) {
        // Native backend may be gone; never claim rollback succeeded.
        _error = '节点切换和恢复失败，请安全断开 VPN 后重试';
        notifyListeners();
        return false;
      }
      _error = '切换失败，已恢复先前节点';
      notifyListeners();
    }
    return false;
  }

  Future<bool> stop() async {
    if (!Platform.isAndroid || _disposed) return false;
    try {
      await _channel.invokeMethod<void>('stop');
      _setPhase(VelaAndroidVpnPhase.disconnected);
      return true;
    } catch (_) {
      _setPhase(VelaAndroidVpnPhase.error, '无法安全关闭 VPN，请检查系统设置');
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
