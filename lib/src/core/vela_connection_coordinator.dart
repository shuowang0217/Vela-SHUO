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

  VelaRealPhase get phase => _phase;
  String? get error => _error;
  bool get busy => _operation;
  bool get connected => _phase == VelaRealPhase.connected && proxy.active &&
      core.isListening && core.remoteVerified;
  bool get hasSelection => subscription.selected != null;
  bool get available => core.supported && core.hasCore && hasSelection &&
      !core.directTestProfile;
  String get nodeName => subscription.selected?.name ?? '请先选择真实节点';
  String get phaseText => switch (_phase) {
    VelaRealPhase.idle => '未连接',
    VelaRealPhase.connecting => '正在建立真实连接…',
    VelaRealPhase.connected => connected ? '已连接（系统代理）' : '连接状态异常',
    VelaRealPhase.disconnecting => '正在安全断开…',
    VelaRealPhase.error => '连接未建立',
  };

  void _emit(VelaRealPhase next, [String? error]) {
    _phase = next;
    _error = error;
    if (!_closed) notifyListeners();
  }

  Future<bool> connect() async {
    if (_closed || _operation || connected || proxy.active) return false;
    if (!available) {
      _emit(VelaRealPhase.error, '请先在设置中导入订阅并选择一个节点');
      return false;
    }
    _operation = true;
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
      _operation = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<bool> disconnect() async {
    if (_closed || _operation) return false;
    _operation = true;
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
      _operation = false;
      if (!_closed) notifyListeners();
    }
  }

  void _onCore() {
    if (_closed || _handlingExit || _operation) return;
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
  Future<void>? _shutdownFuture;
  Future<void> shutdown() =>
      _shutdownFuture ??= _shutdownOnce();

  Future<void> _shutdownOnce() async {
    // Always consult the durable journal, even after a failed apply when
    // _active is false. Do NOT kill the core when restoration cannot be
    // verified; Windows would otherwise point at a dead local port.
    if (await proxy.disable()) {
      await core.stop();
    }
  }

  @override
  void dispose() {
    _closed = true;
    core.removeListener(_onCore);
    super.dispose();
  }
}
