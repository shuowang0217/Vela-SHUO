import 'dart:async';
import 'dart:io';

import '../core/vela_core_controller.dart';
import 'flclash_windows_backend.dart';
import 'flclash_android_backend.dart';

/// Vela UI-facing compatibility surface. Every network operation delegates
/// directly to FlClash Go core; VelaNativeCoreRunner is NEVER started.
class VelaFlClashCoreController extends VelaCoreController {
  VelaFlClashCoreController(this.backend) : super(supported: true);

  final FlClashWindowsBackend backend;
  bool _working = false;
  bool _probing = false;
  bool _remoteVerified = false;
  String? _error;
  /// Ensures the saved route mode is applied before enabling the system proxy.
  Future<bool> Function()? ensureRoutingMode;

  void _changed() => notifyListeners();

  @override
  Future<void> initialize() async {
    try {
      await backend.initialize();
      _error = null;
    } catch (_) {
      _error = '航线服务启动失败，请检查安装文件';
    }
    _changed();
  }

  @override
  bool get hasCore => backend.ready;
  @override
  bool get hasConfig => backend.imported;
  @override
  bool get busy => _working || _probing;
  @override
  bool get isListening => backend.listenerStarted;
  @override
  bool get remoteVerified => _remoteVerified && backend.internetVerified;
  @override
  bool get requiresRemoteProbeBeforeTakeover => false;
  @override
  bool get probing => _probing;
  @override
  bool get directTestProfile => false;
  @override
  bool get usingBundledCore => backend.ready;
  @override
  String? get error => _error;
  @override
  String? get benchmarkCorePath => null;
  @override
  int? get localPort => backend.imported ? 20808 : null;
  @override
  String get localAddress =>
      backend.imported ? '127.0.0.1:20808' : '—';
  @override
  String get phaseLabel => _working
      ? '航线服务正在处理…'
      : isListening
          ? 'Vela 航线服务已开启'
          : hasCore ? 'Vela 航线服务已就绪' : 'Vela 航线服务不可用';

  @override
  Future<bool> start() async {
    if (!backend.imported || _working || isListening) return false;
    _working = true;
    _changed();
    try {
      if (ensureRoutingMode != null && !await ensureRoutingMode!()) {
        _error = '无法应用已保存的航线模式，连接已取消';
        return false;
      }
      await backend.start();
      _error = null;
      return true;
    } catch (_) {
      _error = '代理监听启动失败，请检查端口与配置';
      return false;
    } finally {
      _working = false;
      _changed();
    }
  }

  @override
  Future<bool> verifyRemote() async {
    if (!isListening || _probing) return false;
    _probing = true;
    _remoteVerified = false;
    _changed();
    try {
      _remoteVerified = await backend.verifyInternet();
      return _remoteVerified;
    } finally {
      _probing = false;
      _changed();
    }
  }

  @override
  Future<VelaNodeSwitchResult> switchActiveNode({
    required String currentName,
    required String nextName,
  }) async {
    if (_working || !isListening) {
      return VelaNodeSwitchResult.unverified;
    }
    if (currentName == nextName) return VelaNodeSwitchResult.success;
    _working = true;
    _changed();
    try {
      // FlClash treats the acknowledged core selector as authoritative.
      // A blocked HTTPS test destination is not grounds to undo a change.
      if (await backend.selectNode(nextName)) {
        _remoteVerified = false;
        return VelaNodeSwitchResult.success;
      }
      if (await backend.selectNode(currentName)) {
        _remoteVerified = false;
        return VelaNodeSwitchResult.restored;
      }
      _remoteVerified = false;
      return VelaNodeSwitchResult.unverified;
    } catch (_) {
      _remoteVerified = false;
      return VelaNodeSwitchResult.unverified;
    } finally {
      _working = false;
      _changed();
    }
  }

  @override
  Future<void> stop() async {
    _remoteVerified = false;
    try {
      await backend.stop();
    } finally {
      _changed();
    }
  }

  @override
  Future<(int, int)?> readTrafficCounters() => backend.traffic();

  // Original Vela settings buttons remain where they are, but config import
  // also goes through FlClash. No legacy JSON/sing-box core is executed.
  @override
  Future<bool> chooseConfig(String path) async {
    if (isListening || _working) return false;
    try {
      final raw = await File(path).readAsString();
      await backend.importText(raw);
      _error = null;
      _changed();
      return true;
    } catch (_) {
      _error = '航线服务不接受该配置文件';
      _changed();
      return false;
    }
  }

  @override
  Future<bool> useRemoteSubscriptionProfile(String source) async {
    if (isListening || _working) return false;
    try {
      await backend.importText(source);
      _changed();
      return true;
    } catch (_) {
      _error = '航线服务不接受该订阅';
      _changed();
      return false;
    }
  }

  @override
  Future<bool> useLocalDirectProfile() async => false;
  @override
  Future<bool> chooseBinary(String path) async => false;

  @override
  void dispose() {
    // A foreground Android VpnService owns the Go TUN after Flutter detaches.
    // Shutting the Go core down with the UI would strand a running VPN.
    if (backend is! FlClashAndroidBackend) {
      unawaited(backend.shutdown());
    }
    super.dispose();
  }
}
