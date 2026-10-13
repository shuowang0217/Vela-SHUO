import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'flclash_windows_backend.dart';

/// Native Mihomo routing modes; UI reflects only acknowledged core changes.
/// The mode is not a system-proxy toggle: Direct still uses the app listener.
enum VelaRoutingMode {
  rule('rule', '规则', '按配置中的规则分流'),
  global('global', '全局', '通过选中的代理节点'),
  direct('direct', '直连', '所有连接绕过代理节点');

  const VelaRoutingMode(this.wire, this.label, this.description);
  final String wire;
  final String label;
  final String description;

  static VelaRoutingMode decode(String? mode) =>
      VelaRoutingMode.values.firstWhere((m) => m.wire == mode,
          orElse: () => VelaRoutingMode.global);
}

class VelaRoutingModeController extends ChangeNotifier {
  VelaRoutingModeController(this.backend, {SharedPreferences? preferences})
      : _preferences = preferences;

  static const preferenceKey = 'vela_route_mode_v130';
  final FlClashWindowsBackend backend;
  SharedPreferences? _preferences;

  VelaRoutingMode current = VelaRoutingMode.global;
  bool busy = false;
  String? error;
  bool _closed = false;
  bool _restored = false;
  String? _appliedProfileId;
  Future<bool> Function(VelaRoutingMode)? testingApply;

  /// Load only non-secret presentation preference; do not report it as
  /// applied until Mihomo acknowledges updateConfig.
  Future<void> restore() async {
    if (_restored || _closed) return;
    _restored = true;
    try {
      _preferences ??= await SharedPreferences.getInstance();
      if (_closed) return;
      current = VelaRoutingMode.decode(
          _preferences?.getString(preferenceKey));
      notifyListeners();
    } catch (_) {
      error = '读取代理模式设置失败';
      if (!_closed) notifyListeners();
    }
  }

  /// Reapply after a native profile import or airport switch. All real
  /// updates use the same FlClash Go core on Windows and Android.
  Future<bool> synchronize(String? activeProfileId) async {
    if (_closed || busy || !backend.imported) return false;
    if (_appliedProfileId == activeProfileId && activeProfileId != null) {
      return true;
    }
    return _apply(current, activeProfileId: activeProfileId, persist: false);
  }

  Future<bool> setMode(VelaRoutingMode mode, String? activeProfileId) async {
    if (_closed || busy) return false;
    if (!backend.imported) {
      error = '请先添加机场订阅';
      notifyListeners();
      return false;
    }
    return _apply(mode, activeProfileId: activeProfileId, persist: true);
  }

  Future<bool> _apply(VelaRoutingMode target,
      {required String? activeProfileId, required bool persist}) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final applied = testingApply != null
          ? await testingApply!(target)
          : await backend.updateRoutingMode(target.wire);
      if (!applied) {
        error = '代理核心未确认模式切换，保留原模式';
        return false;
      }
      current = target;
      _appliedProfileId = activeProfileId;
      if (persist) {
        try {
          _preferences ??= await SharedPreferences.getInstance();
          await _preferences?.setString(preferenceKey, target.wire);
        } catch (_) {
          error = '代理模式已生效，但本机保存设置失败';
        }
      }
      return true;
    } catch (_) {
      error = '模式切换失败，原有代理连接未改变';
      return false;
    } finally {
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
