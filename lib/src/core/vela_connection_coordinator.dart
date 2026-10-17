import 'dart:async';

import 'package:flutter/foundation.dart';

import '../subscription/vela_subscription_controller.dart';
import 'vela_core_controller.dart';
import 'vela_system_proxy.dart';

enum VelaRealPhase { idle, connecting, connected, disconnecting, error }

/// Real connection orchestrator; no demo timers or fake performance data.
/// Explicit user authorization is required in the UI for every takeover.
class VelaConnectionCoordinator extends ChangeNotifier {
  VelaConnectionCoordinator({
    required this.core,
    required this.subscription,
    required this.proxy,
  }) {
    core.addListener(_onCore);
  }

  final VelaCoreController core;
  final VelaSubscriptionController subscription;
  final VelaSystemProxyManager proxy;
  VelaRealPhase _phase = VelaRealPhase.idle;
  String? _error;
  bool _closed = false;
  bool _handlingExit = false;
  bool _operation = false;
  bool _exitRequested = false;
  bool _switchingNode = false;
  Completer<void>? _operationIdle;

  void _beginOperation() {
    _operation = true;
    _operationIdle = Completer<void>();
  }

  void _endOperation() {
    _operation = false;
    final idle = _operationIdle;
    _operationIdle = null;
    if (idle != null && !idle.isCompleted) idle.complete();
  }

  VelaRealPhase get phase => _phase;
  String? get error => _error;
  bool get busy => _operation;
  bool get switchingNode => _switchingNode;
  bool get connected => _phase == VelaRealPhase.connected && proxy.active &&
      core.isListening && core.remoteVerified;
  bool get hasSelection => subscription.selected != null;
  bool get available => core.supported && core.hasCore && hasSelection &&
      !core.directTestProfile;
  String get nodeName => subscription.selected?.name ?? '请先选择真实节点';
  String get phaseText => switch (_phase) {
    VelaRealPhase.idle => '未连接',
    VelaRealPhase.connecting => '正在建立真实连接…',
    VelaRealPhase.connected => _switchingNode ? '正在切换节点…' :
        connected ? '已连接（系统代理）' : '连接状态异常',
    VelaRealPhase.disconnecting => '正在安全断开…',
    VelaRealPhase.error => '连接未建立',
  };

  void _emit(VelaRealPhase next, [String? error]) {
    _phase = next;
    _error = error;
    if (!_closed) notifyListeners();
  }

  Future<bool> connect() async {
    if (_closed || _exitRequested || _operation || connected || proxy.active) {
      return false;
    }
    if (!available) {
      _emit(VelaRealPhase.error, '请先在设置中导入订阅并选择一个节点');
      return false;
    }
    _beginOperation();
    _emit(VelaRealPhase.connecting);
    try {
      // Recover the prior journal BEFORE starting anything new.
      if (!await proxy.recover()) {
        _emit(VelaRealPhase.error, proxy.error ?? '系统代理恢复失败');
        return false;
      }
      if (core.isListening) {
        // Avoid unexpectedly taking over an old local direct/other profile.
        _emit(VelaRealPhase.error, '请先停止设置页中已有的手动代理');
        return false;
      }
      if (!await core.start()) {
        _emit(VelaRealPhase.error, core.error ?? '内核启动失败');
        return false;
      }
      if (!await core.verifyRemote()) {
        await core.stop();
        _emit(VelaRealPhase.error, 'HTTPS 代理线路检测未通过，未修改 Windows 系统代理');
        return false;
      }
      if (!await proxy.enable()) {
        // If we cannot verify recovery, keep the live core available,
        // preventing a broken system proxy from pointing to a dead port.
        if (await proxy.disable()) {
          await core.stop();
        }
        _emit(VelaRealPhase.error, proxy.error ?? '无法安全设置系统代理');
        return false;
      }
      _emit(VelaRealPhase.connected);
      return true;
    } catch (_) {
      if (await proxy.disable()) await core.stop();
      _emit(VelaRealPhase.error, '连接失败，请检查内核和 Windows 代理状态');
      return false;
    } finally {
      _endOperation();
      if (!_closed) notifyListeners();
    }
  }

  Future<bool> disconnect() async {
    if (_closed || _exitRequested || _operation) return false;
    _beginOperation();
    _emit(VelaRealPhase.disconnecting);
    try {
      if (!await proxy.disable()) {
        _emit(VelaRealPhase.error, proxy.error ??
            '系统代理恢复失败，内核保持运行以防断网');
        return false;
      }
      await core.stop();
      _emit(VelaRealPhase.idle);
      return true;
    } catch (_) {
      _emit(VelaRealPhase.error, '断开时出现异常，请检查 Windows 代理设置');
      return false;
    } finally {
      _endOperation();
      if (!_closed) notifyListeners();
    }
  }

  /// In-place live route selection: never restart the listening process or
  /// modify WinINet when the new node can be verified. The old route remains
  /// selected in the UI until Mihomo confirms both the API state and HTTPS.
  Future<bool> switchNode(int index) async {
    if (_closed || _exitRequested || _operation || !connected ||
        subscription.selectedIndex == null) {
      return false;
    }
    final previous = subscription.selectedIndex!;
    if (index == previous) return true;
    final oldName = subscription.configuredNameFor(previous);
    final newName = subscription.configuredNameFor(index);
    if (oldName == null || newName == null) {
      _emit(VelaRealPhase.connected, '节点不在当前航线配置中，请先断开后重新导入');
      return false;
    }
    _beginOperation();
    _switchingNode = true;
    _emit(VelaRealPhase.connected);
    try {
      final result = await core.switchActiveNode(
          currentName: oldName, nextName: newName);
      switch (result) {
        case VelaNodeSwitchResult.success:
          if (!subscription.confirmRunningSelection(index)) {
            // UI state must never claim a switch that was not confirmed.
            _emit(VelaRealPhase.error, '节点状态更新失败，请安全断开后重连');
            return false;
          }
          _emit(VelaRealPhase.connected);
          return true;
        case VelaNodeSwitchResult.restored:
          _emit(VelaRealPhase.connected, '新节点 HTTPS 验证失败，已恢复原节点');
          return false;
        case VelaNodeSwitchResult.unverified:
          // Unknown live route is not "connected". Restore the previous
          // Windows proxy before stopping the local listener.
          if (await proxy.disable()) {
            await core.stop();
            _emit(VelaRealPhase.error,
                '切换后无法确认可用线路，已断开并恢复系统代理');
          } else {
            _emit(VelaRealPhase.error,
                '切换验证失败且无法恢复 Windows 代理；内核保持运行');
          }
          return false;
      }
    } catch (_) {
      if (await proxy.disable()) await core.stop();
      _emit(VelaRealPhase.error, '节点切换异常，请检查 Windows 代理状态');
      return false;
    } finally {
      _switchingNode = false;
      _endOperation();
      if (!_closed) notifyListeners();
    }
  }

  void _onCore() {
    if (_closed || _exitRequested || _handlingExit || _operation) return;
    if (_phase == VelaRealPhase.connected && !core.probing &&
        (!core.isListening || !core.remoteVerified)) {
      _handlingExit = true;
      unawaited(_handleExit());
    }
  }

  Future<void> _handleExit() async {
    // If the core dies unexpectedly, immediately restore prior WinINet
    // settings (but do not clobber an external program's new settings).
    final restored = await proxy.disable();
    _emit(VelaRealPhase.error, restored
        ? '代理内核已退出，已尝试恢复原系统代理设置'
        : '代理内核异常退出，系统代理未确认恢复；请检查 Windows 代理');
    _handlingExit = false;
  }

  /// Shutdown is best effort. An abrupt OS process kill is recovered via
  /// the on-disk proxy journal when the application next launches.
  Future<bool>? _shutdownFuture;

  /// Await the entire restore-and-stop sequence BEFORE the native window
  /// is allowed to close. Refuse close if WinINet restoration fails.
  Future<bool> shutdown() {
    _exitRequested = true;
    return _shutdownFuture ??= _shutdownOnce().then((ok) {
      if (!ok) {
        _exitRequested = false;
        _shutdownFuture = null;
      }
      return ok;
    });
  }

  Future<bool> _shutdownOnce() async {
    final active = _operationIdle;
    if (active != null) await active.future;
    try {
      if (!await proxy.disable()) {
        _emit(VelaRealPhase.error, proxy.error ??
            '无法恢复 Windows 代理，请检查后重试关闭');
        return false;
      }
      await core.stop();
      _emit(VelaRealPhase.idle);
      return true;
    } catch (_) {
      _emit(VelaRealPhase.error, '关闭清理失败，请检查系统代理');
      return false;
    }
  }

  @override
  void dispose() {
    _closed = true;
    core.removeListener(_onCore);
    super.dispose();
  }
}
