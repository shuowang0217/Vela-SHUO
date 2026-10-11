import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../subscription/vela_subscription_controller.dart';

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
    VelaAndroidVpnPhase.connecting => '正在建立 Mihomo VPN…',
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
    if (!Platform.isAndroid || _disposed || active ||
        subscription.selected == null) {
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
